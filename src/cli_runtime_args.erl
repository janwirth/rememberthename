-module(cli_runtime_args).
-export([argv/0, now_ms/0]).

argv() ->
    [unicode:characters_to_binary(Arg) || Arg <- init:get_plain_arguments()].

now_ms() ->
    erlang:monotonic_time(millisecond).
