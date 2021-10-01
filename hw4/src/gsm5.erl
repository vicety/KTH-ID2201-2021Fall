-module(gsm5).
-compile(export_all).

-define(timeout, 2000).
-define(crashN, 80).
-define(noresponseN, 10).
-define(sleep, 2000).
-define(retry, 2).

% 新增（相对于gsm4）：client fail场景

% nocrashN, noresponseN=10 无问题 4/10^2 = 0.04 node will fail in every bcast
% nocrashN, noresponseN=5 有时小于5个，但总能恢复
% nocrashN, noresponseN=6 还可以
% crashN=80, noresposeN=10 无问题，0.04 slave fail every bcast, 0.05 leader fail every bcast, 0.09 node fail every bcast


% 假设访问不通等于挂掉，不会后来又恢复
% 那么可以bcast(发消息) + bcast(新view，可丢失) + 本地更新view，等待循环拉起
% 下面说明为什么第二个bcast可丢失
% 因为其他进程可以发现，如果是次leader挂掉，其他进程可以monitor发现；如果是其他进程挂掉，下次请求时也能发现

% 其实可以完全不处理失败，但是这样迟早leader以外全部节点都要挂掉，所以偶尔也要处理

start(Id, Rnd, Replica) ->
    Self = self(),
    register(next_id, spawn(fun() -> next_id(2) end)),
    % timer:sleep(200), % waiting for worker running
    {ok, spawn_link(fun() -> init(Id, Rnd, Self, Replica) end)}.

next_id(Next) ->
    receive
        {get, Remote} ->
            Remote ! {next_id, Next},
            next_id(Next+1)
    end.

init(Id, Rnd, Master, Replica) ->
    rand:seed(exsss, Rnd),
    io:format("spawned leader ~p ~p~n", [Id, self()]),
    leader(Id, Master, 1, [], [Master], Replica).

worker_start_slave(Id, Rnd, Peer, Replica) ->
    spawn(fun() -> 
        {ok, Cast} = start_slave(Id, Peer, Rnd, Replica),
        {ok, Color} = worker:join(Id, Cast),
        worker:init_cont(Id, Rnd, Cast, Color, ?sleep)
    end).

start_slave(Id, Grp, Rnd, Replica) ->
    Self = self(),
    {ok, spawn_link(fun() -> init_slave(Id, Rnd, Grp, Self, Replica) end)}.

init_slave(Id, Rnd, Grp, Master, Replica) ->
    rand:seed(exsss, Rnd),
    Self = self(),
    io:format("spawned [~p,~p], join from ~p~n", [Id, self(), Grp]),
    Grp ! {join, Master, Self},
    receive
        % slaves(first is leader), masters 
        {view, N, [Leader|Slaves], Group} ->
            % Leader ! ack,
            io:format("slave ~p recv first view ~p monitoring ~p~n", [Id, {view, N, [Leader|Slaves], Group}, Leader]),
            erlang:monitor(process, Leader),
            Master ! {view, Group},
            slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group}, Slaves, Group, Replica)
    after ?timeout ->
        Master ! {error, "no reply from leader"}
    end.

% N: seq number to be sent in this loop
% Slaves: group level, do not conatin self
% Group: application level, first is self, than slavess
leader(Id, Master, N, Slaves, Group, Replica) ->
    receive
        {mcast, Msg} ->
            case bcast(Id, {msg, N, Msg}, Slaves) of
                ok ->
                    Master ! Msg,
                    leader(Id, Master, N+1, Slaves, Group, Replica);
                {error, FailedNodes} ->
                    io:format("Id ~p mcast partial failure [~p]~n", [Id, FailedNodes]),
                    Master ! Msg,
                    {Slaves1, Group1} = remaining_nodes(FailedNodes, Slaves, Group),
                    bcast(Id, {view, N+1, [self()|Slaves1], Group1}, Slaves1), % no need to handle failure here
                    leader(Id, Master, N+2, Slaves1, Group1, Replica)
            end;
        stop ->
            ok
    % 如果优先处理加入事件（而不是像这样伪轮询），那么会出现只有1启动了worker，也就是说只有单点有历史状态（尽管这个状态我们知道是0），在启动2345的过程中，会有多次bcast，一旦1fail，状态就丢失了，失败风险很高
    after 200 ->
        case length(Group) of
            Replica ->
                leader(Id, Master, N, Slaves, Group, Replica);
            _Other ->
                [Master|_] = Group,
                next_id ! {get, self()},
                receive
                    {next_id, NextID} ->
                        ok
                end,
                worker_start_slave(NextID, rand:uniform(10000), self(), Replica),
                io:format("Leader ~p waiting join msg from ~p~n", [Id, NextID]),
                receive
                    % node: wrk -> master, peer -> slave(group layer), 
                    {join, Wrk, Peer} ->
                        io:format("Id [~p] add new Peer ~p Wrk ~p~n", [Id, Peer, Wrk]),
                        Slaves2 = lists:append(Slaves, [Peer]),
                        Group2 = lists:append(Group, [Wrk]),
                        case bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2) of
                            ok ->
                                Master ! {view, Group2},
                                leader(Id, Master, N+1, Slaves2, Group2, Replica);
                            {error, FailedNodes} ->
                                io:format("Id ~p join new view bcast partial failure [~p]~n", [Id, FailedNodes]),
                                {Slaves3, Group3} = remaining_nodes(FailedNodes, Slaves2, Group2),
                                Master ! {view, Group3},
                                bcast(Id, {view, N+1, [self()|Slaves3], Group3}, Slaves3), % no need to handle failure here
                                leader(Id, Master, N+2, Slaves3, Group3, Replica)
                        end 
                end
        end
    end.
                
            

