# Provider Timing Spec

Shared timing/runtime policy for provider adapters (`bandcamp`, `soundcloud`, `spotify`, `youtube`).

## Scope

- Applies to `DepthAll` traversal in `adapters/core`.
- Applies to adapters that call `core.resolve_profile_url_with_debug(...)`.
- Tuna is excluded.

## Default Limits

- `requests_per_second = 3`
- `max_concurrency = 3`
- queue start interval: ~`333ms` between worker starts

## Runtime Location

- Core enforcement lives in: `src/adapters/core.gleam`
- Queue module docs + primitives: `src/default_queue.gleam`

## Debug Contract

`DepthAll` debug output must include:

- queue enabled line with limits
- per-node queue start
- per-node fetch start
- per-node fetch complete
- queue completion summary

Example prefix:

- `[queue] enabled mode=concurrent req_per_sec=3 concurrency=3`

## Integration Contract

Provider specs should reference this file instead of duplicating timing values.
