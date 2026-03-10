//// Spotify live adapter (public user playlists).
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import adapters/core

@external(erlang, "spotify_http", "read_access_token_file")
pub fn read_access_token_file(session_file: String) -> String

@external(erlang, "spotify_http", "ensure_access_token")
fn ensure_access_token(
  provided_token: String,
  session_file: String,
  client_id: String,
  redirect_uri: String,
  scopes: String,
) -> String

@external(erlang, "spotify_http", "user_playlists_json")
fn user_playlists_json(user_id: String, token: String, offset: Int) -> String

@external(erlang, "spotify_http", "playlist_tracks_json")
fn playlist_tracks_json(playlist_id: String, token: String, offset: Int) -> String

@external(erlang, "spotify_http", "playlists_tsv")
fn playlists_tsv(json: String) -> String

@external(erlang, "spotify_http", "playlists_next_offset")
fn playlists_next_offset(json: String) -> String

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
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [core.CategoryNode("playlists|" <> user_id <> "|" <> token <> "|0")],
        unresolved: [],
      )
  }
}

fn expand_playlists(ctx: String) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["playlists", user_id, token, offset_str] -> {
      let offset = to_int(offset_str)
      let json = user_playlists_json(user_id, token, offset)
      let playlist_lines = parse_lines(playlists_tsv(json))
      let playlist_nodes =
        list.filter_map(playlist_lines, fn(line) {
          let cols = string.split(line, "\t")
          case cols {
            [playlist_id, _] if playlist_id != "" ->
              Ok(core.ListNode("playlist|" <> playlist_id <> "|" <> token))
            _ -> Error(Nil)
          }
        })
      let next_offset = string.trim(playlists_next_offset(json))
      let next_nodes =
        case next_offset != "" {
          True -> list.append(playlist_nodes, [core.CategoryNode("playlists|" <> user_id <> "|" <> token <> "|" <> next_offset)])
          False -> playlist_nodes
        }
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
    ["playlist", playlist_id, token] ->
      emit_playlist_tracks(playlist_id, token, 0)
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
    ["playlist_page", playlist_id, token, offset_str] ->
      emit_playlist_tracks(playlist_id, token, to_int(offset_str))
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.PageNode(ctx)],
      )
  }
}

fn emit_playlist_tracks(
  playlist_id: String,
  token: String,
  offset: Int,
) -> core.ExpandResult {
  let json = playlist_tracks_json(playlist_id, token, offset)
  let items = parse_track_items(tracks_tsv(json))
  let collection =
    core.UnifiedCollection(
      id: "spotify:collection:playlist:" <> playlist_id,
      title: "Playlist " <> playlist_id,
      track_ids:
        list.map(items, fn(item) {
          let core.UnifiedItem(id, _, _, _, _, _) = item
          id
        }),
      list_ids: [],
      service: "spotify",
      source_type: "collection",
      source_id: "spotify:collection:playlist:" <> playlist_id,
    )
  let next_offset = string.trim(tracks_next_offset(json))
  let next_nodes =
    case next_offset != "" {
      True -> [core.PageNode("playlist_page|" <> playlist_id <> "|" <> token <> "|" <> next_offset)]
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
