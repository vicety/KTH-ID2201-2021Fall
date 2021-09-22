-module(tester).
-compile(export_all).

run() ->
    spawn_link(fun() -> loop(#{}, 0, 0) end).

stop(Tester) ->
    Tester ! stop.

loop(HistoryMap, DisorderCnt, Cnt) ->
    receive
        {msg, MsgID, SendRecv, _MsgFrom, _MsgTo} ->
            case maps:find(MsgID, HistoryMap) of
                {ok, sending} ->
                    DisorderCnt1 = DisorderCnt,
                    HistoryMap1 = maps:remove(MsgID, HistoryMap);
                {ok, received} ->
                    DisorderCnt1 = DisorderCnt + 2,
                    HistoryMap1 = maps:remove(MsgID, HistoryMap);
                error ->
                    HistoryMap1 = HistoryMap#{MsgID => SendRecv},
                    DisorderCnt1 = DisorderCnt
            end,
            loop(HistoryMap1, DisorderCnt1, Cnt + 1);
        stop ->
            io:format("Disorder Rate: [~p/~p = ~p]~n", [DisorderCnt, Cnt, DisorderCnt/Cnt])
    end.
    