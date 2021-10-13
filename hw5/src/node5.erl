-module(node5).
-compile(export_all).

% simplify node2
-define(Stabilize, 100).
-define(VisualizeInterval, 500).
-define(Timeout, 5000).
% simulate add failure
-define(ReplicateTimeout, 80).
-define(StoreValidation, 200).

% mark-red: 
% 1. handle failure: maintain next pointer
% 2. replication: maintain replicated data in next node, when node down, 
%    1. merge replicate to storage that response to lookup request
%    2. make new replication
%    3. replicate for predecessor since its replication is also lost with the down node


% 0(Store:5) (Replica:5) --> 35584(Store:1) (Replica:5) --> 2121782(Store:30) (Replica:1) --> 4161369(Store:18) (Replica:30) 
%                        --> 5458605(Store:11) (Replica:18) --> 6908360(Store:12) (Replica:11) --> 7923512(Store:10) (Replica:12) 
%                        --> 8557287(Store:8) (Replica:10) --> 8645987(Store:0) (Replica:8) --> 9253054(Store:5) (Replica:0) 
%                        --> 0(Store:5) (Replica:5)

start(Id) ->
    First = start(Id, nil),
    spawn(fun() -> timer:sleep(100), timer:send_interval(?VisualizeInterval, First, {visualize, First, 0, 0, ""}) end),
    First.

start(Id, Peer) ->
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    {ok, Successor} = connect(Id, Peer),
    {Skey, _, Spid} = Successor,
    schedule_stabilize(), % TODO：有必要立即call一次stabilize？
    % schedule_store_validation(),
    node(Id, nil, Successor, store:create(), {Skey, Spid}, store:create()).

schedule_store_validation() ->
    timer:send_interval(?StoreValidation, self(), validate_store).
    

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
node(Id, Predecessor, Successor, Store, Next, Replica) ->
    receive
        {replicate, _Qref, K, V} ->
            node(Id, Predecessor, Successor, Store, Next, store:add(K, V, Replica));
        {add, K, V, Qref, Client} ->
            case add(K, V, Qref, Client, Id, Predecessor, Successor, Store) of
                {Qref, error} ->
                    node(Id, Predecessor, Successor, Store, Next, Replica);
                {false, Added} ->
                    node(Id, Predecessor, Successor, Added, Next, Replica);
                {true, Store} ->
                    receive
                        {'DOWN', Ref, process, _, _} ->
                            {Pred, Succ, Nxt, Store1, Replica1} = down(Ref, Predecessor, Successor, Next, Store, Replica, Id),
                            node(Id, Pred, Succ, Store1, Nxt, Replica1)
                    end
            end;    
        {lookup, K, Qref, Client} ->
            lookup(K, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Store, Next, Replica);
        {handover, Qref, Elements, _FromKey, FromPid} ->
            FromPid ! {ack, Qref},
            % Merged = store:merge(Store, Elements), 
            Merged = merge(Store, Elements, Successor),
            node(Id, Predecessor, Successor, Merged, Next, Replica);
        % newly added peer need to know our key
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Store, Next, Replica);
        % new node inform us its existance
        % 只看到pred notice我们时调用，此节点认为是我们的pred，尽量维护前向的正确性
        {notify, New} ->
            % io:format("[~p] notify ~p~n", [Id, New]),
            % io:format("pred ~p~n", [Predecessor]),
            case notify(New, Id, Predecessor, Store) of
                {error, timeout} ->
                    self() ! {notify, New},
                    node(Id, Predecessor, Successor, Store, Next, Replica);
                {Pred, Store1} ->
                    % io:format("here"),
                    node(Id, Pred, Successor, Store1, Next, Replica)
            end;
        % predecessor's stabilize func calls this,
        %  need to know our pred
        {request, Peer} ->
            % io:format("[~p] request Next ~p~n", [Id, Next]),
            request(Peer, Predecessor, Successor),
            node(Id, Predecessor, Successor, Store, Next, Replica);
        % our succ inform us about its pred
        {status, Pred, Nx} ->
            % io:format("[~p] state ~n", [Id]),
            {Succ, Nxt} = stabilize(Pred, Nx, Id, Successor),
            node(Id, Predecessor, Succ, Store, Nxt, Replica);
        % periodically ask succ's pred from succ, to make sure succ is right and updated
        % current stabilize/1 -> current.succ request -> current stabilize/3 -> (current think it is succ's pred and if current.succ dont know ) current.succ notify
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Store, Next, Replica);
        {ack, _} ->
            % should not handle it here, discard
            node(Id, Predecessor, Successor, Store, Next, Replica);
        {'DOWN', Ref, process, _, _} ->
            {Pred, Succ, Nxt, Store1, Replica1} = down(Ref, Predecessor, Successor, Next, Store, Replica, Id),
            node(Id, Pred, Succ, Store1, Nxt, Replica1);
        {replicate_batch, Qref, Data, FromPid} ->
            Replica1 = store:merge(Replica, Data),
            io:format("[~p succ.succ] recv replica_batch, merging [~p] data, replica has now [~p] data~n", [Id, store:size(Data), store:size(Replica1)]),
            FromPid ! Qref,
            node(Id, Predecessor, Successor, Store, Next, Replica1);
        {visualize, Starter, Seq, Acc, RingStr}  ->
            handle_visualize(Id, Starter, Seq, Acc, RingStr, Successor, Store, Replica),
            % handle_visualize(Id, Starter, Seq, Acc, RingStr, Predecessor, Store),
            node(Id, Predecessor, Successor, Store, Next, Replica);
        validate_store ->
            {Store1, Replica1} = validate_store(Id, Predecessor, Store),
            node(Id, Predecessor, Successor, Store1, Replica1, Id);
        stop ->
            io:format("[~p]: stopping...~n", [Id])
        % _Other ->
            % io:format("Unexpected msg: ~p~n", [_Other])
    end.

