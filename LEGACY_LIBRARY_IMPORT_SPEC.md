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

### Matching Strategies (run independently and together)

1. Exact match
   - Match key: normalized `title + artist + duration?` (when duration exists)
   - Goal: highest precision baseline
2. Match by ID
   - Match key: stable source/legacy ids (`source_id`, `legacy_track_id`, external ids)
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

Validation pass criteria:

- Imported set size meets minimum expected volume.
- Each overlap strategy meets its threshold.
- Anchor fragments appear in matched output.

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

### Suggested Shared Helpers

Speculate two reusable modules to avoid duplication across adapters:

- `source_quality_validator`
  - owns assertion types and pass/fail evaluation
  - reusable for current source validation and legacy overlap validation
- `integrator`
  - owns canonical normalization + strategy orchestration
  - returns typed overlap metrics by strategy for validators/tests

## Deliverables from This Spec

- New legacy import resolver contract
- Typed metadata + asset integrity requirements
- Three-strategy overlap validation model
- Geldata discovery/query workflow
- Test checklist aligned with existing validation patterns
