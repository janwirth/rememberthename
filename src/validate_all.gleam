import adapters/cache
import adapters/core
import cli/source_resolve
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import source_root
import source_specs

pub fn main() {
  let specs = source_specs.all()
  let #(total, failed) = validate_sources(specs, 1, 0, 0)
  io.println("")
  io.println(
    "Validation summary: total="
    <> int.to_string(total)
    <> " failed="
    <> int.to_string(failed),
  )
  case failed > 0 {
    True -> panic as "validate_all failed"
    False -> io.println("All sources PASS.")
  }
}

fn validate_sources(
  rows: List(#(String, source_root.SourceRoot, source_root.SourceAssertSpec)),
  index: Int,
  total: Int,
  failed: Int,
) -> #(Int, Int) {
  case rows {
    [] -> #(total, failed)
    [row, ..rest] -> {
      let pass = validate_source(row, index)
      validate_sources(rest, index + 1, total + 1, case pass {
        True -> failed
        False -> failed + 1
      })
    }
  }
}

fn validate_source(
  row: #(String, source_root.SourceRoot, source_root.SourceAssertSpec),
  index: Int,
) -> Bool {
  let #(title, root, assert_spec) = row
  let key = source_root.source_key(root)
  let entry_point = source_root.listing_entry_point(root)
  let cache_mode = cache.CacheUpsert
  let source_root.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
  io.println("")
  io.println(
    "== [" <> int.to_string(index) <> "] " <> title <> " (" <> key <> ") ==",
  )
  io.println("entry: " <> entry_point)
  io.println("cache: " <> cache_mode_text(cache_mode))

  // Warm-up full traversal before measured runs, matching migration test strategy.
  let _ =
    source_resolve.resolve_limited(
      root,
      core.All,
      source_limit,
      cache_mode,
      fn(line) { io.println("[warmup] " <> line) },
    )

  let depth_1 =
    source_resolve.resolve_limited(
      root,
      core.Depth1,
      source_limit,
      cache_mode,
      fn(_line) { Nil },
    )
  let depth_2 =
    source_resolve.resolve_limited(
      root,
      core.Depth2,
      source_limit,
      cache_mode,
      fn(_line) { Nil },
    )
  let depth_all =
    source_resolve.resolve_limited(
      root,
      core.All,
      source_limit,
      cache_mode,
      fn(line) { io.println("[full] " <> line) },
    )

  let pass =
    validate_results(
      key,
      title,
      source_limit,
      assert_spec,
      depth_1,
      depth_2,
      depth_all,
    )
  io.println(case pass {
    True -> "Result: PASS"
    False -> "Result: FAIL"
  })
  pass
}

fn validate_results(
  key: String,
  name: String,
  source_limit: Int,
  assert_spec: source_root.SourceAssertSpec,
  d1: core.ResolveResult,
  d2: core.ResolveResult,
  all: core.ResolveResult,
) -> Bool {
  let source_root.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    _source_limit,
    first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = assert_spec

  let #(i1, l1, u1) = counts(d1)
  let #(i2, _, _) = counts(d2)
  let #(iall, lall, uall) = counts(all)
  let items_1 = result_items(d1)
  let items_2 = result_items(d2)
  let items_all = result_items(all)

  let min_depth_ok = i1 >= min_depth_1_items
  let min_full_ok = iall >= min_full_items
  let monotonic_ok = case key == "tuna" {
    True -> True
    False -> i2 >= i1 && iall >= i2
  }
  let consistency_ok = lall >= l1 && uall == u1
  let first_ids = first_item_ids(d1, first_items_to_preserve)
  let first_items_ok =
    first_ids != [] && list.all(first_ids, fn(id) { has_item_id(all, id) })
  let anchors_shallow_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_1, fragment)
      || has_title_fragment(items_2, fragment)
    })
  let anchors_full_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_all, fragment)
    })
  let required_full_ok =
    list.all(required_full_fragments, fn(fragment) {
      has_title_fragment_ci(items_all, fragment)
    })
  let source_limit_ok = iall <= source_limit

  io.println(name <> " checks:")
  io.println(check(min_depth_ok) <> " min depth-1 items")
  io.println(check(min_full_ok) <> " min full items")
  io.println(check(monotonic_ok) <> " depth monotonicity")
  io.println(check(consistency_ok) <> " list/unresolved consistency")
  io.println(check(first_items_ok) <> " first items preserved")
  io.println(
    check(anchors_shallow_ok && anchors_full_ok) <> " anchor fragments present",
  )
  io.println(check(required_full_ok) <> " required full fragments present")
  io.println(
    check(source_limit_ok) <> " source limit <= " <> int.to_string(source_limit),
  )

  min_depth_ok
  && min_full_ok
  && monotonic_ok
  && consistency_ok
  && first_items_ok
  && anchors_shallow_ok
  && anchors_full_ok
  && required_full_ok
  && source_limit_ok
}

fn counts(result: core.ResolveResult) -> #(Int, Int, Int) {
  let core.ResolveResult(items, lists, unresolved) = result
  #(list.length(items), list.length(lists), list.length(unresolved))
}

fn result_items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

fn first_item_ids(result: core.ResolveResult, count: Int) -> List(String) {
  result
  |> result_items
  |> list.take(count)
  |> list.map(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _, _, _) = item
    id
  })
}

fn has_item_id(result: core.ResolveResult, wanted: String) -> Bool {
  result
  |> result_items
  |> list.any(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _, _, _) = item
    id == wanted
  })
}

fn has_title_fragment(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _) = item
    string.contains(title, wanted)
  })
}

fn has_title_fragment_ci(items: List(core.UnifiedItem), wanted: String) -> Bool {
  let wanted_lc = string.lowercase(wanted)
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _) = item
    string.contains(string.lowercase(title), wanted_lc)
  })
}

fn check(ok: Bool) -> String {
  case ok {
    True -> "[x]"
    False -> "[ ]"
  }
}

fn cache_mode_text(value: cache.CacheMode) -> String {
  case value {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
    cache.CacheReadOnly -> "readonly"
  }
}
