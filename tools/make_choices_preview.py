"""Render docs/art/cover_choices.png: the five shipped covers on a checker.

Regenerate after any cover asset change so the bundled preview matches the
release: uv run --with pillow python tools/make_choices_preview.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
COVERS = ["cover.tga", "cover-red.tga", "cover-blue.tga", "cover-sage.tga",
          "cover-charcoal.tga"]
TILE_W, TILE_H = 160, 200
CHECK = 16
LIGHT, DARK = (134, 140, 154), (88, 94, 108)


def main():
    sheet = Image.new("RGBA", (TILE_W * len(COVERS), TILE_H), LIGHT)
    px = sheet.load()
    for y in range(TILE_H):
        for x in range(TILE_W * len(COVERS)):
            px[x, y] = ((DARK if (x // CHECK + y // CHECK) % 2 else LIGHT) + (255,))
    for i, name in enumerate(COVERS):
        cover = Image.open(ROOT / "ArachnaphobiaShield" / name).convert("RGBA")
        cover = cover.resize((TILE_W, TILE_H - 40), Image.LANCZOS)
        sheet.alpha_composite(cover, (i * TILE_W, 20))
    out = ROOT / "docs" / "art" / "cover_choices.png"
    sheet.convert("RGB").save(out)
    print(f"Wrote {out} ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()
