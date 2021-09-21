-module(dij).
-compile(export_all).

% 每次dij都需要完整图信息
% 单纯的dij无法保持路由信息，所以需要sorted

% Sorted: #{Dest => {Distance, NextHop}}
% Map: #{Location => [Neighbours]}

% return: routing table
dij(Map, Current) ->
    dij(Current, Map, #{Current => {0, Current}}, sets:new(), sets:new(), Current).

% Map, Map, Set, Set, atom
dij(_, #{}, _, _, _, _) ->
    #{};
dij(_, _, Sorted, _, _, "") ->
    Sorted;
    % print_sorted(Sorted);
dij(From, Map, Sorted, VisitedBefore, ToVisitBefore, Base) ->
    Visited = sets:add_element(Base, VisitedBefore),
    ToVisit = sets:del_element(Base, ToVisitBefore),

    Neighbours = map:neighbours(Base, Map),
    io:format("Now at: [~s], Neighbours: [~p]~n", [Base, Neighbours]),

    #{Base := {BaseDistance, BaseNextHop}} = Sorted,
    {UpdatedSorted, UpdatedToVisit} = lists:foldl(fun(Neighbour, Ctx) ->
        {Srted, ToVis} = Ctx,
        Seen = sets:is_element(Neighbour, Visited),
        if
            Seen ->
                ok;
            true ->
                UpdatedToVisit = sets:add_element(Neighbour, ToVis),
                if
                    BaseNextHop == From ->
                        {updateSorted(Srted, Neighbour, BaseDistance + 1, Neighbour), UpdatedToVisit};
                    true ->
                        {updateSorted(Srted, Neighbour, BaseDistance + 1, BaseNextHop), UpdatedToVisit}
                end
        end
    end, {Sorted, ToVisit}, Neighbours),
    io:format("Tovisit: [~p]~n", [sets:to_list(UpdatedToVisit)]),
    Next = next(sets:to_list(UpdatedToVisit), UpdatedSorted, 2147483647, ""), % "" if no more place to visit
    dij(From, Map, UpdatedSorted, Visited, UpdatedToVisit, Next).

table(Current, Map) ->
    Sorted = dij(Map, Current),
    Keys = maps:keys(Sorted),
    table(Sorted, Keys, []).

table(_Sorted, [], Collect) ->
    Collect;
table(Sorted, Keys, Collect) ->
    [First|Rest] = Keys,
    #{First := {_, NextHop}} = Sorted, % may debug distance here
    table(Sorted, Rest, Collect#{First => NextHop}).

route(Node, Table) ->
    case maps:find(Node, Table) of
        {ok, NextHop} ->
            NextHop;
        error ->
            notfound
    end.

% next node to iterate in dij
next([], _, _, CurLoc) ->
    CurLoc;
next(ToVisit, Sorted, CurMin, CurLoc) ->
    [Head|Rest] = ToVisit,
    case maps:find(Head, Sorted) of 
        {ok, {Dist, _}} ->
            if
                Dist < CurMin ->
                    next(Rest, Sorted, Dist, Head);
                true ->
                    next(Rest, Sorted, CurMin, CurLoc)
            end;
        error ->
            unexpected
    end.


updateSorted(Sorted, Dest, Dist, NextHop) ->
    case maps:find(Dest, Sorted) of
        {ok, {DistOld, _}} ->
            if
                Dist < DistOld ->
                    Sorted#{Dest => {Dist, NextHop}};                            
                true ->
                    Sorted
            end;
        error ->
            Sorted#{Dest => {Dist, NextHop}}
    end.

% ================= FOR DEBUG =================

print_sorted(Sorted) ->
    print_sorted(Sorted, maps:keys(Sorted)).

print_sorted(_, []) ->
    ok;
print_sorted(Sorted, Keys) ->
    [Head|Rest] = Keys,
    #{Head := {Distance, NextHop}} = Sorted,
    io:format("To [~s] need [~B] hops, next hop [~s]~n", [Head, Distance, NextHop]),
    print_sorted(Sorted, Rest).

    % 找next， 
    % (Nei, Sorted) 
    % UpdateNeighbour = fun() 

test() ->
    Map = #{a => [b, c], b => [c, d], c => [e], d => [e], f => [d]},
    dij(Map, a).
