-module(runtime_otp).
-export([otp_major/0]).

otp_major() ->
    Release = erlang:system_info(otp_release),
    case string:to_integer(unicode:characters_to_list(Release)) of
        {Major, _Rest} -> Major;
        _ -> 0
    end.
