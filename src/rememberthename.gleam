//// Library API: list configured sources and run fetches without argv parsing.

import adapters/cache
import cli/source_selector as source_pick
import fetch_ops
import gleam/list
import gleam/option.{type Option}
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

/// One track row returned by [`fetch_source_tracks`](#fetch_source_tracks) (no on-disk export).
pub type FetchTrackRow {
  FetchTrackRow(
    title: String,
    artist: String,
    service: String,
    source_id: String,
    /// Stable page URL when the adapter could resolve one; `None` when unknown.
    external_source_url: Option(String),
  )
}

fn track_view_to_row(view: visual_output.TrackView) -> FetchTrackRow {
  let visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    external_source_url,
    _,
    _,
    _,
    _,
  ) = view
  FetchTrackRow(title:, artist:, service:, source_id:, external_source_url:)
}

/// One configured source by selector (`"1"`, `"spotify"`, `"spotify-2"`, …). Not `"all"` — use [`fetch_all`](#fetch_all).
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
/// + Liked songs · user · batch 850 · +50 tracks · total 850 tracks · 1 lists
///
/// Done. items=120 lists=4 unresolved=0 files=80
/// JSON written: output/cli_result_tuna_depth_full.json
/// Export duration: 12ms
/// Validation: PASS
/// Resolve duration: 45000ms
/// ```
pub fn fetch_source(
  selector: String,
  cache: FetchCacheMode,
  on_update: fn(String) -> Nil,
) -> Result(Nil, String) {
  case selector == "all" {
    True -> Error("use fetch_all for all sources")
    False ->
      fetch_ops.fetch_with_cache_mode(
        selector,
        fetch_cache_as_mode(cache),
        on_update,
      )
  }
}

/// Resolve one source and return tracks in memory. Does **not** write
/// `output/cli_result_*.json` (unlike [`fetch_source`](#fetch_source)).
/// Progress lines match the same `on_update` contract.
pub fn fetch_source_tracks(
  selector: String,
  cache: FetchCacheMode,
  on_update: fn(String) -> Nil,
) -> Result(List(FetchTrackRow), String) {
  case fetch_ops.fetch_source_tracks(
    selector,
    fetch_cache_as_mode(cache),
    on_update,
  ) {
    Error(e) -> Error(e)
    Ok(views) -> Ok(list.map(views, track_view_to_row))
  }
}

/// The tuna integration source only — same `on_update` contract as [`fetch_source`](#fetch_source).
///
/// # Example
///
/// Same style of lines as `fetch_source` for the tuna key (header shows the tuna source name).
pub fn fetch_tuna(
  cache: FetchCacheMode,
  on_update: fn(String) -> Nil,
) -> Result(Nil, String) {
  fetch_source("tuna", cache, on_update)
}

/// Every configured source, merged into `output/all_items_latest.json`. Delivers per-source fetch
/// output through `on_update`, then canonical summary lines.
///
/// # Example (tail of `on_update`, illustrative)
///
/// ```text
/// Canonical JSON written: output/all_items_latest.json
/// Canonical info: items=500 files=300 duration=1200ms
/// ```
pub fn fetch_all(cache: FetchCacheMode, on_update: fn(String) -> Nil) -> Nil {
  fetch_ops.fetch_all_sources(fetch_cache_as_mode(cache), on_update)
}
