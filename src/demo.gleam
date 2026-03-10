import gleam/int
import gleam/io
import gleam/list
import soundcloud_adapter
import soundcloud_live_expander

pub fn main() {
  let profile_url = "https://soundcloud.com/tungstenselects"
  io.println("rememberthename demo")
  io.println("profile: " <> profile_url)
  run_depth("depth-10", soundcloud_adapter.Depth10, profile_url)
  run_depth("depth-20", soundcloud_adapter.Depth20, profile_url)
  run_depth("all", soundcloud_adapter.All, profile_url)
}

fn run_depth(
  label: String,
  depth: soundcloud_adapter.DepthMode,
  profile_url: String,
) -> Nil {
  io.println("== " <> label <> " ==")

  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: profile_url,
    )

  let result = soundcloud_adapter.resolve_profile(profile, depth, soundcloud_live_expander.expand)
  let soundcloud_adapter.ResolveResult(items, lists, unresolved) = result

  io.println("items: " <> int.to_string(list.length(items)))
  io.println("lists: " <> int.to_string(list.length(lists)))
  io.println("unresolved: " <> int.to_string(list.length(unresolved)))
  io.println("items:")
  print_item_titles(items)
  io.println("lists:")
  print_list_titles(lists)
  io.println("")
}

fn print_item_titles(items: List(soundcloud_adapter.UnifiedItem)) {
  let count = list.length(items)
  case count == 0 {
    True -> io.println("  - (none)")
    False ->
      case count > 7 {
        True -> {
          let first = list.take(items, 3)
          let last = list.drop(items, count - 3)
          print_items(first)
          io.println("  ...")
          print_items(last)
        }
        False -> print_items(items)
      }
  }
}

fn print_list_titles(lists: List(soundcloud_adapter.UnifiedCollection)) {
  case lists {
    [] -> io.println("  - (none)")
    _ ->
      list.each(lists, fn(collection) {
        let soundcloud_adapter.UnifiedCollection(_, title, track_ids, list_ids, _, _, _) = collection
        io.println(
          "  - "
          <> title
          <> " | tracks="
          <> int.to_string(list.length(track_ids))
          <> " nested_lists="
          <> int.to_string(list.length(list_ids)),
        )
      })
  }
}

fn print_items(items: List(soundcloud_adapter.UnifiedItem)) {
  list.each(items, fn(item) {
    let soundcloud_adapter.UnifiedItem(_, title, artist, _, _, _) = item
    io.println("  - " <> title <> " | " <> artist)
  })
}
