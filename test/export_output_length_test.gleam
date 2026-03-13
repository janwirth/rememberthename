import gleam/list
import gleam/string
import simplifile

pub fn all_items_latest_csv_has_expected_line_count_test() {
  let expected_lines = 11_445
  let actual_lines = case simplifile.read(from: "output/all_items_latest.csv") {
    Ok(content) -> list.length(string.split(content, "\n"))
    Error(_) -> 0
  }
  assert actual_lines == expected_lines
}
