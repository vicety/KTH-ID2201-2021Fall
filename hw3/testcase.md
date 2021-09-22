1. with jitting like giving in the assignment, just set Jitter=1 will cause 100% disorder rate.

2. also jitter in receiver
| Sleep | Jitter | Disorder | Total | Rate  |
| ----- | ------ | -------- | ----- | ----- |
| 400   | 0      | 0        | 164   | 0     |
| 400   | 2      | 36       | 160   | 0.225 |
| 400   | 5      | 68       | 156   | 0.436 |
| 400   | 10     | 68       | 156   | 0.436 |
| 400   | 20     | 80       | 150   | 0.533 |
| 400   | 50     | 64       | 128   | 0.5   |

Guessing that the little advantage that the sender's log comes faster to the logging thread is obscured by the large random jittering time.