# rememberthename - SoundCloud Spec (Factored)

Reference: https://soundcloud.com/tungstenselects

## 1) Scope

Supported SoundCloud input:
- profile URLs

Out of scope for SoundCloud input:
- Individual track URLs (`/artist/track`).
- Search.
- Any untestable behavior.

## 2) Source Contract

- `service`: `soundcloud`
- `source_type`: `collection` for profile roots, `item | collection` for resolved entries
- `source_id`: deterministic ID derived from parsed SoundCloud URL identity

Accepted seed shape:
- `{ service: soundcloud, source_type: collection, source_id: <profile_id> }`

Rejected:
- Any seed where `service != soundcloud`.
- Any seed missing `source_id`.

## 3) URL Parsing Rules

Accepted:
- `https://soundcloud.com/<profile_slug>`
- `http://soundcloud.com/<profile_slug>`
- Optional query params allowed and ignored for canonicalization.

Canonical parse result:
- `service = soundcloud`
- `source_type = collection`
- `source_id = <profile_slug>`

Rejected as parse failures:
- `https://soundcloud.com/<artist>/<track>`
- URLs with missing or empty profile slug
- Non-SoundCloud domains

## 4) Intermediary Model

- `SoundcloudSetSnapshot`
  - `set_id`
  - `set_title`
  - `owner_name`
  - `entries: List(SoundcloudEntry)`
- `SoundcloudEntry`
  - `entry_type: track | set`
  - `entry_id`
  - `title`
  - `artist_or_owner`

Mapping requirements:
- One profile snapshot maps to:
  - one root `UnifiedCollection` for the profile feed
  - N child nodes from resolved entries
- `entry_type = track` maps to `UnifiedItem` with:
  - `service = soundcloud`
  - `source_type = item`
  - `source_id = <entry_id>`
- `entry_type = set` maps to child `UnifiedCollection` with:
  - `service = soundcloud`
  - `source_type = collection`
  - `source_id = <entry_id>`

## 5) Normalization Rules

- Deterministic key format remains `service + source_type + source_id`.
- SoundCloud titles/artists are preserved as fetched except for required trim normalization.
- Duplicate entries collapse during recursive resolver traversal.
- Nested set cycles are permitted in source data but must terminate in resolver via visited set.

## 6) Cache + Resolver Expectations

- Cache key format: `soundcloud:<source_type>:<source_id>`.
- Missing SoundCloud nodes are returned in global `unresolved`.
- Resolver order must be deterministic for SoundCloud entry expansion.

## 7) TDD Requirements (SoundCloud)

Required automated tests:
- Parser accepts valid `/sets/...` URLs.
- Parser rejects `/artist/track` and non-set shapes.
- Snapshot -> canonical mapping for:
  - set with track entries
  - set with nested set entries
  - mixed entries
- Resolver tests for:
  - nested SoundCloud sets
  - duplicate entries
  - cycle handling
  - unresolved missing child set/item

No SoundCloud feature is in scope unless covered by automated tests.

## 8) Integration Fixture Inputs (Developer-provided)

Developer provides stable reference URLs for SoundCloud sets that cover:
- Flat set (tracks only)
- Nested set behavior if available
- Edge cases (empty/near-empty set, duplicate-like entries if possible)

These fixtures are part of the integration test set referenced by `SPEC.md`.
