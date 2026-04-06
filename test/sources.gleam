import adapters/cache
import depth_test_spec
import source_root
import source_specs as canonical_rows

pub type SourceSpec {
  SourceSpec(
    entry_point: String,
    use_cache: cache.CacheMode,
    depth_assert_spec: depth_test_spec.DepthAssertSpec,
  )
}

pub fn entry_point(spec: SourceSpec) -> String {
  let SourceSpec(entry_point, _, _) = spec
  entry_point
}

pub fn use_cache(spec: SourceSpec) -> cache.CacheMode {
  let SourceSpec(_, use_cache, _) = spec
  use_cache
}

pub fn depth_assert_spec(spec: SourceSpec) -> depth_test_spec.DepthAssertSpec {
  let SourceSpec(_, _, depth_assert_spec) = spec
  depth_assert_spec
}

pub fn bandcamp() -> SourceSpec {
  from_canonical(canonical_rows.bandcamp())
}

pub fn soundcloud() -> SourceSpec {
  from_canonical(canonical_rows.soundcloud())
}

pub fn spotify() -> SourceSpec {
  from_canonical(canonical_rows.spotify())
}

pub fn youtube() -> SourceSpec {
  from_canonical(canonical_rows.youtube())
}

fn from_canonical(
  row: #(String, source_root.CatalogRoot, source_root.SourceAssertSpec),
) -> SourceSpec {
  let #(_, catalog, assert_spec) = row
  SourceSpec(
    source_root.catalog_entry_point(catalog),
    cache.CacheUpsert,
    to_depth_assert_spec(assert_spec),
  )
}

fn to_depth_assert_spec(
  assert_spec: source_root.SourceAssertSpec,
) -> depth_test_spec.DepthAssertSpec {
  let source_root.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    _,
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
