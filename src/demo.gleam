import gleam/int
import gleam/io
import gleam/list
import bandcamp_live_expander
import soundcloud_adapter
import soundcloud_live_expander

pub fn main() {
  io.println("rememberthename demo")
  run_all_soundcloud("https://soundcloud.com/tungstenselects")
  run_all_bandcamp("https://bandcamp.com/janwirth")
}

fn run_all_soundcloud(profile_url: String) -> Nil {
  io.println("== soundcloud all ==")
  io.println("profile: " <> profile_url)

  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "soundcloud",
      source_type: "collection",
      source_id: profile_url,
    )

  let result = soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.All, soundcloud_live_expander.expand)
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

fn run_all_bandcamp(profile_url: String) -> Nil {
  io.println("== bandcamp all ==")
  io.println("profile: " <> profile_url)

  let profile =
    soundcloud_adapter.SourceIdentity(
      service: "bandcamp",
      source_type: "collection",
      source_id: profile_url,
    )

  let result = soundcloud_adapter.resolve_profile(profile, soundcloud_adapter.All, bandcamp_live_expander.expand)
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
