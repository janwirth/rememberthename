import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import output/visual_output
import shore
import shore/key
import shore/layout
import shore/style
import shore/ui
import simplifile
import source_specs
import tui/helpers
import tui/navigation as nav

const track_viewport_size = 18

const state_file_path = "tui.state.json"

pub fn main() {
  case otp_supported() {
    True -> run_guarded(start_tui, restore_terminal_cursor)
    False ->
      io.println(
        "tui requires Erlang/OTP 28 or newer. Detected OTP "
        <> int.to_string(otp_major())
        <> ".",
      )
  }
}

@external(erlang, "runtime_otp", "otp_major")
fn otp_major() -> Int

@external(erlang, "runtime_guard", "run")
fn run_guarded(run: fn() -> Nil, cleanup: fn() -> Nil) -> Nil

@external(erlang, "runtime_terminal", "restore_shell")
fn restore_shell() -> Nil

fn otp_supported() -> Bool {
  otp_major() >= 28
}

fn restore_terminal_cursor() {
  // Ensure shell state is restored even if the TUI leaves cursor hidden.
  restore_shell()
  io.print("")
}

fn start_tui() {
  let exit = process.new_subject()
  case
    shore.spec(
      init: fn() { init(exit) },
      update:,
      view:,
      exit:,
      keybinds: shore.keybinds(
        exit: key.Ctrl("X"),
        submit: key.Enter,
        focus_clear: key.Ctrl("Q"),
        focus_next: key.Tab,
        focus_prev: key.BackTab,
      ),
      redraw: shore.on_update(),
    )
    |> shore.start
  {
    Ok(_actor) -> exit |> process.receive_forever
    Error(_) -> io.println("tui failed to start")
  }
}

type Model {
  Model(
    selected_index: Int,
    focus: FocusPane,
    esc_armed: Bool,
    depth_selected_index: Int,
    track_selected_index: Int,
    current_track_lines: List(String),
    source_track_lines: List(#(String, List(String))),
    current_debug_lines: List(String),
    current_fetch: FetchBundle,
    cache_mode: cache.CacheMode,
    exit_subject: process.Subject(Nil),
  )
}

type FocusPane {
  SidebarPane
  DetailPane
  TracksPane
}

type DepthKind {
  Depth1Kind
  Depth3Kind
  DepthAllKind
}

type DepthStatus {
  NotFetched
  Fetching
  Fetched(summary: String, details: String, result: core.ResolveResult)
  FetchFailed(String)
}

type FetchBundle {
  FetchBundle(
    depth_1: DepthStatus,
    depth_3: DepthStatus,
    depth_all: DepthStatus,
  )
}

type SourceRun {
  SourceRun(
    source: nav.SourceEntry,
    depth_1: core.ResolveResult,
    depth_3: core.ResolveResult,
    depth_all: core.ResolveResult,
  )
}

type Msg {
  MoveUp
  MoveDown
  MoveRight
  MoveLeft
  ActivateSelected
  EscPressed
  ExitPressed
  FetchCompleted(String, DepthKind, DepthStatus, List(String), List(String))
  FetchAllStepCompleted(List(SourceRun), List(nav.SourceEntry), List(String))
  CacheUpsertSelected
  CacheIgnoreSelected
  CacheOverrideSelected
  Noop
}

fn init(exit_subject: process.Subject(Nil)) -> #(Model, List(fn() -> Msg)) {
  #(load_model(exit_subject), [])
}

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  let #(next_model, effects) = case msg {
    MoveUp ->
      case model.focus {
        SidebarPane -> #(
          Model(
            ..model,
            selected_index: previous_index(model.selected_index),
            esc_armed: False,
          ),
          [],
        )
        DetailPane -> #(model, [])
        TracksPane -> #(
          Model(
            ..model,
            track_selected_index: previous_track_index(
              model.track_selected_index,
              active_track_lines(model),
            ),
          ),
          [],
        )
      }
    MoveDown ->
      case model.focus {
        SidebarPane -> #(
          Model(
            ..model,
            selected_index: next_index(model.selected_index),
            esc_armed: False,
          ),
          [],
        )
        DetailPane -> #(model, [])
        TracksPane -> #(
          Model(
            ..model,
            track_selected_index: next_track_index(
              model.track_selected_index,
              active_track_lines(model),
            ),
          ),
          [],
        )
      }
    MoveRight ->
      case model.focus {
        TracksPane -> #(model, [])
        DetailPane ->
          case selected_view_type(model.selected_index) {
            nav.Source(_, _) -> #(Model(..model, focus: TracksPane), [])
            _ -> #(model, [])
          }
        SidebarPane -> focus_selected_right(model)
      }
    MoveLeft ->
      case model.focus {
        SidebarPane -> #(model, [])
        DetailPane -> #(Model(..model, focus: SidebarPane), [])
        TracksPane ->
          case selected_view_type(model.selected_index) {
            nav.Source(_, _) -> #(Model(..model, focus: DetailPane), [])
            _ -> #(Model(..model, focus: DetailPane), [])
          }
      }
    ActivateSelected ->
      case model.focus {
        SidebarPane ->
          case selected_view_type(model.selected_index) {
            nav.Exit(_) -> request_exit(model)
            nav.RunAll(_) -> fetch_all_sources(model)
            nav.Source(source, _) -> fetch_selected_full(model, source)
            nav.ToggleCache(_) -> toggle_cache_mode_all(model)
          }
        DetailPane ->
          case selected_view_type(model.selected_index) {
            nav.RunAll(_) -> fetch_all_sources(model)
            nav.Source(source, _) -> fetch_selected_full(model, source)
            nav.Exit(_) -> #(model, [])
            nav.ToggleCache(_) -> toggle_cache_mode_all(model)
          }
        TracksPane -> #(model, [])
      }
    EscPressed ->
      case model.esc_armed {
        True -> request_exit(model)
        False -> #(Model(..model, esc_armed: True), [])
      }
    ExitPressed -> request_exit(model)
    FetchCompleted(source_key, depth_kind, status, track_lines, debug_lines) -> {
      let next_source_track_lines =
        upsert_source_track_lines(
          model.source_track_lines,
          source_key,
          track_lines,
        )
      case selected_source(model.selected_index) {
        Some(current_source) if current_source.key == source_key -> #(
          Model(
            ..model,
            current_fetch: set_depth_status(
              model.current_fetch,
              depth_kind,
              status,
            ),
            track_selected_index: 0,
            source_track_lines: next_source_track_lines,
            current_debug_lines: debug_lines,
          ),
          [],
        )
        _ -> #(
          Model(
            ..model,
            source_track_lines: next_source_track_lines,
            current_debug_lines: debug_lines,
          ),
          [],
        )
      }
    }
    FetchAllStepCompleted(completed_rev, remaining, step_debug_lines) -> {
      let completed = list.reverse(completed_rev)
      let track_lines = validation_lines_from_runs(completed)
      let done = section_count() - list.length(remaining)
      let total = section_count()
      let progress_line =
        "Progress: "
        <> int.to_string(done)
        <> "/"
        <> int.to_string(total)
        <> " sources complete"
      let debug_lines =
        model.current_debug_lines
        |> list.append([progress_line])
        |> list.append(step_debug_lines)
      case remaining {
        [] -> #(
          Model(
            ..model,
            current_fetch: bundle_from_runs(completed),
            track_selected_index: 0,
            current_track_lines: track_lines,
            current_debug_lines: debug_lines,
          ),
          [],
        )
        _ -> #(
          Model(
            ..model,
            current_fetch: FetchBundle(Fetching, Fetching, Fetching),
            track_selected_index: 0,
            current_track_lines: track_lines,
            current_debug_lines: debug_lines,
          ),
          [
            fn() {
              fetch_all_next_step(completed_rev, remaining, model.cache_mode)
            },
          ],
        )
      }
    }
    CacheUpsertSelected -> #(Model(..model, cache_mode: cache.CacheUpsert), [])
    CacheIgnoreSelected -> #(Model(..model, cache_mode: cache.CacheIgnore), [])
    CacheOverrideSelected -> #(
      Model(..model, cache_mode: cache.CacheOverride),
      [],
    )
    Noop -> #(model, [])
  }
  #(persist_model(next_model), effects)
}

