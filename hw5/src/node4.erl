-module(node4).
-compile(export_all).

% simplify node2
-define(Stabilize, 100).
-define(Timeout, 5000).

start(Id) ->
    First = start(Id, nil),
    spawn(fun() -> timer:sleep(100), timer:send_interval(1000, First, {visualize, First, 0, 0, ""}) end),
    First.

start(Id, Peer) ->
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    {ok, Successor} = connect(Id, Peer),
    {Skey, _, Spid} = Successor,
    schedule_stabilize(), % TODO：有必要立即call一次stabilize？
    node(Id, nil, Successor, store:create(), {Skey, Spid}).

% return succ, set succ as self if is first node
connect(Id, nil) ->
    {ok, {Id, nil, self()}};
connect(_Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            {ok, {Skey, monitor(Peer), Peer}} 
    after ?Timeout ->
        io:format("Timeout: no response from peer~n", [])
    end.

visualize(StartNode) ->
    StartNode ! {visualize, StartNode, 0, ""}.

% Seen #{K => Seq}
node(Id, Predecessor, Successor, Store, Next) ->
    receive
        {add, K, V, Qref, Client} ->
            case add(K, V, Qref, Client, Id, Predecessor, Successor, Store) of
                {Qref, error} ->
                    node(Id, Predecessor, Successor, Store, Next);
                Added ->
                    node(Id, Predecessor, Successor, Added, Next)
            end;    
        {lookup, K, Qref, Client} ->
            lookup(K, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Store, Next);
        {handover, Qref, Elements, _FromKey, FromPid} ->
            FromPid ! {ack, Qref},
            Merged = store:merge(Store, Elements), 
            node(Id, Predecessor, Successor, Merged, Next);
        % newly added peer need to know our key
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Store, Next);
        % new node inform us its existance
        % 只看到pred notice我们时调用，此节点认为是我们的pred，尽量维护前向的正确性
        {notify, New} ->
            % io:format("[~p] notify ~p~n", [Id, New]),
            % io:format("pred ~p~n", [Predecessor]),
            case notify(New, Id, Predecessor, Store) of
                {error, timeout} ->
                    self() ! {notify, New},
                    node(Id, Predecessor, Successor, Store, Next);
                {Pred, Store1} ->
                    % io:format("here"),
                    node(Id, Pred, Successor, Store1, Next)
            end;
        % predecessor's stabilize func calls this,
        %  need to know our pred
        {request, Peer} ->
            % io:format("[~p] request Next ~p~n", [Id, Next]),
            request(Peer, Predecessor, Next),
            node(Id, Predecessor, Successor, Store, Next);
        % our succ inform us about its pred
        {status, Pred, Nx} ->
            % io:format("[~p] state ~n", [Id]),
            {Succ, Nxt} = stabilize(Pred, Nx, Id, Successor),
            node(Id, Predecessor, Succ, Store, Nxt);
        % periodically ask succ's pred from succ, to make sure succ is right and updated
        % current stabilize/1 -> current.succ request -> current stabilize/3 -> (current think it is succ's pred and if current.succ dont know ) current.succ notify
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Store, Next);
        {ack, _} ->
            % should not handle it here, discard
            node(Id, Predecessor, Successor, Store, Next);
        {'DOWN', Ref, process, _, _} ->
            {Pred, Succ, Nxt} = down(Ref, Predecessor, Successor, Next),
            node(Id, Pred, Succ, Store, Nxt);
        {visualize, Starter, Seq, Acc, RingStr}  ->
            handle_visualize(Id, Starter, Seq, Acc, RingStr, Successor, Store),
            % handle_visualize(Id, Starter, Seq, Acc, RingStr, Predecessor, Store),
            node(Id, Predecessor, Successor, Store, Next);
        stop ->
            io:format("stopping ~p~n", [Id]);
        _Other ->
            io:format("Unexpected msg: ~p~n", [_Other])
    end.

add(_, _, Qref, Client, _, nil, _, _) ->
    Client ! {Qref, error}; % mark-red happens when step 3 is done, step 4 not executed, else program stuck here
add(K, V, Qref, Client, Id, {Pkey, _, _}, {_, _, Spid}, Store) ->
    case key:between(K, Pkey, Id) of
        true ->
            Store1 = store:add(K, V, Store),
            Client ! {Qref, ok};
        false ->
            Store1 = Store,
            Spid ! {add, K, V, Qref, Client}
    end,
    Store1.

lookup(K, Qref, Client, _, nil, {_, _, Spid}, _) ->
    Spid ! {lookup, K, Qref, Client}; % mark-red happens between step3 and step4, just pass this to next, rare chance will reach here
lookup(K, Qref, Client, Id, {Pkey, _, _}, {_, _, Spid}, Store) ->
    case key:between(K, Pkey, Id) of
        true ->
            Tmp = store:lookup(K, Store),
            Client ! {Qref, Tmp};
        false ->
            Spid ! {lookup, K, Qref, Client}
    end.

