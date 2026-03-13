import gleeunit
import gleeunit/should
import source_id_normalizer

pub fn main() {
  gleeunit.main()
}

pub fn normalizes_spotify_source_id_variants_test() {
  source_id_normalizer.normalize(
    "spotify",
    "https://open.spotify.com/track/5n4uWPmWMbg4XLzrkck25e?si=abc",
  )
  |> should.equal("5n4uWPmWMbg4XLzrkck25e")

  source_id_normalizer.normalize(
    "spotify",
    "spotify:track:5n4uWPmWMbg4XLzrkck25e",
  )
  |> should.equal("5n4uWPmWMbg4XLzrkck25e")
}

pub fn normalizes_youtube_source_id_variants_test() {
  source_id_normalizer.normalize(
    "youtube",
    "https://youtu.be/nPWrkoxiafI?si=foo",
  )
  |> should.equal("nPWrkoxiafI")

  source_id_normalizer.normalize(
    "youtube",
    "https://www.youtube.com/watch?v=nPWrkoxiafI&list=abc",
  )
  |> should.equal("nPWrkoxiafI")

  source_id_normalizer.normalize("youtube", "youtube:nPWrkoxiafI")
  |> should.equal("nPWrkoxiafI")
}

pub fn normalizes_soundcloud_and_bandcamp_source_id_variants_test() {
  source_id_normalizer.normalize("soundcloud", "soundcloud:1685501811")
  |> should.equal("1685501811")

  source_id_normalizer.normalize("soundcloud", "track:1685501811")
  |> should.equal("1685501811")

  source_id_normalizer.normalize("bandcamp", "bandcamp:2365071502")
  |> should.equal("2365071502")
}

pub fn keeps_file_and_itunes_ids_available_for_export_test() {
  source_id_normalizer.normalize("file", " /Users/jan/sets/2024/demo.flac ")
  |> should.equal("/Users/jan/sets/2024/demo.flac")

  source_id_normalizer.normalize("itunes", "itunes:A1B2C3")
  |> should.equal("A1B2C3")
}
