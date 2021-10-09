-module(test).

-compile(export_all).

-define(Timeout, 1000).
-define(AddDelay, 0).
-define(AddRetryAfter, 200).

% TODO: 稳定后加入new node观察
node(MODULE) ->
    rand:seed(exsss, 114),

    First = start(MODULE),
    start(MODULE, 9, First),
    Keys = keys(400000),
    spawn(fun() -> Sets = sets:from_list(Keys), io:format("~p unique keys~n", [sets:size(Sets)]) end),
    
    timer:sleep(2000),
    add(Keys, First),
    loop_check(Keys, First).


node4() ->
    rand:seed(exsss, 114),

    First = start(node4),
    KeyTmp = keys(9),
    NodeKeys = [{0, First}|start(keys, node4, First, KeyTmp)],
    Keys = keys(100),
    Answer = get_answer(NodeKeys, Keys),
    io:format("keys ~p~n", [Answer]),
    
    timer:sleep(3000),
    add(Keys, First),
    timer:sleep(1000),
    % loop_check(Keys, First),
    check(Keys, First),

    N = rand:uniform(length(NodeKeys)),
    {StopNodeKey, StopNodePid} = lists:nth(N, NodeKeys),
    io:format("stop key [~p]~n", [StopNodeKey]),
    {Remain, Split} = split_answer(Answer, StopNodeKey),

    StopNodePid ! stop,
    timer:sleep(1000),
    check(Remain, First),
    check(Split, First).

node5() ->
    rand:seed(exsss, 114),

    First = start(node5),
    KeyTmp = keys(9),
    NodeKeys = [{0, First}|start(keys, node5, First, KeyTmp)],
    Keys = keys(400),
    spawn(fun() -> Sets = sets:from_list(Keys), io:format("~p unique keys~n", [sets:size(Sets)]) end),
    Answer = get_answer(NodeKeys, Keys),
    io:format("keys ~p~n", [Answer]),    

    timer:sleep(3000),
    add(Keys, First),
    timer:sleep(1000), % to print out the graph
    loop_check(Keys, First).


start(keys, MODULE, First, NodeKeys) ->
    start(keys, MODULE, First, NodeKeys, []).

start(keys, _Module, _P, [], Processes) ->
    Processes;
start(keys, Module, P, Keys, Processes) ->
    [Key|Rest] = Keys,
    Pid = apply(Module, start, [Key, P]),
    % timer:sleep(500),
    start(keys, Module, P, Rest, Processes ++ [{Key, Pid}]).

get_answer(Processes, Keys) ->
    get_answer_srted(lists:sort(lists:map(fun(K) -> element(1, K) end, Processes)), lists:sort(Keys), #{}).

get_answer_srted(Nodes, [], Acc) ->
    Acc;
get_answer_srted(Nodes, Ks, Acc) ->
    [K|Rest] = Ks,
    Pos = find_pos(Nodes, K),
    Node = lists:nth(Pos, Nodes),
    case maps:is_key(Node, Acc) of
        false ->
            Acc1 = Acc#{Node => []};
        true -> Acc1 = Acc
    end,
    #{Node := Tmp} = Acc1,
    get_answer_srted(Nodes, Rest, Acc1#{Node => Tmp ++ [K]}).

% {Remaining Keys, Splited Keys}
split_answer(Answer, NodeK) ->
    maps:fold(fun(K, V, {Remain, Split}) ->
        case K of
            NodeK -> 
                Remain1 = Remain,
                Split1 = Split ++ V;
            _ -> 
                Remain1 = Remain ++ V,
                Split1 = Split
        end,
        {Remain1, Split1}
    end, {[], []}, Answer).

find_pos(Nodes, K) ->
    Seq = lists:seq(1, length(Nodes)),
    Nodes1 = [lists:nth(length(Nodes), Nodes)|Nodes],
    Acc = lists:foldl(fun(I, Acc) ->
        case key:between(K, lists:nth(I, Nodes1), lists:nth(I+1, Nodes1)) of
            true -> Acc1 = Acc ++ [I];
            false -> Acc1 = Acc
        end,
        Acc1
    end, [], Seq),
    lists:nth(1, Acc).

loop_check(Keys, First) ->
    check(Keys, First),
    timer:sleep(100),
    loop_check(Keys, First).

%% Starting up a set of nodes is made easier using this function.

start(Module) ->
    % Id = key:generate(), 
    Id = 0, 
    apply(Module, start, [Id]).


start(Module, P) ->
    Id = key:generate(), 
    apply(Module, start, [Id,P]).

start(_, 0, _) ->
    ok;
start(Module, N, P) ->
    start(Module, P),
    start(Module, N-1, P).

%% The functions add and lookup can be used to test if a DHT works.

% TODO: synchronous add, what about async add 
% add(Key, Value , P) ->
%     Q = make_ref(),
%     P ! {add, Key, Value, Q, self()},
%     receive 
% 	{Q, ok} ->
% 	    ok;
%     {Q, error} ->
%         error
% 	after ?Timeout ->
% 	    timeout
%     end.

delay(N) ->
    case N of
        0 -> ok;
        _ -> timer:sleep(N)
    end.

add(Key, Value, P, 3) ->
    error;
add(Key, Value, P, Retry) ->
    delay(?AddDelay),
    Q = make_ref(),
    P ! {add, Key, Value, Q, self()},
    receive 
	{Q, ok} ->
	    ok;
    {Q, error} ->
        timer:sleep(?AddRetryAfter),
        io:format("retry adding~n"),
        add(Key, Value, P, Retry+1)
	after ?Timeout ->
	    timeout
    end.

lookup(Key, Node) ->
    Q = make_ref(),
    Node ! {lookup, Key, Q, self()},
    receive 
	{Q, Value} ->
	    Value
    after ?Timeout ->
	    {error, "timeout"}
    end.


%% This benchmark can be used for a DHT where we can add and lookup
%% key. In order to use it you need to implement a store.

% generate Key array
keys(N) ->
    lists:map(fun(_) -> key:generate() end, lists:seq(1,N)).

% add Keys from P
add(Keys, P) ->
    T1 = now(),
    {Fail, Timeout} = lists:foldl(fun(K, {Fail1, Timeout1}) ->
        case add(K, gurka, P, 0) of
            ok ->
                Fail2 = Fail1,
                Timeout2 = Timeout1;
            error ->
                Fail2 = Fail1 + 1,
                Timeout2 = Timeout1;
            timeout ->
                Fail2 = Fail1,
                Timeout2 = Timeout1 + 1
        end,
        {Fail2, Timeout2}
    end, {0, 0}, Keys),
    T2 = now(),
    Done = (timer:now_diff(T2, T1) div 1000),
    io:format("~w add operation in ~w ms ~n", [length(Keys), Done]),
    io:format("~w add failed, ~w caused a timeout ~n", [Fail, Timeout]).

% do lookup on keys, count time and failure
check(Keys, P) ->
    T1 = now(),
    {Failed, Timeout} = check(Keys, P, 0, 0),
    T2 = now(),
    Done = (timer:now_diff(T2, T1) div 1000),
    io:format("~w lookup operation in ~w ms ~n", [length(Keys), Done]),
    io:format("~w lookups failed, ~w caused a timeout ~n", [Failed, Timeout]).


check([], _, Failed, Timeout) ->
    {Failed, Timeout};
check([Key|Keys], P, Failed, Timeout) ->
    case lookup(Key, P) of
        {Key, _} -> 
            check(Keys, P, Failed, Timeout);
        {error, _} -> 
            check(Keys, P, Failed, Timeout+1);
        false ->
            check(Keys, P, Failed+1, Timeout)
    end.











