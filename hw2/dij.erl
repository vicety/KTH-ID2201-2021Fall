-module(dij).
-compile(export_all).

% 每次dij都需要完整图信息
% 单纯的dij无法保持路由信息，所以需要sorted

% Sorted: #{Dest => {Distance, NextHop}}
% Map: #{Location => [Neighbours]}

% return: routing table
dij(Map, Current) ->
    dij(Map, #{}, sets:new(), sets:new(), Current).

% Map, Map, Set, Set, atom
dij(_, Sorted, _, _, "") ->
    print_sorted(Sorted);
dij(Map, Sorted, VisitedBefore, ToVisitBefore, Base) ->
    Visited = sets:add_element(Base, VisitedBefore),
    ToVisit = sets:del_element(Base, ToVisitBefore),

    Neighbours = map:neighbours(Base, Map),
    #{Base := {BaseDistance, BaseNextHop}} = Sorted,
    UpdatedSorted = lists:foldl(fun(Neighbour, Srted) ->
        Seen = sets:is_element(Neighbour, Visited),
        if
            Seen ->
                ok; % seems buggy here, maybe return an unupdated Srted
            true ->
                sets:add_element(Neighbour, ToVisit),
                updateSorted(Srted, Neighbour, BaseDistance + 1, BaseNextHop) 
        end
    end, Sorted, Neighbours),
    Next = next(sets:to_list(ToVisit), UpdatedSorted, 2147483647, ""), % "" if no more place to visit
    dij(Map, UpdatedSorted, Visited, ToVisit, Next).



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

% list,
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
        {ok, {DistOld, NextHopOld}} ->
            if
                Dist < DistOld ->
                    Sorted#{Dest => {Dist, NextHop}};                            
                true ->
                    Sorted
            end;
        error ->
            Sorted#{Dest => {Dist, NextHop}}
    end.

test() ->
    Map = #{a => [b, c], b => [c, d], c => [e], d => [e], f => [d]},
    dij(Map, a).
