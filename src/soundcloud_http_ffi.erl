-module(soundcloud_http_ffi).
-export([safe_send/1]).

%% Calls hackney directly with session_tickets disabled.
%% gleam@hackney:send/1 doesn't expose ssl_options, and OTP's
%% tls_client_ticket_store crashes (try_clause) on TLS 1.3 session
%% tickets from api-v2.soundcloud.com, killing the connection process.
%%
%% Also adds retry with backoff for 429/5xx and returns {error,...} for
%% non-2xx so the Gleam layer gets an empty string instead of SoundCloud's
%% error body being misread as track data.
safe_send(Request) ->
    do_safe_send(Request, 3).

do_safe_send(Request, Retries) ->
    Method  = method_str(element(2, Request)),
    Headers = element(3, Request),
    Body    = element(4, Request),
    Scheme  = element(5, Request),
    Host    = binary_to_list(element(6, Request)),
    Port    = element(7, Request),
    Path    = binary_to_list(element(8, Request)),
    Query   = element(9, Request),
    Url     = build_url(Scheme, Host, Port, Path, Query),
    Options = [{with_body, true}, {pool, false}, {ssl_options, [{session_tickets, disabled}]}],
    try hackney:request(Method, Url, Headers, Body, Options) of
        {ok, Status, RespHeaders, RespBody} when Status >= 200, Status < 300 ->
            case unicode:characters_to_binary(RespBody) of
                Bin when is_binary(Bin) ->
                    {ok, {response, Status, RespHeaders, Bin}};
                _ ->
                    {error, invalid_utf8_response}
            end;
        {ok, Status, _RespHeaders, _RespBody} when Status =:= 429;
                                                    Status =:= 502;
                                                    Status =:= 503 ->
            case Retries > 0 of
                true ->
                    Delay = (4 - Retries) * 3000,
                    logger:warning("soundcloud ~p, backing off ~pms (~p retries left)",
                                   [Status, Delay, Retries - 1]),
                    receive after Delay -> ok end,
                    do_safe_send(Request, Retries - 1);
                false ->
                    logger:warning("soundcloud ~p, no retries left", [Status]),
                    {error, {other, rate_limited}}
            end;
        {ok, Status, _RespHeaders, _RespBody} ->
            logger:warning("soundcloud http ~p", [Status]),
            {error, {other, {http_error, Status}}};
        {error, Reason} ->
            logger:warning("soundcloud fetch error: ~p", [Reason]),
            case Retries > 0 of
                true ->
                    receive after 1000 -> ok end,
                    do_safe_send(Request, Retries - 1);
                false ->
                    {error, {other, Reason}}
            end
    catch
        Class:Reason ->
            logger:warning("soundcloud fetch ~p: ~P", [Class, Reason, 6]),
            {error, {other, connection_failed}}
    end.

method_str(get)         -> <<"GET">>;
method_str(post)        -> <<"POST">>;
method_str(put)         -> <<"PUT">>;
method_str(patch)       -> <<"PATCH">>;
method_str(delete)      -> <<"DELETE">>;
method_str(head)        -> <<"HEAD">>;
method_str(options)     -> <<"OPTIONS">>;
method_str({other, M})  -> M.

build_url(Scheme, Host, Port, Path, Query) ->
    S = atom_to_list(Scheme) ++ "://",
    P = port_str(Scheme, Port),
    Q = query_str(Query),
    list_to_binary(S ++ Host ++ P ++ Path ++ Q).

port_str(https, none)        -> "";
port_str(http,  none)        -> "";
port_str(https, {some, 443}) -> "";
port_str(http,  {some, 80})  -> "";
port_str(_,     {some, N})   -> ":" ++ integer_to_list(N).

query_str(none)      -> "";
query_str({some, Q}) -> "?" ++ binary_to_list(Q).
