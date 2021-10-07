-module(node2).
-compile(export_all).

-define(Stabilize, 100).
-define(Timeout, 5000).

% mark-red
% 新加入的节点A何时能够被完全认识到？以下按时间排列
% 1 A.succ：加入时的succ是随便选的，之后stabilize的时候，如果发现自己所在的位置没有比succ指出的prev更优，那么认为prev是自己的succ，一个个逆时针找，最终能够找到合法的succ，向其notify，不考虑节点来去，此操作应该O1成功，平均On
% 2 succ.pred: in step 1, succ been notified, and mark A as its pred 
% 3 prev.succ: pred定时stabilize向succ，succ返回A，pred认为A是更优的succ
% 4 A.prev：after step3，succ定时stabilize向A，A此时的prev还是nil，无条件接受

% what happens when a node A joins
% These values should be confirmed before this node has fully joined the system. The confirmed time of the following values are ordered by time.
% 1. A.succ:    when calling stabilize/1, succ calls request/2, A calls stabilize/3, if A's position is more suitable to be succ's prev than succ.prev, than A.succ is confirmed,
%               else set succ.prev as A.succ, waiting for next stabilize to come.
% 2. succ.pred: after A.succ is confirmed, A will notify A.succ that A is its pred, succ.pred is confirmed now, also data will be transfered. (if no concurrent node join/leave)
%               mark-red the circle is not complete now
% 3. pred.succ: pred periodically ask predecessor from pred.succ(which is not A), pred.succ tells pred that A, rather than pred is its predecessor, than prev.succ is set to A, this value is confirmed.
% 4. A.pred:    after step3, will receive a notify saying pred is A's pred

% step 1 takes average N / 2 * Stabilize Interval
% step 2 takes no time(comparing to Stabilize Interval)
% step 3 takes average Stabilize Interval / 2
% step 4 takes no time(comparing to Stabilize Interval)

% TODO: 还有很多消息没有add上，尽管add是成功的
% TODO：还有minor消息没有查找成功

