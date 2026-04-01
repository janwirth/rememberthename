import cli
import gleam/option.{None}
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
        None,
        "2026-03-31T00:00:00Z",
        "bandcamp + profile",
        "",
        "",
        "",
      ),
    ])

  string.contains(content, "\"file\":null")
  |> should.equal(True)

  string.contains(content, "\"cover\":null")
  |> should.equal(True)

  string.contains(content, "\"tags\":[]")
  |> should.equal(True)

  string.contains(content, "\"order\":1")
  |> should.equal(True)

  string.contains(content, "\"imported_date\":null")
  |> should.equal(True)

  string.contains(content, "\"external_source_url\":null")
  |> should.equal(True)

  string.contains(content, "\"added_at\":\"2026-03-31T00:00:00Z\"")
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
        None,
        "",
        "tuna + fishbone",
        "/tmp/track-b.mp3",
        "/tmp/track-b.jpg",
        "genre:house | rating:8",
      ),
    ])

  string.contains(content, "\"file\":\"/tmp/track-b.mp3\"")
  |> should.equal(True)

  string.contains(content, "\"cover\":\"/tmp/track-b.jpg\"")
  |> should.equal(True)

  string.contains(content, "\"tags\":[\"tag/genre/:house\",\":rating:8\"]")
  |> should.equal(True)

  string.contains(content, "\"order\":1")
  |> should.equal(True)

  string.contains(content, "\"imported_date\":null")
  |> should.equal(True)
}

pub fn tracks_json_uses_descending_order_so_first_track_is_highest_test() {
  let content =
    cli.tracks_json([
      visual_output.TrackView(
        "Track Newest",
        "Artist A",
        "youtube",
        "yt-new",
        None,
        "",
        "youtube + profile",
        "",
        "",
        "",
      ),
      visual_output.TrackView(
        "Track Older",
        "Artist B",
        "youtube",
        "yt-old",
        None,
        "",
        "youtube + profile",
        "",
        "",
        "",
      ),
    ])

  {
    string.contains(content, "\"source_id\":\"yt-new\"")
    && string.contains(content, "\"order\":2")
  }
  |> should.equal(True)

  {
    string.contains(content, "\"source_id\":\"yt-old\"")
    && string.contains(content, "\"order\":1")
  }
  |> should.equal(True)
}
