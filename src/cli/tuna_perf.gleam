import adapters/cache
import adapters/core
import adapters/tuna/normalized_source as tuna_normalized_source
import cli/export_json
import cli/runtime
import cli/track_view
import gleam/list
import simplifile
import source_root
import source_specs

/// Runs a full tuna resolve+JSON write and returns how long the file write took (ms).
pub fn tuna_export_duration_ms(cache_mode: cache.CacheMode) -> Int {
  let #(_, tuna_root, _) = source_specs.tuna()
  let key = source_root.source_key(tuna_root)
  let entry_point = source_root.listing_entry_point(tuna_root)
  let tuna_normalized_source.ResolveWithMetadataResult(result, metadata_index) =
    tuna_normalized_source.resolve_with_metadata(core.All, cache_mode, fn(_line) {
      Nil
    })
  let core.ResolveResult(items, _, _) = result
  let adapter_id = track_view.adapter_id_for_source(key, entry_point)
  let tracks = list.map(items, fn(item) {
    track_view.to_tuna_track_view(item, adapter_id, metadata_index)
  })
  let imported_dates = track_view.imported_dates_for_items(items, metadata_index)
  let content =
    export_json.tracks_json_with_imported_dates(tracks, imported_dates, False)
  let export_start_ms = runtime.now_ms()
  let _ =
    simplifile.write(
      content,
      to: export_json.artifact_path("tuna_export_perf_probe.json"),
    )
  runtime.now_ms() - export_start_ms
}
