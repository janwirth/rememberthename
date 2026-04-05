# `fetch_ops` — spec

## Intent

- **Small surface:** `fetch`, `fetch_and_save_json`, nothing else that looks like CLI internals. **Purge CSV** project-wide.
- **Direct resolve:** `SourceRoot` + `cache_mode` only inside core fetch — no selector strings, no multi-source merge. Orchestration lives in CLI.
- **No `.env` in `fetch_ops`:** credentials are always passed in (CLI, DB, …). **`spotify_ensure_auth`** is orchestration/CLI only, then callers build `SpotifyRoot`.
- **Validation is dev-only:** assertion runs (e.g. `validate_all`, `SourceAssertSpec` checks) operate on **saved CLI result JSON**, not on in-memory `fetch` results. Normal **`fetch` / `fetch_and_save_json` do not run validation** — that stays a separate dev tool / command.

## `SourceRoot`

Fetch params only — no assertions, no `source_limit` (those stay on `SourceAssertSpec` / verification).

- Shared: `SourceTimingSpec` (Bandcamp), `DepthMode` (`adapters/core`), `SpotifyCredentials` passed by caller.
- **Spotify:** likes/library from **authenticated session** — no `user_or_collection_url` on the root.
- **YouTube:** `playlist_url` + `google_cloud_api_key`; orchestration may **ping the API** to verify the key.
- **Tuna:** legacy local EdgeDB mirror; sentinel `entry_point` only if `track_view.adapter_id_for_source` still needs a string.

```gleam
pub type SourceRoot {
  BandcampRoot(profile_url: String, depth: DepthMode, timing: SourceTimingSpec)
  SoundcloudRoot(entry_point: String, depth: DepthMode)
  SpotifyRoot(credentials: SpotifyCredentials, depth: DepthMode)
  YoutubeRoot(playlist_url: String, google_cloud_api_key: String)
  TunaRoot
}
```

Derive adapter / `(key, entry_point)` by pattern match on the variant, not a duplicate `key` field on the record.

## Adapter functions (implementation)

- **`fetch` is a thin dispatcher:** `case root { BandcampRoot(...) -> ... }`, each arm calls **exactly one adapter entrypoint**.
- **Each adapter exposes a function whose parameters match the variant’s constructor fields** — no parallel “options bag” that duplicates those names. Examples:
  - `bandcamp_fetch(profile_url, depth, timing, cache_mode, on_update, …)` (only add parameters if they are **not** on `SourceRoot` but are shared across adapters, e.g. `cache_mode`, `progress_callback`; keep the list short and identical across adapters where possible).
  - `soundcloud_fetch(entry_point, depth, …)`
  - `spotify_fetch(credentials, depth, …)`
  - `youtube_fetch(playlist_url, google_cloud_api_key, …)`
  - `tuna_fetch(…)` — **no payload fields** on `TunaRoot`; signature is shared-context only (or empty beyond shared args).
- **Implementation lives next to the adapter** (existing expander/resolve modules), not buried inside a giant `fetch_ops` `case`. `fetch_ops` only matches and forwards.

## Registry

`Dict(String, #(SourceRoot, SourceAssertSpec))` keyed by `selector_key` (`"bandcamp"`, …). **Order irrelevant** (small set); CLI may use `dict.to_list` or similar.

- **`fetch` / `fetch_and_save_json`** receive **`SourceRoot` only** (plus cache mode). Verification is **not** an argument to fetch.
- Caps like `source_limit` live on **`SourceAssertSpec`**, used when a **dev tool loads the written JSON** and runs checks — not during fetch.

## API

| Function | Role |
|----------|------|
| `fetch(root, cache_mode, progress_callback)` | Resolve; return data using **`core.UnifiedItem`** (+ metadata for dates / adapter id as needed). No required JSON write. |
| `fetch_and_save_json(root, cache_mode)` | Same resolve, then write JSON. **Paths/names derived only from `SourceRoot`** (no legacy `cli_result_*` compat). Thin wrapper: `fetch` + write + shared path helper. **No validation** — dev tools read this file later. |

