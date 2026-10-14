# HANDOFF — resume here (fresh session)

Last updated: **2026-10-13**, after probe round SBG6 and M2 in-game
verification. The owner is taking a break; a new agent session should start
with this file.

## One-line status

**M1 (API verification) and M2 (load skeleton) are DONE and verified
in-game.** Next milestone: **M3 — sticky hover shield + parkable shields**.
M3 is pure implementation: every API it needs is already in-client verified.

## Read in this order

1. `docs/PLAN.md` — full design. Key sections: §2 (confirmed API surface +
   SBG1–SBG6 results), §3 (architecture; §3.0 = final UI-anchored design),
   §4 (file inventory, settings schema, slash, panic hotkey), §6
   (milestones), §12 (probe rounds — §12.10 SBG7 is the only remaining
   probe).
2. `docs/API-VERIFICATION.md` — authoritative record of what exists/absent
   on the client (M1 exit record).
3. `SpidersBeGone/` — the addon (currently M2 skeleton: TOC + Core.lua +
   art).
4. `tools/test_core.lua` — offline test harness (run: `lua5.1
   tools/test_core.lua` from the repo root).
5. `~/Apps/AGENTS.md` — the PAWS standard the work is judged by.

## Environment cheat sheet (do NOT re-probe what is verified)

- Repo: local git clone (path is **machine-local** — on the machine from
  2026-10-13 it was `~/Apps/SpidersBeGone`; on the current machine it is
  `~/Apps/SpidersBeGone-ArachnaphobiaAddon`), pushed to
  `github.com/evelyn-loves-coffee/SpidersBeGone-ArachnaphobiaAddon`, public.
- Install: `rm -rf ~/Apps/wow/AddOns/SpidersBeGone && cp -r
  <repo>/SpidersBeGone ~/Apps/wow/AddOns/` (substitute the local clone
  path) — then the user does `/reload` in-game. (`~/Apps/wow/AddOns` is a
  symlink into a Steam/Proton pfx; the compatdata id is machine-local —
  current: `.../compatdata/4154337869/pfx/drive_c/Program Files (x86)/World
  of Warcraft/_classic_beta_/Interface/AddOns/`.)
- Client: WoW **Forever 1.60.1**, build 70374, **interface 16001**,
  **Lua 5.1**, modern codebase, reduced API set. UI-scaled screen
  1772×1181. Character: Horde Warrior.
- Test spider: "Young Night Web Spider" (NPC **1504**, level 2, Tirisfal
  Glades); `UnitCreatureFamily` → `("Spider", 3)`.

## Hard-won client facts (violating these wastes an in-game round)

1. Chat `/run` is capped at **255 chars including `/run`**. Measure every
   line (`wc -c` / `${#line}`) before the user pastes it.
2. `RegisterEvent` **errors** on unknown events (no silent no-op). Only
   register SBG6-confirmed events: `UNIT_TARGET`, `PLAYER_ENTERING_WORLD`,
   `ZONE_CHANGED_NEW_AREA`, `VARIABLES_LOADED`, `UNIT_AURA`,
   `PLAYER_LOGIN` — or pcall-guard everything.
3. Slash commands: **two-part registration only** — `_G.SLASH_SPIDER1 =
   "/spider"` + `SlashCmdList["SPIDER"] = function(msg) end`. Proven by the
   working Spoken addon and by our M2 verification. There is no
   `CHAT_COMMAND` event.
4. `UnitCanAttack` is **two-arg**: `UnitCanAttack(unit, target)`.
5. Keybindings: XML `<Bindings>` files (Spoken ships one, but it is not
   listed in its TOC — ours must be listed and verified via the
   key-binding UI). Lua `Bindings` table absent; `KEY_DOWN`/`KEY_UP` events
   absent.
6. **No world-position or projection APIs** — 3D-follow is closed for good
   (`ClosestUnitPosition` returns nil even in starting zones). Covers are
   UI-anchored (PLAN §3.0).
