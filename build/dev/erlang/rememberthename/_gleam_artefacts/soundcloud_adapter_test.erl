-module(soundcloud_adapter_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/soundcloud_adapter_test.gleam").
-export([live_depth_10_matches_all_for_current_live_graph_test/0, live_depth_1_includes_shallow_spec_track_test/0, live_depth_2_includes_deeper_spec_track_test/0, live_depth_3_includes_spec_list_test/0, live_all_matches_depth_3_for_current_live_graph_test/0, live_all_full_recursion_collects_expected_shape_test/0]).

-file("test/soundcloud_adapter_test.gleam", 76).
-spec live_depth_10_matches_all_for_current_live_graph_test() -> nil.
live_depth_10_matches_all_for_current_live_graph_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/tungstenselects"/utf8>>},
    Result_10 = soundcloud_adapter:resolve_profile(
        Profile,
        depth10,
        fun soundcloud_live_expander:expand/1
    ),
    Result_all = soundcloud_adapter:resolve_profile(
        Profile,
        all,
        fun soundcloud_live_expander:expand/1
    ),
    {resolve_result, Items_10, Lists_10, Unresolved_10} = Result_10,
    {resolve_result, Items_all, Lists_all, Unresolved_all} = Result_all,
    _assert_subject = erlang:length(Items_10),
    _assert_subject@1 = 30,
    case _assert_subject >= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_10_matches_all_for_current_live_graph_test"/utf8>>,
                line => 96,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 3250,
                    'end' => 3271
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 3275,
                    'end' => 3277
                    },
                start => 3243,
                'end' => 3277,
                expression_start => 3250})
    end,
    _assert_subject@2 = erlang:length(Items_10),
    _assert_subject@3 = erlang:length(Items_all),
    case _assert_subject@2 =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_10_matches_all_for_current_live_graph_test"/utf8>>,
                line => 97,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@2,
                    start => 3287,
                    'end' => 3308
                    },
                right => #{kind => expression,
                    value => _assert_subject@3,
                    start => 3312,
                    'end' => 3334
                    },
                start => 3280,
                'end' => 3334,
                expression_start => 3287})
    end,
    _assert_subject@4 = erlang:length(Lists_10),
    _assert_subject@5 = erlang:length(Lists_all),
    case _assert_subject@4 =:= _assert_subject@5 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_10_matches_all_for_current_live_graph_test"/utf8>>,
                line => 98,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => _assert_subject@4,
                    start => 3344,
                    'end' => 3365
                    },
                right => #{kind => expression,
                    value => _assert_subject@5,
                    start => 3369,
                    'end' => 3391
                    },
                start => 3337,
                'end' => 3391,
                expression_start => 3344})
    end,
    case Unresolved_10 =:= Unresolved_all of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_10_matches_all_for_current_live_graph_test"/utf8>>,
                line => 99,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved_10,
                    start => 3401,
                    'end' => 3414
                    },
                right => #{kind => expression,
                    value => Unresolved_all,
                    start => 3418,
                    'end' => 3432
                    },
                start => 3394,
                'end' => 3432,
                expression_start => 3401})
    end.

-file("test/soundcloud_adapter_test.gleam", 122).
-spec contains_title(list(soundcloud_adapter:unified_item()), binary()) -> boolean().
contains_title(Items, Wanted) ->
    gleam@list:any(
        Items,
        fun(Item) ->
            {unified_item, _, Title, _, _, _, _} = Item,
            Title =:= Wanted
        end
    ).

-file("test/soundcloud_adapter_test.gleam", 6).
-spec live_depth_1_includes_shallow_spec_track_test() -> nil.
live_depth_1_includes_shallow_spec_track_test() ->
    Payload = soundcloud_live_expander:fetch_likes_payload(
        <<"https://soundcloud.com/tungstenselects"/utf8>>
    ),
    _assert_subject = <<""/utf8>>,
    case Payload /= _assert_subject of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 8,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Payload,
                    start => 266,
                    'end' => 273
                    },
                right => #{kind => literal,
                    value => _assert_subject,
                    start => 277,
                    'end' => 279
                    },
                start => 259,
                'end' => 279,
                expression_start => 266})
    end,
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/tungstenselects"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        depth1,
        fun soundcloud_live_expander:expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject@1 = erlang:length(Items),
    _assert_subject@2 = 10,
    case _assert_subject@1 >= _assert_subject@2 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 20,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject@1,
                    start => 670,
                    'end' => 688
                    },
                right => #{kind => literal,
                    value => _assert_subject@2,
                    start => 692,
                    'end' => 694
                    },
                start => 663,
                'end' => 694,
                expression_start => 670})
    end,
    _assert_subject@3 = <<"A Horse with no Name (Edit)"/utf8>>,
    case contains_title(Items, _assert_subject@3) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 21,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 719,
                        'end' => 724
                        }, #{kind => literal,
                        value => _assert_subject@3,
                        start => 726,
                        'end' => 755
                        }],
                start => 697,
                'end' => 756,
                expression_start => 704})
    end,
    _assert_subject@4 = [],
    case Lists =:= _assert_subject@4 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 22,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Lists,
                    start => 766,
                    'end' => 771
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 775,
                    'end' => 777
                    },
                start => 759,
                'end' => 777,
                expression_start => 766})
    end,
    _assert_subject@5 = [],
    case Unresolved =:= _assert_subject@5 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 23,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 787,
                    'end' => 797
                    },
                right => #{kind => literal,
                    value => _assert_subject@5,
                    start => 801,
                    'end' => 803
                    },
                start => 780,
                'end' => 803,
                expression_start => 787})
    end.

