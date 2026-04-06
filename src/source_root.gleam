//// Fetch parameters for each source adapter — no assertions in the fetch path.
////
//// `SourceRoot` is the single argument that determines *what* to fetch at resolve time.
//// `CatalogRoot` + `SourceAssertSpec` describe configured integration rows; `source_specs`
//// supplies the concrete list.

import adapters/api_keys
import adapters/core
import gleam/dict
import gleam/list

/// Per-source HTTP queue policy (Bandcamp carries it on `SourceRoot`; catalog rows use it for validation / resolve helpers).
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

/// Static row identity: URLs and timing. Hydrate to `SourceRoot` with `from_catalog` + API keys.

pub type SourceRoot {
  BandcampRoot(
    profile_url: String,
    depth: core.DepthMode,
    timing: SourceTimingSpec,
  )
  SoundcloudRoot(entry_point: String, depth: core.DepthMode, timing: SourceTimingSpec)
  SpotifyRoot(credentials: api_keys.SpotifyCredentials, depth: core.DepthMode)
  YoutubeRoot(playlist_url: String, google_cloud_api_key: String)
  TunaRoot
}


/// Human-readable display name for the source (used in CLI progress output).
pub fn display_name(root: SourceRoot) -> String {
  case root {
    BandcampRoot(_, _, _) -> "Bandcamp"
    SoundcloudRoot(_, _, _) -> "Soundcloud"
    SpotifyRoot(_, _) -> "Spotify"
    YoutubeRoot(_, _) -> "Youtube"
    TunaRoot -> "Tuna"
  }
}

/// Return a copy of the root with a different `depth`, for cross-depth validation runs.
pub fn with_depth(root: SourceRoot, depth: core.DepthMode) -> SourceRoot {
  case root {
    BandcampRoot(url, _, timing) -> BandcampRoot(url, depth, timing)
    SoundcloudRoot(ep, _, timing) -> SoundcloudRoot(ep, depth, timing)
    SpotifyRoot(creds, _) -> SpotifyRoot(creds, depth)
    YoutubeRoot(url, key) -> YoutubeRoot(url, key)
    // YouTube ignores depth (single flat playlist); Tuna has no depth field.
    TunaRoot -> TunaRoot
  }
}

/// Stable label identifying the fetch source for JSON output (mirrors `track_view.adapter_id_for_source`).
pub fn adapter_id(root: SourceRoot) -> String {
  case root {
    BandcampRoot(profile_url, _, _) -> "bandcamp + " <> profile_url
    SoundcloudRoot(entry_point, _, _) -> "soundcloud + " <> entry_point
    SpotifyRoot(_, _) -> "spotify + liked"
    YoutubeRoot(playlist_url, _) -> "youtube + " <> playlist_url
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
    BandcampRoot(_, _, _) -> "bandcamp"
    SoundcloudRoot(_, _, _) -> "soundcloud"
    SpotifyRoot(_, _) -> "spotify"
    YoutubeRoot(_, _) -> "youtube"
    TunaRoot -> "tuna"
  }
}
