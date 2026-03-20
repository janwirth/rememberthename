/// Raw command-line arguments from the Erlang runtime (`argv`).
@external(erlang, "cli_runtime_args", "argv")
pub fn argv() -> List(String)

/// Monotonic clock in milliseconds (for durations and probes).
@external(erlang, "cli_runtime_args", "now_ms")
pub fn now_ms() -> Int
