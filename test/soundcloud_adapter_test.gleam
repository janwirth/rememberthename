import adapters/soundcloud/live_expander as soundcloud_live_expander
import depth_test_spec
import sources

@external(erlang, "test_runtime", "run_live_tests")
fn run_live_tests() -> Bool

pub fn live_soundcloud_follows_unified_depth_spec_test() {
  case run_live_tests() {
    False -> Nil
    True -> {
      let source = sources.soundcloud()
      let payload =
        soundcloud_live_expander.fetch_likes_payload(sources.entry_point(source))
      assert payload != ""

      let profile =
        soundcloud_live_expander.soundcloud_profile(sources.entry_point(source))
      let results =
        depth_test_spec.resolve_standard_depths(fn(depth, cache_mode) {
          soundcloud_live_expander.resolve_profile(profile, depth, cache_mode)
        })

      depth_test_spec.assert_standard_depth_pattern(
        results,
        sources.depth_assert_spec(source),
      )
    }
  }
}
