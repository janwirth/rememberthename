import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import output/csv_writer
import output/visual_output
import simplifile
import source_specs

@external(erlang, "cli_runtime_args", "argv")
fn argv() -> List(String)

type SourceRun {
  SourceRun(
    spec: source_specs.SourceSpec,
    depth_1: core.ResolveResult,
    depth_2: core.ResolveResult,
    depth_all: core.ResolveResult,
  )
}

pub fn main() {
  let args = normalize_args(argv())
  case args {
    ["list"] -> list_sources()
    ["export", "all", "csv"] -> export_all_csv()
    ["source", "fetch", source_index_text, "depth", depth_text] ->
      fetch_source(source_index_text, depth_text, None)
    ["source", "fetch", source_index_text, "depth", depth_text, "cache", cache_mode_text] ->
      fetch_source(source_index_text, depth_text, Some(cache_mode_text))
    _ -> print_usage()
  }
}

fn normalize_args(args: List(String)) -> List(String) {
  case args {
    ["cli", ..rest] -> rest
    _ -> args
  }
}

fn list_sources() {
  let sources = source_specs.all()
  io.println("Sources:")
  list_sources_loop(sources, 1)
}

fn list_sources_loop(sources: List(source_specs.SourceSpec), index: Int) {
  case sources {
    [] -> Nil
    [source, ..rest] -> {
      let source_specs.SourceSpec(_, name, entry_point, cache_mode, _) = source
      io.println(
        int.to_string(index)
        <> ". "
        <> name
        <> " | cache="
        <> cache_mode_text(cache_mode)
        <> " | "
        <> entry_point,
      )
      list_sources_loop(rest, index + 1)
    }
  }
}

fn fetch_source(
  source_index_text: String,
  depth_text: String,
  cache_mode_text_arg: Option(String),
) {
  let source_index = int.parse(source_index_text) |> result.unwrap(or: -1)
  case source_at(source_specs.all(), source_index, 1) {
    Error(_) -> io.println("Invalid source index: " <> source_index_text)
    Ok(source) ->
      case parse_depth(depth_text) {
        Error(_) -> io.println("Invalid depth: " <> depth_text <> " (use: 1 | 2 | full)")
        Ok(depth) ->
          case parse_cache_mode_arg(source, cache_mode_text_arg) {
            Error(_) ->
              io.println(
                "Invalid cache mode (use: upsert | ignore | override)",
              )
            Ok(cache_mode) ->
              run_fetch(source, source_index, depth, depth_text, cache_mode)
          }
      }
  }
}

fn run_fetch(
  source: source_specs.SourceSpec,
  source_index: Int,
  depth: core.DepthMode,
  depth_label: String,
  cache_mode: cache.CacheMode,
) {
  let source_specs.SourceSpec(key, name, entry_point, _, assert_spec) = source
  let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
  io.println("Fetching source " <> int.to_string(source_index) <> ": " <> name)
  io.println("Depth: " <> depth_label)
  io.println("Cache: " <> cache_mode_text(cache_mode))
  io.println("")

  let result =
    resolve_source(
      key,
      entry_point,
      depth,
      source_limit,
      cache_mode,
      fn(line) { io.println(line) },
    )

  let core.ResolveResult(items, lists, unresolved) =
    apply_source_limit(result, source_limit)
  io.println("")
  io.println(
    "Done. items="
    <> int.to_string(list.length(items))
    <> " lists="
    <> int.to_string(list.length(lists))
    <> " unresolved="
    <> int.to_string(list.length(unresolved)),
  )

  let tracks = list.map(items, to_track_view)
  let csv = csv_writer.tracks_csv(tracks)
  let csv_path = artifact_path(
    "cli_result_" <> key <> "_depth_" <> sanitize_depth_label(depth_label) <> ".csv",
  )
  let _ = simplifile.write(csv, to: csv_path)
  io.println("CSV written: " <> csv_path)
}

fn export_all_csv() {
  io.println("Exporting all sources to CSV with cache override...")
  let runs = collect_source_runs(source_specs.all(), [])
  let adapter_items = source_run_items(runs)
  let tuna_items = collect_tuna_items()
  let all_items = list.append(adapter_items, tuna_items)
  let tracks = list.map(all_items, to_track_view)
  let csv = csv_writer.tracks_csv(tracks)
  let csv_path = artifact_path("all_items_latest.csv")
  let _ = simplifile.write(csv, to: csv_path)
  let validation_errors =
    list.append(validate_source_runs(runs), validate_tuna_items(tuna_items))
  io.println(
    "Done. Exported "
    <> int.to_string(list.length(all_items))
    <> " items to "
    <> csv_path,
  )
  case validation_errors == [] {
    True -> io.println("Validation: PASS")
    False -> {
      io.println(
        "Validation: FAIL (" <> int.to_string(list.length(validation_errors)) <> " errors)",
      )
      list.each(validation_errors, fn(line) { io.println("  - " <> line) })
    }
  }
}

