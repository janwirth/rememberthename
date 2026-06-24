import adapters/core
import adapters/tuna/normalized_source as tuna_normalized_source
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import output/visual_output

/// Stable label combining source kind and entry URL/path for JSON output.
pub fn adapter_id_for_source(source_type: String, entry_point: String) -> String {
  source_type <> " + " <> entry_point
}

/// Builds a `TrackView` without tuna-specific file/cover/tags fields.
pub fn to_track_view(
  item: core.UnifiedItem,
  adapter_id: String,
) -> visual_output.TrackView {
  let core.UnifiedItem(
    _,
    title,
    artist,
    service,
    _,
    source_id,
    external_source_url,
    cover_url,
    file_path,
    added_at,
    _,
    _,
    _,
  ) =
    item
  visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    external_source_url,
    added_at,
    adapter_id,
    option.unwrap(file_path, ""),
    cover_url,
    "",
  )
}

/// Looks up tuna `ExportMetadata` for a track or returns empty placeholders.
pub fn tuna_metadata_for(
  metadata_index: dict.Dict(String, tuna_normalized_source.ExportMetadata),
  service: String,
  source_id: String,
) -> tuna_normalized_source.ExportMetadata {
  metadata_index
  |> dict.get(tuna_metadata_key(service, source_id))
  |> result.unwrap(tuna_normalized_source.ExportMetadata("", "", "", 0))
}

/// Composite key `service:source_id` for tuna export dictionaries.
pub fn tuna_metadata_key(service: String, source_id: String) -> String {
  service <> ":" <> source_id
}

/// Collects positive `imported_date` values from metadata into a flat map.
pub fn imported_dates_for_items(
  items: List(core.UnifiedItem),
  metadata_index: dict.Dict(String, tuna_normalized_source.ExportMetadata),
) -> dict.Dict(String, Int) {
  list.fold(items, dict.new(), fn(acc, item) {
    let core.UnifiedItem(_, _, _, service, _, source_id, _, _, _, _, _, _, _) = item
    case dict.get(metadata_index, tuna_metadata_key(service, source_id)) {
      Ok(tuna_normalized_source.ExportMetadata(_, _, _, imported_date))
        if imported_date > 0 ->
        dict.insert(acc, tuna_metadata_key(service, source_id), imported_date)
      _ -> acc
    }
  })
}

/// Like `to_track_view` but fills download, cover, and tags from the tuna export index.
pub fn to_tuna_track_view(
  item: core.UnifiedItem,
  adapter_id: String,
  metadata_index: dict.Dict(String, tuna_normalized_source.ExportMetadata),
) -> visual_output.TrackView {
  let core.UnifiedItem(
    _,
    title,
    artist,
    service,
    _,
    source_id,
    external_source_url,
    item_cover_url,
    item_file_path,
    added_at,
    _,
    _,
    _,
  ) =
    item
  let tuna_normalized_source.ExportMetadata(download, cover, tags, _) =
    tuna_metadata_for(metadata_index, service, source_id)
  let cover_out = case string.trim(cover) {
    "" -> item_cover_url
    value -> option.Some(value)
  }
  visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    external_source_url,
    added_at,
    adapter_id,
    case download {
      "" -> option.unwrap(item_file_path, "")
      value -> value
    },
    cover_out,
    tags,
  )
}

/// Maps depth label to a safe filename segment (`full` stays `full`).
pub fn sanitize_depth_label(value: String) -> String {
  case value {
    "full" -> "full"
    _ -> value
  }
}
