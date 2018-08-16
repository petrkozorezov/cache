%%
%%   Copyright 2012 Dmitry Kolesnikov, All Rights Reserved
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%%  @description
%%   segmented in-memory cache
%%      * cache memory is split into N segments
%%      * cache applies eviction and quota policies at segment level
%%        (e.g. whole segments is destroyed at time)
%%      * cache add new items to youngest segment
%%      * cache lookup items from youngest to oldest segment
%%
%%  @todo
%%   * procedure to get / lookup multiple keys (e.g. get_, getm, ...)
%%   * unit tests (improve coverage)
%%   * cache read/write through handler
%%   * memcached protocol
-module(cache).
-author('Dmitry Kolesnikov <dmkolesnikov@gmail.com>').

-include("cache.hrl").

%% cache management interface
-export([
   start_link/1,
   start_link/2,
   drop/1,
   purge/1,
   i/1,
   i/2,
   heap/2
]).
%% basic cache i/o interface
-export([
   put/3,
   put/4,
   put/5,
   put_/3,
   put_/4,
   put_/5,
   get/2,
   get/3,
   get_/2,
   lookup/2,
   lookup/3,
   lookup_/2,
   has/2,
   has/3,
   ttl/2,
   ttl/3,
   remove/2,
   remove/3,
   remove_/2,
   remove_/3,
   apply/3,
   apply/4,
   apply_/4,
   apply_/3
]).
%% extended cache i/o interface
-export([
   acc/3,
   acc/4,
   acc_/3,
   acc_/4,
   set/3,
   set/4,
   set/5,
   set_/3,
   set_/4,
   set_/5,
   add/3,
   add/4,
   add/5,
   add_/3,
   add_/4,
   add_/5,
   replace/3,
   replace/4,
   replace/5,
   replace_/3,
   replace_/4,
   replace_/5,
   append/3,
   append/4,
   append_/3,
   append_/4,
   prepend/3,
   prepend/4,
   prepend_/3,
   prepend_/4,
   delete/2,
   delete/3,
   delete_/2,
   delete_/3
]).
-export([start/0]).

-export_type([cache_reg_name/0]).
-export_type([cache/0]).
-export_type([options/0]).

-type(cache_reg_name() :: atom() | {global, atom()} | {via, atom(), term()}).
-type(cache()          :: atom() | pid() | {global, atom()} | {via, atom(), term()}).
-type(key()            :: any()).
-type(val()            :: any()).
-type(ttl()            :: integer() | undefined).
-type(acc()            :: integer() | [{integer(), integer()}]).
-type(options()        :: cache_bucket:options()).

%%
%% RnD start application
start() ->
   application:start(cache).

%%%----------------------------------------------------------------------------
%%%
%%% cache management interface
%%%
%%%----------------------------------------------------------------------------

%%
%% start new cache bucket
-spec(start_link(options()) -> {ok, pid()} | {error, any()}).
-spec(start_link(cache_reg_name(), options()) -> {ok, pid()} | {error, any()}).

start_link(Opts) ->
   cache_bucket:start_link(Opts).

start_link(Cache, Opts) ->
   cache_bucket:start_link(Cache, Opts).

%%
%% drop cache
-spec(drop(cache()) -> ok).

drop(Cache) ->
   gen_server:call(Cache, drop).

%%
%% purge cache
-spec(purge(cache()) -> ok).

purge(Cache) ->
   gen_server:call(Cache, purge).


%%
%% return cache meta data
%%    {heap,   [integer()]} - references to cache segments
%%    {expire, [integer()]} - cache segments expiration times
%%    {size,   [integer()]} - cardinality of cache segments
%%    {memory, [integer()]} - memory occupied by each cache segment
-spec(i(cache()) -> list()).
-spec(i(cache(), atom()) -> list()).

i(Cache) ->
   gen_server:call(Cache, i).

i(Cache, Name) ->
   proplists:get_value(Name, i(Cache)).

%%
%% return nth cache segment (e.g. heap(..., 1) returns youngest segment)
-spec(heap(cache(), integer()) -> integer() | badarg).

heap(Cache, N) ->
   gen_server:call(Cache, {heap, N}).


%%%----------------------------------------------------------------------------
%%%
%%% basic cache i/o interface
%%%
%%%----------------------------------------------------------------------------

%%
%% synchronous cache put
-spec(put(cache(), key(), val()) -> ok).
-spec(put(cache(), key(), val(), ttl()) -> ok).
-spec(put(cache(), key(), val(), ttl(), timeout()) -> ok).

