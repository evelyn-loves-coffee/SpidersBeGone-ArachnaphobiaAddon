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
SBeGone.version = "0.2.0"

SBeGone.hidden = nil  -- panic-hide seam (M4); true hides every cover
SBeGone.ready = false -- true once a character's covers are restored

-- ---------------------------------------------------------------- settings
local DEFAULTS = {
	version = 1,
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
	elseif first == "help" then
		print("SBG| /spider [on|off|toggle|clear|help] - bare /spider = selftest")
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
	if SBeGone.char and type(s.covers) == "table"
		and type(s.covers[SBeGone.char]) == "table" then
		for _ in ipairs(s.covers[SBeGone.char]) do saved = saved + 1 end
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
	if SBeGone.ready and SBeGoneSettings.enabled and not SBeGone.hidden then
		SBeGone.Update()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(tickInterval, SBeGone.Tick)
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
function SBeGone.OnEnterWorld()
	if SBeGone.ready then return end
	local char = UnitName and UnitName("player")
	if not char then return end -- still at character select
	SBeGone.char = char
	SBeGone.ready = true
	SBeGone.hover = { slot = nil, key = nil }
	SBeGone.Cover.Restore(char)
	SBeGone.StartDriver()
end

local function EnsureEventFrame()
	if SBeGone.eventFrame then return end
	local f = CreateFrame("Frame")
	-- SBG6-confirmed events only (RegisterEvent errors on unknown names)
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			SBeGone.OnEnterWorld()
		end
	end)
	SBeGone.eventFrame = f
end
EnsureEventFrame()

-- If we load already in-world (e.g. /reload in character),
-- PLAYER_ENTERING_WORLD will not fire again — enter now.
if UnitName and UnitName("player") then
	SBeGone.OnEnterWorld()
end
