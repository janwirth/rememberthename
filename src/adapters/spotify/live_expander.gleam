//// Spotify adapter documentation.
////
//// Scope and root inputs:
//// - Supports authenticated Spotify likes traversal via profile entry roots.
//// - Runtime target is the user-scoped liked tracks feed (`/v1/me/tracks`) via
////   the vendored `spotify_client` (official Web API types and `added_at`).
////
//// Auth/API contract:
//// - Credentials are passed in as `SpotifyConfig` / `ApiKeys.spotify` from the
////   application layer only (no `.env` or session file reads in this module).
//// - Missing/invalid auth resolves to unresolved profile nodes (no process crash).
////
//// Intermediary mapping:
//// - Each fetched page is normalized into `UnifiedItem` values with canonical ids:
////   `spotify:item:<track_id>`.
//// - Liked tracks are emitted as collection:
////   `spotify:collection:likes` ("Liked Songs").
////
//// Depth semantics in this adapter:
//// - Depth1: first page of saved tracks (limit=50), plus collection shell.
//// - DepthN: follows offset pagination page-by-page up to depth budget.
//// - DepthAll: exhausts all reachable pages (via `next` cursor / offset).
////
//// Notes:
//// - Saved albums and album-track expansion are not implemented in this module.

import adapters/api_keys.{
  SpotifyCredentials,
  type SpotifyCredentials as SpotifyCreds,
}
import adapters/cache
import adapters/core
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import spotify_client
import spotify_client/client as spotify_client_mod
import spotify_client/oauth
import spotify_client/resource as spotify_page
import spotify_client/saved_tracks
import spotify_client/types.{
  SavedLibraryTrack,
  type SavedLibraryTrack as SavedLibTrack,
}

pub opaque type SpotifyUserProfile {
  SpotifyUserProfile(profile_url: String)
}

pub type SpotifyConfig {
  SpotifyConfig(credentials: SpotifyCreds)
}

pub fn spotify_user(profile_url: String) -> SpotifyUserProfile {
  SpotifyUserProfile(profile_url: profile_url)
}

pub fn spotify_config(credentials credentials: SpotifyCreds) -> SpotifyConfig {
  SpotifyConfig(credentials: credentials)
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
  resolve_profile_with_debug_limited(
    profile,
    depth,
    config,
    cache_mode,
    0,
    on_debug,
  )
}

pub fn resolve_profile_with_debug_limited(
  profile: SpotifyUserProfile,
  depth: core.DepthMode,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
  max_items: Int,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  resolve_profile_with_debug_limited_timed(
    profile,
    depth,
    config,
    cache_mode,
    max_items,
    core.default_queue_policy(),
    on_debug,
    fn(_) { Nil },
  )
}

pub fn resolve_profile_with_debug_limited_timed(
  profile: SpotifyUserProfile,
  depth: core.DepthMode,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
  max_items: Int,
  queue_policy: core.QueuePolicy,
  on_debug: fn(String) -> Nil,
  on_progress: fn(core.ResolveProgress) -> Nil,
) -> core.ResolveResult {
  let SpotifyUserProfile(profile_url) = profile
  core.resolve_profile_url_with_debug_limit_and_queue_policy(
    profile_url,
    depth,
    max_items,
    queue_policy,
    fn(node) { expand(node, config, cache_mode) },
    on_debug,
    on_progress,
  )
}

pub fn expand(
  node: core.AdapterNode,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  case node {
    core.ProfileEntry(profile_url) ->
      expand_profile(profile_url, config, cache_mode)
    core.CategoryNode(ctx) -> expand_playlists(ctx)
    core.ListNode(ctx) -> expand_playlist_tracks(ctx, config, cache_mode)
    core.PageNode(ctx) -> expand_track_page(ctx, config, cache_mode)
  }
}

fn expand_profile(
  profile_url: String,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let user_id = parse_user_id(profile_url)
  let SpotifyConfig(credentials) = config
  case user_id == "" {
    True ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ProfileEntry(profile_url)],
        cache_hits: 0,
        cache_fetches: 0,
      )
    False ->
      case to_authed_client(credentials) {
        None ->
          core.ExpandResult(
            items: [],
            lists: [],
            next_nodes: [],
            unresolved: [core.ProfileEntry(profile_url)],
            cache_hits: 0,
            cache_fetches: 0,
          )
        Some(client) -> {
          let token = client.auth.access_token
          emit_liked_tracks(client, token, "likes", 0, cache_mode)
        }
      }
  }
}

