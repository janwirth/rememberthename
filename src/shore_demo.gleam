import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/youtube/live_expander as youtube_live_expander
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import output/visual_output
import shore
import shore/key
import shore/layout
import shore/style
import shore/ui
import shore_demo/helpers

const track_viewport_size = 18

pub fn main() {
  case otp_supported() {
    True -> run_guarded(start_tui, restore_terminal_cursor)
    False ->
      io.println(
        "shore_demo requires Erlang/OTP 28 or newer. Detected OTP "
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
  let assert Ok(_actor) =
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
      redraw: shore.on_timer(33),
    )
    |> shore.start

  exit |> process.receive_forever
}

type Model {
  Model(
    selected_index: Int,
    focus: FocusPane,
    esc_armed: Bool,
    cache_enabled: Bool,
    depth_selected_index: Int,
    track_selected_index: Int,
    current_track_lines: List(String),
    current_fetch: FetchBundle,
    cached_fetches: List(#(String, FetchBundle)),
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

type SourceEntry {
  SourceEntry(
    key: String,
    name: String,
    entry_point: String,
    min_depth_1_items: Int,
    min_full_items: Int,
    first_items_to_preserve: Int,
    anchor_fragments: List(String),
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
  ToggleCache
  FetchCompleted(String, DepthKind, core.ResolveResult)
  Noop
}

fn init(exit_subject: process.Subject(Nil)) -> #(Model, List(fn() -> Msg)) {
  #(
    Model(
      selected_index: 0,
      focus: SidebarPane,
      esc_armed: False,
      cache_enabled: True,
      depth_selected_index: 0,
      track_selected_index: 0,
      current_track_lines: [],
      current_fetch: empty_fetch_bundle(),
      cached_fetches: [],
      exit_subject: exit_subject,
    ),
    [],
  )
}

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case msg {
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
        DetailPane -> #(
          Model(
            ..model,
            depth_selected_index: previous_depth_index(
              model.depth_selected_index,
            ),
          ),
          [],
        )
        TracksPane -> #(
          Model(
            ..model,
            track_selected_index: previous_track_index(
              model.track_selected_index,
              model.current_track_lines,
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
        DetailPane -> #(
          Model(
            ..model,
            depth_selected_index: next_depth_index(model.depth_selected_index),
          ),
          [],
        )
        TracksPane -> #(
          Model(
            ..model,
            track_selected_index: next_track_index(
              model.track_selected_index,
              model.current_track_lines,
            ),
          ),
          [],
        )
      }
    MoveRight ->
      case model.focus {
        TracksPane -> #(model, [])
        DetailPane ->
          case model.current_track_lines != [] {
            True -> #(Model(..model, focus: TracksPane), [])
            False -> #(model, [])
          }
        SidebarPane ->
          case selected_source(model.selected_index) {
            None -> #(model, [])
            Some(source) -> focus_detail(model, source)
          }
      }
    MoveLeft ->
      case model.focus {
        SidebarPane -> #(model, [])
        DetailPane -> #(Model(..model, focus: SidebarPane), [])
        TracksPane -> #(Model(..model, focus: DetailPane), [])
      }
    ActivateSelected ->
      case model.focus {
        SidebarPane ->
          case is_exit_selected(model.selected_index) {
            True -> request_exit(model)
            False ->
              case selected_source(model.selected_index) {
                None -> #(model, [])
                Some(source) -> focus_detail(model, source)
              }
          }
        DetailPane ->
          case selected_source(model.selected_index) {
            None -> #(model, [])
            Some(source) -> fetch_selected_depth(model, source)
          }
        TracksPane -> #(model, [])
      }
    EscPressed ->
      case model.esc_armed {
        True -> request_exit(model)
        False -> #(Model(..model, esc_armed: True), [])
      }
    ExitPressed -> request_exit(model)
    ToggleCache -> #(Model(..model, cache_enabled: !model.cache_enabled), [])
    FetchCompleted(source_key, depth_kind, result) -> {
      let status = fetched_status(result)
      let track_lines = track_lines_from_result(result)
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
            current_track_lines: track_lines,
            cached_fetches: put_cache(
              model.cached_fetches,
              source_key,
              set_depth_status(
                option_with_default(
                  get_cache(model.cached_fetches, source_key),
                  model.current_fetch,
                ),
                depth_kind,
                status,
              ),
            ),
          ),
          [],
        )
        _ -> #(
          Model(
            ..model,
            track_selected_index: 0,
            current_track_lines: track_lines,
            cached_fetches: put_cache(
              model.cached_fetches,
              source_key,
              set_depth_status(
                option_with_default(
                  get_cache(model.cached_fetches, source_key),
                  empty_fetch_bundle(),
                ),
                depth_kind,
                status,
              ),
            ),
          ),
          [],
        )
      }
    }
    Noop -> #(model, [])
  }
}

