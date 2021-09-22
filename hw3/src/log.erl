-module(log).
-compile(export_all).

start(Tester, Nodes) ->
    spawn_link(fun() -> init(Tester, Nodes) end).

stop(Logger) ->
    Logger ! stop.

init(Tester, _Nodes) ->
    loop(Tester).

loop(Tester) ->
    receive
        {log, LogFrom, Time, {SendRecv, MsgFrom, MsgTo, Msg}} -> 
            log(LogFrom, SendRecv, MsgFrom, MsgTo, Time, Msg),
            MsgID = Msg, % Msg happens to be randomNum here, we use it as ID
            Tester ! {msg, MsgID, SendRecv, MsgFrom, MsgTo},
            loop(Tester);
        stop ->
            ok
    end.

log(LogFrom, SendRecv, MsgFrom, MsgTo, Time, Msg) ->   
    io:format("[~p] [~w]: ~p msg from [~p] to [~p] msg [~p]~n", [Time, LogFrom, SendRecv, MsgFrom, MsgTo, Msg]).