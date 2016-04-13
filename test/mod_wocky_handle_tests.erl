%%% @copyright 2016+ Hippware, Inc.
%%% @doc Test suite for mod_wocky_phone.erl
-module(mod_wocky_handle_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("ejabberd/include/jlib.hrl").
-include("wocky_db_seed.hrl").

-import(mod_wocky_handle, [handle_iq/3]).


mod_wocky_phone_test_() -> {
  "mod_wocky_handle",
  setup, fun before_all/0, fun after_all/1,
  [
    test_iq_get_request(),
    test_iq_get_results(),
    test_iq_set()
  ]
}.

before_all() ->
    ok = wocky_app:start(),
    ok = wocky_db_seed:prepare_tables(shared, [user, handle_to_user]),
    {ok, _} = wocky_db_seed:seed_table(shared, handle_to_user),
    {ok, _} = wocky_db_seed:seed_table(shared, user),
    ok.

after_all(_) ->
    ok = wocky_db_seed:clear_tables(shared, [user, handle_to_user]),
    ok = wocky_app:stop().

-define(FROM, #jid{luser = ?ALICE, lserver = ?SERVER}).
-define(TO, #jid{lserver = ?SERVER}).

-define(RESULT_IQ(Content),
        #iq{type = result,
            sub_el = [#xmlel{children = Content}]}).

make_iq(Handles) ->
    iq_get([item_el(H) || H <- Handles]).

iq_get(Items) ->
    #iq{type = get,
        sub_el = #xmlel{name = <<"lookup">>,
                        children = Items}}.

item_el(H) ->
    #xmlel{name = <<"item">>,
           attrs = [{<<"id">>, iolist_to_binary(H)}]}.

test_iq_get_request() ->
  { "handle_iq with type get", [
    { "returns an empty result IQ if there are no item elements", [
      ?_assertMatch(?RESULT_IQ([]), handle_iq(?FROM, ?TO, make_iq([])))
    ]},
    { "ignores any item elements without an id", [
      ?_assertMatch(?RESULT_IQ([]),
                    handle_iq(?FROM, ?TO, iq_get([#xmlel{name = <<"item">>}])))
    ]},
    { "returns a result iq when the request is properly formatted", [
      ?_assertMatch(?RESULT_IQ([#xmlel{name = <<"item">>}]),
                    handle_iq(?FROM, ?TO, make_iq([<<"alice">>])))
    ]}
  ]}.

setup_request() ->
    Handles = [<<"alice">>, <<"carol">>, <<"bob">>, <<"karen">>, <<"duke">>],
    ResultIQ = handle_iq(?FROM, ?TO, make_iq(Handles)),
    #iq{type = result,
        sub_el = [#xmlel{children = Els}]} = ResultIQ,
    Els.

after_each(_) ->
    ok.

-define(FIRST(X), element(3, hd(X))).
-define(LAST(X), element(3, hd(lists:reverse(X)))).

test_iq_get_results() ->
  { "handle_iq with type get", setup, fun setup_request/0, fun after_each/1,
    fun (Els) -> [
      { "returns a result item for each item in the lookup list", [
        ?_assertEqual(5, length(Els))
      ]},
      { "returns item-not-found for an unrecognized handle", [
        ?_assertEqual(<<"item-not-found">>,
                      proplists:get_value(<<"error">>, ?LAST(Els)))
      ]},
      { "returns the proper user information for a handle", [
        ?_assertMatch(<<"alice">>,
                      proplists:get_value(<<"id">>, ?FIRST(Els))),
        ?_assertMatch(<<"043e8c96-ba30-11e5-9912-ba0be0483c18@localhost">>,
                      proplists:get_value(<<"jid">>, ?FIRST(Els)))
      ]}
    ] end
  }.


test_iq_set() ->
  ErrorIQ = #iq{type = error, sub_el = [?ERR_NOT_ALLOWED]},
  { "handle_iq returns a error IQ when the IQ type is set", [
      ?_assertMatch(ErrorIQ, handle_iq(?FROM, ?TO, #iq{type = set}))
  ]}.
