# Eliminating Erlang `@external` FFI

Goal: **remove every `@external(erlang, ...)`** from this project so production and test Gleam code calls only Gleam APIs (standard library, Hex packages, or small pure-Gleam helpers), except what the **compiler/runtime** still requires implicitly.

**Status (2026-03):** `rg '@external(erlang'` in `src/` and `test/` returns **no matches**. Transport, cache hashing, CLI argv/time, test env gates, tuna `gel`, and interactive export helpers no longer use project-local `.erl` shims.

Third-party Hex packages used at the boundary (they contain their own FFI): **`argv`**, **`envoy`**, **`shellout`**, **`gleam_hackney`**, plus transitive stdlib/erlang bindings inside dependencies.

## 1) Former inventory (resolved)

| Gleam module | Was | Replacement |
| ------------ | --- | ----------- |
| `adapters/youtube/live_expander` | `youtube_http` | Already on `gleetube` / Gleam HTTP before this pass |
| `adapters/bandcamp/live_expander` | `soundcloud_http` `fetch` / `post_json` | `gleam_http` + `gleam/hackney` (GET/POST, JSON body) |
| `adapters/tuna/normalized_source` | `tuna_runtime` | `adapters/tuna/tracks_source_ids_query.gleam` + `shellout.command` for `gel` |
| `adapters/cache` | `cache_hash` `phash` | Pure Gleam **FNV-1a 32-bit** over UTF-8 bytes → decimal string (cache bust vs old `phash2` rows) |
| `cli/runtime` | `cli_runtime_args` | `argv.load().arguments`, `gleam/time/timestamp.system_time` → ms |
| `cli_export_interactive` | `runtime_otp` / `runtime_guard` / `runtime_terminal` | `shellout` + `erl -eval` for OTP release; sequential `start_ui()` then terminal restore; ANSI + `stty sane` via `shellout` |
| Tests | `test_runtime` | `test/test_env.gleam` using **`envoy`**; perf timing uses **`cli/runtime.now_ms`** |

Removed Erlang sources: `youtube_http.erl` (already gone), `soundcloud_http.erl`, `tuna_runtime.erl`, `cache_hash.erl`, `cli_runtime_args.erl`, `test_runtime.erl`, `runtime_otp.erl`, `runtime_guard.erl`, `runtime_terminal.erl`.

## 2) Notes

- **Cache:** FNV-1a invalidates existing SQLite `adapter_cache` rows (new `key_hash` values). Delete `rememberthename_adapter_cache.sqlite3` or accept a cold cache.
- **CLI time:** `now_ms()` is **wall-clock** ms from `gleam_time` (not BEAM `monotonic_time`); fine for logging and typical perf tests.
- **OTP gate:** Interactive export probes OTP via a one-shot `erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().'` — requires `erl` on `PATH` (same as running the app).
- **Tuna:** Still shells out to **`gel`** via `shellout`; no local `.erl`.

## 3) Definition of done

- [x] No `@external(erlang, ...)` in this repo’s `src/` or `test/` Gleam.
- [x] Core HTTP paths do not use hard-coded `/usr/bin/curl` or Homebrew `jq` in project Erlang (project `.erl` shims removed).
- [x] This file updated when adding temporary FFI (with a removal ticket).
