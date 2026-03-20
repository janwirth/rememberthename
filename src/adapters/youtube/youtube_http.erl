-module(youtube_http).
%% YouTube playlist fetch + continuation via HTTP requests.
%% Contract: depth1 first surface, depth2 continuation.
-export([
    playlist_first_tsv/1,
    playlist_first_next_token/1,
    playlist_api_key/1,
    playlist_client_version/1,
    playlist_title/1,
    continuation_tsv/3,
    continuation_next_token/3
]).

playlist_first_tsv(Url) ->
    with_initial_data(Url, fun(InitialData) ->
        run_jq_on_json(
            InitialData,
            ".contents.twoColumnBrowseResultsRenderer.tabs[]?.tabRenderer.content.sectionListRenderer.contents[]?.itemSectionRenderer.contents[]?.playlistVideoListRenderer.contents[] | .playlistVideoRenderer? | select(.) | [(.videoId // \"\"), (.title.runs[0].text // \"\"), (.shortBylineText.runs[0].text // \"unknown\")] | @tsv"
        )
    end).

playlist_first_next_token(Url) ->
    with_initial_data(Url, fun(InitialData) ->
        trim(
            run_jq_on_json(
                InitialData,
                "[.. | .continuationCommand?.token? // empty] | .[0] // \"\""
            )
        )
    end).

playlist_title(Url) ->
    with_initial_data(Url, fun(InitialData) ->
        trim(run_jq_on_json(InitialData, ".metadata.playlistMetadataRenderer.title // \"\""))
    end).

playlist_api_key(Url) ->
    Html = fetch(Url),
    trim(extract_between(Html, <<"\"INNERTUBE_API_KEY\":\"">>, <<"\"">>)).

playlist_client_version(Url) ->
    Html = fetch(Url),
    trim(extract_between(Html, <<"\"INNERTUBE_CLIENT_VERSION\":\"">>, <<"\"">>)).

continuation_tsv(ApiKey, ClientVersion, Token) ->
    case post_continuation(ApiKey, ClientVersion, Token) of
        <<>> ->
            <<>>;
        Json ->
            run_jq_on_json(
                Json,
                ".onResponseReceivedActions[]?.appendContinuationItemsAction?.continuationItems[] | .playlistVideoRenderer? | select(.) | [(.videoId // \"\"), (.title.runs[0].text // \"\"), (.shortBylineText.runs[0].text // \"unknown\")] | @tsv"
            )
    end.

continuation_next_token(ApiKey, ClientVersion, Token) ->
    case post_continuation(ApiKey, ClientVersion, Token) of
        <<>> ->
            <<>>;
        Json ->
            trim(
                run_jq_on_json(
                    Json,
                    "[.. | .continuationCommand?.token? // empty] | .[0] // \"\""
                )
            )
    end.

with_initial_data(Url, Fun) ->
    Html = fetch(Url),
    case extract_initial_data(Html) of
        <<>> -> <<>>;
        InitialData -> Fun(InitialData)
    end.

fetch(Url) when is_binary(Url) ->
    try
        CmdBin = <<"/usr/bin/curl -L -s --max-time 20 \"", Url/binary, "\"">>,
        unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin)))
    catch
        _:_ -> <<>>
    end;
fetch(Url) ->
    fetch(iolist_to_binary(Url)).

post_continuation(ApiKey, ClientVersion, Token) ->
    try
        Url = <<"https://www.youtube.com/youtubei/v1/browse?key=", ApiKey/binary>>,
        Body = <<
            "{\"context\":{\"client\":{\"clientName\":\"WEB\",\"clientVersion\":\"",
            ClientVersion/binary,
            "\"}},\"continuation\":\"",
            Token/binary,
            "\"}"
        >>,
        CmdBin = <<
            "/usr/bin/curl -L -s --max-time 20 -X POST -H \"content-type: application/json\" -H \"user-agent: Mozilla/5.0\" --data '",
            Body/binary,
            "' \"",
            Url/binary,
            "\""
        >>,
        unicode:characters_to_binary(os:cmd(binary_to_list(CmdBin)))
    catch
        _:_ -> <<>>
    end.

extract_initial_data(Html) ->
    case extract_between(Html, <<"var ytInitialData = ">>, <<";</script>">>) of
        <<>> ->
            extract_between(Html, <<"window[\"ytInitialData\"] = ">>, <<";</script>">>);
        Json ->
            Json
    end.

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
    %% Ephemeral jq input only — persistent caching is SQLite via adapters/cache (Gleam).
    TmpPath = temp_jq_path(),
    case file:write_file(TmpPath, Json) of
        ok ->
            try
                Cmd =
                    "/opt/homebrew/bin/jq -r '" ++
                        Filter ++
                        "' '" ++
                        TmpPath ++
                        "'",
                unicode:characters_to_binary(os:cmd(Cmd))
            after
                _ = file:delete(TmpPath)
            end;
        _ ->
            <<>>
    end.

temp_jq_path() ->
    TmpDir =
        case os:getenv("TMPDIR") of
            false -> "/tmp";
            "" -> "/tmp";
            D -> D
        end,
    filename:join([
        TmpDir,
        "rememberthename_jq_" ++
            integer_to_list(erlang:unique_integer([positive])) ++ ".json"
    ]).

trim(Value) ->
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(Value))).
