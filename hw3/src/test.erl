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