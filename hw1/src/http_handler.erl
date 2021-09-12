-module(http_handler).
-compile(export_all).
-include("http.hrl").

ok(_HTTPRequest) ->
    timer:sleep(40),
    "<html>ok</html>\r\n".

echo(HTTPRequest) ->
    % ?LOG(here),
    HTTPRequest#http_request.body ++ "\r\n".

time(_HTTPRequest) -> 
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:now_to_datetime(erlang:now()),
    lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w",[Year,Month,Day,Hour,Minute,Second])).

error() ->  
    A = 1,
    B = 0,
    A/B.