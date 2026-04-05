import adapters/cache
import adapters/core
import cli/fetch_orchestration
import gleam/io
import gleam/list
import output/visual_output

/// Parses optional flags after `fetch <source>`, then runs the fetch.
pub fn fetch_source_simple(selector: String, args: List(String)) {
  case parse_fetch_args(args) {
    Error(message) -> io.println(message)
    Ok(fetch_args) -> {
      let FetchArgs(use_cache, shallow, validate) = fetch_args
      let cache_mode = case use_cache {
        True -> cache.CacheReadOnly
        False -> cache.CacheOverride
      }
      case shallow {
        True ->
          fetch_source_shallow_with_cache_mode(
            selector,
            cache_mode,
            validate,
            fn(line) { io.println(line) },
          )
        False -> {
          let on_update = fn(line) { io.println(line) }
          case fetch_orchestration.fetch_with_cache_mode(
            selector,
            cache_mode,
            validate,
            on_update,
          ) {
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
    Ok(#(selector, validate)) ->
      fetch_source_shallow_with_cache_mode(
        selector,
        cache.CacheOverride,
        validate,
        fn(line) { io.println(line) },
      )
  }
}

fn fetch_source_shallow_with_cache_mode(
  selector: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_print: fn(String) -> Nil,
) {
  case fetch_orchestration.fetch_source_tracks_with_depth(
    selector,
    core.Depth1,
    "shallow",
    cache_mode,
    True,
    always_validate,
    on_print,
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
  let added_str = core.added_at_display(added_at)
  let added_suffix = case added_str == "" {
    True -> ""
    False -> " · added_at: " <> added_str
  }
  title <> " - " <> artist <> " [" <> service <> "]" <> added_suffix
}

type FetchArgs {
  FetchArgs(use_cache: Bool, shallow: Bool, validate: Bool)
}

fn parse_fetch_args(args: List(String)) -> Result(FetchArgs, String) {
  let validate = list.any(args, fn(a) { a == "--validate" })
  let shallow =
    list.any(args, fn(a) { a == "shallow" || a == "--shallow" })
  let wants_use = list.any(args, fn(a) { a == "use-cache" })
  let wants_override = list.any(args, fn(a) { a == "override-cache" })
  case wants_use && wants_override {
    True -> Error("Use only one of use-cache or override-cache.")
    False -> {
      let use_cache = wants_use
      let unknown =
        list.filter(args, fn(a) {
          a != "use-cache"
          && a != "override-cache"
          && a != "shallow"
          && a != "--shallow"
          && a != "--validate"
        })
      case unknown {
        [] -> Ok(FetchArgs(use_cache, shallow, validate))
        _ -> Error(fetch_arg_error_text())
      }
    }
  }
}

fn parse_shallow_args(args: List(String)) -> Result(#(String, Bool), String) {
  let validate = list.any(args, fn(a) { a == "--validate" })
  let rest = list.filter(args, fn(a) { a != "--validate" })
  case rest {
    [] -> Ok(#("1", validate))
    [selector] -> Ok(#(selector, validate))
    _ -> Error("Too many args. Use: cli shallow [--validate] [source]")
  }
}

fn fetch_arg_error_text() -> String {
  "Invalid fetch args. Use: cli fetch <source> [override-cache|use-cache] [--shallow] [--validate]"
}

pub fn fetch_with_cache_mode(
  selector: String,
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) -> Result(Nil, String) {
  fetch_orchestration.fetch_with_cache_mode(
    selector,
    cache_mode,
    always_validate,
    on_update,
  )
}

pub fn fetch_all_sources(
  cache_mode: cache.CacheMode,
  always_validate: Bool,
  on_update: fn(String) -> Nil,
) {
  fetch_orchestration.fetch_all_sources(cache_mode, always_validate, on_update)
}

