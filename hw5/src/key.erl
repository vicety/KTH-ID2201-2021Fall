-module(key).
-compile(export_all).

% -define(SIZE, 1073741824). % 2^30
-define(SIZE, 10000000). % 10 million

% TODO: number collision
generate() ->
    rand:uniform(?SIZE) - 1. 

% TODO: 处理环形
between(_, From, To) when From == To ->
    true; % when only one node in the system
between(Key, From, To) -> % (From, To]
    case From > To of
        true ->
            if
                ((Key > From) or (Key =< To)) ->
                    true;
                true ->
                    false
            end;
        false -> 
            if
                (Key > From) and (Key =< To)  ->
                    true;
                true ->
                    false
            end
    end.
