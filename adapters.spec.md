# rememberthename - Adapters Spec

It's easy to get lost. We knowingly contract the scope to an extreme.
NO media fetching
NO searching
Just the minimal track metadata as a list - smallest common denominator.
More metadata later

Just profiles that give you track, artist and a backlink

## 1) Scope

Each provider runs as an independent long-running adapter:
- `bandcamp_adapter`
- `soundcloud_adapter`
- `youtube_adapter`
- `spotify_adapter`

Adapters resolve only their own provider data and publish progress updates while running.

## 2) Input

- Only service-specific collection-level `SourceIdentity` inputs are accepted.
- Track URLs are not valid inputs.
- `SourceIdentity` is defined in `SPEC.md` and used unchanged here:
  - `service`
  - `source_type`
  - `source_id`
- accepted source shapes are defined per service in `SPEC.md`:
  - bandcamp album source
  - soundcloud profile source
  - youtube playlist source
  - spotify collection sources (`collection/tracks`, `collection/albums`)

## 3) Resolution Modes

- `shallow`: first fetch pass; return immediately available collections/items.
- `step`: iterative mode; each step can accept prior step output and continue resolution.
- `deep`: run step-wise resolution until required detail is complete. Flat items and deep tree of source

Required output detail:
- collection metadata
- item metadata (currently only track) (`title`, `artist`, `service`, `source_type`, `source_id`)
- list metadata (`title`, `track_ids`, `list_ids`, `service`, `source_type`, `source_id`)
- no media bytes, no artwork bytes

## 4) Update Stream

Per-job event stream is minimal and ordered:
- `started` (debug/context message)
- `progress` (status text + optional payload: item or list; list payload can include `track_ids` and `list_ids`)
- `completed` (final stats)

## 5) Internally

Structural recursion, in-order, no parallelism beyond adapter level.

## 6) Testing & Evolution

test methods in progressive depth
Build resolution methods on top of test harness.

Test data required before starting:

- input source: URL/profile mapped to service-specific collection `SourceIdentity`
