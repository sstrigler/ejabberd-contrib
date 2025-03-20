-module(mod_spam_filter_rtbl).

-include("mod_spam_filter.hrl").
-include_lib("xmpp/include/xmpp.hrl").
-include("logger.hrl").

-define(RTBL_DOMAINS_NODE, <<"spam_source_domains">>).

-export([init_rtbl_host/2,
	 parse_blocked_domains/2,
	 parse_new_blocked_domain/1,
	 parse_subscription/2,
	 reload/2,
	 request_blocked_domains/2,
	 unsubscribe/2]).

init_rtbl_host(undefined, State) ->
    State#state{rtbl_blocked_domains = #{}};
init_rtbl_host(RTBLHost, #state{host = Host} = State) ->
    request_blocked_domains(RTBLHost, Host),
    State#state{rtbl_host = RTBLHost, rtbl_subscribed = true, rtbl_blocked_domains = #{}}.

reload(NewRTBLHost, #state{rtbl_host = OldRTBLHost, host = Host} = State) ->
    unsubscribe(OldRTBLHost, Host),
    init_rtbl_host(NewRTBLHost, State).

subscribe(RTBLHost, From) ->
    FromJID = service_jid(From),
    SubIQ = #iq{type = set, to = jid:make(RTBLHost), from = FromJID,
		sub_els = [
			   #pubsub{subscribe = #ps_subscribe{jid = FromJID, node = ?RTBL_DOMAINS_NODE}}]},
    ?DEBUG("Sending subscription request:~n~p", [xmpp:encode(SubIQ)]),
    ejabberd_router:route_iq(SubIQ, subscribe_result, self()).

unsubscribe(undefined, _From) ->
    ok;
unsubscribe(RTBLHost, From) ->
    FromJID = jid:make(From),
    SubIQ = #iq{type = set, to = jid:make(RTBLHost), from = FromJID,
		sub_els = [
			   #pubsub{unsubscribe = #ps_subscribe{jid = FromJID, node = ?RTBL_DOMAINS_NODE}}]},
    ejabberd_router:route_iq(SubIQ, unsubscribe_result, self()).

-spec request_blocked_domains(binary(), binary()) -> ok.
request_blocked_domains(RTBLHost, From) ->
    IQ = #iq{type = get, from = jid:make(From),
	     to = jid:make(RTBLHost),
	     sub_els = [
			#pubsub{items = #ps_items{node = ?RTBL_DOMAINS_NODE}}]},
    ?DEBUG("Requesting RTBL blocked domains from ~s:~n~p", [RTBLHost, xmpp:encode(IQ)]),
    ejabberd_router:route_iq(IQ, blocked_domains, self()).

-spec parse_blocked_domains(mod_spam_filter:state(), timeout | stanza()) -> mod_spam_filter:state().
parse_blocked_domains(State, timeout) ->
    ?WARNING_MSG("Fetching blocked domains failed: fetch timeout. Retrying in 60 seconds", []),
    State#state{rtbl_retry_timer = erlang:send_after(60000, self(), request_blocked_domains)};
parse_blocked_domains(State, #iq{type = error} = IQ) ->
    ?WARNING_MSG("Fetching blocked domains failed: ~p. Retrying in 60 seconds",
		 [xmpp:format_stanza_error(xmpp:get_error(IQ))]),
    State#state{rtbl_retry_timer = erlang:send_after(60000, self(), request_blocked_domains)};
parse_blocked_domains(#state{rtbl_host = RTBLHost, host = Host} = State,
		      #iq{from = From, type = result} = IQ) ->
    ?DEBUG("parsing fetched items from ~p", [From]),
    case xmpp:get_subtag(IQ, #pubsub{}) of
	#pubsub{items = #ps_items{node = ?RTBL_DOMAINS_NODE, items = Items}} ->
	    ?DEBUG("Got items:~n~p", [Items]),
	    subscribe(RTBLHost, Host),
	    State#state{rtbl_retry_timer = undefined,
			rtbl_subscribed = true,
			rtbl_blocked_domains = parse_items(Items)};
	_ ->
	    ?WARNING_MSG("Fetching initial list failed: invalid result payload", []),
	    State#state{rtbl_retry_timer = undefined}
    end.

-spec parse_new_blocked_domain(stanza()) -> #{binary() => any()}.
parse_new_blocked_domain(Msg) ->
    case xmpp:get_subtag(Msg, #ps_event{}) of
	#ps_event{items = #ps_items{node = ?RTBL_DOMAINS_NODE, items = Items}} ->
	    ?DEBUG("Got items:~n~p", [Items]),
	    parse_items(Items);
	Other ->
	    ?WARNING_MSG("Couldn't extract items: ~p", [Other]),
	    #{}
    end.

-spec parse_items([ps_item()]) -> #{binary() => any()}.
parse_items(Items) ->
    lists:foldl(
      fun(#ps_item{id = ID}, Acc) ->
	      %% TODO extract meta/extra instructions
	      maps:put(ID, true, Acc)
      end, #{}, Items).

parse_subscription(State, timeout) ->
    ?WARNING_MSG("Subscription error: request timeout", []),
    State#state{rtbl_subscribed =  false};
parse_subscription(State, #iq{type = error} = IQ) ->
    ?WARNING_MSG("Subscription error: ~p", [xmpp:format_stanza_error(xmpp:get_error(IQ))]),
    State#state{rtbl_subscribed = false};
parse_subscription(State, _) ->
    State#state{rtbl_subscribed = true}.

service_jid(Host) ->
    jid:make(<<>>, Host, <<?SERVICE_JID_PREFIX, (ejabberd_cluster:node_id())/binary>>).
