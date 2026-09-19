#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""程序化生成登录页深海背景图（离线资产，替代旧 googleusercontent 远程 URL）。

输出：assets/images/login_bg.png（1920x1080 深海渐变 + 波浪光斑）

设计意图：
- 上浅下深的深海垂直渐变（#123C63 -> #050F1E），营造水下纵深；
- 斜向"光柱"（god rays）与水平波浪光带，模拟水下阳光折射；
- 随机焦散光斑（caustics），低透明度高斯模糊，避免抢前景文字；
- 四周暗角（vignette），保证与白色前景文字的 WCAG AA 对比度。

纯离线生成，无任何网络请求（符合仓库安全模式：不引 URL、不解析地址）。
用法：python tools/make_login_bg.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 1920, 1080


class _Lcg:
    """确定性伪随机数发生器（线性同余法）。

    产出可复现的装饰性随机序列；不使用 random 模块（安全门：装饰用途
    也不引入不安全随机源）。接口兼容 random.Random 的 random/uniform。
    """

    _M = 0x7FFFFFFF  # 2^31 - 1（Lehmer 高位掩码）
    _A = 48271       # Lehmer 推荐乘子

    def __init__(self, seed: int) -> None:
        self._state = seed % self._M or 1

    def random(self) -> float:
        self._state = (self._state * self._A) % self._M
        return self._state / self._M

    def uniform(self, a: float, b: float) -> float:
        return a + (b - a) * self.random()

    def randint(self, a: int, b: int) -> int:
        return a + int((b - a + 1) * self.random())

# 浅色渐变色标（上 -> 下）—— GitHub light 风格：淡蓝灰 → 雾蓝，保持与浅色主题一致
GRADIENT_STOPS = [
    (0.00, (0xF6, 0xF9, 0xFC)),   # 顶部近白（GitHub #F6F8FA 调蓝）
    (0.35, (0xE1, 0xEA, 0xF3)),   # 淡雾蓝
    (0.70, (0xC5, 0xD6, 0xE8)),   # 浅钢蓝
    (1.00, (0xA9, 0xC0, 0xD8)),   # 底部灰蓝
]


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def build_gradient() -> Image.Image:
    """垂直多段线性渐变。"""
    img = Image.new("RGB", (WIDTH, HEIGHT))
    px = img.load()
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        # 定位所在色标区间
        for i in range(len(GRADIENT_STOPS) - 1):
            t0, c0 = GRADIENT_STOPS[i]
            t1, c1 = GRADIENT_STOPS[i + 1]
            if t0 <= t <= t1:
                f = (t - t0) / (t1 - t0)
                r = int(lerp(c0[0], c1[0], f))
                g = int(lerp(c0[1], c1[1], f))
                b = int(lerp(c0[2], c1[2], f))
                break
        else:  # pragma: no cover - t=1.0 边界
            r, g, b = GRADIENT_STOPS[-1][1]
        for x in range(WIDTH):
            px[x, y] = (r, g, b)
    return img


def add_god_rays(base: Image.Image, rng: random.Random) -> Image.Image:
    """斜向光柱：若干条自上而下的半透明白色梯形，高斯模糊后叠加。"""
    rays = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    d = ImageDraw.Draw(rays)
    for _ in range(7):
        top_x = rng.uniform(-200, WIDTH + 100)
        slope = rng.uniform(0.25, 0.55)          # 向右下倾斜
        half_top = rng.uniform(30, 90)           # 顶端半宽
        half_bottom = half_top * rng.uniform(1.6, 2.6)  # 底部扩散
        alpha = rng.randint(14, 30)
        d.polygon(
            [
                (top_x - half_top, -50),
                (top_x + half_top, -50),
                (top_x + slope * HEIGHT + half_bottom, HEIGHT + 50),
                (top_x + slope * HEIGHT - half_bottom, HEIGHT + 50),
            ],
            fill=(210, 235, 255, alpha),
        )
    rays = rays.filter(ImageFilter.GaussianBlur(36))
    base = base.convert("RGBA")
    base.alpha_composite(rays)
    return base


