import matplotlib.pyplot as plt
from matplotlib.pyplot import MultipleLocator, LogLocator
import numpy as np
import math

# global fontsize https://stackoverflow.com/questions/3899980/how-to-change-the-font-size-on-a-matplotlib-plot
plt.rcParams.update({'font.size': 8})

AXIS_FONT_SIZE=12
POINT_FONT_SIZE=8

fig, ax = plt.subplots(1, 1)
ax.grid(True)

# n thread reapeat 100 times, comment out if use 160 request data
x = [1, 40, 80, 120, 160, 240, 300, 400]
y_fixed_request_100_multi_thread_1024_queue_size = [4237, 4338, 4388, 4524, 4811, 5391, 6256, 6856]
y_fixed_request_100_theoretical = [4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000]
y_fixed_request_420_thread_pool_1024_queue_size = [4232, 4337, 4459, 4558, 4796, 5611, 6289, 6900]

ax.plot(x, y_fixed_request_100_multi_thread_1024_queue_size, label="multi thread", marker="o")
for a, b in zip(x, y_fixed_request_100_multi_thread_1024_queue_size):
    # text: https://matplotlib.org/stable/api/_as_gen/matplotlib.pyplot.text.html
    ax.text(a, b + 200, "{}".format(b), ha="center", va="bottom", fontsize=POINT_FONT_SIZE)

ax.plot(x, y_fixed_request_420_thread_pool_1024_queue_size, label="thread pool", marker="o")
for a, b in zip(x, y_fixed_request_420_thread_pool_1024_queue_size):
    ax.text(a, b - 300, "{}".format(b), ha="center", va="top", fontsize=POINT_FONT_SIZE)

ax.plot(x, y_fixed_request_100_theoretical, label="multi thread theoretical best", linestyle='--')


ax.set_xlabel("Thread Number", fontsize=AXIS_FONT_SIZE)
ax.set_ylabel("Response Time (ms)", fontsize=AXIS_FONT_SIZE)

plt.legend()
# dpi https://blog.csdn.net/weixin_34613450/article/details/80678522

# plt.figure()
plt.savefig("fixed-repeat-1024-queue-size.jpg", bbox_inches="tight", dpi=300)
