import matplotlib.pyplot as plt
from matplotlib.pyplot import MultipleLocator, LogLocator
import numpy as np
import math

# global fontsize https://stackoverflow.com/questions/3899980/how-to-change-the-font-size-on-a-matplotlib-plot
plt.rcParams.update({'font.size': 8})

AXIS_FONT_SIZE=12
POINT_FONT_SIZE=8

# ax = plt.subplots(1, 1)

# np.seterr(divide='ignore')


def forwardX(x): return np.log2(x + 0.00001)
def backwardX(x): return 2**(x) - 0.00001


def forwardY(x): return (np.log(x + 1) / np.log(5000))
def backwardY(x): return 5000**(x) - 1


fig, ax = plt.subplots(1, 1)

ax.set_xscale('function', functions=(forwardX, backwardX))
ax.set_yscale('function', functions=(forwardY, backwardY))
ax.grid(True)

x = [1, 2, 4, 8, 16, 32, 80, 160]
y_single_thread_5_queue_size = [6562, 6563,
                                6563, 7907, 7248, 10299, 113951, 107960]
y_single_thread_512_queue_size = [6745, 6573,
                                6572, 6573, 6574, 6575, 6574, 6576]                             
y_multi_thread_5_queue_size = [6735, 3374, 1697, 861, 1492, 1295, 3192, 4441]
y_multi_thread_512_queue_size = [6742, 3372, 1697, 869, 445, 234, 111, 77]
single_thread_theoretical = [6400, 6400, 6400, 6400, 6400, 6400, 6400, 6400]
seq = np.logspace(0, math.log2(165), num=50, base=2.0) # https://numpy.org/doc/stable/reference/generated/numpy.logspace.html
multi_thread_theoretical = 6400 / seq

ax.yaxis.set_major_locator(LogLocator(2))
ax.xaxis.set_major_locator(LogLocator(2))


ax.plot(x[:7], y_single_thread_512_queue_size[:7], label="single thread", marker="o")
for a, b in zip(x[:7], y_single_thread_512_queue_size[:7]):
    # text: https://matplotlib.org/stable/api/_as_gen/matplotlib.pyplot.text.html
    ax.text(a, 1.06 * b, "{}".format(b), ha="center", va="bottom", fontsize=POINT_FONT_SIZE)

ax.plot(x, y_multi_thread_512_queue_size, label="multithread", marker="o")
for a, b in zip(x, y_multi_thread_512_queue_size):
    ax.text(a, b / 1.16, "{}".format(b), ha="center", va="top", fontsize=POINT_FONT_SIZE)

ax.plot(x, single_thread_theoretical, label="single thread theoretical best", linestyle='--')
ax.plot(seq, multi_thread_theoretical, label="multithread theoretical best", linestyle='--')

ax.set_xlabel("Thread Number", fontsize=AXIS_FONT_SIZE)
ax.set_ylabel("Response Time (ms)", fontsize=AXIS_FONT_SIZE)

plt.legend()
# dpi https://blog.csdn.net/weixin_34613450/article/details/80678522

# plt.figure()
plt.savefig("result-512-queue-size.jpg", bbox_inches="tight", dpi=300)

# plt.show()
