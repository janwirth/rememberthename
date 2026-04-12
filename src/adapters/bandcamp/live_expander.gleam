//// Bandcamp live adapter.
////
//// Entry contract:
//// - `BandcampProfile` is opaque.
//// - Callers construct roots only via `bandcamp_profile(profile_url)`.
//// - `resolve_profile` delegates traversal to `adapters/core`.
////
//// Accepted root input:
//// - profile URLs (`https://bandcamp.com/<profile_slug>`)
//// - `/track/...` and direct artist album links are out of scope as root inputs.
////
//// Traversal plan:
//// 1) Expand profile root:
////    - fetch profile html
////    - parse initial embedded item data from html payload
////    - extract `fan_id`, collection token, wishlist token
////    - enqueue collection/wishlist API nodes for deeper recursion
//// 2) Expand category node (`collection` or `wishlist`):
////    - call Bandcamp fancollection endpoint
////    - parse `item_id/item_type/item_title/band_name`
////    - follow pagination with `more_available` + `last_token`
////
//// API endpoints:
//// - `POST /api/fancollection/1/collection_items`
//// - `POST /api/fancollection/1/wishlist_items`
////
//// Normalization:
//// - Emitted items carry canonical
////   `service`, `source_type`, `source_id`.
//// - Purchased (`collection`) albums emit `UnifiedCollection` rows; wishlist albums expand tracks only.
////
//// Test coverage:
//// - `test/bandcamp_adapter_test.gleam`
//// - `test/bandcamp_profile_resolution_test.gleam`

import adapters/cache
import adapters/core
import gleam/hackney
import gleam/http.{Post}
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some, unwrap as option_unwrap}
import gleam/string

// Service-specific expansion; recursion, dedupe, and ordering are handled in adapters/core.

fn fetch(url: String) -> String {
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

fn post_json(url: String, body: String) -> String {
  case request.to(url) {
    Error(_) -> ""
    Ok(req) -> {
      let req =
        req
        |> request.set_method(Post)
        |> request.set_header("content-type", "application/json")
        |> request.set_header("user-agent", "Mozilla/5.0")
        |> request.set_body(body)
      case hackney.send(req) {
        Ok(response) -> response.body
        Error(_) -> ""
      }
    }
  }
}

pub opaque type BandcampProfile {
  BandcampProfile(profile_url: String)
}

pub fn bandcamp_profile(profile_url: String) -> BandcampProfile {
  BandcampProfile(profile_url: profile_url)
}

pub fn resolve_profile(
  profile: BandcampProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
) -> core.ResolveResult {
  resolve_profile_with_debug(profile, depth, cache_mode, fn(_) { Nil })
}

pub fn resolve_profile_with_debug(
  profile: BandcampProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  resolve_profile_with_debug_limited(profile, depth, cache_mode, 0, on_debug)
}

pub fn resolve_profile_with_debug_limited(
  profile: BandcampProfile,
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
  profile: BandcampProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  max_items: Int,
  queue_policy: core.QueuePolicy,
  on_debug: fn(String) -> Nil,
  on_progress: fn(core.ResolveProgress) -> Nil,
) -> core.ResolveResult {
  // Keep entry point specific: BandcampProfile -> profile_url traversal root.
  let BandcampProfile(profile_url) = profile
  core.resolve_profile_url_with_debug_limit_and_queue_policy(
    profile_url,
    depth,
    max_items,
    queue_policy,
    fn(node) { expand(node, cache_mode) },
    on_debug,
    on_progress,
  )
}

pub fn expand(
  node: core.AdapterNode,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url, cache_mode)
    core.CategoryNode(ctx) -> expand_category(ctx, cache_mode)
    core.ListNode(ctx) -> expand_album(ctx, cache_mode)
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
  // Depth-1 should come from profile entry payload, then API starts at deeper levels.
  let #(html, #(hits, fetches)) = cached_fetch(profile_url, cache_mode)
  let entry_items = parse_entry_items(html)
  let fan_id = extract_between(html, "&quot;fan_id&quot;:", ",")
  let collection_token =
    extract_between(
      html,
      "&quot;collection_data&quot;:{&quot;redownload_urls&quot;:{},&quot;last_token&quot;:&quot;",
      "&quot;",
    )
  let wishlist_token =
    extract_between(
      html,
      "&quot;wishlist_data&quot;:{&quot;last_token&quot;:&quot;",
      "&quot;",
    )

  case fan_id == "" || collection_token == "" || wishlist_token == "" {
    True ->
      core.ExpandResult(
        items: entry_items,
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
        cache_hits: hits,
        cache_fetches: fetches,
      )
    False ->
      core.ExpandResult(
        items: entry_items,
        lists: [],
        next_nodes: [
          core.CategoryNode(
            "collection" <> "|" <> fan_id <> "|" <> collection_token,
          ),
          core.CategoryNode(
            "wishlist" <> "|" <> fan_id <> "|" <> wishlist_token,
          ),
        ],
        unresolved: [],
        cache_hits: hits,
        cache_fetches: fetches,
      )
  }
}

