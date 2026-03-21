import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/youtube/live_expander as youtube_live_expander
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import output/csv_writer
import output/visual_output
import shore
import shore/key
import shore/layout
import shore/style
import shore/ui
import simplifile
import source_specs

pub fn main() {
  case otp_supported() {
    True -> run_guarded(start_ui, restore_terminal_cursor)
    False ->
      io.println(
        "interactive export requires Erlang/OTP 28 or newer. Detected OTP "
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
  restore_shell()
  io.print("")
}

type Step {
  SelectSourcesStep
  SelectActionStep
  ConfirmStep
  RunningStep
  DoneStep
}

type Action {
  ExportCsv
  FetchOnly
}

type CacheChoice {
  UseLive
  UseCache
}

type Model {
  Model(
    step: Step,
    cursor: Int,
    selected_keys: List(String),
    action: Action,
    cache_choice: CacheChoice,
    status_lines: List(String),
    exit_subject: process.Subject(Nil),
  )
}

type Msg {
  MoveUp
  MoveDown
  Toggle
  Activate
  Back
  ExitPressed
  RunFinished(List(String))
  Noop
}

fn start_ui() {
  let exit = process.new_subject()
  case
    shore.spec(
      init: fn() { #(init(exit), []) },
      update:,
      view:,
      exit: exit,
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
    Error(_) -> io.println("interactive export failed to start")
  }
}

fn init(exit_subject: process.Subject(Nil)) -> Model {
  Model(
    step: SelectSourcesStep,
    cursor: 0,
    selected_keys: [],
    action: ExportCsv,
    cache_choice: UseLive,
    status_lines: ["Select one or more sources, then press Enter."],
    exit_subject: exit_subject,
  )
}

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case msg {
    MoveUp -> #(Model(..model, cursor: previous_cursor(model)), [])
    MoveDown -> #(Model(..model, cursor: next_cursor(model)), [])
    Toggle -> #(toggle_current_source(model), [])
    Back -> #(go_back(model), [])
    ExitPressed -> request_exit(model)
    Activate -> activate(model)
    RunFinished(lines) -> #(
      Model(..model, step: DoneStep, cursor: 0, status_lines: lines),
      [],
    )
    Noop -> #(model, [])
  }
}

fn activate(model: Model) -> #(Model, List(fn() -> Msg)) {
  case model.step {
    SelectSourcesStep ->
      case model.selected_keys == [] {
        True -> #(
          Model(..model, status_lines: [
            "Select at least one source before continuing.",
          ]),
          [],
        )
        False -> #(
          Model(..model, step: SelectActionStep, cursor: 0, status_lines: [
            "Choose action and cache mode.",
          ]),
          [],
        )
      }
    SelectActionStep -> {
      let #(action, cache_choice) = action_for_cursor(model.cursor)
      #(
        Model(
          ..model,
          step: ConfirmStep,
          action: action,
          cache_choice: cache_choice,
          cursor: 0,
          status_lines: [
            "Review and press Enter to run. Press Left to go back.",
          ],
        ),
        [],
      )
    }
    ConfirmStep -> {
      let next =
        Model(..model, step: RunningStep, cursor: 0, status_lines: [
          "Running...",
        ])
      #(next, [fn() { run_selected(next) }])
    }
    RunningStep -> #(model, [])
    DoneStep -> #(
      Model(..model, step: SelectSourcesStep, cursor: 0, status_lines: [
        "Run completed. You can adjust and run again.",
      ]),
      [],
    )
  }
}

