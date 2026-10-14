# Spiders Be Gone — Arachnaphobia Addon

**Plan of record for the addon. Read this before writing code.**

- Repo: `SpidersBeGone-ArachnaphobiaAddon`
- Target client: **World of Warcraft Forever** — official, original, classic-based
  (1.x line) client, version **1.60.1**, with new content. No content or APIs from
  WoW 2.x or later exist on this client.
- Working copy: local git clone (machine-local path — e.g.
  `~/Apps/SpidersBeGone-ArachnaphobiaAddon` on the 2026-10-14 machine)
- In-game install path (verified): `.../World of Warcraft/_classic_beta_/Interface/AddOns/`
  (reachable locally via the `~/Apps/wow/AddOns` symlink).

---

## 1. Purpose

**Release context (2026-10-13):** the game is in **beta for ~1 week**;
official out-of-beta release expected **next month**. Aim: v1.0 ready
before/at the public release window.

For players with arachnaphobia: when a spider is the player's target (or otherwise
a "tracked" unit), a **screen-anchored UI element** is projected onto the spider's
3D position every frame and visually covers the model.

Hard constraints:

1. **UI-layer only.** No model swaps, no asset replacement, no file modification of
   game data, no WMO/model edits. Everything is `CreateFrame` + `SetPoint` +
   `SetTexture` on top of the 3D world.
2. **Dynamic.** The cover is re-projected from world coordinates every frame, so it
   tracks the spider, the camera, and perspective (near = big, far = small).
3. **Classic-generation API only.** The code must run on the 1.x UI API (Lua 5.0,
   old-style unit/aura/event APIs). Nothing introduced in 2.x/3.0+ may be used.

## 2. Target environment & API surface

Facts (verified from the local installation):

- Client install: `World of Warcraft/_classic_beta_/Interface/` (Steam/Proton prefix).
- **Confirmed (2026-10-13, in-client error stack + SBG2 run):** modern codebase
  (`Interface/AddOns/Blizzard_ChatFrameBase/...` in the stack) with classic 1.x
  *content* on a **reduced, custom API set** (classic-era functions stripped,
  modern `C_*` infrastructure present). Details in the confirmed lists below.
- The `Spoken_Books.toc` installed on this machine lists
  `## Interface: 11509, 20506, 16001`. **CONFIRMED (2026-10-13):**
  `GetBuildInfo()` returns `1.60.1 / 70374 / Oct 12 2026 / 16001` (four
  **strings** — modern signature); the 4th value is the interface number:
  **`## Interface: 16001`**. The `.toc` is unblocked.
- Addons are `.toc`-style: one folder in `Interface/AddOns/`, one `.toc` whose
  filename equals the folder name and `## Title`, files listed in the `.toc`.
- Addon scripting is **Lua 5.1 (confirmed 2026-10-13):** `_VERSION = "Lua
  5.1"`, `math.huge` present, `table.unpack`/`table.pack` **absent** (5.2+),
  global `unpack` present. Forbidden: `//`, `goto`, `table.pack`, bitwise ops.
  Everything else is standard 5.1.

**Confirmed present (2026-10-13):** `UnitName`, `GetUnitName`, `UnitLevel`,
`UnitIsVisible`, `UnitIsDead`, `UnitCanAttack`, `UnitCreatureType`, `C_Timer`,
`C_Map` (partial), `SlashCmdList`.

**Confirmed absent (2026-10-13):** `WorldFramePoint3D`, `GetUnitPosition`,
`GetUnitFamily`, `IsPlayerUnit`, `GetNumAuras`, `GetUnitAura`, `GetScreenSize`,
`C_Map.PositionToScreen`.

**Wiki cross-check (2026-10-13):** the Warcraft Wiki maintains a per-client API
comparison table (`World of Warcraft API/Classic`, current as of 2026-10-06)
with an explicit **"Forever 1.60.1 (70235) Beta"** column. It confirms several
position/camera/detection APIs exist in Forever that the in-client probes
haven't tested yet: `UnitCreatureFamily` (returns family name + ID, **Spider =
3**; "works on almost all Beasts"), `UnitCreatureID`, `UnitPosition` (works for
player/party/raid only, z=0), `ClosestUnitPosition` (nearest creature by NPC
ID — **starting zones only**), `GetUICameraInfo` (camera pos + lookAt per
camera ID), `GetCameraZoom`, `GetCameraFOVDefaults`, `GetScreenWidth`/
`GetScreenHeight`. **Implication:** in starting zones, spider world position
(`UnitCreatureID` + `ClosestUnitPosition`) plus camera data could support a
**manual world→screen projection** — i.e. the original 3D-follow cover may be
recoverable for early zones. Probe §12.7 decides it.

**Confirmed spider data (Tirisfal Glades):** "Young Night Web Spider", level
2, NPC ID **1504**, `UnitCreatureType` = "Beast" (too broad), **
`UnitCreatureFamily` = ("Spider", 3)** ✓ — family-based detection **works on
wild spiders** (wiki: "works on almost all Beasts"). Primary detection:
`select(2, UnitCreatureFamily(unit)) == 3`; name patterns + `extraNames` as
fallback for units returning no family.

**Design consequence:** no world→screen projection **and** no usable
unit-position API exist on this client → the 3D-follow cover is **infeasible**
here. Pivoted to UI-anchored covers (§3.0).

**SBG4 results (2026-10-13, spider targeted in Tirisfal Glades):**
`UnitCreatureFamily` ✓ ("Spider", 3), `UnitCreatureID` ✓ (1504),
`UnitPosition("player")` ✓ (2070.9, 1694.3, z=0, map=0 — player/party/raid
only), **`ClosestUnitPosition(1504)` → nil in a starting zone** (dead),
`GetCameraZoom` ✓ (30), `GetCameraFOVDefaults` ✓ (90/50/90),
`GetUICameraInfo` present (probe had a syntax error — moot now),
`GetEffectiveScreenInfo` ✓ (1772×1181 at UI scale). **3D path closed.**

**SBG5 results (2026-10-13, warrior in Tirisfal Glades, mouse over a spider):**
`GetCursorPosition` ✓ (206,409), `UnitClass` ✓ ("Warrior"),
`UnitFactionGroup` ✓ ("Horde"), `PlaySoundFile` ✓, `mouseover` token ✓
("Young Night Web Spider", ("Spider",3), visible, `UnitIsDead` tracks death
state), frame globals `TargetFrame` ✓ / `FocusFrame` ✓ / `UIParent` ✓ but
`MouseOverInfoFrame` ✗ / `PartyFrame1` ✗ / `MainMenuBar` ✗. **`CHAT_COMMAND`
is not a registerable event on this client** (RegisterEvent rejects it), and
`SlashCmdList["spider"]` alone did **not** register the command (client
answered the unknown-command fallback "Type /help..."). The working Spoken
addon on this exact client (Spoken_Books/Commands.lua) proved the actual
mechanism — **classic two-part registration**: `_G.SLASH_<GROUP>N = "/cmd"`
globals declare the typed command strings, and `SlashCmdList["<GROUP>"] =
function(msg)` (uppercase group name) is the handler; `msg` is the rest of
the line after the command word. **`Bindings` table absent** (§4.5; SBG6 also killed the `KEY_DOWN`
event route — `Bindings.xml` is the live candidate).
**`UnitCanAttack` is two-arg on this client**: `UnitCanAttack(unit, target)`
(use `UnitCanAttack("player", unit)` for hostile checks).

