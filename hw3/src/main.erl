-module(main).
-compile(export_all).

run(Sleep, Jitter, ClockType) ->
    % TimerType = vector,
    InitialTime = worker:actual_time(),
    tester:run(InitialTime),
    Log = log:start(ClockType, InitialTime),
    A = worker:start(ClockType, '1', Log, 114, Sleep, Jitter),
    B = worker:start(ClockType, '2', Log, 514, Sleep, Jitter),
    C = worker:start(ClockType, '3', Log, 1919, Sleep, Jitter),
    D = worker:start(ClockType, '4', Log, 810, Sleep, Jitter),
    worker:peers(A, [{B, '2'}, {C, '3'}, {D, '4'}]),
    worker:peers(B, [{A, '1'}, {C, '3'}, {D, '4'}]),
    worker:peers(C, [{A, '1'}, {B, '2'}, {D, '4'}]),
    worker:peers(D, [{A, '1'}, {B, '2'}, {C, '3'}]),

    % one process only send, lamport perform bad in this scenario
    % worker:peers(A, [{B, '2'}, {D, '4'}]),
    % worker:peers(B, [{A, '1'}, {D, '4'}]),
    % worker:peers(C, [{A, '1'}, {B, '2'}, {D, '4'}]),
    % worker:peers(D, [{A, '1'}, {B, '2'}]),
    timer:sleep(4000),

    % add new worker
    % E = worker:start(ClockType, '5', Log, 42, Sleep, Jitter),
    % worker:peers(E, [{A, '1'}, {B, '2'}, {C, '3'}, {D, '4'}]),
    % worker:new_peer(A, {E, '5'}),
    % worker:new_peer(B, {E, '5'}),
    % worker:new_peer(C, {E, '5'}),
    % worker:new_peer(D, {E, '5'}),

    timer:sleep(1000),
    worker:stop(A),
    worker:stop(B),
    worker:stop(C),
    worker:stop(D),
    % worker:stop(E),
    timer:sleep(500), % ensure all async logs are received
    log:stop(Log),
    timer:sleep(500),
    tester:stop().

% init_process_ctl() ->
%     register(ctl, spawn_link())

% ctl_loop(NowNum) ->
%     receive
%         {start, N} ->
%             (fun F(N, Acc) -> Acc;
%                  F(Now, Acc) -> )

% start_processes()

% stop_processes()

% addE() ->
%     E = worker:start(ClockType, '5', Log, 42, Sleep, Jitter),

%     E.