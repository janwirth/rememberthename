# rememberthename - Bandcamp Spec (Factored)

## Reference
Input: https://bandcamp.com/janwirth
Track

shallow (depth 1):
Babylon 47

deeper (depth 2):
manifest content tracks all: +100
acid house album

## 1) Scope

Supported Bandcamp input:
- profile URLs

Out of scope for Bandcamp input:
- Individual track URLs (`/track/...`).
- Search.
- Any untestable behavior.

## 2) Source Contract

- `service`: `bandcamp`
- `source_type`: `collection` for profile roots, `item | collection` for resolved entries
- contract type: `SourceIdentity` from `SPEC.md`

Accepted profile shape:
- `SourceIdentity { service: bandcamp, source_type: collection, source_id: <profile_url> }`

## 3) URL Parsing Rules

Accepted:
- `https://bandcamp.com/<profile_slug>`
- `http://bandcamp.com/<profile_slug>`
- Optional query params allowed and ignored for canonicalization.

Canonical parse result:
- `service = bandcamp`
- `source_type = collection`
- `source_id = <normalized_profile_url>`

Rejected as parse failures:
- `https://<artist>.bandcamp.com/track/<track_slug>`
- `https://<artist>.bandcamp.com/album/<album_slug>` as direct root input
- URLs with missing or empty profile slug
- Non-Bandcamp domains

## 4) Intermediary Model

Bandcamp-specific intermediary models and mapping follow the same adapter and resolver contracts defined in `SPEC.md` and `adapters.spec.md`, aligned with the factored structure used in `SOUNDCLOUD_SPEC.md`.

Minimal profile traversal model:
- profile result
- album/list result
- track result

Example depth expectations for integration fixtures:
- depth 1 from `https://bandcamp.com/janwirth` includes track `Babylon 47`
- depth 2 expands nested/linked manifest content to all tracks (`+100`) and includes `acid house` album

## 5) Depth Semantics

- `depth 1` (`shallow`): fetch immediate profile-level album/list surface and directly enumerable tracks.
- `depth 2` (`deep`): expand emitted list/album references one additional traversal level and include their tracks.
- Deterministic ordering and deduplication rules are inherited from `SPEC.md` recursive resolution semantics.

## 6) Integration Fixture Inputs (Developer-provided)

Developer provides stable reference URLs for Bandcamp profiles that cover:
- profile feed with albums/tracks
- nested collection behavior if available
- edge cases (empty/near-empty profile feed, duplicates if possible)

These fixtures are part of the integration test set referenced by `SPEC.md`.
