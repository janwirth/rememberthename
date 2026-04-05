import adapters/api_keys
import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import cli/api_credentials
import cli/export_json
import cli/fetch_validation
import cli/resolve_adapter
import cli/runtime
import cli/source_selector as source_pick
import cli/terminal
import cli/track_view
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import output/visual_output
import simplifile
import source_root
import source_specs

/// Resolved data from a single `fetch` call.
pub type FetchResult {
  FetchResult(
    items: List(core.UnifiedItem),
    lists: List(core.UnifiedCollection),
    unresolved: List(core.AdapterNode),
    tuna_metadata: option.Option(
      dict.Dict(String, tuna_normalized_source.ExportMetadata),
    ),
  )
}

/// Default item cap used by `fetch` — no `SourceAssertSpec.source_limit` on the fetch path.
const fetch_max_items = 200_000

/// Resolve a source described by `SourceRoot` and return raw items + lists.
///
/// No JSON write, no validation — those are the caller's responsibility.
/// Progress strings are adapter-specific; do not parse them.
pub fn fetch(
  root: source_root.SourceRoot,
  cache_mode: cache.CacheMode,
  on_update: fn(String) -> Nil,
) -> Result(FetchResult, String) {
  case root {
    source_root.BandcampRoot(profile_url, depth, timing) -> {
      let source_specs.SourceTimingSpec(max_conc, rps) = timing
      let qp = resolve_adapter.queue_policy_for_cache_mode(cache_mode, max_conc, rps)
      let profile = bandcamp_live_expander.bandcamp_profile(profile_url)
      let result =
        bandcamp_live_expander.resolve_profile_with_debug_limited_timed(
          profile,
          depth,
          cache_mode,
          fetch_max_items,
          qp,
          fn(_) { Nil },
          fn(p) { on_update(core.format_resolve_progress_line(p)) },
        )
      let core.ResolveResult(items, lists, unresolved) = result
      Ok(FetchResult(items, lists, unresolved, None))
    }

    source_root.SoundcloudRoot(entry_point, depth) -> {
      let qp =
        resolve_adapter.queue_policy_for_cache_mode(cache_mode, 3, 3)
      let profile = soundcloud_live_expander.soundcloud_profile(entry_point)
      let result =
        soundcloud_live_expander.resolve_profile_with_debug_limited_timed(
          profile,
          depth,
          cache_mode,
          fetch_max_items,
          qp,
          fn(_) { Nil },
          fn(p) { on_update(core.format_resolve_progress_line(p)) },
        )
      let core.ResolveResult(items, lists, unresolved) = result
      Ok(FetchResult(items, lists, unresolved, None))
    }

    source_root.SpotifyRoot(credentials, depth) -> {
      let qp =
        resolve_adapter.queue_policy_for_cache_mode(cache_mode, 3, 3)
      let config = spotify_live_expander.spotify_config(credentials)
      let profile =
        spotify_live_expander.spotify_user(
          "https://open.spotify.com/user/liked",
        )
      let result =
        spotify_live_expander.resolve_profile_with_debug_limited_timed(
          profile,
          depth,
          config,
          cache_mode,
          fetch_max_items,
          qp,
          fn(_) { Nil },
          fn(p) { on_update(core.format_resolve_progress_line(p)) },
        )
      let core.ResolveResult(items, lists, unresolved) = result
      Ok(FetchResult(items, lists, unresolved, None))
    }

    source_root.YoutubeRoot(playlist_url, api_key) -> {
      let qp =
        resolve_adapter.queue_policy_for_cache_mode(cache_mode, 3, 3)
      let keys = api_keys.ApiKeys(spotify: None, google_cloud: Some(api_key))
      let profile = youtube_live_expander.youtube_playlist(playlist_url)
      case
        youtube_live_expander.resolve_profile_with_debug_limited_timed(
          profile,
          core.All,
          cache_mode,
          keys,
          fetch_max_items,
          qp,
          fn(_) { Nil },
          fn(p) { on_update(core.format_resolve_progress_line(p)) },
        )
      {
        Ok(result) -> {
          let core.ResolveResult(items, lists, unresolved) = result
          Ok(FetchResult(items, lists, unresolved, None))
        }
        Error(e) ->
          Error(api_keys.format_resolve_adapter_error(e))
      }
    }

    source_root.TunaRoot -> {
      let tuna_normalized_source.ResolveWithMetadataResult(
        resolve_result,
        export_metadata,
      ) = tuna_normalized_source.resolve_with_metadata(core.All, cache_mode, on_update)
      let core.ResolveResult(items, lists, unresolved) = resolve_result
      Ok(FetchResult(items, lists, unresolved, Some(export_metadata)))
    }
  }
}

/// Resolve a source and write JSON to `output/<key>_full.json`.
///
/// Path is derived solely from `SourceRoot` — no legacy `cli_result_*` names.
/// No validation is run; dev tools read the written file separately.
pub fn fetch_and_save_json(
  root: source_root.SourceRoot,
  cache_mode: cache.CacheMode,
) -> Result(String, String) {
  use fetch_result <- result.try(fetch(root, cache_mode, fn(_) { Nil }))
  let FetchResult(items, _lists, _unresolved, tuna_metadata) = fetch_result
  let adapter_id = source_root.adapter_id(root)
  let is_tuna = case root {
    source_root.TunaRoot -> True
    _ -> False
  }
  let #(tracks, imported_dates) = case tuna_metadata {
    Some(metadata_index) -> {
      let ts =
        list.map(items, fn(item) {
          track_view.to_tuna_track_view(item, adapter_id, metadata_index)
        })
      #(ts, track_view.imported_dates_for_items(items, metadata_index))
    }
    None -> #(
      list.map(items, fn(item) { track_view.to_track_view(item, adapter_id) }),
      dict.new(),
    )
  }
  let content =
    export_json.tracks_json_with_imported_dates(
      tracks,
      imported_dates,
      !is_tuna,
    )
  let path = source_root.artifact_json_path(root)
  case simplifile.write(content, to: path) {
    Ok(_) -> Ok(path)
    Error(e) -> Error("Write failed: " <> simplifile.describe_error(e))
  }
}