merge(Store, Elements, {_Skey, _, Spid}) ->
    Qref = make_ref(),
    Spid ! {replicate_batch, Qref, Elements, self()},
    receive
        Qref -> ok
    end,
    store:merge(Store, Elements).

% TODO: 这里由于只需要一个备份，不存在只进行了部分备份的问题
add(_, _, Qref, Client, _, nil, {_, Spid}, _) ->
    Client ! {Qref, error}; % mark-red happens when step 3 is done, step 4 not executed, else program stuck here
add(K, V, Qref, Client, Id, {Pkey, _, _}, {Skey, _, Spid}, Store) ->
    case key:between(K, Pkey, Id) of
        true ->
            case rand:uniform(?ReplicateTimeout) of
                ?ReplicateTimeout ->
                    io:format("add to [~p] failed, successor [~p]~n", [Id, Skey]),
                    % io:format("[~p] replicate to [~p] no response~n", [Id, Skey]),
                    Store1 = Store,
                    Spid ! stop,
                    Crash = true,
                    Client ! {Qref, error};
                    % recv a 'DOWN' before responding to other interrupt
                _ ->
                    Spid ! {replicate, Qref, K, V},
                    Crash = false,
                    Store1 = store:add(K, V, Store),
                    Client ! {Qref, ok}                
            end;
        false ->
            Store1 = Store,
            Crash = false,
            Spid ! {add, K, V, Qref, Client}
    end,
    {Crash, Store1}.

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

% Succ should always be not nil 
request(Peer, Predecessor, {Skey, _, Spid}) ->
    case Predecessor of
        nil -> Peer ! {status, nil, {Skey, Spid}};
        {Pkey, _, Ppid} -> Peer ! {status, {Pkey, Ppid}, {Skey, Spid}}
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

down(Ref, {Pkey, Ref, _}, Successor, Next, Store, Replica, Id) ->
    io:format("[~p succ]: [~p] is down~n", [Id, Pkey]),
    {Skey, _, Spid} = Successor,

    % 不能分为两个trx，在一起才能确保consistency
    io:format("[~p succ] waiting down.next.next replicate down.next's replica[size=~p](will later be merged into store), we have Store[size=~p] now~n", [Id, store:size(Replica), store:size(Store)]),
    Store1 = merge(Store, Replica, Successor), % ensure data is consistent before we respond to next event
    io:format("[~p succ] merging local replica [~p] data into store(now [~p] data), this increment has been sent to down.succ.succ [~p]~n", [Id, store:size(Replica), store:size(Store1), Skey]),
    % should also replicate bulk to next
    receive
        {replicate_all, Qref, PPStore, {PPkey, PPpid}} ->
            Replica1 = PPStore,
            io:format("[~p succ] received replica[size=~p] from down.previous node, now Store[size=~p], Replica[size=~p]~n", [Id, store:size(PPStore), store:size(Store1), store:size(Replica1)]),
            PPpid ! {Qref, {Skey, Spid}}
    end,

    {{PPkey, monitor(PPpid), PPpid}, Successor, Next, Store1, Replica1};

% succ is never nil, so nxt is never nil
down(Ref, Predecessor, {Skey, Ref, _}, {Nkey, Npid}, Store, Replica, Id) ->
    io:format("[~p prev]: [~p] is down~n", [Id, Skey]),

    Qref = make_ref(),
    Npid ! {replicate_all, Qref, Store, {Id, self()}},
    io:format("[~p prev] waiting for down.succ replicate our store[size=~p]~n", [Id, store:size(Store)]),
    receive
        % mark-red do not consider more than one node down
        {Qref, Nx} ->
            ok
    end,

    stabilize({Nkey, dontcare, Npid}),
    {Predecessor, {Nkey, monitor(Npid), Npid}, Nx, Store, Replica}.


handle_visualize(Id, Starter, Seq, Acc, RingStr, {_Skey, _, Spid}, Store, Replica) ->
    Self = self(),
    case Starter of
        Self -> Seq1 = Seq + 1;
        _Else -> Seq1 = Seq
    end,
    case Seq1 of
        2 -> io:format("Total ~p data, graph: ~p~n", [Acc, RingStr ++ integer_to_list(Id) ++ "(Store:" ++ integer_to_list(store:size(Store)) ++ ") (Replica:" ++ 
            integer_to_list(store:size(Replica)) ++ ")"]);
        % 2 -> io:format("Total ~p data~n", [Acc]);
        _ -> 
            Spid ! {visualize, Starter, Seq1, Acc + store:size(Store), RingStr ++ integer_to_list(Id) ++ "(Store:" ++ integer_to_list(store:size(Store)) ++ ") (Replica:" ++ 
            integer_to_list(store:size(Replica)) ++ ") --> "}
    end.

validate_store(Id, Predecessor, Store) ->
    case Predecessor of
        nil -> Store1 = Store;
        {Pkey, Ppid} -> 
            Store1 = handover(Id, Store, Pkey, Ppid, Id)
    end,
    Store1.

monitor(Pid) -> 
    Ref = erlang:monitor(process, Pid),
    % io:format("[~p] monitor [~p, ~p]~n", [self(), Pid, Ref]),
    Ref.

drop(nil) -> ok;
drop(Ref) -> 
    % io:format("[~p] demonitor [~p]~n", [self(), Ref]),
    erlang:demonitor(Ref, [flush]).