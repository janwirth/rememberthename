import gleam/list
import gleeunit
import gleeunit/should
import source_limit_validation

pub fn main() {
  gleeunit.main()
}

pub fn keeps_max_n_per_source_after_sorting_test() {
  let raw = [
    source_limit_validation.RawTrack("a2", "artist", "spotify", "sp-2", 2.0),
    source_limit_validation.RawTrack("a1", "artist", "spotify", "sp-1", 1.0),
    source_limit_validation.RawTrack("y2", "artist", "youtube", "yt-2", 2.0),
    source_limit_validation.RawTrack("y1", "artist", "youtube", "yt-1", 1.0),
    source_limit_validation.RawTrack("y3", "artist", "youtube", "yt-3", 3.0),
  ]
  let limits = [
    source_limit_validation.SourceLimit("spotify", 1),
    source_limit_validation.SourceLimit("youtube", 2),
  ]
  let processed = source_limit_validation.process(raw, limits)
  track_ids(processed)
  |> should.equal(["sp-1", "yt-1", "yt-2"])
}

pub fn treats_timestamp_order_as_numeric_test() {
  let raw = [
    source_limit_validation.RawTrack(
      "late",
      "artist",
      "youtube",
      "yt-late",
      1_710_001_000.0,
    ),
    source_limit_validation.RawTrack(
      "early",
      "artist",
      "youtube",
      "yt-early",
      1_710_000_000.0,
    ),
  ]
  source_limit_validation.process(raw, [])
  |> track_ids
  |> should.equal(["yt-early", "yt-late"])
}

pub fn order_does_not_need_to_be_contiguous_test() {
  let raw = [
    source_limit_validation.RawTrack(
      "gap-c",
      "artist",
      "spotify",
      "sp-c",
      3000.0,
    ),
    source_limit_validation.RawTrack("gap-a", "artist", "spotify", "sp-a", 5.0),
    source_limit_validation.RawTrack(
      "gap-b",
      "artist",
      "spotify",
      "sp-b",
      220.0,
    ),
  ]
  source_limit_validation.process(raw, [])
  |> track_ids
  |> should.equal(["sp-a", "sp-b", "sp-c"])
}

pub fn marks_missing_artist_without_dropping_track_test() {
  let raw = [
    source_limit_validation.RawTrack("normal", "artist", "spotify", "sp-1", 1.0),
    source_limit_validation.RawTrack("missing", "", "spotify", "sp-2", 2.0),
  ]
  let processed = source_limit_validation.process(raw, [])
  list.length(processed) |> should.equal(2)
  let missing =
    processed
    |> list.filter(fn(track) { source_id(track) == "sp-2" })
    |> list.first
    |> should.be_ok
  source_limit_validation.is_missing_artist(missing)
  |> should.equal(True)
}

pub fn non_positive_limit_returns_zero_items_for_service_test() {
  let raw = [
    source_limit_validation.RawTrack("a", "artist", "spotify", "sp-1", 1.0),
    source_limit_validation.RawTrack("b", "artist", "youtube", "yt-1", 1.0),
  ]
  let limits = [source_limit_validation.SourceLimit("spotify", 0)]
  source_limit_validation.process(raw, limits)
  |> track_ids
  |> should.equal(["yt-1"])
}

fn track_ids(
  tracks: List(source_limit_validation.CanonicalTrack),
) -> List(String) {
  list.map(tracks, source_id)
}

fn source_id(track: source_limit_validation.CanonicalTrack) -> String {
  let source_limit_validation.CanonicalTrack(_, _, _, source_id, _, _) = track
  source_id
}
