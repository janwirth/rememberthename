-module(spotify_http).
%% Spotify public user/profile HTTP helpers.
-export([
    extract_access_token/1,
    user_playlists_json/3,
    playlist_tracks_json/3,
    playlists_tsv/1,
    playlists_next_offset/1,
    tracks_tsv/1,
    tracks_next_offset/1
]).

extract_access_token(UserUrl) ->
    Html = fetch(UserUrl),
    trim(extract_between(Html, <<"\"accessToken\":\"">>, <<"\"">>)).

user_playlists_json(UserId, Token, Offset) ->
    Url = <<
        "https://api.spotify.com/v1/users/",
        UserId/binary,
        "/playlists?limit=50&offset=",
        (int_to_bin(Offset))/binary
    >>,
    api_get(Url, Token).

playlist_tracks_json(PlaylistId, Token, Offset) ->
    Url = <<
        "https://api.spotify.com/v1/playlists/",
        PlaylistId/binary,
        "/tracks?limit=100&offset=",
        (int_to_bin(Offset))/binary
    >>,
    api_get(Url, Token).

playlists_tsv(Json) ->
    run_jq_on_json(
        Json,
        ".items[]? | [(.id // \"\"), (.name // \"\")] | @tsv"
    ).

playlists_next_offset(Json) ->
    trim(
        run_jq_on_json(
            Json,
            "(.offset // 0) as $o | (.limit // 0) as $l | (.next // null) | if . == null then \"\" else (($o + $l) | tostring) end"
        )
    ).

tracks_tsv(Json) ->
    run_jq_on_json(
        Json,
        ".items[]? | .track? | select(.) | [(.id // \"\"), (.name // \"\"), (.artists[0].name // \"unknown\")] | @tsv"
    ).

tracks_next_offset(Json) ->
    trim(
        run_jq_on_json(
            Json,
            "(.offset // 0) as $o | (.limit // 0) as $l | (.next // null) | if . == null then \"\" else (($o + $l) | tostring) end"
        )
    ).

api_get(Url, Token) ->
    try
        CachePath = cache_path(<<"api:", Url/binary, "|", Token/binary>>),
        case file:read_file(CachePath) of
            {ok, Cached} when byte_size(Cached) > 0 ->
                Cached;
            _ ->
                CmdBin = <<
                    "/usr/bin/curl -L -s --max-time 20 -H \"Authorization: Bearer ",
                    Token/binary,
                    "\" \"",
                    Url/binary,
                    "\""
                >>,
                Resp = unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin))),
                case byte_size(Resp) > 0 of
                    true ->
                        _ = file:write_file(CachePath, Resp),
                        Resp;
                    false ->
                        <<>>
                end
        end
    catch
        _:_ -> <<>>
    end.

fetch(Url) when is_binary(Url) ->
    try
        CachePath = cache_path(<<"url:", Url/binary>>),
        case file:read_file(CachePath) of
            {ok, Cached} when byte_size(Cached) > 0 ->
                Cached;
            _ ->
                CmdBin = <<"/usr/bin/curl -L -s --max-time 20 \"", Url/binary, "\"">>,
                Resp = unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin))),
                case byte_size(Resp) > 0 of
                    true ->
                        _ = file:write_file(CachePath, Resp),
                        Resp;
                    false ->
                        <<>>
                end
        end
    catch
        _:_ -> <<>>
    end;
fetch(Url) ->
    fetch(iolist_to_binary(Url)).

extract_between(Body, Start, Ending) ->
    case binary:split(Body, Start) of
        [_Before, Tail] ->
            case binary:split(Tail, Ending) of
                [Value | _] -> Value;
                _ -> <<>>
            end;
        _ ->
            <<>>
    end.

run_jq_on_json(Json, Filter) ->
    try
        CachePath = cache_path(Json),
        _ = file:write_file(CachePath, Json),
        Cmd =
            "/opt/homebrew/bin/jq -r '" ++
            Filter ++
            "' '" ++
            CachePath ++
            "'",
        unicode:characters_to_binary(os:cmd(Cmd))
    catch
        _:_ -> <<>>
    end.

cache_path(Blob) ->
    Hash = integer_to_list(erlang:phash2(Blob)),
    "/tmp/rememberthename_spotify_cache_" ++ Hash ++ ".json".

trim(Value) ->
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(Value))).

int_to_bin(Int) ->
    unicode:characters_to_binary(integer_to_list(Int)).
