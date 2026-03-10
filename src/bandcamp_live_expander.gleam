import gleam/int
import gleam/list
import gleam/string
import soundcloud_adapter

@external(erlang, "soundcloud_http", "fetch")
fn fetch(url: String) -> String
@external(erlang, "soundcloud_http", "post_json")
fn post_json(url: String, body: String) -> String

pub fn expand(node: soundcloud_adapter.AdapterNode) -> soundcloud_adapter.ExpandResult {
  case node {
    soundcloud_adapter.ProfileEntry(source) -> expand_profile(source)
    soundcloud_adapter.CategoryNode(ctx) -> expand_category(ctx)
    _ -> soundcloud_adapter.ExpandResult(items: [], lists: [], next_nodes: [], unresolved: [])
  }
}

fn expand_profile(source: soundcloud_adapter.SourceIdentity) -> soundcloud_adapter.ExpandResult {
  let soundcloud_adapter.SourceIdentity(_, _, profile_url) = source
  let html = fetch(profile_url)
  let fan_id = extract_between(html, "&quot;fan_id&quot;:", ",")
  let collection_token = extract_between(html, "&quot;collection_data&quot;:{&quot;redownload_urls&quot;:{},&quot;last_token&quot;:&quot;", "&quot;")
  let wishlist_token = extract_between(html, "&quot;wishlist_data&quot;:{&quot;last_token&quot;:&quot;", "&quot;")

  case fan_id == "" || collection_token == "" || wishlist_token == "" {
    True ->
      soundcloud_adapter.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [soundcloud_adapter.ProfileEntry(source)],
      )
    False -> {
      let collection = fetch_category_page("collection", fan_id, collection_token)
      let wishlist = fetch_category_page("wishlist", fan_id, wishlist_token)
      let soundcloud_adapter.ExpandResult(c_items, _, c_next, _) = collection
      let soundcloud_adapter.ExpandResult(w_items, _, w_next, _) = wishlist
      soundcloud_adapter.ExpandResult(
        items: list.append(c_items, w_items),
        lists: [],
        next_nodes: list.append(c_next, w_next),
        unresolved: [],
      )
    }
  }
}

fn expand_category(ctx: String) -> soundcloud_adapter.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    [kind, fan_id, token] -> fetch_category_page(kind, fan_id, token)
    _ ->
      soundcloud_adapter.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [soundcloud_adapter.CategoryNode(ctx)],
      )
  }
}

fn fetch_category_page(kind: String, fan_id: String, token: String) -> soundcloud_adapter.ExpandResult {
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
      True -> [soundcloud_adapter.CategoryNode(kind <> "|" <> fan_id <> "|" <> next)]
      False -> []
    }

  soundcloud_adapter.ExpandResult(
    items: items,
    lists: [],
    next_nodes: next_nodes,
    unresolved: [],
  )
}

fn parse_items(json: String, kind: String) -> List(soundcloud_adapter.UnifiedItem) {
  let parts = string.split(json, "\"item_id\":")
  case parts {
    [] -> []
    [_, ..rest] -> parse_item_parts(rest, kind, [])
  }
}

fn parse_item_parts(
  parts: List(String),
  kind: String,
  acc: List(soundcloud_adapter.UnifiedItem),
) -> List(soundcloud_adapter.UnifiedItem) {
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
            soundcloud_adapter.UnifiedItem(
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
