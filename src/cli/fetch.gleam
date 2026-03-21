import adapters/cache
import adapters/core
import fetch_ops
import gleam/dict.{type Dict}
import gleam/io
import output/visual_output.{type TrackView}
import source_specs

/// Parses optional cache flags after `fetch <source>`, then runs the fetch.
pub fn fetch_source_simple(selector: String, args: List(String)) {
  case parse_fetch_args(args) {
    Error(message) -> io.println(message)
    Ok(use_cache) -> {
      let cache_mode = case use_cache {
        True -> cache.CacheReadOnly
        False -> cache.CacheOverride
      }
      let on_update = fn(line) { io.println(line) }
      case fetch_ops.fetch_with_cache_mode(selector, cache_mode, on_update) {
        Error(msg) -> io.println(msg)
        Ok(Nil) -> Nil
      }
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
) -> #(List(TrackView), Dict(String, Int)) {
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
