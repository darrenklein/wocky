%%% @copyright 2015+ Hippware, Inc.
%%% @doc A module to store XEP-0012 Last Activity data into Cassandra

-module(mod_last_wocky).

-behaviour(mod_last).

-export([init/2,
         get_last/2,
         count_active_users/2,
         set_last_info/4,
         remove_user/2]).

-include_lib("ejabberd/include/ejabberd.hrl").
-include_lib("ejabberd/include/mod_last.hrl").


%% @doc Initialise this module (from {@link mod_last})
-spec init(ejabberd:server(), list()) -> ok.
init(_Host, _Opts) ->
    ok.

-spec get_last(ejabberd:luser(), ejabberd:lserver())
              -> {ok, non_neg_integer(), binary()}
               | {error, term()}
               | not_found.
get_last(LUser, LServer) ->
    Q = "SELECT timestamp, status FROM last_activity WHERE user = ? AND server = ?",
    Values = [{user, LUser}, {server, LServer}],
    case wocky_db:query(shared, Q, Values, quorum) of
        {error, E} -> {error, E};
        {ok, R} ->
            case wocky_db:single_row(R) of
                undefined -> not_found;
                Row -> {ok, proplists:get_value(timestamp, Row), proplists:get_value(status, Row)}
            end
    end.

-spec count_active_users(ejabberd:lserver(), non_neg_integer())
                        -> non_neg_integer().
count_active_users(LServer, TimeStamp) ->
    Q = "SELECT timestamp FROM last_activity WHERE server = ?",
    Values = [{server, LServer}, {timestamp, TimeStamp}],
    case wocky_db:query(shared, Q, Values, quorum) of
        {error, E} -> {error, E};
        {ok, R} ->
            Pred = fun([{timestamp, Val}]) -> Val > TimeStamp end,
            wocky_db:count(Pred, R)
    end.

-spec set_last_info(ejabberd:luser(), ejabberd:lserver(),
                    non_neg_integer(), binary())
                   -> ok | {error, term()}.
set_last_info(LUser, LServer, TimeStamp, Status) ->
    Q = "INSERT INTO last_activity (user, server, timestamp, status) VALUES (?, ?, ?, ?)",
    Values = [{user, LUser}, {server, LServer}, {timestamp, TimeStamp}, {status, Status}],
    case wocky_db:query(shared, Q, Values, quorum) of
        {error, E} -> {error, E};
        {ok, void} -> ok
    end.

-spec remove_user(ejabberd:luser(), ejabberd:lserver()) -> ok.
remove_user(LUser, LServer) ->
    Q = "DELETE FROM last_activity WHERE user = ? AND server = ?",
    Values = [{user, LUser}, {server, LServer}],
    case wocky_db:query(shared, Q, Values, quorum) of
        {error, E} -> {error, E};
        {ok, void} -> ok
    end.
