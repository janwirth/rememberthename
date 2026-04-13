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
////    - follow `next_href` until exhausted
////
//// Normalization:
//// - Emitted items/lists always include canonical
////   `service`, `source_type`, `source_id`.
////
//// Test coverage:
//// - `test/soundcloud_adapter_test.gleam`
//// - `test/soundcloud_adapter_fake_test.gleam`

import adapters/cache
import adapters/core
import gleam/dynamic
import gleam/dynamic/decode
import gleam/hackney
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some, unwrap as option_unwrap}
import gleam/result
import gleam/string

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
  resolve_profile_with_debug_limited(profile, depth, cache_mode, 0, on_debug)
}

pub fn resolve_profile_with_debug_limited(
  profile: SoundcloudProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  max_items: Int,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  resolve_profile_with_debug_limited_timed(
    profile,
    depth,
    cache_mode,
    max_items,
    core.default_queue_policy(),
    on_debug,
    fn(_) { Nil },
  )
}

pub fn resolve_profile_with_debug_limited_timed(
  profile: SoundcloudProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  max_items: Int,
  queue_policy: core.QueuePolicy,
  on_debug: fn(String) -> Nil,
  on_progress: fn(core.ResolveProgress) -> Nil,
  anchor: option.Option(String),
) -> core.ResolveResultWithAnchor {
  // Keep entry point specific: SoundcloudProfile -> profile_url traversal root.
  let SoundcloudProfile(profile_url) = profile
  core.resolve_profile_url_with_debug_limit_and_queue_policy(
    profile_url,
    depth,
    max_items,
    queue_policy,
    fn(node) { expand(node, cache_mode) },
    on_debug,
    on_progress,
    anchor,
  )
}

pub fn expand(
  node: core.AdapterNode,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url, cache_mode)
    core.CategoryNode(ctx) -> expand_category(ctx, cache_mode)
    core.ListNode(ctx) -> expand_playlist(ctx, cache_mode)
    core.PageNode(_) ->
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
  // Bootstrap from profile HTML, then start category traversal (likes + reposts).
  let #(html, c_html) = cached_fetch_profile_body(profile_url, cache_mode)
  let client_id = extract_between(html, "\"id\":\"", "\"")
  let #(user_id, c_resolve) = resolve_user_id(profile_url, client_id, cache_mode)
  let #(roll_h, roll_f) = cache.merge_rollups(c_html, c_resolve)
  case client_id == "" || user_id == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
        cache_hits: roll_h,
        cache_fetches: roll_f,
      )
    False -> {
      let likes_page = likes_start_url(user_id, client_id)
      let reposts_page = reposts_start_url(user_id, client_id)
      let #(like_items, c_likes) =
        parse_tracks(likes_page, "likes", cache_mode)
      let #(hits, fetches) =
        cache.merge_rollups(#(roll_h, roll_f), c_likes)
      core.ExpandResult(
        items: like_items,
        lists: [],
        next_nodes: [
          core.CategoryNode("likes|" <> likes_page <> "|" <> client_id <> "|"),
          core.CategoryNode(
            "reposts|" <> reposts_page <> "|" <> client_id <> "|",
          ),
        ],
        unresolved: [],
        cache_hits: hits,
        cache_fetches: fetches,
      )
    }
  }
}

