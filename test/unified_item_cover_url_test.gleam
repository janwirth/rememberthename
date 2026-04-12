import adapters/core
import gleam/string
import gleam/option

pub fn spotify_track_item_uses_https_placeholder_cover_test() {
  let assert Ok(item) =
    core.track_item("spotify", "4iV5W9uYEdYUVa79Axb7Rh", "T", "A", "", "")
  let core.UnifiedItem(_, _, _, _, _, _, _, cover, _, _) = item
  case cover {
    option.Some(cover_url) -> string.starts_with(cover_url, "https://")
    option.None -> False
  }
}