**SBG6 results (2026-10-13, event availability map)** — run with mouse over a
spider AND the spider targeted (pcall `RegisterEvent`; the client *errors* on
unknown events): **present** = `UNIT_TARGET`, `PLAYER_ENTERING_WORLD`,
`ZONE_CHANGED_NEW_AREA`, `VARIABLES_LOADED`, `UNIT_AURA`, `PLAYER_LOGIN`.
**Absent** = `MOUSEOVER`, `UPDATE`, `KEY_DOWN`, `KEY_UP`, `PARTY_UPDATE`,
`RAID_UPDATE`, `CHAT_COMMAND`, `ACTIONBAR_BUTTON_UP`. Consequences: hover
detection must **poll** the `mouseover` token each tick; the panic hotkey
cannot use `KEY_DOWN` (§4.5); the driver must not rely on
`RegisterEvent("UPDATE")` (§3.4, SBG7 §12.10).

**M2 in-game verified (2026-10-13):** clean `/reload`; `/spider` prints both
selftest lines (two-part Spoken-style registration works); `/run` load-check
returns `0.1.0`.

APIs the plan relies on (**confirmed** 2026-10-13 unless noted):

| API | Use | Status |
|---|---|---|
| `UnitName` / `GetUnitName` (both present) | identity, name-based detection | ✓ |
| `UnitLevel` | label, size heuristic | ✓ |
| `UnitIsVisible`, `UnitIsDead`, `UnitCanAttack(unit, target)` (two-arg!) | tracking/detection guards | ✓ |
| `UnitCreatureType` | sanity only (spiders report **"Beast"**) | ✓ |
| `C_Timer` | timers | ✓ |
| `SLASH_<GROUP>N` globals + `SlashCmdList["<GROUP>"]` handler (two-part, Spoken-verified) | slash commands | ✓ |
| `GetBuildInfo()` → 4 **strings** (4th = interface no.) | interface check | ✓ |
| `GetCursorPosition` | hover-shield anchor | ✓ (SBG5) |
| `GetEffectiveScreenInfo` | screen size (replaces absent `GetScreenSize`) | ✓ (SBG4) |
| `UnitClass` / `UnitFactionGroup` | "is a player?" (replaces absent `IsPlayerUnit`) | ✓ (SBG5) |
| `CreateFrame`, `SetPoint`, `SetSize`, `SetTexture`, `SetFrameStrata`, `SetClampRect`, `CheckBox`, `Slider`, `EditBox`, `SetBackdrop`, `PlaySoundFile` | UI | assumed ✓, spot-check §12.6 |
| `SavedVariables` in `.toc` | persistence | ✓ |

**API-generation status: CONFIRMED — modern client, reduced API set**
(2026-10-13). `C_Timer`, `C_Map` (partial), `SlashCmdList` are present and
**preferred**; classic `SLASH_` variables are not needed. Unit-enumeration APIs
do not exist in any WoW generation — tracking stays token-based (§3.1).

> **M1 gate: CLEARED (2026-10-13).** `## Interface: 16001` confirmed via
> `GetBuildInfo()`'s 4th return value. `.toc` unblocked.

### Unit-token limitation (design-defining)

No WoW API generation can enumerate arbitrary on-screen creatures. We can only
query units we hold a **unit token** for. Tokens tracked (spot-check §12.6):

`player, pet, focus, target, targettarget, partyleader, party1-4, raid1-20,
arena1-4, mouseover`

Therefore the addon covers spiders among: **target, targettarget, focus, pet,
party1-4, raid1-20, mouseover** (each group individually toggleable). This is the
single biggest functional constraint and it is accepted: the arachnophobe pain
points are "I am fighting this spider" and "I am hovering over that spider" —
both covered.

## 3. How it works (architecture)

```
            ┌─────────────── Core.lua (orchestration) ───────────────┐
            │  init, lifecycle, driver frame OnUpdate, debug ring    │
            └──────┬──────────────┬───────────────┬──────────────────┘
                   │              │               │
            ┌──────▼─────┐ ┌──────▼─────┐ ┌───────▼──────┐
            │  Units.lua │ │ Project.lua│ │  Cover.lua   │
            │ tracked    │ │ world→     │ │ frame pool,  │
            │ unit list +│ │ screen     │ │ per-unit     │
            │ spider     │ │ (pure fns) │ │ cover frames │
            │ predicate  │ │            │ │ + label      │
            └────────────┘ └────────────┘ └──────────────┘
            ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
            │  Config.lua  │ │  UI.lua      │ │  Slash.lua   │
            │ settings     │ │ config       │ │ /spider      │
            │ schema, load │ │ window       │ │ parser       │
            │ + migrate    │ │ (vanilla    │ │              │
            │ + validate   │ │ widgets)    │ │              │
            └──────────────┘ └──────────────┘ └──────────────┘
```

### 3.0 Pivot (2026-10-13): UI-anchored covers, not 3D-follow

M1 probes proved this client has **no** world→screen API (`WorldFramePoint3D`
and `C_Map.PositionToScreen` both absent) and **no** unit-position API
(`GetUnitPosition` absent), so a shield that tracks a spider's 3D position is
**infeasible on this build**. The pivot keeps the owner's hard constraint
(UI-layer only, no model swaps) and covers what the API *can* see:

- **Sticky hover shield (auto — owner requirement: cover *all* spiders, not
  just while-hovered, 2026-10-13):** while `mouseover` resolves to a spider,
  a cover disc renders at the **cursor**; when the mouse leaves, the cover
  **sticks** at that screen position (`settings.stickyCovers`, default **on**)
  until cleared — sweep the mouse across the screen and every spider you
  point at is covered and *stays* covered. Stuck covers join the shared 24-slot
  frame pool (FIFO: a new one evicts the oldest when full). `stickyCovers =
  off` restores while-hovered-only behavior. `/spider clear` and the panic
  key remove all.
- **Frame cover (auto):** when `target`/`focus` is a spider, a tinted plate
  covers that unit frame (`TargetFrame`/`FocusFrame` — both exist; **target
  and focus only**: SBG5 found no `PartyFrame1`/`MainMenuBar` globals on this
  client, so party-frame covers are out of scope) — hides the spider's
  name/health UI.
- **Parkable shields (manual):** up to 8 pre-parked, **draggable** cover discs
  parented to `UIParent` — drag one over a spider, or pre-park them; positions
  persist per character (SavedVariables); panic key / `/spider clear` hides
  all (§4.5). Parkable shields and stuck hover covers share the 24-slot pool.
- **Blind mode (auto/manual):** one large soft cover over the center of the
  screen — "I don't want to see the middle of my screen right now"; toggled
  by slash and/or the panic hotkey.

**Detection (final):** `select(2, UnitCreatureFamily(unit)) == 3` ("Spider")
as the primary signal — **confirmed working on a wild spider** (SBG4). Fallback
name patterns `{"Spider", "Gloomweaver"}` + user `extraNames` for units that
return no family (wiki: family "does not work on all creatures").

**~~Option 0 — 3D hybrid~~ CLOSED (2026-10-13):** `ClosestUnitPosition`
returned nil for NPC 1504 while standing in Tirisfal Glades (a starting zone)
— the "starting zones only" gate rejects it where spiders actually live. No
other API yields a target spider's world position, so 3D-follow is out. If a
future build fixes/extends it, Project.lua keeps a seam for re-activation.

**Owner decision pending (open Q5):** which combination ships in v1.0
(recommendation: hover shield + parkable shields + blind mode + panic hotkey;
frame cover is a cheap extra).

### 3.1 Tracking (Units.lua)

