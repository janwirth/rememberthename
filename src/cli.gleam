import adapters/bandcamp/live_expander as bandcamp_live_expander
import adapters/cache
import adapters/core
import adapters/soundcloud/live_expander as soundcloud_live_expander
import adapters/spotify/live_expander as spotify_live_expander
import adapters/tuna/normalized_source as tuna_normalized_source
import adapters/youtube/live_expander as youtube_live_expander
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import output/visual_output
import simplifile
import source_id_normalizer
import source_specs

@external(erlang, "cli_runtime_args", "argv")
fn argv() -> List(String)

@external(erlang, "tuna_runtime", "tracks_source_ids_json")
fn tracks_source_ids_json() -> String

type SourceRun {
  SourceRun(
    spec: source_specs.SourceSpec,
    depth_1: core.ResolveResult,
    depth_2: core.ResolveResult,
    depth_all: core.ResolveResult,
  )
}

pub fn main() {
  run(normalize_args(argv()))
}

pub fn run(args: List(String)) {
  case args {
    [] -> show_easy_start()
    ["fetch", source_selector, ..rest] ->
      fetch_source_simple(source_selector, rest)
    _ -> print_usage()
  }
  print_exit_signal()
}

fn normalize_args(args: List(String)) -> List(String) {
  case args {
    ["cli", ..rest] -> rest
    _ -> args
  }
}

fn list_sources() {
  let sources = source_specs.all()
  io.println(color("Sources:", ansi_bright_cyan()))
  list_sources_loop(sources, 1)
}

fn list_sources_loop(sources: List(source_specs.SourceSpec), index: Int) {
  case sources {
    [] -> Nil
    [source, ..rest] -> {
      let source_specs.SourceSpec(key, _, entry_point, _, _) = source
      let alias_rank =
        provider_rank_for_index(source_specs.all(), key, index, 1, 0)
      io.println(
        key
        <> "-"
        <> int.to_string(alias_rank)
        <> " | "
        <> entry_point,
      )
      list_sources_loop(rest, index + 1)
    }
  }
}

fn show_easy_start() {
  list_sources()
  io.println("")
  print_usage()
}

fn fetch_source_simple(source_selector: String, args: List(String)) {
  case parse_fetch_args(args) {
    Error(message) -> io.println(message)
    Ok(use_cache) -> fetch_source_simple_with_options(source_selector, use_cache)
  }
}

fn fetch_source_simple_with_options(
  source_selector: String,
  use_cache: Bool,
) {
  case source_selector == "all" {
    True -> fetch_all_sources(use_cache)
    False ->
      case source_by_selector(source_specs.all(), source_selector) {
        Error(_) -> io.println("Invalid source selector: " <> source_selector)
        Ok(#(source_index, source)) -> {
          let cache_mode = case use_cache {
            True -> cache.CacheReadOnly
            False -> cache.CacheOverride
          }
          run_fetch(source, source_index, core.All, "full", cache_mode, True)
        }
      }
  }
}

fn fetch_all_sources(use_cache: Bool) {
  let cache_mode = case use_cache {
    True -> cache.CacheReadOnly
    False -> cache.CacheOverride
  }
  io.println(color("Fetching all sources...", ansi_bright_cyan()))
  fetch_all_sources_loop(source_specs.all(), 1, cache_mode)
}

fn fetch_all_sources_loop(
  sources: List(source_specs.SourceSpec),
  index: Int,
  cache_mode: cache.CacheMode,
) {
  case sources {
    [] -> Nil
    [source, ..rest] -> {
      run_fetch(source, index, core.All, "full", cache_mode, True)
      io.println("")
      fetch_all_sources_loop(rest, index + 1, cache_mode)
    }
  }
}

fn parse_fetch_args(args: List(String)) -> Result(Bool, String) {
  case args {
    [] -> Ok(False)
    [arg1] ->
      case parse_fetch_cache_pref(arg1) {
        Ok(use_cache) -> Ok(use_cache)
        Error(_) ->
          Error(
            "Invalid fetch arg: "
            <> arg1
            <> " (use: override-cache | use-cache)",
          )
      }
    _ ->
      Error(
        "Too many fetch args. Use: cli fetch <source> [override-cache|use-cache]",
      )
  }
}

fn parse_fetch_cache_pref(value: String) -> Result(Bool, Nil) {
  case value {
    "use-cache" -> Ok(True)
    "override-cache" -> Ok(False)
    _ -> Error(Nil)
  }
}


