import adapters/api_keys
import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/youtube/live_expander as youtube_live_expander
import cli
import cli/api_credentials
import cli/runtime
import cli/spotify_credentials
import gleam/list
import gleam/string
import simplifile
import sources
import test_env

pub fn warm_cache_full_depth_under_one_second_per_source_test() {
  case test_env.run_live_perf_tests() {
    False -> Nil
    True -> {
      assert_source_under_one_second(fn() {
        let source = sources.bandcamp()
        let profile =
          bandcamp_live_expander.bandcamp_profile(sources.entry_point(source))
        bandcamp_live_expander.resolve_profile(
          profile,
          core.All,
          cache.CacheUpsert,
        )
      })

      assert_source_under_one_second(fn() {
        let source = sources.soundcloud()
        let profile =
          soundcloud_live_expander.soundcloud_profile(sources.entry_point(
            source,
          ))
        soundcloud_live_expander.resolve_profile(
          profile,
          core.All,
          cache.CacheUpsert,
        )
      })

      assert_source_under_one_second(fn() {
        let source = sources.spotify()
        let session = ".spotify_oauth_session.json"
        let access_token = spotify_credentials.read_access_token_file(session)
        assert access_token != ""
        let creds =
          api_keys.SpotifyCredentials(
            access_token: access_token,
            refresh_token: spotify_credentials.read_refresh_token_file(session),
            client_id: spotify_credentials.read_env_value(
              ".env",
              "SPOTIFY_CLIENT_ID",
            ),
            client_secret: spotify_credentials.read_env_value(
              ".env",
              "SPOTIFY_CLIENT_SECRET",
            ),
            redirect_uri: "https://127.0.0.1:8080/spotify-oauth-success",
          )
        let config = spotify_live_expander.spotify_config(creds)
        let profile =
          spotify_live_expander.spotify_user(sources.entry_point(source))
        spotify_live_expander.resolve_profile(
          profile,
          core.All,
          config,
          cache.CacheUpsert,
        )
      })

      assert_source_under_one_second(fn() {
        let source = sources.youtube()
        let profile =
          youtube_live_expander.youtube_playlist(sources.entry_point(source))
        let assert Ok(result) =
          youtube_live_expander.resolve_profile(
            profile,
            core.All,
            cache.CacheUpsert,
            api_credentials.load_api_keys(),
          )
        result
      })
    }
  }
}

pub fn export_all_csv_with_cache_under_one_second_test() {
  case test_env.run_live_perf_tests() {
    False -> Nil
    True -> {
      let _ = cli.run(["export", "all", "csv", "use-cache"])
      let warm_length = csv_line_count("output/all_items_latest.csv")
      let start = runtime.now_ms()
      let _ = cli.run(["export", "all", "csv", "use-cache"])
      let elapsed_ms = runtime.now_ms() - start
      let cached_length = csv_line_count("output/all_items_latest.csv")
      assert warm_length > 1
      assert cached_length == warm_length
      assert elapsed_ms <= 1000
    }
  }
}

fn assert_source_under_one_second(resolve_all: fn() -> core.ResolveResult) {
  let _ = resolve_all()
  let start = runtime.now_ms()
  let result = resolve_all()
  let elapsed_ms = runtime.now_ms() - start
  let core.ResolveResult(items, _, _) = result
  assert items != []
  assert elapsed_ms <= 1000
}

fn csv_line_count(path: String) -> Int {
  case simplifile.read(from: path) {
    Ok(content) -> list.length(string.split(content, "\n"))
    Error(_) -> 0
  }
}
