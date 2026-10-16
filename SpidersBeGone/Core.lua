--[[ Spiders Be Gone — arachnophobia addon for World of Warcraft Forever.

M3 (UI-anchored covers, docs/PLAN.md §3.0):
  * Sticky hover shield — hover a spider and a cover disc appears at the
    cursor; when the mouse leaves, the cover STICKS (settings.stickyCovers,
    default on). Sweeping the mouse across spiders leaves one stuck cover
    per spider, so every spider you point at stays covered.
  * Parkable shields — on a character's first run, settings.parkCount
    (default 8) pre-parked, draggable cover discs spawn near the top of the
    screen. Covers are SetMovable frames; positions persist per character in
    SBeGoneSettings.covers[<char>] (survive /reload and logout).
  * Slash: /spider [on|off|toggle|clear|help] (bare = selftest).

Client facts (docs/PLAN.md §2, verified in-client 2026-10-13):
  * WoW Forever 1.60.1 / build 70374 / interface 16001, Lua 5.1
  * RegisterEvent ERRORS on unknown events — only SBG6-confirmed events
  * Slash = two-part registration (SLASH_SPIDERn + SlashCmdList["SPIDER"])
  * UnitCanAttack is TWO-ARG on this client: UnitCanAttack(unit, target)
  * No UPDATE / MOUSEOVER events — a ~10 Hz C_Timer driver polls "mouseover"
  * GetCursorPosition / GetEffectiveScreenInfo exist (SBG4/SBG5)
]]

SBeGone = SBeGone or {}
SBeGone.version = "0.2.3"

SBeGone.hidden = nil  -- panic-hide seam (M4); true hides every cover
SBeGone.ready = false -- true once a character's covers are restored

-- Diagnostic logging (/spider debug on). Kept because SBG13 was solved from
-- chat alone; off by default so ordinary play stays quiet.
SBeGone.debug = false

-- M3.5 auto-track state: nameplate token -> cover slot index, plus the reverse
-- map. Pool indices are RECYCLED, so a bare index is not an identity: both maps
-- are checked before an entry is adopted (see SBeGone.TrackTick).
SBeGone.track = {}
SBeGone.trackSlots = {}
-- One sticky cover per hovered creature. Owner report 2026-10-15: "mousing
-- over different units kept creating new covers but didn't clean up old
-- covers, even when mousing over the same unit" — the sticky branch dropped the
-- hover identity, so every re-hover allocated a fresh cover. key -> slot index.
SBeGone.hoverByKey = {}

-- Was SBeGoneSettings already populated when our scripts started running?
-- If it was not, this client may apply SavedVariables after addon Lua, and a
-- restore done at script-load would read empty settings and take the first-run
-- branch (SBG13). Restore then waits for VARIABLES_LOADED.
SBeGone.loadSnapshot = { settingsPresent = (SBeGoneSettings ~= nil) }

-- ---------------------------------------------------------------- settings
local DEFAULTS = {
	-- v2 schema: covers[char] is a { init = true, list = { ... } } record
	-- instead of a bare list (SBG13). Migration is lazy, in Cover.SavedList.
	version = 2,
	enabled = true,
	stickyCovers = true,
	color = { 0.55, 0.12, 0.12 },
	opacity = 0.85,
	coverSize = 96,
	parkCount = 8,
	-- ADDITIONAL name fragments on top of the curated database (SpiderDB.lua).
	-- Empty by default: the DB already carries the owner's fragments.
	namePatterns = {},
	extraNames = {},
	requireHostile = false,
	minLevel = 1,
	maxLevel = 99,
	covers = {}, -- per character: { init = true, list = { {x,y,w,h,kind}, ... } }
	-- M3.5 auto-track: anchor a cover to every visible spider's nameplate and
	-- let the CLIENT move it (SBG15: we cannot measure a plate, but anchoring TO
	-- one is allowed — proven in game 2026-10-15, "anchor=true").
	autoTrack = true,
	trackScale = 1.6,   -- cover size = plate apparent width x this
	drop = 0.9,         -- centre the cover this many cover-heights below the plate
	trackRelease = 0.5, -- seconds a cover survives losing its plate (anti-flicker)
	arrange = false,    -- true = covers take the mouse so they can be dragged
	debug = false,
}

