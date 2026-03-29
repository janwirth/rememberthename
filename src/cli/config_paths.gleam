//// Resolve paths to project files (`.env`, Spotify session) when the process cwd
//// is not the rememberthename package root — e.g. `rememberthename_ui` started from its own directory.

import gleam/list
import simplifile

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
  let candidates = [
    "",
    "../rememberthename",
    "rememberthename",
    "../../rememberthename",
  ]
  case list.find(candidates, dir_has_spotify_config) {
    Ok(d) -> d
    Error(Nil) -> ""
  }
}
