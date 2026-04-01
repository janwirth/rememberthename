/// # rememberthename - Unified Visual Output Spec
///
/// This spec defines one unified output shape across all resolution methods.
///
/// Methods covered:
///
/// - `shallow`
/// - `step`
/// - `deep`
/// - `all`
///
/// The visual/reporting format MUST stay identical across methods.
/// Only the resolved data volume changes by method.
///
/// ## 1) Required Outputs
///
/// Every run can produce two visual outputs:
///
/// - terminal summary (Unicode tree)
/// - full tracks export (CSV)
///
/// ## 2) Full Tracks CSV
///
/// Purpose:
///
/// - export all resolved tracks in a flat, portable format
///
/// Rules:
///
/// - output contains every resolved track (`all tracks`)
/// - deterministic ordering (same input + method => same row order)
/// - include header row
/// - UTF-8 text, comma-separated values, standard CSV escaping
///
/// Required columns:
///
/// - `title`
/// - `artist`
/// - `service`
/// - `source_id`
/// - `external_source_url`
/// - `adapter_id`
/// - `download`
/// - `cover`
/// - `tags`
///
/// ## 3) Terminal Output (Unicode Tree)
///
/// Purpose:
///
/// - quick human scan in terminal
/// - stable shape across all methods
///
/// Rendering rule:
///
/// - Unicode tree style only (`├──`, `└──`, `│`)
/// - do not use ASCII fallback connectors (`|-`, ``-`)
///
/// Top-level sections in this exact order:
///
/// 1. `lists`
/// 2. `all tracks`
///
/// ### 3.1 `lists` section
///
/// For each resolved list, render:
///
/// - list title
/// - track count
/// - first 3 tracks in list order
///
/// Format:
///
/// - `list node`: `<title> (<track_count>)`
/// - `track preview node`: `<track_title> - <artist>`
///
/// If a list has fewer than 3 tracks:
///
/// - render only available tracks
///
/// ### 3.2 `all tracks` section
///
/// Render:
///
/// - first 3 tracks from global track ordering
/// - ellipsis separator line
/// - last 3 tracks from global track ordering
///
/// Rules:
///
/// - if total tracks <= 6, show all tracks once (no duplicated rows)
/// - ellipsis line is exactly `...` and only shown when omitted middle exists
/// - track row format: `<track_title> - <artist> [<service>]`
///
/// ## 4) Canonical Terminal Template
///
/// ```text
/// lists
/// ├── <list title A> (<count>)
/// │   ├── <track 1> - <artist>
/// │   ├── <track 2> - <artist>
/// │   └── <track 3> - <artist>
/// └── <list title B> (<count>)
///     ├── <track 1> - <artist>
///     ├── <track 2> - <artist>
///     └── <track 3> - <artist>
///
/// all tracks
/// ├── first 3
/// │   ├── <title> - <artist> [<service>]
/// │   ├── <title> - <artist> [<service>]
/// │   └── <title> - <artist> [<service>]
/// ├── ...
/// └── last 3
///     ├── <title> - <artist> [<service>]
///     ├── <title> - <artist> [<service>]
///     └── <title> - <artist> [<service>]
/// ```
///
/// ## 5) Compliance Notes
///
/// - All methods MUST use this exact section structure and labels.
/// - CSV export MUST always represent all resolved tracks.
/// - Terminal output is a summary view, not a full dump.
///   Normalization rules:
/// - trailing `/` means folder node
/// - no trailing `/` means file/leaf node
/// - indentation depth defines parent-child nesting
/// - output renderer still MUST emit terminal view in Unicode tree format defined above
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp
import output/tree_view

pub type TrackView {
  TrackView(
    title: String,
    artist: String,
    service: String,
    source_id: String,
    external_source_url: Option(String),
    added_at: timestamp.Timestamp,
    adapter_id: String,
    download: String,
    cover: String,
    tags: String,
  )
}

pub type ListView {
  ListView(title: String, tracks: List(TrackView))
}

pub fn render(input: #(List(ListView), List(TrackView))) -> String {
  input
  |> to_tree_document
  |> tree_view.render
}

pub fn to_tree_document(
  input: #(List(ListView), List(TrackView)),
) -> tree_view.Document {
  let #(lists, flat_tracks) = input
  tree_view.Document([
    lists_section(lists),
    all_tracks_section(flat_tracks),
  ])
}

fn lists_section(lists: List(ListView)) -> tree_view.Section {
  case lists {
    [] -> tree_view.Section("lists", [tree_view.Node("(none)", [])])
    _ -> tree_view.Section("lists", list.map(lists, list_node))
  }
}

fn list_node(list_view: ListView) -> tree_view.Node {
  let ListView(title, tracks) = list_view
  let children = case take_first(tracks, 3) {
    [] -> [tree_view.Node("(none)", [])]
    preview -> list.map(preview, preview_track_node)
  }
  tree_view.Node(
    title <> " (" <> int.to_string(list.length(tracks)) <> ")",
    children,
  )
}

fn preview_track_node(track: TrackView) -> tree_view.Node {
  tree_view.Node(track_label(track), [])
}

fn all_tracks_section(tracks: List(TrackView)) -> tree_view.Section {
  case list.length(tracks) {
    0 -> tree_view.Section("all tracks", [tree_view.Node("(none)", [])])
    total if total <= 6 ->
      tree_view.Section("all tracks", all_tracks_short_nodes(tracks))
    _ -> tree_view.Section("all tracks", all_tracks_long_nodes(tracks))
  }
}

fn all_tracks_short_nodes(tracks: List(TrackView)) -> List(tree_view.Node) {
  list.map(tracks, full_track_node)
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
  let TrackView(title, artist, _, _, _, _, _, _, _, _) = track
  title <> " - " <> artist <> missing_artist_suffix(artist)
}

pub fn track_csv_row(track: TrackView) -> List(String) {
  let TrackView(
    title,
    artist,
    service,
    source_id,
    external_source_url,
    _added_at,
    adapter_id,
    download,
    cover,
    tags,
  ) =
    track
  let url_cell = case external_source_url {
    Some(url) -> url
    None -> ""
  }
  [
    title,
    artist,
    service,
    source_id,
    url_cell,
    adapter_id,
    download,
    cover,
    tags,
  ]
}

fn full_track_label(track: TrackView) -> String {
  let TrackView(title, artist, service, _, _, _, _, _, _, _) = track
  title
  <> " - "
  <> artist
  <> " ["
  <> service
  <> "]"
  <> missing_artist_suffix(artist)
}

fn full_track_node(track: TrackView) -> tree_view.Node {
  tree_view.Node(full_track_label(track), [])
}

fn missing_artist_suffix(artist: String) -> String {
  case string.trim(artist) == "" {
    True -> " (!missing artist)"
    False -> ""
  }
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
