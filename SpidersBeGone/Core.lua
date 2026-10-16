--[[ Spiders Be Gone — arachnophobia addon for World of Warcraft Forever.

Tracking is the only automatic detection mode. Visible accessible spider
nameplates receive click-through covers without targeting or pointer input.
Manual parked shields remain optional; only their positions are persisted.
  * /spider enable: enable tracking (the default) and retry paused coverage.
  * /spider disable: hide every cover and stop tracking.
  * Bare /spider prints diagnostics.

Client facts (docs/PLAN.md §2, verified in-client 2026-10-13):
  * WoW Forever 1.60.1 / build 70374 / interface 16001, Lua 5.1
  * RegisterEvent ERRORS on unknown events — only SBG6-confirmed events
  * Slash = two-part registration (SLASH_SPIDERn + SlashCmdList["SPIDER"])
  * UnitCanAttack is TWO-ARG on this client: UnitCanAttack(unit, target)
  * A ~10 Hz C_Timer driver scans nameplates; optional plate events refresh it.
]]

SBeGone = SBeGone or {}
SBeGone.version = "0.2.7"
local A = SBeGone.Access

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

-- Was SBeGoneSettings already populated when our scripts started running?
-- If it was not, this client may apply SavedVariables after addon Lua, and a
-- restore done at script-load would read empty settings and take the first-run
-- branch (SBG13). Restore then waits for VARIABLES_LOADED.
SBeGone.loadSnapshot = { settingsPresent = (SBeGoneSettings ~= nil) }

-- ---------------------------------------------------------------- settings
local DEFAULTS = {
	-- v2 schema: covers[char] is a { init = true, list = { ... } } record
	-- instead of a bare list (SBG13). Schema 3 retires cursor detection.
	version = 3,
	enabled = true,
	color = { 0.55, 0.12, 0.12 },
	opacity = 0.85,
	coverSize = 96,
	parkCount = 0,
	-- ADDITIONAL name fragments on top of the curated database (SpiderDB.lua).
	-- Empty by default: the DB already carries the owner's fragments.
	namePatterns = {},
	extraNames = {},
	requireHostile = false,
	minLevel = 1,
	maxLevel = 99,
	covers = {}, -- per character: { init = true, list = { {x,y,w,h,kind}, ... } }
	-- Native nameplate tracking is the only detection mode.
	trackScale = 1.6,   -- cover local size = plate local width x this
	-- drop: centre the cover this many cover-heights below the plate.
	-- Calibrated in game 2026-10-16 (owner screenshot, Tirisfal, Young Night
	-- Web Spider): at 0.9 the model sat above the cover's top edge; at 0.5
	-- the whole model (hanging ~0.2-0.3 cover-heights below plate centre) is
	-- inside the cover with only minimal nameplate overlap.
	drop = 0.5,
	trackRelease = 0.5, -- seconds a cover survives losing its plate (anti-flicker)
	-- Near-field boost. The client holds nameplate APPARENT size in a narrow
	-- band while the model keeps growing as the camera approaches, so the
	-- calibrated plate-proportional cover under-covers close spiders (legs
	-- showing - owner screenshot 2026-10-16). True camera distance is
	-- unmeasurable on this client (every position API absent, see
	-- docs/API-VERIFICATION.md); the near band is detected on the one
	-- distance signal the plate does expose: its apparent width
	-- (GetWidth x GetEffectiveScale, in UI-scale px). At/above nearThreshold
	-- the plate is saturated next to the model and the tracked size is
	-- multiplied by nearBoost. Calibrate: /spider debug on, walk 30y -> 2y
	-- at a spider, read the 'SBG| near:' line, then /spider near <N>. 0 = off.
	nearThreshold = 0,
	nearBoost = 2.6,
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
	-- Retire the old mode selectors. An enabled installation now tracks even
	-- if it previously selected the cursor mode. Preserve enabled=false.
	s.autoTrack = nil
	s.stickyCovers = nil
	for char in pairs(s.covers) do SBeGone.Cover.SavedList(s, char) end
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
		SBeGoneSettings.arrange = false
		SBeGone.autoSuspended = false
		SBeGone.trackFailures = 0
		SBeGone.tickErrors = 0
		if SBeGone.ready then
			SBeGone.ClearTrack()
			SBeGone.Cover.Restore(SBeGone.char)
			SBeGone.Cover.ApplyInteractivity()
			SBeGone.Refresh()
		end
		print("SBG| enabled - tracking visible spider nameplates")
	elseif first == "off" or first == "disable" then
		SBeGoneSettings.enabled = false
		SBeGoneSettings.arrange = false
		if SBeGone.ready then
			SBeGone.Cover.Save()
			SBeGone.ClearTrack()
			SBeGone.Cover.HideAll()
			SBeGone.Cover.ApplyInteractivity()
		end
		print("SBG| disabled - all covers hidden (/spider enable restores tracking)")
	elseif first == "toggle" then
		SBeGone.Slash(SBeGoneSettings.enabled and "disable" or "enable")
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
		print("SBG| auto command retired - use /spider enable or /spider disable")
	elseif first == "arrange" then
		-- Covers are click-through by default (a disc must not eat the click
		-- under it). Arrange mode hands the mouse back so they can be dragged.
		if not SBeGoneSettings.enabled then
			print("SBG| disabled - /spider enable before arranging manual shields")
			return
		end
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
		-- size = fixed size of manual parked covers.
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
	elseif first == "near" then
		-- Near-field boost threshold: the plate's apparent width (UI-scale px,
		-- from the 'SBG| near:' debug line) at/above which the client is
		-- holding the nameplate in its near band and the tracked cover is
		-- multiplied by the near-field boost (close spiders, legs showing).
		local v = tonumber(string.match(msg or "", "^%s*%S+%s+(%S+)"))
		if not v then
			print(("SBG| near = %s (set with: /spider near N - 0 off; read N from the 'SBG| near:' debug line)"):format(
				tostring(SBeGoneSettings.nearThreshold)))
		else
			v = math.floor(v)
			if v < 0 then v = 0 elseif v > 1000 then v = 1000 end
			SBeGoneSettings.nearThreshold = v
			print(("SBG| near = %d (0 = off)"):format(v))
		end
	elseif first == "release" then
		-- Tracked covers return on the next scan; manual shields are kept.
		if not SBeGone.ready then
			print("SBG| not in a character yet - nothing to release")
		else
			SBeGone.ClearTrack()
			SBeGone.Cover.Save()
			print("SBG| released tracked covers (parked shields kept)")
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
		print("SBG| /spider [enable / disable / toggle / clear / release / arrange N / parks N / grow N / drop N / near N / size N / name X / names / forget X / debug N / help]")
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
	print(("SBG| enabled=%s | char=%s | driver=%s"):format(
		tostring(s.enabled), tostring(SBeGone.char),
		tostring(SBeGone.driverOn)))
	local tracked = 0
	if type(SBeGone.track) == "table" then
		for _, slot in pairs(SBeGone.track) do
			if SBeGone.Cover.IsAllocated(slot) then tracked = tracked + 1 end
		end
	end
	print(("SBG| mode=tracking tracked=%d arrange=%s grow=%s drop=%s near=%s | covers shown=%d/%d | saved=%d | size=%s | limited=%s paused=%s"):format(
		tracked, tostring(s.arrange), tostring(s.trackScale),
		tostring(s.drop), tostring(s.nearThreshold),
		SBeGone.Cover.ShownCount(), SBeGone.Cover.MAX, saved,
		tostring(s.coverSize), tostring(SBeGone.coverageLimited == true), tostring(SBeGone.autoSuspended == true)))
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
		SBeGone.Refresh()
	end
