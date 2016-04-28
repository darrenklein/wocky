%%% @copyright 2016+ Hippware, Inc.
%%% @doc Integration test suite for wocky_reg
-module(reg_SUITE).

-export([
         suite/0,
         all/0,
         groups/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_group/2,
         end_per_group/2,
         init_per_testcase/2,
         end_per_testcase/2]).

-export([
         incorrect_req_type/1,
         invalid_json/1,
         missing_fields/1,
         unauthorized_new/1,
         new_user/1,
         unauthorized_update/1,
         update/1,
         invalid_phone_number/1,
         session_id_update/1,
         session_id_update_phone_number/1,
         invalid_auth_provider/1,
         invalid_session_id/1,
         missing_auth_data/1,
         session_with_userid/1,
         invalid_user_id/1,
         missing_user_id/1,
         bypass_prefixes/1,
         valid_avatar/1,
         non_existant_avatar/1,
         unowned_avatar/1,
         wrong_purpose_avatar/1
        ]).

-include("wocky_db_seed.hrl").

-define(URL, "http://localhost:1096/wocky/v1/user").
-define(TEST_HANDLE, <<"TinyRooooobot">>).

all() -> [{group, reg}].

groups() ->
    [{reg, [sequence], reg_cases()}].

reg_cases() ->
    [
     incorrect_req_type,
     invalid_json,
     missing_fields,
     unauthorized_new,
     new_user,
     unauthorized_update,
     update,
     invalid_phone_number,
     session_id_update,
     session_id_update_phone_number,
     invalid_auth_provider,
     invalid_session_id,
     missing_auth_data,
     session_with_userid,
     invalid_user_id,
     missing_user_id,
     bypass_prefixes,
     valid_avatar,
     non_existant_avatar,
     unowned_avatar,
     wrong_purpose_avatar
    ].

suite() ->
    escalus:suite().

init_per_suite(Config) ->
    test_helper:start_ejabberd(),
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus:end_per_suite(Config),
    test_helper:stop_ejabberd(),
    ok.

init_per_group(_Group, ConfigIn) -> ConfigIn.

end_per_group(_Group, Config) -> Config.

init_per_testcase(_CaseName, Config) ->
    wocky_db_seed:clear_tables(?LOCAL_CONTEXT, [auth_token]),
    wocky_db_seed:clear_tables(shared, [user, handle_to_user,
                                        phone_number_to_user]),
    Config.

end_per_testcase(_CaseName, Config) ->
    Config.

%%%===================================================================
%%% Tests
%%%===================================================================

incorrect_req_type(_) ->
    {ok, {405, _}} = httpc:request(get, {?URL, []}, [], [{full_result, false}]).

invalid_json(_) ->
    {ok, {400, _}} = request(<<"bogus">>).

missing_fields(_) ->
    start_digits_server(false),
    JSON2 = encode(proplists:delete(resource, test_data())),
    {ok, {400, _}} = request(JSON2),

    JSON3 = encode(proplists:delete(phone_number, test_data())),
    {ok, {400, _}} = request(JSON3),

    JSON4 = encode([{user, <<"bogus">>} | test_data()]),
    {ok, {403, _}} = request(JSON4),

    JSON5 = encode([{avatar, <<"bogus">>} | test_data()]),
    {ok, {400, _}} = request(JSON5),

    AvatarURL = tros:make_url(?LOCAL_CONTEXT, <<"bogus">>),
    JSON6 = encode([{avatar, AvatarURL} | test_data()]),
    {ok, {403, _}} = request(JSON6),
    stop_digits_server().

unauthorized_new(_) ->
    start_digits_server(false),
    JSON = encode(test_data()),
    {ok, {403, _}} = request(JSON),
    stop_digits_server().

new_user(_) ->
    start_digits_server(true),
    JSON = encode(test_data()),
    {ok, {201, Body}} = request(JSON),
    verify_new_result(Body),
    stop_digits_server().

unauthorized_update(_) ->
    start_digits_server(false),
    User = create_user(),
    verify_handle(User, ?TEST_HANDLE),
    Data = lists:keyreplace(handle, 1, test_data(), {handle, <<"NewHandle">>}),
    JSON = encode(Data),
    {ok, {403, _}} = request(JSON),
    verify_handle(User, ?TEST_HANDLE),
    stop_digits_server().

update(_) ->
    start_digits_server(true),
    User = create_user(),
    Data = lists:keyreplace(handle, 1, test_data(), {handle, <<"NewHandle">>}),
    JSON = encode([{server, ?SERVER} | Data]),
    {ok, {201, _Body}} = request(JSON),
    verify_handle(User, <<"NewHandle">>),
    stop_digits_server().