-file("test/soundcloud_adapter_test.gleam", 129).
-spec contains_title_fragment(list(soundcloud_adapter:unified_item()), binary()) -> boolean().
contains_title_fragment(Items, Wanted) ->
    gleam@list:any(
        Items,
        fun(Item) ->
            {unified_item, _, Title, _, _, _, _} = Item,
            gleam_stdlib:contains_string(Title, Wanted)
        end
    ).

-file("test/soundcloud_adapter_test.gleam", 26).
-spec live_depth_2_includes_deeper_spec_track_test() -> nil.
live_depth_2_includes_deeper_spec_track_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/tungstenselects"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        depth2,
        fun soundcloud_live_expander:expand/1
    ),
    {resolve_result, Items, _, Unresolved} = Result,
    _assert_subject = erlang:length(Items),
    _assert_subject@1 = 30,
    case _assert_subject >= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_2_includes_deeper_spec_track_test"/utf8>>,
                line => 37,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 1253,
                    'end' => 1271
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 1275,
                    'end' => 1277
                    },
                start => 1246,
                'end' => 1277,
                expression_start => 1253})
    end,
    _assert_subject@2 = <<"Premiere: KAIPE - Batie"/utf8>>,
    case contains_title_fragment(Items, _assert_subject@2) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_2_includes_deeper_spec_track_test"/utf8>>,
                line => 38,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 1311,
                        'end' => 1316
                        }, #{kind => literal,
                        value => _assert_subject@2,
                        start => 1318,
                        'end' => 1343
                        }],
                start => 1280,
                'end' => 1344,
                expression_start => 1287})
    end,
    _assert_subject@3 = [],
    case Unresolved =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_2_includes_deeper_spec_track_test"/utf8>>,
                line => 39,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1354,
                    'end' => 1364
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 1368,
                    'end' => 1370
                    },
                start => 1347,
                'end' => 1370,
                expression_start => 1354})
    end.

-file("test/soundcloud_adapter_test.gleam", 136).
-spec contains_list_title(
    list(soundcloud_adapter:unified_collection()),
    binary()
) -> boolean().
contains_list_title(Lists, Wanted) ->
    gleam@list:any(
        Lists,
        fun(Collection) ->
            {unified_collection, _, Title, _, _, _, _, _} = Collection,
            Title =:= Wanted
        end
    ).

-file("test/soundcloud_adapter_test.gleam", 143).
-spec contains_any_track_id(
    list(soundcloud_adapter:unified_collection()),
    binary()
) -> boolean().
contains_any_track_id(Lists, Wanted) ->
    gleam@list:any(
        Lists,
        fun(Collection) ->
            {unified_collection, _, _, Track_ids, _, _, _, _} = Collection,
            gleam@list:any(Track_ids, fun(Track_id) -> Track_id =:= Wanted end)
        end
    ).

-file("test/soundcloud_adapter_test.gleam", 42).
-spec live_depth_3_includes_spec_list_test() -> nil.
live_depth_3_includes_spec_list_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/tungstenselects"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        depth3,
        fun soundcloud_live_expander:expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = <<"Mahal"/utf8>>,
    case contains_list_title(Lists, _assert_subject) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_3_includes_spec_list_test"/utf8>>,
                line => 53,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 1831,
                        'end' => 1836
                        }, #{kind => literal,
                        value => _assert_subject,
                        start => 1838,
                        'end' => 1845
                        }],
                start => 1804,
                'end' => 1846,
                expression_start => 1811})
    end,
    _assert_subject@1 = <<"Glass Beams"/utf8>>,
    case contains_any_track_id(Lists, _assert_subject@1) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_3_includes_spec_list_test"/utf8>>,
                line => 54,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 1878,
                        'end' => 1883
                        }, #{kind => literal,
                        value => _assert_subject@1,
                        start => 1885,
                        'end' => 1898
                        }],
                start => 1849,
                'end' => 1899,
                expression_start => 1856})
    end,
    _assert_subject@2 = [],
    case Items /= _assert_subject@2 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_3_includes_spec_list_test"/utf8>>,
                line => 55,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Items,
                    start => 1909,
                    'end' => 1914
                    },
                right => #{kind => literal,
                    value => _assert_subject@2,
                    start => 1918,
                    'end' => 1920
                    },
                start => 1902,
                'end' => 1920,
                expression_start => 1909})
    end,
    _assert_subject@3 = [],
    case Unresolved =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_3_includes_spec_list_test"/utf8>>,
                line => 56,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1930,
                    'end' => 1940
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 1944,
                    'end' => 1946
                    },
                start => 1923,
                'end' => 1946,
                expression_start => 1930})
    end.

