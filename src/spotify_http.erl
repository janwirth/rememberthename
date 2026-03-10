-module(spotify_http).
%% Spotify public user/profile HTTP helpers.
-export([
    read_access_token_file/1,
    ensure_access_token/5,
    user_playlists_json/3,
    playlist_tracks_json/3,
    playlists_tsv/1,
    playlists_next_offset/1,
    tracks_tsv/1,
    tracks_next_offset/1
]).

read_access_token_file(SessionFile) ->
    try
        case file:read_file(SessionFile) of
            {ok, Body} when byte_size(Body) > 0 ->
                Token = trim(extract_between(Body, <<"\"access_token\":\"">>, <<"\"">>)),
                case Token of
                    <<>> -> trim(Body);
                    _ -> Token
                end;
            _ ->
                <<>>
        end
    catch
        _:_ -> <<>>
    end.

ensure_access_token(ProvidedToken, SessionFile, ClientId, RedirectUri, Scopes) ->
    case trim(ProvidedToken) of
        <<>> ->
            case read_access_token_file(SessionFile) of
                <<>> ->
                    log_oauth_flow(SessionFile, ClientId, RedirectUri, Scopes),
                    <<>>;
                TokenFromFile ->
                    TokenFromFile
            end;
        Token ->
            Token
    end.

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

log_oauth_flow(SessionFile, ClientId, RedirectUri, Scopes) ->
    EncRedirect = url_encode(redirect_bin(RedirectUri)),
    EncScopes = url_encode(iolist_to_binary(Scopes)),
    AuthUrl = <<
        "https://accounts.spotify.com/authorize?client_id=",
        (iolist_to_binary(ClientId))/binary,
        "&response_type=token&redirect_uri=",
        EncRedirect/binary,
        "&scope=",
        EncScopes/binary,
        "&show_dialog=true"
    >>,
    io:format("~n[spotify-oauth] No session found at ~s~n", [SessionFile]),
    io:format("[spotify-oauth] Open this URL and authorize:~n~s~n", [AuthUrl]),
    io:format("[spotify-oauth] Then store JSON in session file:~n", []),
    io:format("{\"access_token\":\"<token-from-redirect-fragment>\",\"token_type\":\"Bearer\"}~n", []),
    io:format("[spotify-oauth] Session file path: ~s~n~n", [SessionFile]),
    _ = os:cmd(binary_to_list(<<"open \"", AuthUrl/binary, "\"">>)),
    ok.

redirect_bin(Value) when is_binary(Value) -> Value;
redirect_bin(Value) -> iolist_to_binary(Value).

url_encode(Bin) ->
    list_to_binary(uri_string:quote(binary_to_list(Bin))).
