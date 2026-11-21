-- Pre-raid window (/hga preraid): which items of the best pre-raid set the player does not have
-- yet (worn, bags or bank) and where to get each one. Buttons: AtlasLoot page of the boss /
-- faction / recipe, and a map pin on the vendor or quest giver. Auction and merchant prices come
-- from Auctionator's external API when Auctionator is loaded. The data is Game/PreRaidData.lua,
-- the texts Core/PreRaid.lua.
local _, ns = ...
local PR = ns.PreRaid
local UI = {}
ns.PreRaidUI = UI

----------------------------------------------------------------------------------------------------
-- What the player has: worn, bags, bank. The bank is known to the client only after it was opened
-- in this session, so Syndicator's saved copy of the bank is read too (when Syndicator is loaded).
----------------------------------------------------------------------------------------------------
local function syndicatorBankHas(itemID)
	local api = Syndicator and Syndicator.API
	if not (api and api.GetCurrentCharacter and api.GetByCharacterFullName) then return false end
	local who = api.GetCurrentCharacter()
	local data = who and api.GetByCharacterFullName(who)
	if not data then return false end
	for _, field in ipairs({ "bank", "bankTabs" }) do
		for _, bag in pairs(data[field] or {}) do
			for _, slot in pairs((type(bag) == "table" and (bag.slots or bag)) or {}) do
				if type(slot) == "table" and slot.itemID == itemID then return true end
			end
		end
	end
	return false
end

function UI.Where(itemID)
	if C_Item.IsEquippedItem(itemID) then return "надето" end
	if C_Item.GetItemCount(itemID, false) > 0 then return "в сумках" end
	if C_Item.GetItemCount(itemID, true) > 0 or syndicatorBankHas(itemID) then return "в банке" end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Game context for the texts
----------------------------------------------------------------------------------------------------
-- The price source of the texts (Core/PreRaid.lua) on Auctionator's external API, nil when Auctionator is not
-- loaded. The API (Auctionator Source/API/v1, README.md there): GetAuctionPriceByItemID(callerID, itemID) -> the
-- last scanned price in copper or nil (GetAuctionPrice.lua); GetVendorPriceByItemID -> what a merchant the player
-- visited asks for one item, or nil (GetVendorPrice.lua); GetAuctionAgeByItemID -> the days since the item's price
-- was last recorded, or nil (GetAuctionAge.lua; what its nil means: Core/PreRaid.lua PR.AgeText). callerID is the
-- addon's name: the API throws on an empty one (Source/API/Internal.lua InternalVerifyID).
local function auctionatorPrices()
	if Auctionator == nil then return nil end
	local api = Auctionator.API.v1
	return {
		auction = function(id) return api.GetAuctionPriceByItemID(ns.name, id) end,
		vendor = function(id) return api.GetVendorPriceByItemID(ns.name, id) end,
		age = function(id) return api.GetAuctionAgeByItemID(ns.name, id) end,
	}
end

-- Item data the client is asked for: loading[id] is "asked" until ITEM_DATA_LOAD_RESULT answers (onItemData at
-- the end redraws the window), then nil, or "unknown" when the client cannot load the id - that id is not asked
-- again. Item names come from the client cache; a missing one is asked for once.
local loading = {}
local function askClient(id)
	loading[id] = "asked"
	C_Item.RequestLoadItemDataByID(id)
end
local function cachedName(id)
	local n = C_Item.GetItemNameByID(id)
	if not n and loading[id] == nil then askClient(id) end
	return n
end

local function context()
	return {
		prices = auctionatorPrices(),
		name = cachedName,
		icon = function(id) return (select(5, C_Item.GetItemInfoInstant(id))) end,
		-- Forever has C_Reputation.GetFactionDataByID (ReputationInfoDocumentation), not the old
		-- GetFactionInfoByID; reaction = standing 1..8. nil when the player has never met the faction.
		standing = function(factionID)
			local data = C_Reputation.GetFactionDataByID(factionID)
			return data and data.reaction
		end,
		zone = function(uiMapID)
			local info = C_Map.GetMapInfo(uiMapID)
			return info and info.name
		end,
	}
end