- The **tracked set** = union of enabled groups → list of unit tokens (≤ 24).
- **Spider predicate** (single, DRY, used for every unit):

  1. `UnitClass(unit) ~= nil` → false (never cover players — `IsPlayerUnit`
     is absent; `UnitClass`/`UnitFactionGroup` confirmed in the wiki table,
     in-client probe §12.8);
  2. `select(2, UnitCreatureFamily(unit)) == 3` — "Spider" family;
     **confirmed working on a wild spider** (SBG4: "Spider", id 3);
  3. OR `UnitName(unit)` matches `settings.namePatterns`
     (default `{"Spider", "Gloomweaver"}`) or is in `settings.extraNames`
     — fallback for units returning no family / new content;
  4. level window `settings.minLevel..settings.maxLevel`;
  5. if `settings.requireHostile` and **not** `UnitCanAttack("player", unit)`
     → false. (Two-arg form: `UnitCanAttack(unit, target)` — confirmed by
     SBG5's usage error.)

- Tracked list is rebuilt on events (`UNIT_TARGET`, `UNIT_PET`, `PARTY_UPDATE`,
  `RAID_UPDATE`, `PLAYER_ENTERING_WORLD`), not per frame.

### 3.2 Projection (Project.lua) — **CLOSED on this build, seam kept** (SBG4)

> **Status (2026-10-13):** the APIs this section assumed (`GetUnitPosition`,
> `WorldFramePoint3D`) are absent, and `ClosestUnitPosition` (the only
> candidate position source) returned nil in a starting zone (§2, SBG4).
> The math below is kept as the **re-activation seam**: if a future client
> build exposes a unit-position + camera API, Project.lua implements exactly
> this. v1.0 anchors are UI-space only (§3.0).

For a unit at world position `(wx, wy, wz)` (foot anchor, from whichever
position API a future build provides):

1. `sx, sy, behind = WorldFramePoint3D(wx, wy, wz)` — foot in screen space
   (UIParent coordinates, origin bottom-left).
2. `sx2, sy2, behind2 = WorldFramePoint3D(wx, wy, wz + h)` — estimated model top,
   where `h` ≈ `max(settings.minModelHeight, UnitLevel(unit) * 0.12)` (classic
   spiders scale with level; tunable).
3. If both in front: apparent height `H = max(1, sy2 - sy)`; frame size
   `S = clamp(H * settings.sizeScale, settings.minSize, settings.maxSize)`;
   anchor = midpoint `(sx+sx2)/2, (sy+sy2)/2` plus `yOffset * H`.
4. If top is behind/nil: fall back to `S = clamp(settings.fallbackK / dist,
   minSize, maxSize)` with `dist` from player↔unit positions.
5. Hide if `behind` (foot), positions nil, `UnitIsVisible` false, or
   (`UnitIsDead` and not `settings.coverCorpses`).

This two-point projection gives correct perspective scaling for free.

### 3.3 Cover rendering (Cover.lua)

- **Frame pool**: N frames (N = max tracked units = 24) pre-created at load —
  zero allocation in the per-frame loop. Each cover = Frame + child Texture —
  art: the generated `cover.tga` (soft tintable squircle patch, 64×64 32-bit),
  tinted to the user's color via `SetTexture(path, r, g, b)`; falls back to a
  solid `SetTexture(r, g, b, a)` if the TGA is missing — plus an optional
  `GameFontHighlightSmall` name label above it.
- Strata: `HIGH` (above MEDIUM default UI, below DIALOG; the 3D world is always
  behind all UI strata, so any stratum covers the model — HIGH chosen so the
  shield sits over action bars etc.). Frame level within stratum by distance
  (nearer = drawn last) so covers don't clip each other badly.
- Per frame, per tracked spider: `SetPoint("CENTER", UIParent, "BOTTOMLEFT",
  cx, cy)` + `SetSize(S, S)` (v1 square; v1.1 candidate: 2:1 wide rect, spiders
  are flat). Skip the `SetPoint`/`SetSize` calls if values changed by < 1px
  (epsilon cache) — avoids useless layout work.
- One **driver frame** owns the single `OnUpdate`; individual covers have no
  timers.

### 3.4 Lifecycle

- Modern codebase (confirmed): all `.lua` files run at client load
  (character-select time). Initialize structures at file load, arm the driver
  on `PLAYER_ENTERING_WORLD`, reset all covers on logout events.
- **Events are mapped (SBG6, 2026-10-13).** Present: `UNIT_TARGET`,
  `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `VARIABLES_LOADED`,
  `UNIT_AURA`, `PLAYER_LOGIN`. Absent: `MOUSEOVER`, `UPDATE`, `KEY_DOWN`,
  `KEY_UP`, `PARTY_UPDATE`, `RAID_UPDATE`, `CHAT_COMMAND`,
  `ACTIONBAR_BUTTON_UP`. **`RegisterEvent` *errors* on unknown events** —
  every registration must come from the present list (or be pcall-guarded).
  Classic-only event names (e.g. `UPDATE_AURAS`) are **not** used.
- **Driver (tick loop):** `OnUpdate` script on one driver frame if SBG7
  (§12.10) confirms it (expected — the script system is separate from the
  pruned event system); otherwise a `C_Timer.After(0.1, tick)`
  self-rescheduling loop (C_Timer confirmed present). Either way the same
  tick function re-scans the tracked token list at ~10 Hz (5 cheap calls per
  token, trivial cost) and re-places covers. Registered events are pure
  optimizations on top (e.g. `UNIT_TARGET` to refresh the tracked set sooner).
- Guarded init (idempotent), `settings.enabled` gate checked per frame (cheap).
- `/reload` safe: everything rebuilds from `SavedVariables` + defaults.

## 4. What the addon must contain (file inventory)

Repo layout (the `SpidersBeGone/` folder is the installable addon):

```
SpidersBeGone-ArachnaphobiaAddon/
├── README.md                  install + usage + config reference
├── LICENSE                    MIT
├── .gitignore
├── docs/
│   ├── PLAN.md                this file
│   └── art/                   PNG previews of the generated art
├── tools/
│   └── make_art.py            regenerates all art (stdlib only) → re-run anytime
└── SpidersBeGone/             ← copy this folder to Interface/AddOns/
    ├── SpidersBeGone.toc      Interface (TBD M1), Title "Spiders Be Gone",
    │                          Notes, Version, Author, IconTexture,
    │                          SavedVariables: SBeGoneSettings
    ├── icon.tga               original 32x32 "no spider" icon (generated)
    ├── cover.tga              original 64x64 tintable cover patch (generated)
    ├── Core.lua               init/lifecycle/driver/debug ring buffer
    ├── Units.lua              tracked tokens + spider predicate
    ├── Project.lua            world→screen (pure functions)
    ├── Cover.lua              frame pool + per-frame placement
    ├── Config.lua             defaults, schema validation, load/migrate/save
    ├── UI.lua                 config window (vanilla widgets)
    ├── Slash.lua              /spider parser (SLASH_ + CHAT_COMMAND)
    └── Locales.lua            enUS strings (i18n stub for later)
```

### 4.1 Settings (`SBeGoneSettings`, versioned)

```lua
{
  version = 1,
  enabled = true,
  color = { r=0.55, g=0.12, b=0.12 },  opacity = 0.85,
  sizeScale = 1.0,   minSize = 8,      maxSize = 800,
  yOffset = 0.0,     minModelHeight = 1.0, fallbackK = 600,
  coverCorpses = true,
  showName = false,
  track = { target=true, targettarget=true, focus=true, pet=true,
            party=true, raid=true, mouseover=true },
  families = { ["Spider"]=true },
  extraNames = {},
  requireHostile = false, minLevel = 1, maxLevel = 99,
  minimapButton = true,
  debug = false,
}
```

- Load: `loadstring("return " .. tostring(SBeGoneSettings))`-style deep copy is
  **not** used — plain table traversal with per-key type checks; unknown/missing
  → default; corrupt → full reset + chat message. (No `loadstring` of untrusted
  data at all.)
- All UI inputs clamped to their legal ranges on write (auditability).

### 4.2 Config window (UI.lua)

Draggable ~500x480 `Frame`, `SetBackdrop`, vanilla widgets only:
Enable checkbox; cover color (R/G/B 0-255 edit boxes or 3 sliders) + opacity
slider; size / min / max sliders; offset slider; corpse + name-label checkboxes;
track-group checkboxes; hostile-only checkbox; level range edit boxes;
`Reset defaults` / `Close` buttons. Changes autosave (idempotent `Config.Save`),
take effect next frame.

### 4.3 Slash command

`/spider` (alias `/spidergone`) — **two-part registration (confirmed
working in-game 2026-10-13; there is no `CHAT_COMMAND` event on this
client)**: `_G.SLASH_SPIDER1 = "/spider"`, `_G.SLASH_SPIDER2 =
"/spidergone"`, `SlashCmdList["SPIDER"] = function(msg) … end` (msg = rest
of line, may be nil). Pattern taken from the Spoken addon, which works on
this client.

| cmd | effect |
|---|---|
| `on` / `off` / `toggle` | enable/disable |
| `reset` | reset settings to defaults |
| `debug` | toggle debug ring buffer |
| `hide` / `show` | temporary full hide (panic button) |
| `selftest` | print GetBuildInfo, API probes, unit-position samples |
| `help` | usage |

### 4.4 Minimap button (v1.1, optional)

32x32 button parented to `Minimap`, toggles the config window; reposition on
`MINIMAP_UPDATE_ZOOM` (verify event exists on this build; else OnUpdate poll of
`Minimap` width). Kept out of v1.0 scope.

### 4.5 Panic hotkey (v1.1 candidate — owner decision pending)

A keybind that instantly hides **all** covers (press again to restore), no chat
needed — for when a cover occludes something the player must see.

**Mechanism (final order, SBG6 2026-10-13 — `KEY_DOWN` is absent, so the
event route is dead):** the Lua `Bindings` table is **absent** on this
client; keybindings are XML (`<Bindings>` files — Spoken ships a
`Bindings.xml` with `<Binding name="..." header="...">LuaExpression()</Binding>`
entries, though notably it is *not* listed in its TOC, so its loading is
itself unverified). In order:
1. **`Bindings.xml`** (Spoken pattern, properly listed in our TOC): a named
   binding (e.g. `SBG_HIDE_COVERS`, header "SPIDERS BE GONE", default key
   **F12**) calling a global `SBeGoneBindingCommand()` that toggles a
   session-level `hidden` flag (driver skips all placement while set).
   Verification step: our file must actually load — check the client's
   key-binding UI for the "SPIDERS BE GONE" header (Spoken's own unlisted
   file may never have loaded either).
2. If (1) doesn't load: modifier-key polling in the driver tick (crude but
   dependency-free).
3. `/spider hide` (slash) — always available, guaranteed fallback.
State resets on reload, so it can never leave the player permanently hidden.

## 5. Performance budget (details in §8 PAWS)

- Per frame: one `OnUpdate`; ≤ 24 tokens; per visible spider ≤ 2
  `WorldFramePoint3D` calls + ≤ 2 layout calls (usually 0 thanks to epsilon
  cache). No allocations in the loop (pool + preallocated scratch numbers).
- Memory: fixed (24 cover frames + textures + one 200-entry debug ring).
- Worst case (all 24 tokens are visible spiders, camera spinning): still a few
  hundred simple Lua ops/frame — negligible on the classic client.

## 6. Milestones

| # | Deliverable | Exit criteria | Status |
|---|---|---|---|
| M0 | Repo + this plan | committed, pushed | ✅ done |
| M1 | In-game API verification (probe rounds SBG1–SBG4, §12) | `docs/API-VERIFICATION.md` written from real sessions | ✅ done (2026-10-13) |
| M2 | TOC + load skeleton: `SpidersBeGone.toc` (interface 16001), `Core.lua`, SavedVariables, `/spider` selftest, generated icon | addon loads, appears in AddOns list, `/spider` prints build info, `/run` load-check works | ✅ done (2026-10-13: clean `/reload`, `/spider` prints both selftest lines, `/run` load-check = 0.1.0) |
| M3 | **Hover shield** (auto: cursor-anchored cover while mouseover is a spider) + **parkable shields** (manual draggable covers, positions saved) | hovering a Tirisfal spider hides its model; shields persist across `/reload` and logout | code done 2026-10-14 (offline suite green); pending in-game verification |
| M4 | **Blind mode** + **panic hotkey** (§4.5) + **frame cover** for target/focus (optional) | panic key instantly hides all covers; frame cover tracks the target frame | — |
| M5 | Config window (color, opacity, size, extraNames, enable toggles) + SavedVariables polish (migrate/reset/validation) | settings survive logout/reload; corrupt SV self-heals | — |
| M6 | README, polish, `v1.0.0` tag | install-from-clone instructions verified end-to-end on the Proton client | — |

Post-v1 candidates (roadmap, not planned work): 2:1 wide cover, re-activating
3D-follow if a future client build exposes unit positions + camera data
(Project.lua seam, §3.2), other creature families, per-character settings,
i18n locales, minimap button, panic hotkey default binding.

## 7. Testing & verification plan

No automated test runner exists for 1.x addons; verification is:

1. **`/spider selftest`** (in M2): prints `GetBuildInfo()`, nil-checks for
   `WorldFramePoint3D`, `GetUnitFamily`, `UnitCreatureType`, a sample
   `GetUnitPosition("player")`, and the resolved tracked-token list.
2. **Manual matrix** (M3/M4), in-game on the Proton client:
   - target a small spider (Elwynn ~5) and a large one (later zone); cover
     tracks during camera rotation and movement; size scales with distance;
   - death: cover persists on corpse (default) / hides with setting off;
   - out-of-range / behind camera: cover hidden, no error spam;
   - `/spider hide` then `show`; `/spider reset`; logout/relogin persistence;
   - UI scale change (Ctrl+` in 1.x): cover reprojects correctly next frame.
