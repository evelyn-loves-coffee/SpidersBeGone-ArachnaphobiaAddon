-- Cover choices are data, so additional supplied artwork needs no new UI logic.
SBeGone = SBeGone or {}
local P = {}
SBeGone.Appearance = P
local ROOT = "Interface\\AddOns\\SpidersBeGone\\"
P.PRESETS = {
	{ id = "fox", label = "Fox", path = ROOT .. "cover.tga" },
	{ id = "red", label = "Muted red squircle", path = ROOT .. "cover-red.tga" },
	{ id = "blue", label = "Muted blue squircle", path = ROOT .. "cover-blue.tga" },
	{ id = "sage", label = "Sage green squircle", path = ROOT .. "cover-sage.tga" },
	{ id = "charcoal", label = "Plain charcoal", path = ROOT .. "cover-charcoal.tga" },
}

function P.Find(id)
	for _, preset in ipairs(P.PRESETS) do
		if preset.id == id then return preset end
	end
end

-- Textures are local game assets. A Windows path or URL cannot be loaded by
-- SetTexture. Do not inspect the filesystem or execute anything from a path.
function P.CustomPath(value)
	if not SBeGone.Access.CanRead(value) or type(value) ~= "string" then return nil end
	local path = value:match("^%s*(.-)%s*$"):gsub("/", "\\")
	if path:sub(1, 1) == '"' and path:sub(-1) == '"' then path = path:sub(2, -2) end
	if #path > 240 or path:find("[%c:]") or path:find("..", 1, true) then return nil end
	if not path:lower():match("^interface\\addons\\.+%.tga$") then return nil end
	if path:find("\\\\", 1, true) then return nil end
	return path
end

function P.Normalize(settings)
	local path = P.CustomPath(settings.customCover)
	settings.customCover = path or ""
	local id = type(settings.coverStyle) == "string" and settings.coverStyle:lower() or "fox"
	if not P.Find(id) and not (id == "custom" and path) then id = "fox" end
	settings.coverStyle = id
end

function P.Current()
	local s = SBeGoneSettings or {}
	if s.coverStyle == "custom" then
		local path = P.CustomPath(s.customCover)
		if path then return { id = "custom", label = "Custom image", path = path } end
	end
	return P.Find(s.coverStyle) or P.PRESETS[1]
end

function P.Select(id, customPath)
	id = type(id) == "string" and id:lower() or ""
	local path
	if id == "custom" then
		path = P.CustomPath(customPath or (SBeGoneSettings or {}).customCover)
		if not path then
			return false, "Use a local .tga path, e.g. Interface\\AddOns\\MyCovers\\flower.tga"
		end
	elseif not P.Find(id) then
		return false, "Choose fox / red / blue / sage / charcoal / custom"
	end
	SBeGoneSettings = SBeGoneSettings or {}
	SBeGoneSettings.coverStyle = id
	if path then SBeGoneSettings.customCover = path end
	if SBeGone.Cover and SBeGone.Cover.inited then SBeGone.Cover.ApplyStyle() end
	if SBeGone.Config then SBeGone.Config.Refresh() end
	return true, "Cover: " .. P.Current().label
end

function P.Command(args)
	local id, path = (args or ""):match("^%s*(%S+)%s*(.-)%s*$")
	if not id then
		print("SBG| Cover: " .. P.Current().label .. " - /spider config to choose")
		print("SBG| /spider cover fox / red / blue / sage / charcoal / custom <local .tga path>")
		return
	end
	local ok, message = P.Select(id, path ~= "" and path or nil)
	print("SBG| " .. message)
	return ok
end