fn run_fetch(
  source: source_specs.SourceSpec,
  source_index: Int,
  depth: core.DepthMode,
  depth_label: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
) {
  let source_specs.SourceSpec(key, name, entry_point, timing_spec, assert_spec) =
    source
  let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
  io.println(
    color(
      "Fetching source " <> int.to_string(source_index) <> ": " <> name,
      ansi_bright_cyan(),
    ),
  )
  io.println(color("Depth: ", ansi_yellow()) <> depth_label)
  io.println(color("Cache: ", ansi_yellow()) <> cache_mode_text(cache_mode))
  io.println("")

  let result =
    resolve_source(
      key,
      entry_point,
      depth,
      source_limit,
      timing_spec,
      cache_mode,
      fn(line) { io.println(line) },
    )

  let core.ResolveResult(items, lists, unresolved) = result
  io.println("")
  io.println(
    color("Done.", ansi_green())
    <> " items="
    <> int.to_string(list.length(items))
    <> " lists="
    <> int.to_string(list.length(lists))
    <> " unresolved="
    <> int.to_string(list.length(unresolved)),
  )

  let adapter_id = adapter_id_for_source(key, entry_point)
  let tracks = case key == "tuna" {
    True -> {
      let metadata_rows = tuna_row_metadata(cache_mode)
      list.map(items, fn(item) {
        to_tuna_track_view(item, adapter_id, metadata_rows)
      })
    }
    False -> list.map(items, fn(item) { to_track_view(item, adapter_id) })
  }
  let content = tracks_json(tracks)
  let json_path =
    artifact_path(
      "cli_result_"
      <> key
      <> "_depth_"
      <> sanitize_depth_label(depth_label)
      <> ".json",
    )
  let _ = simplifile.write(content, to: json_path)
  io.println(color("JSON written: ", ansi_green()) <> json_path)
  print_runtime_validation(source, depth, cache_mode, result, always_validate)
}

fn print_runtime_validation(
  source: source_specs.SourceSpec,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  depth_result: core.ResolveResult,
  always_validate: Bool,
) {
  case always_validate || depth == core.All {
    False -> Nil
    True -> {
      let run =
        validation_run_for_depth(source, depth, cache_mode, depth_result)
      let validation_errors = validate_source_run(run)
      io.println("")
      case validation_errors == [] {
        True -> io.println(color("Validation: PASS", ansi_green()))
        False -> {
          io.println(
            color("Validation: FAIL", ansi_red())
            <> " ("
            <> int.to_string(list.length(validation_errors))
            <> " errors)",
          )
          list.each(validation_errors, fn(line) { io.println("  - " <> line) })
        }
      }
    }
  }
}

