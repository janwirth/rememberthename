# rememberthename - Specification (SDD, TDD-first)
Make sure you remember the name of a music track.

Music is fragmented. Music disappears. First step is knowledge


## 1) Product Goal

`rememberthename` is a music-archive ingestion and normalization backend.
It ingests collection profiles from multiple services and exposes a unified API.
Adapter-process details are defined in `adapters.spec.md`.

Primary objective:
- Accept profile URLs via adapter-specific constructors.
- Resolve recursively across collection nodes.
- Normalize into one canonical cross-service data model.

## 2) In Scope

- Input fields: `title`, `artist`, `source_id`, `service`.
- Source parsing and import for collection-level inputs only:
  - Bandcamp profile links (detailed in `BANDCAMP_SPEC.md`)
  - SoundCloud profile links (detailed in `SOUNDCLOUD_SPEC.md`)
  - YouTube playlist URLs
  - Spotify likes (`/collection/tracks`, `/collection/albums`)
- Recursive resolution:
  - Collections can contain items and/or nested collections.
  - Resolver traverses until all reachable nodes are processed.
- Unified API response from resolved data.
- Full automated TDD workflow.
- Backend-only implementation (no Lustre/UI scope).

## 3) Out of Scope

- Individual track sources as input (URLs or rows).
- Media downloads.
- Cover image downloads.
- Search across services.
- Any feature that cannot be validated by automated tests.

## 4) Core Canonical Model

- `Service`: `bandcamp | soundcloud | youtube | spotify`
- `SourceType`: `item | collection`
- Ingestion entry points are adapter-specific opaque types with constructors:
  - `SoundcloudProfile` from `soundcloud_live_expander.soundcloud_profile(profile_url)`
  - `BandcampProfile` from `bandcamp_live_expander.bandcamp_profile(profile_url)`
  - types are not exposed directly; callers use constructor functions only
- `UnifiedItem`:
  - `id` (stable canonical ID)
  - `title`
  - `artist`
  - `service`
  - `source_id`
  - `source_type` (`item`)
- `UnifiedCollection`:
  - `id` (stable canonical ID)
  - `title`
  - `track_ids` (`List(String)`, optional service-emitted list view)
  - `list_ids` (`List(String)`, optional service-emitted nested list references)
  - `service`
  - `source_id`
  - `source_type` (`collection`)
- `UnifiedNode`: `item | collection`

Design constraints:
- Every node is addressable by a deterministic key from `service + source_type + source_id`.
- Duplicates collapse to one canonical node.

## 5) Canonical Intermediary Models Per Adapter

Each adapter returns an intermediary payload first, then a mapper transforms it into canonical nodes.

### 5.1 Bandcamp intermediary

Bandcamp-specific models, parsing rules, and depth semantics are factored into `BANDCAMP_SPEC.md`.

### 5.2 SoundCloud intermediary

SoundCloud-specific models, parsing rules, and tests are factored into `SOUNDCLOUD_SPEC.md`.

### 5.3 YouTube intermediary

- `YoutubePlaylistSnapshot`
  - `playlist_id`
  - `playlist_title`
  - `channel_name`
  - `videos: List(YoutubeVideoEntry)`
- `YoutubeVideoEntry`
  - `video_id`
  - `video_title`
  - `channel_name`

Mapping:
- Profile source type: `collection`
- Snapshot maps to one `UnifiedCollection` + N `UnifiedItem`s.

### 5.4 Spotify intermediary

- `SpotifyLikesTracksSnapshot`
  - `user_scope_id` (or `"me"` placeholder)
  - `entries: List(SpotifyTrackEntry)`
- `SpotifyLikesAlbumsSnapshot`
  - `user_scope_id` (or `"me"` placeholder)
  - `entries: List(SpotifyAlbumEntry)`
- `SpotifyTrackEntry`
  - `track_id`
  - `track_title`
  - `artist_name`
- `SpotifyAlbumEntry`
  - `album_id`
  - `album_title`
  - `artist_name`
  - `tracks: List(SpotifyTrackEntry)` (optional eager expansion)

Mapping:
- Profile source type: `collection`
- Snapshot maps to one logical `UnifiedCollection` plus item nodes (and optional nested album collections).

## 6) Input + Parsing Rules

Accepted input form:
1. URL profile input per adapter; constructor maps URL into an adapter-specific opaque profile type.

Accepted profile shape per service:
- Bandcamp:
  - `bandcamp_profile(<profile_url>) -> BandcampProfile`
