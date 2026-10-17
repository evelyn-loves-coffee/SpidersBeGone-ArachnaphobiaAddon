"""Build an installable ZIP and test its extracted Lua files with Lua 5.1.

The release zip is written to dist/ (the repository's git-ignored build
output directory) - never to the repository's parent folder.

Run from the repository root: uv run --with lupa python tools/package_addon.py
"""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import os
import re
import shutil
import struct

from lupa.lua51 import LuaRuntime


def main():
    root = Path(__file__).resolve().parents[1]
    addon = root / "ArachnaphobiaShield"
    toc_path = addon / "ArachnaphobiaShield.toc"
    toc_text = toc_path.read_text(encoding="utf-8")
    match = re.search(r"^## Version: ([0-9]+(?:\.[0-9]+)*)$", toc_text, re.MULTILINE)
    if not match:
        raise ValueError("Missing or invalid addon version")
    version = match.group(1)
    # Build output belongs in the git-ignored dist/ directory, not in the
    # repository's parent folder (which is where this checkout lives).
    output = root / "dist" / f"ArachnaphobiaShield-{version}-fixed.zip"
    dependencies = [line.strip() for line in toc_text.splitlines()
                    if line.strip() and not line.startswith("#")]
    sources = [toc_path, addon / "icon.tga", addon / "preview-checker.tga"]
    # Only shipped presets belong in a release; never collect private custom art.
    sources.extend(addon / name for name in (
        "cover.tga", "cover-red.tga", "cover-blue.tga", "cover-sage.tga", "cover-charcoal.tga"))
    # The picker's solid colors and the custom-art navy floor are tiny TGA
    # files (string-path SetTexture is the only texture form proven on this
    # client; numeric is a no-op).
    sources.extend(addon / name for name in (
        "picker-bg.tga", "picker-btn.tga", "picker-btn-sel.tga", "picker-field.tga",
        "cover-backdrop.tga"))
    sources.extend(addon / name for name in dependencies)
    for source in sources:
        if not source.resolve().is_relative_to(addon.resolve()) or not source.is_file():
            raise ValueError(f"Invalid addon dependency: {source}")
        if source.name.startswith("cover") and source.suffix == ".tga":
            # Presets and the fox ship as 32-bit RGBA squircle cards (the
            # world shows through the rounded corners); a 24-bit cover is
            # still accepted for the opaque plain-square fallback.
            data = source.read_bytes()
            width, height = struct.unpack_from("<HH", data, 12)
            depth = data[16]
            assert data[2] == 2 and depth in (24, 32), source.name
            assert width > 0 and height > 0 and width & (width - 1) == 0 and height & (height - 1) == 0
            assert len(data) >= 18 + width * height * (4 if depth == 32 else 3)
            if depth == 32:
                # Squircle invariant: top-left corner transparent, center
                # opaque (origin flag is top-left; pixels are BGRA).
                assert data[21] == 0, source.name + ": corner must be transparent"
                mid = 18 + (height // 2) * width * 4 + (width // 2) * 4
                assert data[mid + 3] == 255, source.name + ": center must be opaque"

    with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
        for source in sorted(set(sources)):
            archive.write(source, "ArachnaphobiaShield/" + source.relative_to(addon).as_posix())
        archive.write(root / "README.md", "ArachnaphobiaShield/README.md")
        archive.write(root / "LICENSE", "ArachnaphobiaShield/LICENSE")
        archive.write(root / "LICENSE", "ArachnaphobiaShield/LICENSE.txt")
        # Ship current controls only; archived plans advertise removed features.
        for name in ("HANDOFF.md", "TRACKING-ONLY.md", "COVER-IMAGES.md", "CORPSE-HANDLING.md", "DATA-SOURCES.md"):
            source = root / "docs" / name
            archive.write(source, "ArachnaphobiaShield/" + source.relative_to(root).as_posix())
        for name in ("config_preview.png", "cover_choices.png"):
            source = root / "docs" / "art" / name
            archive.write(source, "ArachnaphobiaShield/docs/art/" + name)

    review = root / "dist" / f"install-check-{version}"
    assert review.resolve().is_relative_to(root.resolve())
    assert review.parent.resolve() == (root / "dist").resolve()
    if review.exists():
        shutil.rmtree(review)  # only this generated, validated review directory
    review.mkdir(parents=True)
    with ZipFile(output) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            assert name.startswith("ArachnaphobiaShield/") and ".." not in Path(name).parts
        archive.extractall(review)
    for source in sources:
        packaged = review / "ArachnaphobiaShield" / source.name
        assert packaged.read_bytes() == source.read_bytes(), source.name
    readme = (review / "ArachnaphobiaShield" / "README.md").read_text(encoding="utf-8")
    assert "GrasHopper42" in readme and "nospider-arachnophobia-mode" in readme
    assert (review / "ArachnaphobiaShield" / "LICENSE.txt").read_bytes() == (root / "LICENSE").read_bytes()

    # Exercise the actual packaged Lua files using the existing client stubs.
    messages = []
    original_cwd = Path.cwd()
    try:
        os.chdir(review)
        lua = LuaRuntime()
        lua.globals().print = lambda message: messages.append(str(message))
        lua.execute((root / "tools" / "test_core.lua").read_text(encoding="utf-8"))
    except Exception:
        for message in messages:
            if message.startswith("FAIL:"):
                print(message)
        raise
    finally:
        os.chdir(original_cwd)
        (root / "dist" / f"validation-{version}.txt").write_text(
            "\n".join(messages) + "\n", encoding="utf-8")
    assert messages[-1] == "ALL TESTS PASS"
    passed = sum(message.startswith("PASS:") for message in messages)
    print(f"Packaged-addon Lua 5.1 regression suite: {passed} checks passed")
    print("Archive integrity, dependencies, version, license and NoSpider credit: passed")
    print(f"ZIP: {output}")
    print(f"SHA256: {hashlib.sha256(output.read_bytes()).hexdigest()}")
    print(f"Size: {output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
