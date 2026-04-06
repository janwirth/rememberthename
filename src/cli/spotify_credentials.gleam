//// Application-layer Spotify session + .env loading (adapters must not read these files).

import adapters/api_keys
import adapters/spotify/oauth_flow
import dot_env as dot
import dot_env/env
import gleam/list
import gleam/string
import simplifile

// Same values as `config_paths`; local to avoid an import cycle with that module.
fn env_search_roots() -> List(String) {
  ["", "../rememberthename", "rememberthename", "../../rememberthename"]
}

fn join_under(root: String, file: String) -> String {
  case root {
    "" -> file
    _ -> root <> "/" <> file
  }
}

pub fn read_env_value(file_path: String, key: String) -> String {
  let _ =
    dot.new() |> dot.set_path(file_path) |> dot.set_debug(False) |> dot.load
  env.get_string_or(key, "")
}

pub fn read_access_token_file(session_file: String) -> String {
  case simplifile.read(from: session_file) {
    Ok(body) ->
      case string.trim(extract_access_token(body)) {
        "" -> string.trim(body)
        token -> token
      }
    Error(_) -> ""
  }
}

pub fn read_refresh_token_file(session_file: String) -> String {
  case simplifile.read(from: session_file) {
    Ok(body) -> string.trim(extract_refresh_token(body))
    Error(_) -> ""
  }
}

/// `SPOTIFY_REDIRECT_URI` from `env_file`, or `oauth_flow.default_redirect_uri` if unset.
pub fn spotify_redirect_uri(env_file: String) -> String {
  case read_env_value(env_file, "SPOTIFY_REDIRECT_URI") |> string.trim {
    "" -> oauth_flow.default_redirect_uri
    uri -> uri
  }
}

/// First `env_search_roots` entry whose `.env` exists and sets non-empty `SPOTIFY_CLIENT_ID`.
pub fn first_spotify_oauth_env_bundle() -> Result(#(String, String), Nil) {
  list.find_map(env_search_roots(), fn(root) {
    let env_file = join_under(root, ".env")
    case simplifile.is_file(env_file) {
      Ok(True) -> {
        let id = read_env_value(env_file, "SPOTIFY_CLIENT_ID") |> string.trim
        case id == "" {
          True -> Error(Nil)
          False -> Ok(#(root, env_file))
        }
      }
      _ -> Error(Nil)
    }
  })
}

/// Merges disk-backed Spotify credentials into `keys`, preserving `google_cloud`.
pub fn with_spotify_from_disk(
  session_file: String,
  env_file: String,
  redirect_uri: String,
) -> api_keys.SpotifyCredentials {
  api_keys.SpotifyCredentials(
    access_token: read_access_token_file(session_file),
    refresh_token: read_refresh_token_file(session_file),
    client_id: read_env_value(env_file, "SPOTIFY_CLIENT_ID"),
    client_secret: read_env_value(env_file, "SPOTIFY_CLIENT_SECRET"),
    redirect_uri: redirect_uri,
  )
}

fn extract_access_token(body: String) -> String {
  let compact = string.replace(body, " ", "")
  let exact = extract_between(compact, "\"access_token\":\"", "\"")
  case exact {
    "" -> extract_between(body, "\"access_token\":\"", "\"")
    token -> token
  }
}

fn extract_refresh_token(body: String) -> String {
  let compact = string.replace(body, " ", "")
  let exact = extract_between(compact, "\"refresh_token\":\"", "\"")
  case exact {
    "" -> extract_between(body, "\"refresh_token\":\"", "\"")
    token -> token
  }
}

fn extract_between(body: String, start: String, ending: String) -> String {
  case string.split(body, start) {
    [_, tail, ..] ->
      case string.split(tail, ending) {
        [value, ..] -> value
        _ -> ""
      }
    _ -> ""
  }
}
