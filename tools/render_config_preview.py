"""Render docs/art/config_preview.png: the cover picker as shipped.

Regenerate after any picker layout or cover asset change so the bundled
preview matches the release:
    uv run --with pillow python tools/render_config_preview.py

The layout mirrors ArachnaphobiaShield/Config.lua (640x480 window, preset buttons
left, checker + fox preview right, custom-image row at the bottom). v0.3.8
removed the opacity section, so the window is shorter.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from make_backgrounds import PICKER_TEXTURES

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "ArachnaphobiaShield"
OUT = ROOT / "docs" / "art" / "config_preview.png"

W, H = 640, 480
BG = PICKER_TEXTURES["picker-bg.tga"]
BTN = PICKER_TEXTURES["picker-btn.tga"]
BTN_SEL = PICKER_TEXTURES["picker-btn-sel.tga"]
FIELD = PICKER_TEXTURES["picker-field.tga"]
TEXT = (242, 242, 250)
PRESETS = ["Fox", "Muted red squircle", "Muted blue squircle",
           "Sage green squircle", "Plain charcoal"]
FONT = "DejaVuSans.ttf"  # found by Pillow's system font search


def label(draw, box, text, size, align="left", color=TEXT):
    x, y, w, h = box
    f = ImageFont.truetype(FONT, size)
    bbox = draw.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = x + 8 if align == "left" else x + (w - tw) // 2
    draw.text((tx, y + (h - th) // 2 - bbox[1]), text, font=f, fill=color)


def main():
    sheet = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(sheet)

    # Title, subtitle, close button.
    label(draw, (16, 12, 480, 30), "Arachnaphobia Shield - Covers", 19)
    label(draw, (20, 44, 600, 26), "Choose the cover image that feels comfortable for you.", 14)
    draw.rectangle((554, 14, 624, 42), fill=BTN)
    label(draw, (554, 14, 70, 28), "Close", 14, align="center")

    # Preset buttons (Fox is selected in this mock).
    for i, name in enumerate(PRESETS):
        y = 80 + i * 44
        draw.rectangle((20, y, 250, y + 36), fill=BTN_SEL if i == 0 else BTN)
        label(draw, (20, y, 230, 36), name, 14, align="center")
    draw.rectangle((20, 300, 250, 336), fill=BTN)
    label(draw, (20, 300, 230, 36), "Custom image", 14, align="center")

    # Preview: stretched checker under the fox cover. The bundled presets'
    # backing layer is vertex-alpha 0, so only checker + art are visible.
    checker = Image.open(ADDON / "preview-checker.tga").convert("RGBA").resize(
        (256, 256), Image.NEAREST)
    fox = Image.open(ADDON / "cover.tga").convert("RGBA").resize((256, 256), Image.LANCZOS)
    preview = checker
    preview.alpha_composite(fox)
    sheet.paste(preview, (349, 80), preview)

    # Status under the preview, then the custom-image row and footer.
    label(draw, (285, 342, 340, 20), "Selected: Fox", 12, align="center")
    label(draw, (285, 362, 340, 20), "Changes save automatically.", 12, align="center")
    label(draw, (20, 384, 600, 24), "Custom image: local addon texture path", 13)
    draw.rectangle((20, 411, 490, 439), fill=FIELD)
    draw.rectangle((500, 411, 620, 439), fill=BTN)
    label(draw, (500, 411, 120, 28), "Use image", 14, align="center")
    label(draw, (20, 453, 600, 22),
          "Covers stay click-through. Close this window to return to play.", 12)

    sheet.save(OUT)
    print(f"Wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
