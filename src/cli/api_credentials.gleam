//// Application-layer credential loading for `ApiKeys` (reads `.env` only here).

import adapters/api_keys
import cli/config_paths
import cli/spotify_credentials
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import simplifile

fn google_cloud_key_from_env_candidates() -> option.Option(String) {
  case
    list.find_map(config_paths.env_search_roots(), fn(root) {
      let env_file = config_paths.join_under(root, ".env")
      case simplifile.is_file(env_file) {
        Ok(True) -> {
          let raw =
            spotify_credentials.read_env_value(env_file, "GOOGLE_CLOUD_API_KEY")
            |> string.trim
          case raw {
            "" -> Error(Nil)
            value -> Ok(value)
          }
        }
        _ -> Error(Nil)
      }
    })
  {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}

/// Reads `GOOGLE_CLOUD_API_KEY` from the first matching `.env` on `config_paths.env_search_roots`.
/// Unlike `spotify_config_root` alone, this does not require `.spotify_oauth_session.json` beside
/// that file, so a key in `rememberthename/.env` is found when Spotify lives in a parent `.env`.
pub fn load_api_keys() -> api_keys.ApiKeys {
  let google_cloud = google_cloud_key_from_env_candidates()
  api_keys.ApiKeys(spotify: None, google_cloud: google_cloud)
}

/// Loads all credentials: Google Cloud key + Spotify OAuth session from disk.
pub fn load_full_api_keys() -> api_keys.ApiKeys {
  let root = config_paths.spotify_config_root()
  let env_file = config_paths.join_under(root, ".env")
  let session_file =
    config_paths.join_under(root, ".spotify_oauth_session.json")
  let redirect = "https://127.0.0.1:8080/spotify-oauth-success"
  let base = load_api_keys()
  spotify_credentials.with_spotify_from_disk(
    base,
    session_file,
    env_file,
    redirect,
  )
}
