import adapters/cache.{CacheIgnore, CacheOverride, CacheUpsert, type CacheMode}
import adapters/core as core
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/tags_catalog_query
import cli/tuna_tags
import cli/track_view
import fetch_ops
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleam/time/timestamp
import source_specs
import source_root

pub type UnifiedItem =
  core.UnifiedItem

pub type UnifiedCollection =
  core.UnifiedCollection

pub type FetchResult =
  fetch_ops.FetchResult

pub type TunaCatalogTag {
  TunaCatalogTag(export_key: String, label: String, emoji: String)
}

pub fn cloud_unified_item(
  id: String,
  title: String,
  artist: String,
  service: String,
  source_type: String,
  source_id: String,
  external_source_url: option.Option(String),
  cover_url: option.Option(String),
  file_path: option.Option(String),
  added_at: timestamp.Timestamp,
) -> UnifiedItem {
  core.UnifiedItem(
    id:,
    title:,
    artist:,
    service:,
    source_type:,
    source_id:,
    external_source_url:,
    cover_url:,
    file_path:,
    added_at:,
    genres: [],
    duration_s: option.None,
  )
}

pub fn with_duration_s(
  item: UnifiedItem,
  duration_s: option.Option(Float),
) -> UnifiedItem {
  core.UnifiedItem(..item, duration_s:)
}

pub fn all_sources() {
  source_specs.all()
}

pub fn all_sources_configured() {
  source_specs.all_configured()
}

/// Like `all_sources_configured` but reads credentials from `profile_dir` (e.g. `~/tuna/default`).
/// Pass `youtube_playlist_url: Some(url)` to override the hardcoded playlist.
pub fn all_sources_for_profile(
  profile_dir: String,
  youtube_playlist_url: option.Option(String),
) {
  source_specs.all_configured_for_profile(profile_dir, youtube_playlist_url)
}

pub fn fetch_source(
  root: source_root.SourceRoot,
  on_log_line: fn(String) -> Nil,
) -> Result(fetch_ops.FetchResult, String) {
  fetch_ops.fetch(root, cache_mode_for_root(root), on_log_line)
}

pub fn fetch_source_no_cache(
  root: source_root.SourceRoot,
  on_log_line: fn(String) -> Nil,
) -> Result(fetch_ops.FetchResult, String) {
  fetch_ops.fetch(root, CacheIgnore, on_log_line)
}

/// Incremental scans must bypass adapter cache — page 0 changes when new likes arrive.
fn cache_mode_for_root(root: source_root.SourceRoot) -> CacheMode {
  case source_root.fetch_newer_than(root) {
    option.None -> CacheUpsert
    option.Some(_) -> CacheOverride
  }
}

/// All tuna `Tag` rows as stable export keys (`tag/<category>/<emoji>:<value>`).
pub fn fetch_tuna_tag_catalog() -> Result(List(TunaCatalogTag), String) {
  let raw = tags_catalog_query.fetch_tags_catalog_json()
  case string.trim(raw) == "" {
    True -> Error("gel query returned empty tag catalog")
    False -> decode_tuna_tag_catalog_gel(raw)
  }
}

/// Persisted catalog — `{ export_key, label, emoji }[]`.
pub fn encode_tuna_tag_catalog(tags: List(TunaCatalogTag)) -> String {
  json.to_string(json.array(tags, tuna_catalog_tag_to_json))
}

pub fn decode_tuna_tag_catalog(text: String) -> Result(List(TunaCatalogTag), Nil) {
  case json.parse(text, decode.list(stored_tuna_catalog_tag_decoder())) {
    Ok(tags) -> Ok(tags)
    Error(_) -> Error(Nil)
  }
}

pub fn decode_tuna_tag_catalog_from_gel(text: String) -> Result(List(TunaCatalogTag), String) {
  decode_tuna_tag_catalog_gel(text)
}

fn decode_tuna_tag_catalog_gel(text: String) -> Result(List(TunaCatalogTag), String) {
  case json.parse(text, decode.list(tuna_catalog_tag_decoder())) {
    Ok(tags) -> Ok(tags)
    Error(_) -> Error("failed to decode tag catalog JSON")
  }
}

fn decode_nullable_string(default: String) -> decode.Decoder(String) {
  decode.optional(decode.string)
  |> decode.map(fn(value) {
    case value {
      option.Some(text) -> text
      option.None -> default
    }
  })
}

fn tuna_catalog_tag_to_json(tag: TunaCatalogTag) -> json.Json {
  let TunaCatalogTag(export_key:, label:, emoji:) = tag
  json.object([
    #("export_key", json.string(export_key)),
    #("label", json.string(label)),
    #("emoji", json.string(emoji)),
  ])
}

fn stored_tuna_catalog_tag_decoder() -> decode.Decoder(TunaCatalogTag) {
  use export_key <- decode.field("export_key", decode.string)
  use label <- decode.field("label", decode.string)
  use emoji <- decode.optional_field("emoji", "", decode.string)
  decode.success(TunaCatalogTag(export_key:, label:, emoji:))
}

