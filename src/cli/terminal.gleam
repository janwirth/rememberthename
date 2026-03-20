import gleam/io

/// Prints a fixed `CLI_EXIT:0` line for wrappers/tests to detect clean exit.
pub fn print_exit_signal() {
  io.println("CLI_EXIT:0")
}

/// Help text: usage line, examples, and source selector tips.
pub fn print_usage() {
  io.println(color("Usage:", ansi_bright_cyan()))
  io.println(
    "  cli fetch <source> [override-cache|use-cache]",
  )
  io.println("")
  io.println(color("Examples:", ansi_bright_cyan()))
  io.println(
    "  gleam run -m cli -- fetch spotify                 # full depth, override cache",
  )
  io.println(
    "  gleam run -m cli -- fetch spotify use-cache       # full depth from cache",
  )
  io.println("")
  io.println(color("Tip:", ansi_bright_cyan()))
  io.println(
    "  source can be all, index (1), id (spotify), or provider alias (spotify-2).",
  )
}

/// Wraps `text` with an ANSI SGR prefix and reset.
pub fn color(text: String, code: String) -> String {
  code <> text <> ansi_reset()
}

/// Resets terminal attributes to default.
pub fn ansi_reset() -> String {
  "\u{001b}[0m"
}

/// Bright cyan SGR for headings.
pub fn ansi_bright_cyan() -> String {
  "\u{001b}[96m"
}

/// Yellow SGR for labels and durations.
pub fn ansi_yellow() -> String {
  "\u{001b}[33m"
}

/// Green SGR for success lines.
pub fn ansi_green() -> String {
  "\u{001b}[32m"
}

/// Red SGR for validation failure.
pub fn ansi_red() -> String {
  "\u{001b}[31m"
}
