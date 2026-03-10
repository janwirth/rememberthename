# Adapter FFI -> Gleam (All Adapters)

- Scope: `spotify`, `soundcloud`, `youtube`, `bandcamp`.
- Goal: move parsing, mapping, traversal, auth/env/session handling, and cache policy into Gleam; keep FFI only for unavoidable OS/transport edges.
- Remove shell-driven core logic (`jq`, regex JSON parsing, broad `curl` orchestration) from adapters.
- `gleam/http/request` is request modeling only; use a real client for outbound HTTP (e.g. [gleam_hackney](https://hexdocs.pm/gleam_hackney/index.html), [gleam/http/request docs](https://hexdocs.pm/gleam_http/gleam/http/request.html)).
- Spotify OAuth note: likely callback scheme mismatch (`https://127.0.0.1:8080` callback vs non-TLS local listener).
- Cache target: standardize on `hardcache` with stable request keys ([hardcache docs](https://hexdocs.pm/hardcache/index.html)).
- Migration test order (per adapter): `depth 1` -> `depth 2` -> `depth all` (after warm-up pass).
- Existing tests must pass
