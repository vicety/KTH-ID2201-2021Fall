-define(debug, true).

-ifdef(debug).
-define(LOG(X), io:format("{~p,~p}: ~p~n", [?MODULE,?LINE,X])).
-else.
-define(LOG(X), true).
-endif.

-record(request_meta, {method, uri, http_version}).
-record(http_request, {meta = #request_meta{}, header = #{}, body = ""}).
-record(http_server, {router = #{}, port}).
-record(http_endpoint, {method, uri}).
-record(handler, {method, uri, handler_func}).