**Progress:** `progress_callback : fn(String) -> Nil` — **arbitrary adapter strings for now**; **do not export log formatters** from `fetch_ops`.

**Persistence:** JSON only. Saved JSON should be rich enough for **`validate_all`**: **tracks plus lists/albums that reference tracks** (not a flat track-only dump if that breaks checks).

**Testing helper:** a **`with_root`-style helper** (exact name TBD) that **inspects the container / root** so tests can use **shallow depth or small limits** to **fail fast** without huge fetches — production depth stays on `SourceRoot`; verification limits stay on assert spec.

## Non-goals

Selectors (`"spotify-2"`, indices) → `cli/source_selector` + registry. **No `fetch_all`** in `fetch_ops` — caller loops sources and merges if needed. **No validation inside fetch** — `validate_all` / similar **ingest JSON artifacts only** (dev workflow), not live resolve output.

## Migration

Replace `run_fetch(SourceSpec, …)` with: lookup triple → **`fetch` / `fetch_and_save_json`** (resolve + optional JSON write **only**). **Validation:** dev runs **`validate_all` (or equivalent) on the JSON files** using `verification` / `SourceAssertSpec` — **not** wired into `fetch`; gives confidence the pipeline + on-disk shape are correct without coupling prod fetch to asserts.

## Implementation plan

Principles: **one PR per phase** where possible; **`gleam test` + `gleam build` green** after each; prefer **characterisation tests** (existing CLI/tests) before refactors, then **narrow unit tests** on new types.

### Phase 0 — Baseline

- [ ] Run full test suite and note anything that depends on CSV paths or `cli_result_*` filenames (grep helps).
- [ ] Optional: one tiny “smoke” test that documents current entrypoint (`fetch_with_cache_mode` / `cli.run`) if coverage is thin — makes later diffs safer.

### Phase 1 — `SourceRoot` type only

- [ ] Add a small module (e.g. `source_root.gleam`) with `SourceRoot` exactly as in this spec (`SpotifyCredentials` imported from existing adapter/cli types).
- [ ] Add `from_legacy_spec(SourceSpec) -> SourceRoot` (or live on `source_specs`) that maps today’s `all()` rows — **no call-site switches yet**.
- [ ] **Tests:** one test per variant (or table-driven) asserting the mapping matches known `entry_point` / URLs / timing fields from `source_specs`.

### Phase 2 — Triple registry alongside list

- [ ] Add `registry() -> Dict(String, #(SourceRoot, SourceAssertSpec))` (and optionally `triple(key) -> Result(...)`) built from current `SourceSpec` list.
- [ ] Keep `all()` + `SourceSpec` until callers are migrated.
- [ ] **Tests:** dict keys equal set of `all()` keys; spot-check one triple’s `SourceAssertSpec` matches the legacy spec.

### Phase 3 — Core `fetch(root, …)` behind existing behavior

- [ ] For each `SourceRoot` variant, add or rename an adapter function whose **args mirror the constructor fields** (+ minimal shared args: `cache_mode`, `on_update`, etc.); `fetch` dispatches with a single `case root`.
- [ ] Extract resolve pipeline from `run_fetch` into `fetch(root, cache_mode, on_update) -> Result(...)` returning **`List(core.UnifiedItem)`** (plus whatever metadata you already thread for imported dates / adapter id — introduce a named `FetchResult` record in this phase if it clarifies diffs).
- [ ] Implement `run_fetch` as: legacy `SourceSpec` → `SourceRoot` → `fetch` → **same JSON write behavior as today**; **strip any validation/assert hooks from the fetch path** so they run only via **`validate_all` on JSON** (may be a follow-up sub-step in the same PR if currently coupled).
- [ ] **Tests:** add **one direct `fetch` test** on the smallest adapter (e.g. `TunaRoot`) to pin the new API. **`validate_all`** remains a **separate** dev entrypoint reading JSON — adjust only if it still assumed in-fetch validation.