3. **Debug ring buffer** (`/spider debug`): every hide reason and projection
   failure is logged with unit token + reason string (auditability).
4. Install test: copy `SpidersBeGone/` → `~/Apps/wow/AddOns/`, character
   select, confirm enabled with no red errors in `/run print(GetError())`
   pattern (classic: check no Lua errors on login via chat `SCRIPT ERROR`).

## 8. PAWS standard review (per AGENTS.md)

Context: single-player, client-side, visual-only WoW classic addon; "agent" =
this planning/implementation agent. Confidence: High/Medium/Low.

### P — Performance (Big O, bottlenecks, memory/time)

- Per-frame cost **O(T)**, T = tracked tokens (≤ 24, fixed bound). Per visible
  spider: O(1) lookups + ≤ 2 projection calls + ≤ 2 layout calls. No per-frame
  table/string allocation (pool + scalar scratch; epsilon cache skips layout).
- Bottleneck: `WorldFramePoint3D` (view/projection math). Worst realistic case
  ≈ 48 calls/frame — negligible; classic clients run far heavier UIs.
- Memory: fixed pool (24 frames + textures), 200-entry debug ring, tiny SV
  table. Zero growth over session.
- Risks: (a) nil-position or nil-behind misuse → guarded, logged; (b) layout
  thrash from sub-pixel jitter → epsilon cache.
- Confidence: **High**.
- Path to improvement: event-driven dirty flag (skip projection entirely when
  camera + all units are static) if M3 profiling ever shows need — not planned.

### A — Auditability (input validation, least privilege, traceable errors)

