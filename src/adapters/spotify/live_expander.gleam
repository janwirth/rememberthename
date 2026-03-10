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
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import dot_env as dot
import dot_env/env
import simplifile
import adapters/cache
import adapters/core

@external(erlang, "spotify_http", "liked_tracks_json")
fn liked_tracks_json(token: String, offset: Int) -> String

@external(erlang, "spotify_http", "tracks_tsv")
fn tracks_tsv(json: String) -> String

pub fn read_access_token_file(session_file: String) -> String {
  case simplifile.read(from: session_file) {
    Ok(body) ->
      case string.trim(extract_access_token(body)) {
        "" -> string.trim(body)
        token -> token
      }
    Error(_) -> ""
  }
}

pub fn read_env_value(file_path: String, key: String) -> String {
  let _ = dot.new() |> dot.set_path(file_path) |> dot.set_debug(False) |> dot.load
  env.get_string_or(key, "")
}

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
  use_cache: Bool,
) -> core.ResolveResult {
  resolve_profile_with_debug(profile, depth, config, use_cache, fn(_) { Nil })
}

pub fn resolve_profile_with_debug(
  profile: SpotifyUserProfile,
  depth: core.DepthMode,
  config: SpotifyConfig,
  use_cache: Bool,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let SpotifyUserProfile(profile_url) = profile
  core.resolve_profile_url_with_debug(
    profile_url,
    depth,
    fn(node) { expand(node, config, use_cache) },
    on_debug,
  )
}

pub fn expand(
  node: core.AdapterNode,
  config: SpotifyConfig,
  use_cache: Bool,
) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url, config, use_cache)
    core.CategoryNode(ctx) -> expand_playlists(ctx)
    core.ListNode(ctx) -> expand_playlist_tracks(ctx, use_cache)
    core.PageNode(ctx) -> expand_track_page(ctx, use_cache)
  }
}

fn expand_profile(
  profile_url: String,
  config: SpotifyConfig,
  use_cache: Bool,
) -> core.ExpandResult {
  let user_id = parse_user_id(profile_url)
  let SpotifyConfig(access_token, session_file, client_id, redirect_uri, scopes) = config
  let token =
    resolve_access_token(access_token, session_file, client_id, redirect_uri, scopes)
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
      emit_liked_tracks(token, 0, use_cache)
  }
}

fn resolve_access_token(
  provided_token: String,
  session_file: String,
  client_id: String,
  redirect_uri: String,
  scopes: String,
) -> String {
  let provided = string.trim(provided_token)
  case provided != "" {
    True -> provided
    False -> {
      let file_token = read_access_token_file(session_file) |> string.trim
      case file_token != "" {
        True -> file_token
        False -> {
          log_oauth_flow(session_file, client_id, redirect_uri, scopes)
          ""
        }
      }
    }
  }
}

fn log_oauth_flow(
  session_file: String,
  client_id: String,
  redirect_uri: String,
  scopes: String,
) {
  let auth_url =
    "https://accounts.spotify.com/authorize?client_id="
    <> client_id
    <> "&response_type=code&redirect_uri="
    <> redirect_uri
    <> "&scope="
    <> scopes
    <> "&show_dialog=true"
  io.println("")
  io.println("[spotify-oauth] No session found at " <> session_file)
  io.println("[spotify-oauth] Open this URL and authorize:")
  io.println(auth_url)
  io.println("[spotify-oauth] Save token JSON into " <> session_file)
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

fn expand_playlist_tracks(ctx: String, use_cache: Bool) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes", token, offset_str] ->
      emit_liked_tracks(token, to_int(offset_str), use_cache)
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ListNode(ctx)],
      )
  }
}

fn expand_track_page(ctx: String, use_cache: Bool) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes_page", token, offset_str] ->
      emit_liked_tracks(token, to_int(offset_str), use_cache)
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
  use_cache: Bool,
) -> core.ExpandResult {
  let json = cached_liked_tracks_json(token, offset, use_cache)
  let items = parse_track_items(cached_tracks_tsv(json, use_cache))
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
  let next_offset = tracks_next_offset(json)
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

fn cached_liked_tracks_json(token: String, offset: Int, use_cache: Bool) -> String {
  cache.read_or_fetch(
    "spotify_liked_tracks_json",
    token <> "|" <> int.to_string(offset),
    use_cache,
    fn() { liked_tracks_json(token, offset) },
  )
}

fn cached_tracks_tsv(json: String, use_cache: Bool) -> String {
  cache.read_or_fetch(
    "spotify_tracks_tsv",
    json,
    use_cache,
    fn() { tracks_tsv(json) },
  )
}

fn parse_track_items(json: String) -> List(core.UnifiedItem) {
  parse_lines(json)
  |> list.filter_map(fn(chunk) {
    let cols = string.split(chunk, "\t")
    let track_id =
      case cols {
        [id, _, _] -> id
        _ -> ""
      }
    let title =
      case cols {
        [_, t, _] -> t
        _ -> ""
      }
    let artist_name =
      case cols {
        [_, _, a] -> a
        _ -> "unknown"
      }
    case track_id == "" {
      True -> Error(Nil)
      False ->
        Ok(
          core.UnifiedItem(
            id: "spotify:item:" <> track_id,
            title: normalize(title),
            artist: normalize(default_if_empty(artist_name, "unknown")),
            service: "spotify",
            source_type: "item",
            source_id: "spotify:item:" <> track_id,
          ),
        )
    }
  })
}

fn tracks_next_offset(json: String) -> String {
  let has_next =
    !string.contains(json, "\"next\":null")
    && !string.contains(json, "\"next\": null")
  case has_next {
    False -> ""
    True -> {
      let offset = extract_number_after(json, "\"offset\":")
      let limit = extract_number_after(json, "\"limit\":")
      int.to_string(offset + limit)
    }
  }
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

fn extract_access_token(body: String) -> String {
  let compact = string.replace(body, " ", "")
  let exact = extract_between(compact, "\"access_token\":\"", "\"")
  case exact {
    "" -> extract_between(body, "\"access_token\":\"", "\"")
    token -> token
  }
}

fn extract_between(body: String, start: String, ending: String) -> String {
  case string.split(body, start) {
    [_, tail, ..] ->
      case string.split(tail, ending) {
        [value, ..] -> value
        _ -> ""
      }
    _ -> ""
  }
}


fn extract_number_after(body: String, needle: String) -> Int {
  case string.split_once(body, needle) {
    Ok(#(_, after)) -> {
      let digits = leading_digits(string.to_graphemes(string.trim_start(after)), [])
      case digits {
        [] -> 0
        _ ->
          digits
          |> list.reverse
          |> string.join("")
          |> to_int
      }
    }
    Error(_) -> 0
  }
}

fn leading_digits(chars: List(String), acc: List(String)) -> List(String) {
  case chars {
    [] -> acc
    [char, ..rest] ->
      case is_ascii_digit(char) {
        True -> leading_digits(rest, [char, ..acc])
        False -> acc
      }
  }
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

