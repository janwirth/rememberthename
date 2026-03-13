import adapters/cache
import adapters/core
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import source_id_normalizer

@external(erlang, "tuna_runtime", "tracks_source_ids_json")
fn tracks_source_ids_json() -> String

pub fn resolve(
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let payload = cached_tracks_source_ids_json(cache_mode)
  let rows = decode_rows(payload)
  let all_items = rows_to_items(rows)
  let items = apply_depth_limit(all_items, depth)
  on_debug(
    "[tuna] normalized_source_ids total="
    <> int.to_string(list.length(all_items))
    <> " returned="
    <> int.to_string(list.length(items)),
  )
  core.ResolveResult(items: items, lists: [], unresolved: [])
}

fn cached_tracks_source_ids_json(cache_mode: cache.CacheMode) -> String {
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

fn rows_to_items(rows: List(dynamic.Dynamic)) -> List(core.UnifiedItem) {
  list.fold(rows, [], fn(acc, row) {
    let preferred_title = row_preferred_title(row)
    let artist = row_artist(row)
    let acc =
      push_item(
        acc,
        "spotify",
        decode_path_or(row, ["spotify_id"], "", decode.string),
        preferred_title,
        artist,
      )
    let acc =
      push_item(
        acc,
        "youtube",
        decode_path_or(row, ["youtube_id"], "", decode.string),
        preferred_title,
        artist,
      )
    let acc =
      push_item(
        acc,
        "soundcloud",
        decode_path_or(row, ["soundcloud_id"], "", decode.string),
        preferred_title,
        artist,
      )
    let acc =
      push_item(
        acc,
        "bandcamp",
        decode_path_or(row, ["bandcamp_track_id"], "", decode.string),
        preferred_title,
        artist,
      )
    let acc =
      push_item(
        acc,
        "file",
        decode_path_or(row, ["file_path"], "", decode.string),
        preferred_title,
        artist,
      )
    let acc =
      push_item(
        acc,
        "itunes",
        decode_path_or(row, ["itunes_track_id"], "", decode.string),
        preferred_title,
        artist,
      )
    push_item(
      acc,
      "itunes",
      decode_path_or(row, ["itunes_persistent_track_id"], "", decode.string),
      preferred_title,
      artist,
    )
  })
  |> list.reverse
}

fn push_item(
  acc: List(core.UnifiedItem),
  service: String,
  raw_source_id: String,
  preferred_title: String,
  artist: String,
) -> List(core.UnifiedItem) {
  let normalized = source_id_normalizer.normalize(service, raw_source_id)
  case normalized == "" {
    True -> acc
    False ->
      case
        core.track_item(
          service,
          normalized,
          choose_title(preferred_title, normalized),
          choose_artist(artist),
        )
      {
        Ok(item) -> [item, ..acc]
        Error(_) -> acc
      }
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
