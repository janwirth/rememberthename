import adapters/youtube/live_expander as youtube_live_expander
import depth_test_spec

pub fn live_youtube_follows_unified_depth_spec_test() {
  let profile =
    youtube_live_expander.youtube_playlist(
      "https://www.youtube.com/playlist?list=PLK7cxKkqBmwmpPoWznuEF-xEljswMRR3V",
    )
  let results =
    depth_test_spec.resolve_standard_depths(fn(depth) {
      youtube_live_expander.resolve_profile(profile, depth)
    })
  depth_test_spec.assert_standard_depth_pattern(
    results,
    depth_test_spec.DepthAssertSpec(
      min_depth_1_items: 5,
      min_full_items: 1000,
      first_items_to_preserve: 3,
      anchor_fragments: [
        "Angine de poitrine - Sahardnieh",
        "Nimo - BITTER",
        "Vengaboys - Up & Down",
        "Dendemann - Wo ich wech bin",
        "BHZ - SCHLIESSE DIE AUGEN",
      ],
    ),
  )
}
