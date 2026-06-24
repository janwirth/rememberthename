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
import gleam/dict
import gleam/dynamic/decode
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
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
    option.None,
  ).result
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
  anchor: option.Option(String),
) -> core.ResolveResultWithAnchor {
  let SpotifyUserProfile(profile_url) = profile
  core.resolve_profile_url_with_debug_limit_and_queue_policy(
    profile_url,
    depth,
    max_items,
    queue_policy,
    fn(node) { expand(node, config, cache_mode) },
    on_debug,
    on_progress,
    anchor,
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
          let liked = emit_liked_tracks(client, token, "likes", 0, cache_mode)
          let album_items = fetch_liked_album_tracks(token)
          let current_user_id = fetch_me_user_id(token)
          let playlist_lists = fetch_user_playlists(token)
          let meta =
            core.UnifiedCollection(
              id: "spotify:meta:current_user",
              title: current_user_id,
              track_ids: [],
              list_ids: [],
              service: "spotify",
              source_type: "meta",
              source_id: "current_user|" <> current_user_id,
            )
          core.ExpandResult(
            ..liked,
            items: list.append(liked.items, album_items),
            lists: list.append(liked.lists, [meta, ..playlist_lists]),
          )
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
  let pairs = parse_track_items_with_artist_ids(tsv)
  let artist_ids =
    list.fold(pairs, set.new(), fn(s, p) { set.insert(s, p.1) })
    |> set.to_list
    |> list.filter(fn(id) { id != "" })
  let genres_by_artist = fetch_artist_genres(token, artist_ids)
  let items =
    list.map(pairs, fn(pair) {
      let #(item, artist_id) = pair
      let genres = result.unwrap(dict.get(genres_by_artist, artist_id), [])
      core.UnifiedItem(..item, genres:)
    })
  let collection =
    core.UnifiedCollection(
      id: "spotify:collection:likes",
      title: "Liked Songs",
      track_ids: list.map(items, fn(item) {
        let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _, _, _, _) = item
        id
      }),
      list_ids: [],
      service: "spotify",
      source_type: "collection",
      source_id: "spotify:collection:likes",
    )
  let genre_collections = build_genre_collections(items)
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
    lists: [collection, ..genre_collections],
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
    let cover_url = case t.album.images {
      [img, ..] -> img.url
      [] -> ""
    }
    let artist_id = case t.artists {
      [a, ..] -> a.id.id
      [] -> ""
    }
    track_id
    <> "\t"
    <> t.name
    <> "\t"
    <> artist_name
    <> "\t"
    <> url
    <> "\t"
    <> cover_url
    <> "\t"
    <> added
    <> "\t"
    <> int.to_string(t.duration_ms)
    <> "\t"
    <> artist_id
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
    let #(cover_url, added_at_raw, duration_ms_str) = case cols {
      [_, _, _, _, cover, raw, dur, ..] -> #(cover, normalize_spotify_added_at(raw), dur)
      [_, _, _, _, cover, raw] -> #(cover, normalize_spotify_added_at(raw), "")
      [_, _, _, _, raw] -> #("", normalize_spotify_added_at(raw), "")
      _ -> #("", None, "")
    }
    let added_at_str = case added_at_raw {
      Some(s) -> s
      None -> ""
    }
    let duration_s = case int.parse(string.trim(duration_ms_str)) {
      Ok(ms) if ms > 0 -> Some(int.to_float(ms) /. 1000.0)
      _ -> None
    }
    case track_id == "" {
      True -> Error(Nil)
      False ->
        core.track_item_strict(
          "spotify",
          track_id,
          normalize(title),
          normalize(default_if_empty(artist_name, "unknown")),
          string.trim(track_url),
          string.trim(cover_url),
          added_at_str,
          [],
          duration_s,
        )
    }
  })
}

fn parse_track_items_with_artist_ids(
  tsv: String,
) -> List(#(core.UnifiedItem, String)) {
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
    let #(cover_url, added_at_raw, duration_ms_str, artist_id) = case cols {
      [_, _, _, _, cover, raw, dur, aid, ..] -> #(
        cover,
        normalize_spotify_added_at(raw),
        dur,
        aid,
      )
      [_, _, _, _, cover, raw, dur] -> #(
        cover,
        normalize_spotify_added_at(raw),
        dur,
        "",
      )
      [_, _, _, _, cover, raw] -> #(cover, normalize_spotify_added_at(raw), "", "")
      _ -> #("", None, "", "")
    }
    let added_at_str = case added_at_raw {
      Some(s) -> s
      None -> ""
    }
    let duration_s = case int.parse(string.trim(duration_ms_str)) {
      Ok(ms) if ms > 0 -> Some(int.to_float(ms) /. 1000.0)
      _ -> None
    }
    case track_id == "" {
      True -> Error(Nil)
      False ->
        case
          core.track_item_strict(
            "spotify",
            track_id,
            normalize(title),
            normalize(default_if_empty(artist_name, "unknown")),
            string.trim(track_url),
            string.trim(cover_url),
            added_at_str,
            [],
            duration_s,
          )
        {
          Ok(item) -> Ok(#(item, string.trim(artist_id)))
          Error(e) -> Error(e)
        }
    }
  })
}

