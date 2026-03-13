import gleam/string

pub type Origin {
  Platform
  Local
}

pub type ResourceId {
  ResourceId(
    version: String,
    origin: Origin,
    service: String,
    resource_type: String,
    encoded_id: String,
  )
}

pub type ParseError {
  InvalidSegmentCount
  InvalidPrefix
  UnsupportedVersion
  InvalidOrigin
  EmptyService
  EmptyResourceType
  EmptyEncodedId
  InvalidLocalFilePayload
}

pub fn to_string(resource_id: ResourceId) -> String {
  let ResourceId(version, origin, service, resource_type, encoded_id) =
    resource_id
  "rid:"
  <> version
  <> ":"
  <> origin_to_string(origin)
  <> ":"
  <> service
  <> ":"
  <> resource_type
  <> ":"
  <> encoded_id
}

pub fn parse(value: String) -> Result(ResourceId, ParseError) {
  case string.trim(value) |> string.split(":") {
    [prefix, version, origin_raw, service, resource_type, encoded_id] -> {
      case validate_head(prefix, version, origin_raw) {
        Error(error) -> Error(error)
        Ok(origin) -> {
          case validate_fields(service, resource_type, encoded_id) {
            Error(error) -> Error(error)
            Ok(_) ->
              case
                validate_local_payload(
                  origin,
                  service,
                  resource_type,
                  encoded_id,
                )
              {
                Error(error) -> Error(error)
                Ok(_) ->
                  Ok(ResourceId(
                    version,
                    origin,
                    service,
                    resource_type,
                    encoded_id,
                  ))
              }
          }
        }
      }
    }
    _ -> Error(InvalidSegmentCount)
  }
}

pub fn build(
  origin: Origin,
  service: String,
  resource_type: String,
  raw_id: String,
) -> Result(ResourceId, ParseError) {
  let cleaned_service = service |> string.trim |> string.lowercase
  let cleaned_resource_type = resource_type |> string.trim |> string.lowercase
  let normalized_id =
    normalize_payload(
      origin,
      cleaned_service,
      cleaned_resource_type,
      raw_id |> string.trim,
    )
    |> encode_payload
  case validate_fields(cleaned_service, cleaned_resource_type, normalized_id) {
    Error(error) -> Error(error)
    Ok(_) ->
      case
        validate_local_payload(
          origin,
          cleaned_service,
          cleaned_resource_type,
          normalized_id,
        )
      {
        Error(error) -> Error(error)
        Ok(_) ->
          Ok(ResourceId(
            version: "v1",
            origin: origin,
            service: cleaned_service,
            resource_type: cleaned_resource_type,
            encoded_id: normalized_id,
          ))
      }
  }
}

pub fn encode_local_file_payload(
  device_id: String,
  normalized_path: String,
) -> Result(String, ParseError) {
  let cleaned_device = string.trim(device_id)
  let cleaned_path = string.trim(normalized_path)
  case cleaned_device == "" {
    True -> Error(InvalidLocalFilePayload)
    False ->
      case cleaned_path == "" {
        True -> Error(InvalidLocalFilePayload)
        False -> Ok("device=" <> cleaned_device <> "|path=" <> cleaned_path)
      }
  }
}

