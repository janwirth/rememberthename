//// Shared source id normalizer used by adapters and import paths.
////
//// Implemented normalization:
//// - spotify URL/URI forms -> canonical track id
//// - youtube URL forms -> canonical video id
//// - soundcloud/bandcamp canonical text cleanup
//// - file/itunes passthrough cleanup
////
//// This module currently returns normalized id strings only.
//// Legacy-import overlap fields (raw + normalized + confidence metadata)
//// are not modeled here yet and must be carried by the importer layer.

import gleam/string

pub fn normalize(service: String, source_id: String) -> String {
  let cleaned = source_id |> string.trim
  case cleaned == "" {
    True -> ""
    False ->
      case service {
        "spotify" -> normalize_spotify(cleaned)
        "youtube" -> normalize_youtube(cleaned)
        "soundcloud" -> normalize_soundcloud(cleaned)
        "bandcamp" -> normalize_bandcamp(cleaned)
        "file" -> normalize_file(cleaned)
        "itunes" -> normalize_itunes(cleaned)
        _ -> cleaned
      }
  }
}

fn normalize_spotify(raw: String) -> String {
  let without_prefix = strip_prefix(raw, "spotify:item:")
  let from_uri = strip_prefix(without_prefix, "spotify:track:")
  case string.contains(from_uri, "open.spotify.com/") {
    True -> {
      let as_track = extract_after_marker(from_uri, "/track/")
      let base = first_before_char(as_track, "?")
      first_before_char(base, "/")
    }
    False -> from_uri
  }
}

fn normalize_youtube(raw: String) -> String {
  let without_prefix = strip_prefix(raw, "youtube:item:")
  case string.contains(without_prefix, "youtu.be/") {
    True -> {
      let short = extract_after_marker(without_prefix, "youtu.be/")
      first_before_char(short, "?")
    }
    False ->
      case string.contains(without_prefix, "watch?v=") {
        True -> {
          let watch = extract_after_marker(without_prefix, "watch?v=")
          first_before_char(watch, "&")
        }
        False -> without_prefix
      }
  }
}

fn normalize_soundcloud(raw: String) -> String {
  raw
  |> strip_prefix("soundcloud:item:")
  |> strip_prefix("track:")
}

fn normalize_bandcamp(raw: String) -> String {
  raw
  |> strip_prefix("bandcamp:item:")
  |> string.trim
}

fn normalize_file(raw: String) -> String {
  string.trim(raw)
}

fn normalize_itunes(raw: String) -> String {
  raw
  |> strip_prefix("itunes:item:")
  |> string.trim
}

fn strip_prefix(value: String, prefix: String) -> String {
  case string.starts_with(value, prefix) {
    True -> extract_after_marker(value, prefix)
    False -> value
  }
}

fn extract_after_marker(value: String, marker: String) -> String {
  case string.split_once(value, marker) {
    Ok(#(_, after)) -> after
    Error(_) -> value
  }
}

fn first_before_char(value: String, separator: String) -> String {
  case string.split_once(value, separator) {
    Ok(#(before, _)) -> before
    Error(_) -> value
  }
}
