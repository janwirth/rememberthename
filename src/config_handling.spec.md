# Config / credentials

**Read** `.env` / `.spotify_oauth_session.json` only in **`src/source_specs.gleam`** (catalog rows) and in the **Spotify OAuth** commands wired from **`src/cli.gleam`** (`spotify-oauth-start`, `spotify-oauth-exchange`). Helpers (`cli/config_paths`, `cli/spotify_credentials`, `cli/spotify_oauth`) are OK only on those paths.

**Everywhere else:** pass `ApiKeys`, `SpotifyCredentials`, `SourceRoot`, argv — no env/session reads (same idea as `fetch_ops.spec.md`; `adapters/api_keys` stays types + `require_*` only).

**`.env`:** use [`dot_env`](https://hexdocs.pm/dot_env/index.html) — `dot.new() |> dot.set_path(...) |> dot.set_debug(False) |> dot.load`, then `dot_env/env`.

**Vars (illustrative):** `SPOTIFY_*`, `GOOGLE_CLOUD_API_KEY` in `.env`; OAuth exchange writes `.spotify_oauth_session.json`, `source_specs` reads it for `SpotifyRoot`.

## Open questions

- **`GOOGLE_CLOUD_API_KEY`:** load it in `source_specs` when building the YouTube row (so the catalog always carries a full `YoutubeRoot`), or keep the key argv-only and merge outside `source_specs`?
  -> the source_specs are the always complete and valid
- **Tests / dev-only binaries:** allow direct `.env` reads there, or require injected creds / small fixtures only?
  - direct env reads are allowed
- **Callers still using `load_api_keys` / `get_*_from_env`:** fold into `source_specs` + explicit args, or is there another approved boundary (e.g. a single “app bootstrap” module)?
  - no other boundaries. External callers are responsible for credential handling (and passing) themselves as SourceRoots.
