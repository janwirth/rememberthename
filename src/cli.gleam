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
import output/csv_writer
import output/visual_output
import simplifile
import source_specs

@external(erlang, "cli_runtime_args", "argv")
fn argv() -> List(String)

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
  let source_specs.SourceSpec(key, name, entry_point, _, _) = source
  io.println("Fetching source " <> int.to_string(source_index) <> ": " <> name)
  io.println("Depth: " <> depth_label)
  io.println("Cache: " <> cache_mode_text(cache_mode))
  io.println("")

  let result =
    resolve_source(
      key,
      entry_point,
      depth,
      cache_mode,
      fn(line) { io.println(line) },
    )

  let core.ResolveResult(items, lists, unresolved) = result
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
  let all_specs = source_specs.all()
  let all_items =
    collect_items_from_specs(all_specs, [])
    |> list.append(collect_tuna_items())
  let tracks = list.map(all_items, to_track_view)
  let csv = csv_writer.tracks_csv(tracks)
  let csv_path = artifact_path("all_items_latest.csv")
  let _ = simplifile.write(csv, to: csv_path)
  io.println(
    "Done. Exported "
    <> int.to_string(list.length(all_items))
    <> " items to "
    <> csv_path,
  )
}

fn collect_items_from_specs(
  specs: List(source_specs.SourceSpec),
  acc: List(core.UnifiedItem),
) -> List(core.UnifiedItem) {
  case specs {
    [] -> acc
    [source, ..rest] -> {
      let source_specs.SourceSpec(key, name, entry_point, _, _) = source
      io.println("  - " <> name)
      let core.ResolveResult(items, _, _) =
        resolve_source(
          key,
          entry_point,
          core.All,
          cache.CacheOverride,
          fn(_line) { Nil },
        )
      collect_items_from_specs(rest, list.append(acc, items))
    }
  }
}

fn collect_tuna_items() -> List(core.UnifiedItem) {
  io.println("  - Tuna")
  let core.ResolveResult(items, _, _) =
    tuna_normalized_source.resolve(core.All, cache.CacheOverride, fn(_line) { Nil })
  items
}

fn resolve_source(
  key: String,
  entry_point: String,
  depth: core.DepthMode,
  cache_mode: cache.CacheMode,
  on_debug: fn(String) -> Nil,
) -> core.ResolveResult {
  case key {
    "bandcamp" -> {
      let profile = bandcamp_live_expander.bandcamp_profile(entry_point)
      bandcamp_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        cache_mode,
        on_debug,
      )
    }
    "soundcloud" -> {
      let profile = soundcloud_live_expander.soundcloud_profile(entry_point)
      soundcloud_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        cache_mode,
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
      spotify_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        config,
        cache_mode,
        on_debug,
      )
    }
    _ -> {
      let profile = youtube_live_expander.youtube_playlist(entry_point)
      youtube_live_expander.resolve_profile_with_debug(
        profile,
        depth,
        cache_mode,
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
