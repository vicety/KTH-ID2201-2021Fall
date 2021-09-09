-module(echo).
-compile(export_all).
-include("http.hrl").

echo(_HTTPRequest) ->
    "ok\r\n".
    % HTTPRequest#http_request.body.
