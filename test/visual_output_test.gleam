import gleeunit
import gleeunit/should
import output/visual_output

pub fn main() {
  gleeunit.main()
}

pub fn render_uses_unicode_tree_connectors_test() {
  let lists = [
    visual_output.ListView(
      "List A",
      [
        visual_output.TrackView("Track 1", "Artist 1", "youtube", "yt-1"),
        visual_output.TrackView("Track 2", "Artist 2", "youtube", "yt-2"),
        visual_output.TrackView("Track 3", "Artist 3", "youtube", "yt-3"),
        visual_output.TrackView("Track 4", "Artist 4", "youtube", "yt-4"),
      ],
    ),
    visual_output.ListView(
      "List B",
      [
        visual_output.TrackView("Track 5", "Artist 5", "spotify", "sp-5"),
        visual_output.TrackView("Track 6", "Artist 6", "spotify", "sp-6"),
        visual_output.TrackView("Track 7", "Artist 7", "spotify", "sp-7"),
      ],
    ),
  ]
  let flat_tracks = [
    visual_output.TrackView("Track 1", "Artist 1", "youtube", "yt-1"),
    visual_output.TrackView("Track 2", "Artist 2", "youtube", "yt-2"),
    visual_output.TrackView("Track 3", "Artist 3", "youtube", "yt-3"),
    visual_output.TrackView("Track 4", "Artist 4", "youtube", "yt-4"),
    visual_output.TrackView("Track 5", "Artist 5", "spotify", "sp-5"),
    visual_output.TrackView("Track 6", "Artist 6", "spotify", "sp-6"),
    visual_output.TrackView("Track 7", "Artist 7", "spotify", "sp-7"),
  ]

  let expected =
    "lists\n"
    <> "├── List A (4)\n"
    <> "│   ├── Track 1 - Artist 1\n"
    <> "│   ├── Track 2 - Artist 2\n"
    <> "│   └── Track 3 - Artist 3\n"
    <> "└── List B (3)\n"
    <> "    ├── Track 5 - Artist 5\n"
    <> "    ├── Track 6 - Artist 6\n"
    <> "    └── Track 7 - Artist 7\n"
    <> "\n"
    <> "all tracks\n"
    <> "├── first 3\n"
    <> "│   ├── Track 1 - Artist 1 [youtube]\n"
    <> "│   ├── Track 2 - Artist 2 [youtube]\n"
    <> "│   └── Track 3 - Artist 3 [youtube]\n"
    <> "├── ...\n"
    <> "└── last 3\n"
    <> "    ├── Track 5 - Artist 5 [spotify]\n"
    <> "    ├── Track 6 - Artist 6 [spotify]\n"
    <> "    └── Track 7 - Artist 7 [spotify]"

  visual_output.render(#(lists, flat_tracks))
  |> should.equal(expected)
}

pub fn render_shows_all_once_when_total_tracks_is_six_or_less_test() {
  let lists = [
    visual_output.ListView(
      "Short",
      [
        visual_output.TrackView("A", "AA", "soundcloud", "sc-a"),
        visual_output.TrackView("B", "BB", "soundcloud", "sc-b"),
      ],
    ),
    visual_output.ListView(
      "Short 2",
      [
        visual_output.TrackView("C", "CC", "bandcamp", "bc-c"),
      ],
    ),
  ]
  let flat_tracks = [
    visual_output.TrackView("A", "AA", "soundcloud", "sc-a"),
    visual_output.TrackView("B", "BB", "soundcloud", "sc-b"),
    visual_output.TrackView("C", "CC", "bandcamp", "bc-c"),
  ]

  let expected =
    "lists\n"
    <> "├── Short (2)\n"
    <> "│   ├── A - AA\n"
    <> "│   └── B - BB\n"
    <> "└── Short 2 (1)\n"
    <> "    └── C - CC\n"
    <> "\n"
    <> "all tracks\n"
    <> "└── all\n"
    <> "    ├── A - AA [soundcloud]\n"
    <> "    ├── B - BB [soundcloud]\n"
    <> "    └── C - CC [bandcamp]"

  visual_output.render(#(lists, flat_tracks))
  |> should.equal(expected)
}