fn default_model(exit_subject: process.Subject(Nil)) -> Model {
  Model(
    selected_index: 0,
    focus: SidebarPane,
    esc_armed: False,
    depth_selected_index: 0,
    track_selected_index: 0,
    current_track_lines: [],
    source_track_lines: [],
    current_debug_lines: [],
    current_fetch: empty_fetch_bundle(),
    cache_mode: cache.CacheUpsert,
    exit_subject: exit_subject,
  )
}

fn load_model(exit_subject: process.Subject(Nil)) -> Model {
  let fallback = default_model(exit_subject)
  case simplifile.read(from: state_file_path) {
    Ok(raw) ->
      case decode_saved_model(raw, exit_subject) {
        Ok(decoded) -> sanitize_model(decoded)
        Error(_) -> fallback
      }
    Error(_) -> fallback
  }
}

fn persist_model(model: Model) -> Model {
  let _ = simplifile.write(encode_model(model), to: state_file_path)
  model
}

fn sanitize_model(model: Model) -> Model {
  let selected_index = case
    model.selected_index < 0 || model.selected_index >= menu_count()
  {
    True -> 0
    False -> model.selected_index
  }
  let depth_selected_index = case
    model.depth_selected_index < 0 || model.depth_selected_index > 2
  {
    True -> 0
    False -> model.depth_selected_index
  }
  let track_count = list.length(active_track_lines(model))
  let track_selected_index = case track_count <= 0 {
    True -> 0
    False ->
      case
        model.track_selected_index < 0
        || model.track_selected_index >= track_count
      {
        True -> 0
        False -> model.track_selected_index
      }
  }
  let focus = case model.focus {
    TracksPane if track_count <= 0 -> DetailPane
    _ -> model.focus
  }
  Model(
    ..model,
    selected_index: selected_index,
    focus: focus,
    depth_selected_index: depth_selected_index,
    track_selected_index: track_selected_index,
  )
}

fn decode_saved_model(
  raw: String,
  exit_subject: process.Subject(Nil),
) -> Result(Model, Nil) {
  case json.parse(raw, decode.dynamic) {
    Error(_) -> Error(Nil)
    Ok(data) ->
      Ok(Model(
        selected_index: decode_path_or(data, ["selected_index"], 0, decode.int),
        focus: decode_focus(data),
        esc_armed: decode_path_or(data, ["esc_armed"], False, decode.bool),
        depth_selected_index: decode_path_or(
          data,
          ["depth_selected_index"],
          0,
          decode.int,
        ),
        track_selected_index: decode_path_or(
          data,
          ["track_selected_index"],
          0,
          decode.int,
        ),
        current_track_lines: decode_path_or(
          data,
          ["current_track_lines"],
          [],
          decode.list(of: decode.string),
        ),
        source_track_lines: [],
        current_debug_lines: decode_path_or(
          data,
          ["current_debug_lines"],
          [],
          decode.list(of: decode.string),
        ),
        current_fetch: decode_fetch_bundle(decode_path_or(
          data,
          ["current_fetch"],
          dynamic.nil(),
          decode.dynamic,
        )),
        cache_mode: decode_cache_mode(data),
        exit_subject: exit_subject,
      ))
  }
}

