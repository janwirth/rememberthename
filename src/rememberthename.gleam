//// Library API: list configured sources and run fetches without argv parsing.

import adapters/cache
import cli/source_selector as source_pick
import fetch_ops
import gleam/list
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

pub type FetchCache {
  ReadOnly
  Override
  Upsert
  Ignore
}

fn fetch_cache_as_mode(pref: FetchCache) -> cache.CacheMode {
  case pref {
    ReadOnly -> cache.CacheReadOnly
    Override -> cache.CacheOverride
    Upsert -> cache.CacheUpsert
    Ignore -> cache.CacheIgnore
  }
}

/// One configured source by selector (`"1"`, `"spotify"`, `"spotify-2"`, …). Not `"all"` — use [`fetch_all`](#fetch_all).
pub fn fetch_source(
  selector: String,
  cache: FetchCache,
) -> Result(Nil, String) {
  case selector == "all" {
    True -> Error("use fetch_all for all sources")
    False ->
      fetch_ops.fetch_with_cache_mode(selector, fetch_cache_as_mode(cache))
  }
}

/// The tuna integration source only.
pub fn fetch_tuna(cache: FetchCache) -> Result(Nil, String) {
  fetch_source("tuna", cache)
}

/// Every configured source, merged into `output/all_items_latest.json`.
pub fn fetch_all(cache: FetchCache) -> Nil {
  fetch_ops.fetch_all_sources(fetch_cache_as_mode(cache))
}