fn to_authed_client(creds: SpotifyCreds) {
  let SpotifyCredentials(at, rt, cid, cs, ru) = creds
  let base = spotify_client.new(cid, cs, ru)
  let at = string.trim(at)
  let rt = string.trim(rt)
  let cid = string.trim(cid)
  let cs = string.trim(cs)
  let expires = timestamp.add(timestamp.system_time(), duration.hours(1))
  case rt != "" && cid != "" && cs != "" {
    True -> {
      let initial = spotify_client_mod.authenticate(base, at, rt, expires)
      case oauth.refresh_access_token(initial) {
        Ok(c) -> Some(c)
        Error(_) ->
          case at != "" {
            True -> Some(spotify_client_mod.authenticate(base, at, rt, expires))
            False -> None
          }
      }
    }
    False ->
      case at != "" {
        True -> Some(spotify_client_mod.authenticate(base, at, "", expires))
        False -> None
      }
  }
}

fn authed_for_bearer(creds: SpotifyCreds, bearer: String) {
  let SpotifyCredentials(_, _, cid, cs, ru) = creds
  let base = spotify_client.new(cid, cs, ru)
  let expires = timestamp.add(timestamp.system_time(), duration.hours(1))
  spotify_client_mod.authenticate(base, bearer, "", expires)
}

fn expand_playlists(ctx: String) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes", token, offset_str] -> {
      let offset = to_int(offset_str)
      let next_nodes = [
        core.ListNode("likes|" <> token <> "|" <> int.to_string(offset)),
      ]
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: next_nodes,
        unresolved: [],
        cache_hits: 0,
        cache_fetches: 0,
      )
    }
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.CategoryNode(ctx)],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

fn expand_playlist_tracks(
  ctx: String,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes", token, offset_str] -> {
      let SpotifyConfig(creds) = config
      let client = authed_for_bearer(creds, token)
      emit_liked_tracks(client, token, "likes", to_int(offset_str), cache_mode)
    }
    ["likes", cache_scope, token, offset_str] -> {
      let SpotifyConfig(creds) = config
      let client = authed_for_bearer(creds, token)
      emit_liked_tracks(
        client,
        token,
        cache_scope,
        to_int(offset_str),
        cache_mode,
      )
    }
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.ListNode(ctx)],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

