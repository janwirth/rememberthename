//// SoundCloud live adapter.
////
//// Entry contract:
//// - `SoundcloudProfile` is opaque.
//// - Callers construct roots only via `soundcloud_profile(profile_url)`.
//// - `resolve_profile` delegates traversal to `adapters/core`.
////
//// Accepted root input:
//// - profile URLs (`https://soundcloud.com/<profile_slug>`)
//// - Track URLs are out of scope as root inputs.
////
//// Traversal plan:
//// 1) Expand profile root:
////    - fetch profile html, extract `client_id`
////    - resolve `user_id` via SoundCloud resolve endpoint
////    - seed category traversal: likes + reposts
//// 2) Expand category node:
////    - fetch page tracks
////    - collect playlist ids from page
////    - follow `next_href` until exhausted
//// 3) After category pagination completes:
////    - enqueue playlist list nodes
//// 4) Expand playlist node:
////    - emit full `UnifiedCollection` with track ids
////
//// Normalization:
//// - Emitted items/lists always include canonical
////   `service`, `source_type`, `source_id`.
////
//// Test coverage:
//// - `test/soundcloud_adapter_test.gleam`
//// - `test/soundcloud_adapter_fake_test.gleam`
import gleam/int
import gleam/hackney
import gleam/http/request
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import adapters/cache
import adapters/core

// Service-specific expansion; recursion, dedupe, and ordering are handled in adapters/core.
pub opaque type SoundcloudProfile {
  SoundcloudProfile(profile_url: String)
}

pub fn soundcloud_profile(profile_url: String) -> SoundcloudProfile {
  SoundcloudProfile(profile_url: profile_url)
}

pub fn resolve_profile(
  profile: SoundcloudProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
) -> core.ResolveResult {
  resolve_profile_with_debug(profile, depth, cache_mode, fn(_) { Nil })
}

pub fn resolve_profile_with_debug(
  profile: SoundcloudProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  resolve_profile_with_debug_limited(
    profile,
    depth,
    cache_mode,
    0,
    on_debug,
  )
}

pub fn resolve_profile_with_debug_limited(
  profile: SoundcloudProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  max_items: Int,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  // Keep entry point specific: SoundcloudProfile -> profile_url traversal root.
  let SoundcloudProfile(profile_url) = profile
  core.resolve_profile_url_with_debug_and_limit(
    profile_url,
    depth,
    max_items,
    fn(node) { expand(node, cache_mode) },
    on_debug,
  )
}

pub fn expand(node: core.AdapterNode, cache_mode: cache.CacheMode) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url, cache_mode)
    core.CategoryNode(ctx) -> expand_category(ctx, cache_mode)
    core.ListNode(ctx) -> expand_playlist(ctx, cache_mode)
    core.PageNode(_) ->
      core.ExpandResult(items: [], lists: [], next_nodes: [], unresolved: [])
  }
}

fn expand_profile(profile_url: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  // Bootstrap from profile HTML, then start category traversal (likes + reposts).
  let html = cached_fetch_profile_body(profile_url, cache_mode)
  let client_id = extract_between(html, "\"id\":\"", "\"")
  let user_id = resolve_user_id(profile_url, client_id, cache_mode)
  case client_id == "" || user_id == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
      )
    False -> {
      let likes_page = likes_start_url(user_id, client_id)
      let reposts_page = reposts_start_url(user_id, client_id)
      core.ExpandResult(
        items: parse_tracks(likes_page, "likes", cache_mode),
        lists: [],
        next_nodes: [
          core.CategoryNode("likes|" <> likes_page <> "|" <> client_id <> "|"),
          core.CategoryNode("reposts|" <> reposts_page <> "|" <> client_id <> "|"),
        ],
        unresolved: [],
      )
    }
  }
}