end

function SBeGone.Refresh()
	if not SBeGone.ready or not SBeGoneSettings.enabled or SBeGone.hidden then return end
	local ok, err = pcall(SBeGone.Update)
	if not ok then
		SBeGone.coverageLimited = true
		SBeGone.tickErrors = (SBeGone.tickErrors or 0) + 1
		if SBeGone.tickErrors <= 3 then
			print("SBG| tick error: " .. tostring(err))
		elseif SBeGone.tickErrors == 4 then
			-- Stop rather than trying another automatic detection channel.
			SBeGone.autoSuspended = true
			SBeGone.ClearTrack()
			print("SBG| automatic covers paused after errors; coverage limited (/spider enable to retry)")
		end
	else
		SBeGone.tickErrors = 0
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

-- Scan accessible nameplates, then pick up optional manual-shield drags.
function SBeGone.Update()
	local s = SBeGoneSettings
	if not SBeGone.ready or not s.enabled or SBeGone.hidden then return end
	SBeGone.coverageLimited = SBeGone.autoSuspended == true
	SBeGone.Cover.RetryReleases()
	if SBeGone.autoSuspended then return end
	-- /spider arrange: the owner is positioning covers by hand, so nothing
	-- tracks and nothing is allocated until arrange is off.
	if s.arrange then
		SBeGone.Cover.SyncDrags()
		return
	end
	SBeGone.TrackTick()
	SBeGone.Cover.SyncDrags()
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
-- That probe only proved that SetPoint is accepted, not that a screen-rooted
-- cover follows the native plate. The reported v0.2.3 cover stayed on screen.
-- v0.2.4 also parents OUR cover to the plate, using plate-local size/offsets
-- so the native transform carries both movement and distance scaling.
--
-- Accepted consequence: a frame anchored to a restricted frame cannot be
-- measured by us either (our own GetPoint threw the same error in that
-- session), so tracked covers are not persistable and their position is
-- verified visually, not numerically. Cover.Save/SyncDrags skip anchored slots.

