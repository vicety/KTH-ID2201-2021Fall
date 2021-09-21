-module(hist).
-compile(export_all).

% CurrentNode, HistoryMap#{Node => N}
new(CurrentNode) ->
    {CurrentNode, #{}}.

% if node restart, other node will recognize this as a new node since name same but process id differs
% if RemoteProcessID
update(Node, N, History, RandomNum) ->
    {Current, HistoryMap} = History,
    case Node of
        Current -> % ignore message from self
            old;
        _ ->
            case maps:find(Node, HistoryMap) of
                {ok, {OldN, OldRandomNum}} ->
                    if
                        RandomNum =/= OldRandomNum -> % this node restarts
                            {new, {Current, HistoryMap#{Node => {N, RandomNum}}}};
                        N > OldN ->
                            {new, {Current, HistoryMap#{Node => {N, OldRandomNum}}}};
                        true -> % process id differs
                            old
                    end;
                error -> % first time this node occurs
                    io:format("received first message from ~p~n", [Node]),
                    {new, {Current, HistoryMap#{Node => {N, RandomNum}}}}
            end
    end.
            
reset(Node, History) ->
    {_Current, HistoryMap} = History, 
    case maps:find(Node, HistoryMap) of
        {ok, {_OldN, _OldRandomNum}} ->
            {_Current, HistoryMap#{Node => {-1, -0.1}}};
        error ->
            io:format("reset unseen node ~p~n", [Node]), % did not receive any msg of this node, has no history of it
            History
    end.


% register(history, spawn(?MODULE, loop, [self(), CurrentNode, #{}])). 