fn collect_source_runs(
  specs: List(source_specs.SourceSpec),
  acc: List(SourceRun),
) -> List(SourceRun) {
  case specs {
    [] -> acc
    [source, ..rest] -> {
      let source_specs.SourceSpec(key, name, entry_point, _, assert_spec) = source
      let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
      io.println("  - " <> name)
      let depth_1 =
        resolve_source(
          key,
          entry_point,
          core.Depth1,
          source_limit,
          cache.CacheOverride,
          fn(line) { io.println("    [" <> key <> "][d1] " <> line) },
        )
      let depth_1 = apply_source_limit(depth_1, source_limit)
      let depth_2 =
        resolve_source(
          key,
          entry_point,
          core.Depth2,
          source_limit,
          cache.CacheOverride,
          fn(line) { io.println("    [" <> key <> "][d2] " <> line) },
        )
      let depth_2 = apply_source_limit(depth_2, source_limit)
      let depth_all =
        resolve_source(
          key,
          entry_point,
          core.All,
          source_limit,
          cache.CacheOverride,
          fn(line) { io.println("    [" <> key <> "][all] " <> line) },
        )
      let depth_all = apply_source_limit(depth_all, source_limit)
      collect_source_runs(
        rest,
        list.append(acc, [SourceRun(source, depth_1, depth_2, depth_all)]),
      )
    }
  }
}

fn collect_tuna_items() -> List(core.UnifiedItem) {
  io.println("  - Tuna")
  let core.ResolveResult(items, _, _) =
    tuna_normalized_source.resolve(core.All, cache.CacheOverride, fn(_line) { Nil })
  items
}

fn source_run_items(runs: List(SourceRun)) -> List(core.UnifiedItem) {
  list.fold(runs, [], fn(acc, run) {
    let SourceRun(_, _, _, depth_all) = run
    let core.ResolveResult(items, _, _) = depth_all
    list.append(acc, items)
  })
}

fn validate_source_runs(runs: List(SourceRun)) -> List(String) {
  list.fold(runs, [], fn(acc, run) {
    list.append(acc, validate_source_run(run))
  })
}

fn validate_source_run(run: SourceRun) -> List(String) {
  let SourceRun(spec, depth_1, depth_2, depth_all) = run
  let source_specs.SourceSpec(key, name, _, _, assert_spec) = spec
  let source_specs.SourceAssertSpec(
    min_depth_1_items,
    min_full_items,
    source_limit,
    first_items_to_preserve,
    anchor_fragments,
    required_full_fragments,
  ) = assert_spec
  let #(i1, l1, u1) = counts(depth_1)
  let #(i2, _, _) = counts(depth_2)
  let #(iall, lall, uall) = counts(depth_all)
  let items_1 = result_items(depth_1)
  let items_2 = result_items(depth_2)
  let items_all = result_items(depth_all)
  let min_depth_ok = i1 >= min_depth_1_items
  let min_full_ok = iall >= min_full_items
  let monotonic_ok = i2 > i1 && iall >= i2
  let consistency_ok = lall >= l1 && uall == u1
  let first_ids = first_item_ids(depth_1, first_items_to_preserve)
  let first_items_ok =
    first_ids != [] && list.all(first_ids, fn(id) { has_item_id(depth_all, id) })
  let anchors_shallow_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_1, fragment) || has_title_fragment(items_2, fragment)
    })
  let anchors_full_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_all, fragment)
    })
  let anchors_ok = anchors_shallow_ok && anchors_full_ok
  let required_full_ok =
    list.all(required_full_fragments, fn(fragment) {
      has_title_fragment_ci(items_all, fragment)
    })
  let source_limit_ok = iall <= source_limit
  []
  |> add_validation_error(
    !min_depth_ok,
    key <> " (" <> name <> "): min depth-1 items failed",
  )
  |> add_validation_error(
    !min_full_ok,
    key <> " (" <> name <> "): min full items failed",
  )
  |> add_validation_error(
    !monotonic_ok,
    key <> " (" <> name <> "): depth monotonicity failed",
  )
  |> add_validation_error(
    !consistency_ok,
    key <> " (" <> name <> "): list/unresolved consistency failed",
  )
  |> add_validation_error(
    !first_items_ok,
    key <> " (" <> name <> "): first items preserved failed",
  )
  |> add_validation_error(
    !anchors_ok,
    key <> " (" <> name <> "): anchor fragments failed",
  )
  |> add_validation_error(
    !required_full_ok,
    key <> " (" <> name <> "): required full fragments failed",
  )
  |> add_validation_error(
    !source_limit_ok,
    key <> " (" <> name <> "): source limit exceeded (" <> int.to_string(source_limit) <> ")",
  )
}