local MAX_PLATES_SCAN = 40 -- nameplate1..N tokens; plates are not dense
local MIN_TRACK, MAX_TRACK = 16, 512

-- A frame's allocation number is not its current unit identity. The public
-- mapper is authoritative when present; the reduced client can instead expose
-- GetUnit/unitToken/unit (or UnitFrame.unit) on its indexed globals. Read only.
local function plateToken(plate)
	if not A.FrameUsable(plate) then return nil, false end
	local method, _, readable = A.Query(function() return plate.GetUnit end)
	if not readable then return nil, false end
	if type(method) == "function" then
		local token, _, ok = A.Query(method, plate)
		return type(token) == "string" and token or nil, ok
	end
	for _, field in ipairs({ "unitToken", "unit" }) do
		local token, _, ok = A.Query(function() return plate[field] end)
		if not ok then return nil, false end
		if type(token) == "string" then return token, true end
	end
	local token, _, ok = A.Query(function()
		if plate.UnitFrame then return plate.UnitFrame.unit end
	end)
	return type(token) == "string" and token or nil, ok
end

local function plateShown(plate)
	if not A.FrameUsable(plate) then return false end
	local shown, _, ok = A.Query(function() return plate:IsShown() end)
	return ok and shown == true
end

function SBeGone.PlateFrameFor(token, idx)
	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local f, _, ok = A.Query(C_NamePlate.GetNamePlateForUnit, token)
		-- A successful nil means there is NO plate, not permission to adopt a
		-- stale indexed global. Never bind a frame known to display another unit.
		if not ok or not plateShown(f) then return nil end
		local owner, readable = plateToken(f)
		if readable and (owner == nil or owner == token) then return f end
		return nil
	end
	-- Prefer an explicitly matching frame, even when its numeric suffix differs.
	for i = 1, MAX_PLATES_SCAN do
		local f = _G["NamePlate" .. i] or _G["nameplate" .. i]
		if plateShown(f) and plateToken(f) == token then return f end
	end
	-- No numeric-suffix guessing: missing identity is limited coverage.
	return nil
end

-- Tracked covers inherit the plate's effective scale via SetParent. Multiplying
-- that scale into their size as well would apply perspective twice. Only the
-- screen-size limits/fallback need converting from UI units to plate units.
-- The only plate properties this client answers (N7); everything else
-- throws (SBG15). Both reads are access-guarded.
local function plateReads(plate)
	local w = A.Query(function() return plate:GetWidth() end)
	local ps = A.Query(function() return plate:GetEffectiveScale() end)
	return w, ps
end

local function plateSize(w, ps, ourScale, grow, fallback)
	local p = ourScale
	if type(ps) == "number" and ps > 0 then p = ps end
	local toLocal = ourScale / p
	local size = fallback * toLocal
	if type(w) == "number" and w > 0 then size = w * grow end
	return math.max(MIN_TRACK * toLocal, math.min(MAX_TRACK * toLocal, size))
end

function SBeGone.OurScale()
	local ou = 1
	if UIParent and type(UIParent.GetEffectiveScale) == "function" then
		local v = A.Query(UIParent.GetEffectiveScale, UIParent)
		if type(v) == "number" and v > 0 then ou = v end
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
-- cover now lives at that index (for example, a parked shield).
if SBeGone.Cover then
	SBeGone.Cover.onEvict = function(slot)
		local token = SBeGone.trackSlots and SBeGone.trackSlots[slot]
		if token ~= nil then
			SBeGone.trackSlots[slot] = nil
			if SBeGone.track[token] == slot then SBeGone.track[token] = nil end
		end
	end
end

-- Release every tracked cover (disable, arrange mode, /spider release).
function SBeGone.ClearTrack()
	local C = SBeGone.Cover
	for token, slot in pairs(SBeGone.track) do
		if C.IsAllocated(slot) then C.Release(slot) end
	end
	SBeGone.track = {}
	SBeGone.trackSlots = {}
end

