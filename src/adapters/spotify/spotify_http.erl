-module(spotify_http).
%% Spotify public user/profile HTTP helpers.
-export([
    liked_tracks_json/2,
    tracks_tsv/1
]).

liked_tracks_json(Token, Offset) ->
    Url = <<
        "https://api.spotify.com/v1/me/tracks?limit=50&offset=",
        (int_to_bin(Offset))/binary
    >>,
    api_get(Url, Token).

tracks_tsv(Json) ->
    run_jq_on_json(
        Json,
        ".items[]? | .track? | select(.) | [(.id // \"\"), (.name // \"\"), (.artists[0].name // \"unknown\")] | @tsv"
    ).

api_get(Url, Token) ->
    try
        CmdBin = <<
            "/usr/bin/curl -L -s --max-time 20 -H \"Authorization: Bearer ",
            Token/binary,
            "\" \"",
            Url/binary,
            "\""
        >>,
        unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin)))
    catch
        _:_ -> <<>>
    end.

run_jq_on_json(Json, Filter) ->
    try
        TempPath = "/tmp/rememberthename_spotify_jq.json",
        _ = file:write_file(TempPath, Json),
        Cmd =
            "/opt/homebrew/bin/jq -r '" ++
            Filter ++
            "' '" ++
            TempPath ++
            "'",
        unicode:characters_to_binary(os:cmd(Cmd))
    catch
        _:_ -> <<>>
    end.

int_to_bin(Int) ->
    unicode:characters_to_binary(integer_to_list(Int)).