fn encode_model(model: Model) -> String {
  json.object([
    #("selected_index", json.int(model.selected_index)),
    #("focus", json.string(encode_focus(model.focus))),
    #("view", encode_view(model)),
    #("esc_armed", json.bool(model.esc_armed)),
    #("depth_selected_index", json.int(model.depth_selected_index)),
    #("track_selected_index", json.int(model.track_selected_index)),
    #(
      "current_track_lines",
      json.array(model.current_track_lines, of: json.string),
    ),
    #(
      "current_debug_lines",
      json.array(model.current_debug_lines, of: json.string),
    ),
    #("current_fetch", encode_fetch_bundle(model.current_fetch)),
    #("cache_mode", json.string(encode_cache_mode(model.cache_mode))),
  ])
  |> json.to_string
}

fn encode_view(model: Model) {
  let kind = case selected_view_type(model.selected_index) {
    nav.RunAll(_) -> "run_all"
    nav.Exit(_) -> "exit"
    nav.Source(_, _) -> "source"
    nav.ToggleCache(_) -> "toggle_cache"
  }
  let source_key = case selected_source(model.selected_index) {
    Some(source) -> source.key
    None -> ""
  }
  json.object([
    #("kind", json.string(kind)),
    #("source_key", json.string(source_key)),
  ])
}

fn decode_focus(data: dynamic.Dynamic) -> FocusPane {
  case decode_path_or(data, ["focus"], "sidebar", decode.string) {
    "detail" -> DetailPane
    "tracks" -> TracksPane
    _ -> SidebarPane
  }
}

fn encode_focus(focus: FocusPane) -> String {
  case focus {
    SidebarPane -> "sidebar"
    DetailPane -> "detail"
    TracksPane -> "tracks"
  }
}

fn decode_cache_mode(data: dynamic.Dynamic) -> cache.CacheMode {
  case decode_path_or(data, ["cache_mode"], "upsert", decode.string) {
    "ignore" -> cache.CacheIgnore
    "override" -> cache.CacheOverride
    "readonly" -> cache.CacheReadOnly
    "read-only" -> cache.CacheReadOnly
    _ -> cache.CacheUpsert
  }
}

fn encode_cache_mode(mode: cache.CacheMode) -> String {
  case mode {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
    cache.CacheReadOnly -> "readonly"
  }
}

fn decode_fetch_bundle(data: dynamic.Dynamic) -> FetchBundle {
  FetchBundle(
    depth_1: decode_depth_status(decode_path_or(
      data,
      ["depth_1"],
      dynamic.nil(),
      decode.dynamic,
    )),
    depth_3: decode_depth_status(decode_path_or(
      data,
      ["depth_3"],
      dynamic.nil(),
      decode.dynamic,
    )),
    depth_all: decode_depth_status(decode_path_or(
      data,
      ["depth_all"],
      dynamic.nil(),
      decode.dynamic,
    )),
  )
}

fn encode_fetch_bundle(bundle: FetchBundle) {
  json.object([
    #("depth_1", encode_depth_status(bundle.depth_1)),
    #("depth_3", encode_depth_status(bundle.depth_3)),
    #("depth_all", encode_depth_status(bundle.depth_all)),
  ])
}

fn decode_depth_status(data: dynamic.Dynamic) -> DepthStatus {
  case decode_path_or(data, ["tag"], "", decode.string) {
    "fetching" -> Fetching
    "fetch_failed" ->
      FetchFailed(decode_path_or(data, ["reason"], "unknown", decode.string))
    "fetched" ->
      Fetched(
        decode_path_or(data, ["summary"], "", decode.string),
        decode_path_or(data, ["details"], "", decode.string),
        decode_resolve_result(decode_path_or(
          data,
          ["result"],
          dynamic.nil(),
          decode.dynamic,
        )),
      )
    _ -> NotFetched
  }
}