fn expand_category(ctx: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  // Exhaust category pagination first; only then enqueue playlist nodes.
  let parts = string.split(ctx, "|")
  case parts {
    [kind, url, client_id, acc_ids] -> {
      let items = parse_tracks(url, kind, cache_mode)
      let page_body = cached_fetch_profile_body(url, cache_mode)
      let page_playlist_ids = parse_lines(cached_json_playlist_ids(page_body, cache_mode))
      let merged_playlist_ids = merge_ids(parse_csv(acc_ids), page_playlist_ids)
      let next_href = trim(cached_json_next_href(page_body, cache_mode))
      case next_href == "" {
        True ->
          core.ExpandResult(
            items: items,
            lists: [],
            next_nodes: playlist_nodes(merged_playlist_ids, client_id),
            unresolved: [],
          )
        False -> {
          let next = ensure_client_id(next_href, client_id)
          core.ExpandResult(
            items: items,
            lists: [],
            next_nodes: [
              core.CategoryNode(
                kind <> "|" <> next <> "|" <> client_id <> "|" <> csv(merged_playlist_ids),
              ),
            ],
            unresolved: [],
          )
        }
      }
    }
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.CategoryNode(ctx)],
      )
  }
}

fn expand_playlist(ctx: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  // Emit only fully-resolved list payloads for playlists.
  let parts = string.split(ctx, "|")
  case parts {
    ["playlist", playlist_id, client_id] -> {
      let url = playlist_url(playlist_id, client_id)
      let json = cached_fetch_profile_body(url, cache_mode)
      let title = trim(cached_json_title(json, cache_mode))
      let track_ids = parse_lines(cached_json_track_ids(json, cache_mode))
      core.ExpandResult(
        items: [],
        lists: [
          core.UnifiedCollection(
            id: "playlist:" <> playlist_id,
            title: title,
            track_ids: track_ids,
            list_ids: [],
            service: "soundcloud",
            source_type: "collection",
            source_id: "playlist:" <> playlist_id,
          ),
        ],
        next_nodes: [],
        unresolved: [],
      )
    }
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ListNode(ctx)],
      )
  }
}

pub fn fetch_likes_payload(profile_url: String) -> String {
  let html = cached_fetch_profile_body(profile_url, cache.CacheUpsert)
  let client_id = extract_between(html, "\"id\":\"", "\"")
  let user_id = resolve_user_id(profile_url, client_id, cache.CacheUpsert)
  case client_id == "" || user_id == "" {
    True -> ""
    False ->
      cached_fetch_profile_body(
        likes_start_url(user_id, client_id),
        cache.CacheUpsert,
      )
  }
}

fn resolve_user_id(
  profile_url: String,
  client_id: String,
  cache_mode: cache.CacheMode,
) -> String {
  case client_id == "" {
    True -> ""
    False -> {
      let resolve_url =
        "https://api-v2.soundcloud.com/resolve?url=" <> profile_url <> "&client_id=" <> client_id
      let resolve_json = cached_fetch_profile_body(resolve_url, cache_mode)
      let parsed = decode_json(resolve_json, decode.dynamic) |> result.unwrap(dynamic.nil())
      case decode_path(parsed, ["id"], id_decoder()) {
        Some(user_id) -> user_id
        None -> extract_between(resolve_json, "\"urn\":\"soundcloud:users:", "\"")
      }
    }
  }
}

fn parse_tracks(
  url: String,
  kind: String,
  cache_mode: cache.CacheMode,
) -> List(core.UnifiedItem) {
  let json = cached_fetch_profile_body(url, cache_mode)
  let lines = parse_lines(cached_json_tracks_tsv(json, cache_mode))
  list.index_map(lines, fn(line, idx) {
    let cols = string.split(line, "\t")
    let #(raw_source_id, title, artist) =
      case cols {
        [id, title, artist] -> #(id, title, artist)
        [id, title] -> #(id, title, "unknown")
        [id] -> #(id, "untitled", "unknown")
        _ -> #(kind <> ":" <> int.to_string(idx + 1), "untitled", "unknown")
      }
    core.track_item("soundcloud", raw_source_id, title, artist)
  })
  |> list.filter_map(fn(item) { item })
}

fn cached_fetch_profile_body(url: String, cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "soundcloud_fetch",
    url,
    cache_mode,
    fn() { fetch_profile_body(url) },
  )
}

