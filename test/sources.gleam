import depth_test_spec

pub type SourceSpec {
  SourceSpec(
    entry_point: String,
    depth_assert_spec: depth_test_spec.DepthAssertSpec,
  )
}

pub fn entry_point(spec: SourceSpec) -> String {
  let SourceSpec(entry_point, _) = spec
  entry_point
}

pub fn depth_assert_spec(spec: SourceSpec) -> depth_test_spec.DepthAssertSpec {
  let SourceSpec(_, depth_assert_spec) = spec
  depth_assert_spec
}

pub fn bandcamp() -> SourceSpec {
  SourceSpec(
    entry_point: "https://bandcamp.com/janwirth",
    depth_assert_spec:
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

pub fn soundcloud() -> SourceSpec {
  SourceSpec(
    entry_point: "https://soundcloud.com/tungstenselects",
    depth_assert_spec:
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

pub fn spotify() -> SourceSpec {
  SourceSpec(
    entry_point: "https://open.spotify.com/user/franzskuffka",
    depth_assert_spec:
      depth_test_spec.DepthAssertSpec(
        min_depth_1_items: 50,
        min_full_items: 1000,
        first_items_to_preserve: 3,
        anchor_fragments: [
          "Blask",
          "SOLD MY SOUL",
        ],
      ),
  )
}

pub fn youtube() -> SourceSpec {
  SourceSpec(
    entry_point: "https://www.youtube.com/playlist?list=PLK7cxKkqBmwmpPoWznuEF-xEljswMRR3V",
    depth_assert_spec:
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