invalid_phone_number(_) ->
    start_digits_server(true),
    User = create_user(),
    Data = lists:keyreplace(phone_number, 1, test_data(),
                            {phone_number, <<"+5551231234">>}),
    JSON = encode(Data),
    {ok, {403, _Body}} = request(JSON),
    verify_phone_number(User, ?PHONE_NUMBER),
    stop_digits_server().

session_id_update(_) ->
    start_digits_server(true),
    User = create_user(),
    JSON = encode(test_data()),
    {ok, {201, Body}} = request(JSON),
    {struct, Elements} = mochijson2:decode(Body),
    SessionID = proplists:get_value(<<"token">>, Elements),
    UUID = proplists:get_value(<<"user">>, Elements),
    Data = [{handle, <<"NewHandle">>} | session_test_data(UUID, SessionID)],
    {ok, {201, Body2}} = request(encode(Data)),
    {struct, Elements2} = mochijson2:decode(Body2),
    true = proplists:get_value(<<"handle_set">>, Elements2),
    <<"NewHandle">> = proplists:get_value(<<"handle">>, Elements2),
    verify_handle(User, <<"NewHandle">>),
    stop_digits_server().


session_id_update_phone_number(_) ->
    start_digits_server(true),
    User = create_user(),
    JSON = encode(test_data()),
    {ok, {201, Body}} = request(JSON),
    {struct, Elements} = mochijson2:decode(Body),
    SessionID = proplists:get_value(<<"token">>, Elements),
    UUID = proplists:get_value(<<"user">>, Elements),
    Data = lists:keyreplace(phone_number, 1, session_test_data(UUID, SessionID),
                            {phone_number, <<"+5551231234">>}),
    {ok, {201, Body2}} = request(encode(Data)),
    {struct, Elements2} = mochijson2:decode(Body2),
    false = proplists:get_value(<<"phone_number_set">>, Elements2),
    ?PHONE_NUMBER = proplists:get_value(<<"phone_number">>, Elements2),
    verify_phone_number(User, ?PHONE_NUMBER),
    stop_digits_server().

invalid_auth_provider(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    Data = lists:keyreplace('X-Auth-Service-Provider', 1, test_data(),
                            {'X-Auth-Service-Provider',
                             <<"http://evilhost.com">>}),
    JSON = encode(Data),
    {ok, {403, _Body}} = request(JSON).

invalid_session_id(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token]),
    Data = lists:keyreplace(token, 1, session_test_data(?ALICE, ?TOKEN),
                            {token, <<"$T$Icantotallyhackthissession">>}),
    JSON = encode(Data),
    {ok, {403, _Body}} = request(JSON).

missing_auth_data(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token]),
    Data = lists:keydelete(token, 1, session_test_data(?ALICE, ?TOKEN)),
    JSON = encode(Data),
    {ok, {400, _Body}} = request(JSON).

session_with_userid(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token]),
    Data = lists:keyreplace(user, 1, session_test_data(?ALICE, ?TOKEN),
                            {auth_user, ?AUTH_USER}),
    ct:log("Data: ~p", [Data]),
    JSON = encode(Data),
    {ok, {201, _Body}} = request(JSON).

invalid_user_id(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token]),
    Data = lists:keyreplace(user, 1, session_test_data(?ALICE, ?TOKEN),
                            {auth_user, <<"999999999">>}),
    JSON = encode(Data),
    {ok, {403, _Body}} = request(JSON).

missing_user_id(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token]),
    Data = lists:keydelete(user, 1, session_test_data(?ALICE, ?TOKEN)),
    JSON = encode(Data),
    {ok, {400, _Body}} = request(JSON).

bypass_prefixes(_) ->
    start_digits_server(false),
    Data = [{resource, ?RESOURCE},
            {auth_user, ?AUTH_USER},
            {phone_number, <<"+15556667777">>},
            {'X-Auth-Service-Provider',
             list_to_binary(fake_digits_server:url())},
            {'X-Verify-Credentials-Authorization', <<"badDigitsAuth">>}
           ],
    JSON = encode(Data),
    {ok, {201, _Body}} = request(JSON),
    stop_digits_server().

valid_avatar(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token, media, media_data]),
    AvatarURL = tros:make_url(?LOCAL_CONTEXT, ?AVATAR_FILE2),
    Data = [{avatar, AvatarURL}|
            session_test_data(?ALICE, ?TOKEN)],
    JSON = encode(Data),
    {ok, {201, Body}} = request(JSON),
    verify_avatar(?ALICE, AvatarURL),
    verify_avatar_in_body(Body, AvatarURL).


