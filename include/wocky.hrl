%%%----------------------------------------------------------------------
%%% File    : wocky.hrl
%%% Author  : Beng Tan
%%% Purpose : A header stub
%%%
%%%
%%% Copyright (C) 2015 Hippware
%%%----------------------------------------------------------------------

-ifndef(WOCKY_HRL).
-define(WOCKY_HRL, true).

-define(WOCKY_VERSION, element(2, application:get_key(wocky,vsn))).

-record(table_def, {
          name          :: atom(),
          columns       :: [{atom(), atom()
                                 | {set | list, atom()}
                                 | {map, atom(), atom()}}],
          primary_key   :: atom() | [[atom()] | atom()],
          order_by = [] :: atom() | [{atom(), asc | desc}]
         }).

-define(NS_TOKEN, <<"hippware.com/token">>).
-define(NS_PHONE, <<"hippware.com/hxep/phone">>).
-define(NS_HANDLE, <<"hippware.com/hxep/handle">>).
-define(NS_GROUP_CHAT, <<"hippware.com/hxep/groupchat">>).

-define(GROUP_CHAT_RESOURCE_PREFIX, "groupchat/").
-define(GROUP_CHAT_WITH_JID, <<"$$GROUP_CHAT$$">>).

-endif. % ifdef WOCKY_HRL
