--!nocheck
--[[
	TopbarPlus executor loader.
	Loads the module tree, builds a fake script hierarchy, returns the Icon class.

	Usage:
		local Icon = loadstring(game:HttpGet(".../Loader.lua"))()
]]

-- [PORT] re-run cleanup (replaces the ReplicatedStorage Reference system)
local env = _G
if type(getgenv) == "function" then
	local ok, result = pcall(getgenv)
	if ok and type(result) == "table" then
		env = result
	end
end
if type(env.TopbarPlusCleanup) == "function" then
	pcall(env.TopbarPlusCleanup)
end

-- (trailing slash required). Example:
local BASE_URL = "https://raw.githubusercontent.com/YetYoursTruly/LuaBar/main/TopbarPlus/"

-- Optional: paste sources locally instead of HttpGet by filling this table,
-- keyed by path relative to BASE_URL:
local LOCAL_SOURCES = {}

local function fetchSource(path)
	local src = game:HttpGet(BASE_URL, true)
	if src:sub(1, 9) ~= "--!nocheck" then
		warn("[ExampleButton] Bad response from GitHub: " .. src:sub(1, 120))
		return
	end
	local success, Icon = pcall(function()
		return loadstring(src)()
	end)
end

--==================================================
-- Fake script tree
--==================================================

local Module = {}
Module.__index = Module

local function newModule(name, parent, source)
	local module = setmetatable({}, Module)
	module.Name = name
	module.Parent = parent
	module.Source = source
	module._result = nil
	module._loaded = false
	if parent then
		parent[name] = module
	end
	return module
end

-- Custom require: accepts a module table (or a function source), caches results.
-- Each module chunk receives (script, require) as its varargs.
local function customRequire(target)
	if type(target) == "function" then
		return target()
	end
	assert(type(target) == "table" and getmetatable(target) == Module,
		"TopbarPlus loader: require expects a module from the fake script tree")
	if target._loaded then
		return target._result
	end
	target._loaded = true
	local chunk = loadstring(target.Source, "=" .. tostring(target.Name))
	assert(chunk, "TopbarPlus loader: failed to compile " .. tostring(target.Name))
	target._result = chunk(target, customRequire)
	return target._result
end

-- Build the tree
local root = newModule("Icon", nil)

local Packages = newModule("Packages", root)
newModule("GoodSignal", Packages, fetchSource("Packages/GoodSignal.lua"))
newModule("Janitor", Packages, fetchSource("Packages/Janitor.lua"))

local Features = newModule("Features", root)
local Themes = newModule("Themes", Features)
newModule("Themes", Themes, fetchSource("Features/Themes.lua")) -- Themes module itself
Themes.Default = newModule("Default", Themes, fetchSource("Features/Themes/Default.lua"))
Themes.Classic = newModule("Classic", Themes, fetchSource("Features/Themes/Classic.lua"))
newModule("Gamepad", Features, fetchSource("Features/Gamepad.lua"))
newModule("Overflow", Features, fetchSource("Features/Overflow.lua"))

local Elements = newModule("Elements", root)
for _, name in ipairs({ "Container", "Widget", "Menu", "Dropdown", "Notice", "Caption", "Selection", "Indicator" }) do
	newModule(name, Elements, fetchSource("Elements/" .. name .. ".lua"))
end

newModule("Utility", root, fetchSource("Utility.lua"))
newModule("VERSION", root, fetchSource("VERSION.lua"))
newModule("Attribute", root, fetchSource("Attribute.lua"))

root.Source = fetchSource("Icon.lua")

-- Load it
local Icon = customRequire(root)

env.TopbarPlusModules = root
env.TopbarPlusIcon = Icon

return Icon