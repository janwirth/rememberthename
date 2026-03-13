import adapters/cache
import cli
import gleeunit

@external(erlang, "test_runtime", "run_live_perf_tests")
fn run_live_perf_tests() -> Bool

pub fn main() {
  gleeunit.main()
}

pub fn tuna_export_json_under_500ms_test() {
  case run_live_perf_tests() {
    False -> Nil
    True -> {
      let elapsed_ms = cli.tuna_export_duration_ms(cache.CacheReadOnly)
      assert elapsed_ms < 500
    }
  }
}
