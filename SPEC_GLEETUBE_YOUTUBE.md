# YouTube Data API via gleetube

This spec covers **YouTube** only. Shared rules for explicit credentials and `ApiKeys` live in [SPEC_OFFICIAL_API_CLIENTS_AND_KEYS.md](./SPEC_OFFICIAL_API_CLIENTS_AND_KEYS.md). Normalization for `added_at` lives in [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md).

## 1) Library

Use **[`gleetube`](https://hexdocs.pm/gleetube/index.html)** for **YouTube Data API v3** (typed client, `Result`-based errors, pagination helpers such as `list_all`).

The project may keep Erlang/HTTP helpers for **non–Data-API** concerns (for example Innertube continuation probes). **`added_at` for YouTube must come from the Data API** via `gleetube` when this spec is implemented, not from HTML scraping alone.

## 2) `ApiKeys.google_cloud`

Per the umbrella spec, adapters receive `ApiKeys { spotify, google_cloud }`. For the YouTube path:

- **`google_cloud`**: credential for YouTube Data API v3 — typically an **API key** from Google Cloud with the YouTube Data API enabled, passed into `gleetube` (for example `gleetube.new("...")` or `auth.api_key` + `config` as in the Hex docs).

**Private or user-specific playlists** may require **OAuth** instead of (or in addition to) an API key. If needed later, extend the explicit config passed into adapters (still **no** `.env` or file reads inside adapter library code) using `gleetube`’s OAuth modules from the same documentation.

## 3) Validation

When the YouTube adapter uses the Data API, it **requires** `google_cloud` to be `Some(non-empty)` (if you adopt an empty-string rule). Otherwise return a dedicated error (for example `MissingApiKey` for `youtube_data_api`) — do not read env or files inside the library.

Illustrative pattern (names and `ApiKeys` module are implementation details):

```gleam
import gleam/option.{type Option, None, Some}
import gleam/string

pub type ApiKeys {
  ApiKeys(spotify: Option(String), google_cloud: Option(String))
}

pub type ResolveError {
  MissingApiKey(service: String)
  // ...
}

/// Call before any `gleetube` request for playlist / added-at data.
pub fn require_youtube_data_api_key(keys: ApiKeys) -> Result(String, ResolveError) {
  case keys.google_cloud {
    None -> Error(MissingApiKey("youtube_data_api"))
    Some(key) ->
      case string.trim(key) {
        "" -> Error(MissingApiKey("youtube_data_api"))
        trimmed -> Ok(trimmed)
      }
  }
}

// use <- result.try(require_youtube_data_api_key(keys))
// let client = gleetube.new(api_key)
```

## 4) CLI (application layer only)

Read the key from `.env` (same file as other local secrets if applicable). Env var: **`GOOGLE_CLOUD_API_KEY`**.

The CLI builds `ApiKeys` with `google_cloud: Some(value)` and passes it into the resolve path. See `cli/config_paths` / `cli/resolve_adapter.gleam` (or successor) for wiring.

## 5) Mapping to `added_at`

Follow [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md) for UTC ISO-8601, date-only midnight UTC, and merge rules.

**API target:** playlist item resource — use Data API fields that represent when the item was added to the playlist (historically `snippet.publishedAt` on `playlistItems` in playlist context; confirm against current Google documentation when implementing). Normalize into `added_at`.

## 6) Checklist

- [ ] Add `gleetube` to `gleam.toml` with a pinned version.
- [ ] Thread `ApiKeys` into the YouTube adapter entry points used for fetch/resolve; validate `google_cloud` as above.
- [ ] Implement Data API fetch for playlist items and map to `added_at` + tests.
- [ ] CLI: read `GOOGLE_CLOUD_API_KEY` from `.env` and set `ApiKeys.google_cloud`.
- [ ] Tick the YouTube line item in [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md) when done.
