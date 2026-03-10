//// Spotify adapter documentation (merged from `SPOTIFY_SPEC.md`)
////
//// Scope and root inputs:
//// - Supports authenticated Spotify likes traversal via profile entry roots.
//// - Runtime target is the user-scoped liked tracks feed (`/v1/me/tracks`).
////
//// Auth/API contract:
//// - OAuth bearer token is required.
//// - Token resolution order: provided token -> session file -> OAuth guidance.
//// - Missing/invalid auth resolves to unresolved profile nodes (no process crash).
////
//// Intermediary mapping:
//// - Each fetched page is normalized into `UnifiedItem` values with canonical ids:
////   `spotify:item:<track_id>`.
//// - Liked tracks are emitted as collection:
////   `spotify:collection:likes` ("Liked Songs").
//// - Item and collection identity follow canonical `service/source_type/source_id`
////   conventions from the shared adapter spec.
////
//// Depth semantics in this adapter:
//// - Depth1: first page of `/v1/me/tracks` (limit=50), plus collection shell.
//// - DepthN: follows `next` pagination offsets page-by-page up to depth budget.
//// - DepthAll: exhausts all reachable liked-tracks pages.
////
//// Ordering and dedup:
//// - Preserves Spotify API order within each page.
//// - Preserves traversal order across pages.
//// - Deduplication is handled by the core resolver using canonical item identity.
////
//// Notes:
//// - This implementation currently focuses on liked tracks.
//// - Saved albums and album-track expansion are not implemented in this module.
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import adapters/core

@external(erlang, "spotify_http", "read_access_token_file")
pub fn read_access_token_file(session_file: String) -> String

@external(erlang, "spotify_http", "read_env_value")
pub fn read_env_value(file_path: String, key: String) -> String

@external(erlang, "spotify_http", "ensure_access_token")
fn ensure_access_token(
  provided_token: String,
  session_file: String,
  client_id: String,
  redirect_uri: String,
  scopes: String,
) -> String

@external(erlang, "spotify_http", "liked_tracks_json")
fn liked_tracks_json(token: String, offset: Int) -> String

@external(erlang, "spotify_http", "tracks_tsv")
fn tracks_tsv(json: String) -> String

@external(erlang, "spotify_http", "tracks_next_offset")
fn tracks_next_offset(json: String) -> String

pub opaque type SpotifyUserProfile {
  SpotifyUserProfile(profile_url: String)
}

pub type SpotifyConfig {
  SpotifyConfig(
    access_token: String,
    session_file: String,
    client_id: String,
    redirect_uri: String,
    scopes: String,
  )
}

pub fn spotify_user(profile_url: String) -> SpotifyUserProfile {
  SpotifyUserProfile(profile_url: profile_url)
}

pub fn spotify_config(
  access_token access_token: String,
  session_file session_file: String,
  client_id client_id: String,
  redirect_uri redirect_uri: String,
  scopes scopes: String,
) -> SpotifyConfig {
  SpotifyConfig(
    access_token: access_token,
    session_file: session_file,
    client_id: client_id,
    redirect_uri: redirect_uri,
    scopes: scopes,
  )
}

pub fn resolve_profile(
  profile: SpotifyUserProfile,
  depth: core.DepthMode,
  config: SpotifyConfig,
) -> core.ResolveResult {
  let SpotifyUserProfile(profile_url) = profile
  core.resolve_profile_url(profile_url, depth, fn(node) { expand(node, config) })
}

pub fn expand(node: core.AdapterNode, config: SpotifyConfig) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url, config)
    core.CategoryNode(ctx) -> expand_playlists(ctx)
    core.ListNode(ctx) -> expand_playlist_tracks(ctx)
    core.PageNode(ctx) -> expand_track_page(ctx)
  }
}

fn expand_profile(profile_url: String, config: SpotifyConfig) -> core.ExpandResult {
  let user_id = parse_user_id(profile_url)
  let SpotifyConfig(access_token, session_file, client_id, redirect_uri, scopes) = config
  let token =
    ensure_access_token(access_token, session_file, client_id, redirect_uri, scopes)
    |> string.trim
  case user_id == "" || token == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
      )
    False ->
      emit_liked_tracks(token, 0)
  }
}

fn expand_playlists(ctx: String) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes", token, offset_str] -> {
      let offset = to_int(offset_str)
      let next_nodes = [core.ListNode("likes|" <> token <> "|" <> int.to_string(offset))]
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: next_nodes,
        unresolved: [],
      )
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

fn expand_playlist_tracks(ctx: String) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes", token, offset_str] ->
      emit_liked_tracks(token, to_int(offset_str))
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ListNode(ctx)],
      )
  }
}

fn expand_track_page(ctx: String) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes_page", token, offset_str] ->
      emit_liked_tracks(token, to_int(offset_str))
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.PageNode(ctx)],
      )
  }
}

fn emit_liked_tracks(
  token: String,
  offset: Int,
) -> core.ExpandResult {
  let json = liked_tracks_json(token, offset)
  let items = parse_track_items(tracks_tsv(json))
  let collection =
    core.UnifiedCollection(
      id: "spotify:collection:likes",
      title: "Liked Songs",
      track_ids:
        list.map(items, fn(item) {
          let core.UnifiedItem(id, _, _, _, _, _) = item
          id
        }),
      list_ids: [],
      service: "spotify",
      source_type: "collection",
      source_id: "spotify:collection:likes",
    )
  let next_offset = string.trim(tracks_next_offset(json))
  let next_nodes =
    case next_offset != "" {
      True -> [core.PageNode("likes_page|" <> token <> "|" <> next_offset)]
      False -> []
    }
  core.ExpandResult(
    items: items,
    lists: [collection],
    next_nodes: next_nodes,
    unresolved: [],
  )
}

fn parse_track_items(raw: String) -> List(core.UnifiedItem) {
  parse_lines(raw)
  |> list.filter_map(fn(line) {
    let cols = string.split(line, "\t")
    case cols {
      [track_id, title, artist] if track_id != "" ->
        Ok(
          core.UnifiedItem(
            id: "spotify:item:" <> track_id,
            title: normalize(title),
            artist: normalize(default_if_empty(artist, "unknown")),
            service: "spotify",
            source_type: "item",
            source_id: "spotify:item:" <> track_id,
          ),
        )
      _ -> Error(Nil)
    }
  })
}

fn parse_lines(raw: String) -> List(String) {
  let value = string.trim(raw)
  case value {
    "" -> []
    _ -> list.filter(string.split(value, "\n"), fn(line) { line != "" })
  }
}

fn parse_user_id(url: String) -> String {
  case string.split_once(url, "/user/") {
    Ok(#(_, after)) ->
      case string.split_once(after, "?") {
        Ok(#(id, _)) -> id
        Error(_) ->
          case string.split_once(after, "/") {
            Ok(#(id, _)) -> id
            Error(_) -> string.trim(after)
          }
      }
    Error(_) -> ""
  }
}

fn to_int(value: String) -> Int {
  int.parse(value) |> result.unwrap(or: 0)
}

fn default_if_empty(value: String, fallback: String) -> String {
  case value == "" {
    True -> fallback
    False -> value
  }
}

fn normalize(value: String) -> String {
  value
  |> string.trim
  |> string.replace("\n", " ")
  |> string.replace("  ", " ")
}
