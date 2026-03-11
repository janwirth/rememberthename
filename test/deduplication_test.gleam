import deduplication
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn inserts_first_track_and_creates_bucket_test() {
  let result = deduplication.deduplicate([track("Song A", "Artist A", "youtube", "yt-1")])
  let deduplication.DeduplicationResult(buckets, ambiguities) = result

  list.length(buckets)
  |> should.equal(1)
  list.length(ambiguities)
  |> should.equal(0)
}

pub fn matches_second_track_by_exact_source_id_test() {
  let result =
    deduplication.deduplicate([
      track("Song A", "Artist A", "spotify", "spotify:track:abc"),
      track("Song A (Live)", "Artist B", "spotify", "abc"),
    ])
  let deduplication.DeduplicationResult(buckets, _) = result
  let bucket = first_bucket(buckets)
  let deduplication.Bucket(_, _, _, source_links, _, _, _) = bucket

  list.length(buckets)
  |> should.equal(1)
  list.length(source_links)
  |> should.equal(1)
}

pub fn matches_by_strong_normalized_title_and_artist_test() {
  let result =
    deduplication.deduplicate([
      track("My Song!", "The Artist", "youtube", "yt-1"),
      track("my song", "the artist", "soundcloud", "sc-1"),
    ])
  let deduplication.DeduplicationResult(buckets, _) = result
  let deduplication.Bucket(_, _, _, source_links, _, _, _) = first_bucket(buckets)

  list.length(buckets)
  |> should.equal(1)
  list.length(source_links)
  |> should.equal(2)
}

pub fn creates_new_bucket_when_no_rule_matches_test() {
  let result =
    deduplication.deduplicate([
      track("Song A", "Artist A", "youtube", "yt-1"),
      track("Song B", "Artist B", "youtube", "yt-2"),
    ])
  let deduplication.DeduplicationResult(buckets, _) = result

  list.length(buckets)
  |> should.equal(2)
}

pub fn rejects_ambiguous_multi_candidate_metadata_matches_test() {
  let result =
    deduplication.deduplicate([
      track("Shared", "Alpha", "youtube", "yt-1"),
      track("Shared", "Beta", "spotify", "sp-1"),
      track("Shared", "", "soundcloud", "sc-1"),
    ])
  let deduplication.DeduplicationResult(buckets, ambiguities) = result

  list.length(buckets)
  |> should.equal(2)
  list.length(ambiguities)
  |> should.equal(1)
}

pub fn prevents_duplicate_source_links_in_one_bucket_test() {
  let result =
    deduplication.deduplicate([
      track("Song A", "Artist A", "youtube", "yt-1"),
      track("Song A", "Artist A", "youtube", "yt-1"),
    ])
  let deduplication.DeduplicationResult(buckets, _) = result
  let deduplication.Bucket(_, _, _, source_links, _, _, _) = first_bucket(buckets)

  list.length(source_links)
  |> should.equal(1)
}

pub fn stores_local_asset_refs_with_device_uri_test() {
  let local_cover =
    deduplication.local_asset(
      deduplication.Cover,
      "mbp-jw-01",
      "/Users/jan/Music/library/Some Track.wav",
      dict.new(),
    )
  let with_asset =
    deduplication.TrackItem(
      title: "Song A",
      artist: "Artist A",
      adapter: "file",
      source_id: "file-1",
      raw_source_id: None,
      assets: [local_cover],
    )
  let result = deduplication.deduplicate([with_asset])
  let deduplication.DeduplicationResult(buckets, _) = result
  let deduplication.Bucket(_, _, _, _, assets, _, _) = first_bucket(buckets)
  let deduplication.AssetRef(_, _, uri, provider, _, _) = first_asset(assets)

  uri
  |> should.equal("device://mbp-jw-01/Users/jan/Music/library/Some Track.wav")
  provider
  |> should.equal("device")
}

pub fn stores_remote_asset_refs_with_s3_or_https_uri_test() {
  let remote_audio =
    deduplication.remote_asset(
      deduplication.Audio,
      "s3://rememberthename-audio/tracks/abc123.flac",
      "s3",
      dict.new(),
    )
  let with_asset =
    deduplication.TrackItem(
      title: "Song A",
      artist: "Artist A",
      adapter: "spotify",
      source_id: "sp-1",
      raw_source_id: None,
      assets: [remote_audio],
    )
  let result = deduplication.deduplicate([with_asset])
  let deduplication.DeduplicationResult(buckets, _) = result
  let deduplication.Bucket(_, _, _, _, assets, _, _) = first_bucket(buckets)
  let deduplication.AssetRef(_, location_type, uri, provider, _, _) = first_asset(assets)

  location_type
  |> should.equal(deduplication.Remote)
  uri
  |> should.equal("s3://rememberthename-audio/tracks/abc123.flac")
  provider
  |> should.equal("s3")
}

pub fn keeps_canonical_bucket_fields_stable_across_merges_test() {
  let result =
    deduplication.deduplicate([
      track("Canonical Title", "Canonical Artist", "youtube", "yt-1"),
      track("Replacement Title", "Replacement Artist", "youtube", "yt-1"),
    ])
  let deduplication.DeduplicationResult(buckets, _) = result
  let deduplication.Bucket(_, title, artist, _, _, _, _) = first_bucket(buckets)

  title
  |> should.equal("Canonical Title")
  artist
  |> should.equal("Canonical Artist")
}

pub fn rerun_of_same_inputs_is_idempotent_test() {
  let items = [
    track("Song A", "Artist A", "youtube", "yt-1"),
    track("Song A", "Artist A", "spotify", "sp-1"),
    track("Song B", "Artist B", "soundcloud", "sc-1"),
  ]
  let once = deduplication.deduplicate(items)
  let again = deduplication.deduplicate(items)

  once
  |> should.equal(again)
}

fn track(
  title: String,
  artist: String,
  adapter: String,
  source_id: String,
) -> deduplication.TrackItem {
  deduplication.TrackItem(
    title: title,
    artist: artist,
    adapter: adapter,
    source_id: source_id,
    raw_source_id: None,
    assets: [],
  )
}

fn first_bucket(buckets: List(deduplication.Bucket)) -> deduplication.Bucket {
  case buckets {
    [bucket, ..] -> bucket
    _ ->
      deduplication.Bucket(
        bucket_id: "missing",
        title: "",
        artist: "",
        source_links: [],
        assets: [],
        created_at: "",
        updated_at: "",
      )
  }
}

fn first_asset(assets: List(deduplication.AssetRef)) -> deduplication.AssetRef {
  case assets {
    [asset, ..] -> asset
    _ ->
      deduplication.AssetRef(
        asset_type: deduplication.Cover,
        location_type: deduplication.Local,
        uri: "",
        provider: "",
        content_hash: None,
        metadata: dict.new(),
      )
  }
}