7. Frame globals that exist: `TargetFrame`, `FocusFrame`, `UIParent`.
   Absent: `MouseOverInfoFrame`, `PartyFrame1`, `MainMenuBar`.
8. Lua 5.1: no `//`, no `goto`, no `table.pack`, no bitwise ops.
9. The client's own UI code is packed (unreadable on disk — `Interface/`
   contains only `AddOns/`). The Spoken addon (`~/Apps/wow/AddOns/Spoken/`)
   is the best working reference for client conventions.
10. All probe output should be `SBG|`/`SBG2|`-prefixed via the helper:
    `/run SBG2={p=function(k,v) print(("SBG2| %s: %s"):format(k,tostring(v))) end}`
    (re-run after any `/reload`; cleanup: `/run SBG2=nil`).

## M3 work order (the next session's job)

1. **Optional:** user runs SBG7 (PLAN §12.10, two short lines) to pick the
   tick driver: OnUpdate script vs `C_Timer.After(0.1)` self-rescheduling
   loop. If the user can't run it, ship with the `C_Timer.After` loop
   (C_Timer confirmed present) — zero risk.
2. **Implement** per PLAN §3/§4 (new files in `SpidersBeGone/`):
   - `Units.lua`: tracked tokens + spider predicate —
     `select(2, UnitCreatureFamily(unit)) == 3` primary; name patterns
     `{"Spider","Gloomweaver"}` + `extraNames` fallback; `UnitClass(unit) ~=
     nil` excludes players.
   - `Cover.lua`: 24-slot frame pool (FIFO), `cover.tga` texture, tint/
     opacity from settings, draggable, positions persisted in
     `SBeGoneSettings` per character.
   - `Core.lua` additions: ~10 Hz tick driver; **sticky hover shield** —
     hover a spider → cover at cursor (`GetCursorPosition`), cover **sticks**
     when the mouse leaves (owner requirement: cover *all* spiders);
     `/spider clear` empties the pool; `/spider on|off`; optional
     `UNIT_TARGET` event to refresh the tracked set sooner.
3. **Extend `tools/test_core.lua`** (predicate with stubbed unit APIs, pool
   FIFO eviction, settings migration) — run under `lua5.1` before every
   in-game round.
4. **Reinstall + in-game test protocol:**
   - `/reload` (no errors), `/spider` (2 selftest lines),
   - hover a Tirisfal spider → cover appears at cursor; move mouse away →
     cover **stays**;
   - drag a cover somewhere; `/reload` → position persists;
   - `/spider clear` → all covers gone; `/spider off` → nothing appears even
     while hovering.
5. **M4 after:** blind mode + panic hotkey (`Bindings.xml` route, §4.5 —
   verify our XML actually loads via the key-binding UI) + frame cover
   (`TargetFrame`/`FocusFrame` only).

## Owner decisions still open

- **Panic hotkey in v1.0?** `KEY_DOWN` route dead (SBG6); `Bindings.xml` is
  the live candidate (needs an in-game key-binding-UI check); `/spider
  hide` is the guaranteed fallback.
- **v1.0 scope** — current default unless the owner objects: sticky hover
  shield + parkable shields + blind mode + `/spider clear`; frame cover
  optional; panic hotkey TBD.
- Owner requirement already encoded (2026-10-13): covers must **persist** —
  "all spiders should be covered", not just while hovered (`stickyCovers`
  default on).

## Release context

Game is in beta ~1 week; out-of-beta release expected next month (2026-11).
Aim: v1.0.0 (M6: README, polish, tag) before/at the public release. Re-run
the §12 probe set on the release client if the interface number changes
(current: 16001).

## Git

- Everything relevant is committed & pushed (check `git log`; latest:
  M2 slash fix + SBG5/SBG6 records). Conventions: `main` branch, lowercase
  conventional-ish messages, tag `v1.0.0` at M6.
- Art regenerates via `python3 tools/make_art.py` (stdlib only) — no binary
  art is ever hand-edited.