put(Cache, Key, Val) ->
   cache:put(Cache, Key, Val, undefined, ?CONFIG_TIMEOUT).

put(Cache, Key, Val, TTL) ->
   cache:put(Cache, Key, Val, TTL, ?CONFIG_TIMEOUT).

put(Cache, Key, Val, TTL, Timeout) ->
   call(Cache, {put, Key, Val, TTL}, Timeout).


%%
%% asynchronous cache put
-spec(put_(cache(), key(), val()) -> ok | reference()).
-spec(put_(cache(), key(), val(), ttl()) -> ok | reference()).
-spec(put_(cache(), key(), val(), ttl(), true | false) -> ok | reference()).

put_(Cache, Key, Val) ->
   cache:put_(Cache, Key, Val, undefined, false).

put_(Cache, Key, Val, TTL) ->
   cache:put_(Cache, Key, Val, TTL, false).

put_(Cache, Key, Val, TTL, true) ->
   cast(Cache, {put, Key, Val, TTL});

put_(Cache, Key, Val, TTL, false) ->
   send(Cache, {put, Key, Val, TTL}).

%%
%% synchronous cache get, the operation prolongs value ttl
-spec(get(cache(), key()) -> val() | undefined).
-spec(get(cache(), key(), timeout()) -> val() | undefined).

get(Cache, Key) ->
   cache:get(Cache, Key, ?CONFIG_TIMEOUT).

get(Cache, Key, Timeout) ->
   call(Cache, {get, Key}, Timeout).

%%
%% asynchronous cache get, the operation prolongs value ttl
-spec(get_(cache(), key()) -> reference()).

get_(Cache, Key) ->
   cast(Cache, {get, Key}).

%%
%% synchronous cache lookup, the operation do not prolong entry ttl
-spec(lookup(cache(), key()) -> val() | undefined).
-spec(lookup(cache(), key(), timeout()) -> val() | undefined).

lookup(Cache, Key) ->
   cache:lookup(Cache, Key, ?CONFIG_TIMEOUT).

lookup(Cache, Key, Timeout) ->
   call(Cache, {lookup, Key}, Timeout).

%%
%% asynchronous cache lookup, the operation do not prolong entry ttl
-spec(lookup_(cache(), key()) -> reference()).

lookup_(Cache, Key) ->
   cast(Cache, {lookup, Key}).

%%
%% check if cache key exists,
-spec(has(cache(), key()) -> true | false).
-spec(has(cache(), key(), timeout()) -> true | false).

has(Cache, Key) ->
   cache:has(Cache, Key, ?CONFIG_TIMEOUT).

has(Cache, Key, Timeout) ->
   call(Cache, {has, Key}, Timeout).

%%
%% check entity at cache and return estimated ttl
-spec(ttl(cache(), key()) -> ttl() | false).
-spec(ttl(cache(), key(), timeout()) -> ttl() | false).

ttl(Cache, Key) ->
   cache:ttl(Cache, Key, ?CONFIG_TIMEOUT).

ttl(Cache, Key, Timeout) ->
   call(Cache, {ttl, Key}, Timeout).

%%
%% synchronous remove entry from cache
-spec(remove(cache(), key()) -> ok).
-spec(remove(cache(), key(), timeout()) -> ok).

remove(Cache, Key) ->
   cache:remove(Cache, Key, ?CONFIG_TIMEOUT).

remove(Cache, Key, Timeout) ->
   call(Cache, {remove, Key}, Timeout).

%%
%% asynchronous remove entry from cache
-spec(remove_(cache(), key()) -> ok | reference()).
-spec(remove_(cache(), key(), true | false) -> ok | reference()).

remove_(Cache, Key) ->
   cache:remove_(Cache, Key, false).

remove_(Cache, Key, true) ->
   cast(Cache, {remove, Key});

remove_(Cache, Key, false) ->
   send(Cache, {remove, Key}).

%%
%% synchronous apply function to entity on cache
%% the function maps element, the new value is returned
%% the operation prolongs value ttl
-spec apply(cache(), key(), fun((_) -> _)) -> val() | undefined.
-spec apply(cache(), key(), fun((_) -> _), timeout()) -> val() | undefined.

apply(Cache, Key, Fun) ->
   cache:apply(Cache, Key, Fun, ?CONFIG_TIMEOUT).

apply(Cache, Key, Fun, Timeout) ->
   call(Cache, {apply, Key, Fun}, Timeout).


%%
%% asynchronous apply function to entity on cache
%% the function maps element, the new value is returned
%% the operation prolongs value ttl
-spec apply_(cache(), key(), fun((_) -> _)) -> ok | reference().
-spec apply_(cache(), key(), fun((_) -> _), true | false) -> ok | reference().