- SoundCloud:
  - `soundcloud_profile(<profile_url>) -> SoundcloudProfile`
  - full parsing/mapping rules in `SOUNDCLOUD_SPEC.md`
- YouTube:
  - adapter-specific playlist/profile constructor (to be implemented)
  - playlist URLs (`list=...`) are accepted.
- Spotify:
  - adapter-specific constructor forms for `collection/tracks` and `collection/albums` (to be implemented)

Rejected as invalid input:
- Bandcamp `/track/...`
- SoundCloud `/artist/track` (see `SOUNDCLOUD_SPEC.md`)
- YouTube non-playlist URLs
- Any unsupported URL shape

Invalid/unsupported input:
- Must return a typed parse failure value.

## 7) Recursive Resolution Semantics

Resolver contract:
- Input: one or more adapter-specific profile values created via constructor functions.
- Adapter lookup expands traversal from profile URL roots.
- `item` nodes are collected.
- `collection` nodes enqueue child entries.
- `list_ids` represent nested lists and must be expanded recursively as child collections.
- Adapters may build list state incrementally during traversal, but contract output must emit only full `UnifiedCollection` lists when recursion is complete.
- Resolver is cycle-safe and duplicate-safe via visited set.
- Output:
  - ordered list of resolved unique `UnifiedItem`s
  - list of resolved full `UnifiedCollection` values
  - list of unresolved adapter traversal nodes

Required behavior:
- Deterministic traversal order.
- No infinite recursion.
- Same source visited at most once.

### 7.1 Recursive Queue Function Model

Resolution must be implemented as a recursive function over an explicit queue state (tail-recursive loop).

State shape:
- `queue: List(AdapterNode)` (pending traversal nodes)
- `visited: Set(String)` (node keys)
- `items: Dict(String, UnifiedItem)` (dedup by canonical key)
- `lists: Dict(String, UnifiedCollection)` (dedup by canonical key)
- `unresolved: List(UnresolvedNode)`

Recursive step:
- if `queue` is empty -> return final result
- pop head node
- if visited -> recurse with remaining queue
- else expand node through adapter
- merge emitted items/lists
- append emitted child nodes to queue
- recurse with updated state

This model is implemented by `adapter_core.resolve_profile_url(...)` and is mandatory for:
- nested list traversal
- profile-category traversal
- page `2..n` traversal via emitted page/list nodes

## 8) Unified API

Unified API responsibilities:
- Accept collection profiles.
- Resolve recursively via adapters.
- Return normalized payload:
  - `items`
  - `unresolved`
  - metadata (`requested_sources`, `resolved_count`, `unresolved_count`)

## 9) TDD Strategy (Mandatory)

Test policy:
- Write failing tests before implementation.
- Implement only enough to pass tests.
- Exclude untestable features.

Test layers:
1. Domain tests
   - Source key determinism
   - Profile restrictions (no track URL profiles)
2. Importer tests
   - Valid collection URL parsing
   - Explicit rejection of track URLs
   - Structured row validation
3. Intermediary mapping tests
   - Service snapshot -> canonical node mapping
   - Field normalization guarantees
4. Resolver tests
   - Nested collection traversal
   - Deduplication
   - Cycle handling
   - Unresolved tracking
5. API tests
   - Idempotent repeated requests
   - Unified payload shape

Definition of done:
- All tests pass locally.
- New behavior has automated coverage.
- No scope drift beyond this spec.

## 10) Tech Stack (Barebones)

- Language/runtime: Gleam.
- HTTP transport (current implementation): Erlang external shell calls via `curl` and `jq`, wrapped from Gleam.
- Bandcamp/SoundCloud/YouTube ingestion: deterministic parser/scraper/API logic on top of cached fetch helpers.
- Spotify ingestion: HTTP requests to Spotify Web API only.
- Dependencies: keep minimal, only add packages required by failing tests.

## 11) Development Cycle

Iteration protocol:
- Agent implements strictly from failing tests for the current request.
- Latest test results are fed back into the next agent iteration.
- Agent repeats until tests pass for the request scope.
- No speculative feature work outside active failing tests.

Integration test fixture ownership:
- Developer provides and maintains:
  - reference URLs per supported service (Bandcamp/SoundCloud/YouTube)
  - Spotify profile ID
  - Spotify API key/credentials for test context
- These fixtures form the integration test set and must be stable/replayable where possible.

## 12) Explicit Non-Goals Reminder

- No track-level input support.
- No media file download pipeline.
- No artwork download pipeline.
- No search feature.
