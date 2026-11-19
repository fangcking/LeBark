# -*- coding: utf-8 -*-
"""
生成 iOS App 图标：1024x1024 铺满画布的深蓝紫渐变底 + 金色硬币 + 白色对勾。
纯标准库实现（SDF 抗锯齿 + 手写 PNG 编码），无需 Pillow / numpy。

输出：
  LeBark/Assets.xcassets/AppIcon.appiconset/AppIcon.png   1024x1024 iOS 图标
  ios-icon-preview.png                                     512x512 预览图
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(ROOT, "LeBark", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(ICONSET, exist_ok=True)

NAVY = (23.0, 32.0, 68.0)
INDIGO = (79.0, 70.0, 229.0)
PURPLE = (124.0, 58.0, 237.0)
GOLD_TOP = (255.0, 224.0, 128.0)
GOLD_BOT = (240.0, 158.0, 24.0)
CHECK = (255.0, 255.0, 255.0)
SHADOW = (10.0, 14.0, 40.0)


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def mix(a, b, t):
    t = clamp(t)
    return (a[0] + (b[0] - a[0]) * t,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t)


def over(dst, src, alpha):
    alpha = clamp(alpha)
    return (dst[0] * (1 - alpha) + src[0] * alpha,
            dst[1] * (1 - alpha) + src[1] * alpha,
            dst[2] * (1 - alpha) + src[2] * alpha)


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_capsule(px, py, ax, ay, bx, by, r):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = clamp((pax * bax + pay * bay) / (bax * bax + bay * bay))
    return math.hypot(pax - bax * h, pay - bay * h) - r


def coverage(d, aa, inset=0.0):
    return clamp(0.5 - (d + inset) / aa)


def render(size):
    buf = bytearray(size * size * 4)
    aa = 1.35 / size

    for y in range(size):
        py = (y + 0.5) / size
        row = y * size * 4
        for x in range(size):
            px = (x + 0.5) / size

            # 深蓝紫斜向渐变（iOS 自行裁圆角）
            t = clamp((px * 0.45 + py * 0.75) - 0.05)
            col = mix(INDIGO, PURPLE, t)
            col = mix(col, NAVY, clamp((py - 0.55) * 1.1) * 0.55)
            glow = clamp(1.0 - math.hypot(px - 0.18, py - 0.10) / 0.85) * 0.20
            col = mix(col, (255, 255, 255), glow)
            vign = clamp((math.hypot(px - 0.75, py - 0.82) - 0.38) / 0.5) * 0.22
            col = mix(col, SHADOW, vign)

            # 硬币投影
            d_shadow = sd_circle(px, py, 0.5, 0.525, 0.305)
            col = over(col, SHADOW, coverage(d_shadow, aa) * 0.28)

            # 硬币主体：金色渐变圆
            d_coin = sd_circle(px, py, 0.5, 0.5, 0.30)
            a_coin = coverage(d_coin, aa)
            gold = mix(GOLD_TOP, GOLD_BOT, clamp((py - 0.24) / 0.52))
            col = over(col, gold, a_coin)

            # 硬币内圈高光环
            d_ring = abs(sd_circle(px, py, 0.5, 0.5, 0.245)) - 0.012
            col = over(col, (255, 236, 170), coverage(d_ring, aa) * 0.85)

            # 硬币上的人民币符号：一竖 + 两横（简化 ¥）
            a_yen = 0.0
            # 竖
            a_yen = max(a_yen, coverage(sd_capsule(px, py, 0.5, 0.36, 0.5, 0.63, 0.018), aa))
            # 两条斜横（V）
            a_yen = max(a_yen, coverage(sd_capsule(px, py, 0.395, 0.40, 0.5, 0.52, 0.016), aa))
            a_yen = max(a_yen, coverage(sd_capsule(px, py, 0.605, 0.40, 0.5, 0.52, 0.016), aa))
            # 下横
            a_yen = max(a_yen, coverage(sd_capsule(px, py, 0.44, 0.55, 0.56, 0.55, 0.016), aa))
            col = over(col, (150, 92, 12), a_yen * 0.85)

            # 右下角白色对勾徽标（结账完成含义）
            d_badge = sd_circle(px, py, 0.755, 0.755, 0.155)
            a_badge = coverage(d_badge, aa)
            col = over(col, SHADOW, coverage(sd_circle(px, py, 0.755, 0.768, 0.155), aa) * 0.35)
            col = over(col, (16, 185, 129), a_badge)
            a_chk = 0.0
            a_chk = max(a_chk, coverage(sd_capsule(px, py, 0.700, 0.755, 0.742, 0.798, 0.022), aa))
            a_chk = max(a_chk, coverage(sd_capsule(px, py, 0.742, 0.798, 0.818, 0.712, 0.022), aa))
            col = over(col, CHECK, a_chk)

            i = row + x * 4
            buf[i] = int(col[0] + 0.5)
            buf[i + 1] = int(col[1] + 0.5)
            buf[i + 2] = int(col[2] + 0.5)
            buf[i + 3] = 255
    return buf


def png_chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def encode_png(size, buf):
    raw = b"".join(b"\x00" + bytes(buf[y * size * 4:(y + 1) * size * 4]) for y in range(size))
    return (b"\x89PNG\r\n\x1a\n"
            + png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + png_chunk(b"IDAT", zlib.compress(raw, 9))
            + png_chunk(b"IEND", b""))


def main():
    with open(os.path.join(ICONSET, "AppIcon.png"), "wb") as f:
        f.write(encode_png(1024, render(1024)))
    with open(os.path.join(ROOT, "ios-icon-preview.png"), "wb") as f:
        f.write(encode_png(512, render(512)))
    print("Output:", os.path.join(ICONSET, "AppIcon.png"))


if __name__ == "__main__":
    main()
