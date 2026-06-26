# fishbone-2026

Short intro: `rememberthename` is a Gleam module for resolving music sources (Bandcamp, SoundCloud, Spotify, YouTube, Tuna) and optionally writing per-source JSON artifacts.

## Fetch item cap

The main `fetch` path (`fetch_ops`) passes a **hard cap of 200,000 unified items** (`fetch_max_items` in `src/fetch_ops.gleam`). When that count is reached, the resolver stops merging further tracks and returns unresolved work (including an internal marker for the limit). Pagination (e.g. 50 items per API page) is not the same thing: adapters keep following pages until this cap or depth rules apply. Use `core.All` for depth where the source supports it if you want full hop traversal; shallow `Depth1` / `Depth2` / … modes limit how deep the graph is expanded regardless of this cap.

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

## Known limitations

### Spotify: no genre data

The Spotify adapter does not fetch or populate genres. Spotify's genre data is unreliable at every level:
- **Artist genres** are frequently wrong (e.g. BAUGRUPPE90 tagged as cumbia, Tame Impala tagged as techno).
- **Album genres** are almost never populated by Spotify (returns `[]` for ~99% of albums).
- Track-level genres do not exist in the Spotify API.

Genre fields for Spotify items are always empty (`[]`). If you need genres, use a different source (Last.fm, MusicBrainz).
