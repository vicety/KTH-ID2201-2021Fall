-module(store).
-compile(export_all).

create() ->
    #{}.

add(K, V, Store) ->
    Store#{K => V}.

lookup(K, Store) ->
    case maps:is_key(K, Store) of
        true ->
            #{K := V} = Store,
            {K, V};
        false ->
            false
    end.

size(Store) ->
    maps:size(Store).

% (From, To]
split(From, To, Store) ->
    Keys = maps:keys(Store),
    {St, Sh} = lists:foldl(fun(K, {Sto, Share}) ->
        case key:between(K, From, To) of
            true ->
                #{K := V} = Sto,
                Sto1 = maps:remove(K, Sto),
                Share1 = Share#{K => V};
            false ->
                Sto1 = Sto,
                Share1 = Share
        end,
        {Sto1, Share1}
    end, {Store, #{}}, Keys),
    
    % LenSt = maps:size(St),
    % LenSh = maps:size(Sh),
    % LenStore = maps:size(Store),
    % case LenSt + LenSh == LenStore of
    %     false ->
    %         io:format("YYYYYYYYYYYYYYY~n");
    %     true -> ok
    % end,

    {St, Sh}.

merge(Entries, Store) ->
    maps:merge(Store, Entries).


% create() ->
%     [].

% add(K, V, Store) ->
%     [{K, V} | Store].

% lookup(K, Store) ->
%     lists:keyfind(K, 1, Store).

% size(S) ->
%     length(S).

% % split(From, To, Store) ->
% %     {Share, Store} = lists:partition(fun({K, _}) -> key:between(K, From, To) end, Store),
% %     io:format("HHHHHHHHHHHHH~n"),
% %     {Store, Share}.

% split(From, To, Store) -> 
% 	{Share, Store1} = lists:partition(fun({Key, _}) -> 
% 							key:between(Key, From, To) end, Store),
%     {Store1, Share}.

% merge(A, B) ->
%     lists:merge(A, B).