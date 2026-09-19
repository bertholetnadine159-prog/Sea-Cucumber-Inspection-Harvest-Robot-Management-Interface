# SeaUI 后端打包运行时钩子（PyInstaller runtime hook）
#
# 背景：backend/app.py 通过 `__file__` 推导 BASE_DIR/BACKEND_DIR。onefile 模式下
# `__file__` 指向临时解包目录（sys._MEIPASS）：
#   - 默认模型路径 BASE_DIR/best.onnx 会落到临时目录的上一级，取不到；
#   - 默认数据库路径 BACKEND_DIR/data/seaUI.db 在进程退出后随解包目录一并清除。
# 本钩子用环境变量 setdefault 纠偏，不改动 backend 源码（backend/** 只读）：
#   - ROV_MODEL_PATH -> 解包目录内的 best.onnx（由 spec datas 打入）；
#   - ROV_DB_PATH   -> %LOCALAPPDATA%\SeaUI\data\seaUI.db（持久化，客户数据不丢）。
# 已显式设置的环境变量优先，便于部署方覆盖。

import os
import sys

_meipass = getattr(sys, "_MEIPASS", "")

# local 模式模型路径：datas 已把 best.onnx 放在解包目录根
_model = os.path.join(_meipass, "best.onnx") if _meipass else ""
if _model and os.path.exists(_model):
    os.environ.setdefault("ROV_MODEL_PATH", _model)

# 数据库持久化目录：onefile 解包目录是临时的，必须落到用户数据目录
if not os.environ.get("ROV_DB_PATH"):
    _base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    _data_dir = os.path.join(_base, "SeaUI", "data")
    try:
        os.makedirs(_data_dir, exist_ok=True)
    except OSError:
        _data_dir = _meipass or os.getcwd()
    os.environ["ROV_DB_PATH"] = os.path.join(_data_dir, "seaUI.db")
