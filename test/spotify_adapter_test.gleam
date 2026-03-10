import adapters/spotify/live_expander as spotify_live_expander
import depth_test_spec

pub fn live_spotify_user_follows_unified_depth_spec_test() {
  let access_token = spotify_live_expander.read_access_token_file(".spotify_oauth_session.json")
  let config =
    spotify_live_expander.spotify_config(
      access_token: access_token,
      session_file: ".spotify_oauth_session.json",
      client_id: "your_spotify_client_id",
      redirect_uri: "http://127.0.0.1:8080/callback",
      scopes: "playlist-read-private playlist-read-collaborative",
    )
  let profile = spotify_live_expander.spotify_user("https://open.spotify.com/user/franzskuffka")
  let results =
    depth_test_spec.resolve_standard_depths(fn(depth) {
      spotify_live_expander.resolve_profile(profile, depth, config)
    })
  depth_test_spec.assert_standard_depth_pattern(
    results,
    depth_test_spec.DepthAssertSpec(
      min_depth_1_items: 50,
      min_full_items: 1000,
      first_items_to_preserve: 3,
      anchor_fragments: [
        "Blask",
        "SOLD MY SOUL",
      ],
    ),
  )
}
