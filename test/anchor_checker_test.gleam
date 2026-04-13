import adapters/core
import anchor_checker
import gleam/option.{None, Some}
import gleeunit/should
import timestamp

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
  )
}

pub fn format_message_no_anchor_requested_test() {
  let anchor_mode = anchor_checker.NoAnchor
  let resource_id = None
  anchor_checker.format_message(anchor_mode, resource_id)
  |> should.equal(Ok("No anchor specified"))
}

pub fn format_message_anchor_requested_not_found_test() {
  let anchor_mode = anchor_checker.SearchForAnchor("track_123", False, 5)
  let resource_id = Some("track_123")
  anchor_checker.format_message(anchor_mode, resource_id)
  |> should.equal(Error("Anchor not found"))
}

pub fn format_message_anchor_requested_and_found_test() {
  let anchor_mode = anchor_checker.SearchForAnchor("track_123", True, 2)
  let resource_id = Some("track_123")
  anchor_checker.format_message(anchor_mode, resource_id)
  |> should.equal(Ok("anchor track_123 found on page 2"))
}

pub fn format_message_anchor_found_on_first_page_test() {
  let anchor_mode = anchor_checker.SearchForAnchor("item_999", True, 0)
  let resource_id = Some("item_999")
  anchor_checker.format_message(anchor_mode, resource_id)
  |> should.equal(Ok("anchor item_999 found on page 0"))
}

pub fn check_items_for_anchor_found_test() {
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
    test_item("track_3", "Song 3"),
  ]
  anchor_checker.check_items_for_anchor(items, "track_2")
  |> should.equal(Some(1))
}

pub fn check_items_for_anchor_not_found_test() {
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
  ]
  anchor_checker.check_items_for_anchor(items, "track_999")
  |> should.equal(None)
}

pub fn update_anchor_mode_finds_anchor_test() {
  let anchor_mode = anchor_checker.SearchForAnchor("track_2", False, 0)
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
  ]
  let updated = anchor_checker.update_anchor_mode(anchor_mode, items)
  updated
  |> should.equal(anchor_checker.SearchForAnchor("track_2", True, 0))
}

pub fn update_anchor_mode_increments_page_on_miss_test() {
  let anchor_mode = anchor_checker.SearchForAnchor("track_999", False, 0)
  let items = [
    test_item("track_1", "Song 1"),
    test_item("track_2", "Song 2"),
  ]
  let updated = anchor_checker.update_anchor_mode(anchor_mode, items)
  updated
  |> should.equal(anchor_checker.SearchForAnchor("track_999", False, 1))
}

pub fn update_anchor_mode_keeps_found_flag_test() {
  let anchor_mode = anchor_checker.SearchForAnchor("track_2", True, 1)
  let items = [
    core.UnifiedItem(id: "track_5", title: "Song 5", ..core.default_unified_item()),
  ]
  let updated = anchor_checker.update_anchor_mode(anchor_mode, items)
  updated
  |> should.equal(anchor_checker.SearchForAnchor("track_2", True, 1))
}
