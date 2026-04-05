// Phase 7: artifact validator tests — no network, fixture JSON only.
import cli/artifact_validator
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import source_specs

pub fn main() {
  gleeunit.main()
}

const fixture_path = "test/fixtures/bandcamp_full.json"

const minimal_json = "{\"tracks\":[{\"title\":\"Track A\",\"artist\":\"A\",\"service\":\"bandcamp\",\"source_id\":\"1\",\"external_source_url\":null,\"added_at\":null,\"order\":1,\"imported_date\":null,\"adapter_id\":\"bandcamp + x\",\"file\":null,\"cover\":null,\"tags\":[]}],\"collections\":[]}"

pub fn parse_artifact_from_fixture_test() {
  let assert Ok(summary) = artifact_validator.read_artifact(fixture_path)
  summary.track_count |> should.equal(5)
  summary.collection_count |> should.equal(1)
}

pub fn parse_artifact_extracts_titles_test() {
  let assert Ok(summary) = artifact_validator.parse_artifact(minimal_json)
  summary.track_titles |> should.equal(["Track A"])
}

pub fn parse_artifact_counts_tracks_and_collections_test() {
  let assert Ok(summary) = artifact_validator.parse_artifact(minimal_json)
  summary.track_count |> should.equal(1)
  summary.collection_count |> should.equal(0)
}

pub fn validate_artifact_passes_when_all_checks_ok_test() {
  let assert Ok(summary) = artifact_validator.read_artifact(fixture_path)
  // 5 tracks, 1 collection; fixture includes "Spore Spreader" anchor + required fragments.
  let spec =
    source_specs.SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 5,
      source_limit: 10,
      first_items_to_preserve: 0,
      anchor_fragments: ["Spore Spreader"],
      required_full_fragments: ["Badlands"],
    )
  let errors = artifact_validator.validate_artifact("bandcamp", summary, spec)
  errors |> should.equal([])
}

pub fn validate_artifact_fails_min_full_items_test() {
  let assert Ok(summary) = artifact_validator.parse_artifact(minimal_json)
  let spec =
    source_specs.SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 100,
      source_limit: 4000,
      first_items_to_preserve: 0,
      anchor_fragments: [],
      required_full_fragments: [],
    )
  let errors = artifact_validator.validate_artifact("test", summary, spec)
  errors |> list.length |> should.equal(1)
  list.any(errors, fn(e) { string.contains(e, "min full items failed") })
  |> should.equal(True)
}

pub fn validate_artifact_fails_source_limit_test() {
  let assert Ok(summary) = artifact_validator.parse_artifact(minimal_json)
  let spec =
    source_specs.SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 0,
      source_limit: 0,
      first_items_to_preserve: 0,
      anchor_fragments: [],
      required_full_fragments: [],
    )
  let errors = artifact_validator.validate_artifact("test", summary, spec)
  errors |> list.length |> should.equal(1)
  list.any(errors, fn(e) { string.contains(e, "source limit exceeded") })
  |> should.equal(True)
}

pub fn validate_artifact_fails_missing_anchor_test() {
  let assert Ok(summary) = artifact_validator.parse_artifact(minimal_json)
  let spec =
    source_specs.SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 0,
      source_limit: 4000,
      first_items_to_preserve: 0,
      anchor_fragments: ["Nonexistent Fragment XYZ"],
      required_full_fragments: [],
    )
  let errors = artifact_validator.validate_artifact("test", summary, spec)
  errors |> list.length |> should.equal(1)
  list.any(errors, fn(e) { string.contains(e, "anchor fragments missing") })
  |> should.equal(True)
}

pub fn validate_artifact_fails_missing_required_fragment_test() {
  let assert Ok(summary) = artifact_validator.parse_artifact(minimal_json)
  let spec =
    source_specs.SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 0,
      source_limit: 4000,
      first_items_to_preserve: 0,
      anchor_fragments: [],
      required_full_fragments: ["Required Fragment XYZ"],
    )
  let errors = artifact_validator.validate_artifact("test", summary, spec)
  errors |> list.length |> should.equal(1)
  list.any(errors, fn(e) { string.contains(e, "required full fragments missing") })
  |> should.equal(True)
}

pub fn validate_artifact_required_fragment_is_case_insensitive_test() {
  let assert Ok(summary) = artifact_validator.parse_artifact(minimal_json)
  let spec =
    source_specs.SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 0,
      source_limit: 4000,
      first_items_to_preserve: 0,
      anchor_fragments: [],
      required_full_fragments: ["TRACK A"],
    )
  let errors = artifact_validator.validate_artifact("test", summary, spec)
  errors |> should.equal([])
}
