import gleam/int
import gleam/list
import gleam/string
import source_id_normalizer

/// Normalizes a service + raw id for consistent metadata keys (exported for reuse).
pub fn normalize_tuna_metadata_source_id(
  service: String,
  source_id: String,
) -> String {
  source_id_normalizer.normalize(service, source_id)
}

/// Splits a tuna tag on US (`\u001F`) into label and emoji (or whole string as label).
pub fn decode_tuna_tag_token(token: String) -> #(String, String) {
  case string.split_once(token, "\u{001F}") {
    Ok(#(label, emoji)) -> #(string.trim(label), string.trim(emoji))
    Error(_) -> #(string.trim(token), "")
  }
}

/// Renders one decoded token as `tag/<category>/<emoji>:<value>`.
pub fn format_export_tag(token: String) -> String {
  let #(label, emoji) = decode_tuna_tag_token(token)
  let #(category, value) = split_tag_label(label)
  "tag/" <> category <> "/" <> emoji <> ":" <> value
}

/// Splits `category:value` on first colon; normalizes empty parts to `unknown`.
fn split_tag_label(label: String) -> #(String, String) {
  case string.split_once(label, ":") {
    Ok(#(category, value)) ->
      #(normalized_tag_part(category), normalized_tag_part(value))
    Error(_) -> #("label", normalized_tag_part(label))
  }
}

/// Trim helper: empty string becomes `"unknown"`.
pub fn normalized_tag_part(value: String) -> String {
  let trimmed = string.trim(value)
  case trimmed == "" {
    True -> "unknown"
    False -> trimmed
  }
}

/// Drops inline rating tags, formats the rest for export, then appends `:rating:N`.
pub fn normalize_tuna_tags(tags: List(String), rating: Int) -> String {
  let rating_tag = ":rating:" <> int.to_string(rating)
  let normalized_tags =
    tags
    |> list.filter(fn(tag) {
      let #(label, _) = decode_tuna_tag_token(tag)
      !string.starts_with(string.lowercase(label), "rating")
    })
    |> list.map(format_export_tag)
  string.join(list.append(normalized_tags, [rating_tag]), " | ")
}

/// Formats a tuna track id for display/export (currently the raw `source_id`).
pub fn format_tuna_source_id(service: String, source_id: String) -> String {
  let _ = service
  source_id
}

/// Splits a `|`-separated tag blob and normalizes each entry for JSON.
pub fn export_tags(tags: String) -> List(String) {
  export_tags_with_mode(tags, True)
}

/// Tokenizes pipe-separated tags; optionally passes each through `normalize_export_tag_entry`.
pub fn export_tags_with_mode(tags: String, normalize_tags: Bool) -> List(String) {
  tags
  |> string.split("|")
  |> list.map(string.trim)
  |> list.filter(fn(tag) { tag != "" })
  |> list.map(fn(tag) {
    case normalize_tags {
      True -> normalize_export_tag_entry(tag)
      False -> tag
    }
  })
}

/// Coerces legacy or shorthand tag strings into stable export form.
pub fn normalize_export_tag_entry(tag: String) -> String {
  let cleaned = string.trim(tag)
  let lowered = string.lowercase(cleaned)
  case cleaned == "" {
    True -> ""
    False ->
      case string.starts_with(cleaned, ":rating:") {
        True -> cleaned
        False ->
          case string.starts_with(cleaned, "tag/") {
            True -> cleaned
            False ->
              case string.starts_with(lowered, "rating:") {
                True ->
                  case string.split_once(cleaned, ":") {
                    Ok(#(_, value)) -> ":rating:" <> normalized_tag_part(value)
                    Error(_) -> ":rating:unknown"
                  }
                False -> format_export_tag(cleaned)
              }
          }
      }
  }
}