----------------------------------------------------------------------------------------------------
-- AtlasLoot: find the page (module, instance key, boss index) that lists an item, a craft spell or
-- a boss npc, then select it in AtlasLoot's own dropdowns (GUI.lua: moduleSelect, subCatSelect,
-- boss). AtlasLoot loads its data modules on demand: Loader:LoadModule calls back when loaded.
----------------------------------------------------------------------------------------------------
local function entryMatches(boss, want)
	if want.npc and boss.npcID == want.npc then return true end
	local id = want.item or want.spell
	if not id then return false end
	for k, list in pairs(boss) do
		if type(k) == "number" and type(list) == "table" then
			for _, e in ipairs(list) do
				if type(e) == "table" and (e[2] == id or e[2] == "i" .. id or e[2] == "s" .. id) then return true end
			end
		end
	end
	return false
end

function UI.FindAtlasPage(moduleData, want)
	for key, inst in pairs(moduleData) do
		if type(inst) == "table" and type(inst.items) == "table" then
			for bossIndex, boss in ipairs(inst.items) do
				if type(boss) == "table" and entryMatches(boss, want) then return key, bossIndex end
			end
		end
	end
	return nil
end

function UI.OpenAtlas(atlas, itemName)
	local AL = AtlasLoot
	if not (AL and AL.Loader and AL.ItemDB and AL.GUI) then
		ns.Print("AtlasLoot не загружен — страницу открыть нельзя.")
		return
	end
	local ran = false
	local state = AL.Loader:LoadModule(atlas.module, function()
		ran = true
		local moduleData = AL.ItemDB:Get(atlas.module)
		if not moduleData then
			ns.Print("AtlasLoot: модуль " .. atlas.module .. " не дал данных.")
			return
		end
		local key, bossIndex = UI.FindAtlasPage(moduleData, atlas)
		if not key then
			ns.Print("В AtlasLoot (" .. atlas.module .. ") нет страницы с " .. itemName .. ".")
			return
		end
		local gui = AL.GUI
		if not gui.frame then
			ns.Print("Окно AtlasLoot ещё не создано — открой его один раз (/al) и нажми снова.")
			return
		end
		if not gui.frame:IsShown() then gui.frame:Show() end
		gui.frame.moduleSelect:SetSelected(atlas.module)
		gui.frame.subCatSelect:SetSelected(key)
		-- Trash and other extra tables (ExtraList = true) are in AtlasLoot's "extra" list, not the
		-- boss list (GUI.lua SubCatSelectFunction); Select:SetSelected leaves selected nil when the id
		-- is not in its list, so the result is checked.
		local list = moduleData[key].items[bossIndex].ExtraList and gui.frame.extra or gui.frame.boss
		list:SetSelected(bossIndex)
		if not (list.selected and list.selected[2] == bossIndex) then
			ns.Print("AtlasLoot не выбрал страницу «" .. tostring(key) .. "» #" .. bossIndex .. " для " .. itemName .. ".")
		end
	end)
	if state == "InCombat" then
		ns.Print("AtlasLoot догрузит данные после боя и откроет страницу сам.")
	elseif state ~= true and state ~= nil then
		ns.Print("AtlasLoot: модуль " .. atlas.module .. " недоступен (" .. tostring(state) .. ").")
	elseif not ran and not (AL.Loader.IsModuleLoaded and AL.Loader:IsModuleLoaded(atlas.module)) then
		-- nil: the module is not in AtlasLoot's list (not installed), or it is being loaded now
		ns.Print("AtlasLoot: модуль " .. atlas.module .. " ещё не загружен или не установлен — нажми ещё раз через секунду.")
	end
end

----------------------------------------------------------------------------------------------------
-- Map pin on an npc: the client's own user waypoint (the yellow pin + super-track arrow), then the
-- world map opens on that zone.
----------------------------------------------------------------------------------------------------
function UI.ShowOnMap(npc)
	if not C_Map.CanSetUserWaypointOnMap(npc.map) then
		ns.Print("На этой карте нельзя поставить метку: " .. tostring(npc.map))
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(npc.map, npc.x / 100, npc.y / 100))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	OpenWorldMap(npc.map)
	ns.Print(string.format("Метка: %s, %.1f %.1f", npc.name, npc.x, npc.y))
end

