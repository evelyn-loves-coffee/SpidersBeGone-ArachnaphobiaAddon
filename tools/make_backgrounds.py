"""Generate original, fully opaque background presets; never replace fox art."""
from pathlib import Path
import struct

from make_art import write_png

ROOT = Path(__file__).resolve().parents[1]
SIZE = 128
BACKDROP = (14, 19, 36)
COLORS = {
    "red": (132, 54, 58),
    "blue": (60, 93, 130),
    "sage": (78, 108, 88),
    "charcoal": (42, 45, 52),
}


def pixel(name, x, y):
    color = COLORS[name]
    if name == "charcoal":
        return color
    # Supersample just the edge of a flat squircle over an opaque backing.
    inside = 0
    for dx in (0.125, 0.375, 0.625, 0.875):
        for dy in (0.125, 0.375, 0.625, 0.875):
            if (abs(x + dx - 64) / 62) ** 4 + (abs(y + dy - 64) / 62) ** 4 <= 1:
                inside += 1
    return tuple(round((color[i] * inside + BACKDROP[i] * (16 - inside)) / 16) for i in range(3))


def main():
    previews = ROOT / "docs" / "art"
    previews.mkdir(parents=True, exist_ok=True)
    for name in COLORS:
        rows = [[pixel(name, x, y) for x in range(SIZE)] for y in range(SIZE)]
        # Uncompressed RGB with a top-left origin; every pixel is opaque.
        header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 24, 0x20)
        body = bytes(channel for row in rows for r, g, b in row for channel in (b, g, r))
        (ROOT / "SpidersBeGone" / f"cover-{name}.tga").write_bytes(header + body)
        write_png(str(previews / f"cover-{name}_preview.png"), SIZE, SIZE, rows)
    print("Generated red, blue, sage and charcoal presets with opaque backings")
    # Editor-only transparency preview; never used as a model cover.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, 64, 64, 24, 0x20)
    body = bytearray()
    for y in range(64):
        for x in range(64):
            color = (88, 94, 108) if (x // 8 + y // 8) % 2 else (134, 140, 154)
            body.extend(reversed(color))
    (ROOT / "SpidersBeGone" / "preview-checker.tga").write_bytes(header + body)


if __name__ == "__main__":
    main()
