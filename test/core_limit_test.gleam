import adapters/core
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/time/timestamp
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn stops_accumulation_when_item_limit_is_reached_test() {
  let result =
    core.resolve_profile_url_with_debug_and_limit(
      "https://example.test/profile",
      core.All,
      4,
      fake_expand,
      fn(_) { Nil },
      fn(_) { Nil },
    )
  let core.ResolveResult(items, _, _) = result
  item_ids(items)
  |> should.equal([
    "demo:item:p1-1",
    "demo:item:p1-2",
    "demo:item:p1-3",
    "demo:item:p2-1",
  ])
}

fn fake_expand(node: core.AdapterNode) -> core.ExpandResult {
  case node {
    core.ProfileEntry(_) ->
      core.ExpandResult(
        items: make_items("p1", 3),
        lists: [],
        next_nodes: [core.PageNode("page-2")],
        unresolved: [],
        cache_hits: 0,
        cache_fetches: 0,
      )
    core.PageNode("page-2") ->
      core.ExpandResult(
        items: make_items("p2", 3),
        lists: [],
        next_nodes: [core.PageNode("page-3")],
        unresolved: [],
        cache_hits: 0,
        cache_fetches: 0,
      )
    core.PageNode("page-3") ->
      core.ExpandResult(
        items: make_items("p3", 3),
        lists: [],
        next_nodes: [],
        unresolved: [],
        cache_hits: 0,
        cache_fetches: 0,
      )
    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [],
        cache_hits: 0,
        cache_fetches: 0,
      )
  }
}

fn make_items(prefix: String, count: Int) -> List(core.UnifiedItem) {
  int.range(from: 1, to: count + 1, with: [], run: fn(acc, n) {
    list.append(acc, [n])
  })
  |> list.map(fn(index) {
    let suffix = int.to_string(index)
    let source_id = prefix <> "-" <> suffix
    core.UnifiedItem(
      id: "demo:item:" <> source_id,
      title: "Track " <> source_id,
      artist: "Artist",
      service: "demo",
      source_type: "item",
      source_id: source_id,
      external_source_url: None,
      file_path: None,
      added_at: timestamp.unix_epoch,
    )
  })
}

fn item_ids(items: List(core.UnifiedItem)) -> List(String) {
  list.map(items, fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _, _, _, _) = item
    id
  })
}
