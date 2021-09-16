-module(tpe).
-compile(export_all).
-include("http.hrl").

submitTask(Disaptcher, Socket, HandlerFunc) ->
    Disaptcher ! {self(), {Socket, HandlerFunc}}. 

createThreadPoolExecutor(ThreadNum) ->
    DispatchThread = spawn(?MODULE, createDispatcher, [ThreadNum]),
    DispatchThread.

createDispatcher(ThreadNum) ->
    Q = createQ(queue:new(), ThreadNum),
    dispatcherLoop(Q).

dispatcherLoop(Q) ->
    receive
        {done, From} ->
            ?LOG(jobdone),
            Q1 = queue:in(From, Q),
            ?LOG(queue:len(Q1)),
            dispatcherLoop(Q1);
        {From, Msg} ->
            ?LOG(newevent),
            {{value, Head}, Q2} = queue:out(Q),
            Head ! {From, Msg},
            dispatcherLoop(Q2)
    end.


createQ(Q, 0) ->
    Q;
createQ(Q, N) ->
    Q1 = queue:in(spawn(?MODULE, workloop, [self()]), Q),
    createQ(Q1, N-1).

workloop(Disaptcher) ->
    receive
        {From, Msg} -> 
            {Socket, HandlerFunc} = Msg,
            ?LOG(here),
            handler(Socket, HandlerFunc), % TODO: handler函数包含在Msg中，如何做到多参数函数的调用？
            Disaptcher ! {done, self()},
            % From ! ok, # dont need this
            workloop(Disaptcher)
    end.


% just cp from tcp_server
handler(Socket, HandleFunc) ->
    % timeout close connection, rather than recv only once, since the msg may not be finished yet
    case gen_tcp:recv(Socket, 0) of 
        {ok, Str} ->
            case HandleFunc(Str) of
                {ok, Resp} ->
                    ?LOG("Resp: " ++ Resp),
                    % io:format("[TCP] Sending back: ~s~n", [Resp]),
                    gen_tcp:send(Socket, Resp);
                {error, _Error} ->
                    error
            end;
        {error, Error} ->
            io:format("rudy: error: ~s~n", [Error])		
    end,
    gen_tcp:close(Socket). % return to pool