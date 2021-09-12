-module(util).
-compile(export_all).

config(Key) ->
    case file:consult("server.config") of
        {ok, [CfgMap]} -> 
            io:format("~p~n", [CfgMap]),
            #{Key := Val} = CfgMap,
            Val;
        {error, _} ->
            error
    end.

debug(Msg) ->
    
