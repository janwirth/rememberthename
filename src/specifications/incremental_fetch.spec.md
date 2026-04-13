# Incremental Fetch Specification

## Problem
Fetching take very longer. User no want wait.

## Goal
 Skip full recursion; fetch only to anchor, then sub-items below.

---

## Data Types
No extra datatype. just extra field on the source root.

### Entry
```gleam
pub fn fetch_incremental(
  root: source_root.SourceRoot,  // Has incremental_opts with fetcher_newer_than is a resource_id.gleam type string
  cache_mode: cache.CacheMode,
) -> Result(IncrementalResult, String)
```

### For Single-Feed (Spotify, SoundCloud, YouTube, Bandcamp)
1. Fetch from entry point
2. Stop at anchor, **not before**
3. Recursively fetch sub-items (playlists → tracks) as before

Tuna supports no resume. Always fetch full.


---

## Stopping Conditions

1. **Anchor found in current batch** → continue processing batch, mark feed `anchor_reached: true`
2. **Feed paginated items exhausted** → stop feed, `last_token: None`
4. **Error in feed** → skip feed, continue others (Bandcamp resilience)

---

## Error Handling
- Anchor not found → return all items fetched, caller decides repeat
   -> anchor_found Result(String (e.g. "anchor X found on page Y" or "No anchor specified"), String "Anchor not found")

---

## SourceRoot Extension

Add incremental opts as attribute on `SourceRoot`:
```gleam
pub type SourceRoot {
  // ... existing fields ...
  fetch_newer_than: ResourceId,
}
```
## CLI Integration
```
cli fetch <source> --newer-than <unified_id>
```
Output as before

---

## Open Questions

1. **Anchor not found** — fetch forever or hard limit? Max pages to scan?
   - no hard limit, see error behavior
2. **Sub-items anchor** — playlists→tracks also stop at anchor, or always full recursion?
   - no stop below level 0
3. **Resume semantics** — "Tuna supports no resume. Always fetch full" mean single call must get all, or full recursion after anchor?
   - don't change tuna that's it
5. **fetch_newer_than field** — always required or optional (None = full fetch)?
   - optional, none = full fetch / init
6. **Partial caching** — cache items before anchor, reuse next run?
   - no cache in incremental mode, cache just for speed in dev
7. **Result structure** — how encode `anchor_reached` state in `IncrementalResult`?
   - no incremental result. Just full result: {items, lists, anchor_found: Ok|err}. anchor found in JSOn export is just text, no type encoded.