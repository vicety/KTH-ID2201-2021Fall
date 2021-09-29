-module(log).
-compile(export_all).

start(TimerType, InitialTime) ->
    spawn_link(fun() -> init(TimerType, InitialTime) end).

stop(Logger) ->
    Logger ! stop.

init(TimerType, InitialTime) ->
    % TODO: worker和log只改一次
    Record = time:new_record(TimerType),
    loop(InitialTime, Record, 0, 0).

loop(InitialTime, Record, Accepted, Printed) ->
    receive
        {log, LogFrom, Timer, RealTime, {SendRecv, MsgFrom, MsgTo, Msg}} ->
            FormatedMsgFunc = fun() -> log(LogFrom, RealTime, SendRecv, MsgFrom, MsgTo, Timer, Msg, InitialTime, Accepted) end,
            case SendRecv of
                send ->
                    Event = time:event(SendRecv, MsgFrom, MsgTo, Timer, FormatedMsgFunc, RealTime);
                recv ->
                    Event = time:event(SendRecv, MsgTo, MsgFrom, Timer, FormatedMsgFunc, RealTime)
            end,
            {Record1, SafeEvents} = time:add_event(Record, Event),

            % io:format("saveEvents: ~p~n", [SafeEvents]),
            % io:format("record1: ~p~n", [Record1]),
            % #{'4' := {LocalSend, LocalWaitingEvents}} = Record1,
            % io:format("LocalSend: ~p~nLocalWait: ~p~n", [LocalSend, LocalWaitingEvents]),

            lists:map(fun(Event1) -> 
                {SendRecv1, Name1, RemoteName1, _Timer, MsgFunc, RealTime1} = Event1,
                {MsgID, PrintFun} = MsgFunc(),
                PrintFun(),
                case SendRecv of
                    send ->
                        tester ! {msg, MsgID, RealTime1, SendRecv1, Name1, RemoteName1};
                    recv ->
                        tester ! {msg, MsgID, RealTime1, SendRecv1, RemoteName1, Name1}
                end 
            end, SafeEvents),

            loop(InitialTime, Record1, Accepted + 1, Printed + length(SafeEvents));
        stop ->
            io:format("Logger received ~p msgs, printed ~p msgs~n", [Accepted, Printed])
    end.

log_str(LogFrom, RealTime, SendRecv, MsgFrom, MsgTo, Timer, Msg, InitialTime) ->
    list_to_atom(io_lib:format("[~p] [RealTime=~p] [~w]: ~p msg from [~p] to [~p] localSeqNum [~p]~n", [Timer, RealTime-InitialTime, LogFrom, SendRecv, MsgFrom, MsgTo, Msg])).
  
log(LogFrom, RealTime, SendRecv, MsgFrom, MsgTo, Timer, Msg, InitialTime, LoggerSeq) ->   
    {Msg, fun() -> io:format("[~p] [LoggerSeq=~p] [RealTime=~p] [~w]: ~p msg from [~p] to [~p] localSeqNum [~p]~n", [Timer, LoggerSeq, RealTime-InitialTime, LogFrom, SendRecv, MsgFrom, MsgTo, Msg]) end}.











% TODO
%  1. 进程中途加入扩展
%  2. 


% 为了模拟到log的通信，在recv发送log也增加了jitter
% 以下讨论的前提条件是使用有序的通信协议，即先发先到。如果不满足这一条件，日志输出会困难很多，这里不讨论

% lamport
% 1. 无法通过时间戳对比是否并发
% 2. 可以找到安全输出点
% 3. recv到了send未到的情况，如果这条send消息是整个系统中序号最小的，会导致整个系统无法进行日志输出
% 4. 整个系统的消息输出速度，取决于最不频繁通信的进程的通信速度，因此如果通信速度不同的话，会堆积大量消息
% 5. 支持新增进程，可以让它从安全点开始累计时钟
% 6. 无法完整输出消息

% vector
% 1. 空间占用，实际上不需要占用所有进程的大小，只需要占用有沟通的那几个就可以了
% 2. send不阻塞，recv阻塞，不可能都在recv，因此最大的消息堆积量为N-1，recv到达send一直未到达的消息只影响recv进程日志的输出
% 3. 支持新增进程
% 4. 能够完整输出消息
% 5. 不依赖进程频繁通信


% 对于啥都没有，那么啥都会乱
% 对于lamport，单进程、因果不会乱，无法控制无因果关系的顺序
% lamport, self 不用管别人，recv，需要管别人，同时自己可能期间也有输出
% 4.0节问题描述的意思是可以随意构造timer结构

% 对于lamport，发送于N事件的上一个事件一定是本地N-1时间的事件，接收于N，依赖于远端N-1时间的到达，无法判断自身N-1至上一个收到的时间段内是否有其他事件
% happen before is a partial order, the lamport clock, however, defines a one dimensional total order, which cannot equivalently express the happen before order. 
% lamport clock需要结合发送/从...接收的信息才能保证因果关系正确

% 对于vector，无论如何当本地时间为N，一定存在本地时间为N-1的事件，同时，如果为从...接收的远端时间为X的事件，那么还依赖远端时间为X事件的发生
% 相对于lamport clock，增加发送/接收这一维度的信息可以保证因果关系正确外，还可以对两个时间的事件是否并发这一问题有明确的答案，同时，由于不存在时间跳跃，单个进程内的事件一定不会乱序
