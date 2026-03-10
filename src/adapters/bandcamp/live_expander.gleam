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
    _ -> core.ExpandResult(items: [], lists: [], next_nodes: [], unresolved: [])
  }
}

fn expand_profile(profile_url: String) -> core.ExpandResult {
  // Bootstrap fan_id and tokens from profile page, then traverse collection/wishlist.
  let html = fetch(profile_url)
  let fan_id = extract_between(html, "&quot;fan_id&quot;:", ",")
  let collection_token = extract_between(html, "&quot;collection_data&quot;:{&quot;redownload_urls&quot;:{},&quot;last_token&quot;:&quot;", "&quot;")
  let wishlist_token = extract_between(html, "&quot;wishlist_data&quot;:{&quot;last_token&quot;:&quot;", "&quot;")

  case fan_id == "" || collection_token == "" || wishlist_token == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
      )
    False -> {
      let collection = fetch_category_page("collection", fan_id, collection_token)
      let wishlist = fetch_category_page("wishlist", fan_id, wishlist_token)
      let core.ExpandResult(c_items, _, c_next, _) = collection
      let core.ExpandResult(w_items, _, w_next, _) = wishlist
      core.ExpandResult(
        items: list.append(c_items, w_items),
        lists: [],
        next_nodes: list.append(c_next, w_next),
        unresolved: [],
      )
    }
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
  let items = parse_items(json, kind)
  let next = extract_between(json, "\"last_token\":\"", "\"")
  let more = string.contains(json, "\"more_available\":true")

  let next_nodes =
    case more && next != "" {
      True -> [core.CategoryNode(kind <> "|" <> fan_id <> "|" <> next)]
      False -> []
    }

  core.ExpandResult(
    items: items,
    lists: [],
    next_nodes: next_nodes,
    unresolved: [],
  )
}

fn parse_items(json: String, kind: String) -> List(core.UnifiedItem) {
  let parts = string.split(json, "\"item_id\":")
  case parts {
    [] -> []
    [_, ..rest] -> parse_item_parts(rest, kind, [])
  }
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
