-module(test).

-compile(export_all).

-define(Timeout, 1000).

node2() ->
    rand:seed(exsss, 114),

    First = start(node2),
    start(node2, 31, First),
    % timer:sleep(1000),
    % Keys = keys(10000),
    Keys = keys(100000),
    spawn(fun() -> Sets = sets:from_list(Keys), io:format("~p unique keys~n", [sets:size(Sets)]) end),
    % Sets = sets:from_list(Keys),
    % io:format("~p unique keys~n", [sets:size(Sets)]),

    add(Keys, First),
    check(Keys, First).

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

add(Key, Value, P, 3) ->
    error;
add(Key, Value, P, Retry) ->
    Q = make_ref(),
    P ! {add, Key, Value, Q, self()},
    receive 
	{Q, ok} ->
	    ok;
    {Q, error} ->
        timer:sleep(300),
        % io:format("retry~n"),
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


    








