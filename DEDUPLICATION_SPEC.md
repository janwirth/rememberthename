# rememberthename - Deduplication Bucket Spec

## Goal

Define how tracks from different adapters are deduplicated into canonical buckets.

## In Scope

- Ingest track items from all supported sources/adapters
- Insert each incoming track into exactly one bucket
- Create a new bucket when no existing bucket matches
- Store canonical bucket metadata (`title`, `artist`)
- Store source links per bucket (adapter + source id references)
- Store asset references per bucket (cover/audio), with local and remote forms

## Out of Scope

- Audio fingerprinting
- ML similarity scoring
- Downloading/transcoding assets
- Conflict resolution UI

## Terms

- `TrackItem`: one normalized input track from one adapter.
- `Bucket`: deduplicated canonical group representing one logical song.
- `SourceLink`: reference to one source-specific track instance.
- `AssetRef`: reference to media for a bucket (`cover` or `audio`).

## Canonical Bucket Model

Each bucket MUST contain:

- `bucket_id: String` (stable internal id)
- `title: String` (canonical title)
- `artist: String` (canonical artist)
- `source_links: List(SourceLink)` (at least 1 link)
- `assets: List(AssetRef)` (0..n assets)
- `created_at`
- `updated_at`

`SourceLink` fields:

- `adapter: String` (e.g. `spotify`, `youtube`, `soundcloud`, `bandcamp`, `file`, `itunes`)
- `source_id: String` (adapter-normalized source id)
- `raw_source_id: String` (optional if available)
- `track_title: String` (as received from source)
- `track_artist: String` (as received from source)
- `inserted_at`

`AssetRef` fields:

- `asset_type: cover | audio`
- `location_type: local | remote`
- `uri: String`
- `provider: String` (`device` for local, `s3` for remote, extensible)
- `content_hash: String` (optional)
- `metadata: Map(String, String)` (optional)

## Asset Location Contract

### Local asset refs

Local refs represent on-device media and MUST encode device identity + path:

- `location_type = local`
- `provider = device`
- `uri` format: `device://<device_id>/<absolute_or_scoped_path>`

Example:

- `device://mbp-jw-01/Users/jan/Music/library/Some Track.wav`

### Remote asset refs

Remote refs represent object storage pointers:

- `location_type = remote`
- `provider = s3`
- `uri` format: `s3://<bucket>/<key>` or HTTPS equivalent

Examples:

- `s3://rememberthename-audio/tracks/abc123.flac`
- `https://cdn.example.com/audio/tracks/abc123.flac`

## Matching Rules

Buckets are built through deterministic matching rules evaluated in order.

### Rule order (mandatory)

1. Exact source-id match
2. Strong normalized metadata match
3. Weak metadata match with guardrails
4. No match -> create new bucket

### Rule 1: exact source-id match

A track MUST match an existing bucket if any `SourceLink` already has:

- same `adapter`
- same normalized `source_id`

This has highest priority and short-circuits other rules.

### Rule 2: strong normalized metadata match

A track MAY match exactly one existing bucket when:

- normalized incoming `title` equals bucket `title` (normalized form), and
- normalized incoming `artist` equals bucket `artist` (normalized form)

If multiple candidate buckets satisfy this, insertion MUST be treated as ambiguous (see ambiguity handling).

### Rule 3: weak metadata match with guardrails

Weak match can be used only if Rule 1 and Rule 2 fail, for example:

- title exact + artist prefix/alias match, or
- title exact + missing artist on one side

Guardrails:

- weak matching MUST never merge two buckets that already contain different links for the same adapter with different `source_id`s
- weak matching MUST produce at most one candidate bucket; otherwise ambiguous

### Rule 4: create new bucket

If no unambiguous match exists, create a new bucket with:

- canonical `title`/`artist` derived from incoming track
- one `SourceLink` from incoming track
- any attached `AssetRef`s from incoming track

## Insert Algorithm

For each incoming `TrackItem`:

1. Normalize source id and text fields (`title`, `artist`)
2. Evaluate matching rules in order
3. If exactly one match:
   - append `SourceLink` if not already present
   - merge/add non-duplicate `AssetRef`s
   - update bucket `updated_at`
4. If no match:
   - create bucket
5. If ambiguous match:
   - do not auto-merge
   - emit ambiguity record for review/reprocessing

## Canonical Field Selection

When a track is merged into an existing bucket:

- Existing bucket `title`/`artist` stay stable by default.
- Canonical fields MAY be upgraded only when configured strategy allows it (e.g. prefer non-empty artist over empty artist).
- Canonical changes MUST be deterministic and reproducible.

## Deduplication Guarantees

- Every inserted track ends in exactly one state:
  - matched to one bucket, or
  - created a new bucket, or
  - flagged ambiguous (no merge done)
- No bucket contains duplicate `SourceLink` entries with same (`adapter`, `source_id`)
- Processing same input set repeatedly is idempotent
- Matching is deterministic for same input order and configuration

## Required Tests

- inserts first track and creates a bucket
- matches second track by exact source id into existing bucket
- matches by strong normalized `title+artist`
- creates new bucket when no rule matches
- rejects ambiguous multi-candidate metadata matches
- prevents duplicate source links in one bucket
- stores local asset refs with `device://<device_id>/<path>`
- stores remote asset refs with `s3://...` or HTTPS URI
- keeps canonical bucket fields stable across merges
- rerun of same inputs is idempotent