fn validation_run_for_depth(
  source: source_specs.SourceSpec,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  depth_result: core.ResolveResult,
) -> SourceRun {
  let source_specs.SourceSpec(key, _, entry_point, timing_spec, assert_spec) =
    source
  let source_specs.SourceAssertSpec(_, _, source_limit, _, _, _) = assert_spec
  let resolve_depth = fn(mode: core.DepthMode) {
    resolve_source(
      key,
      entry_point,
      mode,
      source_limit,
      timing_spec,
      cache_mode,
      fn(_line) { Nil },
    )
  }

  case depth {
    core.Depth1 ->
      SourceRun(
        source,
        depth_result,
        resolve_depth(core.Depth2),
        resolve_depth(core.All),
      )
    core.Depth2 ->
      SourceRun(
        source,
        resolve_depth(core.Depth1),
        depth_result,
        resolve_depth(core.All),
      )
    core.All ->
      SourceRun(
        source,
        resolve_depth(core.Depth1),
        resolve_depth(core.Depth2),
        depth_result,
      )
    _ ->
      SourceRun(
        source,
        resolve_depth(core.Depth1),
        resolve_depth(core.Depth2),
        resolve_depth(core.All),
      )
  }
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
  let monotonic_ok = case key == "tuna" {
    True -> True
    False -> i2 > i1 && iall >= i2
  }
  let consistency_ok = lall >= l1 && uall == u1
  let first_ids = first_item_ids(depth_1, first_items_to_preserve)
  let first_items_ok = case first_items_to_preserve == 0 {
    True -> True
    False -> first_ids != [] && list.all(first_ids, fn(id) { has_item_id(depth_all, id) })
  }
  let anchors_shallow_ok =
    list.all(anchor_fragments, fn(fragment) {
      has_title_fragment(items_1, fragment)
      || has_title_fragment(items_2, fragment)
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
    key
      <> " ("
      <> name
      <> "): source limit exceeded ("
      <> int.to_string(source_limit)
      <> ")",
  )
}

fn add_validation_error(
  errors: List(String),
  condition: Bool,
  line: String,
) -> List(String) {
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
  timing_spec: source_specs.SourceTimingSpec,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  let source_specs.SourceTimingSpec(max_concurrency, requests_per_second) =
    timing_spec
  let queue_policy = queue_policy_for_cache_mode(
    cache_mode,
    max_concurrency,
    requests_per_second,
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
        spotify_live_expander.read_access_token_file(
          ".spotify_oauth_session.json",
        )
      let config =
        spotify_live_expander.spotify_config(
          access_token: access_token,
          session_file: ".spotify_oauth_session.json",
          client_id: spotify_live_expander.read_env_value(
            ".env",
            "SPOTIFY_CLIENT_ID",
          ),
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
    "tuna" -> tuna_normalized_source.resolve(depth, cache_mode, on_debug)
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

fn to_track_view(
  item: core.UnifiedItem,
  adapter_id: String,
) -> visual_output.TrackView {
  let core.UnifiedItem(_, title, artist, service, _, source_id) = item
  visual_output.TrackView(title, artist, service, source_id, adapter_id, "", "")
}

fn to_tuna_track_view(
  item: core.UnifiedItem,
  adapter_id: String,
  metadata_rows: List(TunaRowMetadata),
) -> visual_output.TrackView {
  let core.UnifiedItem(_, title, artist, service, _, source_id) = item
  let TunaRowMetadata(_, _, download, tags) =
    tuna_metadata_for(metadata_rows, service, source_id)
  visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    adapter_id,
    download,
    tags,
  )
}

type TunaRowMetadata {
  TunaRowMetadata(
    service: String,
    source_id: String,
    file_path: String,
    tags: String,
  )
}

fn adapter_id_for_source(source_type: String, entry_point: String) -> String {
  source_type <> " + " <> entry_point
}

fn tuna_row_metadata(cache_mode: cache.CacheMode) -> List(TunaRowMetadata) {
  let payload = cached_tuna_tracks_source_ids_json(cache_mode)
  let rows = decode_dynamic_rows(payload)
  list.fold(rows, [], fn(acc, row) {
    let file_path = decode_path_or(row, ["file_path"], "", decode.string)
    let tags = tuna_tags_with_rating(row)
    let acc =
      push_tuna_metadata(acc, row, "spotify", "spotify_id", file_path, tags)
    let acc =
      push_tuna_metadata(acc, row, "youtube", "youtube_id", file_path, tags)
    let acc =
      push_tuna_metadata(
        acc,
        row,
        "soundcloud",
        "soundcloud_id",
        file_path,
        tags,
      )
    let acc =
      push_tuna_metadata(
        acc,
        row,
        "bandcamp",
        "bandcamp_track_id",
        file_path,
        tags,
      )
    let acc = push_tuna_metadata(acc, row, "file", "file_path", file_path, tags)
    let acc =
      push_tuna_metadata(acc, row, "itunes", "itunes_track_id", file_path, tags)
    push_tuna_metadata(
      acc,
      row,
      "itunes",
      "itunes_persistent_track_id",
      file_path,
      tags,
    )
  })
}

fn cached_tuna_tracks_source_ids_json(cache_mode: cache.CacheMode) -> String {
  cache.read_or_fetch(
    "tuna_tracks_source_ids_enriched_json",
    "tuna_main_default_track_sources_enriched",
    cache_mode,
    fn() { tracks_source_ids_json() },
  )
}

fn push_tuna_metadata(
  acc: List(TunaRowMetadata),
  row: dynamic.Dynamic,
  service: String,
  id_key: String,
  file_path: String,
  tags: String,
) -> List(TunaRowMetadata) {
  let raw_source_id = decode_path_or(row, [id_key], "", decode.string)
  let source_id = normalize_tuna_metadata_source_id(service, raw_source_id)
  case source_id == "" {
    True -> acc
    False ->
      case
        list.any(acc, fn(meta) {
          let TunaRowMetadata(existing_service, existing_source_id, _, _) = meta
          existing_service == service && existing_source_id == source_id
        })
      {
        True -> acc
        False ->
          list.append(acc, [
            TunaRowMetadata(service, source_id, file_path, tags),
          ])
      }
  }
}

pub fn normalize_tuna_metadata_source_id(
  service: String,
  source_id: String,
) -> String {
  source_id_normalizer.normalize(service, source_id)
}

fn tuna_metadata_for(
  rows: List(TunaRowMetadata),
  service: String,
  source_id: String,
) -> TunaRowMetadata {
  rows
  |> list.filter(fn(row) {
    let TunaRowMetadata(row_service, row_source_id, _, _) = row
    row_service == service && row_source_id == source_id
  })
  |> list.first
  |> result.unwrap(TunaRowMetadata(service, source_id, "", ""))
}

fn tuna_tags_with_rating(row: dynamic.Dynamic) -> String {
  let rating = decode_path_or(row, ["rating"], 0, decode.int)
  normalize_tuna_tags(tuna_tag_labels(row), rating)
}

fn tuna_tag_labels(row: dynamic.Dynamic) -> List(String) {
  decode_path_or(row, ["tags"], [], decode.list(of: decode.dynamic))
  |> list.map(fn(tag) { decode_path_or(tag, ["label"], "", decode.string) })
  |> list.filter(fn(label) { label != "" })
}

pub fn normalize_tuna_tags(tags: List(String), rating: Int) -> String {
  let rating_tag = "rating:" <> int.to_string(rating)
  let normalized_tags =
    tags
    |> list.filter(fn(tag) {
      !string.starts_with(string.lowercase(tag), "rating")
    })
  string.join(list.append(normalized_tags, [rating_tag]), " | ")
}

pub fn format_tuna_source_id(service: String, source_id: String) -> String {
  let _ = service
  source_id
}

fn decode_dynamic_rows(payload: String) -> List(dynamic.Dynamic) {
  case json.parse(sanitize_json_payload(payload), decode.dynamic) {
    Error(_) -> []
    Ok(value) ->
      decode.run(value, decode.list(of: decode.dynamic)) |> result.unwrap([])
  }
}

fn sanitize_json_payload(payload: String) -> String {
  let cleaned = string.trim(payload)
  case string.split_once(cleaned, "[") {
    Ok(#(_, after)) -> "[" <> after
    Error(_) ->
      case string.split_once(cleaned, "{") {
        Ok(#(_, after)) -> "{" <> after
        Error(_) -> cleaned
      }
  }
}

fn decode_path_or(
  data: dynamic.Dynamic,
  path: List(String),
  fallback: a,
  decoder: decode.Decoder(a),
) -> a {
  decode.run(data, decode.optionally_at(path, fallback, decoder))
  |> result.unwrap(fallback)
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

fn source_by_selector(
  sources: List(source_specs.SourceSpec),
  wanted: String,
) -> Result(#(Int, source_specs.SourceSpec), Nil) {
  let maybe_index = case int.parse(wanted) {
    Ok(index) -> Some(index)
    Error(_) -> None
  }
  case maybe_index {
    Some(index) ->
      case source_at(sources, index, 1) {
        Ok(source) -> Ok(#(index, source))
        Error(_) -> Error(Nil)
      }
    None ->
      case source_by_key_with_index(sources, wanted, 1) {
        Ok(indexed) -> Ok(indexed)
        Error(_) ->
          case parse_provider_alias(wanted) {
            Ok(#(provider_key, rank)) ->
              source_by_provider_rank(sources, provider_key, rank, 1, 0)
            Error(_) -> Error(Nil)
          }
      }
  }
}

fn source_by_key_with_index(
  sources: List(source_specs.SourceSpec),
  wanted: String,
  current: Int,
) -> Result(#(Int, source_specs.SourceSpec), Nil) {
  case sources {
    [] -> Error(Nil)
    [source, ..rest] -> {
      let source_specs.SourceSpec(key, _, _, _, _) = source
      case key == wanted {
        True -> Ok(#(current, source))
        False -> source_by_key_with_index(rest, wanted, current + 1)
      }
    }
  }
}

fn source_by_provider_rank(
  sources: List(source_specs.SourceSpec),
  wanted_key: String,
  wanted_rank: Int,
  current: Int,
  matched_rank: Int,
) -> Result(#(Int, source_specs.SourceSpec), Nil) {
  case sources {
    [] -> Error(Nil)
    [source, ..rest] -> {
      let source_specs.SourceSpec(key, _, _, _, _) = source
      case key == wanted_key && matched_rank + 1 == wanted_rank {
        True -> Ok(#(current, source))
        False ->
          source_by_provider_rank(
            rest,
            wanted_key,
            wanted_rank,
            current + 1,
            case key == wanted_key {
              True -> matched_rank + 1
              False -> matched_rank
            },
          )
      }
    }
  }
}

fn parse_provider_alias(value: String) -> Result(#(String, Int), Nil) {
  let parts = string.split(value, "-")
  case list.reverse(parts) {
    [rank_text, ..key_rev] ->
      case key_rev == [] {
        True -> Error(Nil)
        False ->
          case int.parse(rank_text) {
            Ok(rank) ->
              case rank >= 1 {
                True -> Ok(#(string.join(list.reverse(key_rev), "-"), rank))
                False -> Error(Nil)
              }
            Error(_) -> Error(Nil)
          }
      }
    _ -> Error(Nil)
  }
}

fn provider_rank_for_index(
  sources: List(source_specs.SourceSpec),
  wanted_key: String,
  wanted_index: Int,
  current_index: Int,
  current_rank: Int,
) -> Int {
  case sources {
    [] -> current_rank
    [source, ..rest] -> {
      let source_specs.SourceSpec(key, _, _, _, _) = source
      let next_rank = case key == wanted_key {
        True -> current_rank + 1
        False -> current_rank
      }
      case current_index == wanted_index {
        True -> next_rank
        False ->
          provider_rank_for_index(
            rest,
            wanted_key,
            wanted_index,
            current_index + 1,
            next_rank,
          )
      }
    }
  }
}

fn cache_mode_text(value: cache.CacheMode) -> String {
  case value {
    cache.CacheUpsert -> "upsert"
    cache.CacheIgnore -> "ignore"
    cache.CacheOverride -> "override"
    cache.CacheReadOnly -> "readonly"
  }
}

fn queue_policy_for_cache_mode(
  cache_mode: cache.CacheMode,
  max_concurrency: Int,
  requests_per_second: Int,
) -> core.QueuePolicy {
  case cache_mode {
    // Cache-only runs should not pay network rate-limit sleeps.
    cache.CacheReadOnly ->
      core.QueuePolicy(max_concurrency: 1000, requests_per_second: 10000)
    _ ->
      core.QueuePolicy(
        max_concurrency: max_concurrency,
        requests_per_second: requests_per_second,
      )
  }
}

pub fn tracks_json(tracks: List(visual_output.TrackView)) -> String {
  json.array(tracks, of: track_json) |> json.to_string
}

fn track_json(track: visual_output.TrackView) -> json.Json {
  let visual_output.TrackView(
    title,
    artist,
    service,
    source_id,
    adapter_id,
    download,
    tags,
  ) = track
  json.object([
    #("title", json.string(title)),
    #("artist", json.string(artist)),
    #("service", json.string(service)),
    #("source_id", json.string(source_id)),
    #("adapter_id", json.string(adapter_id)),
    #("file", nullable_file_json(download)),
    #("tags", json.array(export_tags(tags), of: json.string)),
  ])
}

pub fn export_tags(tags: String) -> List(String) {
  tags
  |> string.split("|")
  |> list.map(string.trim)
  |> list.filter(fn(tag) { tag != "" })
}

pub fn nullable_file_path(path: String) -> Option(String) {
  let cleaned = string.trim(path)
  case cleaned == "" {
    True -> None
    False -> Some(cleaned)
  }
}

fn nullable_file_json(path: String) -> json.Json {
  case nullable_file_path(path) {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn artifact_path(file_name: String) -> String {
  "output/" <> file_name
}

fn print_exit_signal() {
  io.println("CLI_EXIT:0")
}

fn print_usage() {
  io.println(color("Usage:", ansi_bright_cyan()))
  io.println(
    "  cli fetch <source> [override-cache|use-cache]",
  )
  io.println("")
  io.println(color("Examples:", ansi_bright_cyan()))
  io.println(
    "  gleam run -m cli -- fetch spotify                 # full depth, override cache",
  )
  io.println(
    "  gleam run -m cli -- fetch spotify use-cache       # full depth from cache",
  )
  io.println("")
  io.println(color("Tip:", ansi_bright_cyan()))
  io.println(
    "  source can be all, index (1), id (spotify), or provider alias (spotify-2).",
  )
}

fn color(text: String, code: String) -> String {
  code <> text <> ansi_reset()
}

fn ansi_reset() -> String {
  "\u{001b}[0m"
}

fn ansi_bright_cyan() -> String {
  "\u{001b}[96m"
}

fn ansi_yellow() -> String {
  "\u{001b}[33m"
}

fn ansi_green() -> String {
  "\u{001b}[32m"
}

fn ansi_red() -> String {
  "\u{001b}[31m"
}
