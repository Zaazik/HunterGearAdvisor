-- Green double up-arrow on bag item icons: Baganator corner widget, or Blizzard bags without Baganator.
local _, ns = ...

local WIDGET_ID = "hunter_gear_advisor_upgrade"

local function makeCheck(parent)
	return ns.CreateUpgradeMark(parent, 16)
end

-- Baganator: onUpdate returns true (show), false (hide) or nil (item data not ready yet).
local function registerBaganator()
	Baganator.API.RegisterCornerWidget("Апгрейд для ханта (HGA)", WIDGET_ID,
		function(check, details)
			if not details.itemLink then return false end
			-- Baganator stores a plain { bagID, slotIndex } table (ItemViewCommon/ItemButton.lua),
			-- not an ItemLocation object; accept both.
			local where
			local loc = details.itemLocation
			if loc then
				if loc.IsBagAndSlot then
					if loc:IsBagAndSlot() then
						local bag, slot = loc:GetBagAndSlot()
						where = { kind = "bag", bag = bag, slot = slot }
					end
				elseif loc.bagID and loc.slotIndex then
					where = { kind = "bag", bag = loc.bagID, slot = loc.slotIndex }
				end
			end
			local res = ns.Advisor.Evaluate(details.itemLink, where)
			if res == nil then return nil end
			return res.isUpgrade == true
		end,
		function(itemButton) return makeCheck(itemButton) end,
		{ corner = "top_left", priority = 1 })
	ns.OnInvalidate(function() Baganator.API.RequestItemButtonsRefresh() end)
end

-- Blizzard bags: one checkmark per item button, refreshed after each container update.
local function markButton(button)
	local bag, slot = button:GetBagID(), button:GetID()
	local link = C_Container.GetContainerItemLink(bag, slot)
	local res = link and ns.Advisor.Evaluate(link, { kind = "bag", bag = bag, slot = slot })
	local show = res ~= nil and res.isUpgrade == true
	if show and not button.hgaCheck then
		button.hgaCheck = makeCheck(button)
		button.hgaCheck:SetPoint("TOPLEFT", 1, -1)
	end
	if button.hgaCheck then button.hgaCheck:SetShown(show) end
end

local function updateFrame(frame)
	if not frame:IsShown() then return end
	for _, button in frame:EnumerateValidItems() do markButton(button) end
end

local hookedFrames = {}
local function blizzardFrames()
	local frames = {}
	for i = 1, 13 do
		local f = _G["ContainerFrame" .. i]
		if f and f.UpdateItems then frames[#frames + 1] = f end
	end
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags.UpdateItems then
		frames[#frames + 1] = ContainerFrameCombinedBags
	end
	return frames
end

local function hookBlizzard()
	for _, f in ipairs(blizzardFrames()) do
		if not hookedFrames[f] then
			hookedFrames[f] = true
			hooksecurefunc(f, "UpdateItems", updateFrame)
		end
	end
	ns.OnInvalidate(function()
		for _, f in ipairs(blizzardFrames()) do updateFrame(f) end
	end)
end

ns.On("PLAYER_LOGIN", function()
	if Baganator and Baganator.API and Baganator.API.RegisterCornerWidget then
		registerBaganator()
	else
		hookBlizzard()
	end
end)
