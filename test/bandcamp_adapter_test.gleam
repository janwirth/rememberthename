import adapters/bandcamp/live_expander as bandcamp_live_expander
import depth_test_spec

pub fn live_bandcamp_follows_unified_depth_spec_test() {
  let profile = bandcamp_live_expander.bandcamp_profile("https://bandcamp.com/janwirth")
  let results =
    depth_test_spec.resolve_standard_depths(fn(depth) {
      bandcamp_live_expander.resolve_profile(profile, depth)
    })
  depth_test_spec.assert_standard_depth_pattern(
    results,
    depth_test_spec.DepthAssertSpec(
      min_depth_1_items: 1,
      min_full_items: 700,
      first_items_to_preserve: 3,
      anchor_fragments: [
        "PUT THE NEEDLE ON THE RECORD",
        "Look Alive",
        "Manifest Content",
      ],
    ),
  )
}
