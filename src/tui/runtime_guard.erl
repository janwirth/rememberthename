-module(runtime_guard).
-export([run/2]).

run(RunFun, CleanupFun) ->
    try
        RunFun()
    after
        CleanupFun()
    end.
