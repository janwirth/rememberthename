-module(soundcloud_http).
% Spec integration:
% - Transport helper for adapter implementation (SPEC.md tech stack section).
% - Provides cached GET/POST fetch and jq extractors used by SoundCloud/Bandcamp expanders.
-export([
    fetch/1,
    post_json/2,
    json_next_href/1,
    json_next_href_from_json/1,
    json_tracks_tsv/1,
    json_tracks_tsv_from_json/1,
    json_playlist_ids/1,
    json_playlist_ids_from_json/1,
    json_title/1,
    json_title_from_json/1,
    json_track_ids/1,
    json_track_ids_from_json/1
]).

fetch(Url) ->
    try
        BinUrl = iolist_to_binary(Url),
        CmdBin = <<"/usr/bin/curl -L -s --max-time 20 \"", BinUrl/binary, "\"">>,
        unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin)))
    catch
        _:_ -> <<>>
    end.

post_json(Url, Body) ->
    try
        BinUrl = iolist_to_binary(Url),
        BinBody = iolist_to_binary(Body),
        CmdBin = <<
            "/usr/bin/curl -L -s --max-time 20 -X POST -H \"content-type: application/json\" --data '",
            BinBody/binary,
            "' \"",
            BinUrl/binary,
            "\""
        >>,
        unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin)))
    catch
        _:_ -> <<>>
    end.

json_next_href(Url) ->
    json_next_href_from_json(fetch(Url)).

json_next_href_from_json(Json) ->
    run_jq_json(Json, ".next_href // \"\"").

json_tracks_tsv(Url) ->
    json_tracks_tsv_from_json(fetch(Url)).

json_tracks_tsv_from_json(Json) ->
    run_jq_json(
        Json,
        ".collection[] | (if .track then .track elif .kind==\"track\" then . elif .origin and .origin.track then .origin.track else empty end) | [(.id|tostring), (.title // \"\"), (.user.username // \"unknown\")] | @tsv"
    ).

json_playlist_ids(Url) ->
    json_playlist_ids_from_json(fetch(Url)).

json_playlist_ids_from_json(Json) ->
    run_jq_json(
        Json,
        ".collection[] | (if .playlist then .playlist elif .kind==\"playlist\" then . else empty end) | (.id|tostring)"
    ).

json_title(Url) ->
    json_title_from_json(fetch(Url)).

json_title_from_json(Json) ->
    run_jq_json(Json, ".title // \"\"").

json_track_ids(Url) ->
    json_track_ids_from_json(fetch(Url)).

json_track_ids_from_json(Json) ->
    run_jq_json(Json, ".tracks[]?.id | tostring").

run_jq_json(Json, Filter) ->
    try
        {ok, Cwd} = file:get_cwd(),
        TempPath = filename:join(Cwd, "rememberthename_soundcloud_jq.json"),
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
