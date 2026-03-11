import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/youtube/live_expander as youtube_live_expander
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import output/csv_writer
import output/visual_output
import simplifile
import source_specs

pub fn main() {
  let specs = source_specs.all()
  let #(total, failed) = validate_sources(specs, 1, 0, 0)
  io.println("")
  io.println(
    "Validation summary: total="
    <> int.to_string(total)
    <> " failed="
    <> int.to_string(failed),
  )
  case failed > 0 {
    True -> panic as "validate_all failed"
    False -> io.println("All sources PASS.")
  }
}

fn validate_sources(
  specs: List(source_specs.SourceSpec),
  index: Int,
  total: Int,
  failed: Int,
) -> #(Int, Int) {
  case specs {
    [] -> #(total, failed)
    [spec, ..rest] -> {
      let pass = validate_source(spec, index)
      validate_sources(
        rest,
        index + 1,
        total + 1,
        case pass {
          True -> failed
          False -> failed + 1
        },
      )
    }
  }
}

fn validate_source(spec: source_specs.SourceSpec, index: Int) -> Bool {
  let source_specs.SourceSpec(key, name, entry_point, timing_spec, assert_spec) =
    spec
  let cache_mode = cache.CacheUpsert
  let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
  io.println("")
  io.println("== [" <> int.to_string(index) <> "] " <> name <> " (" <> key <> ") ==")
  io.println("entry: " <> entry_point)
  io.println("cache: " <> cache_mode_text(cache_mode))

  // Warm-up full traversal before measured runs, matching migration test strategy.
  let _ =
    resolve_source(key, entry_point, core.All, source_limit, timing_spec, cache_mode, fn(line) {
      io.println("[warmup] " <> line)
    })

  let depth_1 =
    resolve_source(key, entry_point, core.Depth1, source_limit, timing_spec, cache_mode, fn(
      _line,
    ) {
      Nil
    })
  let depth_2 =
    resolve_source(key, entry_point, core.Depth2, source_limit, timing_spec, cache_mode, fn(
      _line,
    ) {
      Nil
    })
  let depth_all =
    resolve_source(key, entry_point, core.All, source_limit, timing_spec, cache_mode, fn(line) {
      io.println("[full] " <> line)
    })

  let pass =
    validate_results(name, source_limit, assert_spec, depth_1, depth_2, depth_all)
  write_csv(key, depth_all)
  io.println(
    case pass {
      True -> "Result: PASS"
      False -> "Result: FAIL"
    },
  )
  pass
}

fn resolve_source(
  key: String,
  entry_point: String,
  depth: core.DepthMode,
  source_limit: Int,
  timing_spec: source_specs.SourceTimingSpec,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let source_specs.SourceTimingSpec(max_concurrency, requests_per_second) = timing_spec
  let queue_policy =
    core.QueuePolicy(
      max_concurrency: max_concurrency,
      requests_per_second: requests_per_second,
    )
  case key {
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(entry_point)
      bandcamp_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
      )
    }
    "soundcloud" -> {
      let profile = soundcloud_live_expander.soundcloud_profile(entry_point)
      soundcloud_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
      )
    }
    "spotify" -> {
      let access_token =
        spotify_live_expander.read_access_token_file(".spotify_oauth_session.json")
      let config =
        spotify_live_expander.spotify_config(
          access_token: access_token,
          session_file: ".spotify_oauth_session.json",
          client_id: spotify_live_expander.read_env_value(".env", "SPOTIFY_CLIENT_ID"),
          client_secret: spotify_live_expander.read_env_value(
            ".env",
            "SPOTIFY_CLIENT_SECRET",
          ),
          redirect_uri: "https://127.0.0.1:8080/spotify-oauth-success",
          scopes: "playlist-read-private playlist-read-collaborative user-library-read",
        )
      let profile = spotify_live_expander.spotify_user(entry_point)
      spotify_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        config,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
      )
    }
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(entry_point)
      youtube_live_expander.resolve_profile_with_debug_limited_timed(
        profile,
        depth,
        cache_mode,
        source_limit,
        queue_policy,
        on_debug,
      )
    }
  }
}

