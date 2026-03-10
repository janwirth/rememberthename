# Adapter FFI -> Gleam Spec

- Adapters in scope: `spotify`, `soundcloud`, `youtube`, `bandcamp`.
- Objective: keep adapter behavior in Gleam; keep FFI only for hard OS/runtime boundaries.
- Move to Gleam: parsing, mapping, traversal, auth/env/session resolution, cache policy, and file I/O.
- Remove from adapter core: `jq`, regex-based JSON parsing, and shell-heavy `curl` orchestration.
- HTTP note: `gleam/http/request` models requests; it is not a transport client ([docs](https://hexdocs.pm/gleam_http/gleam/http/request.html)); use a client such as [gleam_hackney](https://hexdocs.pm/gleam_hackney/index.html) for outbound calls.
- Cache standard: use `hardcache` with stable request keys ([docs](https://hexdocs.pm/hardcache/index.html)).
- Required migration test order per adapter: `depth 1` -> `depth 2` -> `depth all` (after warm-up pass).
- Each depth stage must assert deterministic ordering, canonical dedup, and fixture anchors.
- Existing tests must pass.

## Spotify OAuth Server (Utility, Not Adapter)

- `src/adapters/spotify/oauth_server.gleam` is for obtaining adapter params (token/session), not expansion logic.
- Keep it in the Spotify folder but test and maintain it as separate bootstrap tooling.
- Prefer Gleam for parsing/file/token handling; keep only minimal OS-open shim if required.
- Fix callback transport mismatch (`https` callback vs non-TLS local listener) so request parsing works reliably.
