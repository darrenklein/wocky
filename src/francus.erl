%%% @copyright 2016+ Hippware, Inc.
%%% @doc Francus provides a basic file-like store backed by Cassandra. It's
%%% primary job is breaking up blobs into C*-sized chunks and tracking those and
%%% other metadata, then reassabling them for reading.
%%%
-module(francus).

-export([
         open_write/5,
         open_read/2,
         read/1,
         read/2,
         write/2,
         close/1,
         keep/2,
         delete/2,
         owner/1,
         access/1,
         metadata/1,
         size/1
        ]).

-ignore_xref([read/2, size/1]).

-ifdef(TEST).
-export([open_write/6,
         default_chunk_size/0]).
-endif.

-export_type([
              francus_file/0,
              metadata/0
             ]).

-type file_id() :: binary().
-type user_id() :: binary().
-type content() :: binary().
-type access()  :: binary().
-type metadata() :: #{binary() => binary()}.

-record(state, {
          file_id            :: file_id(),
          user_id            :: user_id(),
          access             :: access(),
          metadata           :: metadata(),
          context            :: wocky_db:context(),
          ttl = infinity     :: wocky_db:ttl(),
          pending = <<>>     :: content(),
          size = 0           :: non_neg_integer(),
          committed_size = 0 :: non_neg_integer(),
          chunks = []        :: [content()]
         }).

-opaque francus_file() :: #state{}.

-define(DEFAULT_CHUNK_SIZE, 1024 * 1024).

-define(DEFAULT_TTL, 60 * 60 * 24 * 28 * 6). % 6 months
-define(DATA_GRACE_SECONDS, 300).

%%%===================================================================
%%% API
%%%===================================================================

%% @equiv open_write(Context, FileID, UserID, Metadata, infinity)
%%
%% @see open_write/7
-spec open_write(wocky_db:context(), file_id(), user_id(),
                 access(), metadata()) ->
    {ok, francus_file()}.
open_write(Context, FileID, UserID, Access, Metadata) ->
    TTL = application:get_env(wocky, francus_file_ttl, ?DEFAULT_TTL),
    open_write(Context, FileID, UserID, Access, Metadata, TTL).

%% @doc Open a file for writing
%%
%% `Context' is the C* context in which to store the file
%%
%% `FileID' is the unique ID of the file to write. This must be generated with
%% {@link mod_wocky_tros:make_file_id/0}
%%
%% `UserID' is the ID owner of the file. Generated by {@link
%% wocky_db:create_id/0}
%%
%% `Metadata' is a map containing additional metadata
%% in HTTP.
%%
%% `TTL' is the time the file will persist for before being cleaned up. May
%% be `infinity'.
-spec open_write(wocky_db:context(), file_id(), user_id(),
                 access(), metadata(), wocky_db:ttl()) ->
    {ok, francus_file()}.
open_write(Context, FileID, UserID, Access, Metadata, TTL) ->
    Values = #{id => FileID,
               user => UserID,
               size => 0,
               access => Access,
               metadata => Metadata,
               '[ttl]' => TTL},
    ok = wocky_db:insert(Context, media, Values),
    {ok, #state{file_id = FileID,
                user_id = UserID,
                access = Access,
                metadata = Metadata,
                context = Context,
                ttl = TTL
               }}.


%% @doc Write bianry data to a file opened with {@link open_write/4}
%%
%% `File' is the file object being written to
%%
%% `Data' is the data to write
%%
%% Note that each call to this function returns an updated file object which
%% must be used for the next call (or on the call to {@link close/1}).
-spec write(File :: francus_file(),
            Data :: content()) -> francus_file().
