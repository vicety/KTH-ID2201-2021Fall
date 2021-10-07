-module(node3).
-compile(export_all).

% simplify node2
-define(Stabilize, 100).
-define(Timeout, 5000).

start(Id) ->
    start(Id, nil).

start(Id, Peer) ->
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    {ok, Successor} = connect(Id, Peer),
    schedule_stabilize(), % TODO：有必要立即call一次stabilize？
    node(Id, nil, Successor, store:create()).

% return succ, set succ as self if is first node
connect(Id, nil) ->
    {ok, {Id, self()}};
connect(_Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            {ok, {Skey, Peer}} 
    after ?Timeout ->
        io:format("Timeout: no response from peer~n", [])
    end.

% Seen #{K => Seq}
node(Id, Predecessor, Successor, Store) ->
    receive
        {add, K, V, Qref, Client} ->
            case add(K, V, Qref, Client, Id, Predecessor, Successor, Store) of
                {Qref, error} ->
                    node(Id, Predecessor, Successor, Store);
                Added ->
                    node(Id, Predecessor, Successor, Added)
            end;    
        {lookup, K, Qref, Client} ->
            lookup(K, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Store);
        {handover, Qref, Elements, _FromKey, FromPid} ->
            FromPid ! {ack, Qref},
            Merged = store:merge(Store, Elements), 
            node(Id, Predecessor, Successor, Merged);
        % newly added peer need to know our key
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Store);
        % new node inform us its existance
        % 只看到pred notice我们时调用，此节点认为是我们的pred，尽量维护前向的正确性
        {notify, New} ->
            % io:format("[~p] notify ~p~n", [Id, New]),
            case notify(New, Id, Predecessor, Store) of
                {error, timeout} ->
                    self() ! {notify, New},
                    node(Id, Predecessor, Successor, Store);
                {Pred, Store1} ->
                    % io:format("here"),
                    node(Id, Pred, Successor, Store1)
            end;
        % predecessor's stabilize func calls this,
        %  need to know our pred
        {request, Peer} ->
            % io:format("[~p] request ~n", [Id]),
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor, Store);
        % our succ inform us about its pred
        {status, Pred} ->
            % io:format("[~p] state ~n", [Id]),
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ, Store);
        % periodically ask succ's pred from succ, to make sure succ is right and updated
        % current stabilize/1 -> current.succ request -> current stabilize/3 -> (current think it is succ's pred and if current.succ dont know ) current.succ notify
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Store);
        {ack, _} ->
            % should not handle it here, discard
            node(Id, Predecessor, Successor, Store);
        _Other ->
            io:format("Unexpected msg: ~p~n", [_Other])
    end.

add(_, _, Qref, Client, _, nil, _, _) ->
    Client ! {Qref, error}; % mark-red happens when step 3 is done, step 4 not executed, else program stuck here
add(K, V, Qref, Client, Id, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(K, Pkey, Id) of
        true ->
            Store1 = store:add(K, V, Store),
            Client ! {Qref, ok};
        false ->
            Store1 = Store,
            Spid ! {add, K, V, Qref, Client}
    end,
    Store1.

lookup(K, Qref, Client, _, nil, {_, Spid}, _) ->
    Spid ! {lookup, K, Qref, Client}; % mark-red happens between step3 and step4, just pass this to next, rare chance will reach here
lookup(K, Qref, Client, Id, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(K, Pkey, Id) of
        true ->
            Tmp = store:lookup(K, Store),
            Client ! {Qref, Tmp};
        false ->
            Spid ! {lookup, K, Qref, Client}
    end.

request(Peer, Predecessor) ->
    case Predecessor of
        nil -> Peer ! {status, nil};
        {Pkey, Ppid} -> Peer ! {status, {Pkey, Ppid}}
    end.

stabilize({_, Spid}) ->
    Spid ! {request, self()}.

stabilize(Pred, Id, Successor) ->
    {Skey, Spid} = Successor,
    case Pred of
        % just join, no pred(maybe first node, maybe not)
        nil ->
            % io:format("[~p] send notify to [~p]~n", [Id, Skey]),
            Spid ! {notify, {Id, self()}}, % tell him I am your pred
            Successor;
        {Id, _} -> % succ's pred is me
            Successor;
        % my succ's pred is my succ, meaning first(and only) node has stabilized at least once, and (another node is joining or first node stabilize again)
        {Skey, _} ->
            Spid ! {notify, {Id, self()}}, % tell him I am your pred
            Successor;
        {XKey, Xpid} ->
            case key:between(XKey, Id, Skey) of
                false -> % we are succ's closer pred
                    Spid ! {notify, {Id, self()}}, % should tell him I am your pred
                    Successor;
                true -> % someone is closer
                    % trigger this immediately
                    stabilize({XKey, Xpid}),
                    {XKey, Xpid}
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
                    timer:sleep(100),
                    {{Nkey, Npid}, Store1};
                {error, timeout} ->
                    {error, timeout}
            end;
            % timer:sleep(150),
            
        {Pkey, _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    case handover(Id, Store, Nkey, Npid, Id) of
                        {ok, Store1} ->
                            timer:sleep(100),
                            {{Nkey, Npid}, Store1};
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
            % after 500 ->
            %     io:format("[~p] timeout to [~p]~n", [Id, Nkey]),
            %     {error, timeout}
            end
    end.

