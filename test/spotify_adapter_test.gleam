import adapters/api_keys
import adapters/spotify/live_expander as spotify_live_expander
import cli/spotify_credentials
import depth_test_spec
import gleam/list
import sources
import test_env

// ── Unit tests for TSV parsing (no network required) ──────────────────────────

const track_url = "https://open.spotify.com/track/"

const cover_url = "https://i.scdn.co/image/abc"

const added_at = "2024-01-01T00:00:00Z"

pub fn parse_8col_extracts_artist_id_test() {
  let tsv =
    "ABC123\tSong Title\tArtist Name\t"
    <> track_url
    <> "ABC123\t"
    <> cover_url
    <> "\t"
    <> added_at
    <> "\t210000\tARTIST456"
  let pairs = spotify_live_expander.parse_track_items_with_artist_ids(tsv)
  let assert [#(item, artist_id)] = pairs
  assert item.id == "spotify:item:ABC123"
  assert artist_id == "ARTIST456"
}

// 6-col format has no duration_ms; track_item_strict rejects rows without duration.
// Stale cache in old 6-col format therefore produces no items at all (not wrong items).
pub fn parse_6col_drops_all_rows_test() {
  let tsv =
    "ABC123\tSong Title\tArtist Name\t"
    <> track_url
    <> "ABC123\t"
    <> cover_url
    <> "\t"
    <> added_at
  let pairs = spotify_live_expander.parse_track_items_with_artist_ids(tsv)
  assert pairs == []
}

pub fn parse_7col_no_artist_id_test() {
  let tsv =
    "ABC123\tSong Title\tArtist Name\t"
    <> track_url
    <> "ABC123\t"
    <> cover_url
    <> "\t"
    <> added_at
    <> "\t210000"
  let pairs = spotify_live_expander.parse_track_items_with_artist_ids(tsv)
  let assert [#(_, artist_id)] = pairs
  assert artist_id == ""
}

// Verifies each track gets its own artist_id, not the positionally nearest one.
// Regression test: stale 6-col cache caused all artist_ids to be "" so no
// genres were fetched; separately, genres stored under wrong item_id format.
pub fn parse_multi_track_artist_ids_not_swapped_test() {
  let row = fn(tid, title, artist, aid) {
    tid
    <> "\t"
    <> title
    <> "\t"
    <> artist
    <> "\t"
    <> track_url
    <> tid
    <> "\t"
    <> cover_url
    <> "\t"
    <> added_at
    <> "\t240000\t"
    <> aid
  }
  let tsv =
    row("TRACK1", "Hip Hop Hooray", "Naughty By Nature", "NBN123")
    <> "\n"
    <> row("TRACK2", "Limbo", "Igorrr", "IGR456")
  let pairs = spotify_live_expander.parse_track_items_with_artist_ids(tsv)
  assert list.length(pairs) == 2
  let assert [#(item1, artist_id_1), #(item2, artist_id_2)] = pairs
  assert item1.id == "spotify:item:TRACK1"
  assert artist_id_1 == "NBN123"
  assert item2.id == "spotify:item:TRACK2"
  assert artist_id_2 == "IGR456"
}

// ── Live test ─────────────────────────────────────────────────────────────────

pub fn live_spotify_user_follows_unified_depth_spec_test() {
  case test_env.run_live_tests() {
    False -> Nil
    True -> {
      let source = sources.spotify()
      let session = ".spotify_oauth_session.json"
      let client_id =
        spotify_credentials.read_env_value(".env", "SPOTIFY_CLIENT_ID")
      let client_secret =
        spotify_credentials.read_env_value(".env", "SPOTIFY_CLIENT_SECRET")
      assert client_id != ""
      assert client_secret != ""
      assert client_id != client_secret
      let access_token =
        spotify_credentials.read_access_token_file(session)
      case access_token == "" {
        True -> Nil
        False -> {
          let creds =
            api_keys.SpotifyCredentials(
              access_token: access_token,
              refresh_token: spotify_credentials.read_refresh_token_file(session),
              client_id: client_id,
              client_secret: client_secret,
              redirect_uri: "https://127.0.0.1:8080/spotify-oauth-success",
            )
          let config = spotify_live_expander.spotify_config(creds)
          let profile =
            spotify_live_expander.spotify_user(sources.entry_point(source))
          let results =
            depth_test_spec.resolve_standard_depths(fn(depth, cache_mode) {
              spotify_live_expander.resolve_profile(
                profile,
                depth,
                config,
                cache_mode,
              )
            })
          depth_test_spec.assert_standard_depth_pattern(
            results,
            sources.depth_assert_spec(source),
          )
        }
      }
    }
  }
}