fn expand_category(
  ctx: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  // Exhaust category pagination for likes/reposts only.
  let parts = string.split(ctx, "|")
  case parts {
    [kind, url, client_id, _acc_ids] -> {
      let #(items, c_items) = parse_tracks(url, kind, cache_mode)
      let #(page_body, c_page) = cached_fetch_profile_body(url, cache_mode)
      let #(next_raw, c_next) =
        cached_json_next_href(page_body, cache_mode)
      let next_href = trim(next_raw)
      let #(hits, fetches) =
        c_items |> cache.merge_rollups(c_page) |> cache.merge_rollups(c_next)
      case next_href == "" {
        True ->
          core.ExpandResult(
            items: items,
            lists: [],
            next_nodes: [],
            unresolved: [],
            cache_hits: hits,
            cache_fetches: fetches,
          )
        False -> {
          let next = ensure_client_id(next_href, client_id)
          core.ExpandResult(
            items: items,
            lists: [],
            next_nodes: [
              core.CategoryNode(kind <> "|" <> next <> "|" <> client_id <> "|"),
            ],
            unresolved: [],
            cache_hits: hits,
            cache_fetches: fetches,
          )
        }
      }
    }
    [kind, url, client_id] ->
      expand_category(kind <> "|" <> url <> "|" <> client_id <> "|", cache_mode)
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.CategoryNode(ctx)],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

fn expand_playlist(
  ctx: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  // Emit only fully-resolved list payloads for playlists.
  let parts = string.split(ctx, "|")
  case parts {
    ["playlist", playlist_id, client_id] -> {
      let url = playlist_url(playlist_id, client_id)
      let #(json, cj) = cached_fetch_profile_body(url, cache_mode)
      let #(title_raw, ct) = cached_json_title(json, cache_mode)
      let title = trim(title_raw)
      let #(track_ids_raw, cid) = cached_json_track_ids(json, cache_mode)
      let track_ids = parse_lines(track_ids_raw)
      let #(hits, fetches) =
        cj |> cache.merge_rollups(ct) |> cache.merge_rollups(cid)
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
        cache_hits: hits,
        cache_fetches: fetches,
      )
    }
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ListNode(ctx)],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

pub fn fetch_likes_payload(profile_url: String) -> String {
  let #(html, _) = cached_fetch_profile_body(profile_url, cache.CacheUpsert)
  let client_id = extract_between(html, "\"id\":\"", "\"")
  let #(user_id, _) = resolve_user_id(profile_url, client_id, cache.CacheUpsert)
  case client_id == "" || user_id == "" {
    True -> ""
    False -> {
      let #(body, _) =
        cached_fetch_profile_body(
          likes_start_url(user_id, client_id),
          cache.CacheUpsert,
        )
      body
    }
  }
}

fn resolve_user_id(
  profile_url: String,
  client_id: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  case client_id == "" {
    True -> #("", #(0, 0))
    False -> {
      let resolve_url =
        "https://api-v2.soundcloud.com/resolve?url="
        <> profile_url
        <> "&client_id="
        <> client_id
      let #(resolve_json, rollup) =
        cached_fetch_profile_body(resolve_url, cache_mode)
      let parsed =
        decode_json(resolve_json, decode.dynamic)
        |> result.unwrap(dynamic.nil())
      case decode_path(parsed, ["id"], id_decoder()) {
        Some(user_id) -> #(user_id, rollup)
        None -> #(
          extract_between(resolve_json, "\"urn\":\"soundcloud:users:", "\""),
          rollup,
        )
      }
    }
  }
}

fn parse_tracks(
  url: String,
  kind: String,
  cache_mode: cache.CacheMode,
) -> #(List(core.UnifiedItem), #(Int, Int)) {
  let #(json, c_page) = cached_fetch_profile_body(url, cache_mode)
  let #(tsv, c_tsv) = cached_json_tracks_tsv(json, cache_mode)
  let lines = parse_lines(tsv)
  let rollup = cache.merge_rollups(c_page, c_tsv)
  #(
    list.index_map(lines, fn(line, idx) {
      let cols = string.split(line, "\t")
      let #(raw_source_id, title, artist, perm_url, cover_url, added_at) = case cols {
        [id, title, artist, u, cover, added] -> #(
          id,
          title,
          artist,
          string.trim(u),
          string.trim(cover),
          option_unwrap(normalize_soundcloud_added_at(added), ""),
        )
        [id, title, artist, u, added] -> #(
          id,
          title,
          artist,
          string.trim(u),
          "",
          option_unwrap(normalize_soundcloud_added_at(added), ""),
        )
        [id, title, artist, u] -> #(id, title, artist, string.trim(u), "", "")
        [id, title, artist] -> #(id, title, artist, "", "", "")
        [id, title] -> #(id, title, "unknown", "", "", "")
        [id] -> #(id, "untitled", "unknown", "", "", "")
        _ -> #(
          kind <> ":" <> int.to_string(idx + 1),
          "untitled",
          "unknown",
          "",
          "",
          "",
        )
      }
      core.track_item_with_added_at(
        "soundcloud",
        raw_source_id,
        title,
        artist,
        perm_url,
        cover_url,
        added_at,
      )
    })
      |> list.filter_map(fn(item) { item }),
    rollup,
  )
}

