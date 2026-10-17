-- A small, lazy-created cover picker using addon-owned frames only.
ArachnaphobiaShield = ArachnaphobiaShield or {}
local O = {}
ArachnaphobiaShield.Config = O
local P, C = ArachnaphobiaShield.Appearance, ArachnaphobiaShield.Cover

local function region(parent, width, height, anchor, relative, x, y, kind)
	local f = CreateFrame(kind or "Frame")
	f:SetParent(parent)
	f:SetWidth(width)
	f:SetHeight(height)
	f:SetPoint(anchor, parent, relative, x, y)
	f:EnableMouse(kind == "Button" or kind == "EditBox")
	f:Show()
	return f
end

-- This client has only proven the string-path SetTexture (Spoken renders
-- every visible texture from a file; the numeric SetTexture(r, g, b, a) form
-- opened here as a silent no-op, which is why the picker showed no
-- background). Solid colors therefore ship as tiny TGA files.
local ASSET = {
	bg = "Interface\\AddOns\\ArachnaphobiaShield\\picker-bg.tga",
	btn = "Interface\\AddOns\\ArachnaphobiaShield\\picker-btn.tga",
	btnSelected = "Interface\\AddOns\\ArachnaphobiaShield\\picker-btn-sel.tga",
	field = "Interface\\AddOns\\ArachnaphobiaShield\\picker-field.tga",
	checker = "Interface\\AddOns\\ArachnaphobiaShield\\preview-checker.tga",
}

local function textureOn(frame)
	local tex = C.CreateTexture(frame)
	if not tex then error("texture API unavailable") end
	tex:SetAllPoints()
	return tex
end

local function solid(frame, file)
	local tex = textureOn(frame)
	tex:SetTexture(file)
	return tex
end

local function text(frame, value, size)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetAllPoints(frame)
	if label.SetFont then pcall(label.SetFont, label, "Fonts\\FRIZQT__.TTF", size or 14, "") end
	if label.SetTextColor then pcall(label.SetTextColor, label, 0.95, 0.95, 0.98, 1) end
	label:SetText(value)
	return label
end

local function button(parent, caption, width, height, anchor, relative, x, y, onClick)
	local f = region(parent, width, height, anchor, relative, x, y, "Button")
	f.background = solid(f, ASSET.btn)
	f.label = text(f, caption)
	-- A closure works with both native no-argument scripts and modern scripts.
	f:SetScript("OnClick", onClick)
	return f
end

function O.RefreshPreview()
	if not O.frame then return end
	local preset = P.Current()
	local loaded = C.PaintCover(O.previewBase, O.preview, preset)
	O.status:SetText("Selected: " .. preset.label .. "\n"
		.. (loaded and "Changes save automatically." or "Image failed to load; showing the fox."))
end

function O.Refresh()
	if not O.frame then return end
	local preset = P.Current()
	for id, control in pairs(O.buttons) do
		if id == preset.id then
			control.background:SetTexture(ASSET.btnSelected)
		else
			control.background:SetTexture(ASSET.btn)
		end
	end
	O.RefreshPreview()
	O.input:SetText((ArachnaphobiaShieldSettings or {}).customCover or "")
end

local function applyCustom()
	local ok, message = P.Select("custom", O.input:GetText())
	if not ok then O.status:SetText(message) end
	if O.input.ClearFocus then pcall(O.input.ClearFocus, O.input) end
end

function O.Close()
	if O.input and O.input.ClearFocus then pcall(O.input.ClearFocus, O.input) end
	if O.frame then O.frame:Hide() end
end

local function create()
	local f = CreateFrame("Frame")
	O.creating = f -- lets Open hide a partially built panel on an API failure
	f:SetParent(UIParent)
	f:SetFrameStrata("HIGH")
	-- Keep the corpse warning (HIGH / level 100) above this editor.
	if f.SetFrameLevel then pcall(f.SetFrameLevel, f, 50) end
	f:SetWidth(640)
	f:SetHeight(480)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:EnableMouse(true)
	f:Hide()
	O.background = solid(f, ASSET.bg)
	text(region(f, 480, 30, "TOPLEFT", "TOPLEFT", 16, -12), "Arachnaphobia Shield - Covers", 19)
	text(region(f, 600, 26, "TOPLEFT", "TOPLEFT", 20, -44), "Choose the cover image that feels comfortable for you.")
	button(f, "Close", 70, 28, "TOPRIGHT", "TOPRIGHT", -16, -14, O.Close)
	O.buttons = {}
	for index, preset in ipairs(P.PRESETS) do
		local id = preset.id
		O.buttons[id] = button(f, preset.label, 230, 36, "TOPLEFT", "TOPLEFT", 20, -80 - (index - 1) * 44,
			function() P.Select(id) end)
	end
	O.buttons.custom = button(f, "Custom image", 230, 36, "TOPLEFT", "TOPLEFT", 20, -80 - #P.PRESETS * 44,
		function() applyCustom() end)
	-- Checker, backing and art live on three stacked single-texture frames:
	-- one texture per frame is the layout every working frame in this addon
	-- already follows, while three textures on one frame is unproven here.
	local preview = {}
	for _, name in ipairs({ "checker", "base", "art" }) do
		preview[name] = region(f, 256, 256, "TOPRIGHT", "TOPRIGHT", -35, -80)
	end
	O.previewChecker = solid(preview.checker, ASSET.checker)
	O.previewBase = textureOn(preview.base)  -- PaintCover fills both below
	O.preview = textureOn(preview.art)
	O.previewFrames = preview
	O.status = text(region(f, 340, 42, "TOPRIGHT", "TOPRIGHT", -15, -342), "")
	text(region(f, 600, 24, "TOPLEFT", "TOPLEFT", 20, -384), "Custom image: local addon texture path", 13)
	O.input = region(f, 470, 28, "TOPLEFT", "TOPLEFT", 20, -411, "EditBox")
	O.input.background = solid(O.input, ASSET.field)
	O.input:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
	if O.input.SetTextColor then pcall(O.input.SetTextColor, O.input, 0.95, 0.95, 0.98, 1) end
	O.input:SetAutoFocus(false)
	if O.input.SetMaxLetters then pcall(O.input.SetMaxLetters, O.input, 240) end
	if O.input.SetTextInsets then pcall(O.input.SetTextInsets, O.input, 5, 5, 0, 0) end
	O.input:SetScript("OnEnterPressed", applyCustom)
	O.input:SetScript("OnEscapePressed", O.Close)
	button(f, "Use image", 120, 28, "TOPRIGHT", "TOPRIGHT", -20, -411, applyCustom)
	text(region(f, 600, 22, "BOTTOMLEFT", "BOTTOMLEFT", 20, 5), "Covers stay click-through. Close this window to return to play.", 12)
	O.frame, O.creating = f, nil
end

function O.Open()
	if not O.unavailable then
		local ok = pcall(function()
			if not O.frame then create() end
			O.Refresh()
			O.frame:Show()
		end)
		if ok then return true end
		if O.creating then pcall(O.creating.Hide, O.creating) end
		if O.frame then pcall(O.frame.Hide, O.frame) end
		O.frame, O.creating, O.unavailable = nil, nil, true
	end
	print("AS| Cover window unavailable on this client - choose with /as cover <choice>")
	P.Command("")
	return false
end
