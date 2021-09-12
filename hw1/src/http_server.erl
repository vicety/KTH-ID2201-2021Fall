-module(http_server).
-compile(export_all).
-include("http.hrl").

create_http_server(Port, Router) ->
    #http_server{port=Port, router=Router}.

build_router(Handlers) ->
    build_router(#{}, Handlers).

build_router(Router, []) ->
    Router;
build_router(Router, Handlers) ->
    [Handler|Rest] = Handlers,
    K = #http_endpoint{method=Handler#handler.method, uri=Handler#handler.uri},
    UpdatedRouter = Router#{K => Handler#handler.handler_func},
    build_router(UpdatedRouter, Rest).

start_server(HTTPServer) ->
    TcpHandler = fun(RequestStr) ->
        % TODO Request may not complete, need a buffer to store that
        http_pipeline(HTTPServer, RequestStr)
    end,
    tcp_server:create_tcp_server(HTTPServer#http_server.port, TcpHandler).

http_pipeline(Server, RequestStr) ->
    HTTPRequest = parse_http_request(RequestStr),
    RawResponse = dispatcher(Server, HTTPRequest),
    make_http_response(RawResponse).

dispatcher(Server, HTTPRequest) ->
    URI = HTTPRequest#http_request.meta#request_meta.uri,
    Method = HTTPRequest#http_request.meta#request_meta.method,
    RouterMap = Server#http_server.router,
    K = #http_endpoint{method=Method, uri=URI},
    case maps:is_key(K, RouterMap) of
        true ->
            #{K := Handler} = RouterMap,
            Handler(HTTPRequest);
        false ->
            error
    end.

make_http_response(RespStr) -> 
    {ok, "HTTP/1.1 200 OK\r\n\r\n" ++ RespStr}. % TODO: handle error

% TODO: ensure I parse it right
parse_http_request(RequestStr) ->
    [RequestLine|Rest] = string:split(RequestStr, "\r\n"),
    [Headers|Body] = string:split(Rest, "\r\n\r\n"), % client must at least include a host header, c.f. rfc2616 14.23
    
    ?LOG("RequestLine: " ++ RequestLine),    
    ?LOG("Headers: " ++ Headers),
    ?LOG("Body: " ++ Body),

    RequestMeta = parse_request_line(RequestLine),
    RequestHeaderMap = parse_request_headers(Headers),

    #http_request{meta=RequestMeta, header=RequestHeaderMap, body=Body}.

parse_request_line(RequestLine) ->
    [Method|Rest] = string:split(RequestLine, " "),
    [URI|HTTPVersion] = string:split(Rest, " "),
    #request_meta{method=Method, uri=URI, http_version=HTTPVersion}.

parse_request_headers(HeaderStr) ->
    parse_request_headers(#{}, HeaderStr).

parse_request_headers(CurMap, []) ->
    CurMap;
parse_request_headers(CurMap, Headers) ->
    [Header|Rest] = string:split(Headers, "\r\n"),
    % io:format("Header: [~s]~n", [Header]),
    [K|V] = string:split(Header, ":"),
    UpdatedMap = CurMap#{K => V},
    parse_request_headers(UpdatedMap, Rest).
