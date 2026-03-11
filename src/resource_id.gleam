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
  let ResourceId(version, origin, service, resource_type, encoded_id) = resource_id
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
              case validate_local_payload(origin, service, resource_type, encoded_id) {
                Error(error) -> Error(error)
                Ok(_) ->
                  Ok(ResourceId(version, origin, service, resource_type, encoded_id))
              }
          }
        }
      }
    }
    _ -> Error(InvalidSegmentCount)
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
        False ->
          Ok(
            "device=" <> cleaned_device <> "|path=" <> cleaned_path,
          )
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

fn origin_to_string(origin: Origin) -> String {
  case origin {
    Platform -> "platform"
    Local -> "local"
  }
}
