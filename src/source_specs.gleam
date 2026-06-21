//// Canonical integration source rows: imports `source_root` types only, defines the ordered list.

import adapters/core
import cli/config_paths
import cli/spotify_credentials
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import simplifile
import source_root


pub fn all() -> List(#(String, source_root.SourceRoot, source_root.SourceAssertSpec)) {
  [bandcamp_purchases(), bandcamp_wishlist(), soundcloud(), spotify(), youtube(), tuna()]
}

fn spotify_if_configured() -> Result(
  #(String, source_root.SourceRoot, source_root.SourceAssertSpec),
  Nil,
) {
  let has_bundle =
    list.any(config_paths.env_search_roots(), fn(root) {
      let env = config_paths.join_under(root, ".env")
      let session = config_paths.join_under(root, ".spotify_oauth_session.json")
      case simplifile.is_file(env), simplifile.is_file(session) {
        Ok(True), Ok(True) -> True
        _, _ -> False
      }
    })
  case has_bundle {
    True -> Ok(spotify())
    False -> Error(Nil)
  }
}

fn youtube_if_configured() -> Result(
  #(String, source_root.SourceRoot, source_root.SourceAssertSpec),
  Nil,
) {
  use api_key <- result.try(google_cloud_api_key_from_env())
  Ok(youtube_with_key(api_key))
}

/// Like [`all_configured`] but reads credentials from an explicit profile directory
/// (e.g. `~/tuna/default`) instead of cwd-relative search roots.
/// Accepts an optional YouTube playlist URL; falls back to YOUTUBE_PLAYLIST_URL in
/// the profile .env when None; skips YouTube entirely if no URL and no key found.
pub fn all_configured_for_profile(
  profile_dir: String,
  youtube_playlist_url: option.Option(String),
) -> List(#(String, source_root.SourceRoot, source_root.SourceAssertSpec)) {
  let env_file = profile_dir <> "/.env"
  let session_file = profile_dir <> "/.spotify_oauth_session.json"

  let rows = case bandcamp_profile_url_from_env_file(env_file) {
    Ok(url) -> [make_bandcamp_purchases(url), make_bandcamp_wishlist(url)]
    Error(_) -> []
  }
  let rows = case soundcloud_profile_url_from_env_file(env_file) {
    Ok(url) -> list.append(rows, [make_soundcloud(url)])
    Error(_) -> rows
  }
  let rows = case simplifile.is_file(env_file), simplifile.is_file(session_file) {
    Ok(True), Ok(True) -> {
      let redirect = spotify_credentials.spotify_redirect_uri(env_file)
      let creds = spotify_credentials.with_spotify_from_disk(session_file, env_file, redirect)
      let row = #(
        "Spotify",
        source_root.SpotifyRoot(credentials: creds, depth: core.All, fetch_newer_than: option.None),
        source_root.SourceAssertSpec(
          min_depth_1_items: 50, min_full_items: 1000, source_limit: 4000,
          first_items_to_preserve: 3, anchor_fragments: [], required_full_fragments: [],
        ),
      )
      list.append(rows, [row])
    }
    _, _ -> rows
  }
  let rows = case simplifile.is_file(env_file) {
    Ok(True) -> {
      let raw = spotify_credentials.read_env_value(env_file, "GOOGLE_CLOUD_API_KEY") |> string.trim
      case raw {
        "" -> rows
        api_key -> {
          let playlist_url = case youtube_playlist_url {
            option.Some(u) -> u
            option.None ->
              spotify_credentials.read_env_value(env_file, "YOUTUBE_PLAYLIST_URL") |> string.trim
          }
          case playlist_url {
            "" -> rows
            url -> {
              let row = #(
                "Youtube",
                source_root.YoutubeRoot(url, api_key, option.None),
                source_root.SourceAssertSpec(
                  min_depth_1_items: 5, min_full_items: 1000, source_limit: 4000,
                  first_items_to_preserve: 3, anchor_fragments: [], required_full_fragments: [],
                ),
              )
              list.append(rows, [row])
            }
          }
        }
      }
    }
    _ -> rows
  }
  list.append(rows, [tuna()])
}

/// Same order intent as [`all`], but omits sources whose credentials/URLs are missing.
pub fn all_configured() -> List(#(String, source_root.SourceRoot, source_root.SourceAssertSpec)) {
  let rows = case bandcamp_profile_url_from_env() {
    Ok(url) -> [make_bandcamp_purchases(url), make_bandcamp_wishlist(url)]
    Error(_) -> []
  }
  let rows = case soundcloud_profile_url_from_env() {
    Ok(url) -> list.append(rows, [make_soundcloud(url)])
    Error(_) -> rows
  }
  let rows = case spotify_if_configured() {
    Ok(row) -> list.append(rows, [row])
    Error(_) -> rows
  }
  let rows = case youtube_if_configured() {
    Ok(row) -> list.append(rows, [row])
    Error(_) -> rows
  }
  list.append(rows, [tuna()])
}

