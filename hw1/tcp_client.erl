-module(tcp_client).
-compile([export_all]).

new_socket() ->
	case gen_tcp:connect("localhost", 12345, [list, {active, false}, {reuseaddr, true}]) of
		{ok, Socket} ->
			case gen_tcp:send(Socket, "hello") of
				ok ->
					Recv = gen_tcp:recv(Socket, 0),
					io:format("~w~n", [Recv]);
				{error, _Reason} ->
					error
			end;
		{error, _Reason} ->
			error
	end.


