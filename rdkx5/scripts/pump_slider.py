#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""泵滑条测试台（GUI，1000-2000 拖动实时测试，含急停）。

用法（PC 上直接运行，无需装任何东西，tkinter 自带）：
    python rdkx5/scripts/pump_slider.py
    python rdkx5/scripts/pump_slider.py --channel 13 --ws ws://192.168.5.127:8080

安全设计（按 docs/PITFALLS_pixhawk_pump_debug.md 实测坑）：
    ① 滑条任意拖动/点击都会被转成平滑斜坡下发（每 30ms 一步 ≤20us）——
       驱动器只认连续爬升，阶跃会被忽略（坑 8）
    ② 急停（红色大按钮 / 空格 / ESC）：立即 950 低于量程硬停脉冲 + 1000 双保险
    ③ 关闭窗口 / 断线重连前都会先急停
    ④ ≥1600 区域滑条与数值变红提示（实测 1600 全速 2 秒发热）
"""

from __future__ import annotations

import argparse
import asyncio
import json
import threading
import time
import tkinter as tk
from tkinter import ttk

import websockets

DEFAULT_WS = "ws://192.168.5.127:8080"
DEFAULT_CHANNEL = 13  # AUX5
HARD_STOP_PWM = 950
STOP_PWM = 1000
STEP_US = 20
STEP_INTERVAL = 0.03
DANGER_PWM = 1600


class PumpWorker(threading.Thread):
    """后台线程：维护 WS 连接；把目标值以平滑斜坡下发；处理急停。"""

    def __init__(self, ws_url: str, channel: int):
        super().__init__(daemon=True)
        self.ws_url = ws_url
        self.channel = channel
        self.target = STOP_PWM
        self.sent = STOP_PWM
        self.emergency = threading.Event()
        self.lock = threading.Lock()
        self.status = "初始化..."
        self.connected = False
        self._loop = None
        self._ws = None

    def set_target(self, pwm: int) -> None:
        with self.lock:
            self.target = max(STOP_PWM, min(2000, int(pwm)))

    def trigger_emergency(self) -> None:
        self.emergency.set()

    def _send(self, pwm: int) -> None:
        if self._ws is None:
            return
        asyncio.run_coroutine_threadsafe(
            self._ws.send(json.dumps({
                "type": "command", "command": "servo",
                "params": {"channel": self.channel, "pwm": pwm},
            })),
            self._loop,
        )

    async def _run(self) -> None:
        while True:
            try:
                self.status, self.connected = f"连接 {self.ws_url} ...", False
                async with websockets.connect(self.ws_url, open_timeout=8) as ws:
                    self._ws = ws
                    await ws.recv()  # hello
                    self.status, self.connected = "已连接", True
                    while True:
                        # 急停优先：950 硬停脉冲 → 1000，斜坡状态复位
                        if self.emergency.is_set():
                            self._send(HARD_STOP_PWM)
                            await asyncio.sleep(0.4)
                            self._send(STOP_PWM)
                            with self.lock:
                                self.sent = self.target = STOP_PWM
                            self.emergency.clear()
                            continue
                        # 平滑逼近目标（每 30ms 一步 ≤20us）
                        with self.lock:
                            delta = self.target - self.sent
                        if delta:
                            step = max(-STEP_US, min(STEP_US, delta))
                            with self.lock:
                                self.sent += step
                            self._send(self.sent)
                        await asyncio.sleep(STEP_INTERVAL)
            except Exception as exc:  # noqa: BLE001
                self.status, self.connected = f"断线（{exc}），2 秒后重连...", False
                self._ws = None
                await asyncio.sleep(2)

    def run(self) -> None:
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        self._loop.run_until_complete(self._run())


class PumpSliderApp:
    def __init__(self, root: tk.Tk, worker: PumpWorker) -> None:
        self.root = root
        self.worker = worker
        self.updating = False
        root.title("泵滑条测试台（含急停）")
        root.geometry("640x420")
        root.protocol("WM_DELETE_WINDOW", self.on_close)

        title = ttk.Label(root, text="拖动滑条测试泵（1000-2000）", font=("Microsoft YaHei", 14))
        title.pack(pady=8)

        self.value_var = tk.StringVar(value=str(STOP_PWM))
        self.value_label = ttk.Label(root, textvariable=self.value_var, font=("Consolas", 28))
        self.value_label.pack()

        self.slider = tk.Scale(
            root, from_=2000, to=1000, resolution=5, orient=tk.HORIZONTAL,
            length=560, showvalue=0, command=self.on_slider,
        )
        self.slider.set(STOP_PWM)
        self.slider.pack(pady=10)

        self.zone_label = ttk.Label(
            root,
            text=f"≥{DANGER_PWM} 为危险区（实测全速 2 秒发热），滑条变红时请短时点动",
            foreground="#666",
        )
        self.zone_label.pack()

        self.stop_btn = tk.Button(
            root, text="急  停", command=self.emergency,
            bg="#d32f2f", fg="white", activebackground="#b71c1c",
            font=("Microsoft YaHei", 22, "bold"), width=14, height=2,
        )
        self.stop_btn.pack(pady=14)

        self.status_var = tk.StringVar(value="初始化...")
        ttk.Label(root, textvariable=self.status_var, foreground="#2563eb").pack()
        hint = ttk.Label(
            root,
            text="空格 / ESC = 急停 · 关窗前自动急停 · 急停后滑条自动回 1000",
            foreground="#666",
        )
        hint.pack(pady=4)

        root.bind("<space>", lambda e: self.emergency())
        root.bind("<Escape>", lambda e: self.emergency())
        self._poll_status()

    def on_slider(self, value: str) -> None:
        if self.updating:
            return
        pwm = int(float(value))
        self.worker.set_target(pwm)
        self._refresh(pwm)

    def emergency(self) -> None:
        self.worker.trigger_emergency()
        self.updating = True
        self.slider.set(STOP_PWM)
        self.updating = False
        self._refresh(STOP_PWM)

    def _refresh(self, pwm: int) -> None:
        self.value_var.set(str(pwm))
        color = "#d32f2f" if pwm >= DANGER_PWM else "#111"
        self.value_label.config(foreground=color)
        self.slider.config(fg=color if pwm >= DANGER_PWM else "#111",
                           troughcolor="#ffcdd2" if pwm >= DANGER_PWM else "#e0e0e0")

    def _poll_status(self) -> None:
        sent = self.worker.sent
        state = "已连接" if self.worker.connected else "未连接"
        self.status_var.set(f"[{state}] {self.worker.status} · 当前下发 {sent}us")
        self.root.after(300, self._poll_status)

    def on_close(self) -> None:
        self.worker.trigger_emergency()
        time.sleep(0.8)  # 给急停一点下发时间
        self.root.destroy()


def main() -> None:
    parser = argparse.ArgumentParser(description="泵滑条测试台（含急停）")
    parser.add_argument("--ws", default=DEFAULT_WS)
    parser.add_argument("--channel", type=int, default=DEFAULT_CHANNEL)
    args = parser.parse_args()

    worker = PumpWorker(args.ws, args.channel)
    worker.start()

    root = tk.Tk()
    PumpSliderApp(root, worker)
    root.mainloop()


if __name__ == "__main__":
    main()