pub fn bandcamp() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  bandcamp_purchases()
}

pub fn bandcamp_purchases() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  let assert Ok(url) = bandcamp_profile_url_from_env()
  make_bandcamp_purchases(url)
}

pub fn bandcamp_wishlist() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  let assert Ok(url) = bandcamp_profile_url_from_env()
  make_bandcamp_wishlist(url)
}

pub fn soundcloud() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  let assert Ok(url) = soundcloud_profile_url_from_env()
  make_soundcloud(url)
}

fn bandcamp_profile_url_from_env() -> Result(String, Nil) {
  list.find_map(config_paths.env_search_roots(), fn(root) {
    bandcamp_profile_url_from_env_file(config_paths.join_under(root, ".env"))
  })
}

fn bandcamp_profile_url_from_env_file(env_file: String) -> Result(String, Nil) {
  case simplifile.is_file(env_file) {
    Ok(True) -> {
      let raw = spotify_credentials.read_env_value(env_file, "BANDCAMP_PROFILE_URL") |> string.trim
      case raw {
        "" -> Error(Nil)
        url -> Ok(url)
      }
    }
    _ -> Error(Nil)
  }
}

fn soundcloud_profile_url_from_env() -> Result(String, Nil) {
  list.find_map(config_paths.env_search_roots(), fn(root) {
    soundcloud_profile_url_from_env_file(config_paths.join_under(root, ".env"))
  })
}

fn soundcloud_profile_url_from_env_file(env_file: String) -> Result(String, Nil) {
  case simplifile.is_file(env_file) {
    Ok(True) -> {
      let raw = spotify_credentials.read_env_value(env_file, "SOUNDCLOUD_PROFILE_URL") |> string.trim
      case raw {
        "" -> Error(Nil)
        url -> Ok(url)
      }
    }
    _ -> Error(Nil)
  }
}

fn make_bandcamp_purchases(url: String) -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  #(
    "Bandcamp Purchases",
    source_root.BandcampRoot(
      url,
      core.All,
      source_root.SourceTimingSpec(max_concurrency: 5, requests_per_second: 5),
      option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 1,
      min_full_items: 700,
      source_limit: 4000,
      first_items_to_preserve: 3,
      anchor_fragments: ["Spore Spreader"],
      required_full_fragments: [
        "Badlands",
        "Dimebag",
        "Buttercup",
        "Acid House",
      ],
    ),
  )
}

fn make_bandcamp_wishlist(url: String) -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  #(
    "Bandcamp Wishlist",
    source_root.BandcampRoot(
      url <> "/wishlist",
      core.All,
      source_root.SourceTimingSpec(max_concurrency: 5, requests_per_second: 5),
      option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 1,
      min_full_items: 700,
      source_limit: 4000,
      first_items_to_preserve: 3,
      anchor_fragments: ["Mini Metro"],
      required_full_fragments: [
        "Redshift 7",
        "World, Hold On",
      ],
    ),
  )
}

fn make_soundcloud(url: String) -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  #(
    "Soundcloud",
    source_root.SoundcloudRoot(
      url,
      core.All,
      source_root.SourceTimingSpec(max_concurrency: 1, requests_per_second: 1),
      option.None,
    ),
    source_root.SourceAssertSpec(
      min_depth_1_items: 10,
      min_full_items: 1000,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Tracks at indices ~30 (likes p1) and ~65 (reposts p1) — both within depth_2 range.
      anchor_fragments: [
        "BAUGRUPPE90 - Quartz",
        "Doechii - Nissan Altima",
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

fn youtube_with_key(api_key: String) -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
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
      anchor_fragments: [
        "Angine de poitrine - Sahardnieh",
        "Nimo - BITTER",
        "Vengaboys - Up & Down",
        "Dendemann - Wo ich wech bin",
        "BHZ - SCHLIESSE DIE AUGEN",
      ],
      required_full_fragments: ["chanel"],
    ),
  )
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
      // Tracks at indices ~20 (depth_1) and ~75 (depth_2) — both within depth_2 range.
      anchor_fragments: ["Groove Constructor", "Eisbaer"],
      required_full_fragments: [],
    ),
  )
}

pub fn youtube() -> #(String, source_root.SourceRoot, source_root.SourceAssertSpec) {
  let assert Ok(api_key) = google_cloud_api_key_from_env()
  youtube_with_key(api_key)
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
