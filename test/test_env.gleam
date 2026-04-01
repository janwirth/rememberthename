import envoy
import gleam/string

pub fn run_live_tests() -> Bool {
  truthy_env("RUN_LIVE_TESTS")
}

pub fn run_live_perf_tests() -> Bool {
  truthy_env("RUN_LIVE_PERF_TESTS")
}

fn truthy_env(name: String) -> Bool {
  case envoy.get(name) {
    Ok(v) ->
      case string.lowercase(string.trim(v)) {
        "1" -> True
        "true" -> True
        _ -> False
      }
    Error(_) -> False
  }
}
