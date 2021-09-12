-module(http_handler).
-compile(export_all).
-include("http.hrl").

ok(_HTTPRequest) ->
    timer:sleep(40),
    "ok\r\n".

echo(HTTPRequest) ->
    % ?LOG(here),
    HTTPRequest#http_request.body ++ "\r\n".