non_existant_avatar(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token, media, media_data]),
    Data = [{avatar, tros:make_url(?LOCAL_CONTEXT, mod_tros:make_file_id())} |
            session_test_data(?ALICE, ?TOKEN)],
    JSON = encode(Data),
    {ok, {409, _Body}} = request(JSON).

unowned_avatar(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token, media, media_data]),
    Data = [{avatar, tros:make_url(?LOCAL_CONTEXT, ?AVATAR_FILE3)} |
            session_test_data(?ALICE, ?TOKEN)],
    JSON = encode(Data),
    {ok, {409, _Body}} = request(JSON).

wrong_purpose_avatar(_) ->
    wocky_db_seed:seed_tables(shared, [user]),
    wocky_db_seed:seed_tables(?LOCAL_CONTEXT, [auth_token, media, media_data]),
    Data = [{avatar, tros:make_url(?LOCAL_CONTEXT, ?MEDIA_FILE)} |
            session_test_data(?ALICE, ?TOKEN)],
    JSON = encode(Data),
    {ok, {409, _Body}} = request(JSON).

%%%===================================================================
%%% Helpers
%%%===================================================================

start_digits_server(Result) ->
    fake_digits_server:start(Result).
stop_digits_server() ->
    fake_digits_server:stop().

encode(Data) ->
    iolist_to_binary(mochijson2:encode({struct, Data})).

request(Body) ->
    httpc:request(post, {?URL, [{"Accept", "application/json"}],
                  "application/json", Body}, [], [{full_result, false}]).

test_data() ->
    [{handle, ?TEST_HANDLE},
     {resource, ?RESOURCE},
     {email, <<"me@alice.com">>},
     {auth_user, ?AUTH_USER},
     {phone_number, ?PHONE_NUMBER},
     {'X-Auth-Service-Provider', list_to_binary(fake_digits_server:url())},
     {'X-Verify-Credentials-Authorization', ?DIGITS_AUTH},
     {first_name, <<"Alice">>},
     {last_name, <<"Alison">>},
     % Key this off a binary to test the atom-creation defence:
     {<<"extraRandomField">>, <<"Ignore me entirely!">>}
    ].

session_test_data(UUID, SessionID) ->
    [
     {user, UUID},
     {token, SessionID},
     {resource, ?RESOURCE},
     {email, <<"me@alice.com">>},
     {phone_number, ?PHONE_NUMBER},
     {first_name, <<"Alice">>},
     {last_name, <<"Alison">>}
    ].

verify_new_result(Body) ->
    {struct, Elements} = mochijson2:decode(Body),
    verify_elements(maps:from_list(Elements)).

verify_elements(#{
  <<"handle">> := ?TEST_HANDLE,
  <<"resource">> := ?RESOURCE,
  <<"email">> := <<"me@alice.com">>,
  <<"auth_user">> := ?AUTH_USER,
  <<"phone_number">> := ?PHONE_NUMBER,
  <<"first_name">> := <<"Alice">>,
  <<"last_name">> := <<"Alison">>,
  <<"user">> := _,
  <<"token">> := _,
  <<"is_new">> := true,
  <<"phone_number_set">> := true,
  <<"handle_set">> := true
 }) -> ok;
verify_elements(Fields) ->
    ct:fail("Missing or incorrect fields: ~p", [Fields]).

create_user() ->
    Fields = #{
      server => ?LOCAL_CONTEXT,
      handle => ?TEST_HANDLE,
      email => <<"me@alice.com">>,
      auth_user => ?AUTH_USER,
      phone_number => ?PHONE_NUMBER,
      first_name => <<"Alice">>,
      last_name => <<"Alison">>
     },
    User = wocky_db_user:create_user(Fields),
    true = wocky_db_user:maybe_set_handle(User, ?LOCAL_CONTEXT, ?TEST_HANDLE),
    ok = wocky_db_user:set_phone_number(User, ?LOCAL_CONTEXT, ?PHONE_NUMBER),
    User.

verify_handle(User, Handle) ->
    {User, ?LOCAL_CONTEXT} =
    wocky_db_user:get_user_by_handle(Handle),
    Handle = wocky_db_user:get_handle(User, ?LOCAL_CONTEXT).

verify_phone_number(User, PhoneNumber) ->
    {User, ?LOCAL_CONTEXT} =
    wocky_db_user:get_user_by_phone_number(PhoneNumber),
    PhoneNumber = wocky_db_user:get_phone_number(User, ?LOCAL_CONTEXT).

verify_avatar(User, Avatar) ->
    Avatar = wocky_db:select_one(shared, user, avatar, #{user => User}).

verify_avatar_in_body(Body, Avatar) ->
    {struct, Elements} = mochijson2:decode(Body),
    Avatar = proplists:get_value(<<"avatar">>, Elements).
