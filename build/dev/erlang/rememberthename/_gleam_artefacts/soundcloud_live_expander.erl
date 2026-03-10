-module(soundcloud_live_expander).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/soundcloud_live_expander.gleam").
-export([expand/1, fetch_likes_payload/1]).

-file("src/soundcloud_live_expander.gleam", 177).
-spec likes_start_url(binary(), binary()) -> binary().
likes_start_url(User_id, Client_id) ->
    <<<<<<<<"https://api-v2.soundcloud.com/users/"/utf8, User_id/binary>>/binary,
                "/likes?client_id="/utf8>>/binary,
            Client_id/binary>>/binary,
        "&limit=50&offset=0&linked_partitioning=1&app_version=1772785214&app_locale=en"/utf8>>.

-file("src/soundcloud_live_expander.gleam", 185).
-spec reposts_start_url(binary(), binary()) -> binary().
reposts_start_url(User_id, Client_id) ->
    <<<<<<<<"https://api-v2.soundcloud.com/stream/users/"/utf8, User_id/binary>>/binary,
                "/reposts?client_id="/utf8>>/binary,
            Client_id/binary>>/binary,
        "&limit=50&offset=0&linked_partitioning=1&app_version=1772785214&app_locale=en"/utf8>>.

-file("src/soundcloud_live_expander.gleam", 193).
-spec playlist_url(binary(), binary()) -> binary().
playlist_url(Playlist_id, Client_id) ->
    <<<<<<"https://api-v2.soundcloud.com/playlists/"/utf8, Playlist_id/binary>>/binary,
            "?client_id="/utf8>>/binary,
        Client_id/binary>>.

-file("src/soundcloud_live_expander.gleam", 197).
-spec ensure_client_id(binary(), binary()) -> binary().
ensure_client_id(Url, Client_id) ->
    case gleam_stdlib:contains_string(Url, <<"client_id="/utf8>>) of
        true ->
            Url;

        false ->
            <<<<Url/binary, "&client_id="/utf8>>/binary, Client_id/binary>>
    end.

-file("src/soundcloud_live_expander.gleam", 219).
-spec csv(list(binary())) -> binary().
csv(Values) ->
    gleam@string:join(Values, <<","/utf8>>).

-file("src/soundcloud_live_expander.gleam", 227).
-spec dedupe(list(binary()), list(binary())) -> list(binary()).
dedupe(Values, Acc) ->
    case Values of
        [] ->
            lists:reverse(Acc);

        [First | Rest] ->
            case gleam@list:contains(Acc, First) of
                true ->
                    dedupe(Rest, Acc);

                false ->
                    dedupe(Rest, [First | Acc])
            end
    end.

-file("src/soundcloud_live_expander.gleam", 223).
-spec merge_ids(list(binary()), list(binary())) -> list(binary()).
merge_ids(A, B) ->
    dedupe(lists:append(A, B), []).

-file("src/soundcloud_live_expander.gleam", 238).
-spec playlist_nodes(list(binary()), binary()) -> list(soundcloud_adapter:adapter_node()).
playlist_nodes(Ids, Client_id) ->
    gleam@list:map(
        Ids,
        fun(Id) ->
            {list_node,
                <<<<<<"playlist|"/utf8, Id/binary>>/binary, "|"/utf8>>/binary,
                    Client_id/binary>>}
        end
    ).

-file("src/soundcloud_live_expander.gleam", 242).
-spec trim(binary()) -> binary().
trim(Value) ->
    gleam@string:trim(Value).

-file("src/soundcloud_live_expander.gleam", 204).
-spec parse_lines(binary()) -> list(binary()).
parse_lines(Raw) ->
    Value = trim(Raw),
    case Value of
        <<""/utf8>> ->
            [];

        _ ->
            gleam@list:filter(
                gleam@string:split(Value, <<"\n"/utf8>>),
                fun(Line) -> Line /= <<""/utf8>> end
            )
    end.

