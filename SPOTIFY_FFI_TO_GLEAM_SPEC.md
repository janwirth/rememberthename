# Adapter FFI -> Gleam (All Adapters)

- Scope: `spotify`, `soundcloud`, `youtube`, `bandcamp`.
- Goal: move parsing, mapping, traversal, auth/env/session handling, and cache policy into Gleam; keep FFI only for unavoidable OS/transport edges.
- Remove shell-driven core logic (`jq`, regex JSON parsing, broad `curl` orchestration) from adapters.
- `gleam/http/request` is request modeling only; use a real client for outbound HTTP (e.g. [gleam_hackney](https://hexdocs.pm/gleam_hackney/index.html), [gleam/http/request docs](https://hexdocs.pm/gleam_http/gleam/http/request.html)).
- Cache target: standardize on `hardcache` with stable request keys ([hardcache docs](https://hexdocs.pm/hardcache/index.html)).
- Migration test order (per adapter): `depth 1` -> `depth 2` -> `depth all` (after warm-up pass).
- Each depth stage should verify deterministic order, canonical dedup, and fixture anchors.
- Existing tests must pass

## Spotify OAuth Server (Non-Adapter Utility)

- `src/adapters/spotify/oauth_server.gleam` is a helper to obtain adapter params (token/session), not adapter expansion logic.
- Keep it in the Spotify folder, but treat it as auth bootstrap tooling with separate ownership/tests.
- Prefer moving its parsing/file/token handling to Gleam; keep only minimal OS-open shim if needed.
- Callback fix: align scheme/transport (`https` callback currently mismatched with non-TLS local listener).
