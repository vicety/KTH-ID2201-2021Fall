-module(main).
-compile(export_all).

run(Sleep, Jitter) ->
    Tester = tester:run(),
    Log = log:start(Tester, ['1', '2', '3', '4']),
    A = worker:start('1', Log, 114, Sleep, Jitter),
    B = worker:start('2', Log, 514, Sleep, Jitter),
    C = worker:start('3', Log, 1919, Sleep, Jitter),
    D = worker:start('4', Log, 810, Sleep, Jitter),
    worker:peers(A, [{B, '2'}, {C, '3'}, {D, '4'}]),
    worker:peers(B, [{A, '1'}, {C, '3'}, {D, '4'}]),
    worker:peers(C, [{A, '1'}, {B, '2'}, {D, '4'}]),
    worker:peers(D, [{A, '1'}, {B, '2'}, {C, '3'}]),
    timer:sleep(5000),
    log:stop(Log),
    worker:stop(A),
    worker:stop(B),
    worker:stop(C),
    worker:stop(D),
    timer:sleep(500),
    tester:stop(Tester).