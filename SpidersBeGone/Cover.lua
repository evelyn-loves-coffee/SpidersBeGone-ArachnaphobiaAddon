-- Spiders Be Gone — Cover.lua: the 24-slot cover frame pool (M3).
-- Sticky hover covers and parkable shields share this pool (FIFO: when full,
-- a new cover evicts the oldest). Covers are draggable (SetMovable) and their
-- positions persist per character in SBeGoneSettings.covers[<char>].
SBeGone = SBeGone or {}

local C = {}
SBeGone.Cover = C

C.MAX = 24
C.ART_PATH = "Interface\\AddOns\\SpidersBeGone\\cover.tga"

C.pool = {}  -- [1..MAX] = { frame, base, art, x, y, w, h, kind }
C.queue = {} -- allocated slot indices, in allocation order (FIFO)
C.free = {}  -- free slot indices

-- This client's native CreateTexture is NOT the classic one. Its usage
-- string is "self:CreateTexture(params)" and it rejects the classic
-- "BACKGROUND" layer (in-game error 2026-10-14, SBG8: "bad argument #3 to
-- 'CreateTexture'"), while the working Spoken addon on this client uses the
-- (nil, "ARTWORK") form. So: try the proven layer first, pcall-guarded.
local LAYER_CANDIDATES = { "ARTWORK", "ART", "BACKGROUND", "MEDIUM", "LOW", "HIGH", "HIGHLIGHT" }
local function makeTexture(frame)
	for _, layer in ipairs(LAYER_CANDIDATES) do
		local ok, tex = pcall(frame.CreateTexture, frame, nil, layer)
		if ok and tex then
			return tex
		end
	end
	local ok, tex = pcall(frame.CreateTexture, frame)
	if ok and tex then
		return tex
	end
	return nil
end

-- A cover frame: the shield disc (draggable), the TGA art on top, and a
-- solid fallback disc under it (same tint, fully inside the TGA's opaque
-- core — only visible if cover.tga is missing). Both textures get the same
-- working layer; base is created first so art draws over it.
local function makeFrame()
	local f = CreateFrame("Frame")
	f:SetParent(UIParent)
	f:SetFrameStrata("HIGH")
	f:EnableMouse(true)
	f:SetMovable(true)
	local base = makeTexture(f)
	local art = makeTexture(f)
	if art then art:SetAllPoints() end
	f:Hide()
	return f, base, art
end

function C.Init()
	if C.inited then return end
	C.inited = true
	C.pool = {}
	C.queue = {}
	C.free = {}
	for i = 1, C.MAX do
		local f, base, art = makeFrame()
		C.pool[i] = { frame = f, base = base, art = art, kind = "park" }
		C.free[#C.free + 1] = i
	end
	C.Clamp()
	C.ApplyStyle()
end

function C.Size()
	local s = SBeGoneSettings
	return (type(s) == "table" and type(s.coverSize) == "number") and s.coverSize or 96
end

-- Native screen clamp for clients that still have it. SetClampRect is
-- ABSENT on this client (SBG9: in-game "attempt to call a nil value");
-- the real keep-on-screen guarantee is the soft clamp in C.SyncDrags.
function C.Clamp()
	local sw, sh
	if GetEffectiveScreenInfo then
		sw, sh = GetEffectiveScreenInfo()
	end
	if type(sw) ~= "number" then sw, sh = 1920, 1080 end
	for i = 1, C.MAX do
		pcall(C.pool[i].frame.SetClampRect, C.pool[i].frame, 0, sw, 0, sh)
	end
end

-- Vertex tint with a pcall fallback for clients whose SetVertexColor
-- rejects the optional 4th (alpha) argument.
local function setTint(tex, r, g, b, a)
	local ok = pcall(tex.SetVertexColor, tex, r, g, b, a)
	if not ok then
		ok = pcall(tex.SetVertexColor, tex, r, g, b)
		if ok then pcall(tex.SetVertexAlpha, tex, a) end
	end
end

-- Tint every cover from settings (red-ish patch, per owner preference).
function C.ApplyStyle()
	local s = SBeGoneSettings or {}
	local col = { 0.55, 0.12, 0.12 }
	if type(s.color) == "table" and #s.color == 3 then
		col = s.color
	end
	local a = (type(s.opacity) == "number") and s.opacity or 0.85
	for i = 1, C.MAX do
		local slot = C.pool[i]
		if slot.base then
			-- base: small solid disc, fully hidden under the TGA's opaque
			-- core; becomes the visible fallback if cover.tga is ever
			-- missing. SetTexture(r,g,b,a) numeric form = the modern
			-- signature used by Spoken on this client.
			slot.base:SetTexture(col[1], col[2], col[3], a)
		end
		if slot.art then
			slot.art:SetTexture(C.ART_PATH)
			setTint(slot.art, col[1], col[2], col[3], a)
		end
	end
end

-- Place a cover centered at (x, y) in UIParent/BOTTOMLEFT UI coordinates —
-- the same space GetCursorPosition and GetPoint use.
-- Epsilon: skip the SetPoint when the cursor moved < 1 UI pixel (PLAN §3.3).
function C.Place(i, x, y)
	local slot = C.pool[i]
	if slot.frame:IsShown() and type(slot.x) == "number"
		and math.abs(slot.x - x) < 1 and math.abs(slot.y - y) < 1 then
		return
	end
	slot.x, slot.y = x, y
	slot.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	if not slot.frame:IsShown() then
		slot.frame:Show()
	end
end

-- SetSize is absent on old clients (Spoken shims it with SetWidth +
-- SetHeight, both proven present) — fall back to those.
local function setSize(frame, w, h)
	local ok = pcall(frame.SetSize, frame, w, h)
	if not ok then
		pcall(frame.SetWidth, frame, w)
		pcall(frame.SetHeight, frame, h)
	end
end

function C.Resize(i, w, h)
	local slot = C.pool[i]
	slot.w, slot.h = w, h
	setSize(slot.frame, w, h)
	if slot.base then
		local inset = math.floor(w * 0.35)
		slot.base:SetPoint("TOPLEFT", slot.frame, "TOPLEFT", inset, inset)
		slot.base:SetPoint("BOTTOMRIGHT", slot.frame, "BOTTOMRIGHT", -inset, -inset)
	end
end

-- Take a slot from the pool (free list first, else evict the oldest = FIFO).
function C.Allocate(kind, x, y)
	local i
	if #C.free > 0 then
		i = table.remove(C.free)
	else
		i = table.remove(C.queue, 1)
		C.pool[i].frame:Hide()
	end
	local slot = C.pool[i]
	C.queue[#C.queue + 1] = i
	slot.kind = kind
	slot.x, slot.y = nil, nil
	C.Resize(i, C.Size(), C.Size())
	C.Place(i, x, y)
	return i
end

-- Return a slot to the pool (cover disappears).
function C.Release(i)
	local slot = C.pool[i]
	slot.frame:Hide()
	slot.x, slot.y = nil, nil
	for q = #C.queue, 1, -1 do
		if C.queue[q] == i then
			table.remove(C.queue, q)
			break
		end
	end
	C.free[#C.free + 1] = i
end

function C.HideAll()
	if not C.inited then return end
	for i = 1, C.MAX do
		C.pool[i].frame:Hide()
	end
end

function C.ClearAll()
	C.queue = {}
	C.free = {}
	for i = 1, C.MAX do
		local slot = C.pool[i]
		slot.frame:Hide()
		slot.x, slot.y = nil, nil
		C.free[#C.free + 1] = i
	end
end

function C.ShownCount()
	if not C.inited then return 0 end
	local n = 0
	for i = 1, C.MAX do
		if C.pool[i].frame:IsShown() then n = n + 1 end
	end
	return n
end

-- Covers are SetMovable frames: when the user drags one, adopt the new
-- position into pool state and persist it (called every tick).
-- Soft clamp: SetClampRect is absent on this client (SBG9), so keep each
-- cover's center inside the screen ourselves — a cover can never be
-- dragged away and lost.
function C.SyncDrags()
	if not C.inited then return end
	local sw, sh
	if GetEffectiveScreenInfo then sw, sh = GetEffectiveScreenInfo() end
	if type(sw) ~= "number" then sw, sh = 1920, 1080 end
	local changed = false
	for i = 1, C.MAX do
		local slot = C.pool[i]
		if slot.frame:IsShown() and type(slot.x) == "number" then
			local _, _, x, y = slot.frame:GetPoint(0, UIParent, "BOTTOMLEFT")
			if type(x) == "number"
				and (math.abs(x - slot.x) > 0.5 or math.abs(y - slot.y) > 0.5) then
				local liveX, liveY = x, y
				if x < 0 then x = 0 elseif x > sw then x = sw end
				if y < 0 then y = 0 elseif y > sh then y = sh end
				slot.x, slot.y = x, y
				changed = true
				if math.abs(liveX - x) > 0.5 or math.abs(liveY - y) > 0.5 then
					slot.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
				end
			end
		end
	end
	if changed then
		C.Save()
	end
end

-- Persist the current pool for the current character. An empty (but present)
-- list means "intentionally cleared" — Restore() will not respawn defaults.
function C.Save()
	local char = SBeGone.char
	local s = SBeGoneSettings
	if not char or not s then return end
	if type(s.covers) ~= "table" then s.covers = {} end
	local list = {}
	for _, i in ipairs(C.queue) do
		local slot = C.pool[i]
		if slot.frame:IsShown() and type(slot.x) == "number" then
			list[#list + 1] = { x = slot.x, y = slot.y, w = slot.w, h = slot.h, kind = slot.kind }
		end
	end
	s.covers[char] = list
end

-- Default pre-park layout: a row of shields near the top of the screen.
local function DefaultParkPos(n, size)
	local sw, sh
	if GetEffectiveScreenInfo then
		sw, sh = GetEffectiveScreenInfo()
	end
	if type(sw) ~= "number" then sw, sh = 1920, 1080 end
	local gap = 24
	return 100 + (n - 1) * (size + gap), sh - 80
end

-- Rebuild the pool for a character: saved covers first, then — only on the
-- character's very first run (no saved list at all) — the default pre-parked
-- shields. Persists the result.
function C.Restore(char)
	C.Init()
	SBeGone.char = char
	C.ClearAll()
	local s = SBeGoneSettings or {}
	local byChar = (type(s.covers) == "table") and s.covers or {}
	local saved = byChar[char]
	local firstRun = (saved == nil)
	if firstRun then saved = {} end
	for _, e in ipairs(saved) do
		if type(e) == "table" and type(e.x) == "number" and type(e.y) == "number" then
			local i = C.Allocate(e.kind or "hover", e.x, e.y)
			local w = (type(e.w) == "number") and e.w or C.Size()
			local h = (type(e.h) == "number") and e.h or w
			C.Resize(i, w, h)
		end
	end
	if firstRun then
		local parks = (type(s.parkCount) == "number") and s.parkCount or 8
		for n = 1, parks do
			local x, y = DefaultParkPos(n, C.Size())
			C.Allocate("park", x, y)
		end
	end
	C.Save()
end
