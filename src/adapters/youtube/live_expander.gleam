//// YouTube live adapter (YouTube Data API v3 via `gleetube`).
////
//// Entry contract:
//// - `YoutubePlaylistProfile` is opaque.
//// - Callers construct roots only via `youtube_playlist(playlist_url)`.
////
//// Accepted root input:
//// - playlist URLs (`list=...`); playlist id is parsed from the `list=` query parameter.
////
//// Resolution uses `adapters/youtube/data_api` and requires `ApiKeys.google_cloud`.

import adapters/api_keys
import adapters/cache
import adapters/core
import adapters/youtube/data_api
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub opaque type YoutubePlaylistProfile {
  YoutubePlaylistProfile(playlist_url: String)
}

pub fn youtube_playlist(playlist_url: String) -> YoutubePlaylistProfile {
  YoutubePlaylistProfile(playlist_url: playlist_url)
}

pub fn resolve_profile(
  profile: YoutubePlaylistProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  keys: api_keys.ApiKeys,
) -> Result(core.ResolveResult, api_keys.ResolveAdapterError) {
  resolve_profile_with_debug(profile, depth, cache_mode, keys, fn(_) { Nil })
}

pub fn resolve_profile_with_debug(
  profile: YoutubePlaylistProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  keys: api_keys.ApiKeys,
  on_debug: fn(String) -> Nil,
) -> Result(core.ResolveResult, api_keys.ResolveAdapterError) {
  resolve_profile_with_debug_limited(
    profile,
    depth,
    cache_mode,
    keys,
    0,
    on_debug,
  )
}

pub fn resolve_profile_with_debug_limited(
  profile: YoutubePlaylistProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  keys: api_keys.ApiKeys,
  max_items: Int,
  on_debug: fn(String) -> Nil,
) -> Result(core.ResolveResult, api_keys.ResolveAdapterError) {
  resolve_profile_with_debug_limited_timed(
    profile,
    depth,
    cache_mode,
    keys,
    max_items,
    core.default_queue_policy(),
    on_debug,
    fn(_) { Nil },
  )
}

pub fn resolve_profile_with_debug_limited_timed(
  profile: YoutubePlaylistProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  keys: api_keys.ApiKeys,
  max_items: Int,
  queue_policy: core.QueuePolicy,
  on_debug: fn(String) -> Nil,
  on_progress: fn(core.ResolveProgress) -> Nil,
) -> Result(core.ResolveResult, api_keys.ResolveAdapterError) {
  let YoutubePlaylistProfile(profile_url) = profile
  let _ = cache_mode
  let _ = queue_policy
  use api_key <- result.try(api_keys.require_youtube_data_api_key(keys))
  let playlist_id = parse_playlist_id(profile_url)
  case playlist_id == "" {
    True ->
      Ok(
        core.ResolveResult(
          items: [],
          lists: [],
          unresolved: [core.ProfileEntry(profile_url)],
        ),
      )
    False -> {
      use pair <- result.try(
        case data_api.fetch_playlist_unified(api_key, playlist_id) {
          Ok(p) -> Ok(p)
          Error(ge) ->
            Error(
              api_keys.YoutubeDataApi(data_api.glee_tube_error_message(ge)),
            )
        },
      )
      let #(all_items, title_raw) = pair
      let visible = apply_depth_and_item_limit(all_items, depth, max_items)
      let title = default_if_empty(string.trim(title_raw), "YouTube Playlist")
      let lists = [make_collection(playlist_id, title, visible)]
      emit_youtube_progress(profile_url, visible, lists, on_progress)
      let _ = on_debug
      Ok(core.ResolveResult(
        items: visible,
        lists: lists,
        unresolved: [],
      ))
    }
  }
}

const youtube_depth_batch_size: Int = 500

/// Shallow depth modes return the first N×500 items (playlist order from the API); `All` returns the full list (then `max_items` applies).
fn depth_visible_cap(depth: core.DepthMode) -> Int {
  case depth {
    core.Depth1 -> 1 * youtube_depth_batch_size
    core.Depth2 -> 2 * youtube_depth_batch_size
    core.Depth3 -> 3 * youtube_depth_batch_size
    core.Depth10 -> 10 * youtube_depth_batch_size
    core.Depth20 -> 20 * youtube_depth_batch_size
    core.All -> 9_999_999
  }
}

fn apply_depth_and_item_limit(
  items: List(core.UnifiedItem),
  depth: core.DepthMode,
  max_items: Int,
) -> List(core.UnifiedItem) {
  let cap = int.min(depth_visible_cap(depth), list.length(items))
  let after_depth = list.take(items, cap)
  case max_items > 0 {
    True -> list.take(after_depth, max_items)
    False -> after_depth
  }
}

fn emit_youtube_progress(
  profile_url: String,
  items: List(core.UnifiedItem),
  lists: List(core.UnifiedCollection),
  on_progress: fn(core.ResolveProgress) -> Nil,
) {
  on_progress(core.ResolveProgress(
    label: core.progress_label(core.ProfileEntry(profile_url)),
    level: 0,
    items_total: list.length(items),
    lists_total: list.length(lists),
    step_items: list.length(items),
    step_lists: list.length(lists),
    cache_hits: 0,
    cache_fetches: 1,
  ))
}

fn make_collection(
  playlist_id: String,
  title: String,
  items: List(core.UnifiedItem),
) -> core.UnifiedCollection {
  let track_ids =
    list.map(items, fn(item) {
      let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _) = item
      id
    })
  let source_id = "youtube:collection:" <> playlist_id
  core.UnifiedCollection(
    id: source_id,
    title: title,
    track_ids: track_ids,
    list_ids: [],
    service: "youtube",
    source_type: "collection",
    source_id: source_id,
  )
}

fn parse_playlist_id(url: String) -> String {
  case string.contains(url, "list=") {
    True -> {
      let parts = string.split(url, "list=")
      case parts {
        [_, rest, ..] -> {
          case string.split_once(rest, "&") {
            Ok(#(first, _)) -> first
            Error(_) -> string.trim(rest)
          }
        }
        _ -> ""
      }
    }
    False -> ""
  }
}

fn default_if_empty(value: String, fallback: String) -> String {
  case value == "" {
    True -> fallback
    False -> value
  }
}
