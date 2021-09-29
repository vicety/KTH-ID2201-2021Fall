-module(worker).
-compile(export_all).

% msg format: {traceID, [{pid, msg}]}

start(TimerType, PName, Logger, Seed, Sleep, Jitter) ->
    register(PName, spawn_link(fun() -> fifo_execute_loop(0, [], recv) end)), % fifo for lamport
    spawn_link(fun() -> init(TimerType, PName, Logger, Seed, Sleep, Jitter) end).

stop(Worker) ->
    Worker ! stop.

init(TimerType, Name, Log, Seed, Sleep, Jitter) ->
    rand:seed(exsss, Seed),
    % Timer = time:new(na, Name),
    % Timer = time:new(lamport, Name),
    Timer = time:new(TimerType, Name, ['1', '2', '3', '4']), % hard code here
    receive
        {peers, Peers} ->
            loop(Name, Log, Peers, Sleep, Jitter, Timer, 0);
        stop ->
            ok
    end.

peers(Wrk, Peers) ->
    Wrk ! {peers, Peers}.

new_peer(Wrk, Peer) ->
    Wrk ! {new_peer, Peer}.

loop(Name, Log, Peers, Sleep, Jitter, Timer, LocalSeqNum) ->
    % case Name of
    %     '3' ->
    %         Wait = rand:uniform(800);
    %     _ ->
    %         Wait = rand:uniform(Sleep)
    % end,
    Wait = rand:uniform(Sleep),
    % TODO: receive should not interrupt send interval, send should not block recv
    receive
        {new_peer, Peer} ->
            loop(Name, Log, Peers ++ [Peer], Sleep, Jitter, Timer, LocalSeqNum);
        {msg, RemoteName, RemoteTimer, Msg} ->
            RealTime = actual_time(),
            Timer1 = time:merge(Timer, RemoteTimer),
            SendLogFun = fun() -> Log ! {log, Name, Timer1, RealTime, {recv, RemoteName, Name, Msg}} end,

            % jitter(Jitter),
            SendLogFun(),
            
            % async_jitter(Jitter, SendLogFun),

            % async_jitter(Jitter, fun() -> Name ! {LocalSeqNum, SendLogFun} end),

            loop(Name, Log, Peers, Sleep, Jitter, Timer1, LocalSeqNum+1);
        stop ->
            ok;
        Error ->
            Log ! {log, Name, time, {error, Error}}
    after Wait ->
        {PeerPID, PeerName} = select(Peers),

        % try always send to '4'
        % case Name of
        %     '4' -> 
        %         {PeerPID, PeerName} = {1, 2},
        %         loop(Name, Log, Peers, Sleep, Jitter, Timer, LocalSeqNum), % not tail recursive, do not care here
        %         % avoid go to code under, sleep inf
        %         timer:sleep(1000000);
        %     _Else -> 
        %         {PeerPID, PeerName} = lists:nth(3, Peers)
        % end,
        
        RealTime = actual_time(),
        Message = atom_to_list(Name) ++ "-" ++ integer_to_list(LocalSeqNum),
        Timer1 = time:update(Timer),
        PeerPID ! {msg, Name, Timer1, Message},
        SendLogFun = fun() -> Log ! {log, Name, Timer1, RealTime, {send, Name, PeerName, Message}} end,

        jitter(Jitter),
        % jitter(),
        SendLogFun(),

        % async_jitter(Jitter, SendLogFun),

        % async_jitter(Jitter, fun() -> Name ! {LocalSeqNum, SendLogFun} end),

        loop(Name, Log, Peers, Sleep, Jitter, Timer1, LocalSeqNum+1)
    end.

actual_time() ->
    erlang:unique_integer([monotonic]).

select(Peers) ->
    lists:nth(rand:uniform(length(Peers)), Peers).

jitter(0) -> ok;
jitter(Jitter) -> timer:sleep(rand:uniform(Jitter)).

async_jitter(Jitter, F) ->
    spawn_link(fun() -> 
        jitter(Jitter),
        F()
    end).




% {lamport, _, N} = Timer1,
% async_jitter(Jitter, fun() -> Name ! {N, SendLogFun} end),


% 不对，发现lamport不是一个个增长的，哭了
fifo_execute_loop(ExpectSeq, Buf, recv) ->
    receive 
        {N, Func} ->
            % io:format("N: ~p~n", [N]),
            Buf1 = lists:keysort(1, Buf ++ [{N, Func}]),
            fifo_execute_loop(ExpectSeq, Buf1, clear)
    end;
% clear the buffer
fifo_execute_loop(ExpectSeq, [], clear) ->
    fifo_execute_loop(ExpectSeq, [], recv);
fifo_execute_loop(ExpectSeq, Buf, clear) ->
    [{N, F}|Rest] = Buf,
    % io:format("[~p]  N: ~p Exp: ~p~n", [self(), N, ExpectSeq]),
    case N of
        ExpectSeq ->
            F(),
            fifo_execute_loop(ExpectSeq+1, Rest, clear);
        _Else ->
            fifo_execute_loop(ExpectSeq, Buf, recv)
    end.





% synchronous -> logging from same process will never be out of order
% async -> how to measure disorder? 
%   1. disorder from same thread
%     1243 -> 1 disorder, 4123 -> ?
%     to be simple, we just treat 
%   2. disorder between threads
% async -> need to change the implementation, receive&after -> receive&sleep(maybe only a little while compared to the jittering time).
% maybe implement vector timer and get bonus first...

% lamport clock maintain partial order, so disorder disappears between send&recv, but disorder happens between threads that does not interact for a while.
% we'd better use outer clock to determine the actual order between events
% here we use erlang:unique_integer([monotonic]) as recommended here https://erlang.org/doc/apps/erts/time_correction.html
% returned integers are strictly monotonically ordered on current runtime system instance corresponding to creation time