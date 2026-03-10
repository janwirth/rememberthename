import gleeunit
import gleeunit/should
import output/csv_writer
import output/visual_output

pub fn main() {
  gleeunit.main()
}

pub fn tracks_csv_writes_header_and_rows_test() {
  let tracks = [
    visual_output.TrackView("A", "AA", "soundcloud", "sc-a"),
    visual_output.TrackView("B", "BB", "spotify", "sp-b"),
  ]

  let expected =
    "title,artist,service,source_id\n"
    <> "A,AA,soundcloud,sc-a\n"
    <> "B,BB,spotify,sp-b"

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
    ),
  ]

  let expected =
    "title,artist,service,source_id\n"
    <> "\"Track, \"\"One\"\"\",\"Line\nBreak\",youtube,id-1"

  csv_writer.tracks_csv(tracks)
  |> should.equal(expected)
}
