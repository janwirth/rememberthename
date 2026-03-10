import adapters/youtube/live_expander as youtube_live_expander
import depth_test_spec
import sources

pub fn live_youtube_follows_unified_depth_spec_test() {
  let source = sources.youtube()
  let profile =
    youtube_live_expander.youtube_playlist(
      sources.entry_point(source),
    )
  let results =
    depth_test_spec.resolve_standard_depths(fn(depth) {
      youtube_live_expander.resolve_profile(profile, depth)
    })
  depth_test_spec.assert_standard_depth_pattern(
    results,
    sources.depth_assert_spec(source),
  )
}