----------------------------------------------------------------------------------------------------
-- Window. Flat dark panel drawn with color textures (no Blizzard tooltip border, no red buttons):
-- header with the progress bar, then one card per item — icon in a quality-colored frame, name in
-- the quality color, the slot, a colored source tag, the head line, lines, price rows in a column
-- and dim notes; flat buttons on the right; a thin scroll bar.
----------------------------------------------------------------------------------------------------
local WIDTH, HEIGHT, HEADER_H = 600, 640, 96
local BAR_W = 12                                   -- scroll bar column
local CONTENT_W = WIDTH - 2 - BAR_W                -- inside the 1px border
local PAD_L, PAD_R, PAD_Y, ICON, GAP = 14, 12, 12, 38, 12
local BUTTON_W, BUTTON_H = 86, 22
local TEXT_X = PAD_L + ICON + GAP
local TEXT_W = CONTENT_W - TEXT_X - GAP - BUTTON_W - PAD_R
local LABEL_W = 112                                -- price row label column
local WHEEL_STEP = 48

local function rgb(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local function fill(parent, hex, alpha, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	local r, g, b = rgb(hex)
	t:SetColorTexture(r, g, b, alpha or 1)
	return t
end
-- a 1px border of four textures; returns them so the color can change (item quality)
local function border(parent, hex, layer)
	local e = {}
	for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = fill(parent, hex, 1, layer or "BORDER")
		if side == "TOP" or side == "BOTTOM" then
			t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
		else
			t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
		end
		e[i] = t
	end
	function e.SetColor(r, g, b) for i = 1, 4 do e[i]:SetColorTexture(r, g, b, 1) end end
	return e
end
local function text(parent, font, hex)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if hex then fs:SetTextColor(rgb(hex)) end
	return fs
end

local frame, scroll, content, bar, thumb, progressFill, countText, priceSource
local rows = {}
local showAll = false

----------------------------------------------------------------------------------------------------
-- Shift-click search on the open auction house. Each auction window a client may have is an entry:
-- shown() - whether it is on screen; search(name) - puts the name into its search box and starts the
-- search when the page on screen lists results, else returns what to tell the player. The page is
-- left as the player set it: going to another page is the player's own click.
----------------------------------------------------------------------------------------------------
local AUCTION_WINDOWS = {
	-- Forever's auction house: Blizzard_AuctionHouseUI, Shared/Blizzard_AuctionHouseFrame.lua (wow-ui-source
	-- branch forever, "1.60.1 (70888)"; that branch has no Blizzard_AuctionUI). Its pages are the
	-- AuctionHouseFrameDisplayMode tables (line 485): the four buy pages (Buy, ItemBuy, CommoditiesBuy,
	-- WoWTokenBuy) hold the SearchBar, the sell and auctions pages do not. AuctionHouseFrame:SetSearchText
	-- (line 878) writes the name into the bar on a buy page and returns whether it did; the chat's Shift-click
	-- fills it the same way (Blizzard_ChatFrameBase/Mainline/ChatFrameUtilOverrides.lua:62-75). Elsewhere the
	-- bar is hidden, and it empties its box when it shows again (AuctionHouseSearchBarMixin:OnShow,
	-- Shared/Blizzard_AuctionHouseSearchBar.lua:177-178), so no name is left there. A search goes through
	-- SendBrowseQueryInternal, which sets the Buy page (Blizzard_AuctionHouseFrame.lua:825; SetDisplayMode
	-- returns at once when that page is already set, lines 560-562): HGA starts one on the Buy page alone, by
	-- the bar's own button as Blizzard's professions frame does (Blizzard_Professions/
	-- Blizzard_ProfessionsFrame.lua:965-966).
	{
		shown = function() return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsVisible() end,
		search = function(name)
			if not AuctionHouseFrame:SetSearchText(name) then
				return "На этой странице аукциона нет строки поиска: открой страницу покупки и снова Shift-клик по предмету."
			end
			if AuctionHouseFrame:GetDisplayMode() ~= AuctionHouseFrameDisplayMode.Buy then
				return "«" .. name .. "» в строке поиска аукциона — нажми «Поиск»."
			end
			AuctionHouseFrame.SearchBar.SearchButton:Click()
		end,
	},
	-- The classic auction window: Blizzard_AuctionUI, Classic/Blizzard_AuctionUI.lua and .xml (wow-ui-source
	-- branch classic_era, "1.15.9 (70576)"). The Browse tab is the frame AuctionFrameBrowse, which
	-- AuctionFrameTab_OnClick shows for tab 1 and hides for the others (lua:396-411); its name box BrowseName
	-- (xml:1024) keeps its text while another tab is open (AuctionFrameBrowse_Reset alone empties it,
	-- lua:512-513); AuctionFrameBrowse_Search (lua:679) searches for the box's text.
	{
		shown = function() return AuctionFrame ~= nil and AuctionFrame:IsVisible() end,
		search = function(name)
			BrowseName:SetText(name)
			if not AuctionFrameBrowse:IsVisible() then
				return "«" .. name .. "» в строке поиска аукциона — открой вкладку «Просмотр» и нажми «Поиск»."
			end
			AuctionFrameBrowse_Search()
		end,
	},
}

local function openAuctionWindow()
	for _, window in ipairs(AUCTION_WINDOWS) do
		if window.shown() then return window end
	end
	return nil
end

-- Click on an item of the window (icon, recipe, price item): Shift-click with the auction house open
-- searches it there; otherwise the game's own modified click (Shift: link in chat, Ctrl: dressing room).
local function itemClick(itemID)
	if not itemID then return end
	if loading[itemID] == "unknown" then ns.Print("Клиент не знает предмет " .. itemID .. ".") return end
	local name, link = C_Item.GetItemInfo(itemID)
	if not name then
		askClient(itemID)
		ns.Print("Данные предмета ещё не загружены — нажми ещё раз.")
		return
	end
	local auction = IsShiftKeyDown() and openAuctionWindow()
	if not auction then
		HandleModifiedItemClick(link)
		return
	end
	local tell = auction.search(name)
	if tell then ns.Print(tell) end
end

local function showItemTooltip(self)
	if self.itemID then ns.ShowTooltip(self, function(tip) tip:SetItemByID(self.itemID) end) end
end
local function hideTooltip() GameTooltip:Hide() end

-- flat button: dark fill, thin gold-brown border, light text on hover
local function makeButton(parent, label, onEnter, onLeave)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(BUTTON_W, BUTTON_H)
	b.bg = fill(b, "1f1d19")
	b.bg:SetAllPoints()
	b.edge = border(b, "4a3e24")
	b.label = text(b, "GameFontHighlightSmall", "d8c48e")
	b.label:SetJustifyH("CENTER")
	b.label:SetJustifyV("MIDDLE")
	b.label:SetAllPoints()
	b.label:SetText(label)
	b:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(rgb("2b2a26")); self.edge.SetColor(rgb("8a7440")); self.label:SetTextColor(rgb("f3e3b0"))
		if onEnter then onEnter(self) end
	end)
	b:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(rgb("1f1d19")); self.edge.SetColor(rgb("4a3e24")); self.label:SetTextColor(rgb("d8c48e"))
		if onLeave then onLeave(self) end
	end)
	return b
