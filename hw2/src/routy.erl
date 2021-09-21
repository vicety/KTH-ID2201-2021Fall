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
    Hist = hist:new(Name),
    Cfg = util:readFile(atom_to_list(Name) ++ ".data"),
    io:format("read config ~p~n", [Cfg]),
    
    % init map and table
    NeighbourNames = lists:map(fun(Neighbour) -> element(1, Neighbour) end, Cfg),
    Map1 = map:update(Name, NeighbourNames, Map),
    Table = dij:table(Name, Map1),

    RandomNum = rand:uniform(),
    router(Name, 0, Hist, Intf, Table, Map1, Cfg, true, RandomNum).

% Neighbour: {name, uname@host}
% mark-red: note that if there's no way that downstream node could reach the upstream node, we cannot rebuild the connection to the downstream node if it breaks, then restarts
%  i.e.: A -> B -> C, we cannot rebuild connection to C if C restarts

% Name: Name of current Node
% N: Seq Number of current node, when connect target down, reset its history to -1, this only solves the target restart, not the source router restart, we use randomNum to solve this
% Hist: History of other nodes in the network % 整个网络可能有无数路由器，此时按子网划分应该往哪个方向发
% Intf: Interface of nodes that current node could connect to directly
% Table: The route table
% Map: A global node connectivity map
% Neighbours: Nodes that can be reached initially, dont change in this func since we dont consider adding more nodes dynamically.
% Init: if the router is ready to broadcast/forward msg

% mark-red: 我们不知道上游何时结束，因此
router(Name, N, Hist, Intf, Table, Map, Neighbours, Init, RandomNum) ->
    receive
        c -> % connect
            Intf1 = lists:foldl(fun(Neighbour, InnerIntf) ->
                {NeighbourName, _Host} = Neighbour,
                Ref = monitor(process, Neighbour), % triggered only once, no need to demonitor
                intf:add(NeighbourName, Neighbour, Ref, InnerIntf)
                end, Intf, Neighbours),
            NeighbourNames = lists:map(fun(Neighbour) -> element(1, Neighbour) end, Neighbours),
            io:format("[~s] receives 'connect' command, broadcasting neighbours ~p...~n", [Name, NeighbourNames]),
            intf:broadcast({links, {Name, N, NeighbourNames, RandomNum}, Name}, Intf1), % isIinit == true
            router(Name, N+1, Hist, Intf1, Table, Map, Neighbours, false, RandomNum);
        {send, Msg, DstName} -> 
            case DstName of
                Name ->
                    io:format("recv message: ~p~n", [Msg]);
                _ ->
                    NextHop = dij:route(DstName, Table),
                    intf:send(NextHop, DstName, Msg, Intf)
            end,
            router(Name, N, Hist, Intf, Table, Map, Neighbours, Init, RandomNum);
        {links, {RemoteName, RemoteN, RemoteNeighbourNames, RemoteRandomNum}, MsgFrom} ->
            case RemoteName of
                Name ->
                    router(Name, N, Hist, Intf, Table, Map, Neighbours, Init, RandomNum);
                _ ->
                    ok
            end,
            % if receives msg from reachable neighbour and dont have its interface, meaning this node is restarted, add it to interface and monitor
            case lists:keyfind(RemoteName, 1, Neighbours) of
                false ->
                    Intf1 = Intf,
                    Map1 = Map,
                    Table1 = Table;
                LocalNeighbourIdentifier ->
                    case intf:pid(RemoteName, Intf) of
                        notfound ->
                            io:format("detected node ~p reconnection~n", [RemoteName]),
                            Ref = monitor(process, LocalNeighbourIdentifier),
                            Intf1 = intf:add(RemoteName, LocalNeighbourIdentifier, Ref, Intf),
                            Map1 = map:addNeighbour(Map, Name, RemoteName),
                            Table1 = dij:table(Name, Map1);
                        {ok, _Pid} ->
                            Intf1 = Intf,
                            Map1 = Map,
                            Table1 = Table
                    end
            end,
            
            case hist:update(RemoteName, RemoteN, Hist, RemoteRandomNum) of
                {new, Hist1} ->
                    io:format("forwarding link msg source ~p seq number ~p neighbours ~p from ~p~n", [RemoteName, RemoteN, RemoteNeighbourNames, MsgFrom]),
                    intf:broadcast({links, {RemoteName, RemoteN, RemoteNeighbourNames, RemoteRandomNum}, Name}, Intf1),
                    Map2 = map:update(RemoteName, RemoteNeighbourNames, Map1), % TODO: if no update, no need to calculate routing table again
                    Table2 = dij:table(Name, Map2), % update route table here
                    router(Name, N, Hist1, Intf1, Table2, Map2, Neighbours, Init, RandomNum);
                old ->
                    router(Name, N, Hist, Intf1, Table1, Map1, Neighbours, Init, RandomNum)
            end;
        {'DOWN', Ref, process, _, Reason} ->
            {ok, DownNode} = intf:name(Ref, Intf),
            io:format("~w: exit recived from ~w, Reason: ~p~n", [Name, DownNode, Reason]),
            % TODO: neighbours stored in intf(maybe also map), maybe broadcast now
            Intf1 = intf:remove(DownNode, Intf),
            Hist1 = hist:reset(DownNode, Hist),
            Map1 = map:removeNeighbour(Map, Name, DownNode),
            Table1 = dij:table(Name, Map1),
            % TODO: demonitor maybe
            router(Name, N, Hist1, Intf1, Table1, Map1, Neighbours, Init, RandomNum);
        broadcast ->
            % only broadcast when connected done, i.e. Init == false
            case Init of
                true ->
                    io:format("ignore timeout before manual connect...~n"),
                    router(Name, N, Hist, Intf, Table, Map, Neighbours, Init, RandomNum);
                false ->
                    NeighbourNames = lists:map(fun(Neighbour) -> element(1, Neighbour) end, Neighbours),
                    io:format("broadcasting local([~p]) neighbour info ~p...~n", [Name, NeighbourNames]),
                    % it's better to use a random number to indicate this router re-runs, in case the init transmission may be lost
                    intf:broadcast({links, {Name, N, NeighbourNames, RandomNum}, Name}, Intf),
                    router(Name, N+1, Hist, Intf, Table, Map, Neighbours, Init, RandomNum)                
            end
    end.


% 单机代表一个洲，所以三台机器，其实三个进程也行