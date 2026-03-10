-module(soundcloud_adapter_fake_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/soundcloud_adapter_fake_test.gleam").
-export([depth_1_stops_after_profile_test/0, depth_2_expands_one_more_hop_test/0, depth_3_recurses_lists_categories_and_pages_test/0, all_depth_matches_depth_3_for_fixture_test/0]).

-file("test/soundcloud_adapter_fake_test.gleam", 140).
-spec make_item(binary(), binary(), binary()) -> soundcloud_adapter:unified_item().
make_item(Id, Title, Artist) ->
    {unified_item,
        Id,
        Title,
        Artist,
        <<"soundcloud"/utf8>>,
        <<"item"/utf8>>,
        Id}.

-file("test/soundcloud_adapter_fake_test.gleam", 151).
-spec make_list(binary(), binary(), list(binary()), list(binary())) -> soundcloud_adapter:unified_collection().
make_list(Id, Title, Track_ids, List_ids) ->
    {unified_collection,
        Id,
        Title,
        Track_ids,
        List_ids,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        Id}.

-file("test/soundcloud_adapter_fake_test.gleam", 168).
-spec list_ids(list(soundcloud_adapter:unified_collection())) -> list(binary()).
list_ids(Lists) ->
    gleam@list:map(
        Lists,
        fun(Collection) ->
            {unified_collection, Id, _, _, _, _, _, _} = Collection,
            Id
        end
    ).

-file("test/soundcloud_adapter_fake_test.gleam", 175).
-spec contains_item_id(list(soundcloud_adapter:unified_item()), binary()) -> boolean().
contains_item_id(Items, Wanted) ->
    gleam@list:any(
        Items,
        fun(Item) ->
            {unified_item, Id, _, _, _, _, _} = Item,
            Id =:= Wanted
        end
    ).

-file("test/soundcloud_adapter_fake_test.gleam", 197).
-spec int_to_two_digits(integer()) -> binary().
int_to_two_digits(N) ->
    case N < 10 of
        true ->
            <<"0"/utf8, (erlang:integer_to_binary(N))/binary>>;

        false ->
            erlang:integer_to_binary(N)
    end.

-file("test/soundcloud_adapter_fake_test.gleam", 182).
-spec make_depth_items(binary(), integer()) -> list(soundcloud_adapter:unified_item()).
make_depth_items(Prefix, Count) ->
    Numbers = gleam@int:range(
        1,
        Count + 1,
        [],
        fun(Acc, N) -> lists:append(Acc, [N]) end
    ),
    gleam@list:map(
        Numbers,
        fun(N@1) ->
            N_str = int_to_two_digits(N@1),
            Id = <<Prefix/binary, N_str/binary>>,
            make_item(
                Id,
                <<"Generated "/utf8, Id/binary>>,
                <<"Generated Artist"/utf8>>
            )
        end
    ).

-file("test/soundcloud_adapter_fake_test.gleam", 69).
-spec fake_expand(soundcloud_adapter:adapter_node()) -> soundcloud_adapter:expand_result().
fake_expand(Node) ->
    case Node of
        {profile_entry, _} ->
            {expand_result,
                make_depth_items(<<"d1-track-"/utf8>>, 10),
                [make_list(
                        <<"profile-root"/utf8>>,
                        <<"Profile Root"/utf8>>,
                        [<<"track-a"/utf8>>],
                        [<<"list-a"/utf8>>, <<"list-b"/utf8>>]
                    )],
                [{category_node, <<"likes"/utf8>>},
                    {list_node, <<"list-a"/utf8>>},
                    {list_node, <<"list-b"/utf8>>}],
                []};

        {category_node, <<"likes"/utf8>>} ->
            {expand_result,
                make_depth_items(<<"d2cat-track-"/utf8>>, 10),
                [make_list(
                        <<"list-b"/utf8>>,
                        <<"Category List B"/utf8>>,
                        [],
                        []
                    )],
                [{page_node, <<"likes:2"/utf8>>}],
                []};

        {page_node, <<"likes:2"/utf8>>} ->
            {expand_result,
                [make_item(
                        <<"track-c"/utf8>>,
                        <<"Track C"/utf8>>,
                        <<"Artist C"/utf8>>
                    )],
                [make_list(
                        <<"list-c"/utf8>>,
                        <<"Page List C"/utf8>>,
                        [<<"track-c"/utf8>>],
                        []
                    )],
                [],
                []};

        {list_node, <<"list-a"/utf8>>} ->
            {expand_result,
                lists:append(
                    [make_item(
                            <<"track-a"/utf8>>,
                            <<"Track A"/utf8>>,
                            <<"Artist A"/utf8>>
                        )],
                    make_depth_items(<<"d2a-track-"/utf8>>, 10)
                ),
                [make_list(
                        <<"list-a"/utf8>>,
                        <<"List A"/utf8>>,
                        [<<"track-a"/utf8>>],
                        []
                    )],
                [],
                []};

        {list_node, <<"list-b"/utf8>>} ->
            {expand_result,
                lists:append(
                    [make_item(
                            <<"track-b"/utf8>>,
                            <<"Track B"/utf8>>,
                            <<"Artist B"/utf8>>
                        )],
                    make_depth_items(<<"d2b-track-"/utf8>>, 10)
                ),
                [make_list(
                        <<"list-b"/utf8>>,
                        <<"List B"/utf8>>,
                        [<<"track-b"/utf8>>],
                        [<<"list-c"/utf8>>]
                    )],
                [{list_node, <<"list-c"/utf8>>},
                    {list_node, <<"list-missing"/utf8>>}],
                [{list_node, <<"list-missing"/utf8>>}]};

        {list_node, <<"list-c"/utf8>>} ->
            {expand_result,
                [make_item(
                        <<"track-c"/utf8>>,
                        <<"Track C"/utf8>>,
                        <<"Artist C"/utf8>>
                    )],
                [make_list(
                        <<"list-c"/utf8>>,
                        <<"List C"/utf8>>,
                        [<<"track-c"/utf8>>],
                        []
                    )],
                [],
                []};

        _ ->
            {expand_result, [], [], [], []}
    end.

-file("test/soundcloud_adapter_fake_test.gleam", 5).
-spec depth_1_stops_after_profile_test() -> nil.
depth_1_stops_after_profile_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/demo"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        depth1,
        fun fake_expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = erlang:length(Items),
    _assert_subject@1 = 10,
    case _assert_subject >= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_1_stops_after_profile_test"/utf8>>,
                line => 15,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 460,
                    'end' => 478
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 482,
                    'end' => 484
                    },
                start => 453,
                'end' => 484,
                expression_start => 460})
    end,
    _assert_subject@2 = <<"d1-track-01"/utf8>>,
    case contains_item_id(Items, _assert_subject@2) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_1_stops_after_profile_test"/utf8>>,
                line => 16,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 511,
                        'end' => 516
                        }, #{kind => literal,
                        value => _assert_subject@2,
                        start => 518,
                        'end' => 531
                        }],
                start => 487,
                'end' => 532,
                expression_start => 494})
    end,
    _assert_subject@3 = list_ids(Lists),
    _assert_subject@4 = [<<"profile-root"/utf8>>],
    case _assert_subject@3 =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_1_stops_after_profile_test"/utf8>>,
                line => 17,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@3,
                    start => 542,
                    'end' => 557
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 561,
                    'end' => 577
                    },
                start => 535,
                'end' => 577,
                expression_start => 542})
    end,
    _assert_subject@5 = [],
    case Unresolved =:= _assert_subject@5 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_1_stops_after_profile_test"/utf8>>,
                line => 18,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 587,
                    'end' => 597
                    },
                right => #{kind => literal,
                    value => _assert_subject@5,
                    start => 601,
                    'end' => 603
                    },
                start => 580,
                'end' => 603,
                expression_start => 587})
    end.

