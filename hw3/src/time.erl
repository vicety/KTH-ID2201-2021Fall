-module(time).
-compile(export_all).


% tutorial lamport clock利用sendRecv排序的逻辑放在log层，timer只负责计数，这里我在timer中也包含SendRecv信息，因为我认为SendRecv也是一个dimension to repersent time

new(na, _Name, _ProcessNames) ->
    na;
new(lamport, Name, _ProcessNames) ->
    {lamport, Name, 0}; % {type, whoseTime, localTime}
% e.g. {vector, 'a', #{'a': 1, 'b': 2, 'c': 3}}
new(vector, Name, _ProcessNames) ->
    {vector, Name, #{}}.

% Event, wrapping time, used by logger
event(SendRecv, Name, RemoteName, Timer, Msg, RealTime) ->
    {SendRecv, Name, RemoteName, Timer, Msg, RealTime}.

% send to remote
update(Timer) ->
    case Timer of
        na ->
            na;
        {lamport, Name, N} ->
            {lamport, Name, N+1};
        {vector, Name, Map} ->
            case maps:find(Name, Map) of
                error -> Map1 = Map#{Name => 0};
                _Else -> Map1 = Map
            end,
            #{Name := N} = Map1,
            {vector, Name, Map1#{Name => N+1}}
    end.

% recv from remote
merge(Timer, RemoteTimer) ->
    case Timer of
        na ->
            na;
        {lamport, Name, N} ->
            {lamport, _RemoteName, RemoteN} = RemoteTimer, % remote must be sending here to call this func
            if
                RemoteN > N ->
                    {lamport, Name, RemoteN + 1};
                true ->
                    {lamport, Name, N + 1}
            end;
        {vector, Name, Map} ->
            case maps:find(Name, Map) of
                error -> Map1 = Map#{Name => 0};
                _Else -> Map1 = Map
            end,
            {vector, RemoteName, RemoteMap} = RemoteTimer,
            #{RemoteName := RemoteN} = RemoteMap,
            case maps:find(RemoteName, Map) of
                error -> Map2 = Map1#{RemoteName => 0};
                _Else1 -> Map2 = Map1
            end,
            {vector, Name, Map2#{RemoteName => RemoteN}}
    end.    

new_record(ClockType) ->
    case ClockType of
        na ->
            na;
        % possible for lamport to realize dynamic processes number, but we just hard code processes for now
        lamport ->
            {lists:foldl(fun(Ele, Acc) ->
                Acc ++ [{Ele, 0}]
            end, [], ['1', '2', '3', '4']), []}; % {LatestTimeForEachProcess, Queue}
        vector ->
            #{}
    end.

% return {UpdatedRecords, SafeEvents}
add_event(Records, Event) ->
    % add event to record, then start to check
    {_SendRecv, Name, _RemoteName, Timer, _Msg, _RealTime} = Event, % 后续改vector可能只改这里
    case Timer of
        na ->
            {Records, [Event]}; % no need to buffer, return this event immediately
        {lamport, Name, EventTime} ->
            {TimeForEachProcess, Queue} = Records,
            Queue1 = lists:keysort(2, Queue ++ [{Name, EventTime, Event}]),
            tester ! {queue, length(Queue1)},
            TimeForEachProcess1 = lists:keyreplace(Name, 1, TimeForEachProcess, {Name, EventTime}),
            MinTime = lists:foldl(fun({_Name, Time}, Acc) ->
                min(Acc, Time)
            end, inf, TimeForEachProcess1),
            {SafeEvents, Rest} = lists:splitwith(fun({_Node, Time, _Event}) ->
                Time < MinTime
            end, Queue1),
            {{TimeForEachProcess1, Rest}, lists:map(fun(Ele) -> element(3, Ele) end, SafeEvents)};
                    
        {vector, Name, _Map} ->
            case maps:find(Name, Records) of
                error -> Records1 = Records#{Name => {#{}, []}};
                _Else -> Records1 = Records
            end,
            #{Name := {LocalSendedRecord, LocalWaitingEvents}} = Records1,
            LocalWaitingEvents1 = [Event|LocalWaitingEvents],
            Records2 = Records#{Name => {LocalSendedRecord, LocalWaitingEvents1}},
            process_vector(Records2, Name, [], []) % use lists:member for now, can be optimized to use set
    end.

% JobList -> [ProcessName]
process_vector(Records, ProcessName, SafeEvents, JobList) ->
    % io:format("now at ~p~n", [ProcessName]),
    tester ! {queue, sumRecordQueue(Records)},
    #{ProcessName := {LocalSendedRecord, LocalWaitingEvents}} = Records,
    case length(LocalWaitingEvents) of
        0 -> {Records, SafeEvents};
        _ ->
            [Event|LocalRestWaitingEvents] = LocalWaitingEvents,
            {SendRecv, Name, RemoteName, {vector, Name, LocalMap}, _Msg, _RealTime} = Event,
            % io:format("Msg ~p SendRecv ~p~n", [_Msg, SendRecv]),
            case SendRecv of
                recv ->
                    % remote maybe not existed here
                    case maps:find(RemoteName, Records) of
                        error -> RecordsTmp = Records#{RemoteName => {#{}, []}};
                        _Elsee -> RecordsTmp = Records
                    end,

                    #{RemoteName := {RemoteSendedRecord, RemoteWaiting}} = RecordsTmp,
                    #{RemoteName := RemoteSendTime} = LocalMap,
                    case maps:find(RemoteSendTime, RemoteSendedRecord) of
                        error -> % not sended yet, block here, seek next job
                            Records1 = Records,
                            SafeEvents1 = SafeEvents,
                            Block = true,
                            JobList1 = JobList;
                        {ok, _RemoteSendedEvent} -> % already logged, safe to go
                            % io:format("here~n"),
                            RemoteSendedRecord1 = maps:remove(RemoteSendTime, RemoteSendedRecord), % clear this send event
                            Records2 = Records#{RemoteName => {RemoteSendedRecord1, RemoteWaiting}},
                            SafeEvents1 = SafeEvents ++ [Event], 
                            Records1 = Records2#{ProcessName => {LocalSendedRecord, LocalRestWaitingEvents}}, % remove this record from waitlist
                            Block = false,
                            JobList1 = JobList
                    end;
                send ->
                    % does not block in any case
                    #{Name := EventTime} = LocalMap,
                    LocalSendedRecord1 = LocalSendedRecord#{EventTime => Event},
                    SafeEvents1 = SafeEvents ++ [Event],
                    Records1 = Records#{ProcessName => {LocalSendedRecord1, LocalRestWaitingEvents}},
                    Block = false,
                    case lists:member(RemoteName, JobList) of 
                        false -> JobList1 = lists:append(JobList, [RemoteName]);
                        true -> JobList1 = JobList
                    end
                    % it is possible in queue [recv, send, send ...more sends]
                    % but in this assignment, queue length in each process never exceeds 2
            end,

            % if self block or self wl empty, change joblist   
            if
                (not Block) and (length(LocalRestWaitingEvents) =/= 0) ->
                    process_vector(Records1, ProcessName, SafeEvents1, JobList1);
                true ->
                    % next job
                    case length(JobList1) of
                        0 -> {Records1, SafeEvents1};
                        _Else -> 
                            [NextProcessName|Rest] = JobList1,
                            process_vector(Records1, NextProcessName, SafeEvents1, Rest)
                    end
            end
    end.


sumRecordQueue(Records) ->
    EventLists = lists:map(fun(Ele) -> element(2, Ele) end, maps:values(Records)),
    % lists:foldl(fun(Ele, Acc) -> 
    %     if
    %         length(Ele) > 1 ->
    %             io:format("[~p]: ~p remaining~n", [Acc, length(Ele)]);
    %         true -> ok
    %     end,
    %     Acc + 1
    % end, 1, EventLists),
    lists:foldl(fun(Ele, Acc) -> Acc + length(Ele) end, 0, EventLists).
















% 每个输出的send/recv，将自身N推进1，每个其他进程的send N，将自身推进至max(self, N+1)
% recv不能确保其他进程通过N+1解锁它，那怎么解锁？只能说是等待
% safe_msgs_lamport(Records1, Name, [], []) ->

% 在这个问题中，jitter时是不会发下一个请求的，也就是简化情况，不会发生，lamport序数大的日志在lamport序数小的日志前到达的情况
% 如果不是简化情况，有办法避免吗？没有办法，lamport无法知道recv前到底有多少个send，因此无法做一个缓存，只把有序的lamport event交给time模块排序
% mark-green: 好像不对，发送方在发送时肯定是有序的，那么如果使用的是有序协议，比如说TCP，或者上层做了有序的封装，也就是说在消息中还是带上一个序号（vector其实就是带上需要），那么就可以用这个简化场景考虑 
% mark-red: 问题来了，如果 recv at 6处理完了，来了个send at 3怎么办，此时我们expect send/recv at 2，不做历史记录是没法搞清楚send2是否发生过的
% 验收的时候提一下这个问题

% 多个send，后等前
% 多个recv，无法保证
% send recv，无法保证
% recv send，可以保证

% 除了因果顺序外，我们还可以利用send前必有事件来避免一部分问题，但是这里的send是有序的（当然如果使用TCP的话在logger也会是有序收到的），recv才是并发的重点问题，维护PreviousCompleteTime没有太大意义
% 如果是  recv X  ???  recv Y 呢，如何确保中间没有事件？现实中无法保证，但这里的send在被logger收到前是无法recv的，因此也不会出现这种情况
% 可否利用local send永远是有序的这一特点？
% send日志发往日志服务由tcp保证有序，从remote接受的recv日志在进程内计算的接收时间就是正确时间，因此，local的send recv在logger永不失序，问题减小为进程间如何保证顺序
% 收到send立刻发送，记录send记录，收到recv先check

% 发送任何消息到logger后sleep能否模拟TCP排队 -> 能，因为即使你不sleep，后来先到也会在服务器端排队直到有序，这里只是把排队放到客户端了

% 存在比如说send到日志服务器的消息拖延很久，导致recv端积累了多个本端的recv、send日志这种情况，
%   send端此时在sleep，recv端阻塞在recv，解除阻塞后按同样流程输出即可（TCP使得本地消息永远有序）。即recv到了，send没到
% 存在send到了，但recv没到的情况（这个是我手动加的，不然不会出现这种情况），此时不会因为这个send的recv没到而阻塞，没有任何人被阻塞
% 可以根据事件先后推出lamport time先后，但不能反推，这也是我为啥觉得lamport time真的很垃圾，这里我们把lamport time + Name当做Msg ID来用

% 队列最大多长，应该是N-1，即来自其他N-1个进程的Recv

% 每次我们处理的第一个事件确保是第一个事件，因为tcp确保之前的事件处理完了才会处理这件事情

% 

% 哭了，下面的是vector的解决方案
% lamport每次发送N输出，说明对端N+1及以内可以直接输出
% vector自带SendRecv判断，自带对端时间戳，可以使用下方的









% 如果确定前面还有事件，那么就存下来，如果不确定，那么直接输出
% 对每个process，存waiting的，对sending来说，等价于等N-1，对recv来说，等价于等Remote的N-1
% lamport的send和recv都要记对端，这样才方便查找
% 每当来了新的事件，如果不是阻塞原因，那么按时间顺序放入队列，注意，有可能当前阻塞在recv 6，但是来了send4，那么阻塞原因需要更新为send4
% 如果是阻塞原因，那么可以安全输出，并且，
% send如果解除了当前的阻塞，记录这条sending，等待recv需要的时候能查到已经输出过这个，那么recv稍后可以解除阻塞
% recv如果是第一条，那么check sending记录，如果找到那么销毁，不阻塞，如果没找到，那么block here
% 作为头节点时，send阻塞N-1，recv查对端sending记录，没有则阻塞，
% sending的N-1阻塞何时能解除，如果来了N-1的send，那么阻塞的就会是N-2，只有当来了一个recv，才有可能由这个recv的解锁，解锁后续
% recv的对端N-1阻塞何时能解除，取决于对端哈哈哈
% 无法预测下一个的序号，因此应该记录最后解决的序号，初始为recv 0，send 1 与 recv N 都可以不依赖Local线程直接解锁；如果初始为 send 0，send 1 与 recv N 都可以不依赖Local线程直接解锁

% 以下步骤适用于初始状态，也适用于后续状态
% 1. 如果来的是 send 1，那么直接加入输出，send记录中记录已经完成此进程send 1，进程进度记录中记录此进程进度为send1，尝试继续向后处理本进程Srted中的元素，直到遇到阻塞，
%    recv的解锁不会影响其他进程，而send会，因此需要检查其他进程（从1到N，不含刚才处理过的），如果Srted第一个为recv，那么有可能已经解锁，如果解锁，继续向后尝试解锁此进程Srted，如果向后的过程解锁了任何send
%    那么在此进程处理完后，重新从1-N进程（不含自己）检查能否解锁其他recv
% 2. 如果来的是 send N，那么依赖send/recv N-1，加入进程sorted不处理，如果记录了send/recv N-1已经完成输出，那么记录此进程进度为 send N，记录send N已经完成，继续处理本进程，随后如同步骤1，处理其他进程
% 3. 如果来的是 recv N，那么查对端sending，查过往后处理，没查到阻塞

% 如果是sending，说明有前置事件（除非N=1，那么可以输出，检查timestamp是否等于N-1，是的话可以直接输出，同时查找是否有其他process的N+1 recv

% new_process_timer(na, _ProcessNames) ->
%     #{};
% new_process_timer(lamport, ProcessNames) ->
%     lists:foldl(fun(Ele, Acc) -> Acc#{Ele => #{0 => {lamport, Ele, {-}}}} end, #{}, ProcessNames).
% new_process_timer(vector, ProcessNames) ->
%     lists:foldl(fun(Ele, Acc) -> Acc#{Ele => #{0 => {vector, Ele, }}})

% Timer, string, Map{string -> Map{LocalTime -> {Timer, Msg}}}
% for vector, e.g.: Map{"process1" -> Map{1, {{1, 3, 4}, "Hello"}}}


% record(na, Msg, ProcessTimers) ->
%     % initialize if ProcessTimers not initialized
%     ProcessTimers#{na => Msg}; % for na, we just store it in a new map, later when calling safelog, we take it out
% record(Timer, Msg, ProcessTimers) ->
%     {_AnyTimerType, ProcessName, _LocalTime} = Timer,
%     #{ProcessName := ProcessTimer} = ProcessTimers,
%     ProcessTimer1 = ProcessTimer#{local_time(Timer, ProcessName) => {Timer, Msg}},
%     ProcessTimers#{ProcessName => ProcessTimer1}.


% % if map empty, put empty here, meaning waiting for send at 1 or recv at any
% first_block_point(ProcessTimers) ->
%     maps:fold(fun(K1, V1, Acc1) -> 
%         MinTime = maps:fold(fun(LocalTime, _V2, Acc2) ->
%             % find min time
%             if
%                 LocalTime < Acc2 -> LocalTime;
%                 true -> Acc2
%             end 
%         end, V1, 2147483647),
%         #{MinTime := {{_AnyTimerType, SelfName, {MinTime, TimeUpdateFrom}}, _Msg}} = V1,
%         Acc1#{K1 => {MinTime - 1, TimeUpdateFrom} % waiting for N-1 event from TimeUpdateFrom
%     end, #{}, ProcessTimers).

% safeLog(Timer, ProcessTimers) ->
%     case Timer of
%         na ->
%             #{na := Msg} = ProcessTimers,
%             Msg;
%         % 如果是发送，那么等待自身的N-1事件，如果是接收，那么等待远端的N-1事件，且必定为发送事件
%         % 无法根据当前事件推断下一事件时间，因为存在时间跳跃
%         {lamport, {LocalTime, SendRecv}} ->

% % ProcessTimers: map[ProcessName]map[LocalTime, {Timer, Msg}], see record/4 upper
% % recv min is 2, send min is 1
% % 每个事件完成输出后，check是否有其他事件显式依赖这一事件
% % 那么如何判断每个进程现在正在依赖谁呢
% safeLog(Timer, ProcessTimers, Acc) ->
%     case Timer of
%         {lamport, LocalName, {N, SendRecv}} ->
%             case SendRecv of 
%                 send -> % waiting for local event at N-1
%                     case maps:find(LocalName, ProcessTimers) of
%                         error -> % if N=1 -> output, else, waiting for N-1 event
                            


%                 recv -> % waiting for remote event at N-1

%         {vector, _Any} ->
%             notimplemented
%     end.


% local_time(Timer, ProcessName) ->
%     case Timer of 
%         na ->
%             na; % code should not be here.
%         {lamport, _Name, LocalTime} ->
%             LocalTime;
%         {vector, Vectors} ->
%             #{ProcessName := LocalVector} = Vectors,
%             #{ProcessName := LocalTime} = LocalVector,
%             LocalTime
%     end.    


    % Y combinator
    % ref1: https://stackoverflow.com/questions/1179655/erlang-how-can-i-reference-an-anonymous-function-from-within-the-body/1179904
    % ref2: https://stackoverflow.com/questions/867418/how-do-you-write-a-fun-thats-recursive-in-erlang
    % BuildList = fun (_F, 0, Lst) -> Lst;
            % (F, N, Lst) -> F(F, N-1, [0|Lst]) end,
    
    % lists:foldl(fun(Ele, Acc) ->
    %     Acc#{Ele => list_to_tuple(
    %         (fun BuildList(0, Lst) -> Lst;
    %              BuildList(N, Lst) -> BuildList(N - 1, [0|Lst])
    %         end)(length(ProcessNames), [])
    %     )}
    % end, #{}, ProcessNames).