import adapters/cache
import rememberthename_cli
import gleeunit
import test_env

pub fn main() {
  gleeunit.main()
}

pub fn tuna_export_json_under_500ms_test() {
  case test_env.run_live_perf_tests() {
    False -> Nil
    True -> {
      let elapsed_ms = rememberthename_cli.tuna_export_duration_ms(cache.CacheReadOnly)
      assert elapsed_ms < 500
    }
  }
}
