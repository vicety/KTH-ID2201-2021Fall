-module(main).
-compile(export_all).
-include("http.hrl").

main(Port) ->
    Router = http_server:build_router([
        #handler{method="GET", uri="/", handler_func=fun http_handler:ok/1},
        #handler{method="GET", uri="/echo", handler_func=fun http_handler:echo/1},
        #handler{method="GET", uri="/time", handler_func=fun http_handler:time/1},
        #handler{method="GET", uri="/error", handler_func=fun http_handler:error/1}
    ]),
    HTTPServer = http_server:create_http_server(Port, Router),
    http_server:start_server(HTTPServer).

main() ->
    spawn(?MODULE, main, [50001]).