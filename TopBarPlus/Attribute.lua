--!nonstrict
--[[
	TopbarPlus was developed by ForeverHD and is possible thanks to HD Admin.
	Ported for executor environments. Attribution retained — please credit
	TopbarPlus if you distribute anything built with it:
	https://github.com/1ForeverHD/TopbarPlus
]]

local script, require = ...

task.defer(function()
	local VERSION = require(script.VERSION)
	local appVersion = VERSION.getAppVersion()
	local latestVersion = VERSION.getLatestVersion()
	local isOutdated = not VERSION.isUpToDate()
	print(`🍍 Running TopbarPlus {appVersion} (executor port) by @ForeverHD & HD Admin`)
	if isOutdated == false and latestVersion ~= nil then
		warn(`A new version of TopbarPlus ({latestVersion}) is available: https://devforum.roblox.com/t/topbarplus/1017485`)
	end
end)

return {}