pub fn decode_local_file_payload(
  payload: String,
) -> Result(#(String, String), ParseError) {
  case string.split_once(payload, "|path=") {
    Ok(#(left, path)) -> {
      case string.split_once(left, "device=") {
        Ok(#("", device_id)) ->
          case device_id == "" || path == "" {
            True -> Error(InvalidLocalFilePayload)
            False -> Ok(#(device_id, path))
          }
        _ -> Error(InvalidLocalFilePayload)
      }
    }
    Error(_) -> Error(InvalidLocalFilePayload)
  }
}

fn validate_head(
  prefix: String,
  version: String,
  origin_raw: String,
) -> Result(Origin, ParseError) {
  case prefix != "rid" {
    True -> Error(InvalidPrefix)
    False ->
      case version != "v1" {
        True -> Error(UnsupportedVersion)
        False -> parse_origin(origin_raw)
      }
  }
}

fn parse_origin(value: String) -> Result(Origin, ParseError) {
  case value {
    "platform" -> Ok(Platform)
    "local" -> Ok(Local)
    _ -> Error(InvalidOrigin)
  }
}

fn validate_fields(
  service: String,
  resource_type: String,
  encoded_id: String,
) -> Result(Nil, ParseError) {
  case service == "" {
    True -> Error(EmptyService)
    False ->
      case resource_type == "" {
        True -> Error(EmptyResourceType)
        False ->
          case encoded_id == "" {
            True -> Error(EmptyEncodedId)
            False -> Ok(Nil)
          }
      }
  }
}

fn validate_local_payload(
  origin: Origin,
  service: String,
  resource_type: String,
  encoded_id: String,
) -> Result(Nil, ParseError) {
  case origin, service, resource_type {
    Local, "file", "path" ->
      case decode_local_file_payload(encoded_id) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(InvalidLocalFilePayload)
      }
    _, _, _ -> Ok(Nil)
  }
}

fn normalize_payload(
  origin: Origin,
  service: String,
  resource_type: String,
  raw_id: String,
) -> String {
  case origin, service, resource_type {
    Platform, "spotify", "track" -> normalize_spotify(raw_id)
    Platform, "youtube", "track" -> normalize_youtube(raw_id)
    Platform, "soundcloud", "track" -> normalize_host_path(raw_id)
    Platform, "bandcamp", "track" -> normalize_bandcamp(raw_id)
    Platform, "itunes", "track" -> raw_id
    Platform, "itunes", "persistent_track" -> raw_id
    Local, "file", "path" -> normalize_local_file_payload(raw_id)
    Local, "legacy", "track" -> raw_id
    _, _, _ -> raw_id
  }
}

fn normalize_spotify(raw_id: String) -> String {
  let from_uri = strip_prefix(raw_id, "spotify:track:")
  case string.contains(from_uri, "open.spotify.com/track/") {
    True -> {
      let value = extract_after_marker(from_uri, "/track/")
      value |> first_before_char("?") |> first_before_char("/")
    }
    False -> from_uri
  }
}

fn normalize_youtube(raw_id: String) -> String {
  case string.contains(raw_id, "youtu.be/") {
    True -> {
      let value = extract_after_marker(raw_id, "youtu.be/")
      value |> first_before_char("?") |> first_before_char("&")
    }
    False ->
      case string.contains(raw_id, "watch?v=") {
        True -> {
          let value = extract_after_marker(raw_id, "watch?v=")
          value |> first_before_char("&") |> first_before_char("/")
        }
        False -> raw_id
      }
  }
}

fn normalize_bandcamp(raw_id: String) -> String {
  case all_digits(raw_id) {
    True -> raw_id
    False -> normalize_host_path(raw_id)
  }
}

fn normalize_host_path(raw_id: String) -> String {
  raw_id
  |> strip_prefix("https://")
  |> strip_prefix("http://")
  |> strip_prefix("www.")
  |> first_before_char("?")
  |> trim_trailing_slash
}

fn normalize_local_file_payload(payload: String) -> String {
  case decode_local_file_payload(payload) {
    Ok(#(device_id, path)) ->
      "device=" <> device_id <> "|path=" <> normalize_path(path)
    Error(_) -> payload
  }
}

fn normalize_path(path: String) -> String {
  path
  |> string.replace("\\", "/")
  |> collapse_double_slashes
}

fn collapse_double_slashes(path: String) -> String {
  case string.contains(path, "//") {
    True -> collapse_double_slashes(string.replace(path, "//", "/"))
    False -> path
  }
}

fn trim_trailing_slash(value: String) -> String {
  case value == "/" || !string.ends_with(value, "/") {
    True -> value
    False ->
      case string.pop_grapheme(value) {
        Ok(#(next, _)) -> trim_trailing_slash(next)
        Error(_) -> value
      }
  }
}

fn encode_payload(value: String) -> String {
  string.replace(value, ":", "%3A")
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

fn all_digits(value: String) -> Bool {
  case string.to_graphemes(value) {
    [] -> False
    chars -> all_digit_chars(chars)
  }
}

fn all_digit_chars(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    [char, ..rest] ->
      case is_ascii_digit(char) {
        True -> all_digit_chars(rest)
        False -> False
      }
  }
}

fn is_ascii_digit(char: String) -> Bool {
  case char {
    "0" -> True
    "1" -> True
    "2" -> True
    "3" -> True
    "4" -> True
    "5" -> True
    "6" -> True
    "7" -> True
    "8" -> True
    "9" -> True
    _ -> False
  }
}

fn origin_to_string(origin: Origin) -> String {
  case origin {
    Platform -> "platform"
    Local -> "local"
  }
}
