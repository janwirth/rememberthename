# fishbone-2026

Gleam CLI for fetching/exporting music source data (Bandcamp, SoundCloud, Spotify, YouTube, Tuna) into CSV artifacts.

## CLI cache behavior

Cache mode is controlled by command shape:

- `use-cache` -> `readonly` mode (`CacheReadOnly`): read cache only, never fetch from network.
- no `use-cache` -> `override` mode (`CacheOverride`): fetch live and overwrite cache.
- explicit `cache <upsert|ignore|override|readonly>` is available on `source fetch` commands.

### Important logging note

Debug lines like `[fetch] start ...` are traversal events from the resolver queue, not guaranteed network calls.
With `use-cache`, you can still see `[fetch]` lines even when payloads are served from cache.

## Export commands

- `gleam run -m cli -- export all csv`
- `gleam run -m cli -- export all csv use-cache`
- `gleam run -m cli -- export source csv <entry_point_id> depth <1|2|full> [use-cache]`

Exports now always run validation checks.

- `export all csv` validates all source runs and Tuna output.
- `export source csv ... depth ...` validates source invariants for depth-1/depth-2/full on every export run.

## Completion signal

The CLI now emits a deterministic completion line at the end of command execution:

- `CLI_EXIT:0`

This can be used by scripts/watchers as a simple end-of-run signal.

## Typical usage

- `gleam run -m cli -- list`
- `gleam run -m cli -- source fetch id spotify depth full use-cache`
- `gleam run -m cli -- export all csv use-cache`