fn cached_fetch_profile_body(
  url: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("soundcloud_fetch", url, cache_mode, fn() {
    fetch_profile_body(url)
  })
}

fn cached_json_next_href(
  json: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("soundcloud_next_href", json, cache_mode, fn() {
    let parsed =
      decode_json(json, decode.dynamic) |> result.unwrap(dynamic.nil())
    decode_path_or(parsed, ["next_href"], "", decode.string)
  })
}

fn cached_json_tracks_tsv(
  json: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("soundcloud_tracks_tsv", json, cache_mode, fn() {
    build_tracks_tsv(json)
  })
}

fn cached_json_title(
  json: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("soundcloud_title", json, cache_mode, fn() {
    let parsed =
      decode_json(json, decode.dynamic) |> result.unwrap(dynamic.nil())
    decode_path_or(parsed, ["title"], "", decode.string)
  })
}

fn cached_json_track_ids(
  json: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("soundcloud_track_ids", json, cache_mode, fn() {
    let parsed =
      decode_json(json, decode.dynamic) |> result.unwrap(dynamic.nil())
    let tracks =
      decode_path_or(parsed, ["tracks"], [], decode.list(of: decode.dynamic))
    collect_track_ids(tracks, [])
    |> string.join("\n")
  })
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

fn soundcloud_track_permalink_url(
  data: dynamic.Dynamic,
  path_prefix: List(String),
) -> String {
  let direct =
    decode_path_or(
      data,
      list.append(path_prefix, ["permalink_url"]),
      "",
      decode.string,
    )
    |> string.trim
  case direct != "" {
    True -> direct
    False -> {
      let user_p =
        decode_path_or(
          data,
          list.append(path_prefix, ["user", "permalink"]),
          "",
          decode.string,
        )
        |> string.trim
      let track_p =
        decode_path_or(
          data,
          list.append(path_prefix, ["permalink"]),
          "",
          decode.string,
        )
        |> string.trim
      case user_p != "" && track_p != "" {
        True -> "https://soundcloud.com/" <> user_p <> "/" <> track_p
        False -> ""
      }
    }
  }
}

fn track_tuple_from_dynamic(
  data: dynamic.Dynamic,
  path_prefix: List(String),
) -> Option(#(String, String, String, String, String, String)) {
  let id_path = list.append(path_prefix, ["id"])
  let title_path = list.append(path_prefix, ["title"])
  let artist_path = list.append(path_prefix, ["user", "username"])
  case decode_path(data, id_path, id_decoder()) {
    None -> None
    Some(id) -> {
      let title = decode_path_or(data, title_path, "untitled", decode.string)
      let artist = decode_path_or(data, artist_path, "unknown", decode.string)
      let perm_url = soundcloud_track_permalink_url(data, path_prefix)
      let artwork =
        decode_path_or(
          data,
          list.append(path_prefix, ["artwork_url"]),
          "",
          decode.string,
        )
        |> string.trim
      Some(#(id, title, artist, perm_url, artwork, ""))
    }
  }
}

fn track_tuple_from_entry(
  entry: dynamic.Dynamic,
) -> Option(#(String, String, String, String, String, String)) {
  let added_at =
    decode_path_or(entry, ["created_at"], "", decode.string)
    |> normalize_soundcloud_added_at
    |> option_unwrap("")
  case track_tuple_from_dynamic(entry, ["track"]) {
    Some(track) -> Some(with_added_at(track, added_at))
    None ->
      case decode_path_or(entry, ["kind"], "", decode.string) == "track" {
        True ->
          case track_tuple_from_dynamic(entry, []) {
            Some(track) -> Some(with_added_at(track, added_at))
            None ->
              case track_tuple_from_dynamic(entry, ["origin", "track"]) {
                Some(track) -> Some(with_added_at(track, added_at))
                None -> None
              }
          }
        False ->
          case track_tuple_from_dynamic(entry, ["origin", "track"]) {
            Some(track) -> Some(with_added_at(track, added_at))
            None -> None
          }
      }
  }
}

fn with_added_at(
  track: #(String, String, String, String, String, String),
  added_at: String,
) -> #(String, String, String, String, String, String) {
  let #(id, title, artist, perm_url, cover, _) = track
  #(id, title, artist, perm_url, cover, added_at)
}

fn collect_track_ids(
  tracks: List(dynamic.Dynamic),
  acc: List(String),
) -> List(String) {
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
          let #(id, title, artist, perm_url, cover, added_at) = track
          collect_track_rows(rest, [
            id
            <> "\t"
            <> title
            <> "\t"
            <> artist
            <> "\t"
            <> perm_url
            <> "\t"
            <> cover
            <> "\t"
            <> added_at,
            ..acc
          ])
        }
        None -> collect_track_rows(rest, acc)
      }
  }
}

