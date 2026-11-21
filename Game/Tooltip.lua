-- Adds the gain line(s) to item tooltips.
local _, ns = ...

-- Where the tooltip's item is, from the tooltip's own data getter (C_TooltipInfo name + args):
-- SetBagItem -> "GetBagItem"(bag, slot), SetInventoryItem -> "GetInventoryItem"(unit, slot).
local NEW_ITEM_GETTERS = {
	GetQuestItem = true, GetQuestLogItem = true, GetLootItem = true, GetMerchantItem = true,
	GetBuybackItem = true, GetLootRollItem = true, GetSendMailItem = true, GetInboxItem = true,
	GetTradePlayerItem = true, GetTradeTargetItem = true, GetAuctionItem = true,
}
local function whereFromTooltip(tooltip)
	local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
	if not info or not info.getterName then return nil end
	local g, a = info.getterName, info.getterArgs or {}
	if g == "GetBagItem" then return { kind = "bag", bag = a[1], slot = a[2] } end
	if g == "GetInventoryItem" then
		-- the Inspect frame uses SetInventoryItem(otherUnit, slot): only the player's own items are worn
		if a[1] == "player" or (a[1] and UnitIsUnit(a[1], "player")) then return { kind = "equipped", slot = a[2] } end
		return { kind = "new" }
	end
	if NEW_ITEM_GETTERS[g] then return { kind = "new" } end
	return nil
end
ns.WhereFromTooltip = whereFromTooltip

local function onItemTooltip(tooltip)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	if not ns.db then return end
	local _, link = tooltip:GetItem()
	if not link then return end
	for _, line in ipairs(ns.Advisor.Explain(link, whereFromTooltip(tooltip))) do
		tooltip:AddLine(line[1], line[2], line[3], line[4], true)
	end
end

ns.OnLoad(function()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
end)
