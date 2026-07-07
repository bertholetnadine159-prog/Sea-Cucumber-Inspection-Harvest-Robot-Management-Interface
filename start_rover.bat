@echo off
setlocal
cd /d "%~dp0"

echo ==============================================
echo  Starting SeaUI ROV System
echo ==============================================

echo [1/2] Starting Inference Backend (port 8765)...
pushd "%~dp0backend"
start "ROV Backend" cmd /k "python app.py"
popd

timeout /t 8 /nobreak >nul

echo [2/2] Starting Flutter Desktop App...
cd /d "%~dp0rov_flutter"
flutter run -d windows

echo.
echo ==============================================
echo  Cleaning up...
echo ==============================================
taskkill /F /IM python.exe /T >nul 2>&1
echo Done. Press any key to exit.
pause >nul
