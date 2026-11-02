import threading
import time
import zlib


def python_busy_loop():
    total = 0
    while True:
        for i in range(100000):
            total += i * i


def native_compress_loop():
    # zlib.compress spends its time in C (libz), used to check --native frames.
    data = bytes(range(256)) * 4096
    while True:
        zlib.compress(data, 9)


threading.Thread(target=native_compress_loop, name="native", daemon=True).start()
threading.Thread(target=python_busy_loop, name="python", daemon=True).start()
time.sleep(float(__import__("sys").argv[1]) if len(__import__("sys").argv) > 1 else 3600)
