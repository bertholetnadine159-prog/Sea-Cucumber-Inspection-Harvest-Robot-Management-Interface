@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%CD%"
set "APP_EXE=%ROOT%\rov_flutter\build\windows\x64\runner\Release\rov_flutter.exe"

if /i "%~1"=="/rebuild" (
  echo [1/2] Rebuilding Windows desktop app...
  pushd "%ROOT%\rov_flutter"
  call flutter build windows --release
  if errorlevel 1 (
    popd
    echo.
    echo [ERROR] Build failed. Check Flutter and Visual Studio setup.
    pause
    exit /b 1
  )
  popd
)

if not exist "%APP_EXE%" (
  set "APP_EXE=%ROOT%\rov_flutter\build\windows\x64\runner\Debug\rov_flutter.exe"
)

if not exist "%APP_EXE%" (
  echo [ERROR] Built app not found:
  echo   %APP_EXE%
  echo Run open_seaUI.bat /rebuild to build it first.
  pause
  exit /b 1
)

set "PY_BIN=python"
if exist "%ROOT%\backend\.venv\Scripts\python.exe" (
  set "PY_BIN=%ROOT%\backend\.venv\Scripts\python.exe"
  set "PATH=%ROOT%\backend\.venv\Scripts;%PATH%"
)

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python not found. Install Python 3.10+ then run:
  echo   pip install -r "%ROOT%\backend\requirements.txt"
  pause
  exit /b 1
)

"%PY_BIN%" -c "import cv2, onnxruntime, numpy, ultralytics, websockets" >nul 2>nul
if errorlevel 1 (
  echo [WARN] Python dependencies are incomplete. The AI backend may fail to start.
  echo        Run: pip install -r "%ROOT%\backend\requirements.txt"
  echo.
)

if not exist "%ROOT%\best.onnx" (
  echo [WARN] Model file not found: %ROOT%\best.onnx
)

echo [2/2] Opening SeaUI. Backend ws://localhost:8765 starts automatically...
start "" "%APP_EXE%"
exit /b 0
