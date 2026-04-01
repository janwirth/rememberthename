//// YouTube live adapter.
////
//// Entry contract:
//// - `YoutubePlaylistProfile` is opaque.
//// - Callers construct roots only via `youtube_playlist(playlist_url)`.
//// - `resolve_profile` delegates traversal to `adapters/core`.
////
//// Accepted root input:
//// - playlist URLs (`list=...`)
//// - playlist id is parsed from the `list=` query parameter.
////
//// Traversal plan:
//// 1) Expand profile root: fetch first playlist surface from HTML.
//// 2) Expand page node: fetch continuation page from youtubei browse endpoint.
////
//// Depth semantics (YOUTUBE_SPEC section 5):
//// - Depth 1: first playlist surface.
//// - Depth 2: one additional continuation level.
//// - Deeper modes continue continuation-page traversal in order.

import adapters/api_keys
import adapters/cache
import adapters/core
import adapters/youtube/data_api
import gleam/int
import gleam/list
import gleam/result
import gleam/string

@external(erlang, "youtube_http", "playlist_first_tsv")
fn playlist_first_tsv(url: String) -> String

@external(erlang, "youtube_http", "playlist_first_next_token")
fn playlist_first_next_token(url: String) -> String

@external(erlang, "youtube_http", "playlist_api_key")
fn playlist_api_key(url: String) -> String

@external(erlang, "youtube_http", "playlist_client_version")
fn playlist_client_version(url: String) -> String

@external(erlang, "youtube_http", "playlist_title")
fn playlist_title(url: String) -> String

@external(erlang, "youtube_http", "continuation_tsv")
fn continuation_tsv(
  api_key: String,
  client_version: String,
  token: String,
) -> String

@external(erlang, "youtube_http", "continuation_next_token")
fn continuation_next_token(
  api_key: String,
  client_version: String,
  token: String,
) -> String

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

pub fn expand(
  node: core.AdapterNode,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url, cache_mode)
    core.PageNode(ctx) -> expand_page(ctx, cache_mode)
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

fn expand_profile(
  profile_url: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let playlist_id = parse_playlist_id(profile_url)
  case playlist_id == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
        cache_hits: 0,
        cache_fetches: 0,
      )
    False -> {
      let #(tsv_raw, c1) =
        cached_playlist_first_tsv(profile_url, cache_mode)
      let items = parse_tracks(tsv_raw)
      let #(title_raw, c2) =
        cached_playlist_title(profile_url, cache_mode)
      let title =
        default_if_empty(string.trim(title_raw), "YouTube Playlist")
      let #(api_key_raw, c3) =
        cached_playlist_api_key(profile_url, cache_mode)
      let api_key = string.trim(api_key_raw)
      let #(client_version_raw, c4) =
        cached_playlist_client_version(profile_url, cache_mode)
      let client_version = string.trim(client_version_raw)
      let #(token_raw, c5) =
        cached_playlist_first_next_token(profile_url, cache_mode)
      let token = string.trim(token_raw)
      let #(hits, fetches) =
        cache.merge_rollups(
          cache.merge_rollups(
            cache.merge_rollups(cache.merge_rollups(c1, c2), c3),
            c4,
          ),
          c5,
        )
      let next_nodes = case
        api_key != "" && client_version != "" && token != ""
      {
        True -> [
          core.PageNode(page_ctx(
            profile_url,
            playlist_id,
            api_key,
            client_version,
            token,
          )),
        ]
        False -> []
      }
      case items == [] {
        True ->
          core.ExpandResult(
            items: [],
            lists: [],
            next_nodes: [],
            unresolved: [core.ProfileEntry(profile_url)],
            cache_hits: hits,
            cache_fetches: fetches,
          )
        False ->
          core.ExpandResult(
            items: items,
            lists: [make_collection(playlist_id, title, items)],
            next_nodes: next_nodes,
            unresolved: [],
            cache_hits: hits,
            cache_fetches: fetches,
          )
      }
    }
  }
}