apply_(Cache, Key, Fun) ->
   cache:apply_(Cache, Key, Fun, false).

apply_(Cache, Key, Fun, true) ->
   cast(Cache, {apply, Key, Fun});

apply_(Cache, Key, Fun, false) ->
   cast(Cache, {apply, Key, Fun}).

%%%----------------------------------------------------------------------------
%%%
%%% extended cache i/o interface
%%%
%%%----------------------------------------------------------------------------

%%
%% synchronous in-cache accumulator
-spec(acc(cache(), key(), acc()) -> integer() | undefined).
-spec(acc(cache(), key(), acc(), timeout()) -> integer() | undefined).

acc(Cache, Key, Val) ->
   cache:acc(Cache, Key, Val, ?CONFIG_TIMEOUT).

acc(Cache, Key, Val, Timeout) ->
   call(Cache, {acc, Key, Val}, Timeout).

%%
%% asynchronous in-cache accumulator
-spec(acc_(cache(), key(), acc()) -> ok | reference()).
-spec(acc_(cache(), key(), acc(), true | false) -> ok).

acc_(Cache, Key, Val) ->
   cache:acc_(Cache, Key, Val, false).

acc_(Cache, Key, Val, true) ->
   cast(Cache, {acc, Key, Val});

acc_(Cache, Key, Val, false) ->
   send(Cache, {acc, Key, Val}).

%%
%% synchronous store key/val
-spec(set(cache(), key(), val()) -> ok).
-spec(set(cache(), key(), val(), ttl()) -> ok).
-spec(set(cache(), key(), val(), ttl(), timeout()) -> ok).

set(Cache, Key, Val) ->
   cache:put(Cache, Key, Val).

set(Cache, Key, Val, TTL) ->
   cache:put(Cache, Key, Val, TTL).

set(Cache, Key, Val, TTL, Timeout) ->
   cache:put(Cache, Key, Val, TTL, Timeout).

%%
%% asynchronous store key/val
-spec(set_(cache(), key(), val()) -> ok | reference()).
-spec(set_(cache(), key(), val(), ttl()) -> ok | reference()).
-spec(set_(cache(), key(), val(), ttl(), true | false) -> ok | reference()).

set_(Cache, Key, Val) ->
   cache:put_(Cache, Key, Val).

set_(Cache, Key, Val, TTL) ->
   cache:put_(Cache, Key, Val, TTL).

set_(Cache, Key, Val, TTL, Flag) ->
   cache:put_(Cache, Key, Val, TTL, Flag).

%%
%% synchronous store key/val only if cache does not already hold data for this key
-spec(add(cache(), key(), val()) -> ok | {error, conflict}).
-spec(add(cache(), key(), val(), ttl()) -> ok | {error, conflict}).
-spec(add(cache(), key(), val(), ttl(), timeout()) -> ok | {error, conflict}).

add(Cache, Key, Val) ->
   cache:add(Cache, Key, Val, undefined, ?CONFIG_TIMEOUT).

add(Cache, Key, Val, TTL) ->
   cache:add(Cache, Key, Val, TTL, ?CONFIG_TIMEOUT).

add(Cache, Key, Val, TTL, Timeout) ->
   call(Cache, {add, Key, Val, TTL}, Timeout).

%%
%% asynchronous store key/val only if cache does not already hold data for this key
-spec(add_(cache(), key(), val()) -> ok | reference()).
-spec(add_(cache(), key(), val(), ttl()) -> ok | reference()).
-spec(add_(cache(), key(), val(), ttl(), true | false) -> ok | reference()).

add_(Cache, Key, Val) ->
   cache:add_(Cache, Key, Val, undefined, false).

add_(Cache, Key, Val, TTL) ->
   cache:add_(Cache, Key, Val, TTL, false).

add_(Cache, Key, Val, TTL, true) ->
   cast(Cache, {add, Key, Val, TTL});

add_(Cache, Key, Val, TTL, false) ->
   send(Cache, {add, Key, Val, TTL}).

%%
%% synchronous store key/val only if cache does hold data for this key
-spec(replace(cache(), key(), val()) -> ok | {error, not_found}).
-spec(replace(cache(), key(), val(), ttl()) -> ok | {error, not_found}).
-spec(replace(cache(), key(), val(), ttl(), timeout()) -> ok | {error, not_found}).

replace(Cache, Key, Val) ->
   cache:replace(Cache, Key, Val, undefined, ?CONFIG_TIMEOUT).

replace(Cache, Key, Val, TTL) ->
   cache:replace(Cache, Key, Val, TTL, ?CONFIG_TIMEOUT).

