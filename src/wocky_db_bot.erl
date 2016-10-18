-module(wocky_db_bot).

-compile({parse_transform, cut}).

-export([get/2,
         owned_bots/2,
         followed_bots/2,
         get_id_by_name/2,
         exists/2,
         insert/2,
         insert_new_name/2,
         owner/2,
         affiliations/2,
         affiliations_from_map/1,
         update_affiliations/3,
         subscribers/2,
         follow_state/3,
         followers/2,
         delete/2,
         has_access/3,
         subscribe/4,
         unsubscribe/3,
         publish_item/5,
         get_item/3,
         get_items/2,
         delete_item/3,
         dissociate_user/2,
         image_items_count/2
        ]).

% We're going to need these sooner or later, but for now stop xref complaining
-ignore_xref([followers/2, get_id_by_name/2]).

-include("wocky.hrl").
-include("wocky_bot.hrl").
-include("wocky_roster.hrl").
-include_lib("ejabberd/include/jlib.hrl").

-type shortname()           :: binary().
-type affiliation_type()    :: none | spectator | owner.
-type affiliate()           :: jid().
-type affiliation()         :: {affiliate(), affiliation_type()}.

%%%===================================================================
%%% API
%%%===================================================================

-spec get(wocky_db:server(), wocky_db:id()) -> map() | not_found.
get(_Server, ID) ->
    wocky_db:select_row(shared, bot, all, #{id => ID}).

-spec owned_bots(wocky_db:server(), binary()) -> [binary()].
owned_bots(_Server, UserJID) ->
    wocky_db:select_column(shared, user_bot, id, #{owner => UserJID}).

-spec followed_bots(wocky_db:server(), binary()) -> [binary()].
followed_bots(Server, UserJID) ->
    Result = wocky_db:select(Server, subscribed_bot,
                             [bot, follow], #{user => UserJID}),
    [Bot || #{bot := Bot, follow := true} <- Result].

-spec get_id_by_name(wocky_db:server(), shortname()) ->
    wocky_db:id() | not_found.
get_id_by_name(Server, Name) ->
    wocky_db:select_one(Server, bot_name, id, #{shortname => Name}).

-spec exists(wocky_db:server(), wocky_db:id()) -> boolean().
exists(_Server, ID) ->
    case wocky_db:select_one(shared, bot, id, #{id => ID}) of
        not_found -> false;
        _ -> true
    end.

-spec insert(wocky_db:server(), map()) -> ok.
insert(_Server, Fields) ->
    wocky_db:insert(shared, bot, Fields).

-spec insert_new_name(wocky_db:id(), shortname()) -> ok | {error, exists}.
insert_new_name(ID, Name) ->
    Vals = #{shortname => Name, id => ID},
    case wocky_db:insert_new(wocky_app:server(), bot_name, Vals) of
        true -> ok;
        false -> {error, exists}
    end.

-spec owner(wocky_db:server(), wocky_db:id()) -> jid() | not_found.
owner(_Server, ID) ->
    maybe_to_jid(wocky_db:select_one(shared, bot, owner, #{id => ID})).

-spec affiliations(wocky_db:server(), wocky_db:id()) ->
    [affiliation()].
affiliations(_Server, ID) ->
    Map = wocky_db:select_row(shared, bot, [affiliates, owner], #{id => ID}),
    affiliations_from_map(Map).

-spec affiliations_from_map(map() | not_found) -> [affiliation()] | not_found.
affiliations_from_map(not_found) -> not_found;
affiliations_from_map(Map = #{affiliates := null}) ->
    affiliations_from_map(Map#{affiliates => []});
affiliations_from_map(#{owner := Owner, affiliates := Affiliations}) ->
    owner_affiliation(Owner) ++
     [{jid:from_binary(A), spectator} || A <- Affiliations].

owner_affiliation(<<>>) -> [];
owner_affiliation(Owner) ->
    [{jid:from_binary(Owner), owner}].

-spec update_affiliations(wocky_db:server(), wocky_db:id(), [affiliation()]) ->
    ok.
update_affiliations(_Server, ID, Affiliations) ->
    {Add, Remove} = lists:partition(fun({_, Type}) -> Type =:= spectator end,
                                    Affiliations),
    AddQ = "UPDATE bot SET affiliates = affiliates + ? "
           "WHERE id = ? IF EXISTS",
    AddV = #{affiliates => user_parts(Add), id => ID},
    RemoveQ = "UPDATE bot SET affiliates = affiliates - ? "
              "WHERE id = ? IF EXISTS",
    RemoveV = #{affiliates => user_parts(Remove), id => ID},

    Add =/= [] andalso
        ({ok, _} = wocky_db:query(shared, AddQ, AddV, quorum)),
    Remove =/= [] andalso
        ({ok, _} = wocky_db:query(shared, RemoveQ, RemoveV, quorum)),
    ok.

-spec followers(wocky_db:server(), wocky_db:id()) -> [jid()].
followers(Server, ID) ->
    [J || {J, F} <- subscribers(Server, ID), F =:= true].

-spec subscribers(wocky_db:server(), wocky_db:id()) -> [{jid(), boolean()}].
subscribers(Server, ID) ->
    Result = wocky_db:select(Server, bot_subscriber,
                             [user, follow], #{bot => ID}),
    Subscribers = [{jid:from_binary(J), F} ||
                   #{user := J, follow := F} <- Result],
    maybe_add_owner_as_follower(owner(Server, ID), Subscribers).

-spec follow_state(wocky_db:server(), wocky_db:id(), jid()) ->
    boolean() | not_found.
follow_state(Server, ID, User) ->
    UserBin = jid:to_binary(jid:to_bare(User)),
    wocky_db:select_one(Server, bot_subscriber, follow,
                        #{bot => ID, user => UserBin}).

-spec delete(wocky_db:server(), wocky_db:id()) -> ok.
delete(Server, ID) ->
    ShortName = wocky_db:select_one(shared, bot, shortname, #{id => ID}),
    ok = delete_bot_name_lookup(Server, ShortName),
    ok = wocky_db:delete(shared, bot, all, #{id => ID}).

delete_bot_name_lookup(Server, Name)
  when is_binary(Name) andalso size(Name) > 0 ->
    wocky_db:delete(Server, bot_name, all, #{shortname => Name});
delete_bot_name_lookup(_, _) ->
    ok.

-spec has_access(wocky_db:server(), wocky_db:id(), jid()) ->
    boolean() | not_found.
has_access(_Server, ID, User) ->
    BareUserBin = jid:to_binary(jid:to_bare(User)),
    Bot =
    wocky_db:select_row(shared, bot,
                        [visibility, affiliates, owner],
                        #{id => ID}),
    has_access(BareUserBin, Bot).

-spec subscribe(wocky_db:server(), wocky_db:id(), jid(), boolean()) -> ok.
subscribe(Server, ID, User, Follow) ->
    case owner(Server, ID) of
        User ->
            ok;
        _ ->
            ok = wocky_db:insert(
                   Server, bot_subscriber,
                   #{bot => ID,
                     user => jid:to_binary(jid:to_bare(User)),
                     follow => Follow})
    end.

-spec unsubscribe(wocky_db:server(), wocky_db:id(), jid()) -> ok.
unsubscribe(Server, ID, User) ->
    case owner(Server, ID) of
        User ->
            ok;
        _ ->
            ok = wocky_db:delete(Server, bot_subscriber, all,
                                 #{bot => ID,
                                   user => jid:to_binary(jid:to_bare(User))})
    end.

-spec publish_item(wocky_db:server(), wocky_db:id(), binary(),
                   binary(), boolean()) -> ok.
publish_item(Server, BotID, NoteID, Stanza, Image) ->
    Existing = wocky_db:select_one(Server, bot_item, id,
                                   #{id => NoteID, bot => BotID}),
    MaybePublished = case Existing of
                         not_found -> #{published => now};
                         _ -> #{}
                     end,
    Note = MaybePublished#{id => NoteID,
                           bot => BotID,
                           updated => now,
                           stanza => Stanza,
                           image => Image
                          },
    wocky_db:insert(Server, bot_item, Note).

get_item(Server, BotID, NoteID) ->
    wocky_db:select_row(Server, bot_item, all, #{id => NoteID, bot => BotID}).

get_items(Server, BotID) ->
    wocky_db:select(Server, bot_item, all, #{bot => BotID}).

-spec delete_item(wocky_db:server(), wocky_db:id(), binary()) -> ok.
delete_item(Server, BotID, NoteID) ->
    wocky_db:delete(Server, bot_item, all, #{id => NoteID, bot => BotID}).

-spec dissociate_user(ejabberd:luser(), wocky_db:server()) -> ok.
dissociate_user(LUser, LServer) ->
    OwnedBots = owned_bots(LServer,
                           jid:to_binary(jid:make(LUser, LServer, <<>>))),
    Roster = wocky_db_roster:get_roster(LUser, LServer),
    Friends = lists:filter(wocky_db_roster:is_friend(_), Roster),
    FriendJIDs = [jid:make(J) || #wocky_roster{contact_jid = J} <- Friends],
    lists:foreach(remove_owner(LServer, _, FriendJIDs), OwnedBots).

-spec image_items_count(wocky_db:server(), wocky_db:id()) -> non_neg_integer().
image_items_count(Server, BotID) ->
    wocky_db:count(Server, bot_item_images, #{bot => BotID, image => true}).

%%%===================================================================
%%% Private helpers
%%%===================================================================

user_parts(Affiliates) ->
    [jid:to_binary(User) || {User, _Role} <- Affiliates].

has_access(_, not_found) ->
    not_found;
has_access(User, #{owner := User}) ->
    true;
has_access(User, #{visibility := ?WOCKY_BOT_VIS_WHITELIST,
                   affiliates := Affiliates}) ->
    lists:member(User, wocky_util:null_to_list(Affiliates));
has_access(User, #{visibility := ?WOCKY_BOT_VIS_FRIENDS,
                   owner:= Owner}) ->
    wocky_db_roster:is_friend(jid:from_binary(Owner),
                              jid:from_binary(User));
has_access(_User, #{visibility := ?WOCKY_BOT_VIS_PUBLIC}) ->
    true;
has_access(_, _) ->
    false.

maybe_to_jid(not_found) ->
    not_found;
maybe_to_jid(null) ->
    [];
maybe_to_jid(<<>>) ->
    not_found;
maybe_to_jid(JIDBin) ->
    jid:from_binary(JIDBin).

remove_owner(Server, BotID, FriendJIDs) ->
    Bot = get(Server, BotID),
    NewBot = maybe_freeze_roster(Bot, FriendJIDs),
    wocky_db:insert(shared, bot, NewBot#{owner => <<>>}).

maybe_freeze_roster(Bot = #{visibility := ?WOCKY_BOT_VIS_FRIENDS},
                    FriendJIDs) ->
    Bot#{visibility => ?WOCKY_BOT_VIS_WHITELIST,
         affiliates => [jid:to_binary(J) || J <- FriendJIDs]};
maybe_freeze_roster(Bot, _) -> Bot.

maybe_add_owner_as_follower(not_found, Subs) -> Subs;
maybe_add_owner_as_follower(Owner, Subs) -> [{Owner, true} | Subs].
