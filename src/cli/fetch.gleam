import adapters/cache
import adapters/core
import fetch_ops
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import output/visual_output
import source_specs

/// Parses optional cache flags after `fetch <source>`, then runs the fetch.
pub fn fetch_source_simple(selector: String, args: List(String)) {
  case parse_fetch_args(args) {
    Error(message) -> io.println(message)
    Ok(fetch_args) -> {
      let FetchArgs(use_cache, shallow) = fetch_args
      let cache_mode = case use_cache {
        True -> cache.CacheReadOnly
        False -> cache.CacheOverride
      }
      case shallow {
        True ->
          fetch_source_shallow_with_cache_mode(
            selector,
            cache_mode,
            fn(line) { io.println(line) },
          )
        False -> {
          let on_update = fn(line) { io.println(line) }
          case fetch_ops.fetch_with_cache_mode(selector, cache_mode, on_update) {
            Error(msg) -> io.println(msg)
            Ok(Nil) -> Nil
          }
        }
      }
    }
  }
}

pub fn fetch_source_shallow_simple(args: List(String)) {
  case parse_shallow_args(args) {
    Error(message) -> io.println(message)
    Ok(selector) ->
      fetch_source_shallow_with_cache_mode(
        selector,
        cache.CacheOverride,
        fn(line) { io.println(line) },
      )
  }
}

fn fetch_source_shallow_with_cache_mode(
  selector: String,
  cache_mode: cache.CacheMode,
  on_print: fn(String) -> Nil,
) {
  case fetch_ops.fetch_source_tracks_with_depth(
    selector,
    core.Depth1,
    "shallow",
    cache_mode,
    False,
    fn(_) { Nil },
  ) {
    Error(msg) -> on_print(msg)
    Ok(tracks) -> print_track_lines(tracks, on_print)
  }
}

fn print_track_lines(
  tracks: List(visual_output.TrackView),
  on_print: fn(String) -> Nil,
) {
  case tracks {
    [] -> on_print("(no tracks)")
    _ ->
      list.each(tracks, fn(track) {
        on_print(track_line(track))
      })
  }
}

fn track_line(track: visual_output.TrackView) -> String {
  let visual_output.TrackView(
    title,
    artist,
    service,
    _,
    _,
    added_at,
    _,
    _,
    _,
    _,
  ) = track
  let added_suffix = case added_at {
    "" -> ""
    value -> " · added_at: " <> value
  }
  title <> " - " <> artist <> " [" <> service <> "]" <> added_suffix
}

type FetchArgs {
  FetchArgs(use_cache: Bool, shallow: Bool)
}

fn parse_fetch_args(args: List(String)) -> Result(FetchArgs, String) {
  case args {
    [] -> Ok(FetchArgs(False, False))
    [arg1] ->
      parse_fetch_args_one(arg1)
    [arg1, arg2] -> parse_fetch_args_two(arg1, arg2)
    _ -> Error(fetch_arg_error_text())
  }
}

fn parse_fetch_cache_pref(value: String) -> Result(Bool, Nil) {
  case value {
    "use-cache" -> Ok(True)
    "override-cache" -> Ok(False)
    _ -> Error(Nil)
  }
}

fn parse_fetch_args_one(arg1: String) -> Result(FetchArgs, String) {
  case parse_fetch_cache_pref(arg1) {
    Ok(use_cache) -> Ok(FetchArgs(use_cache, False))
    Error(_) ->
      case is_shallow_flag(arg1) {
        True -> Ok(FetchArgs(False, True))
        False -> Error(fetch_arg_error_text())
      }
  }
}

fn parse_fetch_args_two(arg1: String, arg2: String) -> Result(FetchArgs, String) {
  case parse_fetch_cache_pref(arg1), parse_fetch_cache_pref(arg2) {
    Ok(use_cache), Error(_) ->
      case is_shallow_flag(arg2) {
        True -> Ok(FetchArgs(use_cache, True))
        False -> Error(fetch_arg_error_text())
      }
    Error(_), Ok(use_cache) ->
      case is_shallow_flag(arg1) {
        True -> Ok(FetchArgs(use_cache, True))
        False -> Error(fetch_arg_error_text())
      }
    _, _ -> Error(fetch_arg_error_text())
  }
}

fn parse_shallow_args(args: List(String)) -> Result(String, String) {
  case args {
    [] -> Ok("1")
    [selector] -> Ok(selector)
    _ -> Error("Too many args. Use: cli shallow [source]")
  }
}

fn is_shallow_flag(value: String) -> Bool {
  value == "shallow" || value == "--shallow"
}

fn fetch_arg_error_text() -> String {
  "Invalid fetch args. Use: cli fetch <source> [override-cache|use-cache] [--shallow]"
}

pub fn fetch_with_cache_mode(
  selector: String,
  cache_mode: cache.CacheMode,
  on_update: fn(String) -> Nil,
) -> Result(Nil, String) {
  fetch_ops.fetch_with_cache_mode(selector, cache_mode, on_update)
}

pub fn fetch_all_sources(
  cache_mode: cache.CacheMode,
  on_update: fn(String) -> Nil,
) {
  fetch_ops.fetch_all_sources(cache_mode, on_update)
}

pub fn run_fetch(
  source: source_specs.SourceSpec,
  source_index: Int,
  depth: core.DepthMode,
  depth_label: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) -> #(List(visual_output.TrackView), Dict(String, Int)) {
  fetch_ops.run_fetch(
    source,
    source_index,
    depth,
    depth_label,
    cache_mode,
    always_validate,
    True,
    on_update,
  )
}
