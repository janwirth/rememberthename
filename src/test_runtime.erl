-module(test_runtime).
-export([now_ms/0, run_live_perf_tests/0, run_live_tests/0]).

now_ms() ->
    erlang:monotonic_time(millisecond).

run_live_perf_tests() ->
    case os:getenv("RUN_LIVE_PERF_TESTS") of
        false -> false;
        "1" -> true;
        "true" -> true;
        "TRUE" -> true;
        _ -> false
    end.

run_live_tests() ->
    case os:getenv("RUN_LIVE_TESTS") of
        false -> false;
        "1" -> true;
        "true" -> true;
        "TRUE" -> true;
        _ -> false
    end.
