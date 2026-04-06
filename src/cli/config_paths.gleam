//// Resolve paths to project files (`.env`, Spotify session) when the process cwd
//// is not the rememberthename package root — e.g. `rememberthename_ui` started from its own directory.

import adapters/api_keys
import cli/spotify_credentials
import gleam/list
import simplifile

/// Ordered roots to try for `.env` when cwd may be the package, a parent monorepo, or a sibling app.
pub fn env_search_roots() -> List(String) {
  ["", "../rememberthename", "rememberthename", "../../rememberthename"]
}

pub fn join_under(root: String, file: String) -> String {
  case root {
    "" -> file
    _ -> root <> "/" <> file
  }
}

fn dir_has_spotify_config(root: String) -> Bool {
  let env = join_under(root, ".env")
  let session = join_under(root, ".spotify_oauth_session.json")
  let has_env = case simplifile.is_file(env) {
    Ok(True) -> True
    _ -> False
  }
  let has_session = case simplifile.is_file(session) {
    Ok(True) -> True
    _ -> False
  }
  has_env && has_session
}

/// First directory (possibly `""` for cwd) that contains both `.env` and
/// `.spotify_oauth_session.json`. Falls back to `""` if none match (legacy cwd-only behaviour).
pub fn spotify_config_root() -> String {
  case list.find(env_search_roots(), dir_has_spotify_config) {
    Ok(d) -> d
    Error(Nil) -> ""
  }
}

/// Loads Spotify credentials from the resolved `.env` + session beside `spotify_config_root`.
pub fn get_spotify_credentials_from_env() -> Result(
  api_keys.SpotifyCredentials,
  api_keys.ResolveAdapterError,
) {
  let root = spotify_config_root()
  let session_file = join_under(root, ".spotify_oauth_session.json")
  let env_file = join_under(root, ".env")
  let redirect = spotify_credentials.spotify_redirect_uri(env_file)
  let keys_with_spotify =
    spotify_credentials.with_spotify_from_disk(
      session_file,
      env_file,
      redirect,
    )
  Ok(keys_with_spotify)
}