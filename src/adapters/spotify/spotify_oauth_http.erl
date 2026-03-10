-module(spotify_oauth_http).
%% Spotify OAuth helper functions (server is implemented in Gleam/mist).
-export([open_url/1, redeem_code/4, write_file/2]).

open_url(Url) ->
    try
        _ = os:cmd(binary_to_list(<<"open \"", (iolist_to_binary(Url))/binary, "\"">>)),
        <<"ok">>
    catch
        _:_ -> <<"error">>
    end.

redeem_code(ClientId, ClientSecret, RedirectUri, Code) ->
    EncCode = uri_string:quote(Code),
    EncRedirect = uri_string:quote(RedirectUri),
    CmdBin = <<
        "/usr/bin/curl -L -s -X POST \"https://accounts.spotify.com/api/token\" ",
        "-u \"", (iolist_to_binary(ClientId))/binary, ":", (iolist_to_binary(ClientSecret))/binary, "\" ",
        "-H \"Content-Type: application/x-www-form-urlencoded\" ",
        "-d \"grant_type=authorization_code&code=", EncCode/binary, "&redirect_uri=", EncRedirect/binary, "\""
    >>,
    unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin))).

write_file(Path, Contents) ->
    case file:write_file(iolist_to_binary(Path), iolist_to_binary(Contents)) of
        ok -> <<"ok">>;
        _ -> <<"error">>
    end.
