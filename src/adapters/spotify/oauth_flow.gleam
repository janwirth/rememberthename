//// Spotify OAuth authorize URL + authorization-code exchange (no local server).

import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/string
import gleam/uri

/// Default redirect; override with `SPOTIFY_REDIRECT_URI` in `.env` (must match Spotify app settings).
pub const default_redirect_uri: String =
  "https://127.0.0.1:8080/spotify-oauth-success"

const scope: String =
  "playlist-read-private playlist-read-collaborative user-library-read"

/// Spotify authorize URL for the manual (copy-`code`) flow.
pub fn authorize_url(client_id: String, redirect_uri: String) -> String {
  "https://accounts.spotify.com/authorize?client_id="
  <> client_id
  <> "&response_type=code&redirect_uri="
  <> uri.percent_encode(redirect_uri)
  <> "&scope="
  <> uri.percent_encode(scope)
  <> "&show_dialog=true"
}

/// POST authorization code to `/api/token`; returns response body (JSON or error payload).
pub fn exchange_authorization_code(
  client_id: String,
  client_secret: String,
  redirect_uri: String,
  code: String,
) -> String {
  let body =
    uri.query_to_string([
      #("grant_type", "authorization_code"),
      #("code", code),
      #("redirect_uri", redirect_uri),
      #("client_id", client_id),
      #("client_secret", client_secret),
    ])
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host("accounts.spotify.com")
    |> request.set_method(http.Post)
    |> request.set_path("/api/token")
    |> request.set_header("content-type", "application/x-www-form-urlencoded")
    |> request.set_body(body)
  case hackney.send(req) {
    Ok(res) -> res.body
    Error(_) -> ""
  }
}

/// If the user pasted a full redirect URL, take the `code` query value; otherwise trim as-is.
pub fn normalize_pasted_code(input: String) -> String {
  let s = string.trim(input)
  case string.split(s, "code=") {
    [_, after_code, ..] ->
      case string.split(after_code, "&") {
        [first, ..] -> string.trim(first)
        _ -> string.trim(after_code)
      }
    _ -> s
  }
}
