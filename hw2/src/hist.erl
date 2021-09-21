-module(hist).
-compile(export_all).

% CurrentNode, HistoryMap#{Node => N}
new(CurrentNode) ->
    {CurrentNode, #{}}.

% if node restart, other node will recognize this as a new node since name same but process id differs
% if RemoteProcessID
update(Node, N, History) ->
    {Current, HistoryMap} = History,
    case Node of
        Current -> % ignore message from self
            old;
        _ ->
            case maps:find(Node, HistoryMap) of
                {ok, OldN} ->
                    if
                        N > OldN ->
                            {new, {Current, HistoryMap#{Node => N}}};
                        true -> % process id differs
                            old
                    end;
                error -> % first time this node occurs
                    io:format("received first message from ~p~n", [Node]),
                    {new, {Current, HistoryMap#{Node => N}}}
            end
    end.
            
reset(Node, History) ->
    {_Current, HistoryMap} = History, 
    case maps:find(Node, HistoryMap) of
        {ok, _OldN} ->
            {_Current, HistoryMap#{Node => -1}};
        error ->
            io:format("reset unseen node ~p~n", [Node]), % did not receive any msg of this node, has no history of it
            History
    end.


% register(history, spawn(?MODULE, loop, [self(), CurrentNode, #{}])). 