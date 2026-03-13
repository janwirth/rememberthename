import cli
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn normalize_tuna_tags_overrides_existing_rating_tags_test() {
  cli.normalize_tuna_tags(
    ["genre:techno", "rating:2", "set:night", "Rating5"],
    4,
  )
  |> should.equal("genre:techno | set:night | rating4")
}

pub fn format_tuna_source_id_uses_source_type_prefix_test() {
  cli.format_tuna_source_id("spotify", "5n4uWPmWMbg4XLzrkck25e")
  |> should.equal("spotify:5n4uWPmWMbg4XLzrkck25e")

  cli.format_tuna_source_id("file", "/Users/janwirth/track.mp3")
  |> should.equal("file:/Users/janwirth/track.mp3")
}
