# Eliminating Erlang `@external` FFI

Goal: **remove every `@external(erlang, ...)`** from this project so production and test Gleam code calls only Gleam APIs (standard library, Hex packages, or small pure-Gleam helpers), except what the **compiler/runtime** still requires implicitly.

This document inventories current FFI, what each Erlang module does, and a practical replacement strategy.

## 1) Inventory

| Gleam module | Erlang module | Functions | Role |
| ------------ | ------------- | --------- | ---- |
| `adapters/youtube/live_expander` | `youtube_http` | `playlist_first_tsv`, `playlist_first_next_token`, `playlist_api_key`, `playlist_client_version`, `playlist_title`, `continuation_tsv`, `continuation_next_token` | Fetch YouTube HTML/JSON via **curl**, extract `ytInitialData`, run **jq** filters, POST Innertube continuation with curl |
| `adapters/bandcamp/live_expander` | `soundcloud_http` | `fetch`, `post_json` | **curl** GET/POST for Bandcamp HTTP (shared with SoundCloud stack naming) |
| `adapters/tuna/normalized_source` | `tuna_runtime` | `tracks_source_ids_json` | **`os:cmd`** running **`gel` CLI** with a large EdgeQL query; returns JSON binary |
| `adapters/cache` | `cache_hash` | `phash` | **`erlang:phash2/1`** on key bytes for deterministic cache shard |
| `cli/runtime` | `cli_runtime_args` | `argv`, `now_ms` | **`init:get_plain_arguments`**, **`erlang:monotonic_time(millisecond)`** |
| `cli_export_interactive` | `runtime_otp` | `otp_major` | Parse **`erlang:system_info(otp_release)`** for OTP ≥ 28 gate |
| `cli_export_interactive` | `runtime_guard` | `run` | **`try ... after`** wrapper so cleanup runs after UI |
| `cli_export_interactive` | `runtime_terminal` | `restore_shell` | ANSI reset + **`stty sane`** via **`os:cmd`** on `/dev/tty` |
| Tests (several) | `test_runtime` | `run_live_tests`, `run_live_perf_tests`, `now_ms` | Read **`RUN_LIVE_TESTS` / `RUN_LIVE_PERF_TESTS`** env; monotonic ms for perf |
| Tests | `tuna_runtime` | `tracks_source_ids_json` | Same as production tuna path |

**Note:** `soundcloud_http.erl` exports additional jq helpers (`json_*`) used only from Erlang, not from Gleam `@external` today. Any migration should either move those call sites to Gleam or delete them if unused.

## 2) Usage patterns (why FFI exists)

1. **Shelling out:** `youtube_http`, `soundcloud_http` (Bandcamp), and `tuna_runtime` rely on **`os:cmd`** for `curl`, `jq`, and `gel`. Paths are partly hard-coded (e.g. `/usr/bin/curl`, `/opt/homebrew/bin/jq`).
2. **OTP/runtime introspection:** argv, monotonic clock, OTP major version.
3. **Small Erlang-only primitives:** `phash2`, `try/after` guard, terminal restore.
4. **Test gates:** boolean flags from environment variables.

## 3) Target architecture (no Gleam `@external(erlang, ...)`)

### 3.1 HTTP + JSON parsing (YouTube scraper path, Bandcamp `fetch` / `post_json`)

**Replace** curl+jq Erlang with a **Gleam HTTP client** (for example a Hex package built on Erlang `hackney`/`gun`/`httpc` behind Gleam types, or whatever the ecosystem standard is when you implement this).

**Parsing:** implement or depend on JSON decode + string/binary extraction for:

- `ytInitialData` extraction from HTML (today: substring between markers).
- Innertube POST body/response handling (today: jq filters in `youtube_http.erl`).
- Bandcamp responses (today: Gleam parses; only transport was FFI).

**Acceptance:** no subprocess for normal fetch; jq becomes optional or a dev-only tool.

### 3.2 Tuna / Gel (`tuna_runtime:tracks_source_ids_json/0`)

**Options (pick one):**

- **Gel client over HTTP:** if/when the stack supports querying without the `gel` CLI, use a typed Gleam client and drop `os:cmd`.
- **Wrapped subprocess in Gleam:** if the CLI must stay, use a **single** thin Gleam module that shells out via a supported API (see §3.5) rather than `@external` to custom Erlang — only if the project standard allows one blessed “run command” abstraction.
- **Pre-exported fixtures in tests:** tests already can avoid live `gel` by injecting JSON; keep that pattern for CI.

### 3.3 Cache key hashing (`cache_hash:phash/1`)

**Replace** `erlang:phash2` with a **stable pure-Gleam hash** over the same string bytes (for example a documented FNV or SipHash implementation), or use a Gleam crypto/hash package that does not expose `@external` at call sites. **Important:** changing the algorithm invalidates existing SQLite cache rows — document a one-time cache bust or namespace bump.

### 3.4 CLI argv and clocks (`cli_runtime_args`)

- **Argv:** use Gleam/Erlang standard library bindings if exposed without custom FFI (check current `gleam_stdlib` / `gleam_erlang` for `erlang` module accessors to `init`); otherwise contribute a tiny official helper upstream rather than local `.erl`.
- **`now_ms`:** prefer **`gleam/erlang`** or stdlib **time** APIs exposed to Gleam; monotonic ms is for durations, not wall clock.

### 3.5 Interactive export TUI (`runtime_otp`, `runtime_guard`, `runtime_terminal`)

- **OTP version gate:** detect via Gleam-accessible **`erlang:system_info`** wrapper from supported packages, or rephrase the feature check (e.g. require documented Gleam/OTP combo).
- **`try/finally`:** use Gleam **`try`/`use`** with explicit cleanup, or `gleam/erlang/process` patterns that guarantee `after` semantics without custom Erlang.
- **Terminal restore:** use a TUI library that handles teardown, or raw ANSI from Gleam with a single documented escape sequence; **`stty sane`** may still need a subprocess — consolidate into one portable “terminal reset” module implemented in Gleam using the same subprocess mechanism as §3.1 (not scattered `@external`).

### 3.6 Test gates (`test_runtime`)

**Replace** env reads with:

- **`gleam/erlang/os`** or equivalent `getenv` from stdlib/package, **or**
- **Gleam feature flags** passed from `gleam test` entry / build tags if the toolchain supports them.

Goal: no dedicated `test_runtime.erl`; tests call only Gleam.

## 4) Erlang source files after migration

Once call sites are gone:

- Delete or shrink: `youtube_http.erl`, `soundcloud_http.erl` (if nothing else needs it), `tuna_runtime.erl`, `cache_hash.erl`, `cli_runtime_args.erl`, `test_runtime.erl`, `runtime_otp.erl`, `runtime_guard.erl`, `runtime_terminal.erl`.
- Update **`gleam.toml`** / build config so no stray `.erl` modules are required for the Gleam app.

## 5) Ordering (suggested)

1. **Cache hash** — isolated, testable, but changes cache keys.
2. **CLI argv / time / test env** — small surface, high leverage.
3. **HTTP migration** — largest effort (YouTube + Bandcamp transport).
4. **Tuna `gel` query** — depends on product decision (CLI vs HTTP API).
5. **TUI cleanup** — align with whatever HTTP and CLI primitives landed.

## 6) Definition of done

- `rg '@external(erlang'` in the repo returns **no matches** in `src/` and `test/` (except if the team explicitly allows a single blessed internal module — then document that exception here).
- CI runs **without** relying on Homebrew `jq` or hard-coded curl paths for core paths, unless documented as optional dev tools.
- This file is updated if new FFI is added temporarily (should include removal ticket).
