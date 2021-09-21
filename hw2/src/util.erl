-module(util).
-compile(export_all).

readFile(FileName) ->
    case file:consult(FileName) of
        {ok, Data} ->
            % io:format("~p~n", [Data]);
            Data;
        {error, Reason} ->
            io:format("readFile failed: ~p~n", [Reason])
    end.