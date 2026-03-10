-module(soundcloud_http).
-export([fetch/1]).

fetch(Url) ->
    try
        BinUrl = iolist_to_binary(Url),
        CmdBin = <<"/usr/bin/curl -L -s \"", BinUrl/binary, "\"">>,
        unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin)))
    catch
        _:_ -> <<>>
    end.
