-module(cache_hash).
-export([phash/1]).

phash(Value) ->
    integer_to_binary(erlang:phash2(iolist_to_binary(Value))).