function SBeGone.TrackTick()
	if SBeGone.autoSuspended or not SBeGoneSettings.enabled or SBeGone.hidden then return end
	local C, U = SBeGone.Cover, SBeGone.Units
	local s = SBeGoneSettings
	local t = SBeGone.track
	local grow = tonumber(s.trackScale) or 1.6
	local dropK = tonumber(s.drop) or 0.5
	local nearT = tonumber(s.nearThreshold) or 0
	local nearB = tonumber(s.nearBoost) or 2.6
	local grace = math.max(1, math.floor(((tonumber(s.trackRelease) or 0.5)
		/ tickInterval) + 0.5))
	local ourScale = SBeGone.OurScale()
	local live = {}
	local nearDbg = SBeGone.debug and {} or nil

	for i = 1, MAX_PLATES_SCAN do
		local token = "nameplate" .. i
		-- Read-only unit queries only (SBG-verified: UnitExists / UnitIsVisible
		-- / UnitCreatureFamily all answer for nameplate tokens).
		if (not UnitExists or A.Query(UnitExists, token) == true)
			and (not UnitIsVisible or A.Query(UnitIsVisible, token) == true) then
			local isSpider = U.IsSpider(token)
			if isSpider then
				local plate = SBeGone.PlateFrameFor(token, i)
				local slot = t[token]
				if plate then
					live[token] = true
					-- Adopt an entry only if its kind and reverse map still agree:
					-- pool indices are recycled and may belong to a parked shield.
					if slot == nil or C.KindOf(slot) ~= "track"
						or SBeGone.trackSlots[slot] ~= token then
						-- Prefer sacrificing another track cover over parked shields.
						slot = C.Allocate("track", nil, nil, "track")
						if slot ~= nil then
							bindTrack(token, slot)
						else
							dropTrack(token)
						end
					end
					if slot ~= nil then
						local w, ps = plateReads(plate)
						local apparent = (type(w) == "number" and w > 0
							and type(ps) == "number" and ps > 0) and (w * ps) or nil
						local growK = grow
						if nearT > 0 and apparent ~= nil and apparent >= nearT then
							growK = grow * nearB
						end
						local size = plateSize(w, ps, ourScale, growK, C.Size())
						if nearDbg then
							nearDbg[#nearDbg + 1] = token .. "="
								.. (apparent and ("%.1f"):format(apparent) or "?")
						end
						C.Resize(slot, size, size)
						-- Models hang BELOW their nameplate, hence the drop.
						if not C.PlaceTracked(slot, plate, size * dropK) then
							-- Parenting or anchoring may be refused by the client.
							-- Release the slot; do not leave an orphaned screen cover.
							C.Release(slot)
							dropTrack(token)
							SBeGone.trackFailures = (SBeGone.trackFailures or 0) + 1
							if SBeGone.trackFailures == 20 then
								SBeGone.autoSuspended = true
								print("SBG| the client would not anchor covers - automatic covers paused; coverage limited (/spider enable to retry)")
							end
						end
					end
				else
					SBeGone.coverageLimited = true
				end
			end
		end
	end

	-- Calibration readout (throttled to 1/second): the plate's apparent
	-- width per tracked spider, for choosing the near-field threshold.
	if nearDbg and #nearDbg > 0 then
		local now = GetTime()
		if now - (SBeGone.nearDbgAt or 0) >= 1 then
			SBeGone.nearDbgAt = now
			table.sort(nearDbg)
			print("SBG| near: " .. table.concat(nearDbg, " "))
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
		elseif (A.Query(UnitExists, token) == true)
			or (state.anchoredPlate and plateToken(state.anchoredPlate)
				and plateToken(state.anchoredPlate) ~= token) then
			-- A known replacement unit/missing mapping is not a brief loss:
			-- the old cover must not follow a different creature during grace.
			C.Release(slot)
			dropTrack(token)
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
	EnsureSettings() -- also migrate SavedVariables applied after script load
	local char = UnitName and UnitName("player")
	if not char then return false end -- still at character select
	SBeGone.char = char
	SBeGone.ready = true
	-- Saved manual shields are restored; native covers are rebuilt by tracking.
	SBeGone.track = {}
	SBeGone.trackSlots = {}
	SBeGone.trackFailures = 0
	SBeGone.autoSuspended = false
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
	-- Optional on the earlier probed build; supported by current Forever docs.
	-- Unknown event registration is rejected normally and polling remains.
	pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_ADDED")
	pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_REMOVED")
	f:SetScript("OnEvent", function(_, evt, unitArg)
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
		elseif ev == "NAME_PLATE_UNIT_REMOVED" then
			local unit = unitArg or arg1
			if A.CanRead(unit) and type(unit) == "string" then
				local slot = SBeGone.track[unit]
				if slot then SBeGone.Cover.Release(slot); dropTrack(unit) end
			end
		elseif ev == "NAME_PLATE_UNIT_ADDED" and SBeGone.ready
			and SBeGoneSettings.enabled and not SBeGone.hidden then
			SBeGone.Refresh()
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
