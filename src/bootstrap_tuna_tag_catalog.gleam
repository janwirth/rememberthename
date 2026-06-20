import gleam/io
import rememberthename

/// Write encoded catalog JSON to stdout: `gleam run -m bootstrap_tuna_tag_catalog > …/tuna_tag_catalog.json`
pub fn main() {
  case rememberthename.fetch_tuna_tag_catalog() {
    Ok(tags) -> io.println(rememberthename.encode_tuna_tag_catalog(tags))
    Error(err) -> {
      io.println("ERROR: " <> err)
      panic
    }
  }
}