### Phase 4 — `fetch_and_save_json` + new artifact names

- [ ] Implement `fetch_and_save_json(root, cache_mode)` = `fetch` + encode + `simplifile.write` using **paths derived only from `SourceRoot`** (document the naming rule in code comment).
- [ ] Switch **one** caller (e.g. single-source CLI path) to the new filenames; update any test that asserts paths **in the same PR**.
- [ ] Repeat for remaining callers until no legacy `cli_result_*` writers remain.
- [ ] **Tests:** file exists + minimal JSON parse smoke per naming convention (or extend an existing golden test).

### Phase 5 — Orchestration stays out of `fetch_ops`

- [ ] Move `fetch_all_sources` / selector handling behind a clear CLI (or `cli/fetch_orchestration`) boundary; **`fetch_ops` exports only `fetch` + `fetch_and_save_json`** (+ types/helpers used by callers).
- [ ] **Tests:** `cli.run` / library smoke still pass; no accidental re-export of adapter internals.

### Phase 6 — Spotify / YouTube credentials

- [ ] Extract `spotify_ensure_auth` (or equivalent) to CLI/orchestration: reads/writes `.env`, validates token; builds `SpotifyCredentials` then `SpotifyRoot`.
- [ ] Optional: YouTube “ping” in orchestration before fetch.
- [ ] **Tests:** mock or stub at orchestration boundary; `fetch` tests receive explicit credential structs (no `.env` reads).

### Phase 7 — JSON shape for `validate_all` (dev-only consumer)

- [ ] Extend **CLI result JSON** encoding so files include **lists/albums referencing tracks** as `validate_all` needs; **`validate_all` reads those files only** (not `fetch` return values).
- [ ] **Tests:** `validate_all` (or focused module) on a **fixture JSON** file — no network; fetch tests do not need to invoke validation.

### Phase 8 — CSV purge (slice by slice)

- [ ] **8a** — Remove CSV from interactive export UI + any `cli.run` CSV subcommands; delete or rewrite tests that run `export … csv`.
- [ ] **8b** — Remove CSV writes from `validate_all.gleam`; update tests.
- [ ] **8c** — Delete `output/csv_writer.gleam`, CSV-only tests, and `track_csv_row` / CSV sections in `visual_output` if nothing else uses them.
- [ ] **8d** — `manifest.toml`: drop CSV-only deps if any.

### Phase 9 — Remove legacy `SourceSpec` path (optional cleanup)

- [ ] Migrate all callers to `registry()` triples + `SourceRoot` only; delete or privatise `SourceSpec` / `all()` if unused.
- [ ] **Tests:** grep for `SourceSpec` in `src/` should be empty or test-only fixtures.

### Phase 10 — Test helper `with_root` (after API stable)

- [ ] Add helper for tests that adjusts depth / caps via **assert spec** or a **test-only root wrapper** — exact API per open points below.
- [ ] **Tests:** demonstrate faster failing run (e.g. shallow depth) without changing production registry entries.

---

## Todos (summary)

- [ ] Phases 0–4: types, registry, `fetch`, JSON write, path migration.
- [ ] Phases 5–6: slim exports, auth orchestration.
- [ ] Phase 7: rich JSON for validation.
- [ ] Phase 8: CSV purge.
- [ ] Phases 9–10: legacy removal, `with_root`.

## Open points

- Exact **API of `with_root` / test wrapper** (container type, how it overrides depth vs verification).
- **Named return type** for `fetch` (wrapper around `List(UnifiedItem)` + adapter id / timestamps) if you want a stable public type.
- **JSON schema** for on-disk artifacts (field names for albums/lists vs tracks) once encoders are unified.
