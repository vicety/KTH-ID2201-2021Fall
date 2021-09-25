1. with jitting like giving in the assignment, just set Jitter=1 will cause 100% disorder rate.

2. also jitter in receiver
| Sleep | Jitter | Total Msgs | Revese Pair Max (First 100 Msgs) | Reverse Pair | Reverse Pair Rate | Casual Disorder | Casual Disorder Rate |
| ----- | ------ | ---------- | -------------------------------- | ------------ | ----------------- | --------------- | -------------------- |
| 300   | 0      | 0          | 4950                             | 0            | 0                 | 0               |                      |
| 295   | 5      | 196        | 4950                             | 18           | 0.003636          | 66              | 0.3367               |
| 290   | 10     | 80         | 4950                             | 93           | 0.465             | 0.4             |                      |
| 250   | 50     | 62         | 4950                             | 77           | 0.481             | 0.3875          |                      |
| 200   | 100    | 72         | 4950                             | 118          | 0.7284            | 0.4444          |                      |
| 150   | 150    | 50         | 4950                             | 129          | 0.8165            | 0.3165          |                      |
| 100   | 200    | 48         | 4950                             | 128          | 0.8591            | 0.3221          |                      |
| 50    | 250    | 28         | 4950                             | 114          | 0.8382            | 0.2059          |                      |
| 1     | 299    | 40         | 4950                             | 119          | 0.8881            | 0.2985          |                      |

猜测gitter时间越长，recv排队导致

单数因为最后没有来得及



Guessing that the little advantage that the sender's log comes faster to the logging thread is obscured by the large random jittering time.

