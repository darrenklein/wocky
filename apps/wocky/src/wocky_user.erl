%%% @copyright 2015+ Hippware, Inc.
%%% @doc Wocky user model

-module(wocky_user).

%% API
-export([create_user/3,
         does_user_exist/1]).

%% For the #scram{} record
-include_lib("ejabberd/include/ejabberd.hrl").

%%%===================================================================
%%% API
%%%===================================================================

-spec create_user(Domain :: binary(),
                  UserName :: binary(),
                  SCRAM :: #scram{}
                 ) -> ok | {error, exists}.
create_user(Domain, UserName, SCRAM) ->
    Id = create_user_id(Domain),
    case create_username_lookup(Id, Domain, UserName) of
        true ->
            {ok, _} = create_user_record(Id, Domain, UserName, SCRAM),
            ok;

        false ->
            {error, exists}
    end.


-spec does_user_exist(UserName :: binary()) -> boolean().
does_user_exist(UserName) ->
    Query = <<"SELECT username, id, domain FROM username_to_user WHERE username = ?">>,
    {ok, Return} = cassandra:pquery(shared, Query, [UserName], quorum),
    Result = cassandra:rows(Return),
    length(Result) > 0.


%%%===================================================================
%%% Internal functions
%%%===================================================================

create_user_id(Domain) ->
    cassandra:timeuuid(Domain).
    
create_username_lookup(Id, Domain, UserName) ->
    Query = <<"INSERT INTO username_to_user (id, domain, username) VALUES (?, ?, ?) IF NOT EXISTS">>,
    {ok, Return} = cassandra:pquery(shared, Query, [Id, Domain, UserName], quorum),
    %% Note: Result is <<1>> for success, <<0>> if error.
    %% There is no documentation on the return type so it's possible,
    %%   in the future, this may not be a binary.
    cassandra:single_result(Return) /= <<0>>.

create_user_record(Id, Domain, UserName, SCRAM) ->
    Query = <<"INSERT INTO user (id, domain, username, stored_key, server_key, salt, iteration_count) VALUES (?, ?, ?, ?, ?, ?, ?)">>,
    cassandra:pquery(Domain, Query, [Id,
                                     Domain,
                                     UserName,
                                     SCRAM#scram.storedkey,
                                     SCRAM#scram.serverkey,
                                     SCRAM#scram.salt,
                                     SCRAM#scram.iterationcount],
                     quorum).

