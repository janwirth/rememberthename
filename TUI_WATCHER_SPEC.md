# TUI Watcher Spec

## Goal

Dev-mode watcher for `.gleam` changes that re-inits TUI with preserved state.

## Scope

- Watch `src/**/*.gleam` and `test/**/*.gleam`
- Trigger rebuild + app restart on change
- Restore prior session state after restart

Out of scope:

- Production hot reload
- Disk persistence across process death
- Non-gleam file watching

## Entrypoints

- Keep `tui.main()` unchanged.
- Add `tui.main_watch()` for watcher mode.

## State Contract

Persist/restore only user-facing session state:

- selected source index
- focused pane
- selected depth index
- selected track index
- esc armed
- current fetch bundle
- current track/debug lines

Do not persist runtime resources (subjects, pids, actor refs).

## Runtime Design

1. Watcher process tracks file mtimes (polling).
2. On change:
   - snapshot current `SessionState`
   - stop running TUI instance gracefully
   - run `bunx gleam build`
   - if build passes: start fresh TUI and inject snapshot
   - if build fails: keep previous instance alive, surface error
3. Debounce events (e.g. 250ms) to avoid restart storms.

## File Watching

- Compute fingerprint = sorted `(path, mtime)` hash.
- Ignore transient build outputs (`build/`, `.git/`).
- Treat add/remove/modify as change.

## Re-init Semantics

- Clamp restored indices to valid bounds.
- If previously selected source no longer exists: fallback to index `0`.
- If restored fetch data references stale shapes, drop invalid parts and continue.

## UX

- Show watcher status line:
  - `watch: idle`
  - `watch: change detected`
  - `watch: rebuilding`
  - `watch: build failed`
  - `watch: restarted`
- On build failure, show last compiler error in debug pane.

## Failure Policy

- Watcher never crashes app on build failure.
- Build failure is non-fatal; app continues with old code/state.
- Retry automatically on next file change.

## Testing (TDD)

Add tests for:

- fingerprint diff detection (add/modify/delete)
- debounce behavior
- state snapshot/restore roundtrip
- index clamping on restored state
- build-fail path keeps previous instance running
- build-pass path restarts and restores state

### Reload Probe Method (Fake Program)

Use `src/tui_watch_probe.gleam` as a deterministic reload target.

Program contract:

- Module prints `tui-watch-probe:<version>` on boot.
- `version` is a constant string changed manually in test.

Manual test flow:

1. Start watcher mode.
2. Keep TUI in a non-default state (change source/focus/depth selection).
3. Edit `src/tui_watch_probe.gleam` and change `const version = "v1"` to `"v2"`.
4. Expect watcher status: `change detected` -> `rebuilding` -> `restarted`.
5. Verify:
   - previous TUI state is restored
   - probe boot line reflects new version (`tui-watch-probe:v2`)

Failure-path check:

1. Introduce syntax error in `src/tui_watch_probe.gleam`.
2. Expect `watch: build failed`.
3. Verify existing TUI instance remains interactive with prior state.
4. Fix syntax error; confirm next change triggers successful restart.

## Suggested Modules

- `src/tui/watch.gleam` - watcher loop + debounce + fingerprint
- `src/tui/session_state.gleam` - snapshot/restore helpers
- `src/tui.gleam` - `main_watch()` integration

## Commands

- Normal: `bunx gleam run -m tui`
- Watch: `bunx gleam run -m tui_watch` (or equivalent module entry)
- Probe: `bunx gleam run -m tui_watch_probe`

## Done Criteria

- Editing any `.gleam` file triggers one debounced restart.
- After restart, selection/focus context is restored.
- Failed rebuild does not kill current UI.
