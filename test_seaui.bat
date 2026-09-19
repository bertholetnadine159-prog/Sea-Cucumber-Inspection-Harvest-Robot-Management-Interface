@echo off
rem =====================================================================
rem SeaUI 打开前自检（test_seaui.bat）—— 本文件须保存为 GBK + CRLF 编码
rem   [1] Python 环境        [2] 单元测试        [3] RDK X5 链路体检
rem   [4] 后端拉起+健康检查  [5] 启动 SeaUI 界面
rem RDK 不在线时自动降级 sim 模式（界面会显示黄色"仿真数据"角标）。
rem =====================================================================
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set EXITCODE=0

echo ============================================================
echo  SeaUI 打开前自检 %date% %time%
echo ============================================================

rem ---------- [1/5] Python ----------
echo.
echo [1/5] Python 环境 ...
python --version >nul 2>&1
if errorlevel 1 (
    echo   [FAIL] 未找到 python，请先安装 Python 3.10+ 并加入 PATH
    set EXITCODE=1
    goto :launch
)
for /f "delims=" %%v in ('python --version') do echo   [OK] %%v

rem ---------- [2/5] 单元测试 ----------
echo.
echo [2/5] 单元测试（backend + rdkx5，约 25 秒）...
pushd backend
python -m unittest discover -s tests > "%TEMP%\seaui_backend_test.log" 2>&1
if errorlevel 1 (
    echo   [FAIL] backend 测试未通过，详见 %TEMP%\seaui_backend_test.log
    set EXITCODE=1
) else (
    echo   [OK] backend 测试通过
)
popd
pushd rdkx5
python -m unittest discover -s tests > "%TEMP%\seaui_rdkx5_test.log" 2>&1
if errorlevel 1 (
    echo   [FAIL] rdkx5 测试未通过，详见 %TEMP%\seaui_rdkx5_test.log
    set EXITCODE=1
) else (
    echo   [OK] rdkx5 测试通过
)
popd

rem ---------- [3/5] RDK X5 链路体检 ----------
echo.
echo [3/5] RDK X5 链路体检 ...
set RDK_MODE=sim
set RDK_NOTE=[WARN] RDK 不可达，自动降级 sim 仿真模式
python rdkx5\scripts\check_rdk_link.py
if not errorlevel 1 (
    set RDK_MODE=rdk
    set RDK_NOTE=[OK] 网关在线，使用 rdk 真实数据模式
) else if errorlevel 3 (
    set RDK_NOTE=[WARN] 检测到代理 TUN 干扰，按 RDK 离线处理
) else if errorlevel 2 (
    set RDK_NOTE=[WARN] 板卡不可达，自动降级 sim 仿真模式
) else (
    set RDK_NOTE=[WARN] 板卡在线但网关未启动，自动降级 sim 仿真模式
)
echo   !RDK_NOTE!

rem ---------- [4/5] 后端健康检查 ----------
echo.
echo [4/5] 拉起后端（!RDK_MODE! 模式）做健康检查 ...
set ROV_BACKEND_MODE=!RDK_MODE!
set ROV_WS_PORT=18765
set ROV_API_PORT=15000
start "SeaUI-Backend-SelfTest" /min cmd /c "python backend\app.py > %TEMP%\seaui_backend.log 2>&1"

set /a TRIES=0
:wait_health
ping -n 2 127.0.0.1 >nul
set /a TRIES+=1
curl -s -o "%TEMP%\seaui_health.json" http://127.0.0.1:15000/api/health 2>nul
if not exist "%TEMP%\seaui_health.json" (
    if !TRIES! lss 10 goto :wait_health
    echo   [FAIL] 后端健康检查超时，详见 %TEMP%\seaui_backend.log
    set EXITCODE=1
    goto :kill_backend
)
findstr /c:"\"ok\": true" "%TEMP%\seaui_health.json" >nul
if errorlevel 1 (
    if !TRIES! lss 10 goto :wait_health
    echo   [FAIL] 后端未返回 ok，详见 %TEMP%\seaui_health.json
    set EXITCODE=1
    goto :kill_backend
)
echo   [OK] 后端健康（!RDK_MODE! 模式）：
python -c "import json;d=json.load(open(r'%TEMP%\seaui_health.json',encoding='utf-8'));print('   backend_mode =',d.get('backend_mode'));r=d.get('rdk') or {};print('   rdk.connected =',r.get('connected'));p=d.get('pixhawk') or {};print('   pixhawk.connected =',p.get('connected'))" 2>nul

:kill_backend
rem 自检用的后端进程先关掉（正式界面会自己拉起后端）
rem 直接按"监听 15000 端口的 PID"清理，netstat 第 5 列即 PID
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /c:":15000 " ^| findstr LISTENING') do (
    taskkill /pid %%p /f >nul 2>&1
)
ping -n 2 127.0.0.1 >nul

rem ---------- [5/5] 启动界面 ----------
:launch
echo.
echo [5/5] 启动 SeaUI 界面 ...
if exist "rov_flutter\build\windows\x64\runner\Release\rov_flutter.exe" (
    echo   [OK] 使用 Release 版
    start "" "rov_flutter\build\windows\x64\runner\Release\rov_flutter.exe"
) else if exist "rov_flutter\build\windows\x64\runner\Debug\rov_flutter.exe" (
    echo   [WARN] 无 Release 版，使用 Debug 版
    start "" "rov_flutter\build\windows\x64\runner\Debug\rov_flutter.exe"
) else (
    echo   [FAIL] 未找到界面程序，请先运行 open_seaUI.bat /rebuild
    set EXITCODE=1
    goto :done
)
echo.
echo ============================================================
echo  自检完成（!RDK_NOTE!）
if "!RDK_MODE!"=="sim" (
    echo  界面顶部会出现黄色"仿真数据"角标 —— 属预期，非真实回传。
    echo  要接真实数据：插好网线并给板卡上电，PC 网卡配 192.168.127.x，
    echo  板卡上执行 cd ~/seaUI_rdk ^&^& ./run_robot.sh，然后重开本程序。
)
echo ============================================================

:done
pause
exit /b %EXITCODE%
