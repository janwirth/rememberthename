# Legacy Library Import Spec

## Goal

Import tracks from a legacy library adapter and resolve them into the current canonical model with measurable overlap against the sources defined in `src/source_specs.gleam`.

This spec is import-focused only (no UI work), and is intentionally compatible with current validation patterns in `src/validate_all.gleam` and `test/depth_test_spec.gleam`.

## Scope

- Add a new legacy resolver path that ingests:
  - metadata tags (typed tag values only)
  - media assets (`cover`, `audio`)
- Normalize imported rows into canonical `UnifiedItem`-compatible fields.
- Compute overlap scores against existing source fixtures.
- Define query and test contracts for repeatable validation.

Out of scope:

- Implementing full adapter code in this spec
- Implementing the final DB schema migration in this spec
- Any UI/TUI feature changes

## Legacy Adapter Input Contract

### Metadata Tags

Legacy metadata is represented as tags only. Tag values are typed:

- `TagBinary(bytes)`
- `TagNumber(Float | Int)`
- `TagString(String)`

Canonical import behavior:

- Keep original tag key and type.
- Preserve raw value exactly (no lossy coercion to string).
- Expose normalized fields for matching:
  - `title` (from configured title tag keys)
  - `artist` (from configured artist tag keys)
  - `legacy_track_id` (if available)

### Media Assets

Each imported item may carry:

- `cover` asset
- `audio` asset

For each asset, importer must persist:

- `asset_kind`: `cover | audio`
- `hash_sha256`: lowercase hex
- `file_extension`: including dot (example: `.jpg`, `.flac`, `.mp3`)
- `byte_size` (optional but recommended)

Hashing requirement:

- Hash bytes as received from legacy adapter (before any transforms).
- Identical bytes across imports must produce identical hash values.

## Overlap Validation Goals

Legacy resolver must be validated by overlap against currently configured sources (`source_specs.all()`).

### Shared Source ID Normalizer (Required)

Add a shared normalization module used by all adapters and the legacy importer before persistence and before overlap checks.

Purpose:

- unify source identifiers into one canonical comparable format
- make overlap-by-source deterministic across heterogeneous adapters
- prevent false negatives caused by url/id formatting differences

Proposed module:

- `source_id_normalizer`
  - input: raw adapter/importer id + service + source_type
  - output: canonical `normalized_source_id`

Canonical output contract:

- lowercase when the service id space is case-insensitive
- trim surrounding whitespace
- collapse known URL forms to id-only value (service-specific)
- strip tracking/query noise that is not identity
- preserve identity-bearing separators (`:`, `/`, `-`, `_`) where needed
- include stable fallback `raw_source_id` when normalization is uncertain

Suggested normalized shape:

- `service`
- `source_type`
- `raw_source_id`
- `normalized_source_id`
- `normalization_version` (for future migration safety)
- `normalization_confidence` (`exact | heuristic`)

Service-level rule examples:

- Spotify:
  - `https://open.spotify.com/track/<id>?si=...` -> `<id>`
  - `spotify:track:<id>` -> `<id>`
- YouTube:
  - `https://www.youtube.com/watch?v=<id>&...` -> `<id>`
  - `https://youtu.be/<id>` -> `<id>`
- SoundCloud/Bandcamp:
  - normalize host + path where ids are URL-derived, removing trailing slash noise
- Legacy importer:
  - if file hash is canonical identity, use that as normalized id fallback
  - otherwise use explicit legacy track id tag when present

Normalizer integration rules:

- adapters/importer must emit both `raw_source_id` and `normalized_source_id`
- overlap matching by id must operate on `normalized_source_id`
- overlap-by-source aggregation keys must use:
  - `service + source_type + normalized_source_id`

### Matching Strategies (run independently and together)

1. Exact match
   - Match key: normalized `title + artist + duration?` (when duration exists)
   - Goal: highest precision baseline
2. Match by ID
   - Match key: `normalized_source_id` (derived from `source_id`, `legacy_track_id`, external ids)
   - Goal: deterministic linking when ids exist
3. Match by Track + Artist Name
   - Match key: normalized (`title`, `artist`)
   - Case-insensitive
   - Whitespace-collapsed
   - Goal: fallback recall strategy

### Overlap Assertion Shape

Define a spec-level assertion record (naming can change in implementation):

