-module(main).
-compile(export_all).
-include("http.hrl").

main(Port) ->
    Router = http_server:build_router([
        #handler{method="GET", uri="/", handler_func=fun http_handler:ok/1}
    ]),
    HTTPServer = http_server:create_http_server(Port, Router),
    http_server:start_server(HTTPServer).