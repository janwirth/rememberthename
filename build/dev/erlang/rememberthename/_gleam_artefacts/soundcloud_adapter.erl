-module(soundcloud_adapter).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/soundcloud_adapter.gleam").
-export([resolve_profile/3]).
-export_type([depth_mode/0, source_identity/0, adapter_node/0, unified_item/0, unified_collection/0, expand_result/0, resolve_result/0]).

-type depth_mode() :: depth1 | depth2 | depth3 | depth10 | depth20 | all.

-type source_identity() :: {source_identity, binary(), binary(), binary()}.

-type adapter_node() :: {profile_entry, source_identity()} |
    {category_node, binary()} |
    {list_node, binary()} |
    {page_node, binary()}.

-type unified_item() :: {unified_item,
        binary(),
        binary(),
        binary(),
        binary(),
        binary(),
        binary()}.

-type unified_collection() :: {unified_collection,
        binary(),
        binary(),
        list(binary()),
        list(binary()),
        binary(),
        binary(),
        binary()}.

-type expand_result() :: {expand_result,
        list(unified_item()),
        list(unified_collection()),
        list(adapter_node()),
        list(adapter_node())}.

-type resolve_result() :: {resolve_result,
        list(unified_item()),
        list(unified_collection()),
        list(adapter_node())}.

-file("src/soundcloud_adapter.gleam", 154).
-spec can_expand(integer(), depth_mode()) -> boolean().
can_expand(Level, Depth) ->
    case Depth of
        depth1 ->
            Level < 1;

        depth2 ->
            Level < 2;

        depth3 ->
            Level < 3;

        depth10 ->
            Level < 10;

        depth20 ->
            Level < 20;

        all ->
            true
    end.

-file("src/soundcloud_adapter.gleam", 165).
-spec with_level(list(adapter_node()), integer()) -> list({adapter_node(),
    integer()}).
with_level(Nodes, Level) ->
    gleam@list:map(Nodes, fun(Node) -> {Node, Level} end).

-file("src/soundcloud_adapter.gleam", 207).
-spec item_key(unified_item()) -> binary().
item_key(Item) ->
    {unified_item, _, _, _, Service, Source_type, Source_id} = Item,
    <<<<<<<<Service/binary, ":"/utf8>>/binary, Source_type/binary>>/binary,
            ":"/utf8>>/binary,
        Source_id/binary>>.

-file("src/soundcloud_adapter.gleam", 169).
-spec merge_items(
    list(unified_item()),
    gleam@set:set(binary()),
    list(unified_item())
) -> {list(unified_item()), gleam@set:set(binary())}.
merge_items(Items, Seen, Incoming) ->
    gleam@list:fold(
        Incoming,
        {Items, Seen},
        fun(Acc, Item) ->
            {Items@1, Seen@1} = Acc,
            Key = item_key(Item),
            case gleam@set:contains(Seen@1, Key) of
                true ->
                    {Items@1, Seen@1};

                false ->
                    {lists:append(Items@1, [Item]),
                        gleam@set:insert(Seen@1, Key)}
            end
        end
    ).

-file("src/soundcloud_adapter.gleam", 212).
-spec collection_key(unified_collection()) -> binary().
collection_key(Collection) ->
    {unified_collection, _, _, _, _, Service, Source_type, Source_id} = Collection,
    <<<<<<<<Service/binary, ":"/utf8>>/binary, Source_type/binary>>/binary,
            ":"/utf8>>/binary,
        Source_id/binary>>.

-file("src/soundcloud_adapter.gleam", 188).
-spec merge_lists(
    list(unified_collection()),
    gleam@set:set(binary()),
    list(unified_collection())
) -> {list(unified_collection()), gleam@set:set(binary())}.
merge_lists(Lists, Seen, Incoming) ->
    gleam@list:fold(
        Incoming,
        {Lists, Seen},
        fun(Acc, Collection) ->
            {Lists@1, Seen@1} = Acc,
            Key = collection_key(Collection),
            case gleam@set:contains(Seen@1, Key) of
                true ->
                    {Lists@1, Seen@1};

                false ->
                    {lists:append(Lists@1, [Collection]),
                        gleam@set:insert(Seen@1, Key)}
            end
        end
    ).

