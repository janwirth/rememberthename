import adapters/cache
import gleam/list
import gleam/option.{type Option, None, Some}
import source_specs

pub type SourceEntry {
  SourceEntry(
    key: String,
    name: String,
    entry_point: String,
    cache_mode: cache.CacheMode,
    timing_spec: source_specs.SourceTimingSpec,
    min_depth_1_items: Int,
    min_full_items: Int,
    first_items_to_preserve: Int,
    anchor_fragments: List(String),
  )
}

pub type View {
  RunAll(entered: Bool)
  Source(source: SourceEntry, entered: Bool)
  ToggleCache(entered: Bool)
  Exit(entered: Bool)
}

pub fn source_entries() -> List(SourceEntry) {
  list.append(list.map(source_specs.all(), source_entry_from_spec), [
    tuna_normalized_source(),
  ])
}

pub fn section_count() -> Int {
  list.length(source_entries())
}

pub fn menu_count() -> Int {
  section_count() + 3
}

pub fn previous_index(index: Int) -> Int {
  case index <= 0 {
    True -> menu_count() - 1
    False -> index - 1
  }
}

pub fn next_index(index: Int) -> Int {
  case index >= menu_count() - 1 {
    True -> 0
    False -> index + 1
  }
}

pub fn is_exit_selected(index: Int) -> Bool {
  index == section_count() + 2
}

pub fn is_toggle_cache_selected(index: Int) -> Bool {
  index == section_count() + 1
}

pub fn view_for_index(index: Int, entered: Bool) -> View {
  case index {
    0 -> RunAll(entered: entered)
    _ ->
      case is_toggle_cache_selected(index) {
        True -> ToggleCache(entered: entered)
        False ->
          case is_exit_selected(index) {
            True -> Exit(entered: entered)
            False ->
              case source_at(source_entries(), index - 1, 0) {
                Some(source) -> Source(source: source, entered: entered)
                None -> Exit(entered: entered)
              }
          }
      }
  }
}

pub fn title(view: View) -> String {
  case view {
    RunAll(_) -> "Run all sources"
    ToggleCache(_) -> "Toggle cache mode"
    Exit(_) -> "Exit"
    Source(source, _) -> source.name
  }
}

pub fn source_from_view(view: View) -> Option(SourceEntry) {
  case view {
    Source(source, _) -> Some(source)
    _ -> None
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

fn source_entry_from_spec(spec: source_specs.SourceSpec) -> SourceEntry {
  let source_specs.SourceSpec(key, name, entry_point, timing_spec, assert_spec) =
    spec
  let source_specs.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    _,
    first_items_to_preserve,
    anchor_fragments,
    _,
  ) = assert_spec
  SourceEntry(
    key: key,
    name: name,
    entry_point: entry_point,
    cache_mode: cache.CacheUpsert,
    timing_spec: timing_spec,
    min_depth_1_items: min_depth_1_items,
    min_full_items: min_full_items,
    first_items_to_preserve: first_items_to_preserve,
    anchor_fragments: anchor_fragments,
  )
}

fn tuna_normalized_source() -> SourceEntry {
  SourceEntry(
    key: "tuna_normalized",
    name: "Tuna Normalized IDs",
    entry_point: "gel:tuna/main::default::Track",
    cache_mode: cache.CacheUpsert,
    timing_spec: source_specs.SourceTimingSpec(
      max_concurrency: 1,
      requests_per_second: 1,
    ),
    min_depth_1_items: 1,
    min_full_items: 1,
    first_items_to_preserve: 1,
    anchor_fragments: [],
  )
}