-file("src/soundcloud_live_expander.gleam", 99).
-spec expand_playlist(binary()) -> soundcloud_adapter:expand_result().
expand_playlist(Ctx) ->
    Parts = gleam@string:split(Ctx, <<"|"/utf8>>),
    case Parts of
        [<<"playlist"/utf8>>, Playlist_id, Client_id] ->
            Url = playlist_url(Playlist_id, Client_id),
            Title = trim(soundcloud_http:json_title(Url)),
            Track_ids = parse_lines(soundcloud_http:json_track_ids(Url)),
            {expand_result,
                [],
                [{unified_collection,
                        <<"playlist:"/utf8, Playlist_id/binary>>,
                        Title,
                        Track_ids,
                        [],
                        <<"soundcloud"/utf8>>,
                        <<"collection"/utf8>>,
                        <<"playlist:"/utf8, Playlist_id/binary>>}],
                [],
                []};

        _ ->
            {expand_result, [], [], [], [{list_node, Ctx}]}
    end.

-file("src/soundcloud_live_expander.gleam", 155).
-spec parse_tracks(binary(), binary()) -> list(soundcloud_adapter:unified_item()).
parse_tracks(Url, Kind) ->
    Lines = parse_lines(soundcloud_http:json_tracks_tsv(Url)),
    gleam@list:index_map(
        Lines,
        fun(Line, Idx) ->
            Cols = gleam@string:split(Line, <<"\t"/utf8>>),
            {Id@3, Title@2, Artist@1} = case Cols of
                [Id, Title, Artist] ->
                    {Id, Title, Artist};

                [Id@1, Title@1] ->
                    {Id@1, Title@1, <<"unknown"/utf8>>};

                [Id@2] ->
                    {Id@2, <<"untitled"/utf8>>, <<"unknown"/utf8>>};

                _ ->
                    {<<<<Kind/binary, ":"/utf8>>/binary,
                            (erlang:integer_to_binary(Idx + 1))/binary>>,
                        <<"untitled"/utf8>>,
                        <<"unknown"/utf8>>}
            end,
            {unified_item,
                <<<<Kind/binary, ":"/utf8>>/binary, Id@3/binary>>,
                Title@2,
                Artist@1,
                <<"soundcloud"/utf8>>,
                <<"item"/utf8>>,
                <<<<Kind/binary, ":"/utf8>>/binary, Id@3/binary>>}
        end
    ).

-file("src/soundcloud_live_expander.gleam", 212).
-spec parse_csv(binary()) -> list(binary()).
parse_csv(Value) ->
    case trim(Value) of
        <<""/utf8>> ->
            [];

        _ ->
            gleam@list:filter(
                gleam@string:split(Value, <<","/utf8>>),
                fun(Part) -> Part /= <<""/utf8>> end
            )
    end.

-file("src/soundcloud_live_expander.gleam", 58).
-spec expand_category(binary()) -> soundcloud_adapter:expand_result().
expand_category(Ctx) ->
    Parts = gleam@string:split(Ctx, <<"|"/utf8>>),
    case Parts of
        [Kind, Url, Client_id, Acc_ids] ->
            Items = parse_tracks(Url, Kind),
            Page_playlist_ids = parse_lines(
                soundcloud_http:json_playlist_ids(Url)
            ),
            Merged_playlist_ids = merge_ids(
                parse_csv(Acc_ids),
                Page_playlist_ids
            ),
            Next_href = trim(soundcloud_http:json_next_href(Url)),
            case Next_href =:= <<""/utf8>> of
                true ->
                    {expand_result,
                        Items,
                        [],
                        playlist_nodes(Merged_playlist_ids, Client_id),
                        []};

                false ->
                    Next = ensure_client_id(Next_href, Client_id),
                    {expand_result,
                        Items,
                        [],
                        [{category_node,
                                <<<<<<<<<<<<Kind/binary, "|"/utf8>>/binary,
                                                    Next/binary>>/binary,
                                                "|"/utf8>>/binary,
                                            Client_id/binary>>/binary,
                                        "|"/utf8>>/binary,
                                    (csv(Merged_playlist_ids))/binary>>}],
                        []}
            end;

        _ ->
            {expand_result, [], [], [], [{category_node, Ctx}]}
    end.

