//// YouTube Data API v3 via `gleetube`: playlist items and `added_at` from `snippet.publishedAt`.
////
//// Duration fetch uses pingpong paging: each PlaylistItems page (≤50 items) is immediately
//// paired with one Videos.list call for those exact video IDs, so duration data arrives
//// alongside items rather than in a separate second pass.

import adapters/core
import gleam/dict.{type Dict}
import gleam/float
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
import gleetube/resource/videos

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

/// Pingpong fetch: each page of playlist items (≤50) is immediately paired with one
/// Videos.list call for those video IDs, interleaving the two API endpoints.
pub fn fetch_playlist_unified(
  api_key: String,
  playlist_id: String,
  on_log: fn(String) -> Nil,
) -> Result(#(List(core.UnifiedItem), String), GleeTubeError) {
  let client = gleetube.new(api_key)
  use all_items <- result.try(fetch_all_pages_pingpong(
    client,
    playlist_id,
    None,
    [],
    on_log,
  ))
  use title <- result.try(fetch_playlist_title(client, playlist_id))
  Ok(#(all_items, title))
}

fn fetch_all_pages_pingpong(
  client: Client,
  playlist_id: String,
  page_token: Option(String),
  acc: List(core.UnifiedItem),
  on_log: fn(String) -> Nil,
) -> Result(List(core.UnifiedItem), GleeTubeError) {
  on_log(
    "youtube: fetching playlist items page"
    <> case page_token {
      None -> ""
      Some(_) -> " (next page)"
    },
  )
  use resp <- result.try(playlist_items.list(
    client,
    parts: [playlist_items.Snippet, playlist_items.ContentDetails],
    filter: playlist_items.ByPlaylistId(playlist_id),
    max_results: Some(50),
    on_behalf_of_content_owner: None,
    page_token: page_token,
    video_id: None,
  ))
  let page_items = resp.items
  let video_ids =
    list.filter_map(page_items, fn(item) {
      option.to_result(playlist_item_video_id(item), Nil)
    })
  on_log(
    "youtube: got "
    <> int.to_string(list.length(page_items))
    <> " items, fetching durations for "
    <> int.to_string(list.length(video_ids))
    <> " videos",
  )
  let durations = fetch_durations_for_ids(client, video_ids, on_log)
  let unified =
    list.filter_map(page_items, fn(item) {
      playlist_item_to_unified_item(item, durations)
    })
  on_log(
    "youtube: page produced "
    <> int.to_string(list.length(unified))
    <> " unified items",
  )
  let new_acc = list.append(acc, unified)
  case resp.next_page_token {
    None -> Ok(new_acc)
    Some(_) ->
      fetch_all_pages_pingpong(
        client,
        playlist_id,
        resp.next_page_token,
        new_acc,
        on_log,
      )
  }
}

/// Batch video IDs into chunks of 50 and call Videos.list for each chunk.
fn fetch_durations_for_ids(
  client: Client,
  video_ids: List(String),
  on_log: fn(String) -> Nil,
) -> Dict(String, Float) {
  list.sized_chunk(video_ids, 50)
  |> list.flat_map(fn(chunk) {
    on_log(
      "youtube: calling Videos.list for "
      <> int.to_string(list.length(chunk))
      <> " IDs",
    )
    case
      videos.list(
        client,
        parts: [videos.ContentDetails],
        filter: videos.ById(chunk),
        hl: None,
        max_height: None,
        max_results: None,
        max_width: None,
        on_behalf_of_content_owner: None,
        page_token: None,
        region_code: None,
        video_category_id: None,
      )
    {
      Error(_) -> []
      Ok(resp) ->
        list.filter_map(resp.items, fn(video) {
          case video.id, video.content_details {
            Some(vid_id), Some(cd) ->
              case cd.duration {
                None -> Error(Nil)
                Some(iso) ->
                  case parse_iso8601_duration(iso) {
                    None -> Error(Nil)
                    Some(s) -> Ok(#(vid_id, s))
                  }
              }
            _, _ -> Error(Nil)
          }
        })
    }
  })
  |> dict.from_list
}

/// Parse ISO 8601 duration string (e.g. "PT3M45S", "PT1H2M3S", "PT45.5S") → seconds.
fn parse_iso8601_duration(iso: String) -> Option(Float) {
  let s = string.trim(iso)
  case string.starts_with(s, "PT") {
    False -> None
    True -> {
      let body = string.drop_start(s, 2)
      let #(hours, after_h) = case string.split_once(body, "H") {
        Ok(#(h, rest)) ->
          case int.parse(string.trim(h)) {
            Ok(n) -> #(n, rest)
            Error(_) -> #(0, body)
          }
        Error(_) -> #(0, body)
      }
      let #(minutes, after_m) = case string.split_once(after_h, "M") {
        Ok(#(m, rest)) ->
          case int.parse(string.trim(m)) {
            Ok(n) -> #(n, rest)
            Error(_) -> #(0, after_h)
          }
        Error(_) -> #(0, after_h)
      }
      let secs_f = case string.split_once(after_m, "S") {
        Ok(#(sec_raw, _)) ->
          case float.parse(string.trim(sec_raw)) {
            Ok(f) -> f
            Error(_) ->
              case int.parse(string.trim(sec_raw)) {
                Ok(n) -> int.to_float(n)
                Error(_) -> 0.0
              }
          }
        Error(_) -> 0.0
      }
      let total =
        int.to_float(hours * 3600 + minutes * 60) +. secs_f
      case total >. 0.0 {
        True -> Some(total)
        False -> None
      }
    }
  }
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
  durations: Dict(String, Float),
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
          let duration_s = dict.get(durations, vid) |> option.from_result
          core.track_item_with_added_at(
            "youtube",
            vid,
            title,
            artist,
            "",
            thumb,
            added_at,
            [],
            duration_s,
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
