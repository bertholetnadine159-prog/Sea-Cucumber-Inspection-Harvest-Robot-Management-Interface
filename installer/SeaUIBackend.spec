# -*- mode: python ; coding: utf-8 -*-
# SeaUI 后端 onefile 打包配置（F 打包智能体所有）
#
# 用法（必须在仓库根执行，spec 内用 SPECPATH 自定位路径）：
#   pyinstaller --noconfirm --clean installer/SeaUIBackend.spec
# 产物：
#   dist/SeaUIBackend.exe
#
# 说明：
#   - app.py 的 ultralytics 是懒加载（local 模式才 import），但其依赖 torch；
#     开发机装的是 CUDA 版 torch（>4GB），onefile 绝不能整包带入。
#     下面在 Analysis 后过滤掉全部 CUDA 运行库，仅保留 torch_cpu 等 CPU 部件，
#     推理实际走 onnxruntime（best.onnx），torch 仅承担 ultralytics 的 CPU 后处理。
#   - best.onnx 由 datas 放到解包目录根，配合运行时钩子 pyi_rth_seaui_paths.py
#     修正 ROV_MODEL_PATH / ROV_DB_PATH（app.py 的 __file__ 在 onefile 下指向临时目录）。

import os
import re

from PyInstaller.utils.hooks import collect_all

ROOT = os.path.abspath(os.path.join(SPECPATH, ".."))
BACKEND_DIR = os.path.join(ROOT, "backend")
MODEL_FILE = os.path.join(ROOT, "best.onnx")

datas = [(MODEL_FILE, ".")]
binaries = []
hiddenimports = ["websockets"]

# ultralytics 自带配置（cfg/*.yaml）与字体等数据文件必须整体收集，否则 YOLO 类初始化失败
for _pkg in ("ultralytics", "onnxruntime"):
    _d, _b, _h = collect_all(_pkg)
    datas += _d
    binaries += _b
    hiddenimports += _h

a = Analysis(
    [os.path.join(BACKEND_DIR, "app.py")],
    pathex=[BACKEND_DIR],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[os.path.join(SPECPATH, "pyi_rth_seaui_paths.py")],
    excludes=["tkinter"],
    noarchive=False,
    optimize=1,
)

# 过滤 CUDA 运行库：保留 CPU 推理所需部件，剔除 4GB+ 的 CUDA DLL
_CUDA_DLL = re.compile(
    r"(torch_cuda|c10_cuda|caffe2_nvrtc|cublas|cudnn|cusparse|cufft|cusolver"
    r"|curand|cudart|nvrtc|nvJitLink|nvfuser|nvinfer|cufile|nvtx|nvml)",
    re.IGNORECASE,
)
_before = len(a.binaries)
a.binaries = [x for x in a.binaries if not _CUDA_DLL.search(os.path.basename(x[0]) or x[0])]
print("[SeaUIBackend.spec] CUDA DLL 过滤：%d -> %d" % (_before, len(a.binaries)))

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="SeaUIBackend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    version=os.path.join(SPECPATH, "backend_version_info.txt"),
)
