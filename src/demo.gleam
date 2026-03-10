import gleam/int
import gleam/io
import gleam/list
import adapters/core
import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/soundcloud/live_expander as soundcloud_live_expander

pub fn main() {
  io.println("rememberthename demo")
  run_all_soundcloud("https://soundcloud.com/tungstenselects")
  run_all_bandcamp("https://bandcamp.com/janwirth")
}

fn run_all_soundcloud(profile_url: String) -> Nil {
  io.println("== soundcloud all ==")
  io.println("profile: " <> profile_url)

  let profile = soundcloud_live_expander.soundcloud_profile(profile_url)
  let result = soundcloud_live_expander.resolve_profile(profile, core.All)
  let core.ResolveResult(items, lists, unresolved) = result

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

  let profile = bandcamp_live_expander.bandcamp_profile(profile_url)
  let result = bandcamp_live_expander.resolve_profile(profile, core.All)
  let core.ResolveResult(items, lists, unresolved) = result

  io.println("items: " <> int.to_string(list.length(items)))
  io.println("lists: " <> int.to_string(list.length(lists)))
  io.println("unresolved: " <> int.to_string(list.length(unresolved)))
  io.println("items:")
  print_item_titles(items)
  io.println("lists:")
  print_list_titles(lists)
  io.println("")
}

fn print_item_titles(items: List(core.UnifiedItem)) {
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

fn print_list_titles(lists: List(core.UnifiedCollection)) {
  case lists {
    [] -> io.println("  - (none)")
    _ ->
      list.each(lists, fn(collection) {
        let core.UnifiedCollection(_, title, track_ids, list_ids, _, _, _) = collection
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

fn print_items(items: List(core.UnifiedItem)) {
  list.each(items, fn(item) {
    let core.UnifiedItem(_, title, artist, _, _, _) = item
    io.println("  - " <> title <> " | " <> artist)
  })
}
