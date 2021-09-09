-module(tcp_client).
-compile([export_all]).

start() ->
	case gen_tcp:connect("localhost", 12345, [list, {active, false}, {reuseaddr, true}]) of
		{ok, Socket} ->
			case gen_tcp:send(Socket, "GET /echo HTTP/1.1") of
				ok ->
					{ok, Recv} = gen_tcp:recv(Socket, 0),
					io:format("From server: ~s~n", [Recv]);
				{error, _Reason} ->
					error
			end;
		{error, _Reason} ->
			error
	end.


