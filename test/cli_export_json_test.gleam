import cli
import gleeunit
import gleeunit/should
import gleam/string
import output/visual_output

pub fn main() {
  gleeunit.main()
}

pub fn tracks_json_exports_nullable_file_and_empty_tags_list_test() {
  let content =
    cli.tracks_json([
      visual_output.TrackView(
        "Track A",
        "Artist A",
        "bandcamp",
        "2365071502",
        "bandcamp + profile",
        "",
        "",
      ),
    ])

  string.contains(content, "\"file\":null")
  |> should.equal(True)

  string.contains(content, "\"tags\":[]")
  |> should.equal(True)
}

pub fn tracks_json_exports_file_and_split_tag_list_test() {
  let content =
    cli.tracks_json([
      visual_output.TrackView(
        "Track B",
        "Artist B",
        "soundcloud",
        "1685501811",
        "tuna + fishbone",
        "/tmp/track-b.mp3",
        "genre:house | rating8",
      ),
    ])

  string.contains(content, "\"file\":\"/tmp/track-b.mp3\"")
  |> should.equal(True)

  string.contains(content, "\"tags\":[\"genre:house\",\"rating8\"]")
  |> should.equal(True)
}