fn expand_category(
  ctx: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    [kind, fan_id, token] ->
      fetch_category_page(kind, fan_id, token, cache_mode)
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

fn fetch_category_page(
  kind: String,
  fan_id: String,
  token: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  // Pagination follows Bandcamp API `more_available` + `last_token`.
  let endpoint = case kind {
    "collection" -> "https://bandcamp.com/api/fancollection/1/collection_items"
    _ -> "https://bandcamp.com/api/fancollection/1/wishlist_items"
  }

  let body =
    "{\"fan_id\":"
    <> fan_id
    <> ",\"older_than_token\":\""
    <> token
    <> "\",\"count\":50}"

  let #(json, #(hits, fetches)) = cached_post_json(endpoint, body, cache_mode)
  let #(page_items, album_nodes) = parse_category_payload(json, kind)
  let items = list.append(page_items, parse_tracklist_items(json, kind))
  let next = extract_between(json, "\"last_token\":\"", "\"")
  let more = string.contains(json, "\"more_available\":true")

  let page_nodes = case more && next != "" {
    True -> [core.CategoryNode(kind <> "|" <> fan_id <> "|" <> next)]
    False -> []
  }
  let next_nodes = list.append(page_nodes, album_nodes)

  core.ExpandResult(
    items: items,
    lists: [],
    next_nodes: next_nodes,
    unresolved: [],
    cache_hits: hits,
    cache_fetches: fetches,
  )
}

fn expand_album(ctx: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["album", feed_kind, album_url, album_id] ->
      expand_album_fetched(feed_kind, album_url, album_id, cache_mode)
    ["album", album_url, album_id] ->
      expand_album_fetched("wishlist", album_url, album_id, cache_mode)
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

fn expand_album_fetched(
  feed_kind: String,
  album_url: String,
  album_id: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let #(html, #(hits, fetches)) = cached_fetch(album_url, cache_mode)
  let tracks = parse_album_tracks(html, album_id)
  let album_title = extract_album_title_from_html(html)
  let lists = case feed_kind == "collection" {
    True -> {
      let track_ids =
        list.map(tracks, fn(t) {
          let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _) = t
          id
        })
      let list_source_id = "bandcamp:collection:" <> album_id
      [
        core.UnifiedCollection(
          id: list_source_id,
          title: album_title,
          track_ids: track_ids,
          list_ids: [],
          service: "bandcamp",
          source_type: "collection",
          source_id: list_source_id,
        ),
      ]
    }
    False -> []
  }
  core.ExpandResult(
    items: tracks,
    lists: lists,
    next_nodes: [],
    unresolved: [],
    cache_hits: hits,
    cache_fetches: fetches,
  )
}

fn extract_album_title_from_html(html: String) -> String {
  let decoded = string.replace(html, "&quot;", "\"")
  let t = extract_between(decoded, "\"album_title\":\"", "\"")
  case t != "" {
    True -> decode(t)
    False ->
      decode(extract_between(html, "property=\"og:title\" content=\"", "\""))
  }
}

fn cached_fetch(
  url: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch("bandcamp_fetch", url, cache_mode, fn() { fetch(url) })
}

fn cached_post_json(
  url: String,
  body: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch(
    "bandcamp_post_json",
    url <> "|" <> body,
    cache_mode,
    fn() { post_json(url, body) },
  )
}

fn parse_items(json: String, _kind: String) -> List(core.UnifiedItem) {
  let parts = string.split(json, "\"item_id\":")
  case parts {
    [] -> []
    [_, ..rest] -> parse_item_parts(rest, [])
  }
}

fn parse_category_payload(
  json: String,
  kind: String,
) -> #(List(core.UnifiedItem), List(core.AdapterNode)) {
  let parts = string.split(json, "\"item_id\":")
  case parts {
    [] -> #([], [])
    [_, ..rest] -> parse_item_parts_with_album_nodes(rest, kind, [], [])
  }
}

