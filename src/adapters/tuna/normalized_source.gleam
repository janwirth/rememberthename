import adapters/cache
import adapters/core
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import source_id_normalizer
import adapters/tuna/tuna_mirror_path

@external(erlang, "tuna_runtime", "tracks_source_ids_json")
fn tracks_source_ids_json() -> String

pub type ExportMetadata {
  ExportMetadata(
    file_path: String,
    cover_path: String,
    tags: String,
    imported_date: Int,
  )
}

pub type ResolveWithMetadataResult {
  ResolveWithMetadataResult(
    resolve_result: core.ResolveResult,
    export_metadata: dict.Dict(String, ExportMetadata),
  )
}

pub fn resolve(
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let ResolveWithMetadataResult(result, _) =
    resolve_with_metadata(depth, cache_mode, on_debug)
  result
}

pub fn resolve_with_metadata(
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> ResolveWithMetadataResult {
  let #(payload, #(cache_hits, cache_fetches)) =
    cached_tracks_source_ids_json(cache_mode)
  on_debug(
    "[tuna] cache hits="
      <> int.to_string(cache_hits)
      <> " fetches="
      <> int.to_string(cache_fetches),
  )
  let rows = decode_rows(payload)
  let #(all_items, all_metadata) = rows_to_items_with_metadata(rows)
  let items = apply_depth_limit(all_items, depth)
  on_debug(
    "[tuna] normalized_source_ids total="
    <> int.to_string(list.length(all_items))
    <> " returned="
    <> int.to_string(list.length(items)),
  )
  ResolveWithMetadataResult(
    resolve_result: core.ResolveResult(items: items, lists: [], unresolved: []),
    export_metadata: all_metadata,
  )
}

fn cached_tracks_source_ids_json(
  cache_mode: cache.CacheMode,
) -> #(String, #(Int, Int)) {
  cache.read_or_fetch(
    "tuna_tracks_source_ids_enriched_json",
    "tuna_main_default_track_sources_enriched",
    cache_mode,
    tracks_source_ids_json,
  )
}

fn decode_rows(payload: String) -> List(dynamic.Dynamic) {
  case json.parse(sanitize_json_payload(payload), decode.dynamic) {
    Error(_) -> []
    Ok(value) ->
      decode.run(value, decode.list(of: decode.dynamic)) |> result.unwrap([])
  }
}

