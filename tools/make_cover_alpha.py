"""Cut the border-connected backing out of the fox cover, then place the
fox on a camouflage squircle card (in place).

Step 1: the imported fox art is painted on a navy backing (14, 19, 36).
Everything connected to the image border and close to that navy becomes
transparent; anti-aliased edge pixels receive partial alpha; art pixels are
left untouched.

Step 2: the cut fox is composited over a navy-toned camouflage squircle -
the same domain-warped noise field and superellipse as the preset covers,
at the same relative blotch scale (the field is normalized by size). The
camo is deliberate: this client fades nameplates (and anything parented to
them, i.e. our covers) with distance, and a flat fill lets a spider's
outline trace through the fade; a busy pattern does not give the eye a
uniform edge to lock onto. The world then shows through the rounded
corners only - the open areas around the fox are the card, not holes, so
the cover keeps a solid backing behind the art.

The file is rewritten as an uncompressed 32-bit RGBA TGA (same writer as
the rest of the pipeline). The script is a pure function of the original
opaque import: the cut and the card are both derived deterministically, so
regenerating from the import always yields the same bytes. It refuses to
treat an already-processed file as input (the card would be double-
baked); to regenerate, restore the import first:

    git show HEAD:ArachnaphobiaShield/cover.tga > ArachnaphobiaShield/cover.tga

Run locally (no network):
    uv run --with pillow python tools/make_cover_alpha.py [cover.tga]
"""
import sys
from collections import deque
from pathlib import Path

from PIL import Image

from make_art import write_png, write_tga
from make_backgrounds import BACKDROP, camo_color, squircle_alpha

ROOT = Path(__file__).resolve().parents[1]
NAVY = BACKDROP
FOX_SEED = 101  # stable seed: the fox card is fixed art, not random output
T_INNER = 24    # color distance from navy at or below this: fully transparent
T_OUTER = 64    # up to this distance: partial alpha (edge feather); beyond: art


def distance(a, b):
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def _over(fox, fox_a, back, back_a):
    """Straight-alpha 'fox over back' composite; back is (r, g, b)."""
    fa, ba = fox_a / 255, back_a / 255
    ao = fa + ba * (1 - fa)
    if ao <= 0:
        return (0, 0, 0, 0)
    fr, fg, fb = fox[0], fox[1], fox[2]
    br, bg, bb = back[0], back[1], back[2]
    return (round((fr * fa + br * ba * (1 - fa)) / ao),
            round((fg * fa + bg * ba * (1 - fa)) / ao),
            round((fb * fa + bb * ba * (1 - fa)) / ao),
            round(ao * 255))


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "ArachnaphobiaShield" / "cover.tga"
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    border = ([px[x, 0][3] for x in range(w)] + [px[x, h - 1][3] for x in range(w)]
              + [px[0, y][3] for y in range(h)] + [px[w - 1, y][3] for y in range(h)])
    if any(a < 255 for a in border):
        sys.exit("input has transparent border pixels: it looks like an "
                 "already-processed cover. Restore the original import "
                 f"({path.name}) and re-run - the card would otherwise be "
                 "baked in twice.")
    visited = [[False] * w for _ in range(h)]
    # Start from the image's own alpha: the cut may only lower it, never
    # raise it (that is what makes re-runs idempotent).
    alpha = [[px[x, y][3] for x in range(w)] for y in range(h)]
    queue = deque()

    def visit(x, y):
        if 0 <= x < w and 0 <= y < h and not visited[y][x]:
            r, g, b, a = px[x, y]
            if a < 255:
                visited[y][x] = True   # already transparent: keep, stop here
                return
            if distance((r, g, b), NAVY) <= T_OUTER:
                visited[y][x] = True
                queue.append((x, y))

    for x in range(w):
        visit(x, 0)
        visit(x, h - 1)
    for y in range(h):
        visit(0, y)
        visit(w - 1, y)
    while queue:
        x, y = queue.popleft()
        visit(x + 1, y)
        visit(x - 1, y)
        visit(x, y + 1)
        visit(x, y - 1)

    for y in range(h):
        for x in range(w):
            if not visited[y][x]:
                continue
            r, g, b, a = px[x, y]
            if a < 255:
                continue   # alpha already holds the stored value
            d = distance((r, g, b), NAVY)
            if d <= T_INNER:
                alpha[y][x] = 0
            else:
                alpha[y][x] = round(255 * (d - T_INNER) / (T_OUTER - T_INNER))

    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = px[x, y]
            fox_a = alpha[y][x]
            card_a = squircle_alpha(x, y, w)
            if card_a == 0:
                # Outside the squircle the world shows through; any art that
                # reaches this far keeps only its own alpha (no card behind).
                row.append((0, 0, 0, 0) if fox_a <= 0 else (r, g, b, fox_a))
                continue
            row.append(_over((r, g, b), fox_a, camo_color(NAVY, x, y, w, FOX_SEED),
                             card_a))
        rows.append(row)
    write_tga(str(path), w, h, rows, 32)
    preview = ROOT / "docs" / "art" / "cover_preview.png"
    preview.parent.mkdir(parents=True, exist_ok=True)
    write_png(str(preview), w, h, rows)
    cut = sum(1 for y in range(h) for x in range(w) if alpha[y][x] == 0)
    print(f"Wrote {path} ({w}x{w} 32-bit RGBA; {cut} fully transparent pixels)")
    print(f"Preview: {preview}")


if __name__ == "__main__":
    main()