fn normalize_soundcloud_added_at(raw: String) -> Option(String) {
  let value = string.trim(raw)
  case is_iso8601_utc(value) {
    True -> Some(value)
    False ->
      case is_date_only(value) {
        True -> Some(value <> "T00:00:00Z")
        False -> None
      }
  }
}

fn is_date_only(value: String) -> Bool {
  list.length(string.to_graphemes(value)) == 10
  && string.slice(value, at_index: 4, length: 1) == "-"
  && string.slice(value, at_index: 7, length: 1) == "-"
  && is_digits(string.slice(value, at_index: 0, length: 4))
  && is_digits(string.slice(value, at_index: 5, length: 2))
  && is_digits(string.slice(value, at_index: 8, length: 2))
}

fn is_iso8601_utc(value: String) -> Bool {
  list.length(string.to_graphemes(value)) >= 20
  && string.ends_with(value, "Z")
  && string.slice(value, at_index: 4, length: 1) == "-"
  && string.slice(value, at_index: 7, length: 1) == "-"
  && string.slice(value, at_index: 10, length: 1) == "T"
  && string.slice(value, at_index: 13, length: 1) == ":"
  && string.slice(value, at_index: 16, length: 1) == ":"
  && is_digits(string.slice(value, at_index: 0, length: 4))
  && is_digits(string.slice(value, at_index: 5, length: 2))
  && is_digits(string.slice(value, at_index: 8, length: 2))
  && is_digits(string.slice(value, at_index: 11, length: 2))
  && is_digits(string.slice(value, at_index: 14, length: 2))
  && is_digits(string.slice(value, at_index: 17, length: 2))
}

fn is_digits(value: String) -> Bool {
  let chars = string.to_graphemes(value)
  chars != [] && list.all(chars, is_ascii_digit)
}

fn is_ascii_digit(char: String) -> Bool {
  case char {
    "0" -> True
    "1" -> True
    "2" -> True
    "3" -> True
    "4" -> True
    "5" -> True
    "6" -> True
    "7" -> True
    "8" -> True
    "9" -> True
    _ -> False
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
  "https://api-v2.soundcloud.com/playlists/"
  <> playlist_id
  <> "?client_id="
  <> client_id
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