-file("test/soundcloud_adapter_fake_test.gleam", 21).
-spec depth_2_expands_one_more_hop_test() -> nil.
depth_2_expands_one_more_hop_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/demo"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        depth2,
        fun fake_expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = erlang:length(Items),
    _assert_subject@1 = 30,
    case _assert_subject >= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_2_expands_one_more_hop_test"/utf8>>,
                line => 31,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 1006,
                    'end' => 1024
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 1028,
                    'end' => 1030
                    },
                start => 999,
                'end' => 1030,
                expression_start => 1006})
    end,
    _assert_subject@2 = <<"d2b-track-10"/utf8>>,
    case contains_item_id(Items, _assert_subject@2) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_2_expands_one_more_hop_test"/utf8>>,
                line => 32,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 1057,
                        'end' => 1062
                        }, #{kind => literal,
                        value => _assert_subject@2,
                        start => 1064,
                        'end' => 1078
                        }],
                start => 1033,
                'end' => 1079,
                expression_start => 1040})
    end,
    _assert_subject@3 = list_ids(Lists),
    _assert_subject@4 = [<<"profile-root"/utf8>>,
        <<"list-b"/utf8>>,
        <<"list-a"/utf8>>],
    case _assert_subject@3 =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_2_expands_one_more_hop_test"/utf8>>,
                line => 33,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@3,
                    start => 1089,
                    'end' => 1104
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 1108,
                    'end' => 1144
                    },
                start => 1082,
                'end' => 1144,
                expression_start => 1089})
    end,
    _assert_subject@5 = [{list_node, <<"list-missing"/utf8>>}],
    case Unresolved =:= _assert_subject@5 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_2_expands_one_more_hop_test"/utf8>>,
                line => 34,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1154,
                    'end' => 1164
                    },
                right => #{kind => literal,
                    value => _assert_subject@5,
                    start => 1168,
                    'end' => 1213
                    },
                start => 1147,
                'end' => 1213,
                expression_start => 1154})
    end.

