#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CWD 兼容垫片（shim）。

门禁以 CWD=rdkx5/ 执行 `python rdkx5/run_tests.py` 时，相对入口被解析为
本嵌套路径（rdkx5/rdkx5/run_tests.py），解释器在打开文件阶段即报
[Errno 2] 退出码 2。本垫片只做一件事：转发到真正的门禁入口
rdkx5/run_tests.py（唯一实现，其内部用 __file__ 定位，与 CWD 无关），
保证从工作区根目录或 rdkx5/ 目录调用均可通过。
"""

import runpy
import sys
from pathlib import Path

_REAL = Path(__file__).resolve().parent.parent / "run_tests.py"

if __name__ == "__main__":
    # runpy 以 __main__ 语义执行真实入口，其 raise SystemExit(main()) 原样
    # 向上传播，退出码（0=全绿 / 1=测试失败 / 2=discover 失败）不受影响。
    sys.argv[0] = str(_REAL)
    runpy.run_path(str(_REAL), run_name="__main__")
