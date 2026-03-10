-module(demo).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/demo.gleam").
-export([main/0]).

-file("src/demo.gleam", 45).
-spec print_item_titles(list(soundcloud_adapter:unified_item()), integer()) -> nil.
print_item_titles(Items, Max) ->
    Subset = gleam@list:take(Items, Max),
    case Subset of
        [] ->
            gleam_stdlib:println(<<"  - (none)"/utf8>>);

        _ ->
            gleam@list:each(
                Subset,
                fun(Item) ->
                    {unified_item, _, Title, Artist, _, _, _} = Item,
                    gleam_stdlib:println(
                        <<<<<<"  - "/utf8, Title/binary>>/binary, " | "/utf8>>/binary,
                            Artist/binary>>
                    )
                end
            )
    end.

-file("src/demo.gleam", 57).
-spec print_list_titles(
    list(soundcloud_adapter:unified_collection()),
    integer()
) -> nil.
print_list_titles(Lists, Max) ->
    Subset = gleam@list:take(Lists, Max),
    case Subset of
        [] ->
            gleam_stdlib:println(<<"  - (none)"/utf8>>);

        _ ->
            gleam@list:each(
                Subset,
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

-file("src/demo.gleam", 18).
-spec run_depth(binary(), soundcloud_adapter:depth_mode(), binary()) -> nil.
run_depth(Label, Depth, Profile_url) ->
    gleam_stdlib:println(<<<<"== "/utf8, Label/binary>>/binary, " =="/utf8>>),
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        Profile_url},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        Depth,
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
    gleam_stdlib:println(<<"sample items:"/utf8>>),
    print_item_titles(Items, 5),
    gleam_stdlib:println(<<"sample lists:"/utf8>>),
    print_list_titles(Lists, 5),
    gleam_stdlib:println(<<""/utf8>>).

-file("src/demo.gleam", 7).
-spec main() -> nil.
main() ->
    Profile_url = <<"https://soundcloud.com/tungstenselects"/utf8>>,
    gleam_stdlib:println(<<"rememberthename demo"/utf8>>),
    gleam_stdlib:println(<<"profile: "/utf8, Profile_url/binary>>),
    gleam_stdlib:println(<<""/utf8>>),
    run_depth(<<"depth-1"/utf8>>, depth1, Profile_url),
    run_depth(<<"depth-2"/utf8>>, depth2, Profile_url),
    run_depth(<<"full"/utf8>>, full, Profile_url).
