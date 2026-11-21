-- Pre-raid list: pure logic (no WoW API). Money text, prices from a price source the window builds,
-- craft cost from reagent prices, and the Russian card of where an item comes from (tag, head
-- line, lines, price rows, dim notes). The WoW glue (window, AtlasLoot, map pin, what the player
-- owns) is Game/PreRaid.lua. Colors are WoW escape codes (|cffRRGGBB ... |r).
local _, ns = ...
local PR = {}
ns.PreRaid = PR

-- palette of the window (docs: the canvas mockup of /hga preraid)
PR.COLOR = {
	gold = "ffd24a", silver = "c9ccd4", copper = "e0955a",
	text = "d8d2c2", soft = "b8b1a0", label = "8a8475", dim = "7d7768",
	good = "7fd36a", warn = "e0955a",
}
local C = PR.COLOR
local function paint(hex, s) return "|cff" .. hex .. s .. "|r" end
PR.Paint = paint

-- 1234567 copper -> "123з 45с 67м" (zero parts left out; 0 -> "0м")
local function moneyParts(copper)
	copper = math.floor(copper + 0.5)
	return math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
end
function PR.Money(copper)
	local g, s, c = moneyParts(copper)
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "з" end
	if s > 0 then parts[#parts + 1] = s .. "с" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "м" end
	return table.concat(parts, " ")
end

-- the same text, gold / silver / copper in the game's coin colors
function PR.MoneyColored(copper)
	local g, s, c = moneyParts(copper)
	local parts = {}
	if g > 0 then parts[#parts + 1] = paint(C.gold, g .. "з") end
	if s > 0 then parts[#parts + 1] = paint(C.silver, s .. "с") end
	if c > 0 or #parts == 0 then parts[#parts + 1] = paint(C.copper, c .. "м") end
	return table.concat(parts, " ")
end

-- Prices. The window hands the texts a price source (Game/PreRaid.lua builds it on Auctionator's external API), or
-- nil when it has none:
--   prices.auction(itemID) -> the lowest buyout of one item at the last scan that saw it (copper), or nil
--   prices.vendor(itemID)  -> what a merchant asks for one item (copper), or nil when no merchant seen sells it
--   prices.age(itemID)     -> whole days since the source last recorded the item's auction price, or nil when it
--                             gives none (what Auctionator's nil means: PR.AgeText)
-- A price that is missing stays missing: it is shown as missing and never counted as 0.

-- Price of one reagent: a merchant's price when a merchant sells it, else the auction price. Returns copper, where it
-- is paid ("торговец" / "аук") and, for an auction price, its age in days; nil when it has no price.
function PR.ReagentPrice(prices, itemID)
	if prices == nil then return nil end
	local vendor = prices.vendor(itemID)
	if vendor then return vendor, "торговец" end
	local auction = prices.auction(itemID)
	if auction then return auction, "аук", prices.age(itemID) end
	return nil
end

-- reagents = { {itemID, count}, ... }. Returns the copper of the priced ones, the itemIDs with no price (named to the
-- player, never counted as 0) and { itemID, age } of the ones whose auction price is not known to be today's.
function PR.CraftCost(prices, reagents)
	local total, missing, old = 0, {}, {}
	for _, r in ipairs(reagents) do
		local copper, paidAt, age = PR.ReagentPrice(prices, r[1])
		if copper == nil then
			missing[#missing + 1] = r[1]
		else
			total = total + copper * r[2]
			if paidAt == "аук" and age ~= 0 then old[#old + 1] = { r[1], age } end
		end
	end
	return total, missing, old
end

-- The age of an auction price in words: nil for today, "вчера", "N дн. назад"; no days read "возраст неизвестен".
-- Auctionator's doc comment of GetAuctionAgeByItemID says nil past 21 days (Source/API/v1/GetAuctionAge.lua), but
-- the GetPriceAge it returns (Source/Database/Mixin.lua) counts the days since the newest day the item's price was
-- recorded, with no cap, and gives nil only for an item with no day kept; the item's old days go only when its price
-- is recorded again (SetPrice). So a price 30 days old reads "30 дн. назад", and a price with no age has none known.
function PR.AgeText(days)
	if days == nil then return "возраст неизвестен" end
	if days == 0 then return nil end
	if days == 1 then return "вчера" end
	return days .. " дн. назад"
end

-- Auction price of one item for a price row: "85з 41с" in coin colors, then its age dim in brackets when the price
-- is not today's; "НА" when there is none. (No "·": the game's Cyrillic font draws it as a box.)
function PR.PriceText(prices, itemID)
	local copper = prices and prices.auction(itemID)
	if copper == nil then return paint(C.soft, "НА") end
	local age = PR.AgeText(prices.age(itemID))
	if age == nil then return PR.MoneyColored(copper) end
	return PR.MoneyColored(copper) .. paint(C.dim, " (" .. age .. ")")
end

local STANDING = { [4] = "Равнодушие", [5] = "Дружелюбие", [6] = "Уважение", [7] = "Почтение", [8] = "Превознесение" }
PR.STANDING = STANDING

-- source tag of each kind: label and its color (text and border)
PR.TAGS = {
	craft  = { "КРАФТ", "e0b26a" },
	quest  = { "КВЕСТ", "e8d36a" },
	rep    = { "РЕПУТАЦИЯ", "8fc1ff" },
	vendor = { "ТОРГОВЕЦ", "8fc1ff" },
	drop   = { "ПОДЗЕМЕЛЬЕ", "e89a7a" },
	trash  = { "ПОДЗЕМЕЛЬЕ", "e89a7a" },
	world  = { "МИРОВОЙ ДРОП", "c9a6e8" },
}

-- The card of one entry. ctx gives what only the game knows:
--   ctx.prices              -> the price source (above) or nil
--   ctx.name(itemID)        -> localized item name or nil (not cached yet)
--   ctx.icon(itemID)        -> icon file id/path or nil
--   ctx.standing(factionID) -> current standing id (1..8) or nil
--   ctx.zone(uiMapID)       -> localized zone name or nil
-- Returns { tag, tagColor, head, lines = {..}, prices = { {label, value, itemID?}, .. }, notes = {..} };
-- every string may carry color codes; a price row with itemID is paid in that item (the window
-- gives it a tooltip). No "·" anywhere: the game font draws it as a box.
function PR.Card(e, ctx)
	local tag = PR.TAGS[e.kind]
	if not tag then error("PreRaid: unknown kind " .. tostring(e.kind) .. " for item " .. tostring(e.id)) end
	local card = { tag = tag[1], tagColor = tag[2], lines = {}, prices = {}, notes = {} }
	local function line(s) card.lines[#card.lines + 1] = s end
	local function price(label, value, itemID) card.prices[#card.prices + 1] = { label, value, itemID } end
	local function note(s) card.notes[#card.notes + 1] = s end
	local function name(id) return (ctx.name and ctx.name(id)) or ("предмет " .. id) end
	local function place(npc)
		local zone = (ctx.zone and ctx.zone(npc.map)) or npc.zoneRu
		return string.format("%s — %s %.1f, %.1f", npc.name, zone, npc.x, npc.y)
	end
	-- vendor price: gold text ("~16з") or an item paid in N pieces (icon, name, count)
	local function cost()
		if e.costItem then
			local id, n = e.costItem[1], e.costItem[2]
			local icon = ctx.icon and ctx.icon(id)
			price("Цена", (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. paint(C.text, name(id))
				.. paint(C.gold, ", " .. n .. " шт."), id)
		elseif e.cost then
			price("Цена", paint(C.gold, e.cost))
		end
	end
	local head
	if e.kind == "craft" then
		head = e.prof .. " " .. e.skill
		local total, missing, old = PR.CraftCost(ctx.prices, e.reagents)
		-- no reagent priced: the cost is missing, not 0
		local c
		if #missing == #e.reagents then
			c = paint(C.warn, "нет цен на реагенты")
		elseif #missing > 0 then
			c = PR.MoneyColored(total) .. paint(C.warn, " + реагенты без цены")
		else
			c = PR.MoneyColored(total)
		end
		price("Стоимость крафта", c)
		price("Рецепт на аук.", PR.PriceText(ctx.prices, e.pattern))
		local function names(ids)
			local out = {}
			for _, id in ipairs(ids) do out[#out + 1] = name(id) end
			return table.concat(out, ", ")
		end
		if #missing > 0 then note(paint(C.warn, "Нет цены на: ") .. names(missing)) end
		if #old > 0 then
			local aged = {}
			for _, o in ipairs(old) do aged[#aged + 1] = name(o[1]) .. " (" .. PR.AgeText(o[2]) .. ")" end
			note(paint(C.warn, "Цена с аукциона не сегодняшняя: ") .. table.concat(aged, ", "))
		end
		-- the pattern's own name already starts with «Выкройка:»
		note(name(e.pattern) .. " — где падает: " .. (e.patternSource or "неизвестно"))
	elseif e.kind == "quest" then
		head = "«" .. e.quest .. "»"
		if e.npc then line((e.npcRole or "Выдаёт") .. ": " .. place(e.npc)) end
		if e.note then note(e.note) end
	elseif e.kind == "rep" then
		-- the needed standing right after the tag, then the faction (user: rank next to the tag)
		head = paint(C.good, STANDING[e.standing] or ("ранг " .. e.standing)) .. " — " .. e.faction
		local cur = ctx.standing and ctx.standing(e.factionId)
		if cur then
			line("У тебя: " .. paint(cur >= e.standing and C.good or C.text, STANDING[cur] or ("ранг " .. cur)))
		end
		line("Продавец: " .. place(e.npc))
		cost()
		if e.note then note(e.note) end
	elseif e.kind == "vendor" then
		line("Продавец: " .. place(e.npc))
		cost()
		if e.note then note(e.note) end
	elseif e.kind == "drop" or e.kind == "trash" then
		head = e.dungeon .. " — " .. e.boss
		if e.note then note(e.note) end
	elseif e.kind == "world" then
		if e.note then line(e.note) end
	end
	if e.reqLevel then head = (head and (head .. ", ") or "") .. paint(C.soft, "ур. " .. e.reqLevel) end
	card.head = head or ""
	if e.boe then
		price(e.kind == "craft" and "Готовый на аук." or "Аукцион",
			PR.PriceText(ctx.prices, e.id) .. paint(C.dim, " (BoE)"))
	end
	return card
end

-- a card as plain lines without color codes (tests, chat)
function PR.Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t ?", "")) end
function PR.CardLines(card)
	local out = { card.tag .. ": " .. PR.Plain(card.head) }
	for _, l in ipairs(card.lines) do out[#out + 1] = PR.Plain(l) end
	for _, p in ipairs(card.prices) do out[#out + 1] = p[1] .. ": " .. PR.Plain(p[2]) end
	for _, n in ipairs(card.notes) do out[#out + 1] = PR.Plain(n) end
	return out
end

return PR