fn run_selected(model: Model) -> Msg {
  let specs = selected_specs(model.selected_keys)
  let cache_mode = cache_mode_from_choice(model.cache_choice)
  let action_label = action_text(model.action)
  let cache_label = cache_choice_text(model.cache_choice)

  let run_lines =
    list.fold(specs, [], fn(lines, spec) {
      let source_specs.SourceSpec(
        key,
        name,
        entry_point,
        timing_spec,
        assert_spec,
      ) = spec
      let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) =
        assert_spec
      let result =
        resolve_source(
          key,
          entry_point,
          core.All,
          source_limit,
          timing_spec,
          cache_mode,
          fn(_line) { Nil },
        )
      let core.ResolveResult(items, lists, unresolved) = result
      let details =
        name
        <> " ("
        <> key
        <> "): items="
        <> int.to_string(list.length(items))
        <> " lists="
        <> int.to_string(list.length(lists))
        <> " unresolved="
        <> int.to_string(list.length(unresolved))
      let lines = list.append(lines, [details])
      case model.action {
        ExportCsv -> {
          let tracks = list.map(items, to_track_view)
          let csv = csv_writer.tracks_csv(tracks)
          let per_source_path = "output/interactive_" <> key <> "_full.csv"
          let _ = simplifile.write(csv, to: per_source_path)
          list.append(lines, ["  csv: " <> per_source_path])
        }
        FetchOnly -> lines
      }
    })

  let summary_lines =
    [
      "Done.",
      "Action: " <> action_label,
      "Cache: " <> cache_label,
      "Sources: " <> string.join(model.selected_keys, ", "),
      "",
    ]
    |> list.append(run_lines)

  let final_lines = case model.action {
    ExportCsv -> {
      let all_items = collect_all_items(specs, cache_mode)
      let tracks = list.map(all_items, to_track_view)
      let csv = csv_writer.tracks_csv(tracks)
      let combined_path = "output/interactive_selected_latest.csv"
      let _ = simplifile.write(csv, to: combined_path)
      list.append(summary_lines, [
        "",
        "Combined CSV: " <> combined_path,
        "Total items: " <> int.to_string(list.length(all_items)),
      ])
    }
    FetchOnly -> summary_lines
  }

  RunFinished(final_lines)
}

fn collect_all_items(
  specs: List(source_specs.SourceSpec),
  cache_mode: cache.CacheMode,
) -> List(core.UnifiedItem) {
  list.fold(specs, [], fn(acc, spec) {
    let source_specs.SourceSpec(key, _, entry_point, timing_spec, assert_spec) =
      spec
    let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
    let core.ResolveResult(items, _, _) =
      resolve_source(
        key,
        entry_point,
        core.All,
        source_limit,
        timing_spec,
        cache_mode,
        fn(_line) { Nil },
      )
    list.append(acc, items)
  })
}

fn selected_specs(selected_keys: List(String)) -> List(source_specs.SourceSpec) {
  list.filter(source_specs.all(), fn(spec) {
    let source_specs.SourceSpec(key, _, _, _, _) = spec
    list.contains(selected_keys, key)
  })
}

fn go_back(model: Model) -> Model {
  case model.step {
    SelectSourcesStep -> model
    SelectActionStep -> Model(..model, step: SelectSourcesStep, cursor: 0)
    ConfirmStep -> Model(..model, step: SelectActionStep, cursor: 0)
    RunningStep -> model
    DoneStep -> Model(..model, step: SelectSourcesStep, cursor: 0)
  }
}