fn encode_depth_status(status: DepthStatus) {
  case status {
    NotFetched -> json.object([#("tag", json.string("not_fetched"))])
    Fetching -> json.object([#("tag", json.string("fetching"))])
    FetchFailed(reason) ->
      json.object([
        #("tag", json.string("fetch_failed")),
        #("reason", json.string(reason)),
      ])
    Fetched(summary, details, result) ->
      json.object([
        #("tag", json.string("fetched")),
        #("summary", json.string(summary)),
        #("details", json.string(details)),
        #("result", encode_resolve_result(result)),
      ])
  }
}

fn decode_resolve_result(data: dynamic.Dynamic) -> core.ResolveResult {
  let item_data =
    decode_path_or(data, ["items"], [], decode.list(of: decode.dynamic))
  let list_data =
    decode_path_or(data, ["lists"], [], decode.list(of: decode.dynamic))
  let unresolved_data =
    decode_path_or(data, ["unresolved"], [], decode.list(of: decode.dynamic))
  core.ResolveResult(
    items: list.map(item_data, decode_unified_item),
    lists: list.map(list_data, decode_unified_collection),
    unresolved: list.map(unresolved_data, decode_adapter_node),
  )
}

fn encode_resolve_result(result: core.ResolveResult) {
  let core.ResolveResult(items, lists, unresolved) = result
  json.object([
    #("items", json.array(items, of: encode_unified_item)),
    #("lists", json.array(lists, of: encode_unified_collection)),
    #("unresolved", json.array(unresolved, of: encode_adapter_node)),
  ])
}

fn decode_unified_item(data: dynamic.Dynamic) -> core.UnifiedItem {
  core.UnifiedItem(
    id: decode_path_or(data, ["id"], "", decode.string),
    title: decode_path_or(data, ["title"], "", decode.string),
    artist: decode_path_or(data, ["artist"], "", decode.string),
    service: decode_path_or(data, ["service"], "", decode.string),
    source_type: decode_path_or(data, ["source_type"], "", decode.string),
    source_id: decode_path_or(data, ["source_id"], "", decode.string),
  )
}

fn encode_unified_item(item: core.UnifiedItem) {
  let core.UnifiedItem(id, title, artist, service, source_type, source_id) =
    item
  json.object([
    #("id", json.string(id)),
    #("title", json.string(title)),
    #("artist", json.string(artist)),
    #("service", json.string(service)),
    #("source_type", json.string(source_type)),
    #("source_id", json.string(source_id)),
  ])
}

fn decode_unified_collection(data: dynamic.Dynamic) -> core.UnifiedCollection {
  core.UnifiedCollection(
    id: decode_path_or(data, ["id"], "", decode.string),
    title: decode_path_or(data, ["title"], "", decode.string),
    track_ids: decode_path_or(
      data,
      ["track_ids"],
      [],
      decode.list(of: decode.string),
    ),
    list_ids: decode_path_or(
      data,
      ["list_ids"],
      [],
      decode.list(of: decode.string),
    ),
    service: decode_path_or(data, ["service"], "", decode.string),
    source_type: decode_path_or(data, ["source_type"], "", decode.string),
    source_id: decode_path_or(data, ["source_id"], "", decode.string),
  )
}

fn encode_unified_collection(collection: core.UnifiedCollection) {
  let core.UnifiedCollection(
    id,
    title,
    track_ids,
    list_ids,
    service,
    source_type,
    source_id,
  ) = collection
  json.object([
    #("id", json.string(id)),
    #("title", json.string(title)),
    #("track_ids", json.array(track_ids, of: json.string)),
    #("list_ids", json.array(list_ids, of: json.string)),
    #("service", json.string(service)),
    #("source_type", json.string(source_type)),
    #("source_id", json.string(source_id)),
  ])
}

fn decode_adapter_node(data: dynamic.Dynamic) -> core.AdapterNode {
  let kind = decode_path_or(data, ["tag"], "page", decode.string)
  let value = decode_path_or(data, ["value"], "", decode.string)
  case kind {
    "profile" -> core.ProfileEntry(value)
    "category" -> core.CategoryNode(value)
    "list" -> core.ListNode(value)
    _ -> core.PageNode(value)
  }
}

fn encode_adapter_node(node: core.AdapterNode) {
  let #(tag, value) = case node {
    core.ProfileEntry(v) -> #("profile", v)
    core.CategoryNode(v) -> #("category", v)
    core.ListNode(v) -> #("list", v)
    core.PageNode(v) -> #("page", v)
  }
  json.object([
    #("tag", json.string(tag)),
    #("value", json.string(value)),
  ])
}

fn decode_path_or(
  data: dynamic.Dynamic,
  path: List(String),
  fallback: a,
  decoder: decode.Decoder(a),
) -> a {
  decode.run(data, decode.optionally_at(path, fallback, decoder))
  |> result.unwrap(fallback)
}

fn request_exit(model: Model) -> #(Model, List(fn() -> Msg)) {
  #(model, [
    fn() {
      process.send(model.exit_subject, Nil)
      Noop
    },
  ])
}

fn toggle_cache_mode_all(model: Model) -> #(Model, List(fn() -> Msg)) {
  let next_mode = case model.cache_mode {
    cache.CacheUpsert -> cache.CacheIgnore
    cache.CacheIgnore -> cache.CacheOverride
    cache.CacheOverride -> cache.CacheReadOnly
    cache.CacheReadOnly -> cache.CacheUpsert
  }
  #(
    Model(
      ..model,
      cache_mode: next_mode,
      current_debug_lines: list.append(model.current_debug_lines, [
        "cache mode switched to " <> cache_mode_text(next_mode),
      ]),
    ),
    [],
  )
}

fn focus_selected_right(model: Model) -> #(Model, List(fn() -> Msg)) {
  case selected_view_type(model.selected_index) {
    nav.RunAll(_) -> #(
      Model(
        ..model,
        focus: DetailPane,
        esc_armed: False,
        current_fetch: empty_fetch_bundle(),
        current_debug_lines: [],
      ),
      [],
    )
    nav.Source(source, _) -> #(
      Model(
        ..model,
        focus: DetailPane,
        esc_armed: False,
        track_selected_index: 0,
        cache_mode: source.cache_mode,
      ),
      [],
    )
    nav.ToggleCache(_) -> #(
      Model(..model, focus: DetailPane, esc_armed: False),
      [],
    )
    nav.Exit(_) -> #(Model(..model, focus: DetailPane, esc_armed: False), [])
  }
}

fn fetch_selected_full(
  model: Model,
  source: nav.SourceEntry,
) -> #(Model, List(fn() -> Msg)) {
  let depth_kind = DepthAllKind
  let staged = set_depth_status(model.current_fetch, depth_kind, Fetching)
  #(Model(..model, current_fetch: staged), [
    fn() {
      let debug_subject = process.new_subject()
      let result =
        resolve_source(source, core.All, model.cache_mode, fn(line) {
          process.send(debug_subject, line)
        })
      let status = fetched_status(result)
      let track_lines = track_lines_from_result(result)
      FetchCompleted(
        source.key,
        depth_kind,
        status,
        track_lines,
        collect_debug_lines(debug_subject, []),
      )
    },
  ])
}

