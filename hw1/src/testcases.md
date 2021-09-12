server handle time 40ms

on windows

| Case | Process | Repeat | Time Used(ms) | Setting                    | Theoretical minimum | Delay Amplification |
| ---- | ------- | ------ | ------------- | -------------------------- | ------------------- | ------------------- |
| 1    | 1       | 160    | 7502          | Single Process(Same below) | 6400                |                     |
| 2    | 2       | 80     | 7504          |                            |                     |                     |
| 3    | 4       | 40     | 7498          |                            |                     |                     |
| 4*   | 8       | 20     | 7326          |                            |                     |                     |
| 5    | 16      | 10     | 6787          |                            |                     |                     |
| 6    | 32      | 5      | 6680          |                            |                     |                     |

4 rej 4 error: econnrefused
5 15
6 20

man listen
> The backlog parameter defines the maximum length for the queue of pending connections. If a connection request arrives with the queue full, the client may receive an error with an indication of ECONNREFUSED. Alternatively, if the underlying protocol supports retransmission, the request may be ignored so that retries may succeed.

stop testing

on linux

| Case | Process | Repeat | Time Used(ms)   | Setting                    | Theoretical minimum | Delay Amplification |
| ---- | ------- | ------ | --------------- | -------------------------- | ------------------- | ------------------- |
| 1    | 1       | 160    | 6562            | Single Process(Same below) | 6400                |                     |
| 2    | 2       | 80     | 6563            |                            |                     |                     |
| 3    | 4       | 40     | 6563            |                            |                     |                     |
| 4    | 8       | 20     | 7907            |                            |                     |                     |
| 5    | 16      | 10     | 7248            |                            |                     |                     |
| 6    | 32      | 5      | 10299           |                            |                     |                     |
| 7    | 80      | 2      | 113951 8 close  |                            |                     |                     |
|      | 1       | 160    | 107960 71 close |                            |                     |                     |

736 742 738 914 306s 310s 314s 302s

每次处理完了只能等下一波syn重试到来，因为之前的都被丢弃了

本质是内核写全连接队列与用户消费全连接队列的竞争

理论上每波处理6个，共8次机会，48个，余32个

10 error closed, 最后几个连接结束慢

受制于逻辑核心数，建立连接+send完这16个，才会send下16个

猜测是syn队列满导致resend，握手时间增加

future work
读取不满

on linux backlog=256, Single Process
start 973 dropped

| Case | Process | Repeat | Time Used(ms) | Setting | Theoretical minimum | Delay Amplification |
| ---- | ------- | ------ | ------------- | ------- | ------------------- | ------------------- |
| 1    | 1       | 160    | 6745          |         |                     |                     |
|      | 2       | 80     | 6573          |         |                     |                     |
|      | 4       | 40     | 6572          |         |                     |                     |
|      | 8       | 20     | 6573          |         |                     |                     |
|      | 16      | 10     | 6574          |         |                     |                     |
|      | 32      | 5      | 6575          |         |                     |                     |
|      | 80      | 2      | 6574          |         |                     |                     |

发现Recv-Q在80的时候也能达到79，说明线程切换还是比这40ms要快

on linux backlog=256, multi-process

| Case | Process | Repeat | Time Used(ms) | Setting | Theoretical minimum | Delay Amplification |
| ---- | ------- | ------ | ------------- | ------- | ------------------- | ------------------- |
| 1    | 1       | 160    | 6742          |         | 6400                | 1.053x              |
|      | 2       | 80     | 3372          |         | 3200                | 1.054x              |
|      | 4       | 40     | 1697          |         | 1600                | 1.061x              |
|      | 8       | 20     | 869           |         | 800                 | 1.120x              |
|      | 16      | 10     | 445           |         | 400                 | 1.113x              |
|      | 32      | 5      | 234           |         | 200                 | 1.170x              |
|      | 80      | 2      | 111           |         | 100                 | 1.110x              |
|      | 160     | 1      | 77            |         | 50                  | 1.540x              |

backlog=5 multi-process

