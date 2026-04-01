//// Application-layer credential loading for `ApiKeys` (reads `.env` only here).

import adapters/api_keys
import cli/config_paths
import cli/spotify_credentials
import gleam/option.{None, Some}
import gleam/string

/// Reads `GOOGLE_CLOUD_API_KEY` from the same `.env` as Spotify (see `config_paths.spotify_config_root`).
pub fn load_api_keys() -> api_keys.ApiKeys {
  let root = config_paths.spotify_config_root()
  let env_file = config_paths.join_under(root, ".env")
  let raw =
    spotify_credentials.read_env_value(env_file, "GOOGLE_CLOUD_API_KEY")
    |> string.trim
  let google_cloud = case raw {
    "" -> None
    value -> Some(value)
  }
  api_keys.ApiKeys(spotify: None, google_cloud: google_cloud)
}
