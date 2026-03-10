-module(soundcloud_adapter_fake_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/soundcloud_adapter_fake_test.gleam").
-export([depth_1_stops_after_profile_test/0, depth_2_expands_one_more_hop_test/0, full_depth_recurses_lists_categories_and_pages_test/0]).

-file("test/soundcloud_adapter_fake_test.gleam", 118).
-spec make_item(binary(), binary(), binary()) -> soundcloud_adapter:unified_item().
make_item(Id, Title, Artist) ->
    {unified_item,
        Id,
        Title,
        Artist,
        <<"soundcloud"/utf8>>,
        <<"item"/utf8>>,
        Id}.

-file("test/soundcloud_adapter_fake_test.gleam", 129).
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

-file("test/soundcloud_adapter_fake_test.gleam", 49).
-spec fake_expand(soundcloud_adapter:adapter_node()) -> soundcloud_adapter:expand_result().
fake_expand(Node) ->
    case Node of
        {profile_entry, _} ->
            {expand_result,
                [],
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
                [],
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
                [make_item(
                        <<"track-a"/utf8>>,
                        <<"Track A"/utf8>>,
                        <<"Artist A"/utf8>>
                    )],
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
                [make_item(
                        <<"track-b"/utf8>>,
                        <<"Track B"/utf8>>,
                        <<"Artist B"/utf8>>
                    )],
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

-file("test/soundcloud_adapter_fake_test.gleam", 146).
-spec item_ids(list(soundcloud_adapter:unified_item())) -> list(binary()).
item_ids(Items) ->
    gleam@list:map(
        Items,
        fun(Item) ->
            {unified_item, Id, _, _, _, _, _} = Item,
            Id
        end
    ).

-file("test/soundcloud_adapter_fake_test.gleam", 153).
-spec list_ids(list(soundcloud_adapter:unified_collection())) -> list(binary()).
list_ids(Lists) ->
    gleam@list:map(
        Lists,
        fun(Collection) ->
            {unified_collection, Id, _, _, _, _, _, _} = Collection,
            Id
        end
    ).

-file("test/soundcloud_adapter_fake_test.gleam", 4).
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
    _assert_subject = item_ids(Items),
    _assert_subject@1 = [],
    case _assert_subject =:= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_1_stops_after_profile_test"/utf8>>,
                line => 14,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 443,
                    'end' => 458
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 462,
                    'end' => 464
                    },
                start => 436,
                'end' => 464,
                expression_start => 443})
    end,
    _assert_subject@2 = list_ids(Lists),
    _assert_subject@3 = [<<"profile-root"/utf8>>],
    case _assert_subject@2 =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_1_stops_after_profile_test"/utf8>>,
                line => 15,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@2,
                    start => 474,
                    'end' => 489
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 493,
                    'end' => 509
                    },
                start => 467,
                'end' => 509,
                expression_start => 474})
    end,
    _assert_subject@4 = [],
    case Unresolved =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_1_stops_after_profile_test"/utf8>>,
                line => 16,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 519,
                    'end' => 529
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 533,
                    'end' => 535
                    },
                start => 512,
                'end' => 535,
                expression_start => 519})
    end.

-file("test/soundcloud_adapter_fake_test.gleam", 19).
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
    _assert_subject = item_ids(Items),
    _assert_subject@1 = [<<"track-a"/utf8>>, <<"track-b"/utf8>>],
    case _assert_subject =:= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_2_expands_one_more_hop_test"/utf8>>,
                line => 29,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 938,
                    'end' => 953
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 957,
                    'end' => 979
                    },
                start => 931,
                'end' => 979,
                expression_start => 938})
    end,
    _assert_subject@2 = list_ids(Lists),
    _assert_subject@3 = [<<"profile-root"/utf8>>,
        <<"list-b"/utf8>>,
        <<"list-a"/utf8>>],
    case _assert_subject@2 =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_2_expands_one_more_hop_test"/utf8>>,
                line => 30,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@2,
                    start => 989,
                    'end' => 1004
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 1008,
                    'end' => 1044
                    },
                start => 982,
                'end' => 1044,
                expression_start => 989})
    end,
    _assert_subject@4 = [{list_node, <<"list-missing"/utf8>>}],
    case Unresolved =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"depth_2_expands_one_more_hop_test"/utf8>>,
                line => 31,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1054,
                    'end' => 1064
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 1068,
                    'end' => 1113
                    },
                start => 1047,
                'end' => 1113,
                expression_start => 1054})
    end.

-file("test/soundcloud_adapter_fake_test.gleam", 34).
-spec full_depth_recurses_lists_categories_and_pages_test() -> nil.
full_depth_recurses_lists_categories_and_pages_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/demo"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        full,
        fun fake_expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = item_ids(Items),
    _assert_subject@1 = [<<"track-a"/utf8>>,
        <<"track-b"/utf8>>,
        <<"track-c"/utf8>>],
    case _assert_subject =:= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"full_depth_recurses_lists_categories_and_pages_test"/utf8>>,
                line => 44,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 1532,
                    'end' => 1547
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 1551,
                    'end' => 1584
                    },
                start => 1525,
                'end' => 1584,
                expression_start => 1532})
    end,
    _assert_subject@2 = list_ids(Lists),
    _assert_subject@3 = [<<"profile-root"/utf8>>,
        <<"list-b"/utf8>>,
        <<"list-a"/utf8>>,
        <<"list-c"/utf8>>],
    case _assert_subject@2 =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"full_depth_recurses_lists_categories_and_pages_test"/utf8>>,
                line => 45,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@2,
                    start => 1594,
                    'end' => 1609
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 1613,
                    'end' => 1659
                    },
                start => 1587,
                'end' => 1659,
                expression_start => 1594})
    end,
    _assert_subject@4 = [{list_node, <<"list-missing"/utf8>>}],
    case Unresolved =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_fake_test"/utf8>>,
                function => <<"full_depth_recurses_lists_categories_and_pages_test"/utf8>>,
                line => 46,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1669,
                    'end' => 1679
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 1683,
                    'end' => 1728
                    },
                start => 1662,
                'end' => 1728,
                expression_start => 1669})
    end.