fn tuna_catalog_tag_decoder() -> decode.Decoder(TunaCatalogTag) {
  use label <- decode.field("label", decode.string)
  use emoji <- decode.field("emoji", decode_nullable_string(""))
  let token =
    case emoji == "" {
      True -> label
      False -> label <> "\u{001F}" <> emoji
    }
  decode.success(TunaCatalogTag(
    export_key: tuna_tags.format_export_tag(token),
    label:,
    emoji:,
  ))
}

/// Baseline tags from a tuna fetch, keyed like `track_tags.best_track_tag_id`.
/// Rating tokens (`:rating:N`) are excluded — use `imported_ratings_from_fetch`.
pub fn imported_tags_from_fetch(
  fetch: FetchResult,
) -> Dict(String, List(String)) {
  let fetch_ops.FetchResult(items, _, _, tuna_metadata, _) = fetch
  case tuna_metadata {
    option.None -> dict.new()
    option.Some(meta) ->
      list.fold(items, dict.new(), fn(acc, item) {
        let core.UnifiedItem(id, _, _, service, _, source_id, _, _, file_path, _, _, _) =
          item
        let tags_str =
          track_view.tuna_metadata_for(meta, service, source_id).tags
        let tags =
          list.filter(tuna_tags.export_tags(tags_str), fn(tag) {
            !string.starts_with(tag, ":rating:")
          })
        case tags {
          [] -> acc
          _ -> {
            let tag_id = imported_track_tag_id(id, file_path)
            dict.insert(acc, tag_id, tags)
          }
        }
      })
  }
}

/// Tuna DB `rating` column, keyed like `track_tags.best_track_tag_id`.
pub fn imported_ratings_from_fetch(
  fetch: FetchResult,
) -> Dict(String, Int) {
  let fetch_ops.FetchResult(items, _, _, tuna_metadata, _) = fetch
  case tuna_metadata {
    option.None -> dict.new()
    option.Some(meta) ->
      list.fold(items, dict.new(), fn(acc, item) {
        let core.UnifiedItem(id, _, _, service, _, source_id, _, _, file_path, _, _, _) =
          item
        let tags_str =
          track_view.tuna_metadata_for(meta, service, source_id).tags
        let rating = rating_from_export_tags_list(tuna_tags.export_tags(tags_str))
        case rating, file_path {
          option.Some(r), option.Some(p) if r > 0 ->
            dict.insert(acc, string.trim(p), r)
          _, _ -> acc
        }
      })
  }
}

fn rating_from_export_tags_list(tags: List(String)) -> option.Option(Int) {
  list.fold(tags, option.None, fn(acc, tag) {
    case acc {
      option.Some(_) -> acc
      option.None ->
        case string.starts_with(tag, ":rating:") {
          True ->
            case int.parse(string.drop_start(tag, 8)) {
              Ok(n) -> option.Some(n)
              Error(_) -> option.None
            }
          False -> option.None
        }
    }
  })
}

fn imported_track_tag_id(
  id: String,
  file_path: option.Option(String),
) -> String {
  case file_path {
    option.Some(p) -> string.trim(p)
    option.None -> id
  }
}

pub fn export_tags(tags: String) -> List(String) {
  tuna_tags.export_tags(tags)
}

/// Bandcamp genre tags — stored with `genre/` prefix by callers.
pub fn imported_genres_from_fetch(
  fetch: FetchResult,
) -> dict.Dict(String, List(String)) {
  let fetch_ops.FetchResult(items, _, _, _, _) = fetch
  list.fold(items, dict.new(), fn(acc, item) {
    let core.UnifiedItem(id, _, _, service, _, _, _, _, file_path, _, genres, _) =
      item
    case service, genres {
      "bandcamp", [_, ..] ->
        dict.insert(acc, imported_track_tag_id(id, file_path), genres)
      "spotify", [_, ..] ->
        dict.insert(acc, imported_track_tag_id(id, file_path), genres)
      _, _ -> acc
    }
  })
}

/// SC tags (CSV-parsed tag_list) as plain tags.
pub fn imported_sc_tags_from_fetch(
  fetch: FetchResult,
) -> dict.Dict(String, List(String)) {
  let fetch_ops.FetchResult(items, _, _, _, _) = fetch
  list.fold(items, dict.new(), fn(acc, item) {
    let core.UnifiedItem(id, _, _, service, _, _, _, _, file_path, _, genres, _) =
      item
    case service, genres {
      "soundcloud", [_, ..] ->
        dict.insert(acc, imported_track_tag_id(id, file_path), genres)
      _, _ -> acc
    }
  })
}

/// Fetch tracks from a Spotify playlist, optionally stopping at `fetch_newer_than` anchor.
/// Returns (items, new_anchor) where new_anchor is the newest added_at seen (to store for next sync).
pub fn fetch_spotify_playlist(
  playlist_id: String,
  root: source_root.SourceRoot,
  fetch_newer_than: option.Option(String),
) -> #(List(UnifiedItem), option.Option(String)) {
  case root {
    source_root.SpotifyRoot(credentials, _, _) ->
      spotify_live_expander.fetch_playlist_tracks_with_anchor(
        playlist_id,
        spotify_live_expander.spotify_config(credentials),
        fetch_newer_than,
      )
    _ -> #([], option.None)
  }
}