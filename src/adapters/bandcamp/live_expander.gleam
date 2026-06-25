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
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/hackney
import gleam/http.{Post}
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some, unwrap as option_unwrap}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import glentities

// ---- Private types for JSON decoding ----------------------------------------

type BcAlbumTrack {
  BcAlbumTrack(
    track_id: Option(Int),
    title: String,
    artist: String,
    title_link: String,
    added: String,
    duration: Option(Float),
  )
}

type BcCategoryItem {
  BcCategoryItem(
    item_id: Int,
    item_type: String,
    item_title: String,
    band_name: String,
    item_url: String,
    added: String,
    purchased: String,
    featured_track_duration: Option(Float),
    art_url: String,
    item_art_url: String,
  )
}

type BcTracklistTrack {
  BcTracklistTrack(
    id: Int,
    title: String,
    artist: String,
    title_link: String,
    added: String,
    duration: Option(Float),
    thumb_url: String,
    art_url: String,
    item_art_url: String,
  )
}

// ---- Lenient decoders -------------------------------------------------------

fn bc_lenient_string() -> decode.Decoder(String) {
  decode.one_of(decode.string, or: [decode.success("")])
}

fn bc_lenient_float_option() -> decode.Decoder(Option(Float)) {
  // Bandcamp sometimes emits duration as an integer (no decimal point).
  decode.one_of(
    decode.optional(decode.float),
    or: [
      decode.optional(decode.int)
        |> decode.map(fn(o) { option.map(o, int.to_float) }),
      decode.success(None),
    ],
  )
}

fn bc_album_track_decoder() -> decode.Decoder(BcAlbumTrack) {
  use track_id <- decode.optional_field(
    "track_id",
    None,
    decode.optional(decode.int),
  )
  use title <- decode.optional_field("title", "", bc_lenient_string())
  use artist <- decode.optional_field("artist", "", bc_lenient_string())
  use title_link <- decode.optional_field("title_link", "", bc_lenient_string())
  use added <- decode.optional_field("added", "", bc_lenient_string())
  use duration <- decode.optional_field(
    "duration",
    None,
    bc_lenient_float_option(),
  )
  decode.success(BcAlbumTrack(track_id:, title:, artist:, title_link:, added:, duration:))
}

fn bc_category_item_decoder() -> decode.Decoder(BcCategoryItem) {
  use item_id <- decode.optional_field("item_id", 0, decode.int)
  use item_type <- decode.optional_field("item_type", "", bc_lenient_string())
  use item_title <- decode.optional_field("item_title", "", bc_lenient_string())
  use band_name <- decode.optional_field("band_name", "", bc_lenient_string())
  use item_url <- decode.optional_field("item_url", "", bc_lenient_string())
  use added <- decode.optional_field("added", "", bc_lenient_string())
  use purchased <- decode.optional_field("purchased", "", bc_lenient_string())
  use featured_track_duration <- decode.optional_field(
    "featured_track_duration",
    None,
    bc_lenient_float_option(),
  )
  use art_url <- decode.optional_field("art_url", "", bc_lenient_string())
  use item_art_url <- decode.optional_field(
    "item_art_url",
    "",
    bc_lenient_string(),
  )
  decode.success(BcCategoryItem(
    item_id:,
    item_type:,
    item_title:,
    band_name:,
    item_url:,
    added:,
    purchased:,
    featured_track_duration:,
    art_url:,
    item_art_url:,
  ))
}

fn bc_tracklist_track_decoder() -> decode.Decoder(BcTracklistTrack) {
  use id <- decode.optional_field("id", 0, decode.int)
  use title <- decode.optional_field("title", "", bc_lenient_string())
  use artist <- decode.optional_field("artist", "", bc_lenient_string())
  use title_link <- decode.optional_field("title_link", "", bc_lenient_string())
  use added <- decode.optional_field("added", "", bc_lenient_string())
  use duration <- decode.optional_field(
    "duration",
    None,
    bc_lenient_float_option(),
  )
  use thumb_url <- decode.optional_field("thumb_url", "", bc_lenient_string())
  use art_url <- decode.optional_field("art_url", "", bc_lenient_string())
  use item_art_url <- decode.optional_field(
    "item_art_url",
    "",
    bc_lenient_string(),
  )
  decode.success(BcTracklistTrack(
    id:,
    title:,
    artist:,
    title_link:,
    added:,
    duration:,
    thumb_url:,
    art_url:,
    item_art_url:,
  ))
}

