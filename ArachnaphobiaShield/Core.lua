--[[ Arachnaphobia Shield — arachnophobia addon for World of Warcraft Forever.

Tracking is the only automatic detection mode. Visible accessible spider
nameplates receive click-through covers without targeting or pointer input.
Covers never accept mouse input or store screen positions.
  * /as enable: enable tracking (the default) and retry paused coverage.
  * /as disable: hide every cover and stop tracking.
  * /as reset: restore every saved setting to its factory default.
  * Bare /as prints diagnostics.

Client facts (docs/PLAN.md §2, verified in-client 2026-10-13):
  * WoW Forever 1.60.1 / build 70374 / interface 16001, Lua 5.1
  * RegisterEvent ERRORS on unknown events — only AS6-confirmed events
  * Slash = two-part registration (SLASH_ASn + SlashCmdList["AS"])
  * UnitCanAttack is TWO-ARG on this client: UnitCanAttack(unit, target)
  * A ~10 Hz C_Timer driver scans nameplates; optional plate events refresh it.
]]

ArachnaphobiaShield = ArachnaphobiaShield or {}
ArachnaphobiaShield.version = "0.4.6"
local A = ArachnaphobiaShield.Access

ArachnaphobiaShield.hidden = nil  -- panic-hide seam (M4); true hides every cover
ArachnaphobiaShield.ready = false -- true once a character's covers are restored

-- Diagnostic logging (/as debug on). Kept because AS13 was solved from
-- chat alone; off by default so ordinary play stays quiet.
ArachnaphobiaShield.debug = false

-- M3.5 auto-track state: nameplate token -> cover slot index, plus the reverse
-- map. Pool indices are RECYCLED, so a bare index is not an identity: both maps
-- are checked before an entry is adopted (see ArachnaphobiaShield.TrackTick).
ArachnaphobiaShield.track = {}
ArachnaphobiaShield.trackSlots = {}

-- Was ArachnaphobiaShieldSettings already populated when our scripts started running?
-- If it was not, this client may apply SavedVariables after addon Lua, and a
-- restore done at script-load would read empty settings and take the first-run
-- branch (AS13). Restore then waits for VARIABLES_LOADED.
ArachnaphobiaShield.loadSnapshot = { settingsPresent = (ArachnaphobiaShieldSettings ~= nil) }

-- ---------------------------------------------------------------- settings
local DEFAULTS = {
	-- Schema 4 removes all screen layouts and input-taking cover settings.
	version = 5,
	enabled = true,
	coverStyle = "fox",
	customCover = "",
	-- v0.3.8: opacity retired; covers are always fully opaque (the client
	-- fades them at distance regardless). Legacy keys are dropped in
	-- Appearance.Normalize.
	coverSize = 96,
	-- ADDITIONAL name fragments on top of the curated database (SpiderDB.lua).
	-- Empty by default: the DB already carries the owner's fragments.
	namePatterns = {},
	extraNames = {},
	requireHostile = false,
	minLevel = 1,
	maxLevel = 99,
	-- Native nameplate tracking is the only detection mode.
	trackScale = 1.0,   -- cover local size = plate local width x this
	-- v0.4.0: /as grow is a PERCENTAGE (100 = default 1.0, allowed 80-120);
	-- the stored value stays a multiplier (0.8-1.2).
	-- drop: centre the cover this many cover-heights below the plate.
	-- Calibrated in game 2026-10-16 (owner screenshot, Tirisfal, Young Night
	-- Web Spider): at 0.9 the model sat above the cover's top edge; at 0.5
	-- the whole model (hanging ~0.2-0.3 cover-heights below plate centre) is
	-- inside the cover with only minimal nameplate overlap.
	drop = 0.5,
	trackRelease = 0.5, -- seconds a cover survives losing its plate (anti-flicker)
	-- Near-field boost (v0.4.1: automatic, no config value). The client
	-- holds nameplate APPARENT size in a narrow band while the model keeps
	-- growing as the camera approaches, so the calibrated plate-proportional
	-- cover under-covers close spiders (legs showing - owner screenshot
	-- 2026-10-16). True camera distance is unmeasurable on this client
	-- (every position API absent, see docs/API-VERIFICATION.md); the only
	-- distance signal the plate exposes is its apparent width (GetWidth x
	-- GetEffectiveScale, in UI-scale px). Every 10 Hz tick multiplies the
	-- tracked size by nearBoostFor(apparent): 1.0 at/under the ramp's low
	-- knee (75 UI), smoothstepping to nearBoost at/above the high knee
	-- (85 UI). The client's actual apparent-width range is narrow: far
	-- plates are clamped at 73.0 UI and grow to ~90 UI as the camera
	-- approaches (debug capture 2026-10-17: far plates steady at 73.0,
	-- approach traces 74.6->77.7->84.4->89.7 and 73.0->77.0->80.5->82.8
	-- ->86.1), so the ramp must sit INSIDE that range - knees below the
	-- 73 clamp boost far plates (the v0.4.1/v0.4.2 bug, docs/NEAR-RAMP.md).
	-- The high knee sits below the measured close-range apparent widths
	-- (87-113 UI, 1.205 px/UI calibration, 2026-10-16 screenshots) so the
	-- boost is constant across the whole band the client clamps to - the
	-- cover cannot "breathe". Far plates (<= ~74) stay unboosted and
	-- plate-proportional, keeping the /as near 1 far-shrink behavior.
	-- Verify with /as debug on and the 'AS| near:' line (apparent width
	-- and computed factor per plate). Ceiling: 3.0 since v0.4.4 (raised
	-- from 2.6) - the plate width saturates at ~91 UI at extreme close
	-- range, so the flat ceiling is the only lever that adds cover there;
	-- at 2.6 the model's legs poked past the cover (owner, 2026-10-17).
	nearBoost = 3.0,
	debug = false,
}

