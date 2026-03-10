-module(bandcamp_live_expander).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bandcamp_live_expander.gleam").
-export([expand/1]).

-file("src/bandcamp_live_expander.gleam", 136).
-spec default_if_empty(binary(), binary()) -> binary().
default_if_empty(Value, Fallback) ->
    case Value of
        <<""/utf8>> ->
            Fallback;

        _ ->
            Value
    end.

-file("src/bandcamp_live_expander.gleam", 143).
-spec decode(binary()) -> binary().
decode(Value) ->
    _pipe = Value,
    _pipe@1 = gleam@string:replace(_pipe, <<"\\u0026"/utf8>>, <<"&"/utf8>>),
    _pipe@2 = gleam@string:replace(_pipe@1, <<"\\u003c"/utf8>>, <<"<"/utf8>>),
    _pipe@3 = gleam@string:replace(_pipe@2, <<"\\u003e"/utf8>>, <<">"/utf8>>),
    gleam@string:replace(_pipe@3, <<"\\\""/utf8>>, <<"\""/utf8>>).

-file("src/bandcamp_live_expander.gleam", 159).
-spec first_segment(binary(), binary()) -> binary().
first_segment(Value, Separator) ->
    Parts = gleam@string:split(Value, Separator),
    case Parts of
        [First | _] ->
            First;

        _ ->
            <<""/utf8>>
    end.

-file("src/bandcamp_live_expander.gleam", 151).
-spec extract_between(binary(), binary(), binary()) -> binary().
extract_between(Body, Start, Ending) ->
    With_start = gleam@string:split(Body, Start),
    case With_start of
        [_, Tail | _] ->
            first_segment(Tail, Ending);

        _ ->
            <<""/utf8>>
    end.

-file("src/bandcamp_live_expander.gleam", 104).
-spec parse_item_parts(
    list(binary()),
    binary(),
    list(soundcloud_adapter:unified_item())
) -> list(soundcloud_adapter:unified_item()).
parse_item_parts(Parts, Kind, Acc) ->
    case Parts of
        [] ->
            lists:reverse(Acc);

        [Part | Rest] ->
            Id = first_segment(Part, <<","/utf8>>),
            Item_type = extract_between(
                Part,
                <<"\"item_type\":\""/utf8>>,
                <<"\""/utf8>>
            ),
            Title = extract_between(
                Part,
                <<"\"item_title\":\""/utf8>>,
                <<"\""/utf8>>
            ),
            Artist = extract_between(
                Part,
                <<"\"band_name\":\""/utf8>>,
                <<"\""/utf8>>
            ),
            case ((Id =:= <<""/utf8>>) orelse (Item_type =:= <<""/utf8>>))
            orelse (Title =:= <<""/utf8>>) of
                true ->
                    parse_item_parts(Rest, Kind, Acc);

                false ->
                    Source = <<<<<<<<Kind/binary, ":"/utf8>>/binary,
                                Item_type/binary>>/binary,
                            ":"/utf8>>/binary,
                        Id/binary>>,
                    Item = {unified_item,
                        Source,
                        decode(Title),
                        decode(default_if_empty(Artist, <<"unknown"/utf8>>)),
                        <<"bandcamp"/utf8>>,
                        <<"item"/utf8>>,
                        Source},
                    parse_item_parts(Rest, Kind, [Item | Acc])
            end
    end.

-file("src/bandcamp_live_expander.gleam", 96).
-spec parse_items(binary(), binary()) -> list(soundcloud_adapter:unified_item()).
parse_items(Json, Kind) ->
    Parts = gleam@string:split(Json, <<"\"item_id\":"/utf8>>),
    case Parts of
        [] ->
            [];

        [_ | Rest] ->
            parse_item_parts(Rest, Kind, [])
    end.

