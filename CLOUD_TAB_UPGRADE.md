# Cloud Tab Upgrade

## Spotify fetch
- Fetch liked albums → index in main pool
- Fetch playlists → store for UI, don't index
- Auto-include own playlists (`owner.id == me`), incl. collaborative
- Followed/liked playlists (other owners) → excluded by default, user toggles in
- Albums never re-fetched (no incremental needed — dedup is moot, albums can't be in playlists)

## Incremental sync (lists only)
- Use Spotify's `after` cursor param (last track anchor) per included playlist
- Upsert on sync; fall back to full fetch if anchor invalid
- Separate "Sync" button (incremental upsert) alongside existing "Fetch" button (full)

## Cloud tab UI
- New column right of tracks: all Spotify playlists + Bandcamp albums
- Toggle per row: include / exclude from next fetch
- State stored locally

## Open questions
- Bandcamp albums column: same toggle UX as Spotify playlists? What's the fetch mechanism?