- `min_exact_overlap_ratio`
- `min_id_overlap_ratio`
- `min_track_artist_overlap_ratio`
- `min_total_legacy_items`
- `required_anchor_fragments` (same idea as current `anchor_fragments`)
- `min_normalized_id_coverage_ratio` (share of imported rows with confident normalized ids)

Validation pass criteria:

- Imported set size meets minimum expected volume.
- Each overlap strategy meets its threshold.
- Anchor fragments appear in matched output.
- Normalized id coverage is high enough for reliable overlap-by-source metrics.

## Geldata Discovery + Query Plan

Use Geldata to inspect available instances, current schema objects, and run overlap queries.

### Instance Discovery

Run:

- `gel instance list`

Expected outcome:

- enumerate all local/known instances
- use `tuna` as the legacy source DB
- use `fishbone` (or another target) for import validation runs

### Schema Discovery

Run on `tuna` first (source of truth), then on the target import instance:

- `gel -I tuna query "select schema::ObjectType { name } filter .name like 'default::%';"`
- `gel -I tuna query "select schema::Property { name, target: { name } } filter .source.name like 'default::%';"`
- `gel -I <target-instance> query "select schema::ObjectType { name } filter .name like 'default::%';"`
- `gel -I <target-instance> query "select schema::Property { name, target: { name } } filter .source.name like 'default::%';"`

Expected outcome:

- list source-side and target-side object types relevant for tracks/assets/tags/import sessions
- verify required fields exist for matching and hashing assertions on both sides

### Query Set (Spec-Level)

1. Imported item count
   - count imported legacy tracks for a run/session
2. Asset integrity
   - ensure every `audio`/`cover` asset has non-empty hash + extension
3. Match counts per strategy
   - exact strategy count
   - id strategy count
   - track+artist strategy count
4. Overlap ratios
   - strategy count / total imported
5. Normalizer coverage
   - imported rows with `normalized_source_id`
   - imported rows with `normalization_confidence = exact`

Representative query skeletons (adapt names to final schema):

```edgeql
with
  imported := (select default::LegacyTrack filter .import_run_id = <uuid>$run_id)
select count(imported);
```

```edgeql
select default::LegacyAsset {
  id,
  kind,
  hash_sha256,
  file_extension
}
filter .import_run_id = <uuid>$run_id
  and (.hash_sha256 = '' or .file_extension = '');
```

```edgeql
with
  imported := (select default::LegacyTrack filter .import_run_id = <uuid>$run_id),
  matched := (
    select imported
    filter exists .matched_exact_target
  )
select {
  imported_total := count(imported),
  matched_total := count(matched),
  overlap_ratio := <float64>count(matched) / <float64>count(imported)
};
```

## Test Plan (modeled after current validation flow)

Mirror existing validation cadence (`warmup -> depth1 -> depth2 -> all`) where applicable, then add overlap assertions.

### Required Tests

1. Input normalization
   - parses binary/number/string tags without coercion loss
   - extracts normalized `title`/`artist` fields from configured tag keys
2. Asset hashing
   - computes deterministic SHA-256 hashes
   - preserves file extension for both cover and audio
3. Resolver progression checks
   - imported counts are monotonic across resolver depth modes (if depth modes apply)
   - unresolved tracking is stable/non-regressive
4. Overlap strategy checks
   - exact match reaches configured minimum ratio
   - id match reaches configured minimum ratio
   - track+artist match reaches configured minimum ratio
5. Anchor checks
   - required anchor fragments appear in overlap outputs
6. Source id normalizer checks
   - known source id variants collapse to one `normalized_source_id`
   - id overlap uses normalized ids only
   - overlap-by-source grouping is stable across adapter/importer paths
   - normalizer coverage ratio reaches configured minimum

### Suggested Shared Helpers

Speculate two reusable modules to avoid duplication across adapters:

- `source_quality_validator`
  - owns assertion types and pass/fail evaluation
  - reusable for current source validation and legacy overlap validation
- `integrator`
  - owns canonical normalization + strategy orchestration
  - returns typed overlap metrics by strategy for validators/tests
- `source_id_normalizer`
  - owns service-specific id canonicalization rules
  - provides typed normalization result + confidence + version

## Deliverables from This Spec

- New legacy import resolver contract
- Typed metadata + asset integrity requirements
- Three-strategy overlap validation model
- Geldata discovery/query workflow
- Test checklist aligned with existing validation patterns
