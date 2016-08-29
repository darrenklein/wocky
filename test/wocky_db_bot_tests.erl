%%% @copyright 2016+ Hippware, Inc.
%%% @doc Test suite for wocky_db_bot.erl
-module(wocky_db_bot_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("ejabberd/include/jlib.hrl").
-include("wocky_db_seed.hrl").
-include("wocky_bot.hrl").

-import(wocky_db_bot,
        [get/2, get_id_by_name/2, exists/2, insert/2,
         insert_new_name/2, owner/2, affiliations/2,
         affiliations_from_map/1, update_affiliations/3, followers/2,
         subscribers/2, delete/2, has_access/3, subscribe/4, unsubscribe/3,
         owner_roster/2, owner_roster_ver/2, update_owner_roster/4

        ]).

wocky_db_bot_test_() -> {
  "wocky_db_bot",
  setup, fun before_all/0, fun after_all/1,
  [ {inorder, [
      {inparallel, [
        test_get(),
        test_get_id_by_name(),
        test_exists(),
        test_insert(),
        test_insert_new_name(),
        test_owner(),
        test_affiliations(),
        test_affiliations_from_map(),
        test_followers(),
        test_subscribers(),
        test_owner_roster(),
        test_owner_roster_ver()
      ]},

      {inorder, [
        test_has_access(),
        test_update_affiliations(),
        test_subscribe(),
        test_unsubscribe(),
        test_update_owner_roster(),
        test_delete()
      ]}
    ]}
  ]}.

before_all() ->
    ok = wocky_db:prepare_tables(?LOCAL_CONTEXT, [roster,
                                                  bot,
                                                  bot_name,
                                                  bot_subscriber
                                                 ]),
    ok = wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [roster,
                                                    bot,
                                                    bot_name,
                                                    bot_subscriber
                                                   ]).

after_all(_) ->
    ok.

