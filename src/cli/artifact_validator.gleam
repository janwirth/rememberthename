//// Validates `fetch_and_save_json` artifacts (`output/<key>_full.json`) offline.
////
//// Reads the `{"tracks": [...], "collections": [...]}` format produced by
//// `export_json.fetch_result_json` and runs the full-depth subset of
//// `SourceAssertSpec` checks — no network access required.
////
//// Cross-depth checks (monotonicity, shallow anchors) stay in
//// `fetch_validation` which runs post-fetch with in-memory results.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import source_specs

/// Summary of a parsed artifact file — only what validators need.
pub type ArtifactSummary {
  ArtifactSummary(
    track_count: Int,
    collection_count: Int,
    track_titles: List(String),
  )
}

fn track_title_decoder() -> decode.Decoder(String) {
  use title <- decode.field("title", decode.string)
  decode.success(title)
}

fn artifact_decoder() -> decode.Decoder(ArtifactSummary) {
  use titles <- decode.field("tracks", decode.list(of: track_title_decoder()))
  use cols <- decode.field(
    "collections",
    decode.list(of: decode.map(decode.dynamic, fn(_: dynamic.Dynamic) { Nil })),
  )
  decode.success(ArtifactSummary(
    track_count: list.length(titles),
    collection_count: list.length(cols),
    track_titles: titles,
  ))
}

/// Parse a `fetch_result_json` string into an `ArtifactSummary`.
pub fn parse_artifact(json_str: String) -> Result(ArtifactSummary, String) {
  case json.parse(json_str, artifact_decoder()) {
    Ok(summary) -> Ok(summary)
    Error(e) -> Error("JSON parse error: " <> string.inspect(e))
  }
}

/// Read and parse an artifact file from disk.
pub fn read_artifact(path: String) -> Result(ArtifactSummary, String) {
  case simplifile.read(path) {
    Ok(content) -> parse_artifact(content)
    Error(e) -> Error("Read failed: " <> simplifile.describe_error(e))
  }
}

/// Run full-depth checks from `SourceAssertSpec` against a parsed artifact.
///
/// Returns a list of human-readable error strings (empty = PASS).
/// Cross-depth checks (monotonicity, depth-1 anchors) are skipped — those
/// require `fetch_validation.validate_source_run` with live results.
pub fn validate_artifact(
  key: String,
  summary: ArtifactSummary,
  assert_spec: source_specs.SourceAssertSpec,
) -> List(String) {
  let source_specs.SourceAssertSpec(
    _min_depth_1_items,
    min_full_items,
    source_limit,
    _first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = assert_spec
  let ArtifactSummary(track_count, _collection_count, track_titles) = summary

  let min_full_ok = track_count >= min_full_items
  let source_limit_ok = track_count <= source_limit
  let anchors_full_ok =
    list.all(anchor_fragments, fn(fragment) {
      list.any(track_titles, fn(title) { string.contains(title, fragment) })
    })
  let required_full_ok =
    list.all(required_full_fragments, fn(fragment) {
      let fragment_lc = string.lowercase(fragment)
      list.any(track_titles, fn(title) {
        string.contains(string.lowercase(title), fragment_lc)
      })
    })

  []
  |> add_error(
    !min_full_ok,
    key
      <> ": min full items failed (got "
      <> int.to_string(track_count)
      <> ", need "
      <> int.to_string(min_full_items)
      <> ")",
  )
  |> add_error(
    !source_limit_ok,
    key
      <> ": source limit exceeded ("
      <> int.to_string(track_count)
      <> " > "
      <> int.to_string(source_limit)
      <> ")",
  )
  |> add_error(!anchors_full_ok, key <> ": anchor fragments missing from full result")
  |> add_error(!required_full_ok, key <> ": required full fragments missing")
}

fn add_error(errors: List(String), condition: Bool, msg: String) -> List(String) {
  case condition {
    True -> list.append(errors, [msg])
    False -> errors
  }
}

/// Convenience: validate an artifact at `path` against an assert spec.
pub fn validate_artifact_file(
  key: String,
  path: String,
  assert_spec: source_specs.SourceAssertSpec,
) -> Result(List(String), String) {
  use summary <- result.map(read_artifact(path))
  validate_artifact(key, summary, assert_spec)
}