slave(Id, Master, Leader, N, Last, Slaves, Group, Replica) ->
    receive
        {'DOWN', _Ref, process, Leader, _Reason} ->
            io:format("slave ~p detect ~p down~n", [Id, Leader]),
            election(Id, Master, N, Last, Slaves, Group, Replica);
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, N, Last, Slaves, Group, Replica);
        {join, Wrk, Peer} ->
            io:format("Id [~p] recv join [~p]~n", [Id, {join, Wrk, Peer}]),
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, N, Last, Slaves, Group, Replica);
        {msg, I, Msg} when I < N ->
            io:format("Id [~p] discard seen message N=[~p] ~p~n", [Id, I, Msg]),
            slave(Id, Master, Leader, N, Last, Slaves, Group, Replica); 
        {msg, N, Msg} ->
            io:format("Id [~p] recv msg [~p]~n", [Id, {msg, N, Msg}]),
            Master ! Msg,
            slave(Id, Master, Leader, N+1, {msg, N, Msg}, Slaves, Group, Replica);
        {view, I, [DeclaredLeader|Slaves2], Group2} when I < N ->
            io:format("Id [~p] rcvd seen view [N=~p] leader ~p slaves ~p group ~p, discard~n", [Id, I, DeclaredLeader, Slaves2, Group2]),
            slave(Id, Master, Leader, N, Last, Slaves, Group, Replica); 
        {view, N, [DeclaredLeader|Slaves2], Group2} ->
            io:format("Id [~p] recv [~p]~n", [Id, {view, N, [DeclaredLeader|Slaves2], Group2}]),
            case DeclaredLeader of
                Leader ->
                    Master ! {view, Group2},
                    slave(Id, Master, Leader, N+1, {view, N, [DeclaredLeader|Slaves2], Group2}, Slaves2, Group2, Replica);
                _Else ->
                    io:format("Id [~p] Different Leader [~p] From Local [~p], suspect to be stale message form new leader~n", [Id, DeclaredLeader, Leader]), % 但是stale的view可能包含新成员，这里先让它fail，观测到新成员无法从leader通信是正常现象
                    slave(Id, Master, Leader, N+1, {view, N, [DeclaredLeader|Slaves2], Group2}, Slaves, Group, Replica)
            end;
        stop ->
            io:format("killing ~p~n", [Id]),
            Master ! stop,
            ok;
        _Else ->
            io:format("HALT slave [~p]: expected N ~p, unexpected message ~p~n", [Id, N, _Else])
    end.

election(Id, Master, N, Last, Slaves, [LastLeader|Group], Replica) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            io:format("Leader is [~p, ~p] Last ~p~n", [Id, Self, Last]),
            timer:sleep(100), % 确保其他进程监听到leader挂掉，转而监听此leader
            % view对于没收到的来说，是stale的，对于已收到的，是已经见过的view
            case Last of
                {msg, NTest, BodyTmp} -> io:format("last message is msg ~p~n", [{msg, NTest, BodyTmp}]);
                {view, NTest, SlavesTmp, GroupTmp} -> io:format("last message is view ~p~n", [{view, NTest, SlavesTmp, GroupTmp}]) % 只有在加入时才可能更新view
            end,
            ExpectedN = N-1,
            case NTest of
                % ExpectedN -> io:format("resend N as expected~n");
                ExpectedN -> ok;
                _Else -> io:format("Error resend N not as expected~n")
            end,
            %  {Slaves3, Group3} = remaining_nodes(FailedNodes, Slaves2, Group2),
            case bcast(Id, Last, Rest) of % 自己期待N，无论如何这个消息都应该是N-1的，此时确保所有client期待N
                ok ->
                    io:format("Id [~p] bcasting new view after last leader [~p] crash~n", [Id, LastLeader]),
                    bcast(Id, {view, N, Slaves, Group}, Rest),
                    Master ! {view, Group},
                    leader(Id, Master, N+1, Rest, Group, Replica);
                {error, FailedNodes} ->
                    io:format("Id ~p elction bcast last msg partial failure [~p]~n", [Id, FailedNodes]),
                    {Slaves1, Group1} = remaining_nodes(FailedNodes, Rest, Group),
                    bcast(Id, {view, N, Slaves1, Group1}, Rest),
                    Master ! {view, Group1},
                    leader(Id, Master, N+1, Slaves1, Group1, Replica)
            end;
        [Leader|Rest] ->
            io:format("slave ~p monitored Last Leader ~p fail, monitoring new leader ~p~n", [Id, LastLeader, Leader]),
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, N, Last, Rest, Group, Replica) % leader挂了，不影响其他人继续期待N
    end.

