#!/usr/bin/env python3
"""Generates the original addon icon without overwriting the supplied cover.

Outputs (relative to the repo root):
  ArachnaphobiaShield/icon.tga   32x32 24-bit TGA - "no spider" addon icon
  docs/art/icon_preview.png    scaled preview of the icon

The fox cover is converted separately by tools/import_cover.py.
Pure standard library; no external image dependencies. Re-run any time:
  python3 tools/make_art.py
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------- geometry

def in_rounded_rect(x, y, x0, y0, x1, y1, r):
    """Point inside a rounded rectangle (y down, coordinates may be float)."""
    if not (x0 <= x <= x1 and y0 <= y <= y1):
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    # in the corner zones, distance to the corner arc center must be <= r
    dx, dy = x - cx, y - cy
    if (x < x0 + r or x > x1 - r) and (y < y0 + r or y > y1 - r):
        return dx * dx + dy * dy <= r * r
    return True


def dist_to_segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = (wx * vx + wy * vy) / (vx * vx + vy * vy)
    t = max(0.0, min(1.0, t))
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.sqrt(dx * dx + dy * dy)


# ---------------------------------------------------------------- icon 32x32

BG = (34, 31, 38)        # dark plum charcoal
BG_CORNER = (10, 10, 12)
SPIDER = (238, 234, 228)
RED = (208, 52, 48)
EYE = (34, 31, 38)

# leg segments: (start, end), thickness 1.1
_ICON_LEGS = [
    ((13.2, 11.8), (7.5, 6.0)),
    ((13.2, 13.8), (5.5, 11.5)),
    ((13.2, 15.8), (5.5, 20.5)),
    ((13.6, 17.6), (8.0, 27.5)),
    ((17.8, 11.8), (23.5, 6.0)),
    ((17.8, 13.8), (25.5, 11.5)),
    ((17.8, 15.8), (25.5, 20.5)),
    ((17.4, 17.6), (23.0, 27.5)),
]


def icon_pixel(i, j):
    """Pixel (i, j) of the 32x32 icon, y down."""
    x, y = i + 0.5, j + 0.5
    if not in_rounded_rect(x, y, 0.5, 0.5, 31.5, 31.5, 6.0):
        return BG_CORNER
    col = BG

    # spider silhouette: abdomen + cephalothorax + legs
    def spider(x, y):
        if ((x - 15.5) / 4.0) ** 2 + ((y - 20.5) / 5.0) ** 2 <= 1.0:
            return True
        if (x - 15.5) ** 2 + (y - 13.0) ** 2 <= 2.9 ** 2:
            return True
        for (ax, ay), (bx, by) in _ICON_LEGS:
            if dist_to_segment(x, y, ax, ay, bx, by) <= 1.1:
                return True
        return False

    if spider(x, y):
        col = SPIDER
    # eyes
    for ex in (14.5, 16.5):
        if (x - ex) ** 2 + (y - 12.3) ** 2 <= 0.45 ** 2:
            col = EYE

    # prohibition ring
    d = math.sqrt((x - 15.5) ** 2 + (y - 15.5) ** 2)
    if abs(d - 13.2) <= 0.9:
        col = RED
    # slash (top-left to bottom-right)
    if dist_to_segment(x, y, 6.0, 6.0, 26.0, 26.0) <= 1.4:
        col = RED
    return col


# ---------------------------------------------------------------- writers

def write_tga(path, w, h, rows, depth):
    """rows: top-down list of rows of (r, g, b[, a]). depth 24 or 32."""
    hdr = bytearray(18)
    hdr[2] = 2  # uncompressed truecolor
    hdr[12] = w & 0xFF
    hdr[13] = (w >> 8) & 0xFF
    hdr[14] = h & 0xFF
    hdr[15] = (h >> 8) & 0xFF
    hdr[16] = depth
    hdr[17] = 0x08 if depth == 24 else 0x28  # origin top-left, alpha bits
    data = bytearray()
    for row in rows:
        for px in row:
            if depth == 24:
                data += bytes((px[2], px[1], px[0]))
            else:
                data += bytes((px[2], px[1], px[0], px[3]))
    with open(path, "wb") as f:
        f.write(bytes(hdr) + bytes(data))


def _png_chunk(typ, data):
    c = struct.pack(">I", len(data)) + typ + data
    return c + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)


def write_png(path, w, h, rows):
    """rows: top-down rows of (r, g, b) or (r, g, b, a)."""
    has_a = len(rows[0][0]) == 4
    raw = bytearray()
    for row in rows:
        raw += b"\x00"
        for px in row:
            raw += bytes(px[:4] if has_a else px[:3])
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = _png_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if has_a else 2, 0, 0, 0))
    idat = _png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    with open(path, "wb") as f:
        f.write(sig + ihdr + idat + _png_chunk(b"IEND", b""))


def upscale(rows, k):
    """Nearest-neighbour upscale by factor k (for previews)."""
    out = []
    for row in rows:
        wide = [px for px in row for _ in range(k)]
        for _ in range(k):
            out.append(wide)
    return out


# ------------------------------------------------------------------- main

def main():
    os.makedirs(os.path.join(ROOT, "docs", "art"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "ArachnaphobiaShield"), exist_ok=True)

    icon = [[icon_pixel(i, j) for i in range(32)] for j in range(32)]
    write_tga(os.path.join(ROOT, "ArachnaphobiaShield", "icon.tga"), 32, 32, icon, 24)
    write_png(os.path.join(ROOT, "docs", "art", "icon_preview.png"), 32 * 8, 32 * 8, upscale(icon, 8))

    print("wrote ArachnaphobiaShield/icon.tga and docs/art/icon_preview.png; cover unchanged")


if __name__ == "__main__":
    main()