end

local function getRow(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Frame", nil, content)
	r:SetWidth(CONTENT_W)
	r.bg = fill(r, "ffffff", 0)
	r.bg:SetAllPoints()
	r.sep = fill(r, "24211c", 1, "BORDER")
	r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT"); r.sep:SetHeight(1)

	r.icon = CreateFrame("Button", nil, r)
	r.icon:SetSize(ICON, ICON)
	r.icon:SetPoint("TOPLEFT", PAD_L, -PAD_Y)
	r.icon.edge = border(r.icon, "4a4538", "OVERLAY")
	r.icon.tex = r.icon:CreateTexture(nil, "ARTWORK")
	r.icon.tex:SetPoint("TOPLEFT", 1, -1); r.icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	r.icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- crop the built-in icon border
	r.icon:SetScript("OnEnter", showItemTooltip)
	r.icon:SetScript("OnLeave", hideTooltip)
	r.icon:SetScript("OnClick", function(self) itemClick(self.itemID) end)

	r.name = text(r, "GameFontNormal")
	r.name:SetWordWrap(false)
	r.slot = text(r, "GameFontHighlightSmall", PR.COLOR.dim)
	r.badge = text(r, "GameFontHighlightSmall", PR.COLOR.good)
	r.badge:SetJustifyH("RIGHT")

	r.tag = CreateFrame("Frame", nil, r)
	r.tag:SetHeight(14)
	r.tag.edge = border(r.tag, "6b5326")
	r.tag.label = text(r.tag, "GameFontNormalSmall")
	r.tag.label:SetPoint("CENTER", 0, 0)
	r.tag.label:SetJustifyV("MIDDLE")
	r.head = text(r, "GameFontHighlightSmall", PR.COLOR.text)
	r.pool, r.used = {}, 0
	-- hover areas over price rows paid in an item: its tooltip, Shift-click puts the link in chat
	r.hits, r.hitsUsed = {}, 0

	r.atlas = makeButton(r, "AtlasLoot")
	r.map = makeButton(r, "На карте")
	-- the recipe of a craft: tooltip on hover; Shift-click searches it on the open auction house,
	-- else puts its link into chat; a plain click prints the link
	r.recipe = makeButton(r, "Рецепт", showItemTooltip, hideTooltip)
	r.recipe:SetScript("OnClick", function(self)
		if IsModifiedClick() then return itemClick(self.itemID) end
		local link = select(2, C_Item.GetItemInfo(self.itemID))
		if link then ns.Print("Рецепт: " .. link .. " (Shift-клик — поиск на аукционе или ссылка в чат)")
		else itemClick(self.itemID) end
	end)
	rows[i] = r
	return r
end

-- a font string of the row's pool, placed at (x, -y) with width w
local function take(r, font, hex, x, y, w, s)
	r.used = r.used + 1
	local fs = r.pool[r.used]
	if not fs then fs = text(r, font); r.pool[r.used] = fs end
	fs:SetFontObject(font)
	fs:SetTextColor(rgb(hex))
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", x, -y)
	fs:SetWidth(w)
	fs:SetText(s)
	fs:Show()
	return fs
end

local function itemName(id)
	return cachedName(id) or ("предмет " .. id .. (loading[id] == "unknown" and " (нет в клиенте)" or ""))
end

local function qualityRGB(id)
	local q = C_Item.GetItemQualityByID(id)
	if not q then return nil end
	local r, g, b = C_Item.GetItemQualityColor(q)
	return r, g, b
end

-- lays out one card; returns the row height
local function fillRow(r, it, ctx, odd)
	local e = it.e
	local card = PR.Card(e, ctx)
	r.used = 0
	if it.where then r.bg:SetColorTexture(rgb("5fae4e")); r.bg:SetAlpha(0.07)
	else r.bg:SetColorTexture(1, 1, 1); r.bg:SetAlpha(odd and 0.018 or 0) end

	r.icon.itemID = e.id
	r.icon.tex:SetTexture(select(5, C_Item.GetItemInfoInstant(e.id)))
	r.icon.tex:SetDesaturated(it.where ~= nil)
	local qr, qg, qb = qualityRGB(e.id)
	if qr then r.icon.edge.SetColor(qr, qg, qb); r.name:SetTextColor(qr, qg, qb)
	else r.icon.edge.SetColor(rgb("4a4538")); r.name:SetTextColor(rgb(PR.COLOR.text)) end

	-- line 1: name, slot, owned badge on the right
	r.badge:SetText(it.where and ("есть: " .. it.where) or "")
	local badgeW = it.where and (r.badge:GetUnboundedStringWidth() + 8) or 0
	r.slot:SetText(e.slotRu)
	local slotW = r.slot:GetUnboundedStringWidth()
	r.name:SetText(itemName(e.id))
	local nameW = math.min(r.name:GetUnboundedStringWidth() + 2, TEXT_W - slotW - 8 - badgeW)
	r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", TEXT_X, -PAD_Y); r.name:SetWidth(nameW)
	r.slot:ClearAllPoints(); r.slot:SetPoint("BOTTOMLEFT", r.name, "BOTTOMRIGHT", 8, 0)
	r.badge:ClearAllPoints(); r.badge:SetPoint("TOPRIGHT", r, "TOPLEFT", TEXT_X + TEXT_W, -PAD_Y - 1)
	local y = PAD_Y + r.name:GetStringHeight() + 5

	-- line 2: source tag and the head line
	r.tag.label:SetText(card.tag)
	r.tag.label:SetTextColor(rgb(card.tagColor))
	local tr, tg, tb = rgb(card.tagColor)
	r.tag.edge.SetColor(tr * 0.5, tg * 0.5, tb * 0.5)
	local tagW = r.tag.label:GetUnboundedStringWidth() + 10
	r.tag:SetWidth(tagW)
	r.tag:ClearAllPoints(); r.tag:SetPoint("TOPLEFT", TEXT_X, -y)
	r.head:ClearAllPoints(); r.head:SetPoint("TOPLEFT", TEXT_X + tagW + 6, -y - 1)
	r.head:SetWidth(TEXT_W - tagW - 6)
	r.head:SetText(card.head)
	y = y + math.max(14, r.head:GetStringHeight() + 1) + 4

	for _, l in ipairs(card.lines) do
		local fs = take(r, "GameFontHighlightSmall", PR.COLOR.soft, TEXT_X, y, TEXT_W, l)
		y = y + fs:GetStringHeight() + 3
	end
	if #card.prices > 0 then y = y + 1 end
	r.hitsUsed = 0
	for _, p in ipairs(card.prices) do
		take(r, "GameFontHighlightSmall", PR.COLOR.label, TEXT_X, y, LABEL_W - 6, p[1])
		local v = take(r, "GameFontHighlightSmall", PR.COLOR.text, TEXT_X + LABEL_W, y, TEXT_W - LABEL_W, p[2])
		if p[3] then
			r.hitsUsed = r.hitsUsed + 1
			local hit = r.hits[r.hitsUsed]
			if not hit then
				hit = CreateFrame("Button", nil, r)
				hit:SetScript("OnEnter", showItemTooltip)
				hit:SetScript("OnLeave", hideTooltip)
				hit:SetScript("OnClick", function(self) itemClick(self.itemID) end)
				r.hits[r.hitsUsed] = hit
			end
			hit.itemID = p[3]
			hit:ClearAllPoints()
			hit:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X + LABEL_W, -y)
			hit:SetSize(math.min(v:GetUnboundedStringWidth(), TEXT_W - LABEL_W), v:GetStringHeight())
			hit:Show()
		end
		y = y + v:GetStringHeight() + 2
	end
	for i = r.hitsUsed + 1, #r.hits do r.hits[i]:Hide() end
	if #card.prices > 0 then y = y + 2 end
	for _, n in ipairs(card.notes) do
		local fs = take(r, "GameFontHighlightSmall", PR.COLOR.dim, TEXT_X, y, TEXT_W, n)
		y = y + fs:GetStringHeight() + 2
	end
	for i = r.used + 1, #r.pool do r.pool[i]:Hide() end

	-- buttons stacked top-right, only the ones this item has
	local by = PAD_Y
	local function place(b, show)
		b:SetShown(show)
		if not show then return end
		b:ClearAllPoints(); b:SetPoint("TOPRIGHT", r, "TOPRIGHT", -PAD_R, -by)
		by = by + BUTTON_H + 4
	end
	place(r.atlas, e.atlas ~= nil)
	r.atlas:SetScript("OnClick", function() UI.OpenAtlas(e.atlas, itemName(e.id)) end)
	place(r.map, e.npc ~= nil)
	r.map:SetScript("OnClick", function() UI.ShowOnMap(e.npc) end)
	place(r.recipe, e.pattern ~= nil)
	r.recipe.itemID = e.pattern

	return math.max(y + PAD_Y - 2, PAD_Y * 2 + ICON, by + PAD_Y - 4)