fn validate_tuna_items(items: List(core.UnifiedItem)) -> List(String) {
  case items == [] {
    True -> ["tuna: no items returned"]
    False ->
      case list.all(items, fn(item) { item_source_id_ok(item) }) {
        True -> []
        False -> ["tuna: one or more items failed source_id constructor validation"]
      }
  }
}

fn item_source_id_ok(item: core.UnifiedItem) -> Bool {
  let core.UnifiedItem(_, title, artist, service, _, source_id) = item
  case core.track_item(service, source_id, title, artist) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn add_validation_error(errors: List(String), condition: Bool, line: String) -> List(String) {
  case condition {
    True -> list.append(errors, [line])
    False -> errors
  }
}

fn result_items(result: core.ResolveResult) -> List(core.UnifiedItem) {
  let core.ResolveResult(items, _, _) = result
  items
}

fn counts(result: core.ResolveResult) -> #(Int, Int, Int) {
  let core.ResolveResult(items, lists, unresolved) = result
  #(list.length(items), list.length(lists), list.length(unresolved))
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

fn resolve_source(
  key: String,
  entry_point: String,
  depth: core.DepthMode,
  source_limit: Int,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  case key {
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(entry_point)
      bandcamp_live_expander.resolve_profile_with_debug_limited(
        profile,
        depth,
        cache_mode,
        source_limit,
        on_debug,
      )
    }
    "soundcloud" -> {
      let profile = soundcloud_live_expander.soundcloud_profile(entry_point)
      soundcloud_live_expander.resolve_profile_with_debug_limited(
        profile,
        depth,
        cache_mode,
        source_limit,
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
      spotify_live_expander.resolve_profile_with_debug_limited(
        profile,
        depth,
        config,
        cache_mode,
        source_limit,
        on_debug,
      )
    }
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(entry_point)
      youtube_live_expander.resolve_profile_with_debug_limited(
        profile,
        depth,
        cache_mode,
        source_limit,
        on_debug,
      )
    }
  }
}

fn to_track_view(item: core.UnifiedItem) -> visual_output.TrackView {
  let core.UnifiedItem(_, title, artist, service, _, source_id) = item
  visual_output.TrackView(title, artist, service, source_id)
}

fn parse_depth(value: String) -> Result(core.DepthMode, Nil) {
  case value {
    "1" -> Ok(core.Depth1)
    "2" -> Ok(core.Depth2)
    "full" -> Ok(core.All)
    _ -> Error(Nil)
  }
}

fn sanitize_depth_label(value: String) -> String {
  case value {
    "full" -> "full"
    _ -> value
  }
}

fn source_at(
  sources: List(source_specs.SourceSpec),
  wanted: Int,
  current: Int,
) -> Result(source_specs.SourceSpec, Nil) {
  case sources {
    [] -> Error(Nil)
    [source, ..rest] ->
      case current == wanted {
        True -> Ok(source)
        False -> source_at(rest, wanted, current + 1)
      }
  }
}

fn parse_cache_mode_arg(
  source: source_specs.SourceSpec,
  maybe_cache_mode: Option(String),
) -> Result(cache.CacheMode, Nil) {
  let source_specs.SourceSpec(_, _, _, default_mode, _) = source
  case maybe_cache_mode {
    None -> Ok(default_mode)
    Some(value) -> parse_cache_mode(value)
  }
}

fn parse_cache_mode(value: String) -> Result(cache.CacheMode, Nil) {
  case value {
    "upsert" -> Ok(cache.CacheUpsert)
    "ignore" -> Ok(cache.CacheIgnore)
    "override" -> Ok(cache.CacheOverride)
    _ -> Error(Nil)
  }
}

fn cache_mode_text(value: cache.CacheMode) -> String {
  case value {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
  }
}

fn artifact_path(file_name: String) -> String {
  "output/" <> file_name
}

fn apply_source_limit(
  result: core.ResolveResult,
  source_limit: Int,
) -> core.ResolveResult {
  let core.ResolveResult(items, lists, unresolved) = result
  case source_limit <= 0 {
    True -> core.ResolveResult(items: [], lists: lists, unresolved: unresolved)
    False ->
      core.ResolveResult(
        items: list.take(items, source_limit),
        lists: lists,
        unresolved: unresolved,
      )
  }
}

fn print_usage() {
  io.println("Usage:")
  io.println("  cli list")
  io.println("  cli export all csv")
  io.println("  cli source fetch <index> depth <1|2|full> [cache <upsert|ignore|override>]")
  io.println("")
  io.println("Examples:")
  io.println("  gleam run -m cli -- list")
  io.println("  gleam run -m cli -- export all csv")
  io.println("  gleam run -m cli -- source fetch 1 depth 1")
  io.println("  gleam run -m cli -- source fetch 2 depth full")
}
