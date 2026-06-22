import adapters/cache
import adapters/core as rtn_core
import dot_env as dot
import dot_env/env
import fetch_ops
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import simplifile
import source_root
import source_specs

const profile_dir = "/Users/janwirth/tuna/default"

const cloud_sources_path = "/Users/janwirth/tuna/default/cloud_sources.json"

const bc_timing = source_root.SourceTimingSpec(
  max_concurrency: 5,
  requests_per_second: 5,
)

const sc_timing = source_root.SourceTimingSpec(
  max_concurrency: 3,
  requests_per_second: 2,
)

type FetchMsg {
  FetchMsg(key: String, count: Int, err: String)
}

pub fn main() {
  io.println("=== parallel fetch test ===")

  let sources = build_sources()
  let n = list.length(sources)
  io.println("sources loaded: " <> int.to_string(n))
  list.each(sources, fn(s) { io.println("  " <> s.0) })

  let subj = process.new_subject()

  list.each(sources, fn(row) {
    let #(key, root) = row
    process.spawn_unlinked(fn() {
      io.println("[start] " <> key)
      case
        fetch_ops.fetch(root, cache.CacheOverride, fn(line) {
          case line {
            "" -> Nil
            _ -> io.println("[" <> key <> "] " <> line)
          }
        })
      {
        Ok(fetch_ops.FetchResult(items, _, _, _, _)) -> {
          let count = list.length(items)
          io.println("[done] " <> key <> " → " <> int.to_string(count))
          process.send(subj, FetchMsg(key, count, ""))
        }
        Error(msg) -> {
          io.println("[err] " <> key <> ": " <> msg)
          process.send(subj, FetchMsg(key, 0, msg))
        }
      }
    })
  })

  let results = collect(subj, n, [])

  io.println("\n=== summary ===")
  let passed =
    list.map(results, fn(r) {
      let min = threshold(r.key)
      let ok = r.err == "" && r.count >= min
      io.println(
        { case ok { True -> "PASS" False -> "FAIL" } }
        <> "  "
        <> r.key
        <> ": "
        <> int.to_string(r.count)
        <> " (min "
        <> int.to_string(min)
        <> ")"
        <> case r.err {
          "" -> ""
          e -> "  ERROR: " <> e
        },
      )
      ok
    })

  case list.all(passed, fn(x) { x }) {
    True -> io.println("\nALL PASSED")
    False -> io.println("\nSOME FAILED")
  }
}

fn build_sources() -> List(#(String, source_root.SourceRoot)) {
  let cloud_json = result.unwrap(simplifile.read(cloud_sources_path), "{}")
  let urls =
    result.unwrap(
      json.parse(cloud_json, decode.dict(decode.string, decode.string)),
      dict.new(),
    )

  let bc_purchases =
    dict.get(urls, "bandcamp_purchases")
    |> result.map(fn(u) {
      #(
        "bandcamp_purchases",
        source_root.BandcampRoot(string.trim(u), rtn_core.All, bc_timing, None),
      )
    })

  let bc_wishlist =
    dict.get(urls, "bandcamp_wishlist")
    |> result.map(fn(u) {
      #(
        "bandcamp_wishlist",
        source_root.BandcampRoot(string.trim(u), rtn_core.All, bc_timing, None),
      )
    })

  let sc =
    dict.get(urls, "soundcloud")
    |> result.map(fn(u) {
      #(
        "soundcloud",
        source_root.SoundcloudRoot(string.trim(u), rtn_core.All, sc_timing, None),
      )
    })

  // Load from bundled app .env so GOOGLE_CLOUD_API_KEY is available
  let bundled_env =
    "/Users/janwirth/all-tuna-versions/versions/tuna-2026-fs/electron/dist/mac-arm64/tuna.app/Contents/Resources/.env"
  let _ =
    dot.new() |> dot.set_path(bundled_env) |> dot.set_debug(False) |> dot.load
  let api_key = env.get_string_or("GOOGLE_CLOUD_API_KEY", "")
  let yt_url = result.unwrap(dict.get(urls, "youtube"), "")
  let youtube = case string.trim(api_key) != "" && string.trim(yt_url) != "" {
    True ->
      Ok(#(
        "youtube",
        source_root.YoutubeRoot(string.trim(yt_url), string.trim(api_key), None),
      ))
    False -> Error(Nil)
  }

  let spotify_rows =
    source_specs.all_configured_for_profile(profile_dir, None)
    |> list.filter_map(fn(row) {
      let #(key, root, _) = row
      case string.contains(string.lowercase(key), "spotify") {
        True -> Ok(#(key, root))
        False -> Error(Nil)
      }
    })

  [bc_purchases, bc_wishlist, sc, youtube]
  |> list.filter_map(fn(r) { r })
  |> list.append(spotify_rows)
}

fn collect(
  subj: process.Subject(FetchMsg),
  n: Int,
  acc: List(FetchMsg),
) -> List(FetchMsg) {
  case n {
    0 -> acc
    _ ->
      case process.receive(subj, 600_000) {
        Ok(msg) -> collect(subj, n - 1, [msg, ..acc])
        Error(Nil) -> {
          io.println("timeout!")
          acc
        }
      }
  }
}

fn threshold(key: String) -> Int {
  let k = string.lowercase(key)
  case
    string.contains(k, "purchases"),
    string.contains(k, "wishlist"),
    string.contains(k, "soundcloud"),
    string.contains(k, "youtube"),
    string.contains(k, "spotify")
  {
    True, _, _, _, _ -> 800
    _, True, _, _, _ -> 500
    _, _, True, _, _ -> 1000
    _, _, _, True, _ -> 1000
    _, _, _, _, True -> 1000
    _, _, _, _, _ -> 0
  }
}
