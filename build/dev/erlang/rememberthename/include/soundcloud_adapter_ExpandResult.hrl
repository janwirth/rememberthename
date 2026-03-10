-record(expand_result, {
    items :: list(soundcloud_adapter:unified_item()),
    lists :: list(soundcloud_adapter:unified_collection()),
    next_nodes :: list(soundcloud_adapter:adapter_node()),
    unresolved :: list(soundcloud_adapter:adapter_node())
}).
