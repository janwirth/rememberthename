-module(soundcloud_http).
-export([fetch/1]).

fetch(Url) ->
    try
        BinUrl = iolist_to_binary(Url),
        CachePath = cache_path(BinUrl),
        case file:read_file(CachePath) of
            {ok, Cached} when byte_size(Cached) > 0 ->
                Cached;
            _ ->
                CmdBin = <<"/usr/bin/curl -L -s \"", BinUrl/binary, "\"">>,
                Body = unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin))),
                case byte_size(Body) > 0 of
                    true ->
                        _ = file:write_file(CachePath, Body),
                        Body;
                    false ->
                        <<>>
                end
        end
    catch
        _:_ -> <<>>
    end.

cache_path(UrlBin) ->
    Hash = integer_to_list(erlang:phash2(UrlBin)),
    "/tmp/rememberthename_http_cache_" ++ Hash ++ ".json".
