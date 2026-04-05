import adapters/cache
import adapters/core
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some, type Option, unwrap as option_unwrap}
import gleam/result
import gleam/string
import gleam/time/timestamp
import adapters/tuna/tuna_mirror_path
import adapters/tuna/tracks_source_ids_query
import source_id_normalizer

pub type ExportMetadata {
  ExportMetadata(
    file_path: String,
    cover_path: String,
    tags: String,
    imported_date: Int,
  )
}

/// One Gel `Track` JSON object: all fields read once per row (no repeated `decode.run` per push).
type TunaGelRow {
  TunaGelRow(
    normalized_title: String,
    title: String,
    artist: String,
    file_path: String,
    cover_path: String,
    mirror_audio_md5: String,
    mirror_audio_ext: String,
    mirror_cover_md5: String,
    mirror_cover_ext: String,
    date_added: String,
    rating: Int,
    tags: List(dynamic.Dynamic),
    created_on: String,
    created_at: String,
    source_created_at: String,
    fishbone_created_at: String,
    spotify_id: String,
    youtube_id: String,
    soundcloud_id: String,
    bandcamp_track_id: String,
    itunes_track_id: String,
    itunes_persistent_track_id: String,
    fishbone_source_platform: String,
    fishbone_source_id: String,
    external_source_url: String,
    source_url: String,
    spotify_url: String,
    youtube_url: String,
    soundcloud_url: String,
    bandcamp_url: String,
    file_url: String,
    itunes_url: String,
    fishbone_url: String,
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
  _depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> ResolveWithMetadataResult {
  let #(payload, #(cache_hits, cache_fetches)) =
    cached_tracks_source_ids_json(cache_mode, on_debug)
  on_debug(
    "[tuna] cache hits="
      <> int.to_string(cache_hits)
      <> " fetches="
      <> int.to_string(cache_fetches),
  )
  let t_decode_start = wall_ms()
  let rows = decode_rows(payload)
  let t_after_decode = wall_ms()
  on_debug(
    "[tuna] postprocessing: JSON decode "
      <> int.to_string(t_after_decode - t_decode_start)
      <> "ms rows="
      <> int.to_string(list.length(rows)),
  )
  let #(all_items, all_metadata) = rows_to_items_with_metadata(rows)
  let t_after_items = wall_ms()
  on_debug(
    "[tuna] postprocessing: rows→items "
      <> int.to_string(t_after_items - t_after_decode)
      <> "ms unified_items="
      <> int.to_string(list.length(all_items)),
  )
  on_debug(
    "[tuna] normalized_source_ids items="
      <> int.to_string(list.length(all_items)),
  )
  ResolveWithMetadataResult(
    resolve_result: core.ResolveResult(
      items: all_items,
      lists: [],
      unresolved: [],
    ),
    export_metadata: all_metadata,
  )
}

fn wall_ms() -> Int {
  let t = timestamp.system_time()
  let #(s, ns) = timestamp.to_unix_seconds_and_nanoseconds(t)
  s * 1000 + ns / 1_000_000
}

fn cached_tracks_source_ids_json(
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> #(String, #(Int, Int)) {
  let #(payload, roll) =
    cache.read_or_fetch(
      "tuna_tracks_source_ids_enriched_json",
      "tuna_main_default_track_sources_enriched",
      cache_mode,
      fn() {
        on_debug(
          "[tuna] database: starting gel query (gel -I tuna -b main query …)",
        )
        let raw = tracks_source_ids_query.fetch_tracks_source_ids_json()
        on_debug(
          "[tuna] database: gel response received (payload_chars="
            <> int.to_string(string.length(raw))
            <> ")",
        )
        raw
      },
    )
  let #(hits, fetches) = roll
  case fetches == 0 && hits > 0 {
    True ->
      on_debug("[tuna] database: payload from adapter cache (gel not run)")
    False -> Nil
  }
  case fetches == 0 && hits == 0 {
    True ->
      on_debug(
        "[tuna] database: no gel run (empty payload; read-only miss or cache miss)",
      )
    False -> Nil
  }
  #(payload, roll)
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

/// One `decode.run` per Gel row (all top-level fields in one composed decoder).
fn empty_tuna_gel_row() -> TunaGelRow {
  TunaGelRow(
    normalized_title: "",
    title: "",
    artist: "",
    file_path: "",
    cover_path: "",
    mirror_audio_md5: "",
    mirror_audio_ext: "",
    mirror_cover_md5: "",
    mirror_cover_ext: "",
    date_added: "",
    rating: 0,
    tags: [],
    created_on: "",
    created_at: "",
    source_created_at: "",
    fishbone_created_at: "",
    spotify_id: "",
    youtube_id: "",
    soundcloud_id: "",
    bandcamp_track_id: "",
    itunes_track_id: "",
    itunes_persistent_track_id: "",
    fishbone_source_platform: "",
    fishbone_source_id: "",
    external_source_url: "",
    source_url: "",
    spotify_url: "",
    youtube_url: "",
    soundcloud_url: "",
    bandcamp_url: "",
    file_url: "",
    itunes_url: "",
    fishbone_url: "",
  )
}

fn tuna_gel_row_decoder() -> decode.Decoder(TunaGelRow) {
  use normalized_title <- decode.optional_field(
    "normalized_title",
    "",
    decode.string,
  )
  use title <- decode.optional_field("title", "", decode.string)
  use artist <- decode.optional_field("artist", "", decode.string)
  use file_path <- decode.optional_field("file_path", "", decode.string)
  use cover_path <- decode.optional_field("cover_path", "", decode.string)
  use mirror_audio_md5 <- decode.optional_field(
    "mirror_audio_md5",
    "",
    decode.string,
  )
  use mirror_audio_ext <- decode.optional_field(
    "mirror_audio_ext",
    "",
    decode.string,
  )
  use mirror_cover_md5 <- decode.optional_field(
    "mirror_cover_md5",
    "",
    decode.string,
  )
  use mirror_cover_ext <- decode.optional_field(
    "mirror_cover_ext",
    "",
    decode.string,
  )
  use date_added <- decode.optional_field("date_added", "", decode.string)
  use rating <- decode.optional_field("rating", 0, decode.int)
  use tags <- decode.optional_field("tags", [], decode.list(decode.dynamic))
  use created_on <- decode.optional_field("created_on", "", decode.string)
  use created_at <- decode.optional_field("created_at", "", decode.string)
  use fishbone_created_at <- decode.optional_field(
    "fishbone_created_at",
    "",
    decode.string,
  )
  use spotify_id <- decode.optional_field("spotify_id", "", decode.string)
  use youtube_id <- decode.optional_field("youtube_id", "", decode.string)
  use soundcloud_id <- decode.optional_field("soundcloud_id", "", decode.string)
  use bandcamp_track_id <- decode.optional_field(
    "bandcamp_track_id",
    "",
    decode.string,
  )
  use itunes_track_id <- decode.optional_field(
    "itunes_track_id",
    "",
    decode.string,
  )
  use itunes_persistent_track_id <- decode.optional_field(
    "itunes_persistent_track_id",
    "",
    decode.string,
  )
  use fishbone_source_platform <- decode.optional_field(
    "fishbone_source_platform",
    "",
    decode.string,
  )
  use fishbone_source_id <- decode.optional_field(
    "fishbone_source_id",
    "",
    decode.string,
  )
  use external_source_url <- decode.optional_field(
    "external_source_url",
    "",
    decode.string,
  )
  use source_url <- decode.optional_field("source_url", "", decode.string)
  use spotify_url <- decode.optional_field("spotify_url", "", decode.string)
  use youtube_url <- decode.optional_field("youtube_url", "", decode.string)
  use soundcloud_url <- decode.optional_field(
    "soundcloud_url",
    "",
    decode.string,
  )
  use bandcamp_url <- decode.optional_field("bandcamp_url", "", decode.string)
  use file_url <- decode.optional_field("file_url", "", decode.string)
  use itunes_url <- decode.optional_field("itunes_url", "", decode.string)
  use fishbone_url <- decode.optional_field("fishbone_url", "", decode.string)
  decode.then(
    decode.optionally_at(["source", "created_at"], "", decode.string),
    fn(source_created_at) {
      decode.success(TunaGelRow(
        normalized_title: normalized_title,
        title: title,
        artist: artist,
        file_path: file_path,
        cover_path: cover_path,
        mirror_audio_md5: mirror_audio_md5,
        mirror_audio_ext: mirror_audio_ext,
        mirror_cover_md5: mirror_cover_md5,
        mirror_cover_ext: mirror_cover_ext,
        date_added: date_added,
        rating: rating,
        tags: tags,
        created_on: created_on,
        created_at: created_at,
        source_created_at: source_created_at,
        fishbone_created_at: fishbone_created_at,
        spotify_id: spotify_id,
        youtube_id: youtube_id,
        soundcloud_id: soundcloud_id,
        bandcamp_track_id: bandcamp_track_id,
        itunes_track_id: itunes_track_id,
        itunes_persistent_track_id: itunes_persistent_track_id,
        fishbone_source_platform: fishbone_source_platform,
        fishbone_source_id: fishbone_source_id,
        external_source_url: external_source_url,
        source_url: source_url,
        spotify_url: spotify_url,
        youtube_url: youtube_url,
        soundcloud_url: soundcloud_url,
        bandcamp_url: bandcamp_url,
        file_url: file_url,
        itunes_url: itunes_url,
        fishbone_url: fishbone_url,
      ))
    },
  )
}

fn decode_tuna_gel_row(d: dynamic.Dynamic) -> TunaGelRow {
  case decode.run(d, tuna_gel_row_decoder()) {
    Ok(row) -> row
    Error(_) -> empty_tuna_gel_row()
  }
}

fn gel_preferred_title(row: TunaGelRow) -> String {
  case row.normalized_title != "" {
    True -> row.normalized_title
    False -> row.title
  }
}

fn gel_audio_path(row: TunaGelRow) -> String {
  prefer_hashed_path(row.mirror_audio_md5, row.mirror_audio_ext, row.file_path)
}

fn gel_cover_path(row: TunaGelRow) -> String {
  prefer_hashed_path(row.mirror_cover_md5, row.mirror_cover_ext, row.cover_path)
}

fn tuna_tag_label_decoder() -> decode.Decoder(#(String, String)) {
  use label <- decode.optional_field("label", "", decode.string)
  use emoji <- decode.optional_field("emoji", "", decode.string)
  decode.success(#(label, emoji))
}

fn row_tag_labels_from_tags(tags: List(dynamic.Dynamic)) -> List(String) {
  list.fold(tags, [], fn(acc, tag) {
    case decode.run(tag, tuna_tag_label_decoder()) {
      Ok(#(label, emoji)) ->
        case label != "" {
          True -> [encode_tag_token(label, emoji), ..acc]
          False -> acc
        }
      Error(_) -> acc
    }
  })
  |> list.reverse
}

fn gel_tags_export_string(row: TunaGelRow) -> String {
  normalize_tags_with_rating(row_tag_labels_from_tags(row.tags), row.rating)
}

fn gel_imported_date(row: TunaGelRow) -> Int {
  compact_datetime_to_int(row.date_added)
}

fn gel_added_at_option(row: TunaGelRow) -> Option(String) {
  first_non_empty_string([
    row.created_on,
    row.created_at,
    row.source_created_at,
    row.fishbone_created_at,
    row.date_added,
  ])
  |> normalize_added_at_value
}

fn gel_external_url(row: TunaGelRow, service: String) -> String {
  let primary = string.trim(row.external_source_url)
  case primary != "" {
    True -> primary
    False -> {
      let legacy = string.trim(row.source_url)
      case legacy != "" {
        True -> legacy
        False -> {
          let keyed = case service {
            "spotify" -> row.spotify_url
            "youtube" -> row.youtube_url
            "soundcloud" -> row.soundcloud_url
            "bandcamp" -> row.bandcamp_url
            "file" -> row.file_url
            "itunes" -> row.itunes_url
            "fishbone" -> row.fishbone_url
            _ -> ""
          }
          string.trim(keyed)
        }
      }
    }
  }
}

fn rows_to_items_with_metadata(
  rows: List(dynamic.Dynamic),
) -> #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)) {
  list.fold(rows, #([], dict.new()), fn(acc, row_dyn) {
    let row = decode_tuna_gel_row(row_dyn)
    let preferred_title = gel_preferred_title(row)
    let artist = row.artist
    let file_path = gel_audio_path(row)
    let cover_path = gel_cover_path(row)
    let tags = gel_tags_export_string(row)
    let imported_date = gel_imported_date(row)
    let added_at = option_unwrap(gel_added_at_option(row), "")
    let acc =
      push_item_with_metadata(
        acc,
        row,
        added_at,
        "spotify",
        row.spotify_id,
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
        added_at,
        "youtube",
        row.youtube_id,
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
        added_at,
        "soundcloud",
        row.soundcloud_id,
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
        added_at,
        "bandcamp",
        row.bandcamp_track_id,
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
        added_at,
        "file",
        row.file_path,
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
        added_at,
        "itunes",
        row.itunes_track_id,
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
        added_at,
        "itunes",
        row.itunes_persistent_track_id,
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
      added_at,
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
  row: TunaGelRow,
  added_at: String,
  preferred_title: String,
  artist: String,
  file_path: String,
  cover_path: String,
  tags: String,
  imported_date: Int,
) -> #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)) {
  let service = fishbone_service_for_platform(row.fishbone_source_platform)
  case service == "" || row.fishbone_source_id == "" {
    True -> acc
    False ->
      push_item_with_metadata(
        acc,
        row,
        added_at,
        service,
        row.fishbone_source_id,
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

fn push_item_with_metadata(
  acc: #(List(core.UnifiedItem), dict.Dict(String, ExportMetadata)),
  row: TunaGelRow,
  added_at: String,
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
        core.track_item_with_added_at(
          service,
          raw_source_id,
          choose_title(preferred_title, normalized),
          choose_artist(artist),
          gel_external_url(row, service),
          added_at,
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

fn first_non_empty_string(values: List(String)) -> String {
  case values {
    [] -> ""
    [value, ..rest] ->
      case string.trim(value) {
        "" -> first_non_empty_string(rest)
        cleaned -> cleaned
      }
  }
}

fn normalize_added_at_value(value: String) -> Option(String) {
  let cleaned = string.trim(value)
  case is_iso8601_utc(cleaned) {
    True -> Some(cleaned)
    False ->
      case is_date_only(cleaned) {
        True -> Some(cleaned <> "T00:00:00Z")
        False ->
          case is_datetime_no_timezone(cleaned) {
            True -> Some(string.replace(cleaned, " ", "T") <> "Z")
            False -> None
          }
      }
  }
}

fn is_date_only(value: String) -> Bool {
  list.length(string.to_graphemes(value)) == 10
  && slice(value, 4, 1) == "-"
  && slice(value, 7, 1) == "-"
  && is_digits(slice(value, 0, 4))
  && is_digits(slice(value, 5, 2))
  && is_digits(slice(value, 8, 2))
}

fn is_datetime_no_timezone(value: String) -> Bool {
  list.length(string.to_graphemes(value)) == 19
  && slice(value, 4, 1) == "-"
  && slice(value, 7, 1) == "-"
  && slice(value, 10, 1) == " "
  && slice(value, 13, 1) == ":"
  && slice(value, 16, 1) == ":"
  && is_digits(slice(value, 0, 4))
  && is_digits(slice(value, 5, 2))
  && is_digits(slice(value, 8, 2))
  && is_digits(slice(value, 11, 2))
  && is_digits(slice(value, 14, 2))
  && is_digits(slice(value, 17, 2))
}

fn is_iso8601_utc(value: String) -> Bool {
  list.length(string.to_graphemes(value)) >= 20
  && string.ends_with(value, "Z")
  && slice(value, 4, 1) == "-"
  && slice(value, 7, 1) == "-"
  && slice(value, 10, 1) == "T"
  && slice(value, 13, 1) == ":"
  && slice(value, 16, 1) == ":"
  && is_digits(slice(value, 0, 4))
  && is_digits(slice(value, 5, 2))
  && is_digits(slice(value, 8, 2))
  && is_digits(slice(value, 11, 2))
  && is_digits(slice(value, 14, 2))
  && is_digits(slice(value, 17, 2))
}

fn is_digits(value: String) -> Bool {
  let chars = string.to_graphemes(value)
  chars != [] && list.all(chars, is_ascii_digit)
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

fn slice(value: String, at_index: Int, length: Int) -> String {
  string.slice(value, at_index: at_index, length: length)
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

fn choose_title(preferred_title: String, fallback: String) -> String {
  case preferred_title != "" {
    True -> preferred_title
    False -> fallback
  }
}

fn choose_artist(artist: String) -> String {
  artist
}
