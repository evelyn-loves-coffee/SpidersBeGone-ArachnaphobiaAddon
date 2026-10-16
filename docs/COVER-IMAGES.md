# Choose your cover image (v0.3.3)

Run `/sbg config` to open the cover picker. Click a preset to preview it
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
| Fox | Supplied illustration, original colors, fitted in proportion | `/sbg cover fox` |
| Muted red | Red squircle, similar in spirit to the previous cover | `/sbg cover red` |
| Muted blue | Plain blue squircle | `/sbg cover blue` |
| Sage green | Plain green squircle | `/sbg cover sage` |
| Plain charcoal | Uniform dark grey square | `/sbg cover charcoal` |

For simple backgrounds, these are starting suggestions to try according to
personal preference. They have no animation, patterns or spider imagery.
All shipped textures have opaque pixels throughout the square: the rounded
shapes sit on a solid dark blue backing. Picture colors are preserved.
Opacity defaults to 100%; at lower settings the scene can show through. Models can still extend beyond an undersized or
misaligned cover; the nameplate-tracking limitations still apply.

`/sbg cover` lists choices and the selected image. `/sbg options` is
an alias for the picker. If this client's window APIs reject the panel,
the addon prints command-based instructions and tracking continues.

Offline layout preview (client fonts/rendering may differ):

![Cover picker layout](art/config_preview.png)

## Opacity

The slider in `/sbg config` runs only from **80% to 100%**, with 1% steps.
The default is **100% (fully opaque)**. Changes update the checkerboard preview
and existing covers immediately, save automatically and survive reloads.
Choosing a different image preserves opacity; adjusting opacity does not
replace an unfinished custom-image path. Lower opacity lets some of the
scene show through, so use 100% for complete opacity within the cover.

The range is enforced in the control, saved-settings migration and rendering,
so a low or invalid old value cannot draw a cover below the 80% setting.
Missing/invalid numeric values use 100%; values below 80% clamp to 80%, and
values above 100% clamp to 100%. The editor and corpse warning are not faded.
Custom images retain a backing and may appear more opaque than the selected
value, protecting areas where an image contains transparent pixels.

Command fallback: `/sbg opacity 0.8` or `/sbg opacity 1`; bare
`/sbg opacity` reports the current value. If the client rejects native
Slider APIs, the picker keeps working with 80/85/90/95/100% buttons. Covers
remain permanently click-through; only the explicit configuration window
accepts slider input. Native slider rendering still needs partner validation.

## Use your own image

Prepare a local square TGA texture, for example:

```text
<game folder>/Interface/AddOns/MyCovers/flower.tga
```

Then paste its game-relative path into the picker and click **Use image**,
or enter:

```text
/sbg cover custom Interface\AddOns\MyCovers\flower.tga
```

Use a separate `MyCovers` folder to keep personal images outside addon
updates. `/sbg cover custom` reselects the last saved custom path.
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