fn toggle_current_source(model: Model) -> Model {
  case model.step {
    SelectSourcesStep -> {
      let specs = source_specs.all()
      case model.cursor {
        0 -> {
          let all_keys =
            list.map(specs, fn(spec) {
              let source_specs.SourceSpec(key, _, _, _, _) = spec
              key
            })
          case list.length(model.selected_keys) == list.length(all_keys) {
            True -> Model(..model, selected_keys: [])
            False -> Model(..model, selected_keys: all_keys)
          }
        }
        _ ->
          case source_at(specs, model.cursor - 1) {
            Ok(spec) -> {
              let source_specs.SourceSpec(key, _, _, _, _) = spec
              let next_selected = toggle_key(model.selected_keys, key)
              Model(..model, selected_keys: next_selected)
            }
            Error(_) -> model
          }
      }
    }
    _ -> model
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

fn previous_cursor(model: Model) -> Int {
  let max = option_count(model.step) - 1
  case model.cursor <= 0 {
    True -> max
    False -> model.cursor - 1
  }
}

fn next_cursor(model: Model) -> Int {
  let max = option_count(model.step) - 1
  case model.cursor >= max {
    True -> 0
    False -> model.cursor + 1
  }
}

fn option_count(step: Step) -> Int {
  case step {
    SelectSourcesStep -> 1 + list.length(source_specs.all())
    SelectActionStep -> list.length(action_options())
    ConfirmStep -> 1
    RunningStep -> 1
    DoneStep -> 1
  }
}

fn action_options() -> List(#(Action, CacheChoice, String)) {
  [
    #(ExportCsv, UseLive, "Export CSV (without cache)"),
    #(ExportCsv, UseCache, "Export CSV (use cache)"),
    #(FetchOnly, UseLive, "Fetch only (without cache)"),
    #(FetchOnly, UseCache, "Fetch only (use cache)"),
  ]
}

fn action_for_cursor(index: Int) -> #(Action, CacheChoice) {
  case action_at(action_options(), index) {
    Ok(#(action, cache_choice, _)) -> #(action, cache_choice)
    Error(_) -> #(ExportCsv, UseLive)
  }
}

fn action_at(
  entries: List(#(Action, CacheChoice, String)),
  index: Int,
) -> Result(#(Action, CacheChoice, String), Nil) {
  case entries {
    [] -> Error(Nil)
    [entry, ..rest] ->
      case index == 0 {
        True -> Ok(entry)
        False -> action_at(rest, index - 1)
      }
  }
}

fn source_at(
  entries: List(source_specs.SourceSpec),
  index: Int,
) -> Result(source_specs.SourceSpec, Nil) {
  case entries {
    [] -> Error(Nil)
    [entry, ..rest] ->
      case index == 0 {
        True -> Ok(entry)
        False -> source_at(rest, index - 1)
      }
  }
}

fn toggle_key(keys: List(String), target: String) -> List(String) {
  case list.contains(keys, target) {
    True -> list.filter(keys, fn(value) { value != target })
    False -> list.append(keys, [target])
  }
}

fn cache_mode_from_choice(choice: CacheChoice) -> cache.CacheMode {
  case choice {
    UseLive -> cache.CacheOverride
    UseCache -> cache.CacheUpsert
  }
}

fn action_text(action: Action) -> String {
  case action {
    ExportCsv -> "Export CSV"
    FetchOnly -> "Fetch only"
  }
}

fn cache_choice_text(choice: CacheChoice) -> String {
  case choice {
    UseLive -> "without cache"
    UseCache -> "use cache"
  }
}

fn view(model: Model) -> shore.Node(Msg) {
  let left = ui.box(left_panel_nodes(model), Some("Step"))
  let right = ui.box(right_panel_nodes(model), Some("Details"))
  layout.grid(
    gap: 1,
    rows: [style.Fill],
    cols: [style.Pct(34), style.Fill],
    cells: [
      layout.cell(content: left, row: #(0, 0), col: #(0, 0)),
      layout.cell(content: right, row: #(0, 0), col: #(1, 1)),
    ],
  )
}

fn left_panel_nodes(model: Model) -> List(shore.Node(Msg)) {
  let step_title = case model.step {
    SelectSourcesStep -> "1) Select sources"
    SelectActionStep -> "2) Select action"
    ConfirmStep -> "3) Confirm"
    RunningStep -> "Running"
    DoneStep -> "Done"
  }
  [ui.text(step_title), ui.br()]
  |> list.append(step_items(model))
  |> list.append([
    ui.br(),
    ui.hr(),
    ui.text("Keys"),
    ui.text("  ↑/↓ or j/k move"),
    ui.text("  Enter/Right continue/run"),
    ui.text("  Space toggle source/all"),
    ui.text("  Left/Esc back"),
    ui.text("  Ctrl+X exit"),
    ui.keybind(key.Up, MoveUp),
    ui.keybind(key.Down, MoveDown),
    ui.keybind(key.Char("k"), MoveUp),
    ui.keybind(key.Char("j"), MoveDown),
    ui.keybind(key.Char(" "), Toggle),
    ui.keybind(key.Enter, Activate),
    ui.keybind(key.Right, Activate),
    ui.keybind(key.Left, Back),
    ui.keybind(key.Esc, Back),
    ui.keybind(key.Char("x"), ExitPressed),
  ])
}

fn step_items(model: Model) -> List(shore.Node(Msg)) {
  case model.step {
    SelectSourcesStep -> source_step_nodes(model)
    SelectActionStep -> action_step_nodes(model)
    ConfirmStep -> [item_node("Run now", model.cursor == 0)]
    RunningStep -> [ui.text("Please wait...")]
    DoneStep -> [ui.text("Press Enter to start another run.")]
  }
}

fn source_step_nodes(model: Model) -> List(shore.Node(Msg)) {
  let specs = source_specs.all()
  let all_selected = list.length(model.selected_keys) == list.length(specs)
  let all_node =
    source_item_node("All sources", all_selected, model.cursor == 0)
  let source_nodes =
    list.index_map(specs, fn(spec, index) {
      let source_specs.SourceSpec(key, name, _, _, _) = spec
      source_item_node(
        name <> " (" <> key <> ")",
        list.contains(model.selected_keys, key),
        model.cursor == index + 1,
      )
    })
  list.append([all_node], source_nodes)
}

fn action_step_nodes(model: Model) -> List(shore.Node(Msg)) {
  list.index_map(action_options(), fn(entry, index) {
    let #(_, _, label) = entry
    item_node(label, model.cursor == index)
  })
}

fn source_item_node(
  text: String,
  selected: Bool,
  focused: Bool,
) -> shore.Node(Msg) {
  let marker = case selected {
    True -> "[x] "
    False -> "[ ] "
  }
  item_node(marker <> text, focused)
}

fn item_node(text: String, focused: Bool) -> shore.Node(Msg) {
  case focused {
    True -> ui.text_styled("● " <> text, Some(style.Red), None)
    False -> ui.text("  " <> text)
  }
}

fn right_panel_nodes(model: Model) -> List(shore.Node(Msg)) {
  let selected_names =
    list.filter_map(source_specs.all(), fn(spec) {
      let source_specs.SourceSpec(key, name, _, _, _) = spec
      case list.contains(model.selected_keys, key) {
        True -> Ok("  - " <> name <> " (" <> key <> ")")
        False -> Error(Nil)
      }
    })
  let action_line =
    "Action: "
    <> action_text(model.action)
    <> " | "
    <> cache_choice_text(model.cache_choice)
  [
    ui.text(
      "Selected sources: " <> int.to_string(list.length(model.selected_keys)),
    ),
    ui.text(action_line),
    ui.br(),
  ]
  |> list.append(case selected_names == [] {
    True -> [ui.text("  - none selected")]
    False -> list.map(selected_names, ui.text)
  })
  |> list.append([
    ui.br(),
    ui.hr(),
    ui.text("Status"),
  ])
  |> list.append(list.map(model.status_lines, ui.text))
}

fn resolve_source(
  key: String,
  entry_point: String,
  depth: core.DepthMode,
  source_limit: Int,
  timing_spec: source_specs.SourceTimingSpec,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let source_specs.SourceTimingSpec(max_concurrency, requests_per_second) =
    timing_spec
  let queue_policy =
    core.QueuePolicy(
      max_concurrency: max_concurrency,
      requests_per_second: requests_per_second,
    )
  case key {
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(entry_point)
      bandcamp_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
    "soundcloud" -> {
      let profile = soundcloud_live_expander.soundcloud_profile(entry_point)
      soundcloud_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        source_limit,
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
      let profile = spotify_live_expander.spotify_user(entry_point)
      spotify_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        config,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(entry_point)
      youtube_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
        fn(_) { Nil },
      )
    }
  }
}

fn to_track_view(item: core.UnifiedItem) -> visual_output.TrackView {
  let core.UnifiedItem(_, title, artist, service, _, source_id, external_source_url) =
    item
  visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    external_source_url,
    "",
    "",
    "",
    "",
  )
}
