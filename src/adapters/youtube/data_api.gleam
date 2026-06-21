//// YouTube Data API v3 via `gleetube`: playlist items and `added_at` from `snippet.publishedAt`.

import adapters/core
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some, unwrap as option_unwrap}
import gleam/result
import gleam/string
import gleetube
import gleetube/client.{type Client}
import gleetube/model/common
import gleetube/error.{
  type GleeTubeError, ApiError, AuthError, DecodeError, HttpError,
  MissingParamsError,
}
import gleetube/model/playlist.{type Playlist}
import gleetube/model/playlist_item.{type PlaylistItem}
import gleetube/resource/playlist_items
import gleetube/resource/playlists

pub fn glee_tube_error_message(error: GleeTubeError) -> String {
  case error {
    ApiError(status, message, ..) ->
      "HTTP " <> int.to_string(status) <> ": " <> message
    HttpError(message) -> message
    AuthError(message) -> message
    DecodeError(message) -> message
    MissingParamsError(message) -> message
  }
}

/// Normalizes YouTube `publishedAt` into UTC ISO-8601 per SPEC_ADDED_AT_TIMESTAMP.
pub fn normalize_youtube_published_at(raw: String) -> Option(String) {
  let cleaned = string.trim(raw)
  case cleaned {
    "" -> None
    _ ->
      case string.ends_with(cleaned, "Z") {
        True -> Some(cleaned)
        False ->
          case is_date_only(cleaned) {
            True -> Some(cleaned <> "T00:00:00Z")
            False -> None
          }
      }
  }
}

pub fn fetch_playlist_unified(
  api_key: String,
  playlist_id: String,
) -> Result(#(List(core.UnifiedItem), String), GleeTubeError) {
  let client = gleetube.new(api_key)
  use items <- result.try(playlist_items.list_all(
    client,
    parts: [playlist_items.Snippet, playlist_items.ContentDetails],
    filter: playlist_items.ByPlaylistId(playlist_id),
    on_behalf_of_content_owner: None,
    video_id: None,
  ))
  use title <- result.try(fetch_playlist_title(client, playlist_id))
  let unified =
    list.filter_map(items, fn(row) { playlist_item_to_unified_item(row) })
  Ok(#(unified, title))
}

fn fetch_playlist_title(client: Client, playlist_id: String) -> Result(
  String,
  GleeTubeError,
) {
  use resp <- result.try(playlists.list(
    client,
    parts: [playlists.Snippet],
    filter: playlists.ById([playlist_id]),
    hl: None,
    max_results: Some(1),
    on_behalf_of_content_owner: None,
    on_behalf_of_content_owner_channel: None,
    page_token: None,
  ))
  case resp.items {
    [] -> Ok("YouTube Playlist")
    [playlist, ..] -> Ok(playlist_title_or_default(playlist))
  }
}

fn playlist_title_or_default(playlist: Playlist) -> String {
  case playlist.snippet {
    None -> "YouTube Playlist"
    Some(snippet) ->
      case snippet.title {
        None -> "YouTube Playlist"
        Some(title) ->
          case string.trim(title) {
            "" -> "YouTube Playlist"
            value -> value
          }
      }
  }
}

fn playlist_item_to_unified_item(
  item: PlaylistItem,
) -> Result(core.UnifiedItem, Nil) {
  let video_id = playlist_item_video_id(item)
  case video_id {
    None -> Error(Nil)
    Some(id) ->
      case string.trim(id) {
        "" -> Error(Nil)
        vid -> {
          let #(title, artist, published) = snippet_fields(item)
          let added_at = case published {
            None -> ""
            Some(raw) ->
              option_unwrap(normalize_youtube_published_at(raw), "")
          }
          let thumb = case item.snippet {
            None -> ""
            Some(sn) -> best_thumbnail_url(sn.thumbnails)
          }
          core.track_item_with_added_at(
            "youtube",
            vid,
            title,
            artist,
            "",
            thumb,
            added_at,
            [],
          )
        }
      }
  }
}

fn best_thumbnail_url(thumbs: Option(common.Thumbnails)) -> String {
  case thumbs {
    None -> ""
    Some(t) -> {
      let pick = fn(o: Option(common.Thumbnail)) -> String {
        case o {
          Some(img) -> string.trim(img.url)
          None -> ""
        }
      }
      first_non_empty_thumb([
        pick(t.maxres),
        pick(t.standard),
        pick(t.high),
        pick(t.medium),
        pick(t.default),
      ])
    }
  }
}

fn first_non_empty_thumb(candidates: List(String)) -> String {
  case candidates {
    [] -> ""
    [s, ..rest] ->
      case string.trim(s) {
        "" -> first_non_empty_thumb(rest)
        v -> v
      }
  }
}

fn playlist_item_video_id(item: PlaylistItem) -> Option(String) {
  case item.content_details {
    None -> snippet_resource_video_id(item)
    Some(cd) ->
      case cd.video_id {
        None -> snippet_resource_video_id(item)
        Some(id) ->
          case string.trim(id) {
            "" -> snippet_resource_video_id(item)
            trimmed -> Some(trimmed)
          }
      }
  }
}

fn snippet_resource_video_id(item: PlaylistItem) -> Option(String) {
  case item.snippet {
    None -> None
    Some(sn) ->
      case sn.resource_id {
        None -> None
        Some(rid) ->
          case rid.video_id {
            None -> None
            Some(id) ->
              case string.trim(id) {
                "" -> None
                trimmed -> Some(trimmed)
              }
          }
      }
  }
}

fn snippet_fields(item: PlaylistItem) -> #(String, String, Option(String)) {
  case item.snippet {
    None -> #("unknown", "unknown", None)
    Some(sn) -> {
      let title = case sn.title {
        None -> "unknown"
        Some(x) ->
          case string.trim(x) {
            "" -> "unknown"
            v -> v
          }
      }
      let artist =
        first_non_empty([
          sn.video_owner_channel_title,
          sn.channel_title,
        ])
      #(title, artist, sn.published_at)
    }
  }
}

fn first_non_empty(candidates: List(Option(String))) -> String {
  case candidates {
    [] -> "unknown"
    [candidate, ..rest] ->
      case candidate {
        None -> first_non_empty(rest)
        Some(value) ->
          case string.trim(value) {
            "" -> first_non_empty(rest)
            cleaned -> cleaned
          }
      }
  }
}

fn is_date_only(value: String) -> Bool {
  list.length(string.to_graphemes(value)) == 10
  && slice(value, 4, 1) == "-"
  && slice(value, 7, 1) == "-"
  && is_digits(slice(value, 0, 4))
  && is_digits(slice(value, 5, 2))
  && is_digits(slice(value, 8, 2))
}

fn is_digits(value: String) -> Bool {
  let chars = string.to_graphemes(value)
  chars != [] && list.all(chars, is_ascii_digit)
}

fn is_ascii_digit(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn slice(value: String, at_index: Int, length: Int) -> String {
  string.slice(value, at_index: at_index, length: length)
}
