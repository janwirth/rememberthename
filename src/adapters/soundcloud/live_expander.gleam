import gleam/int
import gleam/list
import gleam/string
import adapters/core

// Spec integration:
// - SOUNDCLOUD_SPEC.md source contract: opaque SoundcloudProfile + constructor.
// - adapters.spec.md contract: expand one node into items/lists/next/unresolved.
// - SPEC.md recursion semantics are executed by adapters/core.resolve_profile_url.
@external(erlang, "soundcloud_http", "fetch")
fn fetch_profile_body(url: String) -> String
@external(erlang, "soundcloud_http", "json_next_href")
fn json_next_href(url: String) -> String
@external(erlang, "soundcloud_http", "json_tracks_tsv")
fn json_tracks_tsv(url: String) -> String
@external(erlang, "soundcloud_http", "json_playlist_ids")
fn json_playlist_ids(url: String) -> String
@external(erlang, "soundcloud_http", "json_title")
fn json_title(url: String) -> String
@external(erlang, "soundcloud_http", "json_track_ids")
fn json_track_ids(url: String) -> String

pub opaque type SoundcloudProfile {
  SoundcloudProfile(profile_url: String)
}

pub fn soundcloud_profile(profile_url: String) -> SoundcloudProfile {
  SoundcloudProfile(profile_url: profile_url)
}

pub fn resolve_profile(
  profile: SoundcloudProfile,
  depth: core.DepthMode,
) -> core.ResolveResult {
  // Keep entry point specific: SoundcloudProfile -> profile_url traversal root.
  let SoundcloudProfile(profile_url) = profile
  core.resolve_profile_url(profile_url, depth, expand)
}

pub fn expand(node: core.AdapterNode) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url)
    core.CategoryNode(ctx) -> expand_category(ctx)
    core.ListNode(ctx) -> expand_playlist(ctx)
    core.PageNode(_) ->
      core.ExpandResult(items: [], lists: [], next_nodes: [], unresolved: [])
  }
}

fn expand_profile(profile_url: String) -> core.ExpandResult {
  // Bootstrap from profile HTML, then start category traversal (likes + reposts).
  let html = fetch_profile_body(profile_url)
  let client_id = extract_between(html, "\"id\":\"", "\"")
  let user_id = resolve_user_id(profile_url, client_id)
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
        items: parse_tracks(likes_page, "likes"),
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

fn expand_category(ctx: String) -> core.ExpandResult {
  // Exhaust category pagination first; only then enqueue playlist nodes.
  let parts = string.split(ctx, "|")
  case parts {
    [kind, url, client_id, acc_ids] -> {
      let items = parse_tracks(url, kind)
      let page_playlist_ids = parse_lines(json_playlist_ids(url))
      let merged_playlist_ids = merge_ids(parse_csv(acc_ids), page_playlist_ids)
      let next_href = trim(json_next_href(url))
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

fn expand_playlist(ctx: String) -> core.ExpandResult {
  // Emit only fully-resolved list payloads for playlists.
  let parts = string.split(ctx, "|")
  case parts {
    ["playlist", playlist_id, client_id] -> {
      let url = playlist_url(playlist_id, client_id)
      let title = trim(json_title(url))
      let track_ids = parse_lines(json_track_ids(url))
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
  let html = fetch_profile_body(profile_url)
  let client_id = extract_between(html, "\"id\":\"", "\"")
  let user_id = resolve_user_id(profile_url, client_id)
  case client_id == "" || user_id == "" {
    True -> ""
    False -> fetch_profile_body(likes_start_url(user_id, client_id))
  }
}

fn resolve_user_id(profile_url: String, client_id: String) -> String {
  case client_id == "" {
    True -> ""
    False -> {
      let resolve_url =
        "https://api-v2.soundcloud.com/resolve?url=" <> profile_url <> "&client_id=" <> client_id
      let resolve_json = fetch_profile_body(resolve_url)
      extract_between(resolve_json, "\"urn\":\"soundcloud:users:", "\"")
    }
  }
}

fn parse_tracks(url: String, kind: String) -> List(core.UnifiedItem) {
  let lines = parse_lines(json_tracks_tsv(url))
  list.index_map(lines, fn(line, idx) {
    let cols = string.split(line, "\t")
    let #(id, title, artist) =
      case cols {
        [id, title, artist] -> #(id, title, artist)
        [id, title] -> #(id, title, "unknown")
        [id] -> #(id, "untitled", "unknown")
        _ -> #(kind <> ":" <> int.to_string(idx + 1), "untitled", "unknown")
      }
    core.UnifiedItem(
      id: kind <> ":" <> id,
      title: title,
      artist: artist,
      service: "soundcloud",
      source_type: "item",
      source_id: kind <> ":" <> id,
    )
  })
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
