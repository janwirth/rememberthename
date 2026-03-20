import adapters/cache.{type CacheMode}
import cli/export_json
import cli/fetch
import cli/runtime
import cli/terminal
import cli/tuna_perf
import cli/tuna_tags
import gleam/option.{type Option}
import output/visual_output.{type TrackView}

/// CLI entry: normalizes argv and delegates to `run`.
pub fn main() {
  run(normalize_args(runtime.argv()))
}

/// Routes arguments: no args → easy start; `fetch` → fetch flow; otherwise usage.
pub fn run(args: List(String)) {
  case args {
    [] -> terminal.show_easy_start()
    ["fetch", source_selector, ..rest] ->
      fetch.fetch_source_simple(source_selector, rest)
    _ -> terminal.print_usage()
  }
  terminal.print_exit_signal()
}

/// Drops a leading `cli` token when the program is invoked as `cli ...`.
fn normalize_args(args: List(String)) -> List(String) {
  case args {
    ["cli", ..rest] -> rest
    _ -> args
  }
}

// --- Public API re-exports for tests and library callers ---

pub fn normalize_tuna_metadata_source_id(
  service: String,
  source_id: String,
) -> String {
  tuna_tags.normalize_tuna_metadata_source_id(service, source_id)
}

pub fn normalize_tuna_tags(tags: List(String), rating: Int) -> String {
  tuna_tags.normalize_tuna_tags(tags, rating)
}

pub fn format_tuna_source_id(service: String, source_id: String) -> String {
  tuna_tags.format_tuna_source_id(service, source_id)
}

pub fn export_tags(tags: String) -> List(String) {
  tuna_tags.export_tags(tags)
}

pub fn nullable_file_path(path: String) -> Option(String) {
  export_json.nullable_file_path(path)
}

pub fn tracks_json(tracks: List(TrackView)) -> String {
  export_json.tracks_json(tracks)
}

pub fn tuna_export_duration_ms(cache_mode: CacheMode) -> Int {
  tuna_perf.tuna_export_duration_ms(cache_mode)
}
