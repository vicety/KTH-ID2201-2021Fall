-module(gsm4).
-compile(export_all).

-define(timeout, 2000).
-define(crashN, 40).

% 目标：增加故障拉起新的

start(Id, Rnd, Replica) ->
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Rnd, Self, Replica) end)}.

init(Id, Rnd, Master, Replica) ->
    rand:seed(exsss, Rnd),
    io:format("spawned leader ~p ~p~n", [Id, self()]),
    leader(Id, Master, 1, [], [Master], Replica).

start_slave(Id, Grp, Rnd) ->
    Self = self(),
    {ok, spawn_link(fun() -> init_slave(Id, Rnd, Grp, Self) end)}.

init_slave(Id, Rnd, Grp, Master) ->
    rand:seed(exsss, Rnd),
    Self = self(),
    io:format("spawned ~p ~p~n", [Id, self()]),
    Grp ! {join, Master, Self},
    receive
        % slaves(first is leader), masters 
        {view, N, [Leader|Slaves], Group} ->
            io:format("slave ~p recv first view ~p monitoring ~p~n", [Id, {view, N, [Leader|Slaves], Group}, Leader]),
            erlang:monitor(process, Leader),
            Master ! {view, Group},
            slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group}, Slaves, Group)
    after ?timeout ->
        Master ! {error, "no reply from leader"}
    end.

leader(Id, Master, N, Slaves, Group, Replica) ->
    receive
        {mcast, Msg} ->
            % io:format("Id=[~p] leader send msg:[~p]~n", [Id, Msg]),
            bcast(Id, {msg, N, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, N+1, Slaves, Group, Replica);
        % node: wrk -> master, peer -> slave(group layer), 
        {join, Wrk, Peer} ->
            Slaves2 = lists:append(Slaves, [Peer]),
            Group2 = lists:append(Group, [Wrk]),
            bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
            Master ! {view, Group2}, % master not care
            leader(Id, Master, N+1, Slaves2, Group2, Replica);
        stop ->
            ok
    end.

slave(Id, Master, Leader, N, Last, Slaves, Group) ->
    receive
        {'DOWN', _Ref, process, Leader, _Reason} ->
            io:format("slave ~p detect ~p down~n", [Id, Leader]),
            election(Id, Master, N, Last, Slaves, Group);
        {mcast, Msg} ->
            % io:format("leader ~p~n", [Leader]),
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {join, Wrk, Peer} ->
            io:format("Id [~p] recv join [~p]~n", [Id, {join, Wrk, Peer}]),
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {msg, I, Msg} when I < N ->
            io:format("Id [~p] discard seen message ~p~n", [Id, Msg]),
            slave(Id, Master, Leader, N, Last, Slaves, Group); 
        {msg, N, Msg} ->
            io:format("Id [~p] recv msg [~p]~n", [Id, {msg, N, Msg}]),
            % io:format("Id=[~p] recv msg:[~p]~n", [Id, Msg]),，
            Master ! Msg,
            slave(Id, Master, Leader, N+1, {msg, N, Msg}, Slaves, Group);
        {view, I, [DeclaredLeader|Slaves2], Group2} when I < N ->
            io:format("Id [~p] rcvd seen view [N=~p] leader ~p slaves ~p group ~p, discard~n", [Id, I, DeclaredLeader, Slaves2, Group2]),
            slave(Id, Master, Leader, N, Last, Slaves, Group); 
        {view, N, [DeclaredLeader|Slaves2], Group2} ->
            io:format("Id [~p] recv [~p]~n", [Id, {view, N, [DeclaredLeader|Slaves2], Group2}]),
            case DeclaredLeader of
                Leader ->
                    Master ! {view, Group2},
                    slave(Id, Master, Leader, N+1, {view, N, [DeclaredLeader|Slaves2], Group2}, Slaves2, Group2);
                _Else ->
                    io:format("Id [~p] Different Leader [~p] From Local [~p], suspect to be stale message form new leader~n", [Id, DeclaredLeader, Leader]), % 但是stale的view可能包含新成员，这里先让它fail，观测到新成员无法从leader通信是正常现象
                    slave(Id, Master, Leader, N+1, {view, N, [DeclaredLeader|Slaves2], Group2}, Slaves, Group)
            end;
        stop ->
            ok;
        _Else ->
            io:format("HALT slave [~p]: expected N ~p, unexpected message ~p~n", [Id, N, _Else])
    end.

% delete current leader
% 可能不同process进入这里的时间不同，草了
election(Id, Master, N, Last, Slaves, [LastLeader|Group]) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            io:format("Leader is [~p, ~p] Last ~p~n", [Id, Self, Last]),
            timer:sleep(100), % 确保其他进程监听到leader挂掉，转而监听此leader
            % view对于没收到的来说，是stale的，对于已收到的，是已经见过的view
            case Last of
                {msg, NTest, BodyTmp} -> io:format("last is msg ~p~n", [{msg, NTest, BodyTmp}]);
                {view, NTest, SlavesTmp, GroupTmp} -> io:format("last is view ~p~n", [{view, NTest, SlavesTmp, GroupTmp}]) % 只有在加入时才可能更新view
            end,
            ExpectedN = N-1,
            case NTest of
                ExpectedN -> io:format("resend N as expected~n");
                _Else -> io:format("Error resend N not as expected~n")
            end,
            bcast(Id, Last, Rest), % 自己期待N，无论如何这个消息都应该是N-1的，此时确保所有client期待N
            bcast(Id, {view, N, Slaves, Group}, Rest),
            Master ! {view, Group},
            leader(Id, Master, N+1, Rest, Group, 122);
        [Leader|Rest] ->
            io:format("slave ~p monitored Last Leader ~p fail, monitoring new leader ~p~n", [Id, LastLeader, Leader]),
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, N, Last, Rest, Group) % leader挂了，不影响其他人继续期待N
    end.


% bcast(_Id, Msg, Nodes) ->
    % lists:foreach(fun(Node) -> Node ! Msg end, Nodes).

bcast(Id, Msg, Nodes) ->
    lists:foreach(fun(Node) -> Node ! Msg, crash(Id) end, Nodes).

crash(Id) ->
    % ok.
    case rand:uniform(?crashN) of
        ?crashN ->
            io:format("leader ~w crash ~n", [Id]),
            exit(no_luck);
        _E ->
            ok
    end.