fn validate_results(
  name: String,
  source_limit: Int,
  assert_spec: source_specs.SourceAssertSpec,
  d1: core.ResolveResult,
  d2: core.ResolveResult,
  all: core.ResolveResult,
) -> Bool {
  let source_specs.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    _source_limit,
    first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = assert_spec

  let #(i1, l1, u1) = counts(d1)
  let #(i2, _, _) = counts(d2)
  let #(iall, lall, uall) = counts(all)
  let items_1 = result_items(d1)
  let items_2 = result_items(d2)
  let items_all = result_items(all)

  let min_depth_ok = i1 >= min_depth_1_items
  let min_full_ok = iall >= min_full_items
  let monotonic_ok = i2 > i1 && iall >= i2
  let consistency_ok = lall >= l1 && uall == u1
  let first_ids = first_item_ids(d1, first_items_to_preserve)
  let first_items_ok = first_ids != [] && list.all(first_ids, fn(id) { has_item_id(all, id) })
  let anchors_shallow_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_1, fragment) || has_title_fragment(items_2, fragment)
    })
  let anchors_full_ok =
    list.all(anchor_fragments, fn(fragment) { has_title_fragment(items_all, fragment) })
  let required_full_ok =
    list.all(required_full_fragments, fn(fragment) {
      has_title_fragment_ci(items_all, fragment)
    })
  let source_limit_ok = iall <= source_limit

  io.println(name <> " checks:")
  io.println(check(min_depth_ok) <> " min depth-1 items")
  io.println(check(min_full_ok) <> " min full items")
  io.println(check(monotonic_ok) <> " depth monotonicity")
  io.println(check(consistency_ok) <> " list/unresolved consistency")
  io.println(check(first_items_ok) <> " first items preserved")
  io.println(check(anchors_shallow_ok && anchors_full_ok) <> " anchor fragments present")
  io.println(check(required_full_ok) <> " required full fragments present")
  io.println(check(source_limit_ok) <> " source limit <= " <> int.to_string(source_limit))

  min_depth_ok
  && min_full_ok
  && monotonic_ok
  && consistency_ok
  && first_items_ok
  && anchors_shallow_ok
  && anchors_full_ok
  && required_full_ok
  && source_limit_ok
}

fn write_csv(key: String, result: core.ResolveResult) {
  let tracks =
    result_items(result)
    |> list.map(fn(item) {
      let core.UnifiedItem(_, title, artist, service, _, source_id) = item
      visual_output.TrackView(title, artist, service, source_id, "")
    })
  let path = "validate_all_" <> key <> "_full.csv"
  let _ = simplifile.write(csv_writer.tracks_csv(tracks), to: path)
  io.println("CSV: " <> path)
}

fn counts(result: core.ResolveResult) -> #(Int, Int, Int) {
  let core.ResolveResult(items, lists, unresolved) = result
  #(list.length(items), list.length(lists), list.length(unresolved))
}

fn result_items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

fn first_item_ids(result: core.ResolveResult, count: Int) -> List(String) {
  result
  |> result_items
  |> list.take(count)
  |> list.map(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _) = item
    id
  })
}

fn has_item_id(result: core.ResolveResult, wanted: String) -> Bool {
  result
  |> result_items
  |> list.any(fn(item) {
    let core.UnifiedItem(id, _, _, _, _, _) = item
    id == wanted
  })
}

fn has_title_fragment(items: List(core.UnifiedItem), wanted: String) -> Bool {
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _) = item
    string.contains(title, wanted)
  })
}

fn has_title_fragment_ci(items: List(core.UnifiedItem), wanted: String) -> Bool {
  let wanted_lc = string.lowercase(wanted)
  list.any(items, fn(item) {
    let core.UnifiedItem(_, title, _, _, _, _) = item
    string.contains(string.lowercase(title), wanted_lc)
  })
}

fn check(ok: Bool) -> String {
  case ok {
    True -> "[x]"
    False -> "[ ]"
  }
}

fn cache_mode_text(value: cache.CacheMode) -> String {
  case value {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
  }
}

