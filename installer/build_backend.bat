@echo off
rem ============================================================
rem SeaUI 后端打包脚本（PyInstaller onefile）
rem 用法：双击或在任意目录执行 installer\build_backend.bat
rem 前置：Python 3.10+，且已安装 backend/requirements.txt 依赖；
rem       仓库根目录存在 best.onnx（local 模式推理权重）。
rem 产物：dist\SeaUIBackend.exe（仓库根下，git 未忽略，勿提交）
rem ============================================================
setlocal
cd /d "%~dp0.."

echo [1/3] 检查 pyinstaller ...
python -c "import PyInstaller" >nul 2>&1
if errorlevel 1 (
    echo 未检测到 pyinstaller，尝试安装 ...
    python -m pip install pyinstaller
    if errorlevel 1 (
        echo 官方源安装失败，改用清华镜像重试 ...
        python -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple pyinstaller
        if errorlevel 1 goto :fail
    )
)

echo [2/3] 开始打包（onefile，首次约需数分钟）...
python -m PyInstaller --noconfirm --clean installer\SeaUIBackend.spec || goto :fail

echo [3/3] 完成。产物：dist\SeaUIBackend.exe
echo.
echo 冒烟验证（手动执行）：
echo   set ROV_BACKEND_MODE=sim&& set ROV_WS_PORT=18799&& set ROV_API_PORT=15099&& dist\SeaUIBackend.exe
echo   curl http://127.0.0.1:15099/api/health   （应返回 ok）
exit /b 0

:fail
echo 构建失败，请检查上方日志。
exit /b 1
