-module(gsm4).
-compile(export_all).

-define(timeout, 2000).
-define(crashN, 25).
-define(sleep, 2000).

% 目标：增加故障拉起新的

% 30 -> 13.3% 100 -> 4%
% 建议跑一个30，跑一个100
% lowest possible crashN is 25 now 16% crash every bcast


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
    % timer:sleep(500), % waiting gui up
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
            % io:format("Id=[~p] leader send msg:[~p]~n", [Id, Msg]),
            bcast(Id, {msg, N, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, N+1, Slaves, Group, Replica);
        stop ->
            ok
    % 如果优先处理加入事件，那么会出现只有1启动了worker，也就是说只有单点有历史状态（尽管这个状态我们知道是0），在启动2345的过程中，会有多次bcast，一旦1fail，状态就丢失了，失败风险很高
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
                % worker_start_slave(NextID, rand:uniform(10000), Master, Replica), % 给master发也是传给它的cast的，有可能master还没起并且
                worker_start_slave(NextID, rand:uniform(10000), self(), Replica),
                io:format("Leader ~p waiting join msg from ~p~n", [Id, NextID]),
                receive
                    % node: wrk -> master, peer -> slave(group layer), 
                    {join, Wrk, Peer} ->
                        io:format("Id [~p] add new Peer ~p Wrk ~p~n", [Id, Peer, Wrk]),
                        Slaves2 = lists:append(Slaves, [Peer]),
                        Group2 = lists:append(Group, [Wrk]),
                        bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
                        Master ! {view, Group2},
                        % timer:sleep(200),
                        leader(Id, Master, N+1, Slaves2, Group2, Replica)
                end
        end
    end.
                
            

slave(Id, Master, Leader, N, Last, Slaves, Group, Replica) ->
    receive
        {'DOWN', _Ref, process, Leader, _Reason} ->
            io:format("slave ~p detect ~p down~n", [Id, Leader]),
            election(Id, Master, N, Last, Slaves, Group, Replica);
        {mcast, Msg} ->
            % io:format("leader ~p~n", [Leader]),
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, N, Last, Slaves, Group, Replica);
        {join, Wrk, Peer} ->
            io:format("Id [~p] recv join [~p]~n", [Id, {join, Wrk, Peer}]),
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, N, Last, Slaves, Group, Replica);
        {msg, I, Msg} when I < N ->
            io:format("Id [~p] discard seen message ~p~n", [Id, Msg]),
            slave(Id, Master, Leader, N, Last, Slaves, Group, Replica); 
        {msg, N, Msg} ->
            io:format("Id [~p] recv msg [~p]~n", [Id, {msg, N, Msg}]),
            % io:format("Id=[~p] recv msg:[~p]~n", [Id, Msg]),，
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
            ok;
        _Else ->
            io:format("HALT slave [~p]: expected N ~p, unexpected message ~p~n", [Id, N, _Else])
    end.

% delete current leader
% 可能不同process进入这里的时间不同，草了
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
            bcast(Id, Last, Rest), % 自己期待N，无论如何这个消息都应该是N-1的，此时确保所有client期待N
            io:format("Id [~p] bcasting new view after last leader [~p] crash~n", [Id, LastLeader]),
            bcast(Id, {view, N, Slaves, Group}, Rest),
            Master ! {view, Group},
            leader(Id, Master, N+1, Rest, Group, Replica);
        [Leader|Rest] ->
            io:format("slave ~p monitored Last Leader ~p fail, monitoring new leader ~p~n", [Id, LastLeader, Leader]),
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, N, Last, Rest, Group, Replica) % leader挂了，不影响其他人继续期待N
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


%  =========================== CASE 1 ============================

% 一个正常的case，1的窗口是能无条件产生的
% 已经无法复现了，原因是代码改动，原先是优先创建新进程，N=100