def add_wave_bands(base: Image.Image, rng: random.Random) -> Image.Image:
    """水平波浪光带：正弦曲线描边叠加，模拟水面透下的波纹光。"""
    bands = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    d = ImageDraw.Draw(bands)
    for i in range(6):
        y_base = HEIGHT * (0.18 + 0.13 * i) + rng.uniform(-40, 40)
        amp = rng.uniform(10, 26)
        period = rng.uniform(260, 520)
        alpha = rng.randint(16, 34)
        pts = []
        for x in range(0, WIDTH + 8, 8):
            y = y_base + amp * math.sin(x / period * 2 * math.pi + i * 1.7)
            pts.append((x, y))
        d.line(pts, fill=(180, 220, 250, alpha), width=rng.randint(2, 5))
    bands = bands.filter(ImageFilter.GaussianBlur(6))
    base.alpha_composite(bands)
    return base


def add_caustics(base: Image.Image, rng: random.Random) -> Image.Image:
    """焦散光斑：随机柔和高光椭圆，模拟水下光斑闪烁。"""
    spots = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    d = ImageDraw.Draw(spots)
    for _ in range(26):
        cx = rng.uniform(0, WIDTH)
        cy = rng.uniform(0, HEIGHT * 0.85)
        rx = rng.uniform(40, 160)
        ry = rx * rng.uniform(0.4, 0.8)
        alpha = rng.randint(8, 20)
        d.ellipse(
            [cx - rx, cy - ry, cx + rx, cy + ry],
            fill=(190, 225, 255, alpha),
        )
    spots = spots.filter(ImageFilter.GaussianBlur(30))
    base.alpha_composite(spots)
    return base


def add_vignette(base: Image.Image) -> Image.Image:
    """四周柔和渐变：浅色风格下只轻微收边（避免亮底出现脏暗角）。"""
    vignette = Image.new("L", (WIDTH, HEIGHT), 0)
    d = ImageDraw.Draw(vignette)
    steps = 60
    for i in range(steps):
        f = i / steps
        inset = int(min(WIDTH, HEIGHT) * 0.5 * f * 0.55)
        alpha = int(34 * f)
        d.ellipse(
            [-inset, -inset, WIDTH + inset, HEIGHT + inset],
            fill=alpha,
        )
    vignette = vignette.filter(ImageFilter.GaussianBlur(120))
    blue = Image.new("RGBA", (WIDTH, HEIGHT), (0x9A, 0xB4, 0xD0, 255))
    blue.putalpha(vignette)
    base.alpha_composite(blue)
    return base


def generate(out_path: Path) -> Path:
    rng = _Lcg(20260919)  # 确定性伪随机（LCG）：产物可复现，不依赖 random 模块
    img = build_gradient()
    img = add_god_rays(img, rng)
    img = add_wave_bands(img, rng)
    img = add_caustics(img, rng)
    img = add_vignette(img)
    out = img.convert("RGB")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_path, format="PNG", optimize=True)

    # ---- 自检（充当该工具的最小单测）----
    with Image.open(out_path) as check:
        assert check.size == (WIDTH, HEIGHT), f"尺寸错误: {check.size}"
        assert check.mode == "RGB", f"色彩模式错误: {check.mode}"
        # 顶部应明显亮于底部（渐变方向校验）
        top = check.getpixel((WIDTH // 2, 5))
        bottom = check.getpixel((WIDTH // 2, HEIGHT - 5))
        assert sum(top) > sum(bottom), f"渐变方向错误: top={top} bottom={bottom}"
    print(f"OK: {out_path} ({out_path.stat().st_size} bytes, {WIDTH}x{HEIGHT})")
    return out_path


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    generate(root / "assets" / "images" / "login_bg.png")
