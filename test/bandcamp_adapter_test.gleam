import adapters/bandcamp/live_expander as bandcamp_live_expander
import depth_test_spec
import sources

@external(erlang, "test_runtime", "run_live_tests")
fn run_live_tests() -> Bool

pub fn live_bandcamp_follows_unified_depth_spec_test() {
  case run_live_tests() {
    False -> Nil
    True -> {
      let source = sources.bandcamp()
      let profile =
        bandcamp_live_expander.bandcamp_profile(sources.entry_point(source))
      let results =
        depth_test_spec.resolve_standard_depths(fn(depth, cache_mode) {
          bandcamp_live_expander.resolve_profile(profile, depth, cache_mode)
        })
      depth_test_spec.assert_standard_depth_pattern(
        results,
        sources.depth_assert_spec(source),
      )
    }
  }
}
