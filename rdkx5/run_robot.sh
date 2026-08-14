#!/usr/bin/env bash
# ============================================================================
# [RDK X5 side] 启动脚本（在 RDK X5 上执行）
# 用法：
#   chmod +x run_robot.sh
#   ./run_robot.sh                 # 实机
#   ./run_robot.sh --simulate      # 无硬件仿真
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PYTHON:-python3}"

if [ ! -d ".venv" ]; then
  echo "[RDK X5] creating virtualenv..."
  "$PYTHON" -m venv .venv
fi
source .venv/bin/activate

if ! python -c "import websockets, yaml, numpy, cv2" >/dev/null 2>&1; then
  echo "[RDK X5] installing dependencies..."
  pip install -r requirements.txt
fi

echo "[RDK X5] starting gateway (args: $*)"
exec python gateway.py --config config.yaml "$@"
