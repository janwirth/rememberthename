//// Explicit credentials passed into adapters (no env reads here).

import gleam/option.{type Option, None, Some}
import gleam/string

pub type SpotifyCredentials {
  SpotifyCredentials(
    access_token: String,
    refresh_token: String,
    client_id: String,
    client_secret: String,
    redirect_uri: String,
  )
}

pub type ApiKeys {
  ApiKeys(spotify: Option(SpotifyCredentials), google_cloud: Option(String))
}

pub type ResolveAdapterError {
  MissingApiKey(service: String)
  YoutubeDataApi(message: String)
}

/// Spotify resolve/fetch: non-empty access token, or refresh_token + client_id + client_secret (all trimmed).
pub fn require_spotify_credentials(
  keys: ApiKeys,
) -> Result(SpotifyCredentials, ResolveAdapterError) {
  case keys.spotify {
    None -> Error(MissingApiKey("spotify"))
    Some(creds) -> {
      let SpotifyCredentials(at, rt, cid, cs, ru) = creds
      let at = string.trim(at)
      let rt = string.trim(rt)
      let cid = string.trim(cid)
      let cs = string.trim(cs)
      let ru = string.trim(ru)
      case at != "" {
        True ->
          Ok(SpotifyCredentials(at, rt, cid, cs, ru))
        False ->
          case rt != "" && cid != "" && cs != "" {
            True ->
              Ok(SpotifyCredentials(at, rt, cid, cs, ru))
            False -> Error(MissingApiKey("spotify"))
          }
      }
    }
  }
}

/// Call before any `gleetube` request for playlist / added-at data.
pub fn require_youtube_data_api_key(
  keys: ApiKeys,
) -> Result(String, ResolveAdapterError) {
  case keys.google_cloud {
    None -> Error(MissingApiKey("youtube_data_api"))
    Some(key) ->
      case string.trim(key) {
        "" -> Error(MissingApiKey("youtube_data_api"))
        trimmed -> Ok(trimmed)
      }
  }
}

pub fn format_resolve_adapter_error(error: ResolveAdapterError) -> String {
  case error {
    MissingApiKey("spotify") ->
      "Missing Spotify credentials. Set up .spotify_oauth_session.json and SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET in .env (see SPOTIFY_API_USE_LIB.md)."
    MissingApiKey("youtube_data_api") ->
      "Missing API key for youtube_data_api. Set GOOGLE_CLOUD_API_KEY in .env (see SPEC_GLEETUBE_YOUTUBE.md)."
    MissingApiKey(service) ->
      "Missing API key for " <> service <> "."
    YoutubeDataApi(message) -> "YouTube Data API error: " <> message
  }
}
