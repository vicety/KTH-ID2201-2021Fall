-module(worker).
-compile(export_all).

% msg format: {traceID, [{pid, msg}]}

start(PName, Logger, Seed, Sleep, Jitter) ->
    spawn_link(fun() -> init(PName, Logger, Seed, Sleep, Jitter) end).

stop(Worker) ->
    Worker ! stop.

init(Name, Log, Seed, Sleep, Jitter) ->
    rand:seed(exsss, Seed),
    receive
        {peers, Peers} ->
            loop(Name, Log, Peers, Sleep, Jitter);
        stop ->
            ok
    end.

peers(Wrk, Peers) ->
    Wrk ! {peers, Peers}.


loop(Name, Log, Peers, Sleep, Jitter) ->
    Wait = rand:uniform(Sleep),
    receive
        {msg, Time, From, Msg} ->
            jitter(Jitter),
            Log ! {log, Name, Time, {received, From, Name, Msg}},
            loop(Name, Log, Peers, Sleep, Jitter);
        stop ->
            ok;
        Error ->
            Log ! {log, Name, time, {error, Error}}
    after Wait ->
        {PeerPID, PeerName} = select(Peers),
        Time = na,
        Message = {hello, Name, rand:uniform()},
        PeerPID ! {msg, Time, Name, Message}, 
        jitter(Jitter),
        Log ! {log, Name, Time, {sending, Name, PeerName, Message}},
        loop(Name, Log, Peers, Sleep, Jitter)
    end.

select(Peers) ->
    lists:nth(rand:uniform(length(Peers)), Peers).

jitter(0) -> ok;
jitter(Jitter) -> timer:sleep(rand:uniform(Jitter)).