-file("test/soundcloud_adapter_test.gleam", 59).
-spec live_all_matches_depth_3_for_current_live_graph_test() -> nil.
live_all_matches_depth_3_for_current_live_graph_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/tungstenselects"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        all,
        fun soundcloud_live_expander:expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = <<"Mahal"/utf8>>,
    case contains_list_title(Lists, _assert_subject) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_matches_depth_3_for_current_live_graph_test"/utf8>>,
                line => 70,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 2420,
                        'end' => 2425
                        }, #{kind => literal,
                        value => _assert_subject,
                        start => 2427,
                        'end' => 2434
                        }],
                start => 2393,
                'end' => 2435,
                expression_start => 2400})
    end,
    _assert_subject@1 = <<"Glass Beams"/utf8>>,
    case contains_any_track_id(Lists, _assert_subject@1) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_matches_depth_3_for_current_live_graph_test"/utf8>>,
                line => 71,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 2467,
                        'end' => 2472
                        }, #{kind => literal,
                        value => _assert_subject@1,
                        start => 2474,
                        'end' => 2487
                        }],
                start => 2438,
                'end' => 2488,
                expression_start => 2445})
    end,
    _assert_subject@2 = [],
    case Items /= _assert_subject@2 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_matches_depth_3_for_current_live_graph_test"/utf8>>,
                line => 72,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Items,
                    start => 2498,
                    'end' => 2503
                    },
                right => #{kind => literal,
                    value => _assert_subject@2,
                    start => 2507,
                    'end' => 2509
                    },
                start => 2491,
                'end' => 2509,
                expression_start => 2498})
    end,
    _assert_subject@3 = [],
    case Unresolved =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_matches_depth_3_for_current_live_graph_test"/utf8>>,
                line => 73,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 2519,
                    'end' => 2529
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 2533,
                    'end' => 2535
                    },
                start => 2512,
                'end' => 2535,
                expression_start => 2519})
    end.

-file("test/soundcloud_adapter_test.gleam", 102).
-spec live_all_full_recursion_collects_expected_shape_test() -> nil.
live_all_full_recursion_collects_expected_shape_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/tungstenselects"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        all,
        fun soundcloud_live_expander:expand/1
    ),
    {resolve_result, Items, Lists, Unresolved} = Result,
    _assert_subject = erlang:length(Items),
    _assert_subject@1 = 40,
    case _assert_subject >= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_full_recursion_collects_expected_shape_test"/utf8>>,
                line => 114,
                kind => binary_operator,
                operator => '>=',
                left => #{kind => expression,
                    value => _assert_subject,
                    start => 3887,
                    'end' => 3905
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 3909,
                    'end' => 3911
                    },
                start => 3880,
                'end' => 3911,
                expression_start => 3887})
    end,
    _assert_subject@2 = <<"A Horse with no Name (Edit)"/utf8>>,
    case contains_title(Items, _assert_subject@2) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_full_recursion_collects_expected_shape_test"/utf8>>,
                line => 115,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 3936,
                        'end' => 3941
                        }, #{kind => literal,
                        value => _assert_subject@2,
                        start => 3943,
                        'end' => 3972
                        }],
                start => 3914,
                'end' => 3973,
                expression_start => 3921})
    end,
    _assert_subject@3 = <<"Premiere: KAIPE - Batie"/utf8>>,
    case contains_title_fragment(Items, _assert_subject@3) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_full_recursion_collects_expected_shape_test"/utf8>>,
                line => 116,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 4007,
                        'end' => 4012
                        }, #{kind => literal,
                        value => _assert_subject@3,
                        start => 4014,
                        'end' => 4039
                        }],
                start => 3976,
                'end' => 4040,
                expression_start => 3983})
    end,
    _assert_subject@4 = <<"Mahal"/utf8>>,
    case contains_list_title(Lists, _assert_subject@4) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_full_recursion_collects_expected_shape_test"/utf8>>,
                line => 117,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 4070,
                        'end' => 4075
                        }, #{kind => literal,
                        value => _assert_subject@4,
                        start => 4077,
                        'end' => 4084
                        }],
                start => 4043,
                'end' => 4085,
                expression_start => 4050})
    end,
    _assert_subject@5 = <<"Glass Beams"/utf8>>,
    case contains_any_track_id(Lists, _assert_subject@5) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_full_recursion_collects_expected_shape_test"/utf8>>,
                line => 118,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 4117,
                        'end' => 4122
                        }, #{kind => literal,
                        value => _assert_subject@5,
                        start => 4124,
                        'end' => 4137
                        }],
                start => 4088,
                'end' => 4138,
                expression_start => 4095})
    end,
    _assert_subject@6 = [],
    case Unresolved =:= _assert_subject@6 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_all_full_recursion_collects_expected_shape_test"/utf8>>,
                line => 119,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 4148,
                    'end' => 4158
                    },
                right => #{kind => literal,
                    value => _assert_subject@6,
                    start => 4162,
                    'end' => 4164
                    },
                start => 4141,
                'end' => 4164,
                expression_start => 4148})
    end.