start(Id) ->
    First = start(Id, nil),
    % spawn(fun() -> timer:sleep(2000), timer:send_interval(3000, First, {visualize, First, 0, 0, ""}) end),
    register(printer, spawn(fun() -> async_printer() end)),
    register(counter, spawn(fun() -> counter(0, 0) end)),
    % register(addminus, spawn(fun() -> addminus(#{}) end)),
    register(db, spawn(fun() -> db(#{}) end)),
    First.

async_printer() ->
    receive
        {K, Pkey, Id} -> 
            % io:format("error, K=~p Pkey=~p Id=~p~n", [K, Pkey, Id]),
            db ! {q, K},
            timer:sleep(2000),
            async_printer();
        {inconsistent, K, Pkey, Id} ->
            % io:format("inconsistent error, K=~p Pkey=~p Id=~p~n", [K, Pkey, Id]),
            % db ! {q, K},
            timer:sleep(1000),
            async_printer()
    end.

counter(Now, Inconsistent) ->
    receive
        add -> counter(Now+1, Inconsistent);
        inconsistent ->  
            counter(Now, Inconsistent+1)
    after 500 ->
        io:format("get counter now ~p inconsistent ~p~n", [Now, Inconsistent]),
        counter(Now, Inconsistent)
    end.

addminus(Mp) ->
    receive
        {minus, N} -> 
            case N of
                0 -> addminus(Mp);
                _ -> addminus(Mp#{N => 1})
            end;
        {add, N} -> 
            case N of
                0 -> addminus(Mp);
                _ -> 
                    case maps:is_key(N, Mp) of
                    true ->
                        addminus(maps:remove(N, Mp));
                    false ->
                        io:format("Unexpected N ~p~n", [N]), % TODO: 有时候会出现
                        addminus(Mp)
                end
            end
    after 3000 ->
        io:format("remaining Mp: ~p~n", [Mp]) 
    end.

db(DB) ->
    receive
        {q, K} -> 
            #{K := V} = DB,
            % io:format("~p: ~p~n", [K, V]),
            db(DB);
        {add, K, V} -> 
            case maps:is_key(K, DB) of
                false ->
                    db(DB#{K => [V]});
                true ->
                    #{K := OldV} = DB,
                    db(DB#{K => OldV ++ [V]}) 
            end
    end.

start(Id, Peer) ->
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    {ok, Successor} = connect(Id, Peer),
    schedule_stabilize(), % TODO：有必要立即call一次stabilize？
    schedule_store_validation(),
    node(Id, nil, Successor, store:create()).

% return succ, set succ as self if is first node
connect(Id, nil) ->
    {ok, {Id, self()}};
connect(_Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        % 随便拉一个接入点，
        {Qref, Skey} ->
            {ok, {Skey, Peer}} 
    after ?Timeout ->
        io:format("Timeout: no response from peer~n", [])
    end.

visualize(StartNode) ->
    StartNode ! {visualize, StartNode, 0, ""}.

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
        {handover, Elements} ->
            % addminus ! {add, store:size(Elements)},
            Merged = store:merge(Store, Elements), % 可以解决问题，会慢很多，解决了更好的prev先来，无任何东西可split，handover后到，此时又没有交给更好的prev
            % maps:foreach(fun(K, _V) ->
            %     case store:lookup(K, Merged) of
            %         false -> io:format("not found ~n");
            %         _ -> ok
            %     end
            % end, Elements),
            % io:format("before ~p, elements ~p, merged ~p~n", [store:size(Store), store:size(Elements), store:size(Merged)]),

            % TODO: 问题应该是这个问题，但是下面的方法好像不对
            % case Predecessor of
            %     nil ->
            %         node(Id, Predecessor, Successor, Merged);
            %     {Pkey, Ppid} ->
            %         {Store1, Shares} = store:split(Id, Pkey, Store),
            %         % addminus ! {minus, store:size(Shares)},
            %         Ppid ! {handover, Shares},
            %         maps:foreach(fun(K, _V) ->
            %             db ! {add, K, {handover1, Pkey}} % move to Nkey
            %         end, Shares),
            %         node(Id, Predecessor, Successor, Store1)
            % end;
            node(Id, Predecessor, Successor, Merged);    
        {visualize, Starter, Seq, Acc, RingStr}  ->
            handle_visualize(Id, Starter, Seq, Acc, RingStr, Successor, Store),
            % handle_visualize(Id, Starter, Seq, Acc, RingStr, Predecessor, Store),
            node(Id, Predecessor, Successor, Store);
        % newly added peer need to know our key
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Store);
        % new node inform us its existance
        % 只看到pred notice我们时调用，此节点认为是我们的pred，尽量维护前向的正确性
        {notify, New} ->
            {Pred, Store1} = notify(New, Id, Predecessor, Store),
            node(Id, Pred, Successor, Store1);
        % predecessor's stabilize func calls this,
        %  need to know our pred
        {request, Peer} ->
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor, Store);
        % our succ inform us about its pred
        {status, Pred} ->
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ, Store);
        % periodically ask succ's pred from succ, to make sure succ is right and updated
        % current stabilize/1 -> current.succ request -> current stabilize/3 -> (current think it is succ's pred and if current.succ dont know ) current.succ notify
        % 如上，如果一个节点A需要更新Pred，那么需要有一个认为自己是A的pred的节点，
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Store);
        validate_store ->
            validate_store(Id, Predecessor, Store),
            node(Id, Predecessor, Successor, Store);
        _Other ->
            io:format("Unexpected msg: ~p~n", [_Other])
    end.

% mark-red pred could possibly be nil
% 已确认所有的add fail都来自这里，按照论文上的重试方案可以解决所有失败
add(_, _, Qref, Client, _, nil, _, _) ->
    % counter ! add,
    Client ! {Qref, error}; % happens when step 3 is done, step 4 not executed
add(K, V, Qref, Client, Id, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(K, Pkey, Id) of
        true ->
            % counter ! add, % TODO: 发现这里延迟越大，丢失的数据越少
            % case rand:uniform(100) of
            %     10 -> timer:sleep(10);
            %     _ -> ok
            % end,s
            db ! {add, K, {addTo, Id}},
            Store1 = store:add(K, V, Store),
            Client ! {Qref, ok};
        false ->
            Store1 = Store,
            Spid ! {add, K, V, Qref, Client}
    end,
    Store1.

lookup(K, Qref, Client, Id, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(K, Pkey, Id) of
        true ->
            Tmp = store:lookup(K, Store),
            Client ! {Qref, Tmp},
            case Tmp of
                false ->
                    printer ! {K, Pkey, Id};
                _ -> ok
            end;
        false ->
            Spid ! {lookup, K, Qref, Client}
    end.

handle_visualize(Id, Starter, Seq, Acc, RingStr, {_Skey, Spid}, Store) ->
    Self = self(),
    case Starter of
        Self -> Seq1 = Seq + 1;
        _Else -> Seq1 = Seq
    end,
    case Seq1 of
        2 -> io:format("Total ~p data, graph: ~p~n", [Acc, RingStr ++ integer_to_list(Id) ++ "(" ++ integer_to_list(store:size(Store)) ++ ")"]);
        _ -> 
            Spid ! {visualize, Starter, Seq1, Acc + store:size(Store), RingStr ++ integer_to_list(Id) ++ "(" ++ integer_to_list(store:size(Store)) ++ ")" ++ " --> "}
    end.

% TODO：必须要有人认为自己是他的succ才能被call到
request(Peer, Predecessor) ->
    case Predecessor of
        nil -> Peer ! {status, nil};
        {Pkey, Ppid} -> Peer ! {status, {Pkey, Ppid}}
    end.

% periodically triggered, ask succ about its pred
stabilize({_, Spid}) ->
    Spid ! {request, self()}.

% when got successor's pred, return current succ, used to maintain right succ
% TODO：
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
        % my succ's pred is my succ, meaning first(and only) node has stabilized at least once, and another node joining will use this
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

schedule_store_validation() ->
    timer:send_interval(2000, self(), validate_store).

% pred, id, pred_before  used to maintain right pred
notify({Nkey, Npid}, Id, Predecessor, Store) ->
    case Predecessor of
        nil ->
            % io:format("Nkey ~p, Id ~p, size: ~p~n", [Nkey, Id, store:size(Store)]),
            Store1 = handover(Id, Store, Nkey, Npid, Id),
            {{Nkey, Npid}, Store1};
        {Pkey, _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    Store1 = handover(Id, Store, Nkey, Npid, Id),
                    % Store1 = handover(Pkey, Store, Nkey, Npid, Id), % 都是一样的
                    {{Nkey, Npid}, Store1};
                false ->
                    {Predecessor, Store}
            end
    end.

handover(Pkey, Store, Nkey, Npid, Id) ->
    % io:format("store: ~p~n", [Store]),
    {Store1, Shares} = store:split(Pkey, Nkey, Store),
    maps:foreach(fun(K, _V) ->
        db ! {add, K, {handover, Nkey}} % move to Nkey
    end, Shares),
    % addminus ! {minus, store:size(Shares)},
    % ShareSz = store:size(Shares),
    % case ShareSz of
    %     0 -> ok;
    %     _ -> io:format("split from (~p,~p] to (~p,~p], moving ~p/~p elements~n", [Pkey, Id, Pkey, Nkey, ShareSz, store:size(Store)])
    % end,
    Npid ! {handover, Shares},
    Store1.


validate_store(Id, Predecessor, Store) ->
    case Predecessor of
        nil -> ok;
        {Pkey, _} ->
            maps:foreach(fun(K, _V) ->
                case key:between(K, Pkey, Id) of
                    true -> ok;
                    false -> 
                        % printer ! {inconsistent, K, Pkey, Id}
                        counter ! inconsistent
                end
            end, Store)
    end.


% ============== CASE 1 ====================
% sleep 0 400k keys, 32 nodes, add/lookup form single node

% 1> 392219 unique keys
% 1> 400000 add operation in 5103 ms
% 1> 44350 add failed, 0 caused a timeout
% 1> 400000 lookup operation in 1852 ms
% 1> 42851 lookups failed, 0 caused a timeout
% 1> lookup done
% 1> Total 349458 data, graph: "0(26135) --> 35584(1244) --> 78237(1497) --> 446075(12750) --> 1232764(27393) --> 1280690(1645) --> 1712617(15107) --> 2092929(13334) --> 2121782(1056) --> 2250665(4575) --> 2273590(771) --> 2794341(18239) --> 3601249(28242) --> 3826118(7902) --> 3973611(5269) --> 4161369(6508) --> 4915739(26151) --> 5458605(19004) --> 5687019(7811) --> 5717965(1088) --> 6012362(10231) --> 6908360(31406) --> 7325930(14589) --> 7923512(20818) --> 8071109(5223) --> 8134111(2160) --> 8354368(7701) --> 8473733(4185) --> 8557287(2980) --> 8645987(3141) --> 9036172(13718) --> 9253054(7585) --> 0(26135)"

% what about add sleep between add and lookup

% 1> 392219 unique keys
% 1> 400000 add operation in 4856 ms
% 1> 45840 add failed, 0 caused a timeout
% 1> Total 348598 data, graph: "0(26019) --> 35584(1135) --> 78237(1252) --> 446075(10684) --> 1232764(22917) --> 1280690(1348) --> 1712617(12588) --> 2092929(16875) --> 2121782(956) --> 2250665(4203) --> 2273590(721) --> 2794341(16679) --> 3601249(25843) --> 3826118(7270) --> 3973611(4815) --> 4161369(5941) --> 4915739(38326) --> 5458605(18925) --> 5687019(7187) --> 5717965(1716) --> 6012362(10177) --> 6908360(31290) --> 7325930(14509) --> 7923512(20731) --> 8071109(5200) --> 8134111(2151) --> 8354368(7665) --> 8473733(4165) --> 8557287(2963) --> 8645987(3124) --> 9036172(13658) --> 9253054(7565) --> 0(26019)"
% 1> 400000 lookup operation in 1820 ms
% 1> 61413 lookups failed, 0 caused a timeout
% 1> lookup done