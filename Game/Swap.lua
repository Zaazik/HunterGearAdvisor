-- Swap banner: a small bar saying that putting on something from the bags, or taking an item off, is a gain (like
-- Zygor's "You have a new upgrade available"). A click opens what replaces what, with an Equip button per row (a Take
-- off button on a row that takes its item off, A.Plan row.takeOff). Equipping follows Blizzard's EquipmentManager (Mainline/EquipmentManager.lua):
-- pick the item up, check that it fits the slot and the slot is not locked, put it on; the worn
-- item goes back to where the new one came from.
local _, ns = ...
local Swap = {}
ns.Swap = Swap

local S = ns.Score.SLOT
local PANEL_WIDTH = 380
local ICON, BUTTON_W, PAD = 32, 80, 8
local TEXT_X = ICON + 6
local TEXT_W = PANEL_WIDTH - 2 * PAD - TEXT_X - BUTTON_W - 6
local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local GREEN = { 94 / 255, 1, 83 / 255 }

-- slot -> GlobalStrings name (ruRU: "Голова", "Правая рука", ...); rings and trinkets are numbered
local SLOT_KEYS = {
	[S.HEAD] = "HEADSLOT", [S.NECK] = "NECKSLOT", [S.SHOULDER] = "SHOULDERSLOT", [S.BACK] = "BACKSLOT",
	[S.CHEST] = "CHESTSLOT", [S.WRIST] = "WRISTSLOT", [S.HANDS] = "HANDSSLOT", [S.WAIST] = "WAISTSLOT",
	[S.LEGS] = "LEGSSLOT", [S.FEET] = "FEETSLOT", [S.FINGER1] = "FINGER0SLOT", [S.FINGER2] = "FINGER1SLOT",
	[S.TRINKET1] = "TRINKET0SLOT", [S.TRINKET2] = "TRINKET1SLOT", [S.MAINHAND] = "MAINHANDSLOT",
	[S.OFFHAND] = "SECONDARYHANDSLOT", [S.RANGED] = "RANGEDSLOT",
}
local SLOT_NUMBER = { [S.FINGER1] = 1, [S.FINGER2] = 2, [S.TRINKET1] = 1, [S.TRINKET2] = 2 }

-- An unknown key shows itself instead of a blank, so a missing client string is visible.
local function slotName(slot)
	local key = SLOT_KEYS[slot]
	local name = key and _G[key] or key or ("слот " .. tostring(slot))
	if SLOT_NUMBER[slot] then name = name .. " " .. SLOT_NUMBER[slot] end
	return name
end
Swap.SlotName = slotName

local banner, panel
local rowFrames = {}
local currentPlan
local dismissed      -- { [row.key] = true } hidden with the ×: stays hidden while the plan has nothing else
local forced = false -- /hga swap opened it
local dragStoppedAt  -- a drag ends with a mouse-up: that is not a click

local function itemIcon(item)
	return item and select(5, C_Item.GetItemInfoInstant(item.link))
end

local function showItemTooltip(self)
	if self.link then ns.ShowTooltip(self, function(tip) tip:SetHyperlink(self.link) end) end
end

local function hideTooltip() GameTooltip:Hide() end

local function savePosition()
	local point, _, relPoint, x, y = banner:GetPoint(1)
	ns.db.swapBannerPoint = { point = point, relPoint = relPoint, x = x, y = y }
end

local function restorePosition()
	banner:ClearAllPoints()
	local p = ns.db.swapBannerPoint
	if p then
		banner:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	else
		banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
end

