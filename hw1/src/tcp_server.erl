-module(tcp_server).
-compile([export_all]).

% -spec format_ip(tuple()) -> string(). % for documentation only

create_tcp_server(Port, HandlerFunc) ->
	Opt = [list, {active, false}, {reuseaddr, true}, {backlog, 5}], % may recv msg from last connection, ignore this
	case gen_tcp:listen(Port, Opt) of
		{ok, ListenSocket} ->
			io:format("server listening...~n"),
			listen(ListenSocket, HandlerFunc);
		{error, _Error} ->
			io:format("error: ~p~n", [_Error])
	end.

% listen and spawn for every new connection
% 一个是process的复用，一个是socket连接的复用
listen(ListenSocket, HandlerFunc) ->
	case gen_tcp:accept(ListenSocket) of
		{ok, Socket} ->
			% {ok, {Addr, Port}} = inet:peername(Socket),
			% io:format("new connection from ~s:~B~n", [format_ip(Addr), Port]),

			% get from process pool
			_ = spawn(?MODULE, handler, [Socket, HandlerFunc]), % fun tcp_justPrint/1
			% handler(Socket, HandlerFunc),
			% handler(Socket, fun tcp_justPrint/1),
			listen(ListenSocket, HandlerFunc);
		{error, _Error} ->
			error
	end.

% for test only
tcp_justPrint(Req) ->
	io:format("From client: ~s~n", [Req]),
	{ok, "Server received: " ++ Req}.

handler(Socket, HandleFunc) ->
	% timeout close connection, rather than recv only once, since the msg may not be finished yet
	case gen_tcp:recv(Socket, 0) of 
		{ok, Str} ->
			case HandleFunc(Str) of
				{ok, Resp} ->
					% io:format("[TCP] Sending back: ~s~n", [Resp]),
					gen_tcp:send(Socket, Resp);
				{error, _Error} ->
					error
			end;
		{error, Error} ->
			io:format("rudy: error: ~s~n", [Error])		
	end,
	gen_tcp:close(Socket). % return to pool

% only IPV4, e.g. {10, 233, 0, 1}
format_ip(Ip) ->
	format_ip("", tuple_to_list(Ip)).

format_ip(Now, []) ->
	Now;
format_ip("", Ip) ->
	[First|Rest] = Ip,
	format_ip(integer_to_list(First), Rest);
format_ip(Now, Ip) ->
	[First|Rest] = Ip,
	format_ip(Now ++ "." ++ integer_to_list(First), Rest).

