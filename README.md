# fishbone-2026

Short intro: `rememberthename` is a Gleam module for resolving music sources (Bandcamp, SoundCloud, Spotify, YouTube, Tuna) and optionally writing per-source JSON artifacts.

## Installation

```toml
[dependencies]
rememberthename = { path = "../rememberthename" }
```

If published to Hex, replace `path` with a normal version constraint.

## Usage

```gleam
import rememberthename
```

### Public API example

`fetch_source` is the main public fetch function:
- `selector`: `"1"`, `"spotify"`, `"spotify-2"`, ...
- `cache`: `ReadOnly | Override | Upsert | Ignore`
- `write_to_json_file`: `True` writes `output/cli_result_*.json`, `False` keeps it in memory only

```gleam
import gleam/int
import gleam/io
import gleam/list
import rememberthename

pub fn main() {
  list.each(rememberthename.list_sources(), fn(row) {
    io.println(row.key <> " | " <> row.entry_point)
  })

  case rememberthename.fetch_source(
    "spotify",
    rememberthename.ReadOnly,
    False,
    fn(line) { io.println(line) },
  ) {
    Ok(tracks) ->
      io.println("resolved tracks: " <> int.to_string(list.length(tracks)))
    Error(reason) -> io.println("error: " <> reason)
  }
}
```

### Private API example (for maintainers of this repo)

The module also has private helpers for internal flows:
- `fetch_tuna(...)`
- all-sources export flow in internal modules (`fetch_ops`, CLI paths)

Those are not public and cannot be imported from outside this package.