fn parse_item_parts_with_album_nodes(
  parts: List(String),
  feed_kind: String,
  items_acc: List(core.UnifiedItem),
  nodes_acc: List(core.AdapterNode),
) -> #(List(core.UnifiedItem), List(core.AdapterNode)) {
  case parts {
    [] -> #(list.reverse(items_acc), list.reverse(nodes_acc))
    [part, ..rest] -> {
      let id = first_segment(part, ",")
      let item_type = extract_between(part, "\"item_type\":\"", "\"")
      let title = extract_between(part, "\"item_title\":\"", "\"")
      let artist = extract_between(part, "\"band_name\":\"", "\"")
      let item_url = decode(extract_between(part, "\"item_url\":\"", "\""))
      case id == "" || item_type == "" || title == "" {
        True ->
          parse_item_parts_with_album_nodes(
            rest,
            feed_kind,
            items_acc,
            nodes_acc,
          )
        False -> {
          let page_url = decode(item_url)
          let added_at =
            option_unwrap(
              parse_bandcamp_added_at(
                decode(extract_between(part, "\"added\":\"", "\"")),
              ),
              "",
            )
          let maybe_item =
            core.track_item_with_added_at(
              "bandcamp",
              id,
              decode(title),
              decode(default_if_empty(artist, "unknown")),
              page_url,
              fan_item_cover(part),
              added_at,
            )
          let nodes_acc = case item_type == "album" && item_url != "" {
            True -> [
              core.ListNode(
                "album|" <> feed_kind <> "|" <> page_url <> "|" <> id,
              ),
              ..nodes_acc
            ]
            False -> nodes_acc
          }
          parse_item_parts_with_album_nodes(
            rest,
            feed_kind,
            case maybe_item {
              Ok(item) -> [item, ..items_acc]
              Error(_) -> items_acc
            },
            nodes_acc,
          )
        }
      }
    }
  }
}

fn parse_tracklist_items(json: String, kind: String) -> List(core.UnifiedItem) {
  let parts = string.split(json, "\"tracklists\":{")
  case parts {
    [_, tail, ..] ->
      tail
      |> first_segment("},\"purchase_infos\"")
      |> parse_track_title_parts(kind, [])
    _ -> []
  }
}

fn parse_track_title_parts(
  tracklists_segment: String,
  _kind: String,
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  let parts = string.split(tracklists_segment, "\"id\":")
  case parts {
    [] -> []
    [_, ..rest] -> parse_track_id_parts(rest, acc)
  }
}

fn parse_track_id_parts(
  parts: List(String),
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] -> {
      let track_id = first_segment(part, ",")
      let title = extract_between(part, "\"title\":\"", "\"")
      let artist = extract_between(part, "\"artist\":\"", "\"")
      let title_link = decode(extract_between(part, "\"title_link\":\"", "\""))
      let added_at =
        option_unwrap(
          parse_bandcamp_added_at(
            decode(extract_between(part, "\"added\":\"", "\"")),
          ),
          "",
        )
      case track_id == "" || title == "" {
        True -> parse_track_id_parts(rest, acc)
        False -> {
          let maybe_item =
            core.track_item_with_added_at(
              "bandcamp",
              track_id,
              decode(title),
              decode(default_if_empty(artist, "unknown")),
              title_link,
              tracklist_track_cover(part),
              added_at,
            )
          parse_track_id_parts(rest, case maybe_item {
            Ok(item) -> [item, ..acc]
            Error(_) -> acc
          })
        }
      }
    }
  }
}