fn request_exit(model: Model) -> #(Model, List(fn() -> Msg)) {
  #(model, [
    fn() {
      process.send(model.exit_subject, Nil)
      Noop
    },
  ])
}

fn focus_detail(
  model: Model,
  source: SourceEntry,
) -> #(Model, List(fn() -> Msg)) {
  let base_model = Model(..model, focus: DetailPane, esc_armed: False)
  case model.cache_enabled {
    True ->
      case get_cache(model.cached_fetches, source.key) {
        Some(cached) -> #(Model(..base_model, current_fetch: cached), [])
        None -> #(Model(..base_model, current_fetch: empty_fetch_bundle()), [])
      }
    False -> #(Model(..base_model, current_fetch: empty_fetch_bundle()), [])
  }
}

fn fetch_selected_depth(
  model: Model,
  source: SourceEntry,
) -> #(Model, List(fn() -> Msg)) {
  let depth_kind = selected_depth_kind(model.depth_selected_index)
  let staged = set_depth_status(model.current_fetch, depth_kind, Fetching)
  #(Model(..model, current_fetch: staged), [
    fn() {
      let result =
        resolve_source(source, case depth_kind {
          Depth1Kind -> core.Depth1
          Depth3Kind -> core.Depth3
          DepthAllKind -> core.All
        })
      FetchCompleted(source.key, depth_kind, result)
    },
  ])
}

