## single node add/lookup

no error, no timeout

| node | keys  | add time(ms) | lookup time(ms) |
| ---- | ----- | ------------ | --------------- |
| 1    | 50k   | 54           | 41              |
| 1    | 200k  | 261          | 197             |
| 1    | 400k  | 573          | 384             |
| 1    | 1000k | 1576         | 1045            |

## multi node add/lookup from single point

sleep 1000ms waiting all nodes to stabilize

| node | keys | add time(ms) | lookup time(ms) | add fail | lookup fail |
| ---- | ---- | ------------ | --------------- | -------- | ----------- |
| 1    | 400k | 573          | 384             |          |             |
| 2    | 400k | 596          | 441             |          |             |
| 4    | 400k | 743          | 617             |          |             |
| 8    | 400k | 1228         | 776             |          |             |
| 16   | 400k | 1957         | 1103            |          |             |
| 32   | 400k | 3204         | 1798            |          | 2831        |
| 64   | 400k | 6234         | 3403            |          | 8471        |
| 128  | 400k | 12775        | 6647            |          | 52430       |

## distributed add/lookup

| node | keys | time |
| ---- | ---- | ---- |
|      |      |      |