local function freshDefault(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for i, x in ipairs(v) do out[i] = x end
	return out
end

local function EnsureSettings()
	SBeGoneSettings = SBeGoneSettings or {}
	local s = SBeGoneSettings
	-- Versioned schema: missing or wrong-typed keys get fresh defaults;
	-- valid user data (incl. the per-character cover lists) is kept.
	for k, v in pairs(DEFAULTS) do
		if type(s[k]) ~= type(v) then
			s[k] = freshDefault(v)
		end
	end
	-- Version migration seam: apply per-version transforms here as the
	-- schema evolves (currently none — this is v1).
	s.version = DEFAULTS.version
	SBeGone.debug = (s.debug == true)
end
EnsureSettings()

-- ----------------------------------------------------------------- slash
_G.SLASH_SPIDER1 = "/spider"
_G.SLASH_SPIDER2 = "/spidergone"

function SBeGone.ClearCovers()
	if not SBeGone.ready then
		print("SBG| not in a character yet - nothing to clear")
		return
	end
	SBeGone.hover = { slot = nil, key = nil }
	SBeGone.hoverByKey = {}
	SBeGone.track = {}
	SBeGone.trackSlots = {}
	SBeGone.Cover.ClearAll()
	SBeGone.Cover.Save()
end

function SBeGone.Slash(msg)
	local first = string.match(msg or "", "^%s*(%S+)") or ""
	if first == "" then
		SBeGone.Selftest()
	elseif first == "on" or first == "enable" then
		SBeGoneSettings.enabled = true
		if SBeGone.ready then
			SBeGone.hover = { slot = nil, key = nil }
			SBeGone.Cover.Restore(SBeGone.char)
		end
		print("SBG| enabled - covers restored from saved positions")
	elseif first == "off" or first == "disable" then
		SBeGoneSettings.enabled = false
		if SBeGone.ready then
			SBeGone.hover = { slot = nil, key = nil }
			SBeGone.Cover.HideAll()
		end
		print("SBG| disabled - all covers hidden (/spider on restores)")
	elseif first == "toggle" then
		SBeGone.Slash(SBeGoneSettings.enabled and "off" or "on")
	elseif first == "clear" then
		SBeGone.ClearCovers()
		print("SBG| all covers cleared (saved for this character)")
	elseif first == "parks" then
		-- Parked shields are a first-run convenience, not part of the phobia
		-- protection; let the owner set the count (0 = none) without touching
		-- SavedVariables by hand.
		local n = tonumber(string.match(msg or "", "^%s*parks%s+(%S+)"))
		if not n then
			print(("SBG| parked shields = %d (set with: /spider parks N - 0 removes them)"):format(
				SBeGoneSettings.parkCount or 0))
		elseif not SBeGone.ready then
			print("SBG| not in a character yet - parked count unchanged")
		else
			n = math.floor(n)
			if n < 0 then n = 0 end
			if n > SBeGone.Cover.MAX then n = SBeGone.Cover.MAX end
			SBeGoneSettings.parkCount = n
			SBeGone.Cover.RemoveKind("park")
			SBeGone.Cover.Park(n)
			SBeGone.Cover.Save()
			print(("SBG| parked shields = %d"):format(n))
		end
	elseif first == "auto" then
		-- Auto-track is the primary mode (covers follow visible spiders); "off"
		-- falls back to the cursor/sticky behaviour verified in M3.
		local a = string.match(msg or "", "^%s*auto%s+(%S+)") or ""
		if a == "on" or a == "off" then
			SBeGoneSettings.autoTrack = (a == "on")
			if a == "on" then SBeGone.trackFailures = 0 end
			if not SBeGoneSettings.autoTrack and SBeGone.ready then
				SBeGone.ClearTrack()
			end
		end
		print("SBG| auto-track " .. (SBeGoneSettings.autoTrack and "on" or "off"))
	elseif first == "arrange" then
		-- Covers are click-through by default (a disc must not eat the click
		-- under it). Arrange mode hands the mouse back so they can be dragged.
		local a = string.match(msg or "", "^%s*arrange%s+(%S+)") or ""
		if a == "on" then
			SBeGoneSettings.arrange = true
			if SBeGone.ready then
				SBeGone.ClearTrack()
				SBeGone.Cover.ApplyInteractivity()
			end
			print("SBG| arrange ON - covers take the mouse and stop tracking; drag them, then /spider arrange off")
		elseif a == "off" then
			SBeGoneSettings.arrange = false
			if SBeGone.ready then SBeGone.Cover.ApplyInteractivity() end
			print("SBG| arrange OFF - covers are click-through again")
		else
			print("SBG| arrange is " .. (SBeGoneSettings.arrange and "ON" or "OFF")
				.. " ( /spider arrange on to drag covers )")
		end
	elseif first == "grow" or first == "drop" or first == "size" then
		-- grow = cover size relative to the plate; drop = how far below the
		-- plate the cover is centred (models hang below their nameplate);
		-- size = fixed size of parked and sticky covers.
		local key = (first == "grow") and "trackScale" or (first == "drop") and "drop" or "coverSize"
		local v = tonumber(string.match(msg or "", "^%s*%S+%s+(%S+)"))
		if not v then
			print(("SBG| %s = %s (set with: /spider %s N)"):format(key,
				tostring(SBeGoneSettings[key]), first))
		else
			local lo, hi = 0.2, 6
			if first == "drop" then
				lo, hi = 0, 4
			elseif first == "size" then
				lo, hi = 16, 512
			end
			if v < lo then v = lo elseif v > hi then v = hi end
			SBeGoneSettings[key] = v
			print(("SBG| %s = %.2f"):format(key, v))
		end
	elseif first == "release" then
		-- Tracked covers are auto-released when their spider walks away; sticky
		-- covers never are (that is what makes them sticky). This is the
		-- explicit clean-up the owner asked for on 2026-10-15.
		if not SBeGone.ready then
			print("SBG| not in a character yet - nothing to release")
		else
			SBeGone.ResetTrack()
			SBeGone.Cover.Save()
			print("SBG| released tracked and sticky covers (parked shields kept)")
		end
	elseif first == "debug" then
		local a = string.match(msg or "", "^%s*debug%s+(%S+)") or ""
		if a == "on" or a == "off" then SBeGoneSettings.debug = (a == "on") end
		SBeGone.debug = (SBeGoneSettings.debug == true)
		print("SBG| debug logging " .. (SBeGone.debug and "on" or "off"))
	elseif first == "name" then
		-- Owner escape hatch: see a spider that is not covered, name it, done.
		-- EXACT names only (extraNames) — a loose fragment could blanket half a
		-- zone, and curated fragments already live in SpiderDB.lua.
		local name = (msg or ""):match("^%s*%S+%s*(.-)%s*$")
		if not name or name == "" then
			print("SBG| usage: /spider name <exact creature name>  (list them with /spider names)")
		else
			local list = (type(SBeGoneSettings.extraNames) == "table") and SBeGoneSettings.extraNames or {}
			local dup
			for idx, existing in ipairs(list) do
				if type(existing) == "string" and existing:lower() == name:lower() then dup = idx end
			end
			if dup then
				print(("SBG| '%s' is already on your extra-name list (entry %d)"):format(name, dup))
			elseif #list >= 64 then
				print("SBG| extra-name list is full (64) - remove one with /spider forget <name>")
			else
				list[#list + 1] = name
				SBeGoneSettings.extraNames = list
				print(("SBG| will cover '%s' from now on (%d extra) - undo with /spider forget %s")
					:format(name, #list, name))
			end
		end
	elseif first == "names" then
		local list = (type(SBeGoneSettings.extraNames) == "table") and SBeGoneSettings.extraNames or {}
		if #list == 0 then
			print("SBG| no extra names yet - add one with /spider name <exact creature name>")
		else
			print(("SBG| %d extra name(s):"):format(#list))
			local line = ""
			for _, name in ipairs(list) do
				local piece = tostring(name)
				if line ~= "" and #line + #piece + 2 > 200 then
					print("SBG|  " .. line)
					line = piece
				else
					line = (line == "") and piece or (line .. ", " .. piece)
				end
			end
			if line ~= "" then print("SBG|  " .. line) end
		end
	elseif first == "forget" then
		local name = (msg or ""):match("^%s*%S+%s*(.-)%s*$")
		local list = (type(SBeGoneSettings.extraNames) == "table") and SBeGoneSettings.extraNames or {}
		if not name or name == "" then
			print("SBG| usage: /spider forget <name>")
		else
			local kept, removed = {}, 0
			for _, existing in ipairs(list) do
				if type(existing) == "string" and existing:lower() == name:lower() then
					removed = removed + 1
				else
					kept[#kept + 1] = existing
				end
			end
			SBeGoneSettings.extraNames = kept
			print(removed > 0
				and (("SBG| forgot '%s' (%d extra names left)"):format(name, #kept))
				or  (("SBG| '%s' was not on your extra-name list (%d)"):format(name, #kept)))
		end
	elseif first == "help" then
		-- No '|' chars in chat text: the WoW chat filter eats chat-control
		-- sequences like |t / |h (SBG11) — use ' / ' separators.
		print("SBG| /spider [on / off / toggle / clear / release / auto N / arrange N / parks N / grow N / drop N / size N / name X / names / forget X / debug N / help]")
	else
		print(("SBG| unknown subcommand '%s' - /spider help for usage"):format(first))
	end
end

SlashCmdList["SPIDER"] = function(m)
	SBeGone.Slash(m)
end

-- ---------------------------------------------------------------- selftest
local lastSelftest = 0
function SBeGone.Selftest()
	local now = GetTime()
	if now - lastSelftest < 0.25 then return end
	lastSelftest = now
	-- SBG2 (docs/API-VERIFICATION.md): GetBuildInfo returns FOUR values on this
	-- client - "1.60.1", "70374", "Oct 12 2026", "16001" - i.e. build string,
	-- build number, build date, interface version. Not major/minor/patch.
	-- _VERSION already reads "Lua 5.1", so the old "Lua %s" prefix printed
	-- "Lua Lua 5.1" (owner report 2026-10-15); normalise so the word Lua shows
	-- exactly once whatever the client reports.
	local build, buildNo, buildDate, iface = GetBuildInfo()
	local lua = (type(_VERSION) == "string" and _VERSION or "Lua 5.1")
	lua = "Lua " .. ((lua:gsub("^%s*Lua%s+", "")))
	print(("SBG| v%s | WoW %s build %s (%s) | interface %s | %s"):format(
		SBeGone.version, tostring(build), tostring(buildNo), tostring(buildDate),
		tostring(iface), lua))
	local s = SBeGoneSettings
	local saved = 0
	if SBeGone.char and type(s.covers) == "table" then
		local rec = s.covers[SBeGone.char]
		local list
		if type(rec) == "table" then
			list = (type(rec.list) == "table") and rec.list or rec
		end
		if list then
			for _ in ipairs(list) do saved = saved + 1 end
		end
	end
	print(("SBG| enabled=%s | char=%s | driver=%s | sticky=%s"):format(
		tostring(s.enabled), tostring(SBeGone.char),
		tostring(SBeGone.driverOn), tostring(s.stickyCovers)))
	local tracked = 0
	if type(SBeGone.track) == "table" then
		for _, slot in pairs(SBeGone.track) do
			if SBeGone.Cover.IsAllocated(slot) then tracked = tracked + 1 end
		end
	end
	print(("SBG| auto=%s tracked=%d arrange=%s grow=%s drop=%s | covers shown=%d/%d | saved=%d | size=%s"):format(
		tostring(s.autoTrack), tracked, tostring(s.arrange), tostring(s.trackScale),
		tostring(s.drop), SBeGone.Cover.ShownCount(), SBeGone.Cover.MAX, saved,
		tostring(s.coverSize)))
end

-- ----------------------------------------------------------------- driver
-- ~10 Hz tick via a self-rescheduling C_Timer.After loop (C_Timer confirmed
-- present on this client). If the optional SBG7 probe ever shows OnUpdate
-- scripts are live, the driver can switch to an OnUpdate script — the tick
-- function stays identical (PLAN §3.4).
local tickInterval = 0.1

function SBeGone.Tick()
	-- Reschedule FIRST so a one-frame Update error can never kill the
	-- driver; the error is surfaced in chat instead of dying silently.
	if C_Timer and C_Timer.After then
		C_Timer.After(tickInterval, SBeGone.Tick)
	end
	if SBeGone.ready and SBeGoneSettings.enabled and not SBeGone.hidden then
		local ok, err = pcall(SBeGone.Update)
		if not ok then
			SBeGone.tickErrors = (SBeGone.tickErrors or 0) + 1
			if SBeGone.tickErrors <= 3 then
				print("SBG| tick error: " .. tostring(err))
			elseif SBeGone.tickErrors == 4 then
				-- Fail safe instead of spamming chat 10x a second: drop to the
				-- cursor mode the owner knows works.
				SBeGoneSettings.autoTrack = false
				print("SBG| repeated tick errors - auto-track OFF (retry with /spider auto on)")
			end
		else
			SBeGone.tickErrors = 0
		end
	end
end

function SBeGone.StartDriver()
	if SBeGone.driverOn then return end
	if not (C_Timer and C_Timer.After) then
		print("SBG| ERROR: C_Timer.After missing - tick driver cannot start (run SBG7, PLAN §12.10)")
		return
	end
	SBeGone.driverOn = true
	C_Timer.After(tickInterval, SBeGone.Tick)
end

-- Tick logic: pick up drags, then run the sticky hover state machine.
function SBeGone.Update()
	local s = SBeGoneSettings
	-- /spider arrange: the owner is positioning covers by hand, so nothing
	-- tracks and nothing is allocated until arrange is off.
	if s.arrange then
		SBeGone.Cover.SyncDrags()
		return
	end
	-- Auto-track (the owner's goal: covers appear as you walk up on spiders,
	-- no targeting, no mouseover) is the primary mode; the cursor/sticky path
	-- stays available as the fallback for clients without usable nameplates.
	if s.autoTrack then
		SBeGone.TrackTick()
	else
		SBeGone.HoverTick()
	end
	SBeGone.Cover.SyncDrags()
end

-- Fallback mode (also what M3 shipped): a cover follows the cursor while the
-- mouse is on a spider, then sticks.
function SBeGone.HoverTick()
	local s = SBeGoneSettings
	SBeGone.Cover.SyncDrags()

	local name
	if UnitName then
		name = UnitName("mouseover")
	end
	local hovering = name ~= nil and SBeGone.Units.IsSpider("mouseover")
	local h = SBeGone.hover
	local sticky = s.stickyCovers ~= false

	if hovering then
		local cx, cy = GetCursorPosition()
		local id = UnitCreatureID and UnitCreatureID("mouseover")
		local key = name .. "|" .. tostring(id)
		if h.slot == nil or h.key ~= key then
			-- Newly on a (different) spider: settle the previous cover —
			-- release it (sticky off) or leave it stuck (sticky on) — then
			-- start a new cover at the cursor for this spider.
			if h.slot ~= nil and not sticky then
				SBeGone.Cover.Release(h.slot)
			end
			-- One cover per creature: re-hovering a spider re-uses the cover it
			-- already owns instead of allocating a duplicate (owner report:
			-- "kept creating new covers, even when mousing over the same unit").
			-- Same identity rule as tracking (SBG16): a bare index is not an
			-- identity. KindOf must say "hover" - a sticky entry whose cover was
			-- sacrificed to the pool must not adopt somebody else's disc.
			local reuse = sticky and SBeGone.hoverByKey[key] or nil
			if reuse ~= nil and SBeGone.Cover.KindOf(reuse) ~= "hover" then
				reuse = nil
			end
			if reuse ~= nil then
				h.slot = reuse
				SBeGone.Cover.Place(reuse, cx, cy)
			else
				h.slot = SBeGone.Cover.Allocate("hover", cx, cy, "hover")
			end
			SBeGone.hoverByKey[key] = h.slot
			h.key = key
		else
			SBeGone.Cover.Place(h.slot, cx, cy)
		end
	else
		if h.slot ~= nil then
			if not sticky then
				SBeGone.Cover.Release(h.slot)
			end
			-- sticky: the cover simply stays where it is, still mapped to its
			-- creature so the next hover re-uses it
			h.slot = nil
			h.key = nil
			SBeGone.Cover.Save()
		end
	end
end


-- ------------------------------------------------------------ auto-track (M3.5)
-- The behaviour the owner asked for (2026-10-15): "as I walk toward spiders
-- it'll automatically check for the spider... and cover that moves and resizes
-- as the spider moves and resizes" - no target, no mouseover.
--
-- Why anchoring is the ONLY legal way to "move": the client refuses to say
-- where a nameplate is. SBG15 (in game 2026-10-15):
--   NamePlate1:GetRect()/GetCenter()/GetPoint() ->
--     "Action[FrameMeasurement] failed because[Can't measure restricted regions]"
--   GetNamePlateAtPosition -> nil (hit-test reverse lookup absent)
--   C_NamePlate exists as a table, GetNamePlates -> nil
-- but anchoring is allowed:
--   probe:SetPoint("CENTER", NamePlate1, "CENTER", 0, -60) -> "anchor=true"
-- so the client recomputes our frame's position on every layout pass. We get
-- the movement for free, and the plate's own effective scale (0.512 at camera
-- zoom 20 in that same session) tracks distance, so size follows too.
--
-- Accepted consequence: a frame anchored to a restricted frame cannot be
-- measured by us either (our own GetPoint threw the same error in that
-- session), so tracked covers are not persistable and their position is
-- verified visually, not numerically. Cover.Save/SyncDrags skip anchored slots.

local MAX_PLATES_SCAN = 40 -- nameplate1..N tokens; plates are not dense
local MIN_TRACK, MAX_TRACK = 16, 512

function SBeGone.PlateFrameFor(token, idx)
	-- Try the namespace mapper first (C_NamePlate is present on this client but
	-- its members are unverified), then fall back to the indexed globals, which
	-- are proven present in game: _G["NamePlate1"] resolved while its
	-- measurement methods were restricted.
	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local ok, f = pcall(C_NamePlate.GetNamePlateForUnit, token)
		if ok and f then return f end
	end
	return _G["NamePlate" .. idx] or _G["nameplate" .. idx]
end

-- Apparent plate width in OUR frames' units: the plate's own width scaled by
-- the ratio of effective scales. Plain read-only numbers, no measurement of a
-- restricted region (GetWidth / GetEffectiveScale both returned values in game).
local function plateWidthUI(plate, ourScale)
	if type(plate) ~= "table" or type(plate.GetWidth) ~= "function" then return nil end
	local okW, w = pcall(plate.GetWidth, plate)
	if not okW or type(w) ~= "number" or w <= 0 then return nil end
	local ps
	if type(plate.GetEffectiveScale) == "function" then
		local okS, v = pcall(plate.GetEffectiveScale, plate)
		if okS and type(v) == "number" and v > 0 then ps = v end
	end
	local k = (ps or 1) / ((type(ourScale) == "number" and ourScale > 0) and ourScale or 1)
	return w * k
end

function SBeGone.OurScale()
	local ou = 1
	if UIParent and type(UIParent.GetEffectiveScale) == "function" then
		local ok, v = pcall(UIParent.GetEffectiveScale, UIParent)
		if ok and type(v) == "number" and v > 0 then ou = v end
	end
	return ou
end

local function bindTrack(token, slot)
	SBeGone.track[token] = slot
	if slot ~= nil then SBeGone.trackSlots[slot] = token end
end

local function dropTrack(token)
	local slot = SBeGone.track[token]
	if slot ~= nil and SBeGone.trackSlots[slot] == token then
		SBeGone.trackSlots[slot] = nil
	end
	SBeGone.track[token] = nil
end

-- Cover calls this when it sacrifices a slot to make room: an entry that points
-- at a slot we no longer own has to go, otherwise the next tick adopts whatever
-- cover now lives at that index (a parked shield, a sticky cover).
if SBeGone.Cover then
	SBeGone.Cover.onEvict = function(slot)
		local token = SBeGone.trackSlots and SBeGone.trackSlots[slot]
		if token ~= nil then
			SBeGone.trackSlots[slot] = nil
			if SBeGone.track[token] == slot then SBeGone.track[token] = nil end
		end
	end
end

-- Release every tracked cover (mode switch, arrange mode, /spider clear).
function SBeGone.ClearTrack()
	local C = SBeGone.Cover
	for token, slot in pairs(SBeGone.track) do
		if C.IsAllocated(slot) then C.Release(slot) end
	end
	SBeGone.track = {}
	SBeGone.trackSlots = {}
end

-- Tracked covers + the sticky ones (sticky covers are never auto-released, so
-- they need this explicit pass). Parked shields are kept.
function SBeGone.ResetTrack()
	SBeGone.ClearTrack()
	local C = SBeGone.Cover
	for key, slot in pairs(SBeGone.hoverByKey) do
		if C.IsAllocated(slot) then C.Release(slot) end
	end
	SBeGone.hoverByKey = {}
	SBeGone.hover = { slot = nil, key = nil }
end

function SBeGone.TrackTick()
	local C, U = SBeGone.Cover, SBeGone.Units
	local s = SBeGoneSettings
	local t = SBeGone.track
	local grow = tonumber(s.trackScale) or 1.6
	local dropK = tonumber(s.drop) or 0.9
	local grace = math.max(1, math.floor(((tonumber(s.trackRelease) or 0.5)
		/ tickInterval) + 0.5))
	local ourScale = SBeGone.OurScale()
	local live = {}

	for i = 1, MAX_PLATES_SCAN do
		local token = "nameplate" .. i
		-- Read-only unit queries only (SBG-verified: UnitExists / UnitIsVisible
		-- / UnitCreatureFamily all answer for nameplate tokens).
		if (not UnitExists or UnitExists(token))
			and (not UnitIsVisible or UnitIsVisible(token)) then
			local isSpider = U.IsSpider(token)
			live[token] = isSpider
			if isSpider then
				local slot = t[token]
				-- Adopt an existing entry only if it is still OURS: allocated,
				-- still a track cover, and bound to this token. Anything else is
				-- a recycled index and gets a fresh cover instead.
				if slot == nil or C.KindOf(slot) ~= "track"
					or SBeGone.trackSlots[slot] ~= token then
					-- Evict another tracked cover first if the pool is full: a
					-- screen full of spiders must never eat the owner's parked
					-- shields (that is what /spider parks N is for).
					slot = C.Allocate("track", nil, nil, "track")
					if slot ~= nil then
						bindTrack(token, slot)
					else
						dropTrack(token)
					end
				end
				if slot ~= nil then
					local plate = SBeGone.PlateFrameFor(token, i)
					if plate ~= nil then
						local pw = plateWidthUI(plate, ourScale)
						local size = C.Size()
						if pw then
							size = pw * grow
							if size < MIN_TRACK then size = MIN_TRACK end
							if size > MAX_TRACK then size = MAX_TRACK end
						end
						C.Resize(slot, size, size)
						-- Models hang BELOW their nameplate, hence the drop.
						if not C.PlaceTracked(slot, plate, size * dropK) then
							-- The client refused the anchor. Proven legal in game
							-- (2026-10-15), so a refusal means a stale frame handle:
							-- release the slot rather than leave a position-less
							-- frame around, and give up after a run of refusals
							-- instead of churning the pool 10 times a second.
							C.Release(slot)
							dropTrack(token)
							SBeGone.trackFailures = (SBeGone.trackFailures or 0) + 1
							if SBeGone.trackFailures == 20 then
								SBeGoneSettings.autoTrack = false
								print("SBG| the client would not anchor covers - auto-track OFF (/spider auto on to retry)")
							end
						end
					end
				end
			end
		end
	end

	-- Release covers whose spider is gone, after a short grace so plate token
	-- recycling (and a spider walking out of range for a frame) does not
	-- strobe the cover.
	for token, slot in pairs(t) do
		local state = C.pool[slot]
		if state == nil or not state.allocated or state.kind ~= "track" then
			dropTrack(token)
		elseif live[token] then
			state.miss = 0
		else
			state.miss = (state.miss or 0) + 1
			if state.miss > grace then
				C.Release(slot)
				dropTrack(token)
			end
		end
	end
end

-- ---------------------------------------------------------------- lifecycle
-- The restore point needs two things: (a) a character, and (b) this account's
-- SavedVariables actually in hand. (b) is the SBG13 lesson: on 2026-10-15 the
-- character's list was on disk as "cleared" (covers[char] = {}) yet every
-- /reload showed the 8 default parks with saved=0 — Restore had taken the
-- first-run branch, i.e. it ran against settings that did not carry the record.
-- Until VARIABLES_LOADED has been seen (unless the settings table was already
-- populated at script load), refuse to restore rather than guess.
function SBeGone.OnEnterWorld()
	if SBeGone.ready then return true end
	if not SBeGone.loadSnapshot.settingsPresent and not SBeGone.sawVariablesLoaded then
		return false
	end
	local char = UnitName and UnitName("player")
	if not char then return false end -- still at character select
	SBeGone.char = char
	SBeGone.ready = true
	-- This session starts with no hover / tracking state: saved covers are
	-- re-shown by Restore, tracked covers are rebuilt on the first tick.
	SBeGone.hover = { slot = nil, key = nil }
	SBeGone.hoverByKey = {}
	SBeGone.track = {}
	SBeGone.trackSlots = {}
	SBeGone.trackFailures = 0
	SBeGone.tickErrors = 0
	-- Arrange mode is a transient editing state: if it survived in
	-- SavedVariables, every cover would eat clicks at login (playability rule),
	-- so a fresh session always starts click-through.
	SBeGoneSettings.arrange = false
	SBeGone.Cover.Restore(char)
	SBeGone.Cover.ApplyInteractivity()
	SBeGone.StartDriver()
	return true
end

-- Restore when we can, otherwise ask again for ~10 s (C_Timer.After is proven
-- present; the no-op in the offline harness makes the retry inert there).
function SBeGone.RetryEnterWorld()
	if SBeGone.ready then return end
	if SBeGone.OnEnterWorld() then return end
	SBeGone.retries = (SBeGone.retries or 0) + 1
	if SBeGone.retries >= 20 then return end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, SBeGone.RetryEnterWorld)
	end
end

local function EnsureEventFrame()
	if SBeGone.eventFrame then return end
	local f = CreateFrame("Frame")
	-- SBG6-confirmed events only (RegisterEvent errors on unknown names)
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("VARIABLES_LOADED")
	f:SetScript("OnEvent", function(_, evt)
		-- SBG10: this client's native SetScript calls handlers with NO
		-- arguments — event data arrives via the `this`/`event`/`arg1`..
		-- globals (proven by Spoken's Compat.lua override). `evt` covers
		-- modern-style clients; the bare global covers this one. A
		-- parameter named `event` would shadow the global — do not rename.
		local ev = evt or event
		if ev == "VARIABLES_LOADED" then
			SBeGone.sawVariablesLoaded = true
			SBeGone.RetryEnterWorld()
		elseif ev == "PLAYER_ENTERING_WORLD" then
			SBeGone.RetryEnterWorld()
		end
	end)
	SBeGone.eventFrame = f
end
EnsureEventFrame()

-- If we load already in-world (e.g. /reload in character) AND the settings
-- were already applied at script load, enter now. Otherwise PLAYER_ENTERING_WORLD
-- and VARIABLES_LOADED above cover it — restoring any earlier would read empty
-- settings and re-spawn the default parks over the saved state (SBG13).
if UnitName and UnitName("player") and SBeGone.loadSnapshot.settingsPresent then
	SBeGone.OnEnterWorld()
end
