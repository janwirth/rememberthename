import adapters/cache
import adapters/core
import gleam/list
import gleam/string

pub type DepthResults {
  DepthResults(depth_1: core.ResolveResult, depth_all: core.ResolveResult)
}

pub type DepthAssertSpec {
  DepthAssertSpec(
    min_depth_1_items: Int,
    min_full_items: Int,
    first_items_to_preserve: Int,
    anchor_fragments: List(String),
    required_full_fragments: List(String),
  )
}

pub fn resolve_standard_depths(
  resolve: fn(core.DepthMode, cache.CacheMode) -> core.ResolveResult,
) -> DepthResults {
  DepthResults(
    depth_1: resolve(core.Depth1, cache.CacheUpsert),
    depth_all: resolve(core.All, cache.CacheUpsert),
  )
}

pub fn assert_standard_depth_pattern(
  results: DepthResults,
  spec: DepthAssertSpec,
) {
  let DepthAssertSpec(
    min_depth_1_items,
    min_full_items,
    first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = spec
  let DepthResults(d1, all) = results
  let #(i1, l1, u1) = counts(d1)
  let #(iall, lall, uall) = counts(all)

  assert i1 >= min_depth_1_items
  assert iall >= min_full_items

  // Full traversal should include at least shallow traversal content.
  assert iall >= i1

  // Lists and unresolved should not regress at deeper levels.
  assert lall >= l1
  assert uall == u1

  // "First items" contract: early discovered ids stay present in full traversal.
  let first_ids = first_item_ids(d1, first_items_to_preserve)
  assert first_ids != []
  assert list.all(first_ids, fn(id) { has_item_id(all, id) })

  // Anchor fragments must be found in shallow depth and in full result.
  let items_1 = items(d1)
  let items_all = items(all)
  list.each(anchor_fragments, fn(fragment) {
    assert has_title_fragment(items_1, fragment)
    assert has_title_fragment(items_all, fragment)
  })

  // Optional extra full-result expectations should come from source specs.
  list.each(required_full_fragments, fn(fragment) {
    assert has_title_fragment_ci(items_all, fragment)
  })
}

pub fn items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

pub fn has_title(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _, _, _, _, _) = item
    title == wanted
  })
}

pub fn has_title_fragment(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _, _, _, _, _) = item
    string_contains(title, wanted)
  })
}

fn counts(result: core.ResolveResult) -> #(Int, Int, Int) {
  let core.ResolveResult(items, lists, unresolved) = result
  #(list.length(items), list.length(lists), list.length(unresolved))
}

fn first_item_ids(result: core.ResolveResult, count: Int) -> List(String) {
  let ids =
    result
    |> items
    |> list.take(count)
    |> list.map(fn(item) {
      let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _, _, _) = item
      id
    })
  ids
}

fn has_item_id(result: core.ResolveResult, wanted: String) -> Bool {
  result
  |> items
  |> list.any(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _, _, _) = item
    id == wanted
  })
}

fn string_contains(haystack: String, needle: String) -> Bool {
  // Keep helper local so callers can rely on this module only.
  string.contains(haystack, needle)
}

fn has_title_fragment_ci(items: List(core.UnifiedItem), wanted: String) -> Bool {
  let wanted_lc = string.lowercase(wanted)
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _, _, _, _, _) = item
    string.contains(string.lowercase(title), wanted_lc)
  })
}
