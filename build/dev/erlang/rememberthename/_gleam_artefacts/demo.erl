-module(demo).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/demo.gleam").
-export([main/0]).

-file("src/demo.gleam", 80).
-spec print_list_titles(list(soundcloud_adapter:unified_collection())) -> nil.
print_list_titles(Lists) ->
    case Lists of
        [] ->
            gleam_stdlib:println(<<"  - (none)"/utf8>>);

        _ ->
            gleam@list:each(
                Lists,
                fun(Collection) ->
                    {unified_collection, _, Title, Track_ids, List_ids, _, _, _} = Collection,
                    gleam_stdlib:println(
                        <<<<<<<<<<"  - "/utf8, Title/binary>>/binary,
                                        " | tracks="/utf8>>/binary,
                                    (erlang:integer_to_binary(
                                        erlang:length(Track_ids)
                                    ))/binary>>/binary,
                                " nested_lists="/utf8>>/binary,
                            (erlang:integer_to_binary(erlang:length(List_ids)))/binary>>
                    )
                end
            )
    end.

-file("src/demo.gleam", 98).
-spec print_items(list(soundcloud_adapter:unified_item())) -> nil.
print_items(Items) ->
    gleam@list:each(
        Items,
        fun(Item) ->
            {unified_item, _, Title, Artist, _, _, _} = Item,
            gleam_stdlib:println(
                <<<<<<"  - "/utf8, Title/binary>>/binary, " | "/utf8>>/binary,
                    Artist/binary>>
            )
        end
    ).

-file("src/demo.gleam", 62).
-spec print_item_titles(list(soundcloud_adapter:unified_item())) -> nil.
print_item_titles(Items) ->
    Count = erlang:length(Items),
    case Count =:= 0 of
        true ->
            gleam_stdlib:println(<<"  - (none)"/utf8>>);

        false ->
            case Count > 7 of
                true ->
                    First = gleam@list:take(Items, 3),
                    Last = gleam@list:drop(Items, Count - 3),
                    print_items(First),
                    gleam_stdlib:println(<<"  ..."/utf8>>),
                    print_items(Last);

                false ->
                    print_items(Items)
            end
    end.

-file("src/demo.gleam", 14).
-spec run_all_soundcloud(binary()) -> nil.
run_all_soundcloud(Profile_url) ->
    gleam_stdlib:println(<<"== soundcloud all =="/utf8>>),
    gleam_stdlib:println(<<"profile: "/utf8, Profile_url/binary>>),
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        Profile_url},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        all,
        fun soundcloud_live_expander:expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    gleam_stdlib:println(
        <<"items: "/utf8,
            (erlang:integer_to_binary(erlang:length(Items)))/binary>>
    ),
    gleam_stdlib:println(
        <<"lists: "/utf8,
            (erlang:integer_to_binary(erlang:length(Lists)))/binary>>
    ),
    gleam_stdlib:println(
        <<"unresolved: "/utf8,
            (erlang:integer_to_binary(erlang:length(Unresolved)))/binary>>
    ),
    gleam_stdlib:println(<<"items:"/utf8>>),
    print_item_titles(Items),
    gleam_stdlib:println(<<"lists:"/utf8>>),
    print_list_titles(Lists),
    gleam_stdlib:println(<<""/utf8>>).

-file("src/demo.gleam", 38).
-spec run_all_bandcamp(binary()) -> nil.
run_all_bandcamp(Profile_url) ->
    gleam_stdlib:println(<<"== bandcamp all =="/utf8>>),
    gleam_stdlib:println(<<"profile: "/utf8, Profile_url/binary>>),
    Profile = {source_identity,
        <<"bandcamp"/utf8>>,
        <<"collection"/utf8>>,
        Profile_url},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        all,
        fun bandcamp_live_expander:expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    gleam_stdlib:println(
        <<"items: "/utf8,
            (erlang:integer_to_binary(erlang:length(Items)))/binary>>
    ),
    gleam_stdlib:println(
        <<"lists: "/utf8,
            (erlang:integer_to_binary(erlang:length(Lists)))/binary>>
    ),
    gleam_stdlib:println(
        <<"unresolved: "/utf8,
            (erlang:integer_to_binary(erlang:length(Unresolved)))/binary>>
    ),
    gleam_stdlib:println(<<"items:"/utf8>>),
    print_item_titles(Items),
    gleam_stdlib:println(<<"lists:"/utf8>>),
    print_list_titles(Lists),
    gleam_stdlib:println(<<""/utf8>>).

-file("src/demo.gleam", 8).
-spec main() -> nil.
main() ->
    gleam_stdlib:println(<<"rememberthename demo"/utf8>>),
    run_all_soundcloud(<<"https://soundcloud.com/tungstenselects"/utf8>>),
    run_all_bandcamp(<<"https://bandcamp.com/janwirth"/utf8>>).
