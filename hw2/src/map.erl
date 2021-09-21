-module(map).
-compile(export_all).

new() ->
    #{}.

update(Node, Links, Map) ->
    Map#{Node => Links}.
    % lists:foldl(fun(Ele, Mp) -> Mp#{Node})

neighbours(Node, Map) ->
    case maps:find(Node, Map) of
        {ok, Neighbours} ->
            Neighbours;
        error ->
            []
    end.

all_nodes(Map) ->
    Set = sets:from_list(maps:keys(Map)),
    all_nodes(Set, maps:values()).
    
all_nodes(Set, []) ->
    Set;
all_nodes(Set, Lists) ->
    [Li|Rest] = Lists,
    UpdatedSet = lists:foldl(fun(Ele, St) -> sets:add_element(Ele, St) end, Set, Li),
    all_nodes(UpdatedSet, Rest).