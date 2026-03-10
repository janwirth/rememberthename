# Development Cycle

This document describes the development workflow for `rememberthename`. It is referenced from `SPEC.md` section 11. The project is TDD-first: all behavior is driven by automated tests, and agents iterate on failing tests until they pass.

The resolver traverses collection graphs with configurable depth limits (Depth1, Depth2, Depth3, … All). Tests assert that deeper traversal yields more items and lists, that early-discovered items remain in full results, and that anchor fragments (known track titles) appear as expected.

## Iteration protocol

1. Agent implements strictly from failing tests for the current request.
2. Latest test results are fed back into the next agent iteration.
3. Agent repeats until tests pass for the request scope.
4. No speculative feature work outside active failing tests.

## How the tests work

### Test layout

1. **Entry point**: `test/rememberthename_test.gleam` runs `gleeunit.main()`.
2. **Shared depth spec**: `test/depth_test_spec.gleam` provides reusable depth assertions:
   - `resolve_standard_depths(resolve)` runs the resolver in migration order: Depth1, Depth2, then All (with an All warm-up pass before measured assertions).
   - `assert_standard_depth_pattern(results, spec)` checks progression, anchor fragments, and first-items stability.
3. **Unit tests (fake adapter)**: `test/soundcloud_adapter_fake_test.gleam`:
   - Injects a `fake_expand` function into `core.resolve_profile_url` instead of a live adapter.
   - No network; deterministic fixture data.
   - Covers depth 1/2/3/all, list recursion, unresolved tracking, deduplication.
4. **Integration tests (live adapter)**: `test/bandcamp_adapter_test.gleam`, `test/soundcloud_adapter_test.gleam`:
   - Use real profile URLs and live expanders.
   - Call `depth_test_spec.resolve_standard_depths` with the adapter’s `resolve_profile`.
   - Assert via `assert_standard_depth_pattern` with service-specific `DepthAssertSpec` (min items, anchor fragments).

### Running tests

1. `gleam test` runs all tests.
2. Unit tests (fake) run without network; integration tests require valid reference URLs.

## Integration test fixture ownership

1. Developer provides and maintains:
   - reference URLs per supported service (Bandcamp/SoundCloud/YouTube)
   - Spotify profile ID
   - Spotify API key/credentials for test context
2. These fixtures form the integration test set and must be stable/replayable where possible.
