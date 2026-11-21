-- Quest rewards: upgrade arrow on every upgrade, a green frame around the best choice; with no
-- upgrade among the choices, a coin on the choice that sells for the most (like Zygor).
-- Forever loads the Mainline QuestInfo (quest dialog and the map quest log share it).
local _, ns = ...
local Quest = {}
ns.Quest = Quest

local retries = 0
local COIN_TEXTURE = "Interface\\MONEYFRAME\\UI-GoldIcon" -- the coin Zygor puts on that reward

local function decorateCoin(button)
	if button.hgaCoin then return end
	local anchor = button.Icon or button
	button.hgaCoin = button:CreateTexture(nil, "OVERLAY", nil, 7)
	button.hgaCoin:SetTexture(COIN_TEXTURE)
	button.hgaCoin:SetSize(16, 16)
	button.hgaCoin:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
end

-- Quest log: a choice button's ID counts item choices only (QuestInfo.lua sets it from
-- choiceItemIndex), while GetQuestLogChoiceInfo takes the raw choice index that also counts
-- currencies (QuestInfo.lua calls it with the loop index). Maps the one to the other.
local function rawChoiceIndex(button)
	local items = 0
	for i = 1, GetNumQuestLogChoices(button.questID, true) do
		if GetQuestLogChoiceInfoLootType(i) == 0 then -- LOOT_LIST_ITEM
			items = items + 1
			if items == button:GetID() then return i end
		end
	end
end

-- Vendor value of a choice: sell price x count, as Zygor's QuestItem:GetQuestRewardIndex counts
-- it (QuestInfo.lua reads the count with the same calls). Returns value, or nil while the item
-- is not loaded, or nil + an error text when the reward list does not match the buttons.
local function choiceValue(button, link)
	local sellPrice = select(11, C_Item.GetItemInfo(link))
	if sellPrice == nil then return nil end
	local count
	if QuestInfoFrame.questLog then
		local raw = rawChoiceIndex(button)
		if not raw then
			return nil, "HunterGearAdvisor: quest log choice button " .. tostring(button:GetID())
				.. " has no matching reward (quest " .. tostring(button.questID) .. ")"
		end
		count = select(3, GetQuestLogChoiceInfo(raw))
	else
		count = select(3, GetQuestItemInfo(button.type, button:GetID()))
	end
	if count == nil then return nil end
	return sellPrice * count
end

local function decorate(button)
	if button.hgaCheck then return end
	local anchor = button.Icon or button
	button.hgaCheck = ns.CreateUpgradeMark(button, 18)
	button.hgaCheck:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
	button.hgaBest = button:CreateTexture(nil, "OVERLAY", nil, 6)
	button.hgaBest:SetColorTexture(0.25, 1, 0.25, 0.35)
	button.hgaBest:SetAllPoints(anchor)
end

local function linkFor(button)
	if QuestInfoFrame.questLog then
		return GetQuestLogItemLink(button.type, button:GetID())
	end
	return GetQuestItemLink(button.type, button:GetID())
end