/// Library entry: fetch one configured source by selector (`"1"`, `"spotify"`, `"spotify-2"`, …), or `"all"` for merged canonical export.
pub fn fetch_with_cache_mode(
  selector: String,
  cache_mode: cache.CacheMode,
  on_update: fn(String) -> Nil,
) -> Result(Nil, String) {
  case selector == "all" {
    True -> {
      fetch_all_sources(cache_mode, on_update)
      Ok(Nil)
    }
    False ->
      case source_pick.source_by_selector(source_specs.all(), selector) {
        Error(_) -> Error("Invalid source selector: " <> selector)
        Ok(#(source_index, source)) -> {
          let _ =
            run_fetch(
              source,
              source_index,
              core.All,
              "full",
              cache_mode,
              True,
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
  on_update: fn(String) -> Nil,
) {
  on_update(
    terminal.color("Fetching all sources...", terminal.ansi_bright_cyan()),
  )
  let #(all_tracks, all_imported_dates) =
    fetch_all_sources_loop(source_specs.all(), 1, cache_mode, on_update)
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
    terminal.color("Canonical JSON written: ", terminal.ansi_green()) <> canonical_path,
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
  sources: List(source_specs.SourceSpec),
  index: Int,
  cache_mode: cache.CacheMode,
  on_update: fn(String) -> Nil,
) -> #(List(visual_output.TrackView), dict.Dict(String, Int)) {
  case sources {
    [] -> #([], dict.new())
    [source, ..rest] -> {
      let #(tracks, imported_dates) =
        run_fetch(
          source,
          index,
          core.All,
          "full",
          cache_mode,
          True,
          True,
          on_update,
        )
      on_update("")
      let #(rest_tracks, rest_imported_dates) =
        fetch_all_sources_loop(rest, index + 1, cache_mode, on_update)
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

/// Resolve one source and return tracks without writing `output/cli_result_*.json`.
pub fn fetch_source_tracks(
  selector: String,
  cache_mode: cache.CacheMode,
  write_json_artifact: Bool,
  on_update: fn(String) -> Nil,
) -> Result(List(visual_output.TrackView), String) {
  fetch_source_tracks_with_depth(
    selector,
    core.All,
    "full",
    cache_mode,
    write_json_artifact,
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
  on_update: fn(String) -> Nil,
) -> Result(List(visual_output.TrackView), String) {
  case selector == "all" {
    True -> Error("use fetch_all for all sources")
    False ->
      case source_pick.source_by_selector(source_specs.all(), selector) {
        Error(_) -> Error("Invalid source selector: " <> selector)
        Ok(#(source_index, source)) -> {
          let #(tracks, _) =
            run_fetch(
              source,
              source_index,
              depth,
              depth_label,
              cache_mode,
              True,
              write_json_artifact,
              on_update,
            )
          Ok(tracks)
        }
      }
  }
}

/// Resolve, export per-source JSON (optional), validation, timings.
pub fn run_fetch(
  source: source_specs.SourceSpec,
  source_index: Int,
  depth: core.DepthMode,
  depth_label: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  write_json_artifact: Bool,
  on_update: fn(String) -> Nil,
) -> #(List(visual_output.TrackView), dict.Dict(String, Int)) {
  let run_start_ms = runtime.now_ms()
  let source_specs.SourceSpec(key, name, entry_point, _, _) = source
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
  on_update("")

  let resolve_start_ms = runtime.now_ms()
  let keys = api_credentials.load_full_api_keys()
  let root = case source_root.from_legacy_spec(source, depth, keys) {
    Ok(r) -> r
    Error(err) -> {
      on_update(
        terminal.color("Credential error: ", terminal.ansi_red())
        <> api_keys.format_resolve_adapter_error(err),
      )
      source_root.TunaRoot
      // unreachable paths fall through to empty result below
    }
  }
  let fetch_result = case fetch(root, cache_mode, on_update) {
    Ok(r) -> r
    Error(err) -> {
      on_update(terminal.color("Resolve error: ", terminal.ansi_red()) <> err)
      FetchResult(items: [], lists: [], unresolved: [], tuna_metadata: None)
    }
  }
  let resolve_elapsed_ms = runtime.now_ms() - resolve_start_ms

  let FetchResult(items, lists, unresolved, tuna_metadata) = fetch_result
  let adapter_id = track_view.adapter_id_for_source(key, entry_point)
  let #(tracks, imported_dates) = case tuna_metadata {
    Some(metadata_index) -> {
      let tracks =
        list.map(items, fn(item) {
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
  on_update("")
  on_update(
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
  case write_json_artifact {
    True -> {
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
      on_update(terminal.color("JSON written: ", terminal.ansi_green()) <> json_path)
      on_update(
        terminal.color("Export duration: ", terminal.ansi_yellow())
        <> int.to_string(export_elapsed_ms)
        <> "ms",
      )
    }
    False -> Nil
  }
  let validation_start_ms = runtime.now_ms()
  let resolve_result =
    core.ResolveResult(items: items, lists: lists, unresolved: unresolved)
  fetch_validation.print_runtime_validation(
    source,
    depth,
    cache_mode,
    resolve_result,
    always_validate,
    on_update,
    keys,
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
