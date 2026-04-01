# Adapter API keys and explicit credentials

This spec defines **how credentials reach adapters**. It applies to every service that needs secrets at resolve/fetch time (Spotify, YouTube Data API, and any future adapters).

Per-service **what** to send and **which official client** to use are defined elsewhere:

- Spotify — [SPEC_OFFICIAL_API_CLIENTS_AND_KEYS.md](./SPEC_OFFICIAL_API_CLIENTS_AND_KEYS.md)
- YouTube — [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md)

## 1) `ApiKeys` (single bundle)

Adapters that need network credentials receive one extra argument (exact module path is an implementation detail):

```text
ApiKeys {
  spotify: Option(String),
  google_cloud: Option(String),
}
```

Semantics:

- **`spotify`**: one bucket of Spotify secret material from the application layer (typically a **Bearer access token**; extend the type if `spotify_client` needs client id/secret alongside the token).
- **`google_cloud`**: Google Cloud / YouTube Data API material as defined in [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md).

Both fields are `Option(String)` so the CLI can build a value for “YouTube-only” or “Spotify-only” runs. **Each adapter decides which fields are mandatory** for a given operation.

## 2) Adapter validation

When an adapter entry point runs:

1. It reads only the `ApiKeys` fields it needs for that operation.
2. If a required value is `None`, or empty after trim if you adopt that rule, the adapter **does not** read `.env`, OAuth session files, or process environment variables for that secret. It returns a **dedicated error** (for example `MissingApiKey(service: ...)`) so the CLI can print a clear message.
3. If present, the adapter builds the official HTTP client from those values only.

**Library rule:** core adapter and normalization code **must not** load `.spotify_oauth_session.json`, `.env`, or `dot_env` for these credentials. All filesystem and env I/O for secrets stays in the **application layer** (CLI and tests that construct `ApiKeys`).

## 3) CLI and tests: construct and inject

The **CLI** (`src/cli.gleam`, `cli/config_paths`, `cli/resolve_adapter.gleam` or successor) is responsible for reading local configuration and building `ApiKeys`:

| Field            | Typical source (application only)                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------------------- |
| `spotify`        | `.spotify_oauth_session.json` and, if needed, `.env` keys such as `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET`     |
| `google_cloud`   | `.env` — e.g. `GOOGLE_CLOUD_API_KEY` per [SPEC_GLEETUBE_YOUTUBE.md](./SPEC_GLEETUBE_YOUTUBE.md)                      |

**Tests and downstream callers** pass explicit `ApiKeys` (including fakes) so nothing in the adapter layer depends on the filesystem for secrets.

## 4) Typed credentials (open direction)

If a service needs more than one string (OAuth refresh, separate client id/secret), **extend the explicit config type** passed into adapters rather than reading extra env vars inside library code. Prefer a small typed record per service or a refined `ApiKeys` shape; keep the rule: **everything required at the call site, nothing hidden in env inside adapters**.

## 5) Checklist (wiring)

- [ ] Define `ApiKeys` (and `MissingApiKey` or equivalent) in one place; thread through resolve/fetch entry points per service.
- [ ] Ensure no adapter loads `.env` or session files for Spotify/YouTube credentials.
- [ ] CLI builds `ApiKeys` once and passes it into the adapter resolve path.
- [ ] Tests inject `ApiKeys` without touching real secret files.
