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
SBeGone.version = "0.2.2"

SBeGone.hidden = nil  -- panic-hide seam (M4); true hides every cover
SBeGone.ready = false -- true once a character's covers are restored

-- TEMP M3 diagnostic (SBG13): prints one "SBG| restore:" line per restore so
-- the SavedVariables load order is readable in chat. Drop once the restore
-- path is confirmed on the release client.
SBeGone.debug = true

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
	namePatterns = SBeGone.Units and SBeGone.Units.NAME_PATTERNS
		or { "Spider", "Gloomweaver" },
	extraNames = {},
	requireHostile = false,
	minLevel = 1,
	maxLevel = 99,
	covers = {}, -- per character: [char] = { {x,y,w,h,kind}, ... }
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
	elseif first == "help" then
		-- No '|' chars in chat text: the WoW chat filter eats chat-control
		-- sequences like |t / |h (SBG11) — use ' / ' separators.
		print("SBG| /spider [on / off / toggle / clear / parks N / help] - bare /spider = selftest")
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
	local major, minor, patch, build = GetBuildInfo()
	print(("SBG| v%s | build %s %s %s | Lua %s"):format(
		SBeGone.version, tostring(major), tostring(minor), tostring(patch), tostring(_VERSION)))
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
	print(("SBG| enabled=%s | interface=%s | char=%s | driver=%s | sticky=%s"):format(
		tostring(s.enabled), tostring(build), tostring(SBeGone.char),
		tostring(SBeGone.driverOn), tostring(s.stickyCovers)))
	print(("SBG| covers shown=%d/%d | saved=%d | size=%s"):format(
		SBeGone.Cover.ShownCount(), SBeGone.Cover.MAX, saved, tostring(s.coverSize)))
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
			print("SBG| tick error: " .. tostring(err))
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
			h.slot = SBeGone.Cover.Allocate("hover", cx, cy)
			h.key = key
		else
			SBeGone.Cover.Place(h.slot, cx, cy)
		end
	else
		if h.slot ~= nil then
			if not sticky then
				SBeGone.Cover.Release(h.slot)
			end
			-- sticky: the cover simply stays where it is
			h.slot = nil
			h.key = nil
			SBeGone.Cover.Save()
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
	SBeGone.hover = { slot = nil, key = nil }
	SBeGone.Cover.Restore(char)
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
