import gleam/int
import gleam/list
import output/tree_view

pub type TrackView {
  TrackView(title: String, artist: String, service: String, source_id: String)
}

pub type ListView {
  ListView(title: String, tracks: List(TrackView))
}

pub fn render(input: #(List(ListView), List(TrackView))) -> String {
  input
  |> to_tree_document
  |> tree_view.render
}

pub fn to_tree_document(input: #(List(ListView), List(TrackView))) -> tree_view.Document {
  let #(lists, flat_tracks) = input
  tree_view.Document([
    lists_section(lists),
    all_tracks_section(flat_tracks),
  ])
}

fn lists_section(lists: List(ListView)) -> tree_view.Section {
  case lists {
    [] -> tree_view.Section("lists", [tree_view.Node("(none)", [])])
    _ ->
      tree_view.Section("lists", list.map(lists, list_node))
  }
}

fn list_node(list_view: ListView) -> tree_view.Node {
  let ListView(title, tracks) = list_view
  let children =
    case take_first(tracks, 3) {
      [] -> [tree_view.Node("(none)", [])]
      preview -> list.map(preview, preview_track_node)
    }
  tree_view.Node(title <> " (" <> int.to_string(list.length(tracks)) <> ")", children)
}

fn preview_track_node(track: TrackView) -> tree_view.Node {
  tree_view.Node(track_label(track), [])
}

fn all_tracks_section(tracks: List(TrackView)) -> tree_view.Section {
  case list.length(tracks) {
    0 -> tree_view.Section("all tracks", [tree_view.Node("(none)", [])])
    total if total <= 6 -> tree_view.Section("all tracks", all_tracks_short_nodes(tracks))
    _ -> tree_view.Section("all tracks", all_tracks_long_nodes(tracks))
  }
}

fn all_tracks_short_nodes(tracks: List(TrackView)) -> List(tree_view.Node) {
  [
    tree_view.Node("all", list.map(tracks, full_track_node)),
  ]
}

fn all_tracks_long_nodes(tracks: List(TrackView)) -> List(tree_view.Node) {
  let first_three = take_first(tracks, 3)
  let last_three = take_last(tracks, 3)
  [
    tree_view.Node("first 3", list.map(first_three, full_track_node)),
    tree_view.Node("...", []),
    tree_view.Node("last 3", list.map(last_three, full_track_node)),
  ]
}

fn track_label(track: TrackView) -> String {
  let TrackView(title, artist, _, _) = track
  title <> " - " <> artist
}

pub fn track_csv_row(track: TrackView) -> List(String) {
  let TrackView(title, artist, service, source_id) = track
  [title, artist, service, source_id]
}

fn full_track_label(track: TrackView) -> String {
  let TrackView(title, artist, service, _) = track
  title <> " - " <> artist <> " [" <> service <> "]"
}

fn full_track_node(track: TrackView) -> tree_view.Node {
  tree_view.Node(full_track_label(track), [])
}

fn take_first(items: List(a), count: Int) -> List(a) {
  case items, count {
    [], _ -> []
    _, n if n <= 0 -> []
    [first, ..rest], n -> [first, ..take_first(rest, n - 1)]
  }
}

fn take_last(items: List(a), count: Int) -> List(a) {
  items
  |> list.reverse
  |> take_first(count)
  |> list.reverse
}
