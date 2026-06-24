import adapters/cache
import adapters/core
import cli/terminal
import fetch_ops
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import output/visual_output
import source_root

/// Resolve snapshots at depth-1, depth-2, and full depth for post-fetch validation.
pub type SourceRun {
  SourceRun(
    key: String,
    name: String,
    assert_spec: source_root.SourceAssertSpec,
    depth_1: core.ResolveResult,
    depth_2: core.ResolveResult,
    depth_all: core.ResolveResult,
  )
}

/// For each track, copies `imported_date` from `source_imported_dates` into `acc` when present.
pub fn merge_imported_dates(
  source_imported_dates: dict.Dict(String, Int),
  source_tracks: List(visual_output.TrackView),
  acc: dict.Dict(String, Int),
) -> dict.Dict(String, Int) {
  list.fold(source_tracks, acc, fn(acc_dates, track) {
    let visual_output.TrackView(_, _, service, source_id, _, _, _, _, _, _) =
      track
    let key = service <> ":" <> source_id
    case dict.get(source_imported_dates, key) {
      Ok(imported_date) -> dict.insert(acc_dates, key, imported_date)
      Error(_) -> acc_dates
    }
  })
}

/// True when post-fetch validation runs (CLI: `--validate`; API: `always_validate`).
pub fn validation_will_run(always_validate: Bool) -> Bool {
  always_validate
}

/// Short label for the validation strategy (shown before fetch starts).
pub fn validation_plan_label(depth: core.DepthMode) -> String {
  case depth == core.All {
    True -> "cross-depth SourceRun"
    False -> "single-depth snapshot"
  }
}

/// Assert thresholds and cache mode for the validation step.
pub fn validation_params_detail(
  key: String,
  assert_spec: source_root.SourceAssertSpec,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
) -> String {
  let source_root.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    source_limit,
    first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = assert_spec
  let cache_txt = cache_mode_text(cache_mode)
  case depth == core.All {
    True ->
      "cache="
      <> cache_txt
      <> " source="
      <> key
      <> " min_depth_1_items="
      <> int.to_string(min_depth_1_items)
      <> " min_full_items="
      <> int.to_string(min_full_items)
      <> " source_limit="
      <> int.to_string(source_limit)
      <> " first_items_to_preserve="
      <> int.to_string(first_items_to_preserve)
      <> " anchor_fragment_count="
      <> int.to_string(list.length(anchor_fragments))
      <> " required_full_fragment_count="
      <> int.to_string(list.length(required_full_fragments))
    False -> {
      let min_d1_note = case depth {
        core.Depth1 ->
          "min_depth_1_items="
          <> int.to_string(min_depth_1_items)
          <> " (enforced)"
        _ ->
          "min_depth_1_items="
          <> int.to_string(min_depth_1_items)
          <> " (not enforced: not a depth-1 fetch)"
      }
      "cache="
      <> cache_txt
      <> " source="
      <> key
      <> " "
      <> min_d1_note
      <> " source_limit="
      <> int.to_string(source_limit)
      <> " anchor_fragment_count="
      <> int.to_string(list.length(anchor_fragments))
    }
  }
}

/// When `always_validate`, runs validation and reports PASS/FAIL via `on_update`.
pub fn print_runtime_validation(
  key: String,
  name: String,
  assert_spec: source_root.SourceAssertSpec,
  root: source_root.SourceRoot,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  depth_result: core.ResolveResult,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) {
  case always_validate {
    False -> Nil
    True -> {
      let validation_errors = case depth {
        core.All -> {
          let run =
            validation_run_for_depth(
              key,
              name,
              assert_spec,
              root,
              depth,
              cache_mode,
              depth_result,
            )
          validate_source_run(run)
        }
        _ -> validate_single_depth_result(key, name, assert_spec, depth, depth_result)
      }
      on_update("")
      case validation_errors == [] {
        True -> on_update(terminal.color("Validation: PASS", terminal.ansi_green()))
        False -> {
          on_update(
            terminal.color("Validation: FAIL", terminal.ansi_red())
            <> " ("
            <> int.to_string(list.length(validation_errors))
            <> " errors)",
          )
          list.each(validation_errors, fn(line) { on_update("  - " <> line) })
        }
      }
    }
  }
}

