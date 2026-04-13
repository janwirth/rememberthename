//// Tests for anchor detection in fetch_ops.
////
//// CURRENT BEHAVIOR (RED): default_anchor_result always returns static message.
//// It doesn't use the actual anchor detection from anchor_checker.
//// This test will fail until we wire up real anchor detection.

import anchor_checker
import gleam/option.{None, Some}
import gleeunit/should

pub fn anchor_result_no_anchor_requested_test() {
  //// When no anchor is requested, format_message returns "No anchor specified"
  let result = anchor_checker.format_message(anchor_checker.NoAnchor, None)
  result
  |> should.equal(Ok("No anchor specified"))
}

pub fn anchor_result_anchor_requested_not_found_test() {
  //// When anchor requested but not found, should return Error with explanation
  let anchor_mode = anchor_checker.SearchForAnchor("missing_track", False, 5)
  let result = anchor_checker.format_message(anchor_mode, Some("missing_track"))
  result
  |> should.equal(Error("Anchor not found"))
}

pub fn anchor_result_anchor_found_test() {
  //// When anchor found, should return Ok with page number where it was found
  let anchor_mode = anchor_checker.SearchForAnchor("found_track", True, 3)
  let result = anchor_checker.format_message(anchor_mode, Some("found_track"))
  result
  |> should.equal(Ok("anchor found_track found on page 3"))
}
