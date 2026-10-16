"""Build an installable ZIP and test its extracted Lua files with Lua 5.1.

Run from the repository root: uv run --with lupa python tools/package_addon.py
"""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import os
import re
import shutil

from lupa.lua51 import LuaRuntime


def main():
    root = Path(__file__).resolve().parents[1]
    addon = root / "SpidersBeGone"
    toc_path = addon / "SpidersBeGone.toc"
    toc_text = toc_path.read_text(encoding="utf-8")
    match = re.search(r"^## Version: ([0-9]+(?:\.[0-9]+)*)$", toc_text, re.MULTILINE)
    if not match:
        raise ValueError("Missing or invalid addon version")
    version = match.group(1)
    output = root.parent / f"SpidersBeGone-{version}-fixed.zip"
    dependencies = [line.strip() for line in toc_text.splitlines()
                    if line.strip() and not line.startswith("#")]
    sources = [toc_path, addon / "icon.tga"]
    # Only shipped presets belong in a release; never collect private custom art.
    sources.extend(addon / name for name in (
        "cover.tga", "cover-red.tga", "cover-blue.tga", "cover-sage.tga", "cover-charcoal.tga"))
    sources.extend(addon / name for name in dependencies)
    for source in sources:
        if not source.resolve().is_relative_to(addon.resolve()) or not source.is_file():
            raise ValueError(f"Invalid addon dependency: {source}")

    with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
        for source in sorted(set(sources)):
            archive.write(source, "SpidersBeGone/" + source.relative_to(addon).as_posix())
        archive.write(root / "README.md", "SpidersBeGone/README.md")
        archive.write(root / "LICENSE", "SpidersBeGone/LICENSE")
        archive.write(root / "LICENSE", "SpidersBeGone/LICENSE.txt")
        # Ship current controls only; archived plans advertise removed features.
        for name in ("HANDOFF.md", "TRACKING-ONLY.md", "COVER-IMAGES.md", "CORPSE-HANDLING.md", "DATA-SOURCES.md"):
            source = root / "docs" / name
            archive.write(source, "SpidersBeGone/" + source.relative_to(root).as_posix())
        for name in ("config_preview.png", "cover_choices.png"):
            source = root / "docs" / "art" / name
            archive.write(source, "SpidersBeGone/docs/art/" + name)

    review = root / "dist" / f"install-check-{version}"
    assert review.resolve().is_relative_to(root.resolve())
    assert review.parent.resolve() == (root / "dist").resolve()
    if review.exists():
        shutil.rmtree(review)  # only this generated, validated review directory
    review.mkdir(parents=True)
    with ZipFile(output) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            assert name.startswith("SpidersBeGone/") and ".." not in Path(name).parts
        archive.extractall(review)
    for source in sources:
        packaged = review / "SpidersBeGone" / source.name
        assert packaged.read_bytes() == source.read_bytes(), source.name
    readme = (review / "SpidersBeGone" / "README.md").read_text(encoding="utf-8")
    assert "GrasHopper42" in readme and "nospider-arachnophobia-mode" in readme
    assert (review / "SpidersBeGone" / "LICENSE.txt").read_bytes() == (root / "LICENSE").read_bytes()

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
