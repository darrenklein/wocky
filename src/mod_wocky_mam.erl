%%% @copyright 2016+ Hippware, Inc.
%%% @doc Wocky C* Backend for mod_mam
%%%
%%% This module provides the archive_message_hook and lookup_messages_hook that
%%% are called by `mod_mam' to archive and retrive messages.
%%%
%%% See XEP-0313 for MAM details and XEP-0059 for Result Set Management (RSM)
%%% descriptions.
%%%
%%% Data is stored in the `message_archive' table and the `archive_id'
%%% materialized view. Of particular note are the two fields `id' and `time'.
%%% These are both unique, chronologically ordered IDs for the message. The key
%%% difference is that `id' is supplied by MIM when it archives the message. It,
%%% rather unfortunately, relies on Erlang's `now/0' function, the use of which
%%% is now frowned upon. In order to avoid our code relying on that, the `time'
%%% field is a C* v1 UUID which also encodes that time at which the message was
%%% archived. Thus, in this module, `id' is treated as a unique identifier, but
%%% we rely on neither its ordering nor its encoding of the message's timestamp,
%%% both of which are instead supplied by `time'.
%%%
%%% While archiving is relatively simple, there's a bunch of different ways to
%%% look up messages. Each option has an optional limit on the number of
%%% messages returned by the request. Each can also be asked to return a pair of
%%% counts, as described below:
%%%
%%% * Time-only:
%%%     Provides a start and/or end time and optional limit.
%%%     Counts are:
%%%         * Total messages in the archive within specified time range
%%%         * Messages in archive before first returned
%%%
%%% * Borders-only:
%%%     Provides an `#mam_borders{}' record with inclusive or exclusive start
%%%     and/or end ID values.
%%%     Counts are:
%%%         * Total messages in the archive within the specified range of IDs
%%%         * Messages in archive before first returned
%%%
%%% * RSM ID-paging:
%%%     Uses a `#rsm_in{}' record to provide Result Set Management paging. This
%%%     allows forward or backwards paging from a specified ID.
%%%     Counts are:
%%%         * Total messages in the archive
%%%         * The index of the ''oldest'' message in the returned set.
%%%
%%% * RSM Index-paging:
%%%     Provides jump straight to a fixed offset into a user's full archive,
%%%     using the `index' field of an `#rsm_in{}' record. Note that this is
%%%     necessarily a slower operation than any of the above (and is specified
%%%     as such in the RSM XEP) since the concept of an "index" is based
%%%     entirely on the number of items in the archive and cannot therefore be
%%%     easily optimised beyond O(N).
%%%     Counts are:
%%%         * Total messages in the archive
%%%         * The index of the first message (should match requested index
%%%           assuming that falls within the valid range)
%%%
%%%
%%% Other random notes:
%%%
%%% The `rms_in.max' field is at all times treated as being interchangeable with
%%% the `PageSize' parameter. If one is `undefined', the valid value will be
%%% used. It is an error to call `lookup_message_hook' with two different
%%% integer values in these fields.
%%%
-module(mod_wocky_mam).

-behaviour(gen_mod).

-compile({parse_transform, fun_chain}).

-include_lib("ejabberd/include/jlib.hrl").

%% gen_mod handlers
-export([start/2, stop/1]).

-export([
         %% MAM hook handlers
         archive_message_hook/9,
         lookup_messages_hook/14,
         %% Export for DB seeding
         jid_key/2
        ]).

-ifdef(TEST).
-export([
         archive_test_message/7,
         do_lookup/7,
         standard_counts/8
        ]).
-endif.

-type result_row() :: {non_neg_integer(), ejabberd:jid(), exml:element()}.
-type mam_time() :: {uuid, inclusive | exclusive, binary()} |
                    {time, non_neg_integer()} |
                    undefined.

%%%===================================================================
%%% gen_mod implementation
%%%===================================================================

hooks() ->
    [
     {mam_archive_message, archive_message_hook},
     {mam_lookup_messages, lookup_messages_hook}
    ].

start(Host, _Opts) ->
    wocky_util:add_hooks(hooks(), Host, ?MODULE, 50),
    ok.

stop(Host) ->
    wocky_util:delete_hooks(hooks(), Host, ?MODULE, 50),
    ok.

%%%===================================================================
%%% mam_archive_message callback
%%%===================================================================

-spec archive_message_hook(Result :: any(),
                      Host   :: ejabberd:server(),
                      MessID :: mod_mam:message_id(),
                      ArcID  :: mod_mam:archive_id(),
                      LocJID :: ejabberd:jid(),
                      RemJID :: ejabberd:jid(),
                      SrcJID :: ejabberd:jid(),
                      Dir    :: incoming | outgoing,
                      Packet :: exml:element()
                     ) -> ok.
archive_message_hook(_Result, Host, MessID, _UserID,
                LocJID, RemJID, _SrcJID, incoming, Packet) ->
    TTL = gen_mod:get_module_opt(global, ?MODULE, message_ttl, infinity),
    PartKey = jid_key(LocJID, RemJID),
    PacketBin = exml:to_binary(Packet),
    ToLower = sent_to_lower(LocJID, RemJID),
    Row = PartKey#{id => MessID, time => now, message => PacketBin,
                   sent_to_lower => ToLower},
    ok = wocky_db:insert(Host, message_archive, maybe_add_ttl(Row, TTL));

archive_message_hook(_Result, _Host, _MessID, _UserID,
                _LocJID, _RemJID, _SrcJID, outgoing, _Packet) ->
    %% Will be archived by remote jid.
    ok.

%%%===================================================================
%%% mam_lookup_messages callback
%%%===================================================================

-spec lookup_messages_hook(
        Result         :: term(),
        Host           :: ejabberd:server(),
        UserID         :: mod_mam:archive_id(),
        UserJID        :: ejabberd:jid(),
        RSM            :: jlib:rsm_in() | undefined,
        Borders        :: mod_mam:borders() | undefined,
        Start          :: mod_mam:unix_timestamp() | undefined,
        End            :: mod_mam:unix_timestamp() | undefined,
        Now            :: mod_mam:unix_timestamp(),
        WithJID        :: ejabberd:jid() | undefined,
        PageSize       :: non_neg_integer(),
        LimitPassed    :: boolean(),
        MaxResultLimit :: non_neg_integer(),
        IsSimple       :: boolean()
       ) ->
    {ok, {TotalCount  :: non_neg_integer() | undefined,
          Offset      :: non_neg_integer() | undefined,
          MessageRows :: [result_row()]}}
    | {error, missing_with_jid}.

%% No second JID - not implemented nor expected to be:
lookup_messages_hook(_, _, _, _, _, _, _, _, _, undefined, _, _, _, _) ->
    {error, missing_with_jid};

%% No RSM data, no borders; time only - generate some RSM data and use the
%% function below:
lookup_messages_hook(Result, Host, UserID, UserJID,
                undefined, undefined,
                Start, End, Now, WithJID,
                PageSize, LimitPassed, MaxResultLimit, Simple) ->
    lookup_messages_hook(Result, Host, UserID, UserJID,
                    #rsm_in{max = PageSize}, undefined, Start, End, Now,
                    WithJID, PageSize, LimitPassed, MaxResultLimit, Simple);

lookup_messages_hook(_Result, Host, _UserID, UserJID,
                #rsm_in{id = undefined, index = undefined,
                        max = RSMMax, direction = Direction},
                undefined, Start, End, _Now, WithJID,
                RSMMax, _LimitPassed, _MaxResultLimit, Simple) ->
    TaggedStart = {time, Start},
    TaggedEnd = {time, End},
    Rows = do_lookup(Host, UserJID, WithJID, TaggedStart, TaggedEnd,
                     RSMMax, Direction),
    Counts = standard_counts(Simple, RSMMax, Host, UserJID, WithJID,
                             TaggedStart, TaggedEnd, undefined, Rows),
    return_result(Counts, Rows);

%% No RSM data, borders present. Generate RSM based off the pagesize and use
%% the function below:
lookup_messages_hook(Result, Host, UserID, UserJID,
                undefined, Borders,
                undefined, undefined, Now, WithJID,
                PageSize, LimitPassed, MaxResultLimit, Simple) ->
    lookup_messages_hook(Result, Host, UserID, UserJID,
                #rsm_in{max = PageSize}, Borders, undefined, undefined,
                Now, WithJID, PageSize, LimitPassed, MaxResultLimit, Simple);

%% RSM direction/limit data and borders present.
lookup_messages_hook(_Result, Host, _UserID, UserJID,
                #rsm_in{
                   max = RSMMax,
                   direction = Direction,
                   index = undefined,
                   id = undefined
                  },
                Borders =
                #mam_borders{after_id = AfterID,
                             before_id = BeforeID,
                             from_id = FromID,
                             to_id = ToID
                            },
                undefined, undefined, _Now, WithJID,
                RSMMax, _LimitPassed, _MaxResultLimit, Simple) ->
    TaggedStart = get_time_from_id(Host, UserJID, WithJID, AfterID, FromID),
    TaggedEnd = get_time_from_id(Host, UserJID, WithJID, BeforeID, ToID),
    Rows = do_lookup(Host, UserJID, WithJID, TaggedStart, TaggedEnd,
                     RSMMax, Direction),
    Counts = standard_counts(Simple, RSMMax, Host, UserJID, WithJID,
                             TaggedStart, TaggedEnd, Borders, Rows),
    return_result(Counts, Rows);

%% RSM data present with index only (out-of-order retrieval):
lookup_messages_hook(_Result, Host, _UserID, UserJID,
                #rsm_in{id = undefined, index = Index,
                        max = RSMMax, direction = Direction},
                undefined, undefined, undefined, _Now, WithJID,
                RSMMax, _LimitPassed, _MaxResultLimit, Simple) ->
    {Q, V} = find_nth_query_val(UserJID, WithJID, Index, RSMMax, Direction),
    Rows = run_paging_query(Host, Q, V),
    SplitPoint = min(length(Rows), Index),
    {_, RequestedRows} = lists:split(SplitPoint, Rows),
    Counts = index_only_counts(Simple, RSMMax, Host, UserJID, WithJID,
                               SplitPoint),
    return_result(Counts, RequestedRows);

%% RSM data present with ID - find the timestamp for that ID and do a timestamp
%% based lookup:
lookup_messages_hook(_Result, Host, _UserID, UserJID,
                #rsm_in{direction = Direction, id = ID,
                        index = undefined, max = RSMMax},
                undefined, undefined, undefined, _Now, WithJID,
                RSMMax, _LimitPassed, _MaxResultLimit, Simple) ->
    StartPoint = get_time_from_id(Host, UserJID, WithJID, ID, undefined),
    TaggedStart = make_start(Direction, StartPoint),
    TaggedEnd = make_end(Direction, StartPoint),
    Rows = do_lookup(Host, UserJID, WithJID, TaggedStart, TaggedEnd,
                     RSMMax, Direction),
    Counts = standard_counts(Simple, RSMMax, Host, UserJID, WithJID,
                             undefined, undefined, undefined, Rows),
    return_result(Counts, Rows);

lookup_messages_hook(_, _, _, _, _, _, _, _, _, _, _, _, _, _) ->
    error(unhandled_lookup_parameters).

%%%===================================================================
%%% Count functions
%%%===================================================================

need_count(_, 0) -> true;
need_count(true, _) -> false;
need_count(false, _) -> true;
need_count(opt_count, _) -> true.

total_count(Host, JID1, JID2, FirstTime, LastTime) ->
    InitialQuery = "SELECT COUNT(*) FROM message_archive WHERE ",
    {Q, V} =
    fun_chain:last(
      {InitialQuery, #{}},
      add_jids({JID1, JID2}),
      add_times({FirstTime, LastTime})
    ),
    {ok, Result} = wocky_db:query(Host, Q, V, quorum),
    wocky_db:single_result(Result).

offset_count(_, _, _, _, []) -> undefined;
offset_count(Host, JID1, JID2, undefined, Rows) ->
    offset_count(Host, JID1, JID2, #mam_borders{}, Rows);
offset_count(Host, JID1, JID2,
             Borders = #mam_borders{before_id = BeforeID}, Rows) ->
    IndexID = index_id(Rows),
    NewBorders = Borders#mam_borders{before_id = min(IndexID, BeforeID),
                                     to_id = undefined},
    offset_count(Host, JID1, JID2, NewBorders).

offset_count(Host, JID1, JID2, Borders) ->
    InitialQuery = "SELECT COUNT(*) FROM archive_id WHERE ",
    {Q, V} =
    fun_chain:last(
      {InitialQuery, #{}},
      add_jids({JID1, JID2}),
      add_borders(Borders)
    ),
    {ok, Result} = wocky_db:query(Host, Q, V, quorum),
    wocky_db:single_result(Result).

index_only_counts(CountType, RSMMax, Host, JID1, JID2, Index) ->
    NeedCount = need_count(CountType, RSMMax),
    index_only_counts(NeedCount, Host, JID1, JID2, Index).

index_only_counts(false, _, _, _, _) -> {undefined, undefined};
index_only_counts(true, Host, JID1, JID2, Index) ->
    Total = wocky_db:count(Host, message_archive, jid_key(JID1, JID2)),
    {Total, Index}.

standard_counts(CountType, RSMMax, Host, JID1, JID2, TaggedStart, TaggedEnd,
                Borders, Rows) ->
    NeedCount = need_count(CountType, RSMMax),
    standard_counts(NeedCount, Host, JID1, JID2, TaggedStart, TaggedEnd,
                    Borders, Rows).

-spec standard_counts(
        NeedCount   :: boolean(),
        Host        :: binary(),
        JID1        :: ejabberd:jid(),
        JID2        :: ejabberd:jid(),
        TaggedStart :: undefined | mam_time(),
        TaggedEnd   :: undefined | mam_time(),
        Borders     :: undefined | mod_mam:borders(),
        Rows        :: [#{}]
       ) -> {undefined | non_neg_integer(), undefined | non_neg_integer()}.
standard_counts(false, _, _, _, _, _, _, _) -> {undefined, undefined};
standard_counts(true, Host, JID1, JID2, TaggedStart,
                TaggedEnd, Borders, Rows) ->
    Total = total_count(Host, JID1, JID2, TaggedStart, TaggedEnd),
    OffsetCount = offset_count(Host, JID1, JID2, Borders, Rows),
    {Total, OffsetCount}.

%%%===================================================================
%%% Helper functions
%%%===================================================================

-spec do_lookup(
        Host  :: binary(),
        JID1  :: ejabberd:jid(),
        JID2  :: ejabberd:jid(),
        Start :: mam_time(),
        End   :: mam_time(),
        Max   :: undefined | non_neg_integer(),
        Direction :: undefined | before | aft) ->
    [#{}].

do_lookup(_Host, _JID1, _JID2, _Start, _End, 0, _Direction) ->
    [];

do_lookup(Host, JID1, JID2, Start, End, Max, Direction) ->
    InitialQuery = "SELECT * FROM message_archive WHERE ",
    {Q, V} =
    fun_chain:last(
      {InitialQuery, #{}},
      add_jids({JID1, JID2}),
      add_times({Start, End}),
      add_ordering(Direction),
      add_limit(Max)
     ),
    run_paging_query(Host, Q, V).

return_result({Total, OffsetCount}, Rows) ->
    {ok, {Total, OffsetCount, lists:sort([row_to_msg(R) || R <- Rows])}}.

make_start(before, _) -> undefined;
make_start(aft, Time) -> Time.

make_end(before, Time) -> Time;
make_end(aft, _) -> undefined.

get_time_from_id(_Host, _, _, undefined, undefined) -> undefined;
get_time_from_id(Host, JID1, JID2, Exclusive, undefined) ->
    {uuid, exclusive, get_time_from_id(Host, JID1, JID2, Exclusive)};
get_time_from_id(Host, JID1, JID2, undefined, Inclusive) ->
    {uuid, inclusive, get_time_from_id(Host, JID1, JID2, Inclusive)}.

get_time_from_id(Host, JID1, JID2, ID) ->
    PartKey = jid_key(JID1, JID2),
    wocky_db:select_one(Host, archive_id, time, PartKey#{id => ID}).

find_nth_query_val(JID1, JID2, Index, Max, Direction) ->
    InitialQuery = "SELECT * FROM message_archive WHERE ",
    fun_chain:last(
      {InitialQuery, #{}},
      add_jids({JID1, JID2}),
      add_limit(maybe_add(Index, Max)),
      add_ordering(Direction)
    ).

%%%===================================================================
%%% Query element constructors
%%%===================================================================

add_jids({UserJID, WithJID}, {Q, V}) ->
    {[Q, " lower_jid = ? AND upper_jid = ?"],
     maps:merge(V, jid_key(UserJID, WithJID))}.

add_borders(#mam_borders{after_id = AfterID, before_id = BeforeID,
                         from_id = FromID, to_id = ToID}, {Q, V}) ->
    lists:foldl(fun add_border/2,
                {Q, V},
                [{AfterID,  ">"},
                 {BeforeID, "<"},
                 {FromID,   ">="},
                 {ToID,     "<="}]).

add_border({undefined, _Op}, {Q, V}) -> {Q, V};
add_border({Border, Op}, {Q, V}) ->
    {BindStr, BindAtom} = make_binding("border", Op),
    {[Q, " AND id ", Op, " ", BindStr], V#{BindAtom => Border}}.

add_times({Start, End}, {Q, V}) ->
    lists:foldl(fun add_time/2,
                {Q, V},
                [{Start, ">"},
                 {End,   "<"}]).

add_time({undefined, _}, {Q, V}) -> {Q, V};
add_time({{_, undefined}, _}, {Q, V}) -> {Q, V};
add_time({{time, Time}, Op}, {Q, V}) ->
    {BindStr, BindAtom} = make_binding("time", Op),
    {UUIDFun, CompareTS} = uuid_fun(Op, mam_to_wocky_ts(Time)),
    {[Q, " AND time ", Op, " ", UUIDFun, "(", BindStr, ")"],
     V#{BindAtom => CompareTS}};
add_time({{uuid, Type, Time}, Op}, {Q, V}) ->
    {BindStr, BindAtom} = make_binding("time_uuid", Op),
    AllowMatch = maybe_inclusive(Type),
    {[Q, " AND time ", Op, AllowMatch, " ", BindStr],
     V#{BindAtom => Time}}.

add_ordering(before, {Q, V}) -> {[Q, " ORDER BY time DESC"], V};
add_ordering(_, {Q, V}) -> {Q, V}.

add_limit(undefined, {Q, V}) -> {Q, V};
add_limit(Limit, {Q, V}) ->
    {[Q, " LIMIT ?"], V#{'[limit]' => Limit}}.

maybe_add_ttl(Row, infinity) -> Row;
maybe_add_ttl(Row, TTL) -> Row#{'[ttl]' => TTL}.

%%%===================================================================
%%% Other utility functions
%%%===================================================================

maybe_inclusive(inclusive) -> "=";
maybe_inclusive(exclusive) -> "".

% mod_mam uses microsecd timestamps; wocky_db uses millisecond
mam_to_wocky_ts(TimeUS) ->
    TimeUS div 1000.

uuid_fun(">", Time) ->
    {"maxTimeuuid", Time-1};
uuid_fun("<", Time) ->
    {"minTimeuuid", Time+1}.

jid_key(JID1 = #jid{}, JID2 = #jid{}) ->
    jid_key(archive_jid(JID1), archive_jid(JID2));
jid_key(JID1, JID2) ->
    [Lower, Higher] = lists:sort([JID1, JID2]),
    #{lower_jid => Lower,
      upper_jid => Higher}.

archive_jid(JID) -> jid:to_binary(jid:to_bare(JID)).

sent_to_lower(Receiver, Sender) ->
    archive_jid(Receiver) < archive_jid(Sender).

index_id(Rows) ->
    #{id := FirstID} = hd(Rows),
    #{id := LastID} = lists:last(Rows),
    min(FirstID, LastID).

row_to_msg(#{id := ID, sent_to_lower := true,
             upper_jid := SrcJID, message := Packet}) ->
    format_msg(ID, SrcJID, Packet);
row_to_msg(#{id := ID, sent_to_lower := false,
             lower_jid := SrcJID, message := Packet}) ->
    format_msg(ID, SrcJID, Packet).

format_msg(ID, SrcJID, Packet) ->
    {ok, XML} = exml:parse(Packet),
    {ID, jid:from_binary(SrcJID), XML}.

make_binding(Prefix, ">") -> make_binding(Prefix, "gt");
make_binding(Prefix, "<") -> make_binding(Prefix, "lt");
make_binding(Prefix, ">=") -> make_binding(Prefix, "gte");
make_binding(Prefix, "<=") -> make_binding(Prefix, "lte");
make_binding(Prefix, Suffix) ->
    Str = Prefix ++ "_" ++ Suffix,
    {[$: | Str], list_to_atom(Str)}.

maybe_add(undefined, _) -> undefined;
maybe_add(_, undefined) -> undefined;
maybe_add(A, B) -> A + B.

run_paging_query(Host, Query, Values) ->
    Result = wocky_db:query(Host, Query, Values, quorum),
    continue_paging_query(Result, []).

continue_paging_query(no_more_result, Acc) -> Acc;
continue_paging_query({ok, Result}, Acc) ->
    Rows = wocky_db:rows(Result),
    NextResult = wocky_db:fetch_more(Result),
    continue_paging_query(NextResult, Acc ++ Rows).


-ifdef(TEST).
archive_test_message(Host, MessID, LocJID, RemJID, Dir, Packet, Timestamp) ->
    Q = "INSERT INTO message_archive (id, lower_jid, upper_jid, time,
         sent_to_lower, message) VALUES (?, ?, ?, minTimeuuid(:time), ?, ?)",
    PartKey = jid_key(LocJID, RemJID),
    SentToLower = sent_to_lower(LocJID, RemJID) xor (Dir =:= outgoing),
    V = PartKey#{id => MessID, message => exml:to_binary(Packet),
                 time => Timestamp, sent_to_lower => SentToLower},
    {ok, void} = wocky_db:query(Host, Q, V, quorum),
    ok.
-endif.

