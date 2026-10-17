"""Generate camouflage cover presets and the picker's solid UI textures.

Every preset ships as a 32-bit RGBA TGA: a busy multi-octave camouflage
field (domain-warped fractal value noise, three tones plus fine grain)
inside a supersampled squircle, alpha 0 outside the squircle so the world
shows through the rounded corners. The camouflage is deliberate: this
client fades nameplates (and anything parented to them, i.e. our covers)
with distance, and that fade cannot be turned off from the addon. A flat
fill lets a spider's outline trace through the fade; a busy pattern does
not give the eye a uniform edge to lock onto.

The picker's solid colors and the navy floor under unverified custom art
ship as tiny 8x8 TGAs: this client has only proven the string-path
SetTexture (every visible texture Spoken renders comes from a file), while
the numeric SetTexture(r, g, b, a) form silently did nothing on the
picker, which is why the window showed no background.

The fox cover (cover.tga) is handled separately: tools/import_cover.py
imports the supplied art, then tools/make_cover_alpha.py cuts its
border-connected navy backing out and composites the fox over a navy
squircle card (transparent rounded corners only).
"""
import math
from pathlib import Path

from make_art import write_png, write_tga

ROOT = Path(__file__).resolve().parents[1]
SIZE = 128
BACKDROP = (14, 19, 36)
COLORS = {
    "red": (132, 54, 58),
    "blue": (60, 93, 130),
    "sage": (78, 108, 88),
    "charcoal": (42, 45, 52),
}
# Stable per-preset seeds: the pattern is fixed art, not random output.
SEEDS = {"red": 11, "blue": 29, "sage": 47, "charcoal": 73}
# (file name, rgb) - 8x8 solid picker textures loaded via string paths.
PICKER_TEXTURES = {
    "picker-bg.tga": (26, 28, 41),
    "picker-btn.tga": (41, 48, 64),
    "picker-btn-sel.tga": (51, 97, 122),
    "picker-field.tga": (33, 38, 51),
}


# ---------------------------------------------------------------- noise

def _hash(ix, iy, seed):
    h = (ix * 374761393 + iy * 668265263 + seed * 1274126177) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFFFF) / 4294967295.0


def _value_noise(u, v, seed):
    ix, iy = int(math.floor(u)), int(math.floor(v))
    fx, fy = u - ix, v - iy
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    a = _hash(ix, iy, seed)
    b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix + 1, iy + 1, seed)
    top = a + (b - a) * sx
    bot = c + (d - c) * sx
    return top + (bot - top) * sy


def _fbm(u, v, seed, octaves=4, gain=0.55, lacunarity=2.0):
    total = 0.0
    amplitude = 1.0
    freq = 1.0
    norm = 0.0
    for o in range(octaves):
        total += amplitude * _value_noise(u * freq, v * freq, seed + o * 101)
        norm += amplitude
        amplitude *= gain
        freq *= lacunarity
    return total / norm


def _band(n, lo, hi):
    if n <= lo:
        return 0.0
    if n >= hi:
        return 1.0
    t = (n - lo) / (hi - lo)
    return t * t * (3 - 2 * t)


def _camo_field(u, v, seed):
    # Domain-warped fractal noise: the warp gives the blotches their
    # organic, non-repeating swirl instead of foggy blobs.
    wx = _fbm(u * 0.6 + 3.1, v * 0.6 + 7.7, seed + 7, octaves=3)
    wy = _fbm(u * 0.6 + 19.3, v * 0.6 + 2.9, seed + 29, octaves=3)
    return _fbm(u + 1.4 * (wx - 0.5), v + 1.4 * (wy - 0.5), seed, octaves=4)


def camo_color(base, x, y, size, seed):
    """Three-tone camouflage (dark blotch / base / light blotch) + grain."""
    u = (x + 0.5) / size * 5.0
    v = (y + 0.5) / size * 5.0
    f = _camo_field(u, v, seed)
    tone = 0.5 * _band(f, 0.36, 0.50) + 0.5 * _band(f, 0.55, 0.69)
    dark = (round(c * 0.58) for c in base)
    light = (min(255, round(c * 1.32 + 10)) for c in base)
    col = tuple(d + (l - d) * tone for d, l in zip(dark, light))
    # Mid-frequency detail breaks up any remaining flat middle tone.
    m = _fbm(u * 2.3 + 11.7, v * 2.3 + 5.1, seed + 31, octaves=3) - 0.5
    # Fine grain: the busier the fill, the harder an outline reads through it.
    g = _value_noise((x + 0.5) * 0.9, (y + 0.5) * 0.9, seed + 991) - 0.5
    return tuple(max(0, min(255, round(c * (1 + m * 0.10) + g * 18))) for c in col)


def squircle_alpha(x, y, size):
    """0..255 supersampled coverage of the squircle at pixel (x, y)."""
    center = size / 2
    radius = size / 2 - size / 64
    inside = 0
    for dx in (0.125, 0.375, 0.625, 0.875):
        for dy in (0.125, 0.375, 0.625, 0.875):
            if (abs(x + dx - center) / radius) ** 4 + (abs(y + dy - center) / radius) ** 4 <= 1:
                inside += 1
    return round(inside * 255 / 16)


def main():
    previews = ROOT / "docs" / "art"
    previews.mkdir(parents=True, exist_ok=True)
    for name, color in COLORS.items():
        seed = SEEDS[name]
        rows = []
        for y in range(SIZE):
            row = []
            for x in range(SIZE):
                a = squircle_alpha(x, y, SIZE)
                if a == 0:
                    row.append((0, 0, 0, 0))
                else:
                    r, g, b = camo_color(color, x, y, SIZE, seed)
                    row.append((r, g, b, a))
            rows.append(row)
        write_tga(str(ROOT / "ArachnaphobiaShield" / f"cover-{name}.tga"), SIZE, SIZE, rows, 32)
        write_png(str(previews / f"cover-{name}_preview.png"), SIZE, SIZE, rows)
    for filename, color in PICKER_TEXTURES.items():
        rows = [[(color[0], color[1], color[2]) for _ in range(8)] for _ in range(8)]
        write_tga(str(ROOT / "ArachnaphobiaShield" / filename), 8, 8, rows, 24)
    # Navy floor drawn under unverified custom art (Cover.lua's
    # BACKDROP_PATH), string-path texture for the same client reason.
    write_tga(str(ROOT / "ArachnaphobiaShield" / "cover-backdrop.tga"), 8, 8,
              [[BACKDROP for _ in range(8)] for _ in range(8)], 24)
    # Editor-only transparency preview; never used as a model cover.
    import struct
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, 64, 64, 24, 0x20)
    body = bytearray()
    for y in range(64):
        for x in range(64):
            color = (88, 94, 108) if (x // 8 + y // 8) % 2 else (134, 140, 154)
            body.extend(reversed(color))
    (ROOT / "ArachnaphobiaShield" / "preview-checker.tga").write_bytes(header + body)
    print("Generated red, blue, sage, charcoal camouflage squircles (32-bit RGBA, "
          "transparent corners), four picker UI textures, the custom-art navy "
          "floor and the preview checker")


if __name__ == "__main__":
    main()
