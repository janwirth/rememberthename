# Config / credentials

**Read** `.env` / `.spotify_oauth_session.json` only in **`src/source_specs.gleam`** (each row is a complete `SourceRoot`) and in the **Spotify OAuth** commands wired from **`src/cli.gleam`** (`spotify-oauth-start`, `spotify-oauth-exchange`). Helpers (`cli/config_paths`, `cli/spotify_credentials`, `cli/spotify_oauth`) are OK only on those paths.

**Everywhere else:** pass `ApiKeys`, `SpotifyCredentials`, `SourceRoot`, argv — no env/session reads (same idea as `fetch_ops.spec.md`; `adapters/api_keys` stays types + `require_*` only). External/library callers build or receive `SourceRoot` values themselves.

**`.env`:** use [`dot_env`](https://hexdocs.pm/dot_env/index.html) — `dot.new() |> dot.set_path(...) |> dot.set_debug(False) |> dot.load`, then `dot_env/env`.

**Vars (illustrative):** `SPOTIFY_*`, `GOOGLE_CLOUD_API_KEY` in `.env`; OAuth exchange writes `.spotify_oauth_session.json`; `source_specs` loads both for `SpotifyRoot` / `YoutubeRoot`.

**Tests / dev binaries:** may read `.env` or fixtures directly; production paths still follow the rules above.