fn view(model: Model) -> shore.Node(Msg) {
  let selected = selected_content(model.selected_index)
  let sidebar_items = sidebar_item_nodes(model.selected_index, model.focus)
  let cache_label = case model.cache_enabled {
    True -> "cache: ON"
    False -> "cache: OFF"
  }
  let sidebar_children =
    [
      ui.text_styled(cache_label <> " (toggle: C)", Some(style.Yellow), None),
      ui.br(),
    ]
    |> list.append(sidebar_items)
    |> list.append([
      ui.keybind(key.Up, MoveUp),
      ui.keybind(key.Down, MoveDown),
      ui.keybind(key.Char("k"), MoveUp),
      ui.keybind(key.Char("j"), MoveDown),
      ui.keybind(key.Right, MoveRight),
      ui.keybind(key.Left, MoveLeft),
      ui.keybind(key.Enter, ActivateSelected),
      ui.keybind(key.Esc, EscPressed),
      ui.keybind(key.Char("c"), ToggleCache),
      ui.keybind(key.Char("C"), ToggleCache),
      ui.keybind(key.Char("x"), ExitPressed),
    ])

  let sidebar = ui.box(sidebar_children, Some("Sidebar"))

  let #(title, body) = selected
  let validation_checks = list.map(validation_checklist_lines(model), ui.text)
  let depth_nodes = depth_nodes(model)
  let main_content =
    ui.box(
      [ui.text(title), ui.hr(), validation_node(model)]
        |> list.append(validation_checks)
        |> list.append([
          ui.text_wrapped(body),
          ui.br(),
          ui.hr(),
          ui.text("Depth results"),
        ])
        |> list.append(depth_nodes)
        |> list.append([
          ui.br(),
          ui.text_wrapped(selected_depth_details(model)),
        ]),
      Some("Main"),
    )

  let tracks_content =
    ui.box(
      [ui.text("Tracks"), ui.hr()] |> list.append(track_panel_nodes(model)),
      Some("Tracks"),
    )

  layout.grid(
    gap: 1,
    rows: [style.Fill],
    cols: [style.Pct(28), style.Pct(36), style.Fill],
    cells: [
      layout.cell(content: sidebar, row: #(0, 0), col: #(0, 0)),
      layout.cell(content: main_content, row: #(0, 0), col: #(1, 1)),
      layout.cell(content: tracks_content, row: #(0, 0), col: #(2, 2)),
    ],
  )
}

fn section_count() -> Int {
  list.length(source_entries())
}

fn menu_count() -> Int {
  section_count() + 1
}

fn previous_index(index: Int) -> Int {
  case index <= 0 {
    True -> menu_count() - 1
    False -> index - 1
  }
}

fn next_index(index: Int) -> Int {
  case index >= menu_count() - 1 {
    True -> 0
    False -> index + 1
  }
}

fn is_exit_selected(index: Int) -> Bool {
  index == section_count()
}

fn selected_source(index: Int) -> Option(SourceEntry) {
  case is_exit_selected(index) {
    True -> None
    False -> source_at(source_entries(), index, 0)
  }
}

fn section_at(index: Int) -> #(String, String) {
  case source_at(source_entries(), index, 0) {
    Some(source) -> #(source.name, source_info_details(source))
    _ -> #("Unknown Source", "No source found at this index.")
  }
}

fn sidebar_item_nodes(
  selected_index: Int,
  focus: FocusPane,
) -> List(shore.Node(Msg)) {
  sidebar_item_nodes_loop(selected_index, focus, 0, [], menu_count())
  |> list.reverse
}

fn menu_item_title(index: Int) -> String {
  case is_exit_selected(index) {
    True -> "Exit"
    False ->
      case source_at(source_entries(), index, 0) {
        Some(source) -> source.name
        _ -> "Unknown"
      }
  }
}

fn sidebar_item_nodes_loop(
  selected_index: Int,
  focus: FocusPane,
  current_index: Int,
  items: List(shore.Node(Msg)),
  max: Int,
) -> List(shore.Node(Msg)) {
  case current_index >= max {
    True -> items
    False -> {
      let title = menu_item_title(current_index)
      let is_selected = current_index == selected_index && focus == SidebarPane
      let node = helpers.red_dot_node(title, is_selected)
      sidebar_item_nodes_loop(
        selected_index,
        focus,
        current_index + 1,
        [node, ..items],
        max,
      )
    }
  }
}

fn selected_content(index: Int) -> #(String, String) {
  case is_exit_selected(index) {
    True -> #("Exit", "Press Enter to gracefully close the Shore demo.")
    False -> section_at(index)
  }
}

fn source_info_details(source: SourceEntry) -> String {
  "Entry point: "
  <> source.entry_point
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

fn depth_line(model: Model, kind: DepthKind) -> String {
  let is_selected =
    depth_index(kind) == model.depth_selected_index && model.focus == DetailPane
  let marker = case is_selected {
    True -> "● "
    False -> "  "
  }
  let label = case kind {
    Depth1Kind -> "Depth 1"
    Depth3Kind -> "Depth 3"
    DepthAllKind -> "Depth All"
  }
  let status = depth_status_text(model.current_fetch, kind)
  marker <> label <> ": " <> status
}

fn depth_nodes(model: Model) -> List(shore.Node(Msg)) {
  [
    depth_node(model, Depth1Kind),
    depth_node(model, Depth3Kind),
    depth_node(model, DepthAllKind),
  ]
}

fn depth_node(model: Model, kind: DepthKind) -> shore.Node(Msg) {
  let selected =
    depth_index(kind) == model.depth_selected_index && model.focus == DetailPane
  let text = depth_line(model, kind)
  helpers.red_dot_node(text, selected)
}

fn depth_status_text(bundle: FetchBundle, kind: DepthKind) -> String {
  let status = case kind {
    Depth1Kind -> bundle.depth_1
    Depth3Kind -> bundle.depth_3
    DepthAllKind -> bundle.depth_all
  }
  case status {
    NotFetched -> "not fetched"
    Fetching -> "fetching..."
    Fetched(summary, _, _) -> summary
    FetchFailed(text) -> "failed: " <> text
  }
}

fn depth_index(kind: DepthKind) -> Int {
  case kind {
    Depth1Kind -> 0
    Depth3Kind -> 1
    DepthAllKind -> 2
  }
}

fn previous_depth_index(index: Int) -> Int {
  case index <= 0 {
    True -> 2
    False -> index - 1
  }
}

fn next_depth_index(index: Int) -> Int {
  case index >= 2 {
    True -> 0
    False -> index + 1
  }
}

fn empty_fetch_bundle() -> FetchBundle {
  FetchBundle(NotFetched, NotFetched, NotFetched)
}

fn selected_depth_kind(index: Int) -> DepthKind {
  case index {
    0 -> Depth1Kind
    1 -> Depth3Kind
    _ -> DepthAllKind
  }
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

fn track_panel_nodes(model: Model) -> List(shore.Node(Msg)) {
  helpers.track_panel_nodes(
    model.current_track_lines,
    model.track_selected_index,
    model.focus == TracksPane,
    track_viewport_size,
  )
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
  visual_output.TrackView(title, artist, service, source_id)
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
  let depth_kind = selected_depth_kind(model.depth_selected_index)
  let status = case depth_kind {
    Depth1Kind -> model.current_fetch.depth_1
    Depth3Kind -> model.current_fetch.depth_3
    DepthAllKind -> model.current_fetch.depth_all
  }
  case status {
    Fetched(_, details, _) -> details
    Fetching -> "Fetching selected depth..."
    NotFetched -> "Press Enter to fetch selected depth."
    FetchFailed(reason) -> "Fetch failed: " <> reason
  }
}

fn option_with_default(value: Option(a), fallback: a) -> a {
  case value {
    Some(inner) -> inner
    None -> fallback
  }
}

fn validation_node(model: Model) -> shore.Node(Msg) {
  case selected_source(model.selected_index) {
    None -> ui.text_styled("validation: n/a", Some(style.White), None)
    Some(source) -> {
      let helpers.ValidationView(label, color, _) =
        helpers.build_validation(
          source.min_depth_1_items,
          source.min_full_items,
          source.first_items_to_preserve,
          source.anchor_fragments,
          result_option(model.current_fetch.depth_1),
          result_option(model.current_fetch.depth_3),
          result_option(model.current_fetch.depth_all),
        )
      ui.text_styled("validation: " <> label, Some(color), None)
    }
  }
}

fn validation_checklist_lines(model: Model) -> List(String) {
  case selected_source(model.selected_index) {
    None -> ["[-] no source selected"]
    Some(source) -> {
      let helpers.ValidationView(_, _, checks) =
        helpers.build_validation(
          source.min_depth_1_items,
          source.min_full_items,
          source.first_items_to_preserve,
          source.anchor_fragments,
          result_option(model.current_fetch.depth_1),
          result_option(model.current_fetch.depth_3),
          result_option(model.current_fetch.depth_all),
        )
      checks
    }
  }
}

fn result_option(status: DepthStatus) -> Option(core.ResolveResult) {
  case status {
    Fetched(_, _, result) -> Some(result)
    _ -> None
  }
}

fn resolve_source(
  source: SourceEntry,
  depth: core.DepthMode,
) -> core.ResolveResult {
  case source.key {
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(source.entry_point)
      bandcamp_live_expander.resolve_profile(profile, depth)
    }
    "soundcloud" -> {
      let profile =
        soundcloud_live_expander.soundcloud_profile(source.entry_point)
      soundcloud_live_expander.resolve_profile(profile, depth)
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
          redirect_uri: "https://127.0.0.1:8080/spotify-oauth-success",
          scopes: "playlist-read-private playlist-read-collaborative user-library-read",
        )
      let profile = spotify_live_expander.spotify_user(source.entry_point)
      spotify_live_expander.resolve_profile(profile, depth, config)
    }
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(source.entry_point)
      youtube_live_expander.resolve_profile(profile, depth)
    }
  }
}

