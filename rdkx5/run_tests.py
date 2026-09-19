#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[RDK X5 side] unittest 门禁入口。

供工作流门禁从工作区根目录调用：python rdkx5/run_tests.py
（不要求 CWD 在 rdkx5 下）。发现并运行 tests/ 下全部 test_*.py；
任一测试失败、出错或 discover 抛错时以非 0 退出码结束。
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

# 把 rdkx5 目录插入 sys.path，保证任意 CWD 下 `from pixhawk_link import ...` 可用
sys.path.insert(0, str(HERE))


def main() -> int:
    try:
        suite = unittest.defaultTestLoader.discover(str(HERE / "tests"), pattern="test_*.py")
    except Exception as exc:  # noqa: BLE001
        print(f"test discovery failed: {exc}", file=sys.stderr)
        return 2
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
