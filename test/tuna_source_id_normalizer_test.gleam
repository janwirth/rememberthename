import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import adapters/tuna/tracks_source_ids_query
import gleam/list
import gleam/result
import source_id_normalizer
import test_env

pub fn live_tuna_source_ids_normalize_when_available_test() {
  case test_env.run_live_perf_tests() {
    False -> Nil
    True -> {
      let raw = tracks_source_ids_query.fetch_tracks_source_ids_json()
      assert raw != ""

      let decoded =
        json.parse(raw, decode.dynamic) |> result.unwrap(dynamic.nil())
      let rows =
        decode.run(decoded, decode.list(of: decode.dynamic))
        |> result.unwrap([])

      let pairs =
        list.fold(rows, [], fn(acc, row) {
          let acc =
            push_if_present(
              acc,
              "spotify",
              decode_path_or(row, ["spotify_id"], "", decode.string),
            )
          let acc =
            push_if_present(
              acc,
              "youtube",
              decode_path_or(row, ["youtube_id"], "", decode.string),
            )
          let acc =
            push_if_present(
              acc,
              "soundcloud",
              decode_path_or(row, ["soundcloud_id"], "", decode.string),
            )
          let acc =
            push_if_present(
              acc,
              "bandcamp",
              decode_path_or(row, ["bandcamp_track_id"], "", decode.string),
            )
          let acc =
            push_if_present(
              acc,
              "file",
              decode_path_or(row, ["file_path"], "", decode.string),
            )
          let acc =
            push_if_present(
              acc,
              "itunes",
              decode_path_or(row, ["itunes_track_id"], "", decode.string),
            )
          push_if_present(
            acc,
            "itunes",
            decode_path_or(
              row,
              ["itunes_persistent_track_id"],
              "",
              decode.string,
            ),
          )
        })

      assert pairs != []
      assert list.all(pairs, fn(pair) {
        let #(service, source_id) = pair
        source_id_normalizer.normalize(service, source_id) != ""
      })
    }
  }
}

fn push_if_present(
  acc: List(#(String, String)),
  service: String,
  source_id: String,
) -> List(#(String, String)) {
  case source_id == "" {
    True -> acc
    False -> [#(service, source_id), ..acc]
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
