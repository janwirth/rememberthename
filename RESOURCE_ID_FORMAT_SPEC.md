# Resource ID Format Spec

## Goal

Define one canonical resource ID format that encodes:

- origin (`platform` vs `local import`)
- provider/service
- provider-specific resource type
- provider-specific ID

This ID is for deterministic identity and dedupe across adapters.

## Scope

In scope:

- remote platform resources (`spotify`, `youtube`, `soundcloud`, `bandcamp`, `itunes`)
- local-imported resources (`file`, `legacy`, future local adapters)
- normalization and compatibility rules

Out of scope:

- changing adapter traversal logic
- UI behavior

## Canonical Shape

Canonical ID is a string:

`rid:v1:<origin>:<service>:<resource_type>:<encoded_id>`

Segments:

- `rid` fixed prefix
- `v1` format version
- `origin` one of:
  - `platform`
  - `local`
- `service` one of:
  - `spotify`
  - `youtube`
  - `soundcloud`
  - `bandcamp`
  - `itunes`
  - `file`
  - `legacy`
- `resource_type` examples:
  - `track`
  - `collection`
  - `artist`
  - `path`
  - `persistent_track`
- `encoded_id` provider-specific ID payload, normalized and percent-encoded when needed

## Normalization Rules

Before composing `rid:v1:...`:

1. Trim leading/trailing whitespace.
2. Lowercase service names and resource types.
3. Apply service-specific canonicalization for ID payload.
4. Preserve identity-bearing characters in payload.
5. Percent-encode `:` in payload as `%3A` to keep segment boundaries stable.

### Service-Specific Payload Canonicalization

- `spotify:track`
  - `https://open.spotify.com/track/<id>?...` -> `<id>`
  - `spotify:track:<id>` -> `<id>`
- `youtube:track`
  - `https://www.youtube.com/watch?v=<id>&...` -> `<id>`
  - `https://youtu.be/<id>` -> `<id>`
- `soundcloud:track`
  - canonical payload is normalized host+path, no trailing slash
- `bandcamp:track`
  - canonical payload is track numeric ID (string form) when available; otherwise normalized host+path
- `itunes:track`
  - canonical payload is `itunes_track_id` when present
- `itunes:persistent_track`
  - canonical payload is `itunes_persistent_track_id`
- `file:path` (local imports)
  - canonical payload is `device=<device_id>|path=<normalized_absolute_path>`
  - path separators normalized to `/`
  - repeated `/` collapsed
- `legacy:track` (local imports)
  - canonical payload is legacy stable ID (or content hash fallback)

## Examples

- Spotify track:
  - `rid:v1:platform:spotify:track:5n4uWPmWMbg4XLzrkck25e`
- YouTube track:
  - `rid:v1:platform:youtube:track:nPWrkoxiafI`
- SoundCloud track (URL-derived):
  - `rid:v1:platform:soundcloud:track:soundcloud.com/artist-name/track-name`
- Bandcamp track:
  - `rid:v1:platform:bandcamp:track:1234567890`
- iTunes persistent track:
  - `rid:v1:platform:itunes:persistent_track:4A8B23D1E9`
- Local file import:
  - `rid:v1:local:file:path:device=mbp-jan-01|path=/Users/jan/music/folder/track.flac`
- Legacy local import:
  - `rid:v1:local:legacy:track:sha256_2f8d9c...`

## Required Companion Fields

Each canonical item should carry both:

- `raw_source_id` (verbatim, adapter-provided)
- `resource_id` (this canonical `rid:v1:...`)

`raw_source_id` is for audit/debug; `resource_id` is for identity and joins.

## Collision + Dedupe

Primary dedupe key:

- exact `resource_id`

If two records share `resource_id`, they represent the same logical source resource and must collapse to one canonical node.

## Versioning

- Format version is embedded as `v1`.
- Any breaking segment or normalization change requires `v2` and a migration strategy.
- Non-breaking additions (new `service`, new `resource_type`) stay in `v1`.

## Validation Contract

A `resource_id` is valid if:

1. It has exactly 6 segments separated by `:`.
2. Prefix is `rid`.
3. Version is a supported version (`v1`).
4. `origin`, `service`, and `resource_type` are non-empty.
5. `encoded_id` is non-empty after normalization.

Invalid IDs must be rejected in tests and surfaced as failed normalization results.

## Local Device Identity (Required)

For synced local libraries, `local:file:path` IDs must carry a device identifier so providers can be traced across machines.

Local file payload shape:

- `device=<device_id>|path=<normalized_absolute_path>`

Rules:

- `device_id` is required and non-empty.
- `path` is required and non-empty.
- Parser must reject `rid:v1:local:file:path:<payload>` when payload is not in this shape.
