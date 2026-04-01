# Official API clients, explicit credentials, and added-at

This spec extends [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md): **Spotify** library “added” time must come from the **official HTTP API** via [`spotify_client`](https://hexdocs.pm/spotify_client/index.html). **YouTube** is specified separately in [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md) ([`gleetube`](https://hexdocs.pm/gleetube/index.html)).

## 1) Libraries

- **Spotify Web API** — [`spotify_client`](https://hexdocs.pm/spotify_client/index.html) (typed client; follow its auth and resource modules for the version pinned in `gleam.toml`).
- **YouTube Data API v3** — see [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md).

## 2) `ApiKeys` (explicit configuration)

Adapters that need network credentials receive a single extra argument (name illustrative; exact module path is implementation detail):

```text
ApiKeys {
  spotify: Option(String),
  google_cloud: Option(String),
}
```

Semantics:

- **`spotify`**: credential string required for Spotify Web API calls in the flows this project supports (typically a **Bearer access token** from the existing OAuth session). The field name stays `spotify` as one bucket of “Spotify secret material” passed from the CLI.
- **`google_cloud`**: defined in [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md) (YouTube Data API key / future OAuth material).

Both are `Option(String)` so callers can build one value for “YouTube-only” or “Spotify-only” runs; **adapters decide which side is mandatory** for a given operation.

## 3) Adapter validation

When an adapter entry point is invoked:

1. It inspects `ApiKeys` for whatever that adapter needs (Spotify expander needs `spotify`; YouTube Data API path needs `google_cloud` — see gleetube spec).
2. If a required value is `None` (or empty after trim, if you add that rule), the adapter **does not** read `.env`, session files, or environment variables. It returns a **dedicated error** (for example `MissingApiKey(service: ...)` ) so the CLI can print a clear message.
3. If present, the adapter constructs the official client (`spotify_client` / `gleetube`) from those strings only.

**Library rule:** core adapter and normalization code **must not** load `.spotify_oauth_session.json`, `.env`, or `dot_env` for these credentials. All I/O for secrets stays in the application layer.

## 4) CLI: load credentials, pass them explicitly

The **CLI application** (entry `src/cli.gleam`, paths under `cli/config_paths`, wiring in `cli/resolve_adapter.gleam` or successor) is responsible for:

| Credential                                                                                     | Source (application only)                                                                                                                                                                                                                      |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Spotify access token (and any other `spotify_client` inputs required by the chosen API calls) | `.spotify_oauth_session.json` (Spotify config root), plus `.env` keys such as `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` if refresh or client setup still needs them                                                                       |
| YouTube / Google Cloud                                                                         | [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md) — `GOOGLE_CLOUD_API_KEY` from `.env`                                                                                                                                                    |

The CLI builds `ApiKeys { spotify: ..., google_cloud: ... }` and passes that into the adapter resolve path.

**Important:** even though the process reads files and env on startup, **libraries receive only the explicit `ApiKeys` argument**; tests and downstream callers can inject fakes without touching the filesystem.

## 5) Mapping to `added_at` (reminder)

Behavior for normalization, UTC ISO-8601, date-only midnight UTC, missing vs failure, and merge (“earliest wins”) remains in [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md).

- **YouTube:** [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md) §5.
- **Spotify:** saved tracks / library endpoints — use the timestamp field(s) for “added at” in the API response for supported flows (confirm against `spotify_client` types and Spotify’s reference docs).

## 6) Checklist (implementation)

- [ ] Add `spotify_client` and `gleetube` to `gleam.toml` with pinned versions (`gleetube` checklist detail: [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md) §6).
- [ ] Introduce `ApiKeys` and thread it through YouTube and Spotify adapter entry points used for fetch/resolve.
- [ ] Implement `MissingApiKey` (or equivalent) and ensure adapters never silently fall back to env inside library code.
- [ ] CLI: Spotify session + `.env` as today; YouTube key per gleetube spec; construct `ApiKeys` and pass into adapters.
- [ ] Populate `added_at` from API responses + tests; tick items in [SPEC_ADDED_AT_TIMESTAMP.md](./SPEC_ADDED_AT_TIMESTAMP.md).

## 7) Open points

- Whether Spotify flows need only access token in `ApiKeys.spotify` or also client id/secret in the same record vs separate config type — keep the **explicit pass-in** rule; extend the record if `spotify_client` requires more than one string at call sites.
  - All credentials required, with typed interface
