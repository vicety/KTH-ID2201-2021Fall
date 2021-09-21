-module(routy).
-compile(export_all).

start(Name) ->
    register(Name, spawn(?MODULE, init, [Name])),
    spawn(?MODULE, broadcastTimeout, [Name]).
    % timer:apply_interval(5000, ?MODULE, broadcastTimeout, [Name]).
    % timer:send_interval(5000, broadcast).

broadcastTimeout(Name) ->
    receive
        after 5000 ->
            Name ! broadcast,
            broadcastTimeout(Name)
    end.

init(Name) ->
    Intf = intf:new(),
    Map = map:new(),
    Table = dij:table(Intf, Map),
    Hist = hist:new(Name),
    Cfg = util:readFile(atom_to_list(Name) ++ ".data"),
    io:format("read config ~p~n", [Cfg]),
    [SelfPID|Neighbours] = Cfg,
    router(Name, 0, Hist, Intf, Table, Map, Neighbours, true, SelfPID).

% Neighbour: {name, uname@host}
% maybe map should be inside dij
% 随机数的作用是让接受者判断是一次重启
% 重启后connect前的router不会收到消息，因为其他router检测到down后已经将其unregister了
% 下游down，上游知道，下游重启，只能通过其他链路让上游知道已经up，假设不会有新的路由器加入
% {b, sname@host, randomNum}

% Name: Name of current Node
% N: Seq Number of current node
% Hist: History of other nodes in the network % 整个网络可能有无数路由器，此时按子网划分应该往哪个方向发
% Intf: Interface of nodes that current node could connect to directly
% Table: The route table
% Map: A global node connectivity map
% Neighbours: Nodes that can be reached initially, dont change in this func since we dont consider adding more nodes dynamically.
% Init: if the router is ready to broadcast/forward msg
% SelfPID: used for other node 
router(Name, N, Hist, Intf, Table, Map, Neighbours, Init, SelfPID) ->
    receive
        c -> % connect
            Intf1 = lists:foldl(fun(Neighbour, InnerIntf) ->
                {NeighbourName, _Host} = Neighbour,
                Ref = monitor(process, Neighbour), % triggered only once, no need to demonitor
                intf:add(NeighbourName, Neighbour, Ref, InnerIntf)
                end, Intf, Neighbours),
            NeighbourNames = lists:map(fun(Neighbour) -> element(1, Neighbour) end, Neighbours),
            io:format("[~s] receives 'connect' command, broadcasting neighbours ~p...~n", [Name, NeighbourNames]),
            intf:broadcast({links, {Name, N, NeighbourNames, SelfPID}, Name}, Intf1), % isIinit == true
            router(Name, N+1, Hist, Intf1, Table, Map, Neighbours, false, SelfPID);
        {send, Msg, To} -> % To should contain only name
            NextHop = dij:route(To, Table),
            intf:send(NextHop, Msg, Intf);
        {links, {RemoteName, RemoteN, RemoteNeighbourNames, RemoteSelfPID}, MsgFrom} ->
            % if receives msg from reachable neighbour and dont have its interface, meaning this node is restarted, add it to interface and monitor
            LocalNeighbours = lists:map(fun(Neighbour) -> element(1, Neighbour) end, Neighbours),
            case lists:member(RemoteName, LocalNeighbours) of
                true ->
                    case intf:pid(RemoteName, Intf) of
                        notfound ->
                            Ref = monitor(process, RemoteSelfPID),
                            Intf1 = intf:add(RemoteName, RemoteSelfPID, Ref, Intf);
                        {ok, _Pid} ->
                            Intf1 = Intf
                    end;
                false ->
                    Intf1 = Intf
            end,
            
            case hist:update(RemoteName, RemoteN, Hist) of
                {new, Hist1} ->
                    io:format("forwarding link msg source ~p seq number ~p neighbours ~p from ~p~n", [RemoteName, RemoteN, RemoteNeighbourNames, MsgFrom]),
                    intf:broadcast({links, {RemoteName, RemoteN, RemoteNeighbourNames, RemoteSelfPID}, Name}, Intf1),
                    Map1 = map:update(RemoteName, RemoteNeighbourNames, Map),
                    Table1 = dij:table(Name, Map1), % update route table here
                    router(Name, N, Hist1, Intf1, Table1, Map1, Neighbours, Init, SelfPID);
                old ->
                    router(Name, N, Hist, Intf1, Table, Map, Neighbours, Init, SelfPID)
            end;
        {'DOWN', Ref, process, _, _} ->
            {ok, DownNode} = intf:name(Ref, Intf),
            io:format("~w: exit recived from ~w~n", [Name, DownNode]),
            % TODO: neighbours stored in intf(maybe also map), maybe broadcast now
            Intf1 = intf:remove(DownNode, Intf),
            Hist1 = hist:reset(DownNode, Hist),
            % TODO: demonitor maybe
            router(Name, N, Hist1, Intf1, Table, Map, Neighbours, Init, SelfPID);
        broadcast ->
            % only broadcast when connected done, i.e. Init == false
            case Init of
                true ->
                    io:format("ignore timeout before manual connect...~n"),
                    router(Name, N, Hist, Intf, Table, Map, Neighbours, Init, SelfPID);
                false ->
                    NeighbourNames = lists:map(fun(Neighbour) -> element(1, Neighbour) end, Neighbours),
                    io:format("broadcasting local([~p]) neighbour info ~p...~n", [Name, NeighbourNames]),
                    % it's better to use a random number to indicate this router re-runs, in case the init transmission may be lost
                    intf:broadcast({links, {Name, N, NeighbourNames, SelfPID}, Name}, Intf),
                    router(Name, N+1, Hist, Intf, Table, Map, Neighbours, Init, SelfPID)                
            end
    end.



% 单机代表一个洲，所以三台机器，其实三个进程也行