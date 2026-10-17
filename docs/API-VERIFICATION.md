> Historical reference only. v0.3.1 removed screen-positioned covers and all editing/input modes. Follow [HANDOFF.md](HANDOFF.md) for the current implementation and test machine. This file is not shipped in the addon ZIP.

# API verification record — WoW Forever 1.60.1

M1 exit criteria. Compiled 2026-10-13 from in-client probe rounds AS1–AS4
(full probe lines in [PLAN.md §12](PLAN.md#12-m1-in-client-verification-scripts))
and the Warcraft Wiki per-client API table
(`warcraft.wiki.gg/wiki/World_of_Warcraft_API/Classic`, current as of
2026-10-06, with an explicit **Forever 1.60.1 (70235) Beta** column).

## Environment (confirmed in-client)

| Fact | Value | Source |
|---|---|---|
| Build | `GetBuildInfo()` → `"1.60.1"`, `"70374"`, `"Oct 12 2026"`, `"16001"` (four strings, modern signature) | AS2 |
| **TOC interface number** | **16001** (4th `GetBuildInfo()` value; matches `Spoken_Books.toc` listing `16001`) | AS2 |
| Lua | **5.1** (`_VERSION` = "Lua 5.1"; `math.huge` present; `table.unpack`/`table.pack` absent; global `unpack` present) | AS2 |
| Locale | `enUS` | AS2 |
| Codebase generation | **Modern** (post-3.0 layout: `Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua` in error stack) with a **reduced** API set | AS1 error stack |
| Screen | `GetEffectiveScreenInfo()` → 1772.3 × 1181.5 (UI-scaled) | AS4 |
| Camera (moot, 3D path closed) | `GetCameraZoom()` = 30; `GetCameraFOVDefaults()` = 90, 50, 90 | AS4 |

## Confirmed PRESENT (in-client, this build)

`UnitName`, `GetUnitName`, `UnitLevel`, `UnitIsVisible`, `UnitIsDead`,
`UnitCanAttack`, `UnitCreatureType`, `UnitCreatureID` (→ 1504 for Young Night
Web Spider), **`UnitCreatureFamily`** (→ `("Spider", 3)` on a wild spider),
`UnitPosition` (player/party/raid only; player in Tirisfal: 2070.9, 1694.3,
z=0, map=0), `C_Timer`, `C_Map` (partial — no `PositionToScreen`),
`SlashCmdList`, `GetBuildInfo`, `GetEffectiveScreenInfo`, `GetCameraZoom`,
`GetCameraFOVDefaults`, `GetUICameraInfo` (call untested — probe had a syntax
error, irrelevant now).

Confirmed in-client 2026-10-13 (AS5): `GetCursorPosition` (returned
206,409), `UnitClass` (→ "Warrior"), `UnitFactionGroup` (→ "Horde"),
`PlaySoundFile`, the **`mouseover` unit token** end-to-end ("Young Night
Web Spider", family ("Spider",3), `UnitIsVisible` true, `UnitIsDead` tracks
dead state), frame globals `TargetFrame`, `FocusFrame`, `UIParent`.

Wiki-table-only, still unprobed: `GetScreenWidth`/`GetScreenHeight`,
`GetPhysicalScreenSize`, `UnitIsUnit`.

## Confirmed ABSENT (in-client, this build)

`WorldFramePoint3D`, `GetUnitPosition`, `GetUnitFamily`, `IsPlayerUnit`,
`GetNumAuras`, `GetUnitAura`, `GetScreenSize`, `C_Map.PositionToScreen`,
`GetUnitWorldPosition`, `GetCameraPosition` (global), `GetViewingInfo`,
the **`CHAT_COMMAND` event** (RegisterEvent rejects it — slash dispatch is a
direct `SlashCmdList[name]` lookup instead), the **`Bindings` table**, and
default-UI globals `MouseOverInfoFrame`, `PartyFrame1`, `MainMenuBar` (so:
no party-frame covers; screen placement uses `UIParent` +
`GetEffectiveScreenInfo`).

## Confirmed PRESENT — frame events (AS6, 2026-10-13)

`UNIT_TARGET`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`,
`VARIABLES_LOADED`, `UNIT_AURA`, `PLAYER_LOGIN` (pcall `RegisterEvent` — the
client *errors* on unknown events, so only these may be registered, or every
registration must be pcall-guarded).

**Absent events (AS6):** `MOUSEOVER`, `UPDATE`, `KEY_DOWN`, `KEY_UP`,
`PARTY_UPDATE`, `RAID_UPDATE`, `CHAT_COMMAND`, `ACTIONBAR_BUTTON_UP`.

## Confirmed DEAD ENDS (tested)

- **`ClosestUnitPosition(1504)` → nil** while standing in Tirisfal Glades
  (a starting zone) with the spider targeted. Wiki: "Only works for mobs in
  the starting zones" — the gate rejects it where the spiders live. Even a
  working result in Elwynn would not serve the spider use case (Elwynn has no
  spiders). → **3D-follow cover is infeasible on this client; UI-anchored
  design is final (PLAN.md §3.0).** `C_Map.ScreenToPosition` also absent.

## Textures (AS8, 2026-10-14 — in-game error + Spoken source)

- **Native `CreateTexture` is not the classic one.** Usage string:
  `local texture = self:CreateTexture(params)`. The classic call
  `frame:CreateTexture(nil, "BACKGROUND")` → in-game error `bad argument
  #3 to '?'` — **the classic `"BACKGROUND"` layer name is rejected on this
  client** (caught when the M3 build first loaded).
- **Layers proven on this client:** `"ARTWORK"` and `"HIGHLIGHT"` — the
  working Spoken addon's vanilla branch (its `Compat.lua`,
  `Version.IsLegacyVanilla`) calls the native `self:_CreateTexture(nil,
  "ARTWORK")` / `(nil, "HIGHLIGHT")` for SetNormalTexture/
  SetHighlightTexture. `"BACKGROUND"` appears only in Spoken's *mainline*
  branch.
- **Region methods proven** (Spoken vanilla branch, same client):
  `SetTexture(path)` string form, `SetTexture(r, g, b, a)` numeric form,
  `SetVertexColor(r, g, b)`, `SetAllPoints()` (no args), `SetPoint(...)`,
  `SetSize`, `Show`/`Hide`.
- **Spoken replaces the global `CreateFrame`**, installing mixins/overrides
  on returned frames (`CreateTexture(name, layer)` wrapping native
  `_CreateTexture`, plus `SetScript`/`HookScript`/`SetShown`/`SetSize`
  shims). Addons calling the global `CreateFrame` after Spoken loads get
  the shim; ours does not depend on it (we load alphabetically before
  Spoken and use the native API directly).
- **Our code's handling (Cover.lua):** `makeTexture` pcall-probes
  `CreateTexture(nil, layer)` with layers in order `ARTWORK, ART,
  BACKGROUND, MEDIUM, LOW, HIGH, HIGHLIGHT`, then a no-arg call. Both
  cover textures share the first working layer. Since v0.3.0 the fallback
  fills the entire frame and is created first; the opaque full-color fox
  texture is drawn over it with neutral white tint. Both remain fully opaque.

## Frames (AS9, 2026-10-14 — in-game error + Spoken source)

- **`SetClampRect` is ABSENT** (in-game "Cover.lua:82: attempt to call a
  nil value" — zero hits in the working Spoken addon). Covers are kept
  on-screen by a **soft clamp in `C.SyncDrags`** instead: the adopted
  drag position is clamped to the screen bounds and SetPoint back if the
  cover was dragged past the edge.
- **`SetSize` is absent on old clients** (Spoken's `RegionMixins` shims
  it as `SetWidth + SetHeight`; both are proven present via Spoken's
  `UI/Layout.lua`). Our `C.Resize` pcall-probes `SetSize`, falls back to
  `SetWidth`/`SetHeight`.
- **Proven present in-game by the crash location** (all ran before the
  crash, so they work on this client): `SetParent`, `SetFrameStrata`,
  `EnableMouse`, `SetMovable`, pcall-probed `CreateTexture(nil,
  "ARTWORK")`, `SetAllPoints()` (no args). Also proven in Spoken:
  `SetPoint`, `GetPoint`, `IsShown`, `Show`/`Hide`, `SetScript`,
  `RegisterEvent`.

## Scripts (AS10, 2026-10-14 — Spoken source)

- **Native `SetScript` calls handlers with NO arguments.** Event data
  arrives via the globals `this`, `event`, `arg1`..`arg9` — proven by
  Spoken's Compat.lua `FrameOverrides:SetScript`, which wraps every
  handler as `function() handler(this, event, arg1, ...) end` before the
  native `_SetScript`. A handler that declares an `event` parameter
  receives nil and its event check never matches — a *silent* failure
  (no error, addon just never initializes from the event).
- Our OnEvent handler uses `local ev = evt or event` (modern argument
  first, then the old-style global) so it works under either convention.

## Chat text (AS11, 2026-10-14 — observed in-game)

- **Never print `|` + letter in chat**: the client's chat filter eats
  chat-control sequences. `/spider help` printed
  `on|off|toggle|clear|help` and the chat displayed
  `on|offoggle|cleareIp` — `|t` and `|h` were consumed as control
  sequences. Our chat output uses ` / ` separators instead; `AS| ` and
  ` | ` (pipe with surrounding spaces) are observed safe.

## Frames, display pass & GetPoint (AS12, 2026-10-15 — observed in-game)

- **`Show()` is deferred to the next display pass.** In-game: first run
  allocated 8 parks, `IsShown()` was still false when we saved
  synchronously right after, so the WSV file ended up with
  `covers[<char>] = {}` while the screen showed 8 covers (selftest:
  `shown=8/24 saved=0`). Consequence: persistence logic must be based on
  allocation state (the pool queue), never on `IsShown()` called in the
  same synchronous block as `Show()`.
- **`GetPoint` returns 9 values**: (point, relativeToFrame,
  relativeToPoint, x, y, width, height, absX, absY). The offsets are the
  4th/5th returns. Unpacking the 3rd/4th gives x = relativeToPoint (a
  string), which silently disabled drag adoption (our in-game covers never
  registered a drag). The offline stub now returns all 9 values.

## Spider data (reference specimen)

- Name: "Young Night Web Spider" — level 2 — Tirisfal Glades
- `UnitCreatureID` = **1504**; `UnitCreatureType` = "Beast" (too broad for
  detection); `UnitCreatureFamily` = **("Spider", 3)** ← primary detection
  signal.

## Design consequences (final)

1. Detection: `select(2, UnitCreatureFamily(unit)) == 3` primary; name
   patterns `{"Spider","Gloomweaver"}` + user `extraNames` fallback.
2. No spider world position → no projection → covers are UI-anchored:
   **sticky hover shield** (user requirement: cover *all* spiders, not just
   while-hovered — PLAN.md §3.0), parkable shields, blind mode, frame cover
   (target/focus only — no party-frame globals on this client).
3. Player detection: `UnitClass(unit) ~= nil` (replaces absent
   `IsPlayerUnit`).
4. Lua 5.1: never use `//`, `goto`, `table.pack`, bitwise ops.
5. Slash commands: **classic two-part registration** (proven by the working
   Spoken addon on this client): `_G.SLASH_<GROUP>N = "/cmd"` globals +
   `SlashCmdList["<GROUP>"] = function(msg)` handler (msg = rest of line).
   Neither half alone is enough; there is no `CHAT_COMMAND` event on this
   build.
6. **`UnitCanAttack` is two-arg on this client**: `UnitCanAttack(unit,
   target)` — use `UnitCanAttack("player", unit)` for "hostile to me".
7. **Events are mapped (AS6, 2026-10-13):** present = `UNIT_TARGET`,
   `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `VARIABLES_LOADED`,
   `UNIT_AURA`, `PLAYER_LOGIN`; absent = `MOUSEOVER`, `UPDATE`, `KEY_DOWN`,
   `KEY_UP`, `PARTY_UPDATE`, `RAID_UPDATE`, `CHAT_COMMAND`,
   `ACTIONBAR_BUTTON_UP`. Hover detection must **poll** the `mouseover`
   token; the driver must not rely on `RegisterEvent("UPDATE")` (PLAN.md
   §3.4, AS7 §12.10).
8. Panic hotkey: `KEY_DOWN` absent → mechanism is **`Bindings.xml`**
   (Spoken pattern, listed in our TOC) with modifier-key polling as
   fallback; `/spider hide` is the guaranteed fallback (PLAN.md §4.5).

## M2 in-game verification (2026-10-13)

- `/reload` → no error after removing the `CHAT_COMMAND` registration.
- `/spider` → prints both selftest lines (two-part slash registration
  verified working in-game: `SLASH_SPIDER1 = "/spider"` +
  `SlashCmdList["SPIDER"]`).
- `/run print(ArachnaphobiaShield and ArachnaphobiaShield.version or "NOT LOADED")` → `0.1.0`.
- **M2 complete.** Next: M3 (sticky hover shield + parkable shields, pure
  implementation — every API it needs is verified above).
