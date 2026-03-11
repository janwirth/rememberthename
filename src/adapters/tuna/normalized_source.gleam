import adapters/cache
import adapters/core
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
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
    "tuna_tracks_source_ids_json",
    "tuna_main_default_track_sources",
    cache_mode,
    tracks_source_ids_json,
  )
}

fn decode_rows(payload: String) -> List(dynamic.Dynamic) {
  case json.parse(payload, decode.dynamic) {
    Error(_) -> []
    Ok(value) -> decode.run(value, decode.list(of: decode.dynamic)) |> result.unwrap([])
  }
}

fn rows_to_items(rows: List(dynamic.Dynamic)) -> List(core.UnifiedItem) {
  list.fold(rows, [], fn(acc, row) {
    let acc = push_item(acc, "spotify", decode_path_or(row, ["spotify_id"], "", decode.string))
    let acc = push_item(acc, "youtube", decode_path_or(row, ["youtube_id"], "", decode.string))
    let acc =
      push_item(acc, "soundcloud", decode_path_or(row, ["soundcloud_id"], "", decode.string))
    let acc =
      push_item(acc, "bandcamp", decode_path_or(row, ["bandcamp_track_id"], "", decode.string))
    let acc = push_item(acc, "file", decode_path_or(row, ["dropped_path"], "", decode.string))
    let acc = push_item(acc, "itunes", decode_path_or(row, ["itunes_track_id"], "", decode.string))
    push_item(
      acc,
      "itunes",
      decode_path_or(row, ["itunes_persistent_track_id"], "", decode.string),
    )
  })
  |> list.reverse
}

fn push_item(
  acc: List(core.UnifiedItem),
  service: String,
  raw_source_id: String,
) -> List(core.UnifiedItem) {
  let normalized = source_id_normalizer.normalize(service, raw_source_id)
  case normalized == "" {
    True -> acc
    False -> [
      core.UnifiedItem(
        id: "tuna:normalized:" <> service <> ":" <> normalized <> ":" <> raw_source_id,
        title: normalized,
        artist: raw_source_id,
        service: service,
        source_type: "item",
        source_id: normalized,
      ),
      ..acc
    ]
  }
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