fn cached_json_next_href(json: String, cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "soundcloud_next_href",
    json,
    cache_mode,
    fn() {
      let parsed = decode_json(json, decode.dynamic) |> result.unwrap(dynamic.nil())
      decode_path_or(parsed, ["next_href"], "", decode.string)
    },
  )
}

fn cached_json_tracks_tsv(json: String, cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "soundcloud_tracks_tsv",
    json,
    cache_mode,
    fn() { build_tracks_tsv(json) },
  )
}

fn cached_json_playlist_ids(json: String, cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "soundcloud_playlist_ids",
    json,
    cache_mode,
    fn() {
      decode_collection_entries(json)
      |> collect_playlist_ids([])
      |> string.join("\n")
    },
  )
}

fn cached_json_title(json: String, cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "soundcloud_title",
    json,
    cache_mode,
    fn() {
      let parsed = decode_json(json, decode.dynamic) |> result.unwrap(dynamic.nil())
      decode_path_or(parsed, ["title"], "", decode.string)
    },
  )
}

fn cached_json_track_ids(json: String, cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "soundcloud_track_ids",
    json,
    cache_mode,
    fn() {
      let parsed = decode_json(json, decode.dynamic) |> result.unwrap(dynamic.nil())
      let tracks = decode_path_or(parsed, ["tracks"], [], decode.list(of: decode.dynamic))
      collect_track_ids(tracks, [])
      |> string.join("\n")
    },
  )
}

fn fetch_profile_body(url: String) -> String {
  case request.to(url) {
    Error(_) -> ""
    Ok(req) -> {
      let req =
        req
        |> request.set_header("user-agent", "Mozilla/5.0")
        |> request.set_header("accept", "application/json,text/html,*/*")
      case hackney.send(req) {
        Ok(response) -> response.body
        Error(_) -> ""
      }
    }
  }
}

fn decode_json(
  raw: String,
  decoder: decode.Decoder(a),
) -> Result(a, json.DecodeError) {
  json.parse(raw, decoder)
}

fn decode_collection_entries(raw: String) -> List(dynamic.Dynamic) {
  let parsed = decode_json(raw, decode.dynamic) |> result.unwrap(dynamic.nil())
  decode_path_or(parsed, ["collection"], [], decode.list(of: decode.dynamic))
}

fn id_decoder() -> decode.Decoder(String) {
  decode.one_of(decode.string, or: [decode.int |> decode.map(int.to_string)])
}

