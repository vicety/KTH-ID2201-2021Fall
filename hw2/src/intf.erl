-module(intf).
-compile(export_all).

new() ->
    {#{}, #{}, #{}}.

add(Name, Pid, Ref, Intf) ->
    {NameToPid, NameToRef, RefToName} = Intf,
    NameToPid1 = NameToPid#{Name => Pid},
    NameToRef1 = NameToRef#{Name => Ref},
    RefToName1 = RefToName#{Ref => Name},
    {NameToPid1, NameToRef1, RefToName1}.

% will we need this?
remove(Name, Intf) ->
    {NameToPid, NameToRef, RefToName} = Intf,
    NameToPid1 = maps:remove(Name, NameToPid),
    NameToRef1 = maps:remove(Name, NameToRef),
    RefToName1 = maps:remove(Name, RefToName),
    {NameToPid1, NameToRef1, RefToName1}.

ref(Name, Intf) ->
    {_, NameToRef, _} = Intf,
    case maps:find(Name, NameToRef) of
        {ok, Ref} ->
            {ok, Ref};
        error ->
            notfound
    end.

name(Ref, Intf) ->
    {_, _, RefToName} = Intf,
    case maps:find(Ref, RefToName) of
        {ok, Name} ->
            {ok, Name};
        error ->
            notfound
    end.

pid(Name, Intf) ->
    {NameToPid, _, _} = Intf,
    case maps:find(Name, NameToPid) of
        {ok, Pid} ->
            {ok, Pid};
        error ->
            notfound
    end.

broadcast(Message, Intf) ->
    {NameToPid, _, _} = Intf,
    lists:map(fun(Pid) -> Pid ! Message end, maps:values(NameToPid)).

send(NextHop, To, Message, Intf) ->
    {NameToPid, _, _} = Intf,
    case maps:find(NextHop, NameToPid) of
        {ok, Pid} ->
            io:format("send NextHop ~p Pid ~p To ~p, ~p~n", [NextHop, Pid, To, Message]),
            Pid ! {send, Message, To};
        error ->
            notfound
    end.