- Inputs: SV load validates every key (type + range), resets corrupt data with
  a visible message; config widgets clamp on write; slash parser is a strict
  lookup (unknown → help line, never `loadstring`/`load` of user input).
- Least privilege: pure UI. No protected frames, no macros, no CLEAVE, no file
  I/O, no network, no `Secure` interaction. Nothing the game doesn't already
  render to us.
- Traceability: debug ring buffer (unit token, reason, timestamp via
  `GetTime()`); `/spider selftest` for environment; every failure path produces
  an actionable chat line, never a silent no-op.
- Risks: API availability on the 1.60.1 build unconfirmed until M1 (this is
  the main audit gap in the plan). Mitigation: M1 gate + selftest + name-list
  fallback so detection degrades gracefully.
- Confidence: **High** for design; **Medium** for API availability until M1.
- Path to improvement: numeric error codes in the ring buffer; optional
  "print ring" slash subcommand for reports.

### W — Workability (edge cases, idempotency, thread safety)

- Idempotency: guarded init; `Config.Save`/`Load` safe to call any time; driver
  frame created once (nil-check before create); `/reload` fully rebuilds state.
- Edge cases covered: foot behind camera (hide); top behind camera (fallback
  sizing); distance ≈ 0 (clamp); nil positions (hide, no error); dead unit
  (corpse setting); target/focus cleared (event rebuild); player death (covers
  persist — harmless); zone change (positions go nil → hide); UI rescale
  (reprojection next frame); borderless window (UIParent coords still valid);
  4:3/16:9 (projection is aspect-aware by construction).
- Thread safety: single-threaded Lua; all mutation inside event/OnUpdate
  callbacks; no re-entrancy (no event fired from our own handlers).
- Risks: stale corpse positions (accepted: covering a corpse is the point);
  `GetUnitFamily` returning localized strings on non-enUS locale (mitigation:
  also match via `extraNames`; v1 is enUS anyway).
- Confidence: **High**.
- Path to improvement: panic hotkey via `Bindings.xml`; "idle pause" (stop
  OnUpdate when no tracked spider visible for N seconds).

### S — Scalability (modularity, DRY, separation of concerns)

- Modules have one responsibility each; `Project` is pure (trivially
  re-testable); the spider predicate is a single function shared by every
  tracked group (DRY); detection is data-driven (`families`/`extraNames`) so
  "support a new spider type" is a data edit, not code; cover visuals isolated
  in `Cover` (swap solid→art texture later without touching projection).
- Anti-goal honored: no speculative frameworks — 9 small files, no Libs, no
  embedded third-party code (zero dependency surface).
- Risks: slight over-modularization for a single-user addon; kept in check by
  the file inventory in §4 (each file has a clear, non-overlapping role).
- Confidence: **High**.
- Path to improvement: if multi-family support lands, promote the predicate to
  a rule list; per-character SV if needed.

### Adherence to original intent

Intent: "cover up spider models in-game, by using a dynamic UI element … no
model swaps." Plan is 100% UI-layer: no game-file or model modification of any
kind; covers are recomputed from live world coordinates every frame (dynamic);
spiders are detected by game APIs + user data. **Fully adherent.** The only
intent-adjacent compromise is the unit-token limitation (§2): spiders you never
target/focus/mouseover are not covered — an API boundary of the 1.x client,
documented, accepted, and mitigated where it hurts most (your target +
mouseover).

## 9. Risks & mitigations (consolidated)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | ~~Wrong `## Interface:` number~~ **RESOLVED**: 16001 confirmed (2026-10-13) | — | — | `GetBuildInfo()` 4th value; Spoken TOC cross-check |
| 2 | ~~No world→screen projection~~ **CONFIRMED ABSENT** (`WorldFramePoint3D`, `C_Map.PositionToScreen`, `GetUnitPosition`) | — | Partially mitigated | Wiki shows Forever has `ClosestUnitPosition` (starting zones) + `GetUICameraInfo`/`GetCameraZoom` → **manual projection** path, probe §12.7; UI-anchored covers remain the guaranteed fallback (§3.0) |
| 3 | ~~Manual projection math/calibration~~ **CLOSED (2026-10-13)**: `ClosestUnitPosition` → nil in starting zone (Tirisfal); no spider position obtainable | — | — | UI-anchored design is final; Project.lua seam kept for a future client that exposes spider positions |
| 4 | ~~`GetUnitFamily` absent~~ **CONFIRMED ABSENT**; `UnitCreatureType`="Beast" too broad | — | Resolved better | **`UnitCreatureFamily` confirmed working** ("Spider", id 3, SBG4) — primary detection; name patterns + `extraNames` as fallback (§3.0) |
| 5 | Cover undersized for large/flat spiders | Medium | Medium | sizeScale/minSize/maxSize/yOffset tuning; v1.1 wide rect + height table |
| 6 | Can't cover non-token spiders (API boundary) | Certain | Medium | Documented limitation; target+mouseover cover the real pain points |
| 7 | Proton/Wine path quirks | Low | Low | Standard folder copy into `Interface/AddOns/` (symlinked); test at M2 |
| 8 | ~~"New content" spiders with unknown family strings~~ | — | Resolved | Name-based: `/spider add <name>`, selftest prints target **name** for discovery |
| 9 | Name-based detection misses spiders without a matching name pattern | Medium | Medium | Defaults include "Spider"+"Gloomweaver"; user `extraNames`; config window shows tracked spider list; document how to add names |
| 10 | Beta client API surface may still shift before out-of-beta release | Medium | Medium | All API use goes through a thin compat layer (Compat.lua) so one API swap = one-line change; re-run §12 probes on the release client; wiki comparison table (per-client columns) is the reference |
| 11 | `ClosestUnitPosition` returns the nearest mob of that NPC ID, not necessarily the targeted one (same-species duplicates) | Medium | Low | Acceptable for a visual aid (targeted spider is almost always the nearest when engaged); document; detection stays on the tracked unit's own data |

## 10. Open questions

1. ~~Repo visibility~~ — resolved: **public**.
2. ~~Cover appearance~~ — resolved: original generated art (`cover.tga`, tintable
   soft patch; generator `tools/make_art.py`), tinted by the user's color/opacity.
3. ~~Icon~~ — resolved: original generated 32x32 "no spider" icon (`icon.tga`).
4. Panic hotkey — owner decision pending (mechanism documented in §4.5;
   SBG6 killed the `KEY_DOWN` route — `Bindings.xml` is the live candidate).
5. **Pivot feature set (2026-10-13, §3.0):** 3D-follow is infeasible on this
   client (SBG4 closed the 3D path). Owner requirement recorded 2026-10-13:
   **cover ALL spiders** — covers must persist, not just last while hovered
   (→ sticky hover shield, `stickyCovers` default on). v1.0 scope: sticky
   hover shield + parkable shields + blind mode + `/spider clear`; frame
   cover optional; panic hotkey TBD. **Defaulting to this unless owner
   objects.**

## 11. Conventions

- Lua 5.0-compatible (see §2). No global pollution: all state under one `local SBeGone = {}`
  namespace table (plus the SV table); files attach to it. **Sanctioned extra
  globals** (framework conventions, mirroring the working Spoken addon):
  `SLASH_SPIDER1`/`SLASH_SPIDER2` (slash command registration) and the
  binding command function if the panic key lands (§4.5).
- No per-frame string concatenation outside debug mode.
- Comments: `--` only, short; each file starts with a one-line purpose comment.
- Git: `main` branch, conventional-ish lowercase commit messages, tag `v1.0.0`
  at M6. Addon folder name == TOC file name == `SpidersBeGone`.

## 12. M1 in-client verification scripts

Run in-game, in character (chat box). All output is prefixed `SBG|`. The single
line reports every plan assumption; the individual lines are the same probes for
readability.

