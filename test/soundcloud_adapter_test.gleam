import adapters/soundcloud/live_expander as soundcloud_live_expander
import depth_test_spec

pub fn live_soundcloud_follows_unified_depth_spec_test() {
  let payload = soundcloud_live_expander.fetch_likes_payload("https://soundcloud.com/tungstenselects")
  assert payload != ""

  let profile = soundcloud_live_expander.soundcloud_profile("https://soundcloud.com/tungstenselects")
  let results =
    depth_test_spec.resolve_standard_depths(fn(depth) {
      soundcloud_live_expander.resolve_profile(profile, depth)
    })

  depth_test_spec.assert_standard_depth_pattern(
    results,
    depth_test_spec.DepthAssertSpec(
      min_depth_1_items: 10,
      min_full_items: 1000,
      first_items_to_preserve: 3,
      anchor_fragments: [
        "A Horse with no Name (Edit)",
        "Nyxtape: Vol.12 - Harley D",
        "PREMIERE| Rebecca Delle Piane - Genomica [FIDESX4]",
        "Premiere: KAIPE - Batie",
      ],
    ),
  )
}