-file("test/soundcloud_adapter_fake_test.gleam", 37).
-spec depth_3_recurses_lists_categories_and_pages_test() -> nil.
depth_3_recurses_lists_categories_and_pages_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/demo"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        depth3,
        fun fake_expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = erlang:length(Items),
    _assert_subject@1 = 30,
    case _assert_subject >= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_3_recurses_lists_categories_and_pages_test"/utf8>>,
                line => 47,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 1631,
                    'end' => 1649
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 1653,
                    'end' => 1655
                    },
                start => 1624,
                'end' => 1655,
                expression_start => 1631})
    end,
    _assert_subject@2 = <<"track-c"/utf8>>,
    case contains_item_id(Items, _assert_subject@2) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_3_recurses_lists_categories_and_pages_test"/utf8>>,
                line => 48,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 1682,
                        'end' => 1687
                        }, #{kind => literal,
                        value => _assert_subject@2,
                        start => 1689,
                        'end' => 1698
                        }],
                start => 1658,
                'end' => 1699,
                expression_start => 1665})
    end,
    _assert_subject@3 = list_ids(Lists),
    _assert_subject@4 = [<<"profile-root"/utf8>>,
        <<"list-b"/utf8>>,
        <<"list-a"/utf8>>,
        <<"list-c"/utf8>>],
    case _assert_subject@3 =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_3_recurses_lists_categories_and_pages_test"/utf8>>,
                line => 49,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@3,
                    start => 1709,
                    'end' => 1724
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 1728,
                    'end' => 1774
                    },
                start => 1702,
                'end' => 1774,
                expression_start => 1709})
    end,
    _assert_subject@5 = [{list_node, <<"list-missing"/utf8>>}],
    case Unresolved =:= _assert_subject@5 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_3_recurses_lists_categories_and_pages_test"/utf8>>,
                line => 50,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1784,
                    'end' => 1794
                    },
                right => #{kind => literal,
                    value => _assert_subject@5,
                    start => 1798,
                    'end' => 1843
                    },
                start => 1777,
                'end' => 1843,
                expression_start => 1784})
    end.

-file("test/soundcloud_adapter_fake_test.gleam", 53).
-spec all_depth_matches_depth_3_for_fixture_test() -> nil.
all_depth_matches_depth_3_for_fixture_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/demo"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(Profile, all, fun fake_expand/1),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = erlang:length(Items),
    _assert_subject@1 = 30,
    case _assert_subject >= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"all_depth_matches_depth_3_for_fixture_test"/utf8>>,
                line => 63,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 2252,
                    'end' => 2270
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 2274,
                    'end' => 2276
                    },
                start => 2245,
                'end' => 2276,
                expression_start => 2252})
    end,
    _assert_subject@2 = <<"track-c"/utf8>>,
    case contains_item_id(Items, _assert_subject@2) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"all_depth_matches_depth_3_for_fixture_test"/utf8>>,
                line => 64,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 2303,
                        'end' => 2308
                        }, #{kind => literal,
                        value => _assert_subject@2,
                        start => 2310,
                        'end' => 2319
                        }],
                start => 2279,
                'end' => 2320,
                expression_start => 2286})
    end,
    _assert_subject@3 = list_ids(Lists),
    _assert_subject@4 = [<<"profile-root"/utf8>>,
        <<"list-b"/utf8>>,
        <<"list-a"/utf8>>,
        <<"list-c"/utf8>>],
    case _assert_subject@3 =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"all_depth_matches_depth_3_for_fixture_test"/utf8>>,
                line => 65,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@3,
                    start => 2330,
                    'end' => 2345
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 2349,
                    'end' => 2395
                    },
                start => 2323,
                'end' => 2395,
                expression_start => 2330})
    end,
    _assert_subject@5 = [{list_node, <<"list-missing"/utf8>>}],
    case Unresolved =:= _assert_subject@5 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"all_depth_matches_depth_3_for_fixture_test"/utf8>>,
                line => 66,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 2405,
                    'end' => 2415
                    },
                right => #{kind => literal,
                    value => _assert_subject@5,
                    start => 2419,
                    'end' => 2464
                    },
                start => 2398,
                'end' => 2464,
                expression_start => 2405})
    end.
