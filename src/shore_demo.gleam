import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import shore
import shore/key
import shore/layout
import shore/ui

pub fn main() {
  let exit = process.new_subject()
  let assert Ok(_actor) =
    shore.spec(
      init:,
      update:,
      view:,
      exit:,
      keybinds: shore.default_keybinds(),
      redraw: shore.on_update(),
    )
    |> shore.start

  exit |> process.receive_forever
}

type Model {
  Model(selected_index: Int)
}

type Msg {
  MoveUp
  MoveDown
}

fn init() -> #(Model, List(fn() -> Msg)) {
  #(Model(selected_index: 0), [])
}

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case msg {
    MoveUp -> #(Model(selected_index: previous_index(model.selected_index)), [])
    MoveDown -> #(Model(selected_index: next_index(model.selected_index)), [])
  }
}

fn view(model: Model) -> shore.Node(Msg) {
  let selected = section_at(model.selected_index)

  let sidebar =
    ui.box(
      [
        ui.text("Navigate"),
        ui.text("up/down arrows or k/j"),
        ui.br(),
        ui.text(sidebar_menu(model.selected_index)),
        ui.br(),
        ui.button("Move up (k)", key.Char("k"), MoveUp),
        ui.button("Move down (j)", key.Char("j"), MoveDown),
        ui.keybind(key.Up, MoveUp),
        ui.keybind(key.Down, MoveDown),
      ],
      Some("Sidebar"),
    )

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
          <> int.to_string(section_count()),
        ),
      ],
      Some("Main"),
    )

  layout.split(sidebar, main_content)
}

fn section_count() -> Int {
  5
}

fn previous_index(index: Int) -> Int {
  case index <= 0 {
    True -> section_count() - 1
    False -> index - 1
  }
}

fn next_index(index: Int) -> Int {
  case index >= section_count() - 1 {
    True -> 0
    False -> index + 1
  }
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

fn sidebar_menu(selected_index: Int) -> String {
  menu_lines(selected_index, 0, [], section_count())
  |> list.reverse
  |> string.join("\n")
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
      let #(title, _) = section_at(current_index)
      let marker = case current_index == selected_index {
        True -> ">"
        False -> " "
      }
      let line = marker <> " " <> title
      menu_lines(selected_index, current_index + 1, [line, ..lines], max)
    }
  }
}