fn parse_album_tracks(html: String, album_id: String) -> List(core.UnifiedItem) {
  let album_cover = album_thumb_from_html(html)
  let decoded = string.replace(html, "&quot;", "\"")
  let trackinfo_split = string.split(decoded, "\"trackinfo\":")
  case trackinfo_split {
    [_, tail, ..] ->
      tail
      |> first_segment("],")
      |> parse_album_track_parts(album_id, album_cover)
    _ -> []
  }
}

fn parse_album_track_parts(
  segment: String,
  album_id: String,
  album_cover: String,
) -> List(core.UnifiedItem) {
  let parts = string.split(segment, "\"title\":\"")
  case parts {
    [] -> []
    [_, ..rest] ->
      parse_album_track_titles(rest, album_id, 0, [], album_cover)
  }
}

fn parse_album_track_titles(
  parts: List(String),
  album_id: String,
  index: Int,
  acc: List(core.UnifiedItem),
  album_cover: String,
) -> List(core.UnifiedItem) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] -> {
      let title = decode(first_segment(part, "\""))
      let track_id =
        first_segment(extract_between(part, "\"track_id\":", ","), ",")
      let artist =
        decode(default_if_empty(
          extract_between(part, "\"artist\":\"", "\""),
          "unknown",
        ))
      let title_link = decode(extract_between(part, "\"title_link\":\"", "\""))
      let track_thumb = tracklist_track_cover(part)
      let cover = case string.trim(track_thumb) != "" {
        True -> track_thumb
        False -> album_cover
      }
      let added_at =
        option_unwrap(
          parse_bandcamp_added_at(
            decode(extract_between(part, "\"added\":\"", "\"")),
          ),
          "",
        )
      case title == "" {
        True ->
          parse_album_track_titles(rest, album_id, index + 1, acc, album_cover)
        False -> {
          let raw_source_id = case track_id {
            "" -> album_id <> ":" <> int.to_string(index)
            _ -> track_id
          }
          let maybe_item =
            core.track_item_with_added_at(
              "bandcamp",
              raw_source_id,
              title,
              artist,
              title_link,
              cover,
              added_at,
            )
          parse_album_track_titles(rest, album_id, index + 1, case maybe_item {
            Ok(item) -> [item, ..acc]
            Error(_) -> acc
          }, album_cover)
        }
      }
    }
  }
}

fn parse_entry_items(html: String) -> List(core.UnifiedItem) {
  // Profile page stores initial rows inside HTML-escaped JSON (`&quot;...&quot;`).
  html
  |> string.replace("&quot;", "\"")
  |> parse_items("collection")
}

fn parse_item_parts(
  parts: List(String),
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] -> {
      let id = first_segment(part, ",")
      let item_type = extract_between(part, "\"item_type\":\"", "\"")
      let title = extract_between(part, "\"item_title\":\"", "\"")
      let artist = extract_between(part, "\"band_name\":\"", "\"")
      let item_url = decode(extract_between(part, "\"item_url\":\"", "\""))
      let added_at =
        option_unwrap(
          parse_bandcamp_added_at(
            decode(extract_between(part, "\"added\":\"", "\"")),
          ),
          "",
        )
      case id == "" || item_type == "" || title == "" {
        True -> parse_item_parts(rest, acc)
        False -> {
          let maybe_item =
            core.track_item_with_added_at(
              "bandcamp",
              id,
              decode(title),
              decode(default_if_empty(artist, "unknown")),
              item_url,
              fan_item_cover(part),
              added_at,
            )
          parse_item_parts(rest, case maybe_item {
            Ok(item) -> [item, ..acc]
            Error(_) -> acc
          })
        }
      }
    }
  }
}

fn default_if_empty(value: String, fallback: String) -> String {
  case value {
    "" -> fallback
    _ -> value
  }
}

fn fan_item_cover(part: String) -> String {
  let a = decode(extract_between(part, "\"art_url\":\"", "\""))
  case string.trim(a) != "" {
    True -> a
    False -> decode(extract_between(part, "\"item_art_url\":\"", "\""))
  }
}

