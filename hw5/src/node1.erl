-module(node1).
-compile(export_all).

-define(Stabilize, 200).
-define(Timeout, 5000).

% A = node1:start(100).
% node1:start(200, A).
% node1:visualize(A).
test() ->
    Start = start(key:generate()),
    timer:sleep(2000),
    start(key:generate(), Start),
    timer:sleep(2000),
    start(key:generate(), Start),
    timer:sleep(2000),
    start(key:generate(), Start),
    timer:sleep(2000),
    start(key:generate(), Start),
    timer:sleep(2000),
    start(key:generate(), Start).


start(Id) ->
    First = start(Id, nil),
    spawn(fun() -> timer:sleep(2000), timer:send_interval(2000, First, {visualize, First, 0, ""}) end),
    First.

start(Id, Peer) ->
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    {ok, Successor} = connect(Id, Peer),
    schedule_stabilize(), % TODO：有必要立即call一次stabilize？
    node(Id, nil, Successor).

% return succ, set succ as self if is first node
connect(Id, nil) ->
    {ok, {Id, self()}};
connect(_Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        % 随便拉一个接入点，之后stabilize的时候，如果发现succ指出的prev不是自己，那么认为prev是自己的succ，总会找到的，属实是坑
        {Qref, Skey} ->
            {ok, {Skey, Peer}} 
    after ?Timeout ->
        io:format("Timeout: no response from peer~n", [])
    end.

visualize(StartNode) ->
    StartNode ! {visualize, StartNode, 0, ""}.

node(Id, Predecessor, Successor) ->
    receive
        {visualize, Starter, Seq, RingStr}  ->
            handle_visualize(Id, Starter, Seq, RingStr, Successor),
            node(Id, Predecessor, Successor);
        % newly added peer need to know our key
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor);
        % new node inform us its existance
        % 只看见了pred可能会notice我们，此节点认为是我们的pred，尽量维护前向的正确性
        {notify, New} ->
            Pred = notify(New, Id, Predecessor),
            node(Id, Pred, Successor);
        % predecessor's stabilize func calls this,
        %  need to know our pred
        {request, Peer} ->
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor);
        % our succ inform us about its pred
        {status, Pred} ->
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ);
        % periodically ask succ's pred from succ, to make sure succ is right and updated
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor);
        _Other ->
            io:format("Unexpected msg: ~p~n", [_Other])
    end.

handle_visualize(Id, Starter, Seq, RingStr, {_Skey, Spid}) ->
    Self = self(),
    case Starter of
        Self -> Seq1 = Seq + 1;
        _Else -> Seq1 = Seq
    end,
    case Seq1 of
        2 -> io:format("~p~n", [RingStr ++ integer_to_list(Id)]);
        _ -> 
            Spid ! {visualize, Starter, Seq1, RingStr ++ integer_to_list(Id) ++ " --> "}
    end.

request(Peer, Predecessor) ->
    case Predecessor of
        nil -> Peer ! {status, nil};
        {Pkey, Ppid} -> Peer ! {status, {Pkey, Ppid}}
    end.

% periodically triggered, ask succ about its pred
stabilize({_, Spid}) ->
    Spid ! {request, self()}.

% when got successor's pred, return current succ
stabilize(Pred, Id, Successor) ->
    {Skey, Spid} = Successor,
    case Pred of
        % just join, no pred(maybe first node, maybe not)
        nil ->
            Spid ! {notify, {Id, self()}}, % should tell him I am your pred
            Successor;
        {Id, _} -> % it's me
            Successor;
        % TODO: what about multiple concurrent join?
        % my succ's pred is my succ, meaning first(and only) node has stabilized at least once
        {Skey, _} ->
            Spid ! {notify, {Id, self()}}, % should tell him I am your pred
            Successor;
        {XKey, Xpid} -> % unk succ's pred
            % TODO：这里为啥会有个case，我猜是并发加入，所以connect给的succ不是真的succ
            case key:between(XKey, Id, Skey) of
                false -> % we are closer
                    Spid ! {notify, {Id, self()}}, % should tell him I am your pred
                    Successor;
                true -> % someone is closer
                    % run this again
                    stabilize({XKey, Xpid}),
                    {XKey, Xpid}
            end
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

% pred, id, pred_before
notify({Nkey, Npid}, Id, Predecessor) ->
    case Predecessor of
        nil ->
            {Nkey, Npid};
        {Pkey, _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    {Nkey, Npid};
                false ->
                    Predecessor
            end
    end.