test_get() ->
    { "get", [
      { "returns bot data if it exists", [
        ?_assertEqual(hd(wocky_db_seed:seed_data(bot, ?LOCAL_CONTEXT)),
                      get(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "returns not_found if no bot exists", [
        ?_assertEqual(not_found, get(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.

test_get_id_by_name() ->
    { "get_id_by_name", [
      { "returns bot id if it exists", [
        ?_assertEqual(?BOT, get_id_by_name(?LOCAL_CONTEXT, ?BOT_NAME))
      ]},
      { "returns not_found if no bot exists with the supplied name", [
        ?_assertEqual(not_found, get_id_by_name(?LOCAL_CONTEXT,
                                                <<"other name">>))
      ]}
    ]}.

test_exists() ->
    { "exists", [
      { "returns true if a bot ID exists", [
        ?_assert(exists(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "returns false if a bot does not exist", [
        ?_assertNot(exists(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.

test_insert() ->
    NewBot = #{id := ID} = new_bot(),
    { "insert", [
      { "inserts a new bot with the supplied parameters", inorder, [
        ?_assertEqual(ok, insert(?LOCAL_CONTEXT, NewBot)),
        ?_assertEqual(NewBot, get(?LOCAL_CONTEXT, ID))
      ]}
    ]}.

test_insert_new_name() ->
    ID = wocky_db:create_id(),
    { "insert_new_name", [
      { "inserts a new name if that name is not already taken", inorder, [
        ?_assertEqual(ok, insert_new_name(ID, <<"brandnewname">>)),
        ?_assertEqual(ID, get_id_by_name(?LOCAL_CONTEXT, <<"brandnewname">>))
      ]},
      { "refuses to insert a new name if that name is already taken", inorder, [
        ?_assertEqual({error, exists},
                      insert_new_name(?BOT, ?BOT_NAME)),
        ?_assertEqual(?BOT, get_id_by_name(?LOCAL_CONTEXT, ?BOT_NAME))
      ]}
    ]}.

test_owner() ->
    { "owner", [
      { "gets the owner of the bot", [
        ?_assert(jid:are_bare_equal(?ALICE_JID, owner(?LOCAL_CONTEXT, ?BOT)))
      ]},
      { "returns not_found if the bot doesn't exist", [
        ?_assertEqual(not_found, owner(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.

test_affiliations() ->
    { "affiliations", [
      { "gets the bots affiliation list", [
        ?_assertEqual(expected_affiliations(),
                      affiliations(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "returns not_found for non-existant bot", [
        ?_assertEqual(not_found, affiliations(?LOCAL_CONTEXT,
                                              wocky_db:create_id()))
      ]}
    ]}.

test_affiliations_from_map() ->
    NewBot = #{id := ID} = maps:without([affiliates], new_bot()),
    { "affiliations_from_map", [
      { "generates a normalised affiliate list", [
        ?_assertEqual(expected_affiliations(),
                      affiliations_from_map(
                        hd(wocky_db_seed:seed_data(bot, ?LOCAL_CONTEXT))))
      ]},
      { "returns not_found for input of not_found", [
        ?_assertEqual(not_found, affiliations_from_map(not_found))
      ]},
      { "returns only the owner list for a bot with an unset affiliates field",
       inorder, [
        ?_assertEqual(ok, insert(?LOCAL_CONTEXT, NewBot)),
        ?_assertEqual([{?BOB_JID, owner}],
                      affiliations_from_map(get(?LOCAL_CONTEXT, ID)))
      ]}
    ]}.

test_update_affiliations() ->
    ID = wocky_db:create_id(),
    { "update_affiliations", [
      { "updates the affiliations", inorder, [
        ?_assertEqual(ok, update_affiliations(?LOCAL_CONTEXT, ?BOT,
                                              [{?BOB_JID, none},
                                               {?CAROL_JID, spectator}])),
        ?_assertEqual(expected_affiliations_after_change(),
                      affiliations(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "removing non-affiliate or owner has no effect", inorder, [
        ?_assertEqual(ok, update_affiliations(?LOCAL_CONTEXT, ?BOT,
                                              [{?KAREN_JID, none}])),
        ?_assertEqual(ok, update_affiliations(?LOCAL_CONTEXT, ?BOT,
                                              [{?ALICE_JID, none}])),
        ?_assertEqual(expected_affiliations_after_change(),
                      affiliations(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "changing a non-existant bot does not create it", inorder, [
        ?_assertEqual(ok, update_affiliations(?LOCAL_CONTEXT, ID,
                                              [{?KAREN_JID, none},
                                               {?ALICE_JID, spectator}
                                              ])),
        ?_assertEqual(not_found, get(?LOCAL_CONTEXT, ID))
      ]}
    ]}.

test_followers() ->
    { "followers", [
      { "returns the list of followers", [
        ?_assertEqual([?KAREN_JID], followers(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "returns empty list for non existant bot", [
        ?_assertEqual([], followers(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.

test_subscribers() ->
    { "subscribers", [
      { "returns the list of subscribers and their follower status", [
        ?_assertEqual(lists:sort([{?CAROL_JID, false}, {?KAREN_JID, true}]),
                      lists:sort(subscribers(?LOCAL_CONTEXT, ?BOT)))
      ]},
      { "returns empty list for non existant bot", [
        ?_assertEqual([], followers(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.

test_has_access() ->
    { "has_access", [
      { "returns true for owners only with VIS_OWNER", [
        ?_assertEqual(ok, insert(?LOCAL_CONTEXT, #{id => ?BOT,
                                                   visibility =>
                                                   ?WOCKY_BOT_VIS_OWNER})),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?ALICE_JID)),
        ?_assertNot(has_access(?LOCAL_CONTEXT, ?BOT, ?BOB_JID)),
        ?_assertNot(has_access(?LOCAL_CONTEXT, ?BOT, ?CAROL_JID))
      ]},
      { "returns true for owners and affiliates with VIS_WHITELIST", [
        ?_assertEqual(ok, insert(?LOCAL_CONTEXT, #{id => ?BOT,
                                                   visibility =>
                                                   ?WOCKY_BOT_VIS_WHITELIST})),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?ALICE_JID)),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?BOB_JID)),
        ?_assertNot(has_access(?LOCAL_CONTEXT, ?BOT, ?CAROL_JID)),
        ?_assertNot(has_access(?LOCAL_CONTEXT, ?BOT, ?TIM_JID))
      ]},
      { "returns true for owners and members of the bot's owner_roster set", [
        ?_assertEqual(ok, insert(?LOCAL_CONTEXT, #{id => ?BOT,
                                                   visibility =>
                                                   ?WOCKY_BOT_VIS_FRIENDS})),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?ALICE_JID)),
        ?_assertNot(has_access(?LOCAL_CONTEXT, ?BOT, ?BOB_JID)),
        ?_assertNot(has_access(?LOCAL_CONTEXT, ?BOT, ?CAROL_JID)),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?KAREN_JID))
      ]},
      { "returns true for everyone with VIS_PUBLIC", [
        ?_assertEqual(ok, insert(?LOCAL_CONTEXT, #{id => ?BOT,
                                                   visibility =>
                                                   ?WOCKY_BOT_VIS_PUBLIC})),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?ALICE_JID)),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?BOB_JID)),
        ?_assert(has_access(?LOCAL_CONTEXT, ?BOT, ?TIM_JID))
      ]},
      { "returns not_found for non-existant bot", [
        ?_assertEqual(not_found, has_access(?LOCAL_CONTEXT,
                                            wocky_db:create_id(),
                                            ?BOB_JID))
      ]}
    ]}.


test_subscribe() ->
    { "subscribe", [
      { "adds user to list of subscribers", [
        ?_assertEqual(ok, subscribe(?LOCAL_CONTEXT, ?BOT, ?TIM_JID, false)),
        ?_assertEqual(ok, subscribe(?LOCAL_CONTEXT, ?BOT, ?BOB_JID, true)),
        ?_assertEqual(lists:sort([{?TIM_JID, false}, {?CAROL_JID, false},
                                  {?BOB_JID, true}, {?KAREN_JID, true}]),
                      lists:sort(subscribers(?LOCAL_CONTEXT, ?BOT)))
      ]}
    ]}.

test_unsubscribe() ->
    { "unsubscribe", [
      { "removes user from the list of subscribers", [
        ?_assertEqual(ok, unsubscribe(?LOCAL_CONTEXT, ?BOT, ?TIM_JID)),
        ?_assertEqual(ok, unsubscribe(?LOCAL_CONTEXT, ?BOT, ?BOB_JID)),
        ?_assertEqual(lists:sort([{?CAROL_JID, false}, {?KAREN_JID, true}]),
                      subscribers(?LOCAL_CONTEXT, ?BOT))
      ]}
    ]}.

test_owner_roster() ->
    { "owner_roster", [
      { "gets the roster of the current owner, as recorded by the bot", [
        ?_assertEqual(
           lists:sort([jid:from_binary(I) || I <- ?BOT_OWNER_ROSTER]),
           lists:sort(owner_roster(?LOCAL_CONTEXT, ?BOT)))
      ]},
      { "returns not_found for non-existant bot", [
        ?_assertEqual(not_found,
                      owner_roster(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.

test_owner_roster_ver() ->
    { "owner_roster_ver", [
      { "gets the roster version of the owner, as recorded by the bot", [
        ?_assertEqual(<<"999-4">>, owner_roster_ver(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "returns not_found for non-existant bot", [
        ?_assertEqual(not_found,
                      owner_roster_ver(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.


test_update_owner_roster() ->
    NewRoster = lists:sort([?BOB_JID, ?KAREN_JID]),
    { "update_owner_roster", [
      { "entirely replaces the roster and roster version data", [
        ?_assertEqual(ok, update_owner_roster(
                            ?LOCAL_CONTEXT, ?BOT,
                            NewRoster, <<"999">>)),
        ?_assertEqual(NewRoster, lists:sort(owner_roster(?LOCAL_CONTEXT, ?BOT)))
      ]}
    ]}.

test_delete() ->
    NewBot = #{id := ID} = new_bot(),
    { "delete", [
      { "deletes the specified bot and its shortname lookup, if present", [
        ?_assertEqual(ok, delete(?LOCAL_CONTEXT, ?BOT)),
        ?_assertEqual(not_found, get(?LOCAL_CONTEXT, ?BOT)),
        ?_assertEqual(not_found, get_id_by_name(?LOCAL_CONTEXT, ?BOT))
      ]},
      { "deletes cleanly when no shortname exists", [
        ?_assertEqual(ok, insert(?LOCAL_CONTEXT,
                                 maps:without([shortname], NewBot))),
        ?_assertEqual(ok, delete(?LOCAL_CONTEXT, ID)),
        ?_assertEqual(not_found, get(?LOCAL_CONTEXT, ID))
      ]},
      { "does not fail on invalid ID", [
        ?_assertEqual(ok, delete(?LOCAL_CONTEXT, wocky_db:create_id()))
      ]}
    ]}.

expected_affiliations() ->
    [{?ALICE_JID, owner}, {?BOB_JID, spectator}].

expected_affiliations_after_change() ->
    [{?ALICE_JID, owner}, {?CAROL_JID, spectator}].

new_bot() ->
    #{id => wocky_db:create_id(), server => ?LOCAL_CONTEXT,
      title => <<"Test bot X">>, shortname => <<"ShortName">>,
      owner => ?BOB_B_JID, description => <<"Test insert bot">>,
      lat => 1.0, lon => -2.0, radius => 10,
      visibility => ?WOCKY_BOT_VIS_OWNER, affiliates => [?CAROL_B_JID],
      alerts => ?WOCKY_BOT_ALERT_ENABLED,
      owner_roster => null, owner_roster_ver => null
     }.
