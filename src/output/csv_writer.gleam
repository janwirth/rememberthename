import gleam/list
import gleam/string
import output/visual_output

pub fn tracks_csv(tracks: List(visual_output.TrackView)) -> String {
  let header =
    "title,artist,service,source_id,external_source_url,adapter_id,download,cover,tags"
  let rows =
    list.map(tracks, fn(track) {
      visual_output.track_csv_row(track)
      |> list.map(csv_cell)
      |> string.join(",")
    })
  string.join([header, ..rows], "\n")
}

fn csv_cell(value: String) -> String {
  let escaped = string.replace(value, "\"", "\"\"")
  case needs_quotes(escaped) {
    True -> "\"" <> escaped <> "\""
    False -> escaped
  }
}

fn needs_quotes(value: String) -> Bool {
  string.contains(value, ",")
  || string.contains(value, "\"")
  || string.contains(value, "\n")
  || string.contains(value, "\r")
}