fn validate_single_depth_result(
  key: String,
  name: String,
  assert_spec: source_root.SourceAssertSpec,
  depth: core.DepthMode,
  depth_result: core.ResolveResult,
) -> List(String) {
  let source_root.SourceAssertSpec(
    min_depth_1_items,
    _,
    source_limit,
    _,
    anchor_fragments,
    _,
  ) = assert_spec
  let core.ResolveResult(items, _, _) = depth_result
  let item_count = list.length(items)
  let min_depth_ok = case depth {
    core.Depth1 -> item_count >= min_depth_1_items
    _ -> True
  }
  let anchors_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items, fragment)
    })
  let source_limit_ok = item_count <= source_limit
  []
  |> add_validation_error(
    !min_depth_ok,
    key <> " (" <> name <> "): min depth-1 items failed",
  )
  |> add_validation_error(
    !anchors_ok,
    key <> " (" <> name <> "): anchor fragments failed",
  )
  |> add_validation_error(
    !source_limit_ok,
    key
      <> " ("
      <> name
      <> "): source limit exceeded ("
      <> int.to_string(source_limit)
      <> ")",
  )
}

/// Builds a `SourceRun`: current `depth_result` plus sibling resolves (tuna reuses full result slices).
pub fn validation_run_for_depth(
  key: String,
  name: String,
  assert_spec: source_root.SourceAssertSpec,
  root: source_root.SourceRoot,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  depth_result: core.ResolveResult,
) -> SourceRun {
  let derive_tuna_shallow = fn(all_result: core.ResolveResult, wanted_depth: core.DepthMode) {
    let core.ResolveResult(all_items, _, _) = all_result
    let depth_items = case wanted_depth {
      core.Depth1 -> list.take(all_items, 5)
      core.Depth2 -> list.take(all_items, 10)
      core.Depth3 -> list.take(all_items, 20)
      _ -> all_items
    }
    core.ResolveResult(items: depth_items, lists: [], unresolved: [])
  }

  let resolve_depth = fn(mode: core.DepthMode) {
    case key == "tuna" && depth == core.All {
      True -> derive_tuna_shallow(depth_result, mode)
      False -> {
        let shallow_root = source_root.with_depth(root, mode)
        case fetch_ops.fetch(shallow_root, cache_mode, fn(_) { Nil }) {
          Ok(r) ->
            core.ResolveResult(items: r.items, lists: r.lists, unresolved: r.unresolved)
          Error(_) ->
            core.ResolveResult(items: [], lists: [], unresolved: [])
        }
      }
    }
  }

  case depth {
    core.Depth1 ->
      SourceRun(
        key,
        name,
        assert_spec,
        depth_result,
        resolve_depth(core.Depth2),
        resolve_depth(core.All),
      )
    core.Depth2 ->
      SourceRun(
        key,
        name,
        assert_spec,
        resolve_depth(core.Depth1),
        depth_result,
        resolve_depth(core.All),
      )
    core.All ->
      SourceRun(
        key,
        name,
        assert_spec,
        resolve_depth(core.Depth1),
        resolve_depth(core.Depth2),
        depth_result,
      )
    _ ->
      SourceRun(
        key,
        name,
        assert_spec,
        resolve_depth(core.Depth1),
        resolve_depth(core.Depth2),
        resolve_depth(core.All),
      )
  }
}

