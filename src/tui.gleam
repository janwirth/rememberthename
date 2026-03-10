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
import tui/helpers
import source_specs

const track_viewport_size = 18

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
    Error(_) ->
      io.println("tui failed to start")
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
    current_debug_lines: List(String),
    current_fetch: FetchBundle,
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
    use_cache: Bool,
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
  FetchCompleted(String, DepthKind, DepthStatus, List(String), List(String))
  Noop
}

fn init(exit_subject: process.Subject(Nil)) -> #(Model, List(fn() -> Msg)) {
  #(
    Model(
      selected_index: 0,
      focus: SidebarPane,
      esc_armed: False,
      depth_selected_index: 0,
      track_selected_index: 0,
      current_track_lines: [],
      current_debug_lines: [],
      current_fetch: empty_fetch_bundle(),
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
    FetchCompleted(source_key, depth_kind, status, track_lines, debug_lines) -> {
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
            current_debug_lines: debug_lines,
          ),
          [],
        )
        _ -> #(
          Model(
            ..model,
            track_selected_index: 0,
            current_track_lines: track_lines,
            current_debug_lines: debug_lines,
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
  _source: SourceEntry,
) -> #(Model, List(fn() -> Msg)) {
  #(
    Model(
      ..model,
      focus: DetailPane,
      esc_armed: False,
      current_fetch: empty_fetch_bundle(),
      current_debug_lines: [],
    ),
    [],
  )
}

fn fetch_selected_depth(
  model: Model,
  source: SourceEntry,
) -> #(Model, List(fn() -> Msg)) {
  let depth_kind = selected_depth_kind(model.depth_selected_index)
  let staged = set_depth_status(model.current_fetch, depth_kind, Fetching)
  #(Model(..model, current_fetch: staged), [
    fn() {
      let debug_subject = process.new_subject()
      let result =
        resolve_source(
          source,
          case depth_kind {
            Depth1Kind -> core.Depth1
            Depth3Kind -> core.Depth3
            DepthAllKind -> core.All
          },
          source.use_cache,
          fn(line) { process.send(debug_subject, line) },
        )
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

fn view(model: Model) -> shore.Node(Msg) {
  let sidebar_items = sidebar_item_nodes(model.selected_index, model.focus)
  let sidebar_children =
    [ui.text_styled("adapter cache: per-source", Some(style.Yellow), None), ui.br()]
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
      ui.keybind(key.Char("x"), ExitPressed),
    ])

  let sidebar = ui.box(sidebar_children, Some("Sidebar"))

  let main_children = {
    let #(title, body) = selected_content(model.selected_index)
    [ui.text(title), ui.hr()]
    |> list.append(validation_view_nodes(model))
    |> list.append([
      ui.text(body),
      ui.br(),
      ui.hr(),
      ui.text("Depth results"),
    ])
    |> list.append(depth_nodes(model))
    |> list.append([
      ui.br(),
      ui.text(selected_depth_details(model)),
      ui.br(),
      ui.text("Debug"),
      ui.hr(),
    ])
    |> list.append(debug_nodes(model.current_debug_lines))
  }
  let main_content =
    ui.box(
      main_children,
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

fn validation_view_nodes(model: Model) -> List(shore.Node(Msg)) {
  case selected_source(model.selected_index) {
    None -> helpers.validation_unavailable_nodes()
    Some(source) -> {
      helpers.validation_nodes(
        source.min_depth_1_items,
        source.min_full_items,
        source.first_items_to_preserve,
        source.anchor_fragments,
        result_option(model.current_fetch.depth_1),
        result_option(model.current_fetch.depth_3),
        result_option(model.current_fetch.depth_all),
      )
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
  use_cache: Bool,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  case source.key {
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(source.entry_point)
      bandcamp_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        use_cache,
        on_debug,
      )
    }
    "soundcloud" -> {
      let profile =
        soundcloud_live_expander.soundcloud_profile(source.entry_point)
      soundcloud_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        use_cache,
        on_debug,
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
      spotify_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        config,
        use_cache,
        on_debug,
      )
    }
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(source.entry_point)
      youtube_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        use_cache,
        on_debug,
      )
    }
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
  list.map(source_specs.all(), source_entry_from_spec)
}

fn source_entry_from_spec(spec: source_specs.SourceSpec) -> SourceEntry {
  let source_specs.SourceSpec(key, name, entry_point, use_cache, assert_spec) = spec
  let source_specs.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    first_items_to_preserve,
    anchor_fragments,
    _,
  ) = assert_spec
  SourceEntry(
    key: key,
    name: name,
    entry_point: entry_point,
    use_cache: use_cache,
    min_depth_1_items: min_depth_1_items,
    min_full_items: min_full_items,
    first_items_to_preserve: first_items_to_preserve,
    anchor_fragments: anchor_fragments,
  )
}