-- Puts row.new on in row.slot. Every refusal is said in chat; nothing fails quietly. Only a row with an item to put on has
-- the Надеть button (fillRow), so a row without one is an error.
function Swap.EquipRow(row)
	if not (row and row.new) then error("HunterGearAdvisor: an equip row without the item it puts on", 2) end
	local item = row.new
	local name = item.name
	if InCombatLockdown() then ns.Print("в бою вещи не переодеть — после боя"); return end
	if CursorHasItem() then ns.Print("на курсоре уже есть предмет — положи его и нажми ещё раз"); return end
	local w = item.where
	if w.kind == "bag" then
		if C_Container.GetContainerItemLink(w.bag, w.slot) ~= item.link then
			ns.Print(name .. ": вещь в сумках сдвинулась — список обновлён, нажми ещё раз")
			ns.Invalidate()
			return
		end
		C_Container.PickupContainerItem(w.bag, w.slot)
	elseif w.kind == "equipped" then
		-- the plan moves a worn item to another slot (a weapon to the other hand, a ring)
		if GetInventoryItemLink("player", w.slot) ~= item.link then
			ns.Print(name .. ": надетые вещи изменились — список обновлён, нажми ещё раз")
			ns.Invalidate()
			return
		end
		PickupInventoryItem(w.slot)
	else
		error("HunterGearAdvisor: swap row item without a bag or slot: " .. tostring(w.kind))
	end
	if not CursorHasItem() then
		ns.Print("не удалось взять " .. name .. " (вещь заблокирована — подожди секунду)")
		return
	end
	if not C_PaperDollInfo.CursorCanGoInSlot(row.slot) then
		ClearCursor()
		ns.Print(name .. " не надевается в слот «" .. slotName(row.slot) .. "»")
		return
	end
	if IsInventoryItemLocked(row.slot) then
		ClearCursor()
		ns.Print("слот «" .. slotName(row.slot) .. "» сейчас занят сменой вещи — нажми ещё раз")
		return
	end
	-- a bind-on-equip item asks for confirmation here (the game's own dialog)
	EquipCursorItem(row.slot)
end

-- Takes row.old off row.slot (a take-off row, A.Plan row.takeOff) into a free slot of a bag, as Blizzard's EquipmentManager
-- puts an unequipped item away (Mainline/EquipmentManager.lua:18-43, 147-190): the backpack first, then the bags, a bag
-- only of family 0 (C_Container.GetContainerNumFreeSlots' bagFamily: a quiver or an ammo pouch takes ammo alone),
-- PutItemInBackpack for the backpack, PutItemInBag with the bag's inventory slot (C_Container.ContainerIDToInventoryID)
-- for the others. Every refusal is said in chat; nothing fails quietly. A take-off row always holds the worn item it takes
-- off (A.Plan: takesOff marks only a row with nothing to put on, and Score.PlanRows gives such a row only for a worn
-- slot), so a row without one is an error.
function Swap.UnequipRow(row)
	if not (row and row.old) then error("HunterGearAdvisor: a take-off row without the item it takes off", 2) end
	local item = row.old
	local name = item.name
	if InCombatLockdown() then ns.Print("в бою вещи не снять — после боя"); return end
	if CursorHasItem() then ns.Print("на курсоре уже есть предмет — положи его и нажми ещё раз"); return end
	if GetInventoryItemLink("player", row.slot) ~= item.link then
		ns.Print(name .. ": надетые вещи изменились — список обновлён, нажми ещё раз")
		ns.Invalidate()
		return
	end
	local bag
	for b = 0, NUM_BAG_SLOTS do
		local free, family = C_Container.GetContainerNumFreeSlots(b)
		if free > 0 and family == 0 then bag = b; break end
	end
	if not bag then ns.Print("в сумках нет места — " .. name .. " не снять"); return end
	if IsInventoryItemLocked(row.slot) then
		ns.Print("слот «" .. slotName(row.slot) .. "» сейчас занят сменой вещи — нажми ещё раз")
		return
	end
	PickupInventoryItem(row.slot)
	if not CursorHasItem() then
		ns.Print("не удалось взять " .. name .. " (вещь заблокирована — подожди секунду)")
		return
	end
	if bag == 0 then PutItemInBackpack() else PutItemInBag(C_Container.ContainerIDToInventoryID(bag)) end
end

local function makeRow(i)
	local r = CreateFrame("Frame", nil, panel)
	r:SetWidth(PANEL_WIDTH - 2 * PAD)

	r.icon = CreateFrame("Button", nil, r)
	r.icon:SetSize(ICON, ICON)
	r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
	r.icon.tex = r.icon:CreateTexture(nil, "ARTWORK")
	r.icon.tex:SetAllPoints(r.icon)
	r.icon:SetScript("OnEnter", showItemTooltip)
	r.icon:SetScript("OnLeave", hideTooltip)

	r.equip = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
	r.equip:SetSize(BUTTON_W, 22)
	r.equip:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -6)
	r.equip:SetScript("OnClick", function()
		if r.data.takeOff then Swap.UnequipRow(r.data) else Swap.EquipRow(r.data) end
	end)

	local function text(font, wrap)
		local fs = r:CreateFontString(nil, "OVERLAY", font)
		fs:SetWidth(TEXT_W)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(wrap)
		return fs
	end
	r.slot = text("GameFontNormalSmall", false)
	r.name = text("GameFontHighlight", false)
	r.old = text("GameFontHighlightSmall", true)
	r.hint = text("GameFontDisableSmall", true)
	r.gain = text("GameFontHighlightSmall", true)
	r.notes = text("GameFontHighlightSmall", true)
	r.notes:SetTextColor(0.9, 0.9, 0.6)
	r.lines = { r.slot, r.name, r.old, r.hint, r.gain, r.notes }
	rowFrames[i] = r
	return r
end

-- Fills a row and stacks its text lines; returns the row height.
local function fillRow(r, row)
	r.data = row
	local shown = row.new or row.old
	r.icon.link = shown and shown.link
	r.icon.tex:SetTexture(itemIcon(shown))
	r.icon.tex:SetDesaturated(row.new == nil)
	r.slot:SetText(slotName(row.slot))
	local hint, gainText, gainColor = "", "", nil
	local notes = {}
	if row.new then
		r.name:SetText(row.new.link)
		r.old:SetText("вместо: " .. (row.old and row.old.link or "пусто"))
		if row.new.where.kind == "equipped" then
			hint = "переложить из слота «" .. slotName(row.new.where.slot) .. "»"
		end
		if row.pairPart then
			local with = row.unit == "pair" and "соседним слотом (уникальная вещь)" or "другой рукой"
			hint = (hint ~= "" and hint .. "; " or "") .. "одна замена вместе с " .. with .. " — прирост в её строке"
		elseif row.gain then
			local line = ns.Advisor.GainLines(row.gain, "")[1]
			gainText, gainColor = line[1], { line[2], line[3], line[4] }
		end
		local f = row.familySwitch
		if f and f.noAmmo then notes[#notes + 1] = "в сумках нет " .. (f.family == 2 and "стрел" or "пуль") .. " для него" end
		if f and f.quiverMismatch then notes[#notes + 1] = "к нему нужен " .. (f.family == 2 and "колчан" or "подсумок") .. ", твой не подходит" end
		r.equip:SetText("Надеть")
		r.equip:Show()
		r.equip:SetEnabled(not InCombatLockdown())
	elseif row.takeOff then
		-- the plan takes the item off by itself (A.Plan row.takeOff): part of what to wear
		r.name:SetText(row.old.link)
		r.old:SetText("снять в сумку — " .. ((row.slot == S.MAINHAND or row.slot == S.OFFHAND) and "рука останется пустой" or "слот останется пустым"))
		if row.pairPart then
			hint = "одна замена вместе с другой рукой — прирост в её строке"
		elseif row.gain then
			local line = ns.Advisor.GainLines(row.gain, "")[1]
			gainText, gainColor = line[1], { line[2], line[3], line[4] }
		end
		r.equip:SetText("Снять")
		r.equip:Show()
		r.equip:SetEnabled(not InCombatLockdown())
	elseif row.movesTo then
		-- another row moves this slot's item to row.movesTo (A.Plan): that row's Надеть picks it up from here; the slot is
		-- empty after it when the other slot is empty now, and what lands here otherwise the next plan shows
		r.name:SetText(row.old.link)
		r.old:SetText(row.moveDisplaces
			and ("перейдёт в слот «" .. slotName(row.movesTo) .. "»; что окажется здесь, покажет обновлённый список")
			or ("освободится само: вещь перейдёт в слот «" .. slotName(row.movesTo) .. "»"))
		if row.pairPart then
			local with = row.unit == "pair" and "соседним слотом (уникальная вещь)" or "другой рукой"
			hint = "одна замена вместе с " .. with .. " — прирост в её строке"
		elseif row.gain then
			local line = ns.Advisor.GainLines(row.gain, "")[1]
			gainText, gainColor = line[1], { line[2], line[3], line[4] }
		end
		r.equip:Hide()
	else
		r.name:SetText(row.old and row.old.link or "")
		if row.slot == S.MAINHAND then
			-- only an off-hand item beats the worn two-hander: putting it on takes the 2H off
			r.old:SetText("снимется само, когда наденешь вещь в левую руку; правая останется пустой")
		else
			r.old:SetText("снимется само: эту руку займёт двуручное")
		end
		r.equip:Hide()
	end
	r.hint:SetText(hint)
	r.gain:SetText(gainText)
	if gainColor then r.gain:SetTextColor(gainColor[1], gainColor[2], gainColor[3]) end
	r.notes:SetText(table.concat(notes, "; "))
	-- stack the non-empty lines under each other (long ones wrap)
	local y = 0
	for _, fs in ipairs(r.lines) do
		local t = fs:GetText()
		if t and t ~= "" then
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -y)
			fs:Show()
			y = y + fs:GetStringHeight() + 1
		else
			fs:Hide()
		end
	end
	local h = math.max(ICON + 6, y + 6)
	r:SetHeight(h)
	r:Show()
	return h
end

-- The list opens towards the free side of the screen: up when the banner is in the lower half,
-- right-aligned when it would run off the right edge.
local function anchorPanel()
	panel:ClearAllPoints()
	local left, bottom = banner:GetLeft(), banner:GetBottom()
	local up = bottom ~= nil and bottom < UIParent:GetHeight() / 2
	local side = (left ~= nil and left + PANEL_WIDTH > UIParent:GetWidth()) and "RIGHT" or "LEFT"
	if up then
		panel:SetPoint("BOTTOM" .. side, banner, "TOP" .. side, 0, 2)
	else
		panel:SetPoint("TOP" .. side, banner, "BOTTOM" .. side, 0, -2)
	end
end

local function fillPanel(plan)
	local y = PAD
	for i, row in ipairs(plan.rows) do
		local r = rowFrames[i] or makeRow(i)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
		y = y + fillRow(r, row) + 4
	end
	for i = #plan.rows + 1, #rowFrames do rowFrames[i]:Hide() end
	local lines = ns.Advisor.GainLines(plan, "всё вместе: ")
	local first, second = lines[1], lines[2]
	panel.total:SetText(first and first[1] or "")
	if first then panel.total:SetTextColor(first[2], first[3], first[4]) end
	panel.total:ClearAllPoints()
	panel.total:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 2, -y)
	y = y + panel.total:GetStringHeight() + 2
	panel.total2:SetText(second and second[1] or "")
	if second then y = y + panel.total2:GetStringHeight() end
	panel:SetHeight(y + PAD)
	anchorPanel()
end

local function closeList()
	panel:Hide()
	forced = false
end

local function build()
	banner = CreateFrame("Button", "HunterGearAdvisorSwapBanner", UIParent, "BackdropTemplate")
	banner:SetSize(270, 38)
	banner:SetFrameStrata("MEDIUM")
	banner:SetClampedToScreen(true)
	banner:SetMovable(true)
	banner:EnableMouse(true)
	banner:RegisterForDrag("LeftButton")
	banner:RegisterForClicks("LeftButtonUp")
	banner:SetBackdrop(BACKDROP)
	banner:SetBackdropColor(0, 0, 0, 0.85)
	banner:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3])
	restorePosition()

	banner.icon = ns.CreateUpgradeMark(banner, 24)
	banner.icon:SetPoint("LEFT", banner, "LEFT", 8, 0)
	banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	banner.title:SetPoint("TOPLEFT", banner.icon, "TOPRIGHT", 6, 1)
	banner.title:SetJustifyH("LEFT")
	banner.sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	banner.sub:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -2)
	banner.sub:SetJustifyH("LEFT")
	banner.sub:SetText("нажми — что на что менять")

	banner.close = CreateFrame("Button", nil, banner, "UIPanelCloseButton")
	banner.close:SetSize(22, 22)
	banner.close:SetPoint("TOPRIGHT", banner, "TOPRIGHT", 1, 1)
	banner.close:SetScript("OnClick", function()
		dismissed = {}
		for _, row in ipairs(currentPlan and currentPlan.rows or {}) do dismissed[row.key] = true end
		closeList()
		ns.Print("плашка скрыта, пока не появится новая замена; /hga swap — показать список")
		Swap.Refresh()
	end)

	banner:SetScript("OnDragStart", function(self) self:StartMoving() end)
	banner:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
		dragStoppedAt = GetTime()
		if panel:IsShown() then anchorPanel() end
	end)
	banner:SetScript("OnClick", function()
		if dragStoppedAt and GetTime() - dragStoppedAt < 0.3 then return end
		if panel:IsShown() then
			closeList()
			Swap.Refresh() -- the banner stays while the plan suggests a swap the × has not hidden
		elseif currentPlan then
			fillPanel(currentPlan)
			panel:Show()
		end
	end)
	banner:Hide()

	panel = CreateFrame("Frame", nil, banner, "BackdropTemplate")
	banner.panel, panel.rows = panel, rowFrames -- reachable for the tests
	panel:SetWidth(PANEL_WIDTH)
	panel:SetClampedToScreen(true)
	panel:SetBackdrop(BACKDROP)
	panel:SetBackdropColor(0, 0, 0, 0.92)
	panel:SetBackdropBorderColor(0.6, 0.6, 0.6)
	panel.total = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.total:SetWidth(PANEL_WIDTH - 2 * PAD - 4)
	panel.total:SetJustifyH("LEFT")
	panel.total2 = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.total2:SetPoint("TOPLEFT", panel.total, "BOTTOMLEFT", 0, -2)
	panel.total2:SetWidth(PANEL_WIDTH - 2 * PAD - 4)
	panel.total2:SetJustifyH("LEFT")
	panel:Hide()
