import argv as argv_loader
import gleam/time/timestamp

/// Raw command-line arguments from the runtime (via `argv` package).
pub fn argv() -> List(String) {
  argv_loader.load().arguments
}

/// Wall-clock time in milliseconds (suitable for durations in normal runs).
pub fn now_ms() -> Int {
  let t = timestamp.system_time()
  let #(s, ns) = timestamp.to_unix_seconds_and_nanoseconds(t)
  s * 1000 + ns / 1_000_000
}