fn sanitize_json_payload(payload: String) -> String {
  let cleaned = string.trim(payload)
  case string.split_once(cleaned, "[") {
    Ok(#(_, after)) -> "[" <> after
    Error(_) ->
      case string.split_once(cleaned, "{") {
        Ok(#(_, after)) -> "{" <> after
        Error(_) -> cleaned
      }
  }
}

fn rows_to_items_with_metadata(
  rows: List(dynamic.Dynamic),
) -> #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)) {
  list.fold(rows, #([], dict.new()), fn(acc, row) {
    let preferred_title = row_preferred_title(row)
    let artist = row_artist(row)
    let file_path = row_audio_path(row)
    let cover_path = row_cover_path(row)
    let tags = row_tags_with_rating(row)
    let imported_date = row_compact_imported_date(row)
    let acc =
      push_item_with_metadata(
        acc,
        row,
        "spotify",
        decode_path_or(row, ["spotify_id"], "", decode.string),
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
    let acc =
      push_item_with_metadata(
        acc,
        row,
        "youtube",
        decode_path_or(row, ["youtube_id"], "", decode.string),
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
    let acc =
      push_item_with_metadata(
        acc,
        row,
        "soundcloud",
        decode_path_or(row, ["soundcloud_id"], "", decode.string),
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
    let acc =
      push_item_with_metadata(
        acc,
        row,
        "bandcamp",
        decode_path_or(row, ["bandcamp_track_id"], "", decode.string),
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
    let acc =
      push_item_with_metadata(
        acc,
        row,
        "file",
        decode_path_or(row, ["file_path"], "", decode.string),
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
    let acc =
      push_item_with_metadata(
        acc,
        row,
        "itunes",
        decode_path_or(row, ["itunes_track_id"], "", decode.string),
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
    let acc =
      push_item_with_metadata(
        acc,
        row,
        "itunes",
        decode_path_or(row, ["itunes_persistent_track_id"], "", decode.string),
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
    push_fishbone_item_with_metadata(
      acc,
      row,
      preferred_title,
      artist,
      file_path,
      cover_path,
      tags,
      imported_date,
    )
  })
  |> map_items_reverse
}

fn map_items_reverse(
  value: #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)),
) -> #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)) {
  let #(items, metadata) = value
  #(list.reverse(items), metadata)
}

fn push_fishbone_item_with_metadata(
  acc: #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)),
  row: dynamic.Dynamic,
  preferred_title: String,
  artist: String,
  file_path: String,
  cover_path: String,
  tags: String,
  imported_date: Int,
) -> #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)) {
  let fishbone_platform =
    decode_path_or(row, ["fishbone_source_platform"], "", decode.string)
  let fishbone_source_id =
    decode_path_or(row, ["fishbone_source_id"], "", decode.string)
  let service = fishbone_service_for_platform(fishbone_platform)
  case service == "" || fishbone_source_id == "" {
    True -> acc
    False ->
      push_item_with_metadata(
        acc,
        row,
        service,
        fishbone_source_id,
        preferred_title,
        artist,
        file_path,
        cover_path,
        tags,
        imported_date,
      )
  }
}

fn fishbone_service_for_platform(platform: String) -> String {
  let normalized = platform |> string.lowercase |> string.trim
  case normalized {
    "" -> ""
    _ ->
      case string.contains(normalized, "youtube") {
        True -> "youtube"
        False ->
          case string.contains(normalized, "soundcloud") {
            True -> "soundcloud"
            False ->
              case string.contains(normalized, "spotify") {
                True -> "spotify"
                False ->
                  case string.contains(normalized, "bandcamp") {
                    True -> "bandcamp"
                    False ->
                      case string.contains(normalized, "itunes") {
                        True -> "itunes"
                        False ->
                          case string.contains(normalized, "file") {
                            True -> "file"
                            False -> "fishbone"
                          }
                      }
                  }
              }
          }
      }
  }
}

fn row_explicit_external_source_url(row: dynamic.Dynamic, service: String) -> String {
  let primary =
    decode_path_or(row, ["external_source_url"], "", decode.string)
    |> string.trim
  case primary != "" {
    True -> primary
    False -> {
      let legacy = decode_path_or(row, ["source_url"], "", decode.string)
      |> string.trim
      case legacy != "" {
        True -> legacy
        False -> {
          let keyed = decode_path_or(row, [service <> "_url"], "", decode.string)
          string.trim(keyed)
        }
      }
    }
  }
}

fn push_item_with_metadata(
  acc: #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)),
  row: dynamic.Dynamic,
  service: String,
  raw_source_id: String,
  preferred_title: String,
  artist: String,
  file_path: String,
  cover_path: String,
  tags: String,
  imported_date: Int,
) -> #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)) {
  let #(items, metadata) = acc
  let normalized = source_id_normalizer.normalize(service, raw_source_id)
  case normalized == "" {
    True -> acc
    False ->
      case
        core.track_item(
          service,
          raw_source_id,
          choose_title(preferred_title, normalized),
          choose_artist(artist),
          row_explicit_external_source_url(row, service),
        )
      {
        Ok(item) -> {
          let key = metadata_key(service, normalized)
          let metadata =
            dict.insert(
              metadata,
              key,
              ExportMetadata(file_path, cover_path, tags, imported_date),
            )
          #([item, ..items], metadata)
        }
        Error(_) -> acc
      }
  }
}

fn row_audio_path(row: dynamic.Dynamic) -> String {
  let fallback = decode_path_or(row, ["file_path"], "", decode.string)
  let mirror_md5 = decode_path_or(row, ["mirror_audio_md5"], "", decode.string)
  let mirror_ext = decode_path_or(row, ["mirror_audio_ext"], "", decode.string)
  prefer_hashed_path(mirror_md5, mirror_ext, fallback)
}

fn row_cover_path(row: dynamic.Dynamic) -> String {
  let fallback = decode_path_or(row, ["cover_path"], "", decode.string)
  let mirror_md5 = decode_path_or(row, ["mirror_cover_md5"], "", decode.string)
  let mirror_ext = decode_path_or(row, ["mirror_cover_ext"], "", decode.string)
  prefer_hashed_path(mirror_md5, mirror_ext, fallback)
}

pub fn prefer_hashed_path(md5: String, ext: String, fallback_path: String) -> String {
  let hashed = tuna_mirror_path.from_md5_source(md5, ext)
  case hashed == "" {
    True -> fallback_path |> string.trim
    False -> hashed
  }
}

fn metadata_key(service: String, source_id: String) -> String {
  service <> ":" <> source_id
}

fn row_compact_imported_date(row: dynamic.Dynamic) -> Int {
  decode_path_or(row, ["date_added"], "", decode.string)
  |> compact_datetime_to_int
}

fn row_tags_with_rating(row: dynamic.Dynamic) -> String {
  let rating = decode_path_or(row, ["rating"], 0, decode.int)
  normalize_tags_with_rating(row_tag_labels(row), rating)
}

fn row_tag_labels(row: dynamic.Dynamic) -> List(String) {
  decode_path_or(row, ["tags"], [], decode.list(of: decode.dynamic))
  |> list.fold([], fn(acc, tag) {
    let label = decode_path_or(tag, ["label"], "", decode.string)
    let emoji = decode_path_or(tag, ["emoji"], "", decode.string)
    case label != "" {
      True -> list.append(acc, [encode_tag_token(label, emoji)])
      False -> acc
    }
  })
}

fn normalize_tags_with_rating(tags: List(String), rating: Int) -> String {
  let rating_tag = ":rating:" <> int.to_string(rating)
  let normalized_tags =
    tags
    |> list.filter(fn(tag) {
      let #(label, _) = decode_tag_token(tag)
      !string.starts_with(string.lowercase(label), "rating")
    })
    |> list.map(format_export_tag)
  string.join(list.append(normalized_tags, [rating_tag]), " | ")
}

fn encode_tag_token(label: String, emoji: String) -> String {
  label <> "\u{001F}" <> emoji
}

fn decode_tag_token(token: String) -> #(String, String) {
  case string.split_once(token, "\u{001F}") {
    Ok(#(label, emoji)) -> #(string.trim(label), string.trim(emoji))
    Error(_) -> #(string.trim(token), "")
  }
}

fn format_export_tag(token: String) -> String {
  let #(label, emoji) = decode_tag_token(token)
  let #(category, value) = split_tag_label(label)
  "tag/" <> category <> "/" <> emoji <> ":" <> value
}

fn split_tag_label(label: String) -> #(String, String) {
  case string.split_once(label, ":") {
    Ok(#(category, value)) ->
      #(normalized_tag_part(category), normalized_tag_part(value))
    Error(_) -> #("label", normalized_tag_part(label))
  }
}

fn normalized_tag_part(value: String) -> String {
  let trimmed = string.trim(value)
  case trimmed == "" {
    True -> "unknown"
    False -> trimmed
  }
}

fn compact_datetime_to_int(value: String) -> Int {
  let digits =
    value
    |> string.to_graphemes
    |> list.filter(fn(char) {
      case int.parse(char) {
        Ok(_) -> True
        Error(_) -> False
      }
    })
    |> list.take(14)
    |> string.concat
  case int.parse(digits) {
    Ok(number) -> number
    Error(_) -> 0
  }
}

fn row_preferred_title(row: dynamic.Dynamic) -> String {
  let normalized_title =
    decode_path_or(row, ["normalized_title"], "", decode.string)
  case normalized_title != "" {
    True -> normalized_title
    False -> decode_path_or(row, ["title"], "", decode.string)
  }
}

fn row_artist(row: dynamic.Dynamic) -> String {
  decode_path_or(row, ["artist"], "", decode.string)
}

fn choose_title(preferred_title: String, fallback: String) -> String {
  case preferred_title != "" {
    True -> preferred_title
    False -> fallback
  }
}

fn choose_artist(artist: String) -> String {
  artist
}

fn apply_depth_limit(
  items: List(core.UnifiedItem),
  depth: core.DepthMode,
) -> List(core.UnifiedItem) {
  case depth {
    core.Depth1 -> list.take(items, 5)
    core.Depth2 -> list.take(items, 10)
    core.Depth3 -> list.take(items, 20)
    _ -> items
  }
}

fn decode_path_or(
  data: dynamic.Dynamic,
  path: List(String),
  fallback: a,
  decoder: decode.Decoder(a),
) -> a {
  decode.run(data, decode.optionally_at(path, fallback, decoder))
  |> result.unwrap(fallback)
}
