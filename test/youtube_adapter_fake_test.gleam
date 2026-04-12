import adapters/core
import gleam/int
import gleam/option.{None, Some}
import gleam/list
import gleam/string
import gleam/time/timestamp

pub fn depth_1_stops_after_profile_test() {
  let result =
    core.resolve_profile_url(
      "https://www.youtube.com/playlist?list=PLdemo",
      core.Depth1,
      fake_expand,
    )
  let core.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 5
  assert contains_item_id(items, "yt-d1-01")
  assert items_have_https_covers(items)
  assert list_ids(lists) == ["youtube:collection:PLdemo"]
  assert unresolved == []
}

pub fn depth_2_expands_one_more_page_test() {
  let result =
    core.resolve_profile_url(
      "https://www.youtube.com/playlist?list=PLdemo",
      core.Depth2,
      fake_expand,
    )
  let core.ResolveResult(items, lists, unresolved) = result

  assert list.length(items) >= 15
  assert contains_item_id(items, "yt-d2-05")
  assert list_ids(lists) == ["youtube:collection:PLdemo"]
  assert unresolved == []
}

fn fake_expand(node: core.AdapterNode) -> core.ExpandResult {
  case node {
    core.ProfileEntry(_) ->
      core.ExpandResult(
        items: make_depth_items("yt-d1-", 10),
        lists: [
          make_list(
            "youtube:collection:PLdemo",
            "Demo Playlist",
            ["yt-d1-01"],
            [],
          ),
        ],
        next_nodes: [
          core.PageNode("https://www.youtube.com/playlist?list=PLdemo|10"),
        ],
        unresolved: [],
        cache_hits: 0,
        cache_fetches: 0,
      )

    core.PageNode(ctx) -> {
      let parts = string.split(ctx, "|")
      case parts {
        [_, "10"] ->
          core.ExpandResult(
            items: make_depth_items("yt-d2-", 10),
            lists: [
              make_list(
                "youtube:collection:PLdemo",
                "Demo Playlist",
                ["yt-d1-01"],
                [],
              ),
            ],
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

fn make_item(id: String, title: String, artist: String) -> core.UnifiedItem {
  core.UnifiedItem(
    id: id,
    title: title,
    artist: artist,
    service: "youtube",
    source_type: "item",
    source_id: id,
    external_source_url: None,
    cover_url: Some("https://i.ytimg.com/vi/" <> id <> "/hqdefault.jpg"),
    file_path: None,
    added_at: timestamp.unix_epoch,
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
    service: "youtube",
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
    let core.UnifiedItem(id, _, _, _, _, _, _, _, _, _) = item
    id == wanted
  })
}

fn items_have_https_covers(items: List(core.UnifiedItem)) -> Bool {
  list.all(items, fn(item) {
    let core.UnifiedItem(_, _, _, _, _, _, _, cover, _, _) = item
    case cover {
      Some(url) -> string.starts_with(url, "https://")
      None -> False
    }
  })
}

fn make_depth_items(prefix: String, count: Int) -> List(core.UnifiedItem) {
  let numbers =
    int.range(from: 1, to: count + 1, with: [], run: fn(acc, n) {
      list.append(acc, [n])
    })
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
