//// Fetch parameters for each source adapter — no assertions in the fetch path.
////
//// `SourceRoot` is the single argument that determines *what* to fetch at resolve time.
//// `source_specs` supplies `#(title, SourceRoot, SourceAssertSpec)` rows.

import adapters/api_keys
import adapters/core
import gleam/list
import gleam/option
import gleam/string

/// Per-source HTTP queue policy (Bandcamp and Soundcloud carry it on `SourceRoot`).
pub type SourceTimingSpec {
  SourceTimingSpec(max_concurrency: Int, requests_per_second: Int)
}

/// Dev validation limits and title anchors (consumers: `validate_all`, artifact checks).
pub type SourceAssertSpec {
  SourceAssertSpec(
    min_depth_1_items: Int,
    min_full_items: Int,
    source_limit: Int,
    first_items_to_preserve: Int,
    anchor_fragments: List(String),
    required_full_fragments: List(String),
  )
}

pub type SourceRoot {
  BandcampRoot(
    profile_url: String,
    depth: core.DepthMode,
    timing: SourceTimingSpec,
    fetch_newer_than: option.Option(String),
  )
  SoundcloudRoot(
    entry_point: String,
    depth: core.DepthMode,
    timing: SourceTimingSpec,
    fetch_newer_than: option.Option(String),
  )
  SpotifyRoot(
    credentials: api_keys.SpotifyCredentials,
    depth: core.DepthMode,
    fetch_newer_than: option.Option(String),
  )
  YoutubeRoot(
    playlist_url: String,
    google_cloud_api_key: String,
    fetch_newer_than: option.Option(String),
  )
  TunaRoot
}

/// Entry point string for listings / validate output (mirrors former `catalog_entry_point`).
pub fn listing_entry_point(root: SourceRoot) -> String {
  case root {
    BandcampRoot(url, _, _, _) -> url
    SoundcloudRoot(ep, _, _, _) -> ep
    SpotifyRoot(_, _, _) -> "https://open.spotify.com/user/liked"
    YoutubeRoot(url, _, _) -> url
    TunaRoot -> "gel:tuna/main::default::Track"
  }
}

/// `#(selector_key, root, assert)` for orchestration (`triple_by_selector` expects this shape).
pub fn ordered_selector_triples(
  rows: List(#(String, SourceRoot, SourceAssertSpec)),
) -> List(#(String, SourceRoot, SourceAssertSpec)) {
  list.map(rows, fn(row) {
    let #(_title, root, assert_spec) = row
    #(source_key(root), root, assert_spec)
  })
}

/// Human-readable display name for the source (used in CLI progress output).
pub fn display_name(root: SourceRoot) -> String {
  case root {
    BandcampRoot(url, _, _, _) ->
      case string.contains(url, "/wishlist") {
        True -> "Bandcamp Wishlist"
        False -> "Bandcamp Purchases"
      }
    SoundcloudRoot(_, _, _, _) -> "Soundcloud"
    SpotifyRoot(_, _, _) -> "Spotify"
    YoutubeRoot(_, _, _) -> "Youtube"
    TunaRoot -> "Tuna"
  }
}

/// Return a copy of the root with a different `depth`, for cross-depth validation runs.
pub fn with_depth(root: SourceRoot, depth: core.DepthMode) -> SourceRoot {
  case root {
    BandcampRoot(url, _, timing, fetch_newer_than) ->
      BandcampRoot(url, depth, timing, fetch_newer_than)
    SoundcloudRoot(ep, _, timing, fetch_newer_than) ->
      SoundcloudRoot(ep, depth, timing, fetch_newer_than)
    SpotifyRoot(creds, _, fetch_newer_than) -> SpotifyRoot(creds, depth, fetch_newer_than)
    YoutubeRoot(url, key, fetch_newer_than) -> YoutubeRoot(url, key, fetch_newer_than)
    // YouTube ignores depth (single flat playlist); Tuna has no depth field.
    TunaRoot -> TunaRoot
  }
}

/// Return a copy of the root with a different `fetch_newer_than`, for incremental fetch.
pub fn with_newer_than(root: SourceRoot, fetch_newer_than: option.Option(String)) -> SourceRoot {
  case root {
    BandcampRoot(url, depth, timing, _) ->
      BandcampRoot(url, depth, timing, fetch_newer_than)
    SoundcloudRoot(ep, depth, timing, _) ->
      SoundcloudRoot(ep, depth, timing, fetch_newer_than)
    SpotifyRoot(creds, depth, _) -> SpotifyRoot(creds, depth, fetch_newer_than)
    YoutubeRoot(url, key, _) -> YoutubeRoot(url, key, fetch_newer_than)
    TunaRoot -> TunaRoot
  }
}

/// Stable label identifying the fetch source for JSON output (mirrors `track_view.adapter_id_for_source`).
pub fn adapter_id(root: SourceRoot) -> String {
  case root {
    BandcampRoot(profile_url, _, _, _) -> {
      let feed_label = case string.contains(profile_url, "/wishlist") {
        True -> "bandcamp_wishlist + "
        False -> "bandcamp_purchases + "
      }
      feed_label <> profile_url
    }
    SoundcloudRoot(entry_point, _, _, _) -> "soundcloud + " <> entry_point
    SpotifyRoot(_, _, _) -> "spotify + liked"
    YoutubeRoot(playlist_url, _, _) -> "youtube + " <> playlist_url
    TunaRoot -> "tuna + gel:tuna/main::default::Track"
  }
}

/// Output JSON artifact path for a `fetch_and_save_json` result.
///
/// Convention: `output/<source_key>_full.json` — derived solely from the root variant.
pub fn artifact_json_path(root: SourceRoot) -> String {
  "output/" <> source_key(root) <> "_full.json"
}

/// Selector key string derived from the root variant.
pub fn source_key(root: SourceRoot) -> String {
  case root {
    BandcampRoot(url, _, _, _) ->
      case string.contains(url, "/wishlist") {
        True -> "bandcamp_wishlist"
        False -> "bandcamp_purchases"
      }
    SoundcloudRoot(_, _, _, _) -> "soundcloud"
    SpotifyRoot(_, _, _) -> "spotify"
    YoutubeRoot(_, _, _) -> "youtube"
    TunaRoot -> "tuna"
  }
}
