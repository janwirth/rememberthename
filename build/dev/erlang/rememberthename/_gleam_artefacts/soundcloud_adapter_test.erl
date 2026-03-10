-module(soundcloud_adapter_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/soundcloud_adapter_test.gleam").
-export([live_depth_1_includes_shallow_spec_track_test/0, live_depth_2_includes_deeper_spec_track_test/0, live_full_includes_spec_list_test/0]).

-file("test/soundcloud_adapter_test.gleam", 58).
-spec contains_title(list(soundcloud_adapter:unified_item()), binary()) -> boolean().
contains_title(Items, Wanted) ->
    gleam@list:any(
        Items,
        fun(Item) ->
            {unified_item, _, Title, _, _, _, _} = Item,
            Title =:= Wanted
        end
    ).

-file("test/soundcloud_adapter_test.gleam", 5).
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
                line => 7,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Payload,
                    start => 246,
                    'end' => 253
                    },
                right => #{kind => literal,
                    value => _assert_subject,
                    start => 257,
                    'end' => 259
                    },
                start => 239,
                'end' => 259,
                expression_start => 246})
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
    _assert_subject@1 = [],
    case Items /= _assert_subject@1 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 19,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Items,
                    start => 650,
                    'end' => 655
                    },
                right => #{kind => literal,
                    value => _assert_subject@1,
                    start => 659,
                    'end' => 661
                    },
                start => 643,
                'end' => 661,
                expression_start => 650})
    end,
    _assert_subject@2 = <<"A Horse with no Name (Edit)"/utf8>>,
    case contains_title(Items, _assert_subject@2) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 20,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 686,
                        'end' => 691
                        }, #{kind => literal,
                        value => _assert_subject@2,
                        start => 693,
                        'end' => 722
                        }],
                start => 664,
                'end' => 723,
                expression_start => 671})
    end,
    _assert_subject@3 = [],
    case Lists =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_1_includes_shallow_spec_track_test"/utf8>>,
                line => 21,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Lists,
                    start => 733,
                    'end' => 738
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 742,
                    'end' => 744
                    },
                start => 726,
                'end' => 744,
                expression_start => 733})
    end,
    _assert_subject@4 = [],
    case Unresolved =:= _assert_subject@4 of
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
                    value => Unresolved,
                    start => 754,
                    'end' => 764
                    },
                right => #{kind => literal,
                    value => _assert_subject@4,
                    start => 768,
                    'end' => 770
                    },
                start => 747,
                'end' => 770,
                expression_start => 754})
    end.

-file("test/soundcloud_adapter_test.gleam", 25).
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
    _assert_subject = [],
    case Items /= _assert_subject of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_2_includes_deeper_spec_track_test"/utf8>>,
                line => 36,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Items,
                    start => 1220,
                    'end' => 1225
                    },
                right => #{kind => literal,
                    value => _assert_subject,
                    start => 1229,
                    'end' => 1231
                    },
                start => 1213,
                'end' => 1231,
                expression_start => 1220})
    end,
    _assert_subject@1 = <<"Premiere: KAIPE - Batie"/utf8>>,
    case contains_title(Items, _assert_subject@1) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_2_includes_deeper_spec_track_test"/utf8>>,
                line => 37,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Items,
                        start => 1256,
                        'end' => 1261
                        }, #{kind => literal,
                        value => _assert_subject@1,
                        start => 1263,
                        'end' => 1288
                        }],
                start => 1234,
                'end' => 1289,
                expression_start => 1241})
    end,
    _assert_subject@2 = [],
    case Unresolved =:= _assert_subject@2 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_depth_2_includes_deeper_spec_track_test"/utf8>>,
                line => 38,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1299,
                    'end' => 1309
                    },
                right => #{kind => literal,
                    value => _assert_subject@2,
                    start => 1313,
                    'end' => 1315
                    },
                start => 1292,
                'end' => 1315,
                expression_start => 1299})
    end.

-file("test/soundcloud_adapter_test.gleam", 65).
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

-file("test/soundcloud_adapter_test.gleam", 72).
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

-file("test/soundcloud_adapter_test.gleam", 41).
-spec live_full_includes_spec_list_test() -> nil.
live_full_includes_spec_list_test() ->
    Profile = {source_identity,
        <<"soundcloud"/utf8>>,
        <<"collection"/utf8>>,
        <<"https://soundcloud.com/tungstenselects"/utf8>>},
    Result = soundcloud_adapter:resolve_profile(
        Profile,
        full,
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
                function => <<"live_full_includes_spec_list_test"/utf8>>,
                line => 52,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 1771,
                        'end' => 1776
                        }, #{kind => literal,
                        value => _assert_subject,
                        start => 1778,
                        'end' => 1785
                        }],
                start => 1744,
                'end' => 1786,
                expression_start => 1751})
    end,
    _assert_subject@1 = <<"Glass Beams"/utf8>>,
    case contains_any_track_id(Lists, _assert_subject@1) of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_full_includes_spec_list_test"/utf8>>,
                line => 53,
                kind => function_call,
                arguments => [#{kind => expression,
                        value => Lists,
                        start => 1818,
                        'end' => 1823
                        }, #{kind => literal,
                        value => _assert_subject@1,
                        start => 1825,
                        'end' => 1838
                        }],
                start => 1789,
                'end' => 1839,
                expression_start => 1796})
    end,
    _assert_subject@2 = [],
    case Items /= _assert_subject@2 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_full_includes_spec_list_test"/utf8>>,
                line => 54,
                kind => binary_operator,
                operator => '!=',
                left => #{kind => expression,
                    value => Items,
                    start => 1849,
                    'end' => 1854
                    },
                right => #{kind => literal,
                    value => _assert_subject@2,
                    start => 1858,
                    'end' => 1860
                    },
                start => 1842,
                'end' => 1860,
                expression_start => 1849})
    end,
    _assert_subject@3 = [],
    case Unresolved =:= _assert_subject@3 of
        true -> nil;
        false -> erlang:error(#{gleam_error => assert,
                message => <<"Assertion failed."/utf8>>,
                file => <<?FILEPATH/utf8>>,
                module => <<"soundcloud_adapter_test"/utf8>>,
                function => <<"live_full_includes_spec_list_test"/utf8>>,
                line => 55,
                kind => binary_operator,
                operator => '==',
                left => #{kind => expression,
                    value => Unresolved,
                    start => 1870,
                    'end' => 1880
                    },
                right => #{kind => literal,
                    value => _assert_subject@3,
                    start => 1884,
                    'end' => 1886
                    },
                start => 1863,
                'end' => 1886,
                expression_start => 1870})
    end.
