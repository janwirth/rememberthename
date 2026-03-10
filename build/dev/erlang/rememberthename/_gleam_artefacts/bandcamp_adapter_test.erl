-module(bandcamp_adapter_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/bandcamp_adapter_test.gleam").
-export([bandcamp_depth_1_fetches_initial_items_test/0, bandcamp_depths_keep_increasing_test/0]).

-file("test/bandcamp_adapter_test.gleam", 5).
-spec bandcamp_depth_1_fetches_initial_items_test() -> nil.
bandcamp_depth_1_fetches_initial_items_test() ->
    Profile = {source_identity,
        <<"bandcamp"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://bandcamp.com/janwirth"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        depth1,
        fun bandcamp_live_expander:expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = [],
    case Items /= _assert_subject of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depth_1_fetches_initial_items_test"/utf8>>,
                line => 17,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Items,
                    start => 507,
                    'end' => 512
                    },
                right => #{kind => literal,
                    value => _assert_subject,
                    start => 516,
                    'end' => 518
                    },
                start => 500,
                'end' => 518,
                expression_start => 507})
    end,
    _assert_subject@1 = [],
    case Lists =:= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depth_1_fetches_initial_items_test"/utf8>>,
                line => 18,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Lists,
                    start => 528,
                    'end' => 533
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 537,
                    'end' => 539
                    },
                start => 521,
                'end' => 539,
                expression_start => 528})
    end,
    _assert_subject@2 = [],
    case Unresolved =:= _assert_subject@2 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depth_1_fetches_initial_items_test"/utf8>>,
                line => 19,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 549,
                    'end' => 559
                    },
                right => #{kind => literal,
                    value => _assert_subject@2,
                    start => 563,
                    'end' => 565
                    },
                start => 542,
                'end' => 565,
                expression_start => 549})
    end.

-file("test/bandcamp_adapter_test.gleam", 22).
-spec bandcamp_depths_keep_increasing_test() -> nil.
bandcamp_depths_keep_increasing_test() ->
    Profile = {source_identity,
        <<"bandcamp"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://bandcamp.com/janwirth"/utf8>>},
    {resolve_result, Items_3, _, _} = soundcloud_adapter:resolve_profile(
        Profile,
        depth3,
        fun bandcamp_live_expander:expand/1
    ),
    {resolve_result, Items_10, _, _} = soundcloud_adapter:resolve_profile(
        Profile,
        depth10,
        fun bandcamp_live_expander:expand/1
    ),
    {resolve_result, Items_20, _, _} = soundcloud_adapter:resolve_profile(
        Profile,
        depth20,
        fun bandcamp_live_expander:expand/1
    ),
    {resolve_result, Items_all, _, Unresolved_all} = soundcloud_adapter:resolve_profile(
        Profile,
        all,
        fun bandcamp_live_expander:expand/1
    ),
    _assert_subject = erlang:length(Items_10),
    _assert_subject@1 = erlang:length(Items_3),
    case _assert_subject > _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depths_keep_increasing_test"/utf8>>,
                line => 39,
                kind => binary_operator,
                operator => '>',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 1463,
                    'end' => 1484
                    },
                right => #{kind => expression,
                    value => _assert_subject@1,
                    start => 1487,
                    'end' => 1507
                    },
                start => 1456,
                'end' => 1507,
                expression_start => 1463})
    end,
    _assert_subject@2 = erlang:length(Items_20),
    _assert_subject@3 = erlang:length(Items_10),
    case _assert_subject@2 > _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depths_keep_increasing_test"/utf8>>,
                line => 40,
                kind => binary_operator,
                operator => '>',
                left => #{kind => expression,
                    value => _assert_subject@2,
                    start => 1517,
                    'end' => 1538
                    },
                right => #{kind => expression,
                    value => _assert_subject@3,
                    start => 1541,
                    'end' => 1562
                    },
                start => 1510,
                'end' => 1562,
                expression_start => 1517})
    end,
    _assert_subject@4 = erlang:length(Items_all),
    _assert_subject@5 = erlang:length(Items_20),
    case _assert_subject@4 >= _assert_subject@5 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depths_keep_increasing_test"/utf8>>,
                line => 41,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject@4,
                    start => 1572,
                    'end' => 1594
                    },
                right => #{kind => expression,
                    value => _assert_subject@5,
                    start => 1598,
                    'end' => 1619
                    },
                start => 1565,
                'end' => 1619,
                expression_start => 1572})
    end,
    _assert_subject@6 = erlang:length(Items_all),
    _assert_subject@7 = 700,
    case _assert_subject@6 >= _assert_subject@7 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depths_keep_increasing_test"/utf8>>,
                line => 42,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject@6,
                    start => 1629,
                    'end' => 1651
                    },
                right => #{kind => literal,
                    value => _assert_subject@7,
                    start => 1655,
                    'end' => 1658
                    },
                start => 1622,
                'end' => 1658,
                expression_start => 1629})
    end,
    _assert_subject@8 = [],
    case Unresolved_all =:= _assert_subject@8 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"bandcamp_adapter_test"/utf8>>,
                function => <<"bandcamp_depths_keep_increasing_test"/utf8>>,
                line => 43,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved_all,
                    start => 1668,
                    'end' => 1682
                    },
                right => #{kind => literal,
                    value => _assert_subject@8,
                    start => 1686,
                    'end' => 1688
                    },
                start => 1661,
                'end' => 1688,
                expression_start => 1668})
    end.
