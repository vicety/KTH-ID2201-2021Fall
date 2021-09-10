-module(bench).
-export([parse/0, bench/2, bench/4]).

parse() ->
    http:parse_request("GET /foo HTTP/1.1\r\nUser-Agent: Test\r\nAccept: anything\r\n\r\nThis is the body").

bench(Host, Port) ->
    bench(Host, Port, 4, 10).

bench(Host, Port, C, N) ->
    Start = now(),
    parallel(C, Host, Port, N, self()),
    collect(C),
    Finish = now(),
    T = timer:now_diff(Finish, Start),
    io:format(" ~wx~w requests in ~w ms~n", [C,N, (T div 1000)]).

parallel(0, _, _, _, _) ->
    ok;
parallel(C, Host, Port, N, Ctrl) ->
    spawn(fun() -> report(N, Host, Port, Ctrl) end),
    parallel(C-1, Host, Port, N, Ctrl).

report(N, Host, Port, Ctrl) ->
    run(N, Host, Port),
    Ctrl ! ok.


collect(0) ->
    ok;
collect(N) ->    
    receive 
	ok ->
	    collect(N-1)
    end.

run(0, _, _) ->
    ok;
run(N, Host, Port) ->
    %%io:format("sending request ~w~n", [N]),
    request(Host, Port),
    %%dummy(Host, Port),
    run(N-1, Host, Port).

dummy(_, _) ->
     ok.

request(Host, Port) ->
    {ok, Server} = gen_tcp:connect(Host, Port, [list, {active, false}, {reuseaddr, true}]),
    gen_tcp:send(Server, "GET / HTTP/1.1"),
    Recv = gen_tcp:recv(Server, 0),
    case Recv of
     	{ok, _} ->
     	    ok;
     	{error, Error} ->
     	    io:format("test: error: ~w~n", [Error])
    end,
    gen_tcp:close(Server).
    