fn build_genre_collections(
  items: List(core.UnifiedItem),
) -> List(core.UnifiedCollection) {
  let genre_map =
    list.fold(items, dict.new(), fn(acc, item) {
      let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _, genres, _, _) = item
      list.fold(genres, acc, fn(acc2, genre) {
        let existing = result.unwrap(dict.get(acc2, genre), [])
        dict.insert(acc2, genre, [id, ..existing])
      })
    })
  dict.to_list(genre_map)
  |> list.map(fn(pair) {
    let #(genre, track_ids) = pair
    let genre_id = "spotify:collection:genre:" <> genre
    core.UnifiedCollection(
      id: genre_id,
      title: genre,
      track_ids: list.reverse(track_ids),
      list_ids: [],
      service: "spotify",
      source_type: "collection",
      source_id: genre_id,
    )
  })
}

fn fetch_artist_genres(
  token: String,
  artist_ids: List(String),
) -> dict.Dict(String, List(String)) {
  let batches = list.sized_chunk(artist_ids, 50)
  let artist_pair_decoder = {
    use id <- decode.field("id", decode.string)
    use genres <- decode.field("genres", decode.list(decode.string))
    decode.success(#(id, genres))
  }
  let decoder = {
    use artists <- decode.field("artists", decode.list(artist_pair_decoder))
    decode.success(artists)
  }
  list.fold(batches, dict.new(), fn(acc, batch) {
    let ids_param = string.join(batch, ",")
    let req =
      request.new()
      |> request.set_scheme(http.Https)
      |> request.set_host("api.spotify.com")
      |> request.set_path("/v1/artists")
      |> request.set_query([#("ids", ids_param)])
      |> request.set_method(http.Get)
      |> request.set_header("Authorization", "Bearer " <> token)
      |> request.set_header("Accept", "application/json")
    case hackney.send(req) {
      Ok(resp) ->
        case json.parse(resp.body, decoder) {
          Ok(pairs) ->
            list.fold(pairs, acc, fn(d, pair) {
              let #(id, genres) = pair
              dict.insert(d, id, genres)
            })
          Error(_) -> acc
        }
      Error(_) -> acc
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

fn fetch_me_user_id(token: String) -> String {
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("api.spotify.com")
    |> request.set_path("/v1/me")
    |> request.set_method(http.Get)
    |> request.set_header("Authorization", "Bearer " <> token)
    |> request.set_header("Accept", "application/json")
  let decoder = {
    use id <- decode.field("id", decode.string)
    decode.success(id)
  }
  case hackney.send(req) {
    Ok(resp) ->
      case json.parse(resp.body, decoder) {
        Ok(id) -> id
        Error(_) -> ""
      }
    Error(_) -> ""
  }
}

fn fetch_liked_album_tracks(token: String) -> List(core.UnifiedItem) {
  do_fetch_liked_album_tracks(token, 0, [])
}

fn do_fetch_liked_album_tracks(
  token: String,
  offset: Int,
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("api.spotify.com")
    |> request.set_path("/v1/me/albums")
    |> request.set_query([
      #("limit", "50"),
      #("offset", int.to_string(offset)),
    ])
    |> request.set_method(http.Get)
    |> request.set_header("Authorization", "Bearer " <> token)
    |> request.set_header("Accept", "application/json")
  let name_decoder = {
    use name <- decode.field("name", decode.string)
    decode.success(name)
  }
  let track_decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use artists <- decode.field("artists", decode.list(name_decoder))
    use duration_ms <- decode.field("duration_ms", decode.int)
    decode.success(#(id, name, artists, duration_ms))
  }
  let img_decoder = {
    use url <- decode.field("url", decode.string)
    decode.success(url)
  }
  let album_decoder = {
    use artists <- decode.field("artists", decode.list(name_decoder))
    use images <- decode.field("images", decode.list(img_decoder))
    use tracks <- decode.field("tracks", {
      use items <- decode.field("items", decode.list(track_decoder))
      decode.success(items)
    })
    decode.success(#(artists, images, tracks))
  }
  let item_decoder = {
    use added_at <- decode.field("added_at", decode.string)
    use album <- decode.field("album", album_decoder)
    decode.success(#(added_at, album))
  }
  let resp_decoder = {
    use items <- decode.field("items", decode.list(item_decoder))
    use next <- decode.field("next", decode.optional(decode.string))
    decode.success(#(items, next))
  }
  case hackney.send(req) {
    Error(_) -> acc
    Ok(resp) ->
      case json.parse(resp.body, resp_decoder) {
        Error(_) -> acc
        Ok(#(items, next)) -> {
          let new_items =
            list.flat_map(items, fn(entry) {
              let #(added_at_str, #(album_artists, images, tracks)) = entry
              let cover_url = case images {
                [url, ..] -> url
                [] -> ""
              }
              let album_artist = case album_artists {
                [a, ..] -> a
                [] -> "unknown"
              }
              let added = option.unwrap(normalize_spotify_added_at(added_at_str), "")
              list.filter_map(tracks, fn(track) {
                let #(track_id, track_name, track_artists, duration_ms) = track
                let artist = case track_artists {
                  [a, ..] -> a
                  [] -> album_artist
                }
                core.track_item_strict(
                  "spotify",
                  track_id,
                  normalize(track_name),
                  normalize(default_if_empty(artist, "unknown")),
                  "https://open.spotify.com/track/" <> track_id,
                  cover_url,
                  added,
                  [],
                  case duration_ms > 0 {
                    True -> Some(int.to_float(duration_ms) /. 1000.0)
                    False -> None
                  },
                )
              })
            })
          let acc2 = list.append(acc, new_items)
          case next {
            None -> acc2
            Some(_) -> do_fetch_liked_album_tracks(token, offset + 50, acc2)
          }
        }
      }
  }
}

fn fetch_user_playlists(token: String) -> List(core.UnifiedCollection) {
  do_fetch_user_playlists(token, 0, [])
}

fn do_fetch_user_playlists(
  token: String,
  offset: Int,
  acc: List(core.UnifiedCollection),
) -> List(core.UnifiedCollection) {
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("api.spotify.com")
    |> request.set_path("/v1/me/playlists")
    |> request.set_query([
      #("limit", "50"),
      #("offset", int.to_string(offset)),
    ])
    |> request.set_method(http.Get)
    |> request.set_header("Authorization", "Bearer " <> token)
    |> request.set_header("Accept", "application/json")
  let playlist_decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use owner_id <- decode.field("owner", {
      use id <- decode.field("id", decode.string)
      decode.success(id)
    })
    decode.success(#(id, name, owner_id))
  }
  let resp_decoder = {
    use items <- decode.field("items", decode.list(playlist_decoder))
    use next <- decode.field("next", decode.optional(decode.string))
    decode.success(#(items, next))
  }
  case hackney.send(req) {
    Error(_) -> acc
    Ok(resp) ->
      case json.parse(resp.body, resp_decoder) {
        Error(_) -> acc
        Ok(#(items, next)) -> {
          let new_cols =
            list.map(items, fn(entry) {
              let #(id, name, owner_id) = entry
              core.UnifiedCollection(
                id: "spotify:playlist:" <> id,
                title: name,
                track_ids: [],
                list_ids: [],
                service: "spotify",
                source_type: "playlist",
                source_id: id <> "|" <> owner_id,
              )
            })
          let acc2 = list.append(acc, new_cols)
          case next {
            None -> acc2
            Some(_) -> do_fetch_user_playlists(token, offset + 50, acc2)
          }
        }
      }
  }
}

pub fn fetch_playlist_tracks_with_anchor(
  playlist_id: String,
  config: SpotifyConfig,
  fetch_newer_than: option.Option(String),
) -> #(List(core.UnifiedItem), option.Option(String)) {
  let SpotifyConfig(credentials) = config
  case to_authed_client(credentials) {
    None -> #([], option.None)
    Some(client) ->
      do_fetch_playlist_tracks(
        client.auth.access_token,
        playlist_id,
        fetch_newer_than,
        0,
        [],
        option.None,
      )
  }
}

fn do_fetch_playlist_tracks(
  token: String,
  playlist_id: String,
  fetch_newer_than: option.Option(String),
  offset: Int,
  acc: List(core.UnifiedItem),
  newest_added_at: option.Option(String),
) -> #(List(core.UnifiedItem), option.Option(String)) {
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("api.spotify.com")
    |> request.set_path("/v1/playlists/" <> playlist_id <> "/tracks")
    |> request.set_query([
      #("limit", "100"),
      #("offset", int.to_string(offset)),
    ])
    |> request.set_method(http.Get)
    |> request.set_header("Authorization", "Bearer " <> token)
    |> request.set_header("Accept", "application/json")
  let name_decoder = {
    use name <- decode.field("name", decode.string)
    decode.success(name)
  }
  let img_decoder = {
    use url <- decode.field("url", decode.string)
    decode.success(url)
  }
  let track_decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use artists <- decode.field("artists", decode.list(name_decoder))
    use images <- decode.field("album", {
      use imgs <- decode.field("images", decode.list(img_decoder))
      decode.success(imgs)
    })
    use duration_ms <- decode.field("duration_ms", decode.int)
    decode.success(#(id, name, artists, images, duration_ms))
  }
  let item_decoder = {
    use added_at <- decode.field("added_at", decode.string)
    use track <- decode.field("track", decode.optional(track_decoder))
    decode.success(#(added_at, track))
  }
  let resp_decoder = {
    use items <- decode.field("items", decode.list(item_decoder))
    use next <- decode.field("next", decode.optional(decode.string))
    decode.success(#(items, next))
  }
  case hackney.send(req) {
    Error(_) -> #(acc, newest_added_at)
    Ok(resp) ->
      case json.parse(resp.body, resp_decoder) {
        Error(_) -> #(acc, newest_added_at)
        Ok(#(items, next)) -> {
          let valid = list.filter_map(items, fn(entry) {
            let #(added_at, track_opt) = entry
            option.to_result(option.map(track_opt, fn(t) { #(added_at, t) }), Nil)
          })
          let #(new_items, should_stop, new_newest) =
            list.fold(valid, #([], False, newest_added_at), fn(state, entry) {
              let #(acc_items, stop, newed) = state
              case stop {
                True -> state
                False -> {
                  let #(added_at_str, #(track_id, track_name, track_artists, images, duration_ms)) =
                    entry
                  let normalized_added = normalize_spotify_added_at(added_at_str)
                  let added_unix = case normalized_added {
                    None -> 0
                    Some(s) -> {
                      let #(sec, _) =
                        timestamp.to_unix_seconds_and_nanoseconds(
                          core.added_at_timestamp_from_raw(s),
                        )
                      sec
                    }
                  }
                  let anchor_unix = case fetch_newer_than {
                    None -> 0
                    Some(s) -> {
                      let #(sec, _) =
                        timestamp.to_unix_seconds_and_nanoseconds(
                          core.added_at_timestamp_from_raw(s),
                        )
                      sec
                    }
                  }
                  let past_anchor =
                    fetch_newer_than != option.None
                    && added_unix <= anchor_unix
                  case past_anchor {
                    True -> #(acc_items, True, newed)
                    False -> {
                      let cover_url = case images {
                        [url, ..] -> url
                        [] -> ""
                      }
                      let artist = case track_artists {
                        [a, ..] -> a
                        [] -> "unknown"
                      }
                      let added_str = option.unwrap(normalized_added, "")
                      let new_newest2 = case newed {
                        None -> normalized_added
                        Some(existing_str) -> {
                          let #(existing_unix, _) =
                            timestamp.to_unix_seconds_and_nanoseconds(
                              core.added_at_timestamp_from_raw(existing_str),
                            )
                          case added_unix > existing_unix {
                            True -> normalized_added
                            False -> newed
                          }
                        }
                      }
                      case
                        core.track_item_strict(
                          "spotify",
                          track_id,
                          normalize(track_name),
                          normalize(default_if_empty(artist, "unknown")),
                          "https://open.spotify.com/track/" <> track_id,
                          cover_url,
                          added_str,
                          [],
                          case duration_ms > 0 {
                            True -> Some(int.to_float(duration_ms) /. 1000.0)
                            False -> None
                          },
                        )
                      {
                        Ok(item) -> #([item, ..acc_items], False, new_newest2)
                        Error(_) -> #(acc_items, False, new_newest2)
                      }
                    }
                  }
                }
              }
            })
          let acc2 = list.append(acc, list.reverse(new_items))
          case should_stop || next == option.None {
            True -> #(acc2, new_newest)
            False ->
              do_fetch_playlist_tracks(
                token,
                playlist_id,
                fetch_newer_than,
                offset + 100,
                acc2,
                new_newest,
              )
          }
        }
      }
  }
}
