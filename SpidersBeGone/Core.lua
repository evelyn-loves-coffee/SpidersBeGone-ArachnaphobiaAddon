--[[ Spiders Be Gone — arachnophobia addon for World of Warcraft Forever.

Tracking is the only automatic detection mode. Visible accessible spider
nameplates receive click-through covers without targeting or pointer input.
Covers never accept mouse input or store screen positions.
  * /sbg enable: enable tracking (the default) and retry paused coverage.
  * /sbg disable: hide every cover and stop tracking.
  * Bare /sbg prints diagnostics.

Client facts (docs/PLAN.md §2, verified in-client 2026-10-13):
  * WoW Forever 1.60.1 / build 70374 / interface 16001, Lua 5.1
  * RegisterEvent ERRORS on unknown events — only SBG6-confirmed events
  * Slash = two-part registration (SLASH_SBGn + SlashCmdList["SBG"])
  * UnitCanAttack is TWO-ARG on this client: UnitCanAttack(unit, target)
  * A ~10 Hz C_Timer driver scans nameplates; optional plate events refresh it.
]]

SBeGone = SBeGone or {}
SBeGone.version = "0.3.3"
local A = SBeGone.Access

SBeGone.hidden = nil  -- panic-hide seam (M4); true hides every cover
SBeGone.ready = false -- true once a character's covers are restored

-- Diagnostic logging (/sbg debug on). Kept because SBG13 was solved from
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
	-- Schema 4 removes all screen layouts and input-taking cover settings.
	version = 4,
	enabled = true,
	coverStyle = "fox",
	customCover = "",
	opacity = 1,
	coverSize = 96,
	-- ADDITIONAL name fragments on top of the curated database (SpiderDB.lua).
	-- Empty by default: the DB already carries the owner's fragments.
	namePatterns = {},
	extraNames = {},
	requireHostile = false,
	minLevel = 1,
	maxLevel = 99,
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
	-- multiplied by nearBoost. Calibrate: /sbg debug on, walk 30y -> 2y
	-- at a spider, read the 'SBG| near:' line, then /sbg near <N>. 0 = off.
	nearThreshold = 0,
	nearBoost = 2.6,
	debug = false,
}