% 1> Id 1, <0.80.0> starting gui here
% 1> spawned leader 1 <0.80.0>
% 1> Leader 1 waiting join msg from 2
% 1> spawned [2,<0.84.0>], join from <0.80.0>
% 1> Id [1] add new Peer <0.84.0> Wrk <0.83.0>
% 1> slave 2 recv first view {view,1,[<0.80.0>,<0.84.0>],[<0.78.0>,<0.83.0>]} monitoring <0.80.0>
% mark-red 2接受到的view也会回传给master，但是无法使master获得初始状态，2的state_request还在1的队列中，1要把这个request发出去，以获得其他人的初始状态回应
% 1> Id 2 master <0.83.0> is waiting for state_request
% 1> Leader 1 waiting join msg from 3
% 1> spawned [3,<0.90.0>], join from <0.80.0>
% 1> Id [1] add new Peer <0.90.0> Wrk <0.89.0>
% 1> Id [2] recv [{view,2,
%                    [<0.80.0>,<0.84.0>,<0.90.0>],
%                    [<0.78.0>,<0.83.0>,<0.89.0>]}]
% 1> slave 3 recv first view {view,2,
%                               [<0.80.0>,<0.84.0>,<0.90.0>],
%                               [<0.78.0>,<0.83.0>,<0.89.0>]} monitoring <0.80.0>
% 1> Id 2 master <0.83.0> is waiting for state_request
% 1> Id 3 master <0.89.0> is waiting for state_request
% 1> Leader 1 waiting join msg from 4
% 1> spawned [4,<0.92.0>], join from <0.80.0>
% 1> Id [1] add new Peer <0.92.0> Wrk <0.91.0>
% 1> Id [2] recv [{view,3,
%                    [<0.80.0>,<0.84.0>,<0.90.0>,<0.92.0>],
%                    [<0.78.0>,<0.83.0>,<0.89.0>,<0.91.0>]}]
% 1> Id [3] recv [{view,3,
%                    [<0.80.0>,<0.84.0>,<0.90.0>,<0.92.0>],
%                    [<0.78.0>,<0.83.0>,<0.89.0>,<0.91.0>]}]
% 1> slave 4 recv first view {view,3,
%                               [<0.80.0>,<0.84.0>,<0.90.0>,<0.92.0>],
%                               [<0.78.0>,<0.83.0>,<0.89.0>,<0.91.0>]} monitoring <0.80.0>
% 1> Id 2 master <0.83.0> is waiting for state_request
% 1> Id 3 master <0.89.0> is waiting for state_request
% 1> Id 4 master <0.91.0> is waiting for state_request
% 1> Leader 1 waiting join msg from 5
% 1> spawned [5,<0.94.0>], join from <0.80.0>
% 1> Id [1] add new Peer <0.94.0> Wrk <0.93.0>
% 1> Id [2] recv [{view,4,
%                    [<0.80.0>,<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>],
%                    [<0.78.0>,<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>]}]
% 1> Id [3] recv [{view,4,
%                    [<0.80.0>,<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>],
%                    [<0.78.0>,<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>]}]
% 1> Id [4] recv [{view,4,
%                    [<0.80.0>,<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>],
%                    [<0.78.0>,<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>]}]
% 1> slave 5 recv first view {view,4,
%                               [<0.80.0>,<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>],
%                               [<0.78.0>,<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>]} monitoring <0.80.0>
% mark-red 所有人都在等
% 1> Id 2 master <0.83.0> is waiting for state_request
% 1> Id 3 master <0.89.0> is waiting for state_request
% 1> Id 4 master <0.91.0> is waiting for state_request
% 1> Id 5 master <0.93.0> is waiting for state_request
% mark-red 1开始处理堆积的state_request
% 1> Id [3] recv msg [{msg,5,{state_request,#Ref<0.205385773.2086404100.62174>}}]
% 1> Id [4] recv msg [{msg,5,{state_request,#Ref<0.205385773.2086404100.62174>}}]
% 1> Id [5] recv msg [{msg,5,{state_request,#Ref<0.205385773.2086404100.62174>}}]
% 1> Id [2] recv msg [{msg,5,{state_request,#Ref<0.205385773.2086404100.62174>}}]
% mark-red 这里日志的顺序不一定对
% 1> leader 1 crash
% 1> Id [3] recv msg [{msg,6,{state_request,#Ref<0.205385773.2086404100.62202>}}]
% 1> Id [4] recv msg [{msg,6,{state_request,#Ref<0.205385773.2086404100.62202>}}]
% 1> Id [5] recv msg [{msg,6,{state_request,#Ref<0.205385773.2086404100.62202>}}]
% 1> Id 3 master <0.89.0> is waiting for state_request
% 1> Id 4 master <0.91.0> is waiting for state_request
% 1> Id 5 master <0.93.0> is waiting for state_request
% mark-red 2收到多次state_request请求，只需要一次就够了，下一步等待state消息作为初始颜色
% 1> Id [2] recv msg [{msg,6,{state_request,#Ref<0.205385773.2086404100.62202>}}]
% mark-red 这里在收到两次state_request才输出的原因，是rcvd这条命令在master进程打的
% 1> Id 2 master <0.83.0> rcvd state_request
% 1> Id [3] recv msg [{msg,7,{state_request,#Ref<0.205385773.2086404100.62233>}}]
% 1> Id [4] recv msg [{msg,7,{state_request,#Ref<0.205385773.2086404100.62233>}}]
% 1> Id [5] recv msg [{msg,7,{state_request,#Ref<0.205385773.2086404100.62233>}}]
% mark-red 逐渐3, 4, 5也收到state_request
% 1> Id 3 master <0.89.0> rcvd state_request
% 1> Id 4 master <0.91.0> is waiting for state_request
% 1> Id 5 master <0.93.0> is waiting for state_request
% 1> Id [2] recv msg [{msg,7,{state_request,#Ref<0.205385773.2086404100.62233>}}]
% 1> Id [3] recv msg [{msg,8,{state_request,#Ref<0.205385773.2086404100.62253>}}]
% 1> Id [4] recv msg [{msg,8,{state_request,#Ref<0.205385773.2086404100.62253>}}]
% 1> Id [5] recv msg [{msg,8,{state_request,#Ref<0.205385773.2086404100.62253>}}]
% 1> Id 4 master <0.91.0> rcvd state_request
% 1> Id 5 master <0.93.0> is waiting for state_request
% 1> Id [2] recv msg [{msg,8,{state_request,#Ref<0.205385773.2086404100.62253>}}]
% mark-red 1 receive 好几次 state_request，自然应该回应好几次 state，看下面的日志，在发第二个state时挂掉，2,3已收到
% 1> Id [3] recv msg [{msg,9,{state,#Ref<0.205385773.2086404100.62174>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,9,{state,#Ref<0.205385773.2086404100.62174>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,9,{state,#Ref<0.205385773.2086404100.62174>,{0,0,0}}}]
% 1> Id 5 master <0.93.0> rcvd state_request
% 1> Id [2] recv msg [{msg,9,{state,#Ref<0.205385773.2086404100.62174>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,10,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% mark-red 3 4 5检测到1挂掉，2称为leader
% 1> slave 4 detect <0.80.0> down
% 1> slave 5 detect <0.80.0> down
% 1> Id [2] recv msg [{msg,10,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% mark-red: 2, 3收到初始state，成功启动gui、worker
% 1> Id 2, <0.84.0> starting gui here
% 1> slave 3 detect <0.80.0> down
% 1> Id 3, <0.90.0> starting gui here
% 1> slave 2 detect <0.80.0> down
% 1> slave 4 monitored Last Leader <0.78.0> fail, monitoring new leader <0.84.0>
% 1> slave 5 monitored Last Leader <0.78.0> fail, monitoring new leader <0.84.0>
% 1> slave 3 monitored Last Leader <0.78.0> fail, monitoring new leader <0.84.0>
% 1> Leader is [2, <0.84.0>] Last {msg,10,
%                                  {state,#Ref<0.205385773.2086404100.62202>,
%                                      {0,0,0}}}
% mark-red: resend message，可以发现1在发送state的过程挂掉了
% 1> last message is msg {msg,10,
%                          {state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}
% 1> Id [3] discard seen message {state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}
% mark-red: 发完上次剩下的消息
% 1> Id [2] bcasting new view after last leader [<0.78.0>] crash
% 1> Id [4] recv msg [{msg,10,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,10,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% 1> Id [3] recv [{view,11,
%                    [<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>],
%                    [<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>]}]
% 1> Id [4] recv [{view,11,
%                    [<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>],
%                    [<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>]}]
% 1> Id [5] recv [{view,11,
%                    [<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>],
%                    [<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>]}]
% 1> Leader 2 waiting join msg from 6
% 1> spawned [6,<0.101.0>], join from <0.84.0>
% 1> Id [2] add new Peer <0.101.0> Wrk <0.100.0>
% 1> Id [3] recv [{view,12,
%                    [<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>,<0.101.0>],
%                    [<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>,<0.100.0>]}]
% 1> Id [4] recv [{view,12,
%                    [<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>,<0.101.0>],
%                    [<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>,<0.100.0>]}]
% 1> Id [5] recv [{view,12,
%                    [<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>,<0.101.0>],
%                    [<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>,<0.100.0>]}]
% 1> slave 6 recv first view {view,12,
%                               [<0.84.0>,<0.90.0>,<0.92.0>,<0.94.0>,<0.101.0>],
%                               [<0.83.0>,<0.89.0>,<0.91.0>,<0.93.0>,<0.100.0>]} monitoring <0.84.0>
% 1> Id 6 master <0.100.0> is waiting for state_request
% 1> Id [4] recv msg [{msg,13,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,13,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,13,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,13,{state,#Ref<0.205385773.2086404100.62202>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,14,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,14,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,14,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,14,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,15,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id 6 master <0.100.0> is waiting for state_request
% 1> Id [5] recv msg [{msg,15,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% mark-red master线程稍后打出了日志
% 1> Id 4, <0.92.0> starting gui here
% 1> Id [3] recv msg [{msg,15,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,15,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,16,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id 6 master <0.100.0> is waiting for state_request
% 1> Id [5] recv msg [{msg,16,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id 5, <0.94.0> starting gui here
% 1> Id [3] recv msg [{msg,16,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,16,{state,#Ref<0.205385773.2086404100.62233>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,17,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id 6 master <0.100.0> is waiting for state_request
% 1> Id [5] recv msg [{msg,17,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,17,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,17,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,18,{state_request,#Ref<0.205385773.2086404100.62335>}}]
% 1> Id 6 master <0.100.0> is waiting for state_request
% 1> Id [5] recv msg [{msg,18,{state_request,#Ref<0.205385773.2086404100.62335>}}]
% 1> Id [3] recv msg [{msg,18,{state_request,#Ref<0.205385773.2086404100.62335>}}]
% 1> Id [6] recv msg [{msg,18,{state_request,#Ref<0.205385773.2086404100.62335>}}]
% 1> Id [4] recv msg [{msg,19,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id 6 master <0.100.0> is waiting for state_request
% 1> Id [5] recv msg [{msg,19,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,19,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,19,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id 6 master <0.100.0> rcvd state_request
% 1> Id [4] recv msg [{msg,20,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,20,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,20,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,20,{state,#Ref<0.205385773.2086404100.62253>,{0,0,0}}}]
% mark-red 最后一个线程也成功启动gui、worker
% 1> Id 6, <0.101.0> starting gui here
% 1> Id [4] recv msg [{msg,21,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,21,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,21,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,21,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,22,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,22,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,22,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,22,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [4] recv msg [{msg,23,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [5] recv msg [{msg,23,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,23,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% 1> Id [6] recv msg [{msg,23,{state,#Ref<0.205385773.2086404100.62335>,{0,0,0}}}]
% mark-red 正常通信开始
% 1> Id [5] recv msg [{msg,24,{change,9}}]
% 1> Id [6] recv msg [{msg,24,{change,9}}]
% 1> Id [3] recv msg [{msg,24,{change,9}}]
% 1> Id [4] recv msg [{msg,24,{change,9}}]
% 1> Id [5] recv msg [{msg,25,{change,14}}]
% 1> Id [6] recv msg [{msg,25,{change,14}}]
% 1> Id [3] recv msg [{msg,25,{change,14}}]
% 1> Id [4] recv msg [{msg,25,{change,14}}]
% 1> Id [4] recv msg [{msg,26,{change,17}}]
% 1> Id [5] recv msg [{msg,26,{change,17}}]
% 1> Id [3] recv msg [{msg,26,{change,17}}]





% =========================== CASE 2 ===========================
% crashN = 20

% 1> Id 1, <0.80.0> starting gui here
% 1> spawned leader 1 <0.80.0>
% 1> Leader 1 waiting join msg from 2
% 1> spawned [2,<0.88.0>], join from <0.80.0>
% 1> Id [1] add new Peer <0.88.0> Wrk <0.87.0>
% 1> slave 2 recv first view {view,1,[<0.80.0>,<0.88.0>],[<0.78.0>,<0.87.0>]} monitoring <0.80.0>
% 1> Id 2 master <0.87.0> is waiting for state_request
% 1> leader 1 crash
% 1> Id [2] recv msg [{msg,2,{change,2}}]
% 1> Id [2] recv msg [{msg,3,{state_request,#Ref<0.474017969.215482372.121933>}}]
% 1> Id 2 master <0.87.0> is waiting for state_request
% 1> slave 2 detect <0.80.0> down
% mark-red: process 2 received state_request (sent by himself), but process 1 (leader) dies before sending his init state, in this case the program cannot continue
% 1> Id 2 master <0.87.0> rcvd state_request
% 1> Leader is [2, <0.88.0>] Last {msg,3,
%                                  {state_request,
%                                      #Ref<0.474017969.215482372.121933>}}
% 1> last message is msg {msg,3,{state_request,#Ref<0.474017969.215482372.121933>}}
% 1> Id [2] bcasting new view after last leader [<0.78.0>] crash
% 1> Leader 2 waiting join msg from 3
% 1> spawned [3,<0.91.0>], join from <0.88.0>
% 1> Id [2] add new Peer <0.91.0> Wrk <0.90.0>
% 1> slave 3 recv first view {view,5,[<0.88.0>,<0.91.0>],[<0.87.0>,<0.90.0>]} monitoring <0.88.0>
% 1> Id 3 master <0.90.0> is waiting for state_request
% 1> Id [3] recv msg [{msg,6,{state_request,#Ref<0.474017969.215482372.121969>}}]
% 1> Id 3 master <0.90.0> rcvd state_request
% 1> Leader 2 waiting join msg from 4
% 1> spawned [4,<0.93.0>], join from <0.88.0>
% 1> Id [2] add new Peer <0.93.0> Wrk <0.92.0>
% 1> Id [3] recv [{view,7,
%                    [<0.88.0>,<0.91.0>,<0.93.0>],
%                    [<0.87.0>,<0.90.0>,<0.92.0>]}]
% ...................