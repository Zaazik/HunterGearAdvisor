-- Namespace, saved data and the event dispatcher.
local addonName, ns = ...
ns.name = addonName

-- HGA keeps no setting (raid-mode design 14.6; the user's decision of 2026-11-17 on the tuning commands, and U4 = (a): no
-- proc rate is made up, Score.ProcRateSource): the target and the hit cap follow the mode, any damage gain gets the
-- checkmark, the swap banner is always on, the Survival branch's melee is wowsims' SV Weave. ADDON_LOADED removes the
-- saved settings table whole, whatever version saved it and whatever keys it holds, and saves SETTINGS_VERSION; the saved
-- data keeps the banner's position, the dump and the pre-raid window's data.
local SETTINGS_VERSION = 5

local frame = CreateFrame("Frame")
local subscribers = {} -- event -> the functions given for it, called in that order

-- The list of an event not registered yet: the frame registers it, unless the client does not know the name. Such a
-- name (seen in game: LEARNED_SPELL_IN_TAB does not exist in Forever) makes RegisterEvent throw and aborts the rest
-- of the file; C_EventUtils.IsEventValid tells it beforehand (Blizzard_APIDocumentationGenerated/
-- EventUtilsDocumentation.lua: IsEventValid(eventName) -> valid), so it goes to the error handler, where it stays
-- visible, and nil comes back; the other events still get registered.
local function subscribe(event)
	if not C_EventUtils.IsEventValid(event) then
		geterrorhandler()("HunterGearAdvisor: unknown event " .. event .. " (handler not registered)")
		return nil
	end
	frame:RegisterEvent(event)
	subscribers[event] = {}
	return subscribers[event]
end

function ns.On(event, fn)
	local list = subscribers[event] or subscribe(event)
	if list then list[#list + 1] = fn end
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = subscribers[event]
	for i = 1, #list do list[i](event, ...) end
end)

ns.onLoad = {}
function ns.OnLoad(fn) table.insert(ns.onLoad, fn) end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	HunterGearAdvisorDB = HunterGearAdvisorDB or {}
	local db = HunterGearAdvisorDB
	db.settings = nil
	db.settingsVersion = SETTINGS_VERSION
	ns.db = db
	for _, fn in ipairs(ns.onLoad) do fn() end
end)

function ns.Print(...)
	print("|cff7fbf3fHGA:|r", ...)
end

-- The game's tooltip to the right of `owner`, its lines given by fill(GameTooltip).
function ns.ShowTooltip(owner, fill)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	fill(GameTooltip)
	GameTooltip:Show()
end

-- Upgrade mark on item icons (bags, quest rewards, loot): a white double up-arrow from the
-- addon's own Media folder, tinted with Zygor's upgrade green #5eff53 (the user asked for
-- Zygor's look). A texture file added while the game runs is seen only after a client restart.
ns.UPGRADE_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Media\\UpgradeArrow"
function ns.CreateUpgradeMark(parent, size)
	local tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	tex:SetTexture(ns.UPGRADE_TEXTURE)
	tex:SetVertexColor(94 / 255, 1, 83 / 255)
	tex:SetSize(size, size)
	return tex
end

-- Something changes (gear, bags, level, settings, item data): drop cached results and
-- tell the UI parts to redraw. Coalesced to one refresh per frame burst.
local listeners = {}
function ns.OnInvalidate(fn) table.insert(listeners, fn) end
local queued = false
function ns.Invalidate()
	if ns.Advisor then ns.Advisor.Reset() end
	if queued then return end
	queued = true
	C_Timer.After(0.2, function()
		queued = false
		-- one failing listener must not skip the others (a banner error would leave the bag
		-- arrows stale); the error still goes to the game's error handler, so it stays visible
		for _, fn in ipairs(listeners) do xpcall(fn, geterrorhandler()) end
	end)
end
