# rememberthename - Services Spec

It's easy to get lost. We knowingly contract the scope to an extreme.
NO media fetching
NO searching
Just the minimal track metadata as a list - smallest common denominator.
More metadata later

Just profiles that give you track, artist and a backlink

## 1) Scope

Each provider runs as an independent long-running process:
- `bandcamp_service`
- `soundcloud_service`
- `youtube_service`
- `spotify_service`

Processes resolve only their own service data and publish progress updates while running.

## 2) Input

- Only profile-level seeds are accepted.
- Track URLs are not valid seeds.
- Seed identity is:
  - `service`
  - `source_type`
  - `source_id`

## 3) Resolution Modes

- `shallow`: first fetch pass; return immediately available collections/items.
- `step`: iterative mode; each step can accept prior step output and continue resolution.
- `deep`: run step-wise resolution until required detail is complete. Flat items and deep tree of source

Required output detail:
- collection metadata
- item metadata (currently only track) (`title`, `artist`, `service`, `source_id`)
- no media bytes, no artwork bytes

## 4) Update Stream

Per-job event stream is minimal and ordered:
- `started` (debug/context message)
- `progress` (status text + optional item payload)
- `completed` (final stats)

## 5) Internally

Structural recursion, in-order, no parallelism beyond service level.


## 6) Testing & Evolution

test methods in progressive depth
Build resolution methods on top of test harness.

Test data required before starting

input seed: profile URL