write(S = #state{pending = Pending, size = Size}, Data) ->
    NewData = <<Pending/binary, Data/binary>>,
    NewSize = Size + byte_size(Data),
    maybe_commit(S#state{size = NewSize}, NewData).


%% @doc Open a file for reading
%%
%% `Context' is the C* context from which to read the file
%%
%% `FileID' is the ID of the file, as generated by {@link
%% mod_wocky_tros:make_file_id/0} and used in {@link open_write}.
-spec open_read(wocky_db:context(), file_id()) ->
    {ok, francus_file()} | {error, not_found}.
open_read(Context, FileID) ->
    case read_keep_file(Context, FileID) of
        not_found -> {error, not_found};
        Row -> {ok, open_result(Context, FileID, Row)}
    end.


%% @doc Read all data from a file
%%
%% @equiv read(File, infinity)
-spec read(francus_file()) -> eof | {francus_file(), content()}.
read(State) -> read(State, infinity).

%% @doc Read data from a file
%%
%% `File' is the file object being read
%%
%% `Size' is the maximum number of bytes to read. This may be `infinity' to
%% place no limit on reading.
%%
%% The function returns either `eof' if no more data is available to read, or
%% `{File, Data}' where `File' is the updated file object to use for subsequent
%% reads.
-spec read(File:: francus_file(),
           Size :: pos_integer() | infinity) ->
    eof | {francus_file(), content()}.
% End of file reached:
read(#state{chunks = [], pending = <<>>}, _) -> eof;

% Read everything from DB, but still have some to return:
read(S = #state{chunks = [], pending = Pending}, Size)
  when Size =:= infinity orelse byte_size(Pending) =< Size ->
    {S#state{pending = <<>>}, Pending};

% Data still in DB, but enough already read to return requested amount:
read(S = #state{pending = Pending}, Size)
  when is_integer(Size) andalso byte_size(Pending) > Size ->
    <<ToReturn:Size/binary, Remaining/binary>> = Pending,
    {S#state{pending = Remaining}, ToReturn};

% Data still in DB and not enough already read. Do a DB read to get more data
% and then try again:
read(S, Size) ->
    S1 = read_chunk(S),
    read(S1, Size).


%% @doc Delete a file
%%
%% `Context' is the C* context in which the file exists
%%
%% `FileID' is the ID of the file to be deleted
-spec delete(wocky_db:context(), file_id()) -> ok.
delete(Context, FileID) ->
    case open_read(Context, FileID) of
        {error, not_found} ->
            ok;
        {ok, File} ->
            delete_file(File)
    end.


%%%===================================================================
%%% Helper functions
%%%===================================================================


maybe_commit(State, Data) ->
    ChunkSize = chunk_size(),
    case byte_size(Data) of
        X when X < ChunkSize -> State#state{pending = Data};
        _ -> commit(State, Data)
    end.

commit(S = #state{file_id = FileID, committed_size = CS,
                  context = Context, ttl = TTL},
       Data) ->
    ChunkSize = chunk_size(),
    <<ToWrite:ChunkSize/binary, Remaining/binary>> = Data,
    NewCommittedSize = CS + byte_size(ToWrite),
    commit_chunk(FileID, Context, TTL, NewCommittedSize, ToWrite),
    maybe_commit(S#state{committed_size = NewCommittedSize}, Remaining).

commit_chunk(FileID, Context, TTL, NewCommittedSize, Data) ->
    %% This would ideally be a batch query. However apparently C* doesn't
    %% particularly like batches where the total data size is > 50kb. This is
    %% configurable (batch_size_fail_threshold_in_kb) but the comments
    %% specifically advise against it, waving their hands about "node
    %% instability". Which sounds bad.
    ChunkID = ossp_uuid:make(v1, text),
    Q = ["UPDATE media ", maybe_ttl(TTL), " SET chunks = chunks + ?, size = ? "
          "WHERE id = ?"],
    V1 = #{id => FileID,
           chunks => [ChunkID],
           size => NewCommittedSize,
           '[ttl]' => TTL
          },
    {ok, _} = wocky_db:query(Context, Q, V1, quorum),

    V2 = #{chunk_id => ChunkID,
           file_id => FileID,
           data => Data,
           '[ttl]' => add_grace(TTL)
          },
    ok = wocky_db:insert(Context, media_data, V2),
    ok.

-spec close(francus_file()) -> ok.
close(#state{pending = <<>>}) -> ok;
close(#state{file_id = FileID, committed_size = CS,
             context = Context, pending = Pending,
             ttl = TTL}) ->
    commit_chunk(FileID, Context, TTL, CS + byte_size(Pending), Pending),
    ok.

read_keep_file(Context, FileID) ->
    Columns = [id, user, size, access, metadata, chunks, 'ttl(user)'],
    Row = wocky_db:select_row(Context, media, Columns, #{id => FileID}),
    case Row of
        not_found ->
            not_found;
        #{'ttl(user)' := null} ->
            %% TTL is already cleared - nothing to do
            Row;
        #{chunks := Chunks} ->
            ok = wocky_db:insert(Context, media, maps:remove('ttl(user)', Row)),
            keep_chunks(Context, Chunks),
            Row
    end.


-spec keep(wocky_db:context(), file_id()) -> ok | {error, not_found}.
keep(Context, FileID) ->
    case read_keep_file(Context, FileID) of
        not_found -> {error, not_found};
        _ -> ok
    end.

keep_chunks(_Context, null) ->
    ok;
keep_chunks(Context, Chunks) ->
    lists:foreach(fun(C) -> keep_chunk(Context, C) end, Chunks).

keep_chunk(Context, ChunkID) ->
    Row = wocky_db:select_row(Context, media_data, all,
                              #{chunk_id => ChunkID}),
    ok = wocky_db:insert(Context, media_data, Row).

open_result(Context, FileID,
            Row = #{user := UserID, size := Size,
                    access := Access,
                    metadata := Metadata}) ->
    maybe_add_chunks(#state{file_id = FileID,
                            user_id = UserID,
                            context = Context,
                            size = Size,
                            access = Access,
                            metadata = Metadata}, Row).

maybe_add_chunks(State, #{chunks := null}) -> State;
maybe_add_chunks(State, #{chunks := Chunks}) -> State#state{chunks = Chunks}.

read_chunk(S = #state{context = Context, chunks = [Chunk | Rest],
                      pending = Pending}) ->
    NewData = wocky_db:select_one(Context, media_data, data,
                                  #{chunk_id => Chunk}),
    S#state{chunks = Rest, pending = <<Pending/binary, NewData/binary>>}.

delete_file(#state{context = Context, file_id = FileID, chunks = Chunks}) ->
    delete_chunks(Context, Chunks),
    delete_metadata(Context, FileID).

delete_chunks(Context, Chunks) ->
    lists:foreach(fun(C) -> delete_chunk(Context, C) end, Chunks).

delete_chunk(Context, Chunk) ->
    wocky_db:delete(Context, media_data, all, #{chunk_id => Chunk}).

delete_metadata(Context, FileID) ->
    wocky_db:delete(Context, media, all, #{id => FileID}).

-spec owner(francus_file()) -> user_id().
owner(#state{user_id = Owner}) -> Owner.

-spec access(francus_file()) -> access().
access(#state{access = Access}) -> Access.

-spec metadata(francus_file()) -> metadata().
metadata(#state{metadata = Metadata}) -> Metadata.

-spec size(francus_file()) -> non_neg_integer().
size(#state{size = Size}) -> Size.

default_chunk_size() -> ?DEFAULT_CHUNK_SIZE.

chunk_size() ->
    case application:get_env(wocky, francus_chunk_size) of
        undefined -> default_chunk_size();
        {ok, X} when is_integer(X) -> X
    end.

%% Allow the data to persist a few minutes longer than the metadata - this
%% should prevent us opening a file whose data is already expired (or trying
%% to keep a partially expired file).
add_grace(infinity) -> infinity;
add_grace(TTL) -> TTL + ?DATA_GRACE_SECONDS.

maybe_ttl(infinity) -> "";
maybe_ttl(_) -> "USING TTL ?".
