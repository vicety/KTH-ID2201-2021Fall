-module(worker).

% -export([start/4, start/5, gsm1/0, gsm2/0, gsm3/0, gsm3_restart/0, gsm4/0]).
-compile(export_all).

-define(change, 20).
-define(color, {0,0,0}).

% ======= gsm1 =========

% no one dies

gsm1() ->
	A = worker:start(1, gsm1, 114, 2000),
	timer:sleep(100),
	B = worker:start(2, gsm1, 115, A, 2000),
	timer:sleep(100),
	C = worker:start(3, gsm1, 116, B, 2000).

% ======= gsm2 =========

% process 1 very quick

gsm2() ->
	A = worker:start(1, gsm2, 114, 3000),
	timer:sleep(100),
	B = worker:start(2, gsm2, 115, A, 3000),
	timer:sleep(100),
	C = worker:start(3, gsm2, 116, B, 3000),
	timer:sleep(100),
	D = worker:start(4, gsm2, 118, B, 3000),
	timer:sleep(100),
	E = worker:start(5, gsm2, 119, B, 3000).
	% A ! stop.

% ======= gsm3 =========
% worker:gsm3().
% {}
% 
% case 1 [113, 514, 1919, 810, 893]  timeout=2000 crashN=50
% case 2 [12, 23, 34, 45, 56]  timeout=2000 crashN=50

% 会不会存在join不成功，也就是这个view未完全发送：不存在，目前不存在发送的第一个节点即非正确节点的情况
% 会不会存在join成功，但是后续的color同步不成功：基本不存在，同上，选举机制确保了只要有节点存活就一定能继续传递，唯一的例外是，join的时候挂到只剩自己，而自己的worker还没起来，因此没有running的worker可以回应这个state_request

% 好了，基本稳定，基于这个开始做4，加一个滚动重启

% 存在问题：消息完全没法出去，就挂了，怎么办

gsm3() ->
	A = worker:start(1, gsm3, 2, 2000),
	timer:sleep(200),
	B = worker:start(2, gsm3, 88, A, 2000),
	timer:sleep(200),
	C = worker:start(3, gsm3, 433, B, 2000),
	timer:sleep(200),
	D = worker:start(4, gsm3, 565888, C, 2000),
	timer:sleep(200),
	E = worker:start(5, gsm3, 4565888, D, 2000).

% gsm3_restart() ->
% 	A = worker:start(1, gsm3, 114, 2000),
% 	timer:sleep(100),
% 	B = worker:start(2, gsm3, 115, A, 2000),
% 	timer:sleep(100),
% 	C = worker:start(3, gsm3, 116, B, 2000),
% 	timer:sleep(100),
% 	D = worker:start(4, gsm3, 118, C, 2000),
% 	timer:sleep(100),
% 	E = worker:start(5, gsm3, 119, D, 2000),
% 	timer:sleep(100),
% 	new_worker(6).

% ======= gsm4 =========
gsm4() ->
	A = worker:start(1, gsm4, 114, 2000),
	timer:sleep(100),
	B = worker:start(2, gsm4, 115, A, 2000),
	timer:sleep(100),
	C = worker:start(3, gsm4, 116, B, 2000),
	timer:sleep(100),
	D = worker:start(4, gsm4, 118, B, 2000),
	timer:sleep(100),
	E = worker:start(5, gsm4, 119, B, 2000).

% assume communication to this thread is reliable
new_worker(Expect) ->
	register(new, spawn_link(fun() -> new_worker_loop(Expect) end)).

new_worker_loop(Expect) ->
	receive
		{new, Node} ->
			timer:sleep(100),
			{{Year, Month, Day}, {Hour, Minute, Second}} = calendar:now_to_datetime(erlang:now()),
			Time = lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w",[Year,Month,Day,Hour,Minute,Second])),
			io:format("Time=[~p] spawn ~p~n", [Time, Expect]),
			worker:start(Expect, gsm3, rand:uniform(1000), Node, 2000),
			Node ! ack,
			new_worker_loop(Expect+1)
	end.


% Start a worker given:
%  Id - a unique interger, only used for debugging
%  Module - the module we want to use, i.e. gms1
%  Rnd - a value to seed the random generator
%  Sleep  - for how long should we sleep between proposing state changes

% return master pid
start(Id, Module, Rnd, Sleep) ->
    spawn(fun() -> init(Id, Module, Rnd, Sleep) end).

% for master
init(Id, Module, Rnd, Sleep) ->
	% group loop
    {ok, Cast} = apply(Module, start, [Id, Rnd]),
    Color = ?color,
	% worker loop
    init_cont(Id, Rnd, Cast, Color, Sleep).

