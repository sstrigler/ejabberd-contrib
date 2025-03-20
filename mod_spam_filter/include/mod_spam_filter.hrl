-record(state,
		{host = <<>>					:: binary(),
		 dump_fd = undefined			:: file:io_device() | undefined,
		 url_set = sets:new()			:: mod_spam_filter:url_set(),
		 jid_set = sets:new()			:: mod_spam_filter:jid_set(),
		 jid_cache = #{}				:: map(),
		 max_cache_size = 0				:: non_neg_integer() | unlimited,
		 rtbl_host = undefined          :: binary() | undefined,
		 rtbl_subscribed = false		:: boolean(),
		 rtbl_retry_timer = undefined	:: timer:tref() | undefined,
		 rtbl_blocked_domains = #{}      :: #{binary() => any()}}).

-define(SERVICE_JID_PREFIX, "rtbl-").
