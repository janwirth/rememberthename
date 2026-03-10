# rememberthename - YouTube Spec (Factored)

## Reference
Input: https://youtube.com/playlist?list=PLK7cxKkqBmwmpPoWznuEF-xEljswMRR3V
Track

shallow (depth 1):
first videos from playlist

deeper (depth 2):
same playlist, paginated continuation coverage

Expected found tracks (ordered prefix from list entry point):
- `Angine de poitrine - Sahardnieh` (`CEM`, `4:30`)
- `Bitter` (`Nimo`, `2:53`)
- `Up & Down (More Airplay)` (`Vengaboys`, `3:40`)
- `Wo ich wech bin` (`Dendemann`, `3:39`)
- `BHZ - SCHLIESSE DIE AUGEN (prod. by MotB)` (`BHZ`)

Integration expectation:
- Depth-1 resolution from the reference playlist MUST include at least the ordered prefix above.
- Title matching is strict on normalized text (trim/collapse whitespace).
- Artist/channel matching uses emitted channel/owner text for each video entry.

## 1) Scope

Supported YouTube input:
- playlist URLs (`list=...`)

Out of scope for YouTube input:
- Individual video URLs as root input.
- Channel URLs as root input.
- Search.
- Any untestable behavior.

## 2) Source Contract

- Target contract (to be implemented): adapter-specific opaque playlist/profile entry type with constructor.
- Current resolver architecture requires constructor-created entry roots (no generic public `SourceIdentity` ingestion type).

## 3) URL Parsing Rules

Accepted:
- `https://www.youtube.com/playlist?list=<playlist_id>`
- `http://www.youtube.com/playlist?list=<playlist_id>`
- `https://www.youtube.com/watch?v=<video_id>&list=<playlist_id>` (playlist context URL)
- Optional additional query params allowed and ignored for canonicalization.

Canonical parse result:
- constructor stores canonical `playlist_id`

Rejected as parse failures:
- `https://www.youtube.com/watch?v=<video_id>` without `list`
- `https://www.youtube.com/channel/<channel_id>` as direct root input
- `https://www.youtube.com/@<handle>` as direct root input
- URLs with missing or empty `list` value
- Non-YouTube domains

## 4) Intermediary Model

YouTube-specific intermediary models and mapping follow the same adapter and resolver contracts defined in `SPEC.md` and `adapters.spec.md`.

Intermediary model:
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
- Playlist snapshot maps to one `UnifiedCollection`.
- Each `YoutubeVideoEntry` maps to one `UnifiedItem`.
- Collection `entries` include item identities for all emitted videos.

## 5) Depth Semantics

- `depth 1` (`shallow`): fetch playlist metadata and directly enumerable videos from the first playlist surface.
- `depth 2` (`deep`): fetch one additional continuation level for playlists that require pagination, then merge/deduplicate items.
- Deterministic ordering and deduplication rules are inherited from `SPEC.md` recursive resolution semantics.

## 6) Integration Fixture Inputs (Developer-provided)

Developer provides stable reference URLs for YouTube playlists that cover:
- small playlist (single-page videos)
- long playlist (continuation/paginated videos)
- edge cases (empty/near-empty playlist, duplicate video references if possible)

These fixtures are part of the integration test set referenced by `SPEC.md`.
