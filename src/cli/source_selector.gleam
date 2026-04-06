import gleam/int
import gleam/list
import source_root

/// `triples`: `source_root.ordered_selector_triples(source_specs.all())` → `#(key, root, assert)`.
///
/// `wanted` is either a **1-based index** (`"1"` …) or the **source key** (`bandcamp`, `spotify`, …).
pub fn triple_by_selector(
  triples: List(#(String, source_root.SourceRoot, source_root.SourceAssertSpec)),
  wanted: String,
) -> Result(
  #(Int, String, source_root.SourceRoot, source_root.SourceAssertSpec),
  Nil,
) {
  case int.parse(wanted) {
    Ok(i) if i >= 1 ->
      case list.drop(triples, i - 1) {
        [#(key, root, assert_spec), ..] -> Ok(#(i, key, root, assert_spec))
        [] -> Error(Nil)
      }
    _ -> find_key(triples, wanted, 1)
  }
}

fn find_key(
  triples: List(#(String, source_root.SourceRoot, source_root.SourceAssertSpec)),
  wanted: String,
  one_based: Int,
) -> Result(
  #(Int, String, source_root.SourceRoot, source_root.SourceAssertSpec),
  Nil,
) {
  case triples {
    [] -> Error(Nil)
    [#(key, root, assert_spec), ..rest] ->
      case key == wanted {
        True -> Ok(#(one_based, key, root, assert_spec))
        False -> find_key(rest, wanted, one_based + 1)
      }
  }
}