### 12.1 One-shot report (one line, paste after the chat input)

```
/run local function p(k,v) print(("SBG| %s: %s"):format(k, tostring(v))) end; local a,b,c,d = GetBuildInfo(); p("buildInfo", string.format("major=%s minor=%s patch=%s build=%s", tostring(a), tostring(b), tostring(c), tostring(d))); p("lua50_marker", select(2, _G)); p("_VERSION", _VERSION); p("unpack_global", unpack ~= nil); p("table.unpack", rawget(table, "unpack") ~= nil); p("table.pack", rawget(table, "pack") ~= nil); p("math.huge", math.huge ~= nil); p("WorldFramePoint3D", WorldFramePoint3D ~= nil); p("GetUnitFamily", GetUnitFamily ~= nil); p("UnitCreatureType", UnitCreatureType ~= nil); p("GetUnitPosition", GetUnitPosition ~= nil); p("GetNumAuras_returns", GetNumAuras and select("#", GetNumAuras("player")) or "n/a"); p("screen", (function() local w,h,s = GetScreenSize(); return string.format("%sx%s scale=%s", w, h, tostring(s)) end)()); p("locale", GetLocale()); p("zone", GetZoneText()); p("Minimap", Minimap ~= nil); p("GameFontHighlightSmall", GameFontHighlightSmall ~= nil); p("SetBackdrop", SetBackdrop ~= nil); p("core_unit_apis", (UnitIsVisible and UnitIsDead and UnitCanAttack and UnitLevel and UnitName and IsPlayerUnit and GetUnitAura and "all_present") or "SOME_MISSING"); local px,py,pz = GetUnitPosition("player"); p("playerPos", string.format("%.1f %.1f %.1f", px, py, pz)); if WorldFramePoint3D then local sx,sy,beh = WorldFramePoint3D(px,py,pz); p("projPlayerScreen", string.format("x=%s y=%s behind=%s", tostring(sx), tostring(sy), tostring(beh))) end
```

### 12.2 Individual probes

```lua
/run print("SBG lua: 5.0marker=" .. tostring(select(2, _G)) .. " _VERSION=" .. tostring(_VERSION) .. " table.unpack=" .. tostring(rawget(table, "unpack") ~= nil) .. " table.pack=" .. tostring(rawget(table, "pack") ~= nil) .. " math.huge=" .. tostring(math.huge ~= nil))
```

```lua
/run local a,b,c,d = GetBuildInfo(); print("SBG buildInfo: major=" .. tostring(a) .. " minor=" .. tostring(b) .. " patch=" .. tostring(c) .. " build=" .. tostring(d))
```

```lua
/run print("SBG WorldFramePoint3D=" .. tostring(WorldFramePoint3D ~= nil) .. " GetUnitPosition=" .. tostring(GetUnitPosition ~= nil) .. " GetUnitFamily=" .. tostring(GetUnitFamily ~= nil) .. " UnitCreatureType=" .. tostring(UnitCreatureType ~= nil))
```

```lua
/run local px,py,pz = GetUnitPosition("player"); print("SBG playerPos:", px, py, pz); local sx,sy,beh = WorldFramePoint3D(px,py,pz); print("SBG proj:", sx, sy, beh)
```

```lua
/run print("SBG GetNumAuras(player) returns:", select("#", GetNumAuras("player")), "values")
```

```lua
/run local w,h,s = GetScreenSize(); print("SBG screen:", w, "x", h, "scale", s, "locale:", GetLocale(), "zone:", GetZoneText())
```

### 12.3 Spider probe (target a spider first, ideally a small + a large one)

```lua
/run local n = UnitName("target"); print("SBG target: name=" .. tostring(n) .. " family=" .. tostring(GetUnitFamily("target")) .. " creatureType=" .. tostring(UnitCreatureType("target")) .. " level=" .. tostring(UnitLevel("target")))
```

### 12.4 Interpretation

