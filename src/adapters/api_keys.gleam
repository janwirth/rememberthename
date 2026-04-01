//// Explicit credentials passed into adapters (no env reads here).

import gleam/option.{type Option, None, Some}
import gleam/string

pub type ApiKeys {
  ApiKeys(spotify: Option(String), google_cloud: Option(String))
}

pub type ResolveAdapterError {
  MissingApiKey(service: String)
  YoutubeDataApi(message: String)
}

/// Call before any `gleetube` request for playlist / added-at data.
pub fn require_youtube_data_api_key(keys: ApiKeys) -> Result(String, ResolveAdapterError) {
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
    MissingApiKey(service) ->
      "Missing API key for "
      <> service
      <> ". Set GOOGLE_CLOUD_API_KEY in .env (see SPEC_GLEETUBE_YOUTUBE.md)."
    YoutubeDataApi(message) -> "YouTube Data API error: " <> message
  }
}
