import adapters/api_keys
import adapters/cache
import adapters/core
import adapters/youtube/live_expander as youtube_live_expander
import cli/spotify_credentials
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import sources
import test_env

pub fn live_youtube_playlist_resolves_test() {
  case test_env.run_live_tests() {
    False -> Nil
    True -> {
      let source = sources.youtube()
      let profile =
        youtube_live_expander.youtube_playlist(sources.entry_point(source))
      let keys =
        api_keys.ApiKeys(
          spotify: None,
          google_cloud: Some(
            spotify_credentials.read_env_value(
              ".env",
              "GOOGLE_CLOUD_API_KEY",
            )
            |> string.trim,
          ),
        )
      let assert Ok(core.ResolveResult(items, lists, unresolved)) =
        youtube_live_expander.resolve_profile(
          profile,
          core.All,
          cache.CacheUpsert,
          keys,
        )
      assert list.length(items) >= 5
      assert list.length(lists) == 1
      assert unresolved == []
    }
  }
}