fn tracklist_track_cover(part: String) -> String {
  let thumb = decode(extract_between(part, "\"thumb_url\":\"", "\""))
  case string.trim(thumb) != "" {
    True -> thumb
    False -> fan_item_cover(part)
  }
}

fn album_thumb_from_html(html: String) -> String {
  let decoded = string.replace(html, "&quot;", "\"")
  let og = extract_between(decoded, "property=\"og:image\" content=\"", "\"")
  case string.trim(og) != "" {
    True -> decode(og)
    False -> decode(extract_between(decoded, "\"artThumbURL\":\"", "\""))
  }
}

fn decode(value: String) -> String {
  value
  |> string.replace("\\/", "/")
  |> string.replace("\\u0026", "&")
  |> string.replace("\\u003c", "<")
  |> string.replace("\\u003e", ">")
  |> string.replace("\\\"", "\"")
}

fn extract_between(body: String, start: String, ending: String) -> String {
  let with_start = string.split(body, start)
  case with_start {
    [_, tail, ..] -> first_segment(tail, ending)
    _ -> ""
  }
}

fn first_segment(value: String, separator: String) -> String {
  let parts = string.split(value, separator)
  case parts {
    [first, ..] -> first
    _ -> ""
  }
}

fn parse_bandcamp_added_at(raw: String) -> Option(String) {
  let value = string.trim(raw)
  case is_iso8601_utc(value) {
    True -> Some(value)
    False ->
      case string.split(value, " ") {
        [day, month, year, hhmmss, zone] -> {
          let day = zero_pad_2(day)
          let month = bandcamp_month_to_number(month)
          let time_parts = string.split(hhmmss, ":")
          case
            month != "" && zone == "GMT" && is_year(year) && is_hms(time_parts)
          {
            True ->
              Some(year <> "-" <> month <> "-" <> day <> "T" <> hhmmss <> "Z")
            False -> None
          }
        }
        _ -> None
      }
  }
}

fn bandcamp_month_to_number(value: String) -> String {
  case value {
    "Jan" -> "01"
    "Feb" -> "02"
    "Mar" -> "03"
    "Apr" -> "04"
    "May" -> "05"
    "Jun" -> "06"
    "Jul" -> "07"
    "Aug" -> "08"
    "Sep" -> "09"
    "Oct" -> "10"
    "Nov" -> "11"
    "Dec" -> "12"
    _ -> ""
  }
}

fn zero_pad_2(value: String) -> String {
  let chars = string.to_graphemes(value)
  case list.length(chars) {
    1 -> "0" <> value
    2 -> value
    _ -> value
  }
}

fn is_year(value: String) -> Bool {
  let chars = string.to_graphemes(value)
  list.length(chars) == 4 && list.all(chars, is_ascii_digit)
}

fn is_hms(parts: List(String)) -> Bool {
  case parts {
    [h, m, s] -> is_two_digits(h) && is_two_digits(m) && is_two_digits(s)
    _ -> False
  }
}

fn is_two_digits(value: String) -> Bool {
  let chars = string.to_graphemes(value)
  list.length(chars) == 2 && list.all(chars, is_ascii_digit)
}

fn is_iso8601_utc(value: String) -> Bool {
  let chars = string.to_graphemes(value)
  list.length(chars) >= 20
  && string.ends_with(value, "Z")
  && list.all(string.to_graphemes(slice(value, 0, 4)), is_ascii_digit)
  && list.all(string.to_graphemes(slice(value, 5, 2)), is_ascii_digit)
  && list.all(string.to_graphemes(slice(value, 8, 2)), is_ascii_digit)
  && list.all(string.to_graphemes(slice(value, 11, 2)), is_ascii_digit)
  && list.all(string.to_graphemes(slice(value, 14, 2)), is_ascii_digit)
  && list.all(string.to_graphemes(slice(value, 17, 2)), is_ascii_digit)
  && slice(value, 4, 1) == "-"
  && slice(value, 7, 1) == "-"
  && slice(value, 10, 1) == "T"
  && slice(value, 13, 1) == ":"
  && slice(value, 16, 1) == ":"
}

fn slice(value: String, at_index: Int, length: Int) -> String {
  string.slice(value, at_index: at_index, length: length)
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
