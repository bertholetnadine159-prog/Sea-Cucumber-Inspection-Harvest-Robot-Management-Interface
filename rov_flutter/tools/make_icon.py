#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 SeaUI 应用图标（深海蓝底 + 白色波浪 + S 字标）。

产出：
- assets/images/app_icon_1024.png      （1024x1024 母版，便于后续复用）
- windows/runner/resources/app_icon.ico（多尺寸 ICO：16~256）
- android/app/src/main/res/mipmap-*/ic_launcher.png（mdpi~xxxhdpi）

设计意图：
- 深海蓝垂直渐变圆角方块，白色双波浪居中，上方简洁 "S" 字标；
- 波浪用正弦曲线绘制并轻微模糊，柔和不抢眼；
- S 字标使用项目已本地化的 Inter-Bold（assets/fonts），无外部字体依赖。

纯离线生成，无任何网络请求。用法：python tools/make_icon.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
CORNER = 200          # 圆角半径（约 20%，接近主流桌面图标观感）
GRAD_TOP = (0x17, 0x4E, 0x7A)     # 顶部海水蓝
GRAD_BOTTOM = (0x08, 0x1B, 0x33)  # 底部深海蓝
ACCENT = (0x5B, 0xB5, 0xE8)       # 波浪浅蓝高光


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )
    return mask


def build_background() -> Image.Image:
    """圆角方块 + 垂直渐变。"""
    bg = Image.new("RGB", (SIZE, SIZE))
    px = bg.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        r = int(lerp(GRAD_TOP[0], GRAD_BOTTOM[0], t))
        g = int(lerp(GRAD_TOP[1], GRAD_BOTTOM[1], t))
        b = int(lerp(GRAD_TOP[2], GRAD_BOTTOM[2], t))
        for x in range(SIZE):
            px[x, y] = (r, g, b)
    img = bg.convert("RGBA")
    # 顶部柔光：左上角轻微提亮，增加立体感
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [-SIZE * 0.35, -SIZE * 0.4, SIZE * 0.75, SIZE * 0.35],
        fill=(255, 255, 255, 26),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img.alpha_composite(glow)
    return img


def draw_waves(img: Image.Image) -> None:
    """中下部两道白色波浪（正弦曲线，粗细渐变观感）。"""
    waves = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(waves)
    for i, (y_base, width, alpha, color) in enumerate([
        (SIZE * 0.66, 26, 235, (255, 255, 255, 235)),
        (SIZE * 0.78, 20, 160, (*ACCENT, 160)),
    ]):
        amp = SIZE * 0.035
        period = SIZE * (0.52 - 0.06 * i)
        pts = []
        for x in range(-20, SIZE + 21, 6):
            y = y_base + amp * math.sin(x / period * 2 * math.pi + i * 2.2)
            pts.append((x, y))
        d.line(pts, fill=color, width=width, joint="curve")
    waves = waves.filter(ImageFilter.GaussianBlur(2))
    img.alpha_composite(waves)


def draw_letter(img: Image.Image) -> None:
    """白色 S 字标（使用项目本地 Inter-Bold 字体）。"""
    font_path = Path(__file__).resolve().parent.parent / "assets" / "fonts" / "Inter-Bold.ttf"
    if font_path.exists():
        font = ImageFont.truetype(str(font_path), int(SIZE * 0.42))
    else:  # pragma: no cover - 字体缺失时的降级（正常流程不会走到）
        font = ImageFont.load_default()
    text = "S"
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (SIZE - tw) / 2 - bbox[0]
    ty = SIZE * 0.30 - th / 2 - bbox[1]
    # 底部淡影
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((tx + 6, ty + 10), text, font=font, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(shadow)
    d.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))
    img.alpha_composite(layer)


def build_master() -> Image.Image:
    img = build_background()
    draw_waves(img)
    draw_letter(img)
    mask = rounded_mask(SIZE, CORNER)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def write_icon(master: Image.Image, out_path: Path) -> None:
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    master.resize((256, 256), Image.LANCZOS).save(
        out_path, format="ICO", sizes=sizes
    )


def write_android(master: Image.Image, res_dir: Path) -> None:
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, side in densities.items():
        target = res_dir / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        master.resize((side, side), Image.LANCZOS).save(target, format="PNG")


def generate() -> None:
    root = Path(__file__).resolve().parent.parent
    master = build_master()

    master_png = root / "assets" / "images" / "app_icon_1024.png"
    master_png.parent.mkdir(parents=True, exist_ok=True)
    master.save(master_png, format="PNG", optimize=True)

    ico_path = root / "windows" / "runner" / "resources" / "app_icon.ico"
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    write_icon(master, ico_path)

    res_dir = root / "android" / "app" / "src" / "main" / "res"
    write_android(master, res_dir)

    # ---- 自检（充当该工具的最小单测）----
    with Image.open(master_png) as m:
        assert m.size == (SIZE, SIZE), f"母版尺寸错误: {m.size}"
        assert m.mode == "RGBA", f"母版模式错误: {m.mode}"
        assert m.getpixel((5, 5))[3] == 0, "圆角外应为透明"
        center = m.getpixel((SIZE // 2, SIZE // 2))
        assert center[3] == 255, "中心应不透明"
    assert ico_path.exists() and ico_path.stat().st_size > 10_000, "ICO 过小"
    for side in (48, 72, 96, 144, 192):
        folder = {48: "mdpi", 72: "hdpi", 96: "xhdpi", 144: "xxhdpi", 192: "xxxhdpi"}[side]
        p = res_dir / f"mipmap-{folder}" / "ic_launcher.png"
        with Image.open(p) as im:
            assert im.size == (side, side), f"{p} 尺寸错误: {im.size}"
    print(f"OK: {master_png}, {ico_path}, mipmap-* ic_launcher.png")


if __name__ == "__main__":
    generate()