end

-- Thin scroll bar (drag the thumb or use the wheel). The thumb's length is the share of the list in
-- view, at least THUMB_MIN; its top moves along the track's free length as the offset goes from 0 to
-- the scroll range.
local THUMB_MIN = 24
local function thumbGeometry(trackLength, viewLength, range, offset)
	local length = math.max(THUMB_MIN, trackLength * viewLength / (viewLength + range))
	return length, (trackLength - length) * offset / range
end

-- Puts the list at `offset` kept within 0..range, then the thumb. A list that got shorter keeps its
-- old offset in the ScrollFrame, so it is brought back within the range here (Blizzard's scroll bars
-- do the same by hand: Blizzard_SharedXML/SecureScrollTemplates.lua:74, ScrollFrame_OnScrollRangeChanged).
-- The bar shows while the list is longer than the view.
local function showAt(offset)
	local maxOffset = scroll:GetVerticalScrollRange()
	local kept = math.max(0, math.min(maxOffset, offset))
	if kept ~= scroll:GetVerticalScroll() then scroll:SetVerticalScroll(kept) end
	local scrolls = maxOffset > 0
	bar:SetShown(scrolls)
	if scrolls then
		local length, top = thumbGeometry(bar:GetHeight(), scroll:GetHeight(), maxOffset, kept)
		thumb:SetHeight(length)
		thumb:SetPoint("TOP", bar, "TOP", 0, -top) -- the thumb's only anchor: this one replaces it
	end
