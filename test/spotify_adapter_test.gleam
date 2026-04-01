import adapters/api_keys
import adapters/spotify/live_expander as spotify_live_expander
import cli/spotify_credentials
import depth_test_spec
import sources

@external(erlang, "test_runtime", "run_live_tests")
fn run_live_tests() -> Bool

pub fn live_spotify_user_follows_unified_depth_spec_test() {
  case run_live_tests() {
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
