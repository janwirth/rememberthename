//// Canonical integration source specs used by CLI, TUI, and validation runs.
////
//// This module is the single source of truth for implemented source fixtures.
//// Each `SourceSpec` defines:
//// - a stable entry point URL
//// - a per-source output cap (`source_limit`)
//// - provider timing policy for `DepthAll` queue traversal
//// - depth assertions used by tests and `validate_all`
////
//// Assertion semantics:
//// - `min_depth_1_items`: lower bound for shallow resolution
//// - `min_full_items`: lower bound for full traversal
//// - `source_limit`: max items allowed in validated/exported full output, this is useful if you don't want to accidentally download the whole internet
//// - `first_items_to_preserve`: early discovered ids that must survive deeper traversal
//// - `anchor_fragments`: title fragments that should appear in shallow/deep outputs
//// - `required_full_fragments`: title fragments that must appear in full output

pub type SourceAssertSpec {
  SourceAssertSpec(
    min_depth_1_items: Int,
    min_full_items: Int,
    source_limit: Int,
    first_items_to_preserve: Int,
    anchor_fragments: List(String),
    required_full_fragments: List(String),
  )
}

pub type SourceTimingSpec {
  SourceTimingSpec(max_concurrency: Int, requests_per_second: Int)
}

pub type SourceSpec {
  SourceSpec(
    key: String,
    name: String,
    entry_point: String,
    timing_spec: SourceTimingSpec,
    assert_spec: SourceAssertSpec,
  )
}

pub fn all() -> List(SourceSpec) {
  [bandcamp(), soundcloud(), spotify(), youtube(), tuna()]
}

pub fn bandcamp() -> SourceSpec {
  SourceSpec(
    key: "bandcamp",
    name: "Bandcamp",
    entry_point: "https://bandcamp.com/janwirth",
    timing_spec: SourceTimingSpec(max_concurrency: 5, requests_per_second: 5),
    assert_spec: SourceAssertSpec(
      min_depth_1_items: 1,
      min_full_items: 700,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Stable fixture anchors from live Bandcamp profile traversal.
      anchor_fragments: ["Spore Spreader"],
      required_full_fragments: [
        "Badlands",
        "Dimebag",
        "Redshift 7",
        "World, Hold On",
        "Buttercup",
        "Ghost Radio",
        "Acid House",
      ],
    ),
  )
}

pub fn soundcloud() -> SourceSpec {
  SourceSpec(
    key: "soundcloud",
    name: "Soundcloud",
    entry_point: "https://soundcloud.com/tungstenselects",
    timing_spec: SourceTimingSpec(max_concurrency: 3, requests_per_second: 3),
    assert_spec: SourceAssertSpec(
      min_depth_1_items: 10,
      min_full_items: 1000,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Stable fixture anchors from likes/reposts category traversal.
      anchor_fragments: [
        "A Horse with no Name (Edit)",
        "Nyxtape: Vol.12 - Harley D",
        "PREMIERE| Rebecca Delle Piane - Genomica [FIDESX4]",
        "Premiere: KAIPE - Batie",
      ],
      required_full_fragments: [],
    ),
  )
}

pub fn spotify() -> SourceSpec {
  SourceSpec(
    key: "spotify",
    name: "Spotify",
    entry_point: "https://open.spotify.com/user/franzskuffka",
    timing_spec: SourceTimingSpec(max_concurrency: 3, requests_per_second: 3),
    assert_spec: SourceAssertSpec(
      min_depth_1_items: 50,
      min_full_items: 1000,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Liked tracks fixture anchors from Spotify authenticated traversal.
      anchor_fragments: ["Blask", "SOLD MY SOUL"],
      required_full_fragments: [],
    ),
  )
}

pub fn youtube() -> SourceSpec {
  SourceSpec(
    key: "youtube",
    name: "Youtube",
    entry_point: "https://www.youtube.com/playlist?list=PLK7cxKkqBmwmpPoWznuEF-xEljswMRR3V",
    timing_spec: SourceTimingSpec(max_concurrency: 3, requests_per_second: 3),
    assert_spec: SourceAssertSpec(
      min_depth_1_items: 5,
      min_full_items: 1000,
      source_limit: 4000,
      first_items_to_preserve: 3,
      // Ordered playlist prefix fragments from reference YouTube fixture.
      anchor_fragments: [
        "Angine de poitrine - Sahardnieh",
        "Nimo - BITTER",
        "Vengaboys - Up & Down",
        "Dendemann - Wo ich wech bin",
        "BHZ - SCHLIESSE DIE AUGEN",
      ],
      // Full traversal includes titles with case-varying "chanel" substring.
      required_full_fragments: ["chanel"],
    ),
  )
}

pub fn tuna() -> SourceSpec {
  SourceSpec(
    key: "tuna",
    name: "Tuna",
    entry_point: "gel:tuna/main::default::Track",
    timing_spec: SourceTimingSpec(max_concurrency: 1, requests_per_second: 1),
    assert_spec: SourceAssertSpec(
      min_depth_1_items: 0,
      min_full_items: 10,
      source_limit: 100000,
      first_items_to_preserve: 0,
      anchor_fragments: [],
      required_full_fragments: [],
    ),
  )
}