end
-- the bar again at the list's own offset (a new list, a new range)
local function refreshBar() showAt(scroll:GetVerticalScroll()) end

function UI.Refresh()
	if not (frame and frame:IsShown()) then return end
	local ctx = context()
	local list, missing = {}, 0
	for _, e in ipairs(ns.PreRaidData.items) do
		local where = UI.Where(e.id)
		if not where then missing = missing + 1 end
		if showAll or not where then list[#list + 1] = { e = e, where = where } end
	end
	local total = #ns.PreRaidData.items
	local have = total - missing
	countText:SetText("Собрано " .. PR.Paint(PR.COLOR.good, tostring(have)) .. " из " .. total)
	progressFill:SetShown(have > 0)
	progressFill:SetWidth(math.max(1, progressFill.maxW * have / total))
	if ctx.prices then
		priceSource:SetText("Цены — Auctionator")
	else
		priceSource:SetText(PR.Paint(PR.COLOR.warn, "Auctionator не загружен — цен аукциона и торговцев нет"))
	end
	local y = 0
	for i, it in ipairs(list) do
		local r = getRow(i)
		local h = fillRow(r, it, ctx, i % 2 == 0)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		r:SetHeight(h)
		r:Show()
		y = y + h
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	content:SetHeight(math.max(y, 1))
	refreshBar()
end

-- A window frame: in the screen's center, above the game's panels (strata HIGH), kept on the screen,
-- moved while the left button drags it (StartMoving / StopMovingOrSizing need SetMovable and the
-- mouse on), closed by Esc: CloseSpecialWindows hides the shown frames whose names UISpecialFrames
-- lists (Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:1106-1116).
local function windowFrame(name, width, height)
	local w = CreateFrame("Frame", name, UIParent)
	w:SetSize(width, height)
	w:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	w:SetFrameStrata("HIGH")
	w:SetClampedToScreen(true)
	w:EnableMouse(true)
	w:SetMovable(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", function(self) self:StartMoving() end)
	w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	table.insert(UISpecialFrames, name)
	return w
end

local function create()
	frame = windowFrame("HunterGearAdvisorPreRaid", WIDTH, HEIGHT)
	local bg = fill(frame, "0e0d0c", 0.96)
	bg:SetAllPoints()
	border(frame, "5a4a28", "OVERLAY")

	-- header
	local hbg = fill(frame, "1a1815", 1, "BORDER")
	hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1); hbg:SetHeight(HEADER_H)
	local hline = fill(frame, "3a3122", 1, "ARTWORK")
	hline:SetPoint("TOPLEFT", 1, -1 - HEADER_H); hline:SetPoint("TOPRIGHT", -1, -1 - HEADER_H); hline:SetHeight(1)
	local title = text(frame, "GameFontNormalLarge", "e8c66a")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Пререйд-набор")
	local sub = text(frame, "GameFontHighlightSmall", "9a9384")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	sub:SetText("Лучший набор для BM, хит-кап 8%")

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -12, -12)
	close.edge = border(close, "3a3122")
	for _, deg in ipairs({ 45, -45 }) do
		local l = fill(close, "9a9384", 1, "ARTWORK")
		l:SetSize(12, 1.5); l:SetPoint("CENTER"); l:SetRotation(math.rad(deg))
		close[deg] = l
	end
	close:SetScript("OnEnter", function(self) self.edge.SetColor(rgb("8a7440")); self[45]:SetColorTexture(rgb("f3e3b0")); self[-45]:SetColorTexture(rgb("f3e3b0")) end)
	close:SetScript("OnLeave", function(self) self.edge.SetColor(rgb("3a3122")); self[45]:SetColorTexture(rgb("9a9384")); self[-45]:SetColorTexture(rgb("9a9384")) end)
	close:SetScript("OnClick", function() frame:Hide() end)

	countText = text(frame, "GameFontHighlightSmall", PR.COLOR.text)
	countText:SetJustifyH("RIGHT")
	countText:SetPoint("TOPRIGHT", -16, -52)
	countText:SetWidth(110)
	local track = fill(frame, "2b2721", 1, "ARTWORK")
	track:SetPoint("TOPLEFT", 16, -55); track:SetPoint("TOPRIGHT", -136, -55); track:SetHeight(6)
	progressFill = fill(frame, "5fae4e", 1, "OVERLAY")
	progressFill:SetPoint("TOPLEFT", track, "TOPLEFT"); progressFill:SetHeight(6)
	progressFill.maxW = WIDTH - 16 - 136

	local all = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	all:SetPoint("TOPLEFT", 12, -68)
	all:SetSize(20, 20)
	all.label = text(all, "GameFontHighlightSmall", PR.COLOR.soft)
	all.label:SetPoint("LEFT", all, "RIGHT", 2, 0)
	all.label:SetText("Показать собранное")
	all:SetScript("OnClick", function(self) showAll = self:GetChecked() and true or false; UI.Refresh() end)
	priceSource = text(frame, "GameFontHighlightSmall", "6e685c")
	priceSource:SetPoint("LEFT", all.label, "RIGHT", 18, 0)

	-- list
	scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", 1, -2 - HEADER_H)
	scroll:SetPoint("BOTTOMRIGHT", -1 - BAR_W, 1)
	-- the cards' parent: as wide as the list, its height set by each redraw
	content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(CONTENT_W)
	content:SetHeight(1)
	scroll:SetScrollChild(content)

	bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -6)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 6)
	bar:SetWidth(4)
	thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(4)
	thumb.tex = fill(thumb, "4a4234", 1, "ARTWORK")
	thumb.tex:SetAllPoints()
	thumb:SetHitRectInsets(-4, -4, 0, 0)
	thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(rgb("8a7440")) end)
	thumb:SetScript("OnLeave", function(self) if not self.drag then self.tex:SetColorTexture(rgb("4a4234")) end end)
	thumb:SetScript("OnMouseDown", function(self)
		local _, cy = GetCursorPosition()
		self.drag = { y = cy / self:GetEffectiveScale(), scroll = scroll:GetVerticalScroll() }
	end)
	thumb:SetScript("OnMouseUp", function(self)
		self.drag = nil
		if not self:IsMouseOver() then self.tex:SetColorTexture(rgb("4a4234")) end
	end)
	thumb:SetScript("OnUpdate", function(self)
		if not self.drag then return end
		local _, cy = GetCursorPosition()
		local dy = self.drag.y - cy / self:GetEffectiveScale()
		local free = bar:GetHeight() - self:GetHeight()
		if free > 0 then showAt(self.drag.scroll + dy * scroll:GetVerticalScrollRange() / free) end
	end)
	-- the list's scripts once the bar and the thumb they draw exist: the wheel moves the list by WHEEL_STEP; a new
	-- scroll range (the list's height changed) redraws the bar
	scroll:SetScript("OnScrollRangeChanged", refreshBar)
	scroll:SetScript("OnMouseWheel", function(self, delta) showAt(self:GetVerticalScroll() - delta * WHEEL_STEP) end)
	scroll:EnableMouseWheel(true)

	frame:SetScript("OnShow", UI.Refresh)
	frame:Hide() -- a new frame is shown; Toggle below must open it on the first call
end

function UI.Toggle()
	if not frame then create() end
	frame:SetShown(not frame:IsShown())
end

-- Names, icons and quality colors arrive with item data: C_Item.RequestLoadItemDataByID answers
-- with ITEM_DATA_LOAD_RESULT (Blizzard_ObjectAPI AsyncCallbackSystem.lua), older paths with
-- GET_ITEM_INFO_RECEIVED. Many arrive at once, so one redraw per burst.
-- An id the client cannot load answers success = false: it is reported once and not asked again
-- (asking on every redraw would redraw forever).
local refreshQueued = false
local function queueRefresh()
	if refreshQueued or not (frame and frame:IsShown()) then return end
	refreshQueued = true
	C_Timer.After(0.2, function() refreshQueued = false; UI.Refresh() end)
end
local function onItemData(_, itemID, success)
	if not itemID or loading[itemID] ~= "asked" then return end
	if success == false then
		loading[itemID] = "unknown"
		geterrorhandler()("HunterGearAdvisor: клиент не знает предмет " .. itemID .. " (список пререйда)")
	else
		loading[itemID] = nil
	end
	queueRefresh()
end
ns.OnInvalidate(UI.Refresh)
ns.On("GET_ITEM_INFO_RECEIVED", onItemData)
ns.On("ITEM_DATA_LOAD_RESULT", onItemData)
ns.On("BANKFRAME_OPENED", function() ns.Invalidate() end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() ns.Invalidate() end)
ns.On("UPDATE_FACTION", queueRefresh)
