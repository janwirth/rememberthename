# Added-At Timestamps (Best Effort)

Goal:
- get added-at timestamps where available from every adapter.

Rule:
- adapters should extract added-at when the source exposes it.
- if unavailable, keep the track and set added-at to missing (do not fail ingestion).
- this is **not** track upload/release date; this is when track was added to library/collection.

Normalization:
- store as UTC ISO-8601 when parseable.
- if raw value exists but cannot be normalized, keep it missing for now.
- if source gives date-only, normalize to midnight UTC (`T00:00:00Z`).

Merge rule:
- when duplicate canonical tracks have different added-at values, keep **earliest**.

Source notes (from research):
- SoundCloud: collection entry `created_at` is added-to-library timestamp.
- Bandcamp: `added` value like `"19 Nov 2025 17:20:23 GMT"` is added timestamp.
- YouTube: scraper path may not expose it; use YouTube Data API where `snippet.publishedAt` on playlist item is when video was added to playlist/library context.
- Spotify: use API added timestamp field for saved tracks/items (confirm exact field path in code/tests).
- Tuna: use source `created_at` (confirm exact schema field path).

## TODO

- [ ] Add `added_at` to canonical `UnifiedItem` (optional/missing allowed)
- [ ] Bandcamp: map `added` -> `added_at` + tests
- [ ] SoundCloud: map collection `created_at` -> `added_at` + tests
- [ ] YouTube: fetch playlist-item `snippet.publishedAt` via Data API -> `added_at` + tests
- [ ] Spotify: map saved-item added timestamp -> `added_at` + tests
- [ ] Tuna: map `created_at` -> `added_at` + tests
- [ ] Ensure API/export include `added_at` when present
- [ ] Add resolver test: duplicate-track merge keeps earliest added-at

## Open Questions

- Confirm exact Tuna schema path for `created_at`.
- Confirm exact Spotify API field(s) for added timestamp in all supported flows.
