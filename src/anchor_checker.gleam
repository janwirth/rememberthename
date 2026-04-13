//// Incremental fetch anchor detection and handling.

import adapters/core
import gleam/int
import gleam/list
import gleam/option

/// Scan a batch of items for anchor match. Returns position if found.
pub fn check_items_for_anchor(
  items: List(core.UnifiedItem),
  target_id: String,
) -> option.Option(Int) {
  list.index_fold(items, option.None, fn(result, item, idx) {
    case result {
      option.Some(_) -> result
      option.None ->
        case item.id == target_id {
          True -> option.Some(idx)
          False -> option.None
        }
    }
  })
}

/// Update AnchorMode after checking items. Sets found=True if match detected.
pub fn update_anchor_mode(
  anchor_mode: core.AnchorMode,
  items: List(core.UnifiedItem),
) -> core.AnchorMode {
  case anchor_mode {
    core.NoAnchor -> core.NoAnchor
    core.SearchForAnchor(target_id, found, page_number) ->
      case found {
        True -> core.SearchForAnchor(target_id, True, page_number)
        False ->
          case check_items_for_anchor(items, target_id) {
            option.Some(_) -> core.SearchForAnchor(target_id, True, page_number)
            option.None -> core.SearchForAnchor(target_id, False, page_number + 1)
          }
      }
  }
}

/// Check if anchor was found (used to stop pagination at level 0).
pub fn is_anchor_reached(anchor_mode: core.AnchorMode) -> Bool {
  case anchor_mode {
    core.NoAnchor -> False
    core.SearchForAnchor(_, found, _) -> found
  }
}

/// Format final anchor_found result message.
pub fn format_message(anchor_mode: core.AnchorMode, resource_id: option.Option(String)) -> Result(String, String) {
  case resource_id {
    option.None -> Ok("No anchor specified")
    option.Some(rid) ->
      case anchor_mode {
        core.NoAnchor -> Ok("No anchor specified")
        core.SearchForAnchor(_, True, page) ->
          Ok("anchor " <> rid <> " found on page " <> int.to_string(page))
        core.SearchForAnchor(_, False, _) -> Error("Anchor not found")
      }
  }
}
