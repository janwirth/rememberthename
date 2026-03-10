import adapters/bandcamp/live_expander as bandcamp_live_expander
import depth_test_spec
import sources

pub fn live_bandcamp_follows_unified_depth_spec_test() {
  let source = sources.bandcamp()
  let profile = bandcamp_live_expander.bandcamp_profile(sources.entry_point(source))
  let results =
    depth_test_spec.resolve_standard_depths(fn(depth) {
      bandcamp_live_expander.resolve_profile(profile, depth)
    })
  depth_test_spec.assert_standard_depth_pattern(
    results,
    sources.depth_assert_spec(source),
  )
}
