-module(gsm3).
-compile(export_all).

-define(timeout, 2000).
-define(crashN, 40).

% 增加了发送后随机退出，由于可能只发给部分client，会导致最终不同步
% 能够观察到，没有问题
% 没有观察到进程卡死、进程未启动等问题
% 基于这个继续做gsm3

% 目标，增加N Last，故障恢复正常

start(Id, Rnd) ->
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Rnd, Self) end)}.

init(Id, Rnd, Master) ->
    rand:seed(exsss, Rnd),
    io:format("spawned leader ~p ~p~n", [Id, self()]),
    leader(Id, Master, 1, [], [Master]).

start(Id, Grp, Rnd) ->
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Rnd, Grp, Self) end)}.

init(Id, Rnd, Grp, Master) ->
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

leader(Id, Master, N, Slaves, Group) ->
    receive
        {mcast, Msg} ->
            % io:format("Id=[~p] leader send msg:[~p]~n", [Id, Msg]),
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
            leader(Id, Master, N+1, Rest, Group);
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

% % case study

% =================== CASE 1 ==========================

% 现象，最后只剩5

% 1> spawned leader 1 <0.79.0>
% 1> spawned 2 <0.87.0>
% 1> slave 2 recv first view {view,1,[<0.79.0>,<0.87.0>],[<0.78.0>,<0.86.0>]} monitoring <0.79.0>
% % mark-red 从2的master来，广播一个state_request
% 1> Id [2] recv msg [{msg,2,{state_request,#Ref<0.1378067103.4206624770.110068>}}] 
% % mark-red 理论上所有人（除了他自己）都会回复state，只需要一个
% 1> Id [2] recv msg [{msg,3,{state,#Ref<0.1378067103.4206624770.110068>,{0,0,0}}}] 
% 1> spawned 3 <0.91.0>
% % mark-red 3从2接入gorup
% 1> Id [2] recv join [{join,<0.90.0>,<0.91.0>}]
% 1> Id [2] recv [{view,4,
%                    [<0.79.0>,<0.87.0>,<0.91.0>],
%                    [<0.78.0>,<0.86.0>,<0.90.0>]}]
% 1> slave 3 recv first view {view,4,
%                               [<0.79.0>,<0.87.0>,<0.91.0>],
%                               [<0.78.0>,<0.86.0>,<0.90.0>]} monitoring <0.79.0>
% 1> Id [2] recv msg [{msg,5,{state_request,#Ref<0.1378067103.4206624770.110104>}}]
% 1> Id [3] recv msg [{msg,5,{state_request,#Ref<0.1378067103.4206624770.110104>}}]
% % mark-red 来自2,3的state
% 1> Id [2] recv msg [{msg,6,{state,#Ref<0.1378067103.4206624770.110104>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,6,{state,#Ref<0.1378067103.4206624770.110104>,{0,0,0}}}]
% 1> Id [2] recv msg [{msg,7,{state,#Ref<0.1378067103.4206624770.110104>,{0,0,0}}}]
% 1> Id [3] recv msg [{msg,7,{state,#Ref<0.1378067103.4206624770.110104>,{0,0,0}}}]
% 1> spawned 4 <0.95.0>
% 1> Id [3] recv msg [{msg,8,{change,10}}]
% 1> Id [2] recv msg [{msg,8,{change,10}}]
% 1> Id [3] recv join [{join,<0.94.0>,<0.95.0>}]
% 1> leader 1 crash
% 1> Id [2] recv [{view,9,
%                    [<0.79.0>,<0.87.0>,<0.91.0>,<0.95.0>],
%                    [<0.78.0>,<0.86.0>,<0.90.0>,<0.94.0>]}]
% 1> Id [3] recv [{view,9,
%                    [<0.79.0>,<0.87.0>,<0.91.0>,<0.95.0>],
%                    [<0.78.0>,<0.86.0>,<0.90.0>,<0.94.0>]}]
% 1> slave 2 detect <0.79.0> down
% 1> slave 3 detect <0.79.0> down
% % mark-red 未发送完毕的消息是一个view消息，2 3收到了，新加入的4没有收到
% 1> Leader is [2, <0.87.0>] Last {view,9, 
%                                    [<0.79.0>,<0.87.0>,<0.91.0>,<0.95.0>],
%                                    [<0.78.0>,<0.86.0>,<0.90.0>,<0.94.0>]}
% 1> slave 3 monitored Last Leader <0.78.0> fail, monitoring new leader <0.87.0>
% 1> last is view {view,9,
%                    [<0.79.0>,<0.87.0>,<0.91.0>,<0.95.0>],
%                    [<0.78.0>,<0.86.0>,<0.90.0>,<0.94.0>]}
% 1> resend N as expected
% % mark-red 3 丢弃已经收到的msg
% 1> Id [3] rcvd seen view [N=9] leader <0.79.0> slaves [<0.87.0>,<0.91.0>,
%                                                     <0.95.0>] group [<0.78.0>,
%                                                                      <0.86.0>,
%                                                                      <0.90.0>,
%                                                                      <0.94.0>], discard
% % mark-red 4收到这条新消息
% 1> slave 4 recv first view {view,9,
%                               [<0.79.0>,<0.87.0>,<0.91.0>,<0.95.0>],
%                               [<0.78.0>,<0.86.0>,<0.90.0>,<0.94.0>]} monitoring <0.79.0>
% 1> Id [3] recv [{view,10,
%                    [<0.87.0>,<0.91.0>,<0.95.0>],
%                    [<0.86.0>,<0.90.0>,<0.94.0>]}]
% 1> Id [4] recv [{view,10,
%                    [<0.87.0>,<0.91.0>,<0.95.0>],
%                    [<0.86.0>,<0.90.0>,<0.94.0>]}]
% 1> Id [4] Different Leader [<0.87.0>] From Local [<0.79.0>], suspect to be stale message form new leader
% 1> slave 4 detect <0.79.0> down
% 1> slave 4 monitored Last Leader <0.78.0> fail, monitoring new leader <0.87.0>
% 1> Id [4] recv msg [{msg,11,{state_request,#Ref<0.1378067103.4206624769.109816>}}]
% 1> Id [3] recv msg [{msg,11,{state_request,#Ref<0.1378067103.4206624769.109816>}}]
% 1> leader 2 crash
% % mark-red 最后的消息被 3 4 收到
% 1> Id [4] recv msg [{msg,12,
%                       {state,#Ref<0.1378067103.4206624769.109816>,{0,0,10}}}]
% 1> Id [3] recv msg [{msg,12,
%                       {state,#Ref<0.1378067103.4206624769.109816>,{0,0,10}}}]
% 1> slave 4 detect <0.87.0> down
% 1> slave 3 detect <0.87.0> down
% 1> slave 4 monitored Last Leader <0.86.0> fail, monitoring new leader <0.91.0>
% % mark-red 3 重发消息
% 1> Leader is [3, <0.91.0>] Last {msg,12,
%                                  {state,#Ref<0.1378067103.4206624769.109816>,
%                                      {0,0,10}}}
% 1> spawned 5 <0.101.0>
% 1> Id [4] recv join [{join,<0.100.0>,<0.101.0>}]
% 1> last is msg {msg,12,{state,#Ref<0.1378067103.4206624769.109816>,{0,0,10}}}
% 1> resend N as expected
% 1> leader 3 crash
% % mark-red 4 丢弃seen消息
% 1> Id [4] discard seen message {state,#Ref<0.1378067103.4206624769.109816>,
%                                    {0,0,10}}
% 1> Id [4] recv [{view,13,[<0.91.0>,<0.95.0>],[<0.90.0>,<0.94.0>]}]
% 1> Id [4] recv [{view,14,
%                    [<0.91.0>,<0.95.0>,<0.101.0>],
%                    [<0.90.0>,<0.94.0>,<0.100.0>]}]
% 1> slave 4 detect <0.91.0> down
% 1> Leader is [4, <0.95.0>] Last {view,14,
%                                    [<0.91.0>,<0.95.0>,<0.101.0>],
%                                    [<0.90.0>,<0.94.0>,<0.100.0>]}
% 1> last is view {view,14,
%                    [<0.91.0>,<0.95.0>,<0.101.0>],
%                    [<0.90.0>,<0.94.0>,<0.100.0>]}
% 1> resend N as expected
% 1> slave 5 recv first view {view,14,
%                               [<0.91.0>,<0.95.0>,<0.101.0>],
%                               [<0.90.0>,<0.94.0>,<0.100.0>]} monitoring <0.91.0>
% % mark-red process 5 收到第二个view，但是还没收到process 3挂掉的消息
% 1> Id [5] recv [{view,15,[<0.95.0>,<0.101.0>],[<0.94.0>,<0.100.0>]}]
% % mark-red process 5 收到来自4的leader宣称，自己的leader没发现挂掉，抛弃消息
% 1> Id [5] Different Leader [<0.95.0>] From Local [<0.91.0>], suspect to be stale message form new leader
% % mark-red 发现自己的leader挂掉了
% 1> slave 5 detect <0.91.0> down
% 1> slave 5 monitored Last Leader <0.90.0> fail, monitoring new leader <0.95.0>
% 1> Id [5] recv msg [{msg,16,{state_request,#Ref<0.1378067103.4206624769.109847>}}]
% 1> Id [5] recv msg [{msg,17,
%                       {state,#Ref<0.1378067103.4206624769.109847>,{0,0,10}}}]
% 1> Id [5] recv msg [{msg,18,{change,6}}]
% 1> Id [5] recv msg [{msg,19,{change,14}}]
% 1> Id [5] recv msg [{msg,20,{change,19}}]
% 1> Id [5] recv msg [{msg,21,{change,10}}]
% 1> Id [5] recv msg [{msg,22,{change,4}}]
% 1> Id [5] recv msg [{msg,23,{change,17}}]
% 1> Id [5] recv msg [{msg,24,{change,13}}]
% 1> Id [5] recv msg [{msg,25,{change,2}}]
% 1> Id [5] recv msg [{msg,26,{change,20}}]
% 1> Id [5] recv msg [{msg,27,{change,8}}]
% 1> Id [5] recv msg [{msg,28,{change,1}}]
% 1> Id [5] recv msg [{msg,29,{change,7}}]
% 1> Id [5] recv msg [{msg,30,{change,8}}]
% 1> Id [5] recv msg [{msg,31,{change,7}}]
% 1> Id [5] recv msg [{msg,32,{change,9}}]
% 1> Id [5] recv msg [{msg,33,{change,20}}]
% 1> Id [5] recv msg [{msg,34,{change,6}}]
% 1> leader 4 crash
% 1> Id [5] recv msg [{msg,35,{change,3}}]
% 1> slave 5 detect <0.95.0> down
% 1> Leader is [5, <0.101.0>] Last {msg,35,{change,3}}
% 1> last is msg {msg,35,{change,3}}
% 1> resend N as expected



% =================== CASE 2 ==========================

% what I see: process 1 dies soon, then process 2, 3 dies together, process 4 does not die for a long time