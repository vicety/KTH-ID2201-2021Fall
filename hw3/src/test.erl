-module(test).
-compile(export_all).

% to test if receive will stop the time countdown for after
% result: yes

start() ->
    register(main, spawn_link(fun() -> recv() end)),
    spawn_link(fun() -> send() end),
    timer:sleep(100000).

send() ->
    timer:sleep(1000),
    main ! ok,
    send().

recv() ->
    receive
        ok ->
            io:format("okk~n")
    after 2000 ->
        io:format("timeout 2000~n")
    end,
    recv().

test() ->
    A = na,
    case A of
        na ->
            okk;
        {lamport, _N} ->
            la
    end.

ycomb() ->
    % Fac  = fun(0, F) -> 1; 
    %                 (N, F) -> N * F(N-1, F) end,
    %                 Fac(6, Fac).

    ProcessNames = ['1', '2', '3'],
    X = fun (_F, 0, Lst) -> Lst;
            (F, N, Lst) -> F(F, N-1, [0|Lst]) end,

    X(X, length(ProcessNames), []).

    % lists:foldl(fun(Ele, Acc) ->
    % Acc#{Ele => list_to_tuple(
    % X(X, length(ProcessNames), [])
    % )}
    % end, #{}, ProcessNames).

ans() ->
    (fun X (0, Lst) -> Lst;
        X (N, Lst) -> X(N - 1, [0|Lst]) end)(3, []).