remaining_nodes(FailedNodes, Slaves, Group) ->
    Zipped = lists:zip([self()|Slaves], Group),
    Zipped1 = lists:foldl(fun(Ele, Acc) ->
        lists:keydelete(Ele, 1, Acc)
    end, Zipped, FailedNodes),
    Self = self(),
    {[Self|Slaves1], Group1} = lists:unzip(Zipped1),
    {Slaves1, Group1}.

% return [remainingSlaves, remainingGroupWithoutSelf]
recover(Id, Slaves, Group, DownSlaves) ->
    io:format("~p recover here~n", [Id]),
    [_|GroupWithoutLeader] = Group,
    Nodes = lists:zip(Slaves, GroupWithoutLeader),
    NodesRemain = lists:foldl(fun(DownSlave, Acc) ->
        lists:keydelete(DownSlave, 1, Acc)
    end, Nodes, DownSlaves),
    % 这里bcast出去的消息不用重试，因为重试会导致recover前的消息丢失，而这里的view消息不需要重试的理由是其他节点如果成为leader可以自己试出来，信息不会丢失
    % 如果这里第一个消息都没发出去挂了，新leader等于重新开始，要是能和挂掉的节点联通，那也ok。
    % 如果只成功了一部分怎么办，将失败的计入，尝试剩下的，不断尝试，直到只剩自己，然后开始拉起
    bcast_until_success(Id, NodesRemain).

% return nodesRemain, DownCnt
bcast_until_success(_Id, []) ->
    [];
bcast_until_success(Id, Remaining) ->
    {RemainingSlaves, RemainingApps} = lists:unzip(Remaining),
    case bcast(Id, {view_not_safe, [self()|RemainingSlaves], [self()|RemainingApps]}, RemainingSlaves) of
        ok ->
            Remaining;
        {error, FailedSlaves} ->
            Remaining1 = lists:foreach(fun(FSlave) -> lists:keydelete(FSlave, 1, Remaining) end, FailedSlaves),
            bcast_until_success(Id, Remaining1)
    end.


bcast(Id, Msg, Nodes) ->
    % 如果只发出去一部分，没发成的会被干掉，看不到不一致
    % io:format("nodes: ~p~n", [Nodes]),
    FailedNodes = lists:foldl(fun(Node, FailNodes) -> 
        case reliable_send(Id, Node, Msg) of
            ok -> FailNodes1 = FailNodes;
            error -> FailNodes1 = FailNodes ++ [Node]
        end,
        crash(Id),
        FailNodes1 
    end, [], Nodes),
    case length(FailedNodes) of
        0 -> ok;
        _Else -> {error, FailedNodes} % actually failed slaves
    end.

crash(Id) ->
    case rand:uniform(?crashN) of
        ?crashN ->
            io:format("leader ~w crash ~n", [Id]),
            exit(no_luck);
        _E ->
            ok
    end.

reliable_send(Id, Dst, Msg) ->
    reliable_send(Id, Dst, Msg, 0).

% involve chance that a resend is not ok, then declare this node down, update view
reliable_send(Id, Dst, _Msg, Resend) when Resend == ?retry ->
    Dst ! stop,
    io:format("[~p] retried maximum times~n", [Id]),
    timer:sleep(50), % make sure stop is delivered
    error;

% mimic msg lost with 1 resend, mimic client down with maximum(?retry) resend
reliable_send(Id, Dst, Msg, Resend) ->
    % Dst ! Msg,
    case rand:uniform(?noresponseN) of
        ?noresponseN ->
            io:format("Id ~p msg [~p] sent to [~p] fail, retry ~p~n", [Id, Msg, Dst, Resend]),
            reliable_send(Id, Dst, Msg, Resend+1);
        _Else ->
            Dst ! Msg,
            ok
    end.