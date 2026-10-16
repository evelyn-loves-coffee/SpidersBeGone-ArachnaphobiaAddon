-- Nameplate-only cover pool. Every cover is permanently click-through.
-- Frames stay hidden until attached to an accessible native nameplate.
SBeGone = SBeGone or {}

local C = {}
SBeGone.Cover = C

C.MAX = 24
C.ART_PATH = "Interface\\AddOns\\SpidersBeGone\\cover.tga"
C.BACKDROP = { 14 / 255, 19 / 255, 36 / 255 }

C.pool = {}  -- [1..MAX] = nameplate-only frames; no saved screen positions
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
C.CreateTexture = makeTexture

local function makeFrame()
	local f = CreateFrame("Frame")
	f:SetParent(UIParent)
	f:SetFrameStrata("HIGH")
	f:EnableMouse(false)
	local base, art = makeTexture(f), makeTexture(f)
	if base then base:SetAllPoints() end
	if art then art:SetAllPoints() end
	f:Hide()
	return f, base, art
end

function C.Init()
	if C.inited then return end
	C.inited = true
	C.pool, C.free = {}, {}
	for i = 1, C.MAX do
		local f, base, art = makeFrame()
		C.pool[i] = { frame = f, base = base, art = art,
			anchored = false, anchoredDrop = 0, miss = 0 }
		C.free[#C.free + 1] = i
	end
	C.ApplyStyle()
end

function C.Size()
	local s = SBeGoneSettings
	return (type(s) == "table" and type(s.coverSize) == "number") and s.coverSize or 96
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

-- Some client builds return no value on success; only false or an error is
-- a detectable failure. A syntactically valid missing file may still show a
-- placeholder, so custom choices must be checked in the preview in game.
function C.PaintArt(tex, path)
	local ok, result = pcall(tex.SetTexture, tex, path)
	local loaded = ok and result ~= false
	if not loaded then pcall(tex.SetTexture, tex, C.ART_PATH) end
	setTint(tex, 1, 1, 1, 1)
	return loaded
end

-- Preserve the supplied artwork's colors. Old color/opacity settings must
-- not tint the fox or reveal a spider through the cover. The imported TGA
-- is also opaque, so coverage does not depend on the fallback texture.
function C.ApplyStyle()
	local path = SBeGone.Appearance.Current().path
	C.textureFailed = false
	for i = 1, C.MAX do
		local slot = C.pool[i]
		if slot.base then
			local ok, result = pcall(slot.base.SetTexture, slot.base, C.BACKDROP[1], C.BACKDROP[2], C.BACKDROP[3], 1)
			if not ok or result == false then C.textureFailed = true end
		end
		if slot.art then
			if not C.PaintArt(slot.art, path) then C.textureFailed = true end
		end
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
	-- Epsilon: auto-track re-sizes every tick from the plate's apparent width;
	-- skip the work when it barely moved.
	if type(w) == "number" and type(h) == "number"
		and type(slot.w) == "number" and type(slot.h) == "number"
		and math.abs(slot.w - w) < 1 and math.abs(slot.h - h) < 1 then
		return
	end
	slot.w, slot.h = w, h
	setSize(slot.frame, w, h)
end

-- Detach only OUR hidden frame through normal APIs. Do not measure or
-- reposition it on the screen; a refused operation quarantines this slot.
function C.Detach(i)
	local slot = C.pool[i]
	if not slot then return false end
	if not pcall(slot.frame.EnableMouse, slot.frame, false) then return false end
	if not pcall(slot.frame.SetParent, slot.frame, UIParent) then
		SBeGone.coverageLimited = true
		return false
	end
	if slot.frame.ClearAllPoints and not pcall(slot.frame.ClearAllPoints, slot.frame) then return false end
	slot.anchored, slot.anchoredPlate, slot.anchoredDrop = false, nil, 0
	return true
end

-- Native parenting carries movement and perspective between polling ticks.
function C.PlaceTracked(i, plate, dropY)
	if not SBeGoneSettings.enabled or SBeGone.hidden then return false end
	local slot = C.pool[i]
	if not slot or not slot.allocated or slot.pendingRelease or not SBeGone.Access.FrameUsable(plate) or not slot.frame.SetPoint then return false end
	local mouseOK = pcall(slot.frame.EnableMouse, slot.frame, false)
	if not mouseOK then return false end
	dropY = dropY or 0
	-- Re-anchor only when the target changed or the offset moved >= 1 UI unit
	-- (epsilon policy) — 10 Hz x 24 slots stays trivial.
	if slot.anchored and slot.anchoredPlate == plate
		and math.abs((slot.anchoredDrop or 0) - dropY) < 1 then
		if not slot.frame:IsShown() then slot.frame:Show() end
		return true
	end
	if slot.frame.ClearAllPoints then
		local clearOK = pcall(slot.frame.ClearAllPoints, slot.frame)
		if not clearOK then return false end
	end
	local parentOK = pcall(slot.frame.SetParent, slot.frame, plate)
	if not parentOK then return false end
	-- Track attachment immediately, including when the following anchor is
	-- rejected. Cleanup must never mistake a plate child for a screen frame.
	slot.anchored = true
	slot.anchoredPlate = plate
	local ok = pcall(slot.frame.SetPoint, slot.frame, "CENTER", plate, "CENTER", 0, -dropY)
	if not ok then
		return false
	end
	slot.anchored = true
	slot.anchoredPlate = plate
	slot.anchoredDrop = dropY
	if not slot.frame:IsShown() then slot.frame:Show() end
	return true
end

-- Recycle the oldest allocation if necessary; blocked slots stay excluded.
local function oldestAllocated()
	local oldest
	for i, slot in ipairs(C.pool) do
		if slot.allocated and (not oldest or slot.seq < C.pool[oldest].seq) then oldest = i end
	end
	return oldest
end

function C.Allocate()
	local i
	for _ = 1, C.MAX do
		if #C.free > 0 then i = table.remove(C.free); break end
		local victim = oldestAllocated()
		if not victim then return nil end
		if C.onEvict then C.onEvict(victim) end
		C.Release(victim)
	end
	if not i then
		if #C.free == 0 then return nil end
		i = table.remove(C.free)
	end
	local slot = C.pool[i]
	if not C.Detach(i) then
		slot.pendingRelease, slot.anchored = true, true
		return nil
	end
	C.seq = (C.seq or 0) + 1
	slot.seq, slot.miss, slot.allocated = C.seq, 0, true
	C.Resize(i, C.Size(), C.Size())
	return i -- still hidden, with no screen anchor
end

function C.IsAllocated(i)
	local slot = C.pool[i]
	return slot ~= nil and slot.allocated == true
end

function C.Release(i)
	local slot = C.pool[i]
	if not slot then return false end
	if not slot.allocated and not slot.pendingRelease then return true end
	pcall(slot.frame.Hide, slot.frame)
	local detached = C.Detach(i)
	slot.pendingRelease, slot.allocated = not detached, false
	if not detached then slot.anchored = true end
	if detached then C.free[#C.free + 1] = i end
	return detached
end

function C.RetryReleases()
	if not C.inited then return end
	for i, slot in ipairs(C.pool) do
		if slot.pendingRelease then C.Release(i) end
	end
end

function C.HideAll()
	if not C.inited then return end
	for _, slot in ipairs(C.pool) do pcall(slot.frame.Hide, slot.frame) end
end

function C.ClearAll()
	if not C.inited then return end
	C.free = {}
	for i, slot in ipairs(C.pool) do
		pcall(slot.frame.Hide, slot.frame)
		local detached = C.Detach(i)
		slot.pendingRelease, slot.allocated = not detached, false
		if not detached then slot.anchored = true end
		if detached then C.free[#C.free + 1] = i end
	end
end

function C.ShownCount()
	if not C.inited then return 0 end
	local n = 0
	for _, slot in ipairs(C.pool) do
		if SBeGone.Access.Query(slot.frame.IsShown, slot.frame) == true then n = n + 1 end
	end
	return n
end
