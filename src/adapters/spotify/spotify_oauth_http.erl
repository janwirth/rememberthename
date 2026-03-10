-module(spotify_oauth_http).
%% Spotify OAuth helper functions (server is implemented in Gleam/mist).
-export([open_url/1]).

open_url(Url) ->
    try
        _ = os:cmd(binary_to_list(<<"open \"", (iolist_to_binary(Url))/binary, "\"">>)),
        <<"ok">>
    catch
        _:_ -> <<"error">>
    end.
