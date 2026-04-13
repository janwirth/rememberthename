//// Incremental fetch anchor detection and handling.
////
//// Anchors identify a target item by ResourceId string; when found during pagination,
//// stop adding new pagination nodes to the queue at level 0 (but continue fetching
//// sub-items at level > 0).

import adapters/core
import gleam/int
import gleam/list
import gleam/option

/// Anchor search state threading through resolve/loop.
pub type AnchorMode {
  NoAnchor
  SearchForAnchor(target_id: String, found: Bool, page_number: Int)
}

/// Scan a batch of items for anchor match. Returns position if found.
pub fn check_items_for_anchor(
  items: List(core.UnifiedItem),
  target_id: String,
) -> option.Option(Int) {
  list.index_map(items, fn(item, idx) {
    case item.id == target_id {
      True -> option.Some(idx)
      False -> option.None
    }
  })
  |> list.find_map(fn(result) { result })
}

/// Update AnchorMode after checking items. Sets found=True if match detected.
pub fn update_anchor_mode(
  anchor_mode: AnchorMode,
  items: List(core.UnifiedItem),
) -> AnchorMode {
  case anchor_mode {
    NoAnchor -> NoAnchor
    SearchForAnchor(target_id, found, page_number) ->
      case found {
        True -> SearchForAnchor(target_id, True, page_number)
        False ->
          case check_items_for_anchor(items, target_id) {
            option.Some(_) -> SearchForAnchor(target_id, True, page_number)
            option.None -> SearchForAnchor(target_id, False, page_number + 1)
          }
      }
  }
}

/// Check if anchor was found (used to stop pagination at level 0).
pub fn is_anchor_reached(anchor_mode: AnchorMode) -> Bool {
  case anchor_mode {
    NoAnchor -> False
    SearchForAnchor(_, found, _) -> found
  }
}

/// Format final anchor_found result message.
pub fn format_message(anchor_mode: AnchorMode, resource_id: option.Option(String)) -> Result(String, String) {
  case resource_id {
    option.None -> Ok("No anchor specified")
    option.Some(rid) ->
      case anchor_mode {
        NoAnchor -> Ok("No anchor specified")
        SearchForAnchor(_, True, page) ->
          Ok("anchor " <> rid <> " found on page " <> int.to_string(page))
        SearchForAnchor(_, False, _) -> Error("Anchor not found")
      }
  }
}
