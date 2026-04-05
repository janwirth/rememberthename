//// Fetch orchestration: selector resolution, source looping, validation, timing.
////
//// This module owns the glue between the source registry and `fetch_ops.fetch`.
//// `fetch_ops` itself exports only `fetch` / `fetch_and_save_json` plus types.
////
//// `SourceSpec` is not imported here — selection and dispatch go through
//// `source_root.ordered_registry_list` + `source_selector.triple_by_selector`.

import adapters/cache
import adapters/core
import cli/api_credentials
import cli/export_json
import cli/fetch_validation
import cli/resolve_adapter
import cli/runtime
import cli/source_selector as source_pick
import cli/terminal
import fetch_ops
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import output/visual_output
import simplifile
import source_root
import source_specs

/// Fetch one source by selector, or all sources when selector is `"all"`.
pub fn fetch_with_cache_mode(
  selector: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) -> Result(Nil, String) {
  let keys = api_credentials.load_full_api_keys()
  let ordered = source_root.ordered_registry_list(keys)
  case selector == "all" {
    True -> {
      fetch_all_sources_with_ordered(ordered, cache_mode, always_validate, on_update)
      Ok(Nil)
    }
    False ->
      case source_pick.triple_by_selector(ordered, selector) {
        Error(_) -> Error("Invalid source selector: " <> selector)
        Ok(#(source_index, key, root, assert_spec)) -> {
          let _ =
            run_fetch(
              key,
              source_index,
              root,
              assert_spec,
              core.All,
              "full",
              cache_mode,
              always_validate,
              True,
              on_update,
            )
          Ok(Nil)
        }
      }
  }
}

/// Merge every configured source into `output/all_items_latest.json`.
pub fn fetch_all_sources(
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) {
  let keys = api_credentials.load_full_api_keys()
  let ordered = source_root.ordered_registry_list(keys)
  fetch_all_sources_with_ordered(ordered, cache_mode, always_validate, on_update)
}

