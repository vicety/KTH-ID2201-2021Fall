-module(worker).
-compile(export_all).

% msg format: {traceID, [{pid, msg}]}

start(TimerType, PName, Logger, Seed, Sleep, Jitter) ->
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
    Wait = rand:uniform(Sleep),
    receive
        {new_peer, Peer} ->
            loop(Name, Log, Peers ++ [Peer], Sleep, Jitter, Timer, LocalSeqNum);
        {msg, RemoteName, RemoteTimer, Msg} ->
            RealTime = actual_time(),
            % io:format("actual_time: ~p, recv from ~p to local ~p~n", [RealTime, RemoteName, Name]),
            Timer1 = time:merge(Timer, RemoteTimer),
            
            % send log
            jitter(Jitter),
            Log ! {log, Name, Timer1, RealTime, {recv, RemoteName, Name, Msg}},
            
            loop(Name, Log, Peers, Sleep, Jitter, Timer1, LocalSeqNum+1);
        stop ->
            ok;
        Error ->
            Log ! {log, Name, time, {error, Error}}
    after Wait ->
        {PeerPID, PeerName} = select(Peers),
        
        % prepare msg & time 
        RealTime = actual_time(),
        % io:format("actual_time: ~p, send from local ~p to remote ~p~n", [RealTime, Name, PeerName]),
        Message = atom_to_list(Name) ++ "-" ++ integer_to_list(LocalSeqNum),
        Timer1 = time:update(Timer),
        PeerPID ! {msg, Name, Timer1, Message},

        % send log
        jitter(Jitter),
        Log ! {log, Name, Timer1, RealTime, {send, Name, PeerName, Message}},

        loop(Name, Log, Peers, Sleep, Jitter, Timer1, LocalSeqNum+1)
    end.

actual_time() ->
    erlang:unique_integer([monotonic]).

select(Peers) ->
    lists:nth(rand:uniform(length(Peers)), Peers).

jitter(0) -> ok;
jitter(Jitter) -> timer:sleep(rand:uniform(Jitter)).




















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