-file("src/soundcloud_live_expander.gleam", 246).
-spec extract_between(binary(), binary(), binary()) -> binary().
extract_between(Body, Start, Ending) ->
    With_start = gleam@string:split(Body, Start),
    case With_start of
        [_, Tail | _] ->
            Before_end = gleam@string:split(Tail, Ending),
            case Before_end of
                [Value | _] ->
                    Value;

                _ ->
                    <<""/utf8>>
            end;

        _ ->
            <<""/utf8>>
    end.

-file("src/soundcloud_live_expander.gleam", 143).
-spec resolve_user_id(binary(), binary()) -> binary().
resolve_user_id(Profile_url, Client_id) ->
    case Client_id =:= <<""/utf8>> of
        true ->
            <<""/utf8>>;

        false ->
            Resolve_url = <<<<<<"https://api-v2.soundcloud.com/resolve?url="/utf8,
                        Profile_url/binary>>/binary,
                    "&client_id="/utf8>>/binary,
                Client_id/binary>>,
            Resolve_json = soundcloud_http:fetch(Resolve_url),
            extract_between(
                Resolve_json,
                <<"\"urn\":\"soundcloud:users:"/utf8>>,
                <<"\""/utf8>>
            )
    end.

-file("src/soundcloud_live_expander.gleam", 29).
-spec expand_profile(soundcloud_adapter:source_identity()) -> soundcloud_adapter:expand_result().
expand_profile(Source) ->
    {source_identity, _, _, Profile_url} = Source,
    Html = soundcloud_http:fetch(Profile_url),
    Client_id = extract_between(Html, <<"\"id\":\""/utf8>>, <<"\""/utf8>>),
    User_id = resolve_user_id(Profile_url, Client_id),
    case (Client_id =:= <<""/utf8>>) orelse (User_id =:= <<""/utf8>>) of
        true ->
            {expand_result, [], [], [], [{profile_entry, Source}]};

        false ->
            Likes_page = likes_start_url(User_id, Client_id),
            Reposts_page = reposts_start_url(User_id, Client_id),
            {expand_result,
                parse_tracks(Likes_page, <<"likes"/utf8>>),
                [],
                [{category_node,
                        <<<<<<<<"likes|"/utf8, Likes_page/binary>>/binary,
                                    "|"/utf8>>/binary,
                                Client_id/binary>>/binary,
                            "|"/utf8>>},
                    {category_node,
                        <<<<<<<<"reposts|"/utf8, Reposts_page/binary>>/binary,
                                    "|"/utf8>>/binary,
                                Client_id/binary>>/binary,
                            "|"/utf8>>}],
                []}
    end.

-file("src/soundcloud_live_expander.gleam", 19).
-spec expand(soundcloud_adapter:adapter_node()) -> soundcloud_adapter:expand_result().
expand(Node) ->
    case Node of
        {profile_entry, Source} ->
            expand_profile(Source);

        {category_node, Ctx} ->
            expand_category(Ctx);

        {list_node, Ctx@1} ->
            expand_playlist(Ctx@1);

        {page_node, _} ->
            {expand_result, [], [], [], []}
    end.

-file("src/soundcloud_live_expander.gleam", 133).
-spec fetch_likes_payload(binary()) -> binary().
fetch_likes_payload(Profile_url) ->
    Html = soundcloud_http:fetch(Profile_url),
    Client_id = extract_between(Html, <<"\"id\":\""/utf8>>, <<"\""/utf8>>),
    User_id = resolve_user_id(Profile_url, Client_id),
    case (Client_id =:= <<""/utf8>>) orelse (User_id =:= <<""/utf8>>) of
        true ->
            <<""/utf8>>;

        false ->
            soundcloud_http:fetch(likes_start_url(User_id, Client_id))
    end.
