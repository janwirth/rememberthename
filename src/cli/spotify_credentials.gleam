//// Application-layer Spotify session + .env loading (adapters must not read these files).

import adapters/api_keys
import dot_env as dot
import dot_env/env
import gleam/option.{Some}
import gleam/string
import simplifile

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

/// Merges disk-backed Spotify credentials into `keys`, preserving `google_cloud`.
pub fn with_spotify_from_disk(
  keys: api_keys.ApiKeys,
  session_file: String,
  env_file: String,
  redirect_uri: String,
) -> api_keys.ApiKeys {
  let api_keys.ApiKeys(_, google_cloud) = keys
  let spotify =
    Some(api_keys.SpotifyCredentials(
      access_token: read_access_token_file(session_file),
      refresh_token: read_refresh_token_file(session_file),
      client_id: read_env_value(env_file, "SPOTIFY_CLIENT_ID"),
      client_secret: read_env_value(env_file, "SPOTIFY_CLIENT_SECRET"),
      redirect_uri: redirect_uri,
    ))
  api_keys.ApiKeys(spotify: spotify, google_cloud: google_cloud)
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
