%%% @copyright 2015+ Hippware, Inc.
%%% @doc Integration test suite for last activity and offline modules
-module(ejabberd_activity_SUITE).
-compile(export_all).

-include_lib("ejabberd/include/jlib.hrl").
-include_lib("common_test/include/ct.hrl").

-include("wocky_db_seed.hrl").

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------

all() ->
    [{group, last_activity}, {group, offline}].

groups() ->
    [{last_activity, [sequence], [activity_story,
                                  update_activity_story,
                                  server_uptime_story,
                                  unknown_user_acivity_story]},
     {offline, [sequence], [offline_message_story]}].

suite() ->
    escalus:suite().


%%--------------------------------------------------------------------
%% Init & teardown
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    ok = test_helper:start_ejabberd(),
    wocky_db_seed:clear_user_tables(?LOCAL_CONTEXT),
    wocky_db_seed:clear_tables(?LOCAL_CONTEXT, [last_activity, privacy,
                                                privacy_item]),
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus:end_per_suite(Config),
    test_helper:stop_ejabberd().

init_per_group(_GroupName, Config) ->
    escalus:create_users(Config),
    Config2 = escalus:make_everyone_friends(Config),
    escalus_ejabberd:wait_for_session_count(Config2, 0),
    Config2.

end_per_group(_GroupName, Config) ->
    escalus:delete_users(Config).

init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).


%%--------------------------------------------------------------------
%% mod_last tests
%%--------------------------------------------------------------------

activity_story(Config) ->
    % Last online story
    escalus:story(Config, [1, 1],
        fun(Alice, _Bob) ->
            %% Alice asks about Bob's last activity
            escalus_client:send(Alice, escalus_stanza:last_activity(bob)),

            %% server replies on Bob's behalf
            Stanza = escalus_client:wait_for_stanza(Alice),
            escalus:assert(is_last_result, Stanza),
            0 = get_last_activity(Stanza)
        end).

update_activity_story(Config) ->
    escalus:story(Config, [1],
        fun(Alice) ->
            %% Bob logs in
            {ok, Bob} = escalus_client:start_for(Config, bob, <<"bob">>),

            %% Bob logs out with a status
            Status = escalus_stanza:tags([{<<"status">>,
                                           <<"I am a banana!">>}]),
            Presence = escalus_stanza:presence(<<"unavailable">>, Status),
            escalus_client:send(Bob, Presence),
            escalus_client:stop(Bob),
            timer:sleep(1024), % more than a second

            %% Alice asks for Bob's last availability
            escalus_client:send(Alice, escalus_stanza:last_activity(bob)),

            %% Alice receives Bob's status and last online time > 0
            Stanza = escalus_client:wait_for_stanza(Alice),
            escalus:assert(is_last_result, Stanza),
            true = (1 =< get_last_activity(Stanza)),
            <<"I am a banana!">> = get_last_status(Stanza)
        end).

server_uptime_story(Config) ->
    escalus:story(Config, [1],
        fun(Alice) ->
            %% Alice asks for server's uptime
            Server = escalus_users:get_server(Config, alice),
            escalus_client:send(Alice, escalus_stanza:last_activity(Server)),

            %% Server replies with the uptime > 0
            Stanza = escalus_client:wait_for_stanza(Alice),
            escalus:assert(is_last_result, Stanza),
            true = (get_last_activity(Stanza) > 0)
        end).

unknown_user_acivity_story(Config) ->
    escalus:story(Config, [1],
        fun(Alice) ->
            escalus_client:send(Alice,
                                escalus_stanza:last_activity(<<"sven">>)),
            Stanza = escalus_client:wait_for_stanza(Alice),
            escalus:assert(is_error,
                           [<<"cancel">>, <<"service-unavailable">>], Stanza)
        end),
    ok.


get_last_activity(Stanza) ->
    S = exml_query:path(Stanza, [{element, <<"query">>},
                                 {attr, <<"seconds">>}]),
    list_to_integer(binary_to_list(S)).

get_last_status(Stanza) ->
    exml_query:path(Stanza, [{element, <<"query">>}, cdata]).


%%--------------------------------------------------------------------
%% mod_offline tests
%%--------------------------------------------------------------------

offline_message_story(Config) ->
    %% Alice sends a message to Bob, who is offline
    escalus:story(Config, [{alice, 1}], fun(Alice) ->
        escalus:send(Alice, escalus_stanza:chat_to(bob, <<"Hi, Offline!">>))
    end),

    %% Bob logs in
    Bob = login_send_presence(Config, bob),

    %% He receives his initial presence and the message
    Stanzas = escalus:wait_for_stanzas(Bob, 2),
    escalus_new_assert:mix_match([is_presence,
                                  is_chat(<<"Hi, Offline!">>)],
                                 Stanzas),
    escalus_cleaner:clean(Config).

is_chat(Content) ->
    fun(Stanza) -> escalus_pred:is_chat_message(Content, Stanza) end.

login_send_presence(Config, User) ->
    Spec = escalus_users:get_userspec(Config, User),
    {ok, Client} = escalus_client:start(Config, Spec, <<"dummy">>),
    escalus:send(Client, escalus_stanza:presence(<<"available">>)),
    Client.


