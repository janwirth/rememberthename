import adapters/core
import cli/tuna_tags
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import output/visual_output

/// Path under `output/` for CLI-written JSON and probe files.
pub fn artifact_path(file_name: String) -> String {
  "output/" <> file_name
}

/// `None` when path is blank/whitespace; otherwise trimmed `Some`.
pub fn nullable_file_path(path: String) -> Option(String) {
  let cleaned = string.trim(path)
  case cleaned == "" {
    True -> None
    False -> Some(cleaned)
  }
}

/// JSON string path or `null` if not present.
pub fn nullable_file_json(path: String) -> json.Json {
  case nullable_file_path(path) {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

/// JSON integer or `null` for missing optional numbers.
pub fn nullable_int_json(value: Option(Int)) -> json.Json {
  case value {
    Some(number) -> json.int(number)
    None -> json.null()
  }
}

/// Counts tracks whose `download` path is non-empty after trim.
pub fn count_tracks_with_file(tracks: List(visual_output.TrackView)) -> Int {
  tracks
  |> list.filter(fn(track) {
    let visual_output.TrackView(_, _, _, _, _, _, _, download, _, _) = track
    case nullable_file_path(download) {
      Some(_) -> True
      None -> False
    }
  })
  |> list.length
}

/// Serializes tracks to a JSON array string with normalized tags and no imported dates.
pub fn tracks_json(tracks: List(visual_output.TrackView)) -> String {
  tracks_json_with_imported_dates(tracks, dict.new(), True)
}

/// JSON array of track objects, optionally attaching `imported_date` and tag normalization.
pub fn tracks_json_with_imported_dates(
  tracks: List(visual_output.TrackView),
  imported_dates: dict.Dict(String, Int),
  normalize_tags: Bool,
) -> String {
  tracks
  |> tracks_with_order(list.length(tracks))
  |> json.array(of: fn(track_with_order) {
    track_json_with_order(track_with_order, imported_dates, normalize_tags)
  })
  |> json.to_string
}

/// Zips tracks with descending `order` integers (list length down to 1).
fn tracks_with_order(
  tracks: List(visual_output.TrackView),
  order: Int,
) -> List(#(visual_output.TrackView, Int)) {
  case tracks {
    [] -> []
    [track, ..rest] -> [#(track, order), ..tracks_with_order(rest, order - 1)]
  }
}

/// One track as `json.Json` including optional file paths and tag array.
fn track_json_with_order(
  track_with_order: #(visual_output.TrackView, Int),
  imported_dates: dict.Dict(String, Int),
  normalize_tags: Bool,
) -> json.Json {
  let #(track, order) = track_with_order
  let visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    external_source_url,
    added_at,
    adapter_id,
    download,
    cover,
    tags,
  ) = track
  let imported_date = case dict.get(imported_dates, service <> ":" <> source_id) {
    Ok(value) if value > 0 -> Some(value)
    _ -> None
  }
  let external_url_json = case external_source_url {
    Some(url) -> json.string(url)
    None -> json.null()
  }
  let added_at_json = case core.added_at_display(added_at) {
    "" -> json.null()
    value -> json.string(value)
  }
  json.object([
    #("title", json.string(title)),
    #("artist", json.string(artist)),
    #("service", json.string(service)),
    #("source_id", json.string(source_id)),
    #("external_source_url", external_url_json),
    #("added_at", added_at_json),
    #("order", json.int(order)),
    #("imported_date", nullable_int_json(imported_date)),
    #("adapter_id", json.string(adapter_id)),
    #("file", nullable_file_json(download)),
    #("cover", nullable_file_json(cover)),
    #("tags", json.array(tuna_tags.export_tags_with_mode(tags, normalize_tags), of: json.string)),
  ])
}
