import adapters/spotify/live_expander as spotify_live_expander
import adapters/core
import depth_test_spec

pub fn spotify_oauth_authorization_view_test() {
  // This is the only test that should trigger OAuth browser flow.
  let client_id = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_ID")
  let client_secret = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_SECRET")
  assert client_id != ""
  assert client_secret != ""
  // Guard against common misconfiguration where both vars are the same.
  assert client_id != client_secret
  let config =
    spotify_live_expander.spotify_config(
      access_token: "",
      session_file: ".spotify_oauth_bootstrap.json",
      client_id: client_id,
      redirect_uri: "http://127.0.0.1:8080/callback",
      scopes: "playlist-read-private playlist-read-collaborative",
    )
  let profile = spotify_live_expander.spotify_user("https://open.spotify.com/user/franzskuffka")
  let result = spotify_live_expander.resolve_profile(profile, core.Depth1, config)
  let core.ResolveResult(_, _, unresolved) = result
  assert unresolved != []
}

pub fn live_spotify_user_follows_unified_depth_spec_test() {
  let client_id = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_ID")
  let client_secret = spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_SECRET")
  assert client_id != ""
  assert client_secret != ""
  assert client_id != client_secret
  let access_token = spotify_live_expander.read_access_token_file(".spotify_oauth_session.json")
  assert access_token != ""
  let config =
    spotify_live_expander.spotify_config(
      access_token: access_token,
      session_file: ".spotify_oauth_session.json",
      client_id: client_id,
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
