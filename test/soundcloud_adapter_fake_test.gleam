import gleam/int
import gleam/list
import adapters/core

pub fn depth_1_stops_after_profile_test() {
  let result = core.resolve_profile_url("https://soundcloud.com/demo", core.Depth1, fake_expand)
  let core.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 10
  assert contains_item_id(items, "d1-track-01")
  assert list_ids(lists) == ["profile-root"]
  assert unresolved == []
}

pub fn depth_2_expands_one_more_hop_test() {
  let result = core.resolve_profile_url("https://soundcloud.com/demo", core.Depth2, fake_expand)
  let core.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 30
  assert contains_item_id(items, "d2b-track-10")
  assert list_ids(lists) == ["profile-root", "list-b", "list-a"]
  assert unresolved == [core.ListNode("list-missing")]
}

pub fn depth_3_recurses_lists_categories_and_pages_test() {
  let result = core.resolve_profile_url("https://soundcloud.com/demo", core.Depth3, fake_expand)
  let core.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 30
  assert contains_item_id(items, "track-c")
  assert list_ids(lists) == ["profile-root", "list-b", "list-a", "list-c"]
  assert unresolved == [core.ListNode("list-missing")]
}

pub fn all_depth_matches_depth_3_for_fixture_test() {
  let result = core.resolve_profile_url("https://soundcloud.com/demo", core.All, fake_expand)
  let core.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 30
  assert contains_item_id(items, "track-c")
  assert list_ids(lists) == ["profile-root", "list-b", "list-a", "list-c"]
  assert unresolved == [core.ListNode("list-missing")]
}

fn fake_expand(node: core.AdapterNode) -> core.ExpandResult {
  case node {
    core.ProfileEntry(_) ->
      core.ExpandResult(
        items: make_depth_items("d1-track-", 10),
        lists: [
          make_list("profile-root", "Profile Root", ["track-a"], ["list-a", "list-b"]),
        ],
        next_nodes: [
          core.CategoryNode("likes"),
          core.ListNode("list-a"),
          core.ListNode("list-b"),
        ],
        unresolved: [],
      )

    core.CategoryNode("likes") ->
      core.ExpandResult(
        items: make_depth_items("d2cat-track-", 10),
        lists: [make_list("list-b", "Category List B", [], [])],
        next_nodes: [core.PageNode("likes:2")],
        unresolved: [],
      )

    core.PageNode("likes:2") ->
      core.ExpandResult(
        items: [make_item("track-c", "Track C", "Artist C")],
        lists: [make_list("list-c", "Page List C", ["track-c"], [])],
        next_nodes: [],
        unresolved: [],
      )

    core.ListNode("list-a") ->
      core.ExpandResult(
        items:
          list.append([make_item("track-a", "Track A", "Artist A")], make_depth_items("d2a-track-", 10)),
        lists: [make_list("list-a", "List A", ["track-a"], [])],
        next_nodes: [],
        unresolved: [],
      )

    core.ListNode("list-b") ->
      core.ExpandResult(
        items:
          list.append([make_item("track-b", "Track B", "Artist B")], make_depth_items("d2b-track-", 10)),
        lists: [make_list("list-b", "List B", ["track-b"], ["list-c"])],
        next_nodes: [
          core.ListNode("list-c"),
          core.ListNode("list-missing"),
        ],
        unresolved: [core.ListNode("list-missing")],
      )

    core.ListNode("list-c") ->
      core.ExpandResult(
        items: [make_item("track-c", "Track C", "Artist C")],
        lists: [make_list("list-c", "List C", ["track-c"], [])],
        next_nodes: [],
        unresolved: [],
      )

    _ ->
      core.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [],
      )
  }
}

fn make_item(id: String, title: String, artist: String) -> core.UnifiedItem {
  core.UnifiedItem(
    id: id,
    title: title,
    artist: artist,
    service: "soundcloud",
    source_type: "item",
    source_id: id,
  )
}

fn make_list(
  id: String,
  title: String,
  track_ids: List(String),
  list_ids: List(String),
) -> core.UnifiedCollection {
  core.UnifiedCollection(
    id: id,
    title: title,
    track_ids: track_ids,
    list_ids: list_ids,
    service: "soundcloud",
    source_type: "collection",
    source_id: id,
  )
}

fn list_ids(lists: List(core.UnifiedCollection)) -> List(String) {
  list.map(lists, fn(collection) {
    let core.UnifiedCollection(id, _, _, _, _, _, _) = collection
    id
  })
}

fn contains_item_id(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _) = item
    id == wanted
  })
}

fn make_depth_items(prefix: String, count: Int) -> List(core.UnifiedItem) {
  let numbers =
    int.range(
      from: 1,
      to: count + 1,
      with: [],
      run: fn(acc, n) { list.append(acc, [n]) },
    )
  list.map(numbers, fn(n) {
    let n_str = int_to_two_digits(n)
    let id = prefix <> n_str
    make_item(id, "Generated " <> id, "Generated Artist")
  })
}

fn int_to_two_digits(n: Int) -> String {
  case n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
}

