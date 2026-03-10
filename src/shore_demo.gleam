import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import shore
import shore/key
import shore/layout
import shore/style
import shore/ui

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
    esc_armed: Bool,
    exit_subject: process.Subject(Nil),
  )
}

type Msg {
  MoveUp
  MoveDown
  ActivateSelected
  EscPressed
  ExitPressed
  Noop
}

fn init(exit_subject: process.Subject(Nil)) -> #(Model, List(fn() -> Msg)) {
  #(Model(selected_index: 0, esc_armed: False, exit_subject: exit_subject), [])
}

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case msg {
    MoveUp -> #(
      Model(
        ..model,
        selected_index: previous_index(model.selected_index),
        esc_armed: False,
      ),
      [],
    )
    MoveDown -> #(
      Model(
        ..model,
        selected_index: next_index(model.selected_index),
        esc_armed: False,
      ),
      [],
    )
    ActivateSelected ->
      case is_exit_selected(model.selected_index) {
        True -> request_exit(model)
        False -> #(model, [])
      }
    EscPressed ->
      case model.esc_armed {
        True -> request_exit(model)
        False -> #(Model(..model, esc_armed: True), [])
      }
    ExitPressed -> request_exit(model)
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

fn view(model: Model) -> shore.Node(Msg) {
  let selected = selected_content(model.selected_index)
  let sidebar_items = sidebar_items(model.selected_index)
  let sidebar_children =
    [
      ui.text("Navigate"),
      ui.text("Up/Down or k/j to target"),
      ui.text("Enter to open/confirm"),
      ui.text("Esc Esc to exit"),
      ui.br(),
    ]
    |> list.append(list.map(sidebar_items, ui.text))
    |> list.append([
      ui.keybind(key.Up, MoveUp),
      ui.keybind(key.Down, MoveDown),
      ui.keybind(key.Char("k"), MoveUp),
      ui.keybind(key.Char("j"), MoveDown),
      ui.keybind(key.Enter, ActivateSelected),
      ui.keybind(key.Esc, EscPressed),
      ui.keybind(key.Char("x"), ExitPressed),
    ])

  let sidebar = ui.box(sidebar_children, Some("Sidebar"))

  let #(title, body) = selected
  let main_content =
    ui.box(
      [
        ui.text(title),
        ui.hr(),
        ui.text_wrapped(body),
        ui.br(),
        ui.text(
          "Selection "
          <> int.to_string(model.selected_index + 1)
          <> "/"
          <> int.to_string(menu_count()),
        ),
      ],
      Some("Main"),
    )

  layout.grid(
    gap: 1,
    rows: [style.Fill],
    cols: [style.Pct(32), style.Fill],
    cells: [
      layout.cell(content: sidebar, row: #(0, 0), col: #(0, 0)),
      layout.cell(content: main_content, row: #(0, 0), col: #(1, 1)),
    ],
  )
}

fn section_count() -> Int {
  5
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

fn section_at(index: Int) -> #(String, String) {
  case index {
    0 -> #(
      "Overview",
      "This demo shows a Shore terminal layout with a navigable sidebar on the left and detail content on the right.",
    )
    1 -> #(
      "How To Use",
      "Press Up/Down arrows, or use k and j, to move the selection through sidebar items. The main panel updates immediately.",
    )
    2 -> #(
      "Architecture",
      "This app follows The Elm Architecture: a model stores selected_index, messages update it, and view renders from state.",
    )
    3 -> #(
      "Why Shore",
      "Shore provides focus management, keybinds, layouts, and terminal widgets while keeping Gleam code simple and predictable.",
    )
    _ -> #(
      "Next Steps",
      "Replace these static sections with real data (tracks, playlists, sync jobs) and keep the same navigation pattern.",
    )
  }
}

fn sidebar_items(selected_index: Int) -> List(String) {
  menu_lines(selected_index, 0, [], menu_count()) |> list.reverse
}

fn menu_item_title(index: Int) -> String {
  case is_exit_selected(index) {
    True -> "Exit"
    False -> section_at(index).0
  }
}

fn selected_content(index: Int) -> #(String, String) {
  case is_exit_selected(index) {
    True -> #("Exit", "Press Enter to gracefully close the Shore demo.")
    False -> section_at(index)
  }
}

fn menu_lines(
  selected_index: Int,
  current_index: Int,
  lines: List(String),
  max: Int,
) -> List(String) {
  case current_index >= max {
    True -> lines
    False -> {
      let title = menu_item_title(current_index)
      let marker = case current_index == selected_index {
        True -> ">"
        False -> " "
      }
      let line = marker <> " " <> title
      menu_lines(selected_index, current_index + 1, [line, ..lines], max)
    }
  }
}
