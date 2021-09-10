-module(echo).
-compile(export_all).
-include("http.hrl").

echo(_HTTPRequest) ->
    timer:sleep(40),
    "ok\r\n".
    % HTTPRequest#http_request.body.
