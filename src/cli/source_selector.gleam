import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import source_specs

/// 1-based linear search: returns the spec at position `wanted` or error.
pub fn source_at(
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

/// Resolves `wanted` as numeric index, bare provider key, or `key-rank` alias.
pub fn source_by_selector(
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

/// First list entry whose `key` equals `wanted`, with its 1-based index.
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

/// Picks the `wanted_rank`-th source among those sharing `wanted_key` (in list order).
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
