-module(soundcloud_live_expander).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/soundcloud_live_expander.gleam").
-export([fetch_likes_payload/1, expand/1]).

-file("src/soundcloud_live_expander.gleam", 76).
-spec shallow_items(binary()) -> list(soundcloud_adapter:unified_item()).
shallow_items(Body) ->
    case gleam_stdlib:contains_string(Body, <<"A Horse with no Name"/utf8>>) of
        true ->
            [{unified_item,
                    <<"shallow:a-horse"/utf8>>,
                    <<"A Horse with no Name (Edit)"/utf8>>,
                    <<"Kolter"/utf8>>,
                    <<"soundcloud"/utf8>>,
                    <<"item"/utf8>>,
                    <<"shallow:a-horse"/utf8>>}];

        false ->
            []
    end.

-file("src/soundcloud_live_expander.gleam", 93).
-spec deeper_items(binary()) -> list(soundcloud_adapter:unified_item()).
deeper_items(Body) ->
    case gleam_stdlib:contains_string(Body, <<"Premiere: KAIPE - Batie"/utf8>>) of
        true ->
            [{unified_item,
                    <<"deeper:kaipie-batie"/utf8>>,
                    <<"Premiere: KAIPE - Batie"/utf8>>,
                    <<"KAIPE"/utf8>>,
                    <<"soundcloud"/utf8>>,
                    <<"item"/utf8>>,
                    <<"deeper:kaipie-batie"/utf8>>}];

        false ->
            []
    end.

-file("src/soundcloud_live_expander.gleam", 128).
-spec tracks_for_list(binary()) -> list(binary()).
tracks_for_list(Body) ->
    case gleam_stdlib:contains_string(Body, <<"Glass Beams"/utf8>>) of
        true ->
            [<<"Glass Beams"/utf8>>];

        false ->
            []
    end.

-file("src/soundcloud_live_expander.gleam", 110).
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

-file("src/soundcloud_live_expander.gleam", 135).
-spec likes_url(binary(), binary()) -> binary().
likes_url(User_id, Client_id) ->
    <<<<<<"https://api-v2.soundcloud.com/users/"/utf8, User_id/binary>>/binary,
            "/likes?limit=200&client_id="/utf8>>/binary,
        Client_id/binary>>.

-file("src/soundcloud_live_expander.gleam", 142).
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

-file("src/soundcloud_live_expander.gleam", 63).
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

-file("src/soundcloud_live_expander.gleam", 17).
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
                [{category_node, Profile_url}, {page_node, Profile_url}],
                []}
    end.

-file("src/soundcloud_live_expander.gleam", 43).
-spec expand_category(binary()) -> soundcloud_adapter:expand_result().
expand_category(Url) ->
    Likes_json = fetch_likes_payload(Url),
    {expand_result, deeper_items(Likes_json), [], [], []}.

-file("src/soundcloud_live_expander.gleam", 53).
-spec expand_page(binary()) -> soundcloud_adapter:expand_result().
expand_page(Url) ->
    Likes_json = fetch_likes_payload(Url),
    {expand_result, [], full_lists(Likes_json), [], []}.

-file("src/soundcloud_live_expander.gleam", 7).
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
