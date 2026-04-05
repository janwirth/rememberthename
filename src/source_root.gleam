//// Fetch parameters for each source adapter — no assertions, no selector strings.
////
//// `SourceRoot` is the single argument that determines *what* to fetch.
//// Validation limits (`SourceAssertSpec`) and selector logic live elsewhere.

import adapters/api_keys
import adapters/core
import gleam/dict
import gleam/list
import source_specs

pub type SourceRoot {
  BandcampRoot(
    profile_url: String,
    depth: core.DepthMode,
    timing: source_specs.SourceTimingSpec,
  )
  SoundcloudRoot(entry_point: String, depth: core.DepthMode)
  SpotifyRoot(credentials: api_keys.SpotifyCredentials, depth: core.DepthMode)
  YoutubeRoot(playlist_url: String, google_cloud_api_key: String)
  TunaRoot
}

/// Human-readable display name for the source (used in CLI progress output).
pub fn display_name(root: SourceRoot) -> String {
  case root {
    BandcampRoot(_, _, _) -> "Bandcamp"
    SoundcloudRoot(_, _) -> "Soundcloud"
    SpotifyRoot(_, _) -> "Spotify"
    YoutubeRoot(_, _) -> "Youtube"
    TunaRoot -> "Tuna"
  }
}

/// Return a copy of the root with a different `depth`, for cross-depth validation runs.
pub fn with_depth(root: SourceRoot, depth: core.DepthMode) -> SourceRoot {
  case root {
    BandcampRoot(url, _, timing) -> BandcampRoot(url, depth, timing)
    SoundcloudRoot(ep, _) -> SoundcloudRoot(ep, depth)
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
    SoundcloudRoot(entry_point, _) -> "soundcloud + " <> entry_point
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
    SoundcloudRoot(_, _) -> "soundcloud"
    SpotifyRoot(_, _) -> "spotify"
    YoutubeRoot(_, _) -> "youtube"
    TunaRoot -> "tuna"
  }
}

/// Ordered list of `#(key, SourceRoot, SourceAssertSpec)` triples in `source_specs.all()` order.
///
/// Sources for which credentials are absent are silently dropped (e.g. Spotify without token).
/// Use this instead of `source_specs.all()` when the caller only needs fetch-ready triples.
pub fn ordered_registry_list(
  keys: api_keys.ApiKeys,
) -> List(#(String, SourceRoot, source_specs.SourceAssertSpec)) {
  source_specs.all()
  |> list.filter_map(fn(spec) {
    let source_specs.SourceSpec(key, _, _, _, assert_spec) = spec
    case from_legacy_spec(spec, core.All, keys) {
      Ok(root) -> Ok(#(key, root, assert_spec))
      Error(_) -> Error(Nil)
    }
  })
}

/// Registry of all configured sources as `#(SourceRoot, SourceAssertSpec)` triples.
///
/// Keyed by stable selector string (`"bandcamp"`, `"soundcloud"`, …).
/// Panics if required credentials are absent — callers must ensure keys are loaded.
pub fn registry(
  keys: api_keys.ApiKeys,
) -> dict.Dict(String, #(SourceRoot, source_specs.SourceAssertSpec)) {
  source_specs.all()
  |> list.map(fn(spec) {
    let source_specs.SourceSpec(key, _, _, _, assert_spec) = spec
    let assert Ok(root) = from_legacy_spec(spec, core.All, keys)
    #(key, #(root, assert_spec))
  })
  |> dict.from_list
}

/// Look up a single triple from the registry.
pub fn triple(
  key: String,
  keys: api_keys.ApiKeys,
) -> Result(#(SourceRoot, source_specs.SourceAssertSpec), String) {
  case dict.get(registry(keys), key) {
    Ok(triple) -> Ok(triple)
    Error(_) -> Error("Unknown source key: " <> key)
  }
}

/// Map a legacy `SourceSpec` + runtime depth + API keys to a `SourceRoot`.
///
/// Returns `Error` if required credentials are absent (Spotify, YouTube).
pub fn from_legacy_spec(
  spec: source_specs.SourceSpec,
  depth: core.DepthMode,
  keys: api_keys.ApiKeys,
) -> Result(SourceRoot, api_keys.ResolveAdapterError) {
  let source_specs.SourceSpec(key, _, entry_point, timing_spec, _) = spec
  case key {
    "bandcamp" -> Ok(BandcampRoot(entry_point, depth, timing_spec))
    "soundcloud" -> Ok(SoundcloudRoot(entry_point, depth))
    "spotify" ->
      case api_keys.require_spotify_credentials(keys) {
        Ok(creds) -> Ok(SpotifyRoot(creds, depth))
        Error(e) -> Error(e)
      }
    "youtube" ->
      case api_keys.require_youtube_data_api_key(keys) {
        Ok(api_key) -> Ok(YoutubeRoot(entry_point, api_key))
        Error(e) -> Error(e)
      }
    _ -> Ok(TunaRoot)
  }
}