// Service-specific expansion; recursion, dedupe, and ordering are handled in adapters/core.

fn should_retry(status: Int) -> Bool {
  status == 429 || status == 503 || status == 500
}

fn fetch_with_retry(req: request.Request(String), attempt: Int) -> String {
  case hackney.send(req) {
    Error(_) -> ""
    Ok(response) -> {
      case response.status == 200 {
        True -> response.body
        False ->
          case should_retry(response.status) && attempt < 4 {
            True -> {
              process.sleep(1000 * int.bitwise_shift_left(1, attempt))
              fetch_with_retry(req, attempt + 1)
            }
            False -> ""
          }
      }
    }
  }
}

fn fetch(url: String) -> String {
  case request.to(url) {
    Error(_) -> ""
    Ok(req) -> {
      let req =
        req
        |> request.set_header("user-agent", "Mozilla/5.0")
        |> request.set_header("accept", "application/json,text/html,*/*")
      fetch_with_retry(req, 0)
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
      fetch_with_retry(req, 0)
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
    option.None,
  ).result
}

pub fn resolve_profile_with_debug_limited_timed(
  profile: BandcampProfile,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  max_items: Int,
  queue_policy: core.QueuePolicy,
  on_debug: fn(String) -> Nil,
  on_progress: fn(core.ResolveProgress) -> Nil,
  anchor: option.Option(String),
) -> core.ResolveResultWithAnchor {
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

// Extract fan_id, first item's pagination token, and decoded JSON blob from
// a Bandcamp profile HTML page.
//
// data-blob uses &quot; to encode internal quotes, so the first literal " after
// data-blob=" is always the closing attribute delimiter — extract_between works.
// data-token on item elements is a plain value with no entity encoding.
fn scan_profile_html(html: String) -> #(String, String, String) {
  let raw_blob = extract_between(html, "data-blob=\"", "\"")
  let decoded_blob = case string.contains(raw_blob, "&") {
    True -> glentities.decode(raw_blob)
    False -> raw_blob
  }
  let fan_id = extract_between(decoded_blob, "\"fan_id\":", ",")
  let first_data_token = extract_between(html, "data-token=\"", "\"")
  #(fan_id, first_data_token, decoded_blob)
}

fn expand_profile(
  profile_url: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let #(html, #(hits, fetches)) = cached_fetch(profile_url, cache_mode)
  case html == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
        cache_hits: hits,
        cache_fetches: fetches,
      )
    False -> {
      let is_wishlist = string.contains(profile_url, "/wishlist")
      let feed_kind = case is_wishlist {
        True -> "wishlist"
        False -> "collection"
      }
      let #(fan_id, first_data_token, decoded_blob) =
        scan_profile_html(html)
      // first_data_token is e.g. "1763576106:2365071502:t::" — the proper
      // older_than_token for the fancollection API to get items 2, 3, …
      let #(api_json, #(a_hits, a_fetches)) = case
        fan_id == "" || first_data_token == ""
      {
        True -> #("", #(0, 0))
        False -> {
          let endpoint = case is_wishlist {
            True -> "https://bandcamp.com/api/fancollection/1/wishlist_items"
            False ->
              "https://bandcamp.com/api/fancollection/1/collection_items"
          }
          let body =
            "{\"fan_id\":"
            <> fan_id
            <> ",\"older_than_token\":\""
            <> first_data_token
            <> "\",\"count\":50}"
          cached_post_json(endpoint, body, cache_mode)
        }
      }
      // Items 2+ come from the API with real added_at dates.
      let #(api_items, api_album_nodes) = case api_json {
        "" -> #([], [])
        json -> parse_category_payload(json, feed_kind)
      }
      let api_tracklist_items = case api_json {
        "" -> []
        json -> parse_tracklist_items(json, feed_kind)
      }
      let all_api_items = list.append(api_items, api_tracklist_items)
      // Item 2's date is the best proxy for item 1's purchase date.
      let first_api_ts = case all_api_items {
        [first, ..] -> first.added_at
        _ -> timestamp.unix_epoch
      }
      // Item 1 comes from the item_cache in the decoded blob.
      let #(html_all_items, html_album_nodes) =
        parse_entry_items_with_nodes(decoded_blob, feed_kind)
      let first_api_ts_bumped = case first_api_ts != timestamp.unix_epoch {
        True -> timestamp.add(first_api_ts, duration.seconds(3600))
        False -> first_api_ts
      }
      let first_api_ts_str = core.added_at_display(first_api_ts_bumped)
      // Check whether item #1 in the cache is an album. If so, html_all_items[0]
      // would be item #2 (album filtered out) — wrong item to treat as item #1.
      let first_item_type =
        extract_between(
          entry_items_segment(decoded_blob, feed_kind),
          "\"item_type\":\"",
          "\"",
        )
      let first_item_is_album = first_item_type == "album"
      let html_first_item = case first_item_is_album {
        True -> []
        False ->
          case html_all_items {
            [h_item, ..] -> [
              core.UnifiedItem(
                ..h_item,
                added_at: first_api_ts_bumped,
                date_added_is_hypothetical: first_api_ts_bumped
                  != timestamp.unix_epoch,
              ),
            ]
            [] -> []
          }
      }
      // For item 1, build its expansion node with the bumped timestamp.
      // If item #1 is an album, reuse html_album_nodes[0] (which has empty date)
      // and stamp it with first_api_ts_str. For items 2-20, the API nodes carry
      // proper dates already, so html_album_nodes for those are discarded.
      let html_first_nodes = case first_item_is_album {
        True ->
          case html_album_nodes {
            [core.ListNode(node_data), ..] -> {
              // node_data ends with "|" (empty added_at); append bumped date
              let updated = case string.ends_with(node_data, "|") {
                True -> node_data <> first_api_ts_str
                False -> node_data
              }
              [core.ListNode(updated)]
            }
            _ -> []
          }
        False ->
          case html_first_item {
            [item] -> {
              let item_url = option_unwrap(item.external_source_url, "")
              case item.duration_s == None && item_url != "" {
                False -> []
                True -> [
                  core.ListNode(
                    "album|"
                    <> feed_kind
                    <> "|"
                    <> item_url
                    <> "|"
                    <> item.source_id
                    <> "|"
                    <> first_api_ts_str,
                  ),
                ]
              }
            }
            _ -> []
          }
      }
      // Pagination: API covers items 2-51; if more remain, enqueue next page.
      let api_more = string.contains(api_json, "\"more_available\":true")
      let api_next = extract_between(api_json, "\"last_token\":\"", "\"")
      case fan_id == "" {
        True ->
          core.ExpandResult(
            items: list.append(html_first_item, all_api_items),
            lists: [],
            next_nodes: list.append(html_first_nodes, api_album_nodes),
            unresolved: [core.ProfileEntry(profile_url)],
            cache_hits: hits + a_hits,
            cache_fetches: fetches + a_fetches,
          )
        False -> {
          let cat_node = case api_more && api_next != "" {
            True -> [core.CategoryNode(feed_kind <> "|" <> fan_id <> "|" <> api_next)]
            False -> []
          }
          core.ExpandResult(
            items: list.append(html_first_item, all_api_items),
            lists: [],
            next_nodes: list.flatten([
              cat_node,
              html_first_nodes,
              api_album_nodes,
            ]),
            unresolved: [],
            cache_hits: hits + a_hits,
            cache_fetches: fetches + a_fetches,
          )
        }
      }
    }
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
  // Empty response = HTTP failure; re-queue node as unresolved rather than
  // treating it as a legitimate empty last page (which silently stops pagination).
  case json == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.CategoryNode(kind <> "|" <> fan_id <> "|" <> token)],
        cache_hits: hits,
        cache_fetches: fetches,
      )
    False -> {
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
  }
}

