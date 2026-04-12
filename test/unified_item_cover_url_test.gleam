import adapters/core
import gleam/string

pub fn spotify_track_item_uses_https_placeholder_cover_test() {
  let assert Ok(item) =
    core.track_item("spotify", "4iV5W9uYEdYUVa79Axb7Rh", "T", "A", "", "")
  let core.UnifiedItem(_, _, _, _, _, _, _, cover, _, _) = item
  string.starts_with(cover, "https://")
}
