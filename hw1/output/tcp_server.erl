-module(tcp_server).
-compile([export_all]).

init(Port) ->
	Opt = [list, {active, false}, {reuseaddr, true}],
	case gen_tcp:listen(Port, Opt) of
		{ok, Listen} ->
			% gen_tcp:close(Listen),
			io:format("listening...~n"),
			handler(Listen);
		{error, _Error} ->
			io:format("error: ~p~n", [_Error])
	end.

handler(Listen) ->
	% TODO spawn
	case gen_tcp:accept(Listen) of
		{ok, Client} ->
			{ok, {Addr, Port}} = inet:peername(Client),
			io:format("new connection from ~s:~B~n", [format_ip(Addr), Port]),
			request(Client);
		{error, _Error} ->
			error
	end.

% send not block, recv block
request(Client) ->
	io:format("waiting for recv...~n"),
	Recv = gen_tcp:recv(Client, 0), % do not handle error now
	case Recv of
		{ok, Str} ->
			io:format("Received: ~s~n", [Str]),
			gen_tcp:send(Client, "Server received: " ++ Str);
		{error, Error} ->
			io:format("rudy: error: ~s~n", [Error])
	end,
	gen_tcp:close(Client).

% only IPV4
format_ip(Ip) ->
	format_ip("", tuple_to_list(Ip)).

format_ip(Now, Ip) when Ip == [] ->
	Now;
format_ip(Now, Ip) when Now == "" ->
	[First|Rest] = Ip,
	format_ip(integer_to_list(First), Rest);
format_ip(Now, Ip) ->
	[First|Rest] = Ip,
	format_ip(Now ++ "." ++ integer_to_list(First), Rest).

