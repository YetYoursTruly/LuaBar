--!nonstrict
-- [PORT] The original polled MarketplaceService:GetProductInfo(117501901079852)
-- inside an infinite while-true loop. That's executor-hostile (rate-limited,
-- usually irrelevant). Replaced with a one-shot HttpGet check that only runs
-- if CHECK_UPDATES is enabled and an http function exists. Never yields forever.

local VERSION = {}

-- Changing appVersion from "v3.4.0" can cause errors
VERSION.appVersion = "v3.4.0"
VERSION.latestVersion = nil
VERSION.CHECK_UPDATES = false -- set true to enable the version check

function VERSION.getLatestVersion()
	local latestVersion = VERSION.latestVersion
	if latestVersion ~= nil then
		return latestVersion
	end
	if not VERSION.CHECK_UPDATES then
		return nil
	end
	local requestFn = (type(http_request) == "function" and http_request)
		or (type(request) == "function" and request)
		or (typeof(syn) == "table" and type(syn.request) == "function" and syn.request)
		or nil
	if not requestFn then
		return nil
	end
	local ok, response = pcall(requestFn, {
		Url = "https://raw.githubusercontent.com/1ForeverHD/TopbarPlus/main/version.txt",
		Method = "GET",
	})
	if ok and type(response) == "table" and type(response.Body) == "string" then
		latestVersion = response.Body:match("^TopbarPlus%s*(%S+)") or response.Body:match("(%S+)")
		VERSION.latestVersion = latestVersion
	end
	return latestVersion
end

function VERSION.getAppVersion()
	return VERSION.appVersion
end

function VERSION.isUpToDate()
	local latestVersion = VERSION.getLatestVersion()
	local appVersion = VERSION.getAppVersion()
	return latestVersion ~= nil and latestVersion == appVersion
end

return VERSION