import gleam/list
import gleam/string

const default_bucket_id = "<bucket_id>"

pub fn from_md5_source(md5: String, ext: String) -> String {
  from_md5_source_with_bucket(default_bucket_id, md5, ext)
}

pub fn from_md5_source_with_bucket(
  bucket_id: String,
  md5: String,
  ext: String,
) -> String {
  let clean_bucket = string.trim(bucket_id)
  let clean_md5 = string.trim(md5)
  let clean_ext = normalize_ext(ext)
  case clean_bucket == "" || clean_md5 == "" || clean_ext == "" {
    True -> ""
    False -> "s3://" <> clean_bucket <> "/" <> clean_md5 <> "." <> clean_ext
  }
}

fn normalize_ext(ext: String) -> String {
  let trimmed = string.trim(ext)
  case string.starts_with(trimmed, ".") {
    True -> trimmed |> string.to_graphemes |> list.drop(1) |> string.concat
    False -> trimmed
  }
}
