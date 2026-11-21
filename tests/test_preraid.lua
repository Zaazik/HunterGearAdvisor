-- Core/PreRaid.lua (pure texts: cards) and the integrity of Game/PreRaidData.lua.
return function(ns, T)
	local PR = ns.PreRaid
	-- A price source as the window builds it (Core/PreRaid.lua: auction, vendor and age by item id): Eaglehorn Long Bow
	-- 13023 listed yesterday, the Dawn Armor pattern 252892 three days ago, Rugged Leather 8170 today; Black Dye 14341
	-- sold by a merchant and listed today too; Black Dragonscale 15416 has no price. `extra` adds auction prices and ages.
	local function source(extra)
		local auction = { [13023] = 854100, [252892] = 11758999, [8170] = 1500, [14341] = 4900 }
		local age = { [13023] = 1, [252892] = 3, [8170] = 0, [14341] = 0 }
		local vendor = { [14341] = 5000 }
		for id, a in pairs(extra or {}) do auction[id], age[id] = a[1], a[2] end
		return {
			auction = function(id) return auction[id] end,
			vendor = function(id) return vendor[id] end,
			age = function(id) return age[id] end,
		}
	end
	local function ctx(over)
		local c = { prices = source(),
			name = function(id) return ({ [252892] = "Выкройка: Броня рассвета", [15416] = "Черная драконья чешуя",
				[8170] = "Грубая кожа" })[id] end,
			standing = function() return 5 end,
			zone = function(map) return ({ [1413] = "Степи" })[map] end }
		for k, v in pairs(over or {}) do c[k] = v end
		return c
	end
	local function has(lines, pat)
		for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
		return false
	end
	local function lines(e, c) return PR.CardLines(PR.Card(e, c)) end

	return {
		{ "money text", function()
			T.eq(PR.Money(854100), "85з 41с", "gold silver")
			T.eq(PR.Money(0), "0м", "zero")
			T.eq(PR.Money(10005), "1з 5м", "no silver part")
		end },
		{ "money in coin colors", function()
			T.eq(PR.Plain(PR.MoneyColored(854100)), "85з 41с", "plain")
			T.truthy(PR.MoneyColored(854100):find("|cffffd24a85з|r", 1, true), "gold colored")
		end },
		-- the rules of a reagent's price (PR.ReagentPrice): a merchant's price first, the auction price with its age
		-- second, nil when neither knows it or there is no price source (no Auctionator)
		{ "reagent price: merchant first, then the auction with its age, else none", function()
			local p, at, age = PR.ReagentPrice(source(), 14341)
			T.eq(p, 5000, "the merchant's price, though the auction has 49s"); T.eq(at, "торговец"); T.eq(age, nil, "no age")
			p, at, age = PR.ReagentPrice(source(), 252892)
			T.eq(p, 11758999, "auction price"); T.eq(at, "аук"); T.eq(age, 3, "its age in days")
			T.eq(PR.ReagentPrice(source(), 15416), nil, "no price anywhere")
			T.eq(PR.ReagentPrice(nil, 14341), nil, "no price source")
		end },
		{ "price text: today's price bare, an older one with its age in days, НА when missing", function()
			T.eq(PR.Plain(PR.PriceText(source(), 8170)), "15с", "today: no age")
			T.eq(PR.Plain(PR.PriceText(source(), 13023)), "85з 41с (вчера)", "listed yesterday")
			T.eq(PR.Plain(PR.PriceText(source(), 252892)), "1175з 89с 99м (3 дн. назад)", "listed 3 days ago")
			T.eq(PR.Plain(PR.PriceText(source({ [15416] = { 100, nil } }), 15416)), "1с (возраст неизвестен)",
				"a price whose age the source does not give")
			T.eq(PR.Plain(PR.PriceText(source(), 999)), "НА", "never listed")
			T.eq(PR.Plain(PR.PriceText(source(), 14341)), "49с", "a merchant's price is no auction price")
			T.eq(PR.Plain(PR.PriceText(nil, 13023)), "НА", "no price source")
		end },
		{ "craft cost: merchant and auction prices summed; a reagent without a price is named, never counted as 0", function()
			local total, missing, old = PR.CraftCost(source(), { { 8170, 20 }, { 14341, 2 }, { 15416, 40 } })
			T.eq(total, 20 * 1500 + 2 * 5000, "total")
			T.eq(#missing, 1, "one missing"); T.eq(missing[1], 15416, "missing id")
			T.eq(#old, 0, "today's auction price and a merchant's price are not old")
			local craft = { id = 9, kind = "craft", prof = "К", skill = 300, pattern = 1, reagents = { { 15416, 2 } } }
			local L = lines(craft, ctx())
			T.truthy(has(L, "Стоимость крафта: нет цен на реагенты"), "no reagent priced: the cost is missing")
			T.truthy(not has(L, "Стоимость крафта: 0м"), "not 0")
			T.truthy(has(L, "Нет цены на: Черная драконья чешуя"), "named")
			local none = ctx(); none.prices = nil
			T.truthy(has(lines(craft, none), "Стоимость крафта: нет цен на реагенты"), "no price source")
		end },
		{ "craft card: reagents priced from an older auction listing are named with their age", function()
			local prices = source({ [8170] = { 1500, 2 }, [15416] = { 100, nil } })
			local total, missing, old = PR.CraftCost(prices, { { 8170, 1 }, { 15416, 2 } })
			T.eq(total, 1500 + 2 * 100, "old prices still count"); T.eq(#missing, 0, "none missing")
			T.eq(#old, 2, "both old"); T.eq(old[1][1], 8170); T.eq(old[1][2], 2); T.eq(old[2][1], 15416); T.eq(old[2][2], nil)
			local L = lines({ id = 9, kind = "craft", prof = "К", skill = 300, pattern = 1, reagents = { { 8170, 1 }, { 15416, 2 } } },
				ctx({ prices = prices }))
			T.truthy(has(L, "Цена с аукциона не сегодняшняя: Грубая кожа (2 дн. назад), Черная драконья чешуя (возраст неизвестен)"),
				"old prices named")
		end },
		{ "card: quest npc label can be set per entry", function()
			local npc = { name = "доска", map = 1425, x = 79.1, y = 79.0, zoneRu = "Внутренние земли" }
			T.truthy(has(lines({ id = 19120, kind = "quest", quest = "Q", npc = npc, npcRole = "Взять" }, ctx()), "Взять: доска"), "role")
		end },
		{ "card: craft shows profession, recipe price, cost and missing reagents", function()
			local e = { id = 252483, kind = "craft", boe = true, prof = "Кожевничество", skill = 300, pattern = 252892,
				patternSource = "неизвестно ни одному сайту", reagents = { { 8170, 20 }, { 15416, 40 } }, reqLevel = 56 }
			local card = PR.Card(e, ctx())
			T.eq(card.tag, "КРАФТ", "tag")
			T.eq(PR.Plain(card.head), "Кожевничество 300, ур. 56", "head")
			local L = PR.CardLines(card)
			T.truthy(has(L, "Стоимость крафта: 3з + реагенты без цены"), "cost + missing mark")
			T.truthy(has(L, "Нет цены на: Черная драконья чешуя"), "missing named")
			T.truthy(has(L, "Рецепт на аук.: 1175з 89с 99м (3 дн. назад)"), "recipe price with its age")
			T.truthy(has(L, "Готовый на аук.: НА (BoE)"), "BoE item price")
			T.truthy(has(L, "Выкройка: Броня рассвета — где падает: неизвестно ни одному сайту"), "pattern source")
			T.eq(card.prices[1][1], "Стоимость крафта", "cost first")
		end },
		{ "card: drop, rep with current standing, vendor, quest, world", function()
			local d = PR.Card({ id = 1, kind = "drop", dungeon = "Стратхольм", boss = "Барон Ривендер", reqLevel = 58 }, ctx())
			T.eq(d.tag, "ПОДЗЕМЕЛЬЕ"); T.eq(PR.Plain(d.head), "Стратхольм — Барон Ривендер, ур. 58", "drop head")
			local npc = { name = "Криг Ботмяс", map = 1413, x = 65.0, y = 34.6, zoneRu = "fallback" }
			local L = lines({ id = 2, kind = "rep", faction = "Налетчики Черного Копья", factionId = 2798, standing = 8, npc = npc, cost = "~16з" }, ctx())
			T.truthy(has(L, "РЕПУТАЦИЯ: Превознесение — Налетчики Черного Копья"), "rep head: needed standing next to the tag")
			T.truthy(has(L, "У тебя: Дружелюбие"), "current standing")
			T.truthy(has(L, "Продавец: Криг Ботмяс — Степи 65.0, 34.6"), "vendor place from the game zone name")
			T.truthy(has(L, "Цена: ~16з"), "price row")
			local L2 = lines({ id = 2, kind = "rep", faction = "F", factionId = 1, standing = 7, npc = npc },
				ctx({ standing = function() return nil end, zone = function() return nil end }))
			T.truthy(has(L2, "РЕПУТАЦИЯ: Почтение — F"), "rep without standing")
			T.truthy(not has(L2, "У тебя"), "no standing shown when unknown")
			T.truthy(has(L2, "fallback 65.0, 34.6"), "zone fallback")
			T.truthy(has(lines({ id = 3, kind = "quest", quest = "За Орду!", questId = 4974, npc = npc }, ctx()), "КВЕСТ: «За Орду!»"), "quest")
			T.truthy(has(lines({ id = 4, kind = "world", boe = true, note = "x" }, ctx()), "x"), "world note")
			T.truthy(has(lines({ id = 13023, kind = "world", boe = true }, ctx()), "Аукцион: 85з 41с (вчера) (BoE)"), "world BoE price")
			local v = PR.Card({ id = 5, kind = "vendor", npc = npc, costItem = { 226404, 75 } },
				ctx({ name = function(id) return id == 226404 and "Потускневший реал" or nil end, icon = function() return 133784 end }))
			T.truthy(has(PR.CardLines(v), "Цена: Потускневший реал, 75 шт."), "vendor price in an item")
			T.eq(v.prices[1][3], 226404, "price row carries the item for the tooltip")
			T.truthy(v.prices[1][2]:find("|T133784:14:14:0:0|t", 1, true), "item icon inline")
		end },
		{ "card: unknown kind is an error, not a silent blank", function()
			local ok, err = pcall(PR.Card, { id = 5, kind = "nope" }, ctx())
			T.eq(ok, false, "errors"); T.truthy(tostring(err):find("unknown kind", 1, true), "message")
		end },
		{ "pre-raid data: every entry is complete and describable", function()
			local G = setmetatable({}, { __index = _G })
			local dns = {}
			assert(loadfile("Game/PreRaidData.lua", "t", G))("HunterGearAdvisor", dns)
			local items = dns.PreRaidData.items
			T.eq(#items, 16, "16 slots")
			local seen = {}
			local MODULES = { AtlasLootClassic_DungeonsAndRaids = 1, AtlasLootClassic_PvP = 1, AtlasLootClassic_Crafting = 1 }
			for _, e in ipairs(items) do
				T.truthy(type(e.id) == "number" and not seen[e.id], "unique id " .. tostring(e.id)); seen[e.id] = true
				T.truthy(e.slotRu, "slot " .. e.id)
				if e.npc then
					T.truthy(e.npc.name and e.npc.map and e.npc.x and e.npc.y and e.npc.zoneRu, "npc fields " .. e.id)
				end
				if e.kind == "rep" or e.kind == "vendor" then T.truthy(e.npc, "vendor npc " .. e.id) end
				if e.kind == "rep" then T.truthy(e.factionId and e.standing and e.faction, "faction " .. e.id) end
				if e.kind == "craft" then T.truthy(e.pattern and #e.reagents > 0 and e.prof and e.skill, "craft " .. e.id) end
				if e.atlas then
					T.truthy(MODULES[e.atlas.module], "atlas module " .. e.id)
					T.truthy(e.atlas.item or e.atlas.spell or e.atlas.npc, "atlas target " .. e.id)
				end
				T.truthy(#PR.CardLines(PR.Card(e, ctx())) > 0, "card " .. e.id)
				-- the game's Cyrillic font has no middle dot: it shows as a box (seen in game)
				local c = PR.Card(e, ctx())
				for _, str in ipairs({ c.head, table.unpack(c.lines) }) do T.truthy(not str:find("·", 1, true), "no middle dot " .. e.id) end
				for _, pr in ipairs(c.prices) do T.truthy(not pr[2]:find("·", 1, true), "no middle dot in price " .. e.id) end
			end
		end },
		-- Game/PreRaidData.lua's crafts come from the client DB2 and foreverdb.net (its head): each craft card names where
		-- the pattern comes from; both Devilsaur patterns need Tribal Leatherworking (ItemSparse RequiredAbility 10660,
		-- 15758 and 15772); the two new Forever patterns have no known source; no text names Mastercraft
		{ "pre-raid data: pattern sources, the Devilsaur specialization, no Mastercraft", function()
			local G = setmetatable({}, { __index = _G })
			local dns = {}
			assert(loadfile("Game/PreRaidData.lua", "t", G))("HunterGearAdvisor", dns)
			local byId = {}
			for _, e in ipairs(dns.PreRaidData.items) do byId[e.id] = e end
			local function walk(v, path)
				if type(v) == "string" then T.truthy(not v:lower():find("mastercraft", 1, true), "no Mastercraft in " .. path)
				elseif type(v) == "table" then for k, x in pairs(v) do walk(x, path .. "." .. tostring(k)) end end
			end
			walk(dns.PreRaidData, "PreRaidData")
			for _, id in ipairs({ 15063, 15062 }) do
				T.eq(byId[id].kind, "craft")
				T.truthy(byId[id].patternSource:find("требует специализации «Кожевничество: традиции предков»", 1, true), "specialization " .. id)
			end
			T.truthy(byId[15063].patternSource:find("торговец Nergal, Кратер Ун'Горо, 2з 20с", 1, true), "the gauntlets' vendor")
			T.truthy(byId[15062].patternSource:find("слизни Glutinous, Primal, Cloned и Muculent Ooze, 0.9–1.1%", 1, true), "the leggings' drop")
			T.eq(byId[252605].patternSource, "источник выкройки не найден"); T.eq(byId[252483].patternSource, "источник выкройки не найден")
			for _, e in ipairs(dns.PreRaidData.items) do
				if e.kind == "craft" then
					T.truthy(has(lines(e, ctx()), "где падает: " .. e.patternSource), "pattern source on the card " .. e.id)
				end
			end
		end },
		-- tools/preraid/ah.lua reads the price database Auctionator saves (the layout in its head); loaded with no
		-- arguments it returns its functions. A house may be saved as CBOR (RFC 8949): the vectors below by hand
		{ "ah.lua: CBOR integers, strings, maps, arrays, floats, tags and indefinite lengths", function()
			local AH = assert(loadfile("tools/preraid/ah.lua"))()
			local function bytes(hex) return (hex:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end
			local cbor = function(hex) return AH.DecodeCBOR(bytes(hex)) end
			T.eq(cbor("17"), 23, "a small integer"); T.eq(cbor("1a000d0854"), 854100, "4-byte unsigned"); T.eq(cbor("3863"), -100, "negative")
			T.eq(cbor("fb412a10a800000000"), 854100, "double"); T.eq(cbor("fb3fb999999999999a"), 0.1, "a double's fraction exact")
			T.eq(cbor("fa47c35000"), 100000, "single"); T.eq(cbor("f93e00"), 1.5, "half"); T.eq(cbor("f9c000"), -2, "negative half")
			T.eq(cbor("6432313439"), "2149", "text"); T.eq(cbor("7f626162616" .. "3ff"), "abc", "indefinite text")
			T.eq(cbor("c1182a"), 42, "a tag keeps its item")
			local map = cbor("a2616d1903e8616182f5f6") -- { m = 1000, a = { true, null } }
			T.eq(map.m, 1000); T.eq(map.a[1], true); T.eq(map.a[2], nil, "null")
			local indef = cbor("bf616d01ff") -- an indefinite map { m = 1 }
			T.eq(indef.m, 1, "indefinite map")
			T.eq(pcall(cbor, "1a000d08"), false, "data that ends inside a value is an error")
			T.eq(pcall(cbor, "0101"), false, "bytes after the value are an error")
		end },
		{ "ah.lua: one line per item, its lowest price, the time and count of its newest day, gone when older than the house's", function()
			local AH = assert(loadfile("tools/preraid/ah.lua"))()
			local day0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
			local house = {
				["13023"] = { m = 854100, h = { ["2150"] = 1, ["2151"] = 1 }, a = { ["2151"] = 3 } },
				["g:13023:65"] = { m = 700000, h = { ["2149"] = 1 }, a = { ["2149"] = 1 } }, -- the bow at an item level
				["15758"] = { m = 459998, h = { ["2149"] = 1 }, a = { ["2149"] = 15 } },
				["8170"] = { m = 1500, h = { ["2151"] = 1500 } },                            -- no a: a database before December 2020
				["p:1234"] = { m = 5, h = { ["2152"] = 1 } },                                -- a battle pet: no item
				version = 2,                                                                 -- InitializeDatabase's mark: no item
			}
			local L = AH.Lines(house)
			T.eq(#L, 3, "three items")
			T.eq(L[1][1], 8170); T.eq(L[1][2], 1500); T.eq(L[1][3], day0 + 2151 * 86400); T.eq(L[1][4], 0, "no count without a")
			T.eq(L[1][5], false, "seen on the house's newest day")
			T.eq(L[2][1], 13023); T.eq(L[2][2], 700000, "the lowest of its keys"); T.eq(L[2][3], day0 + 2151 * 86400, "newest day")
			T.eq(L[2][4], 3, "listed that day"); T.eq(L[2][5], false, "seen on the house's newest day")
			T.eq(L[3][1], 15758); T.eq(L[3][3], day0 + 2149 * 86400); T.eq(L[3][4], 15); T.eq(L[3][5], true, "not seen on day 2151")
			-- the same keys with the prices swapped: the lowest still wins, whichever key the table gives first
			house["13023"].m, house["g:13023:65"].m = 700000, 854100
			T.eq(AH.Lines(house)[2][2], 700000, "the lowest of its keys, swapped")
			-- and the days swapped: the newest day of either key
			house["13023"].h, house["g:13023:65"].h = house["g:13023:65"].h, house["13023"].h
			house["13023"].a, house["g:13023:65"].a = house["g:13023:65"].a, house["13023"].a
			L = AH.Lines(house)
			T.eq(L[2][3], day0 + 2151 * 86400, "the newest day of its keys, swapped"); T.eq(L[2][4], 3, "listed that day, swapped")
			-- a house saved as CBOR: { ["15758"] = { m = 7, h = { ["2149"] = 7 }, a = { ["2149"] = 2 } } }
			local cbor = ("a1653135373538a3616d076168a16432313439076161a1643231343902"):gsub("%x%x",
				function(h) return string.char(tonumber(h, 16)) end)
			L = AH.Lines(cbor)
			T.eq(#L, 1); T.eq(L[1][1], 15758); T.eq(L[1][2], 7); T.eq(L[1][3], day0 + 2149 * 86400); T.eq(L[1][4], 2); T.eq(L[1][5], false)
			-- SetPrice writes today's day into h each time it records an item: an entry with no day is an error naming it
			local ok, err = pcall(AH.Lines, { ["8170"] = { m = 1500 } })
			T.eq(ok, false); T.truthy(tostring(err):find("'8170' has no day table h", 1, true), "no h: " .. tostring(err))
			ok, err = pcall(AH.Lines, { ["8170"] = { m = 1500, h = {} } })
			T.eq(ok, false); T.truthy(tostring(err):find("'8170' has no day in h", 1, true), "an empty h: " .. tostring(err))
		end },
		-- the whole tool on a saved file laid out as the account's (the head of ah.lua): the houses are CBOR byte strings
		-- written byte for byte, and a price of 26 copper is 18 1a, the byte a Windows text-mode read stops at
		{ "ah.lua: a saved Auctionator.lua with byte 0x1A in a house is read whole; the Horde house's lines in the TSV", function()
			local AH = assert(loadfile("tools/preraid/ah.lua"))()
			local function bytes(hex) return (hex:gsub("%s", ""):gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end
			-- { ["15758"] = { m = 26, h = { ["2149"] = 26 }, a = { ["2149"] = 2 }, l = {} }, version = 2 }
			local horde = bytes("a2 453135373538 a4 416d 181a 4168 a1 4432313439 181a 4161 a1 4432313439 02 416c 80"
				.. " 4776657273696f6e 02")
			-- { ["8170"] = { m = 5, h = { ["2149"] = 5 } } }
			local alliance = bytes("a1 4438313730 a2 416d 05 4168 a1 4432313439 05")
			local saved, tsv = os.tmpname(), os.tmpname()
			local f = assert(io.open(saved, "wb"))
			f:write('\r\nAUCTIONATOR_PRICE_DATABASE = {\r\n["__dbversion"] = 8,\r\n["PvP Alliance"] = "', alliance,
				'",\r\n["PvP Horde"] = "', horde, '",\r\n}\r\n')
			f:close()
			local ok, realm = pcall(AH.Write, saved, tsv)
			local text
			if ok then
				f = assert(io.open(tsv, "r")); text = f:read("*a"); f:close()
			end
			os.remove(saved); os.remove(tsv)
			T.truthy(ok, "read: " .. tostring(realm))
			T.eq(realm, "PvP Horde", "the faction's key")
			local day0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
			T.eq(text, "15758\t26\t" .. (day0 + 2149 * 86400) .. "\t2\tfalse\n", "the TSV line")
		end },
		{ "ah.lua: the realm key is the one asked for, else the faction's only one; anything else is an error", function()
			local AH = assert(loadfile("tools/preraid/ah.lua"))()
			local db = { __dbversion = 8, ["PvP Horde"] = {}, ["PvP Alliance"] = {} }
			T.eq(AH.PickRealm(db, "Horde"), "PvP Horde")
			T.eq(AH.PickRealm(db, "Horde", "PvP Alliance"), "PvP Alliance", "asked for")
			local ok, err = pcall(AH.PickRealm, db, "Horde", "PvE Horde")
			T.eq(ok, false); T.truthy(tostring(err):find("PvP Alliance, PvP Horde", 1, true), "the keys there are")
			db["PvE Horde"] = {}
			ok, err = pcall(AH.PickRealm, db, "Horde")
			T.eq(ok, false); T.truthy(tostring(err):find("PvE Horde, PvP Horde", 1, true), "two Horde keys named")
		end },
		-- the client loads Auctionator before HGA when both are installed (the TOC's OptionalDeps): the window's prices
		-- come from Auctionator's API (Game/PreRaid.lua); HGA reads no other price addon
		{ "the TOC names Auctionator as an optional dependency and no Mastercraft", function()
			local deps
			for l in io.lines("HunterGearAdvisor.toc") do
				deps = deps or l:match("^## OptionalDeps:%s*(.-)%s*$")
			end
			T.truthy(deps, "an OptionalDeps line")
			local names = {}
			for n in deps:gmatch("[^,%s]+") do names[n] = true end
			T.truthy(names.Auctionator, "Auctionator in " .. deps)
			T.eq(names.Mastercraft, nil, "no Mastercraft in " .. deps)
		end },
	}
end
