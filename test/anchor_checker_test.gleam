import adapters/core
import gleam/option.{None, Some}
import gleam/time/timestamp
import gleeunit/should

fn test_item(id: String, title: String) -> core.UnifiedItem {
  core.UnifiedItem(
    id: id,
    title: title,
    artist: "Test Artist",
    service: "test",
    source_type: "track",
    source_id: id,
    external_source_url: None,
    cover_url: None,
    file_path: None,
    added_at: timestamp.unix_epoch,
    genres: [],
    duration_s: None,
    albumid_trackindex: None,
    date_added_is_hypothetical: False,
  )
}

pub fn format_message_no_anchor_requested_test() {
  let anchor_mode = core.NoAnchor
  let resource_id = None
  core.format_message(anchor_mode, resource_id)
  |> should.equal(Ok("No anchor specified"))
}

pub fn format_message_anchor_requested_not_found_test() {
  let anchor_mode = core.SearchForAnchor("track_123", False, 5)
  let resource_id = Some("track_123")
  core.format_message(anchor_mode, resource_id)
  |> should.equal(Error("Anchor not found"))
}

pub fn format_message_anchor_requested_and_found_test() {
  let anchor_mode = core.SearchForAnchor("track_123", True, 2)
  let resource_id = Some("track_123")
  core.format_message(anchor_mode, resource_id)
  |> should.equal(Ok("anchor track_123 found on page 2"))
}

pub fn format_message_anchor_found_on_first_page_test() {
  let anchor_mode = core.SearchForAnchor("item_999", True, 0)
  let resource_id = Some("item_999")
  core.format_message(anchor_mode, resource_id)
  |> should.equal(Ok("anchor item_999 found on page 0"))
}

pub fn check_items_for_anchor_found_test() {
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
    test_item("track_3", "Song 3"),
  ]
  core.check_items_for_anchor(items, "track_2")
  |> should.equal(Some(1))
}

pub fn check_items_for_anchor_not_found_test() {
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
  ]
  core.check_items_for_anchor(items, "track_999")
  |> should.equal(None)
}

pub fn update_anchor_mode_finds_anchor_test() {
  let anchor_mode = core.SearchForAnchor("track_2", False, 0)
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
  ]
  let updated = core.update_anchor_mode(anchor_mode, items)
  updated
  |> should.equal(core.SearchForAnchor("track_2", True, 0))
}

pub fn update_anchor_mode_increments_page_on_miss_test() {
  let anchor_mode = core.SearchForAnchor("track_999", False, 0)
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
  ]
  let updated = core.update_anchor_mode(anchor_mode, items)
  updated
  |> should.equal(core.SearchForAnchor("track_999", False, 1))
}

pub fn update_anchor_mode_keeps_found_flag_test() {
  let anchor_mode = core.SearchForAnchor("track_2", True, 1)
  let items = [test_item("track_5", "Song 5")]
  let updated = core.update_anchor_mode(anchor_mode, items)
  updated
  |> should.equal(core.SearchForAnchor("track_2", True, 1))
}