fn fetch_all_sources_with_ordered(
  ordered: List(#(String, source_root.SourceRoot, source_specs.SourceAssertSpec)),
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) {
  on_update(
    terminal.color("Fetching all sources...", terminal.ansi_bright_cyan()),
  )
  let #(all_tracks, all_imported_dates) =
    fetch_all_sources_loop(ordered, 1, cache_mode, always_validate, on_update)
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
  on_update("")
  on_update(
    terminal.color("Canonical JSON written: ", terminal.ansi_green())
    <> canonical_path,
  )
  on_update(
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
  ordered: List(#(String, source_root.SourceRoot, source_specs.SourceAssertSpec)),
  index: Int,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) -> #(List(visual_output.TrackView), dict.Dict(String, Int)) {
  case ordered {
    [] -> #([], dict.new())
    [#(key, root, assert_spec), ..rest] -> {
      let #(tracks, imported_dates) =
        run_fetch(
          key,
          index,
          root,
          assert_spec,
          core.All,
          "full",
          cache_mode,
          always_validate,
          True,
          on_update,
        )
      on_update("")
      let #(rest_tracks, rest_imported_dates) =
        fetch_all_sources_loop(
          rest,
          index + 1,
          cache_mode,
          always_validate,
          on_update,
        )
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

/// Resolve one source and return tracks without writing JSON.
pub fn fetch_source_tracks(
  selector: String,
  cache_mode: cache.CacheMode,
  write_json_artifact: Bool,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) -> Result(List(visual_output.TrackView), String) {
  fetch_source_tracks_with_depth(
    selector,
    core.All,
    "full",
    cache_mode,
    write_json_artifact,
    always_validate,
    on_update,
  )
}

/// Resolve one source and return tracks with explicit depth control.
pub fn fetch_source_tracks_with_depth(
  selector: String,
  depth: core.DepthMode,
  depth_label: String,
  cache_mode: cache.CacheMode,
  write_json_artifact: Bool,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) -> Result(List(visual_output.TrackView), String) {
  case selector == "all" {
    True -> Error("use fetch_all for all sources")
    False -> {
      let keys = api_credentials.load_full_api_keys()
      let ordered = source_root.ordered_registry_list(keys)
      case source_pick.triple_by_selector(ordered, selector) {
        Error(_) -> Error("Invalid source selector: " <> selector)
        Ok(#(source_index, key, base_root, assert_spec)) -> {
          let root = source_root.with_depth(base_root, depth)
          let #(tracks, _) =
            run_fetch(
              key,
              source_index,
              root,
              assert_spec,
              depth,
              depth_label,
              cache_mode,
              always_validate,
              write_json_artifact,
              on_update,
            )
          Ok(tracks)
        }
      }
    }
  }
}

/// Resolve, export per-source JSON (optional), validation, timings.
///
/// `root` already encodes depth — callers use `source_root.with_depth` to override.
/// `depth` is passed separately for the validation strategy decision.
pub fn run_fetch(
  key: String,
  source_index: Int,
  root: source_root.SourceRoot,
  assert_spec: source_specs.SourceAssertSpec,
  depth: core.DepthMode,
  depth_label: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  write_json_artifact: Bool,
  on_update: fn(String) -> Nil,
) -> #(List(visual_output.TrackView), dict.Dict(String, Int)) {
  let run_start_ms = runtime.now_ms()
  let name = source_root.display_name(root)
  on_update(
    terminal.color(
      "Fetching source " <> int.to_string(source_index) <> ": " <> name,
      terminal.ansi_bright_cyan(),
    ),
  )
  on_update(terminal.color("Depth: ", terminal.ansi_yellow()) <> depth_label)
  on_update(
    terminal.color("Cache: ", terminal.ansi_yellow())
    <> resolve_adapter.cache_mode_text(cache_mode),
  )
  let will_validate = fetch_validation.validation_will_run(always_validate)
  on_update(
    terminal.color("Validation: ", terminal.ansi_yellow())
    <> case will_validate {
      True ->
        "will run — "
        <> fetch_validation.validation_plan_label(depth)
        <> " (enabled)"
      False -> "skipped — enable with --validate"
    },
  )
  on_update("")

  let resolve_start_ms = runtime.now_ms()
  let fetch_result = case fetch_ops.fetch(root, cache_mode, on_update) {
    Ok(r) -> r
    Error(err) -> {
      on_update(terminal.color("Resolve error: ", terminal.ansi_red()) <> err)
      fetch_ops.FetchResult(
        items: [],
        lists: [],
        unresolved: [],
        tuna_metadata: None,
      )
    }
  }
  let resolve_elapsed_ms = runtime.now_ms() - resolve_start_ms

  let adapter_id = source_root.adapter_id(root)
  let fetch_ops.FetchResult(items, lists, unresolved, ..) = fetch_result
  let #(tracks, imported_dates) =
    fetch_ops.fetch_result_to_tracks(fetch_result, adapter_id)
  let files_count = export_json.count_tracks_with_file(tracks)
  on_update("")
  on_update(
    terminal.color("Fetch completed.", terminal.ansi_green())
    <> " "
    <> int.to_string(resolve_elapsed_ms)
    <> "ms",
  )
  on_update(
    terminal.color("Result: ", terminal.ansi_green())
    <> "items="
    <> int.to_string(list.length(items))
    <> " lists="
    <> int.to_string(list.length(lists))
    <> " unresolved="
    <> int.to_string(list.length(unresolved))
    <> " files="
    <> int.to_string(files_count),
  )
  case write_json_artifact {
    True -> {
      let is_tuna = case root {
        source_root.TunaRoot -> True
        _ -> False
      }
      let content =
        export_json.fetch_result_json(tracks, imported_dates, !is_tuna, lists)
      let json_path = source_root.artifact_json_path(root)
      let export_start_ms = runtime.now_ms()
      let _ = simplifile.write(content, to: json_path)
      let export_elapsed_ms = runtime.now_ms() - export_start_ms
      on_update(
        terminal.color("JSON written: ", terminal.ansi_green()) <> json_path,
      )
      on_update(
        terminal.color("Export duration: ", terminal.ansi_yellow())
        <> int.to_string(export_elapsed_ms)
        <> "ms",
      )
    }
    False -> Nil
  }
  case will_validate {
    True -> {
      on_update("")
      on_update(
        terminal.color("Validation starting.", terminal.ansi_bright_cyan()),
      )
      on_update(
        terminal.color("Validation params: ", terminal.ansi_yellow())
        <> fetch_validation.validation_params_detail(
          key,
          assert_spec,
          depth,
          cache_mode,
        ),
      )
    }
    False -> Nil
  }
  let validation_start_ms = runtime.now_ms()
  let resolve_result =
    core.ResolveResult(items: items, lists: lists, unresolved: unresolved)
  fetch_validation.print_runtime_validation(
    key,
    name,
    assert_spec,
    root,
    depth,
    cache_mode,
    resolve_result,
    always_validate,
    on_update,
  )
  let validation_elapsed_ms = runtime.now_ms() - validation_start_ms
  let total_elapsed_ms = runtime.now_ms() - run_start_ms
  on_update(
    terminal.color("Resolve duration: ", terminal.ansi_yellow())
    <> int.to_string(resolve_elapsed_ms)
    <> "ms",
  )
  on_update(
    terminal.color("Validation duration: ", terminal.ansi_yellow())
    <> int.to_string(validation_elapsed_ms)
    <> "ms",
  )
  on_update(
    terminal.color("Total duration: ", terminal.ansi_yellow())
    <> int.to_string(total_elapsed_ms)
    <> "ms",
  )
  #(tracks, imported_dates)
}
