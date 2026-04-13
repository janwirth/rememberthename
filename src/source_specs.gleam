//// Canonical integration source rows: imports `source_root` types only, defines the ordered list.

import adapters/core
import cli/config_paths
import cli/spotify_credentials
import gleam/list
import gleam/option
import gleam/string
import simplifile
import source_root


pub fn all() -> List(#(String, source_root.SourceRoot, source_root.SourceAssertSpec)) {
  [bandcamp_purchases(), bandcamp_wishlist(), soundcloud(), spotify(), youtube(), tuna()]
}

pub fn bandcamp_purchases() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  #(
    "Bandcamp",
    source_root.BandcampRoot(
      "https://bandcamp.com/janwirth",
      core.All,
      source_root.SourceTimingSpec(max_concurrency: 5, requests_per_second: 5),
      option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 1,
      min_full_items: 700,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Stable fixture anchors from live Bandcamp profile traversal.
      anchor_fragments: ["Spore Spreader"],
      required_full_fragments: [
        "Badlands",
        "Dimebag",
        "Buttercup",
        "Ghost Radio",
        "Acid House",
      ],
    ),
  )
}

pub fn bandcamp_wishlist() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  #(
    "Bandcamp",
    source_root.BandcampRoot(
      "https://bandcamp.com/janwirth/wishlist",
      core.All,
      source_root.SourceTimingSpec(max_concurrency: 5, requests_per_second: 5),
      option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 1,
      min_full_items: 700,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Stable fixture anchors from live Bandcamp profile traversal.
      anchor_fragments: ["Spore Spreader"],
      required_full_fragments: [
        "Redshift 7",
        "World, Hold On",
      ],
    ),
  )
}

pub fn soundcloud() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  #(
    "Soundcloud",
    source_root.SoundcloudRoot(
      "https://soundcloud.com/tungstenselects",
      core.All,
      source_root.SourceTimingSpec(max_concurrency: 3, requests_per_second: 3),
      option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 10,
      min_full_items: 1000,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Stable fixture anchors from likes/reposts category traversal.
      anchor_fragments: [
        "A Horse with no Name (Edit)",
        "Nyxtape: Vol.12 - Harley D",
        "PREMIERE| Rebecca Delle Piane - Genomica [FIDESX4]",
        "Premiere: KAIPE - Batie",
      ],
      required_full_fragments: [],
    ),
  )
}

fn google_cloud_api_key_from_env() -> Result(String, Nil) {
  list.find_map(config_paths.env_search_roots(), fn(root) {
    let env_file = config_paths.join_under(root, ".env")
    case simplifile.is_file(env_file) {
      Ok(True) -> {
        let raw =
          spotify_credentials.read_env_value(env_file, "GOOGLE_CLOUD_API_KEY")
          |> string.trim
        case raw == "" {
          True -> Error(Nil)
          False -> Ok(raw)
        }
      }
      _ -> Error(Nil)
    }
  })
}

pub fn spotify() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  let assert Ok(credentials) = config_paths.get_spotify_credentials_from_env()
  #(
    "Spotify",
    source_root.SpotifyRoot(
      credentials: credentials,
      depth: core.All,
      fetch_newer_than: option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 50,
      min_full_items: 1000,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Liked tracks fixture anchors from Spotify authenticated traversal.
      anchor_fragments: ["Blask", "SOLD MY SOUL"],
      required_full_fragments: [],
    ),
  )
}

pub fn youtube() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  let assert Ok(api_key) = google_cloud_api_key_from_env()
  #(
    "Youtube",
    source_root.YoutubeRoot(
      "https://www.youtube.com/playlist?list=PLK7cxKkqBmwmpPoWznuEF-xEljswMRR3V",
      api_key,
      option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 5,
      min_full_items: 1000,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Ordered playlist prefix fragments from reference YouTube fixture.
      anchor_fragments: [
        "Angine de poitrine - Sahardnieh",
        "Nimo - BITTER",
        "Vengaboys - Up & Down",
        "Dendemann - Wo ich wech bin",
        "BHZ - SCHLIESSE DIE AUGEN",
      ],
      // Full traversal includes titles with case-varying "chanel" substring.
      required_full_fragments: ["chanel"],
    ),
  )
}

pub fn tuna() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  #(
    "Tuna",
    source_root.TunaRoot,
    source_root.SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 10,
      source_limit: 100000,
      first_items_to_preserve: 0,
      anchor_fragments: [],
      required_full_fragments: [],
    ),
  )
}