| Case | Process | Repeat | Time Used(ms)                | Setting | Theoretical minimum | Delay Amplification |
| ---- | ------- | ------ | ---------------------------- | ------- | ------------------- | ------------------- |
| 1    | 1       | 160    | 6735                         |         | 6400                |                     |
|      | 2       | 80     | 3374                         |         |                     |                     |
|      | 4       | 40     | 1697                         |         |                     |                     |
|      | 8       | 20     | 861                          |         |                     |                     |
| 5    | 16      | 10     | 450/1492 （如果发生syn重传） |         |                     |                     |
| 6    | 32      | 5      | 1295 （一定重传）            |         |                     |                     |
| 7    | 80      | 2      | 波动 1285-3192               |         |                     |                     |
| 8    | 160     | 1      | 27481-4441                   |         |                     |                     |

5 * 1 overflow
6 * 10 overflow
141 * overflow -> 155
325 * overflow

backlog=5 4 accept thread

| Case | Process | Repeat | Time Used(ms)            | Setting | Theoretical minimum | Delay Amplification |
| ---- | ------- | ------ | ------------------------ | ------- | ------------------- | ------------------- |
| 1    | 1       | 160    | 6732                     |         | 6400                |                     |
|      | 2       | 80     | 3373                     |         |                     |                     |
|      | 4       | 40     | 1714                     |         |                     |                     |
|      | 8       | 20     | 862                      |         |                     |                     |
| 5    | 16      | 10     | 438                      |         |                     |                     |
| 6    | 32      | 5      | 1286                     |         |                     |                     |
| 7    | 80      | 2      | 波动 1373-3422           |         |                     |                     |
| 8    | 160     | 1      | 2783/3547/1530/2788/7698 |         |                     |                     |

6 * 9 overflow
7 * 33
8 * 191 overflow

但是基本看不到

backlog对高并发的影响

现在看到好像不是syn的锅啊

成功观察到了syn重传
```sh
00:23:42.856662 IP gateway.62334 > 94691c3630a7.50001: Flags [S], seq 2452097982, win 64240, options [mss 1460,sackOK,TS val 821792061 ecr 0,nop,wscale 7], length 0
...
00:23:43.887737 IP gateway.62334 > 94691c3630a7.50001: Flags [S], seq 2452097982, win 64240, options [mss 1460,sackOK,TS val 821793092 ecr 0,nop,wscale 7], length 0
...
00:23:43.887759 IP 94691c3630a7.50001 > gateway.62334: Flags [S.], seq 1267588439, ack 2452097983, win 65160, options [mss 1460,sackOK,TS val 3218736846 ecr 821793092,nop,wscale 7], length 0
...
00:23:43.887948 IP gateway.62334 > 94691c3630a7.50001: Flags [P.], seq 1:15, ack 1, win 502, options [nop,nop,TS val 821793093 ecr 3218736846], length 14 # GET / HTTP/1.1 # third handshake combined with msg
...
00:23:43.928618 IP 94691c3630a7.50001 > gateway.62334: Flags [P.], seq 1:24, ack 15, win 509, options [nop,nop,TS val 3218736886 ecr 821793093], length 23 # HTTP/1.1 200 OK\r\n\r\nok\r\n # ack and msg combined
...
00:23:43.928671 IP gateway.62334 > 94691c3630a7.50001: Flags [.], ack 24, win 502, options [nop,nop,TS val 821793133 ecr 3218736886], length 0
...
00:23:43.928694 IP 94691c3630a7.50001 > gateway.62334: Flags [F.], seq 24, ack 15, win 509, options [nop,nop,TS val 3218736886 ecr 821793133], length 0 # why ack here? 当然加一个ACK也不会造成什么问题
...
00:23:43.929822 IP gateway.62334 > 94691c3630a7.50001: Flags [F.], seq 15, ack 25, win 502, options [nop,nop,TS val 821793135 ecr 3218736886], length 0
00:23:43.929828 IP 94691c3630a7.50001 > gateway.62334: Flags [.], ack 16, win 509, options [nop,nop,TS val 3218736888 ecr 821793135], length 0

```

PSH=1 立即发送而不做缓冲（等到最大分段大小）

32thread 1repeat，时延40000，backlog=5，单线程处理，运行时Recv-Q=6，临时变量一个，25个exponential backoff，最终返回closed错误

经验证，队列满了是直接放弃客户端发来的SYN，而不是回复SYN+ACK后放弃来自客户端的ACK
见16年linux内核的这个提交 https://github.com/torvalds/linux/commit/5ea8ea2cb7f1d0db15762c9b0bb9e7330425a071

TODO 写报告

现在单个请求单开线程是没问题的，因为是IO密集型，如果是计算密集型，线程数没必要那么多，线程切换成本，ThreadPool实现用户级线程即可
