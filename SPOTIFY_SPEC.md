# rememberthename - Spotify Spec (Factored)

## Reference
Input:
- `https://open.spotify.com/collection/tracks`
- `https://open.spotify.com/collection/albums`

Shallow (`depth 1`):
- `collection/tracks`: first saved-tracks page from `/v1/me/tracks`
- `collection/albums`: first saved-albums page from `/v1/me/albums` (album shells only unless eager album-track expansion is explicitly enabled)

Deeper (`depth 2`):
- one additional pagination continuation for saved tracks/albums
- if album-track expansion is enabled, first page of tracks for albums discovered in shallow pass

Expected found tracks:
- Defined by developer-managed integration fixture account.
- Integration tests assert `anchor_fragments` against stable, curated saved tracks/albums for that fixture.

Integration expectation:
- Depth-1 resolution from `collection/tracks` MUST include at least the fixture's ordered prefix anchors.
- `collection/albums` MUST emit at least album collection nodes at depth 1.
- Deeper resolution MUST preserve deterministic ordering and deduplicate by canonical identity.
- Integration tests use `DepthAssertSpec` (see `test/depth_test_spec.gleam`) with Spotify fixture anchors.

## 1) Scope

Supported Spotify input:
- `https://open.spotify.com/collection/tracks`
- `https://open.spotify.com/collection/albums`
- equivalent host variants (`open.spotify.com` with optional locale segment/query parameters)

Out of scope for Spotify input:
- individual track URLs (`/track/<id>`) as root input
- individual album URLs (`/album/<id>`) as root input
- artist/profile URLs as root input
- search
- any untestable behavior

## 2) Source Contract

- Target contract (to be implemented): adapter-specific opaque Spotify profile entry type with constructor.
- Constructor canonicalizes input into one of:
  - `SpotifyCollectionTracks`
  - `SpotifyCollectionAlbums`
- Current resolver architecture requires constructor-created entry roots (no generic public `SourceIdentity` ingestion type).

## 3) URL Parsing Rules

Accepted:
- `https://open.spotify.com/collection/tracks`
- `http://open.spotify.com/collection/tracks`
- `https://open.spotify.com/collection/albums`
- `http://open.spotify.com/collection/albums`
- optional query parameters and locale prefixes allowed and ignored for canonicalization

Canonical parse result:
- constructor stores canonical collection kind (`tracks | albums`)

Rejected as parse failures:
- `https://open.spotify.com/track/<track_id>` as direct root input
- `https://open.spotify.com/album/<album_id>` as direct root input
- `https://open.spotify.com/artist/<artist_id>` as direct root input
- malformed or unknown Spotify paths
- non-Spotify domains

## 4) Auth + API Contract

Spotify collection endpoints are user-scoped and require OAuth access tokens.

Required API behavior:
- adapter reads token from configured runtime auth source (developer-provided for tests)
- missing/expired token must yield typed unresolved/auth failure entries (not process crash)
- HTTP requests target Spotify Web API:
  - saved tracks: `/v1/me/tracks`
  - saved albums: `/v1/me/albums`
  - optional album tracks: `/v1/albums/{id}/tracks`

Headers:
- `Authorization: Bearer <token>`

Pagination:
- follow `next` URLs (or equivalent offset/limit fields) according to requested depth

## 5) Intermediary Model

Spotify-specific intermediary models and mapping follow contracts in `SPEC.md` and `adapters.spec.md`.

Intermediary model:
- `SpotifyLikesTracksSnapshot`
  - `user_scope_id` (`"me"` or stable fixture identifier)
  - `entries: List(SpotifyTrackEntry)`
- `SpotifyLikesAlbumsSnapshot`
  - `user_scope_id` (`"me"` or stable fixture identifier)
  - `entries: List(SpotifyAlbumEntry)`
- `SpotifyTrackEntry`
  - `track_id`
  - `track_title`
  - `artist_name` (primary artist display)
- `SpotifyAlbumEntry`
  - `album_id`
  - `album_title`
  - `artist_name`
  - `tracks: List(SpotifyTrackEntry)` (optional eager expansion)

Mapping:
- Track snapshot maps to one `UnifiedCollection` plus one `UnifiedItem` per track.
- Album snapshot maps to one `UnifiedCollection` plus album child collection references/items according to expansion mode.
- Collection `entries` include emitted item identities in deterministic order.

## 6) Depth Semantics

- `depth 1` (`shallow`):
  - fetch first saved page only for requested collection kind
  - emit immediately enumerable tracks/albums
- `depth 2` (`deep`):
  - fetch one additional continuation page for saved source
  - if album-track expansion is enabled, fetch first track page for newly discovered albums
- `depth 3+`:
  - continue page-wise expansion deterministically until depth budget is exhausted
- `depth all`:
  - exhaust all reachable pagination/album-track nodes

Ordering + dedup:
- preserve Spotify API order within each fetched page
- preserve page order by traversal sequence
- deduplicate by canonical key (`service + source_type + source_id`) per `SPEC.md`

## 7) Integration Fixture Inputs (Developer-provided)

Developer provides stable Spotify fixture context:
- OAuth credentials/token provisioning for test runtime
- fixture account with curated saved tracks and saved albums
- optional known albums with stable track lists for deep traversal assertions

Depth assertions should include:
- minimum item counts by depth
- anchor fragments for known track titles
- stability of early discovered items in deeper results

These fixtures are part of the integration test set referenced by `SPEC.md`.
