"""Convert a local image into the addon's opaque, full-color cover texture.

Run locally: uv run --with pillow python tools/import_cover.py <image-path> --output <cover.tga>
No network calls are made. The source image is read without modifying it.
"""
import argparse
from pathlib import Path
import struct

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SIZE = 512
BACKDROP = (14, 19, 36)  # Keep in sync with Cover.lua's fallback color.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True,
                        help="Destination .tga inside a local addon folder")
    parser.add_argument("--preview", type=Path, help="Optional preview PNG destination")
    args = parser.parse_args()
    output = args.output.resolve()
    preview = args.preview.resolve() if args.preview else output.with_name(output.stem + "_preview.png")
    if output.suffix.lower() != ".tga" or preview.suffix.lower() != ".png":
        parser.error("Output must end in .tga and preview must end in .png")
    if args.source.resolve() in (output.resolve(), preview.resolve()):
        parser.error("Use the original local image, not an output file")

    with Image.open(args.source) as original:
        image = ImageOps.exif_transpose(original).convert("RGBA")
        # Fit the entire illustration without cropping or changing its aspect.
        image.thumbnail((SIZE, SIZE), Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", (SIZE, SIZE), BACKDROP)
        canvas.paste(image, ((SIZE - image.width) // 2,
                             (SIZE - image.height) // 2), image)
    # Uncompressed, 24-bit, bottom-left TGA: no alpha/RLE support required.
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, format="TGA", compression=None)
    preview.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(preview)

    header = output.read_bytes()[:18]
    assert header[2] == 2 and header[16] == 24
    assert struct.unpack_from("<HH", header, 12) == (SIZE, SIZE)
    with Image.open(output) as installed:
        assert installed.mode == "RGB"
        assert installed.tobytes() == canvas.tobytes()
    print(f"Wrote {output} ({SIZE}x{SIZE}, opaque RGB)")
    print(f"Preview: {preview}")


if __name__ == "__main__":
    main()