% Same as above, but now we join an existing worker
%  Peer - the process id of a worker

start(Id, Module, Rnd, Peer, Sleep) ->
    spawn(fun() -> init(Id, Module, Rnd, Peer, Sleep) end).

% for slave
init(Id, Module, Rnd, Peer, Sleep) ->
    {ok, Cast} = apply(Module, start, [Id, Peer, Rnd]),
    {ok, Color} = join(Id, Cast),
    init_cont(Id, Rnd, Cast, Color, Sleep).

% Wait for the first view to be delivered

join(Id, Cast) ->
    receive 
	{view, _} ->
	    Ref = make_ref(),
	    Cast ! {mcast, {state_request, Ref}},
	    state(Id, Ref);
	{error, Reason} ->
		io:format("Id:[~p] Reason:[~p]~n", [Id, Reason]),
	    {error, Reason}
    end.

% and then wait for the, state

state(Id, Ref) ->
    receive
	{state_request, Ref} ->
	    receive
		{state, Ref, Color} ->
		    {ok, Color}
	    end;
	_Ignore ->
	    state(Id, Ref)
    end.

% we're either the first worker or has joined an existing group, but
% know we know everything to continue. 
		
init_cont(Id, Rnd, Cast, Color, Sleep) ->
	rand:seed(exsss, Rnd),
    % rand:seed(Rnd, Rnd, Rnd),
    Title = "Worker: " ++ integer_to_list(Id),
    Gui = gui:start(Title, self()),
    Gui ! {color, Color}, 
    worker(Id, Cast, Color, Gui, Sleep),
    Cast ! stop,
    Gui ! stop.

% The worker process, 

worker(Id, Cast, Color, Gui, Sleep) ->
    Wait = wait(Sleep),
    receive

	%% Someone wants us to change the color
	{change, N} ->
	    % io:format("worker ~w change ~w~n", [Id, N]),
	    Color2 = change_color(N, Color),
	    Gui ! {color, Color2},
	    worker(Id, Cast, Color2, Gui, Sleep);

	%% Someone needs to know the state at this point
	{state_request, Ref} ->
	    Cast ! {mcast, {state, Ref, Color}},
	    worker(Id, Cast, Color, Gui, Sleep);

	%% A reply on a state request but we don't care	
	{state, _, _} ->
	    worker(Id, Cast, Color, Gui, Sleep);	    

	%% Someone wants to join our group
	{join, Peer, Gms} ->
	    Cast ! {join, Peer, Gms},
	    worker(Id, Cast, Color, Gui, Sleep);	    

	%% A view, who cares
	{view, _} ->
	    worker(Id, Cast, Color, Gui, Sleep);	    

	%% So I should stop for a while
	freeze ->
	    frozen(Id, Cast, Color, Gui, Sleep);	   

	%% Change the sleep time
	{sleep, Slp} ->
	    worker(Id, Cast, Color, Gui, Slp);	  

	%% That's all folks
	stop ->
	    ok;

	%% Someone from above wants us to multicast a message.
	{send, Msg} ->
	    Cast !  {mcast, Msg},	    
	    worker(Id, Cast, Color, Gui, Sleep);	    

	Error ->
    	    io:format("strange message: ~w~n", [Error]),
	    worker(Id, Cast, Color, Gui, Sleep)

    after Wait ->
	    %% Ok, let's propose a change of colors
	    %% io:format("worker ~w mcast message~n", [Id]),
	    Cast ! {mcast, {change, rand:uniform(?change)}},
	    worker(Id, Cast, Color, Gui, Sleep)	    
    end.


frozen(Id, Cast, Color, Gui, Sleep) ->
    receive 
	go ->
	    worker(Id, Cast, Color, Gui, Sleep);
	stop ->
	    ok;

	%% Someone from above wants us to multicast a message.
	{send, Msg} ->
	    Cast !  {mcast, Msg},	    
	    frozen(Id, Cast, Color, Gui, Sleep)
    end.


wait(Sleep) ->
    if 
	Sleep == 0 -> 
	    0; 
	true -> 
	    rand:uniform(Sleep) 
    end.

%% Change of color, we rotate RGB and add N. Since we also make a
%% rotations we will end up in very different state if we receive
%% messages in different order. If we have an initial state of {1,2,3}
%% and receive messages 10 and 20 we would end up in either {3,11,22}
%% or {3,21,12} depending on the order. 

change_color(N, {R,G,B}) ->
    {G, B, ((R+N) rem 256)}.



 

