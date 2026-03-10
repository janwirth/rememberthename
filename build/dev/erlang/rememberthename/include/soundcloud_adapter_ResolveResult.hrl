-record(resolve_result, {
    items :: list(soundcloud_adapter:unified_item()),
    lists :: list(soundcloud_adapter:unified_collection()),
    unresolved :: list(soundcloud_adapter:adapter_node())
}).