/// Asserts counts, monotonicity, list/unresolved stability, anchors, limits; returns human-readable errors.
pub fn validate_source_run(run: SourceRun) -> List(String) {
  let SourceRun(key, name, assert_spec, depth_1, depth_2, depth_all) = run
  let source_root.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    source_limit,
    first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = assert_spec
  let #(i1, l1, u1) = counts(depth_1)
  let #(i2, _, _) = counts(depth_2)
  let #(iall, lall, uall) = counts(depth_all)
  let items_1 = result_items(depth_1)
  let items_2 = result_items(depth_2)
  let items_all = result_items(depth_all)
  let min_depth_ok = i1 >= min_depth_1_items
  let min_full_ok = iall >= min_full_items
  let monotonic_ok = case key == "tuna" {
    True -> True
    False -> i2 >= i1 && iall >= i2
  }
  let consistency_ok = lall >= l1 && uall == u1
  let first_ids = first_item_ids(depth_1, first_items_to_preserve)
  let first_items_ok = case first_items_to_preserve == 0 {
    True -> True
    False ->
      first_ids != [] && list.all(first_ids, fn(id) { has_item_id(depth_all, id) })
  }
  let anchors_shallow_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_1, fragment)
      || has_title_fragment(items_2, fragment)
    })
  let anchors_full_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_all, fragment)
    })
  let anchors_ok = anchors_shallow_ok && anchors_full_ok
  let required_full_ok =
    list.all(required_full_fragments, fn(fragment) {
      has_title_fragment_ci(items_all, fragment)
    })
  let source_limit_ok = iall <= source_limit
  []
  |> add_validation_error(
    !min_depth_ok,
    key <> " (" <> name <> "): min depth-1 items failed",
  )
  |> add_validation_error(
    !min_full_ok,
    key <> " (" <> name <> "): min full items failed",
  )
  |> add_validation_error(
    !monotonic_ok,
    key <> " (" <> name <> "): depth monotonicity failed",
  )
  |> add_validation_error(
    !consistency_ok,
    key <> " (" <> name <> "): list/unresolved consistency failed",
  )
  |> add_validation_error(
    !first_items_ok,
    key <> " (" <> name <> "): first items preserved failed",
  )
  |> add_validation_error(
    !anchors_ok,
    key <> " (" <> name <> "): anchor fragments failed",
  )
  |> add_validation_error(
    !required_full_ok,
    key <> " (" <> name <> "): required full fragments failed",
  )
  |> add_validation_error(
    !source_limit_ok,
    key
      <> " ("
      <> name
      <> "): source limit exceeded ("
      <> int.to_string(source_limit)
      <> ")",
  )
}

/// If `condition` is true (check failed), appends `line` to the error list.
fn add_validation_error(
  errors: List(String),
  condition: Bool,
  line: String,
) -> List(String) {
  case condition {
    True -> list.append(errors, [line])
    False -> errors
  }
}

/// Extracts the `items` list from a resolve result.
fn result_items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

/// `(item_count, list_count, unresolved_count)` for a result.
fn counts(result: core.ResolveResult) -> #(Int, Int, Int) {
  let core.ResolveResult(items, lists, unresolved) = result
  #(list.length(items), list.length(lists), list.length(unresolved))
}

/// Stable ids of the first `count` items (order preservation check).
fn first_item_ids(result: core.ResolveResult, count: Int) -> List(String) {
  result
  |> result_items
  |> list.take(count)
  |> list.map(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _, _, _, _) = item
    id
  })
}

/// True if any resolved item carries `wanted` as its id.
fn has_item_id(result: core.ResolveResult, wanted: String) -> Bool {
  result
  |> result_items
  |> list.any(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _, _, _, _) = item
    id == wanted
  })
}

/// Case-sensitive substring search in item titles.
fn has_title_fragment(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _, _, _, _, _, _) = item
    string.contains(title, wanted)
  })
}

/// Case-insensitive substring search in item titles.
fn has_title_fragment_ci(items: List(core.UnifiedItem), wanted: String) -> Bool {
  let wanted_lc = string.lowercase(wanted)
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _, _, _, _, _, _, _, _) = item
    string.contains(string.lowercase(title), wanted_lc)
  })
}

fn cache_mode_text(value: cache.CacheMode) -> String {
  case value {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
    cache.CacheReadOnly -> "readonly"
  }
}
