import cli
import gleeunit
import gleeunit/should
import gleam/option.{None, Some}

pub fn main() {
  gleeunit.main()
}

pub fn normalize_tuna_tags_overrides_existing_rating_tags_test() {
  cli.normalize_tuna_tags(
    ["genre:techno", "rating:2", "set:night", "Rating5"],
    4,
  )
  |> should.equal("tag/genre/:techno | tag/set/:night | :rating:4")
}

pub fn format_tuna_source_id_uses_source_type_prefix_test() {
  cli.format_tuna_source_id("spotify", "5n4uWPmWMbg4XLzrkck25e")
  |> should.equal("5n4uWPmWMbg4XLzrkck25e")

  cli.format_tuna_source_id("file", "/Users/janwirth/track.mp3")
  |> should.equal("/Users/janwirth/track.mp3")
}

pub fn export_tags_returns_empty_list_for_empty_input_test() {
  cli.export_tags("") |> should.equal([])
  cli.export_tags("   ") |> should.equal([])
}

pub fn export_tags_splits_pipe_separated_values_test() {
  cli.export_tags("tag/genre/:house | :rating:8 |  tag/label/:night ")
  |> should.equal(["tag/genre/:house", ":rating:8", "tag/label/:night"])
}

pub fn nullable_file_path_uses_none_for_empty_values_test() {
  cli.nullable_file_path("") |> should.equal(None)
  cli.nullable_file_path("   ") |> should.equal(None)
}

pub fn nullable_file_path_preserves_non_empty_values_test() {
  cli.nullable_file_path("/tmp/set.mp3")
  |> should.equal(Some("/tmp/set.mp3"))
}

pub fn normalize_tuna_metadata_source_id_handles_prefixed_values_test() {
  cli.normalize_tuna_metadata_source_id("soundcloud", "soundcloud:1685501811")
  |> should.equal("1685501811")

  cli.normalize_tuna_metadata_source_id("spotify", "spotify:track:5n4uWPm")
  |> should.equal("5n4uWPm")
}