replace(Cache, Key, Val, TTL, Timeout) ->
   call(Cache, {replace, Key, Val, TTL}, Timeout).

%%
%% asynchronous store key/val only if cache does hold data for this key
-spec(replace_(cache(), key(), val()) -> ok | reference()).
-spec(replace_(cache(), key(), val(), ttl()) -> ok | reference()).
-spec(replace_(cache(), key(), val(), ttl(), true | false) -> ok | reference()).

replace_(Cache, Key, Val) ->
   cache:replace_(Cache, Key, Val, undefined, false).

replace_(Cache, Key, Val, TTL) ->
   cache:replace_(Cache, Key, Val, TTL, false).

replace_(Cache, Key, Val, TTL, true) ->
   cast(Cache, {replace, Key, Val, TTL});

replace_(Cache, Key, Val, TTL, false) ->
   send(Cache, {replace, Key, Val, TTL}).


%%
%% synchronously add data to existing key after existing data,
%% the operation do not prolong entry ttl
-spec(append(cache(), key(), val()) -> ok | {error, not_found}).
-spec(append(cache(), key(), val(), timeout()) -> ok | {error, not_found}).

append(Cache, Key, Val) ->
   cache:append(Cache, Key, Val, ?CONFIG_TIMEOUT).

append(Cache, Key, Val, Timeout) ->
   call(Cache, {append, Key, Val}, Timeout).

%%
%% asynchronously add data to existing key after existing data,
%% the operation do not prolong entry ttl
-spec(append_(cache(), key(), val()) -> ok | reference()).
-spec(append_(cache(), key(), val(), true | false) -> ok | reference()).

append_(Cache, Key, Val) ->
   cache:append_(Cache, Key, Val, false).

append_(Cache, Key, Val, true) ->
   cast(Cache, {append, Key, Val});
append_(Cache, Key, Val, false) ->
   send(Cache, {append, Key, Val}).


%%
%% synchronously add data to existing key before existing data
%% the operation do not prolong entry ttl
-spec(prepend(cache(), key(), val()) -> ok | {error, not_found}).
-spec(prepend(cache(), key(), val(), timeout()) -> ok | {error, not_found}).

prepend(Cache, Key, Val) ->
   cache:prepend(Cache, Key, Val, ?CONFIG_TIMEOUT).

prepend(Cache, Key, Val, Timeout) ->
   call(Cache, {prepend, Key, Val}, Timeout).

%%
%% asynchronously add data to existing key before existing data
%% the operation do not prolong entry ttl
-spec(prepend_(cache(), key(), val()) -> reference()).
-spec(prepend_(cache(), key(), val(), true | false) -> reference()).

prepend_(Cache, Key, Val) ->
   cache:prepend_(Cache, Key, Val, false).

prepend_(Cache, Key, Val, true) ->
   cast(Cache, {prepend, Key, Val});

prepend_(Cache, Key, Val, false) ->
   send(Cache, {prepend, Key, Val}).

%%
%% synchronous remove entry from cache
-spec(delete(cache(), key()) -> ok).
-spec(delete(cache(), key(), timeout()) -> ok).

delete(Cache, Key) ->
   cache:remove(Cache, Key).

delete(Cache, Key, Timeout) ->
   cache:remove(Cache, Key, Timeout).

%%
%% asynchronous remove entry from cache
-spec(delete_(cache(), key()) -> ok | reference()).
-spec(delete_(cache(), key(), true | false) -> ok | reference()).

delete_(Cache, Key) ->
   cache:remove_(Cache, Key).

delete_(Cache, Key, Flag) ->
   cache:remove_(Cache, Key, Flag).


%%%----------------------------------------------------------------------------
%%%
%%% private
%%%
%%%----------------------------------------------------------------------------

%%
%% synchronous call to server, client is blocks
call(Ref, Req, Timeout) ->
   gen_server:call(Ref, Req, Timeout).

%%
%% asynchronous call to server,
%% the request is acknowledged using reference
cast(Ref, Req) ->
   Ref = erlang:make_ref(),
   erlang:send(where(Ref), {'$gen_call', {self(), Ref}, Req}, [noconnect]),
   Ref.

%%
%% fire-and-forget
send(Ref, Req) ->
   gen_server:cast(Ref, Req).

where(Name) when is_atom(Name) ->
    erlang:whereis(Name);
where({global, Name}) ->
    global:whereis_name(Name);
where({via, Module, Name}) ->
    Module:whereis_name(Name);
where(Pid) when is_pid(Pid) ->
    Pid.
