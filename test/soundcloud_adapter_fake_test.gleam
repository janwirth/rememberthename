import gleam/list
import soundcloud_adapter

pub fn depth_1_stops_after_profile_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/demo",
    )
  let result = soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth1, fake_expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert item_ids(items) == []
  assert list_ids(lists) == ["profile-root"]
  assert unresolved == []
}

pub fn depth_2_expands_one_more_hop_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/demo",
    )
  let result = soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Depth2, fake_expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert item_ids(items) == ["track-a", "track-b"]
  assert list_ids(lists) == ["profile-root", "list-b", "list-a"]
  assert unresolved == [soundcloud_adapter.ListNode("list-missing")]
}

pub fn full_depth_recurses_lists_categories_and_pages_test() {
  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: "https://soundcloud.com/demo",
    )
  let result = soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.Full, fake_expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  assert item_ids(items) == ["track-a", "track-b", "track-c"]
  assert list_ids(lists) == ["profile-root", "list-b", "list-a", "list-c"]
  assert unresolved == [soundcloud_adapter.ListNode("list-missing")]
}

fn fake_expand(node: soundcloud_adapter.AdapterNode) -> soundcloud_adapter.ExpandResult {
  case node {
    soundcloud_adapter.ProfileEntry(_) ->
      soundcloud_adapter.ExpandResult(
        items: [],
        lists: [
          make_list("profile-root", "Profile Root", ["track-a"], ["list-a", "list-b"]),
        ],
        next_nodes: [
          soundcloud_adapter.CategoryNode("likes"),
          soundcloud_adapter.ListNode("list-a"),
          soundcloud_adapter.ListNode("list-b"),
        ],
        unresolved: [],
      )

    soundcloud_adapter.CategoryNode("likes") ->
      soundcloud_adapter.ExpandResult(
        items: [],
        lists: [make_list("list-b", "Category List B", [], [])],
        next_nodes: [soundcloud_adapter.PageNode("likes:2")],
        unresolved: [],
      )

    soundcloud_adapter.PageNode("likes:2") ->
      soundcloud_adapter.ExpandResult(
        items: [make_item("track-c", "Track C", "Artist C")],
        lists: [make_list("list-c", "Page List C", ["track-c"], [])],
        next_nodes: [],
        unresolved: [],
      )

    soundcloud_adapter.ListNode("list-a") ->
      soundcloud_adapter.ExpandResult(
        items: [make_item("track-a", "Track A", "Artist A")],
        lists: [make_list("list-a", "List A", ["track-a"], [])],
        next_nodes: [],
        unresolved: [],
      )

    soundcloud_adapter.ListNode("list-b") ->
      soundcloud_adapter.ExpandResult(
        items: [make_item("track-b", "Track B", "Artist B")],
        lists: [make_list("list-b", "List B", ["track-b"], ["list-c"])],
        next_nodes: [
          soundcloud_adapter.ListNode("list-c"),
          soundcloud_adapter.ListNode("list-missing"),
        ],
        unresolved: [soundcloud_adapter.ListNode("list-missing")],
      )

    soundcloud_adapter.ListNode("list-c") ->
      soundcloud_adapter.ExpandResult(
        items: [make_item("track-c", "Track C", "Artist C")],
        lists: [make_list("list-c", "List C", ["track-c"], [])],
        next_nodes: [],
        unresolved: [],
      )

    _ ->
      soundcloud_adapter.ExpandResult(
        items: [],
        lists: [],
        next_nodes: [],
        unresolved: [],
      )
  }
}

fn make_item(id: String, title: String, artist: String) -> soundcloud_adapter.UnifiedItem {
  soundcloud_adapter.UnifiedItem(
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
) -> soundcloud_adapter.UnifiedCollection {
  soundcloud_adapter.UnifiedCollection(
    id: id,
    title: title,
    track_ids: track_ids,
    list_ids: list_ids,
    service: "soundcloud",
    source_type: "collection",
    source_id: id,
  )
}

fn item_ids(items: List(soundcloud_adapter.UnifiedItem)) -> List(String) {
  list.map(items, fn(item) {
    let soundcloud_adapter.UnifiedItem(id, _, _, _, _, _) = item
    id
  })
}

fn list_ids(lists: List(soundcloud_adapter.UnifiedCollection)) -> List(String) {
  list.map(lists, fn(collection) {
    let soundcloud_adapter.UnifiedCollection(id, _, _, _, _, _, _) = collection
    id
  })
}
