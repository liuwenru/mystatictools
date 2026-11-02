#!/usr/bin/env python3
"""运行 Ubuntu unzip autopkgtest，排除与运行包无关的用例。

ManPage：依赖 man-db 的 man -P cat，构建容器中不可用；手册页由 smoke-test.py 检查。
ZipGrep：zipgrep 是依赖系统 egrep/sed 的 shell 脚本，不进运行包。
"""
import importlib.util
import sys
import unittest

spec = importlib.util.spec_from_file_location("SmokeTests", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

suite, excluded = unittest.TestSuite(), []


def collect(tests):
    for test in tests:
        if isinstance(test, unittest.TestSuite):
            collect(test)
        elif "ManPage" in test.id() or "ZipGrep" in test.id():
            excluded.append(test.id())
        else:
            suite.addTest(test)


collect(unittest.defaultTestLoader.loadTestsFromModule(module))
print(f"excluded {len(excluded)}:", *excluded, sep="\n  ", flush=True)
result = unittest.TextTestRunner(verbosity=2).run(suite)
print(f"ran {result.testsRun}, failures {len(result.failures)}, errors {len(result.errors)}, "
      f"skipped {len(result.skipped)}, excluded {len(excluded)}", flush=True)
sys.exit(0 if result.wasSuccessful() and result.testsRun > 0 else 1)
