import gleam/list
import gleam/string
import adapters/core

pub type DepthResults {
  DepthResults(
    depth_1: core.ResolveResult,
    depth_2: core.ResolveResult,
    depth_3: core.ResolveResult,
    depth_10: core.ResolveResult,
    depth_20: core.ResolveResult,
    depth_all: core.ResolveResult,
  )
}

pub type DepthAssertSpec {
  DepthAssertSpec(
    min_depth_1_items: Int,
    min_full_items: Int,
    first_items_to_preserve: Int,
    anchor_fragments: List(String),
  )
}

pub fn resolve_standard_depths(
  resolve: fn(core.DepthMode) -> core.ResolveResult,
) -> DepthResults {
  DepthResults(
    depth_1: resolve(core.Depth1),
    depth_2: resolve(core.Depth2),
    depth_3: resolve(core.Depth3),
    depth_10: resolve(core.Depth10),
    depth_20: resolve(core.Depth20),
    depth_all: resolve(core.All),
  )
}

pub fn assert_standard_depth_pattern(results: DepthResults, spec: DepthAssertSpec) {
  let DepthAssertSpec(min_depth_1_items, min_full_items, first_items_to_preserve, anchor_fragments) =
    spec
  let DepthResults(d1, d2, d3, d10, d20, all) = results
  let #(i1, l1, u1) = counts(d1)
  let #(i2, _, _) = counts(d2)
  let #(i3, _, _) = counts(d3)
  let #(i10, l10, u10) = counts(d10)
  let #(i20, l20, u20) = counts(d20)
  let #(iall, lall, uall) = counts(all)

  assert i1 >= min_depth_1_items
  assert iall >= min_full_items

  // Transitivity over depth modes.
  assert i2 > i1
  assert i3 > i2
  assert i10 >= i3
  assert i20 > i10
  assert iall >= i20

  // Lists and unresolved should not regress at deeper levels.
  assert l10 >= l1
  assert l20 >= l10
  assert lall >= l20
  assert u10 == u1
  assert u20 == u10
  assert uall == u20

  // "First items" contract: early discovered ids stay present in full traversal.
  let first_ids = first_item_ids(d1, first_items_to_preserve)
  assert first_ids != []
  assert list.all(first_ids, fn(id) { has_item_id(all, id) })

  // Anchor fragments must be found in shallow depth (items_1 or items_2) and in full result.
  let items_1 = items(d1)
  let items_2 = items(d2)
  let items_all = items(all)
  list.each(anchor_fragments, fn(fragment) {
    assert has_title_fragment(items_1, fragment) || has_title_fragment(items_2, fragment)
    assert has_title_fragment(items_all, fragment)
  })
}

pub fn items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

pub fn has_title(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _) = item
    title == wanted
  })
}

pub fn has_title_fragment(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _) = item
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
      let core.UnifiedItem(id, _, _, _, _, _) = item
      id
    })
  ids
}

fn has_item_id(result: core.ResolveResult, wanted: String) -> Bool {
  result
  |> items
  |> list.any(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _) = item
    id == wanted
  })
}

fn string_contains(haystack: String, needle: String) -> Bool {
  // Keep helper local so callers can rely on this module only.
  string.contains(haystack, needle)
}
