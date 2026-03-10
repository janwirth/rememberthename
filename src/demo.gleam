import gleam/int
import gleam/io
import gleam/list
import soundcloud_adapter
import soundcloud_live_expander

pub fn main() {
  let profile_url = "https://soundcloud.com/tungstenselects"
  io.println("rememberthename demo")
  io.println("profile: " <> profile_url)
  io.println("")

  run_depth("depth-1", soundcloud_adapter.Depth1, profile_url)
  run_depth("depth-2", soundcloud_adapter.Depth2, profile_url)
  run_depth("full", soundcloud_adapter.Full, profile_url)
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
  io.println("sample items:")
  print_item_titles(items, 5)
  io.println("sample lists:")
  print_list_titles(lists, 5)
  io.println("")
}

fn print_item_titles(items: List(soundcloud_adapter.UnifiedItem), max: Int) {
  let subset = list.take(items, max)
  case subset {
    [] -> io.println("  - (none)")
    _ ->
      list.each(subset, fn(item) {
        let soundcloud_adapter.UnifiedItem(_, title, artist, _, _, _) = item
        io.println("  - " <> title <> " | " <> artist)
      })
  }
}

fn print_list_titles(lists: List(soundcloud_adapter.UnifiedCollection), max: Int) {
  let subset = list.take(lists, max)
  case subset {
    [] -> io.println("  - (none)")
    _ ->
      list.each(subset, fn(collection) {
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
