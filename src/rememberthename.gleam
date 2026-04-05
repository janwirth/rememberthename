//// Library API: list configured sources and run fetches without argv parsing.

import adapters/cache
import cli/fetch_orchestration
import cli/source_selector as source_pick
import gleam/list
import gleam/option.{type Option}
import gleam/time/timestamp
import output/visual_output
import source_specs

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

pub type SourceListing {
  SourceListing(
    index: Int,
    key: String,
    name: String,
    entry_point: String,
    rank_for_key: Int,
  )
}

/// Configured integration sources in CLI order (index is 1-based).
///
/// # Example
///
/// One row (values come from your `source_specs`):
///
/// ```text
/// SourceListing(index: 1, key: "tuna", name: "Tuna", entry_point: "~/Music/tuna", rank_for_key: 1)
/// ```
pub fn list_sources() -> List(SourceListing) {
  list_sources_acc(source_specs.all(), 1, [])
}

fn list_sources_acc(
  sources: List(source_specs.SourceSpec),
  index: Int,
  acc: List(SourceListing),
) -> List(SourceListing) {
  case sources {
    [] -> list.reverse(acc)
    [source, ..rest] -> {
      let source_specs.SourceSpec(key, name, entry_point, _, _) = source
      let rank =
        source_pick.provider_rank_for_index(
          source_specs.all(),
          key,
          index,
          1,
          0,
        )
      list_sources_acc(rest, index + 1, [
        SourceListing(index, key, name, entry_point, rank),
        ..acc,
      ])
    }
  }
}

// ---------------------------------------------------------------------------
// Fetch
// ---------------------------------------------------------------------------

/// Adapter cache policy for fetches: `ReadOnly` uses existing rows only; `Override` replaces;
/// `Upsert` merges; `Ignore` skips cache reads and writes (same semantics as `adapters/cache.CacheMode`).
pub type FetchCacheMode {
  ReadOnly
  Override
  Upsert
  Ignore
}

fn fetch_cache_as_mode(pref: FetchCacheMode) -> cache.CacheMode {
  case pref {
    ReadOnly -> cache.CacheReadOnly
    Override -> cache.CacheOverride
    Upsert -> cache.CacheUpsert
    Ignore -> cache.CacheIgnore
  }
}

/// One track row returned by [`fetch_source`](#fetch_source).
pub type FetchTrackRow {
  FetchTrackRow(
    /// Example: `"Windowlicker"`
    title: String,
    /// Example: `"Aphex Twin"`
    artist: String,
    /// Example: `"spotify"` (also `"youtube"`, `"soundcloud"`, `"bandcamp"`, `"tuna"`)
    service: String,
    /// Example: `"3VQAKWf7U8s3B7vQfQ8kqM"` (service-specific id format)
    source_id: String,
    /// Example: `Some("https://open.spotify.com/track/3VQAKWf7U8s3B7vQfQ8kqM")` or `None`
    /// Stable page URL when the adapter could resolve one; `None` when unknown.
    external_source_url: Option(String),
    /// When known, the instant the source reported; [`timestamp.unix_epoch`] when missing.
    added_at: timestamp.Timestamp,
  )
}

fn track_view_to_row(view: visual_output.TrackView) -> FetchTrackRow {
  let visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    external_source_url,
    added_at,
    _,
    _,
    _,
    _,
  ) = view
  FetchTrackRow(
    title: title,
    artist: artist,
    service: service,
    source_id: source_id,
    external_source_url: external_source_url,
    added_at: added_at,
  )
}

/// One configured source by selector (`"1"`, `"spotify"`, `"spotify-2"`, …). Not `"all"` — this public API
/// resolves one source at a time.
///
/// Resolver progress, timings, and paths are sent one line at a time to `on_update` (may include ANSI
/// color sequences). Use `fn(_) { Nil }` to silence.
///
/// # Example (`on_update` lines, illustrative)
///
/// ```text
/// Fetching source 1: Tuna
/// Depth: full
/// Cache: read-only
///
/// + Liked songs · user · batch 850 · +50 tracks · total 850 tracks · 1 lists · cache hits=2 fetches=1
///
/// Done. items=120 lists=4 unresolved=0 files=80
/// JSON written: output/tuna_full.json
/// Export duration: 12ms
/// Validation: PASS
/// Resolve duration: 45000ms
/// ```
pub fn fetch_source(
  selector: String,
  cache: FetchCacheMode,
  write_to_json_file: Bool,
  on_update: fn(String) -> Nil,
) -> Result(List(FetchTrackRow), String) {
  case selector == "all" {
    True -> Error("selector 'all' is private; use CLI for full export")
    False ->
      case selector == "tuna" {
        True -> fetch_tuna(cache, write_to_json_file, on_update)
        False ->
          case fetch_orchestration.fetch_source_tracks(
            selector,
            fetch_cache_as_mode(cache),
            write_to_json_file,
            True,
            on_update,
          ) {
            Error(e) -> Error(e)
            Ok(views) -> Ok(list.map(views, track_view_to_row))
          }
      }
  }
}

/// Private convenience for tuna-only fetches.
fn fetch_tuna(
  cache: FetchCacheMode,
  write_to_json_file: Bool,
  on_update: fn(String) -> Nil,
) -> Result(List(FetchTrackRow), String) {
  case fetch_orchestration.fetch_source_tracks(
    "tuna",
    fetch_cache_as_mode(cache),
    write_to_json_file,
    True,
    on_update,
  ) {
    Error(e) -> Error(e)
    Ok(views) -> Ok(list.map(views, track_view_to_row))
  }
}
