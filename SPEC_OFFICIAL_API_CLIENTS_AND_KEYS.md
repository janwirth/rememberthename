# Official Spotify Web API, credentials, and added-at

This document is **Spotify-focused**. Shared rules for passing **`ApiKeys` into adapters** (structure, validation, CLI vs library boundaries) live in [SPEC_ADAPTER_API_KEYS.md](./SPEC_ADAPTER_API_KEYS.md). **YouTube** is specified in [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md). Normalization rules for **`added_at`** (UTC, merge, missing vs failure) remain in [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md).

## 1) Library

Use **[`spotify_client`](https://hexdocs.pm/spotify_client/index.html)** for the **Spotify Web API**: typed client, follow its auth and resource modules for the version pinned in `gleam.toml`.

Do not scrape the Spotify web app for library timestamps when this spec is in effect; **“added to library” time must come from the official API** for supported flows.

## 2) Credentials (`ApiKeys.spotify`)

Per [SPEC_ADAPTER_API_KEYS.md](./SPEC_ADAPTER_API_KEYS.md), adapters receive `ApiKeys` with a `spotify` field. For Spotify resolve/fetch:

- Pass whatever **`spotify_client`** needs for the chosen endpoints (at minimum a **Bearer access token** from the existing OAuth session).
- If refresh or client registration requires **client id / secret**, those also belong in explicit application-loaded config; extend the typed `ApiKeys` (or a nested Spotify config record) rather than reading `.env` inside adapter code.

## 3) Validation

Before calling `spotify_client`, require `spotify` to be `Some(non-empty)` (and any other required fields once the type is extended). On failure, return **`MissingApiKey`** (or equivalent) for a stable service label such as `"spotify"` — see [SPEC_ADAPTER_API_KEYS.md](./SPEC_ADAPTER_API_KEYS.md) §2.

## 4) CLI (application layer only)

The CLI reads `.spotify_oauth_session.json` (Spotify config root) and, when needed, `.env` for `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET`. It constructs `ApiKeys` and passes it into the adapter resolve path. Adapters never open those files themselves.

## 5) Mapping to `added_at`

Follow [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md) for storage format and merge (“earliest wins”).

For Spotify, use the API fields that represent when a track (or saved item) was **added to the user’s library** in the flows you support — for example saved tracks / library endpoints. Confirm exact field paths against `spotify_client` types and [Spotify’s Web API reference](https://developer.spotify.com/documentation/web-api).

## 6) Checklist (Spotify)

- [ ] Add `spotify_client` to `gleam.toml` with a pinned version.
- [ ] Thread `ApiKeys` through Spotify adapter entry points used for fetch/resolve; validate `spotify` per [SPEC_ADAPTER_API_KEYS.md](./SPEC_ADAPTER_API_KEYS.md).
- [ ] Replace or narrow any non-API paths so `added_at` for Spotify comes from official responses where available; align tests with [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md).

## 7) Related work outside this doc

- YouTube Data API + `gleetube` — [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md).
- Shared `ApiKeys` / `MissingApiKey` — [SPEC_ADAPTER_API_KEYS.md](./SPEC_ADAPTER_API_KEYS.md).