| Output | Confirms |
|---|---|
| `lua50_marker` = `Lua 5.0` | Lua 5.0 as assumed |
| marker nil + `_VERSION` set | newer Lua (5.1+); 5.0-compatible code still valid |
| `buildInfo` major/minor/patch | the exact `## Interface:` number (classic mapping major·10000 + minor·100 + patch) |
| `WorldFramePoint3D = true` | core feasibility (risk #2 cleared) |
| `GetNumAuras_returns = 2` | classic-era aura API shape (`1` = modern shape) |
| `projPlayerScreen` x/y numbers, `behind=false` | world→screen projection works in this client |
| spider probe `family=` value | the exact family string(s) for `settings.families` (risk #7) |

### 12.5 Hardened probes (SBG2, nil-safe) — supersedes 12.1–12.3

First in-client run (2026-10-13): the spider probe died with
`attempt to call a nil value` — one of `UnitName`/`GetUnitFamily`/
`UnitCreatureType`/`UnitLevel` is **absent** on this client — and the error
stack revealed the modern codebase (see §2 finding). The SBG2 probes are
nil-safe (missing → `MISSING` / `API_MISSING`) and add modern-generation
checks (`C_Timer`, `C_Map.PositionToScreen`, `SlashCmdList`).

**Client constraint (2026-10-13):** chat `/run` is capped at **255 chars
including `/run`**. Use the split lines below (each ≤ 223 chars, measured).
Line A1 defines a persistent helper — re-run it after any `/reload`.
Cleanup when done: `/run SBG2=nil`.

**Part A — environment (run A1 first, then A2–A12 in any order):**

```
/run SBG2={p=function(k,v) print(("SBG2| %s: %s"):format(k,tostring(v))) end}
/run local p=SBG2.p; p("lua50",select(2,_G)); p("_VERSION",_VERSION); p("t.unpack",rawget(table,"unpack")~=nil); p("t.pack",rawget(table,"pack")~=nil); p("math.huge",math.huge~=nil)
/run local p=SBG2.p; p("WorldFramePoint3D",WorldFramePoint3D~=nil); p("GetUnitPosition",GetUnitPosition~=nil); p("GetUnitFamily",GetUnitFamily~=nil); p("UnitCreatureType",UnitCreatureType~=nil)
/run local p=SBG2.p; p("UnitName",UnitName~=nil); p("GetUnitName",GetUnitName~=nil); p("UnitLevel",UnitLevel~=nil); p("UnitIsVisible",UnitIsVisible~=nil); p("UnitIsDead",UnitIsDead~=nil)
/run local p=SBG2.p; p("UnitCanAttack",UnitCanAttack~=nil); p("IsPlayerUnit",IsPlayerUnit~=nil); p("GetNumAuras",GetNumAuras~=nil); p("GetUnitAura",GetUnitAura~=nil); p("GetScreenSize",GetScreenSize~=nil)
/run local p=SBG2.p; p("C_Timer",C_Timer~=nil); p("C_Map",C_Map~=nil); p("C_Map.PosToScreen",C_Map and type(rawget(C_Map,"PositionToScreen"))=="function" or false); p("SlashCmdList",SlashCmdList~=nil)
/run local p=SBG2.p; local a,b,c,d=GetBuildInfo(); p("buildInfo",string.format("major=%s minor=%s patch=%s build=%s",tostring(a),tostring(b),tostring(c),tostring(d)))
/run local p=SBG2.p; if GetScreenSize then local w,h,s=GetScreenSize(); p("screen",w.."x"..h.." scale="..tostring(s)) end; p("locale",GetLocale()); p("zone",GetZoneText())
/run local p=SBG2.p; local px,py,pz=GetUnitPosition("player"); p("playerPos",string.format("%.1f %.1f %.1f",px,py,pz))
/run local p=SBG2.p; if WorldFramePoint3D then local px,py,pz=GetUnitPosition("player"); local sx,sy,beh=WorldFramePoint3D(px,py,pz); p("proj_player",sx.." "..sy.." "..tostring(beh)) end
/run local p=SBG2.p; if C_Map and C_Map.PositionToScreen then local px,py,pz=GetUnitPosition("player"); local cx,cy,cb=C_Map.PositionToScreen(px,py,pz); p("proj_CMap",cx.." "..cy.." "..tostring(cb)) end
/run local p=SBG2.p; if GetNumAuras then p("numAuras_vals",select("#",GetNumAuras("player"))) else p("numAuras_vals","API_MISSING") end
```

**Part B — spider probe (3 lines; target a spider first, ideally a small + a large one):**

```
/run local p=SBG2.p; local n; if UnitName then n=UnitName("target") elseif GetUnitName then n=GetUnitName("target") end; p("name",n); p("level",UnitLevel and UnitLevel("target") or "MISSING")
/run local p=SBG2.p; if GetUnitFamily then p("family",GetUnitFamily("target") or "nil") else p("family","API_MISSING") end; if UnitCreatureType then p("ct",UnitCreatureType("target") or "nil") else p("ct","API_MISSING") end
/run local p=SBG2.p; if GetUnitPosition then local x,y,z=GetUnitPosition("target"); if x then p("pos",string.format("%.1f %.1f %.1f",x,y,z)) else p("pos","nil/restricted") end else p("pos","API_MISSING") end
```

**Interpretation deltas vs §12.4:** any `MISSING` on `WorldFramePoint3D` is no
longer fatal if `C_Map.PosToScreen = true` (modern projection path);
`numAuras_vals = 1` + `_VERSION = Lua 5.1` confirms modern generation;
`family = API_MISSING` forces detection onto `creatureType`/`extraNames`
(both already in the design, §3.1).

### 12.6 Probe round 3 (SBG3) — confirms pivot building blocks (2026-10-13)

Purpose: (1) final check for any alternative projection/position API; (2)
confirm the building blocks of the pivoted design (§3.0): cursor position,
screen info, player-detection replacement, unit-frame availability, modern
aura API, sound, Bindings. All lines nil-safe, each ≤ 255 chars. Run R1 first
only if `SBG2` was cleared; then any order. R7 needs a spider targeted.

```
/run local p=SBG2.p; p("C_Map.ScreenToPosition",C_Map.ScreenToPosition~=nil); p("GetCameraPosition",GetCameraPosition~=nil); p("GetUnitWorldPosition",GetUnitWorldPosition~=nil); p("GetViewingInfo",GetViewingInfo~=nil)
/run local p=SBG2.p; p("GetCursorPosition",GetCursorPosition~=nil); p("GetEffectiveScreenInfo",GetEffectiveScreenInfo~=nil); p("UnitClass",UnitClass~=nil); p("UnitFactionGroup",UnitFactionGroup~=nil); p("UnitIsUnit",UnitIsUnit~=nil)
/run local p=SBG2.p; p("TargetFrame",TargetFrame~=nil); p("FocusFrame",FocusFrame~=nil); p("MouseOverInfoFrame",MouseOverInfoFrame~=nil); p("PartyFrame",PartyFrame~=nil); p("MainMenuBar",MainMenuBar~=nil)
/run local p=SBG2.p; if GetEffectiveScreenInfo then local w,h,s=GetEffectiveScreenInfo(); p("screen",w.."x"..h.." scale="..tostring(s)) end; if UnitClass then p("playerClass",UnitClass("player")) end
/run local p=SBG2.p; p("playerFaction",UnitFactionGroup and UnitFactionGroup("player") or "API_MISSING"); p("mouseover_class",UnitClass and UnitClass("mouseover") or "n/a")
/run local p=SBG2.p; p("C_UnitAura",C_UnitAura~=nil); p("C_UnitAura.Count",C_UnitAura and C_UnitAura.GetNumUnitAuras and "fn" or "no"); p("PlaySoundFile",PlaySoundFile~=nil); p("Bindings_table",type(Bindings)=="table")
/run local p=SBG2.p; if C_UnitAura and C_UnitAura.GetNumUnitAuras then p("targetAuras",C_UnitAura.GetNumUnitAuras("target")) else p("targetAuras","API_MISSING") end
```

### 12.7 Probe round 4 (SBG4) — wiki-confirmed position/camera chain (2026-10-13)

Context: the Wiki's per-client API table (current 2026-10-06, explicit
"Forever 1.60.1 (70235) Beta" column) lists these as **present in Forever**:
`UnitCreatureFamily` (family name+ID, Spider=3), `UnitCreatureID`,
`UnitPosition` (player/party/raid only), `ClosestUnitPosition` (nearest
creature by NPC ID — starting zones only), `GetUICameraInfo`,
`GetCameraZoom`, `GetCameraFOVDefaults`, `GetScreenWidth`/`GetScreenHeight`.
If the chain works, starting-zone spiders get true 3D-follow covers via manual
projection.

**Run with a spider TARGETED while standing in a starting zone**
(Tirisfal Glades qualifies). R1–R2: spider targeted. R3: no target needed.
R4: spider targeted (re-target if it died). R5–R8: no target needed.
Re-run R1 (`SBG2` helper) only if it was cleared.

```
/run local p=SBG2.p; p("UnitCreatureFamily",UnitCreatureFamily~=nil); if UnitCreatureFamily then local n,id=UnitCreatureFamily("target"); p("fam",tostring(n).." id="..tostring(id)) end
/run local p=SBG2.p; p("UnitCreatureID",UnitCreatureID~=nil); if UnitCreatureID then p("crid",tostring(UnitCreatureID("target"))) end
/run local p=SBG2.p; p("UnitPosition",UnitPosition~=nil); if UnitPosition then local x,y,z,m=UnitPosition("player"); p("playerPos",tostring(x)..","..tostring(y).." z="..tostring(z).." map="..tostring(m)) end
/run local p=SBG2.p; p("ClosestUnitPosition",ClosestUnitPosition~=nil); if UnitCreatureID and ClosestUnitPosition then local x,y,d=ClosestUnitPosition(UnitCreatureID("target")); p("closest",tostring(x)..","..tostring(y).." dist="..tostring(d)) end
/run local p=SBG2.p; p("GetUICameraInfo",GetUICameraInfo~=nil); p("GetCameraZoom",GetCameraZoom~=nil); if GetCameraZoom then p("zoom",tostring(GetCameraZoom())) end
/run local p=SBG2.p; p("GetCameraFOVDefaults",GetCameraFOVDefaults~=nil); if GetCameraFOVDefaults then local a,b,c=GetCameraFOVDefaults(); p("fovDef",tostring(a).."|"..tostring(b).."|"..tostring(c)) end
/run local p=SBG2.p; if GetUICameraInfo then for i=1,5 do local ok,px,py,pz,lx,ly,lz=pcall(GetUICameraInfo,i); p("cam"..i,ok and (tostring(px)..","..tostring(py)..","..tostring(pz)) or "nil") end
/run local p=SBG2.p; local W,H; if GetEffectiveScreenInfo then W,H=GetEffectiveScreenInfo() elseif GetScreenWidth then W,H=GetScreenWidth(),GetScreenHeight() end; p("WH",tostring(W).."x"..tostring(H))
```

**Interpretation:**
- R1 `fam: Spider id=3` (or any `id=3`) → **family-based detection works**
  (primary detection path restored; name patterns stay as fallback).
  `fam: nil` → name-based only.
- R2 `crid: <number>` → needed for R4.
- R3 `playerPos: x,y z=0 map=<id>` → player world position baseline.
- R4 `closest: x,y dist=d` → spider position candidate. If (x,y) is within
  ~`d` of playerPos (same coordinate frame) the chain is geometrically sane.
  `nil` → not a starting zone (or API restriction) → 3D path unavailable
  there.
- R5 `zoom`, R6 `fovDef`, R8 `WH` → projection parameters.
- R7 `cam1..cam5` → find the camera ID whose position is near the player
  (world camera). That ID is the projection input.

Calibration (offline, done by maintainer with R3+R7+R8 numbers): project the
**player's own position** through the manual perspective transform; it must
land at bottom-center of the screen (±~10%). If it does, 3D-follow is on for
starting zones; if not, UI-anchored covers only (time-box per risk 3).

### 12.8 Probe round 5 (SBG5) — UI-anchored design building blocks (2026-10-13)

The 3D path is closed (SBG4). The final probe round confirms the building
blocks of the UI-anchored design (§3.0): cursor position, the `mouseover`
token (hover-shield trigger + detection through it), unit frames, player
detection, sound, `Bindings`.

**R3: hover the mouse over a spider before running it** (and keep it hovering
while R4 runs too). R1, R2, R5, R6: no hover needed. Re-run the `SBG2` helper
(A1) only if it was cleared.

```
/run local p=SBG2.p; p("GetCursorPosition",GetCursorPosition~=nil); if GetCursorPosition then local x,y=GetCursorPosition(); p("cursor",tostring(x)..","..tostring(y)) end
/run local p=SBG2.p; p("playerClass",UnitClass and tostring(UnitClass("player")) or "MISSING"); p("playerFaction",UnitFactionGroup and tostring(UnitFactionGroup("player")) or "MISSING")
/run local p=SBG2.p; p("mouseover",tostring(UnitName("mouseover"))); if UnitCreatureFamily then local n,id=UnitCreatureFamily("mouseover"); p("hover_fam",tostring(n).." id="..tostring(id)) end
/run local p=SBG2.p; p("mouseover_visible",tostring(UnitIsVisible("mouseover"))); p("mouseover_canattack",tostring(UnitCanAttack("mouseover")))
/run local p=SBG2.p; p("TargetFrame",TargetFrame~=nil); p("FocusFrame",FocusFrame~=nil); p("MouseOverInfoFrame",MouseOverInfoFrame~=nil); p("PartyFrame1",PartyFrame1~=nil); p("MainMenuBar",MainMenuBar~=nil); p("UIParent",UIParent~=nil)
/run local p=SBG2.p; p("PlaySoundFile",PlaySoundFile~=nil); p("Bindings",type(Bindings)=="table"); p("UnitIsDead_mouseover",tostring(UnitIsDead("mouseover")))
```

**Interpretation:**
- R1 `cursor: x,y` → `GetCursorPosition` works; numbers should be within the
  `WH` range from SBG4 (1772×1181).
- R2 `playerClass: <class> playerFaction: <Alliance|Horde>` → player-detection
  replacement for the absent `IsPlayerUnit`.
- R3 (mouse on a spider) `mouseover: <spider name> hover_fam: Spider id=3` →
  the hover shield's trigger + detection both work end-to-end. `mouseover:
  nil` = mouse wasn't over a unit when run.
- R4 `mouseover_visible: true mouseover_canattack: true/false` → guard APIs
  accept the `mouseover` token.
- R5 frame globals → where frame covers anchor.
- R6 `PlaySoundFile: true` → config-window sounds; `Bindings: true` → hotkey
  plumbing available.

After this round every API the design depends on is in-client verified, and
M2 (skeleton + load) can start immediately — it needs none of R5's answers.

### 12.9 Probe round 6 (SBG6) — event availability map (2026-10-13)

SBG5 showed `CHAT_COMMAND` is **not** a registerable event on this client,
and the Lua `Bindings` table is absent (this client does keybindings via
XML `<Bindings>` files — see the Spoken addon's Bindings.xml), so the
panic-hotkey mechanism (§4.5) and any event-driven optimizations depend on
which frame events exist at all. These probes pcall `RegisterEvent` (it
*errors* on unknown events, so pcall is the test) and report true/false per
event. Run both lines in order (line 2 needs the frame from line 1; re-run
line 1 after `/reload`).

```
/run local p=SBG2.p; SBG2.f=CreateFrame("Frame"); for _,e in ipairs({"MOUSEOVER","UNIT_TARGET","UPDATE","PLAYER_ENTERING_WORLD","KEY_DOWN","KEY_UP"}) do local ok=pcall(SBG2.f.RegisterEvent,SBG2.f,e); p(e,ok) end
```
```
/run local p=SBG2.p; for _,e in ipairs({"ZONE_CHANGED_NEW_AREA","PARTY_UPDATE","RAID_UPDATE","CHAT_COMMAND","ACTIONBAR_BUTTON_UP","VARIABLES_LOADED","UNIT_AURA","PLAYER_LOGIN"}) do local ok=pcall(SBG2.f.RegisterEvent,SBG2.f,e); p(e,ok) end
```

**Interpretation:**
- `KEY_DOWN: true` → panic hotkey via event (mechanism 1, §4.5).
- `MOUSEOVER: true` → hover shield can be event-driven (polling stays as
  fallback).
- `PLAYER_ENTERING_WORLD: true` → proper init/lifecycle point.
- Anything `true` is an optimization; the design's primary refresh remains
  OnUpdate polling (PLAN.md §3.4). The frames left registered on `SBG2.f`
  are harmless (no OnEvent scripts) but `/reload` (or re-running line 1) keeps
  things clean.

**SBG6 results (2026-10-13; mouse over a spider, spider targeted):**
present = `UNIT_TARGET`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`,
`VARIABLES_LOADED`, `UNIT_AURA`, `PLAYER_LOGIN`; absent = `MOUSEOVER`,
`UPDATE`, `KEY_DOWN`, `KEY_UP`, `PARTY_UPDATE`, `RAID_UPDATE`,
`CHAT_COMMAND`, `ACTIONBAR_BUTTON_UP`. → hover detection must poll the
`mouseover` token; the panic hotkey cannot use `KEY_DOWN` (see §4.5); the
driver must not rely on `RegisterEvent("UPDATE")` (see §3.4, SBG7).

### 12.10 Probe round 7 (SBG7) — driver primitives (2026-10-13)

The tick driver (§3.4) needs one last confirmation: does the *script*
system's `OnUpdate` work (it is separate from the pruned event system), and
which `C_Timer` methods exist? Run both lines in order (line 2 prints
`OnUpdate_ticks: 3` about a second after `armed: true`). Re-run the `SBG2`
helper first if it was cleared.

```
/run local p=SBG2.p; p("CTimer_After",type(C_Timer and C_Timer.After)); p("CTimer_NewTimer",type(C_Timer and C_Timer.NewTimer)); p("CTimer_CancelAll",type(C_Timer and C_Timer.CancelAll))
```
```
/run local p=SBG2.p; local f=CreateFrame("Frame"); f.sbgn=0; f:SetScript("OnUpdate",function(s,dt) s.sbgn=s.sbgn+1; if s.sbgn>=3 then s:SetScript("OnUpdate",nil); p("OnUpdate_ticks",s.sbgn) end end); p("armed",true)
```

**Interpretation:**
- `OnUpdate_ticks: 3` appears → **driver = `OnUpdate` script** (best:
  frame-synced, no drift).
- `OnUpdate_ticks` never appears but `CTimer_After: function` → **driver =
  `C_Timer.After(0.1)` self-rescheduling loop**.
- Both dead (extremely unlikely) → stop and re-evaluate the design with the
  owner; without a periodic driver nothing can tick.