local function freshDefault(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for i, x in ipairs(v) do out[i] = x end
	return out
end

local function EnsureSettings()
	if type(ArachnaphobiaShieldSettings) ~= "table" then ArachnaphobiaShieldSettings = {} end
	local s = ArachnaphobiaShieldSettings
	-- Versioned schema: missing or wrong-typed keys get fresh defaults;
	-- supported preferences are kept.
	for k, v in pairs(DEFAULTS) do
		if type(s[k]) ~= type(v) then
			s[k] = freshDefault(v)
		end
	end
	-- v0.4.0: legacy v0.3.x multipliers (0.2-6) are outside the new 80-120
	-- percent band; clamp them into it instead of silently keeping them.
	if type(s.trackScale) == "number" then
		s.trackScale = math.max(0.8, math.min(1.2, s.trackScale))
	end
	-- Purge retired fields for every character at once. A late-loaded save
	-- must not restore an input-taking mode or any screen-positioned cover.
	for _, key in ipairs({ "autoTrack", "stickyCovers", "parkCount", "arrange", "covers", "color", "nearThreshold" }) do
		s[key] = nil
	end
	ArachnaphobiaShield.Appearance.Normalize(s)
	s.version = DEFAULTS.version
	ArachnaphobiaShield.debug = (s.debug == true)
end
EnsureSettings()

-- /as reset: restore the SavedVariables table to factory defaults and apply
-- them live the way the load path does. Replacing the global table is safe:
-- every consumer reads ArachnaphobiaShieldSettings fresh, and the client saves the table
-- the global references at shutdown.
function ArachnaphobiaShield.Reset()
	local s = {}
	for k, v in pairs(DEFAULTS) do s[k] = freshDefault(v) end
	ArachnaphobiaShieldSettings = s
	ArachnaphobiaShield.Appearance.Normalize(s)
	ArachnaphobiaShield.debug = (s.debug == true)
	-- The default is tracking on, so resume exactly like /as enable.
	ArachnaphobiaShield.DeathWarning.Clear()
	ArachnaphobiaShield.autoSuspended = false
	ArachnaphobiaShield.trackFailures = 0
	ArachnaphobiaShield.tickErrors = 0
	if ArachnaphobiaShield.ready then
		ArachnaphobiaShield.ClearTrack()
		ArachnaphobiaShield.Cover.Init()
		ArachnaphobiaShield.Cover.ApplyStyle()
		ArachnaphobiaShield.Refresh()
	end
	if ArachnaphobiaShield.Config and ArachnaphobiaShield.Config.frame then ArachnaphobiaShield.Config.Refresh() end
	print("AS| settings restored to defaults - tracking on, fox cover")
end

-- ----------------------------------------------------------------- slash
_G.SLASH_AS1 = "/as"

function ArachnaphobiaShield.Slash(msg)
	local first = string.match(msg or "", "^%s*(%S+)") or ""
	if first == "" then
		ArachnaphobiaShield.Selftest()
	elseif first == "config" or first == "options" then
		ArachnaphobiaShield.Config.Open()
	elseif first == "cover" then
		ArachnaphobiaShield.Appearance.Command((msg or ""):match("^%s*%S+%s*(.-)%s*$"))
	elseif first == "on" or first == "enable" then
		ArachnaphobiaShield.DeathWarning.Clear()
		ArachnaphobiaShieldSettings.enabled = true
		ArachnaphobiaShield.autoSuspended = false
		ArachnaphobiaShield.trackFailures = 0
		ArachnaphobiaShield.tickErrors = 0
		if ArachnaphobiaShield.ready then
			ArachnaphobiaShield.ClearTrack()
			ArachnaphobiaShield.Cover.Init()
			ArachnaphobiaShield.Cover.ApplyStyle()
			ArachnaphobiaShield.Refresh()
		end
		print("AS| enabled - tracking visible spider nameplates")
	elseif first == "off" or first == "disable" then
		ArachnaphobiaShield.DeathWarning.Clear()
		ArachnaphobiaShieldSettings.enabled = false
		if ArachnaphobiaShield.ready then
			ArachnaphobiaShield.ClearTrack()
			ArachnaphobiaShield.Cover.HideAll()
		end
		print("AS| disabled - all covers hidden (/as enable restores tracking)")
	elseif first == "toggle" then
		ArachnaphobiaShield.Slash(ArachnaphobiaShieldSettings.enabled and "disable" or "enable")
	elseif first == "reset" then
		ArachnaphobiaShield.Reset()
	elseif first == "grow" then
		-- v0.4.0: cover size as a PERCENTAGE of the plate width. 100 = the
		-- default; allowed 80-120. Stored as a multiplier (0.8-1.2).
		local v = tonumber(string.match(msg or "", "^%s*%S+%s+(%S+)"))
		if not v then
			local cur = (type(ArachnaphobiaShieldSettings.trackScale) == "number")
				and ArachnaphobiaShieldSettings.trackScale or 1.0
			print(("AS| grow = %d%% (100 = default, allowed 80-120)")
				:format(math.floor(cur * 100 + 0.5)))
			return
		end
		if v ~= math.floor(v) or v < 80 or v > 120 then
			print("AS| grow: expected a whole number 80-120 (100 = default)")
			return
		end
		ArachnaphobiaShieldSettings.trackScale = v / 100
		print(("AS| grow = %d%%"):format(v))
	elseif first == "drop" then
		-- drop = how far below the plate the cover is centred (models hang
		-- below their nameplate)
		local v = tonumber(string.match(msg or "", "^%s*%S+%s+(%S+)"))
		if not v then
			print(("AS| drop = %s (set with: /as drop N)"):format(
				tostring(ArachnaphobiaShieldSettings.drop)))
			return
		end
		if v < 0 then v = 0 elseif v > 4 then v = 4 end
		ArachnaphobiaShieldSettings.drop = v
		print(("AS| drop = %.2f"):format(v))
	elseif first == "near" then
		-- v0.4.1: the boost is computed automatically every tick from the
		-- plate's apparent width (see nearBoostFor); the level config is
		-- retired.
		print("AS| near: the boost is automatic now (it ramps with apparent width - watch the 'AS| near:' line via /as debug on); there is no setting to change")
	elseif first == "debug" then
		local a = string.match(msg or "", "^%s*debug%s+(%S+)") or ""
		if a == "on" or a == "off" then ArachnaphobiaShieldSettings.debug = (a == "on") end
		ArachnaphobiaShield.debug = (ArachnaphobiaShieldSettings.debug == true)
		print("AS| debug logging " .. (ArachnaphobiaShield.debug and "on" or "off"))
	elseif first == "name" then
		-- Owner escape hatch: see a spider that is not covered, name it, done.
		-- EXACT names only (extraNames) — a loose fragment could blanket half a
		-- zone, and curated fragments already live in SpiderDB.lua.
		local name = (msg or ""):match("^%s*%S+%s*(.-)%s*$")
		if not name or name == "" then
			print("AS| usage: /as name <exact creature name>  (list them with /as names)")
		else
			local list = (type(ArachnaphobiaShieldSettings.extraNames) == "table") and ArachnaphobiaShieldSettings.extraNames or {}
			local dup
			for idx, existing in ipairs(list) do
				if type(existing) == "string" and existing:lower() == name:lower() then dup = idx end
			end
			if dup then
				print(("AS| '%s' is already on your extra-name list (entry %d)"):format(name, dup))
			elseif #list >= 64 then
				print("AS| extra-name list is full (64) - remove one with /as forget <name>")
			else
				list[#list + 1] = name
				ArachnaphobiaShieldSettings.extraNames = list
				print(("AS| will cover '%s' from now on (%d extra) - undo with /as forget %s")
					:format(name, #list, name))
			end
		end
	elseif first == "names" then
		local list = (type(ArachnaphobiaShieldSettings.extraNames) == "table") and ArachnaphobiaShieldSettings.extraNames or {}
		if #list == 0 then
			print("AS| no extra names yet - add one with /as name <exact creature name>")
		else
			print(("AS| %d extra name(s):"):format(#list))
			local line = ""
			for _, name in ipairs(list) do
				local piece = tostring(name)
				if line ~= "" and #line + #piece + 2 > 200 then
					print("AS|  " .. line)
					line = piece
				else
					line = (line == "") and piece or (line .. ", " .. piece)
				end
			end
			if line ~= "" then print("AS|  " .. line) end
		end
	elseif first == "forget" then
		local name = (msg or ""):match("^%s*%S+%s*(.-)%s*$")
		local list = (type(ArachnaphobiaShieldSettings.extraNames) == "table") and ArachnaphobiaShieldSettings.extraNames or {}
		if not name or name == "" then
			print("AS| usage: /as forget <name>")
		else
			local kept, removed = {}, 0
			for _, existing in ipairs(list) do
				if type(existing) == "string" and existing:lower() == name:lower() then
					removed = removed + 1
				else
					kept[#kept + 1] = existing
				end
			end
			ArachnaphobiaShieldSettings.extraNames = kept
			print(removed > 0
				and (("AS| forgot '%s' (%d extra names left)"):format(name, #kept))
				or  (("AS| '%s' was not on your extra-name list (%d)"):format(name, #kept)))
		end
	elseif first == "help" then
		-- No '|' chars in chat text: the WoW chat filter eats chat-control
		-- sequences like |t / |h (AS11) — use ' / ' separators.
		print("AS| /as enable / disable / reset / config - image picker / cover <fox / red / blue / sage / charcoal / custom PATH>")
		print("AS| Advanced: grow N (80-120, 100 = default) / drop N / name X / names / forget X / debug on / debug off")
	else
		print(("AS| unknown subcommand '%s' - /as help for usage"):format(first))
	end
end

SlashCmdList["AS"] = function(m)
	ArachnaphobiaShield.Slash(m)
end

-- ---------------------------------------------------------------- selftest
local lastSelftest = 0
function ArachnaphobiaShield.Selftest()
	local now = GetTime()
	if now - lastSelftest < 0.25 then return end
	lastSelftest = now
	-- AS2 (docs/API-VERIFICATION.md): GetBuildInfo returns FOUR values on this
	-- client - "1.60.1", "70374", "Oct 12 2026", "16001" - i.e. build string,
	-- build number, build date, interface version. Not major/minor/patch.
	-- _VERSION already reads "Lua 5.1", so the old "Lua %s" prefix printed
	-- "Lua Lua 5.1" (owner report 2026-10-15); normalise so the word Lua shows
	-- exactly once whatever the client reports.
	local build, buildNo, buildDate, iface = GetBuildInfo()
	local lua = (type(_VERSION) == "string" and _VERSION or "Lua 5.1")
	lua = "Lua " .. ((lua:gsub("^%s*Lua%s+", "")))
	print(("AS| v%s | WoW %s build %s (%s) | interface %s | %s"):format(
		ArachnaphobiaShield.version, tostring(build), tostring(buildNo), tostring(buildDate),
		tostring(iface), lua))
	local s = ArachnaphobiaShieldSettings
	local warning = ArachnaphobiaShield.DeathWarning
	local popupState = warning.popupUnavailable and "unavailable" or (warning.expires and "active" or "idle")
	print(("AS| enabled=%s | char=%s | driver=%s | corpsePopup=%s | cover=%s"):format(
		tostring(s.enabled), tostring(ArachnaphobiaShield.char),
		tostring(ArachnaphobiaShield.driverOn), popupState, ArachnaphobiaShield.Appearance.Current().id))
	local tracked = 0
	if type(ArachnaphobiaShield.track) == "table" then
		for _, slot in pairs(ArachnaphobiaShield.track) do
			if ArachnaphobiaShield.Cover.IsAllocated(slot) then tracked = tracked + 1 end
		end
	end
	-- v0.4.1: report the same units the commands accept (grow %).
	local growPct = math.floor((tonumber(s.trackScale) or 1.0) * 100 + 0.5)
	local nearLabel = ("auto(x%.1f)"):format(tonumber(s.nearBoost) or 2.6)
	print(("AS| mode=tracking tracked=%d grow=%d%% drop=%s near=%s | covers shown=%d/%d | fallbackSize=%s | limited=%s paused=%s"):format(
		tracked, growPct,
		tostring(s.drop), nearLabel,
		ArachnaphobiaShield.Cover.ShownCount(), ArachnaphobiaShield.Cover.MAX,
		tostring(s.coverSize), tostring(ArachnaphobiaShield.coverageLimited == true), tostring(ArachnaphobiaShield.autoSuspended == true)))
end

-- ----------------------------------------------------------------- driver
-- ~10 Hz tick via a self-rescheduling C_Timer.After loop (C_Timer confirmed
-- present on this client). If the optional AS7 probe ever shows OnUpdate
-- scripts are live, the driver can switch to an OnUpdate script — the tick
-- function stays identical (PLAN §3.4).
local tickInterval = 0.1

function ArachnaphobiaShield.Tick()
	-- Reschedule FIRST so a one-frame Update error can never kill the
	-- driver; the error is surfaced in chat instead of dying silently.
	if C_Timer and C_Timer.After then
		C_Timer.After(tickInterval, ArachnaphobiaShield.Tick)
	end
	-- Expiration/cleanup must still run while tracking is disabled or paused.
	local warningOK = pcall(ArachnaphobiaShield.DeathWarning.Tick)
	if not warningOK then ArachnaphobiaShield.DeathWarning.Clear() end
	if ArachnaphobiaShield.ready and ArachnaphobiaShieldSettings.enabled and not ArachnaphobiaShield.hidden then
		ArachnaphobiaShield.Refresh()
	end
end

function ArachnaphobiaShield.Refresh()
	if not ArachnaphobiaShield.ready or not ArachnaphobiaShieldSettings.enabled or ArachnaphobiaShield.hidden then return end
	local ok, err = pcall(ArachnaphobiaShield.Update)
	if not ok then
		ArachnaphobiaShield.coverageLimited = true
		ArachnaphobiaShield.tickErrors = (ArachnaphobiaShield.tickErrors or 0) + 1
		if ArachnaphobiaShield.tickErrors <= 3 then
			print("AS| tick error: " .. tostring(err))
		elseif ArachnaphobiaShield.tickErrors == 4 then
			-- Stop rather than trying another automatic detection channel.
			ArachnaphobiaShield.autoSuspended = true
			ArachnaphobiaShield.ClearTrack()
			print("AS| automatic covers paused after errors; coverage limited (/as enable to retry)")
		end
	else
		ArachnaphobiaShield.tickErrors = 0
	end
end

function ArachnaphobiaShield.StartDriver()
	if ArachnaphobiaShield.driverOn then return end
	if not (C_Timer and C_Timer.After) then
		print("AS| ERROR: C_Timer.After missing - tick driver cannot start (run AS7, PLAN §12.10)")
		return
	end
	ArachnaphobiaShield.driverOn = true
	C_Timer.After(tickInterval, ArachnaphobiaShield.Tick)
end

-- Scan accessible native nameplates. Covers never handle pointer input.
function ArachnaphobiaShield.Update()
	if not ArachnaphobiaShield.ready or not ArachnaphobiaShieldSettings.enabled or ArachnaphobiaShield.hidden then return end
	ArachnaphobiaShield.coverageLimited = ArachnaphobiaShield.autoSuspended == true
	ArachnaphobiaShield.Cover.RetryReleases()
	if not ArachnaphobiaShield.autoSuspended then ArachnaphobiaShield.TrackTick() end
end

-- ------------------------------------------------------------ auto-track (M3.5)
-- The behaviour the owner asked for (2026-10-15): "as I walk toward spiders
-- it'll automatically check for the spider... and cover that moves and resizes
-- as the spider moves and resizes" - no target, no mouseover.
--
-- Why anchoring is the ONLY legal way to "move": the client refuses to say
-- where a nameplate is. AS15 (in game 2026-10-15):
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

function ArachnaphobiaShield.PlateFrameFor(token, idx)
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
-- throws (AS15). Both reads are access-guarded.
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

-- Near-field boost as a continuous function of the plate's apparent width
-- (v0.4.1; the /as near level config is retired). Returns 1.0 at/under
-- NEAR_RAMP_LO and smoothsteps to the nearBoost ceiling at/above
-- NEAR_RAMP_HI. The client clamps far plates at ~73 UI apparent width and
-- lets them grow to ~90 on approach (debug capture 2026-10-17), so the
-- ramp lives inside that real range: low knee 75 keeps far plates
-- unboosted (plate-proportional, small), high knee 85 sits below the
-- measured close band (87-113 UI, 2026-10-16 calibration), so the boost
-- is flat across the band the client clamps to - no cover "breathing" at
-- close range. Smoothstep keeps the slope zero at both knees, so the size
-- change starts and ends gently while approaching. History: knee 30
-- (v0.4.1) and 60 (v0.4.2) both sat below the client's 73 clamp and
-- boosted far plates (docs/NEAR-RAMP.md).
local NEAR_RAMP_LO, NEAR_RAMP_HI = 75, 85
local function nearBoostFor(apparent, ceiling)
	local b = type(ceiling) == "number" and ceiling or 3.0
	if b <= 1 then return 1.0 end
	if type(apparent) ~= "number" or apparent <= NEAR_RAMP_LO then return 1.0 end
	local x = (apparent - NEAR_RAMP_LO) / (NEAR_RAMP_HI - NEAR_RAMP_LO)
	if x >= 1 then return b end
	x = x * x * (3 - 2 * x)
	return 1 + (b - 1) * x
end

function ArachnaphobiaShield.OurScale()
	local ou = 1
	if UIParent and type(UIParent.GetEffectiveScale) == "function" then
		local v = A.Query(UIParent.GetEffectiveScale, UIParent)
		if type(v) == "number" and v > 0 then ou = v end
	end
	return ou
end

local function bindTrack(token, slot)
	ArachnaphobiaShield.track[token] = slot
	if slot ~= nil then ArachnaphobiaShield.trackSlots[slot] = token end
end

local function dropTrack(token)
	local slot = ArachnaphobiaShield.track[token]
	if slot ~= nil and ArachnaphobiaShield.trackSlots[slot] == token then
		ArachnaphobiaShield.trackSlots[slot] = nil
	end
	ArachnaphobiaShield.track[token] = nil
end

-- Cover calls this when it sacrifices a slot to make room: an entry that points
-- at a slot we no longer own has to go, otherwise the next tick adopts whatever
-- unit now owns that index.
if ArachnaphobiaShield.Cover then
	ArachnaphobiaShield.Cover.onEvict = function(slot)
		local token = ArachnaphobiaShield.trackSlots and ArachnaphobiaShield.trackSlots[slot]
		if token ~= nil then
			ArachnaphobiaShield.trackSlots[slot] = nil
			if ArachnaphobiaShield.track[token] == slot then ArachnaphobiaShield.track[token] = nil end
		end
	end
end

-- Release the entire nameplate-only pool, including deferred/orphaned slots.
function ArachnaphobiaShield.ClearTrack()
	ArachnaphobiaShield.Cover.ClearAll()
	ArachnaphobiaShield.track, ArachnaphobiaShield.trackSlots = {}, {}
end

function ArachnaphobiaShield.TrackTick()
	if ArachnaphobiaShield.autoSuspended or not ArachnaphobiaShieldSettings.enabled or ArachnaphobiaShield.hidden then return end
	local C, U = ArachnaphobiaShield.Cover, ArachnaphobiaShield.Units
	local s = ArachnaphobiaShieldSettings
	local t = ArachnaphobiaShield.track
	local grow = tonumber(s.trackScale) or 1.0
	local dropK = tonumber(s.drop) or 0.5
	local nearB = tonumber(s.nearBoost) or 2.6
	local grace = math.max(1, math.floor(((tonumber(s.trackRelease) or 0.5)
		/ tickInterval) + 0.5))
	local ourScale = ArachnaphobiaShield.OurScale()
	local live = {}
	local nearDbg = ArachnaphobiaShield.debug and {} or nil

	for i = 1, MAX_PLATES_SCAN do
		local token = "nameplate" .. i
		-- Read-only unit queries only (AS-verified: UnitExists / UnitIsVisible
		-- / UnitCreatureFamily all answer for nameplate tokens).
		if (not UnitExists or A.Query(UnitExists, token) == true)
			and (not UnitIsVisible or A.Query(UnitIsVisible, token) == true) then
			local isSpider = U.IsSpider(token)
			if isSpider then
				ArachnaphobiaShield.DeathWarning.Observe(token)
				local plate = ArachnaphobiaShield.PlateFrameFor(token, i)
				local slot = t[token]
				if plate then
					live[token] = true
					-- Adopt an entry only if its allocation and reverse map agree:
					-- pool indices are recycled between different units.
					if slot == nil or not C.IsAllocated(slot)
						or ArachnaphobiaShield.trackSlots[slot] ~= token then
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
						local boost = nearBoostFor(apparent, nearB)
						local size = plateSize(w, ps, ourScale, grow * boost, C.Size())
						if nearDbg then
							nearDbg[#nearDbg + 1] = token .. "="
								.. (apparent and ("%.1f"):format(apparent) or "?")
								.. ("*%.2f"):format(boost)
						end
						C.Resize(slot, size, size)
						-- Models hang BELOW their nameplate, hence the drop.
						if not C.PlaceTracked(slot, plate, size * dropK) then
							-- Parenting or anchoring may be refused by the client.
							-- Release the slot; do not leave an orphaned screen cover.
							C.Release(slot)
							dropTrack(token)
							ArachnaphobiaShield.trackFailures = (ArachnaphobiaShield.trackFailures or 0) + 1
							if ArachnaphobiaShield.trackFailures == 20 then
								ArachnaphobiaShield.autoSuspended = true
								print("AS| the client would not anchor covers - automatic covers paused; coverage limited (/as enable to retry)")
							end
						end
					end
				else
					ArachnaphobiaShield.coverageLimited = true
				end
			end
		end
	end

	-- Calibration readout (throttled to 1/second): the plate's apparent
	-- width per tracked spider plus the computed boost factor, for tuning
	-- the near ramp.
	if nearDbg and #nearDbg > 0 then
		local now = GetTime()
		if now - (ArachnaphobiaShield.nearDbgAt or 0) >= 1 then
			ArachnaphobiaShield.nearDbgAt = now
			table.sort(nearDbg)
			print("AS| near: " .. table.concat(nearDbg, " "))
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
function ArachnaphobiaShield.OnEnterWorld()
	if ArachnaphobiaShield.ready then return true end
	if not ArachnaphobiaShield.loadSnapshot.settingsPresent and not ArachnaphobiaShield.sawVariablesLoaded then
		return false
	end
	EnsureSettings() -- also migrate SavedVariables applied after script load
	local char = UnitName and UnitName("player")
	if not char then return false end -- still at character select
	ArachnaphobiaShield.char = char
	ArachnaphobiaShield.ready = true
	ArachnaphobiaShield.DeathWarning.Clear()
	-- Every cover is rebuilt from live nameplates; none are restored from disk.
	ArachnaphobiaShield.track = {}
	ArachnaphobiaShield.trackSlots = {}
	ArachnaphobiaShield.trackFailures = 0
	ArachnaphobiaShield.autoSuspended = false
	ArachnaphobiaShield.tickErrors = 0
	ArachnaphobiaShield.Cover.Init()
	ArachnaphobiaShield.Cover.ClearAll()
	ArachnaphobiaShield.Cover.ApplyStyle()
	ArachnaphobiaShield.StartDriver()
	return true
end

-- Restore when we can, otherwise ask again for ~10 s (C_Timer.After is proven
-- present; the no-op in the offline harness makes the retry inert there).
function ArachnaphobiaShield.RetryEnterWorld()
	if ArachnaphobiaShield.ready then return end
	if ArachnaphobiaShield.OnEnterWorld() then return end
	ArachnaphobiaShield.retries = (ArachnaphobiaShield.retries or 0) + 1
	if ArachnaphobiaShield.retries >= 20 then return end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, ArachnaphobiaShield.RetryEnterWorld)
	end
end

local function EnsureEventFrame()
	if ArachnaphobiaShield.eventFrame then return end
	local f = CreateFrame("Frame")
	-- AS6-confirmed events only (RegisterEvent errors on unknown names)
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
		-- AS10: this client's native SetScript calls handlers with NO
		-- arguments — event data arrives via the `this`/`event`/`arg1`..
		-- globals (proven by Spoken's Compat.lua override). `evt` covers
		-- modern-style clients; the bare global covers this one. A
		-- parameter named `event` would shadow the global — do not rename.
		local ev = evt or event
		local payload = readablePayload(unitArg, arg1)
		if ev == "VARIABLES_LOADED" then
			ArachnaphobiaShield.sawVariablesLoaded = true
			ArachnaphobiaShield.RetryEnterWorld()
		elseif ev == "PLAYER_ENTERING_WORLD" then
			ArachnaphobiaShield.DeathWarning.Clear()
			ArachnaphobiaShield.RetryEnterWorld()
		elseif ev == "NAME_PLATE_UNIT_REMOVED" then
			local unit = payload
			if A.CanRead(unit) and type(unit) == "string" then
				ArachnaphobiaShield.DeathWarning.CheckUnit(unit)
				ArachnaphobiaShield.DeathWarning.ForgetToken(unit)
				local slot = ArachnaphobiaShield.track[unit]
				if slot then ArachnaphobiaShield.Cover.Release(slot); dropTrack(unit) end
			end
		elseif ev == "NAME_PLATE_UNIT_ADDED" and ArachnaphobiaShield.ready
			and ArachnaphobiaShieldSettings.enabled and not ArachnaphobiaShield.hidden then
			ArachnaphobiaShield.Refresh()
		elseif ev == "UNIT_HEALTH" or ev == "UNIT_FLAGS" then
			ArachnaphobiaShield.DeathWarning.CheckUnit(payload)
		elseif ev == "UNIT_DIED" then
			ArachnaphobiaShield.DeathWarning.OnDeath(payload)
		end
	end)
	ArachnaphobiaShield.eventFrame = f
end
EnsureEventFrame()

-- If we load already in-world (e.g. /reload in character) AND the settings
-- were already applied at script load, enter now. Otherwise PLAYER_ENTERING_WORLD
-- and VARIABLES_LOADED above cover it, ensuring migration sees the real save.
if UnitName and UnitName("player") and ArachnaphobiaShield.loadSnapshot.settingsPresent then
	ArachnaphobiaShield.OnEnterWorld()
end
