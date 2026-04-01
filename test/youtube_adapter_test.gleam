import adapters/cache
import adapters/core
import adapters/youtube/live_expander as youtube_live_expander
import cli/api_credentials
import gleam/list
import sources
import test_env

pub fn live_youtube_playlist_resolves_test() {
  case test_env.run_live_tests() {
    False -> Nil
    True -> {
      let source = sources.youtube()
      let profile =
        youtube_live_expander.youtube_playlist(sources.entry_point(source))
      let keys = api_credentials.load_api_keys()
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
