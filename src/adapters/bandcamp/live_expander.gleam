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
//// - Lists are not emitted by current Bandcamp implementation.
////
//// Test coverage:
//// - `test/bandcamp_adapter_test.gleam`
import gleam/int
import gleam/list
import gleam/string
import adapters/core

// Spec integration:
// - BANDCAMP_SPEC.md source contract: opaque BandcampProfile + constructor.
// - adapters.spec.md contract: one-node expansion into items/lists/next/unresolved.
// - SPEC.md recursion/dedupe behavior is delegated to adapters/core.
@external(erlang, "soundcloud_http", "fetch")
fn fetch(url: String) -> String
@external(erlang, "soundcloud_http", "post_json")
fn post_json(url: String, body: String) -> String

pub opaque type BandcampProfile {
  BandcampProfile(profile_url: String)
}

pub fn bandcamp_profile(profile_url: String) -> BandcampProfile {
  BandcampProfile(profile_url: profile_url)
}

pub fn resolve_profile(
  profile: BandcampProfile,
  depth: core.DepthMode,
) -> core.ResolveResult {
  // Keep entry point specific: BandcampProfile -> profile_url traversal root.
  let BandcampProfile(profile_url) = profile
  core.resolve_profile_url(profile_url, depth, expand)
}

pub fn expand(node: core.AdapterNode) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url)
    core.CategoryNode(ctx) -> expand_category(ctx)
    core.ListNode(ctx) -> expand_album(ctx)
    _ -> core.ExpandResult(items: [], lists: [], next_nodes: [], unresolved: [])
  }
}

fn expand_profile(profile_url: String) -> core.ExpandResult {
  // Depth-1 should come from profile entry payload, then API starts at deeper levels.
  let html = fetch(profile_url)
  let entry_items = parse_entry_items(html)
  let fan_id = extract_between(html, "&quot;fan_id&quot;:", ",")
  let collection_token = extract_between(html, "&quot;collection_data&quot;:{&quot;redownload_urls&quot;:{},&quot;last_token&quot;:&quot;", "&quot;")
  let wishlist_token = extract_between(html, "&quot;wishlist_data&quot;:{&quot;last_token&quot;:&quot;", "&quot;")

  case fan_id == "" || collection_token == "" || wishlist_token == "" {
    True ->
      core.ExpandResult(
        items: entry_items,
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
      )
    False ->
      core.ExpandResult(
        items: entry_items,
        lists: [],
        next_nodes: [
          core.CategoryNode("collection" <> "|" <> fan_id <> "|" <> collection_token),
          core.CategoryNode("wishlist" <> "|" <> fan_id <> "|" <> wishlist_token),
        ],
        unresolved: [],
      )
  }
}

fn expand_category(ctx: String) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    [kind, fan_id, token] -> fetch_category_page(kind, fan_id, token)
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.CategoryNode(ctx)],
      )
  }
}

fn fetch_category_page(kind: String, fan_id: String, token: String) -> core.ExpandResult {
  // Pagination follows Bandcamp API `more_available` + `last_token`.
  let endpoint =
    case kind {
      "collection" -> "https://bandcamp.com/api/fancollection/1/collection_items"
      _ -> "https://bandcamp.com/api/fancollection/1/wishlist_items"
    }

  let body =
    "{\"fan_id\":"
    <> fan_id
    <> ",\"older_than_token\":\""
    <> token
    <> "\",\"count\":50}"

  let json = post_json(endpoint, body)
  let #(page_items, album_nodes) = parse_category_payload(json, kind)
  let items = list.append(page_items, parse_tracklist_items(json, kind))
  let next = extract_between(json, "\"last_token\":\"", "\"")
  let more = string.contains(json, "\"more_available\":true")

  let page_nodes =
    case more && next != "" {
      True -> [core.CategoryNode(kind <> "|" <> fan_id <> "|" <> next)]
      False -> []
    }
  let next_nodes = list.append(page_nodes, album_nodes)

  core.ExpandResult(
    items: items,
    lists: [],
    next_nodes: next_nodes,
    unresolved: [],
  )
}

