//// EdgeQL payload for listing all tuna `Tag` rows.

import shellout

pub fn fetch_tags_catalog_json() -> String {
  case
    shellout.command(
      "gel",
      [
        "-I", "tuna", "-b", "main", "query", "--output-format=json",
        tags_catalog_edgeql,
      ],
      in: ".",
      opt: [],
    )
  {
    Ok(out) -> out
    Error(_) -> ""
  }
}

const tags_catalog_edgeql: String =
  "select Tag { label, emoji } order by .label;"
