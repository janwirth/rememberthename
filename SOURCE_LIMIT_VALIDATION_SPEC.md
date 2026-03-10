# rememberthename - Source Limit + Validation Spec

## Goal

Define how unified tracks are validated, ordered, and limited per source.

## In Scope

- Per-source item limits
- Artist-presence validation with highlight behavior
- Numeric `order` semantics

## Canonical Track Requirements

Each track item must include:

- `title: String`
- `artist: String`
- `service: Service`
- `source_id: String`
- `order: Int | Float` (always numeric; may be rank or timestamp)

## Validation Rules

- `artist` is required for `valid` status.
- If `artist` is empty/missing, item is marked `missing_artist`.
- `missing_artist` items are still returned, but MUST be highlighted in visual output.
- Highlight contract:
  - terminal: add marker `(!missing artist)` next to the item
  - structured output: include `validation: missing_artist`

## Ordering Rules

- Sort tracks by `order` ascending (lower value first).
- `order` is treated as an opaque numeric key:
  - not required to be contiguous
  - not required to start at `0` or `1`
  - can represent timestamp values
- Tie-breaker for deterministic output:
  1. `service`
  2. `source_id`

## Per-Source Limit Rules

- Limit is applied per source/service bucket after ordering.
- Config shape:
  - `source_limits: Dict(Service, Int)`
- Limit semantics:
  - missing source key => unlimited
  - `n <= 0` => return zero items for that source
  - `n > 0` => keep first `n` ordered items for that source

## Processing Sequence (Mandatory)

1. Normalize incoming tracks to canonical shape (including `order`)
2. Validate required fields (`artist`)
3. Sort deterministically by `order` + tie-breakers
4. Apply per-source limits
5. Render/export with highlight metadata for validation failures

## Required Tests

- keeps max `n` per source after sorting
- treats timestamp-like `order` values as valid numeric order
- does not assume index-like sequence for `order`
- marks missing artist as `missing_artist`
- includes missing-artist items in output with highlight marker