fn expand_page(ctx: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    [profile_url, playlist_id, api_key, client_version, token] -> {
      let #(tsv_body, c_tsv) =
        cached_continuation_tsv(
          api_key,
          client_version,
          token,
          cache_mode,
        )
      let items = parse_tracks(tsv_body)
      let #(next_raw, c_next) =
        cached_continuation_next_token(
          api_key,
          client_version,
          token,
          cache_mode,
        )
      let next_token = string.trim(next_raw)
      let #(hits, fetches) = cache.merge_rollups(c_tsv, c_next)
      let next_nodes = case next_token != "" {
        True -> [
          core.PageNode(page_ctx(
            profile_url,
            playlist_id,
            api_key,
            client_version,
            next_token,
          )),
        ]
        False -> []
      }
      core.ExpandResult(
        items: items,
        lists: [make_collection(playlist_id, "YouTube Playlist", items)],
        next_nodes: next_nodes,
        unresolved: [],
        cache_hits: hits,
        cache_fetches: fetches,
      )
    }
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.PageNode(ctx)],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

fn parse_tracks(raw: String) -> List(core.UnifiedItem) {
  let lines = parse_lines(raw)
  list.fold(lines, [], fn(acc, line) {
    let cols = string.split(line, "\t")
    case cols {
      [video_id, title, artist] ->
        case video_id == "" {
          True -> acc
          False ->
            case make_item(video_id, title, artist) {
              Ok(item) -> list.append(acc, [item])
              Error(_) -> acc
            }
        }
      [video_id, title] ->
        case video_id == "" {
          True -> acc
          False ->
            case make_item(video_id, title, "unknown") {
              Ok(item) -> list.append(acc, [item])
              Error(_) -> acc
            }
        }
      _ -> acc
    }
  })
}

fn make_item(
  video_id: String,
  title: String,
  artist: String,
) -> Result(core.UnifiedItem, Nil) {
  core.track_item(
    "youtube",
    video_id,
    normalize_text(title),
    normalize_text(default_if_empty(artist, "unknown")),
    "",
  )
}

fn make_collection(
  playlist_id: String,
  title: String,
  items: List(core.UnifiedItem),
) -> core.UnifiedCollection {
  let track_ids =
    list.map(items, fn(item) {
      let core.UnifiedItem(id, _, _, _, _, _, _, _) = item
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

fn page_ctx(
  profile_url: String,
  playlist_id: String,
  api_key: String,
  client_version: String,
  token: String,
) -> String {
  profile_url
  <> "|"
  <> playlist_id
  <> "|"
  <> api_key
  <> "|"
  <> client_version
  <> "|"
  <> token
}

fn parse_lines(raw: String) -> List(String) {
  let value = string.trim(raw)
  case value {
    "" -> []
    _ -> list.filter(string.split(value, "\n"), fn(line) { line != "" })
  }
}

fn default_if_empty(value: String, fallback: String) -> String {
  case value == "" {
    True -> fallback
    False -> value
  }
}

fn normalize_text(value: String) -> String {
  value
  |> string.trim
  |> string.replace("\n", " ")
  |> string.replace("  ", " ")
}

fn cached_playlist_first_tsv(
  url: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("youtube_playlist_first_tsv", url, cache_mode, fn() {
    playlist_first_tsv(url)
  })
}

fn cached_playlist_first_next_token(
  url: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch(
    "youtube_playlist_first_next_token",
    url,
    cache_mode,
    fn() { playlist_first_next_token(url) },
  )
}

fn cached_playlist_api_key(
  url: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("youtube_playlist_api_key", url, cache_mode, fn() {
    playlist_api_key(url)
  })
}

fn cached_playlist_client_version(
  url: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("youtube_playlist_client_version", url, cache_mode, fn() {
    playlist_client_version(url)
  })
}

fn cached_playlist_title(
  url: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("youtube_playlist_title", url, cache_mode, fn() {
    playlist_title(url)
  })
}

fn cached_continuation_tsv(
  api_key: String,
  client_version: String,
  token: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  let key = api_key <> "|" <> client_version <> "|" <> token
  cache.read_or_fetch("youtube_continuation_tsv", key, cache_mode, fn() {
    continuation_tsv(api_key, client_version, token)
  })
}

fn cached_continuation_next_token(
  api_key: String,
  client_version: String,
  token: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  let key = api_key <> "|" <> client_version <> "|" <> token
  cache.read_or_fetch("youtube_continuation_next_token", key, cache_mode, fn() {
    continuation_next_token(api_key, client_version, token)
  })
}