fn decode_path(
  data: dynamic.Dynamic,
  path: List(b),
  decoder: decode.Decoder(a),
) -> Option(a) {
  case decode.run(data, decode.at(path, decoder)) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn decode_path_or(
  data: dynamic.Dynamic,
  path: List(b),
  fallback: a,
  decoder: decode.Decoder(a),
) -> a {
  decode.run(data, decode.optionally_at(path, fallback, decoder))
  |> result.unwrap(fallback)
}

fn track_tuple_from_dynamic(
  data: dynamic.Dynamic,
  path_prefix: List(String),
) -> Option(#(String, String, String)) {
  let id_path = list.append(path_prefix, ["id"])
  let title_path = list.append(path_prefix, ["title"])
  let artist_path = list.append(path_prefix, ["user", "username"])
  case decode_path(data, id_path, id_decoder()) {
    None -> None
    Some(id) -> {
      let title = decode_path_or(data, title_path, "untitled", decode.string)
      let artist = decode_path_or(data, artist_path, "unknown", decode.string)
      Some(#(id, title, artist))
    }
  }
}

fn track_tuple_from_entry(entry: dynamic.Dynamic) -> Option(#(String, String, String)) {
  case track_tuple_from_dynamic(entry, ["track"]) {
    Some(track) -> Some(track)
    None ->
      case decode_path_or(entry, ["kind"], "", decode.string) == "track" {
        True ->
          case track_tuple_from_dynamic(entry, []) {
            Some(track) -> Some(track)
            None -> track_tuple_from_dynamic(entry, ["origin", "track"])
          }
        False -> track_tuple_from_dynamic(entry, ["origin", "track"])
      }
  }
}

fn playlist_id_from_entry(entry: dynamic.Dynamic) -> Option(String) {
  case decode_path(entry, ["playlist", "id"], id_decoder()) {
    Some(id) -> Some(id)
    None ->
      case decode_path_or(entry, ["kind"], "", decode.string) == "playlist" {
        True -> decode_path(entry, ["id"], id_decoder())
        False -> None
      }
  }
}

fn collect_playlist_ids(
  entries: List(dynamic.Dynamic),
  acc: List(String),
) -> List(String) {
  case entries {
    [] -> list.reverse(acc)
    [entry, ..rest] ->
      case playlist_id_from_entry(entry) {
        Some(id) -> collect_playlist_ids(rest, [id, ..acc])
        None -> collect_playlist_ids(rest, acc)
      }
  }
}

fn collect_track_ids(tracks: List(dynamic.Dynamic), acc: List(String)) -> List(String) {
  case tracks {
    [] -> list.reverse(acc)
    [track, ..rest] ->
      case decode_path(track, ["id"], id_decoder()) {
        Some(id) -> collect_track_ids(rest, [id, ..acc])
        None -> collect_track_ids(rest, acc)
      }
  }
}

fn build_tracks_tsv(raw: String) -> String {
  decode_collection_entries(raw)
  |> collect_track_rows([])
  |> string.join("\n")
}

fn collect_track_rows(
  entries: List(dynamic.Dynamic),
  acc: List(String),
) -> List(String) {
  case entries {
    [] -> list.reverse(acc)
    [entry, ..rest] ->
      case track_tuple_from_entry(entry) {
        Some(track) -> {
          let #(id, title, artist) = track
          collect_track_rows(rest, [id <> "\t" <> title <> "\t" <> artist, ..acc])
        }
        None -> collect_track_rows(rest, acc)
      }
  }
}

fn likes_start_url(user_id: String, client_id: String) -> String {
  "https://api-v2.soundcloud.com/users/"
  <> user_id
  <> "/likes?client_id="
  <> client_id
  <> "&limit=50&offset=0&linked_partitioning=1&app_version=1772785214&app_locale=en"
}

fn reposts_start_url(user_id: String, client_id: String) -> String {
  "https://api-v2.soundcloud.com/stream/users/"
  <> user_id
  <> "/reposts?client_id="
  <> client_id
  <> "&limit=50&offset=0&linked_partitioning=1&app_version=1772785214&app_locale=en"
}

fn playlist_url(playlist_id: String, client_id: String) -> String {
  "https://api-v2.soundcloud.com/playlists/" <> playlist_id <> "?client_id=" <> client_id
}

fn ensure_client_id(url: String, client_id: String) -> String {
  case string.contains(url, "client_id=") {
    True -> url
    False -> url <> "&client_id=" <> client_id
  }
}

fn parse_lines(raw: String) -> List(String) {
  let value = trim(raw)
  case value {
    "" -> []
    _ -> list.filter(string.split(value, "\n"), fn(line) { line != "" })
  }
}

fn parse_csv(value: String) -> List(String) {
  case trim(value) {
    "" -> []
    _ -> list.filter(string.split(value, ","), fn(part) { part != "" })
  }
}

fn csv(values: List(String)) -> String {
  string.join(values, ",")
}

fn merge_ids(a: List(String), b: List(String)) -> List(String) {
  dedupe(list.append(a, b), [])
}

fn dedupe(values: List(String), acc: List(String)) -> List(String) {
  case values {
    [] -> list.reverse(acc)
    [first, ..rest] ->
      case list.contains(acc, first) {
        True -> dedupe(rest, acc)
        False -> dedupe(rest, [first, ..acc])
      }
  }
}

fn playlist_nodes(ids: List(String), client_id: String) -> List(core.AdapterNode) {
  list.map(ids, fn(id) { core.ListNode("playlist|" <> id <> "|" <> client_id) })
}

fn trim(value: String) -> String {
  string.trim(value)
}

fn extract_between(body: String, start: String, ending: String) -> String {
  let with_start = string.split(body, start)
  case with_start {
    [_, tail, ..] -> {
      let before_end = string.split(tail, ending)
      case before_end {
        [value, ..] -> value
        _ -> ""
      }
    }
    _ -> ""
  }
}
