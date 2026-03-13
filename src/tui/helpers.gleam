import adapters/core
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import shore
import shore/style
import shore/ui

pub type ValidationView {
  ValidationView(
    status_label: String,
    status_color: style.Color,
    checks: List(String),
  )
}

pub fn red_dot_node(text: String, selected: Bool) -> shore.Node(msg) {
  let marker = case selected {
    True -> "● "
    False -> "  "
  }
  case selected {
    True -> ui.text_styled(marker <> text, Some(style.Red), None)
    False -> ui.text(marker <> text)
  }
}

pub fn sidebar_item_node(
  text: String,
  selected: Bool,
  sidebar_focused: Bool,
) -> shore.Node(msg) {
  case selected {
    True ->
      case sidebar_focused {
        True -> red_dot_node(text, True)
        False ->
          ui.text_styled("  " <> text, Some(style.Black), Some(style.White))
      }
    False -> red_dot_node(text, False)
  }
}

pub fn track_panel_nodes(
  lines: List(String),
  selected_index: Int,
  focused: Bool,
  viewport_size: Int,
) -> List(shore.Node(msg)) {
  case lines {
    [] -> [ui.text("enter to fetch")]
    _ -> {
      let visible = visible_track_lines(lines, selected_index, viewport_size)
      list.map(visible, fn(entry) {
        let #(actual_index, line) = entry
        red_dot_node(line, focused && actual_index == selected_index)
      })
    }
  }
}

pub fn build_validation(
  min_depth_1_items: Int,
  min_full_items: Int,
  first_items_to_preserve: Int,
  anchor_fragments: List(String),
  depth_1: Option(core.ResolveResult),
  depth_3: Option(core.ResolveResult),
  depth_all: Option(core.ResolveResult),
) -> ValidationView {
  case depth_1, depth_3, depth_all {
    Some(r1), Some(r3), Some(rall) -> {
      let #(i1, l1, u1) = result_counts(r1)
      let #(i3, _, _) = result_counts(r3)
      let #(iall, lall, uall) = result_counts(rall)

      let min_depth_ok = i1 >= min_depth_1_items
      let min_full_ok = iall >= min_full_items
      let monotonic_ok = i3 > i1 && iall >= i3
      let consistency_ok = lall >= l1 && uall == u1

      let first_ids = first_ids_from_result(r1, first_items_to_preserve)
      let first_items_ok =
        first_ids != [] && list.all(first_ids, fn(id) { has_item_id(rall, id) })

      let anchors_shallow_ok =
        list.all(anchor_fragments, fn(fragment) {
          has_title_fragment(result_items(r1), fragment)
          || has_title_fragment(result_items(r3), fragment)
        })
      let anchors_full_ok =
        list.all(anchor_fragments, fn(fragment) {
          has_title_fragment(result_items(rall), fragment)
        })
      let anchors_ok = anchors_shallow_ok && anchors_full_ok
      let missing_shallow =
        missing_fragments_from_items(
          anchor_fragments,
          result_items(r1),
          result_items(r3),
        )
      let missing_full =
        missing_fragments_from_items(anchor_fragments, result_items(rall), [])
      let anchor_reason_lines = case anchors_ok {
        True -> []
        False -> [
          "  - missing in depth 1/3: " <> format_fragments(missing_shallow),
          "  - missing in full: " <> format_fragments(missing_full),
        ]
      }

      let checks =
        [
          "[x] depth 1/3/all fetched",
          checkbox(min_depth_ok) <> " min depth-1 items",
          checkbox(min_full_ok) <> " min full items",
          checkbox(monotonic_ok) <> " depth monotonicity",
          checkbox(consistency_ok) <> " list/unresolved consistency",
          checkbox(first_items_ok) <> " first items preserved",
          checkbox(anchors_ok) <> " anchor fragments present",
        ]
        |> list.append(anchor_reason_lines)
      let passed =
        min_depth_ok
        && min_full_ok
        && monotonic_ok
        && consistency_ok
        && first_items_ok
        && anchors_ok
      case passed {
        True -> ValidationView("PASS", style.Green, checks)
        False -> ValidationView("FAIL", style.Red, checks)
      }
    }
    _, _, _ ->
      ValidationView("PENDING", style.Yellow, [
        "[-] depth 1/3/all fetched",
        "[-] min depth-1 items",
        "[-] min full items",
        "[-] depth monotonicity",
        "[-] list/unresolved consistency",
        "[-] first items preserved",
        "[-] anchor fragments present",
      ])
  }
}

pub fn validation_nodes(
  min_depth_1_items: Int,
  min_full_items: Int,
  first_items_to_preserve: Int,
  anchor_fragments: List(String),
  depth_1: Option(core.ResolveResult),
  depth_3: Option(core.ResolveResult),
  depth_all: Option(core.ResolveResult),
) -> List(shore.Node(msg)) {
  let ValidationView(label, color, checks) =
    build_validation(
      min_depth_1_items,
      min_full_items,
      first_items_to_preserve,
      anchor_fragments,
      depth_1,
      depth_3,
      depth_all,
    )
  [ui.text_styled("validation: " <> label, Some(color), None)]
  |> list.append(list.map(checks, ui.text))
}

pub fn validation_unavailable_nodes() -> List(shore.Node(msg)) {
  [
    ui.text_styled("validation: n/a", Some(style.White), None),
    ui.text("[-] no source selected"),
  ]
}

fn checkbox(passed: Bool) -> String {
  case passed {
    True -> "[x]"
    False -> "[ ]"
  }
}

fn visible_track_lines(
  lines: List(String),
  selected_index: Int,
  viewport_size: Int,
) -> List(#(Int, String)) {
  let total = list.length(lines)
  case total <= viewport_size {
    True -> index_lines(lines, 0, [])
    False -> {
      let half = viewport_size / 2
      let start = clamp_int(selected_index - half, 0, total - viewport_size)
      lines
      |> list.drop(start)
      |> list.take(viewport_size)
      |> index_lines(start, [])
    }
  }
}

fn index_lines(
  lines: List(String),
  start_index: Int,
  acc: List(#(Int, String)),
) -> List(#(Int, String)) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] ->
      index_lines(rest, start_index + 1, [#(start_index, line), ..acc])
  }
}

fn result_counts(result: core.ResolveResult) -> #(Int, Int, Int) {
  let core.ResolveResult(items, lists, unresolved) = result
  #(list.length(items), list.length(lists), list.length(unresolved))
}

fn result_items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

fn first_ids_from_result(result: core.ResolveResult, count: Int) -> List(String) {
  result
  |> result_items
  |> list.take(count)
  |> list.map(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _) = item
    id
  })
}

fn has_item_id(result: core.ResolveResult, wanted: String) -> Bool {
  result
  |> result_items
  |> list.any(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _) = item
    id == wanted
  })
}

fn has_title_fragment(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _) = item
    string.contains(title, wanted)
  })
}

fn missing_fragments_from_items(
  fragments: List(String),
  primary_items: List(core.UnifiedItem),
  fallback_items: List(core.UnifiedItem),
) -> List(String) {
  list.filter(fragments, fn(fragment) {
    !has_title_fragment(primary_items, fragment)
    && !has_title_fragment(fallback_items, fragment)
  })
}

fn format_fragments(fragments: List(String)) -> String {
  case fragments {
    [] -> "(none)"
    _ -> string.join(fragments, ", ")
  }
}

fn clamp_int(value: Int, low: Int, high: Int) -> Int {
  case value < low {
    True -> low
    False ->
      case value > high {
        True -> high
        False -> value
      }
  }
}
