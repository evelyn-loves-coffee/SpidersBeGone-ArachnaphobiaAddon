-- Cover choices are data, so additional supplied artwork needs no new UI logic.
ArachnaphobiaShield = ArachnaphobiaShield or {}
local P = {}
ArachnaphobiaShield.Appearance = P
local ROOT = "Interface\\AddOns\\ArachnaphobiaShield\\"
-- Custom artwork lives in the addon's own Custom folder. It is git-ignored
-- (ArachnaphobiaShield/Custom/) and never packaged (tools/package_addon.py ships
-- an explicit file list), so personal images stay out of releases.
P.CUSTOM_ROOT = "Interface\\AddOns\\ArachnaphobiaShield\\Custom\\"
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
-- Only the addon's own Custom folder is accepted, so the documented path and
-- the validated path are the same place.
function P.CustomPath(value)
	if not ArachnaphobiaShield.Access.CanRead(value) or type(value) ~= "string" then return nil end
	local path = value:match("^%s*(.-)%s*$"):gsub("/", "\\")
	if path:sub(1, 1) == '"' and path:sub(-1) == '"' then path = path:sub(2, -2) end
	if #path > 240 or path:find("[%c:]") or path:find("..", 1, true) then return nil end
	if path:find("\\\\", 1, true) then return nil end
	if not path:lower():match("^interface\\addons\\arachnaphobiashield\\custom\\.+%.tga$") then return nil end
	return path
end

function P.Normalize(settings)
	-- v0.3.8: covers are always fully opaque. The client fades covers at
	-- distance no matter what we set, so the opacity preference is retired;
	-- drop any legacy key so it cannot be restored on the next load.
	settings.opacity = nil
	local path = P.CustomPath(settings.customCover)
	settings.customCover = path or ""
	local id = type(settings.coverStyle) == "string" and settings.coverStyle:lower() or "fox"
	if not P.Find(id) and not (id == "custom" and path) then id = "fox" end
	settings.coverStyle = id
end

function P.Current()
	local s = ArachnaphobiaShieldSettings or {}
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
		path = P.CustomPath(customPath or (ArachnaphobiaShieldSettings or {}).customCover)
		if not path then
			return false, "Use a local .tga path under Interface\\AddOns\\ArachnaphobiaShield\\Custom\\"
		end
	elseif not P.Find(id) then
		return false, "Choose fox / red / blue / sage / charcoal / custom"
	end
	ArachnaphobiaShieldSettings = ArachnaphobiaShieldSettings or {}
	ArachnaphobiaShieldSettings.coverStyle = id
	if path then ArachnaphobiaShieldSettings.customCover = path end
	if ArachnaphobiaShield.Cover and ArachnaphobiaShield.Cover.inited then ArachnaphobiaShield.Cover.ApplyStyle() end
	if ArachnaphobiaShield.Config then ArachnaphobiaShield.Config.Refresh() end
	return true, "Cover: " .. P.Current().label
end

function P.Command(args)
	local id, path = (args or ""):match("^%s*(%S+)%s*(.-)%s*$")
	if not id then
		print("AS| Cover: " .. P.Current().label .. " - /as config to choose")
		print("AS| /as cover fox / red / blue / sage / charcoal / custom <local .tga path>")
		return
	end
	local ok, message = P.Select(id, path ~= "" and path or nil)
	print("AS| " .. message)
	return ok
end
