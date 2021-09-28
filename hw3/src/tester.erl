-module(tester).
-compile(export_all).

run(InitialSeqNum) ->
    register(tester, spawn_link(fun() -> loop(InitialSeqNum + 1, {#{}, #{}}, 0, 0, 0, [], 0, 0) end)).

stop() ->
    tester ! stop.

% need to check by msgID(actually traceID) and realTime, so need two maps here
loop(NextSeqNum, Maps, DisorderCnt, CasualDisorderCnt, Cnt, RealTimes, QueueSize, QueueSizeAcc) ->
    {HistoryMap, SendRecvMap} = Maps,
    receive
        {queue, QSize} ->
            loop(NextSeqNum, Maps, DisorderCnt, CasualDisorderCnt, Cnt, RealTimes, max(QSize, QueueSize), QueueSizeAcc + QSize);
        {msg, MsgID, RealTime, SendRecv, MsgFrom, MsgTo} ->
            % put into
            HistoryMap1 = HistoryMap#{RealTime => SendRecv},
            % consider causal event disorder here
            case maps:find(MsgID, SendRecvMap) of
                {ok, send} ->
                    CasualDisorderCnt1 = CasualDisorderCnt,
                    SendRecvMap1 = maps:remove(MsgID, SendRecvMap);
                {ok, recv} ->
                    io:format("detected casual disorder here, send from ~p to ~p happens after recv~n", [MsgTo, MsgFrom]),
                    CasualDisorderCnt1 = CasualDisorderCnt + 2,
                    SendRecvMap1 = maps:remove(MsgID, SendRecvMap);
                error ->
                    SendRecvMap1 = SendRecvMap#{MsgID => SendRecv},
                    CasualDisorderCnt1 = CasualDisorderCnt
            end, 

            case RealTime of
                NextSeqNum ->
                    {DisorderDelta, NextSeqNumDelta, HistoryMap2} = handleNextSeqNum(HistoryMap1, NextSeqNum);
                _Else ->
                    HistoryMap2 = HistoryMap1,
                    NextSeqNumDelta = 0,
                    DisorderDelta = 0
            end,

            RealTimes1 = lists:append(RealTimes, [RealTime]), 

            loop(NextSeqNum + NextSeqNumDelta, {HistoryMap2, SendRecvMap1}, DisorderCnt + DisorderDelta, CasualDisorderCnt1, Cnt + 1, RealTimes1, QueueSize, QueueSizeAcc);
        stop ->
            ReversePairCnt = count_reverse_pairs(lists:sublist(RealTimes, 100)),
            io:format("reverse pair [~p/4950] =~p~n", [ReversePairCnt, ReversePairCnt/4950]),
            % io:format("Disorder Rate: [~p/~p = ~p] Casual Disorder Rate: [~p/~p] = ~p~n", [DisorderCnt, Cnt, DisorderCnt/Cnt, CasualDisorderCnt, Cnt, CasualDisorderCnt/Cnt])
            io:format("Casual Disorder Rate: [~p/~p] = ~p~n", [CasualDisorderCnt, Cnt, CasualDisorderCnt/Cnt]),
            io:format("Maximum Queue Size: ~p~n", [QueueSize]),
            io:format("Avg Queue Size: ~p~n", [QueueSizeAcc/Cnt])
    end.

count_reverse_pairs(Arr) ->
    count_reverse_pairs(Arr, 1, 2, 0).

count_reverse_pairs(_, 100, _, Cnt) ->
    Cnt;
count_reverse_pairs(Arr, I, J, Cnt) ->
    case J of
        100 ->
            NextJ = I + 2,
            NextI = I + 1;
        _Else ->
            NextJ = J + 1,
            NextI = I
    end,
    Reverse = lists:nth(I, Arr) > lists:nth(J, Arr),
    if
        Reverse ->
            count_reverse_pairs(Arr, NextI, NextJ, Cnt+1);
        true ->
            count_reverse_pairs(Arr, NextI, NextJ, Cnt)
    end.

handleNextSeqNum(HistoryMap, NextSeqNum) ->
    handleNextSeqNum(HistoryMap, NextSeqNum, 0, 0).

handleNextSeqNum(HistoryMap, NextSeqNum, DisorderDelta, NextSeqNumDelta) ->
    HistoryMap1 = maps:remove(NextSeqNum, HistoryMap),
    case maps:size(HistoryMap1) of
        0 ->
            case DisorderDelta of
                0 ->
                    {DisorderDelta, NextSeqNumDelta+1, HistoryMap1}; % [1]
                _Other ->
                    {DisorderDelta+1, NextSeqNumDelta+1, HistoryMap1} % [1(removed) 2(removed) 3(now)]
            end;
        _Else ->
            case maps:find(NextSeqNum+1, HistoryMap1) of
                {ok, _Anything} ->
                    handleNextSeqNum(HistoryMap1, NextSeqNum+1, DisorderDelta+1, NextSeqNumDelta+1); % [1 2 3]
                error ->
                    {DisorderDelta+1, NextSeqNumDelta+1, HistoryMap1} % [1]
            end
    end.
    % if map empty, just return current counter
    % if not, add counter 
% case maps:find(NextSeqNum + 1, HistoryMap) of
    %     error ->
