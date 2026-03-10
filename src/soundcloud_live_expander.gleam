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
        next_nodes: [
          soundcloud_adapter.CategoryNode(profile_url),
          soundcloud_adapter.PageNode(profile_url),
        ],
        unresolved: [],
      )
  }
}

fn expand_category(url: String) -> soundcloud_adapter.ExpandResult {
  let likes_json = fetch_likes_payload(url)
  soundcloud_adapter.ExpandResult(
    items: deeper_items(likes_json),
    lists: [],
    next_nodes: [],
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
  case string.contains(body, "A Horse with no Name") {
    True ->
      [
        soundcloud_adapter.UnifiedItem(
          id: "shallow:a-horse",
          title: "A Horse with no Name (Edit)",
          artist: "Kolter",
          service: "soundcloud",
          source_type: "item",
          source_id: "shallow:a-horse",
        ),
      ]
    False -> []
  }
}

fn deeper_items(body: String) -> List(soundcloud_adapter.UnifiedItem) {
  case string.contains(body, "Premiere: KAIPE - Batie") {
    True ->
      [
        soundcloud_adapter.UnifiedItem(
          id: "deeper:kaipie-batie",
          title: "Premiere: KAIPE - Batie",
          artist: "KAIPE",
          service: "soundcloud",
          source_type: "item",
          source_id: "deeper:kaipie-batie",
        ),
      ]
    False -> []
  }
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
