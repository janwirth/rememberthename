# Task: Geldata Entry Normalization Spec

## Goal

Normalize all exported Geldata entries into one stable shape so downstream tooling does not need type-specific handling.

## Canonical Output Shape

Each exported item must contain:

- `title`
- `artist`
- `tags`
- `source_id` in format `<source_type:id>` (example: `file:123`, `soundcloud:abc`)
- `files` with a hard max of 1 resolved file per item
- `rating` encoded as tag `rating<value>`

## Rules

- File resolution is recursive across source relations.
- If multiple file candidates exist, resolve depth-first and keep only the first match.
- `rating<value>` takes precedence over any existing rating-like tag from the original `tags` column.

## Implementation Steps

1. Fetch the full Geldata schema and save it to the filesystem.
2. Analyze all entity types and relations.
3. Identify every path that can resolve to a file (including recursive source chains).
4. Write a `LIMIT 1` query strategy per relevant type/path.
5. Export sample entries for each type and verify canonical output shape.
6. Add tests confirming correct normalization for all covered types.

## Clarifying Questions

1. Should `tags` include or exclude the final `rating<value>` tag (in addition to the dedicated `rating` field intent)?
   -> just the rating field replacing the tag / overriding
2. What should happen when no file can be resolved: `files: []`, `files: null`, or drop item?

- still list, just keep file column null

3. For `source_id`, what is the exact allowed set of `source_type` values?

- check youtube|bandcamp|spotify:id itunes|file:id (if available)/path

4. If multiple ratings exist (column tag, computed relation, or duplicates), what is the deterministic priority order?

- just one rating

5. Should recursive file traversal have a max depth guard to avoid cycles/infinite recursion?

- it's not recursive just like 3 levels deep spread across different types

6. Do we normalize missing text fields to empty string or null (`title`, `artist`)?

- null