fn expand_album(ctx: String) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["album", album_url, album_id] -> {
      let html = fetch(album_url)
      core.ExpandResult(
        items: parse_album_tracks(html, album_id),
        lists: [],
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

fn parse_items(json: String, kind: String) -> List(core.UnifiedItem) {
  let parts = string.split(json, "\"item_id\":")
  case parts {
    [] -> []
    [_, ..rest] -> parse_item_parts(rest, kind, [])
  }
}

fn parse_category_payload(
  json: String,
  kind: String,
) -> #(List(core.UnifiedItem), List(core.AdapterNode)) {
  let parts = string.split(json, "\"item_id\":")
  case parts {
    [] -> #([], [])
    [_, ..rest] -> parse_item_parts_with_album_nodes(rest, kind, [], [], 0)
  }
}

fn parse_item_parts_with_album_nodes(
  parts: List(String),
  kind: String,
  items_acc: List(core.UnifiedItem),
  nodes_acc: List(core.AdapterNode),
  album_nodes_added: Int,
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
        True -> parse_item_parts_with_album_nodes(rest, kind, items_acc, nodes_acc, album_nodes_added)
        False -> {
          let source = kind <> ":" <> item_type <> ":" <> id
          let item =
            core.UnifiedItem(
              id: source,
              title: decode(title),
              artist: decode(default_if_empty(artist, "unknown")),
              service: "bandcamp",
              source_type: "item",
              source_id: source,
            )
          let #(nodes_acc, album_nodes_added) =
            case item_type == "album" && item_url != "" && album_nodes_added < 2 {
              True ->
                #(
                  [core.ListNode("album|" <> item_url <> "|" <> id), ..nodes_acc],
                  album_nodes_added + 1,
                )
              False -> #(nodes_acc, album_nodes_added)
            }
          parse_item_parts_with_album_nodes(
            rest,
            kind,
            [item, ..items_acc],
            nodes_acc,
            album_nodes_added,
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
  kind: String,
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  let parts = string.split(tracklists_segment, "\"id\":")
  case parts {
    [] -> []
    [_, ..rest] -> parse_track_id_parts(rest, kind, acc)
  }
}

fn parse_track_id_parts(
  parts: List(String),
  kind: String,
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] -> {
      let track_id = first_segment(part, ",")
      let title = extract_between(part, "\"title\":\"", "\"")
      let artist = extract_between(part, "\"artist\":\"", "\"")
      case track_id == "" || title == "" {
        True -> parse_track_id_parts(rest, kind, acc)
        False -> {
          let source = kind <> ":album_track:" <> track_id
          let item =
            core.UnifiedItem(
              id: source,
              title: decode(title),
              artist: decode(default_if_empty(artist, "unknown")),
              service: "bandcamp",
              source_type: "item",
              source_id: source,
            )
          parse_track_id_parts(rest, kind, [item, ..acc])
        }
      }
    }
  }
}

fn parse_album_tracks(html: String, album_id: String) -> List(core.UnifiedItem) {
  let decoded = string.replace(html, "&quot;", "\"")
  let trackinfo_split = string.split(decoded, "\"trackinfo\":")
  case trackinfo_split {
    [_, tail, ..] ->
      tail
      |> first_segment("],")
      |> parse_album_track_parts(album_id)
    _ -> []
  }
}

fn parse_album_track_parts(segment: String, album_id: String) -> List(core.UnifiedItem) {
  let parts = string.split(segment, "\"title\":\"")
  case parts {
    [] -> []
    [_, ..rest] -> parse_album_track_titles(rest, album_id, 0, [])
  }
}

fn parse_album_track_titles(
  parts: List(String),
  album_id: String,
  index: Int,
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] -> {
      let title = decode(first_segment(part, "\""))
      let track_id = first_segment(extract_between(part, "\"track_id\":", ","), ",")
      let artist = decode(default_if_empty(extract_between(part, "\"artist\":\"", "\""), "unknown"))
      case title == "" {
        True -> parse_album_track_titles(rest, album_id, index + 1, acc)
        False -> {
          let source_id =
            case track_id {
              "" -> "album_track:" <> album_id <> ":" <> int.to_string(index)
              _ -> "album_track:" <> album_id <> ":" <> track_id
            }
          let item =
            core.UnifiedItem(
              id: source_id,
              title: title,
              artist: artist,
              service: "bandcamp",
              source_type: "item",
              source_id: source_id,
            )
          parse_album_track_titles(rest, album_id, index + 1, [item, ..acc])
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
  kind: String,
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  case parts {
    [] -> list.reverse(acc)
    [part, ..rest] -> {
      let id = first_segment(part, ",")
      let item_type = extract_between(part, "\"item_type\":\"", "\"")
      let title = extract_between(part, "\"item_title\":\"", "\"")
      let artist = extract_between(part, "\"band_name\":\"", "\"")
      case id == "" || item_type == "" || title == "" {
        True -> parse_item_parts(rest, kind, acc)
        False -> {
          let source = kind <> ":" <> item_type <> ":" <> id
          let item =
            core.UnifiedItem(
              id: source,
              title: decode(title),
              artist: decode(default_if_empty(artist, "unknown")),
              service: "bandcamp",
              source_type: "item",
              source_id: source,
            )
          parse_item_parts(rest, kind, [item, ..acc])
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
