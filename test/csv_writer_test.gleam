import gleam/option.{None}
import gleeunit
import gleeunit/should
import output/csv_writer
import output/visual_output

pub fn main() {
  gleeunit.main()
}

pub fn tracks_csv_writes_header_and_rows_test() {
  let tracks = [
    visual_output.TrackView(
      "A",
      "AA",
      "soundcloud",
      "sc-a",
      None,
      "source-a",
      "",
      "",
      "",
    ),
    visual_output.TrackView(
      "B",
      "BB",
      "spotify",
      "sp-b",
      None,
      "source-b",
      "",
      "",
      "tag-one",
    ),
  ]

  let expected =
    "title,artist,service,source_id,external_source_url,adapter_id,download,cover,tags\n"
    <> "A,AA,soundcloud,sc-a,,source-a,,,\n"
    <> "B,BB,spotify,sp-b,,source-b,,,tag-one"

  csv_writer.tracks_csv(tracks)
  |> should.equal(expected)
}

pub fn tracks_csv_escapes_quotes_commas_and_newlines_test() {
  let tracks = [
    visual_output.TrackView(
      "Track, \"One\"",
      "Line\nBreak",
      "youtube",
      "id-1",
      None,
      "source-youtube",
      "/tmp/track.mp3",
      "/tmp/track.jpg",
      "drum & bass, \"leftfield\"",
    ),
  ]

  let expected =
    "title,artist,service,source_id,external_source_url,adapter_id,download,cover,tags\n"
    <> "\"Track, \"\"One\"\"\",\"Line\nBreak\",youtube,id-1,,source-youtube,/tmp/track.mp3,/tmp/track.jpg,\"drum & bass, \"\"leftfield\"\"\""

  csv_writer.tracks_csv(tracks)
  |> should.equal(expected)
}
