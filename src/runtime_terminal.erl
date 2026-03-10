-module(runtime_terminal).
-export([restore_shell/0]).

restore_shell() ->
    io:put_chars("\e[?25h\e[0m\e[?7h\e[?1049l"),
    _ = os:cmd("stty sane < /dev/tty 2>/dev/null"),
    ok.
