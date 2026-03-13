import gleeunit
import gleeunit/should
import resource_id

pub fn main() {
  gleeunit.main()
}

pub fn parse_valid_platform_id_test() {
  let parsed =
    resource_id.parse("rid:v1:platform:youtube:track:nPWrkoxiafI")
    |> should.be_ok
  resource_id.to_string(parsed)
  |> should.equal("rid:v1:platform:youtube:track:nPWrkoxiafI")
}

pub fn parse_rejects_invalid_prefix_test() {
  resource_id.parse("bad:v1:platform:youtube:track:nPWrkoxiafI")
  |> should.equal(Error(resource_id.InvalidPrefix))
}

pub fn parse_rejects_invalid_segment_count_test() {
  resource_id.parse("rid:v1:platform:youtube:track")
  |> should.equal(Error(resource_id.InvalidSegmentCount))
}

pub fn local_file_payload_encode_decode_test() {
  let payload =
    resource_id.encode_local_file_payload(
      "mbp-jan-01",
      "/Users/jan/music/a.flac",
    )
    |> should.be_ok
  payload
  |> should.equal("device=mbp-jan-01|path=/Users/jan/music/a.flac")

  resource_id.decode_local_file_payload(payload)
  |> should.equal(Ok(#("mbp-jan-01", "/Users/jan/music/a.flac")))
}

pub fn parse_valid_local_file_id_with_device_test() {
  let parsed =
    resource_id.parse(
      "rid:v1:local:file:path:device=mbp-jan-01|path=/Users/jan/music/a.flac",
    )
    |> should.be_ok
  resource_id.to_string(parsed)
  |> should.equal(
    "rid:v1:local:file:path:device=mbp-jan-01|path=/Users/jan/music/a.flac",
  )
}

pub fn parse_rejects_local_file_without_device_payload_test() {
  resource_id.parse("rid:v1:local:file:path:/Users/jan/music/a.flac")
  |> should.equal(Error(resource_id.InvalidLocalFilePayload))
}

pub fn build_normalizes_spotify_track_url_test() {
  let built =
    resource_id.build(
      resource_id.Platform,
      "spotify",
      "track",
      "https://open.spotify.com/track/5n4uWPmWMbg4XLzrkck25e?si=abc",
    )
    |> should.be_ok
  resource_id.to_string(built)
  |> should.equal("rid:v1:platform:spotify:track:5n4uWPmWMbg4XLzrkck25e")
}

pub fn build_normalizes_youtube_short_url_test() {
  let built =
    resource_id.build(
      resource_id.Platform,
      "youtube",
      "track",
      "https://youtu.be/nPWrkoxiafI?si=foo",
    )
    |> should.be_ok
  resource_id.to_string(built)
  |> should.equal("rid:v1:platform:youtube:track:nPWrkoxiafI")
}

pub fn build_encodes_colon_in_payload_test() {
  let built =
    resource_id.build(resource_id.Platform, "legacy", "track", "sha256:2f8d9c")
    |> should.be_ok
  resource_id.to_string(built)
  |> should.equal("rid:v1:platform:legacy:track:sha256%3A2f8d9c")
}

pub fn build_normalizes_local_file_path_payload_test() {
  let built =
    resource_id.build(
      resource_id.Local,
      "file",
      "path",
      "device=mbp-jan-01|path=//Users//jan\\music\\set//a.flac",
    )
    |> should.be_ok
  resource_id.to_string(built)
  |> should.equal(
    "rid:v1:local:file:path:device=mbp-jan-01|path=/Users/jan/music/set/a.flac",
  )
}
