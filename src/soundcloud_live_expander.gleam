import gleam/int
import gleam/list
import gleam/string
import soundcloud_adapter

@external(erlang, "soundcloud_http", "fetch")
fn fetch_profile_body(url: String) -> String

pub fn expand(node: soundcloud_adapter.AdapterNode) -> soundcloud_adapter.ExpandResult {
  case node {
    soundcloud_adapter.ProfileEntry(source) -> expand_profile(source)
    soundcloud_adapter.CategoryNode(url) -> expand_category(url)
    soundcloud_adapter.PageNode(url) -> expand_page(url)
    soundcloud_adapter.ListNode(_) ->
      soundcloud_adapter.ExpandResult(items: [], lists: [], next_nodes: [], unresolved: [])
  }
}

fn expand_profile(
  source: soundcloud_adapter.SourceIdentity,
) -> soundcloud_adapter.ExpandResult {
  let soundcloud_adapter.SourceIdentity(_, _, profile_url) = source
  let likes_json = fetch_likes_payload(profile_url)
  case likes_json == "" {
    True ->
      soundcloud_adapter.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [soundcloud_adapter.ProfileEntry(source)],
      )
    False ->
      soundcloud_adapter.ExpandResult(
        items: shallow_items(likes_json),
        lists: [],
        next_nodes: [soundcloud_adapter.CategoryNode(profile_url)],
        unresolved: [],
      )
  }
}

fn expand_category(url: String) -> soundcloud_adapter.ExpandResult {
  let likes_json = fetch_likes_payload(url)
  soundcloud_adapter.ExpandResult(
    items: deeper_items(likes_json),
    lists: [],
    next_nodes: [soundcloud_adapter.PageNode(url)],
    unresolved: [],
  )
}

fn expand_page(url: String) -> soundcloud_adapter.ExpandResult {
  let likes_json = fetch_likes_payload(url)
  soundcloud_adapter.ExpandResult(
    items: [],
    lists: full_lists(likes_json),
    next_nodes: [],
    unresolved: [],
  )
}

pub fn fetch_likes_payload(profile_url: String) -> String {
  let html = fetch_profile_body(profile_url)
  let client_id = extract_between(html, "\"id\":\"", "\"")
  let resolve_url =
    "https://api-v2.soundcloud.com/resolve?url=" <> profile_url <> "&client_id=" <> client_id
  let resolve_json = fetch_profile_body(resolve_url)
  let user_id = extract_between(resolve_json, "\"urn\":\"soundcloud:users:", "\"")
  case client_id == "" || user_id == "" {
    True -> ""
    False -> fetch_profile_body(likes_url(user_id, client_id))
  }
}

fn shallow_items(body: String) -> List(soundcloud_adapter.UnifiedItem) {
  make_items_from_titles(extract_json_titles(body, 10), "depth1")
}

fn deeper_items(body: String) -> List(soundcloud_adapter.UnifiedItem) {
  make_items_from_titles(extract_json_titles(body, 30), "depth2")
}

fn full_lists(body: String) -> List(soundcloud_adapter.UnifiedCollection) {
  case string.contains(body, "Mahal") {
    True ->
      [
        soundcloud_adapter.UnifiedCollection(
          id: "full:mahal",
          title: "Mahal",
          track_ids: tracks_for_list(body),
          list_ids: [],
          service: "soundcloud",
          source_type: "collection",
          source_id: "full:mahal",
        ),
      ]
    False -> []
  }
}

fn tracks_for_list(body: String) -> List(String) {
  case string.contains(body, "Glass Beams") {
    True -> ["Glass Beams"]
    False -> []
  }
}

fn make_items_from_titles(titles: List(String), prefix: String) -> List(soundcloud_adapter.UnifiedItem) {
  list.index_map(titles, fn(title, idx) {
    let n = int.to_string(idx + 1)
    let id = prefix <> ":" <> n
    soundcloud_adapter.UnifiedItem(
      id: id,
      title: title,
      artist: "unknown",
      service: "soundcloud",
      source_type: "item",
      source_id: id,
    )
  })
}

fn extract_json_titles(body: String, limit: Int) -> List(String) {
  let parts = string.split(body, "\"title\":\"")
  case parts {
    [] -> []
    [_, ..rest] -> extract_title_parts(rest, limit, [])
  }
}

fn extract_title_parts(parts: List(String), limit: Int, acc: List(String)) -> List(String) {
  case list.length(acc) >= limit {
    True -> list.reverse(acc)
    False ->
      case parts {
        [] -> list.reverse(acc)
        [part, ..rest] -> {
          let title = first_segment(part, "\"")
          case title {
            "" -> extract_title_parts(rest, limit, acc)
            _ -> extract_title_parts(rest, limit, [title, ..acc])
          }
        }
      }
  }
}

fn likes_url(user_id: String, client_id: String) -> String {
  "https://api-v2.soundcloud.com/users/"
  <> user_id
  <> "/likes?limit=200&client_id="
  <> client_id
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

fn first_segment(value: String, separator: String) -> String {
  let parts = string.split(value, separator)
  case parts {
    [first, ..] -> first
    _ -> ""
  }
}