fn fetch_all_sources(model: Model) -> #(Model, List(fn() -> Msg)) {
  let total = section_count()
  #(
    Model(
      ..model,
      current_fetch: FetchBundle(Fetching, Fetching, Fetching),
      track_selected_index: 0,
      current_track_lines: [],
      current_debug_lines: [
        "Progress: 0/" <> int.to_string(total) <> " sources complete",
      ],
    ),
    [fn() { fetch_all_next_step([], nav.source_entries(), model.cache_mode) }],
  )
}

fn view(model: Model) -> shore.Node(Msg) {
  let current_view =
    nav.view_for_index(model.selected_index, model.focus != SidebarPane)
  let sidebar_items =
    sidebar_item_nodes(model.selected_index, model.focus, model.cache_mode)
  let sidebar_context = sidebar_context_nodes(current_view)
  let sidebar_children =
    []
    |> list.append(sidebar_items)
    |> list.append([ui.br(), ui.hr(), ui.br()])
    |> list.append(sidebar_context)
    |> list.append([
      ui.keybind(key.Up, MoveUp),
      ui.keybind(key.Down, MoveDown),
      ui.keybind(key.Char("k"), MoveUp),
      ui.keybind(key.Char("j"), MoveDown),
      ui.keybind(key.Right, MoveRight),
      ui.keybind(key.Left, MoveLeft),
      ui.keybind(key.Enter, ActivateSelected),
      ui.keybind(key.Esc, EscPressed),
      ui.keybind(key.Char("x"), ExitPressed),
      ui.keybind(key.Char("u"), CacheUpsertSelected),
      ui.keybind(key.Char("i"), CacheIgnoreSelected),
      ui.keybind(key.Char("o"), CacheOverrideSelected),
    ])

  let sidebar = ui.box(sidebar_children, Some("Sources"))
  let right_content = case current_view {
    nav.RunAll(_) ->
      ui.box(run_all_main_nodes(model), Some(nav.title(current_view)))
    nav.Source(_, _) -> {
      let source_track_lines = selected_source_track_lines(model)
      let source_nodes = source_main_nodes(model)
      let tracks_nodes =
        helpers.track_panel_nodes(
          source_track_lines,
          model.track_selected_index,
          model.focus == TracksPane,
          track_viewport_size,
        )
      ui.box(
        source_nodes
          |> list.append([ui.br(), ui.hr(), ui.text("Tracks")])
          |> list.append(tracks_nodes),
        Some(
          "Tracks (" <> int.to_string(list.length(source_track_lines)) <> ")",
        ),
      )
    }
    nav.Exit(_) -> ui.box(exit_main_nodes(model), Some(nav.title(current_view)))
    nav.ToggleCache(_) ->
      ui.box(toggle_cache_main_nodes(model), Some(nav.title(current_view)))
  }

  layout.grid(
    gap: 1,
    rows: [style.Fill],
    cols: [style.Pct(30), style.Fill],
    cells: [
      layout.cell(content: sidebar, row: #(0, 0), col: #(0, 0)),
      layout.cell(content: right_content, row: #(0, 0), col: #(1, 1)),
    ],
  )
}

fn section_count() -> Int {
  nav.section_count()
}

fn menu_count() -> Int {
  nav.menu_count()
}

fn previous_index(index: Int) -> Int {
  nav.previous_index(index)
}

fn next_index(index: Int) -> Int {
  nav.next_index(index)
}

fn selected_view_type(index: Int) -> nav.View {
  nav.view_for_index(index, False)
}

fn selected_source(index: Int) -> Option(nav.SourceEntry) {
  nav.source_from_view(selected_view_type(index))
}

fn active_track_lines(model: Model) -> List(String) {
  case selected_view_type(model.selected_index) {
    nav.Source(_, _) -> selected_source_track_lines(model)
    _ -> model.current_track_lines
  }
}

fn selected_source_track_lines(model: Model) -> List(String) {
  case selected_source(model.selected_index) {
    Some(source) ->
      lookup_source_track_lines(model.source_track_lines, source.key)
    None -> []
  }
}

fn lookup_source_track_lines(
  entries: List(#(String, List(String))),
  source_key: String,
) -> List(String) {
  case entries {
    [] -> []
    [entry, ..rest] -> {
      let #(key, lines) = entry
      case key == source_key {
        True -> lines
        False -> lookup_source_track_lines(rest, source_key)
      }
    }
  }
}

fn upsert_source_track_lines(
  entries: List(#(String, List(String))),
  source_key: String,
  lines: List(String),
) -> List(#(String, List(String))) {
  case entries {
    [] -> [#(source_key, lines)]
    [entry, ..rest] -> {
      let #(key, _) = entry
      case key == source_key {
        True -> [#(source_key, lines), ..rest]
        False -> [entry, ..upsert_source_track_lines(rest, source_key, lines)]
      }
    }
  }
}

fn section_at(index: Int) -> #(String, String) {
  case selected_view_type(index) {
    nav.Source(source, _) -> #(source.name, source_info_details(source))
    _ -> #("Unknown Source", "No source found at this index.")
  }
}

fn sidebar_item_nodes(
  selected_index: Int,
  focus: FocusPane,
  cache_mode: cache.CacheMode,
) -> List(shore.Node(Msg)) {
  let run_all_node =
    sidebar_node_for_index(0, selected_index, focus, cache_mode)
  let sources =
    source_sidebar_nodes_loop(
      selected_index,
      focus,
      cache_mode,
      0,
      section_count(),
      [],
    )
    |> list.reverse
  let toggle_cache_node =
    sidebar_node_for_index(
      section_count() + 1,
      selected_index,
      focus,
      cache_mode,
    )
  let exit_node =
    sidebar_node_for_index(menu_count() - 1, selected_index, focus, cache_mode)
  [run_all_node, ui.br()]
  |> list.append(sources)
  |> list.append([ui.br(), toggle_cache_node, ui.br(), exit_node])
}

fn menu_item_title(index: Int, cache_mode: cache.CacheMode) -> String {
  case selected_view_type(index) {
    nav.ToggleCache(_) ->
      "Toggle cache mode (" <> cache_mode_text(cache_mode) <> ")"
    _ -> nav.title(selected_view_type(index))
  }
}

fn sidebar_node_for_index(
  menu_index: Int,
  selected_index: Int,
  focus: FocusPane,
  cache_mode: cache.CacheMode,
) -> shore.Node(Msg) {
  let title = menu_item_title(menu_index, cache_mode)
  let is_selected = menu_index == selected_index
  helpers.sidebar_item_node(title, is_selected, focus == SidebarPane)
}

fn source_sidebar_nodes_loop(
  selected_index: Int,
  focus: FocusPane,
  cache_mode: cache.CacheMode,
  source_index: Int,
  source_count: Int,
  items: List(shore.Node(Msg)),
) -> List(shore.Node(Msg)) {
  case source_index >= source_count {
    True -> items
    False -> {
      let node =
        sidebar_node_for_index(
          source_index + 1,
          selected_index,
          focus,
          cache_mode,
        )
      source_sidebar_nodes_loop(
        selected_index,
        focus,
        cache_mode,
        source_index + 1,
        source_count,
        [node, ..items],
      )
    }
  }
}

fn selected_content(index: Int) -> #(String, String) {
  case selected_view_type(index) {
    nav.RunAll(_) -> #(
      "Run all source tests",
      "Press Enter in this panel to run depth 1/3/all for every source.",
    )
    nav.Exit(_) -> #("Exit", "Press Enter to gracefully close the Shore demo.")
    nav.ToggleCache(_) -> #(
      "Toggle cache mode",
      "Press Enter to cycle cache mode for all sources: upsert -> ignore -> override.",
    )
    nav.Source(_, _) -> section_at(index)
  }
}

fn source_info_details(source: nav.SourceEntry) -> String {
  "Entry point: "
  <> source.entry_point
  <> "\nCache(default): "
  <> cache_mode_text(source.cache_mode)
  <> "\n\nDepth assert spec:"
  <> "\n- min_depth_1_items: "
  <> int.to_string(source.min_depth_1_items)
  <> "\n- min_full_items: "
  <> int.to_string(source.min_full_items)
  <> "\n- first_items_to_preserve: "
  <> int.to_string(source.first_items_to_preserve)
  <> "\n- anchor_fragments: "
  <> string.join(source.anchor_fragments, ", ")
}

fn sidebar_context_nodes(view: nav.View) -> List(shore.Node(Msg)) {
  case view {
    nav.Source(source, _) -> [
      ui.text_styled("focused source", Some(style.White), None),
      ui.text(source.name),
      ui.br(),
      ui.text(source_info_details(source)),
    ]
    _ -> [
      ui.text("Select a source to inspect metadata."),
    ]
  }
}

fn empty_fetch_bundle() -> FetchBundle {
  FetchBundle(NotFetched, NotFetched, NotFetched)
}

fn set_depth_status(
  bundle: FetchBundle,
  kind: DepthKind,
  status: DepthStatus,
) -> FetchBundle {
  case kind {
    Depth1Kind -> FetchBundle(..bundle, depth_1: status)
    Depth3Kind -> FetchBundle(..bundle, depth_3: status)
    DepthAllKind -> FetchBundle(..bundle, depth_all: status)
  }
}

fn summarize_result(result: core.ResolveResult) -> String {
  let core.ResolveResult(items, lists, unresolved) = result
  let first_item_text = case list.first(items) {
    Ok(first) -> {
      let core.UnifiedItem(_, title, _, _, _, _) = first
      " | first=" <> title
    }
    Error(_) -> ""
  }
  "items="
  <> int.to_string(list.length(items))
  <> " lists="
  <> int.to_string(list.length(lists))
  <> " unresolved="
  <> int.to_string(list.length(unresolved))
  <> first_item_text
}

fn fetched_status(result: core.ResolveResult) -> DepthStatus {
  Fetched(summarize_result(result), render_result_details(result), result)
}

fn render_result_details(result: core.ResolveResult) -> String {
  let core.ResolveResult(items, lists, _) = result
  let tracks = list.map(items, item_to_track_view)
  let list_views =
    list.map(lists, fn(collection) {
      let core.UnifiedCollection(_, title, track_ids, _, _, _, _) = collection
      let collection_tracks =
        list.filter_map(track_ids, fn(track_id) {
          case track_view_by_id(items, track_id) {
            Some(track) -> Ok(track)
            None -> Error(Nil)
          }
        })
      visual_output.ListView(title, collection_tracks)
    })
  visual_output.render(#(list_views, tracks))
}

fn track_lines_from_result(result: core.ResolveResult) -> List(String) {
  let core.ResolveResult(items, _, _) = result
  list.map(items, fn(item) {
    let core.UnifiedItem(_, title, artist, service, _, _) = item
    title <> " - " <> artist <> " [" <> service <> "]"
  })
}

fn run_all_main_nodes(model: Model) -> List(shore.Node(Msg)) {
  let #(_, body) = selected_content(model.selected_index)
  let button_label = case model.focus == DetailPane {
    True -> "● [ RUN ALL ] (press Enter)"
    False -> "  [ RUN ALL ] (press Right then Enter)"
  }
  [
    ui.text_styled("validation", Some(style.White), None),
    ui.text("[-] aggregate mode"),
    ui.text(body),
    ui.br(),
    ui.hr(),
    ui.text("Run all"),
    ui.text(button_label),
    ui.br(),
    ui.text(selected_depth_details(model)),
    ui.br(),
    ui.text("Results"),
    ui.hr(),
  ]
  |> list.append(run_all_result_nodes(model.current_track_lines))
  |> list.append([
    ui.br(),
    ui.text("Debug"),
    ui.hr(),
  ])
  |> list.append(debug_nodes(model.current_debug_lines))
}

fn toggle_cache_main_nodes(model: Model) -> List(shore.Node(Msg)) {
  let #(_, body) = selected_content(model.selected_index)
  let button_label = case model.focus == DetailPane {
    True ->
      "● [ TOGGLE CACHE MODE ] current="
      <> cache_mode_text(model.cache_mode)
      <> " (press Enter)"
    False ->
      "  [ TOGGLE CACHE MODE ] current="
      <> cache_mode_text(model.cache_mode)
      <> " (press Right then Enter)"
  }
  [
    ui.text_styled("cache", Some(style.White), None),
    ui.text(body),
    ui.br(),
    ui.hr(),
    ui.text(button_label),
    ui.br(),
    ui.text("Applies globally to all source fetches."),
  ]
}

fn exit_main_nodes(model: Model) -> List(shore.Node(Msg)) {
  let #(_, body) = selected_content(model.selected_index)
  [
    ui.text_styled("validation", Some(style.White), None),
    ui.text("[-] no source selected"),
    ui.text(body),
    ui.br(),
    ui.hr(),
    ui.text("No actions available."),
    ui.br(),
    ui.text("Debug"),
    ui.hr(),
  ]
  |> list.append(debug_nodes(model.current_debug_lines))
}

fn run_all_result_nodes(lines: List(String)) -> List(shore.Node(Msg)) {
  case lines {
    [] -> [ui.text("(no results yet)")]
    _ -> list.map(lines, ui.text)
  }
}

fn previous_track_index(current: Int, lines: List(String)) -> Int {
  let max = list.length(lines)
  case max <= 0 {
    True -> 0
    False ->
      case current <= 0 {
        True -> max - 1
        False -> current - 1
      }
  }
}

fn next_track_index(current: Int, lines: List(String)) -> Int {
  let max = list.length(lines)
  case max <= 0 {
    True -> 0
    False ->
      case current >= max - 1 {
        True -> 0
        False -> current + 1
      }
  }
}

fn item_to_track_view(item: core.UnifiedItem) -> visual_output.TrackView {
  let core.UnifiedItem(_, title, artist, service, _, source_id) = item
  visual_output.TrackView(title, artist, service, source_id, "", "", "", "")
}

fn track_view_by_id(
  items: List(core.UnifiedItem),
  wanted_id: String,
) -> Option(visual_output.TrackView) {
  case items {
    [] -> None
    [item, ..rest] -> {
      let core.UnifiedItem(id, _, _, _, _, _) = item
      case id == wanted_id {
        True -> Some(item_to_track_view(item))
        False -> track_view_by_id(rest, wanted_id)
      }
    }
  }
}

fn selected_depth_details(model: Model) -> String {
  let status = model.current_fetch.depth_all
  case status {
    Fetched(_, details, _) -> details
    Fetching ->
      case selected_view_type(model.selected_index) {
        nav.RunAll(_) -> "Running all source tests..."
        _ -> "Fetching full depth..."
      }
    NotFetched ->
      case selected_view_type(model.selected_index) {
        nav.RunAll(_) ->
          "Press Enter to run depth 1/3/all test suite for every source."
        _ -> "Press Enter to fetch full depth."
      }
    FetchFailed(reason) -> "Fetch failed: " <> reason
  }
}

fn source_main_nodes(model: Model) -> List(shore.Node(Msg)) {
  let #(_, body) = selected_content(model.selected_index)
  let fetch_button_label = case model.focus {
    DetailPane -> "● [ FETCH ] (press Enter)"
    TracksPane -> "  [ FETCH ] (press Left then Enter)"
    SidebarPane -> "  [ FETCH ] (press Right then Enter)"
  }
  let status_line = case model.current_fetch.depth_all {
    Fetching -> "fetching started..."
    FetchFailed(reason) -> "fetch failed: " <> reason
    Fetched(_, _, _) -> "fetched"
    NotFetched -> "enter to fetch"
  }
  [
    ui.text_styled("source", Some(style.White), None),
    ui.text(body),
    ui.br(),
    ui.text(fetch_button_label),
    ui.text("status: " <> status_line),
  ]
}

fn resolve_source(
  source: nav.SourceEntry,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let source_specs.SourceTimingSpec(max_concurrency, requests_per_second) =
    source.timing_spec
  let queue_policy =
    core.QueuePolicy(
      max_concurrency: max_concurrency,
      requests_per_second: requests_per_second,
    )
  case source.key {
    "tuna_normalized" ->
      tuna_normalized_source.resolve(depth, cache_mode, on_debug)
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(source.entry_point)
      bandcamp_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        0,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
    "soundcloud" -> {
      let profile =
        soundcloud_live_expander.soundcloud_profile(source.entry_point)
      soundcloud_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        0,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
    "spotify" -> {
      let access_token =
        spotify_live_expander.read_access_token_file(
          ".spotify_oauth_session.json",
        )
      let config =
        spotify_live_expander.spotify_config(
          access_token: access_token,
          session_file: ".spotify_oauth_session.json",
          client_id: spotify_live_expander.read_env_value(
            ".env",
            "SPOTIFY_CLIENT_ID",
          ),
          client_secret: spotify_live_expander.read_env_value(
            ".env",
            "SPOTIFY_CLIENT_SECRET",
          ),
          redirect_uri: "https://127.0.0.1:8080/spotify-oauth-success",
          scopes: "playlist-read-private playlist-read-collaborative user-library-read",
        )
      let profile = spotify_live_expander.spotify_user(source.entry_point)
      spotify_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        config,
        cache_mode,
        0,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(source.entry_point)
      youtube_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        0,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
  }
}

fn fetch_all_next_step(
  completed_rev: List(SourceRun),
  remaining: List(nav.SourceEntry),
  cache_mode: cache.CacheMode,
) -> Msg {
  case remaining {
    [] -> FetchAllStepCompleted(completed_rev, [], [])
    [source, ..rest] -> {
      let debug_subject = process.new_subject()
      let depth_1 =
        resolve_source(source, core.Depth1, cache_mode, fn(line) {
          process.send(
            debug_subject,
            "[" <> source.name <> "][depth1] " <> line,
          )
        })
      let depth_3 =
        resolve_source(source, core.Depth3, cache_mode, fn(line) {
          process.send(
            debug_subject,
            "[" <> source.name <> "][depth3] " <> line,
          )
        })
      let depth_all =
        resolve_source(source, core.All, cache_mode, fn(line) {
          process.send(
            debug_subject,
            "[" <> source.name <> "][depth-all] " <> line,
          )
        })
      let run = SourceRun(source, depth_1, depth_3, depth_all)
      let step_header = "Completed: " <> validation_line_from_run(run)
      let debug_lines =
        [step_header]
        |> list.append(collect_debug_lines(debug_subject, []))
      FetchAllStepCompleted([run, ..completed_rev], rest, debug_lines)
    }
  }
}

fn bundle_from_runs(runs: List(SourceRun)) -> FetchBundle {
  FetchBundle(
    depth_1: depth_status_from_runs(runs, Depth1Kind),
    depth_3: depth_status_from_runs(runs, Depth3Kind),
    depth_all: depth_status_from_runs(runs, DepthAllKind),
  )
}

fn depth_status_from_runs(runs: List(SourceRun), kind: DepthKind) -> DepthStatus {
  let summary = summarize_depth_runs(runs, kind)
  let details = depth_details_from_runs(runs, kind)
  Fetched(summary, details, core.ResolveResult([], [], []))
}

fn summarize_depth_runs(runs: List(SourceRun), kind: DepthKind) -> String {
  let #(items, lists, unresolved) =
    depth_totals_from_runs(runs, kind, #(0, 0, 0))
  "sources="
  <> int.to_string(list.length(runs))
  <> " items="
  <> int.to_string(items)
  <> " lists="
  <> int.to_string(lists)
  <> " unresolved="
  <> int.to_string(unresolved)
}

fn depth_totals_from_runs(
  runs: List(SourceRun),
  kind: DepthKind,
  acc: #(Int, Int, Int),
) -> #(Int, Int, Int) {
  case runs {
    [] -> acc
    [run, ..rest] -> {
      let #(items_acc, lists_acc, unresolved_acc) = acc
      let result = depth_result_for_run(run, kind)
      let core.ResolveResult(items, lists, unresolved) = result
      depth_totals_from_runs(rest, kind, #(
        items_acc + list.length(items),
        lists_acc + list.length(lists),
        unresolved_acc + list.length(unresolved),
      ))
    }
  }
}

fn depth_details_from_runs(runs: List(SourceRun), kind: DepthKind) -> String {
  runs
  |> list.map(fn(run) {
    let SourceRun(source, _, _, _) = run
    let result = depth_result_for_run(run, kind)
    source.name <> ": " <> summarize_result(result)
  })
  |> string.join("\n")
}

fn validation_lines_from_runs(runs: List(SourceRun)) -> List(String) {
  list.map(runs, validation_line_from_run)
}

fn validation_line_from_run(run: SourceRun) -> String {
  let SourceRun(source, depth_1, depth_3, depth_all) = run
  let helpers.ValidationView(label, _, checks) =
    helpers.build_validation(
      source.min_depth_1_items,
      source.min_full_items,
      source.first_items_to_preserve,
      source.anchor_fragments,
      Some(depth_1),
      Some(depth_3),
      Some(depth_all),
    )
  let failed_checks =
    list.filter(checks, fn(check) {
      string.starts_with(check, "[ ]") || string.starts_with(check, "  -")
    })
  case label {
    "PASS" -> source.name <> ": PASS"
    _ ->
      case failed_checks {
        [] -> source.name <> ": FAIL"
        _ -> source.name <> ": FAIL | " <> string.join(failed_checks, " | ")
      }
  }
}

fn depth_result_for_run(run: SourceRun, kind: DepthKind) -> core.ResolveResult {
  let SourceRun(_, depth_1, depth_3, depth_all) = run
  case kind {
    Depth1Kind -> depth_1
    Depth3Kind -> depth_3
    DepthAllKind -> depth_all
  }
}

fn collect_debug_lines(
  subject: process.Subject(String),
  acc: List(String),
) -> List(String) {
  case process.receive(subject, within: 0) {
    Ok(line) -> collect_debug_lines(subject, [line, ..acc])
    Error(_) -> list.reverse(acc)
  }
}

fn debug_nodes(lines: List(String)) -> List(shore.Node(Msg)) {
  case lines {
    [] -> [ui.text("(no debug output)")]
    _ ->
      lines
      |> list.reverse
      |> list.take(20)
      |> list.reverse
      |> list.map(ui.text)
  }
}

fn cache_mode_text(value: cache.CacheMode) -> String {
  case value {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
    cache.CacheReadOnly -> "readonly"
  }
}
