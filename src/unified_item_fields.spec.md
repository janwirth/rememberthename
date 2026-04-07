# Unified item field alignment

## Scope

Two behavior fixes for unified export data.

## Requirements

1. **Tuna export includes `file_path`:**
   - When using the Tuna source/adapter, exported unified items include a `file_path` field when known.
   - `file_path` is optional on unified item and may be absent when unavailable.

2. **YouTube artist source fix:**
   - YouTube adapter sets unified item `artist` from the uploading channel.
   - Do not use playlist owner as `artist`.

## Acceptance criteria

- Tuna-exported unified items serialize `file_path` when present.
- Existing non-Tuna adapters remain valid with optional `file_path`.
- YouTube unified items show uploader channel name as `artist`.
