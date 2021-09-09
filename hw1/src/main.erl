-module(main).
-compile(export_all).
-include("http.hrl").

main() ->
    Router = http_server:build_router([
        #handler{method="GET", uri="/echo", handler_func=fun echo:echo/1}
    ]),
    HTTPServer = http_server:create_http_server(12345, Router),
    http_server:start_server(HTTPServer).