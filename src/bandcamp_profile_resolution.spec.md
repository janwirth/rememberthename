# Bandcamp profile — lists and album tracks

## Scope

Bandcamp **profile** roots only (`https://bandcamp.com/<slug>`): fan **collection** (purchased) via `collection_items` and **wishlist** (liked) via `wishlist_items`. Standalone album or track URLs as roots stay out of scope.

## Requirements

1. **Tracks from album rows (both feeds)**  
   When a fan API row is an **album** (not a single-track line item), resolution must include **each constituent track** as a normal `UnifiedItem`, whether the row came from the **collection** or **wishlist** feed. Expansion semantics match per-album HTML track extraction used today for `ListNode` album expansion.

2. **List output for purchased albums**  
   For each **album** row in the **collection** (purchased) feed, the resolve / saved artifact must include a **`UnifiedCollection`** in the **`collections`** array (`fetch_result_json` / `collection_json` in `cli/export_json.gleam`): **`title`** is the album title, **`track_ids`** lists the **`id`** of each expanded track from that album, **`service`** `bandcamp`, **`source_type`** `"collection"` (aligned with SoundCloud / YouTube list payloads). Wishlist-only albums are **not** required to produce a `collections` row.

## Acceptance criteria

**Collection (purchased)**

- **Digi Spa EP** — present as a **collection** entry (purchased album in list output).
- **Nord dab** — present as an **extracted track** (`tracks` / unified item, typically from an expanded purchased album).

**Wishlist (likes)**

- **The Frightnrs - Nothing More To Say** — liked **album** row must expand; constituent tracks appear as **`UnifiedItem`**s (list / `collections` row not required for wishlist-only albums).
- **All My Tears** — present as an **extracted track** from that liked album.

Album expansion must not be limited to a fixed small number of albums per API page when the fan has more album rows (no arbitrary per-page cap that drops the rest).

## Non-goals

Changing `SourceRoot`, registry keys, or CLI source selection — adapter behavior and on-disk `tracks` + `collections` shape only.