fn expand_album(ctx: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["album", feed_kind, album_url, album_id, album_added_at] ->
      expand_album_fetched(feed_kind, album_url, album_id, album_added_at, cache_mode)
    ["album", feed_kind, album_url, album_id] ->
      expand_album_fetched(feed_kind, album_url, album_id, "", cache_mode)
    ["album", album_url, album_id] ->
      expand_album_fetched("wishlist", album_url, album_id, "", cache_mode)
    ["duration_probe", item_url, source_id, added_at] ->
      expand_duration_probe(item_url, source_id, added_at, cache_mode)
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

fn expand_duration_probe(
  item_url: String,
  source_id: String,
  added_at: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let #(html, #(hits, fetches)) = cached_fetch(item_url, cache_mode)
  let items = case html == "" {
    True -> []
    False -> {
      let decoded = string.replace(html, "&quot;", "\"")
      let duration_s =
        float.parse(string.trim(extract_between(decoded, "\"duration\":", ",")))
        |> option.from_result
      let title = extract_album_title_from_html(html)
      let artist = extract_album_artist_from_html(html)
      let cover = album_thumb_from_html(html)
      case duration_s {
        None -> []
        Some(_) ->
          case core.track_item_with_added_at(
            "bandcamp", source_id, title, artist, item_url, cover, added_at, [], duration_s,
          ) {
            Ok(item) -> [item]
            Error(_) -> []
          }
      }
    }
  }
  core.ExpandResult(
    items:,
    lists: [],
    next_nodes: [],
    unresolved: [],
    cache_hits: hits,
    cache_fetches: fetches,
  )
}

fn expand_album_fetched(
  feed_kind: String,
  album_url: String,
  album_id: String,
  album_added_at: String,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let #(html, #(hits, fetches)) = cached_fetch(album_url, cache_mode)
  case html == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [
          core.ListNode(
            "album|" <> feed_kind <> "|" <> album_url <> "|" <> album_id <> "|" <> album_added_at,
          ),
        ],
        cache_hits: hits,
        cache_fetches: fetches,
      )
    False -> {
      let tracks = parse_album_tracks(html, album_id, album_added_at)
      let album_title = extract_album_title_from_html(html)
      let lists = case feed_kind == "collection" {
        True -> {
          let track_ids =
            list.map(tracks, fn(t) {
              let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _, _, _, _, _) = t
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
  }
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

fn parse_category_payload(
  json_str: String,
  kind: String,
) -> #(List(core.UnifiedItem), List(core.AdapterNode)) {
  let items_decoder = {
    use items <- decode.optional_field(
      "items",
      [],
      decode.list(bc_category_item_decoder()),
    )
    decode.success(items)
  }
  case json.parse(json_str, items_decoder) {
    Error(_) -> #([], [])
    Ok(items) -> bc_category_items_to_result(items, kind)
  }
}

fn bc_category_items_to_result(
  bc_items: List(BcCategoryItem),
  feed_kind: String,
) -> #(List(core.UnifiedItem), List(core.AdapterNode)) {
  let #(items, nodes) =
    list.fold(bc_items, #([], []), fn(acc, bc) {
      let #(items_acc, nodes_acc) = acc
      let id = int.to_string(bc.item_id)
      let title = glentities.decode(bc.item_title)
      let band_name = glentities.decode(bc.band_name)
      case bc.item_id == 0 || bc.item_type == "" || title == "" {
        True -> acc
        False -> {
          let page_url = bc.item_url
          let added_raw = case bc.added { "" -> bc.purchased v -> v }
          let added_at = option_unwrap(parse_bandcamp_added_at(added_raw), "")
          let cover = case string.trim(bc.art_url) {
            "" -> bc.item_art_url
            a -> a
          }
          let is_album = bc.item_type == "album"
          let nodes_acc = case is_album && page_url != "" {
            True -> [
              core.ListNode(
                "album|"
                <> feed_kind
                <> "|"
                <> page_url
                <> "|"
                <> id
                <> "|"
                <> added_at,
              ),
              ..nodes_acc
            ]
            False -> nodes_acc
          }
          let maybe_item =
            core.track_item_with_added_at(
              "bandcamp",
              id,
              title,
              default_if_empty(band_name, "unknown"),
              page_url,
              cover,
              added_at,
              [],
              bc.featured_track_duration,
            )
          // Albums expand into tracks via ListNode; skip emitting as item.
          let items_acc = case maybe_item {
            Ok(item) ->
              case is_album {
                True -> items_acc
                False -> [item, ..items_acc]
              }
            Error(_) -> items_acc
          }
          // Schedule a page fetch for tracks missing duration.
          let nodes_acc = case bc.featured_track_duration == None && page_url != "" && !is_album {
            True -> [
              core.ListNode(
                "duration_probe|" <> page_url <> "|" <> id <> "|" <> added_at,
              ),
              ..nodes_acc
            ]
            False -> nodes_acc
          }
          #(items_acc, nodes_acc)
        }
      }
    })
  #(list.reverse(items), list.reverse(nodes))
}

fn parse_tracklist_items(json_str: String, _kind: String) -> List(core.UnifiedItem) {
  let decoder = {
    use tracklists <- decode.optional_field(
      "tracklists",
      dict.new(),
      decode.dict(decode.string, decode.list(bc_tracklist_track_decoder())),
    )
    decode.success(tracklists)
  }
  case json.parse(json_str, decoder) {
    Error(_) -> []
    Ok(tracklists) ->
      dict.values(tracklists)
      |> list.flatten
      |> list.filter_map(fn(track) {
        case track.id == 0 || track.title == "" {
          True -> Error(Nil)
          False -> {
            let cover = case string.trim(track.thumb_url) {
              "" ->
                case string.trim(track.art_url) {
                  "" -> track.item_art_url
                  a -> a
                }
              t -> t
            }
            let added_at =
              option_unwrap(parse_bandcamp_added_at(track.added), "")
            core.track_item_strict(
              "bandcamp",
              int.to_string(track.id),
              glentities.decode(track.title),
              default_if_empty(glentities.decode(track.artist), "unknown"),
              track.title_link,
              cover,
              added_at,
              [],
              track.duration,
            )
          }
        }
      })
  }
}

fn extract_bc_tags(html: String) -> List(String) {
  let decoded = string.replace(html, "&quot;", "\"")
  case string.split_once(decoded, "\"tags\":[") {
    Error(_) -> []
    Ok(#(_, after)) ->
      case string.split_once(after, "]") {
        Error(_) -> []
        Ok(#(tags_raw, _)) ->
          string.split(tags_raw, ",")
          |> list.map(fn(s) {
            s |> string.replace("\"", "") |> string.trim |> string.lowercase
          })
          |> list.filter(fn(s) { s != "" })
      }
  }
}

fn extract_album_artist_from_html(html: String) -> String {
  let decoded = string.replace(html, "&quot;", "\"")
  let a = extract_between(decoded, "\"artist\":\"", "\"")
  case a != "" {
    True -> decode(a)
    False -> decode(extract_between(html, "property=\"og:site_name\" content=\"", "\""))
  }
}

fn parse_album_tracks(html: String, album_id: String, album_added_at: String) -> List(core.UnifiedItem) {
  let album_cover = album_thumb_from_html(html)
  let album_genres = extract_bc_tags(html)
  let album_artist = extract_album_artist_from_html(html)
  let decoded = string.replace(html, "&quot;", "\"")
  case string.split_once(decoded, "\"trackinfo\":[") {
    Error(_) -> []
    Ok(#(_, tail)) -> {
      // Find end of outer array using the first unmatched ]. We reconstruct a
      // valid JSON array and let the parser handle escaping and nesting.
      let array_json = "[" <> take_outer_array(tail) <> "]"
      case json.parse(array_json, decode.list(bc_album_track_decoder())) {
        Error(_) -> []
        Ok(tracks) ->
          list.index_fold(tracks, [], fn(acc, track, index) {
            case track.title {
              "" -> acc
              _ -> {
                let ati = album_id <> ":" <> int.to_string(index)
                let source_id = case track.track_id {
                  None -> ati
                  Some(id) -> int.to_string(id)
                }
                let artist =
                  glentities.decode(default_if_empty(
                    default_if_empty(track.artist, album_artist),
                    "unknown",
                  ))
                let per_added =
                  option_unwrap(parse_bandcamp_added_at(track.added), "")
                let added_at = case per_added {
                  "" -> album_added_at
                  t -> t
                }
                case
                  core.track_item_strict(
                    "bandcamp",
                    source_id,
                    glentities.decode(track.title),
                    artist,
                    track.title_link,
                    album_cover,
                    added_at,
                    album_genres,
                    track.duration,
                  )
                  |> result.map(fn(item) {
                    core.UnifiedItem(..item, albumid_trackindex: option.Some(ati))
                  })
                {
                  Ok(item) -> [item, ..acc]
                  Error(_) -> acc
                }
              }
            }
          })
          |> list.reverse
      }
    }
  }
}

// Consume characters from `s` (which starts just inside a `[`) and return the
// content before the closing `]` of that outer array. Proper JSON parsing then
// handles the actual nesting; we just need the boundary.
fn take_outer_array(s: String) -> String {
  take_outer_array_loop(string.to_graphemes(s), 1, [])
}

fn take_outer_array_loop(
  chars: List(String),
  depth: Int,
  acc: List(String),
) -> String {
  case chars {
    [] -> string.concat(list.reverse(acc))
    [c, ..rest] ->
      case c {
        "[" | "{" -> take_outer_array_loop(rest, depth + 1, [c, ..acc])
        "]" | "}" ->
          case depth <= 1 {
            True -> string.concat(list.reverse(acc))
            False -> take_outer_array_loop(rest, depth - 1, [c, ..acc])
          }
        _ -> take_outer_array_loop(rest, depth, [c, ..acc])
      }
  }
}

fn parse_entry_items_with_nodes(
  decoded_blob: String,
  feed_kind: String,
) -> #(List(core.UnifiedItem), List(core.AdapterNode)) {
  let segment = entry_items_segment(decoded_blob, feed_kind)
  case segment {
    "" -> #([], [])
    s -> {
      // item_cache is a JSON object; split on "item_id": preserves text order
      // (most recently added first). dict.Dict decoder loses this ordering.
      let parts = string.split(s, "\"item_id\":")
      let #(items, nodes) =
        list.fold(list.drop(parts, 1), #([], []), fn(acc, part) {
          let #(items_acc, nodes_acc) = acc
          let id = string.trim(first_segment(part, ","))
          let item_type = extract_between(part, "\"item_type\":\"", "\"")
          let title = extract_between(part, "\"item_title\":\"", "\"")
          let item_url = decode(extract_between(part, "\"item_url\":\"", "\""))
          case id == "" || item_type == "" || title == "" {
            True -> acc
            False -> {
              let added_raw =
                decode(extract_between(part, "\"added\":\"", "\""))
              let purchased_raw =
                decode(extract_between(part, "\"purchased\":\"", "\""))
              let added_at =
                option_unwrap(
                  parse_bandcamp_added_at(case added_raw {
                    "" -> purchased_raw
                    v -> v
                  }),
                  "",
                )
              let cover = case
                string.trim(decode(extract_between(part, "\"art_url\":\"", "\"")))
              {
                "" -> decode(extract_between(part, "\"item_art_url\":\"", "\""))
                a -> a
              }
              let duration_s =
                float.parse(
                  string.trim(
                    extract_between(part, "\"featured_track_duration\":", ","),
                  ),
                )
                |> option.from_result
              let artist = extract_between(part, "\"band_name\":\"", "\"")
              let is_album = item_type == "album"
              let nodes_acc = case is_album && item_url != "" {
                True -> [
                  core.ListNode(
                    "album|"
                    <> feed_kind
                    <> "|"
                    <> item_url
                    <> "|"
                    <> id
                    <> "|"
                    <> added_at,
                  ),
                  ..nodes_acc
                ]
                False -> nodes_acc
              }
              let items_acc =
                case
                  core.track_item_with_added_at(
                    "bandcamp",
                    id,
                    decode(title),
                    decode(default_if_empty(artist, "unknown")),
                    item_url,
                    cover,
                    added_at,
                    [],
                    duration_s,
                  )
                {
                  Ok(item) ->
                    case is_album {
                      True -> items_acc
                      False -> [item, ..items_acc]
                    }
                  Error(_) -> items_acc
                }
              let nodes_acc = case
                duration_s == None && item_url != "" && !is_album
              {
                True -> [
                  core.ListNode(
                    "duration_probe|" <> item_url <> "|" <> id <> "|" <> added_at,
                  ),
                  ..nodes_acc
                ]
                False -> nodes_acc
              }
              #(items_acc, nodes_acc)
            }
          }
        })
      #(list.reverse(items), list.reverse(nodes))
    }
  }
}

fn entry_items_segment(decoded: String, feed_kind: String) -> String {
  case string.split(decoded, "\"item_cache\":{") {
    [_, tail, ..] -> {
      let open = "\"" <> feed_kind <> "\":{"
      case string.split(tail, open) {
        [_, body, ..] ->
          case feed_kind {
            "wishlist" -> first_segment(body, "},\"gifts_given\":")
            _ -> first_segment(body, "},\"wishlist\":{")
          }
        _ -> ""
      }
    }
    _ -> ""
  }
}

fn default_if_empty(value: String, fallback: String) -> String {
  case value {
    "" -> fallback
    _ -> value
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

