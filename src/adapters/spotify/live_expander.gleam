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
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import dot_env as dot
import dot_env/env
import simplifile
import adapters/cache
import adapters/core

fn liked_tracks_json(token: String, offset: Int) -> String {
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("api.spotify.com")
    |> request.set_method(http.Get)
    |> request.set_path("/v1/me/tracks")
    |> request.set_query([
      #("limit", "50"),
      #("offset", int.to_string(offset)),
    ])
    |> request.set_header("authorization", "Bearer " <> token)

  case hackney.send(req) {
    Ok(res) -> res.body
    Error(_) -> ""
  }
}

fn tracks_tsv(json_body: String) -> String {
  let parsed = decode_json(json_body, decode.dynamic) |> result.unwrap(dynamic.nil())
  let items = decode_path_or(parsed, ["items"], [], decode.list(of: decode.dynamic))
  collect_tracks_tsv(items, [])
  |> string.join("\n")
}

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
    client_secret: String,
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
  client_secret client_secret: String,
  redirect_uri redirect_uri: String,
  scopes scopes: String,
) -> SpotifyConfig {
  SpotifyConfig(
    access_token: access_token,
    session_file: session_file,
    client_id: client_id,
    client_secret: client_secret,
    redirect_uri: redirect_uri,
    scopes: scopes,
  )
}

pub fn resolve_profile(
  profile: SpotifyUserProfile,
  depth: core.DepthMode,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
) -> core.ResolveResult {
  resolve_profile_with_debug(profile, depth, config, cache_mode, fn(_) { Nil })
}

pub fn resolve_profile_with_debug(
  profile: SpotifyUserProfile,
  depth: core.DepthMode,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let SpotifyUserProfile(profile_url) = profile
  core.resolve_profile_url_with_debug(
    profile_url,
    depth,
    fn(node) { expand(node, config, cache_mode) },
    on_debug,
  )
}

pub fn expand(
  node: core.AdapterNode,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) -> expand_profile(profile_url, config, cache_mode)
    core.CategoryNode(ctx) -> expand_playlists(ctx)
    core.ListNode(ctx) -> expand_playlist_tracks(ctx, cache_mode)
    core.PageNode(ctx) -> expand_track_page(ctx, cache_mode)
  }
}

fn expand_profile(
  profile_url: String,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let user_id = parse_user_id(profile_url)
  let SpotifyConfig(
    access_token,
    session_file,
    client_id,
    client_secret,
    redirect_uri,
    scopes,
  ) = config
  let token =
    resolve_access_token(
      access_token,
      session_file,
      client_id,
      client_secret,
      redirect_uri,
      scopes,
    )
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
      emit_liked_tracks(token, 0, cache_mode)
  }
}

fn resolve_access_token(
  provided_token: String,
  session_file: String,
  client_id: String,
  client_secret: String,
  redirect_uri: String,
  scopes: String,
) -> String {
  let refresh_token = read_refresh_token_file(session_file) |> string.trim
  let refreshed =
    case refresh_token != "" && client_id != "" && client_secret != "" {
      True -> refresh_access_token(refresh_token, client_id, client_secret)
      False -> ""
    }
    |> string.trim
  case refreshed != "" {
    True -> refreshed
    False -> {
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
  }
}

fn read_refresh_token_file(session_file: String) -> String {
  case simplifile.read(from: session_file) {
    Ok(body) -> string.trim(extract_refresh_token(body))
    Error(_) -> ""
  }
}

fn refresh_access_token(
  refresh_token: String,
  client_id: String,
  client_secret: String,
) -> String {
  let body =
    "grant_type=refresh_token&refresh_token="
    <> refresh_token
    <> "&client_id="
    <> client_id
    <> "&client_secret="
    <> client_secret
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("accounts.spotify.com")
    |> request.set_method(http.Post)
    |> request.set_path("/api/token")
    |> request.set_header("content-type", "application/x-www-form-urlencoded")
    |> request.set_body(body)
  case hackney.send(req) {
    Ok(res) -> string.trim(extract_access_token(res.body))
    Error(_) -> ""
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

fn expand_playlist_tracks(ctx: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes", token, offset_str] ->
      emit_liked_tracks(token, to_int(offset_str), cache_mode)
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ListNode(ctx)],
      )
  }
}

fn expand_track_page(ctx: String, cache_mode: cache.CacheMode) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes_page", token, offset_str] ->
      emit_liked_tracks(token, to_int(offset_str), cache_mode)
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
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let json = cached_liked_tracks_json(token, offset, cache_mode)
  let items = parse_track_items(cached_tracks_tsv(json, cache_mode))
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

fn cached_liked_tracks_json(
  token: String,
  offset: Int,
  cache_mode: cache.CacheMode,
) -> String {
  cache.read_or_fetch(
    "spotify_liked_tracks_json",
    token <> "|" <> int.to_string(offset),
    cache_mode,
    fn() { liked_tracks_json(token, offset) },
  )
}

fn cached_tracks_tsv(json: String, cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "spotify_tracks_tsv",
    json,
    cache_mode,
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

fn decode_json(
  raw: String,
  decoder: decode.Decoder(a),
) -> Result(a, json.DecodeError) {
  json.parse(raw, decoder)
}

fn decode_path(
  data: dynamic.Dynamic,
  path: List(b),
  decoder: decode.Decoder(a),
) -> Option(a) {
  case decode.run(data, decode.at(path, decoder)) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn decode_path_or(
  data: dynamic.Dynamic,
  path: List(b),
  fallback: a,
  decoder: decode.Decoder(a),
) -> a {
  decode.run(data, decode.optionally_at(path, fallback, decoder))
  |> result.unwrap(fallback)
}

fn collect_tracks_tsv(
  items: List(dynamic.Dynamic),
  acc: List(String),
) -> List(String) {
  case items {
    [] -> list.reverse(acc)
    [item, ..rest] ->
      case spotify_track_tsv(item) {
        Some(line) -> collect_tracks_tsv(rest, [line, ..acc])
        None -> collect_tracks_tsv(rest, acc)
      }
  }
}

fn spotify_track_tsv(item: dynamic.Dynamic) -> Option(String) {
  case decode_path(item, ["track", "id"], decode.string) {
    None -> None
    Some(id) -> {
      let title = decode_path_or(item, ["track", "name"], "", decode.string)
      let artists =
        decode_path_or(item, ["track", "artists"], [], decode.list(of: decode.dynamic))
      let artist = first_artist_name(artists)
      Some(id <> "\t" <> title <> "\t" <> artist)
    }
  }
}

fn first_artist_name(artists: List(dynamic.Dynamic)) -> String {
  case artists {
    [] -> "unknown"
    [first, .._] -> decode_path_or(first, ["name"], "unknown", decode.string)
  }
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

fn extract_refresh_token(body: String) -> String {
  let compact = string.replace(body, " ", "")
  let exact = extract_between(compact, "\"refresh_token\":\"", "\"")
  case exact {
    "" -> extract_between(body, "\"refresh_token\":\"", "\"")
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