-file("src/bandcamp_live_expander.gleam", 63).
-spec fetch_category_page(binary(), binary(), binary()) -> soundcloud_adapter:expand_result().
fetch_category_page(Kind, Fan_id, Token) ->
    Endpoint = case Kind of
        <<"collection"/utf8>> ->
            <<"https://bandcamp.com/api/fancollection/1/collection_items"/utf8>>;

        _ ->
            <<"https://bandcamp.com/api/fancollection/1/wishlist_items"/utf8>>
    end,
    Body = <<<<<<<<"{\"fan_id\":"/utf8, Fan_id/binary>>/binary,
                ",\"older_than_token\":\""/utf8>>/binary,
            Token/binary>>/binary,
        "\",\"count\":50}"/utf8>>,
    Json = soundcloud_http:post_json(Endpoint, Body),
    Items = parse_items(Json, Kind),
    Next = extract_between(Json, <<"\"last_token\":\""/utf8>>, <<"\""/utf8>>),
    More = gleam_stdlib:contains_string(
        Json,
        <<"\"more_available\":true"/utf8>>
    ),
    Next_nodes = case More andalso (Next /= <<""/utf8>>) of
        true ->
            [{category_node,
                    <<<<<<<<Kind/binary, "|"/utf8>>/binary, Fan_id/binary>>/binary,
                            "|"/utf8>>/binary,
                        Next/binary>>}];

        false ->
            []
    end,
    {expand_result, Items, [], Next_nodes, []}.

-file("src/bandcamp_live_expander.gleam", 19).
-spec expand_profile(soundcloud_adapter:source_identity()) -> soundcloud_adapter:expand_result().
expand_profile(Source) ->
    {source_identity, _, _, Profile_url} = Source,
    Html = soundcloud_http:fetch(Profile_url),
    Fan_id = extract_between(Html, <<"&quot;fan_id&quot;:"/utf8>>, <<","/utf8>>),
    Collection_token = extract_between(
        Html,
        <<"&quot;collection_data&quot;:{&quot;redownload_urls&quot;:{},&quot;last_token&quot;:&quot;"/utf8>>,
        <<"&quot;"/utf8>>
    ),
    Wishlist_token = extract_between(
        Html,
        <<"&quot;wishlist_data&quot;:{&quot;last_token&quot;:&quot;"/utf8>>,
        <<"&quot;"/utf8>>
    ),
    case ((Fan_id =:= <<""/utf8>>) orelse (Collection_token =:= <<""/utf8>>))
    orelse (Wishlist_token =:= <<""/utf8>>) of
        true ->
            {expand_result, [], [], [], [{profile_entry, Source}]};

        false ->
            Collection = fetch_category_page(
                <<"collection"/utf8>>,
                Fan_id,
                Collection_token
            ),
            Wishlist = fetch_category_page(
                <<"wishlist"/utf8>>,
                Fan_id,
                Wishlist_token
            ),
            {expand_result, C_items, _, C_next, _} = Collection,
            {expand_result, W_items, _, W_next, _} = Wishlist,
            {expand_result,
                lists:append(C_items, W_items),
                [],
                lists:append(C_next, W_next),
                []}
    end.

-file("src/bandcamp_live_expander.gleam", 49).
-spec expand_category(binary()) -> soundcloud_adapter:expand_result().
expand_category(Ctx) ->
    Parts = gleam@string:split(Ctx, <<"|"/utf8>>),
    case Parts of
        [Kind, Fan_id, Token] ->
            fetch_category_page(Kind, Fan_id, Token);

        _ ->
            {expand_result, [], [], [], [{category_node, Ctx}]}
    end.

-file("src/bandcamp_live_expander.gleam", 11).
-spec expand(soundcloud_adapter:adapter_node()) -> soundcloud_adapter:expand_result().
expand(Node) ->
    case Node of
        {profile_entry, Source} ->
            expand_profile(Source);

        {category_node, Ctx} ->
            expand_category(Ctx);

        _ ->
            {expand_result, [], [], [], []}
    end.
