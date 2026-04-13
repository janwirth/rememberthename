import adapters/api_keys
import adapters/core
import cli/source_selector as source_pick
import gleam/list
import gleam/option
import gleam/set
import gleeunit/should
import source_root
import source_specs

pub fn ordered_triples_keys_match_all_rows_test() {
  let ordered = source_root.ordered_selector_triples(source_specs.all())
  let keys = list.map(ordered, fn(t) { t.0 }) |> set.from_list
  let expected =
    source_specs.all()
    |> list.map(fn(row) {
      let #(_, root, _) = row
      source_root.source_key(root)
    })
    |> set.from_list
  keys
  |> should.equal(expected)
}

pub fn ordered_triple_bandcamp_assert_spec_test() {
  let #(_, _, expected) = source_specs.bandcamp()
  let ordered = source_root.ordered_selector_triples(source_specs.all())
  let assert Ok(#(_, _, spec)) =
    list.find_map(ordered, fn(t) {
      case t.0 == "bandcamp" {
        True -> Ok(t)
        False -> Error(Nil)
      }
    })
  spec
  |> should.equal(expected)
}

pub fn bandcamp_row_is_bandcamp_root_test() {
  let #(_, root, _) = source_specs.bandcamp()
  let assert source_root.BandcampRoot(url, depth, _, _) = root
  depth
  |> should.equal(core.All)
  url
  |> should.not_equal("")
}

pub fn triple_by_selector_soundcloud_test() {
  let ordered = source_root.ordered_selector_triples(source_specs.all())
  source_pick.triple_by_selector(ordered, "soundcloud")
  |> should.be_ok
}

pub fn triple_by_selector_unknown_test() {
  let ordered = source_root.ordered_selector_triples(source_specs.all())
  source_pick.triple_by_selector(ordered, "nonexistent")
  |> should.be_error
}

pub fn artifact_json_path_tuna_test() {
  source_root.artifact_json_path(source_root.TunaRoot)
  |> should.equal("output/tuna_full.json")
}

pub fn artifact_json_path_bandcamp_test() {
  let #(_, root, _) = source_specs.bandcamp()
  source_root.artifact_json_path(root)
  |> should.equal("output/bandcamp_full.json")
}

pub fn artifact_json_path_spotify_test() {
  let root =
    source_root.SpotifyRoot(
      api_keys.SpotifyCredentials(
        access_token: "t",
        refresh_token: "r",
        client_id: "c",
        client_secret: "s",
        redirect_uri: "u",
      ),
      core.All,
      option.None,
    )
  source_root.artifact_json_path(root)
  |> should.equal("output/spotify_full.json")
}

pub fn with_newer_than_bandcamp_test() {
  let #(_, root, _) = source_specs.bandcamp()
  let root_with_anchor = source_root.with_newer_than(root, option.Some("rid:v1:platform:spotify:track:abc"))
  let assert source_root.BandcampRoot(_, _, _, fetch_newer_than) = root_with_anchor
  fetch_newer_than
  |> should.equal(option.Some("rid:v1:platform:spotify:track:abc"))
}

pub fn with_newer_than_youtube_test() {
  let #(_, root, _) = source_specs.youtube()
  let root_with_anchor = source_root.with_newer_than(root, option.Some("rid:v1:platform:youtube:track:xyz"))
  let assert source_root.YoutubeRoot(_, _, fetch_newer_than) = root_with_anchor
  fetch_newer_than
  |> should.equal(option.Some("rid:v1:platform:youtube:track:xyz"))
}

pub fn with_newer_than_clears_when_none_test() {
  let #(_, root, _) = source_specs.spotify()
  let root_with_anchor = source_root.with_newer_than(root, option.Some("rid:v1:platform:spotify:track:old"))
  let root_cleared = source_root.with_newer_than(root_with_anchor, option.None)
  let assert source_root.SpotifyRoot(_, _, fetch_newer_than) = root_cleared
  fetch_newer_than
  |> should.equal(option.None)
}
