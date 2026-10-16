# Choose your cover image (v0.3.1)

Run `/spider config` to open the cover picker. Click a preset to preview it
and update every cover immediately. The choice is saved in addon settings
and survives reloads; the fox is the default for new or migrated settings.
The window appears only when requested. Close it to return to play.

Covers are permanently click-through and attach only to nameplates. They
cannot be moved by hand or restored from a saved screen layout. Changing an image while
the addon is disabled keeps it disabled. Tracking, cover sizing and the
1.75-second look-away warning are independent of the selected picture.

## Included choices

![Included cover choices](art/cover_choices.png)

| Choice | Appearance | Command |
| --- | --- | --- |
| Fox | Supplied illustration, original colors, fitted in proportion | `/spider cover fox` |
| Muted red | Red squircle, similar in spirit to the previous cover | `/spider cover red` |
| Muted blue | Plain blue squircle | `/spider cover blue` |
| Sage green | Plain green squircle | `/spider cover sage` |
| Plain charcoal | Uniform dark grey square | `/spider cover charcoal` |

For simple backgrounds, these are starting suggestions to try according to
personal preference. They have no animation, patterns or spider imagery.
All shipped textures have opaque pixels throughout the square: the rounded
shapes sit on a solid dark blue backing so their corners cannot reveal a
model. Covers remain fully opaque and preserve picture colors regardless of
old tint/opacity settings. Models can still extend beyond an undersized or
misaligned cover; the nameplate-tracking limitations still apply.

`/spider cover` lists choices and the selected image. `/spider options` is
an alias for the picker. If this client's window APIs reject the panel,
the addon prints command-based instructions and tracking continues.

Offline layout preview (client fonts/rendering may differ):

![Cover picker layout](art/config_preview.png)

## Use your own image

Prepare a local square TGA texture, for example:

```text
<game folder>/Interface/AddOns/MyCovers/flower.tga
```

Then paste its game-relative path into the picker and click **Use image**,
or enter:

```text
/spider cover custom Interface\AddOns\MyCovers\flower.tga
```

Use a separate `MyCovers` folder to keep personal images outside addon
updates. `/spider cover custom` reselects the last saved custom path.
Choose a bundled preset at any time to switch back.

The addon reads only a local `.tga` texture through the game's normal UI
API. The picker does not browse Windows files, download images or upload
anything. Windows paths and web addresses are rejected. To use a PNG or
JPEG illustration, convert it first with the included local helper:

```powershell
uv run --with pillow python tools/import_cover.py "C:\Pictures\flower.png" --output "C:\Games\WoW\Interface\AddOns\MyCovers\flower.tga"
```

Replace those example paths with your own. The helper reads the source
without modifying it, fits the entire illustration into a 512 x 512 square
without stretching/cropping, composites transparent areas over dark blue,
and writes an uncompressed 24-bit RGB TGA plus a PNG preview alongside it.
Image processing stays local; `uv` may download the Pillow dependency.
If you use another converter, a 512 x 512 uncompressed RGB TGA is the format
used and checked for the included fox. Transparent custom images receive
the addon's opaque backing too.

Fully exit and reopen the game after adding a new texture, then check the
picker's preview. This is a conservative installation step: new-file reload
behavior has not been verified on this Forever client. A reported texture
failure falls back to the fox. Some clients accept a missing filename and
display a placeholder instead; Lua cannot reliably detect that, so use the
preview to confirm the image appears. A solid backing still hides the area
behind transparent portions of the cover.

Personal custom files are not part of release packages. The packaging tool
uses an explicit list of approved bundled images. `SpidersBeGone/Custom/`
is ignored by Git if you keep local files there during development.

## Additional examples and maintenance

The preset list in `SpidersBeGone/Appearance.lua` drives the buttons and
selection handler. To ship another approved illustration, prepare its TGA,
add a preset entry, add the filename to `tools/package_addon.py`, and
regenerate the package. Changing a user's custom image requires no code
changes. Supplied artwork needs permission before publication.

`tools/make_backgrounds.py` regenerates only the four original simple
backgrounds; `tools/make_art.py` regenerates only the addon icon. Neither
overwrites the supplied fox. The supplied fox is included with the user's
explicit permission to publish it with this addon. No NoSpider artwork is
used.

The picker uses ordinary addon-owned Button/EditBox frames, without changing
protected game frames. The Forever snapshot's generated
[EditBox API documentation](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleEditBoxAPIDocumentation.lua)
documents the text/focus methods. The full picker has offline behavioral
coverage; its native rendering and input still require live-client validation.