local function freshDefault(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for i, x in ipairs(v) do out[i] = x end
	return out
end

local function EnsureSettings()
	if type(SBeGoneSettings) ~= "table" then SBeGoneSettings = {} end
	local s = SBeGoneSettings
	-- Versioned schema: missing or wrong-typed keys get fresh defaults;
	-- supported preferences are kept.
	for k, v in pairs(DEFAULTS) do
		if type(s[k]) ~= type(v) then
			s[k] = freshDefault(v)
		end
	end
	-- Purge retired fields for every character at once. A late-loaded save
	-- must not restore an input-taking mode or any screen-positioned cover.
	for _, key in ipairs({ "autoTrack", "stickyCovers", "parkCount", "arrange", "covers", "color" }) do
		s[key] = nil
	end
	SBeGone.Appearance.Normalize(s)
	s.version = DEFAULTS.version
	SBeGone.debug = (s.debug == true)
end
EnsureSettings()

-- ----------------------------------------------------------------- slash
_G.SLASH_SBG1 = "/sbg"

function SBeGone.Slash(msg)
	local first = string.match(msg or "", "^%s*(%S+)") or ""
	if first == "" then
		SBeGone.Selftest()
	elseif first == "config" or first == "options" then
		SBeGone.Config.Open()
	elseif first == "cover" then
		SBeGone.Appearance.Command((msg or ""):match("^%s*%S+%s*(.-)%s*$"))
	elseif first == "opacity" then
		local value = tonumber((msg or ""):match("^%s*%S+%s+(%S+)%s*$"))
		if value then SBeGone.Appearance.SetOpacity(value) end
		print(("SBG| opacity = %d%% (80-100%%; /sbg config or /sbg opacity 0.8-1)")
			:format(math.floor(SBeGone.Appearance.Opacity() * 100 + 0.5)))
	elseif first == "on" or first == "enable" then
		SBeGone.DeathWarning.Clear()
		SBeGoneSettings.enabled = true
		SBeGone.autoSuspended = false
		SBeGone.trackFailures = 0
		SBeGone.tickErrors = 0
		if SBeGone.ready then
			SBeGone.ClearTrack()
			SBeGone.Cover.Init()
			SBeGone.Cover.ApplyStyle()
			SBeGone.Refresh()
		end
		print("SBG| enabled - tracking visible spider nameplates")
	elseif first == "off" or first == "disable" then
		SBeGone.DeathWarning.Clear()
		SBeGoneSettings.enabled = false
		if SBeGone.ready then
			SBeGone.ClearTrack()
			SBeGone.Cover.HideAll()
		end
		print("SBG| disabled - all covers hidden (/sbg enable restores tracking)")
	elseif first == "toggle" then
		SBeGone.Slash(SBeGoneSettings.enabled and "disable" or "enable")
	elseif first == "grow" or first == "drop" or first == "size" then
		-- grow = cover size relative to the plate; drop = how far below the
		-- plate the cover is centred (models hang below their nameplate);
		-- size = fallback UI size when a plate width is unavailable.
		local key = (first == "grow") and "trackScale" or (first == "drop") and "drop" or "coverSize"
		local v = tonumber(string.match(msg or "", "^%s*%S+%s+(%S+)"))
		if not v then
			print(("SBG| %s = %s (set with: /sbg %s N)"):format(key,
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
			print(("SBG| near = %s (set with: /sbg near N - 0 off; read N from the 'SBG| near:' debug line)"):format(
				tostring(SBeGoneSettings.nearThreshold)))
		else
			v = math.floor(v)
			if v < 0 then v = 0 elseif v > 1000 then v = 1000 end
			SBeGoneSettings.nearThreshold = v
			print(("SBG| near = %d (0 = off)"):format(v))
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
			print("SBG| usage: /sbg name <exact creature name>  (list them with /sbg names)")
		else
			local list = (type(SBeGoneSettings.extraNames) == "table") and SBeGoneSettings.extraNames or {}
			local dup
			for idx, existing in ipairs(list) do
				if type(existing) == "string" and existing:lower() == name:lower() then dup = idx end
			end
			if dup then
				print(("SBG| '%s' is already on your extra-name list (entry %d)"):format(name, dup))
			elseif #list >= 64 then
				print("SBG| extra-name list is full (64) - remove one with /sbg forget <name>")
			else
				list[#list + 1] = name
				SBeGoneSettings.extraNames = list
				print(("SBG| will cover '%s' from now on (%d extra) - undo with /sbg forget %s")
					:format(name, #list, name))
			end
		end
	elseif first == "names" then
		local list = (type(SBeGoneSettings.extraNames) == "table") and SBeGoneSettings.extraNames or {}
		if #list == 0 then
			print("SBG| no extra names yet - add one with /sbg name <exact creature name>")
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
			print("SBG| usage: /sbg forget <name>")
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
		print("SBG| /sbg enable / disable / config - image picker / cover <fox / red / blue / sage / charcoal / custom PATH>")
		print("SBG| Advanced: opacity 0.8-1 / grow N / drop N / near N / size N / name X / names / forget X / debug on / debug off")
	else
		print(("SBG| unknown subcommand '%s' - /sbg help for usage"):format(first))
	end
end

SlashCmdList["SBG"] = function(m)
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
	local warning = SBeGone.DeathWarning
	local popupState = warning.popupUnavailable and "unavailable" or (warning.expires and "active" or "idle")
	print(("SBG| enabled=%s | char=%s | driver=%s | corpsePopup=%s | cover=%s"):format(
		tostring(s.enabled), tostring(SBeGone.char),
		tostring(SBeGone.driverOn), popupState, SBeGone.Appearance.Current().id))
	local tracked = 0
	if type(SBeGone.track) == "table" then
		for _, slot in pairs(SBeGone.track) do
			if SBeGone.Cover.IsAllocated(slot) then tracked = tracked + 1 end
		end
	end
	print(("SBG| mode=tracking tracked=%d grow=%s drop=%s near=%s | covers shown=%d/%d | fallbackSize=%s | limited=%s paused=%s"):format(
		tracked, tostring(s.trackScale),
		tostring(s.drop), tostring(s.nearThreshold),
		SBeGone.Cover.ShownCount(), SBeGone.Cover.MAX,
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
	-- Expiration/cleanup must still run while tracking is disabled or paused.
	local warningOK = pcall(SBeGone.DeathWarning.Tick)
	if not warningOK then SBeGone.DeathWarning.Clear() end
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
			print("SBG| automatic covers paused after errors; coverage limited (/sbg enable to retry)")
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

-- Scan accessible native nameplates. Covers never handle pointer input.
function SBeGone.Update()
	if not SBeGone.ready or not SBeGoneSettings.enabled or SBeGone.hidden then return end
	SBeGone.coverageLimited = SBeGone.autoSuspended == true
	SBeGone.Cover.RetryReleases()
	if not SBeGone.autoSuspended then SBeGone.TrackTick() end
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
-- session), so no cover coordinates are queried or persisted. Their position is
-- verified visually on the test client.

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
-- unit now owns that index.
if SBeGone.Cover then
	SBeGone.Cover.onEvict = function(slot)
		local token = SBeGone.trackSlots and SBeGone.trackSlots[slot]
		if token ~= nil then
			SBeGone.trackSlots[slot] = nil
			if SBeGone.track[token] == slot then SBeGone.track[token] = nil end
		end
	end
end

-- Release the entire nameplate-only pool, including deferred/orphaned slots.
function SBeGone.ClearTrack()
	SBeGone.Cover.ClearAll()
	SBeGone.track, SBeGone.trackSlots = {}, {}
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
				SBeGone.DeathWarning.Observe(token)
				local plate = SBeGone.PlateFrameFor(token, i)
				local slot = t[token]
				if plate then
					live[token] = true
					-- Adopt an entry only if its allocation and reverse map agree:
					-- pool indices are recycled between different units.
					if slot == nil or not C.IsAllocated(slot)
						or SBeGone.trackSlots[slot] ~= token then
						slot = C.Allocate()
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
								print("SBG| the client would not anchor covers - automatic covers paused; coverage limited (/sbg enable to retry)")
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
		if state == nil or not state.allocated then
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
-- Wait for a character and its actual SavedVariables before applying the
-- settings migration. This client may supply them after addon script load.
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
	SBeGone.DeathWarning.Clear()
	-- Every cover is rebuilt from live nameplates; none are restored from disk.
	SBeGone.track = {}
	SBeGone.trackSlots = {}
	SBeGone.trackFailures = 0
	SBeGone.autoSuspended = false
	SBeGone.tickErrors = 0
	SBeGone.Cover.Init()
	SBeGone.Cover.ClearAll()
	SBeGone.Cover.ApplyStyle()
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
	pcall(f.RegisterEvent, f, "UNIT_HEALTH")
	pcall(f.RegisterEvent, f, "UNIT_FLAGS")
	pcall(f.RegisterEvent, f, "UNIT_DIED")
	local function readablePayload(primary, legacy)
		if not A.CanRead(primary) then return nil end
		if primary ~= nil then return primary end
		if not A.CanRead(legacy) then return nil end
		return legacy
	end
	f:SetScript("OnEvent", function(_, evt, unitArg)
		-- SBG10: this client's native SetScript calls handlers with NO
		-- arguments — event data arrives via the `this`/`event`/`arg1`..
		-- globals (proven by Spoken's Compat.lua override). `evt` covers
		-- modern-style clients; the bare global covers this one. A
		-- parameter named `event` would shadow the global — do not rename.
		local ev = evt or event
		local payload = readablePayload(unitArg, arg1)
		if ev == "VARIABLES_LOADED" then
			SBeGone.sawVariablesLoaded = true
			SBeGone.RetryEnterWorld()
		elseif ev == "PLAYER_ENTERING_WORLD" then
			SBeGone.DeathWarning.Clear()
			SBeGone.RetryEnterWorld()
		elseif ev == "NAME_PLATE_UNIT_REMOVED" then
			local unit = payload
			if A.CanRead(unit) and type(unit) == "string" then
				SBeGone.DeathWarning.CheckUnit(unit)
				SBeGone.DeathWarning.ForgetToken(unit)
				local slot = SBeGone.track[unit]
				if slot then SBeGone.Cover.Release(slot); dropTrack(unit) end
			end
		elseif ev == "NAME_PLATE_UNIT_ADDED" and SBeGone.ready
			and SBeGoneSettings.enabled and not SBeGone.hidden then
			SBeGone.Refresh()
		elseif ev == "UNIT_HEALTH" or ev == "UNIT_FLAGS" then
			SBeGone.DeathWarning.CheckUnit(payload)
		elseif ev == "UNIT_DIED" then
			SBeGone.DeathWarning.OnDeath(payload)
		end
	end)
	SBeGone.eventFrame = f
end
EnsureEventFrame()

-- If we load already in-world (e.g. /reload in character) AND the settings
-- were already applied at script load, enter now. Otherwise PLAYER_ENTERING_WORLD
-- and VARIABLES_LOADED above cover it, ensuring migration sees the real save.
if UnitName and UnitName("player") and SBeGone.loadSnapshot.settingsPresent then
	SBeGone.OnEnterWorld()
end