function Quest.Refresh()
	local rewardsFrame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
	if not rewardsFrame or not rewardsFrame.RewardButtons or not ns.db then return end
	local best, bestDelta, notReady = nil, nil, false
	local choices = {}
	for _, button in ipairs(rewardsFrame.RewardButtons) do
		if button.hgaCheck then button.hgaCheck:Hide(); button.hgaBest:Hide() end
		if button.hgaCoin then button.hgaCoin:Hide() end
		if button:IsShown() and button.objectType == "item" then
			local link = linkFor(button)
			-- a reward is a new item even when an identical one is worn
			local res = link and ns.Advisor.Evaluate(link, { kind = "new" })
			if not res then
				notReady = true
			elseif res.isUpgrade then
				decorate(button)
				button.hgaCheck:Show()
				if button.type == "choice" and (not bestDelta or res.delta > bestDelta) then
					best, bestDelta = button, res.delta
				end
			end
			if button.type == "choice" then
				local value, err
				if link then value, err = choiceValue(button, link) end
				choices[#choices + 1] = { button = button, value = value, err = err }
			end
		end
	end
	if best then best.hgaBest:Show() end
	-- no upgrade to choose: the coin marks the choice that sells for the most. Only once every
	-- choice is known (an unloaded one could still be an upgrade or the most expensive).
	if not best and not notReady and #choices >= 2 then
		local top, topValue, failed
		for _, c in ipairs(choices) do
			if c.err then
				-- the most expensive choice cannot be known: no coin, and say why (no retry loop)
				geterrorhandler()(c.err)
				failed = true
			elseif c.value == nil then
				notReady = true
			elseif c.value > 0 and (not topValue or c.value > topValue) then
				top, topValue = c.button, c.value
			end
		end
		if top and not notReady and not failed then
			decorateCoin(top)
			top.hgaCoin:Show()
		end
	end
	if notReady and retries < 10 then
		retries = retries + 1
		C_Timer.After(0.3, Quest.Refresh)
	end
end

-- Templates that fill the reward buttons have QuestInfo_ShowRewards among their elements
-- (QuestInfo.lua: a flat { func, x, y, ... } list). The map's details pane
-- (QUEST_TEMPLATE_MAP_DETAILS) has none: QuestInfoFrame.rewardsFrame then still points at the
-- NPC dialog's buttons from the last quest, which must not be judged against the quest now
-- selected on the map (quest-log calls answer for that one). The function is taken at load:
-- a later hooksecurefunc replaces the global, the templates keep the original.
-- (QuestInfo_Display itself reads template.elements before this post-hook runs.)
local SHOW_REWARDS
local function showsRewards(template)
	local elements = template.elements
	for i = 1, #elements, 3 do
		if elements[i] == SHOW_REWARDS then return true end
	end
	return false
end

ns.OnLoad(function()
	SHOW_REWARDS = QuestInfo_ShowRewards
	if showsRewards(QUEST_TEMPLATE_DETAIL) then
		hooksecurefunc("QuestInfo_Display", function(template)
			if not showsRewards(template) then return end
			retries = 0
			Quest.Refresh()
		end)
	else
		-- reported, not raised: the other modules' load must still run
		geterrorhandler()("HunterGearAdvisor: QuestInfo_ShowRewards was replaced before this addon "
			.. "loaded, so quest dialogs are not marked when they open")
	end
	-- QuestInfoFrame itself stays hidden (QuestInfo.xml: hidden="true"; its parts are reparented),
	-- so the visible thing to check is the rewards frame, as Blizzard's QuestFrame.lua does.
	ns.OnInvalidate(function()
		local rf = QuestInfoFrame and QuestInfoFrame.rewardsFrame
		if rf and rf:IsVisible() then
			retries = 0
			Quest.Refresh()
		end
	end)
end)

-- ===== Loot window and group loot rolls (kept in this file so a /reload is enough) =====
-- Upgrade arrow on looted and rolled items: the loot window and the group loot roll frames
-- (Need / Greed / Pass). Forever loads the Mainline LootFrame (ScrollBox rows with :GetSlotIndex()
-- and .Item) and GroupLootFrame1..4 (.rollID, .IconFrame with .Icon); links come from
-- GetLootSlotLink / GetLootRollItemLink, as Blizzard's own code uses them.
do

	local MAX_RETRIES = 10
	local retries = 0

	local function setCheck(button, anchor, show)
		if show and not button.hgaCheck then
			button.hgaCheck = ns.CreateUpgradeMark(button, 18)
			button.hgaCheck:SetPoint("TOPLEFT", anchor or button, "TOPLEFT", -2, 2)
		end
		if button.hgaCheck then button.hgaCheck:SetShown(show) end
	end
	
	-- returns show, notReady
	local function judge(link)
		if not link then return false, false end
		local res = ns.Advisor.Evaluate(link, { kind = "new" })
		if res == nil then return false, true end
		return res.isUpgrade == true, false
	end
	
	local function refreshRolls()
		local notReady = false
		for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
			local f = _G["GroupLootFrame" .. i]
			if f and f.IconFrame then
				local show = false
				if f:IsShown() and f.rollID then
					local wait
					show, wait = judge(GetLootRollItemLink(f.rollID))
					notReady = notReady or wait
				end
				setCheck(f.IconFrame, f.IconFrame.Icon, show)
			end
		end
		return notReady
	end
	
	local function refreshLoot()
		local notReady = false
		local lf = LootFrame
		if lf and lf:IsShown() and lf.ScrollBox and lf.ScrollBox.ForEachFrame then
			lf.ScrollBox:ForEachFrame(function(row)
				local button = row.Item
				if button and row.GetSlotIndex then
					local show, wait = judge(GetLootSlotLink(row:GetSlotIndex()))
					notReady = notReady or wait
					setCheck(button, button.icon or button.Icon, show)
				end
			end)
		end
		return notReady
	end
	
	local function refresh()
		if not ns.db then return end
		local a = refreshRolls()
		local b = refreshLoot()
		if (a or b) and retries < MAX_RETRIES then
			retries = retries + 1
			C_Timer.After(0.3, refresh)
		end
	end
	
	local function kick()
		retries = 0
		C_Timer.After(0, refresh) -- after Blizzard has filled the frames
	end
	
	for _, ev in ipairs({ "START_LOOT_ROLL", "LOOT_OPENED", "LOOT_READY", "LOOT_SLOT_CHANGED" }) do
		ns.On(ev, kick)
	end
	
	ns.OnLoad(function()
		for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
			local f = _G["GroupLootFrame" .. i]
			if f then f:HookScript("OnShow", kick) end
		end
		ns.OnInvalidate(refresh)
	end)
end
