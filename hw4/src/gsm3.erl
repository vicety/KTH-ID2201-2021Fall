-module(gsm3).
-compile(export_all).

% -define(timeout, 2000).
% -define(crashN, 80).

% % 增加了发送后随机退出，由于可能只发给部分client，会导致最终不同步
% % 能够观察到，没有问题
% % 没有观察到进程卡死、进程未启动等问题
% % 基于这个继续做gsm3

% start(Id) ->
%     Rnd = rand:uniform(1000),
%     Self = self(),
%     {ok, spawn_link(fun() -> init(Id, Rnd, Self) end)}.

% init(Id, Rnd, Master) ->
%     rand:seed(exsss, Rnd),
%     leader(Id, Master, [], [Master]).

% start(Id, Grp) ->
%     Rnd = rand:uniform(1000),
%     Self = self(),
%     {ok, spawn_link(fun() -> init(Id, Rnd, Grp, Self) end)}.

% init(Id, Rnd, Grp, Master) ->
%     rand:seed(exsss, Rnd),
%     Self = self(),
%     Grp ! {join, Master, Self},
%     receive
%         % slaves(first is leader), masters 
%         {view, [Leader|Slaves], Group} ->
%             erlang:monitor(process, Leader),
%             Master ! {view, Group}, % master not care
%             slave(Id, Master, Leader, Slaves, Group)
%     after ?timeout ->
%         Master ! {error, "no reply from leader"}
%     end.

% leader(Id, Master, N, Slaves, Group) ->
%     receive
%         {mcast, Msg} ->
%             % io:format("Id=[~p] leader send msg:[~p]~n", [Id, Msg]),
%             bcast(Id, {msg, N, Msg}, Slaves),
%             Master ! Msg,
%             leader(Id, Master, Slaves, Group);
%         % node: wrk -> master, peer -> slave(group layer), 
%         {join, Wrk, Peer} ->
%             Slaves2 = lists:append(Slaves, [Peer]),
%             Group2 = lists:append(Group, [Wrk]),
%             bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
%             Master ! {view, Group2}, % master not care
%             leader(Id, Master, Slaves2, Group2);
%         stop ->
%             ok
%     end.

% slave(Id, Master, Leader, N, Last, Slaves, Group) ->
%     receive
%         {mcast, Msg} ->
%             Leader ! {mcast, Msg},
%             slave(Id, Master, Leader, Slaves, Group);
%         {join, Wrk, Peer} ->
%             Leader ! {join, Wrk, Peer},
%             slave(Id, Master, Leader, Slaves, Group);
%         {msg, I, _} when I < N ->
%             slave(Id, Master, Leader, N, Last, Slaves, Group);
%         {msg, N, Msg} ->
%             % io:format("Id=[~p] recv msg:[~p]~n", [Id, Msg]),
%             Master ! Msg,
%             slave(Id, Master, Leader, N+1, Slaves, Group);
%         % TODO: what if did not recv 'DOWN' and view msg (from new leader) come?
%         %   then this line won't be matched
%         % I think we should just take this leader, monitor it,
%         %  and forget the old leader 
%         {view, [Leader|Slaves2], Group2} ->
%             Master ! {view, Group2},
%             slave(Id, Master, Leader, Slaves2, Group2);
%         {'DOWN', _Ref, process, Leader, _Reason} ->
%             election(Id, Master, N, Last, Slaves, Group);
%         stop ->
%             ok
%     end.

% % delete current leader
% election(Id, Master, N, Last, Slaves, [_|Group]) ->
%     Self = self(),
%     case Slaves of
%         [Self|Rest] ->
%             bcast(Id, {view, Slaves, Group}, Rest),
%             Master ! {view, Group},
%             leader(Id, Master, Rest, Group);
%         [Leader|Rest] ->
%             erlang:monitor(process, Leader),
%             slave(Id, Master, Leader, Rest, Group)
%     end.


% % bcast(_Id, Msg, Nodes) ->
%     % lists:foreach(fun(Node) -> Node ! Msg end, Nodes).

% bcast(Id, Msg, Nodes) ->
%     lists:foreach(fun(Node) -> Node ! Msg, crash(Id) end, Nodes).

% crash(Id) ->
%     % ok.
%     case rand:uniform(?crashN) of
%         ?crashN ->
%             io:format("leader ~w crash ~n", [Id]),
%             exit(no_luck);
%         _E ->
%             ok
%     end.

% % case study
% % 1> Id=[3] leader send msg:[{change,11}]
% % 1> Id=[5] recv msg:[{change,11}]
% % 1> worker 3 change 11
% % 1> Id=[4] recv msg:[{change,11}]
% % 1> worker 4 change 11
% % 1> worker 5 change 11
% % 1> Id=[3] leader send msg:[{change,13}]
% % 1> leader 3 crash
% % 1> Id=[4] recv msg:[{change,13}] % here pid=5 missing message 
% % 1> worker 4 change 13
% % 1> Id=[4] leader send msg:[{change,4}]
% % 1> Id=[5] recv msg:[{change,4}]
% % 1> worker 4 change 4
% % 1> worker 5 change 4