fn expand_track_page(
  ctx: String,
  config: SpotifyConfig,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let parts = string.split(ctx, "|")
  case parts {
    ["likes_page", token, offset_str] -> {
      let SpotifyConfig(creds) = config
      let client = authed_for_bearer(creds, token)
      emit_liked_tracks(client, token, "likes", to_int(offset_str), cache_mode)
    }
    ["likes_page", cache_scope, token, offset_str] -> {
      let SpotifyConfig(creds) = config
      let client = authed_for_bearer(creds, token)
      emit_liked_tracks(
        client,
        token,
        cache_scope,
        to_int(offset_str),
        cache_mode,
      )
    }
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [core.PageNode(ctx)],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

fn emit_liked_tracks(
  client: spotify_client_mod.AuthenticatedClient,
  token: String,
  cache_scope: String,
  offset: Int,
  cache_mode: cache.CacheMode,
) -> core.ExpandResult {
  let #(packed, cj) =
    cached_liked_tracks_page(client, cache_scope, offset, cache_mode)
  let #(tsv, ct) = cached_tracks_tsv(packed, cache_mode)
  let #(hits, fetches) = cache.merge_rollups(cj, ct)
  let items = parse_track_items(tsv)
  let collection =
    core.UnifiedCollection(
      id: "spotify:collection:likes",
      title: "Liked Songs",
      track_ids: list.map(items, fn(item) {
        let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _) = item
        id
      }),
      list_ids: [],
      service: "spotify",
      source_type: "collection",
      source_id: "spotify:collection:likes",
    )
  let next_offset = page_next_offset_from_packed(packed)
  let next_nodes = case next_offset != "" {
    True -> [
      core.PageNode(
        "likes_page|" <> cache_scope <> "|" <> token <> "|" <> next_offset,
      ),
    ]
    False -> []
  }
  core.ExpandResult(
    items: items,
    lists: [collection],
    next_nodes: next_nodes,
    unresolved: [],
    cache_hits: hits,
    cache_fetches: fetches,
  )
}

const page_pack_magic = "SPOTIFY_PAGE_V1"

fn pack_liked_page(tsv: String, next_offset: String) -> String {
  page_pack_magic <> "\n" <> next_offset <> "\n" <> tsv
}

fn unpack_liked_page(packed: String) -> #(String, String) {
  case string.split_once(packed, "\n") {
    Error(_) -> #("", "")
    Ok(#(head, rest)) ->
      case head == page_pack_magic {
        False -> #(packed, "")
        True ->
          case string.split_once(rest, "\n") {
            Error(_) -> #("", "")
            Ok(#(next_off, tsv)) -> #(tsv, next_off)
          }
      }
  }
}

fn page_next_offset_from_packed(packed: String) -> String {
  let #(_, next) = unpack_liked_page(packed)
  next
}

fn cached_liked_tracks_page(
  client: spotify_client_mod.AuthenticatedClient,
  cache_scope: String,
  offset: Int,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch(
    "spotify_liked_tracks_json",
    cache_scope <> "|" <> int.to_string(offset),
    cache_mode,
    fn() {
      case saved_tracks.fetch_page(client, 50, offset) {
        Ok(page) ->
          pack_liked_page(
            saved_library_items_to_tsv(page.items),
            paginated_next_offset_string(page),
          )
        Error(_) -> pack_liked_page("", "")
      }
    },
  )
}

fn paginated_next_offset_string(page: spotify_page.PaginatedResult(a)) -> String {
  case page.next_cursor {
    Some(cursor) ->
      case cursor {
        spotify_page.Cursor(_limit, off) -> int.to_string(off)
        spotify_page.Start(_) -> ""
      }
    None -> ""
  }
}

fn cached_tracks_tsv(
  packed: String,
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  let #(tsv, _) = unpack_liked_page(packed)
  cache.read_or_fetch("spotify_tracks_tsv", tsv, cache_mode, fn() { tsv })
}

fn saved_library_items_to_tsv(items: List(SavedLibTrack)) -> String {
  items
  |> list.map(fn(item) {
    let SavedLibraryTrack(track: t, added_at: at) = item
    let track_id = t.id.id
    let url = "https://open.spotify.com/track/" <> track_id
    let artist_name = case t.artists {
      [] -> "unknown"
      [a, ..] -> a.name
    }
    let added = case normalize_spotify_added_at(at.value) {
      Some(s) -> s
      None -> ""
    }
    track_id
    <> "\t"
    <> t.name
    <> "\t"
    <> artist_name
    <> "\t"
    <> url
    <> "\t"
    <> ""
    <> "\t"
    <> added
  })
  |> string.join("\n")
}

fn parse_track_items(tsv: String) -> List(core.UnifiedItem) {
  parse_lines(tsv)
  |> list.filter_map(fn(chunk) {
    let cols = string.split(chunk, "\t")
    let track_id = case cols {
      [id, ..] -> id
      _ -> ""
    }
    let title = case cols {
      [_, t, ..] -> t
      _ -> ""
    }
    let artist_name = case cols {
      [_, _, a, ..] -> a
      _ -> "unknown"
    }
    let track_url = case cols {
      [_, _, _, u, ..] -> u
      _ -> ""
    }
    let #(cover_url, added_at_raw) = case cols {
      [_, _, _, _, cover, raw, ..] -> #(cover, normalize_spotify_added_at(raw))
      [_, _, _, _, raw] -> #("", normalize_spotify_added_at(raw))
      _ -> #("", None)
    }
    let added_at_str = case added_at_raw {
      Some(s) -> s
      None -> ""
    }
    case track_id == "" {
      True -> Error(Nil)
      False ->
        core.track_item_with_added_at(
          "spotify",
          track_id,
          normalize(title),
          normalize(default_if_empty(artist_name, "unknown")),
          string.trim(track_url),
          string.trim(cover_url),
          added_at_str,
        )
    }
  })
}

fn normalize_spotify_added_at(raw: String) -> Option(String) {
  let value = string.trim(raw)
  case is_iso8601_utc(value) {
    True -> Some(value)
    False -> None
  }
}

fn is_iso8601_utc(value: String) -> Bool {
  let graphemes = string.to_graphemes(value)
  let len = list.length(graphemes)
  case len >= 20 && string.ends_with(value, "Z") {
    False -> False
    True -> {
      let year = take_graphemes(graphemes, 0, 4)
      let month = take_graphemes(graphemes, 5, 2)
      let day = take_graphemes(graphemes, 8, 2)
      let hour = take_graphemes(graphemes, 11, 2)
      let minute = take_graphemes(graphemes, 14, 2)
      let second = take_graphemes(graphemes, 17, 2)
      list.all(string.to_graphemes(year), is_ascii_digit)
      && list.all(string.to_graphemes(month), is_ascii_digit)
      && list.all(string.to_graphemes(day), is_ascii_digit)
      && list.all(string.to_graphemes(hour), is_ascii_digit)
      && list.all(string.to_graphemes(minute), is_ascii_digit)
      && list.all(string.to_graphemes(second), is_ascii_digit)
      && string.slice(value, at_index: 4, length: 1) == "-"
      && string.slice(value, at_index: 7, length: 1) == "-"
      && string.slice(value, at_index: 10, length: 1) == "T"
      && string.slice(value, at_index: 13, length: 1) == ":"
      && string.slice(value, at_index: 16, length: 1) == ":"
    }
  }
}

fn take_graphemes(chars: List(String), offset: Int, length: Int) -> String {
  chars |> list.drop(offset) |> list.take(length) |> string.concat
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

fn is_ascii_digit(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}
