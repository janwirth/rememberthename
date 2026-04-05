import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import source_root
import source_specs

/// Parses strings like `spotify-2` into provider key and 1-based duplicate rank.
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

/// How many sources with `wanted_key` occur up to and including `wanted_index`.
pub fn provider_rank_for_index(
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

/// Resolves `wanted` selector against an ordered registry list, returning `#(index, key, root, assert_spec)`.
///
/// Supports numeric index, bare key, and `key-rank` alias (`spotify-2`).
pub fn triple_by_selector(
  triples: List(#(String, source_root.SourceRoot, source_specs.SourceAssertSpec)),
  wanted: String,
) -> Result(
  #(Int, String, source_root.SourceRoot, source_specs.SourceAssertSpec),
  Nil,
) {
  let keys = list.map(triples, fn(t) { t.0 })
  let maybe_index = case int.parse(wanted) {
    Ok(i) -> Some(i)
    Error(_) -> None
  }
  let resolve_index = fn(index) {
    case list.drop(triples, index - 1) {
      [#(key, root, assert_spec), ..] -> Ok(#(index, key, root, assert_spec))
      [] -> Error(Nil)
    }
  }
  case maybe_index {
    Some(index) -> resolve_index(index)
    None ->
      case key_index_in_list(keys, wanted, 1) {
        Ok(index) -> resolve_index(index)
        Error(_) ->
          case parse_provider_alias(wanted) {
            Ok(#(provider_key, rank)) ->
              key_rank_index(keys, provider_key, rank, 1, 0)
              |> result.map(resolve_index)
              |> result.flatten
            Error(_) -> Error(Nil)
          }
      }
  }
}

fn key_index_in_list(
  keys: List(String),
  wanted: String,
  current: Int,
) -> Result(Int, Nil) {
  case keys {
    [] -> Error(Nil)
    [key, ..rest] ->
      case key == wanted {
        True -> Ok(current)
        False -> key_index_in_list(rest, wanted, current + 1)
      }
  }
}

fn key_rank_index(
  keys: List(String),
  wanted_key: String,
  wanted_rank: Int,
  current: Int,
  matched_rank: Int,
) -> Result(Int, Nil) {
  case keys {
    [] -> Error(Nil)
    [key, ..rest] ->
      case key == wanted_key && matched_rank + 1 == wanted_rank {
        True -> Ok(current)
        False ->
          key_rank_index(
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
