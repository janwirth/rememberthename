//// Core fetch API — `fetch` and `fetch_and_save_json` only.
////
//// Orchestration (selector resolution, source looping, validation, timings)
//// lives in `cli/fetch_orchestration`.

import adapters/api_keys
import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import cli/export_json
import cli/resolve_adapter
import cli/track_view
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import output/visual_output
import simplifile
import source_root

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

/// Default item cap — no `SourceAssertSpec.source_limit` on the fetch path.
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
      let source_root.SourceTimingSpec(max_conc, rps) = timing
      let qp =
        resolve_adapter.queue_policy_for_cache_mode(cache_mode, max_conc, rps)
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

    source_root.SoundcloudRoot(entry_point, depth, timing) -> {
      let source_root.SourceTimingSpec(max_conc, rps) = timing
      let qp =
        resolve_adapter.queue_policy_for_cache_mode(cache_mode, max_conc, rps)
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
      let qp = resolve_adapter.queue_policy_for_cache_mode(cache_mode, 3, 3)
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
      let qp = resolve_adapter.queue_policy_for_cache_mode(cache_mode, 3, 3)
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
        Error(e) -> Error(api_keys.format_resolve_adapter_error(e))
      }
    }

    source_root.TunaRoot -> {
      let tuna_normalized_source.ResolveWithMetadataResult(
        resolve_result,
        export_metadata,
      ) =
        tuna_normalized_source.resolve_with_metadata(
          core.All,
          cache_mode,
          on_update,
        )
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
  let FetchResult(items, lists, _unresolved, tuna_metadata) = fetch_result
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
    export_json.fetch_result_json(tracks, imported_dates, !is_tuna, lists)
  let path = source_root.artifact_json_path(root)
  case simplifile.write(content, to: path) {
    Ok(_) -> Ok(path)
    Error(e) -> Error("Write failed: " <> simplifile.describe_error(e))
  }
}

/// Convert a `FetchResult` to `TrackView` list using the given adapter label.
pub fn fetch_result_to_tracks(
  fetch_result: FetchResult,
  adapter_id: String,
) -> #(List(visual_output.TrackView), dict.Dict(String, Int)) {
  let FetchResult(items, _lists, _unresolved, tuna_metadata) = fetch_result
  case tuna_metadata {
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
}