request(Peer, Predecessor, Next) ->
    case Next of
        nil -> Nx = nil;
        {Nxkey, Nxpid} -> Nx = {Nxkey, Nxpid}
    end,
    case Predecessor of
        nil -> Peer ! {status, nil, Nx};
        {Pkey, _, Ppid} -> Peer ! {status, {Pkey, Ppid}, Nx}
    end.

stabilize({_, _, Spid}) ->
    Spid ! {request, self()}.

stabilize(Pred, Nx, Id, Successor) ->
    {Skey, SRef, Spid} = Successor,
    case Pred of
        % just join, no pred(maybe first node, maybe not)
        nil ->
            % io:format("[~p] send notify to [~p]~n", [Id, Skey]),
            Spid ! {notify, {Id, self()}}, % tell him I am your pred
            {Successor, Nx};
        {Id, _} -> % succ's pred is me
            {Successor, Nx};
        % my succ's pred is my succ, meaning first(and only) node has stabilized at least once, and (another node is joining or first node stabilize again)
        {Skey, _} ->
            Spid ! {notify, {Id, self()}}, % tell him I am your pred
            {Successor, Nx}; % 没发现这里啥时候不是nil，总之不能写nil
        {XKey, Xpid} ->
            case key:between(XKey, Id, Skey) of
                false -> % we are succ's closer pred
                    Spid ! {notify, {Id, self()}}, % should tell him I am your pred
                    {Successor, Nx};
                true -> % someone is closer
                    % trigger this immediately
                    stabilize({XKey, dontcare, Xpid}),
                    drop(SRef),
                    % io:format("[~p] stabilize monitor [~p, ~p]~n", [self(), XKey, Xpid]),
                    {{XKey, monitor(Xpid), Xpid}, {Skey, Spid}}
            end
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

% [pred_been_notified, id, pred_before]  used to maintain right pred
notify({Nkey, Npid}, Id, Predecessor, Store) ->
    case Predecessor of
        nil ->
            % io:format("Nkey ~p, Id ~p, size: ~p~n", [Nkey, Id, store:size(Store)]),
            case handover(Id, Store, Nkey, Npid, Id) of
                {ok, Store1} ->
                    % timer:sleep(100),
                    % io:format("[~p] notify nil monitor [~p, ~p]~n", [self(), Nkey, Npid]),
                    {{Nkey, monitor(Npid), Npid}, Store1};
                {error, timeout} ->
                    {error, timeout}
            end;
            
        {Pkey, Pref, Ppid} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    case handover(Id, Store, Nkey, Npid, Id) of
                        {ok, Store1} ->
                            % timer:sleep(100),
                            drop(Pref),
                            % io:format("[~p] notify monitor [~p, ~p]~n", [self(), Nkey, Npid]),
                            {{Nkey, monitor(Npid), Npid}, Store1};
                        {error, timeout} ->
                            {error, timeout}
                    end;  
                false ->
                    {Predecessor, Store}
            end
    end.

handover(Pkey, Store, Nkey, Npid, Id) ->
    case Id == Nkey of
        true ->
            {ok, Store};
        false ->
            {Store1, Shares} = store:split(Pkey, Nkey, Store),
            QRef = make_ref(),
            Npid ! {handover, QRef, Shares, Id, self()},
            receive
                {ack, QRef} ->
                    {ok, Store1}
            end
    end.

down(Ref, {Pkey, Ref, _}, Successor, Next) ->
    io:format("[~p] is down~n", [Pkey]),
    {nil, Successor, Next};
down(Ref, Predecessor, {Skey, Ref, _}, {Nkey, Npid}) ->
    io:format("[~p] is down~n", [Skey]),
    stabilize({Nkey, dontcare, Npid}),
    {Predecessor, {Nkey, monitor(Npid), Npid}, nil}.

handle_visualize(Id, Starter, Seq, Acc, RingStr, {_Skey, _, Spid}, Store) ->
    Self = self(),
    case Starter of
        Self -> Seq1 = Seq + 1;
        _Else -> Seq1 = Seq
    end,
    case Seq1 of
        2 -> io:format("Total ~p data, graph: ~p~n", [Acc, RingStr ++ integer_to_list(Id) ++ "(" ++ integer_to_list(store:size(Store)) ++ ")"]);
        % 2 -> io:format("Total ~p data~n", [Acc]);
        _ -> 
            Spid ! {visualize, Starter, Seq1, Acc + store:size(Store), RingStr ++ integer_to_list(Id) ++ "(" ++ integer_to_list(store:size(Store)) ++ ")" ++ " --> "}
    end.

monitor(Pid) -> 
    
    Ref = erlang:monitor(process, Pid),
    % io:format("[~p] monitor [~p, ~p]~n", [self(), Pid, Ref]),
    Ref.

drop(nil) -> ok;
drop(Ref) -> 
    % io:format("[~p] demonitor [~p]~n", [self(), Ref]),
    erlang:demonitor(Ref, [flush]).