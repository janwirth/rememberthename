-module(soundcloud_http).
% Spec integration:
% - Transport helper for adapter implementation (SPEC.md tech stack section).
% - Provides cached GET/POST fetch and jq extractors used by SoundCloud/Bandcamp expanders.
-export([
    fetch/1,
    post_json/2,
    json_next_href/1,
    json_tracks_tsv/1,
    json_playlist_ids/1,
    json_title/1,
    json_track_ids/1
]).

fetch(Url) ->
    try
        BinUrl = iolist_to_binary(Url),
        CachePath = ensure_cached(BinUrl),
        case file:read_file(CachePath) of
            {ok, Cached} when byte_size(Cached) > 0 ->
                Cached;
            _ -> <<>>
        end
    catch
        _:_ -> <<>>
    end.

post_json(Url, Body) ->
    try
        BinUrl = iolist_to_binary(Url),
        BinBody = iolist_to_binary(Body),
        CachePath = post_cache_path(BinUrl, BinBody),
        case file:read_file(CachePath) of
            {ok, Cached} when byte_size(Cached) > 0 ->
                Cached;
            _ ->
                CmdBin = <<
                    "/usr/bin/curl -L -s -X POST -H \"content-type: application/json\" --data '",
                    BinBody/binary,
                    "' \"",
                    BinUrl/binary,
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

json_next_href(Url) ->
    run_jq(Url, ".next_href // \"\"").

json_tracks_tsv(Url) ->
    run_jq(
        Url,
        ".collection[] | (if .track then .track elif .kind==\"track\" then . elif .origin and .origin.track then .origin.track else empty end) | [(.id|tostring), (.title // \"\"), (.user.username // \"unknown\")] | @tsv"
    ).

json_playlist_ids(Url) ->
    run_jq(
        Url,
        ".collection[] | (if .playlist then .playlist elif .kind==\"playlist\" then . else empty end) | (.id|tostring)"
    ).

json_title(Url) ->
    run_jq(Url, ".title // \"\"").

json_track_ids(Url) ->
    run_jq(Url, ".tracks[]?.id | tostring").

run_jq(Url, Filter) ->
    try
        BinUrl = iolist_to_binary(Url),
        CachePath = ensure_cached(BinUrl),
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

ensure_cached(BinUrl) ->
    CachePath = cache_path(BinUrl),
    case file:read_file(CachePath) of
        {ok, Cached} when byte_size(Cached) > 0 ->
            CachePath;
        _ ->
            CmdBin = <<"/usr/bin/curl -L -s \"", BinUrl/binary, "\"">>,
            Body = unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin))),
            case byte_size(Body) > 0 of
                true ->
                    _ = file:write_file(CachePath, Body),
                    CachePath;
                false ->
                    CachePath
            end
    end.

cache_path(UrlBin) ->
    Hash = integer_to_list(erlang:phash2(UrlBin)),
    "/tmp/rememberthename_http_cache_" ++ Hash ++ ".json".

post_cache_path(UrlBin, BodyBin) ->
    Hash = integer_to_list(erlang:phash2(<<UrlBin/binary, "||", BodyBin/binary>>)),
    "/tmp/rememberthename_http_post_cache_" ++ Hash ++ ".json".
