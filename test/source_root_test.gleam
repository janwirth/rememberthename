import adapters/api_keys
import adapters/core
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleeunit/should
import source_root
import source_specs

fn empty_keys() -> api_keys.ApiKeys {
  api_keys.ApiKeys(spotify: None, google_cloud: None)
}

fn fake_spotify_keys() -> api_keys.ApiKeys {
  api_keys.ApiKeys(
    spotify: Some(api_keys.SpotifyCredentials(
      access_token: "tok",
      refresh_token: "ref",
      client_id: "cid",
      client_secret: "cs",
      redirect_uri: "https://localhost",
    )),
    google_cloud: None,
  )
}

fn fake_youtube_keys() -> api_keys.ApiKeys {
  api_keys.ApiKeys(spotify: None, google_cloud: Some("yt-key"))
}

pub fn bandcamp_maps_url_depth_and_timing_test() {
  let spec = source_specs.bandcamp()
  let source_specs.SourceSpec(_, _, entry_point, timing_spec, _) = spec
  let result = source_root.from_legacy_spec(spec, core.All, empty_keys())
  result
  |> should.equal(Ok(source_root.BandcampRoot(entry_point, core.All, timing_spec)))
}

pub fn soundcloud_maps_entry_point_and_depth_test() {
  let spec = source_specs.soundcloud()
  let source_specs.SourceSpec(_, _, entry_point, _, _) = spec
  let result = source_root.from_legacy_spec(spec, core.Depth1, empty_keys())
  result
  |> should.equal(Ok(source_root.SoundcloudRoot(entry_point, core.Depth1)))
}

pub fn spotify_maps_credentials_and_depth_test() {
  let spec = source_specs.spotify()
  let keys = fake_spotify_keys()
  let result = source_root.from_legacy_spec(spec, core.All, keys)
  let assert api_keys.ApiKeys(spotify: Some(creds), ..) = keys
  result
  |> should.equal(Ok(source_root.SpotifyRoot(creds, core.All)))
}

pub fn spotify_errors_without_credentials_test() {
  let spec = source_specs.spotify()
  source_root.from_legacy_spec(spec, core.All, empty_keys())
  |> should.equal(Error(api_keys.MissingApiKey("spotify")))
}

pub fn youtube_maps_playlist_url_and_api_key_test() {
  let spec = source_specs.youtube()
  let source_specs.SourceSpec(_, _, entry_point, _, _) = spec
  let result = source_root.from_legacy_spec(spec, core.All, fake_youtube_keys())
  result
  |> should.equal(Ok(source_root.YoutubeRoot(entry_point, "yt-key")))
}

pub fn youtube_errors_without_api_key_test() {
  let spec = source_specs.youtube()
  source_root.from_legacy_spec(spec, core.All, empty_keys())
  |> should.equal(Error(api_keys.MissingApiKey("youtube_data_api")))
}

pub fn tuna_maps_to_tuna_root_test() {
  let spec = source_specs.tuna()
  source_root.from_legacy_spec(spec, core.All, empty_keys())
  |> should.equal(Ok(source_root.TunaRoot))
}

fn full_keys() -> api_keys.ApiKeys {
  api_keys.ApiKeys(
    spotify: Some(api_keys.SpotifyCredentials(
      access_token: "tok",
      refresh_token: "ref",
      client_id: "cid",
      client_secret: "cs",
      redirect_uri: "https://localhost",
    )),
    google_cloud: Some("yt-key"),
  )
}

pub fn registry_has_all_source_keys_test() {
  let reg = source_root.registry(full_keys())
  let reg_keys =
    dict.keys(reg)
    |> set.from_list
  let expected =
    source_specs.all()
    |> list.map(fn(s) {
      let source_specs.SourceSpec(key, _, _, _, _) = s
      key
    })
    |> set.from_list
  reg_keys
  |> should.equal(expected)
}

pub fn registry_assert_spec_matches_legacy_bandcamp_test() {
  let reg = source_root.registry(full_keys())
  let assert Ok(#(_root, assert_spec)) = dict.get(reg, "bandcamp")
  let source_specs.SourceSpec(_, _, _, _, expected_spec) = source_specs.bandcamp()
  assert_spec
  |> should.equal(expected_spec)
}

pub fn triple_returns_ok_for_known_key_test() {
  source_root.triple("soundcloud", full_keys())
  |> should.be_ok
}

pub fn triple_returns_error_for_unknown_key_test() {
  source_root.triple("nonexistent", full_keys())
  |> should.be_error
}

// Phase 4: artifact path naming convention — derived solely from SourceRoot variant.
pub fn artifact_json_path_tuna_test() {
  source_root.artifact_json_path(source_root.TunaRoot)
  |> should.equal("output/tuna_full.json")
}

pub fn artifact_json_path_bandcamp_test() {
  let spec = source_specs.bandcamp()
  let assert Ok(root) = source_root.from_legacy_spec(spec, core.All, empty_keys())
  source_root.artifact_json_path(root)
  |> should.equal("output/bandcamp_full.json")
}

pub fn artifact_json_path_spotify_test() {
  let assert Ok(root) =
    source_root.from_legacy_spec(source_specs.spotify(), core.All, fake_spotify_keys())
  source_root.artifact_json_path(root)
  |> should.equal("output/spotify_full.json")
}
