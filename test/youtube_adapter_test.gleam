import adapters/youtube/live_expander as youtube_live_expander
import depth_test_spec
import sources

@external(erlang, "test_runtime", "run_live_tests")
fn run_live_tests() -> Bool

pub fn live_youtube_follows_unified_depth_spec_test() {
  case run_live_tests() {
    False -> Nil
    True -> {
      let source = sources.youtube()
      let profile =
        youtube_live_expander.youtube_playlist(sources.entry_point(source))
      let results =
        depth_test_spec.resolve_standard_depths(fn(depth, cache_mode) {
          youtube_live_expander.resolve_profile(profile, depth, cache_mode)
        })
      depth_test_spec.assert_standard_depth_pattern(
        results,
        sources.depth_assert_spec(source),
      )
    }
  }
}