fn get_cache(
  entries: List(#(String, FetchBundle)),
  key: String,
) -> Option(FetchBundle) {
  case entries {
    [] -> None
    [#(entry_key, value), ..rest] ->
      case entry_key == key {
        True -> Some(value)
        False -> get_cache(rest, key)
      }
  }
}

fn put_cache(
  entries: List(#(String, FetchBundle)),
  key: String,
  value: FetchBundle,
) -> List(#(String, FetchBundle)) {
  case entries {
    [] -> [#(key, value)]
    [#(entry_key, entry_value), ..rest] ->
      case entry_key == key {
        True -> [#(key, value), ..rest]
        False -> [#(entry_key, entry_value), ..put_cache(rest, key, value)]
      }
  }
}

fn source_at(
  sources: List(SourceEntry),
  wanted: Int,
  current: Int,
) -> Option(SourceEntry) {
  case sources {
    [] -> None
    [source, ..rest] ->
      case current == wanted {
        True -> Some(source)
        False -> source_at(rest, wanted, current + 1)
      }
  }
}

fn source_entries() -> List(SourceEntry) {
  [
    SourceEntry(
      key: "bandcamp",
      name: "Bandcamp",
      entry_point: "https://bandcamp.com/janwirth",
      min_depth_1_items: 1,
      min_full_items: 700,
      first_items_to_preserve: 3,
      anchor_fragments: [
        "PUT THE NEEDLE ON THE RECORD",
        "Look Alive",
        "Manifest Content",
      ],
    ),
    SourceEntry(
      key: "soundcloud",
      name: "Soundcloud",
      entry_point: "https://soundcloud.com/tungstenselects",
      min_depth_1_items: 10,
      min_full_items: 1000,
      first_items_to_preserve: 3,
      anchor_fragments: [
        "A Horse with no Name (Edit)",
        "Nyxtape: Vol.12 - Harley D",
        "PREMIERE| Rebecca Delle Piane - Genomica [FIDESX4]",
        "Premiere: KAIPE - Batie",
      ],
    ),
    SourceEntry(
      key: "spotify",
      name: "Spotify",
      entry_point: "https://open.spotify.com/user/franzskuffka",
      min_depth_1_items: 50,
      min_full_items: 1000,
      first_items_to_preserve: 3,
      anchor_fragments: ["Blask", "SOLD MY SOUL"],
    ),
    SourceEntry(
      key: "youtube",
      name: "Youtube",
      entry_point: "https://www.youtube.com/playlist?list=PLK7cxKkqBmwmpPoWznuEF-xEljswMRR3V",
      min_depth_1_items: 5,
      min_full_items: 1000,
      first_items_to_preserve: 3,
      anchor_fragments: [
        "Angine de poitrine - Sahardnieh",
        "Nimo - BITTER",
        "Vengaboys - Up & Down",
        "Dendemann - Wo ich wech bin",
        "BHZ - SCHLIESSE DIE AUGEN",
      ],
    ),
  ]
}
