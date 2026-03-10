import depth_test_spec
import source_specs as canonical_sources

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
  from_canonical(canonical_sources.bandcamp())
}

pub fn soundcloud() -> SourceSpec {
  from_canonical(canonical_sources.soundcloud())
}

pub fn spotify() -> SourceSpec {
  from_canonical(canonical_sources.spotify())
}

pub fn youtube() -> SourceSpec {
  from_canonical(canonical_sources.youtube())
}

fn from_canonical(spec: canonical_sources.SourceSpec) -> SourceSpec {
  let canonical_sources.SourceSpec(_, _, entry_point, assert_spec) = spec
  SourceSpec(entry_point, to_depth_assert_spec(assert_spec))
}

fn to_depth_assert_spec(
  assert_spec: canonical_sources.SourceAssertSpec,
) -> depth_test_spec.DepthAssertSpec {
  let canonical_sources.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = assert_spec
  depth_test_spec.DepthAssertSpec(
    min_depth_1_items: min_depth_1_items,
    min_full_items: min_full_items,
    first_items_to_preserve: first_items_to_preserve,
    anchor_fragments: anchor_fragments,
    required_full_fragments: required_full_fragments,
  )
}
