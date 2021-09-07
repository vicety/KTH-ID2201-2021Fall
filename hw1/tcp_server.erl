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
			error
	end.

handler(Listen) ->
	% TODO spawn
	case gen_tcp:accept(Listen) of 
		{ok, Client} ->
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

