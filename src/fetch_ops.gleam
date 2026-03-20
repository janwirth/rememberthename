import adapters/cache
import adapters/core
import adapters/tuna/normalized_source as tuna_normalized_source
import cli/export_json
import cli/fetch_validation
import cli/resolve_adapter
import cli/runtime
import cli/source_selector as source_pick
import cli/terminal
import cli/track_view
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import output/visual_output
import simplifile
import source_specs

/// Library entry: fetch one configured source by selector (`"1"`, `"spotify"`, `"spotify-2"`, …), or `"all"` for merged canonical export.
pub fn fetch_with_cache_mode(
  selector: String,
  cache_mode: cache.CacheMode,
) -> Result(Nil, String) {
  case selector == "all" {
    True -> {
      fetch_all_sources(cache_mode)
      Ok(Nil)
    }
    False ->
      case source_pick.source_by_selector(source_specs.all(), selector) {
        Error(_) -> Error("Invalid source selector: " <> selector)
        Ok(#(source_index, source)) -> {
          let _ =
            run_fetch(source, source_index, core.All, "full", cache_mode, True)
          Ok(Nil)
        }
      }
  }
}

/// Merge every configured source into `output/all_items_latest.json`.
pub fn fetch_all_sources(cache_mode: cache.CacheMode) {
  io.println(terminal.color("Fetching all sources...", terminal.ansi_bright_cyan()))
  let #(all_tracks, all_imported_dates) =
    fetch_all_sources_loop(source_specs.all(), 1, cache_mode)
  let canonical_start_ms = runtime.now_ms()
  let canonical_content =
    export_json.tracks_json_with_imported_dates(
      all_tracks,
      all_imported_dates,
      True,
    )
  let canonical_path = export_json.artifact_path("all_items_latest.json")
  let _ = simplifile.write(canonical_content, to: canonical_path)
  let canonical_elapsed_ms = runtime.now_ms() - canonical_start_ms
  io.println("")
  io.println(
    terminal.color("Canonical JSON written: ", terminal.ansi_green()) <> canonical_path,
  )
  io.println(
    terminal.color("Canonical info: ", terminal.ansi_yellow())
    <> "items="
    <> int.to_string(list.length(all_tracks))
    <> " files="
    <> int.to_string(export_json.count_tracks_with_file(all_tracks))
    <> " duration="
    <> int.to_string(canonical_elapsed_ms)
    <> "ms",
  )
}

fn fetch_all_sources_loop(
  sources: List(source_specs.SourceSpec),
  index: Int,
  cache_mode: cache.CacheMode,
) -> #(List(visual_output.TrackView), dict.Dict(String, Int)) {
  case sources {
    [] -> #([], dict.new())
    [source, ..rest] -> {
      let #(tracks, imported_dates) =
        run_fetch(source, index, core.All, "full", cache_mode, True)
      io.println("")
      let #(rest_tracks, rest_imported_dates) =
        fetch_all_sources_loop(rest, index + 1, cache_mode)
      #(
        list.append(tracks, rest_tracks),
        fetch_validation.merge_imported_dates(
          imported_dates,
          tracks,
          rest_imported_dates,
        ),
      )
    }
  }
}

/// Resolve, export per-source JSON, validation, timings.
pub fn run_fetch(
  source: source_specs.SourceSpec,
  source_index: Int,
  depth: core.DepthMode,
  depth_label: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
) -> #(List(visual_output.TrackView), dict.Dict(String, Int)) {
  let run_start_ms = runtime.now_ms()
  let source_specs.SourceSpec(key, name, entry_point, timing_spec, assert_spec) =
    source
  let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
  io.println(
    terminal.color(
      "Fetching source " <> int.to_string(source_index) <> ": " <> name,
      terminal.ansi_bright_cyan(),
    ),
  )
  io.println(
    terminal.color("Depth: ", terminal.ansi_yellow()) <> depth_label,
  )
  io.println(
    terminal.color("Cache: ", terminal.ansi_yellow())
    <> resolve_adapter.cache_mode_text(cache_mode),
  )
  io.println("")

  let resolve_start_ms = runtime.now_ms()
  let #(result, tuna_export_metadata) = case key == "tuna" {
    True -> {
      let tuna_normalized_source.ResolveWithMetadataResult(
        resolve_result,
        export_metadata,
      ) =
        tuna_normalized_source.resolve_with_metadata(depth, cache_mode, fn(line) {
          io.println(line)
        })
      #(resolve_result, Some(export_metadata))
    }
    False ->
      #(
        resolve_adapter.resolve_source(
          key,
          entry_point,
          depth,
          source_limit,
          timing_spec,
          cache_mode,
          fn(_line) { Nil },
          fn(progress) {
            io.println(core.format_resolve_progress_line(progress))
          },
        ),
        None,
      )
  }
  let resolve_elapsed_ms = runtime.now_ms() - resolve_start_ms

  let core.ResolveResult(items, lists, unresolved) = result
  let adapter_id = track_view.adapter_id_for_source(key, entry_point)
  let #(tracks, imported_dates) = case tuna_export_metadata {
    Some(metadata_index) -> {
      let tracks = list.map(items, fn(item) {
        track_view.to_tuna_track_view(item, adapter_id, metadata_index)
      })
      #(tracks, track_view.imported_dates_for_items(items, metadata_index))
    }
    None -> #(
      list.map(items, fn(item) { track_view.to_track_view(item, adapter_id) }),
      dict.new(),
    )
  }
  let files_count = export_json.count_tracks_with_file(tracks)
  io.println("")
  io.println(
    terminal.color("Done.", terminal.ansi_green())
    <> " items="
    <> int.to_string(list.length(items))
    <> " lists="
    <> int.to_string(list.length(lists))
    <> " unresolved="
    <> int.to_string(list.length(unresolved))
    <> " files="
    <> int.to_string(files_count),
  )
  let content =
    export_json.tracks_json_with_imported_dates(
      tracks,
      imported_dates,
      key != "tuna",
    )
  let json_path =
    export_json.artifact_path(
      "cli_result_"
      <> key
      <> "_depth_"
      <> track_view.sanitize_depth_label(depth_label)
      <> ".json",
    )
  let export_start_ms = runtime.now_ms()
  let _ = simplifile.write(content, to: json_path)
  let export_elapsed_ms = runtime.now_ms() - export_start_ms
  io.println(
    terminal.color("JSON written: ", terminal.ansi_green()) <> json_path,
  )
  io.println(
    terminal.color("Export duration: ", terminal.ansi_yellow())
    <> int.to_string(export_elapsed_ms)
    <> "ms",
  )
  let validation_start_ms = runtime.now_ms()
  fetch_validation.print_runtime_validation(
    source,
    depth,
    cache_mode,
    result,
    always_validate,
  )
  let validation_elapsed_ms = runtime.now_ms() - validation_start_ms
  let total_elapsed_ms = runtime.now_ms() - run_start_ms
  io.println(
    terminal.color("Resolve duration: ", terminal.ansi_yellow())
    <> int.to_string(resolve_elapsed_ms)
    <> "ms",
  )
  io.println(
    terminal.color("Validation duration: ", terminal.ansi_yellow())
    <> int.to_string(validation_elapsed_ms)
    <> "ms",
  )
  io.println(
    terminal.color("Total duration: ", terminal.ansi_yellow())
    <> int.to_string(total_elapsed_ms)
    <> "ms",
  )
  #(tracks, imported_dates)
}
