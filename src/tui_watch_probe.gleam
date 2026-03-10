import gleam/io

// Change this value to simulate a code change/reload target.
const version = "v1"

pub fn main() {
  io.println("tui-watch-probe:" <> version)
}
