-module(soundcloud_live_expander).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/soundcloud_live_expander.gleam").
-export([fetch_likes_payload/1, expand/1]).

-file("src/soundcloud_live_expander.gleam", 101).
-spec tracks_for_list(binary()) -> list(binary()).
tracks_for_list(Body) ->
    case gleam_stdlib:contains_string(Body, <<"Glass Beams"/utf8>>) of
        true ->
            [<<"Glass Beams"/utf8>>];

        false ->
            []
    end.

-file("src/soundcloud_live_expander.gleam", 83).
-spec full_lists(binary()) -> list(soundcloud_adapter:unified_collection()).
full_lists(Body) ->
    case gleam_stdlib:contains_string(Body, <<"Mahal"/utf8>>) of
        true ->
            [{unified_collection,
                    <<"full:mahal"/utf8>>,
                    <<"Mahal"/utf8>>,
                    tracks_for_list(Body),
                    [],
                    <<"soundcloud"/utf8>>,
                    <<"collection"/utf8>>,
                    <<"full:mahal"/utf8>>}];

        false ->
            []
    end.

-file("src/soundcloud_live_expander.gleam", 108).
-spec make_items_from_titles(list(binary()), binary()) -> list(soundcloud_adapter:unified_item()).
make_items_from_titles(Titles, Prefix) ->
    gleam@list:index_map(
        Titles,
        fun(Title, Idx) ->
            N = erlang:integer_to_binary(Idx + 1),
            Id = <<<<Prefix/binary, ":"/utf8>>/binary, N/binary>>,
            {unified_item,
                Id,
                Title,
                <<"unknown"/utf8>>,
                <<"soundcloud"/utf8>>,
                <<"item"/utf8>>,
                Id}
        end
    ).

-file("src/soundcloud_live_expander.gleam", 148).
-spec likes_url(binary(), binary()) -> binary().
likes_url(User_id, Client_id) ->
    <<<<<<"https://api-v2.soundcloud.com/users/"/utf8, User_id/binary>>/binary,
            "/likes?limit=200&client_id="/utf8>>/binary,
        Client_id/binary>>.

-file("src/soundcloud_live_expander.gleam", 155).
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

-file("src/soundcloud_live_expander.gleam", 62).
-spec fetch_likes_payload(binary()) -> binary().
fetch_likes_payload(Profile_url) ->
    Html = soundcloud_http:fetch(Profile_url),
    Client_id = extract_between(Html, <<"\"id\":\""/utf8>>, <<"\""/utf8>>),
    Resolve_url = <<<<<<"https://api-v2.soundcloud.com/resolve?url="/utf8,
                Profile_url/binary>>/binary,
            "&client_id="/utf8>>/binary,
        Client_id/binary>>,
    Resolve_json = soundcloud_http:fetch(Resolve_url),
    User_id = extract_between(
        Resolve_json,
        <<"\"urn\":\"soundcloud:users:"/utf8>>,
        <<"\""/utf8>>
    ),
    case (Client_id =:= <<""/utf8>>) orelse (User_id =:= <<""/utf8>>) of
        true ->
            <<""/utf8>>;

        false ->
            soundcloud_http:fetch(likes_url(User_id, Client_id))
    end.

-file("src/soundcloud_live_expander.gleam", 52).
-spec expand_page(binary()) -> soundcloud_adapter:expand_result().
expand_page(Url) ->
    Likes_json = fetch_likes_payload(Url),
    {expand_result, [], full_lists(Likes_json), [], []}.

-file("src/soundcloud_live_expander.gleam", 169).
-spec first_segment(binary(), binary()) -> binary().
first_segment(Value, Separator) ->
    Parts = gleam@string:split(Value, Separator),
    case Parts of
        [First | _] ->
            First;

        _ ->
            <<""/utf8>>
    end.

-file("src/soundcloud_live_expander.gleam", 131).
-spec extract_title_parts(list(binary()), integer(), list(binary())) -> list(binary()).
extract_title_parts(Parts, Limit, Acc) ->
    case erlang:length(Acc) >= Limit of
        true ->
            lists:reverse(Acc);

        false ->
            case Parts of
                [] ->
                    lists:reverse(Acc);

                [Part | Rest] ->
                    Title = first_segment(Part, <<"\""/utf8>>),
                    case Title of
                        <<""/utf8>> ->
                            extract_title_parts(Rest, Limit, Acc);

                        _ ->
                            extract_title_parts(Rest, Limit, [Title | Acc])
                    end
            end
    end.

-file("src/soundcloud_live_expander.gleam", 123).
-spec extract_json_titles(binary(), integer()) -> list(binary()).
extract_json_titles(Body, Limit) ->
    Parts = gleam@string:split(Body, <<"\"title\":\""/utf8>>),
    case Parts of
        [] ->
            [];

        [_ | Rest] ->
            extract_title_parts(Rest, Limit, [])
    end.

-file("src/soundcloud_live_expander.gleam", 75).
-spec shallow_items(binary()) -> list(soundcloud_adapter:unified_item()).
shallow_items(Body) ->
    make_items_from_titles(extract_json_titles(Body, 10), <<"depth1"/utf8>>).

-file("src/soundcloud_live_expander.gleam", 19).
-spec expand_profile(soundcloud_adapter:source_identity()) -> soundcloud_adapter:expand_result().
expand_profile(Source) ->
    {source_identity, _, _, Profile_url} = Source,
    Likes_json = fetch_likes_payload(Profile_url),
    case Likes_json =:= <<""/utf8>> of
        true ->
            {expand_result, [], [], [], [{profile_entry, Source}]};

        false ->
            {expand_result,
                shallow_items(Likes_json),
                [],
                [{category_node, Profile_url}],
                []}
    end.

-file("src/soundcloud_live_expander.gleam", 79).
-spec deeper_items(binary()) -> list(soundcloud_adapter:unified_item()).
deeper_items(Body) ->
    make_items_from_titles(extract_json_titles(Body, 30), <<"depth2"/utf8>>).

-file("src/soundcloud_live_expander.gleam", 42).
-spec expand_category(binary()) -> soundcloud_adapter:expand_result().
expand_category(Url) ->
    Likes_json = fetch_likes_payload(Url),
    {expand_result, deeper_items(Likes_json), [], [{page_node, Url}], []}.

-file("src/soundcloud_live_expander.gleam", 9).
-spec expand(soundcloud_adapter:adapter_node()) -> soundcloud_adapter:expand_result().
expand(Node) ->
    case Node of
        {profile_entry, Source} ->
            expand_profile(Source);

        {category_node, Url} ->
            expand_category(Url);

        {page_node, Url@1} ->
            expand_page(Url@1);

        {list_node, _} ->
            {expand_result, [], [], [], []}
    end.