-file("src/soundcloud_adapter.gleam", 217).
-spec node_key(adapter_node()) -> binary().
node_key(Node) ->
    case Node of
        {profile_entry, {source_identity, Service, Source_type, Source_id}} ->
            <<<<<<<<<<"profile:"/utf8, Service/binary>>/binary, ":"/utf8>>/binary,
                        Source_type/binary>>/binary,
                    ":"/utf8>>/binary,
                Source_id/binary>>;

        {category_node, Id} ->
            <<"category:"/utf8, Id/binary>>;

        {list_node, Id@1} ->
            <<"list:"/utf8, Id@1/binary>>;

        {page_node, Id@2} ->
            <<"page:"/utf8, Id@2/binary>>
    end.

-file("src/soundcloud_adapter.gleam", 85).
-spec loop(
    list({adapter_node(), integer()}),
    gleam@set:set(binary()),
    gleam@set:set(binary()),
    gleam@set:set(binary()),
    list(unified_item()),
    list(unified_collection()),
    list(adapter_node()),
    depth_mode(),
    fun((adapter_node()) -> expand_result())
) -> resolve_result().
loop(
    Queue,
    Visited,
    Item_seen,
    List_seen,
    Items,
    Lists,
    Unresolved,
    Depth,
    Expand
) ->
    case Queue =:= [] of
        true ->
            {resolve_result, Items, Lists, Unresolved};

        false ->
            Current = gleam@result:unwrap(
                gleam@list:first(Queue),
                {{page_node, <<""/utf8>>}, 0}
            ),
            Rest = gleam@result:unwrap(gleam@list:rest(Queue), []),
            {Node, Level} = Current,
            Key = node_key(Node),
            case gleam@set:contains(Visited, Key) of
                true ->
                    loop(
                        Rest,
                        Visited,
                        Item_seen,
                        List_seen,
                        Items,
                        Lists,
                        Unresolved,
                        Depth,
                        Expand
                    );

                false ->
                    Visited@1 = gleam@set:insert(Visited, Key),
                    case can_expand(Level, Depth) of
                        false ->
                            loop(
                                Rest,
                                Visited@1,
                                Item_seen,
                                List_seen,
                                Items,
                                Lists,
                                Unresolved,
                                Depth,
                                Expand
                            );

                        true ->
                            gleam_stdlib:println(
                                <<<<<<"[fetch] node="/utf8,
                                            (node_key(Node))/binary>>/binary,
                                        " level="/utf8>>/binary,
                                    (erlang:integer_to_binary(Level))/binary>>
                            ),
                            {expand_result,
                                Next_items,
                                Next_lists,
                                Next_nodes,
                                Next_unresolved} = Expand(Node),
                            gleam_stdlib:println(
                                <<<<<<<<<<<<<<"[fetched] node="/utf8,
                                                            (node_key(Node))/binary>>/binary,
                                                        " items="/utf8>>/binary,
                                                    (erlang:integer_to_binary(
                                                        erlang:length(
                                                            Next_items
                                                        )
                                                    ))/binary>>/binary,
                                                " lists="/utf8>>/binary,
                                            (erlang:integer_to_binary(
                                                erlang:length(Next_lists)
                                            ))/binary>>/binary,
                                        " next="/utf8>>/binary,
                                    (erlang:integer_to_binary(
                                        erlang:length(Next_nodes)
                                    ))/binary>>
                            ),
                            {Items@1, Item_seen@1} = merge_items(
                                Items,
                                Item_seen,
                                Next_items
                            ),
                            {Lists@1, List_seen@1} = merge_lists(
                                Lists,
                                List_seen,
                                Next_lists
                            ),
                            Queue@1 = lists:append(
                                Rest,
                                with_level(Next_nodes, Level + 1)
                            ),
                            Unresolved@1 = lists:append(
                                Unresolved,
                                Next_unresolved
                            ),
                            loop(
                                Queue@1,
                                Visited@1,
                                Item_seen@1,
                                List_seen@1,
                                Items@1,
                                Lists@1,
                                Unresolved@1,
                                Depth,
                                Expand
                            )
                    end
            end
    end.

-file("src/soundcloud_adapter.gleam", 67).
-spec resolve_profile(
    source_identity(),
    depth_mode(),
    fun((adapter_node()) -> expand_result())
) -> resolve_result().
resolve_profile(Profile, Depth, Expand) ->
    loop(
        [{{profile_entry, Profile}, 0}],
        gleam@set:new(),
        gleam@set:new(),
        gleam@set:new(),
        [],
        [],
        [],
        Depth,
        Expand
    ).