end

-- Rows the player acts on: something to put on, or an item the plan takes off by itself (A.Plan row.takeOff); the off hand
-- a two-hander empties has neither.
local function acts(row) return row.new ~= nil or row.takeOff end
local function actionable(plan)
	local n = 0
	for _, row in ipairs(plan.rows) do if acts(row) then n = n + 1 end end
	return n
end

-- Hidden with the × while every suggestion is one the banner showed at the × (equipping one of them by
-- hand or sorting the bags does not bring it back, like Zygor's "don't repop if equipped by hand").
local function isDismissed(plan)
	if not dismissed then return false end
	for _, row in ipairs(plan.rows) do
		if acts(row) and not dismissed[row.key] then return false end
	end
	return true
end

function Swap.Refresh()
	if not banner then return end
	local plan
	-- the banner is always on (the user, 2026-11-17: no setting turns it off): the plan is built whenever out of combat;
	-- the × hides it until the plan changes (isDismissed)
	if not InCombatLockdown() then plan = ns.Advisor.Plan() end
	currentPlan = plan
	local n = plan and actionable(plan) or 0
	if n == 0 or (not forced and isDismissed(plan)) then
		if n == 0 then forced = false end
		banner:Hide()
		panel:Hide()
		return
	end
	if plan.fromBags == 0 and plan.takeOffs == n then
		-- the plan only takes items off
		banner.title:SetText(n == 1 and "Можно снять вещь с выгодой" or ("Можно снять вещи с выгодой: " .. n))
	elseif plan.fromBags == 0 then
		banner.title:SetText("Можно переложить оружие")
	elseif plan.fromBags == 1 then
		banner.title:SetText("Можно надеть улучшение")
	else
		banner.title:SetText("Можно надеть улучшения: " .. plan.fromBags)
	end
	banner:Show()
	if panel:IsShown() then fillPanel(plan) end
end

-- /hga swap: the banner with its list, also after the ×.
function Swap.Show()
	dismissed = nil
	if InCombatLockdown() then ns.Print("в бою список замен не показывается"); return end
	forced = true
	Swap.Refresh()
	if not banner:IsShown() then
		if not currentPlan then
			ns.Print(ns.Advisor.NotReadyText())
		else
			ns.Print("нечего надеть или снять с выгодой")
		end
		return
	end
	fillPanel(currentPlan)
	panel:Show()
end

ns.OnLoad(function()
	build()
	ns.OnInvalidate(Swap.Refresh)
end)

-- armor cannot be changed in combat: the banner goes away until combat ends
-- (PLAYER_REGEN_ENABLED re-evaluates everything, Commands.lua)
ns.On("PLAYER_REGEN_DISABLED", function()
	if banner then
		forced = false
		banner:Hide()
		panel:Hide()
	end
end)
