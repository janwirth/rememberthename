# UnifiedItem — required `cover_url`

## Scope

The canonical track row `core.UnifiedItem` in `src/adapters/core.gleam` and every code path that **constructs** or **normalizes** items for export (live adapters, Tuna import, fakes/fixtures, `track_item` / helpers).

## Requirements

1. **Field**  
   Add **`cover_url: String`** to `UnifiedItem`. It is **required** on the type: no `Option`, no omission at construction sites.

2. **Value**  
   `cover_url` must be a **non-empty** absolute `http` or `https` URL pointing at the item’s cover/thumbnail image as offered by that source (API field, oEmbed, Open Graph, embed JSON, etc.). Normalization rules (trim, scheme, redirects) are implementation details; the stored value is the URL string the pipeline uses for display or downstream tools.

3. **Extractors**  
   Every service extractor that emits `UnifiedItem` must **obtain and set** `cover_url` from that service’s data in the same pass that produces title/artist/id (no “later enrichment” phase required by this spec). Test doubles and JSON fixtures that build `UnifiedItem` must include a valid example URL.

4. **When no artwork exists**  
   If a source truly exposes no image for an item, behavior is **either** fail that item’s parse/expand with an existing error path **or** document a single project-wide fallback URL — pick one approach in implementation; ad-hoc empty strings are not allowed.

## Acceptance criteria

- `gleam test` passes with `UnifiedItem` updated everywhere constructors/destructuring appear.
- At least one integration or fake test per major adapter asserts `cover_url` is non-empty and looks like `http(s)://…` for a known fixture item.

## Non-goals

- Downloading image bytes or caching blobs (URL only).  
- Adding `cover_url` to `UnifiedCollection` unless a separate spec requires it.  
- Changing traversal depth, dedupe keys, or CLI surface beyond what follows from the new field.
