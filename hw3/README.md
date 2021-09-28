## milestones

1. [x] implement a erroneous logger for distributed application.
2. [x] detect disorder of logs
3. [x] implement a lamport clock to solve this issue
4. [] robustness issue. e.g. logger down, worker down.
5. [x] (optional) vector clock

## findings

同步或只有一方是异步的不会导致lamport casual乱序，send/recv都是异步地会导致
vector则完全不受影响

如果lamport要支持异步日志，那么要使得发送是FIFO的

TODO: 考虑多个进程给一个进程发送的场景，如果一个进程很不经常发送消息，lamport的算法也会失效

## presentation

1. describe solution
2. lamport issues
    0. rely on FIFO
    1. buffer size (with data)
    2. remaining log (with data)
    3. 3 send 1 recv
    4. 1 slow sender