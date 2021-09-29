-module(gsm3).
-compile(export_all).

-define(timeout, 2000).
-define(crashN, 100).

start(Id) ->
    Rnd = rand:uniform(1000),
    Self = self(),
    {ok, spawn_link(fun() -> init(leader, Id, Rnd, Self) end)}.

start(Id, Grp) ->
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Grp, Self) end)}.

init(Id, Grp, Master) ->
    Self = self(),
    Grp ! {join, Master, Self},
    receive
        % slaves(first is leader), masters 
        {view, N, [Leader|Slaves], Group} ->
            erlang:monitor(process, Leader),
            Master ! {view, Group}, % master not care
            slave(Id, Master, Leader, N+1, {}, Slaves, Group)
    after ?timeout ->
        Master ! {error, "no reply from leader"}
    end.

init(leader, Id, Rnd, Master) ->
    rand:seed(exsss, Rnd),
    leader(Id, Master, 0, [], [Master]).

% N: seq number to be sent in this loop
leader(Id, Master, N, Slaves, Group) ->
    receive
        {mcast, Msg} ->
            bcast(Id, {msg, N, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, N+1, Slaves, Group);
        % node: wrk -> master, peer -> slave(group layer), 
        {join, Wrk, Peer} ->
            Slaves2 = lists:append(Slaves, [Peer]),
            Group2 = lists:append(Group, [Wrk]),
            bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
            Master ! {view, Group2}, % master not care
            leader(Id, Master, N+1, Slaves2, Group2);
        stop ->
            ok
    end.

slave(Id, Master, Leader, N, Last, Slaves, Group) ->
    receive
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {msg, I, _} when I < N ->
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {msg, N, Msg} ->
            Master ! Msg,
            slave(Id, Master, Leader, N+1, {msg, N, Msg}, Slaves, Group);
        % TODO: what if did not recv 'DOWN' and view msg come?
        %   then this line won't be matched
        {view, N, [Leader|Slaves2], Group2} ->
            Master ! {view, Group2},
            slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves2], Group2}, Slaves2, Group2);
        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Id, Master, N, Last, Slaves, Group);
        stop ->
            ok
    end.

% delete current leader
election(Id, Master, N, Last, Slaves, [_|Group]) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            % make sure new node is up before electing new leader
            spawn(fun() -> new ! {new, Self} end),
            receive
                ack -> ok
            end,

            % TODO but still need to spread new view out before this node is allowed to crash... 
            % just to solve this issue temprorarily, we could use last node as new node's first contactor, but node may down too

            % maybe implementing a rcast will solve all these
            % we just stop here for gsm3 and leave this problem to gsm4

            % finish leader's requet
            bcast(Id, Last, Rest), % what about down now
            bcast(Id, {view, N, Slaves, Group}, Rest), % TODO: should make sure bcast success
            Master ! {view, Group},
            
            leader(Id, Master, N+1, Rest, Group);
        [Leader|Rest] ->
            % if potential leader dies before election, start another election
            % but the msg, if only sent to the potential leader, will be lost
            % which is ok, because it does not result in 
            erlang:monitor(process, Leader), 
            slave(Id, Master, Leader, N, Last, Rest, Group)
    end.

% only last node does not crash, it does not bcast
bcast(Id, Msg, Nodes) ->
    lists:foreach(fun(Node) -> Node ! Msg, crash(Id) end, Nodes).

% TODO: what about node (not leader) crash?
crash(Id) ->
    case rand:uniform(?crashN) of
        ?crashN ->
            io:format("leader ~w crash ~n", [Id]),
            exit(no_luck);
        _E ->
            % io:format("~p~n", [_E]),
            ok
    end.