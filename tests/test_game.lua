-- Integration smoke test: loads every Game/*.lua file against stubbed WoW APIs and runs
-- the real flow (ADDON_LOADED, PLAYER_LOGIN, tooltip post-call, Baganator widget, quest
-- rewards, slash commands). Catches nil-index and wiring errors before the game does.
return function(_, T)
	local F = require("fixtures_templates")

	local function env()
		local G = {}
		setmetatable(G, { __index = _G })
		G._G = G -- Templates.lua reads _G[...]: must see the stubbed client strings
		for k, v in pairs(F.ruRU) do G[k] = v end
		G.CR_HIT_RANGED = 7
		-- Game/ProcData.lua entries of the made-up items (loadAll adds them to the DB2's), by item id, as tools/gen_proc_data.py
		-- writes the DB2's (made-up spell ids): the staff's and the dagger's melee equip auras (mask 0x14: the melee swings
		-- and abilities; chance 100: no stated rate, so a test that prices them gives the item a measured rate, G.measuredPPM;
		-- U4 = (a)), the gloves' 5% a melee hit with a 1 s internal cooldown, the
		-- slow bow's chance on hit (a ranged table). The env's other made-up procs (the new bow, the swords, the dagger and
		-- the mace with a chance on hit) have none: they stay unlinked (Items.LinkProcs)
		G.procData = {
			[99502] = { { trigger = 990001, kind = "equip", mask = 20, chance = 100, ppm = 0, icd = 0, spell = 990002, avg = 250, min = 200, max = 300, school = 1, defense = 2, crit = true } },
			[99504] = { { trigger = 990003, kind = "equip", mask = 20, chance = 100, ppm = 0, icd = 0, spell = 990004, avg = 120, min = 100, max = 140, school = 1, defense = 2, crit = true } },
			[99505] = { { trigger = 990005, kind = "equip", mask = 20, chance = 5, ppm = 0, icd = 1000, spell = 990006, avg = 60, min = 50, max = 70, school = 1, defense = 2, crit = true } },
			[99507] = { { trigger = 990007, kind = "hit", spell = 990007, avg = 50, min = 40, max = 60, school = 1, defense = 3, crit = true } },
		}

		local events = {}
		-- events documented in the Forever client (Blizzard_APIDocumentationGenerated); RegisterEvent
		-- throws on anything else, like the real client does
		local KNOWN = { ADDON_LOADED = 1, PLAYER_LOGIN = 1, PLAYER_ENTERING_WORLD = 1, PLAYER_EQUIPMENT_CHANGED = 1,
			BAG_UPDATE_DELAYED = 1, PLAYER_LEVEL_UP = 1, SKILL_LINES_CHANGED = 1, LEARNED_SPELL_IN_SKILL_LINE = 1,
			UPDATE_FACTION = 1, PLAYER_REGEN_ENABLED = 1, GET_ITEM_INFO_RECEIVED = 1, ITEM_DATA_LOAD_RESULT = 1,
			TRAIT_CONFIG_UPDATED = 1, PLAYER_TALENT_UPDATE = 1, TRAIT_NODE_CHANGED = 1,
			START_LOOT_ROLL = 1, LOOT_OPENED = 1, LOOT_READY = 1, LOOT_SLOT_CHANGED = 1, PLAYER_REGEN_DISABLED = 1,
			ACTIVE_COMBAT_CONFIG_CHANGED = 1, ACTIVE_TALENT_GROUP_CHANGED = 1, TRAIT_CONFIG_LIST_UPDATED = 1, UNIT_PET = 1, UNIT_HEALTH = 1,
			BANKFRAME_OPENED = 1, PLAYERBANKSLOTS_CHANGED = 1,
			UNIT_ATTACK_SPEED = 1, ADDON_RESTRICTION_STATE_CHANGED = 1 }
		G.C_EventUtils = { IsEventValid = function(e) return KNOWN[e] ~= nil end }
		G.reportedErrors = {}
		G.geterrorhandler = function() return function(msg) table.insert(G.reportedErrors, msg) end end
		G.issecretvalue = function(v) return G.secretValues and G.secretValues[v] or false end
		G.UnitIsUnit = function(a, b) return a == b end
		G.UnitHealthMax = function() return 2133 end
		G.UnitPowerMax = function() return 1725 end
		G.UnitArmor = function() return 1500, 1500, 1500, 0 end
		G.UnitRace = function() return "Орк", "Orc", 2 end
		-- talents by node id; default = the user's build of 2026-11-12 (BM 32 / MM 2: the nodes that
		-- matter for the model). G.noTalentConfig: the client has no config yet; G.staged: clicks not applied.
		G.talentRanks = { [104960] = 5, [104976] = 1, [104975] = 2, [104969] = 5, [104967] = 5, [104966] = 1,
			[104962] = 4, [104961] = 1, [104963] = 2, [105011] = 2 }
		-- G.activeCfg: the active config; G.ranksByCfg[cfg]: ranks of another config (dual spec);
		-- G.groupCfg[group]: the spec group fallback; G.emptyNode: a node the client cannot answer yet
		G.activeCfg = 7
		G.C_ClassTalents = { GetActiveConfigID = function() if not G.noTalentConfig then return G.activeCfg end end }
		G.C_SpecializationInfo = {
			GetActiveSpecGroup = function() return G.specGroup or 1 end,
			GetCombatConfigIDForSpecGroup = function(group) return G.groupCfg and G.groupCfg[group] end,
		}
		G.C_Traits = {
			GetNodeInfo = function(cfg, nodeID)
				if G.emptyNode == nodeID then return { ID = 0 } end
				local ranks = (G.ranksByCfg and G.ranksByCfg[cfg]) or G.talentRanks
				return { ID = nodeID, activeRank = ranks[nodeID] or 0 }
			end,
			ConfigHasStagedChanges = function() return G.staged == true end,
		}
		G.GetCritChance = function() return 8.66 end
		G.petOut = true
		G.UnitExists = function(u) if u == "pet" then return G.petOut end return true end
		G.UnitIsDead = function() return false end
		G.petFamilyID = 2 -- Cat
		G.UnitCreatureFamily = function(u) if u == "pet" then return "Кошка", G.petFamilyID end end
		-- the pet's main-hand swing (UnitAttackSpeed) and GUID: a cat with Faster Attack VI; the hunter's
		-- swings: the worn sword (2.60) and off-hand sword (1.80) with no melee haste
		G.petSpeed = 1.2
		G.ownerSpeed, G.ownerOffSpeed = 2.6, 1.8
		G.UnitAttackSpeed = function(u)
			if u == "pet" then return G.petSpeed end
			if u == "player" then return G.ownerSpeed, G.ownerOffSpeed end
			error("UnitAttackSpeed stub: only the pet and the player are read")
		end
		G.petGUID = "Pet-0-1"
		G.UnitGUID = function(u) if u == "pet" then return G.petGUID end end
		-- frames, textures and font strings: state that the tests read (shown, text, scripts),
		-- any other widget method is a no-op
		local function widget(kind)
			local w = { scripts = {}, shown = true, kind = kind }
			-- only method names (WoW methods are CamelCase) fall back to a no-op; state fields stay nil
			setmetatable(w, { __index = function(_, k)
				if type(k) == "string" and k:match("^%u") then return function() end end
			end })
			function w:RegisterEvent(e)
				if not KNOWN[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
				events[e] = events[e] or {}; table.insert(events[e], self)
			end
			function w:SetScript(n, fn) self.scripts[n] = fn end
			function w:GetScript(n) return self.scripts[n] end
			function w:HookScript(n, fn) self.scripts[n] = fn end
			function w:Show() self.shown = true end
			function w:Hide() self.shown = false end
			function w:SetShown(v) self.shown = v and true or false end
			function w:IsShown() return self.shown end
			function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
			function w:SetText(t) self.text = t end
			function w:GetText() return self.text end
			function w:GetStringHeight() return (self.text and self.text ~= "") and 12 or 0 end
			function w:SetEnabled(v) self.enabled = v end
			function w:SetTexture(f) self.file = f end
			function w:Click() self.scripts.OnClick(self, "LeftButton") end
			function w:CreateTexture() local t = widget("Texture"); t.parent = self; return t end
			function w:CreateFontString() local t = widget("FontString"); t.parent = self; return t end
			function w:GetPoint() return "TOP", nil, "TOP", 0, -140 end
			-- sizes and scrolling for the pre-raid window layout
			function w:GetUnboundedStringWidth() return 6 * #(self.text or "") end
			function w:SetHeight(h) self.height = h end
			function w:GetHeight() return self.height or 100 end
			function w:SetVerticalScroll(v) self.vscroll = v end
			function w:GetVerticalScroll() return self.vscroll or 0 end
			function w:GetVerticalScrollRange() return self.vrange or 0 end
			function w:GetEffectiveScale() return 1 end
			return w
		end
		G.UIParent = widget("Frame")
		G.GameTooltip = widget("GameTooltip")
		G.CreateFrame = function(kind, name, parent, template)
			local f = widget(kind)
			f.parent, f.template = parent, template
			if name then G[name] = f end
			return f
		end
		-- a clock the tests move: G.advance(s) runs the timers that come due on the way
		G.now = 1000
		G.GetTime = function() return G.now end
		G.inCombat = false
		G.InCombatLockdown = function() return G.inCombat end
		-- cursor and equipping: every call is recorded in G.equipCalls
		G.equipCalls = {}
		G.CursorHasItem = function() return G.cursor ~= nil end
		G.ClearCursor = function() G.cursor = nil; table.insert(G.equipCalls, "ClearCursor") end
		G.PickupInventoryItem = function(slot) G.cursor = "inv" .. slot; table.insert(G.equipCalls, "PickupInventoryItem " .. slot) end
		G.EquipCursorItem = function(slot) G.cursor = nil; table.insert(G.equipCalls, "EquipCursorItem " .. slot) end
		G.IsInventoryItemLocked = function() return false end
		-- AmmoNeeded and UnitUsesAmmo (Forever PaperDollInfoDocumentation.lua:11 and UnitDocumentation.lua:3359: bools, not
		-- nilable): stubs that answer G.ammoNeeded and G.unitUsesAmmo, true unless a test sets them. The client's own rule
		-- for either is not modeled (Camelot/PaperDollFrame.lua reads AmmoNeeded once, when a slot button loads).
		G.ammoNeeded, G.unitUsesAmmo = true, true
		G.C_PaperDollInfo = { CursorCanGoInSlot = function() return true end,
			AmmoNeeded = function() return G.ammoNeeded end }
		G.UnitUsesAmmo = function(u) return u == "player" and G.unitUsesAmmo end
		G.HEADSLOT, G.HANDSSLOT, G.MAINHANDSLOT, G.SECONDARYHANDSLOT, G.RANGEDSLOT =
			"Голова", "Кисти рук", "Правая рука", "Левая рука", "Оружие дальнего боя"
		G.fire = function(e, ...)
			for _, f in ipairs(events[e] or {}) do f.scripts.OnEvent(f, e, ...) end
		end
		-- C_Timer.After: a delay under 1 s (Init.lua's refresh burst, Quest.lua's redraws) runs at once with the
		-- clock moved to its end; a longer one (Player.lua's pet heartbeat re-check) waits in G.timers until
		-- G.advance moves the clock to it
		G.timers = {}
		G.C_Timer = { After = function(delay, fn)
			if delay < 1 then
				G.now = G.now + delay
				fn()
			else
				table.insert(G.timers, { at = G.now + delay, fn = fn })
			end
		end }
		G.advance = function(seconds)
			local to = G.now + seconds
			while true do
				local first
				for i, t in ipairs(G.timers) do
					if t.at <= to and (not first or t.at < G.timers[first].at) then first = i end
				end
				if not first then break end
				local t = table.remove(G.timers, first)
				G.now = math.max(G.now, t.at)
				t.fn()
			end
			G.now = math.max(G.now, to)
		end
		G.hooks = {}
		G.hooksecurefunc = function(a, b, c)
			if type(a) == "string" then G.hooks[a] = b else G.hooks[b] = c end
		end
		-- QuestInfo.lua templates: flat { func, x, y, ... }; the map's details pane has no rewards
		G.QuestInfo_ShowTitle = function() end
		G.QuestInfo_ShowRewards = function() end
		G.QUEST_TEMPLATE_DETAIL = { elements = { G.QuestInfo_ShowTitle, 10, -10, G.QuestInfo_ShowRewards, 0, -15 } }
		G.QUEST_TEMPLATE_REWARD = { chooseItems = true, elements = { G.QuestInfo_ShowTitle, 10, -10, G.QuestInfo_ShowRewards, 0, -10 } }
		G.QUEST_TEMPLATE_MAP_DETAILS = { questLog = true, elements = { G.QuestInfo_ShowTitle, 5, -10 } }
		G.QUEST_TEMPLATE_MAP_REWARDS = { questLog = true, elements = { G.QuestInfo_ShowRewards, 12, -52 } }
		G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) G.tooltipPost = fn end }
		G.Enum = { TooltipDataType = { Item = 0 }, PowerType = { Mana = 0 } }
		G.SlashCmdList = {}
		G.printed = {}
		G.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end table.insert(G.printed, table.concat(t, " ")) end
		G.date = os.date
		G.GetLocale = function() return "ruRU" end
		G.GetBuildInfo = function() return "1.60.1" end

		-- items: link -> { info = {id, equipLoc, classID, subclassID}, lines = {...}, api = {...} }
		local RED = { r = 1, g = 0.125, b = 0.125 }
		local W = { r = 1, g = 1, b = 1 }
		local function line(l, r, red) return { leftText = l, rightText = r, leftColor = W, rightColor = red and RED or W } end
		local items = {
			bow = { info = { 1, "INVTYPE_RANGED", 2, 2 }, lines = { line("Короткий лук"), line("Дальний бой", "Лук"),
				line("Урон: 40-70", "Скорость 2,60"), line("(21,2 ед. урона в секунду)"), line("+5 к ловкости") },
				api = { ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 21.2 } },
			newbow = { info = { 2, "INVTYPE_RANGED", 2, 2 }, lines = { line("Новый лук"), line("Дальний бой", "Лук"),
				line("Урон: 50-80", "Скорость 2,60"), line("(24,6 ед. урона в секунду)"),
				line("Возможный эффект при попадании: наносит 22 - 34 ед. урона от огня.") },
				api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 24.6 } },
			sword = { info = { 3, "INVTYPE_WEAPON", 2, 7 }, lines = { line("Меч Покорителя"), line("Одноручное", "Меч"),
				line("Урон: 40-75", "Скорость 2,60"), line("(22,1 ед. урона в секунду)"), line("Если на персонаже: +22 к силе атаки.") },
				api = { ITEM_MOD_ATTACK_POWER_SHORT = 22, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 22.1 } },
			offsword = { info = { 4, "INVTYPE_WEAPON", 2, 7 }, lines = { line("Заточка"), line("Одноручное", "Меч"),
				line("Урон: 25-40", "Скорость 1,80"), line("(18,0 ед. урона в секунду)"), line("+4 к ловкости") }, api = { ITEM_MOD_AGILITY_SHORT = 4 } },
			bagsword = { info = { 5, "INVTYPE_WEAPON", 2, 7 }, lines = { line("Меч из сумки"), line("Одноручное", "Меч"),
				line("Урон: 38-58", "Скорость 2,40"), line("(20,0 ед. урона в секунду)"), line("+10 к ловкости") }, api = { ITEM_MOD_AGILITY_SHORT = 10 } },
			staff = { info = { 6, "INVTYPE_2HWEAPON", 2, 10 }, lines = { line("Посох"), line("Двуручное", "Посох"),
				line("Урон: 77-115", "Скорость 3,20"), line("(30,0 ед. урона в секунду)"), line("+12 к ловкости") }, api = { ITEM_MOD_AGILITY_SHORT = 12 } },
			mace = { info = { 7, "INVTYPE_WEAPON", 2, 4 }, lines = { line("Булава"), line("Одноручное", "Дробящее", true),
				line("Урон: 32-48", "Скорость 2,00"), line("(20,0 ед. урона в секунду)"), line("+30 к ловкости") }, api = { ITEM_MOD_AGILITY_SHORT = 30 } },
			gloves = { info = { 8, "INVTYPE_HAND", 4, 2 }, lines = { line("Перчатки дрессировщика собак"), line("Кисти рук", "Кожа"),
				line("Броня: 80"), line("Если на персонаже: +24 к силе атаки."),
				line("Если на персонаже: +21 к силе атаки против животных.") },
				api = { ITEM_MOD_ATTACK_POWER_SHORT = 24, RESISTANCE0_NAME = 80 } },
			helm = { info = { 9, "INVTYPE_HEAD", 4, 3 }, lines = { line("Шлем"), line("Голова", "Кольчуга"), line("Броня: 200"),
				line("+18 к ловкости"), line("+11 к духу"), line("Если на персонаже: Повышает силу зверя на 1."),
				line("Чары: +3 к выносливости и +24 к броне"), line("Прочность: 75 / 75") },
				api = { ITEM_MOD_AGILITY_SHORT = 18, ITEM_MOD_SPIRIT_SHORT = 11, RESISTANCE0_NAME = 200 } },
			newhelm = { info = { 10, "INVTYPE_HEAD", 4, 3 }, lines = { line("Новый шлем"), line("Голова", "Кольчуга"),
				line("Броня: 210"), line("+16 к ловкости"), line("Если на персонаже: повышает вероятность попадания на 1,0%."),
				line("Требуется 45-й уровень", nil, false) },
				api = { ITEM_MOD_AGILITY_SHORT = 16, ITEM_MOD_HIT_RATING_SHORT = 10 } },
		}
		-- red level line
		items.newhelm.lines[6].leftColor = RED
		G.items = items
		G.C_Item = {
			GetItemInfoInstant = function(link) local it = items[link]; if not it then return nil end
				return it.info[1], "t", "s", it.info[2], 0, it.info[3], it.info[4] end,
			IsItemDataCachedByID = function() return true end,
			RequestLoadItemDataByID = function() end,
			GetItemStats = function(link) return items[link] and items[link].api end,
		}
		G.C_TooltipInfo = { GetHyperlink = function(link) return items[link] and { lines = items[link].lines } end }
		local equipped = { [1] = "helm", [10] = "gloves", [16] = "sword", [17] = "offsword", [18] = "bow" }
		G.equippedLinks = equipped
		G.GetInventoryItemLink = function(_, slot) if slot == 0 then return nil end return equipped[slot] end
		-- Forever: the ammo slot only answers to GetInventoryItemID
		G.GetInventoryItemID = function(_, slot) if slot == 0 then return 13 end return nil end
		-- the stack in the ammo slot (the in-game count of 2026-11-12, Game/Player.lua Snapshot: 2790), 1 for any other worn
		-- item (Forever Camelot/PaperDollFrame.lua:2185 shows it on every slot button)
		G.GetInventoryItemCount = function(_, slot)
			if slot == 0 then return 2790 end
			return equipped[slot] and 1 or 0
		end
		-- by id or by link; sell price = items[link].price (11th value), set = items[link].setID (16th value,
		-- nil outside a set), in the order of Forever's ItemDocumentation.lua
		G.C_Item.GetItemInfo = function(idOrLink)
			for link, it in pairs(items) do
				if it.info[1] == idOrLink or link == idOrLink then
					return it.lines[1].leftText, link, 1, 1, 1, "t", "s", 1, it.info[2], 0, it.price or 0, it.info[3], it.info[4],
						1, 0, it.setID, false, ""
				end
			end
		end
		items.bullets = { info = { 11, "INVTYPE_AMMO", 6, 3 }, lines = { line("Точные пули"), line("Боеприпасы", "Пуля"),
			line("Добавляет 13 ед. урона в секунду") }, api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.33 } }
		items.betterbullets = { info = { 12, "INVTYPE_AMMO", 6, 3 }, lines = { line("Лучшие пули"), line("Боеприпасы", "Пуля"),
			line("Добавляет 14,5 ед. урона в секунду") }, api = {} }
		items.arrows = { info = { 13, "INVTYPE_AMMO", 6, 2 }, lines = { line("Стрелы"), line("Боеприпасы", "Стрела"),
			line("Добавляет 16 ед. урона в секунду") }, api = {} }
		local bags = { [0] = { "newbow", "bagsword", "staff", "mace", "newhelm" } }
		G.bags = bags
		G.C_Container = {
			GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
			GetContainerItemLink = function(bag, slot) return bags[bag] and bags[bag][slot] end,
			PickupContainerItem = function(bag, slot)
				G.cursor = bags[bag][slot]; table.insert(G.equipCalls, "PickupContainerItem " .. bag .. " " .. slot)
			end,
		}
		G.UnitLevel = function() return 43 end
		G.UnitRangedAttackPower = function() return 413, 70, 0 end
		G.UnitAttackPower = function() return 376, 0, 0 end
		G.GetCombatRatingBonus = function() return 1.0 end
		G.GetRangedHitModifier = function() return 0 end
		G.GetRangedCritChance = function() return 8.66 end
		G.UnitRangedDamage = function() return 2.6 / 1.13 end
		G.GetRangedHaste = function() return 0, 13 end -- percent, as PaperDollFrame_SetHaste prints it
		-- UnitStat by the client's stat index (Forever UnitDocumentation.lua:3198: currentStat, effectiveStat, ...): Agility
		-- (the reference character's 167) and Spirit, the two the addon reads; GetManaRegen and GetManaRegenFromSpirit in mana
		-- a second (PlayerScriptDocumentation.lua:571-590), the spell and melee hit modifiers and the spell crit: stub values.
		-- The stub's currentStat sits below its effectiveStat (G.statAgi, G.statSpirit, the values the addon reads) by a
		-- positive buff, so a reading of the first return shows
		G.LE_UNIT_STAT_AGILITY, G.LE_UNIT_STAT_SPIRIT = 2, 5
		G.statAgi, G.statSpirit = 167, 64
		G.UnitStat = function(u, index)
			if u ~= "player" then error("UnitStat stub: only the player is read") end
			if index == 2 then return G.statAgi - 7, G.statAgi, 7, 0 end
			if index == 5 then return G.statSpirit - 4, G.statSpirit, 4, 0 end
			error("UnitStat stub: only Agility (2) and Spirit (5) are read, got " .. tostring(index))
		end
		G.GetManaRegen = function() return 12.6, 3.15 end
		G.GetManaRegenFromSpirit = function() return 9.45, 2.36 end
		G.GetSpellHitModifier = function() return 0 end
		G.GetSpellCritChance = function() return 5.63 end
		G.GetHitModifier = function() return 0 end
		-- bag slots 1-4 are inventory slots 20-23; a 13% quiver in bag slot 1
		G.C_Container.ContainerIDToInventoryID = function(bag) return 19 + bag end
		-- free slots and the family of each bag (C_Container.GetContainerNumFreeSlots: numFreeSlots, bagFamily, Forever
		-- ContainerDocumentation.lua:297-312; 0 a bag of any item), the backpack (0) and bags 1-4 (NUM_BAG_SLOTS); putting the
		-- cursor's item into the backpack or a bag (its inventory slot) is recorded in G.equipCalls
		G.NUM_BAG_SLOTS = 4
		G.freeSlots, G.bagFamily = { [0] = 4 }, {}
		G.C_Container.GetContainerNumFreeSlots = function(bag) return G.freeSlots[bag] or 0, G.bagFamily[bag] or 0 end
		G.PutItemInBackpack = function() G.cursor = nil; table.insert(G.equipCalls, "PutItemInBackpack") end
		G.PutItemInBag = function(inv) G.cursor = nil; table.insert(G.equipCalls, "PutItemInBag " .. inv) end
		local baseInvLink = G.GetInventoryItemLink
		G.GetInventoryItemLink = function(u, slot) if slot == 20 then return "quiver13" end return baseInvLink(u, slot) end
		items.quiver13 = { info = { 20, "INVTYPE_BAG", 11, 2 }, lines = { line("Колчан 13"), line("Колчан"),
			line("Если на персонаже: Увеличение скорости дальней атаки на 13%.") }, api = {} }
		items.quiver15 = { info = { 21, "INVTYPE_BAG", 11, 2 }, lines = { line("Колчан 15"), line("Колчан"),
			line("Если на персонаже: Увеличение скорости дальней атаки на 15%.") }, api = {} }
		items.pouch15 = { info = { 22, "INVTYPE_BAG", 11, 3 }, lines = { line("Подсумок 15"), line("Подсумок"),
			line("Если на персонаже: Увеличение скорости дальней атаки на 15%.") }, api = {} }
		items.gun = { info = { 23, "INVTYPE_RANGEDRIGHT", 2, 3 }, lines = { line("Ружьё"), line("Дальний бой", "Огнестрельное"),
			line("Урон: 50-80", "Скорость 2,60"), line("(24,0 ед. урона в секунду)") }, api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 24 } }
		items.polearm = { info = { 24, "INVTYPE_2HWEAPON", 2, 6 }, lines = { line("Древко"), line("Двуручное", "Древковое", true),
			line("Урон: 112-168", "Скорость 3,50"), line("(40,0 ед. урона в секунду)"), line("+30 к ловкости") }, api = { ITEM_MOD_AGILITY_SHORT = 30 } }
		-- an item of another class in a weapon slot, like Torch of Retribution 10515 (class 4, two-hand)
		items.torch = { info = { 25, "INVTYPE_2HWEAPON", 4, 0 }, lines = { line("Факел"), line("Двуручное") }, api = {} }
		G.GetPrimaryTooltipInfoFor = nil
		-- auras by unit and spell id (Aspect of the Hawk V 14321 on the player); G.secretAuras[id]: the
		-- client says that aura would be secret (C_Secrets.ShouldSpellAuraBeSecret), and a query for it
		-- returns nothing, up or not (RequiresNonSecretAura, Forever SecretPredicatesDocumentation.lua)
		G.auras = { player = { [14321] = true }, pet = {} }
		G.C_UnitAuras = {
			GetPlayerAuraBySpellID = function(id)
				if G.secretAuras[id] then return nil end
				return G.auras.player[id] and {} or nil
			end,
			GetUnitAuraBySpellID = function(u, id)
				if G.secretAuras[id] then return nil end
				return G.auras[u] and G.auras[u][id] and {} or nil
			end,
		}
		G.secretAuras = {}
		G.C_Secrets = { ShouldSpellAuraBeSecret = function(id) return G.secretAuras[id] == true end }
		-- the weapon lines a hunter learns (Game/Player.lua HUNTER_SKILLS: swords 43, axes 44, bows 45, guns 46, two-handed
		-- swords 55, staves 136, two-handed axes 172, daggers 173, crossbows 226, polearms 229, fist weapons 473) trained to the
		-- level's maximum, 5 x the level read at the call (215 at the env's 43): the most a trained line reaches, its maxRank
		-- (the Forever client's SKILL_RANKS_PER_SKILL_LEVEL = 5 and GetExpectedSkillForLevelOffset, Camelot/SkillsFrame.lua:1,
		-- 40-42), the skill wowsims leaves a weapon line it is not given (sim/core/weapon_skill.go:56). Polearms only from
		-- level 20, the line's MinLevel for the hunter (Forever DB2 SkillRaceClassInfo 136: SkillID 229, ClassMask 7 with the
		-- hunter's 4, MinLevel 20); maces (54, 160) and thrown (176) unlearned
		G.C_SkillInfo = { GetSkillLineInfoByID = function(id)
			local weapon = { [43] = 1, [44] = 1, [45] = 1, [46] = 1, [55] = 1, [136] = 1, [172] = 1, [173] = 1, [226] = 1, [229] = 20,
				[473] = 1 }
			local level = G.UnitLevel()
			if weapon[id] and level >= weapon[id] then return { rank = 5 * level, maxRank = 5 * level, modifier = 0 } end
			local known = { [414] = 1, [415] = 1, [413] = 1, [118] = 1 }
			return known[id] and { rank = 1, maxRank = 1, modifier = 0 } or nil end }
		G.IsPlayerSpell = function() return false end
		G.GetQuestItemLink = function(_, i) return ({ "newbow", "mace", "newhelm" })[i] end
		G.GetQuestLogItemLink = G.GetQuestItemLink
		-- name, texture, count (3rd value, as QuestInfo.lua reads it)
		G.questCounts = {}
		G.GetQuestItemInfo = function(_, i) return "n", 0, G.questCounts[i] or 1 end
		G.GetQuestLogChoiceInfo = function(i) return "n", 0, G.questCounts[i] or 1 end
		-- pre-raid window: owned items, Auctionator's prices, reputation, map pin, AtlasLoot
		G.UISpecialFrames = {}
		G.owned = { worn = {}, bags = {}, bank = {} }
		G.C_Item.IsEquippedItem = function(id) return G.owned.worn[id] == true end
		G.C_Item.GetItemCount = function(id, bank)
			return (G.owned.bags[id] and 1 or 0) + ((bank and G.owned.bank[id]) and 1 or 0)
		end
		G.C_Item.GetItemNameByID = function(id) if not (G.unloaded and G.unloaded[id]) then return "item" .. id end end
		G.C_Item.RequestLoadItemDataByID = function(id) G.requested = G.requested or {}; G.requested[id] = true end
		G.C_Item.GetItemQualityByID = function(id) if not (G.unloaded and G.unloaded[id]) then return 4 end end
		G.C_Item.GetItemQualityColor = function() return 0.64, 0.21, 0.93, "ffa335ee" end
		G.GetCursorPosition = function() return 0, G.cursorY or 0 end
		-- Auctionator's external API (Auctionator Source/API/v1): a price in copper or nil, an age in days or nil. The real
		-- API wants the calling addon's name and a numeric item id (Source/API/Internal.lua, each v1 file); the stub writes
		-- every call down as { callerID, itemID } in G.auctionatorCalls, and the window's test checks both. It knows
		-- Eaglehorn Long Bow 13023, listed yesterday, and Black Dye 14341 at a merchant for 50s
		G.auctionatorCalls = {}
		local function auctionatorCall(values)
			return function(caller, id)
				table.insert(G.auctionatorCalls, { caller, id })
				return values[id]
			end
		end
		G.Auctionator = { API = { v1 = {
			GetAuctionPriceByItemID = auctionatorCall({ [13023] = 854100 }),
			GetAuctionAgeByItemID = auctionatorCall({ [13023] = 1 }),
			GetVendorPriceByItemID = auctionatorCall({ [14341] = 5000 }),
		} } }
		G.C_Reputation = { GetFactionDataByID = function(id) return id == 2798 and { reaction = 5 } or nil end }
		G.C_Map = {
			GetMapInfo = function(id) return { name = "map" .. id } end,
			CanSetUserWaypointOnMap = function() return true end,
			SetUserWaypoint = function(p) G.waypoint = p end,
		}
		G.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
		G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) G.superTracked = v end }
		G.OpenWorldMap = function(m) G.openedMap = m end
		local function select(name)
			return { SetSelected = function(self, id)
				G.atlasSel[name] = id
				-- like Template_Select: selected = { index, id } only when the id is in its list
				self.selected = (not G.atlasRefuse) and { id, id } or nil
			end }
		end
		G.atlasSel = {}
		G.atlasFrame = widget("Frame"); G.atlasFrame.shown = false
		G.atlasFrame.moduleSelect, G.atlasFrame.subCatSelect, G.atlasFrame.boss = select("module"), select("inst"), select("boss")
		G.atlasFrame.extra = select("extra")
		G.atlasData = {
			AtlasLootClassic_DungeonsAndRaids = {
				Stratholme = { items = { { npcID = 1, [1] = { { 1, 111 } } }, { npcID = 10440, [1] = { { 6, 13340 } } } } },
				UpperBlackrockSpire = { items = { { npcID = 10429, [1] = { { 1, 12630 } } } } },
				DireMaulEast = { items = { { npcID = 11490, [1] = { { 1, 1 } } }, { ExtraList = true, [1] = { { 2, 18296 } } } } },
			},
			AtlasLootClassic_Crafting = { Leatherworking = { items = { { [1] = { { 16, 1254968 }, { 17, 1255015 } } } } } },
			AtlasLootClassic_PvP = {},
		}
		G.AtlasLoot = {
			Loader = { LoadModule = function(_, m, fn) fn(m); return true end },
			ItemDB = { Get = function(_, m) return G.atlasData[m] end },
			GUI = { frame = G.atlasFrame },
		}
		return G
	end

	-- the addon's files in the TOC's order; after Game/ProcData.lua the env's entries for its made-up items (G.procData)
	-- join the DB2's, and after Core/Score.lua the measured rates a test gives its made-up proc items (G.measuredPPM: id ->
	-- procs per minute) join Score.MEASURED_PPM: no rate is made up for an unmeasured proc (U4 = (a), Score.ProcRateSource),
	-- so a test of the procs' hits and speeds gives its items a rate from a source HGA reads; a real measured id is an error
	local function loadAll(G)
		local ns = {}
		for _, f in ipairs({ "Core/Model.lua", "Core/Parse.lua", "Core/Score.lua", "Core/PreRaid.lua", "Game/Init.lua", "Game/Templates.lua",
			"Game/SetData.lua", "Game/UseData.lua", "Game/ProcData.lua", "Game/StatMultData.lua", "Game/Items.lua", "Game/Player.lua",
			"Game/Advisor.lua",
			"Game/Tooltip.lua", "Game/Bags.lua", "Game/Quest.lua", "Game/Swap.lua", "Game/PreRaidData.lua", "Game/PreRaid.lua",
			"Game/Commands.lua" }) do
			local chunk = assert(loadfile(f, "t", G))
			chunk("HunterGearAdvisor", ns)
			if f == "Core/Score.lua" then
				for id, rate in pairs(G.measuredPPM or {}) do
					if ns.Score.MEASURED_PPM[id] then error("the env's measured rate " .. id .. " is a measured item's own") end
					ns.Score.MEASURED_PPM[id] = rate
				end
			end
			if f == "Game/ProcData.lua" then
				for id, entries in pairs(G.procData) do
					if ns.ProcData[id] then error("the env's ProcData entry " .. id .. " is the DB2's own item") end
					ns.ProcData[id] = entries
				end
			end
		end
		G.fire("ADDON_LOADED", "HunterGearAdvisor")
		G.fire("PLAYER_LOGIN")
		return ns
	end

	-- The factor of a proc's damage at a model point m by hand (Model.ProcOutcomes, raid-mode design 4.6.4), at the env's
	-- equal-level mob (no crit suppression, the spell miss 4%) and its build without Lone Wolf or Improved Tracking: Focused
	-- Fire 1% a rank with the pet out, x for the physical school the armor (Model.PhysMult), x the outcome of its table:
	-- magic (1 - max(0, 4% - spell hit)) x (1 + 0.5 x spell crit); melee (1 - the miss - the dodge) x (1 + the melee
	-- crit); ranged (1 - the miss) x (1 + the melee crit), the miss 5% less p.hit alone; no DefenseType (0) by the school
	local function procFactor(M, m, defense, school, crit)
		assert(m.mobDiff == 0 and m.tal.loneWolf == 0 and m.tal.improvedTracking == 0, "the env's point")
		local miss = math.max(0, 5 - m.hit) / 100
		local dodge = math.max(0, 0.05 - m.expertise / 100)
		local tbl = defense == 0 and (school == "physical" and 2 or 1) or defense
		local hit, critMult
		if tbl == 1 then
			hit, critMult = 1 - math.max(0, 0.04 - m.spellHit / 100), 1 + 0.5 * m.spellCrit / 100
		elseif tbl == 2 then
			hit, critMult = 1 - miss - dodge, 1 + m.meleeCrit / 100
		else
			hit, critMult = 1 - miss, 1 + m.meleeCrit / 100
		end
		local own = (m.petOut and m.level >= 10) and 1 + 0.01 * m.tal.focusedFire or 1
		return own * (school == "physical" and M.PhysMult(m.level, m.mobDiff) or 1) * hit * (crit and critMult or 1)
	end

	-- the pet comes out and the hunter's melee speed holds for a pet heartbeat (5.25 s): Player.PetSwing
	-- may read the pet's swing from then on
	local function settlePet(G)
		G.fire("UNIT_PET", "player")
		G.advance(5.25)
	end

	-- A Survival tree (Player.SurvivalBranch: strictly more talent points in Survival than in Beast Mastery and than in
	-- Marksmanship), the one build that melees (Player.Snapshot: the weave, Core/Model.lua weaveParts), for the tests of a
	-- melee mechanism: 27 points on Survival nodes whose rank the model reads nowhere (Deflection 104995, Entrapment 104994:
	-- 10 each; Improved Wing Clip 104990: 5; Deterrence 104986, Counterattack 104989: 1 each) over the env's BM 26 / MM 2, so
	-- the talents the model reads, and every number of the env's build, stay. The stub's ranks and point total are no
	-- game's.
	local SURVIVAL_TREE_NODES = { [104995] = 10, [104994] = 10, [104990] = 5, [104986] = 1, [104989] = 1 }
	local function survivalTree(G)
		for node, rank in pairs(SURVIVAL_TREE_NODES) do G.talentRanks[node] = rank end
	end

	-- A level-60 character, the raid mode's (Player.Snapshot: Model.RAID_LEVEL): the stub's weapon lines follow the level, so
	-- every line it knows is at 300, the level's 5 x 60, and the worn bow and sword are at the level's skill
	local function raidLevel(G)
		G.UnitLevel = function() return 60 end
	end

	-- Two melee lines in the hands, each below the level's 215 (the stub's ranks and items are no game's): a 5.0 s sword in
	-- the main hand (swords 205: -10) and a 1.8 s dagger in the off hand (daggers 195: -20). The slow main hand keeps the
	-- hunter in melee long enough for the off hand to swing in the Survival weave (Model weaveParts' shareOH)
	local function twoLines(G)
		local Wc = { r = 1, g = 1, b = 1 }
		local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
		local base = G.C_SkillInfo.GetSkillLineInfoByID
		G.C_SkillInfo.GetSkillLineInfoByID = function(id)
			if id == 43 then return { rank = 205, maxRank = 215, modifier = 0 } end
			if id == 173 then return { rank = 195, maxRank = 215, modifier = 0 } end
			return base(id)
		end
		G.items.slowsword = { info = { 78, "INVTYPE_WEAPONMAINHAND", 2, 7 }, lines = { ln("Медленный меч"), ln("Правая рука", "Меч"),
			ln("Урон: 80-150", "Скорость 5,00"), ln("(23,0 ед. урона в секунду)") }, api = {} }
		G.items.wdagger = { info = { 79, "INVTYPE_WEAPON", 2, 15 }, lines = { ln("Кинжал"), ln("Одноручное", "Кинжал"),
			ln("Урон: 25-40", "Скорость 1,80"), ln("(18,0 ед. урона в секунду)") }, api = {} }
		G.equippedLinks[16], G.equippedLinks[17] = "slowsword", "wdagger"
		return ln
	end

	-- the Highborne Research Tablet 260205 in the env's items (Forever Item.csv class 4, InventoryType 12; its "Equip:" line
	-- of spell 1318159, 69 - 81 Arcane damage)
	local function addTablet(G)
		local Wc = { r = 1, g = 1, b = 1 }
		local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
		G.items.tablet = { info = { 260205, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Исследовательская табличка высокорожденных"),
			ln("Аксессуар"), ln("Если на персонаже: С некоторой вероятностью при попадании наносит 69 - 81 ед. урона от тайной магии. Против наг и сатиров урон увеличивается в 2 раза.") },
			api = {} }
	end

	-- a made-up bag two-hander with a melee equip proc (a 3.4 s staff, "Атаки ближнего боя с некоторой вероятностью наносят
	-- 200 - 300 ед. урона", Parse hits "melee"), the env's worn pair (a 2.6 s sword and a 1.8 s off-hand sword) and the
	-- Survival branch's weave; returns the env, ns, the state and the staff's result
	local function procStaffSetup()
		local G = env()
		survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
		local Wc = { r = 1, g = 1, b = 1 }
		local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
		G.items.procstaff = { info = { 99502, "INVTYPE_2HWEAPON", 2, 10 }, lines = { ln("Посох с эффектом"), ln("Двуручное", "Посох"),
			ln("Урон: 77-115", "Скорость 3,40"), ln("(28,2 ед. урона в секунду)"),
			ln("Если на персонаже: Атаки ближнего боя с некоторой вероятностью наносят 200 - 300 ед. урона.") }, api = {} }
		G.bags[0] = { "procstaff" }
		G.measuredPPM = { [99502] = 1.5 } -- a rate from a source HGA reads (U4 = (a)): the env's measured one
		local ns = loadAll(G)
		local st = ns.Advisor.State()
		return G, ns, st, ns.Advisor.Evaluate("procstaff", { kind = "bag", bag = 0, slot = 1 })
	end

	return {
		{ "addon loads, tooltip lines for a better bow", function()
			local G = env(); local ns = loadAll(G)
			local res = ns.Advisor.Evaluate("newbow")
			T.truthy(res and res.isUpgrade, "new bow is an upgrade")
			local tip = { lines = {} }
			function tip:GetItem() return "Новый лук", "newbow" end
			function tip:AddLine(t) table.insert(self.lines, t) end
			G.GameTooltip = tip
			G.tooltipPost(tip)
			T.truthy(tip.lines[1]:find("усиление %+"), "gain line: " .. tostring(tip.lines[1]))
		end },
		{ "mace is not usable, staff is a 2H swap, bag sword pairs", function()
			local G = env(); local ns = loadAll(G)
			local mace = ns.Advisor.Evaluate("mace")
			T.eq(mace.usable, false); T.truthy(mace.reason, "reason")
			local staff = ns.Advisor.Evaluate("staff")
			T.eq(staff.hand, "2h")
			local bs = ns.Advisor.Evaluate("bagsword", { kind = "bag", bag = 0, slot = 2 })
			T.truthy(bs.hand == "mh" or bs.hand == "oh", "one-hander goes to a hand")
			T.truthy(bs.mh ~= bs.oh, "never paired with itself")
			local lines = ns.Advisor.Explain("bagsword")
			T.truthy(#lines >= 2, "gain + hand lines")
		end },
		{ "level-45 helm keeps its checkmark, hit counts below cap", function()
			local G = env(); local ns = loadAll(G)
			T.near(ns.Items.Get("bow").speed, 2.6, 1e-9, "speed only exists in the tooltip text")
			T.eq(ns.Items.Get("helm").stats.STA, 3, "enchant stamina only exists in the tooltip text")
			local mm = ns.Items.Get("helm").mismatch
			T.eq(#mm, 1, "only armor differs"); T.truthy(mm[1]:find("^ARMOR"), "enchant armor is not in GetItemStats: " .. tostring(mm[1]))
			T.eq(ns.Items.Get("helm").stats.ARMOR, 224, "tooltip armor includes the enchant")
			local r = ns.Advisor.Evaluate("newhelm")
			T.eq(r.aboveLevel, true)
			T.eq(r.usable, true, "red level line is not a restriction")
			T.truthy(r.isUpgrade, "1% hit + 16 agi beats 18 agi + 11 spirit + enchant: delta " .. tostring(r.delta))
		end },
		{ "baganator widget and quest rewards", function()
			local G = env()
			local widget
			G.Baganator = { API = {
				RegisterCornerWidget = function(_, _, onUpdate, onInit) widget = { onUpdate = onUpdate, onInit = onInit } end,
				RequestItemButtonsRefresh = function() end } }
			local ns = loadAll(G)
			T.truthy(widget, "widget registered")
			local fakeButton = { CreateTexture = function() return { SetTexture = function(t, f) t.file = f end, SetVertexColor = function() end, SetSize = function() end } end }
			local check = widget.onInit(fakeButton)
			-- Baganator hands over a plain { bagID, slotIndex } table
			T.truthy(check.file:match("^Interface.AddOns.HunterGearAdvisor.Media.UpgradeArrow$"), "bag mark is the double arrow")
			T.eq(widget.onUpdate(check, { itemLink = "newbow", itemLocation = { bagID = 0, slotIndex = 1 } }), true)
			T.eq(widget.onUpdate(check, { itemLink = "mace", itemLocation = { bagID = 0, slotIndex = 4 } }), false)

			local function button(i)
				local b = { type = "choice", objectType = "item", id = i }
				function b:GetID() return self.id end
				function b:IsShown() return true end
				function b:CreateTexture()
					local t = { shown = false }
					function t:SetTexture(f) self.file = f end function t:SetVertexColor(r, g, bl) self.color = { r, g, bl } end
					function t:SetSize() end function t:SetPoint() end
					function t:SetColorTexture() end function t:SetAllPoints() end
					function t:Show() self.shown = true end function t:Hide() self.shown = false end
					return t
				end
				return b
			end
			G.QuestInfoFrame = { rewardsFrame = { RewardButtons = { button(1), button(2), button(3) } } }
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_REWARD)
			local btns = G.QuestInfoFrame.rewardsFrame.RewardButtons
			T.truthy(btns[1].hgaCheck and btns[1].hgaCheck.shown, "bow reward marked")
			T.eq(btns[2].hgaCheck, nil, "mace not marked")
		end },
		{ "ammo slot read through GetInventoryItemID, ammo type must match the weapon", function()
			local G = env(); local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.snap.model.ammoDPS, 16, "equipped arrows found via item id")
			T.eq(st.snap.ammoFromBag, false)
			local b = ns.Advisor.Evaluate("bullets")
			T.eq(b.usable, false, "bullets do not fit a bow")
			T.eq(ns.Items.Get("bullets").stats.DPS, nil, "GetItemStats DPS ignored on ammo")
		end },
		{ "a bag copy of a worn item is a bag item, located through the tooltip getter", function()
			local G = env()
			G.C_Container.GetContainerItemLink = function(bag, slot) if bag == 0 and slot == 1 then return "sword" end end
			G.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
			local ns = loadAll(G)
			local worn = ns.Advisor.Evaluate("sword", { kind = "equipped", slot = 16 })
			T.eq(worn.equippedSlot, 16)
			local copy = ns.Advisor.Evaluate("sword", { kind = "bag", bag = 0, slot = 1 })
			T.eq(copy.equippedSlot, nil, "bag copy is not the worn one")
			T.truthy(copy.delta ~= nil, "bag copy is scored")
			local tip = { lines = {} }
			function tip:GetItem() return "Меч", "sword" end
			function tip:AddLine(t) table.insert(self.lines, t) end
			function tip:GetPrimaryTooltipInfo() return { getterName = "GetBagItem", getterArgs = { 0, 1, n = 2 } } end
			G.GameTooltip = tip
			G.tooltipPost(tip)
			T.truthy(#tip.lines >= 1, "tooltip for the bag copy has HGA lines")
		end },
		{ "quiver items are scored and their tooltip gives the speed against the model's; a pouch for a bow is not usable", function()
			local G = env(); local ns = loadAll(G)
			T.near(ns.Advisor.State().snap.model.quiver, 0.13, 1e-9, "quiver from GetRangedHaste")
			local q = ns.Advisor.Evaluate("quiver15", { kind = "new" })
			T.truthy(q.isUpgrade and q.delta > 0, "15% quiver beats 13%: " .. tostring(q.delta))
			local t = {}
			for i, l in ipairs(ns.Advisor.Explain("quiver15", { kind = "new" })) do t[i] = l[1] end
			local text = table.concat(t, "\n")
			T.truthy(text:find("HGA: скорость стрельбы 15% (сейчас 13%)", 1, true), text)
			local worn = ns.Advisor.Evaluate("quiver13", { kind = "equipped", slot = 20 })
			T.eq(worn.equippedSlot, 20)
			local p = ns.Advisor.Evaluate("pouch15", { kind = "new" })
			T.eq(p.usable, false)
		end },
		{ "user rule: bow <-> gun is scored as the weapon only; missing ammo / wrong quiver are notes", function()
			local function run(bags)
				local G = env()
				G.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and #bags or 0 end
				G.C_Container.GetContainerItemLink = function(bag, slot) return bag == 0 and bags[slot] or nil end
				local ns = loadAll(G)
				local r = ns.Advisor.Evaluate("gun", { kind = "bag", bag = 0, slot = 1 })
				local lines = ns.Advisor.Explain("gun", { kind = "bag", bag = 0, slot = 1 })
				local t = {}
				for _, l in ipairs(lines) do t[#t + 1] = l[1] end
				return r, table.concat(t, "\n"), ns.Advisor.State()
			end
			-- no bullets in the bags
			local r, text, st = run({ "gun" })
			-- gun 24.0 DPS, no stats; bow 21.2 DPS + 5 Agility: pure weapon comparison
			T.near(r.delta, (24 - 21.2) * st.W.RANGED_DPS - 5 * st.W.AGI, 1e-6, "ammo and quiver do not change the score")
			T.eq(r.familySwitch.noAmmo, true); T.eq(r.familySwitch.quiverMismatch, true)
			T.truthy(text:find("нет пуль"), "note: no bullets")
			T.truthy(text:find("нужен подсумок"), "note: quiver does not fit")
			T.eq(text:find("стрелять будет нечем"), nil, "no alarm text")
			-- with bullets in the bags: same score, no ammo note
			local r2, text2 = run({ "gun", "bullets" })
			T.near(r2.delta, r.delta, 1e-9)
			T.eq(text2:find("нет пуль"), nil)
		end },
		{ "learning a weapon skill re-reads red tooltip lines", function()
			local G = env()
			local bags = { "polearm" }
			G.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
			G.C_Container.GetContainerItemLink = function(bag, slot) return bag == 0 and bags[slot] or nil end
			-- polearms not learned yet: the client answers no info for the line
			local oldSkill = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id) if id == 229 then return nil end return oldSkill(id) end
			local ns = loadAll(G)
			T.eq(ns.Advisor.Evaluate("polearm").usable, false, "not trained yet")
			-- train polearms: the client tooltip line turns white
			G.items.polearm.lines[2] = { leftText = "Двуручное", rightText = "Древковое", leftColor = { r = 1, g = 1, b = 1 }, rightColor = { r = 1, g = 1, b = 1 } }
			G.C_SkillInfo.GetSkillLineInfoByID = function(id) if id == 229 then return { rank = 1, maxRank = 225, modifier = 0 } end return oldSkill(id) end
			G.fire("SKILL_LINES_CHANGED")
			T.eq(ns.Advisor.Evaluate("polearm").usable, true, "usable after training")
		end },
		{ "quest rewards refresh on Invalidate while the rewards frame is visible", function()
			local G = env(); local ns = loadAll(G)
			local b = { type = "choice", objectType = "item", id = 1 }
			function b:GetID() return self.id end
			function b:IsShown() return true end
			function b:CreateTexture()
				local t = { shown = false }
				function t:SetTexture(f) self.file = f end function t:SetVertexColor(r, g, bl) self.color = { r, g, bl } end
					function t:SetSize() end function t:SetPoint() end
				function t:SetColorTexture() end function t:SetAllPoints() end
				function t:Show() self.shown = true end function t:Hide() self.shown = false end
				return t
			end
			local rf = { RewardButtons = { b } }
			function rf:IsVisible() return true end
			G.QuestInfoFrame = { rewardsFrame = rf }
			function G.QuestInfoFrame:IsVisible() return false end -- the real QuestInfoFrame stays hidden
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			T.truthy(b.hgaCheck and b.hgaCheck.shown, "reward marked after Invalidate")
		end },
		{ "every event registers, no error is reported at load", function()
			local G = env(); loadAll(G)
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		{ "an unknown event is reported, the rest still registers", function()
			local G = env(); local ns = {}
			assert(loadfile("Game/Init.lua", "t", G))("HunterGearAdvisor", ns)
			ns.On("NO_SUCH_EVENT", function() end)
			ns.On("PLAYER_LOGIN", function() G.loginSeen = true end)
			T.eq(#G.reportedErrors, 1); T.truthy(G.reportedErrors[1]:find("NO_SUCH_EVENT"), "named")
			G.fire("PLAYER_LOGIN"); T.eq(G.loginSeen, true)
		end },
		{ "secret stats do not crash: the hidden message while no reading exists, the last stats once one does", function()
			local G = env()
			local secret = {}
			G.UnitRangedAttackPower = function() return secret, 0, 0 end
			G.secretValues = { [secret] = true }
			local ns = loadAll(G)
			T.eq(ns.Advisor.Evaluate("newbow"), nil, "no evaluation while hidden")
			local lines = ns.Advisor.Explain("newbow")
			T.truthy(lines[1][1]:find("скрывает статы"), lines[1][1])
			-- stats readable again (after combat): then hidden again -> last values are reused
			G.UnitRangedAttackPower = function() return 413, 70, 0 end
			G.fire("PLAYER_REGEN_ENABLED")
			T.truthy(ns.Advisor.Evaluate("newbow"), "evaluated after combat")
			G.UnitRangedAttackPower = function() return secret, 0, 0 end
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			local r = ns.Advisor.Evaluate("newbow")
			T.truthy(r and ns.Advisor.State().snap.statsStale, "stale stats used while hidden")
		end },
		-- Player.lua's isSecret tests each value: the last of the sheet's values (the spell crit) hidden
		{ "a secret value last in the sheet's values hides the stats", function()
			local G = env()
			local secret = {}
			G.GetSpellCritChance = function() return secret end
			G.secretValues = { [secret] = true }
			local ns = loadAll(G)
			T.eq(ns.Advisor.Evaluate("newbow"), nil, "no evaluation while the last value is hidden")
			T.truthy(ns.Advisor.Explain("newbow")[1][1]:find("скрывает статы"), "the hidden message")
			G.GetSpellCritChance = function() return 5.63 end
			G.fire("PLAYER_REGEN_ENABLED")
			T.truthy(ns.Advisor.Evaluate("newbow"), "evaluated once it is readable")
		end },
		-- Init.lua's ns.On: the handlers of one event run in the order given, with the event's name and arguments
		{ "event handlers run in the order given, with the event and its arguments", function()
			local G = env(); local ns = {}
			assert(loadfile("Game/Init.lua", "t", G))("HunterGearAdvisor", ns)
			local calls = {}
			ns.On("UNIT_PET", function(event, unit) calls[#calls + 1] = "a " .. event .. " " .. unit end)
			ns.On("UNIT_PET", function(event, unit) calls[#calls + 1] = "b " .. event .. " " .. unit end)
			G.fire("UNIT_PET", "player")
			T.eq(#calls, 2); T.eq(calls[1], "a UNIT_PET player"); T.eq(calls[2], "b UNIT_PET player")
			T.eq(#G.reportedErrors, 0, "no errors")
		end },
		{ "inspected players' items are candidates, not worn", function()
			local G = env(); local ns = loadAll(G)
			local tip = { lines = {} }
			function tip:GetItem() return "Лук", "bow" end
			function tip:AddLine(t) table.insert(self.lines, t) end
			-- the inspected hunter wears the same bow as the player: still not "worn" by the player
			function tip:GetPrimaryTooltipInfo() return { getterName = "GetInventoryItem", getterArgs = { "target", 18, n = 2 } } end
			G.GameTooltip = tip
			G.tooltipPost(tip)
			T.truthy(tip.lines[1] and tip.lines[1]:find("примерно как надетое"), "evaluated as a candidate: " .. tostring(tip.lines[1]))
			local mine = { lines = {} }
			function mine:GetItem() return "Лук", "bow" end
			function mine:AddLine(t) table.insert(self.lines, t) end
			function mine:GetPrimaryTooltipInfo() return { getterName = "GetInventoryItem", getterArgs = { "player", 18, n = 2 } } end
			G.GameTooltip = mine
			G.tooltipPost(mine)
			T.eq(#mine.lines, 0, "own worn bow: no gain line")
		end },
		{ "2H-vs-pair DPS counts damage only", function()
			local G = env()
			G.equippedLinks[16] = "staff"; G.equippedLinks[17] = nil
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			G.items.tank1 = { info = { 30, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Меч стойкости"), ln("Одноручное", "Меч"),
				ln("Урон: 50-85", "Скорость 2,60"), ln("(26,0 ед. урона в секунду)"), ln("+20 к выносливости"), ln("+15 к интеллекту") }, api = {} }
			G.items.tank2 = { info = { 31, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Меч разума"), ln("Одноручное", "Меч"),
				ln("Урон: 50-85", "Скорость 2,60"), ln("(26,0 ед. урона в секунду)"), ln("+20 к выносливости"), ln("+15 к интеллекту") }, api = {} }
			local bags = { "tank1", "tank2" }
			G.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
			G.C_Container.GetContainerItemLink = function(bag, slot) return bag == 0 and bags[slot] or nil end
			local ns = loadAll(G)
			local pair = ns.Advisor.BestPairVs2H()
			local viaItem = ns.Advisor.Evaluate("tank1", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(pair and viaItem, "both computed")
			T.near(pair.dps, viaItem.dps, 1e-6, "same DPS number in both tooltips")
			T.truthy(pair.dps < 0 and pair.secHp > 0 and pair.secMana > 0, "losing 12 agi is a DPS loss; stamina/int are secondary")
			T.eq(pair.verdict, "worse", "damage decides even with lots of health and mana")
			T.eq(viaItem.isUpgrade, false)
		end },
		{ "no 'better without' line that just repeats the worn hands", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			G.items.rusty = { info = { 32, "INVTYPE_WEAPON", 2, 7 }, lines = { { leftText = "Ржавый меч", leftColor = W1 },
				{ leftText = "Одноручное", rightText = "Меч", leftColor = W1, rightColor = W1 },
				{ leftText = "Урон: 4-8", rightText = "Скорость 2,00", leftColor = W1, rightColor = W1 },
				{ leftText = "(3,0 ед. урона в секунду)", leftColor = W1 } }, api = {} }
			local bags = { "rusty" }
			G.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
			G.C_Container.GetContainerItemLink = function(bag, slot) return bag == 0 and bags[slot] or nil end
			local ns = loadAll(G)
			local r = ns.Advisor.Evaluate("rusty", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(r.delta < 0, "rusty is worse")
			T.eq(r.betterOther, nil)
		end },
		{ "talents are read live: Careful Aim 5/5 makes an Intellect neck a damage upgrade", function()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			local function setup(ranks)
				local G = env()
				G.talentRanks = ranks
				G.items.intneck = { info = { 40, "INVTYPE_NECK", 4, 0 }, lines = { ln("Ожерелье разума"), ln("Шея"), ln("+20 к интеллекту") }, api = {} }
				local bags = { "intneck" }
				G.C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
				G.C_Container.GetContainerItemLink = function(bag, slot) return bag == 0 and bags[slot] or nil end
				return G, loadAll(G)
			end
			-- the user's build: no Careful Aim -> Intellect is mana only, damage equal, mana better
			local _, ns0 = setup({ [104960] = 5, [104969] = 5, [104967] = 5, [105011] = 2 })
			local r0 = ns0.Advisor.Evaluate("intneck", { kind = "bag", bag = 0, slot = 1 })
			T.eq(ns0.Advisor.State().snap.points.BM, 15, "points per branch from the read ranks")
			T.near(r0.delta, 0, 1e-9); T.eq(r0.verdict, "better2")
			-- with Careful Aim 5/5 (node 105008) Intellect is damage
			local _, ns1 = setup({ [104960] = 5, [104969] = 5, [104967] = 5, [105011] = 2, [105008] = 5 })
			local r1 = ns1.Advisor.Evaluate("intneck", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(r1.delta > 15, "20 Int = ~20 AP of damage: " .. r1.delta)
			T.eq(r1.verdict, "better")
		end },
		-- HGA keeps no setting (Init.lua; raid-mode design 14.6): a saved settings table goes whole at ADDON_LOADED, whatever
		-- version saved it (the keys of /hga target, /hga cap, /hga min and /hga banner, of /hga melee, /hga weave and /hga ppm,
		-- and a key HGA does not know), the saved version is 5; the other saved data stays; ns.settings is no more. The loaded
		-- checks of the tooltip and the quest frames read ns.db (set at ADDON_LOADED)
		{ "settings: the saved settings table goes whole, whatever version saved it; the other saved data stays; the loaded checks read ns.db", function()
			for _, version in ipairs({ 5, 4, 3, 2, false }) do
				local G = env()
				G.HunterGearAdvisorDB = { settingsVersion = version or nil, settings = { mobDiff = 2, hitCapOverride = 7, threshold = 0.5,
					swapBanner = false, meleeFrac = 0.3, weave = true, procsPerMinute = 2.5, someOtherKey = "x" },
					swapBannerPoint = { point = "TOP", relPoint = "TOP", x = 1, y = 2 } }
				local ns = loadAll(G)
				local name = "settingsVersion " .. tostring(version)
				T.eq(G.HunterGearAdvisorDB.settings, nil, "no settings under " .. name)
				T.eq(G.HunterGearAdvisorDB.settingsVersion, 5, name)
				T.eq(G.HunterGearAdvisorDB.swapBannerPoint.x, 1, "the banner's position stays under " .. name)
				T.eq(ns.settings, nil); T.eq(ns.DEFAULTS, nil); T.eq(ns.db, G.HunterGearAdvisorDB)
			end
			local G = env()
			local ns = loadAll(G)
			T.eq(G.HunterGearAdvisorDB.settings, nil, "a new saved data has no settings")
			-- the tooltip's loaded check: ns.db
			local tip = { lines = {} }
			function tip:GetItem() return "Шлем", "helm" end
			function tip:AddLine(t) self.lines[#self.lines + 1] = t end
			G.GameTooltip = tip
			G.tooltipPost(tip)
			T.truthy(#tip.lines > 0, "after ADDON_LOADED the tooltip gets its lines")
			ns.db = nil
			tip.lines = {}
			G.tooltipPost(tip)
			T.eq(#tip.lines, 0, "the loaded check reads ns.db")
		end },
		-- A raid fixture (raid-mode design section 5): the env's character at level 60 (raidLevel: every weapon line at
		-- 300, the level's 5 x 60) in raid mode against the +3 boss: the hit cap 8% (Model.HitCap(3)), the expertise cap the
		-- boss's 6.5% dodge and no parry (the pet behind, Model.PetTanks); the boss's armor 976 less the worn armor penetration
		-- (a ring's 50: Player.Snapshot p.armorPen, Model.BossArmor) in the procs' outcome (the hunter's own) with Curse of the
		-- Elements and Gift of Arthas; the creature-type bonuses at the boss's type (Model.TargetShare): the gloves' +21
		-- against beasts nothing, a trinket's +15 against dragonkin whole; the worn set gives exactly 0, a bag ring without the
		-- armor penetration in its place loses 50 x W.ARMOR_PEN; the tooltips and /hga weights' mode line say it
		{ "raid fixture at 60: +3, the 8% cap, the boss's armor less the worn armor penetration, dragonkin shares, the pet behind; the worn set gives 0", function()
			local G = env()
			raidLevel(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.penring = { info = { 45, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо пробивания"), ln("Палец"),
				ln("+5 к ловкости"), ln("Если на персонаже: ваши атаки пробивают до 50 брони.") }, api = {} }
			G.items.plainring = { info = { 46, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо"), ln("Палец"), ln("+5 к ловкости") }, api = {} }
			G.items.dragontrinket = { info = { 47, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Драконий талисман"), ln("Аксессуар"),
				ln("Если на персонаже: +15 к силе атаки против драконов.") }, api = {} }
			G.items.beastsword = { info = { 44, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Меч"), ln("Одноручное", "Меч"),
				ln("Урон: 40-75", "Скорость 2,60"), ln("(22,1 ед. урона в секунду)"), ln("Чары: +6 к убийству животных") },
				api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 22.1 } }
			G.equippedLinks[11], G.equippedLinks[13] = "penring", "dragontrinket"
			G.bags[0] = { "plainring", "beastsword", "penring", "dragontrinket", "gloves" }
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			T.truthy(st, "state: " .. tostring(ns.Advisor.notReadyReason))
			local m, ctx, W, M = st.model, st.ctx, st.W, ns.Model
			T.eq(m.mode, "raid"); T.eq(m.level, 60); T.eq(m.mobDiff, 3)
			T.eq(m.rangedSkill, 0, "the bow at 300"); T.eq(m.mhSkill, 0, "the sword at 300"); T.eq(m.rangedHit, 0)
			T.eq(ctx.hitCap, 8); T.eq(ctx.expertiseCap, 6.5); T.eq(ctx.parryCap, 6.5, "the pet behind: no parry")
			T.eq(m.armorPen, 50, "the ring's armor penetration")
			T.eq(m.apVsTarget, 15, "the dragonkin trinket's 15 whole, the gloves' 21 against beasts nothing")
			local o = ctx.procOutcome
			T.near(o.phys, M.ArmorMult(926, 60), 1e-12, "the boss's 976 less 50"); T.eq(o.coe, 1.10); T.eq(o.gift, 8)
			T.truthy(W.ARMOR_PEN > 0, "armor penetration has a damage weight")
			T.eq(W.AP_VS_BEAST, 0); T.near(W.AP_VS_DRAGONKIN, W.AP_VS, 1e-12); T.eq(W.BEAST_SLAYING, 0)
			-- the worn set gives 0, every worn item too; the plain ring in the worn ring's place loses the armor penetration alone
			T.eq(ctx.weaponGain(st.snap.equipped), 0, "the worn weapons")
			for slot, piece in pairs(st.snap.equipped) do
				T.eq(ns.Advisor.Evaluate(piece.link, { kind = "equipped", slot = slot }).delta, 0, "worn " .. piece.link)
			end
			-- a bag copy of the worn ring goes into the empty second ring slot: the copy's own 5 Agility and 50 armor penetration
			T.near(ns.Advisor.Evaluate("penring", { kind = "bag", bag = 0, slot = 3 }).delta, 5 * W.AGI + 50 * W.ARMOR_PEN, 1e-9,
				"the bag copy of the worn ring in the empty slot")
			-- the plain ring in the worn ring's place (Score.SetValue of the worn set with that slot changed): the armor
			-- penetration alone, priced by its key at W.ARMOR_PEN
			local swapped = ns.Score.CopySet(st.snap.equipped)
			swapped[11] = ns.Items.Piece(ns.Items.Get("plainring"), { kind = "bag", bag = 0, slot = 1 })
			T.near(ns.Score.SetValue(swapped, W, ctx) - ns.Score.SetValue(st.snap.equipped, W, ctx), -50 * W.ARMOR_PEN, 1e-9,
				"the ring without its 50 armor penetration")
			-- the tooltips: the creature-type bonuses by the boss's type
			local function explain(link, slot)
				local t = {}
				for i, l in ipairs(ns.Advisor.Explain(link, { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local sword = explain("beastsword", 2)
			T.truthy(sword:find("HGA: «+6 к убийству животных» — в рейд-режиме цель дракон: не учитывается", 1, true), sword)
			T.eq(sword:find("учтено по зверям", 1, true), nil, sword)
			local gloves = explain("gloves", 5)
			T.truthy(gloves:find("HGA: «+21 к силе атаки против животных» — в рейд-режиме цель дракон: не учитывается (только твои атаки: пету и ястребам не идёт)", 1, true), gloves)
			local trinket = explain("dragontrinket", 4)
			T.truthy(trinket:find("HGA: «+15 к силе атаки против драконов» учтено полностью: в рейд-режиме цель дракон (только твои атаки: пету и ястребам не идёт)", 1, true), trinket)
			-- /hga weights: the mode line with the worn armor penetration
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.eq(G.printed[1], "|cff7fbf3fHGA:|r режим: рейд (ур. 60) — босс +3 (дракон), броня 976 (твоим атакам с пробиванием брони 50 — 926), кап меткости 8.0%, бой 180 ± 5 с, кулдауны с 5-й секунды, пет сзади")
			T.eq(#G.reportedErrors, 0)
			-- the same items at 59 (levelling): the creature-type bonuses at the share of mobs (30%), the tooltip lines say so
			local G2 = env()
			G2.items.dragontrinket, G2.items.beastsword = G.items.dragontrinket, G.items.beastsword
			G2.equippedLinks[13] = "dragontrinket"
			G2.bags[0] = { "beastsword" }
			G2.UnitLevel = function() return 59 end
			local ns2 = loadAll(G2)
			local st2 = ns2.Advisor.State()
			T.eq(st2.model.mode, "level")
			T.near(st2.model.apVsTarget, (15 + 21) * M.AP_CREATURE_SHARE, 1e-12, "levelling: every type at the share")
			local t2 = {}
			for i, l in ipairs(ns2.Advisor.Explain("beastsword", { kind = "bag", bag = 0, slot = 1 })) do t2[i] = l[1] end
			local s2 = table.concat(t2, "\n")
			T.truthy(s2:find("учтено по зверям (доля 30%)", 1, true), s2)
			T.eq(s2:find("рейд-режиме", 1, true), nil, s2)
		end },
		-- The Use buffs in raid mode (raid-mode design 6.3, 6.8): Advisor A.State's ctx.useGain(set) is the model's total with
		-- the set's buffs in the raid fight (Model.Total with p.uses = Score.SetUses(set)) less the point's, in the weights'
		-- unit; ctx.useUptime(set) their shares (Model.UseUptimes). The env at 60 wears Earthstrike 21180 (20 s every 120 s:
		-- 5-25 and 125-145 s, 40 of the 180 weighted seconds, 22%); Kiss of the Spider 22954 from the bag goes into the empty
		-- trinket slot 14 and waits for Earthstrike's burst lock: 25-40 and 145-160 s, 30 s, 17%. The worn set and the worn
		-- trinket give exactly 0; the bag trinket's delta is the two buffs' gain less Earthstrike's alone; the tooltips name the
		-- casts, the share and the start
		{ "raid use: ctx.useGain runs the set's Use buffs through the fight; the worn set gives 0; the tooltip names the windows", function()
			local G = env()
			raidLevel(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.earthstrike = { info = { 21180, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Земной удар"), ln("Аксессуар"),
				ln("Использование: Увеличивает силу атаки на 280 ед. на 20 сек.") }, api = {} }
			G.items.kiss = { info = { 22954, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Поцелуй паука"), ln("Аксессуар"),
				ln("Использование: Увеличивает скорость атаки на 20% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "earthstrike"
			G.bags[0] = { "kiss" }
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			T.truthy(st, "state: " .. tostring(ns.Advisor.notReadyReason))
			local ctx, M = st.ctx, ns.Model
			T.eq(ctx.mode, "raid")
			local function gainOf(uses)
				local p = {}
				for k, v in pairs(st.model) do p[k] = v end
				p.uses = uses
				return (M.Total(p) - st.total) / st.unitDps
			end
			local es, kiss = ns.UseData[21180], ns.UseData[22954]
			T.near(ctx.useGain(st.snap.equipped), gainOf({ es }), 1e-12, "the worn Earthstrike through the fight")
			T.truthy(ctx.useGain(st.snap.equipped) > 0, "it gains")
			T.near(ctx.useUptime(st.snap.equipped)[es.spell], 40 / 180, 1e-12)
			for slot, piece in pairs(st.snap.equipped) do
				T.eq(ns.Advisor.Evaluate(piece.link, { kind = "equipped", slot = slot }).delta, 0, "worn " .. piece.link)
			end
			local r = ns.Advisor.Evaluate("kiss", { kind = "bag", bag = 0, slot = 1 })
			T.near(r.delta, gainOf({ es, kiss }) - gainOf({ es }), 1e-9, "Kiss of the Spider after Earthstrike")
			-- the order decides which burst buff waits: the two in the other slots are another run (Score.SetUses' order)
			local kissPiece = ns.Items.Piece(ns.Items.Get("kiss"), { kind = "bag", bag = 0, slot = 1 })
			local esPiece = st.snap.equipped[13]
			T.near(ctx.useGain({ [13] = esPiece, [14] = kissPiece }), gainOf({ es, kiss }), 1e-12, "Earthstrike first")
			T.near(ctx.useGain({ [13] = kissPiece, [14] = esPiece }), gainOf({ kiss, es }), 1e-12, "Kiss of the Spider first")
			T.truthy(math.abs(gainOf({ kiss, es }) - gainOf({ es, kiss })) > 1e-6, "the two orders differ")
			T.near(ctx.useUptime({ [13] = kissPiece, [14] = esPiece })[kiss.spell], 30 / 180, 1e-12, "Kiss of the Spider first: 5-20, 125-140 s")
			T.truthy(r.delta > 0, "it gains")
			local function explain(link, where)
				local t = {}
				for i, l in ipairs(ns.Advisor.Explain(link, where)) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local kissText = explain("kiss", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(kissText:find("HGA: «Использование» учтено как оценка: 15 сек. раз в 2 мин. — в бою 180 с 2 раз(а), 17% времени, с 25-й секунды, после «Использования» другой вещи (общий откат)", 1, true), kissText)
			local esText = explain("earthstrike", { kind = "equipped", slot = 13 })
			T.truthy(esText:find("HGA: «Использование» учтено как оценка: 20 сек. раз в 2 мин. — в бою 180 с 2 раз(а), 22% времени, с 5-й секунды вместе с Rapid Fire и Bestial Wrath", 1, true), esText)
			T.eq(#G.reportedErrors, 0)
		end },
		-- The change of the raid fight's events on a set (raid-mode design 25.1): the env at 60 with a pool of 2250, where the mana
		-- potion's 2250 and 5 s of the casting regen never fit (Model.Fight: no potion), and a neck of 20 Intellect in the bag
		-- (300 mana more: it fits). The weights hold the model point's events (A.State's W are Model.Weights'), so the neck's
		-- W.INT x 20 leaves the potion out; ctx.eventGain({ INT = 20 }) is Model.EventGain at the model point with the neck's
		-- Intellect applied against its events, in the weights' unit, one run cached; none gives 0. The neck's delta is the
		-- model's own gain of 20 Intellect (the fight is linear in it on each side of the fit here: to 1e-6, my run), the worn
		-- pieces 0
		{ "raid events: a bag neck whose Intellect makes the mana potion fit gets the potion's change (ctx.eventGain); the worn pieces 0", function()
			local G = env()
			raidLevel(G)
			G.UnitPowerMax = function() return 2250 end
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.intneck = { info = { 40, "INVTYPE_NECK", 4, 0 }, lines = { ln("Ожерелье разума"), ln("Шея"), ln("+20 к интеллекту") }, api = {} }
			G.bags[0] = { "intneck" }
			local ns = loadAll(G)
			settlePet(G)
			local M = ns.Model
			-- every run of the fight ctx.eventGain makes (Model.EventGain), counted from a fresh state's
			local runs = 0
			local eg = M.EventGain
			M.EventGain = function(...) runs = runs + 1; return eg(...) end
			ns.Advisor.Reset()
			local st = ns.Advisor.State()
			T.truthy(st, "state: " .. tostring(ns.Advisor.notReadyReason))
			local ctx = st.ctx
			T.eq(st.snap.equipped[2], nil, "no neck worn")
			T.eq(M.Fight(st.model).manaPotion, nil, "2250: no room for the potion")
			local q = {}
			for k, v in pairs(st.model) do q[k] = v end
			M.ApplyStats(q, { INT = 20 })
			T.eq(M.Fight(q).manaPotion, 125, "300 mana more: it fits")
			local gain = ctx.eventGain({ INT = 20 })
			T.eq(runs, 1, "one run")
			T.near(gain, eg(q, M.FightEvents(st.model)) / st.unitDps, 1e-12, "Model.EventGain in the weights' unit")
			T.truthy(gain > 20 * st.W.INT, "the potion's change: " .. gain)
			T.eq(ctx.eventGain({}), 0); T.eq(runs, 1, "no stats: no run")
			-- the cache keys on the amounts as well: 1 Intellect (15 mana) leaves the potion out, its own gain 0, and the 20's
			-- gain stays its own
			local q1 = {}
			for k, v in pairs(st.model) do q1[k] = v end
			M.ApplyStats(q1, { INT = 1 })
			T.eq(M.Fight(q1).manaPotion, nil, "15 mana more: still no room")
			T.eq(ctx.eventGain({ INT = 1 }), 0, "another amount of the same stat: its own gain"); T.eq(runs, 2, "its own run")
			T.eq(ctx.eventGain({ INT = 20 }), gain, "the 20's gain"); T.eq(runs, 2, "cached")
			-- the runs (raid-mode design 26.3): stats with no key of Model.EventKeys change no event, 0 with no run (the BM tree has
			-- no Resourcefulness: Agility's crit is no mana input); a projection on those keys whose run changed none gives 0 to
			-- every stats table of it with no run; a stats table of a projection that changes one runs on its own, the cross term
			-- of its other keys in its gain
			T.eq(ctx.eventGain({ AP = 50, STR = 10, AGI = 12, ARMOR_PEN = 30 }), 0, "no key of the mana's"); T.eq(runs, 2, "no run")
			T.eq(ctx.eventGain({ INT = 1, AP = 50 }), 0, "the projection of 1 Intellect, whose run changed no event"); T.eq(runs, 2, "no run")
			local q20 = {}
			for k, v in pairs(st.model) do q20[k] = v end
			M.ApplyStats(q20, { INT = 20, AP = 50 })
			local g20 = ctx.eventGain({ INT = 20, AP = 50 })
			T.eq(runs, 3, "a projection that changes an event: a run of its own")
			T.near(g20, eg(q20, M.FightEvents(st.model)) / st.unitDps, 1e-12, "the whole stats' gain")
			T.truthy(math.abs(g20 - gain) > 1e-6, "the attack power's cross term in it: " .. g20 .. " against " .. gain)
			ctx.eventGain({ INT = 20, AP = 50 }); T.eq(runs, 3, "cached")
			M.EventGain = eg
			local r = ns.Advisor.Evaluate("intneck", { kind = "bag", bag = 0, slot = 1 })
			T.near(r.delta, (M.Total(q) - st.total) / st.unitDps, 1e-6, "the model's own gain of 20 Intellect")
			T.near(r.delta, 20 * st.W.INT + gain, 1e-9, "W.INT x 20 + the event's change")
			for slot, piece in pairs(st.snap.equipped) do
				T.eq(ns.Advisor.Evaluate(piece.link, { kind = "equipped", slot = slot }).delta, 0, "worn " .. piece.link)
			end
			T.eq(#G.reportedErrors, 0)
		end },
		-- The raid Use line (raid-mode design 6.8, 19.1): «вместе с Rapid Fire» alone where the fight has no Bestial Wrath (the
		-- env without the talent), the casts the buff's windows in the fight: Molten Heart of the Mountain 249470 (55 attack
		-- power, 15 s every 5 min, Game/UseData.lua) once, 15 of the 180 weighted seconds (8%). An item the character cannot
		-- wear (a class line in red: Parse restricted, Player.CanUse) goes into no set, so its buff fires alone: Earthstrike
		-- 21180 from 5 s, not after the worn Heart's 15 s burst lock. A set that holds the item but not its Use spell cannot be
		-- (Score.Evaluate puts the item into res.newSet, a worn item is in the worn set): an error
		{ "raid use line: «вместе с Rapid Fire» without Bestial Wrath; one cast; an item in no set alone; a set without the item's spell an error", function()
			local G = env()
			raidLevel(G)
			G.talentRanks[104961] = nil -- no Bestial Wrath (Player.BRANCHES bestialWrath)
			local Wc, RED = { r = 1, g = 1, b = 1 }, { r = 1, g = 0.125, b = 0.125 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.heart = { info = { 249470, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сердце горы"), ln("Аксессуар"),
				ln("Использование: Увеличивает силу атаки на 55 ед. на 15 сек.") }, api = {} }
			G.items.warriorstrike = { info = { 21180, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Земной удар"), ln("Аксессуар"),
				{ leftText = "Классы: Воин", leftColor = RED, rightColor = Wc },
				ln("Использование: Увеличивает силу атаки на 280 ед. на 20 сек.") }, api = {} }
			G.equippedLinks[13] = "heart"
			G.bags[0] = { "warriorstrike" }
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			T.truthy(st, "state: " .. tostring(ns.Advisor.notReadyReason))
			T.eq(st.model.mode, "raid"); T.eq(st.model.tal.bestialWrath, 0, "no Bestial Wrath")
			local function explain(link, where)
				local t = {}
				for i, l in ipairs(ns.Advisor.Explain(link, where)) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local heartText = explain("heart", { kind = "equipped", slot = 13 })
			T.truthy(heartText:find("HGA: «Использование» учтено как оценка: 15 сек. раз в 5 мин. — в бою 180 с 1 раз(а), 8% времени, с 5-й секунды вместе с Rapid Fire", 1, true), heartText)
			T.eq(heartText:find("Bestial Wrath", 1, true), nil, heartText)
			local r = ns.Advisor.Evaluate("warriorstrike", { kind = "bag", bag = 0, slot = 1 })
			T.eq(r.usable, false, "a warrior's trinket"); T.eq(r.newSet, nil, "in no set")
			local wsText = explain("warriorstrike", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(wsText:find("HGA: «Использование» учтено как оценка: 20 сек. раз в 2 мин. — в бою 180 с 2 раз(а), 22% времени, с 5-й секунды вместе с Rapid Fire", 1, true), wsText)
			local keep = ns.Score.SetUses
			ns.Score.SetUses = function() return {} end
			local ok, err = pcall(ns.Advisor.Explain, "heart", { kind = "equipped", slot = 13 })
			ns.Score.SetUses = keep
			T.eq(ok, false, "a set without the item's spell")
			T.truthy(tostring(err):find("the set of Сердце горы holds no Use spell 1249113", 1, true), tostring(err))
			T.eq(#G.reportedErrors, 0)
		end },
		-- The Use buffs fire at one instant in wowsims' order (Score.SetUses: the ItemSlot order of its equipment array,
		-- sim/core/item_effects.go:107-120): the worn Cloudkeeper Legplates 14554 (100 attack power, 30 s every 15 min, the burst
		-- category 1141) before the worn Earthstrike 21180 in trinket slot 13, so the legs fire at 5 s with Rapid Fire and
		-- Bestial Wrath and Earthstrike when their 30 s lock ends, 35-55 and 155-175 s: ctx.useGain runs them in that order, and
		-- the tooltips say so
		{ "raid use order: the legs before the trinkets, as wowsims registers them; Earthstrike waits for the legs' lock", function()
			local G = env()
			raidLevel(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.cloudlegs = { info = { 14554, "INVTYPE_LEGS", 4, 4 }, lines = { ln("Поножи Облачного Стража"), ln("Ноги", "Латы"),
				ln("Использование: Увеличивает силу атаки на 100 ед. на 30 сек.") }, api = {} }
			G.items.earthstrike = { info = { 21180, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Земной удар"), ln("Аксессуар"),
				ln("Использование: Увеличивает силу атаки на 280 ед. на 20 сек.") }, api = {} }
			G.equippedLinks[7], G.equippedLinks[13] = "cloudlegs", "earthstrike"
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			T.truthy(st, "state: " .. tostring(ns.Advisor.notReadyReason))
			local legs, es = ns.UseData[14554], ns.UseData[21180]
			local function gainOf(uses)
				local p = {}
				for k, v in pairs(st.model) do p[k] = v end
				p.uses = uses
				return (ns.Model.Total(p) - st.total) / st.unitDps
			end
			T.near(st.ctx.useGain(st.snap.equipped), gainOf({ legs, es }), 1e-12, "the legs first")
			T.truthy(math.abs(gainOf({ legs, es }) - gainOf({ es, legs })) > 1e-6, "the other order differs")
			for slot, piece in pairs(st.snap.equipped) do
				T.eq(ns.Advisor.Evaluate(piece.link, { kind = "equipped", slot = slot }).delta, 0, "worn " .. piece.link)
			end
			local function explain(link, where)
				local t = {}
				for i, l in ipairs(ns.Advisor.Explain(link, where)) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local legsText = explain("cloudlegs", { kind = "equipped", slot = 7 })
			T.truthy(legsText:find("HGA: «Использование» учтено как оценка: 30 сек. раз в 15 мин. — в бою 180 с 1 раз(а), 17% времени, с 5-й секунды вместе с Rapid Fire и Bestial Wrath", 1, true), legsText)
			local esText = explain("earthstrike", { kind = "equipped", slot = 13 })
			T.truthy(esText:find("HGA: «Использование» учтено как оценка: 20 сек. раз в 2 мин. — в бою 180 с 2 раз(а), 22% времени, с 35-й секунды, после «Использования» другой вещи (общий откат)", 1, true), esText)
			T.eq(#G.reportedErrors, 0)
		end },
		-- A worn set bonus's armor penetration (Game/SetData.lua ARMOR_PEN; raid-mode design 2.4 and 5.1: p.armorPen is the
		-- worn items' and set bonuses' ARMOR_PEN; tools/gen_set_data.py writes none for build 70888, so the set here is made
		-- up): at 60 a ring's 50 and the set's 30 make p.armorPen 80, the boss's 976 less 80 in the procs' outcome; the worn
		-- set gives exactly 0, and a set without one of its two pieces loses the bonus's 30 x W.ARMOR_PEN
		{ "raid: a worn set bonus's ARMOR_PEN is in p.armorPen with the items'; the worn set gives 0", function()
			local G = env()
			raidLevel(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.penring = { info = { 45, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо пробивания"), ln("Палец"),
				ln("Если на персонаже: ваши атаки пробивают до 50 брони.") }, api = {} }
			G.items.aplegs = { info = { 83, "INVTYPE_LEGS", 4, 3 }, setID = 99913, lines = { ln("Поножи"), ln("Ноги", "Кольчуга") }, api = {} }
			G.items.apfeet = { info = { 84, "INVTYPE_FEET", 4, 3 }, setID = 99913, lines = { ln("Сапоги"), ln("Ступни", "Кольчуга") }, api = {} }
			G.items.plainlegs = { info = { 85, "INVTYPE_LEGS", 4, 3 }, lines = { ln("Поножи"), ln("Ноги", "Кольчуга") }, api = {} }
			G.equippedLinks[11], G.equippedLinks[7], G.equippedLinks[8] = "penring", "aplegs", "apfeet"
			G.bags[0] = { "plainlegs" }
			local ns = loadAll(G)
			ns.SetData[99913] = { name = "made-up", { n = 2, spell = 1, stats = { ARMOR_PEN = 30 } } }
			ns.Invalidate()
			local st = ns.Advisor.State()
			T.truthy(st, "state: " .. tostring(ns.Advisor.notReadyReason))
			local m, ctx, W = st.model, st.ctx, st.W
			T.eq(m.mode, "raid")
			T.eq(m.armorPen, 80, "the ring's 50 and the set bonus's 30")
			T.near(ctx.procOutcome.phys, ns.Model.ArmorMult(896, 60), 1e-12, "the boss's 976 less 80")
			T.truthy(W.ARMOR_PEN > 0, "armor penetration has a damage weight")
			for slot, piece in pairs(st.snap.equipped) do
				T.eq(ns.Advisor.Evaluate(piece.link, { kind = "equipped", slot = slot }).delta, 0, "worn " .. piece.link)
			end
			local broken = ns.Score.CopySet(st.snap.equipped)
			broken[7] = ns.Items.Piece(ns.Items.Get("plainlegs"), { kind = "bag", bag = 0, slot = 1 })
			T.near(ns.Score.SetValue(broken, W, ctx) - ns.Score.SetValue(st.snap.equipped, W, ctx), -30 * W.ARMOR_PEN, 1e-9,
				"the set without its bonus loses the 30 armor penetration")
			T.eq(#G.reportedErrors, 0)
		end },
		-- The env's weapon lines follow the level (env: 5 x the level, polearms from 20), so at 60 the worn lines are at 300 and
		-- the pet's melee crit branch (wowsims sim/hunter/pets.go:147-153 inheritedCrit: the owner's melee crit less 0.04% a
		-- point of the main hand's skill below the level's maximum; an empty main hand has no bonus, sim/core/weapon_skill.go:
		-- 17-19, sim/core/character.go:612-618) loses nothing to the worn main hand: no hands configuration of the worn weapons
		-- beats the worn one, and the plan without candidates is empty. A bow and a main hand on lines trained to 215 of 300 are
		-- 85 points below, each branch 3.4% lower (the sheet's melee and ranged crit equal): by wowsims' rule an empty main
		-- hand gives the pet the whole melee branch, so BestHands empties the main hand, and the empty main hand's weapon run
		-- gains exactly the pet's and the hawks' parts at skill 0 against -85 (the hawks take half the pet's crit; the BM build
		-- has no melee: the main hand reaches nothing else of the model)
		{ "env: the weapon lines follow the level; at 60 the worn main hand at the level's skill stays, one 85 points below comes off for the pet's melee crit (wowsims)", function()
			local G = env()
			local skill = G.C_SkillInfo.GetSkillLineInfoByID
			T.eq(skill(43).rank, 215, "level 43: 5 x 43"); T.eq(skill(43).maxRank, 215)
			G.UnitLevel = function() return 8 end
			T.eq(skill(45).rank, 40, "level 8: 5 x 8"); T.eq(skill(229), nil, "no polearms before 20")
			G.UnitLevel = function() return 20 end
			T.eq(skill(229).rank, 100, "polearms from 20")
			raidLevel(G)
			T.eq(skill(43).rank, 300); T.eq(skill(45).maxRank, 300)
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			local Sc = ns.Score
			local eq, W, ctx = st.ctx.equipped, st.W, st.ctx
			T.eq(st.model.mode, "raid"); T.eq(st.model.mhSkill, 0, "the sword at 300")
			local cur = Sc.SetValue(eq, W, ctx)
			T.near(Sc.BestHands(nil, eq, {}, W, ctx).value, cur, 1e-9, "no hands configuration of the worn weapons beats the worn one")
			T.eq(#Sc.PlanRows(eq, Sc.Plan(eq, {}, W, ctx)), 0, "no plan without candidates")
			local G2 = env()
			raidLevel(G2)
			local base = G2.C_SkillInfo.GetSkillLineInfoByID
			G2.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 43 or id == 45 then return { rank = 215, maxRank = 300, modifier = 0 } end
				return base(id)
			end
			local ns2 = loadAll(G2)
			settlePet(G2)
			local st2 = ns2.Advisor.State()
			local eq2, W2, ctx2, M = st2.ctx.equipped, st2.W, st2.ctx, ns2.Model
			T.eq(st2.model.mhSkill, -85, "the sword at 215 of 300"); T.eq(st2.model.rangedSkill, -85, "the bow at 215 of 300")
			local cur2 = ns2.Score.SetValue(eq2, W2, ctx2)
			local bh = ns2.Score.BestHands(nil, eq2, {}, W2, ctx2)
			T.eq(bh.mh, nil, "the main hand comes off")
			T.truthy(bh.value > cur2 + ns2.Score.EPS, "a gain")
			local empty = {}
			for k, v in pairs(st2.model) do empty[k] = v end
			for k, v in pairs(ns2.Player.WeaponInputs(bh.set)) do empty[k] = v end
			empty.mhSkill, empty.ohSkill = ns2.Score.MeleeSkills(bh.set, ctx2)
			T.eq(empty.mhSkill, 0, "an empty main hand has no bonus")
			local held = {}
			for k, v in pairs(empty) do held[k] = v end
			held.mhSkill = -85
			local pe, ph = M.Parts(empty), M.Parts(held)
			for k, v in pairs(pe) do
				if k ~= "pet" and k ~= "hawks" then T.eq(v, ph[k], "the empty main hand moves no part but the pet's and the hawks': " .. k) end
			end
			T.truthy(pe.pet > ph.pet, "the pet's crit branch whole")
			T.truthy(pe.hawks > ph.hawks, "the hawks' half of the pet's crit (summon_hawk.go:83)")
			T.near(ctx2.weaponGain(bh.set) * st2.unitDps, M.Total(empty) - M.Total(st2.model), 1e-9, "the weapon run's gain")
			T.near(M.Total(held), M.Total(st2.model), 1e-9, "at the worn main hand's -85 the empty hands configuration gains nothing")
			T.eq(#G.reportedErrors + #G2.reportedErrors, 0)
		end },
		-- the target follows the mode (Player.Snapshot; the user, 2026-11-17: on levelling the hunter's own level, at 60 the
		-- raid): mobDiff 0 below 60, 3 at 60; a mobDiff left in old saved settings is never read (the table goes at load)
		{ "target: Snapshot's mobDiff is 0 at 59 and 3 at 60, and a saved mobDiff is not read", function()
			for _, case in ipairs({ { 59, 0 }, { 43, 0 }, { 60, 3 } }) do
				local G = env()
				G.UnitLevel = function() return case[1] end
				G.HunterGearAdvisorDB = { settingsVersion = 3, settings = { mobDiff = 2 } }
				local ns = loadAll(G)
				T.eq(ns.Player.Snapshot().model.mobDiff, case[2], "level " .. case[1])
				T.eq(ns.Advisor.State().model.mobDiff, case[2], "the model point at level " .. case[1])
			end
		end },
		-- the hit cap follows the target (Advisor A.State: Model.HitCap of the model point's mobDiff): 5% at 59, 8% at 60; a
		-- hitCapOverride left in the saved settings is never read. /hga weights' first line names the mode, the target and
		-- the cap (raid-mode design 8, 14.5): levelling the averaged cooldowns, Serpent Sting's 80% and the tanking pet; raid
		-- the dragonkin boss, its armor 976 with the preset's debuffs (Model.BossArmor), the fight of 180 +- 5 s with the
		-- cooldowns from 5 s (Model.Fight) and the pet behind
		{ "hit cap: ctx.hitCap 5% at 59 and 8% at 60; /hga weights names the mode and the target", function()
			for _, case in ipairs({ { 59, 5, "режим: прокачка (ур. 59) — цель твоего уровня, кап меткости 5.0%, кулдауны в среднем, Serpent Sting 80%, пет держит цель" },
				{ 60, 8, "режим: рейд (ур. 60) — босс +3 (дракон), броня 976, кап меткости 8.0%, бой 180 ± 5 с, кулдауны с 5-й секунды, пет сзади" } }) do
				local G = env()
				G.UnitLevel = function() return case[1] end
				G.HunterGearAdvisorDB = { settingsVersion = 3, settings = { hitCapOverride = 7 } }
				local ns = loadAll(G)
				T.near(ns.Advisor.State().ctx.hitCap, case[2], 1e-12, "level " .. case[1])
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR("weights")
				T.eq(G.printed[1], "|cff7fbf3fHGA:|r " .. case[3], "level " .. case[1])
			end
		end },
		-- the removed commands are any other text: they print the help and change nothing (Commands.lua), no saved data and
		-- no state
		{ "slash commands: target, melee, weave, cap, ppm, min and banner print the help and change nothing", function()
			local G = env(); local ns = loadAll(G)
			local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
			local before = copy(ns.db)
			local st = ns.Advisor.State()
			for _, cmd in ipairs({ "target 3", "melee 30", "weave", "cap 7", "cap auto", "ppm 2", "min 2", "banner" }) do
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR(cmd)
				T.eq(G.printed[1], "|cff7fbf3fHGA:|r /hga weights — веса статов и входные цифры", cmd .. ": the help")
				T.eq(#G.printed, 4, cmd .. ": the whole help")
				for k, v in pairs(before) do T.eq(ns.db[k], v, cmd .. ": " .. k) end
				for k in pairs(ns.db) do T.truthy(before[k] ~= nil, cmd .. ": no new key " .. k) end
				T.eq(ns.db.settings, nil, cmd .. ": no settings")
				T.eq(ns.Advisor.State(), st, cmd .. ": the state stays")
			end
		end },
		-- the help names the commands HGA keeps: weights, dump, swap and preraid (raid-mode design 14.5)
		{ "help: the four lines of weights, dump, swap and preraid", function()
			local G = env(); loadAll(G)
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("help")
			local want = {
				"/hga weights — веса статов и входные цифры",
				"/hga dump — записать разбор всех вещей в файл (потом /reload)",
				"/hga swap — показать список замен (что из сумок надеть вместо чего)",
				"/hga preraid (/hga pr) — окно пререйд-набора: чего не хватает и где брать",
			}
			T.eq(#G.printed, #want)
			for i, l in ipairs(want) do T.eq(G.printed[i], "|cff7fbf3fHGA:|r " .. l, "line " .. i) end
		end },
		-- the mode by the level (Player.Snapshot: the user, 2026-11-17: at 60 the raid, below it levelling; Model.RAID_LEVEL)
		{ "mode: level 60 is raid, 59 is levelling (Snapshot); a raid state builds with the raid inputs", function()
			for _, case in ipairs({ { 60, "raid" }, { 59, "level" }, { 43, "level" } }) do
				local G = env()
				G.UnitLevel = function() return case[1] end
				local ns = loadAll(G)
				T.eq(ns.Player.Snapshot().model.mode, case[2], "level " .. case[1])
				local st = ns.Advisor.State()
				T.eq(st.model.mode, case[2], "the model point at level " .. case[1])
				T.truthy(st.total > 0, "the model runs at level " .. case[1])
			end
		end },
		-- The new live values of the model point (Player.ReadStats, Player.Snapshot): the effective Agility and Spirit
		-- (UnitStat's second return), the mana pool and regen (UnitPowerMax, GetManaRegen), the spell hit and crit
		-- (GetSpellHitModifier, GetSpellCritChance); the worn gear's ranged-only hit (0: no parsed stat holds one); the worn
		-- items' attack power against a creature type at Model.AP_CREATURE_SHARE (the env's gloves: +21 against beasts);
		-- Beastslaying of the hands (Player.WeaponInputs: none worn here)
		{ "snapshot: Agility, Spirit, mana, regen, spell hit and crit read live; rangedGearHit 0; apVsTarget the worn AP vs type x share", function()
			local G = env(); local ns = loadAll(G)
			local m = ns.Player.Snapshot().model
			T.eq(m.agi, 167); T.eq(m.spirit, 64); T.eq(m.manaMax, 1725)
			T.eq(m.regenRest, 12.6); T.eq(m.regenCast, 3.15)
			T.eq(m.spellHit, 0); T.eq(m.spellCrit, 5.63)
			T.eq(m.rangedGearHit, 0); T.eq(m.beastSlaying, 0)
			T.eq(ns.Items.Get("gloves").stats.AP_VS_BEAST, 21)
			T.near(m.apVsTarget, 21 * ns.Model.AP_CREATURE_SHARE, 1e-12, "the gloves' AP against beasts at the share")
		end },
		-- each new live value is SecretWhenUnitStatsRestricted (Forever UnitDocumentation.lua:3198 UnitStat,
		-- PlayerScriptDocumentation.lua:571 GetManaRegen, :1086 GetSpellCritChance, :1113 GetSpellHitModifier): one secret
		-- hides the stats like the others, and with no reading before the state is not built
		{ "secret Agility, Spirit, mana regen, spell hit or spell crit hides the stats like the other secret values", function()
			for _, case in ipairs({
				{ "Agility", function(G) G.statAgi = 167.5; return 167.5 end },
				{ "Spirit", function(G) G.statSpirit = 64.5; return 64.5 end },
				{ "regen out of the five-second rule", function(G) G.GetManaRegen = function() return 12.7, 3.15 end; return 12.7 end },
				{ "regen inside it", function(G) G.GetManaRegen = function() return 12.6, 3.17 end; return 3.17 end },
				{ "spell hit", function(G) G.GetSpellHitModifier = function() return 0.37 end; return 0.37 end },
				{ "spell crit", function(G) G.GetSpellCritChance = function() return 5.67 end; return 5.67 end },
			}) do
				local G = env()
				G.secretValues = { [case[2](G)] = true }
				local ns = loadAll(G)
				T.eq(ns.Advisor.State(), nil, case[1]); T.eq(ns.Advisor.notReadyReason, "hidden", case[1])
			end
		end },
		-- a level-up from 59 to 60 in combat: the stats secret, the last reading (taken at 59) serves only its own level
		-- (Player.ReadStats), so no state is built until the stats can be read; then the state is raid mode
		{ "mode switch: a level-up 59 -> 60 while the stats are secret uses no level-59 reading; after combat the mode is raid", function()
			local G = env()
			G.UnitLevel = function() return 59 end
			local ns = loadAll(G)
			T.eq(ns.Advisor.State().model.mode, "level", "at 59")
			G.UnitLevel = function() return 60 end
			G.secretValues = { [413] = true }
			G.fire("PLAYER_LEVEL_UP", 60)
			T.eq(ns.Advisor.State(), nil, "the level-59 reading does not serve at 60")
			T.eq(ns.Advisor.notReadyReason, "hidden")
			G.secretValues = nil
			G.advance(1)
			G.fire("PLAYER_REGEN_ENABLED")
			local st = ns.Advisor.State()
			T.eq(st.model.mode, "raid", "after combat"); T.eq(st.model.level, 60)
			T.eq(st.snap.statsStale, nil, "a new reading")
		end },
		-- Beastslaying of the set's hands (Player.WeaponInputs beastSlaying): the main hand's and the off hand's summed
		{ "WeaponInputs: beastSlaying sums the main hand's and the off hand's Beastslaying", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function sword(id, n)
				return { info = { id, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Меч " .. n), ln("Одноручное", "Меч"),
					ln("Урон: 40-75", "Скорость 2,60"), ln("(22,1 ед. урона в секунду)"), ln("Чары: +" .. n .. " к убийству животных") },
					api = {} }
			end
			G.items.bs6, G.items.bs8 = sword(71, 6), sword(72, 8)
			local ns = loadAll(G)
			local function pc(link) return ns.Items.Piece(ns.Items.Get(link), { kind = "new" }) end
			T.eq(ns.Player.WeaponInputs({ [16] = pc("bs6"), [17] = pc("bs8") }).beastSlaying, 14, "both hands")
			T.eq(ns.Player.WeaponInputs({ [16] = pc("sword"), [17] = pc("bs8") }).beastSlaying, 8, "the off hand alone")
			T.eq(ns.Player.WeaponInputs({ [16] = pc("bs6") }).beastSlaying, 6, "the main hand alone")
			T.eq(ns.Player.WeaponInputs({}).beastSlaying, 0, "no weapon")
		end },
		-- the client's mana regen and hit modifiers in /hga dump, to check the model's readings against them in game
		{ "/hga dump has manaRegen, manaRegenFromSpirit and hitModifiers; the model point holds the new inputs", function()
			local G = env()
			-- three distinct modifiers, so each field shows the function it comes from
			G.GetHitModifier = function() return 0.5 end
			G.GetRangedHitModifier = function() return 1.5 end
			G.GetSpellHitModifier = function() return 2.5 end
			local ns = loadAll(G)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump
			T.eq(d.manaRegen[1], 12.6); T.eq(d.manaRegen[2], 3.15)
			T.eq(d.manaRegenFromSpirit[1], 9.45); T.eq(d.manaRegenFromSpirit[2], 2.36)
			T.eq(d.hitModifiers.melee, 0.5, "melee: GetHitModifier"); T.eq(d.hitModifiers.ranged, 1.5, "ranged: GetRangedHitModifier")
			T.eq(d.hitModifiers.spell, 2.5, "spell: GetSpellHitModifier")
			T.eq(d.model.mode, "level"); T.eq(d.model.agi, 167); T.eq(d.model.spirit, 64); T.eq(d.model.spellCrit, 5.63)
		end },
		-- the client's ranged hit rating template reaches the parser (Game/Templates.lua KEYS)
		{ "templates: BuildTemplates returns ITEM_MOD_HIT_RANGED_RATING", function()
			local G = env(); local ns = loadAll(G)
			T.eq(ns.BuildTemplates().ITEM_MOD_HIT_RANGED_RATING, "Меткость (оруж. дальн. боя) +%s.")
		end },
		-- the client's twenty melee weapon skill templates reach the parser (Game/Templates.lua KEYS; GlobalStrings 59290-59309).
		-- Mutant: a key missing from KEYS
		{ "templates: BuildTemplates returns the twenty melee skill keys", function()
			local G = env(); local ns = loadAll(G)
			local T2 = ns.BuildTemplates()
			local n = 0
			for _, line in ipairs({ "SWORDS", "MACES", "AXES", "FIST_WEAPONS", "DAGGERS", "STAVES", "TWO-HANDED_SWORDS",
				"TWO-HANDED_MACES", "TWO-HANDED_AXES", "POLEARMS" }) do
				for _, dir in ipairs({ "INCREASE", "DECREASE" }) do
					local key = "TOOLTIP_ITEM_STAT_SKILL_" .. line .. "_" .. dir
					T.eq(T2[key], F.ruRU[key], key); T.truthy(T2[key] ~= nil, key)
					n = n + 1
				end
			end
			T.eq(n, 20)
		end },
		-- The worn gear's ranged-only hit (Player.Snapshot rangedGearHit): Marksman Bands 18296's 1% (spell 1294769) and the
		-- worn bow's +3% hit scope (SpellItemEnchantment 2523, spell 22780). The live hit is the ranged reading, which holds
		-- them (a sheet of 5%), so the hit of every attack is 1%, the model's p.rangedGearHit 4%, ctx.baseHit 1%; the worn set
		-- gives 0, and a bow without the scope loses its 3% at W.RANGED_HIT (base 1% + 4% = the 5% cap). /hga weights' cap
		-- line holds the worn ranged gear hit, and its sheet hit is the live one
		{ "snapshot: worn Marksman Bands and a worn +3% scope leave p.hit and go to p.rangedGearHit; /hga weights' cap line holds them", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.bands = { info = { 18296, "INVTYPE_WRIST", 4, 3 }, lines = { ln("Браслеты меткого стрелка"), ln("Запястья", "Кольчуга"),
				ln("Броня: 100"), ln("Если на персонаже: Повышает вероятность попадания в дальнем бою на 1%.") }, api = {} }
			local function bow(id, scope)
				local lines = { ln("Лук " .. id), ln("Дальний бой", "Лук"), ln("Урон: 40-70", "Скорость 2,60"), ln("(21,2 ед. урона в секунду)") }
				if scope then lines[#lines + 1] = ln("Чары: +3% к рейтингу меткости") end
				return { info = { id, "INVTYPE_RANGED", 2, 2 }, lines = lines, api = {} }
			end
			G.items.scopebow, G.items.plainbow = bow(75, true), bow(76, false)
			G.equippedLinks[9], G.equippedLinks[18] = "bands", "scopebow"
			G.bags[0] = { "plainbow", "bands" }
			G.GetCombatRatingBonus = function() return 5 end
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(ns.Items.Get("bands").stats.RANGED_HIT, 1); T.eq(ns.Items.Get("scopebow").stats.RANGED_HIT, 3)
			T.near(st.snap.liveHit, 5, 1e-12); T.near(st.snap.rangedGearHit, 4, 1e-12); T.near(st.snap.gearHit, 0, 1e-12)
			T.near(st.model.hit, 1, 1e-12, "the hit of every attack: the live hit less the ranged-only gear hit")
			T.near(st.model.rangedGearHit, 4, 1e-12)
			T.near(st.ctx.baseHit, 1, 1e-12); T.near(st.ctx.wornHit, 1, 1e-12)
			T.eq(st.ctx.skillBase, 0); T.eq(st.model.rangedSkill, 0); T.eq(st.model.rangedHit, 0)
			local worn = ns.Advisor.Evaluate("bands", { kind = "equipped", slot = 9 })
			T.near(worn.delta, 0, 1e-12, "the worn bands")
			T.near(ns.Advisor.Evaluate("bands", { kind = "bag", bag = 0, slot = 2 }).delta, 0, 1e-12, "the bag copy of the worn bands")
			local plain = ns.Advisor.Evaluate("plainbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(plain.slot, 18)
			T.near(st.ctx.weaponGain(plain.newSet), 0, 1e-12, "the same weapon")
			T.near(plain.delta, -3 * st.W.RANGED_HIT, 1e-9, "the scope's 3% at W.RANGED_HIT")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local all = table.concat(G.printed, "\n")
			T.truthy(all:find("меткость 5.00% (кап 5.0%; в листе 5.00%,", 1, true), all)
		end },
		-- a set bonus's ranged-only hit (Game/SetData.lua RANGED_HIT; tools/gen_set_data.py gives it to an aura 54 bound to
		-- ranged weapons alone; no set of build 70888 has one, so the set here is made up) is worn gear's ranged-only hit
		{ "snapshot: a worn set bonus's RANGED_HIT is in p.rangedGearHit, out of p.hit and ctx.baseHit", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.rhlegs = { info = { 77, "INVTYPE_LEGS", 4, 3 }, setID = 99911, lines = { ln("Поножи"), ln("Ноги", "Кольчуга") }, api = {} }
			G.items.rhfeet = { info = { 78, "INVTYPE_FEET", 4, 3 }, setID = 99911, lines = { ln("Сапоги"), ln("Ступни", "Кольчуга") }, api = {} }
			G.equippedLinks[7], G.equippedLinks[8] = "rhlegs", "rhfeet"
			G.GetCombatRatingBonus = function() return 3 end
			local ns = loadAll(G)
			ns.SetData[99911] = { name = "made-up", { n = 2, spell = 1, stats = { RANGED_HIT = 2 } } }
			ns.Invalidate()
			local st = ns.Advisor.State()
			T.near(st.snap.rangedGearHit, 2, 1e-12); T.near(st.model.rangedGearHit, 2, 1e-12)
			T.near(st.model.hit, 1, 1e-12); T.near(st.ctx.baseHit, 1, 1e-12)
			T.near(ns.Advisor.Evaluate("rhlegs", { kind = "equipped", slot = 7 }).delta, 0, 1e-12, "the worn set gives 0")
		end },
		-- The worn gear's attack power against a creature type (Player.Snapshot apVsTarget): every type's AP_VS_<TYPE> of the
		-- worn items and set bonuses at Model.AP_CREATURE_SHARE (the env's gloves +21 against beasts, a ring +15 against
		-- undead, Counterattack Lodestone 18537's +30 against mechanical units with its plain +30 AP, a made-up set's +10
		-- against demons); GetItemStats' ATTACK_POWER_VS_BEAST is AP_VS_BEAST (Items.API_MAP); each key's tooltip line
		{ "AP vs type: Snapshot sums every type's worn AP_VS at the share; GetItemStats maps to AP_VS_BEAST; the tooltip names the type", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.undeadring = { info = { 79, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо"), ln("Палец"),
				ln("Если на персонаже: +15 к силе атаки против нежити.") }, api = {} }
			G.items.lodestone = { info = { 18537, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Камень контратаки"), ln("Аксессуар"),
				ln("Если на персонаже: +30 к силе атаки. Бонус удваивается против механизмов.") }, api = { ITEM_MOD_ATTACK_POWER_SHORT = 30 } }
			G.items.dslegs = { info = { 80, "INVTYPE_LEGS", 4, 3 }, setID = 99912, lines = { ln("Поножи"), ln("Ноги", "Кольчуга") }, api = {} }
			G.items.dsfeet = { info = { 81, "INVTYPE_FEET", 4, 3 }, setID = 99912, lines = { ln("Сапоги"), ln("Ступни", "Кольчуга") }, api = {} }
			G.items.apiboots = { info = { 82, "INVTYPE_FEET", 4, 3 }, lines = { ln("Сапоги"), ln("Ступни", "Кольчуга") },
				api = { ITEM_MOD_ATTACK_POWER_VS_BEAST_SHORT = 12 } }
			G.equippedLinks[11], G.equippedLinks[13] = "undeadring", "lodestone"
			G.equippedLinks[7], G.equippedLinks[8] = "dslegs", "dsfeet"
			G.bags[0] = { "apiboots" }
			local ns = loadAll(G)
			ns.SetData[99912] = { name = "made-up", { n = 2, spell = 1, stats = { AP_VS_DEMON = 10 } } }
			ns.Invalidate()
			local lode = ns.Items.Get("lodestone")
			T.eq(lode.stats.AP, 30); T.eq(lode.stats.AP_VS_MECHANICAL, 30); T.eq(#lode.mismatch, 0, "GetItemStats' AP agrees")
			local boots = ns.Items.Get("apiboots")
			T.eq(boots.stats.AP_VS_BEAST, 12, "GetItemStats' ATTACK_POWER_VS_BEAST")
			local st = ns.Advisor.State()
			T.near(st.model.apVsTarget, (21 + 15 + 30 + 10) * ns.Model.AP_CREATURE_SHARE, 1e-12, "every type at the share")
			T.near(ns.Advisor.Evaluate("undeadring", { kind = "equipped", slot = 11 }).delta, 0, 1e-12, "the worn set gives 0")
			local texts = {}
			for i, l in ipairs(ns.Advisor.Explain("lodestone", { kind = "equipped", slot = 13 })) do texts[i] = l[1] end
			local text = table.concat(texts, "\n")
			T.truthy(text:find("HGA: «+30 к силе атаки против механизмов» учтено по доле таких существ 30% (только твои атаки: пету и ястребам не идёт; оценка)", 1, true), text)
			texts = {}
			for i, l in ipairs(ns.Advisor.Explain("gloves", { kind = "equipped", slot = 10 })) do texts[i] = l[1] end
			text = table.concat(texts, "\n")
			T.truthy(text:find("«+21 к силе атаки против животных» учтено по доле таких существ 30%", 1, true), text)
		end },
		-- Melee for the Survival branch alone (the user, 2026-11-17: the hunter avoids melee in every build but Survival):
		-- Player.Snapshot passes model.survival (the Survival branch weaves, Model weaveParts) with strictly more talent points
		-- in Survival than in Beast Mastery and than in Marksmanship (Player.SurvivalBranch); no setting is read, and the model
		-- point holds no meleeFrac and no weave
		{ "Snapshot: model.survival from strictly most SV points; no meleeFrac, no weave", function()
			local function state(ranks)
				local G = env()
				G.talentRanks = ranks
				return loadAll(G).Advisor.State()
			end
			-- SV 11 (Deflection 5, Entrapment 5, Improved Wing Clip 1) / BM 5 (Deadly Aspects) / MM 5 (Lethal Attacks)
			local st = state({ [104995] = 5, [104994] = 5, [104990] = 1, [104960] = 5, [105011] = 5 })
			T.eq(st.snap.points.SV, 11); T.eq(st.snap.survival, true); T.eq(st.model.survival, true, "SV most")
			T.eq(st.model.meleeFrac, nil, "no meleeFrac"); T.eq(st.model.weave, nil, "no weave")
			-- the env's BM 26 / MM 2
			local G = env(); local ns = loadAll(G)
			st = ns.Advisor.State()
			T.eq(st.snap.points.BM, 26); T.eq(st.snap.survival, false); T.eq(st.model.survival, false, "BM most")
			-- MM 10 (Lethal Attacks 5, Careful Aim 5) / SV 5 / BM 5
			st = state({ [105011] = 5, [105008] = 5, [104995] = 5, [104960] = 5 })
			T.eq(st.snap.points.MM, 10); T.eq(st.model.survival, false, "MM most")
		end },
		{ "melee: a tie SV = MM or SV = BM weaves not; one point more in Survival weaves", function()
			local function survival(ranks)
				local G = env()
				G.talentRanks = ranks
				return loadAll(G).Advisor.State().model.survival
			end
			T.eq(survival({ [104995] = 5, [104994] = 5, [105011] = 5, [105008] = 5 }), false, "SV 10 = MM 10")
			T.eq(survival({ [104995] = 5, [104994] = 5, [104960] = 5, [104967] = 5 }), false, "SV 10 = BM 10")
			T.eq(survival({ [104995] = 5, [104994] = 5, [104990] = 1, [105011] = 5, [105008] = 5 }), true, "SV 11 over MM 10")
		end },
		-- below level 10 no talent point exists: no branch has the most points
		{ "melee: below level 10 (no points) weaves not", function()
			local G = env()
			G.UnitLevel = function() return 8 end
			G.talentRanks = {}
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.snap.points.SV + st.snap.points.BM + st.snap.points.MM, 0)
			T.eq(st.snap.survival, false); T.eq(st.model.survival, false)
		end },
		{ "melee: the rule holds in raid mode too", function()
			local G = env()
			G.UnitLevel = function() return 60 end
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.mode, "raid"); T.eq(st.model.survival, false, "BM at 60")
			local G2 = env()
			G2.UnitLevel = function() return 60 end
			survivalTree(G2)
			local st2 = loadAll(G2).Advisor.State()
			T.eq(st2.model.mode, "raid"); T.eq(st2.model.survival, true, "the Survival branch at 60")
			T.truthy(st2.total > 0 and ns.Model.Parts(st2.model).melee > 0, "the weave at 60")
		end },
		-- /hga weights' melee line (raid-mode design 15.6): the Survival branch's weave with its cycle outside Rapid Fire,
		-- Raptor Strike every nCycles(6) cycles and the melee look's casts a minute averaged over Rapid Fire (Model.Weave);
		-- every other build "не в счёт"; /hga dump writes survival and the weave (Model.Weave of the model point). The Survival
		-- environment adds Rapid Killing 2/2 (Rapid Fire 15 s of every 180), Strider Kick and Expose Prey 2/2 (nodes 105005,
		-- 104981, 104985: Player.BRANCHES), where the casts a minute averaged over Rapid Fire and the ones of the cycle outside it
		-- print apart
		{ "/hga weights: the weave line with the cycle for Survival; \"не в счёт\" otherwise; /hga dump has survival and the weave", function()
			local function lines(setup)
				local G = env()
				if setup then setup(G) end
				local ns = loadAll(G)
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR("weights")
				G.SlashCmdList.HUNTERGEARADVISOR("dump")
				return table.concat(G.printed, "\n"), ns.db.dump, ns
			end
			local bm, bmDump = lines()
			T.truthy(bm:find("ближний бой: не в счёт — больше всего очков не в Выживании\n", 1, true), bm)
			T.eq(bmDump.survival, false); T.eq(bmDump.weave, nil)
			local sv, svDump, ns = lines(function(G)
				survivalTree(G)
				G.talentRanks[105005] = 2; G.talentRanks[104981] = 1; G.talentRanks[104985] = 2
			end)
			local wv = ns.Model.Weave(ns.Advisor.State().model)
			local b, r = wv.base, wv.average.rates
			local LINE = "ближний бой: плетение как в wowsims (SV Weave) — цикл %.2f с: выстрел и удар правой рукой, Raptor Strike раз в %.1f цикла, Strider Kick %.1f, Mongoose Bite %.1f, Wing Clip %.1f, Immolation Trap %.1f в минуту"
			local want = string.format(LINE, b.C, 1 / (b.rates.raptor * b.C), r.strider * 60, r.bite * 60, r.wingClip * 60, r.trap * 60)
			T.truthy(sv:find(want, 1, true), want .. " in " .. sv)
			local outside = string.format(LINE, b.C, 1 / (b.rates.raptor * b.C), b.rates.strider * 60, b.rates.bite * 60,
				b.rates.wingClip * 60, b.rates.trap * 60)
			T.truthy(outside ~= want, "the casts outside Rapid Fire print apart here: " .. outside)
			T.truthy(wv.rfUp > 0.08, "Rapid Killing 2/2: Rapid Fire 15 s of 180")
			T.truthy(r.strider > 0 and r.bite > 0 and r.wingClip > 0 and r.trap > 0, "every melee look's cast at 43")
			T.eq(svDump.survival, true); T.near(svDump.weave.base.C, b.C, 1e-12, "dump: the weave")
			-- the Survival branch without a bow, gun or crossbow
			local nb = lines(function(G) survivalTree(G); G.equippedLinks[18] = nil end)
			T.truthy(nb:find("ближний бой: плетение как в wowsims (SV Weave) — без лука, ружья или арбалета нет ни выстрелов, ни ближнего боя", 1, true), nb)
			-- unarmed: no Raptor Strike
			local un = lines(function(G) survivalTree(G); G.equippedLinks[16] = nil; G.equippedLinks[17] = nil end)
			T.truthy(un:find(": выстрел и удар правой рукой, без Raptor Strike (в правой руке нет оружия для него), Strider Kick", 1, true), un)
		end },
		-- Raptor Strike, Wing Clip and Mongoose Bite ranks 1-3 need a weapon of SpellEquippedItems subclass mask 173555 (Forever
		-- DB2 build 70888: rows 166357, 175525, 166400, 174762, 254988, 254990), which holds neither a fishing pole (subclass
		-- 20) nor a miscellaneous weapon (14); wowsims checks it before the cast (resolve_spell.go:281-283). Such a main hand
		-- swings at its own speed and DPS in the weave and takes no strike: Player.WeaponInputs gives unarmed for it
		{ "weapon inputs: a fishing pole or a miscellaneous weapon swings at its speed and DPS but takes no Raptor Strike, Wing Clip or Mongoose Bite", function()
			local G = env()
			survivalTree(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.pole = { info = { 6256, "INVTYPE_2HWEAPON", 2, 20 }, lines = { ln("Удочка"), ln("Двуручное", "Удочка"),
				ln("Урон: 2-4", "Скорость 3,00"), ln("(1,0 ед. урона в секунду)") }, api = {} }
			G.items.misc = { info = { 91, "INVTYPE_WEAPON", 2, 14 }, lines = { ln("Разное оружие"), ln("Одноручное", "Разное"),
				ln("Урон: 20-30", "Скорость 2,00"), ln("(12,5 ед. урона в секунду)") }, api = {} }
			G.equippedLinks[16], G.equippedLinks[17] = "pole", nil
			G.talentRanks[104985] = 2; G.talentRanks[104981] = 1 -- Expose Prey 2/2, Strider Kick (Player.BRANCHES)
			local ns = loadAll(G)
			local P, I = ns.Player, ns.Items
			local function inputs(link) return P.WeaponInputs({ [16] = I.Piece(I.Get(link), { kind = "new" }) }) end
			local pole, misc, sword = inputs("pole"), inputs("misc"), inputs("sword")
			T.eq(pole.unarmed, true, "a fishing pole takes no strike"); T.eq(pole.mhSpeed, 3.0); T.near(pole.mhDPS, 1.0, 1e-9)
			T.eq(misc.unarmed, true, "a miscellaneous weapon takes no strike"); T.eq(misc.mhSpeed, 2.0)
			T.eq(sword.unarmed, false)
			-- every weapon subclass against the strikes' EquippedItemSubclass 173555 (SpellEquippedItems 166357, 175525, 166400,
			-- 174762, 254988, 254990): a strike weapon exactly where its bit is set, 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 17 (my
			-- arithmetic)
			local swordRec, inMask = I.Get("sword"), {}
			for sub = 0, 20 do
				local bit = math.floor(173555 / 2 ^ sub) % 2 == 1
				local piece = setmetatable({ subclassID = sub, where = { kind = "new" } }, { __index = swordRec })
				T.eq(P.WeaponInputs({ [16] = piece }).unarmed, not bit, "subclass " .. sub)
				if bit then inMask[#inMask + 1] = sub end
			end
			T.eq(table.concat(inMask, ","), "0,1,4,5,6,7,8,10,13,15,17")
			local st = ns.Advisor.State()
			T.eq(st.model.survival, true); T.eq(st.model.unarmed, true); T.eq(st.model.mhSpeed, 3.0)
			T.eq(st.model.tal.exposePrey, 2); T.eq(st.model.tal.striderKick, 1)
			local r = ns.Model.Weave(st.model).average.rates
			T.eq(r.raptor, 0, "no Raptor Strike"); T.eq(r.wingClip, 0, "no Wing Clip"); T.eq(r.bite, 0, "no Mongoose Bite at 43")
			T.truthy(r.mhWhite > 0 and r.strider > 0, "the pole's white swings and Strider Kick, which needs no weapon")
			T.eq(#G.reportedErrors, 0)
		end },
		-- talents applied after load (TRAIT_CONFIG_UPDATED, Game/Commands.lua): the next snapshot reads the branch again
		{ "mode switch: applying a Survival tree (TRAIT_CONFIG_UPDATED) turns the weave on", function()
			local G = env(); local ns = loadAll(G)
			T.eq(ns.Advisor.State().model.survival, false, "BM")
			local bm = SURVIVAL_TREE_NODES
			survivalTree(G)
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			local st = ns.Advisor.State()
			T.eq(st.snap.survival, true); T.eq(st.model.survival, true, "the Survival tree applied")
			for node in pairs(bm) do G.talentRanks[node] = nil end
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			T.eq(ns.Advisor.State().model.survival, false, "back to BM")
		end },
		-- Beastslaying is flat damage on every weapon strike and shot of the hunter (Model.Parts flat, the wowsims rule), so a
		-- bag sword's Beastslaying raises the shots outside the Survival branch too; ctx.weaponGain runs it with the sword's
		-- set (Player.WeaponInputs beastSlaying). With no melee the flat reaches the shots alone, which no melee weapon
		-- changes: the sword's Beastslaying is 6 x W.BEAST_SLAYING of the worn point
		{ "Beastslaying on a bag sword raises the shots outside the Survival branch, inside the sword's weapon run", function()
			-- one bag sword at a time (two in the bags would go into one pair): the same sword with and without Beastslaying
			local function delta(setup, extra)
				local G = env()
				if setup then setup(G) end
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
				local lines = { ln("Меч"), ln("Одноручное", "Меч"), ln("Урон: 40-75", "Скорость 2,60"), ln("(22,1 ед. урона в секунду)"),
					ln("+12 к ловкости") }
				if extra then lines[#lines + 1] = ln(extra) end
				G.items.bagsword2 = { info = { 73, "INVTYPE_WEAPON", 2, 7 }, lines = lines, api = {} }
				G.bags[0] = { "bagsword2" }
				local ns = loadAll(G)
				local r = ns.Advisor.Evaluate("bagsword2", { kind = "bag", bag = 0, slot = 1 })
				return ns.Advisor.State(), r.delta, r.slot
			end
			local function deltas(setup)
				local st, a, slotA = delta(setup, "Чары: +6 к убийству животных")
				local _, b, slotB = delta(setup)
				T.eq(slotA, slotB, "the same hand")
				return st, a - b
			end
			local st, diff = deltas()
			T.eq(st.model.survival, false, "BM: no melee")
			T.truthy(st.W.BEAST_SLAYING > 0, "the shots take it: " .. st.W.BEAST_SLAYING)
			T.near(diff, 6 * st.W.BEAST_SLAYING, 1e-9, "BM: the shots' flat damage, whichever melee weapon")
			local st2, diff2 = deltas(survivalTree)
			T.eq(st2.model.survival, true)
			T.truthy(diff2 > 0, "the Survival branch: the shots and the melee swings: " .. diff2)
		end },
		{ "loot roll frame and loot window get the checkmark", function()
			local G = env()
			local function tex()
				local t = { shown = false }
				function t:SetTexture(f) self.file = f end function t:SetVertexColor(r, g, bl) self.color = { r, g, bl } end
					function t:SetSize() end function t:SetPoint() end
				function t:SetShown(v) self.shown = v end
				return t
			end
			local function button() local b = { Icon = {} }; function b:CreateTexture() return tex() end; return b end
			local hooks = {}
			local function rollFrame(rollID, shown)
				local f = { rollID = rollID, IconFrame = button() }
				function f:IsShown() return shown end
				function f:HookScript(_, fn) hooks[#hooks + 1] = fn end
				return f
			end
			G.NUM_GROUP_LOOT_FRAMES = 4
			G.GroupLootFrame1 = rollFrame(101, true)  -- better bow
			G.GroupLootFrame2 = rollFrame(102, true)  -- mace: cannot use
			G.GroupLootFrame3 = rollFrame(nil, false)
			G.GroupLootFrame4 = rollFrame(nil, false)
			G.GetLootRollItemLink = function(id) return ({ [101] = "newbow", [102] = "mace" })[id] end
			local rows = {}
			for slot, link in ipairs({ "newhelm", "mace" }) do
				local row = { Item = button(), slot = slot }
				function row:GetSlotIndex() return self.slot end
				rows[#rows + 1] = row
			end
			G.LootFrame = { ScrollBox = {} }
			function G.LootFrame:IsShown() return true end
			function G.LootFrame.ScrollBox:ForEachFrame(fn) for _, r in ipairs(rows) do fn(r) end end
			G.GetLootSlotLink = function(slot) return ({ "newhelm", "mace" })[slot] end
			local ns = loadAll(G)
			G.fire("START_LOOT_ROLL", 101)
			T.truthy(G.GroupLootFrame1.IconFrame.hgaCheck and G.GroupLootFrame1.IconFrame.hgaCheck.shown, "better bow on the roll frame")
			T.truthy(G.GroupLootFrame1.IconFrame.hgaCheck.file:match("^Interface.AddOns.HunterGearAdvisor.Media.UpgradeArrow$"), "roll mark is the double arrow")
			T.near(G.GroupLootFrame1.IconFrame.hgaCheck.color[1], 94 / 255, 1e-9, "Zygor green")
			T.truthy(not (G.GroupLootFrame2.IconFrame.hgaCheck and G.GroupLootFrame2.IconFrame.hgaCheck.shown), "mace not marked")
			G.fire("LOOT_OPENED")
			T.truthy(rows[1].Item.hgaCheck and rows[1].Item.hgaCheck.shown, "better helm in the loot window")
			T.truthy(not (rows[2].Item.hgaCheck and rows[2].Item.hgaCheck.shown), "mace not marked in the loot window")
			T.truthy(#hooks >= 1, "roll frames hooked on show")
		end },
		{ "swap banner: shows the plan, opens the list, Equip puts the bag item on", function()
			local G = env(); local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			T.truthy(banner and banner.shown, "banner shown")
			T.truthy(banner.title.text:match("^Можно надеть улучшени"), tostring(banner.title.text))
			local plan = ns.Advisor.Plan()
			local ranged
			for _, r in ipairs(plan.rows) do
				if r.slot == 18 then ranged = r end
				T.truthy(not (r.new and r.new.link == "newhelm"), "level 45 helm is not suggested at level 43")
				T.truthy(not (r.new and r.new.link == "mace"), "unusable mace is not suggested")
			end
			T.truthy(ranged and ranged.new.link == "newbow" and ranged.old.link == "bow", "new bow instead of the old one")
			T.truthy(plan.delta > 0, "the whole plan is a gain")
			T.eq(banner.panel.shown, false, "list closed until clicked")
			banner:Click()
			T.eq(banner.panel.shown, true, "click opens the list")
			-- the plan's DPS and each row's: the gain times the DPS of one RAP (A.Plan), as the list says them (Swap.lua
			-- fillPanel and fillRow through A.GainLines)
			local st = ns.Advisor.State()
			T.eq(st.unit, "RAP"); T.eq(plan.verdict, "better")
			T.eq(plan.dps, plan.delta * st.unitDps, "the plan's DPS")
			T.eq(banner.panel.total.text, string.format("всё вместе: усиление +%.1f (~ +%.1f DPS)", plan.delta, plan.delta * st.unitDps))
			for i, row in ipairs(plan.rows) do
				local rf = banner.panel.rows[i]
				T.eq(rf.data, row, "row " .. i .. " of this plan"); T.eq(row.gain.verdict, "better", "row " .. i)
				T.eq(row.gain.dps, row.gain.delta * st.unitDps, "row " .. i .. ": the DPS")
				T.eq(rf.gain.text, string.format("усиление +%.1f (~ +%.1f DPS)", row.gain.delta, row.gain.delta * st.unitDps), "row " .. i)
			end
			local rowFrame
			for _, rf in ipairs(banner.panel.rows) do if rf.shown and rf.data.slot == 18 then rowFrame = rf end end
			T.truthy(rowFrame, "row for the ranged slot")
			T.eq(rowFrame.name.text, "newbow"); T.eq(rowFrame.slot.text, "Оружие дальнего боя")
			T.eq(rowFrame.old.text, "вместо: bow")
			T.truthy(rowFrame.gain.text:match("^усиление %+"), tostring(rowFrame.gain.text))
			rowFrame.equip:Click()
			T.eq(table.concat(G.equipCalls, " | "), "PickupContainerItem 0 1 | EquipCursorItem 18")
		end },
		{ "swap banner: a moved item, combat or a busy cursor are said in chat, nothing is equipped", function()
			local G = env(); local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			banner:Click()
			local rowFrame
			for _, rf in ipairs(banner.panel.rows) do if rf.shown and rf.data.slot == 18 then rowFrame = rf end end
			G.cursor = "something"
			rowFrame.equip:Click()
			T.truthy(G.printed[#G.printed]:match("на курсоре"), G.printed[#G.printed])
			G.cursor = nil
			G.inCombat = true
			rowFrame.equip:Click()
			T.truthy(G.printed[#G.printed]:match("в бою"), G.printed[#G.printed])
			G.inCombat = false
			G.bags[0][1] = "mace" -- the bag slot the list names holds the mace, not the bow
			rowFrame.equip:Click()
			T.truthy(G.printed[#G.printed]:match("сдвинулась"), G.printed[#G.printed])
			T.eq(#G.equipCalls, 0, "nothing picked up or equipped")
		end },
		{ "swap banner: x hides it until the plan changes, combat hides it, /hga swap", function()
			local G = env(); local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			banner.close:Click()
			T.eq(banner.shown, false, "x hides")
			ns.Invalidate()
			T.eq(banner.shown, false, "stays hidden while the plan is the same")
			G.SlashCmdList.HUNTERGEARADVISOR("swap")
			T.eq(banner.shown, true, "/hga swap shows it again"); T.eq(banner.panel.shown, true, "with the list")
			G.fire("PLAYER_REGEN_DISABLED")
			T.eq(banner.shown, false, "hidden in combat")
			G.inCombat = true; ns.Invalidate()
			T.eq(banner.shown, false, "not shown while in combat")
			G.inCombat = false; G.fire("PLAYER_REGEN_ENABLED")
			T.eq(banner.shown, true, "back after combat")
			G.bags[0] = { "mace", "newhelm" } -- nothing wearable and better
			ns.Invalidate()
			T.eq(banner.shown, false, "nothing to suggest -> no banner")
		end },
		{ "the banner's × survives a bag sort and a manual equip, a new suggestion brings it back", function()
			local G = env(); local ns = loadAll(G)
			local W = { r = 1, g = 1, b = 1 }
			G.items.goodhelm = { info = { 30, "INVTYPE_HEAD", 4, 3 }, lines = { { leftText = "Хороший шлем", leftColor = W },
				{ leftText = "Голова", rightText = "Кольчуга", leftColor = W, rightColor = W }, { leftText = "+40 к ловкости", leftColor = W } },
				api = { ITEM_MOD_AGILITY_SHORT = 40 } }
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			T.eq(banner.title.text, "Можно надеть улучшения: 2")
			banner.close:Click()
			T.eq(banner.shown, false)
			G.bags[0] = { "mace", "staff", "newhelm", "bagsword", "newbow" } -- sorted: same items, other slots
			ns.Invalidate()
			T.eq(banner.shown, false, "sorting the bags keeps it hidden")
			G.equippedLinks[18] = "newbow"; G.bags[0][5] = "bow" -- one suggestion put on by hand
			ns.Invalidate()
			T.eq(banner.shown, false, "equipping one suggestion by hand keeps it hidden")
			G.bags[0][6] = "goodhelm"
			ns.Invalidate()
			T.eq(banner.shown, true, "a new suggestion shows it again")
		end },
		-- the banner is always on (Swap.Refresh builds the plan whenever out of combat; the user, 2026-11-17): a swapBanner
		-- left in old saved settings is never read (the table goes at load); the × hides it until the plan changes
		{ "banner: the plan is built whenever out of combat; the × hides it until the plan changes", function()
			local G = env()
			G.HunterGearAdvisorDB = { settingsVersion = 3, settings = { swapBanner = false } }
			local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			T.eq(banner.shown, true, "shown out of combat, whatever the saved key")
			banner.close:Click()
			ns.Invalidate()
			T.eq(banner.shown, false, "the × hides it while the plan is the same")
			G.bags[0][#G.bags[0] + 1] = "betterbullets" -- no gear: the plan stays the same
			ns.Invalidate()
			T.eq(banner.shown, false, "still the same plan")
		end },
		-- /hga swap clears the × (Swap.Show): the banner, always on, stays when its list closes
		{ "/hga swap after the × shows the banner and its list; the list stays open after a refresh; closing it leaves the banner", function()
			local G = env(); local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			banner.close:Click()
			ns.Invalidate()
			T.eq(banner.shown, false, "hidden by the ×")
			G.SlashCmdList.HUNTERGEARADVISOR("swap")
			T.eq(banner.shown, true); T.eq(banner.panel.shown, true, "list on demand")
			ns.Invalidate() -- what an Equip click causes
			T.eq(banner.shown, true); T.eq(banner.panel.shown, true, "stays open after a refresh")
			banner:Click()
			T.eq(banner.panel.shown, false); T.eq(banner.shown, true, "the banner stays: /hga swap cleared the ×")
		end },
		{ "a worn weapon moved to the other hand: its row says so and shares the main hand's gain", function()
			local G = env()
			local W = { r = 1, g = 1, b = 1 }
			G.items.bigmh = { info = { 31, "INVTYPE_WEAPONMAINHAND", 2, 7 }, lines = { { leftText = "Большой меч", leftColor = W },
				{ leftText = "Правая рука", rightText = "Меч", leftColor = W, rightColor = W },
				{ leftText = "Урон: 65-97", rightText = "Скорость 2,70", leftColor = W, rightColor = W },
				{ leftText = "(30,0 ед. урона в секунду)", leftColor = W }, { leftText = "+20 к ловкости", leftColor = W } },
				api = { ITEM_MOD_AGILITY_SHORT = 20 } }
			G.bags[0] = { "bigmh" }
			local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			T.eq(banner.title.text, "Можно надеть улучшение", "one item comes from the bags")
			banner:Click()
			local mhRow, ohRow
			for _, rf in ipairs(banner.panel.rows) do
				if rf.shown and rf.data.slot == 16 then mhRow = rf end
				if rf.shown and rf.data.slot == 17 then ohRow = rf end
			end
			T.eq(mhRow.name.text, "bigmh"); T.truthy(mhRow.gain.text:match("^усиление %+"), tostring(mhRow.gain.text))
			T.eq(ohRow.name.text, "sword")
			T.truthy(ohRow.hint.text:match("переложить из слота «Правая рука»"), tostring(ohRow.hint.text))
			T.truthy(ohRow.hint.text:match("одна замена вместе с другой рукой"), tostring(ohRow.hint.text))
			T.eq(ohRow.gain.text, "", "no second number")
			ohRow.equip:Click()
			T.eq(table.concat(G.equipCalls, " | "), "PickupInventoryItem 16 | EquipCursorItem 17")
		end },
		{ "a worn 2H beaten by an off-hand item only: the main-hand row says it stays empty", function()
			local G = env()
			local W = { r = 1, g = 1, b = 1 }
			G.items.frill = { info = { 32, "INVTYPE_HOLDABLE", 4, 0 }, lines = { { leftText = "Безделушка", leftColor = W },
				{ leftText = "Левая рука", leftColor = W }, { leftText = "+40 к ловкости", leftColor = W } },
				api = { ITEM_MOD_AGILITY_SHORT = 40 } }
			G.equippedLinks[16], G.equippedLinks[17] = "staff", nil
			G.bags[0] = { "frill" }
			local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			banner:Click()
			local mhRow, ohRow
			for _, rf in ipairs(banner.panel.rows) do
				if rf.shown and rf.data.slot == 16 then mhRow = rf end
				if rf.shown and rf.data.slot == 17 then ohRow = rf end
			end
			T.truthy(mhRow and mhRow.old.text:match("правая останется пустой"), mhRow and tostring(mhRow.old.text))
			T.eq(mhRow.equip.shown, false, "nothing to put on in the main hand")
			T.eq(ohRow.name.text, "frill"); T.truthy(ohRow.gain.text:match("^усиление %+"), tostring(ohRow.gain.text))
		end },
		-- A plan that only takes an item off (A.Plan row.takeOff): the env's Survival tree weaves, and behind the 2.6 s sword,
		-- whose swing the walk sets, the 1.8 s off-hand sword swings in no visit while it gives every main-hand white swing
		-- 19% more miss (Core/Model.lua weaveParts, wowsims' rule), so taking it off is the plan, the only gain with nothing in
		-- the bags. Taking off is part of what to wear: the banner shows, its row says to take the item off into a bag and has a
		-- «Снять» button, which puts the item into the first bag of family 0 with a free slot (the backpack, else a bag; a quiver
		-- takes none); no free slot is said in chat; /hga swap lists the row
		{ "swap banner: a plan that only takes the off hand off shows; its row says «снять в сумку» with a «Снять» button that puts the item in a bag", function()
			local G = env()
			survivalTree(G)
			G.bags[0] = {}
			local ns = loadAll(G)
			ns.Invalidate()
			local plan = ns.Advisor.Plan()
			T.eq(#plan.rows, 1, "one row"); T.eq(plan.fromBags, 0); T.eq(plan.takeOffs, 1)
			local row = plan.rows[1]
			T.eq(row.slot, 17); T.eq(row.new, nil); T.eq(row.old.link, "offsword"); T.eq(row.takeOff, true)
			T.eq(row.key, "17=-offsword"); T.eq(row.gain.verdict, "better"); T.eq(plan.verdict, "better")
			local banner = G.HunterGearAdvisorSwapBanner
			T.eq(banner.shown, true, "the banner shows a plan that only takes off")
			T.eq(banner.title.text, "Можно снять вещь с выгодой")
			banner:Click()
			local rf = banner.panel.rows[1]
			T.eq(rf.data, row); T.eq(rf.slot.text, "Левая рука"); T.eq(rf.name.text, "offsword")
			T.eq(rf.old.text, "снять в сумку — рука останется пустой")
			T.eq(rf.gain.text, string.format("усиление +%.1f (~ +%.1f DPS)", row.gain.delta, row.gain.dps))
			T.eq(rf.equip.shown, true); T.eq(rf.equip.text, "Снять")
			rf.equip:Click()
			T.eq(table.concat(G.equipCalls, " | "), "PickupInventoryItem 17 | PutItemInBackpack")
			-- the backpack full, a quiver with room: the first bag of family 0 with room
			G.equipCalls = {}
			G.freeSlots = { [0] = 0, [1] = 3, [2] = 2 }; G.bagFamily = { [1] = 1 }
			rf.equip:Click()
			T.eq(table.concat(G.equipCalls, " | "), "PickupInventoryItem 17 | PutItemInBag 21", "bag 2, past the quiver in bag 1")
			-- no room: said in chat, nothing picked up
			G.equipCalls = {}
			G.freeSlots = {}
			rf.equip:Click()
			T.truthy(G.printed[#G.printed]:find("в сумках нет места", 1, true), G.printed[#G.printed])
			T.eq(#G.equipCalls, 0)
			-- the worn item changed since the plan: said in chat, nothing picked up
			G.freeSlots = { [0] = 4 }
			G.equippedLinks[17] = "bagsword"
			rf.equip:Click()
			T.truthy(G.printed[#G.printed]:find("надетые вещи изменились", 1, true), G.printed[#G.printed])
			T.eq(#G.equipCalls, 0)
			G.equippedLinks[17] = "offsword"
			-- combat, an item on the cursor and a locked slot: said in chat, nothing picked up; an item the game does not give
			-- to the cursor: said in chat, nothing put away
			local function refused(text, set, unset, calls)
				G.equipCalls = {}
				set(); rf.equip:Click(); unset()
				T.truthy(G.printed[#G.printed]:find(text, 1, true), text .. ": " .. G.printed[#G.printed])
				T.eq(table.concat(G.equipCalls, " | "), calls, text)
			end
			refused("в бою вещи не снять", function() G.inCombat = true end, function() G.inCombat = false end, "")
			refused("на курсоре уже есть предмет", function() G.cursor = "something" end, function() G.cursor = nil end, "")
			local unlocked = G.IsInventoryItemLocked
			refused("сейчас занят сменой вещи", function() G.IsInventoryItemLocked = function(slot) return slot == 17 end end,
				function() G.IsInventoryItemLocked = unlocked end, "")
			local pickup = G.PickupInventoryItem
			refused("не удалось взять Заточка", function()
				G.PickupInventoryItem = function(slot) table.insert(G.equipCalls, "PickupInventoryItem " .. slot) end
			end, function() G.PickupInventoryItem = pickup end, "PickupInventoryItem 17")
			-- a row without its item is no row the panel makes: an error, not a quiet return
			T.truthy(not pcall(ns.Swap.UnequipRow, { slot = 17, takeOff = true }), "a take-off row without its item")
			T.truthy(not pcall(ns.Swap.EquipRow, { slot = 16 }), "an equip row without its item")
			G.equipCalls = {}
			ns.Invalidate()
			-- the × hides it, /hga swap lists it again
			banner.close:Click()
			T.eq(banner.shown, false)
			G.SlashCmdList.HUNTERGEARADVISOR("swap")
			T.eq(banner.shown, true); T.eq(banner.panel.shown, true)
			T.eq(banner.panel.rows[1].equip.text, "Снять")
			T.eq(#G.reportedErrors, 0)
			-- a two-hander from the bags in place of the worn pair (the BM build): the game takes the off hand off itself, so
			-- that row takes nothing off by itself: no button, its text says the two-hander takes the hand
			local G2 = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G2.items.bigstaff = { info = { 33, "INVTYPE_2HWEAPON", 2, 10 }, lines = { ln("Большой посох"), ln("Двуручное", "Посох"),
				ln("Урон: 77-115", "Скорость 3,20"), ln("(30,0 ед. урона в секунду)"), ln("+60 к ловкости") }, api = {} }
			G2.bags[0] = { "bigstaff" }
			local ns2 = loadAll(G2)
			ns2.Invalidate()
			local plan2 = ns2.Advisor.Plan()
			T.eq(plan2.takeOffs, 0); T.eq(plan2.fromBags, 1)
			local oh
			for _, r in ipairs(plan2.rows) do if r.slot == 17 then oh = r end end
			T.truthy(oh and oh.new == nil and oh.takeOff == false, "the off hand the two-hander empties")
			local banner2 = G2.HunterGearAdvisorSwapBanner
			T.eq(banner2.title.text, "Можно надеть улучшение")
			banner2:Click()
			for _, rf2 in ipairs(banner2.panel.rows) do
				if rf2.shown and rf2.data.slot == 17 then
					T.eq(rf2.old.text, "снимется само: эту руку займёт двуручное"); T.eq(rf2.equip.shown, false, "nothing to do in that row")
				end
			end
		end },
		-- A worn item the plan moves to another slot leaves its slot by that row (A.Plan row.movesTo): the row that puts it on
		-- picks it up there (Swap.EquipRow, as EquipmentManager_EquipInventoryItem), so the slot it leaves is no take-off row
		-- (raid-mode design 18.2). The env's Survival tree with nothing in the bags: (1) an empty main hand and the off-hand
		-- sword (18.1's C4): the weave swings the sword in the main hand and the off hand frees itself; (2) a weak sword in
		-- the main hand: the off-hand sword goes to the main hand, and what lands in the off hand the next plan shows
		{ "swap banner: a worn weapon the plan moves to the other hand leaves its slot by that row: no take-off row, no «Снять»", function()
			local function moved(mh, oldText)
				local G = env()
				survivalTree(G)
				for k in pairs(G.bags) do G.bags[k] = {} end
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
				G.items.weakmh = { info = { 99601, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Слабый меч"), ln("Одноручное", "Меч"),
					ln("Урон: 1-2", "Скорость 2,60"), ln("(0,6 ед. урона в секунду)") }, api = {} }
				G.equippedLinks[16] = mh
				local ns = loadAll(G)
				ns.Invalidate()
				local plan = ns.Advisor.Plan()
				local label = "main hand " .. tostring(mh)
				T.eq(#plan.rows, 2, label); T.eq(plan.fromBags, 0, label); T.eq(plan.takeOffs, 0, label)
				local mhRow, ohRow = plan.rows[1], plan.rows[2]
				T.eq(mhRow.slot, 16); T.eq(mhRow.new.link, "offsword"); T.eq(mhRow.new.where.kind, "equipped"); T.eq(mhRow.new.where.slot, 17)
				T.eq(ohRow.slot, 17); T.eq(ohRow.new, nil); T.eq(ohRow.old.link, "offsword")
				T.eq(ohRow.takeOff, false, label .. ": the move empties the off hand"); T.eq(ohRow.movesTo, 16)
				T.eq(ohRow.moveDisplaces, mh ~= nil, label)
				local banner = G.HunterGearAdvisorSwapBanner
				T.eq(banner.title.text, "Можно переложить оружие", label)
				banner:Click()
				local mhFrame, ohFrame
				for _, rf in ipairs(banner.panel.rows) do
					if rf.shown and rf.data.slot == 16 then mhFrame = rf end
					if rf.shown and rf.data.slot == 17 then ohFrame = rf end
				end
				T.eq(ohFrame.name.text, "offsword"); T.eq(ohFrame.old.text, oldText, label)
				T.eq(ohFrame.equip.shown, false, label .. ": nothing to click in the off hand")
				T.eq(ohFrame.hint.text, "одна замена вместе с другой рукой — прирост в её строке")
				T.eq(mhFrame.equip.text, "Надеть")
				mhFrame.equip:Click()
				T.eq(table.concat(G.equipCalls, " | "), "PickupInventoryItem 17 | EquipCursorItem 16", label)
				T.eq(#G.reportedErrors, 0)
			end
			moved(nil, "освободится само: вещь перейдёт в слот «Правая рука»")
			moved("weakmh", "перейдёт в слот «Правая рука»; что окажется здесь, покажет обновлённый список")
		end },
		-- A proc spell's melee and ranged tables are the main hand's entry of the weapons the hunter holds (wowsims
		-- sim/core/target.go:606-615 Hand, weapon_skill.go:85-94 UpdateAttackTableWeapons): a set's procs roll at its own main
		-- hand's skill (ctx.procOutcomeFor, Advisor A.State; raid-mode design 18.7). The Survival tree with a bag dagger of a
		-- physical chance-on-hit proc (100 - 140, unlinked: the melee table by its school; a measured 1.5 the test gives it)
		-- on the daggers line at 195 of 215 (-20): in the main hand its proc rolls at the dagger's skill, more miss, more dodge
		-- and less crit than the worn sword's 215 (Model.ProcOutcomes at -20)
		{ "procs: a set's procs roll at its own main hand's skill (the dagger at 195 of 215), not the worn one's", function()
			local G = env()
			survivalTree(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.procdagger = { info = { 99540, "INVTYPE_WEAPON", 2, 15 }, lines = { ln("Кинжал с эффектом"), ln("Одноручное", "Кинжал"),
				ln("Урон: 25-40", "Скорость 1,80"), ln("(18,0 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 100 - 140 ед. урона.") }, api = {} }
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 173 then return { rank = 195, maxRank = 215, modifier = 0 } end
				return base(id)
			end
			G.bags[0] = { "procdagger" }
			G.measuredPPM = { [99540] = 1.5 }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local Sc, ctx, W = ns.Score, st.ctx, st.W
			local dagger = ns.Items.Piece(ns.Items.Get("procdagger"), { kind = "bag", bag = 0, slot = 1 })
			local set = Sc.CopySet(st.snap.equipped); set[16] = dagger
			T.eq((Sc.MeleeSkills(set, ctx)), -20, "the dagger's line at 195 of 215")
			T.eq(st.model.mhSkill, 0, "the worn sword at 215")
			local bare = setmetatable({ procs = {} }, { __index = dagger })
			local plain = Sc.CopySet(set); plain[16] = bare
			local part = Sc.SetValue(set, W, ctx) - Sc.SetValue(plain, W, ctx)
			local hits = Sc.LandedHitsOf(set, ctx)
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			p.mhSkill = -20
			local at20 = Sc.ProcValue(dagger, "mh", W, hits, { procOutcome = ns.Model.ProcOutcomes(p) })
			local worn = Sc.ProcValue(dagger, "mh", W, hits, { procOutcome = ctx.procOutcome })
			T.truthy(at20 > 0 and at20 < worn - 1e-9, "the dagger's skill: more miss and dodge, less crit")
			T.near(part, at20, 1e-9, "the set's proc at its own main hand's skill")
			T.eq(ctx.procOutcomeFor(0), ctx.procOutcome, "the worn main hand's skill: the worn outcome")
			T.eq(ctx.procOutcomeFor(-20), ctx.procOutcomeFor(-20), "one run a skill")
			T.eq(#G.reportedErrors, 0)
		end },
		-- The base spell hit and the trap's spell hit cap (Advisor A.State; raid-mode design 18.8): the live spell hit
		-- (GetSpellHitModifier) less the worn items' and set bonuses' SPELL_HIT (Player.Snapshot gearSpellHit), and
		-- Model.TrapHitCap of the model point's mob level difference and Survival Tactics: 17% against the +3 boss
		{ "spell hit: ctx.baseSpellHit is the live spell hit less the worn set bonus's; the trap's cap 17% at 60", function()
			local G = env()
			raidLevel(G)
			survivalTree(G)
			G.GetSpellHitModifier = function() return 3 end
			local Wc = { r = 1, g = 1, b = 1 }
			G.items.shbelt = { info = { 82, "INVTYPE_WAIST", 4, 2 }, setID = 99912, lines = { { leftText = "Пояс", leftColor = Wc },
				{ leftText = "Пояс", rightText = "Кожа", leftColor = Wc, rightColor = Wc } }, api = {} }
			G.equippedLinks[6] = "shbelt"
			local ns = loadAll(G)
			ns.SetData[99912] = { name = "made-up", { n = 1, spell = 1, stats = { SPELL_HIT = 1 } } }
			ns.Invalidate()
			local st = ns.Advisor.State()
			T.truthy(st, "state: " .. tostring(ns.Advisor.notReadyReason) .. " " .. table.concat(G.reportedErrors, " | "))
			T.eq(st.model.spellHit, 3); T.eq(st.snap.gearSpellHit, 1, "the worn set bonus's")
			T.eq(st.ctx.baseSpellHit, 2); T.eq(st.ctx.spellHitCap, 17)
			for slot, piece in pairs(st.snap.equipped) do
				T.eq(ns.Advisor.Evaluate(piece.link, { kind = "equipped", slot = slot }).delta, 0, "worn " .. piece.link)
			end
			T.truthy(st.W.SPELL_HIT > 0 and st.W.SPELL_CRIT > 0, "the trap in the weave at 60")
			-- /hga weights names both, the spell hit up to the trap's cap (raid-mode design 25.7)
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local wl
			for _, l in ipairs(G.printed) do if l:find("урон (", 1, true) then wl = l end end
			local want = string.format("мастерство 1%% %.2f, меткость заклинаний 1%% %.2f (до капа ловушки 17.0%%), крит заклинаний 1%% %.2f, скорость атаки 1%%",
				st.W.EXPERTISE, st.W.SPELL_HIT, st.W.SPELL_CRIT)
			T.truthy(wl and wl:find(want, 1, true), tostring(wl))
			T.eq(#G.reportedErrors, 0)
		end },
		-- GetItemStats' melee weapon skill keys (Items.API_MAP; the client's ITEM_MOD_<LINE>_SHORT, GlobalStrings 58882-58908)
		-- map to Score.MELEE_SKILL's stats: a stat the tooltip has no line for is taken from the API and noted, one the tooltip
		-- states is checked against it
		{ "GetItemStats: the melee weapon skill keys map to Score.MELEE_SKILL's stats", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local keys = { TWOHANDED_AXES = "SKILL_2H_AXES", TWOHANDED_MACES = "SKILL_2H_MACES", TWOHANDED_SWORDS = "SKILL_2H_SWORDS",
				AXES = "SKILL_AXES", DAGGERS = "SKILL_DAGGERS", FIST_WEAPONS = "SKILL_FIST", MACES = "SKILL_MACES",
				POLEARMS = "SKILL_POLEARMS", STAVES = "SKILL_STAVES", SWORDS = "SKILL_SWORDS" }
			local id = 99600
			for short in pairs(keys) do
				id = id + 1
				G.items["ring" .. short] = { info = { id, "INVTYPE_FINGER", 4, 0 }, lines = { { leftText = "Кольцо", leftColor = Wc },
					{ leftText = "Палец", leftColor = Wc } }, api = { ["ITEM_MOD_" .. short .. "_SHORT"] = 4 } }
			end
			G.items.swordring = { info = { 99699, "INVTYPE_FINGER", 4, 0 }, lines = { { leftText = "Кольцо", leftColor = Wc },
				{ leftText = "Палец", leftColor = Wc }, { leftText = "Если на персонаже: повышение навыка владения мечом на 5.", leftColor = Wc } },
				api = { ITEM_MOD_SWORDS_SHORT = 4 } }
			local ns = loadAll(G)
			local melee = {}
			for _, stat in pairs(ns.Score.MELEE_SKILL) do melee[stat] = true end
			for short, stat in pairs(keys) do
				T.eq(ns.Items.API_MAP[short], stat, short); T.truthy(melee[stat], stat .. " is a melee skill stat")
				local rec = ns.Items.Get("ring" .. short)
				T.eq(rec.stats[stat], 4, short .. ": the API's value")
				T.eq(rec.mismatch[1], stat .. ": api 4, tooltip none", short)
			end
			local sw = ns.Items.Get("swordring")
			T.eq(sw.stats.SKILL_SWORDS, 5, "the tooltip's"); T.truthy(sw.mismatch[1]:find("SKILL_SWORDS: api 4, tooltip 5", 1, true), sw.mismatch[1])
		end },
		{ "one failing Invalidate listener does not skip the others, and its error is reported", function()
			local G = env(); local ns = loadAll(G)
			local ran = false
			ns.OnInvalidate(function() error("boom") end)
			ns.OnInvalidate(function() ran = true end)
			ns.Invalidate()
			T.eq(ran, true, "the later listener ran")
			local seen = false
			for _, e in ipairs(G.reportedErrors) do if tostring(e):match("boom") then seen = true end end
			T.truthy(seen, "error went to the error handler")
		end },
		{ "quest log coin reads the count by the raw choice index (a currency choice first)", function()
			local G = env(); local ns = loadAll(G)
			local function button(i)
				local b = { type = "choice", objectType = "item", id = i, questID = 99 }
				function b:GetID() return self.id end
				function b:IsShown() return true end
				function b:CreateTexture()
					local t = { shown = false }
					function t:SetTexture(f) self.file = f end function t:SetVertexColor() end
					function t:SetSize() end function t:SetPoint() end
					function t:SetColorTexture() end function t:SetAllPoints() end
					function t:Show() self.shown = true end function t:Hide() self.shown = false end
					return t
				end
				return b
			end
			G.items.mace.price, G.items.polearm.price = 500, 300
			-- raw choices: 1 = currency x50, 2 = mace x1, 3 = polearm x2; buttons count items only
			G.GetNumQuestLogChoices = function() return 3 end
			G.GetQuestLogChoiceInfoLootType = function(i) return i == 1 and 1 or 0 end
			G.GetQuestLogChoiceInfo = function(i) return "n", 0, ({ 50, 1, 2 })[i] end
			G.GetQuestLogItemLink = function(_, id) return ({ "mace", "polearm" })[id] end
			G.QuestInfoFrame = { questLog = true, rewardsFrame = { RewardButtons = { button(1), button(2) } } }
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_REWARD)
			local btns = G.QuestInfoFrame.rewardsFrame.RewardButtons
			T.truthy(btns[2].hgaCoin and btns[2].hgaCoin.shown, "2 x 300 beats 500 (not 50 x 500)")
			T.truthy(not (btns[1].hgaCoin and btns[1].hgaCoin.shown), "no coin on the mace")
			-- the reward list does not match the buttons: reported, no coin
			G.GetNumQuestLogChoices = function() return 1 end
			G.QuestInfoFrame = { questLog = true, rewardsFrame = { RewardButtons = { button(1), button(2) } } }
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_REWARD)
			btns = G.QuestInfoFrame.rewardsFrame.RewardButtons
			T.truthy(not (btns[1].hgaCoin and btns[1].hgaCoin.shown) and not (btns[2].hgaCoin and btns[2].hgaCoin.shown), "no coin")
			local seen = false
			for _, e in ipairs(G.reportedErrors) do if tostring(e):match("has no matching reward") then seen = true end end
			T.truthy(seen, "mismatch reported")
		end },
		{ "quest rewards: the map's details pane (no rewards) leaves the NPC dialog's leftover buttons alone", function()
			local G = env(); local ns = loadAll(G)
			local function button(i)
				local b = { type = "choice", objectType = "item", id = i, questID = 77 } -- turned in at the NPC
				function b:GetID() return self.id end
				function b:IsShown() return true end
				function b:CreateTexture()
					local t = { shown = false }
					function t:SetTexture(f) self.file = f end function t:SetVertexColor() end
					function t:SetSize() end function t:SetPoint() end
					function t:SetColorTexture() end function t:SetAllPoints() end
					function t:Show() self.shown = true end function t:Hide() self.shown = false end
					return t
				end
				return b
			end
			G.items.mace.price, G.items.polearm.price = 500, 300
			-- quest-log calls answer for the quest selected on the map, not for quest 77
			G.GetNumQuestLogChoices = function() return 0 end
			G.GetQuestLogChoiceInfoLootType = function() return 0 end
			G.GetQuestLogChoiceInfo = function(i) return "n", 0, 1 end
			G.GetQuestLogItemLink = function(_, id) return ({ "mace", "polearm" })[id] end
			G.QuestInfoFrame = { questLog = true, rewardsFrame = { RewardButtons = { button(1), button(2) } } }
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_MAP_DETAILS)
			local btns = G.QuestInfoFrame.rewardsFrame.RewardButtons
			T.eq(btns[1].hgaCoin, nil, "leftover button 1 not judged")
			T.eq(btns[2].hgaCoin, nil, "leftover button 2 not judged")
			T.eq(#G.reportedErrors, 0, "no 'no matching reward' error from the leftover buttons")
			-- the map's rewards pane right after it is judged as usual
			G.GetNumQuestLogChoices = function() return 2 end
			G.GetQuestLogChoiceInfo = function(i) return "n", 0, 1 end
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_MAP_REWARDS)
			T.truthy(btns[1].hgaCoin and btns[1].hgaCoin.shown, "map rewards: coin on the 500 mace")
		end },
		{ "quest rewards: QuestInfo_ShowRewards replaced before load -> reported, other modules still load", function()
			local G = env()
			local original = G.QuestInfo_ShowRewards
			G.QuestInfo_ShowRewards = function(...) return original(...) end -- what an earlier hooksecurefunc leaves
			local ns = loadAll(G)
			local seen = false
			for _, e in ipairs(G.reportedErrors) do if tostring(e):match("QuestInfo_ShowRewards was replaced") then seen = true end end
			T.truthy(seen, "reported")
			T.eq(G.hooks.QuestInfo_Display, nil, "no hook that would never fire")
			T.truthy(G.HunterGearAdvisorSwapBanner, "Swap.lua's load (after Quest.lua) still ran")
		end },
		{ "quest rewards: no upgrade among the choices -> coin on the one that sells for the most", function()
			local G = env(); local ns = loadAll(G)
			local function button(i)
				local b = { type = "choice", objectType = "item", id = i }
				function b:GetID() return self.id end
				function b:IsShown() return true end
				function b:CreateTexture()
					local t = { shown = false }
					function t:SetTexture(f) self.file = f end function t:SetVertexColor() end
					function t:SetSize() end function t:SetPoint() end
					function t:SetColorTexture() end function t:SetAllPoints() end
					function t:Show() self.shown = true end function t:Hide() self.shown = false end
					return t
				end
				return b
			end
			G.items.mace.price, G.items.polearm.price, G.items.gloves.price, G.items.newbow.price = 500, 300, 100, 50
			G.GetQuestItemLink = function(_, i) return ({ "mace", "polearm", "gloves" })[i] end
			G.questCounts = { [2] = 2 } -- 2 x 300 = 600 beats 500
			G.QuestInfoFrame = { rewardsFrame = { RewardButtons = { button(1), button(2), button(3) } } }
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_REWARD)
			local btns = G.QuestInfoFrame.rewardsFrame.RewardButtons
			T.truthy(btns[2].hgaCoin and btns[2].hgaCoin.shown, "coin on 2 x 300")
			T.eq(btns[2].hgaCoin.file, "Interface\\MONEYFRAME\\UI-GoldIcon")
			T.truthy(not (btns[1].hgaCoin and btns[1].hgaCoin.shown), "no coin on 500")
			T.truthy(not (btns[2].hgaCheck and btns[2].hgaCheck.shown), "no upgrade arrow")
			-- an upgrade among the choices: the arrow and the green frame decide, no coin
			G.GetQuestItemLink = function(_, i) return ({ "mace", "newbow" })[i] end
			G.questCounts = {}
			G.QuestInfoFrame = { rewardsFrame = { RewardButtons = { button(1), button(2) } } }
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_REWARD)
			btns = G.QuestInfoFrame.rewardsFrame.RewardButtons
			T.truthy(btns[2].hgaCheck and btns[2].hgaCheck.shown, "bow is an upgrade")
			T.truthy(not (btns[1].hgaCoin and btns[1].hgaCoin.shown) and not (btns[2].hgaCoin and btns[2].hgaCoin.shown), "no coin")
			-- a single reward to take: nothing to choose, no coin
			G.GetQuestItemLink = function(_, i) return ({ "mace" })[i] end
			G.QuestInfoFrame = { rewardsFrame = { RewardButtons = { button(1) } } }
			G.hooks.QuestInfo_Display(G.QUEST_TEMPLATE_REWARD)
			T.eq(G.QuestInfoFrame.rewardsFrame.RewardButtons[1].hgaCoin, nil, "one choice: no coin")
		end },
		{ "spec: no talent data yet -> said in the tooltip and /hga, never the screenshot build", function()
			local G = env()
			G.noTalentConfig = true
			local ns = loadAll(G)
			T.eq(ns.Advisor.State(), nil)
			T.eq(ns.Advisor.notReadyReason, "talents")
			local lines = ns.Advisor.Explain("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(lines[1][1]:match("таланты ещё не прочитаны"), lines[1][1])
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.truthy(G.printed[#G.printed]:match("таланты ещё не прочитаны"), G.printed[#G.printed])
			-- the data arrives: the next pass reads it
			G.noTalentConfig = false
			ns.Invalidate()
			T.truthy(ns.Advisor.State(), "ready after the talents came")
		end },
		{ "spec: clicks not applied yet do not move the weights; a spec switch reads the new config", function()
			local G = env(); local ns = loadAll(G)
			local w0 = ns.Advisor.State().W.CRIT
			-- 5 points staged into Mortal Shots (not applied): the applied snapshot stays
			G.talentRanks[105002] = 5; G.staged = true
			ns.Invalidate()
			T.near(ns.Advisor.State().W.CRIT, w0, 1e-9, "staged Mortal Shots ignored")
			-- applied
			G.staged = false
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			T.truthy(ns.Advisor.State().W.CRIT > w0, "applied Mortal Shots raise crit")
			-- dual spec: another config, staged right away -> no snapshot of it yet: said, not guessed
			G.staged = true
			G.fire("ACTIVE_COMBAT_CONFIG_CHANGED", 8)
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "staged")
		end },
		{ "spec: Lone Wolf follows the live pet; without Lone Wolf a missing pet changes nothing", function()
			local G = env()
			G.petOut = false
			local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.model.petOut, true, "no Lone Wolf: a pet is assumed")
			G.talentRanks[105007] = 1 -- Lone Wolf
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			local st = ns.Advisor.State()
			T.eq(st.snap.model.petOut, false)
			-- without the pet, expertise is the hawks' and the weave's melee (Model.Parts); the pet adds its own
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			p.tal = {}
			for k, v in pairs(st.model.tal) do p.tal[k] = v end
			p.tal.summonHawk, p.survival = 0, false
			T.eq(ns.Model.Weights(p).EXPERTISE, 0, "no pet, no hawks, no melee: expertise worthless")
			local expNoPet = st.W.EXPERTISE
			G.petOut = true
			G.fire("UNIT_PET", "player")
			T.eq(ns.Advisor.State().snap.model.petOut, true, "pet summoned -> re-evaluated")
			T.truthy(ns.Advisor.State().W.EXPERTISE > expNoPet + 0.5, "the pet adds its expertise: "
				.. expNoPet .. " -> " .. ns.Advisor.State().W.EXPERTISE)
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local all = table.concat(G.printed, "\n")
			T.truthy(all:match("билд BM %d+ / MM %d+ / SV %d+"), "build line")
			T.truthy(all:match("кому идёт урон: Auto Shot"), "damage shares")
		end },
		-- /hga weights with Lone Wolf (node 105007) and no pet out: the pet's share of crit, hit and expertise is gone,
		-- while expertise still lowers the mob's dodge against the hawks (Summon Hawk, node 104966; Model.Parts hawkDodge;
		-- outside the Survival branch, whose weave casts no Summon Hawk) and the weave's melee swings (the Survival branch with
		-- a bow); the line says where it goes, and W.EXPERTISE agrees
		{ "/hga weights: Lone Wolf with no pet says the pet's stats are not counted and where expertise still goes", function()
			local function petLine(hawk, melee)
				local G = env()
				if melee ~= "none" then survivalTree(G) end -- a melee mechanism: the Survival branch's weave
				if melee == "noBow" then G.equippedLinks[18] = nil end
				G.talentRanks[105007] = 1
				G.talentRanks[104966] = hawk and 1 or 0
				G.petOut = false
				local ns = loadAll(G)
				local st = ns.Advisor.State()
				T.eq(st.snap.petOut, false)
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR("weights")
				for _, l in ipairs(G.printed) do if l:find("билд BM", 1, true) then return l, st.W.EXPERTISE end end
				return "no line", st.W.EXPERTISE
			end
			local head = "пета нет — Lone Wolf +20%; доля пета в крите, меткости и мастерстве не в счёт, "
			for _, case in ipairs({
				{ true, "weave", "мастерство идёт ближнему бою", true },
				{ true, "none", "мастерство идёт ястребам", true },
				{ false, "weave", "мастерство идёт ближнему бою", true },
				{ false, "none", "мастерство урона не даёт", false },
				{ true, "noBow", "мастерство урона не даёт", false },
			}) do
				local l, wExp = petLine(case[1], case[2])
				local tag = string.format("Summon Hawk %s, melee %s", tostring(case[1]), case[2])
				T.truthy(l:find(head .. case[3], 1, true) and l:sub(-#case[3]) == case[3], tag .. ": " .. l)
				if case[4] then
					T.truthy(wExp > 0.1, tag .. ": expertise adds damage: " .. wExp)
				else
					T.eq(wExp, 0, tag .. ": expertise adds nothing")
				end
			end
		end },
		{ "wowsims check: pet family read live and kept, Serpent Sting IX only from the book", function()
			local G = env()
			local ns = loadAll(G)
			local m = ns.Advisor.State().snap.model
			T.eq(m.petFamily, 2, "Cat read from UnitCreatureFamily")
			T.eq(m.serpentTick, nil, "no book: the trainer rank")
			-- another pet summoned: the family changes, the snapshot follows
			G.petFamilyID = 1
			G.fire("UNIT_PET", "player")
			T.eq(ns.Advisor.State().snap.model.petFamily, 1, "Wolf")
			-- the pet dismissed: the last family seen this session stays
			G.petOut = false
			G.fire("UNIT_PET", "player")
			T.eq(ns.Advisor.State().snap.model.petFamily, 1, "kept while dismissed")
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.truthy(table.concat(G.printed, "\n"):match("семейство %+0%% урона, Bite"), "family in /hga weights")
			G.IsPlayerSpell = function(id) return id == 25295 end
			ns.Advisor.Reset()
			T.eq(ns.Advisor.State().snap.model.serpentTick, 135, "Guide: Serpent Sting IX learned")
		end },
		{ "spec: Trueshot Aura's RAP is counted when the talent is taken and the aura is off", function()
			local G = env(); local ns = loadAll(G)
			local rap0 = ns.Advisor.State().snap.model.rap
			G.talentRanks[105004] = 1
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			T.eq(ns.Advisor.State().snap.model.rap, rap0 + 50, "level 43: rank of 40 = +50 RAP")
		end },
		-- each test below pins one reading rule of Game/Player.lua: the talents (the spec group's config, an unanswered node,
		-- the dual spec switch, talents after login, Apply read at once), the pet that dies under Lone Wolf, a secret melee
		-- crit, a dagger's normalized speed
		{ "no active config id -> the active spec group's config is read", function()
			local G = env()
			G.noTalentConfig = true
			G.specGroup = 2
			G.groupCfg = { [1] = 5, [2] = 9 }
			G.ranksByCfg = { [5] = {}, [9] = { [105002] = 5 } } -- group 2 has Mortal Shots
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.truthy(st, "read through the spec group")
			T.eq(st.snap.model.tal.mortalShots, 5, "config of the ACTIVE group (2), not group 1")
		end },
		-- the ranks name every talent of Player.BRANCHES, 0 for one not taken (Player.PetOut, ReadStats, Snapshot and the
		-- model read them directly); the old Lightning Reflexes node counts under its one key (SAME_TALENT)
		{ "ReadTalents gives a rank for every talent of BRANCHES, 0 for one not taken, the old Lightning Reflexes node under its one key", function()
			local G = env()
			G.talentRanks[104982] = 3 -- the old Lightning Reflexes node, off the grid
			local ns = loadAll(G)
			local tal = ns.Player.ReadTalents()
			local names = 0
			for _, branch in ipairs(ns.Player.BRANCHES) do
				for name in pairs(branch.nodes) do
					if name ~= "lightningReflexesOld" then
						names = names + 1
						T.eq(type(tal[name]), "number", "a rank for " .. name)
					end
				end
			end
			local keys = 0
			for _ in pairs(tal) do keys = keys + 1 end
			T.eq(keys, names, "no other key"); T.eq(tal.lightningReflexesOld, nil)
			T.eq(tal.lightningReflexes, 3, "the old node's rank under lightningReflexes")
			T.eq(tal.loneWolf, 0); T.eq(tal.trueshotAura, 0); T.eq(tal.unleashedFury, 5)
			local modelTal = ns.Advisor.State().snap.model.tal
			for k, v in pairs(tal) do T.eq(modelTal[k], v, "the model's rank of " .. k) end
		end },
		-- C_Traits.GetNodeInfo returns a TraitNodeInfo, whose activeRank is a number, 0 for a node not taken (Forever
		-- Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua: Nilable = false): a node answered without one is
		-- an error, not a rank of 0
		{ "ReadTalents: a node answered without an activeRank is an error", function()
			local G = env()
			local ns = loadAll(G)
			local get = G.C_Traits.GetNodeInfo
			G.C_Traits.GetNodeInfo = function(cfg, nodeID)
				local info = get(cfg, nodeID)
				if nodeID == 104969 then info.activeRank = nil end -- Unleashed Fury
				return info
			end
			local ok, err = pcall(ns.Player.ReadTalents)
			T.eq(ok, false); T.truthy(tostring(err):find("talent node 104969 without an activeRank", 1, true), tostring(err))
		end },
		{ "a node the client cannot answer yet (ID 0) -> 'talents', not zero ranks", function()
			local G = env()
			G.emptyNode = 104969 -- Unleashed Fury
			local ns = loadAll(G)
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "talents")
			-- a failed snapshot is not redone for every bag button within a second
			local calls = 0
			local get = G.C_Traits.GetNodeInfo
			G.C_Traits.GetNodeInfo = function(...) calls = calls + 1; return get(...) end
			ns.Invalidate()
			for _ = 1, 10 do ns.Advisor.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 }) end
			local one = calls
			T.truthy(one > 0, "a snapshot is tried")
			for _ = 1, 10 do ns.Advisor.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 }) end
			T.eq(calls, one, "no new snapshot until the retry time or an Invalidate")
		end },
		{ "dual spec switch (ACTIVE_TALENT_GROUP_CHANGED) reads the other config's build", function()
			local G = env(); local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.model.tal.summonHawk, 1)
			G.ranksByCfg = { [8] = { [105007] = 1, [105002] = 5, [104997] = 1 } } -- MM: Lone Wolf, Mortal Shots, Sniper
			G.activeCfg = 8
			G.fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
			local tal = ns.Advisor.State().snap.model.tal
			T.eq(tal.summonHawk, 0); T.eq(tal.sniperShot, 1); T.eq(tal.loneWolf, 1)
		end },
		{ "talents that arrive after login (TRAIT_CONFIG_LIST_UPDATED) bring the banner", function()
			local G = env()
			G.noTalentConfig = true
			local ns = loadAll(G)
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			T.eq(banner.shown, false, "no talents, no banner")
			G.noTalentConfig = false
			G.fire("TRAIT_CONFIG_LIST_UPDATED")
			T.eq(banner.shown, true, "configs arrived -> re-evaluated")
		end },
		{ "Lone Wolf and the pet dies (UNIT_HEALTH of the pet) -> no pet counted", function()
			local G = env()
			G.talentRanks[105007] = 1
			local dead = false
			G.UnitIsDead = function(u) return u == "pet" and dead end
			local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.model.petOut, true)
			dead = true
			G.fire("UNIT_HEALTH", "pet")
			T.eq(ns.Advisor.State().snap.model.petOut, false)
		end },
		{ "secret melee crit hides the stats like the other secret values", function()
			local G = env()
			G.GetCritChance = function() return 8.67 end
			G.secretValues = { [8.67] = true }
			local ns = loadAll(G)
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "hidden")
		end },
		{ "a dagger in the main hand uses normalized speed 1.7", function()
			local G = env()
			local W = { r = 1, g = 1, b = 1 }
			G.items.dagger = { info = { 33, "INVTYPE_WEAPON", 2, 15 }, lines = { { leftText = "Кинжал", leftColor = W },
				{ leftText = "Одноручное", rightText = "Кинжал", leftColor = W, rightColor = W },
				{ leftText = "Урон: 27-41", rightText = "Скорость 1,70", leftColor = W, rightColor = W },
				{ leftText = "(20,0 ед. урона в секунду)", leftColor = W } }, api = {} }
			G.equippedLinks[16] = "dagger"
			local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.model.mhNorm, 1.7)
		end },
		{ "Apply is read at once, so clicks staged before any tooltip keep the applied build", function()
			local G = env(); local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.model.tal.mortalShots, 0)
			-- banner off: then nothing re-evaluates on its own after Apply (only a tooltip would)
			G.SlashCmdList.HUNTERGEARADVISOR("banner")
			G.talentRanks[105002] = 5
			G.fire("TRAIT_CONFIG_UPDATED", 7) -- Apply: Mortal Shots 5/5
			G.talentRanks[104998] = 5; G.staged = true -- new clicks, nothing evaluated in between
			ns.Invalidate()
			local tal = ns.Advisor.State().snap.model.tal
			T.eq(tal.mortalShots, 5, "the applied build"); T.eq(tal.rangedWeaponSpec, 0, "not the staged one")
		end },
		-- weapons at their own speed: ctx.weaponGain runs the damage model with the set's weapons
		{ "weapon speed: equal-DPS bows of different speed score as the model says (BM: fast, MM without Deadly Aspects: slow)", function()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			local function run(ranks)
				local G = env()
				if ranks then G.talentRanks = ranks end
				-- the worn bow's DPS and Agility (21,2 DPS, +5), other speeds
				for i, sp in ipairs({ "1,80", "3,40" }) do
					G.items["bow" .. i] = { info = { 40 + i, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Лук " .. sp), ln("Дальний бой", "Лук"),
						ln("Урон: 30-50", "Скорость " .. sp), ln("(21,2 ед. урона в секунду)"), ln("+5 к ловкости") }, api = {} }
				end
				G.bags[0] = { "bow1", "bow2" }
				local ns = loadAll(G)
				local st = ns.Advisor.State()
				local function modelGain(speed)
					local p = {}
					for k, v in pairs(st.model) do p[k] = v end
					p.bowSpeed = speed
					return (ns.Model.Total(p) - st.total) / st.unitDps
				end
				local fast = ns.Advisor.Evaluate("bow1", { kind = "bag", bag = 0, slot = 1 })
				local slow = ns.Advisor.Evaluate("bow2", { kind = "bag", bag = 0, slot = 2 })
				T.near(fast.delta, modelGain(1.8), 1e-9, "fast bow = the model at 1.8 s")
				T.near(slow.delta, modelGain(3.4), 1e-9, "slow bow = the model at 3.4 s")
				return fast.delta, slow.delta
			end
			-- BM 32/2 (Deadly Aspects 5/5): more shots keep Quick Shots up
			local bmFast, bmSlow = run()
			T.truthy(bmFast > bmSlow + 5, string.format("BM: fast %.2f vs slow %.2f", bmFast, bmSlow))
			-- MM without Deadly Aspects (Mortal Shots, Ranged Weapon Specialization, Barrage, Lethal
			-- Attacks): Aimed Shot carries weapon DPS x speed
			local mmFast, mmSlow = run({ [105002] = 5, [104998] = 5, [105001] = 3, [105011] = 2 })
			T.truthy(mmSlow > mmFast + 20, string.format("MM: slow %.2f vs fast %.2f", mmSlow, mmFast))
		end },
		{ "weapon speed: the worn set gives exactly 0; a scope is its damage / speed in the model, worn or not", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local plain = {}
			for i, l in ipairs(G.items.bow.lines) do plain[i] = l end
			G.items.plainbow = { info = { 43, "INVTYPE_RANGED", 2, 2 }, lines = plain, api = G.items.bow.api }
			-- the worn bow carries a scope: +7 damage a shot
			G.items.bow.lines[#G.items.bow.lines + 1] = { leftText = "Прицел (+7 к урону)", leftColor = W1 }
			G.bags[0] = { "bow", "plainbow" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.near(st.snap.model.bowDPS, 21.2 + 7 / 2.6, 1e-9, "the worn scope is in the model's bow DPS")
			T.eq(st.ctx.weaponGain(st.snap.equipped), 0, "worn set: exactly 0")
			local copy = ns.Advisor.Evaluate("bow", { kind = "bag", bag = 0, slot = 1 })
			T.near(copy.delta, 0, 1e-9, "a bag copy of the worn bow"); T.eq(copy.verdict, "same")
			local r = ns.Advisor.Evaluate("plainbow", { kind = "bag", bag = 0, slot = 2 })
			T.near(r.delta, -(7 / 2.6) * st.W.RANGED_DPS, 1e-6, "without the scope: its damage / speed less")
		end },
		{ "weapon speed: a 2H and a 1H pair are priced at each weapon's own speed", function()
			local function setup(ranks)
				local G = env()
				survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
				if ranks then for k, v in pairs(ranks) do G.talentRanks[k] = v end end
				local W1 = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
				for i, sp in ipairs({ "2,90", "3,80" }) do
					G.items["two" .. i] = { info = { 44 + i, "INVTYPE_2HWEAPON", 2, 10 }, lines = { ln("Посох " .. sp), ln("Двуручное", "Посох"),
						ln("Урон: 90-140", "Скорость " .. sp), ln("(40,0 ед. урона в секунду)") }, api = {} }
				end
				G.items.fastsword = { info = { 47, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Быстрый меч"), ln("Одноручное", "Меч"),
					ln("Урон: 25-41", "Скорость 1,50"), ln("(22,1 ед. урона в секунду)") }, api = {} }
				G.bags[0] = { "two1", "two2", "fastsword" }
				local ns = loadAll(G)
				local st = ns.Advisor.State()
				local function modelGain(changes)
					local p = {}
					for k, v in pairs(st.model) do p[k] = v end
					for k, v in pairs(changes) do p[k] = v end
					return (ns.Model.Total(p) - st.total) / st.unitDps
				end
				local fastPiece
				for _, piece in ipairs(st.snap.bagPieces) do if piece.link == "fastsword" then fastPiece = piece end end
				return ns, st, modelGain, fastPiece
			end
			local ns, st, modelGain = setup()
			-- worn: sword (22,1 DPS, 2,6 s, +22 AP) + offsword (18 DPS, +4 Agility)
			local handStats = 22 * st.W.AP + 4 * st.W.AGI
			local a = ns.Advisor.Evaluate("two1", { kind = "bag", bag = 0, slot = 1 })
			local b = ns.Advisor.Evaluate("two2", { kind = "bag", bag = 0, slot = 2 })
			T.eq(a.hand, "2h"); T.eq(b.hand, "2h")
			local function twoH(speed) return { mhDPS = 40, mhSpeed = speed, mhNorm = 3.3, twoH = true, ohDPS = 0, ohSpeed = 2.6, unarmed = false } end
			T.near(a.delta, modelGain(twoH(2.9)) - handStats, 1e-9, "2H at 2.9 s")
			T.near(b.delta, modelGain(twoH(3.8)) - handStats, 1e-9, "2H at 3.8 s")
			T.truthy(math.abs(a.delta - b.delta) > 0.1, "speed moves the 2H: " .. a.delta .. " vs " .. b.delta)
			-- Strider Kick and Expose Prey's Mongoose Bite hit with the normalized speed: a two-hander's 3.3
			-- (Player.NormSpeed), not the one-hander's 2.4 (Expose Prey 2, Strider Kick, Savage Strikes 2)
			local ns3, st3, modelGain3 = setup({ [104985] = 2, [104981] = 1, [104993] = 2 })
			local c = ns3.Advisor.Evaluate("two1", { kind = "bag", bag = 0, slot = 1 })
			T.near(c.delta, modelGain3(twoH(2.9)) - (22 * st3.W.AP + 4 * st3.W.AGI), 1e-9, "2H at 2.9 s, normalized 3.3")
			local at24 = twoH(2.9)
			at24.mhNorm = 2.4
			T.truthy(math.abs(modelGain3(twoH(2.9)) - modelGain3(at24)) > 0.1, "the normalized speed moves the 2H's score")
			-- a pair: the main hand's speed; the off hand behind the 2.6 s main hand swings in no visit of the weave (the
			-- ranged path sets the cycle, Model weaveParts' off-hand share), so its speed and DPS move nothing there
			local ns2, st2, modelGain2, fast = setup({ [104985] = 2 })
			-- the worn triple first: the cache keys the whole (ranged, main hand, off hand) triple
			T.eq(st2.ctx.weaponGain(st2.snap.equipped), 0, "worn hands: 0")
			local mhSet = ns2.Score.CopySet(st2.snap.equipped); mhSet[16] = fast
			T.near(st2.ctx.weaponGain(mhSet), modelGain2({ mhDPS = 22.1, mhSpeed = 1.5 }), 1e-12, "main hand at 1.5 s")
			T.truthy(math.abs(st2.ctx.weaponGain(mhSet)) > 0.01, "the faster main hand moves the score")
			local ohSet = ns2.Score.CopySet(st2.snap.equipped); ohSet[17] = fast
			T.near(st2.ctx.weaponGain(ohSet), modelGain2({ ohDPS = 22.1, ohSpeed = 1.5 }), 1e-12, "off hand at 1.5 s")
			T.near(st2.ctx.weaponGain(ohSet), 0, 1e-12, "the weave: no off-hand swing behind the 2.6 s main hand")
			T.eq(st2.ctx.landedHits.oh.swings, 0, "the worn off hand lands no hit")
		end },
		{ "weapon speed: taking both weapons off is a loss (the weave stays, unarmed)", function()
			local G = env()
			survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local bare = ns.Score.CopySet(st.snap.equipped)
			bare[16], bare[17] = nil, nil
			local g = st.ctx.weaponGain(bare)
			T.truthy(g < -5, "no weapons: " .. g)
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			p.mhDPS, p.mhSpeed, p.mhNorm, p.ohDPS, p.ohSpeed, p.twoH, p.unarmed = 0, 1.0, 1.0, 0, 2.6, false, true
			T.eq(g, (ns.Model.Total(p) - st.total) / st.unitDps, "empty hands: unarmed, 0 DPS, the main hand at 1.0 s")
		end },
		{ "weapon inputs: a weapon without a parsed speed or DPS is an error; a slot with no weapon is 0 DPS, the main hand at 1.0 s, the others at 2.6 s", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			G.items.nospeed = { info = { 64, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Меч без скорости"), ln("Одноручное", "Меч"),
				ln("(20,0 ед. урона в секунду)") }, api = {} }
			G.items.nodps = { info = { 65, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Меч без DPS"), ln("Одноручное", "Меч"),
				ln("Урон: 30-50", "Скорость 2,00") }, api = {} }
			G.items.nospeedbow = { info = { 66, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Лук без скорости"), ln("Дальний бой", "Лук"),
				ln("(20,0 ед. урона в секунду)") }, api = {} }
			G.items.frill = { info = { 67, "INVTYPE_HOLDABLE", 4, 0 }, lines = { ln("Безделушка"), ln("Левая рука") }, api = {} }
			-- items of other classes with a weapon inventory type (Forever Item.csv: Egan's Blaster 13289 class 12,
			-- Torch of Retribution 10515 class 4)
			G.items.blaster = { info = { 13289, "INVTYPE_RANGEDRIGHT", 12, 0 }, lines = { ln("Бластер Игана"), ln("Дальний бой") }, api = {} }
			G.items.torch = { info = { 10515, "INVTYPE_2HWEAPON", 4, 0 }, lines = { ln("Факел возмездия"), ln("Двуручное") }, api = {} }
			local ns = loadAll(G)
			local P = ns.Player
			local function pc(link) return ns.Items.Piece(ns.Items.Get(link), { kind = "new" }) end
			for _, cs in ipairs({ { 16, "nospeed", "speed" }, { 17, "nospeed", "speed" }, { 16, "nodps", "DPS" }, { 17, "nodps", "DPS" },
				{ 18, "nospeedbow", "speed" } }) do
				local ok, err = pcall(P.WeaponInputs, { [cs[1]] = pc(cs[2]) })
				T.eq(ok, false, cs[2] .. " in slot " .. cs[1])
				T.truthy(tostring(err):find("weapon in slot " .. cs[1] .. " without a parsed " .. cs[3], 1, true), tostring(err))
			end
			local empty = P.WeaponInputs({})
			T.eq(empty.bowDPS, 0); T.eq(empty.bowSpeed, 2.6); T.eq(empty.mhDPS, 0); T.eq(empty.mhSpeed, 1.0)
			T.eq(empty.ohDPS, 0); T.eq(empty.ohSpeed, 2.6); T.eq(empty.unarmed, true); T.eq(empty.mhNorm, 1.0)
			local held = P.WeaponInputs({ [16] = pc("sword"), [17] = pc("frill"), [18] = pc("blaster") })
			T.near(held.mhDPS, 22.1, 1e-9); T.eq(held.unarmed, false)
			T.eq(held.ohDPS, 0); T.eq(held.ohSpeed, 2.6, "a held-in-off-hand item: no weapon")
			T.eq(held.bowDPS, 0); T.eq(held.bowSpeed, 2.6, "a class-12 item in the ranged slot: no weapon")
			local torch = P.WeaponInputs({ [16] = pc("torch") })
			T.eq(torch.mhDPS, 0); T.eq(torch.mhSpeed, 1.0); T.eq(torch.unarmed, true, "a class-4 two-hand item: no weapon, unarmed")
			T.eq(torch.mhNorm, 1.0)
			-- worn: the snapshot raises; in game the tooltip post-call runs under securecallfunction
			-- (TooltipDataHandler.lua), which hands the error to the error handler
			G.equippedLinks[17] = "nospeed"
			ns.Advisor.Reset()
			local tip = { lines = {} }
			function tip:GetItem() return "Новый лук", "newbow" end
			function tip:AddLine(t) table.insert(self.lines, t) end
			G.GameTooltip = tip
			local ok, err = pcall(G.tooltipPost, tip)
			T.eq(ok, false); T.truthy(tostring(err):find("weapon in slot 17 without a parsed speed", 1, true), tostring(err))
		end },
		-- dual-wield hit past the cap: weaponGain runs the model at the worn hit, so Score adds only the hit beyond it
		{ "dual-wield hit past the cap: hands of the other kind than the worn ones score as the model at the worn 9% hit", function()
			local function setup(mh, oh, bags)
				local G = env()
				survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
				G.GetCombatRatingBonus = function() return 9 end -- 9% hit, 4% past the 5% cap
				G.equippedLinks[16], G.equippedLinks[17] = mh, oh
				G.bags[0] = bags
				local ns = loadAll(G)
				local st = ns.Advisor.State()
				local function modelGain(changes)
					local p = {}
					for k, v in pairs(st.model) do p[k] = v end
					for k, v in pairs(changes) do p[k] = v end
					return (ns.Model.Total(p) - st.total) / st.unitDps
				end
				return ns, st, modelGain
			end
			-- worn sword (22,1 DPS, 2,6 s, +22 AP) + offsword (18 DPS, 1,8 s, +4 Agility): dual wield; the staff from the bags
			local ns, st, modelGain = setup("sword", "offsword", { "staff" })
			T.truthy(st.W.HIT_DW > 0, "the weave: dual-wield hit has a value")
			T.near(st.ctx.wornHit, 9, 1e-12)
			local staff = ns.Advisor.Evaluate("staff", { kind = "bag", bag = 0, slot = 1 })
			T.eq(staff.hand, "2h")
			local twoH = { mhDPS = 30, mhSpeed = 3.2, mhNorm = 3.3, twoH = true, ohDPS = 0, ohSpeed = 2.6, unarmed = false }
			T.near(staff.delta, modelGain(twoH) + 12 * st.W.AGI - (22 * st.W.AP + 4 * st.W.AGI), 1e-9,
				"the model's gain at the worn hit plus the stats; the dual-wield hit is not counted twice")
			-- the reverse: worn staff, the best pair of one-handers from the bags (sword +22 AP, bagsword +10 Agility)
			local ns2, st2, modelGain2 = setup("staff", nil, { "sword", "bagsword" })
			local pair = ns2.Advisor.BestPairVs2H()
			T.truthy(pair and pair.mh and pair.oh, "a pair")
			local pairInputs = { mhDPS = pair.mh.stats.DPS, mhSpeed = pair.mh.speed, mhNorm = 2.4, twoH = false,
				ohDPS = pair.oh.stats.DPS, ohSpeed = pair.oh.speed, unarmed = false }
			T.near(pair.delta, modelGain2(pairInputs) + 22 * st2.W.AP + 10 * st2.W.AGI - 12 * st2.W.AGI, 1e-9,
				"the pair: the model's gain at the worn hit plus the stats")
		end },
		{ "weapon speed: the plan settles over weapons of many speeds and keeps its properties", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			-- one-handers with equal Agility (above the worn off hand's 4), so the speed decides between them
			local specs = { { "w1", "INVTYPE_WEAPON", 7, "1,50", "22,0", "+12 к ловкости" }, { "w2", "INVTYPE_WEAPON", 7, "2,90", "22,0", "+12 к ловкости" },
				{ "w3", "INVTYPE_WEAPONMAINHAND", 7, "3,40", "22,0", "+12 к ловкости" }, { "w4", "INVTYPE_2HWEAPON", 10, "3,60", "31,0", "+25 к ловкости" },
				{ "w5", "INVTYPE_2HWEAPON", 10, "2,40", "32,0", "+25 к ловкости" }, { "r1", "INVTYPE_RANGED", 2, "1,50", "22,5", "+5 к ловкости" },
				{ "r2", "INVTYPE_RANGED", 2, "3,10", "23,0", "+5 к ловкости" } }
			local bag = {}
			for i, s in ipairs(specs) do
				local kind = s[2] == "INVTYPE_RANGED" and "Дальний бой" or (s[2] == "INVTYPE_2HWEAPON" and "Двуручное" or "Одноручное")
				local lines = { ln("Оружие " .. s[1]), ln(kind, "x"), ln("Урон: 1-2", "Скорость " .. s[4]), ln("(" .. s[5] .. " ед. урона в секунду)") }
				if s[6] then lines[#lines + 1] = ln(s[6]) end
				G.items[s[1]] = { info = { 50 + i, s[2], 2, s[3] }, lines = lines, api = {} }
				bag[#bag + 1] = s[1]
			end
			G.bags[0] = bag
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local plan = ns.Advisor.Plan()
			T.truthy(plan and #plan.rows > 0, "a plan")
			for _, row in ipairs(plan.rows) do
				T.truthy(not row.gain or row.gain.verdict ~= "worse", "row " .. row.slot .. " is no loss")
			end
			-- planning again from the result finds no further damage step
			local eq, cands = st.ctx.equipped, {}
			for _, p in ipairs(st.snap.bagPieces) do cands[#cands + 1] = p end
			local target = ns.Score.Plan(eq, cands, st.W, st.ctx)
			-- BM: the 1.5 s bow keeps Quick Shots up; by DPS alone the 23-DPS 3.1 s bow would win
			T.eq(target[18].link, "r1", "the model's bow")
			local left, inT = {}, {}
			for _, it in pairs(target) do inT[it] = true end
			for _, it in ipairs(cands) do if not inT[it] then left[#left + 1] = it end end
			for _, it in pairs(eq) do if not inT[it] then left[#left + 1] = it end end
			local c2 = ns.Score.CopySet(st.ctx); c2.equipped = target
			local again = ns.Score.Plan(target, left, st.W, c2)
			T.truthy(ns.Score.SetValue(again, st.W, st.ctx) - ns.Score.SetValue(target, st.W, st.ctx) <= ns.Score.EPS, "fixed point")
			-- the best hands of Evaluate and of the plan agree
			local best = ns.Score.BestHands(nil, eq, st.ctx.pool, st.W, st.ctx)
			T.eq(target[16], best.mh); T.eq(target[17], best.oh)
		end },
		-- item sets (Game/SetData.lua): Devilsaur Armor 143 (Devilsaur Leggings 15062, Devilsaur Gauntlets
		-- 15063; 2 pieces: +2% hit), Embrace of the Viper 162 (2: +10 Intellect, 3: +10 attack power, 4 and 5:
		-- procs HGA does not count)
		{ "set: Items record the set id; the base hit leaves out the worn set bonus' hit", function()
			local G = env()
			local W = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W, rightColor = W } end
			G.items.devlegs = { info = { 15062, "INVTYPE_LEGS", 4, 2 }, setID = 143, lines = { ln("Штаны девизавра"), ln("Ноги", "Кожа"), ln("+22 к ловкости") }, api = {} }
			G.items.devgloves = { info = { 15063, "INVTYPE_HAND", 4, 2 }, setID = 143, lines = { ln("Рукавицы девизавра"), ln("Кисти рук", "Кожа"), ln("+18 к ловкости") }, api = {} }
			G.equippedLinks[7], G.equippedLinks[10] = "devlegs", "devgloves"
			-- live hit: 1% from rating plus the set's 2% (an aura: the hit modifier)
			G.GetRangedHitModifier = function() return 2 end
			local ns = loadAll(G)
			T.eq(ns.Items.Get("devlegs").setID, 143); T.eq(ns.Items.Get("helm").setID, nil)
			local st = ns.Advisor.State()
			T.near(st.snap.liveHit, 3, 1e-9); T.near(st.snap.gearHit, 0, 1e-9); T.near(st.snap.setHit, 2, 1e-9)
			T.near(st.ctx.baseHit, 1, 1e-9, "3% live - 2% from the worn set")
			-- taking the gloves off breaks the pair: the 2% hit goes with them
			local gloves = ns.Advisor.Evaluate("gloves")
			local W2 = st.W
			local agiLoss = 18 * W2.AGI
			local expected = 24 * W2.AP + 21 * W2.AP_VS_BEAST - agiLoss - 2 * W2.HIT
			T.near(gloves.delta, expected, 1e-6, "the pair's 2% hit is lost")
		end },
		{ "set: the tooltip names pieces worn, bonuses counted and not counted; unknown bonuses join the note", function()
			local G = env()
			local W = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W, rightColor = W } end
			G.items.viperchest = { info = { 6473, "INVTYPE_CHEST", 4, 2 }, setID = 162, lines = { ln("Доспех Клыка"), ln("Грудь", "Кожа") }, api = {} }
			G.items.vipergloves = { info = { 10413, "INVTYPE_HAND", 4, 2 }, setID = 162, lines = { ln("Перчатки Клыка"), ln("Кисти рук", "Кожа") }, api = {} }
			G.items.viperbelt = { info = { 10412, "INVTYPE_WAIST", 4, 2 }, setID = 162, lines = { ln("Пояс Клыка"), ln("Пояс", "Кожа"),
				ln("Комплект (4 предмета): Получение урона при низком здоровье восстанавливает здоровье и ману.") }, api = {} }
			G.items.oddbelt = { info = { 50, "INVTYPE_WAIST", 4, 2 }, setID = 99999, lines = { ln("Странный пояс"), ln("Пояс", "Кожа"),
				ln("Комплект: +5 к ловкости."), ln("Комплект (3 предмета): +10 к силе атаки.") }, api = {} }
			G.equippedLinks[5], G.equippedLinks[10] = "viperchest", "vipergloves"
			table.insert(G.bags[0], "viperbelt")
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local res = ns.Advisor.Evaluate("viperbelt", { kind = "bag", bag = 0, slot = #G.bags[0] })
			T.near(res.delta, 10 * st.W.AP, 1e-9, "the third piece adds the 3-piece +10 attack power, nothing else")
			local lines = ns.Advisor.Explain("viperbelt", { kind = "bag", bag = 0, slot = #G.bags[0] })
			local texts, setText = {}, nil
			for i, l in ipairs(lines) do
				texts[i] = l[1]
				if l[1]:find("^HGA: комплект") then setText = l[1] end
			end
			local all = table.concat(texts, "\n")
			T.eq(setText, "HGA: комплект: надето 2, с этой вещью 3; учтены бонусы (2), (3); не учитываются (4), (5)")
			T.truthy(all:find("HGA: эффекты не учтены: 2 %(смотри сам%)"), all)
			-- a set HGA has no data for: its tooltip set lines are not counted
			local odd = {}
			for i, l in ipairs(ns.Advisor.Explain("oddbelt")) do odd[i] = l[1] end
			local oddAll = table.concat(odd, "\n")
			T.truthy(oddAll:find("HGA: комплект неизвестен HGA"), oddAll)
			T.truthy(oddAll:find("HGA: эффекты не учтены: 2 %(смотри сам%)"), oddAll)
		end },
		{ "set: a profession set (Blood Tiger Harness, Leatherworking 300) counts only at the required rank", function()
			-- Blood Tiger Harness 442: ItemSet RequiredSkill 165 (Leatherworking), RequiredSkillRank 300; 2 pieces: 7597
			-- +1% crit and 18384 +1% spell crit. info: the Leatherworking line's SkillLineAttributes (nil: not learned).
			local function run(info)
				local G = env()
				local W = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = W, rightColor = W } end
				G.items.tigerchest = { info = { 19688, "INVTYPE_CHEST", 4, 2 }, setID = 442, lines = { ln("Кираса кровавого тигра"), ln("Грудь", "Кожа") }, api = {} }
				G.items.tigershoulders = { info = { 19689, "INVTYPE_SHOULDER", 4, 2 }, setID = 442, lines = { ln("Наплечники кровавого тигра"), ln("Плечи", "Кожа") }, api = {} }
				G.equippedLinks[5] = "tigerchest"
				local skillInfo = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 165 then return info end
					return skillInfo(id)
				end
				local ns = loadAll(G)
				local st = ns.Advisor.State()
				local res = ns.Advisor.Evaluate("tigershoulders")
				local setText
				for _, l in ipairs(ns.Advisor.Explain("tigershoulders")) do
					if l[1]:find("^HGA: комплект") then setText = l[1] end
				end
				return res.delta, st.W, setText
			end
			local d1, W1, t1 = run({ rank = 300, maxRank = 300, modifier = 0 })
			T.near(d1, W1.CRIT, 1e-9, "rank 300: the pair gives 1% crit")
			-- the two bonus spells at 2 pieces are one threshold on the line
			T.eq(t1, "HGA: комплект: надето 1, с этой вещью 2; учтены бонусы (2)")
			local d2, _, t2 = run({ rank = 299, maxRank = 300, modifier = 0 })
			T.near(d2, 0, 1e-9, "rank 299: nothing")
			T.eq(t2, "HGA: комплект: надето 1, с этой вещью 2; бонусы только с профессией комплекта на 300 — у тебя 299")
			local d3, W3 = run({ rank = 295, maxRank = 300, modifier = 5 })
			T.near(d3, W3.CRIT, 1e-9, "rank 295 + modifier 5 reaches 300 (the skill the Skills frame computes)")
			local d0, _, t0 = run(nil)
			T.near(d0, 0, 1e-9, "not learned: nothing")
			T.eq(t0, "HGA: комплект: надето 1, с этой вещью 2; бонусы только с профессией комплекта на 300 — она не изучена")
			-- a line with rank 0 and maxRank 0 is not learned either (Player.HasSkill's rule)
			local dz, _, tz = run({ rank = 0, maxRank = 0, modifier = 0 })
			T.near(dz, 0, 1e-9, "rank 0 / maxRank 0: nothing")
			T.eq(tz, "HGA: комплект: надето 1, с этой вещью 2; бонусы только с профессией комплекта на 300 — она не изучена")
		end },
		{ "set: a worn profession set's hit and ranged skill count only at the required rank (Snapshot, A.State)", function()
			-- made-up set 99001 (Leatherworking 165 at rank 300; 2 pieces: +1% hit and +5 Bows), both pieces worn with the
			-- bow (Bows 215, live hit 1%): at rank 300 the snapshot takes the set's 1% out of the base hit and A.State its
			-- 5 points out of the trained Bows skill; at rank 299 the set gives nothing
			local function run(rank)
				local G = env()
				local W1 = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
				G.items.lwchest = { info = { 99101, "INVTYPE_CHEST", 4, 2 }, setID = 99001, lines = { ln("Кожаный нагрудник"), ln("Грудь", "Кожа") }, api = {} }
				G.items.lwshoulders = { info = { 99102, "INVTYPE_SHOULDER", 4, 2 }, setID = 99001, lines = { ln("Кожаные наплечники"), ln("Плечи", "Кожа") }, api = {} }
				G.equippedLinks[5], G.equippedLinks[3] = "lwchest", "lwshoulders"
				local skillInfo = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 165 then return { rank = rank, maxRank = 300, modifier = 0 } end
					return skillInfo(id)
				end
				local ns = loadAll(G)
				ns.SetData[99001] = { name = "made-up", skill = 165, skillRank = 300, { n = 2, stats = { HIT = 1, SKILL_BOWS = 5 } } }
				ns.Advisor.Reset()
				return ns.Advisor.State()
			end
			local st300 = run(300)
			T.near(st300.snap.setHit, 1, 1e-9, "rank 300: the set's 1% hit is in the live hit")
			T.near(st300.ctx.baseHit, 0, 1e-9, "rank 300: 1% live less the set's 1%")
			T.eq(st300.rangedSkill.skill, 210, "rank 300: Bows 215 less the set's 5")
			local st299 = run(299)
			T.near(st299.snap.setHit, 0, 1e-9, "rank 299: no set hit")
			T.near(st299.ctx.baseHit, 1, 1e-9, "rank 299: the live 1% is base hit")
			T.eq(st299.rangedSkill.skill, 215, "rank 299: the set's Bows do not count")
		end },
		{ "set: setID 0 is no set; a set without bonuses says so", function()
			local G = env()
			local W = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W, rightColor = W } end
			-- the client gives 0 at return 16 for an item outside any set (ItemSparse.ItemSet 0)
			G.items.newhelm.setID = 0
			-- Goliaths' Adaptive Garments 1969: an ItemSet row without ItemSetSpell rows (item 251769)
			G.items.goliath = { info = { 251769, "INVTYPE_WAIST", 4, 2 }, setID = 1969, lines = { ln("Пояс Голиафа"), ln("Пояс", "Кожа") }, api = {} }
			table.insert(G.bags[0], "goliath")
			local ns = loadAll(G)
			T.eq(ns.Items.Get("newhelm").setID, nil, "setID 0 is no set")
			for _, l in ipairs(ns.Advisor.Explain("newhelm", { kind = "bag", bag = 0, slot = 5 })) do
				T.truthy(not l[1]:find("комплект"), "no set line for an item outside any set: " .. l[1])
			end
			local setText
			for _, l in ipairs(ns.Advisor.Explain("goliath", { kind = "bag", bag = 0, slot = #G.bags[0] })) do
				if l[1]:find("^HGA: комплект") then setText = l[1] end
			end
			T.eq(setText, "HGA: комплект: надето 0, с этой вещью 1; у комплекта нет бонусов")
		end },
		{ "items: cached item data with an empty GetItemInfo is not loaded yet (requested, nil)", function()
			local G = env()
			local W = { r = 1, g = 1, b = 1 }
			G.items.halfloaded = { info = { 77, "INVTYPE_HEAD", 4, 2 }, lines = { { leftText = "Шлем", leftColor = W }, { leftText = "Голова", leftColor = W } }, api = {} }
			local requested = {}
			G.C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
			local info = G.C_Item.GetItemInfo
			G.C_Item.GetItemInfo = function(idOrLink)
				if idOrLink == "halfloaded" or idOrLink == 77 then return nil end
				return info(idOrLink)
			end
			local ns = loadAll(G)
			T.eq(G.C_Item.IsItemDataCachedByID(77), true)
			T.eq(ns.Items.Get("halfloaded"), nil, "no record while GetItemInfo is empty")
			T.eq(#requested, 1); T.eq(requested[1], 77, "the item data is requested")
		end },

		-- stats-gear-2: weapon skill of a ranged weapon of another type (skill = rank + modifier), by wowsims' attack table
		-- (Model.SkillMiss: 0.1% miss a point of the gap up to 10 points, 0.2% a point of the whole gap past it; the crit
		-- suppression 0.2% a point below the level's maximum, none above it; raid-mode W1 design 3.3)
		{ "stats-gear-2: a gun with less skill than the worn bow loses hit and crit by wowsims' table; the tooltip says so", function()
			local function run(gunRank, bowOwnSkill)
				local G = env()
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					-- the worn bow's own skill bonus is in the bows line's modifier, as the client counts worn gear
					if id == 45 then return { rank = 215, maxRank = 215, modifier = bowOwnSkill or 0 } end
					if id == 46 then return { rank = gunRank, maxRank = 215, modifier = 0 } end
					return base(id)
				end
				if bowOwnSkill then
					table.insert(G.items.bow.lines, { leftText = "Если на персонаже: повышение навыка владения луком на " .. bowOwnSkill .. ".",
						leftColor = { r = 1, g = 1, b = 1 } })
				end
				G.bags[0] = { "gun" }
				local ns = loadAll(G)
				local where = { kind = "bag", bag = 0, slot = 1 }
				local r = ns.Advisor.Evaluate("gun", where)
				local texts = {}
				for i, l in ipairs(ns.Advisor.Explain("gun", where)) do texts[i] = l[1] end
				return r, table.concat(texts, "\n"), ns.Advisor.State(), ns
			end
			local full, fullText, st = run(215)
			local low, lowText = run(195)
			-- level 43 (215): the gun at 195 is the gap 20, 9% miss against the level's 5%: the shots' -4% at the live 1% hit
			-- (under the cap) and 20 points of crit suppression (my arithmetic)
			T.near(full.delta - low.delta, 4 * st.W.HIT_RANGED + 20 * st.W.SKILL_CRIT, 1e-6, "20 points: 4% of the shots' hit and 20 points of skill crit")
			T.eq(fullText:find("навык"), nil, "equal skill: no skill line")
			T.truthy(lowText:find("HGA: навык Ружья 195/215 (против надетого) — меткость выстрелов -4.0%, крит выстрелов -4.0% (по правилу wowsims)", 1, true), lowText)
			-- the worn bow's own +5 Bows: Score.SetValue measures each set's ranged skill against the worn set's, so
			-- the gun loses those 5 points once, not twice. The worn bow at 220 moves the model point (A.State: p.rangedSkill
			-- 5, the shots' hit + 0.5%), so the gun is priced in that state's own terms: its weapons through the model, the
			-- bow's +5 Agility, and the shots' 0.5%; above the level's maximum no crit
			T.near(full.delta, st.ctx.weaponGain(full.newSet) - 5 * st.W.AGI, 1e-9, "equal skill: the weapons and the Agility")
			local own, ownText, st5 = run(215, 5)
			T.eq(st5.W.SKILL_BOWS, nil, "no linear skill weight")
			T.near(st5.ctx.baseHit, 1, 1e-12, "the base hit keeps the live 1%")
			T.near(own.delta, st5.ctx.weaponGain(own.newSet) - 5 * st5.W.AGI - 0.5 * st5.W.HIT_RANGED, 1e-9,
				"5 points of the worn bow's own bonus, once")
			T.truthy(ownText:find("HGA: навык Ружья 215/220 (против надетого) — меткость выстрелов -0.5%, крит выстрелов +0.0% (по правилу wowsims)", 1, true), ownText)
		end },
		-- At level 60 the tooltip prices the skill against the raid boss, the model point's +3 (Player.Snapshot): a gun at 296
		-- against the worn bow's 300, the gap 19, past 10 points: 8.8% miss against 8% (-0.8%, where +0 gives -0.4%) and 4
		-- points of crit suppression, -0.8% (my arithmetic). Mutant: the tooltip's skill hit at +0
		{ "stats-gear-2: at 60 the gun's skill line is priced against the raid boss's +3", function()
			local G = env()
			G.UnitLevel = function() return 60 end
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 45 then return { rank = 300, maxRank = 300, modifier = 0 } end
				if id == 46 then return { rank = 296, maxRank = 300, modifier = 0 } end
				return base(id)
			end
			G.bags[0] = { "gun" }
			local ns = loadAll(G)
			T.eq(ns.Advisor.State().model.mobDiff, 3)
			local texts = {}
			for i, l in ipairs(ns.Advisor.Explain("gun", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
			local text = table.concat(texts, "\n")
			T.truthy(text:find("HGA: навык Ружья 296/300 (против надетого) — меткость выстрелов -0.8%, крит выстрелов -0.8% (по правилу wowsims)", 1, true), text)
		end },
		{ "stats-gear-2: the swap plan prices a bag gun with its weapon skill", function()
			local function plan(gunRank)
				local G = env()
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 45 then return { rank = 215, maxRank = 215, modifier = 0 } end
					if id == 46 then return { rank = gunRank, maxRank = 215, modifier = 0 } end
					return base(id)
				end
				G.bags[0] = { "gun" }
				local ns = loadAll(G)
				local rows = ns.Advisor.Plan().rows
				for _, row in ipairs(rows) do
					if row.slot == 18 then return row end
				end
			end
			local row = plan(215)
			T.truthy(row and row.new.link == "gun", "equal skill: the 24 DPS gun is planned")
			T.eq(row.new.where.bag, 0, "the planned piece keeps its bag position")
			T.eq(plan(1), nil, "214 points short: the gap 214, the shots' -42.8% and 42.8% crit suppression (my arithmetic), the gun stays in the bag")
		end },
		-- ranged weapon skill bonuses on gear (Score.SetValue, Advisor rangedSkillPiece); the fixture strings are
		-- TOOLTIP_ITEM_STAT_SKILL_GUNS_INCREASE / _BOWS_INCREASE
		{ "stats-gear-2: a gun's own +Guns and worn items' +Guns / +Bows count once; at the worn bow's skill no skill line", function()
			local GUNS = "Если на персонаже: повышение навыка владения огнестрельным оружием на %d."
			local BOWS = "Если на персонаже: повышение навыка владения луком на %d."
			local function run(gunRank, gunBonus, gloveGuns, gloveBows)
				local G = env()
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					-- the worn gear's skill bonuses are in their line's modifier, as the client counts worn gear
					if id == 45 then return { rank = 215 - (gloveBows or 0), maxRank = 215, modifier = gloveBows or 0 } end
					if id == 46 then return { rank = gunRank, maxRank = 215, modifier = gloveGuns or 0 } end
					return base(id)
				end
				local Wc = { r = 1, g = 1, b = 1 }
				if gunBonus then table.insert(G.items.gun.lines, { leftText = GUNS:format(gunBonus), leftColor = Wc }) end
				if gloveGuns then table.insert(G.items.gloves.lines, { leftText = GUNS:format(gloveGuns), leftColor = Wc }) end
				if gloveBows then table.insert(G.items.gloves.lines, { leftText = BOWS:format(gloveBows), leftColor = Wc }) end
				G.bags[0] = { "gun" }
				local ns = loadAll(G)
				local where = { kind = "bag", bag = 0, slot = 1 }
				local r = ns.Advisor.Evaluate("gun", where)
				local texts = {}
				for i, l in ipairs(ns.Advisor.Explain("gun", where)) do texts[i] = l[1] end
				return r, table.concat(texts, "\n"), ns
			end
			local plain, plainText = run(215)
			T.eq(plainText:find("навык"), nil, "215 against 215: no skill line")
			-- 210 trained and the gun's own +5 Guns: the bow's 215
			local own, ownText, ns = run(210, 5)
			T.eq(ns.Items.Get("gun").stats.SKILL_GUNS, 5)
			T.near(own.delta, plain.delta, 1e-9, "its own +5 makes up the 5 trained points, once")
			T.eq(ownText:find("навык"), nil, "215 against 215: no skill line")
			-- worn gloves with +3 Guns: 212 trained, the guns line shows 215; the gloves stay on with the gun
			local gl, glText = run(212, nil, 3)
			T.near(gl.delta, plain.delta, 1e-9, "212 trained and the gloves' 3: 215, counted once")
			T.eq(glText:find("навык"), nil, "215 against 215: no skill line")
			-- worn gloves with +3 Bows: the worn bows line shows 215 of 212 trained; with the gun the gloves' Bows
			-- count nothing, so the 215-trained gun is the worn line's equal
			local gb, gbText = run(215, nil, nil, 3)
			T.near(gb.delta, plain.delta, 1e-9, "the worn reference leaves out the gloves' +3 Bows too")
			T.eq(gbText:find("навык"), nil, "215 against 215: no skill line")
		end },
		{ "stats-gear-2: a bag bow's own +Bows counts once, through the capped hit; a bow of the worn type has no skill line", function()
			local function run(hitRating)
				local G = env()
				G.GetCombatRatingBonus = function() return hitRating end
				local lines = {}
				for i, l in ipairs(G.items.bow.lines) do lines[i] = l end
				lines[#lines + 1] = { leftText = "Если на персонаже: повышение навыка владения луком на 5.", leftColor = { r = 1, g = 1, b = 1 } }
				G.items.bow5 = { info = { 62, "INVTYPE_RANGED", 2, 2 }, lines = lines, api = G.items.bow.api }
				G.bags[0] = { "bow5" }
				local ns = loadAll(G)
				local where = { kind = "bag", bag = 0, slot = 1 }
				local r = ns.Advisor.Evaluate("bow5", where)
				local texts = {}
				for i, l in ipairs(ns.Advisor.Explain("bow5", where)) do texts[i] = l[1] end
				return r, table.concat(texts, "\n"), ns.Advisor.State()
			end
			-- the worn bow's copy with +5 Bows: the same weapon, 5 more skill points over the level's maximum (220 of 215): the
			-- gap -5, 0.5% of the shots' hit (Model.SkillHit(0, 5)) and no crit above the maximum
			local under, text, st = run(1)
			T.near(under.delta, 0.5 * st.W.HIT_RANGED, 1e-9, "1% hit: 0.5% of the shots' hit, once")
			T.eq(text:find("навык"), nil, "a bow of the worn type: no skill line")
			local over = run(9)
			T.near(over.delta, 0, 1e-9, "9% hit, past the 5% cap: nothing")
		end },
		{ "stats-gear-2: with no ranged weapon worn a gun is measured against 5 skill points a level; the tooltip says so", function()
			local function run(gunRank)
				local G = env()
				G.equippedLinks[18] = nil
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 46 then return { rank = gunRank, maxRank = 215, modifier = 0 } end
					return base(id)
				end
				G.bags[0] = { "gun" }
				local ns = loadAll(G)
				local where = { kind = "bag", bag = 0, slot = 1 }
				local r = ns.Advisor.Evaluate("gun", where)
				local texts = {}
				for i, l in ipairs(ns.Advisor.Explain("gun", where)) do texts[i] = l[1] end
				return r, table.concat(texts, "\n"), ns.Advisor.State()
			end
			-- level 43: 5 x 43 = 215
			local at, atText, st = run(215)
			T.eq(st.rangedSkill.line, nil); T.eq(st.rangedSkill.skill, 215); T.eq(st.rangedSkill.shown, 215)
			T.eq(atText:find("навык"), nil, "215 against 215: no skill line")
			local low, lowText = run(200)
			-- the weights come from the worn set (A.State): with no ranged weapon worn the model casts no shot, so the
			-- shots' own hit has no value there and the skill's crit reaches the pet, the dive and the hawks alone
			T.eq(st.W.HIT_RANGED, 0, "no shots in the worn model")
			T.truthy(st.W.SKILL_CRIT > 0, "the pet, the dive and the hawks take the skill's crit")
			-- 200 of 215: the gap 15, 8% miss, the shots' -3%, 15 points of crit suppression (my arithmetic)
			T.near(at.delta - low.delta, 3 * st.W.HIT_RANGED + 15 * st.W.SKILL_CRIT, 1e-6, "15 points under the level's 215")
			T.truthy(lowText:find("HGA: навык Ружья 200/215 (против навыка уровня) — меткость выстрелов -3.0%, крит выстрелов -3.0% (по правилу wowsims)", 1, true), lowText)
		end },
		{ "errors: no skill info for a weapon line; a ranged item without a skill line, worn or not", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			-- weapon subclass 14 (Miscellaneous) has no skill line (Player WEAPON_SKILL)
			G.items.oddranged = { info = { 63, "INVTYPE_RANGED", 2, 14 }, lines = { ln("Странное оружие"), ln("Дальний бой", "Разное"),
				ln("Урон: 40-70", "Скорость 2,60"), ln("(21,2 ед. урона в секунду)") }, api = {} }
			local ns = loadAll(G)
			local ok, err = pcall(ns.Player.WeaponSkill, 54) -- maces: the stub's client has no such line (a hunter learns none)
			T.eq(ok, false); T.truthy(tostring(err):find("no skill info for weapon skill line 54", 1, true), tostring(err))
			ok, err = pcall(ns.Advisor.Evaluate, "oddranged", { kind = "new" })
			T.eq(ok, false); T.truthy(tostring(err):find("ranged item without a weapon skill line", 1, true), tostring(err))
			G.equippedLinks[18] = "oddranged"
			ns.Advisor.Reset()
			ok, err = pcall(ns.Advisor.State)
			T.eq(ok, false); T.truthy(tostring(err):find("worn ranged item without a weapon skill line", 1, true), tostring(err))
		end },
		-- ranged-slot items of other item classes than 2 (Forever Item.csv build 70888: Egan's Blaster 13289 class 12,
		-- Replica Ironforge Air Rifle 281060 class 15 subclass 4, both InventoryType 26): no weapon, no skill line
		{ "a ranged-slot item that is no weapon: in the bags the plan settles and the tooltip works; worn, A.State builds", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			G.items.blaster = { info = { 13289, "INVTYPE_RANGEDRIGHT", 12, 0 }, lines = { ln("Бластер Игана"), ln("Дальний бой") }, api = {} }
			G.items.airrifle = { info = { 281060, "INVTYPE_RANGEDRIGHT", 15, 4 }, lines = { ln("Replica Ironforge Air Rifle"), ln("Дальний бой") }, api = {} }
			G.bags[0] = { "blaster", "airrifle" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local plan = ns.Advisor.Plan()
			T.truthy(plan, "the plan settles")
			for _, row in ipairs(plan.rows) do T.truthy(row.slot ~= 18, "the bow stays") end
			-- no bow, gun or crossbow: every shot goes (Model noShots), the bow's +5 Agility too
			local bare = ns.Score.CopySet(st.snap.equipped); bare[18] = nil
			for i, link in ipairs({ "blaster", "airrifle" }) do
				local where = { kind = "bag", bag = 0, slot = i }
				local r = ns.Advisor.Evaluate(link, where)
				T.eq(r.usable, true); T.eq(r.slot, 18); T.eq(r.skillGap, nil, link .. ": no skill line")
				T.near(r.delta, st.ctx.weaponGain(bare) - 5 * st.W.AGI, 1e-9, link .. ": the full loss of the bow")
				local texts = {}
				for j, l in ipairs(ns.Advisor.Explain(link, where)) do texts[j] = l[1] end
				local text = table.concat(texts, "\n")
				T.truthy(text:find("HGA: хуже надетого"), text); T.eq(text:find("навык"), nil, text)
			end
			T.eq(#G.reportedErrors, 0)
			-- worn: the reference is the level's 5 points, as with no ranged weapon; a bag bow brings the shots back
			G.equippedLinks[18] = "blaster"
			G.bags[0] = { "newbow" }
			ns.Advisor.Reset()
			local worn = ns.Advisor.State()
			T.truthy(worn, "A.State builds")
			T.eq(worn.rangedSkill.line, nil); T.eq(worn.rangedSkill.shown, 215); T.eq(worn.rangedSkill.skill, 215)
			T.eq(worn.ctx.skillBase, 0); T.eq(worn.model.rangedSkill, 0); T.eq(worn.model.rangedHit, 0); T.eq(worn.snap.model.noShots, true)
			T.eq(worn.ctx.weaponGain(worn.snap.equipped), 0, "the worn set: exactly 0")
			local bow = ns.Advisor.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(bow.skillGap, nil, "the bows line at 215 against the level's 215")
			T.truthy(bow.isUpgrade and bow.delta > 50, "the bow's shots: " .. tostring(bow.delta))
			T.truthy(ns.Advisor.Plan(), "the plan settles with the blaster worn")
		end },
		-- the worn ranged skill against the level's 5 points a level, the skill the hit cap is at, by wowsims' table
		-- (Model.SkillHit): A.State's p.rangedSkill and p.rangedHit, Score's ctx.skillBase
		{ "worn bow skill below or above 5 points a level moves the room under the hit cap", function()
			local function run(rank, modifier, ownBows)
				local G = env()
				G.GetCombatRatingBonus = function() return 5 end -- the 5% cap on the sheet
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 45 then return { rank = rank, maxRank = 215, modifier = modifier } end
					return base(id)
				end
				local BOWS = { leftText = "Если на персонаже: повышение навыка владения луком на 5.", leftColor = { r = 1, g = 1, b = 1 } }
				local plain = {}
				for i, l in ipairs(G.items.bow.lines) do plain[i] = l end
				local five = {}
				for i, l in ipairs(G.items.bow.lines) do five[i] = l end
				five[#five + 1] = BOWS
				-- the worn bow with or without its own +5 Bows; the bag holds the other one
				G.items.bow.lines = ownBows and five or plain
				G.items.otherbow = { info = { 62, "INVTYPE_RANGED", 2, 2 }, lines = ownBows and plain or five, api = G.items.bow.api }
				G.bags[0] = { "otherbow" }
				local ns = loadAll(G)
				return ns.Advisor.Evaluate("otherbow", { kind = "bag", bag = 0, slot = 1 }), ns.Advisor.State()
			end
			-- level 43 (5 x 43 = 215), a worn plain bow at 195: the gap 20, the shots 4% short of the cap (9% miss), so +5
			-- Bows (the gap 15, 8%) adds 1% of their hit and 5 points of skill crit
			local up, st = run(195, 0, false)
			T.eq(st.ctx.skillBase, -20); T.eq(st.model.rangedSkill, -20); T.near(st.model.rangedHit, -4, 1e-12)
			T.near(up.delta, st.W.HIT_RANGED + 5 * st.W.SKILL_CRIT, 1e-9, "+5 Bows under the shots' cap: 1% of their hit and 5 points of skill crit")
			-- a worn bow with its own +5 Bows at 220 (215 trained): a bow without it is at 215, still at the cap, and no crit
			-- above the level's maximum
			local down, st2 = run(215, 5, true)
			T.eq(st2.ctx.skillBase, 0); T.eq(st2.model.rangedSkill, 5); T.near(st2.model.rangedHit, 0.5, 1e-12)
			T.near(down.delta, 0, 1e-9, "without the +5 Bows: nothing")
		end },
		{ "no bow, gun or crossbow: taking the bow off loses every shot; a held-in-off-hand weapon-class item is no weapon", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			-- Frying Pan 280317: Item.csv class 2, subclass 14, InventoryType 23 (held in off hand), ItemSparse ItemDelay
			-- 2000; the fixture carries no weapon lines
			G.items.pan = { info = { 280317, "INVTYPE_HOLDABLE", 2, 14 }, lines = { ln("Frying Pan"), ln("Левая рука", "Разное") }, api = {} }
			-- Heavy Throwing Dagger 3108: Item.csv class 2, subclass 16 (Thrown), InventoryType 25; ItemSparse ItemDelay 2100,
			-- ItemLevel 27, quality 1, DmgVariance 0.6: ItemDamageThrown 11.64 DPS, 24.5 average damage
			G.items.throwing = { info = { 3108, "INVTYPE_THROWN", 2, 16 }, lines = { ln("Heavy Throwing Dagger"),
				ln("Метательное", "Метательное оружие"), ln("Урон: 17-32", "Скорость 2,10"), ln("(11,6 ед. урона в секунду)") }, api = {} }
			local ns = loadAll(G)
			local P = ns.Player
			local function pc(link) return ns.Items.Piece(ns.Items.Get(link), { kind = "new" }) end
			local held = P.WeaponInputs({ [16] = pc("sword"), [17] = pc("pan"), [18] = pc("bow") })
			T.eq(held.ohDPS, 0); T.eq(held.ohSpeed, 2.6, "a class-2 held-in-off-hand item: no weapon")
			T.eq(held.noShots, false, "a bow shoots")
			T.eq(P.WeaponInputs({ [18] = pc("gun") }).noShots, false, "a gun shoots")
			T.eq(P.WeaponInputs({}).noShots, true, "an empty ranged slot")
			local thrown = P.WeaponInputs({ [18] = pc("throwing") })
			T.eq(thrown.noShots, true, "a thrown weapon is a weapon, but no bow, gun or crossbow")
			T.near(thrown.bowDPS, 11.6, 1e-9); T.near(thrown.bowSpeed, 2.1, 1e-9)
			local st = ns.Advisor.State()
			T.eq(st.snap.model.noShots, false)
			local bare = ns.Score.CopySet(st.snap.equipped); bare[18] = nil
			local g = st.ctx.weaponGain(bare)
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			p.bowDPS, p.bowSpeed, p.noShots = 0, 2.6, true
			T.eq(g, (ns.Model.Total(p) - st.total) / st.unitDps, "no ranged weapon: 0 DPS at 2.6 s, no shots")
			local worn = ns.Model.Parts(st.model)
			local shots = worn.auto + worn.aimed + worn.multi + worn.arcane + worn.serpent + worn.sniper
			T.truthy(shots > 0 and g <= -shots / st.unitDps + 1e-9, string.format("every shot lost: %.2f vs %.2f", g, -shots / st.unitDps))
		end },
		-- stats-gear-4: Heartseeking Crossbow 13040 (equip trigger, spell 29626), measured at 2.7 a minute (EV-0119)
		{ "stats-gear-4: Heartseeking Crossbow's equip proc scores at its measured rate on its own shots, no Serpent Sting application; the tooltip says so", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function crossbow(id, name, extra)
				local lines = { ln(name), ln("Дальний бой", "Арбалет"), ln("Урон: 40-70", "Скорость 2,60"), ln("(21,2 ед. урона в секунду)") }
				if extra then lines[#lines + 1] = ln(extra) end
				return { info = { id, "INVTYPE_RANGEDRIGHT", 2, 18 }, lines = lines, api = {} }
			end
			G.items.heart = crossbow(13040, "Арбалет сердцееда", "Если на персонаже: Шанс поразить отдаленную цель стрелой Тьмы и нанести ей 13 - 19 ед. урона от темной магии.")
			G.items.plaincrossbow = crossbow(60001, "Арбалет")
			G.bags[0] = { "heart", "plaincrossbow" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local heart = ns.Advisor.Evaluate("heart", { kind = "bag", bag = 0, slot = 1 })
			local plain = ns.Advisor.Evaluate("plaincrossbow", { kind = "bag", bag = 0, slot = 2 })
			-- the landed hits of the crossbow's own set (A.State: ctx.landedHitsFor, the model point with that set's weapons):
			-- its Auto Shots and special shots at its own 2.6 s; its equip trigger is an equip aura (Parse proc.equip), which
			-- no hit without damage rolls, so Serpent Sting's applications take no part (EV-0021 lines 18-19 and 41-47; wowsims
			-- sim/common/forever/items_weapons.go:207-223 registers 29626 without WeaponProc)
			T.eq(heart.hand, nil); T.eq(heart.slot, 18)
			T.eq(heart.rec.procs[1].equip, true, "the proc of an \"Если на персонаже:\" line")
			-- linked to Game/ProcData.lua's 13040 (29626 -> 29640: mask 320, ranged auto and abilities; chance 100, no stated
			-- rate: the measured 2.7; Shadow, SchoolMask 32; DefenseType 3, the ranged table)
			local hp = heart.rec.procs[1]
			T.eq(hp.linked, true); T.eq(hp.mask, 320); T.eq(hp.chance, 100); T.eq(hp.school, "magic"); T.eq(hp.schoolMask, 32)
			T.eq(hp.defense, 3); T.eq(hp.crit, true)
			local r = st.ctx.landedHitsFor(heart.newSet).ranged
			local q = {}
			for k, v in pairs(st.model) do q[k] = v end
			for k, v in pairs(ns.Player.WeaponInputs(heart.newSet)) do q[k] = v end
			local own = ns.Model.LandedHits(q).ranged
			for _, k in ipairs({ "swings", "specials", "casts", "speed" }) do T.eq(r[k], own[k], "the crossbow's set: " .. k) end
			T.eq(r.speed, 2.6)
			-- its Auto Shots (0x40) and ranged abilities (0x100: the special shots and the dives) at the crossbow's 2.6 s
			local perMinute = 2.7 * 2.6 * (r.swings + r.specials)
			T.truthy(r.swings > 0 and r.specials > 0 and r.casts > 0, "the crossbow shoots and stings")
			T.near(ns.Advisor.ModelProcRates(heart)[1], perMinute, 1e-12, "the tooltip's rate: the crossbow's own shots in its own set")
			-- 16 average damage, Shadow (no armor) on the ranged table: the hit of p.hit alone, the melee crit
			T.near(heart.delta - plain.delta, 16 * procFactor(ns.Model, st.model, 3, "magic", true) * perMinute / 60 * st.W.EXTRA_DPS, 1e-9,
				"16 average damage, 2.7 a minute at 2.6 s, every shot, no sting, on the ranged table")
			local texts = {}
			for i, l in ipairs(ns.Advisor.Explain("heart", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
			local all = table.concat(texts, "\n")
			T.truthy(all:find(string.format("HGA: эффект при попадании учтён как оценка (2.70/мин на базовой скорости оружия — замер по логам; если надеть — ~%.2f/мин)",
				perMinute), 1, true), all)
			T.eq(all:find("эффекты не учтены"), nil, all)
		end },
		-- U4 = (a), as wowsims (no rate is made up, docs/rulings/R-0047): a weapon that shares a measured weapon's proc spell
		-- takes no rate of its own unless wowsims' override data gives one; it has no row for Skullforge Reaver 228542
		-- (tools/database/overrides/weapon_procs.go), so the reaver's proc is not priced at any speed, and its tooltip says its
		-- rate is unknown; it scores as the same sword without the proc. A rate of wowsims' override data (the Bow of Searing
		-- Arrows 2825: its WeaponProcs row 29638, 3.35 a minute, a carry-over) prices the proc, and its tooltip says the rate is
		-- carried over from classic, unchecked in Forever. The effect lines are made up to reach the tooltip's rate line (the
		-- real 17484 is a drain over time, which Parse's procDamage does not price)
		-- The tooltip names an override row's source (Advisor A.Explain; wowsims weapon_procs.go:13): a measurement «замер по
		-- логам (данные wowsims, EV-<n>)», Classic's rate «перенос из классики», The Burning Crusade's «перенос из TBC». The
		-- real rows: Blade of Eternal Darkness 17780 (21978: PPM 1.8 EV-0025, a 100 ms internal cooldown) and Darkmoon Card:
		-- Maelstrom 19289 (23686: PPM 1 tbc-carryover), each with an "Equip:" line Parse reads that links to its entry (17780's
		-- real text is a spell-cast trigger Parse does not read: the line and the weapon's numbers are the test's). An
		-- unpriced proc with no Game/ProcData.lua entry says only that its rate is unknown, not how its outcome would be priced
		{ "U4: a twin of a measured weapon takes no carried rate: not priced, its tooltip says the rate is unknown; a wowsims carry-over row prices a proc and says so", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function reaver(id, effect)
				local lines = { ln("Череполом"), ln("Одноручное", "Меч"), ln("Урон: 40-75", "Скорость 2,50"), ln("(23,0 ед. урона в секунду)") }
				if effect then lines[#lines + 1] = ln("Возможный эффект при попадании: Наносит цели 90 - 110 ед. урона от темной магии.") end
				return { info = { id, "INVTYPE_WEAPON", 2, 7 }, lines = lines, api = {} }
			end
			G.items.reaver, G.items.plainreaver = reaver(228542, true), reaver(99530, false)
			G.items.searing = { info = { 2825, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Лук обжигающих стрел"), ln("Дальний бой", "Лук"),
				ln("Урон: 40-70", "Скорость 2,60"), ln("(21,2 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 23 - 33 ед. урона от огня.") }, api = {} }
			G.items.eternal = { info = { 17780, "INVTYPE_WEAPON", 2, 15 }, lines = { ln("Клинок вечной тьмы"), ln("Одноручное", "Кинжал"),
				ln("Урон: 30-60", "Скорость 1,80"), ln("(25,0 ед. урона в секунду)"),
				ln("Если на персонаже: Атаки ближнего боя с некоторой вероятностью наносят 100 - 124 ед. урона от темной магии.") }, api = {} }
			G.items.maelstrom = { info = { 19289, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Карта Новолуния: Водоворот"), ln("Аксессуар"),
				ln("Если на персонаже: Вероятность поражения вашей цели в ближнем бою молнией с нанесением 200 - 300 ед. урона от сил природы.") }, api = {} }
			G.bags[0] = { "reaver", "plainreaver", "searing", "eternal", "maelstrom" }
			local ns = loadAll(G)
			local A = ns.Advisor
			local function explain(link, slot)
				local texts = {}
				for i, l in ipairs(A.Explain(link, { kind = "bag", bag = 0, slot = slot })) do texts[i] = l[1] end
				return table.concat(texts, "\n")
			end
			local r = A.Evaluate("reaver", { kind = "bag", bag = 0, slot = 1 })
			T.eq(r.hand, "mh"); T.eq(A.ModelProcRates(r)[1], 0, "the twin's proc: no rate")
			T.near(r.delta, A.Evaluate("plainreaver", { kind = "bag", bag = 0, slot = 2 }).delta, 1e-9, "the same sword without the proc")
			local text = explain("reaver", 1)
			T.truthy(text:find("HGA: частота эффекта при попадании не замерена — не учитывается (как в wowsims)", 1, true), text)
			T.eq(text:find("1.95", 1, true), nil, text); T.eq(text:find("двойник", 1, true), nil, text)
			T.eq(r.rec.procs[1].linked, false, "no Game/ProcData.lua entry for the twin")
			T.eq(text:find("не найден в данных DB2", 1, true), nil, "an unpriced proc names no outcome: " .. text)
			-- the carried-over rate of wowsims' row: the bow's own shots, its specials and Serpent Sting's applications at its
			-- 2.6 s (a chance on hit of the ranged hand)
			local sr = A.Evaluate("searing", { kind = "bag", bag = 0, slot = 3 })
			local proc = sr.rec.procs[1]
			T.eq(proc.linked, true); T.eq(proc.source, "vanilla-carryover"); T.eq(proc.ppm, 3.35)
			local own = ns.Score.LandedHitsOf(sr.newSet, A.State().ctx).ranged
			local rate = 3.35 * 2.6 * (own.swings + own.specials + own.casts)
			T.near(A.ModelProcRates(sr)[1], rate, 1e-12, "3.35 a minute at the bow's 2.6 s")
			local st = explain("searing", 3)
			T.truthy(st:find(string.format("HGA: эффект при попадании учтён как оценка (3.35/мин на скорости бьющей руки — перенос из классики (данные wowsims), в Forever не проверено; если надеть — ~%.2f/мин)",
				rate), 1, true), st)
			local et = explain("eternal", 4)
			T.eq(ns.Items.Get("eternal").procs[1].source, "EV-0025")
			T.truthy(et:find("(1.80/мин на скорости бьющей руки — замер по логам (данные wowsims, EV-0025), не чаще раза в 0.1 с;", 1, true), et)
			local ms = explain("maelstrom", 5)
			T.eq(ns.Items.Get("maelstrom").procs[1].source, "tbc-carryover")
			T.truthy(ms:find("(1.00/мин на скорости бьющей руки — перенос из TBC (данные wowsims), в Forever не проверено;", 1, true), ms)
			-- a source the overrides do not name is an error
			ns.Items.Get("maelstrom").procs[1].source = "estimate"
			T.eq(pcall(A.Explain, "maelstrom", { kind = "bag", bag = 0, slot = 5 }), false, "an unknown source")
			ns.Items.Get("maelstrom").procs[1].source = "tbc-carryover"
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- Highborne Research Tablet 260205 (Forever Item.csv class 4, InventoryType 12): its "Chance on hit" (spell 1318159,
		-- the ruRU Spell description "С некоторой вероятностью при попадании наносит $1265634s1 ед. урона от тайной магии"
		-- with 1265634's damage filled in: SpellEffect EffectBasePointsF 75, Variance 0.16, 69 to 81), linked to Game/ProcData.lua
		-- (an equip aura, chance 100: no stated rate), rolls the measured 2.6 a minute (EV-0021) at the speed of the hand that
		-- hits (wowsims NewLegacyPPMManagerWithSpells, Score.PROC_OVERRIDES); in the set it goes into, whose weapons are the
		-- worn ones, on the worn set's landed hits, without Serpent Sting's applications
		{ "procs: the Tablet's tooltip names the speed of the hand that hits and the rate at the model point; /hga dump lists the hits", function()
			local G = env()
			addTablet(G)
			G.bags[0] = { "tablet" }
			-- the worn bow's line at 205 of the level's 215 at a 1% sheet hit: its shots miss 1% more at the model point
			-- (A.State: p.rangedHit = Model.SkillHit(0, -10) = -1) than at the sheet's
			local skill = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 45 then return { rank = 205, maxRank = 215, modifier = 0 } end
				return skill(id)
			end
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.rangedSkill, -10); T.near(st.model.rangedHit, -1, 1e-12)
			local lh = st.ctx.landedHits
			local fromModel = ns.Model.LandedHits(st.model)
			for _, hand in ipairs({ "mh", "oh", "ranged" }) do
				for _, k in ipairs({ "swings", "specials", "speed" }) do
					T.eq(lh[hand][k], fromModel[hand][k], "A.State's landed hits: the model point's " .. hand .. " " .. k)
				end
			end
			-- the sheet's point: the live reading with the ranged skill at the level's (A.State adds rangedSkill and rangedHit)
			-- and the worn hands' melee skills (A.State's)
			local sheet = {}
			for k, v in pairs(st.snap.model) do sheet[k] = v end
			sheet.rangedHit, sheet.rangedSkill = 0, 0
			sheet.mhSkill, sheet.ohSkill, sheet.meleeHit = st.model.mhSkill, st.model.ohSkill, st.model.meleeHit
			T.truthy(lh.ranged.swings < ns.Model.LandedHits(sheet).ranged.swings, "the shots at the model point's hit, not the sheet's")
			-- the env's BM 26 / MM 2 build is no Survival branch, so it has no melee (Player.Snapshot,
			-- Player.SurvivalBranch): shots and no melee swing at the model point
			T.truthy(lh.ranged.swings > 0, "shots at the model point")
			T.eq(lh.mh.swings, 0, "no main-hand swing outside the Survival branch"); T.eq(lh.oh.swings, 0, "no off-hand swing")
			local rec = ns.Items.Get("tablet")
			T.eq(#rec.procs, 1); T.eq(rec.procs[1].avg, 75); T.eq(rec.procs[1].hits, "weapon")
			T.eq(rec.procs[1].linked, true); T.eq(rec.procs[1].mask, 65876); T.eq(rec.procs[1].defense, 1)
			T.truthy(lh.ranged.casts > 0, "the worn bow stings: no application rolls the Tablet")
			local perMinute = 0
			for _, hand in ipairs({ "mh", "oh", "ranged" }) do perMinute = perMinute + 2.6 * lh[hand].speed * (lh[hand].swings + lh[hand].specials) end
			local r = ns.Advisor.Evaluate("tablet", { kind = "bag", bag = 0, slot = 1 })
			T.eq(st.ctx.landedHitsFor(r.newSet), lh, "the Tablet's set: the worn weapons, the worn set's hits")
			local texts = {}
			for i, l in ipairs(ns.Advisor.Explain("tablet", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
			local text = table.concat(texts, "\n")
			T.truthy(text:find(string.format("HGA: эффект при попадании учтён как оценка (2.60/мин на скорости бьющей руки — замер по логам; если надеть — ~%.2f/мин)",
				perMinute), 1, true), text)
			T.eq(text:find("не найден в данных DB2", 1, true), nil, text)
			T.near(ns.Advisor.ModelProcRates(r)[1], perMinute, 1e-12)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump
			T.eq(d.landedHits, lh, "the dump: the model point's landed hits")
			T.eq(d.procOutcome, st.ctx.procOutcome, "the dump: the outcomes of the procs' tables")
			local bag = d.bags[1]
			T.near(bag.result.procsPerMinuteAtModel[1], perMinute, 1e-12, "the dump: the Tablet's procs a minute at the model point")
			T.eq(d.equipped["16"].result.procsPerMinuteAtModel, nil, "no proc: none listed")
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- A.ModelProcRates' second value for a bag item the evaluation places (res.newSet): the hits of the set it goes into,
		-- "newSet", worded "если надеть" (A.Explain RATE_HITS_TEXT), also when that set's hits are the worn set's (the Tablet
		-- changes no weapon)
		{ "procs: the Tablet from a bag goes into a set whose hits are the worn set's; its rate is named as that set's ('если надеть')", function()
			local G = env()
			addTablet(G)
			G.bags[0] = { "tablet" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local r = ns.Advisor.Evaluate("tablet", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(r.newSet ~= nil, "placed in a set")
			T.eq(st.ctx.landedHitsFor(r.newSet), st.ctx.landedHits, "that set's hits are the worn set's")
			local rates, hitsOf = ns.Advisor.ModelProcRates(r)
			T.eq(hitsOf, "newSet")
			local texts = {}
			for i, l in ipairs(ns.Advisor.Explain("tablet", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
			local text = table.concat(texts, "\n")
			T.truthy(text:find(string.format("если надеть — ~%.2f/мин)", rates[1]), 1, true), text)
			T.eq(text:find("сейчас ~", 1, true), nil, text)
		end },
		-- Each set's procs roll on the landed hits of that set's own model point (A.State ctx.landedHitsFor: the model point
		-- with the set's weapon inputs, the run ctx.weaponGain takes). A worn two-hander and two bag one-handers, the weaker
		-- with a chance-on-hit proc (made-up items: "proc sword" 1.8 s, 10 DPS, 190 - 210 damage; "slow sword" 5.0 s, 22 DPS,
		-- +10 Agility): in the Survival weave the pair's off hand swings where the slow main hand's swing timer holds the
		-- hunter in melee (Model weaveParts), so the proc sword's off-hand swings count, which the worn two-hander, swinging no
		-- off hand, has none of
		{ "procs: a proc weapon in the off hand of a pair, a two-hander worn: the pair's own off-hand hits at that weapon's speed", function()
			local G = env()
			survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.procsword = { info = { 99501, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Меч с эффектом"), ln("Одноручное", "Меч"),
				ln("Урон: 15-21", "Скорость 1,80"), ln("(10,0 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 190 - 210 ед. урона.") }, api = {} }
			G.items.slowsword = { info = { 99510, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Медленный меч"), ln("Одноручное", "Меч"),
				ln("Урон: 90-130", "Скорость 5,00"), ln("(22,0 ед. урона в секунду)"), ln("+10 к ловкости") }, api = {} }
			G.equippedLinks[16] = "staff"; G.equippedLinks[17] = nil
			G.ownerSpeed, G.ownerOffSpeed = 3.2, nil
			G.bags[0] = { "procsword", "slowsword" }
			G.measuredPPM = { [99501] = 1.5 }
			local ns = loadAll(G)
			local A, Sc = ns.Advisor, ns.Score
			local st = A.State()
			local ctx, W = st.ctx, st.W
			T.eq(ctx.landedHits.oh.swings, 0, "the worn two-hander swings no off hand")
			local function piece(link)
				for _, p in ipairs(st.snap.bagPieces) do if p.link == link then return p end end
			end
			local slow, procsword = piece("slowsword"), piece("procsword")
			-- the pair's own model point: the off hand at the proc sword's 1.8 s, dual wielding
			local set = Sc.CopySet(ctx.equipped)
			set[16], set[17] = slow, procsword
			local q = {}
			for k, v in pairs(st.model) do q[k] = v end
			for k, v in pairs(ns.Player.WeaponInputs(set)) do q[k] = v end
			local oh = ns.Model.LandedHits(q).oh
			T.eq(oh.speed, 1.8); T.truthy(oh.swings > 0, "the pair's off hand swings")
			T.eq(ctx.landedHitsFor(set).oh.swings, oh.swings, "the set's own hits")
			local rate = 1.5 * 1.8 * oh.swings
			T.near(Sc.ProcRate(procsword, "oh", procsword.procs[1], ctx.landedHitsFor(set), ctx), rate, 1e-12, "the pair's off-hand hits")
			-- the pair's value: the same pair with the proc taken off the proc sword, plus the proc at 200 average damage, unlinked
			-- (no Game/ProcData.lua entry): physical by its text, the melee table
			T.eq(procsword.procs[1].linked, false); T.eq(procsword.procs[1].school, "physical"); T.eq(procsword.procs[1].defense, 0)
			local noProc = Sc.CopySet(set); noProc[17] = setmetatable({ procs = {} }, { __index = procsword })
			T.near(Sc.SetValue(set, W, ctx), Sc.SetValue(noProc, W, ctx)
				+ 200 * procFactor(ns.Model, st.model, 0, "physical", true) * rate / 60 * W.EXTRA_DPS, 1e-9,
				"the proc on the pair's own off-hand hits")
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- A bag bow with a proc (the env's "new bow": 2.6 s, 22 - 34 damage) and no bow, gun or crossbow worn: the worn set casts
		-- no shot and no sting, the bow's own set does, and its proc rolls on that set's Auto Shots, special shots and Serpent
		-- Sting's applications at its own 2.6 s
		{ "procs: a bag bow's proc with no bow worn rolls on that bow's own shots and Serpent Sting's applications", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.plainnewbow = { info = { 60003, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Новый лук без эффекта"), ln("Дальний бой", "Лук"),
				ln("Урон: 50-80", "Скорость 2,60"), ln("(24,6 ед. урона в секунду)") }, api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 24.6 } }
			G.equippedLinks[18] = nil
			G.bags[0] = { "newbow", "plainnewbow" }
			G.measuredPPM = { [2] = 1.5 }
			local ns = loadAll(G)
			local A = ns.Advisor
			local st = A.State()
			local lh = st.ctx.landedHits
			-- no ranged weapon worn: no shot, no sting, the ranged hand's speed 0; the dives (two a 18 s) stay
			T.eq(lh.ranged.swings, 0); T.eq(lh.ranged.casts, 0, "no bow worn: no shot, no sting"); T.eq(lh.ranged.speed, 0)
			T.near(lh.ranged.specials, 2 / 18, 1e-15)
			local res = A.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 })
			local plain = A.Evaluate("plainnewbow", { kind = "bag", bag = 0, slot = 2 })
			T.eq(res.slot, 18); T.eq(plain.slot, 18)
			local q = {}
			for k, v in pairs(st.model) do q[k] = v end
			for k, v in pairs(ns.Player.WeaponInputs(res.newSet)) do q[k] = v end
			local r = ns.Model.LandedHits(q).ranged
			T.truthy(r.swings > 0 and r.specials > 0 and r.casts > 0, "the bow's own shots and stings")
			local rate = 1.5 * 2.6 * (r.swings + r.specials + r.casts)
			T.near(A.ModelProcRates(res)[1], rate, 1e-12, "the tooltip's rate")
			-- 28 average damage, unlinked (no Game/ProcData.lua entry): Fire by its text, the spell table
			T.eq(res.rec.procs[1].linked, false); T.eq(res.rec.procs[1].school, "magic")
			T.near(res.delta - plain.delta, 28 * procFactor(ns.Model, st.model, 0, "magic", true) * rate / 60 * st.W.EXTRA_DPS, 1e-9,
				"28 average damage on the bow's own hits")
			local texts = {}
			for i, l in ipairs(A.Explain("newbow", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
			local all = table.concat(texts, "\n")
			T.truthy(all:find(string.format("если надеть — ~%.2f/мин)", rate), 1, true), all)
			-- an unlinked proc says so, and that its outcome follows the school its text names
			T.truthy(all:find("HGA: эффект при попадании не найден в данных DB2 (Game/ProcData.lua): исход по школе урона из текста (оценка)", 1, true), all)
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- A bag two-hander with a melee equip proc (made-up: a 3.4 s staff, "Атаки ближнего боя с некоторой вероятностью
		-- наносят 200 - 300 ед. урона", Parse hits "melee") against the worn pair (the env's 2.6 s sword and 1.8 s off-hand
		-- sword): its own set swings no off hand and its white swings miss at the one-hand rate, not the dual-wield one
		{ "procs: a two-hander's melee proc, a pair worn: the two-hander's own set, no off-hand swings and no dual-wield miss", function()
			local G, ns, st, res = procStaffSetup()
			local A = ns.Advisor
			local m = st.model
			local worn = st.ctx.landedHits
			-- the one-hand white miss (the base miss less the model's hit), the dual-wield one 19% more, and the mob's dodge
			local miss = (ns.Model.HitCap(m.mobDiff) - m.hit) / 100
			local dodge = ns.Model.MobAvoid(m.mobDiff) / 100 - (m.expertise or 0) / 100
			-- the weave's white swings (Model.Weave, averaged over Rapid Fire): the worn pair's main hand at the dual-wield miss
			local wornRates = ns.Model.Weave(m).average.rates
			T.near(worn.mh.swings, wornRates.mhWhite * (1 - miss - 0.19 - dodge), 1e-12, "the worn pair: the dual-wield miss")
			T.eq(res.hand, "2h"); T.eq(res.oh, nil); T.eq(res.swapTo2H, true)
			local h = st.ctx.landedHitsFor(res.newSet)
			T.eq(h.oh.swings, 0, "no off-hand swing in the two-hander's set"); T.eq(h.mh.speed, 3.4)
			local q = {}
			for k, v in pairs(m) do q[k] = v end
			for k, v in pairs(ns.Player.WeaponInputs(res.newSet)) do q[k] = v end
			T.near(h.mh.swings, ns.Model.Weave(q).average.rates.mhWhite * (1 - miss - dodge), 1e-12, "no dual-wield miss")
			local rate = 1.5 * 3.4 * (h.mh.swings + h.mh.specials)
			T.near(A.ModelProcRates(res)[1], rate, 1e-12, "the tooltip's rate: the two-hander's own set")
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- the same staff's value: its own set with the proc taken off the staff, less the worn set, plus the proc at 250
		-- average damage at the rate on the two-hander's own set's hits (Score.LandedHitsOf), never the worn pair's
		{ "procs: a two-hander's melee proc is valued on its own set's hits: that set without the proc plus the proc at that set's rate", function()
			local G, ns, st, res = procStaffSetup()
			local Sc, W, ctx = ns.Score, st.W, st.ctx
			local h = ctx.landedHitsFor(res.newSet)
			local rate = 1.5 * 3.4 * (h.mh.swings + h.mh.specials)
			local staff = res.newSet[16]
			T.eq(staff.procs[1].avg, 250); T.eq(staff.procs[1].hits, "melee")
			T.eq(Sc.LandedHitsOf(res.newSet, ctx), h, "the two-hander's set's hits")
			-- linked to the env's entry (an equip aura of melee swings and abilities, physical, the melee table)
			T.eq(staff.procs[1].linked, true); T.eq(staff.procs[1].mask, 20); T.eq(staff.procs[1].defense, 2)
			local noProc = Sc.CopySet(res.newSet); noProc[16] = setmetatable({ procs = {} }, { __index = staff })
			T.near(res.delta, Sc.SetValue(noProc, W, ctx) - Sc.SetValue(ctx.equipped, W, ctx)
				+ 250 * procFactor(ns.Model, st.model, 2, "physical", true) * rate / 60 * W.EXTRA_DPS, 1e-9,
				"the proc on the two-hander's own set's hits")
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- A.ModelProcRates' slot kind: a worn item's from its slot (a worn off-hand weapon's "Chance on hit" rolls on the off
		-- hand's hits), an item placed in no set's from its equipLoc (EQUIP_KIND). Stinging Viper 6472: Forever Item.csv class 2
		-- subclass 4 InventoryType 13, a one-handed mace (Era ItemSparse ItemDelay 2800), measured at 1.75 a minute
		-- (MEASURED_PPM, EV-0119); a hunter learns no mace (the env's weapon lines: swords, axes, bows, guns, staves, daggers,
		-- crossbows), so it goes into no set and its rate is on the worn set's hits, in the main hand its equipLoc names, at
		-- the worn main hand's speed. The off-hand dagger and the viper's stats are made up.
		-- A.Explain reads what every item record holds (Items.Get from Parse:Lines: effects and unparsed, empty when there are
		-- none): a record without one is an error, never "nothing to show"
		{ "A.Explain: an item record without its unparsed list or, in an unknown set, its effects list is an error", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.oddbelt = { info = { 50, "INVTYPE_WAIST", 4, 2 }, setID = 99999, lines = { ln("Странный пояс"), ln("Пояс", "Кожа"),
				ln("Комплект: +5 к ловкости.") }, api = {} }
			G.bags[0] = { "newhelm", "oddbelt" }
			local ns = loadAll(G)
			local helm = { kind = "bag", bag = 0, slot = 1 }
			T.truthy(#ns.Advisor.Explain("newhelm", helm) > 0, "a full record")
			ns.Items.Get("newhelm").unparsed = nil
			T.eq(pcall(ns.Advisor.Explain, "newhelm", helm), false, "a record without unparsed")
			local belt = { kind = "bag", bag = 0, slot = 2 }
			T.truthy(table.concat((function() local t = {} for i, l in ipairs(ns.Advisor.Explain("oddbelt", belt)) do t[i] = l[1] end return t end)(), "\n")
				:find("HGA: комплект неизвестен HGA", 1, true), "a set HGA has no data for")
			ns.Items.Get("oddbelt").effects = nil
			T.eq(pcall(ns.Advisor.Explain, "oddbelt", belt), false, "a record without effects")
		end },
		{ "ModelProcRates: a worn off-hand weapon at the off hand's rate; an unusable measured mace by its equipLoc, raising nothing", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.viper = { info = { 6472, "INVTYPE_WEAPON", 2, 4 }, lines = { ln("Жалящая гадюка"), ln("Одноручное", "Дробящее"),
				ln("Урон: 20-40", "Скорость 2,80"), ln("(10,7 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 10 - 20 ед. урона.") }, api = {} }
			G.items.procdagger = { info = { 99503, "INVTYPE_WEAPON", 2, 15 }, lines = { ln("Кинжал с эффектом"), ln("Одноручное", "Кинжал"),
				ln("Урон: 25-40", "Скорость 1,80"), ln("(18,0 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 30 - 50 ед. урона.") }, api = {} }
			G.equippedLinks[17] = "procdagger"
			G.bags[0] = { "viper" }
			survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
			local ns = loadAll(G)
			local A = ns.Advisor
			local lh = A.State().ctx.landedHits
			T.eq(lh.mh.speed, 2.6); T.eq(lh.oh.speed, 1.8)
			local viper = A.Evaluate("viper", { kind = "bag", bag = 0, slot = 1 })
			T.eq(viper.usable, false); T.eq(viper.newSet, nil); T.eq(viper.slot, nil)
			local ok, rates = pcall(A.ModelProcRates, viper)
			T.truthy(ok, tostring(rates))
			if ok then T.near(rates[1], 1.75 * 2.6 * (lh.mh.swings + lh.mh.specials), 1e-12, "the main hand of the worn set") end
			local okE, lines = pcall(A.Explain, "viper", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(okE, tostring(lines))
			local dagger = A.Evaluate("procdagger", { kind = "equipped", slot = 17 })
			T.near(A.ModelProcRates(dagger)[1], 1.5 * 1.8 * lh.oh.swings, 1e-12, "the off hand's own swings at its 1.8 s")
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.near(ns.db.dump.equipped["17"].result.procsPerMinuteAtModel[1], 1.5 * 1.8 * lh.oh.swings, 1e-12, "the dump: the off hand's")
			-- every result A.Evaluate places in a set names its slot there (Score.Evaluate): a set without one is an error
			local okS, errS = pcall(A.ModelProcRates, { rec = dagger.rec, newSet = A.State().ctx.equipped })
			T.eq(okS, false); T.truthy(tostring(errS):find("a result with a set and no slot", 1, true), tostring(errS))
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- The tooltip's procs per minute name the hits they are on (A.ModelProcRates' second value): a worn item's are on the
		-- worn set's hits, as the character attacks now ("с твоими атаками сейчас"), and so are the rates of an item the
		-- evaluation places in no set; the rates of an item the evaluation places in res.newSet are on that set's hits
		-- ("если надеть"): a bag item, and an item of where.kind "new" (a quest reward, loot, a merchant's item: Tooltip.lua).
		-- The env's "new bow" (2.6 s, a chance on hit of 22 - 34) worn; made up: a 3.0 s bag bow and a bag mace (a hunter
		-- learns no mace: the env's weapon lines), each with a chance on hit.
		{ "procs: the tooltip's rate says 'сейчас' on the worn set's hits and 'если надеть' on the set a bag, a new or a chat-linked item goes into", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.slowprocbow = { info = { 99507, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Медленный лук с эффектом"), ln("Дальний бой", "Лук"),
				ln("Урон: 60-100", "Скорость 3,00"), ln("(26,7 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 40 - 60 ед. урона.") }, api = {} }
			G.items.procmace = { info = { 99508, "INVTYPE_WEAPON", 2, 4 }, lines = { ln("Булава с эффектом"), ln("Одноручное", "Дробящее"),
				ln("Урон: 30-50", "Скорость 2,20"), ln("(18,2 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 50 - 70 ед. урона.") }, api = {} }
			G.equippedLinks[18] = "newbow"
			G.bags[0] = { "slowprocbow", "procmace" }
			G.measuredPPM = { [2] = 1.5, [99507] = 1.5, [99508] = 1.5 }
			local ns = loadAll(G)
			local A = ns.Advisor
			local st = A.State()
			local lh = st.ctx.landedHits
			local function text(link, where)
				local t = {}
				for i, l in ipairs(A.Explain(link, where)) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			-- the worn bow: the worn set's shots and stings at its 2.6 s
			local worn = A.Evaluate("newbow", { kind = "equipped", slot = 18 })
			local wornRates, wornOf = A.ModelProcRates(worn)
			T.eq(wornOf, "worn")
			T.eq(lh.ranged.speed, 2.6)
			T.near(wornRates[1], 1.5 * 2.6 * (lh.ranged.swings + lh.ranged.specials + lh.ranged.casts), 1e-12)
			local wornText = text("newbow", { kind = "equipped", slot = 18 })
			T.truthy(wornText:find(string.format("; с твоими атаками сейчас ~%.2f/мин)", wornRates[1]), 1, true), wornText)
			T.eq(wornText:find("если надеть", 1, true), nil, wornText)
			-- the bag bow: its own set's shots and stings at its 3.0 s
			local bag = A.Evaluate("slowprocbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(bag.slot, 18)
			local bagRates, bagOf = A.ModelProcRates(bag)
			T.eq(bagOf, "newSet")
			local own = st.ctx.landedHitsFor(bag.newSet).ranged
			T.eq(own.speed, 3.0)
			T.near(bagRates[1], 1.5 * 3.0 * (own.swings + own.specials + own.casts), 1e-12)
			local bagText = text("slowprocbow", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(bagText:find(string.format("; если надеть — ~%.2f/мин)", bagRates[1]), 1, true), bagText)
			T.eq(bagText:find("сейчас ~", 1, true), nil, bagText)
			-- the same bow as a quest reward (where.kind "new"): placed in the same set, on that set's hits
			local new = A.Evaluate("slowprocbow", { kind = "new" })
			T.eq(new.slot, 18); T.truthy(new.newSet ~= nil, "a new item placed in a set")
			local newRates, newOf = A.ModelProcRates(new)
			T.eq(newOf, "newSet")
			T.near(newRates[1], bagRates[1], 1e-12, "the set it goes into: the bag copy's")
			local newText = text("slowprocbow", { kind = "new" })
			T.truthy(newText:find(string.format("; если надеть — ~%.2f/мин)", newRates[1]), 1, true), newText)
			T.eq(newText:find("сейчас ~", 1, true), nil, newText)
			-- the same bow from a chat link (no where): placed in the same set, on that set's hits
			local chat = A.Evaluate("slowprocbow", nil)
			T.truthy(chat.newSet ~= nil, "a chat-linked item placed in a set")
			local chatRates, chatOf = A.ModelProcRates(chat)
			T.eq(chatOf, "newSet")
			local chatText = text("slowprocbow", nil)
			T.truthy(chatText:find(string.format("; если надеть — ~%.2f/мин)", chatRates[1]), 1, true), chatText)
			T.eq(chatText:find("сейчас ~", 1, true), nil, chatText)
			-- the mace goes into no set: the worn set's hits, in the main hand its equipLoc names, at the worn 2.6 s
			local mace = A.Evaluate("procmace", { kind = "bag", bag = 0, slot = 2 })
			T.eq(mace.usable, false); T.eq(mace.newSet, nil)
			local maceRates, maceOf = A.ModelProcRates(mace)
			T.eq(maceOf, "worn")
			T.near(maceRates[1], 1.5 * 2.6 * (lh.mh.swings + lh.mh.specials), 1e-12)
			local maceText = text("procmace", { kind = "bag", bag = 0, slot = 2 })
			T.truthy(maceText:find(string.format("; с твоими атаками сейчас ~%.2f/мин)", maceRates[1]), 1, true), maceText)
			-- /hga dump names the hits of each
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump
			T.eq(d.equipped["18"].result.procsPerMinuteHits, "worn")
			local byLink = {}
			for _, b in ipairs(d.bags) do byLink[b.link] = b end
			T.eq(byLink.slowprocbow.result.procsPerMinuteHits, "newSet"); T.eq(byLink.procmace.result.procsPerMinuteHits, "worn")
			T.near(byLink.slowprocbow.result.procsPerMinuteAtModel[1], bagRates[1], 1e-12)
			T.eq(d.equipped["16"].result.procsPerMinuteHits, nil, "no proc: none named")
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- A worn set with procs on both hands, the bow and armor: Ripsaw 9478 in the main hand (Item.csv InventoryType 21, Era
		-- ItemSparse ItemDelay 2700; 2 a minute, EV-0022), an off-hand dagger with a melee equip proc, Verdant Keeper's Aim
		-- 17753 (2.8 s; 3.5 a minute, EV-0003), the Highborne Research Tablet 260205 (2.6 a minute at 2.5 s, EV-0021) and gloves
		-- with a melee equip proc; the ids the rules key on are Forever's, the stats and the other items made up. Every bag
		-- piece is unique-equipped, so a bag copy goes into its own slot alone.
		{ "procs: a worn set with procs on both hands, the bow and armor gives 0, each worn proc at its own set's hits", function()
			local G = env()
			survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function add(link, id, loc, class, sub, lines)
				for i, l in ipairs(lines) do lines[i] = type(l) == "table" and ln(l[1], l[2]) or ln(l) end
				G.items[link] = { info = { id, loc, class, sub }, lines = lines, api = {} }
			end
			local U = "Уникальный использующийся"
			add("vka", 17753, "INVTYPE_RANGED", 2, 2, { "Верный лук хранителя", U, { "Дальний бой", "Лук" }, { "Урон: 40-70", "Скорость 2,80" },
				"(19,6 ед. урона в секунду)", "+5 к ловкости", "Возможный эффект при попадании: наносит 20 - 36 ед. урона." })
			add("ripsaw", 9478, "INVTYPE_WEAPONMAINHAND", 2, 0, { "Пила", U, { "Правая рука", "Топор" }, { "Урон: 40-75", "Скорость 2,70" },
				"(21,3 ед. урона в секунду)", "+4 к ловкости", "Возможный эффект при попадании: наносит 30 - 50 ед. урона." })
			add("mdagger", 99504, "INVTYPE_WEAPON", 2, 15, { "Кинжал", U, { "Одноручное", "Кинжал" }, { "Урон: 25-40", "Скорость 1,80" },
				"(18,0 ед. урона в секунду)", "Если на персонаже: Атаки ближнего боя с некоторой вероятностью наносят 100 - 140 ед. урона." })
			add("tablet", 260205, "INVTYPE_TRINKET", 4, 0, { "Исследовательская табличка высокорожденных", U, "Аксессуар",
				"Если на персонаже: С некоторой вероятностью при попадании наносит 69 - 81 ед. урона от тайной магии." })
			add("pgloves", 99505, "INVTYPE_HAND", 4, 2, { "Перчатки", U, { "Кисти рук", "Кожа" }, "Броня: 55", "+4 к ловкости",
				"Если на персонаже: 5% вероятность на нанесение 50 - 70 ед. урона при успешной атаке в ближнем бою." })
			add("weakstaff", 99506, "INVTYPE_2HWEAPON", 2, 10, { "Палка", { "Двуручное", "Посох" }, { "Урон: 10-20", "Скорость 3,00" },
				"(5,0 ед. урона в секунду)" })
			for k in pairs(G.equippedLinks) do G.equippedLinks[k] = nil end
			local worn = { [10] = "pgloves", [13] = "tablet", [16] = "ripsaw", [17] = "mdagger", [18] = "vka" }
			for slot, link in pairs(worn) do G.equippedLinks[slot] = link end
			G.ownerSpeed, G.ownerOffSpeed = 2.7, 1.8
			G.bags[0] = { "vka", "ripsaw", "mdagger", "tablet", "pgloves", "weakstaff" }
			G.measuredPPM = { [99504] = 1.5 }
			local ns = loadAll(G)
			local A, Sc = ns.Advisor, ns.Score
			local st = A.State()
			local eq, W, ctx = st.ctx.equipped, st.W, st.ctx
			local lh = ctx.landedHits
			T.eq(ctx.landedHitsFor(eq), lh, "the worn set's own hits")
			T.eq(lh.mh.speed, 2.7); T.eq(lh.oh.speed, 1.8); T.eq(lh.ranged.speed, 2.8)
			-- the main hand and the ranged slot land hits; the off hand behind the 2.7 s main hand swings in no visit of the weave
			-- (the ranged path sets the cycle, Model weaveParts)
			T.truthy(lh.mh.swings > 0 and lh.ranged.swings > 0 and lh.ranged.casts > 0, "the main hand and the ranged slot land hits")
			T.eq(lh.oh.swings, 0, "no off-hand swing")
			T.eq(ctx.weaponGain(eq), 0, "the worn weapons")
			local cur = Sc.SetValue(eq, W, ctx)
			-- the worn main hand beats a weak two-hander (BestHands' order), on its own hits; the off-hand dagger comes off: in
			-- the weave it swings in no visit behind the 2.7 s main hand, and dual wield adds 19% miss to the main hand's white
			-- swings (Model weaveParts)
			local bh = Sc.BestHands(nil, eq, { ns.Items.Get("weakstaff") }, W, ctx)
			T.eq(bh.mh, eq[16]); T.eq(bh.oh, nil, "the off hand off"); T.truthy(bh.value > cur, "above the worn set's value")
			local rows = Sc.PlanRows(eq, Sc.Plan(eq, {}, W, ctx))
			T.eq(#rows, 1, "a plan with no candidates: the off hand off"); T.eq(rows[1].slot, 17); T.eq(rows[1].new, nil)
			-- each worn proc on the worn set's hits: Ripsaw (unlinked: its made-up text's 40 is not the DB2's 70) on its main
			-- hand at 2.7 s; the dagger's melee equip aura (the env's entry) on both hands' swings and the main hand's specials
			-- at their weapons' speeds; the bow (17753, linked: Keeper's Sting 29655, Nature on the ranged table) on its shots,
			-- the dives and Serpent Sting's applications at 2.8 s; the Tablet (linked) at each hand's speed on every landed
			-- damaging hit, no application; the gloves (the env's entry) at 5% a melee hit, at most once a second: r / (1 + r x 1)
			local mh, oh, r = lh.mh.swings + lh.mh.specials, lh.oh.swings, lh.ranged
			local gloves = 60 * 0.05 * (mh + oh)
			local M, m = ns.Model, st.model
			local expect = {
				[16] = { 2 * 2.7 * mh, 40, procFactor(M, m, 0, "physical", true) },
				[17] = { 1.5 * (2.7 * mh + 1.8 * oh), 120, procFactor(M, m, 2, "physical", true) },
				[18] = { 3.5 * 2.8 * (r.swings + r.specials + r.casts), 28, procFactor(M, m, 3, "magic", true) },
				[13] = { 2.6 * (2.7 * mh + 1.8 * oh + 2.8 * (r.swings + r.specials)), 75, procFactor(M, m, 1, "magic", true) },
				[10] = { 60 * (gloves / 60) / (1 + gloves / 60 * 1), 60, procFactor(M, m, 2, "physical", true) },
			}
			local procs = 0
			for slot, e in pairs(expect) do
				local res = A.Evaluate(eq[slot].link, { kind = "equipped", slot = slot })
				T.eq(res.delta, 0, "worn " .. eq[slot].link); T.eq(res.verdict, "same", "worn " .. eq[slot].link)
				T.near(A.ModelProcRates(res)[1], e[1], 1e-12, "the rate of worn " .. eq[slot].link)
				T.eq(eq[slot].procs[1].avg, e[2], eq[slot].link .. "'s damage")
				procs = procs + e[2] * e[3] * e[1] / 60 * W.EXTRA_DPS
			end
			-- the tooltip of the gloves names the DB2's chance and internal cooldown; the linked ones say nothing of DB2 data
			-- not found, the unlinked Ripsaw does
			local function explain(slot)
				local t = {}
				for i, l in ipairs(A.Explain(eq[slot].link, { kind = "equipped", slot = slot })) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local g = explain(10)
			T.truthy(g:find(string.format("HGA: эффект при попадании учтён как оценка (5%% за попадание — данные DB2, не чаще раза в 1 с; с твоими атаками сейчас ~%.2f/мин)",
				expect[10][1]), 1, true), g)
			T.eq(g:find("не найден в данных DB2", 1, true), nil, g)
			T.truthy(explain(16):find("не найден в данных DB2", 1, true), "Ripsaw unlinked")
			-- the set's procs are the difference to the same set with every proc taken off
			local bare = {}
			for slot, it in pairs(eq) do bare[slot] = setmetatable({ procs = {} }, { __index = it }) end
			T.near(cur - Sc.SetValue(bare, W, ctx), procs, 1e-9, "the worn procs' sum")
			-- a bag copy of a worn piece scores 0, but the main hand's: Score.Evaluate credits a weapon with the best hands it is
			-- part of, and the copy of Ripsaw takes the main hand of the best hands, the off hand off (BestHands above)
			for i, link in ipairs(G.bags[0]) do
				if st.snap.links[link] then
					local res = A.Evaluate(link, { kind = "bag", bag = 0, slot = i })
					local want = link == "ripsaw" and bh.value - cur or 0
					T.truthy(math.abs(res.delta - want) < 1e-9 and math.abs(res.sec) < 1e-9,
						string.format("bag copy of %s: %s, want %s", link, tostring(res.delta), tostring(want)))
				end
			end
			local planRows = A.Plan().rows
			T.eq(#planRows, 1, "the plan over the bags: the off hand off"); T.eq(planRows[1].slot, 17); T.eq(planRows[1].new, nil)
			T.eq(#G.reportedErrors, 0, "errors: " .. table.concat(G.reportedErrors, " | "))
		end },
		-- Items.LinkProcs: a parsed proc takes the one Game/ProcData.lua entry of its kind (an "Equip:" line: "equip"; a "Chance
		-- on hit:" line: "hit") whose mean is its average within 0.5 (its school "physical" when the SchoolMask holds the
		-- physical bit, defense, crit, and an equip aura's mask, chance, ppm, icd); with none, or two, it stays unlinked:
		-- defense 0, crit allowed, the school its text names (made-up entries)
		{ "ProcData link: one match by kind and mean; none or two: unlinked", function()
			local G = env()
			G.procData[99710] = {
				{ trigger = 990011, kind = "equip", mask = 64, chance = 8, ppm = 0, icd = 200, spell = 990012, avg = 16, min = 13, max = 19, school = 32, defense = 3, crit = false },
				{ trigger = 990013, kind = "hit", spell = 990013, avg = 40.4, min = 30, max = 51, school = 3, defense = 2, crit = true },
			}
			G.procData[99711] = {
				{ trigger = 990014, kind = "equip", mask = 64, chance = 100, ppm = 0, icd = 0, spell = 990015, avg = 16, min = 13, max = 19, school = 1, defense = 3, crit = true },
				{ trigger = 990016, kind = "equip", mask = 320, chance = 100, ppm = 0, icd = 0, spell = 990017, avg = 16.4, min = 13, max = 20, school = 1, defense = 3, crit = true },
			}
			local ns = loadAll(G)
			local L = ns.Items.LinkProcs
			local procs = L(99710, { { avg = 16, hits = "ranged", equip = true, school = "physical" }, { avg = 40, hits = "weapon", school = "physical" },
				{ avg = 17, hits = "ranged", equip = true, school = "magic" } }, {})
			local a, b, c = procs[1], procs[2], procs[3]
			T.eq(a.linked, true); T.eq(a.school, "magic"); T.eq(a.schoolMask, 32); T.eq(a.defense, 3); T.eq(a.crit, false)
			T.eq(a.mask, 64); T.eq(a.chance, 8); T.eq(a.ppm, 0); T.eq(a.icd, 200); T.eq(a.spell, 990012)
			T.eq(b.linked, true, "within 0.5"); T.eq(b.school, "physical", "SchoolMask 3: the physical bit"); T.eq(b.defense, 2); T.eq(b.mask, nil)
			T.eq(c.linked, false, "17 against 16: no entry"); T.eq(c.defense, 0); T.eq(c.crit, true); T.eq(c.school, "magic", "its text's")
			T.eq(L(99710, { { avg = 16, hits = "weapon", school = "physical" } }, {})[1].linked, false, "a chance on hit: no equip entry")
			T.eq(L(99710, { { avg = 16.5, hits = "ranged", equip = true, school = "magic" } }, {})[1].linked, true, "0.5 off: within")
			T.eq(L(99710, { { avg = 15.4, hits = "ranged", equip = true, school = "magic" } }, {})[1].linked, false, "0.6 off: not within")
			local two = L(99711, { { avg = 16.2, hits = "ranged", equip = true, school = "physical" } }, {})[1]
			T.eq(two.linked, false, "two entries within 0.5"); T.eq(two.defense, 0); T.eq(two.mask, nil)
			T.eq(L(99999, { { avg = 16, hits = "ranged", equip = true, school = "magic" } }, {})[1].linked, false, "no entry for the item")
			T.eq(#G.reportedErrors, 0)
		end },
		-- Items.LinkProcs, a damage over time with no direct damage (raid-mode design 17.4, approximation DA2): it links by item
		-- and kind to the item's one line of its kind Parse leaves not counted (a "Chance on hit:" line with no damage range; an
		-- "Equip:" line Parse reads nothing of), which becomes its proc (no avg; "weapon" hits for a chance on hit) and is
		-- counted; two such lines, or two such entries of the kind, leave it unlinked; an entry with a direct damage still links
		-- by its mean and brings its dot (made-up entries)
		{ "dot link: one unparsed \"Chance on hit\" line links the item's dot entry; two lines leave it unlinked", function()
			local G = env()
			local DOT = { tick = 24, period = 1000, ticks = 7, canCrit = true }
			G.procData[99720] = { { trigger = 990020, kind = "hit", ppm = 1.45, source = "EV-0122", spell = 990020, avg = 0, min = 0, max = 0, school = 8, defense = 1, crit = true, dot = DOT } }
			G.procData[99721] = { { trigger = 990021, kind = "equip", mask = 20, chance = 5, ppm = 0, icd = 0, spell = 990022, avg = 0, min = 0, max = 0, school = 1, defense = 2, crit = true, dot = DOT } }
			G.procData[99722] = { { trigger = 990023, kind = "hit", spell = 990023, avg = 150, min = 150, max = 150, school = 32, defense = 1, crit = true, dot = DOT } }
			G.procData[99723] = { { trigger = 990024, kind = "hit", spell = 990024, avg = 0, min = 0, max = 0, school = 8, defense = 1, crit = true, dot = DOT },
				{ trigger = 990025, kind = "hit", spell = 990025, avg = 0, min = 0, max = 0, school = 8, defense = 1, crit = true, dot = DOT } }
			local ns = loadAll(G)
			local L = ns.Items.LinkProcs
			local HIT_LINE = "Возможный эффект при попадании: поражает цель гнилью, нанося 24 ед. урона от сил природы раз в 1 сек."
			local function effects(...)
				local t = {}
				for i, e in ipairs({ ... }) do t[i] = e end
				return t
			end
			-- one not-counted chance-on-hit line: linked, its proc made, the line counted
			local line = { kind = "proc", text = HIT_LINE, hits = "weapon" }
			local procs = L(99720, {}, effects(line, { kind = "use", text = "Использование: x" }))
			T.eq(#procs, 1); local p = procs[1]
			T.eq(p.linked, true); T.eq(p.avg, nil, "no direct damage"); T.eq(p.dot, DOT); T.eq(p.hits, "weapon"); T.eq(p.equip, nil)
			T.eq(p.school, "magic"); T.eq(p.defense, 1); T.eq(p.ppm, 1.45); T.eq(p.source, "EV-0122"); T.eq(p.spell, 990020)
			T.eq(line.linked, true, "the line is counted")
			-- two such lines: unlinked, no proc, neither line marked
			local l1, l2 = { kind = "proc", text = HIT_LINE, hits = "weapon" }, { kind = "proc", text = HIT_LINE .. "!", hits = "weapon" }
			T.eq(#L(99720, {}, effects(l1, l2)), 0, "two lines: unlinked"); T.eq(l1.linked, nil); T.eq(l2.linked, nil)
			-- no such line (the chance-on-hit line reads a range: a parsed proc, which no direct entry matches): unlinked
			local parsed = L(99720, { { avg = 25, hits = "weapon", school = "magic" } }, effects({ kind = "proc", text = "x", hits = "weapon", avg = 25 }))
			T.eq(#parsed, 1); T.eq(parsed[1].linked, false, "a dot entry has no mean to match")
			-- an equip line: the equip entry links to the one not-counted "Equip:" line, its mask and rate with it
			local eline = { kind = "equip", text = "Если на персонаже: атаки ближнего боя ранят цель." }
			local ep = L(99721, {}, effects(eline, { kind = "proc", text = HIT_LINE, hits = "weapon" }))
			T.eq(#ep, 1); T.eq(ep[1].equip, true); T.eq(ep[1].mask, 20); T.eq(ep[1].chance, 5); T.eq(ep[1].school, "physical")
			T.eq(ep[1].hits, nil); T.eq(eline.linked, true)
			-- a direct damage with a dot: linked by its mean, its dot along
			local d = L(99722, { { avg = 150, hits = "weapon", school = "magic" } }, effects({ kind = "proc", text = "y", hits = "weapon", avg = 150 }))
			T.eq(#d, 1); T.eq(d[1].linked, true); T.eq(d[1].avg, 150); T.eq(d[1].dot, DOT)
			-- two dot entries of the kind: unlinked
			local two = { kind = "proc", text = HIT_LINE, hits = "weapon" }
			T.eq(#L(99723, {}, effects(two)), 0, "two dot entries: unlinked"); T.eq(two.linked, nil)
			-- a dot entry has no mean: a parsed average of 0.5 does not match its avg 0
			T.eq(L(99720, { { avg = 0.5, hits = "weapon", school = "magic" } }, {})[1].linked, false, "no mean to match")
			-- without the parse's effects: an error, an item without a dot entry too
			T.eq(pcall(L, 99720, {}), false)
			T.eq(pcall(L, 99710, {}), false, "no effects: an error whatever the item")
			T.eq(#G.reportedErrors, 0)
		end },
		-- Items.LinkProcs, a fixed direct damage (Game/ProcData.lua min == max above 0: a damage effect of Variance 0, whose
		-- tooltip shows one number, no range Parse reads; raid-mode design 24.2, approximation DA4): it links by item and kind
		-- to the one line of its kind Parse leaves not counted that states its amount as damage (Parse.StatesDamage: ruRU "N
		-- ед. урона", enUS "N <school> damage"), a line no other such entry of the kind claims; that line becomes its proc
		-- (the entry's mean as its direct damage, its dot along; "weapon" hits for a chance on hit) and is counted. A line of
		-- another amount, two lines of the amount, or two such entries on one line leave it unlinked; the dot-only link takes
		-- the lines the fixed entries leave (made-up entries)
		{ "fixed link: one not-counted line that states the entry's amount links it; another amount, two lines, two entries leave it unlinked", function()
			local G = env()
			local DOT = { tick = 6, period = 2000, ticks = 3, canCrit = true }
			G.procData[99730] = { { trigger = 990030, kind = "hit", ppm = 1, source = "vanilla-carryover", spell = 990030, avg = 42, min = 42, max = 42, school = 4, defense = 1, crit = true } }
			G.procData[99731] = { { trigger = 990031, kind = "hit", spell = 990031, avg = 42, min = 42, max = 42, school = 4, defense = 1, crit = true },
				{ trigger = 990032, kind = "hit", spell = 990032, avg = 42, min = 42, max = 42, school = 1, defense = 2, crit = true } }
			G.procData[99732] = { { trigger = 990033, kind = "equip", mask = 40, chance = 20, ppm = 0, icd = 0, spell = 990034, avg = 25, min = 25, max = 25, school = 4, defense = 1, crit = true } }
			G.procData[99733] = { { trigger = 990035, kind = "hit", spell = 990035, avg = 80, min = 80, max = 80, school = 4, defense = 1, crit = true, dot = DOT },
				{ trigger = 990036, kind = "hit", spell = 990036, avg = 0, min = 0, max = 0, school = 8, defense = 1, crit = true, dot = DOT } }
			G.procData[99734] = { { trigger = 990037, kind = "hit", spell = 990037, avg = 50, min = 40, max = 60, school = 4, defense = 1, crit = true } }
			local ns = loadAll(G)
			local L = ns.Items.LinkProcs
			local function hit(text) return { kind = "proc", text = "Возможный эффект при попадании: " .. text, hits = "weapon" } end
			-- an entry of a range (min 40, max 60) shows a range Parse reads: a line of one amount, its min, is no line of it
			T.eq(#L(99734, {}, { hit("Наносит противнику 40 ед. урона от огня.") }), 0, "a range entry links by its mean alone")
			-- the line states 42: linked, its proc made with the entry's mean, the line counted
			local line = hit("Наносит противнику 42 ед. урона от огня.")
			local procs = L(99730, {}, { line, { kind = "use", text = "Использование: x" } })
			T.eq(#procs, 1); local p = procs[1]
			T.eq(p.linked, true); T.eq(p.avg, 42, "the entry's mean"); T.eq(p.dot, nil); T.eq(p.hits, "weapon"); T.eq(p.equip, nil)
			T.eq(p.school, "magic"); T.eq(p.defense, 1); T.eq(p.ppm, 1); T.eq(p.source, "vanilla-carryover"); T.eq(p.spell, 990030)
			T.eq(p.text, line.text); T.eq(line.linked, true, "the line is counted")
			-- the enUS form, and a physical damage word between
			T.eq(#L(99730, {}, { { kind = "proc", text = "Chance on hit: Blasts a target for 42 Fire damage.", hits = "weapon" } }), 1, "enUS")
			T.eq(#L(99730, {}, { hit("Наносит 42 ед. физического урона.") }), 1, "a word between ед. and урона")
			-- another amount, an amount that only ends in 42, a number that is no damage: unlinked, the line not marked
			local other = hit("Наносит противнику 43 ед. урона от огня.")
			T.eq(#L(99730, {}, { other }), 0, "43"); T.eq(other.linked, nil)
			T.eq(#L(99730, {}, { hit("Наносит противнику 142 ед. урона от огня.") }), 0, "142 is not 42")
			T.eq(#L(99730, {}, { hit("Снижает броню цели на 42 ед.") }), 0, "42 armor: no damage")
			-- two lines of the amount: unlinked, neither marked
			local l1, l2 = hit("Наносит 42 ед. урона от огня."), hit("Наносит 42 ед. урона от льда.")
			T.eq(#L(99730, {}, { l1, l2 }), 0, "two lines"); T.eq(l1.linked, nil); T.eq(l2.linked, nil)
			-- a line with a range is a parsed proc (avg set): not a line to link by the amount
			T.eq(#L(99730, {}, { { kind = "proc", text = "x 42 ед. урона", hits = "weapon", avg = 30 } }), 0, "a parsed line is no open line")
			-- two fixed entries of the kind on the one line: both unlinked
			local shared = hit("Наносит 42 ед. урона от огня.")
			T.eq(#L(99731, {}, { shared }), 0, "two entries claim one line"); T.eq(shared.linked, nil)
			-- an equip entry: the "Equip:" line that states 25, its mask and chance with it
			local eline = { kind = "equip", text = "Если на персонаже: атаки дальнего боя могут нанести 25 ед. урона от огня." }
			local ep = L(99732, {}, { { kind = "equip", text = "Если на персонаже: +10 к чему-то." }, eline })
			T.eq(#ep, 1); T.eq(ep[1].equip, true); T.eq(ep[1].hits, nil); T.eq(ep[1].mask, 40); T.eq(ep[1].chance, 20); T.eq(ep[1].avg, 25)
			T.eq(eline.linked, true)
			T.eq(#L(99732, {}, { hit("Наносит 25 ед. урона от огня.") }), 0, "an equip entry takes no chance-on-hit line")
			-- a fixed entry with a dot and a dot-only entry: the fixed one takes the line of its amount, the dot-only one the other
			local fire, rot = hit("Выпускает огненный шар, который наносит 80 ед. урона от огня сразу и еще 18 ед. урона за 6 сек."),
				hit("Поражает цель гнилью.")
			local two = L(99733, {}, { rot, fire })
			T.eq(#two, 2); T.eq(two[1].avg, 80); T.eq(two[1].spell, 990035); T.eq(two[1].dot, DOT); T.eq(two[1].text, fire.text)
			T.eq(two[2].avg, nil); T.eq(two[2].spell, 990036); T.eq(two[2].text, rot.text); T.eq(fire.linked, true); T.eq(rot.linked, true)
			-- one line, the fixed entry's: the dot-only entry finds none left
			local only = L(99733, {}, { hit("Выпускает огненный шар, который наносит 80 ед. урона от огня сразу и еще 18 ед. урона за 6 сек.") })
			T.eq(#only, 1); T.eq(only[1].spell, 990035)
			-- a parsed proc that matches the fixed entry by its mean keeps it: no second link by the amount
			local parsed = L(99730, { { avg = 42, hits = "weapon", school = "magic" } },
				{ { kind = "proc", text = "y", hits = "weapon", avg = 42 }, hit("Наносит 42 ед. урона от огня.") })
			T.eq(#parsed, 1, "the entry linked once"); T.eq(parsed[1].linked, true)
			T.eq(#G.reportedErrors, 0)
		end },
		-- The real texts (ruRU, the item's DB2 Spell description, db2_ru Spell.csv, its tokens at the entry's values; the stub's
		-- name, damage and speed lines are no game's): Demonshear 13348's Shadow Bolt 17483 ("наносящей $s1 ед. урона от
		-- темной магии и $s2 ед. урона раз в $t2 сек. в течение $d": 150 and 34 every 2 s for 6 s; measured 1.1 a minute,
		-- EV-0003) and Meteor Shard 6220's 1292152 ("Наносит противнику $s1 ед. урона от огня": 42; measured 1.55, EV-0119)
		-- link to their Game/ProcData.lua entries and are priced in the Survival tree's weave: the direct line and the dot line,
		-- no effect left not counted
		{ "fixed link: Demonshear's 150 with its dot and Meteor Shard's 42, from their real lines, are priced", function()
			local G = env()
			survivalTree(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.demonshear = { info = { 13348, "INVTYPE_2HWEAPON", 2, 8 }, lines = { ln("Демонический клинок"), ln("Двуручное", "Меч"),
				ln("Урон: 90-150", "Скорость 3,80"), ln("(31,6 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: Поражение противника теневой молнией, наносящей 150 ед. урона от темной магии и 34 ед. урона раз в 2 сек. в течение 6 сек.") },
				api = {} }
			G.items.meteor = { info = { 6220, "INVTYPE_WEAPON", 2, 15 }, lines = { ln("Метеоритный осколок"), ln("Одноручное", "Кинжал"),
				ln("Урон: 20-38", "Скорость 1,50"), ln("(19,3 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: Наносит противнику 42 ед. урона от огня.") }, api = {} }
			G.bags[0] = { "demonshear", "meteor" }
			local ns = loadAll(G)
			local A = ns.Advisor
			local function explain(link, slot)
				local t = {}
				for i, l in ipairs(A.Explain(link, { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local rec = ns.Items.Get("demonshear")
			T.eq(#rec.procs, 1); local p = rec.procs[1]
			T.eq(p.linked, true); T.eq(p.avg, 150); T.eq(p.dot.tick, 34); T.eq(p.dot.ticks, 3); T.eq(p.spell, 17483); T.eq(p.school, "magic")
			local res = A.Evaluate("demonshear", { kind = "bag", bag = 0, slot = 1 })
			local rates = A.ModelProcRates(res)
			T.truthy(rates[1] > 0, "priced on the weave's hits: " .. tostring(rates[1]))
			local all = explain("demonshear", 1)
			T.truthy(all:find("HGA: эффект при попадании учтён как оценка (1.10/мин на базовой скорости оружия — замер по логам;", 1, true), all)
			T.truthy(all:find("HGA: урон со временем учтён: 34 ед. × 3 тика за 6 с (", 1, true), all)
			T.eq(all:find("эффекты не учтены", 1, true), nil, all)
			local m = ns.Items.Get("meteor")
			T.eq(#m.procs, 1); T.eq(m.procs[1].linked, true); T.eq(m.procs[1].avg, 42); T.eq(m.procs[1].dot, nil); T.eq(m.procs[1].school, "magic")
			local mall = explain("meteor", 2)
			T.truthy(mall:find("HGA: эффект при попадании учтён как оценка (1.55/мин на базовой скорости оружия — замер по логам;", 1, true), mall)
			T.eq(mall:find("эффекты не учтены", 1, true), nil, mall)
			T.eq(#G.reportedErrors, 0, table.concat(G.reportedErrors, " | "))
		end },
		-- Versus bonuses (raid-mode design 25.2): Drakefang Butcher 12463's Rend 14118 (db2_ru Spell.csv: "Ранит цель, нанося
		-- $o1 ед. урона от кровотечения за $d. Наносит в $s2 раз больше урона драконам": 161 over 7 s, x2) and Lightcrest Hammer
		-- 276419's Smite 1299631 ("Карает цель, нанося $s1 ед. урона от светлой магии. Нежить получает в $s2 раза больше урона":
		-- 105, x2) link to their Game/ProcData.lua entries with the versus of their trigger (Items.LinkProcs), the Survival
		-- tree pricing them in its weave. At 60 the boss is a dragonkin: the bleed's tick x2 before own, Gift of Arthas' 8
		-- after it (the value against the same proc without the bonus: (23 x 2 x own + 8) / (23 x own + 8)), the Smite x1;
		-- below 60 30% of the targets of each type, x1.3. The tooltip says which
		{ "versus: Drakefang Butcher's Rend x2 against dragonkin and Lightcrest Hammer's Smite x2 against undead link with their bonus; raid x2 and x1, levelling x1.3; the tooltip says so", function()
			local function setup(level)
				local G = env()
				survivalTree(G)
				G.UnitLevel = function() return level end
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
				G.items.drakefang = { info = { 12463, "INVTYPE_2HWEAPON", 2, 8 }, lines = { ln("Тесак драконьего клыка"), ln("Двуручное", "Меч"),
					ln("Урон: 95-143", "Скорость 3,40"), ln("(35,0 ед. урона в секунду)"),
					ln("Возможный эффект при попадании: Ранит цель, нанося 161 ед. урона от кровотечения за 7 сек. Наносит в 2 раза больше урона драконам.") },
					api = {} }
				G.items.lightcrest = { info = { 276419, "INVTYPE_WEAPON", 2, 4 }, lines = { ln("Молот светлого гребня"), ln("Одноручное", "Дробящее"),
					ln("Урон: 60-112", "Скорость 2,60"), ln("(33,1 ед. урона в секунду)"),
					ln("Возможный эффект при попадании: Карает цель, нанося 105 ед. урона от светлой магии. Нежить получает в 2 раза больше урона.") },
					api = {} }
				G.bags[0] = { "drakefang", "lightcrest" }
				local ns = loadAll(G)
				settlePet(G)
				return G, ns
			end
			local function explain(ns, link, slot)
				local t = {}
				for i, l in ipairs(ns.Advisor.Explain(link, { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local G, ns = setup(60)
			local rec = ns.Items.Get("drakefang")
			T.eq(#rec.procs, 1); local p = rec.procs[1]
			T.eq(p.linked, true); T.eq(p.dot.tick, 23); T.eq(p.versus.factor, 2); T.eq(p.versus.types[1], "DRAGONKIN")
			local lc = ns.Items.Get("lightcrest")
			T.eq(lc.procs[1].linked, true); T.eq(lc.procs[1].avg, 105); T.eq(lc.procs[1].versus.types[1], "UNDEAD")
			local st = ns.Advisor.State()
			local res = ns.Advisor.Evaluate("drakefang", { kind = "bag", bag = 0, slot = 1 })
			local _, _, outcome = ns.Advisor.ModelProcRates(res)
			local hits = st.ctx.landedHitsFor(res.newSet)
			local with = ns.Score.ProcValue(rec, "2h", st.W, hits, { procOutcome = outcome })
			local bare = { procs = { {} }, name = rec.name, id = rec.id, classID = rec.classID, equipLoc = rec.equipLoc, speed = rec.speed }
			for k, v in pairs(p) do bare.procs[1][k] = v end
			bare.procs[1].versus = nil
			local without = ns.Score.ProcValue(bare, "2h", st.W, hits, { procOutcome = outcome })
			T.truthy(without > 0, "priced in the weave")
			T.near(with / without, (23 * 2 * outcome.own + 8) / (23 * outcome.own + 8), 1e-9, "raid: the tick x2 before own, the gift after")
			local d = explain(ns, "drakefang", 1)
			T.truthy(d:find("HGA: урон эффекта ×2 против драконов — в рейд-режиме цель дракон: учтено ×2", 1, true), d)
			local l = explain(ns, "lightcrest", 2)
			T.truthy(l:find("HGA: урон эффекта ×2 против нежити — в рейд-режиме цель дракон: не учитывается", 1, true), l)
			T.eq(#G.reportedErrors, 0, table.concat(G.reportedErrors, " | "))
			local G2, ns2 = setup(44)
			local d2 = explain(ns2, "drakefang", 1)
			T.truthy(d2:find("HGA: урон эффекта ×2 против драконов — при прокачке доля таких целей 30%: учтено ×1.30", 1, true), d2)
			local l2 = explain(ns2, "lightcrest", 2)
			T.truthy(l2:find("HGA: урон эффекта ×2 против нежити — при прокачке доля таких целей 30%: учтено ×1.30", 1, true), l2)
			T.eq(#G2.reportedErrors, 0, table.concat(G2.reportedErrors, " | "))
		end },
		-- A proc on every hit (raid-mode design 25.3): Hurricane 2824's "Equip:" line (db2_ru Spell.csv 1316319 at its values:
		-- 6 to 10 Frost) and Blazefury Medallion 17111's (7711: "уронаот огня на 2 ед.") are read as equip procs (Core/Parse.lua
		-- ALWAYS_PROC_PATTERNS) and link to their Game/ProcData.lua entries with always (wowsims' "every time" registrations),
		-- so they are priced at a chance of 100 on their masks' hits: the bow on every landed Auto Shot of the set it goes in
		-- (the BM env at 60), the trinket on every landed melee swing and ability (the Survival tree); the tooltip says so
		{ "always: Hurricane's icy bolt on every Auto Shot and Blazefury Medallion's fire on every melee hit, from their real lines, are priced", function()
			local function setup(survival)
				local G = env()
				raidLevel(G)
				if survival then survivalTree(G) end
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
				G.items.hurricane = { info = { 2824, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Ураган"), ln("Дальний бой", "Лук"),
					ln("Урон: 60-112", "Скорость 2,80"), ln("(30,7 ед. урона в секунду)"),
					ln("Если на персонаже: Автоатаки в дальнем бою призывают ледяные стрелы, наносящие цели 6 - 10 ед. урона от магии льда.") },
					api = {} }
				G.items.blazefury = { info = { 17111, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Медальон пылающей ярости"), ln("Аксессуар"),
					ln("Если на персонаже: Повышение наносимого в ближнем бою уронаот огня на 2 ед.") }, api = {} }
				G.bags[0] = { "hurricane", "blazefury" }
				local ns = loadAll(G)
				settlePet(G)
				return G, ns
			end
			local function explain(ns, link, slot)
				local t = {}
				for i, l in ipairs(ns.Advisor.Explain(link, { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local G, ns = setup(false)
			local rec = ns.Items.Get("hurricane")
			T.eq(#rec.procs, 1); local p = rec.procs[1]
			T.eq(p.linked, true); T.eq(p.always, true); T.eq(p.mask, 64); T.eq(p.avg, 8); T.eq(p.school, "magic")
			local res = ns.Advisor.Evaluate("hurricane", { kind = "bag", bag = 0, slot = 1 })
			local rates = ns.Advisor.ModelProcRates(res)
			local hits = ns.Advisor.State().ctx.landedHitsFor(res.newSet)
			T.truthy(hits.ranged.swings > 0, "the set's Auto Shots")
			T.near(rates[1], 60 * hits.ranged.swings, 1e-9, "every landed Auto Shot")
			local h = explain(ns, "hurricane", 1)
			T.truthy(h:find("HGA: эффект при попадании учтён как оценка (на каждом попадании — как в wowsims;", 1, true), h)
			T.eq(h:find("эффекты не учтены", 1, true), nil, h)
			T.eq(#G.reportedErrors, 0, table.concat(G.reportedErrors, " | "))
			local G2, ns2 = setup(true)
			local b = ns2.Items.Get("blazefury")
			T.eq(#b.procs, 1); T.eq(b.procs[1].linked, true); T.eq(b.procs[1].always, true); T.eq(b.procs[1].avg, 2)
			local res2 = ns2.Advisor.Evaluate("blazefury", { kind = "bag", bag = 0, slot = 2 })
			local rates2 = ns2.Advisor.ModelProcRates(res2)
			local hits2 = ns2.Advisor.State().ctx.landedHitsFor(res2.newSet)
			T.truthy(hits2.mh.swings > 0, "the weave's melee")
			T.near(rates2[1], 60 * (hits2.mh.swings + hits2.oh.swings + hits2.mh.specials), 1e-9, "every landed melee swing and ability")
			T.truthy(res2.delta > 0, "it gains: " .. res2.delta)
			local bt = explain(ns2, "blazefury", 2)
			T.truthy(bt:find("HGA: эффект при попадании учтён как оценка (на каждом попадании — как в wowsims;", 1, true), bt)
			T.eq(#G2.reportedErrors, 0, table.concat(G2.reportedErrors, " | "))
		end },
		-- A proc of the main hand alone (raid-mode design 26.2): Iceblade Hacker 13952 (1298413: 41 Frost a hit, the DB2 base
		-- points 40.7), Warblade of Caer Darrow 13982 (1298500: 28 Frost, 22 to 33 with its Variance) and Dreadfrost Saber
		-- 274603 (1294939: 1 Frost) are wowsims' "every time" registrations of ProcMaskMeleeMHAuto | ProcMaskMeleeMHSpecial
		-- (stat_bonus_procs_auto_gen.go:4423-4437, 4677-4683; their ProcTypeMask_1 0x20). Their real ruRU lines (db2_ru
		-- Spell.csv at their values, the Warblade's as a range and as one number) link to their Game/ProcData.lua entries with
		-- always and mainHand, so in the Survival tree at 60 each is priced on every landed main-hand swing and ability, the off
		-- hand's swings out (a 5.0 s Hacker beside the worn 1.8 s off-hand sword, which swings); the tooltip says so
		{ "main hand: Iceblade Hacker's, Warblade of Caer Darrow's and Dreadfrost Saber's frost on every main-hand hit, from their real lines, are priced", function()
			local G = env()
			raidLevel(G)
			survivalTree(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.hacker = { info = { 13952, "INVTYPE_WEAPONMAINHAND", 2, 0 }, lines = { ln("Ледяной рубака"), ln("Правая рука", "Топор"),
				ln("Урон: 90-160", "Скорость 5,00"), ln("(25,0 ед. урона в секунду)"),
				ln("Если на персонаже: Атаки этим оружием в ближнем бою наносят 41 ед. урона от магии льда.") }, api = {} }
			G.items.warblade = { info = { 13982, "INVTYPE_2HWEAPON", 2, 8 }, lines = { ln("Боевой клинок Каэр Дарроу"), ln("Двуручное", "Меч"),
				ln("Урон: 100-150", "Скорость 3,50"), ln("(35,7 ед. урона в секунду)"),
				ln("Если на персонаже: Атаки этим оружием в ближнем бою наносят 22 - 33 ед. урона от магии льда.") }, api = {} }
			G.items.warblade1 = { info = { 13982, "INVTYPE_2HWEAPON", 2, 8 }, lines = { ln("Боевой клинок Каэр Дарроу"), ln("Двуручное", "Меч"),
				ln("Урон: 100-150", "Скорость 3,50"), ln("(35,7 ед. урона в секунду)"),
				ln("Если на персонаже: Атаки этим оружием в ближнем бою наносят 28 ед. урона от магии льда.") }, api = {} }
			G.items.saber = { info = { 274603, "INVTYPE_WEAPONMAINHAND", 2, 7 }, lines = { ln("Сабля жуткого мороза"), ln("Правая рука", "Меч"),
				ln("Урон: 40-75", "Скорость 2,60"), ln("(22,1 ед. урона в секунду)"),
				ln("Если на персонаже: Атаки ближнего боя также наносят 1 ед. урона от магии льда.") }, api = {} }
			G.bags[0] = { "hacker", "warblade", "warblade1", "saber" }
			local ns = loadAll(G)
			settlePet(G)
			T.truthy(ns.Advisor.State(), "state: " .. tostring(ns.Advisor.notReadyReason))
			for slot, case in ipairs({ { "hacker", 41 }, { "warblade", 27.5 }, { "warblade1", 28 }, { "saber", 1 } }) do
				local link, avg = case[1], case[2]
				local rec = ns.Items.Get(link)
				T.eq(#rec.procs, 1, link); local p = rec.procs[1]
				T.eq(p.linked, true, link); T.eq(p.always, true, link); T.eq(p.mainHand, true, link); T.eq(p.mask, 20, link)
				T.eq(p.avg, avg, link); T.eq(p.school, "magic", link)
				local res = ns.Advisor.Evaluate(link, { kind = "bag", bag = 0, slot = slot })
				local hits = ns.Advisor.State().ctx.landedHitsFor(res.newSet)
				T.truthy(hits.mh.swings > 0 and hits.mh.specials > 0, link .. ": the weave's main hand")
				T.near(ns.Advisor.ModelProcRates(res)[1], 60 * (hits.mh.swings + hits.mh.specials), 1e-9, link .. ": every landed main-hand hit")
				local t = {}
				for i, l in ipairs(ns.Advisor.Explain(link, { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
				local text = table.concat(t, "\n")
				T.truthy(text:find("HGA: эффект при попадании учтён как оценка (на каждом попадании правой руки — как в wowsims;", 1, true), text)
				T.eq(text:find("эффекты не учтены", 1, true), nil, text)
			end
			local resH = ns.Advisor.Evaluate("hacker", { kind = "bag", bag = 0, slot = 1 })
			T.truthy(ns.Advisor.State().ctx.landedHitsFor(resH.newSet).oh.swings > 0, "the off hand swings beside the Hacker")
			T.eq(#G.reportedErrors, 0, table.concat(G.reportedErrors, " | "))
		end },
		-- The tooltip's ticks between procs take the application's chance of the set the item goes in (A.ModelProcRates' third
		-- value: ctx.procOutcomeFor of the set's main hand skill, as Score.SetValue prices the set's procs): the Survival tree
		-- with a bag dagger of a bleed (a made-up dot-only entry, the melee table) on the daggers line at 195 of 215 (-20),
		-- measured 40 a minute so the ticks between procs show the skill's miss and dodge
		{ "dot tooltip: a main-hand weapon's dot lands at its own main hand's skill", function()
			local G = env()
			survivalTree(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.bleeddagger = { info = { 99726, "INVTYPE_WEAPON", 2, 15 }, lines = { ln("Кинжал крови"), ln("Одноручное", "Кинжал"),
				ln("Урон: 25-40", "Скорость 1,80"), ln("(18,0 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: ранит цель, нанося 210 ед. урона от кровотечения за 7 сек.") }, api = {} }
			G.procData[99726] = { { trigger = 990028, kind = "hit", spell = 990028, avg = 0, min = 0, max = 0, school = 1, defense = 2, crit = true,
				dot = { tick = 30, period = 1000, ticks = 7, canCrit = true } } }
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 173 then return { rank = 195, maxRank = 215, modifier = 0 } end
				return base(id)
			end
			G.bags[0] = { "bleeddagger" }
			G.measuredPPM = { [99726] = 40 }
			local ns = loadAll(G)
			local A, Sc = ns.Advisor, ns.Score
			local st = A.State()
			local res = A.Evaluate("bleeddagger", { kind = "bag", bag = 0, slot = 1 })
			T.eq(res.slot, 16, "the dagger goes into the main hand"); T.eq((Sc.MeleeSkills(res.newSet, st.ctx)), -20)
			local rates, hitsOf, outcome = A.ModelProcRates(res)
			T.eq(hitsOf, "newSet"); T.eq(outcome, st.ctx.procOutcomeFor(-20), "the dagger's main hand skill's outcome")
			local rec = ns.Items.Get("bleeddagger")
			local own = string.format("%.1f", Sc.DotTicks(rec.procs[1].dot, rates[1], outcome[2].land, 0))
			local worn = string.format("%.1f", Sc.DotTicks(rec.procs[1].dot, rates[1], st.ctx.procOutcome[2].land, 0))
			local whole = string.format("%.1f", Sc.DotTicks(rec.procs[1].dot, rates[1], 1, 0))
			T.truthy(own ~= worn and own ~= whole, "the skill's land shows: " .. own .. " / " .. worn .. " / " .. whole)
			local t = {}
			for i, l in ipairs(A.Explain("bleeddagger", { kind = "bag", bag = 0, slot = 1 })) do t[i] = l[1] end
			local all = table.concat(t, "\n")
			T.truthy(all:find("HGA: урон со временем учтён: 30 ед. × 7 тиков за 7 с (" .. own .. " тика между срабатываниями), ", 1, true), all)
			T.eq(#G.reportedErrors, 0)
		end },
		-- The tooltip of a damage over time (raid-mode design 17.4): «урон со временем учтён: N ед. × M тиков за S с (E тика
		-- между срабатываниями), <the rate text>», the ticks' noun in the form of M (тик, тика, тиков: A.RuPlural), E =
		-- Score.DotTicks at the proc's rate there and its application's chance; a dot alone has no direct line, and its line is
		-- counted (effect.linked); a direct part with a dot shows both lines (made-up bows, whose chance on hit rolls on the
		-- shots outside the Survival branch: a poison of 24 every 1 s for 7 s, measured 1.5 a minute; a fireball of 40 - 60
		-- with 6 every 2 s, 3 ticks)
		{ "dot tooltip: the ticks, the duration and the ticks between procs at the proc's rate; a direct part with a dot shows both", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.dotbow = { info = { 99724, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Лук яда"), ln("Дальний бой", "Лук"),
				ln("Урон: 50-80", "Скорость 2,60"), ln("(25,0 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: поражает цель ядом, нанося 24 ед. урона от сил природы раз в 1 сек. в течение 7 сек.") },
				api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 } }
			G.items.firebow = { info = { 99725, "INVTYPE_RANGED", 2, 2 }, lines = { ln("Лук огня"), ln("Дальний бой", "Лук"),
				ln("Урон: 50-80", "Скорость 2,60"), ln("(25,0 ед. урона в секунду)"),
				ln("Возможный эффект при попадании: наносит 40 - 60 ед. урона от огня и еще 18 ед. урона в течение 6 сек.") },
				api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 } }
			G.procData[99724] = { { trigger = 990026, kind = "hit", spell = 990026, avg = 0, min = 0, max = 0, school = 8, defense = 1, crit = true,
				dot = { tick = 24, period = 1000, ticks = 7, canCrit = true } } }
			G.procData[99725] = { { trigger = 990027, kind = "hit", spell = 990027, avg = 50, min = 40, max = 60, school = 4, defense = 1, crit = true,
				dot = { tick = 6, period = 2000, ticks = 3, canCrit = true } } }
			G.measuredPPM = { [99724] = 1.5, [99725] = 1.5 }
			G.bags[0] = { "dotbow", "firebow" }
			local ns = loadAll(G)
			local A = ns.Advisor
			local function explain(link, slot)
				local t = {}
				for i, l in ipairs(A.Explain(link, { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
				return table.concat(t, "\n")
			end
			local res = A.Evaluate("dotbow", { kind = "bag", bag = 0, slot = 1 })
			local rates, hitsOf, outcome = A.ModelProcRates(res)
			T.truthy(rates[1] > 0, "priced"); T.eq(hitsOf, res.newSet and "newSet" or "worn")
			local rec = ns.Items.Get("dotbow")
			T.eq(#rec.procs, 1); T.eq(rec.procs[1].avg, nil); T.eq(rec.procs[1].dot.tick, 24)
			local n = ns.Score.DotTicks(rec.procs[1].dot, rates[1], outcome[1].land, 0)
			local all = explain("dotbow", 1)
			local want = string.format("HGA: урон со временем учтён: 24 ед. × 7 тиков за 7 с (%.1f тика между срабатываниями), 1.50/мин на базовой скорости оружия — замер по логам; %s%.2f/мин)",
				n, hitsOf == "newSet" and "если надеть — ~" or "с твоими атаками сейчас ~", rates[1])
			T.truthy(all:find(want:sub(1, -2), 1, true), want .. "\n" .. all)
			T.eq(all:find("эффект при попадании учтён как оценка", 1, true), nil, "a dot alone: no direct line")
			T.eq(all:find("эффекты не учтены", 1, true), nil, "the linked dot line is counted")
			local fire = explain("firebow", 2)
			T.truthy(fire:find("HGA: эффект при попадании учтён как оценка (1.50/мин на базовой скорости оружия — замер по логам;", 1, true), fire)
			T.truthy(fire:find("HGA: урон со временем учтён: 6 ед. × 3 тика за 6 с (", 1, true), fire)
			-- the value: the bow's delta holds the dot
			T.truthy(res.delta ~= nil)
			-- the noun's form by the count: one (1, 21, 101), few (2-4, 22-24), many (0, 5-20, 25-30, 111-114)
			local P = A.RuPlural
			local want = { [0] = "c", "a", "b", "b", "b", "c", "c", "c", "c", "c", "c", "c", "c", "c", "c", "c", "c", "c", "c", "c", "c",
				"a", "b", "b", "b", "c" }
			for n = 0, 25 do T.eq(P(n, "a", "b", "c"), want[n], "form of " .. n) end
			for n, form in pairs({ [101] = "a", [111] = "c", [112] = "c", [114] = "c", [121] = "a", [122] = "b" }) do
				T.eq(P(n, "a", "b", "c"), form, "form of " .. n)
			end
			T.eq(#G.reportedErrors, 0, table.concat(G.reportedErrors, " | "))
		end },
		-- A linked equip aura with a stated procs-per-minute rate (SpellProcsPerMinute) names it in its tooltip line, at the
		-- speed of the hand that hits (a made-up ring, "Атаки дальнего боя могут нанести 20 - 30 ед. урона": Parse hits
		-- "ranged"; the env's entry: mask 0x140, 2 a minute)
		{ "procs: a linked equip aura's stated rate in its tooltip line", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.ppmring = { info = { 99712, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо"), ln("Палец"),
				ln("Если на персонаже: Атаки дальнего боя могут нанести 20 - 30 ед. урона.") }, api = {} }
			G.procData[99712] = { { trigger = 990018, kind = "equip", mask = 320, chance = 100, ppm = 2, icd = 0, spell = 990019, avg = 25, min = 20, max = 30, school = 1, defense = 3, crit = true } }
			G.bags[0] = { "ppmring" }
			local ns = loadAll(G)
			local A = ns.Advisor
			local res = A.Evaluate("ppmring", { kind = "bag", bag = 0, slot = 1 })
			local st = A.State()
			local r = st.ctx.landedHitsFor(res.newSet).ranged
			local rate = 2 * r.speed * (r.swings + r.specials)
			T.near(A.ModelProcRates(res)[1], rate, 1e-12, "2 a minute at the bow's speed on its shots and the dives")
			local t = {}
			for i, l in ipairs(A.Explain("ppmring", { kind = "bag", bag = 0, slot = 1 })) do t[i] = l[1] end
			local all = table.concat(t, "\n")
			T.truthy(all:find(string.format("HGA: эффект при попадании учтён как оценка (2.00/мин на скорости бьющей руки — данные DB2; если надеть — ~%.2f/мин)", rate), 1, true), all)
			T.eq(#G.reportedErrors, 0)
		end },
		-- stats-gear-4: Earthstrike 21180 (Game/UseData.lua: +280 attack power for 20 s every 2 min)
		{ "stats-gear-4: a Use trinket is priced over its uptime; a Use line that is no stat buff stays not counted", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.earthstrike = { info = { 21180, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Земной удар"), ln("Аксессуар"),
				ln("Использование: Увеличивает силу атаки на 280 ед. на 20 сек.") }, api = {} }
			G.items.stamtrinket = { info = { 60002, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Талисман"), ln("Аксессуар"), ln("+10 к выносливости") },
				api = { ITEM_MOD_STAMINA_SHORT = 10 } }
			G.items.healtrinket = { info = { 60003, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Флакон"), ln("Аксессуар"),
				ln("Использование: Восстанавливает 100 ед. здоровья.") }, api = {} }
			-- Kiss of the Spider 22954 has a Use buff in UseData: a tooltip without its Use line is reported
			G.items.kiss = { info = { 22954, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Поцелуй паука"), ln("Аксессуар") }, api = {} }
			G.bags[0] = { "earthstrike", "stamtrinket", "healtrinket", "kiss" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local function explain(link, slot)
				local texts = {}
				for i, l in ipairs(ns.Advisor.Explain(link, { kind = "bag", bag = 0, slot = slot })) do texts[i] = l[1] end
				return table.concat(texts, "\n")
			end
			local es = ns.Advisor.Evaluate("earthstrike", { kind = "bag", bag = 0, slot = 1 })
			-- at the Use weight of attack power (Model.Weights W.AP_USE: the pet keeps its summon's attack power, the user's
			-- answer O6), below W.AP with the env's pet out
			T.near(es.delta, 280 * 20 / 120 * st.W.AP_USE, 1e-9, "280 attack power a sixth of the time")
			T.truthy(st.W.AP_USE < st.W.AP - 0.01, "the pet's share left out")
			T.eq(es.verdict, "better")
			T.eq(ns.Advisor.Evaluate("stamtrinket", { kind = "bag", bag = 0, slot = 2 }).verdict, "better2", "Stamina: survival only")
			local esText = explain("earthstrike", 1)
			T.truthy(esText:find("HGA: «Использование» учтено как оценка: 20 сек%. раз в 2 мин%. — в среднем 17%% времени"), esText)
			T.eq(esText:find("эффекты не учтены"), nil, esText)
			T.near(ns.Advisor.Evaluate("healtrinket", { kind = "bag", bag = 0, slot = 3 }).delta, 0, 1e-9)
			local healText = explain("healtrinket", 3)
			T.truthy(healText:find("HGA: эффекты не учтены: 1 %(смотри сам%)"), healText)
			T.eq(#G.reportedErrors, 0)
			explain("kiss", 4)
			T.eq(#G.reportedErrors, 1); T.truthy(G.reportedErrors[1]:find("no Use line"), G.reportedErrors[1])
		end },
		-- Serenity Field 272439 (Game/UseData.lua: Spirit 72 for 15 s every 6 min): levelling weighs Spirit at 0 and its tie-break
		-- reads no Use buff (Score.UsePriced), so its Use line stays not counted there; the raid fight prices it (name from
		-- ItemSparse 272439)
		{ "a Use buff of Spirit alone: not counted while levelling, priced through the raid fight", function()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			for _, case in ipairs({ { 43, false }, { 60, true } }) do
				local G = env()
				G.UnitLevel = function() return case[1] end
				G.items.sf = { info = { 272439, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Поле безмятежности"), ln("Аксессуар"),
					ln("Использование: Увеличивает дух на 72 ед. на 15 сек.") }, api = {} }
				G.bags[0] = { "sf" }
				local ns = loadAll(G)
				settlePet(G)
				local texts = {}
				for i, l in ipairs(ns.Advisor.Explain("sf", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
				local all = table.concat(texts, "\n")
				local r = ns.Advisor.Evaluate("sf", { kind = "bag", bag = 0, slot = 1 })
				T.eq(ns.Score.UsePriced(ns.UseData[272439], case[2] and "raid" or "level"), case[2])
				if case[2] then
					T.truthy(all:find("HGA: «Использование» учтено как оценка: 15 сек. раз в 6 мин. — в бою 180 с 1 раз(а)", 1, true), all)
					T.eq(all:find("эффекты не учтены", 1, true), nil, all)
					T.truthy(r.delta > 0, "the raid fight prices its Spirit")
				else
					T.eq(all:find("учтено как оценка", 1, true), nil, all)
					T.truthy(all:find("HGA: эффекты не учтены: 1 (смотри сам)", 1, true), all)
					T.eq(r.delta, 0, "Spirit at 0 while levelling")
				end
				T.eq(#G.reportedErrors, 0)
			end
		end },
		-- Weakness Analyzer 272438: its crit buff ends at the first crit (spell 1291101, SpellAuraOptions ProcCharges 1),
		-- so Game/UseData.lua has no entry for it; name from ItemSparse 272438, Use text from the ruRU Spell.csv row 1291101
		{ "a Use buff that a crit uses up is not priced; its Use line stays not counted", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.analyzer = { info = { 272438, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Weakness Analyzer"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность критического удара заклинаний и атак на 5% на 20 сек. или до тех пор, "
					.. "пока вы не нанесете критический удар заклинанием или атакой прямого действия.") }, api = {} }
			G.bags[0] = { "analyzer" }
			local ns = loadAll(G)
			T.eq(ns.Items.Get("analyzer").use, nil)
			T.near(ns.Advisor.Evaluate("analyzer", { kind = "bag", bag = 0, slot = 1 }).delta, 0, 1e-9)
			local texts = {}
			for i, l in ipairs(ns.Advisor.Explain("analyzer", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
			local all = table.concat(texts, "\n")
			T.truthy(all:find("HGA: эффекты не учтены: 1 %(смотри сам%)"), all)
			T.eq(all:find("«Использование» учтено"), nil, all)
			T.eq(#G.reportedErrors, 0)
		end },
		-- stats-gear-10: SpellItemEnchantment 8720 on the worn bow, 853 Beastslaying on a bag sword
		{ "stats-gear-10: the worn bow's crit scope counts; Beastslaying is noted at the beasts' share on every strike and shot", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local plain = {}
			for i, l in ipairs(G.items.bow.lines) do plain[i] = l end
			G.items.plainbow = { info = { 43, "INVTYPE_RANGED", 2, 2 }, lines = plain, api = G.items.bow.api }
			G.items.bow.lines[#G.items.bow.lines + 1] = { leftText = "Чары: +2% к вероятности критического удара", leftColor = Wc }
			G.items.beastsword = { info = { 44, "INVTYPE_WEAPON", 2, 7 }, lines = { { leftText = "Меч", leftColor = Wc },
				{ leftText = "Одноручное", rightText = "Меч", leftColor = Wc, rightColor = Wc },
				{ leftText = "Урон: 40-75", rightText = "Скорость 2,60", leftColor = Wc, rightColor = Wc },
				{ leftText = "(22,1 ед. урона в секунду)", leftColor = Wc }, { leftText = "Чары: +6 к убийству животных", leftColor = Wc } },
				api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 22.1 } }
			G.bags[0] = { "plainbow", "beastsword" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(ns.Items.Get("bow").stats.CRIT_RANGED, 2); T.eq(ns.Items.Get("bow").stats.CRIT, nil); T.eq(#ns.Items.Get("bow").unparsed, 0)
			local r = ns.Advisor.Evaluate("plainbow", { kind = "bag", bag = 0, slot = 1 })
			T.near(r.delta, -2 * st.W.CRIT_RANGED, 1e-9, "without the scope: 2% ranged crit less")
			local sword = ns.Items.Get("beastsword")
			T.eq(sword.stats.BEAST_SLAYING, 6); T.eq(#sword.unparsed, 0)
			local texts = {}
			for i, l in ipairs(ns.Advisor.Explain("beastsword", { kind = "bag", bag = 0, slot = 2 })) do texts[i] = l[1] end
			local all = table.concat(texts, "\n")
			T.truthy(all:find("HGA: «+6 к убийству животных» учтено по зверям (доля 30%) на всех ударах оружием и выстрелах (оценка)", 1, true), all)
			T.eq(all:find("нераспознанных"), nil, all)
		end },
		-- Beastslaying is flat damage on every weapon strike and shot of the hunter (Model.Parts flat), at the share of mobs
		-- that are beasts (Model.AP_CREATURE_SHARE 0.3): the tooltip line says so for every branch, the weave or not
		{ "Beastslaying's tooltip line: the beasts' share on every weapon strike and shot, whatever the branch", function()
			local function explain(tree)
				local G = env()
				if tree then tree(G) end
				local Wc = { r = 1, g = 1, b = 1 }
				G.items.beastsword = { info = { 44, "INVTYPE_WEAPON", 2, 7 }, lines = { { leftText = "Меч", leftColor = Wc },
					{ leftText = "Одноручное", rightText = "Меч", leftColor = Wc, rightColor = Wc },
					{ leftText = "Урон: 40-75", rightText = "Скорость 2,60", leftColor = Wc, rightColor = Wc },
					{ leftText = "(22,1 ед. урона в секунду)", leftColor = Wc }, { leftText = "Чары: +6 к убийству животных", leftColor = Wc } },
					api = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 22.1 } }
				G.bags[0] = { "beastsword" }
				local ns = loadAll(G)
				local texts = {}
				for i, l in ipairs(ns.Advisor.Explain("beastsword", { kind = "bag", bag = 0, slot = 1 })) do texts[i] = l[1] end
				T.eq(#G.reportedErrors, 0)
				return table.concat(texts, "\n"), ns.Advisor.State()
			end
			local line = "HGA: «+6 к убийству животных» учтено по зверям (доля 30%) на всех ударах оружием и выстрелах (оценка)"
			local bm, stBM = explain()
			T.eq(stBM.snap.survival, false)
			T.truthy(bm:find(line, 1, true), bm)
			T.eq(bm:find("ближнем бою", 1, true), nil, bm)
			local sv, stSV = explain(survivalTree)
			T.eq(stSV.snap.survival, true)
			T.truthy(sv:find(line, 1, true), sv)
		end },
		{ "slash commands run", function()
			local G = env(); local ns = loadAll(G)
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.truthy(ns.db.dump and ns.db.dump.equipped["16"], "dump written")
			T.eq(ns.db.dump.setHit, 0, "no set worn: no set hit")
			T.truthy(#G.printed > 3, "printed")
		end },
		{ "pre-raid window: lists what is missing, owned items (worn, bags, bank) drop out", function()
			local G = env(); local ns = loadAll(G)
			local UI = ns.PreRaidUI
			G.owned.worn[13340] = true; G.owned.bags[15411] = true; G.owned.bank[13023] = true
			T.eq(UI.Where(13340), "надето"); T.eq(UI.Where(15411), "в сумках"); T.eq(UI.Where(13023), "в банке")
			T.eq(UI.Where(22232), nil, "missing")
			G.SlashCmdList.HUNTERGEARADVISOR("preraid")
			local f = G.HunterGearAdvisorPreRaid
			T.truthy(f and f.shown, "window shown")
			f.scripts.OnShow(f)
			T.eq(#G.reportedErrors, 0, "no errors: " .. tostring(G.reportedErrors[1]))
		end },
		{ "pre-raid window: cards show name, tag, prices; owned rows only with the checkbox; names arrive later", function()
			local G = env()
			G.unloaded = { [15411] = true }
			local ns = loadAll(G)
			local made = {}
			local create = G.CreateFrame
			G.CreateFrame = function(kind, name, parent, template)
				local f = create(kind, name, parent, template)
				made[#made + 1] = f
				local cfs = f.CreateFontString
				f.CreateFontString = function(self, ...) local t = cfs(self, ...); made[#made + 1] = t; return t end
				return f
			end
			G.owned.worn[13340] = true
			G.SlashCmdList.HUNTERGEARADVISOR("preraid")
			G.HunterGearAdvisorPreRaid.scripts.OnShow(G.HunterGearAdvisorPreRaid) -- the stub does not fire OnShow
			local function texts()
				local out = {}
				for _, w in ipairs(made) do
					if w.kind == "FontString" and w.text and w.shown and (not w.parent or w.parent:IsVisible()) then
						out[#out + 1] = (w.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
					end
				end
				return table.concat(out, string.char(10))
			end
			local t = texts()
			T.truthy(t:find("Собрано 1 из 16", 1, true), "progress count")
			T.truthy(t:find("item252605", 1, true) and t:find("КРАФТ", 1, true), "craft card")
			T.truthy(t:find("Стоимость крафта", 1, true), "price row")
			T.truthy(t:find("предмет 15411", 1, true), "unloaded name placeholder")
			T.truthy(G.requested[15411], "name requested")
			T.truthy(not t:find("item13340", 1, true), "worn item hidden")
			-- prices from Auctionator's API, asked under the addon's name: the bow's auction price with its age, the
			-- merchant's Black Dye in the craft cost (Black Dragonscale Helm: 2 x 50s, the other reagents unpriced)
			T.truthy(t:find("Цены — Auctionator", 1, true), "price source line")
			T.truthy(t:find("85з 41с (вчера) (BoE)", 1, true), "the bow's auction price and age")
			T.truthy(t:find("1з + реагенты без цены", 1, true), "the merchant's price in the helm's craft cost")
			T.truthy(#G.auctionatorCalls > 0, "Auctionator asked")
			for _, call in ipairs(G.auctionatorCalls) do
				T.eq(call[1], "HunterGearAdvisor", "callerID: the addon's name")
				T.eq(type(call[2]), "number", "the item id a number")
			end
			-- the name arrives: ITEM_DATA_LOAD_RESULT redraws the window
			G.unloaded = {}
			G.fire("ITEM_DATA_LOAD_RESULT", 15411, true)
			t = texts()
			T.truthy(t:find("item15411", 1, true) and not t:find("предмет 15411", 1, true), "name filled after load")
			-- the answer ends the request: a name the cache has lost again is asked for again
			G.requested = {}
			G.unloaded = { [15411] = true }
			ns.PreRaidUI.Refresh()
			T.truthy(G.requested[15411], "asked again after the answer")
			G.unloaded = {}
			G.fire("ITEM_DATA_LOAD_RESULT", 15411, true)
			-- the checkbox shows owned items with their place
			for _, w in ipairs(made) do
				if w.kind == "CheckButton" then w.GetChecked = function() return true end; w.scripts.OnClick(w) end
			end
			t = texts()
			T.truthy(t:find("item13340", 1, true) and t:find("есть: надето", 1, true), "owned shown with place")
			-- the list gets shorter while scrolled down: the offset is clamped to the new range
			local scroll
			for _, w in ipairs(made) do if w.kind == "ScrollFrame" then scroll = w end end
			scroll.vrange, scroll.vscroll = 300, 900
			ns.PreRaidUI.Refresh()
			T.eq(scroll.vscroll, 300, "scroll clamped")
			scroll.vscroll = 100
			scroll.scripts.OnMouseWheel(scroll, -1)
			T.eq(scroll.vscroll, 148, "wheel scrolls down by one step")
			scroll.scripts.OnMouseWheel(scroll, -100)
			T.eq(scroll.vscroll, 300, "wheel stops at the end")
			-- an id the client cannot load is reported once and not requested again (no redraw loop)
			G.requested = {}
			G.unloaded = { [13967] = true }
			ns.PreRaidUI.Refresh()
			T.truthy(G.requested[13967], "requested")
			G.fire("ITEM_DATA_LOAD_RESULT", 13967, false)
			T.eq(#G.reportedErrors, 1, "failure reported")
			T.truthy(G.reportedErrors[1]:find("13967", 1, true), "failure names the id")
			G.requested = {}
			ns.PreRaidUI.Refresh()
			T.eq(G.requested[13967], nil, "not requested again")
			T.truthy(texts():find("предмет 13967 (нет в клиенте)", 1, true), "shown as unknown")
			G.reportedErrors = {}
			-- without Auctionator: the line says so, prices are missing (НА, no craft cost), never 0
			G.Auctionator = nil
			ns.PreRaidUI.Refresh()
			t = texts()
			T.truthy(t:find("Auctionator не загружен — цен аукциона и торговцев нет", 1, true), "no Auctionator is said")
			T.truthy(not t:find("Цены — Auctionator", 1, true), "no price source claimed")
			T.truthy(t:find("НА (BoE)", 1, true) and not t:find("85з", 1, true), "the bow has no price")
			T.truthy(t:find("нет цен на реагенты", 1, true) and not t:find("реагенты без цены", 1, true), "no craft cost")
			T.eq(#G.reportedErrors, 0, "no errors: " .. tostring(G.reportedErrors[1]))
		end },
		-- Game/PreRaid.lua's thin scroll bar: the thumb's length is the share of the list in view, at least 24, its top moves
		-- along the free track (the stub's bar and scroll frame are 100 high); the window frame (windowFrame): centered,
		-- strata HIGH, kept on the screen, dragged by the left button, closed by Esc (UISpecialFrames)
		{ "pre-raid window: the thumb's length and place follow the list; the window is dragged and closed by Esc", function()
			local G = env(); local ns = loadAll(G)
			local made = {}
			local create = G.CreateFrame
			G.CreateFrame = function(kind, name, parent, template)
				local f = create(kind, name, parent, template)
				made[#made + 1] = f
				if name == "HunterGearAdvisorPreRaid" then
					f.set = {}
					for _, m in ipairs({ "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag" }) do
						f[m] = function(self, v) self.set[m] = v end
					end
					f.SetPoint = function(self, ...) self.set.point = { ... } end
					f.StartMoving = function(self) self.set.moving = true end
					f.StopMovingOrSizing = function(self) self.set.moving = false end
				end
				-- this scroll frame reports a new range as soon as its child is set, the earliest a client could: the bar
				-- that OnScrollRangeChanged draws has to exist by then
				if kind == "ScrollFrame" then
					f.SetScrollChild = function(self, child)
						self.child = child
						if self.scripts.OnScrollRangeChanged then self.scripts.OnScrollRangeChanged(self, 0, 0) end
					end
				end
				return f
			end
			G.SlashCmdList.HUNTERGEARADVISOR("preraid")
			local f = G.HunterGearAdvisorPreRaid
			T.truthy(f, "the window made")
			T.eq(f.set.SetFrameStrata, "HIGH"); T.eq(f.set.SetClampedToScreen, true); T.eq(f.set.SetMovable, true)
			T.eq(f.set.EnableMouse, true); T.eq(f.set.RegisterForDrag, "LeftButton")
			T.eq(f.set.point[1], "CENTER", "centered"); T.eq(f.set.point[2], G.UIParent)
			f.scripts.OnDragStart(f); T.eq(f.set.moving, true, "a drag moves it")
			f.scripts.OnDragStop(f); T.eq(f.set.moving, false, "and stops")
			local esc = false
			for _, n in ipairs(G.UISpecialFrames) do esc = esc or n == "HunterGearAdvisorPreRaid" end
			T.truthy(esc, "Esc closes it")
			local scroll, thumb
			for _, w in ipairs(made) do
				if w.kind == "ScrollFrame" then scroll = w end
				if w.scripts.OnMouseDown and w.scripts.OnUpdate then thumb = w end
			end
			local bar = thumb.parent
			thumb.SetPoint = function(self, ...) self.point = { ... } end
			scroll.vrange, scroll.vscroll = 300, 150
			ns.PreRaidUI.Refresh()
			T.eq(bar.shown, true, "bar shown for a long list")
			T.eq(thumb.height, 25, "100 x 100 / (100 + 300)")
			T.eq(thumb.point[1], "TOP"); T.eq(thumb.point[2], bar); T.eq(thumb.point[5], -37.5, "(100 - 25) x 150 / 300")
			scroll.vrange, scroll.vscroll = 10000, 0
			ns.PreRaidUI.Refresh()
			T.eq(thumb.height, 24, "at least 24"); T.eq(thumb.point[5], 0, "at the top")
			-- the wheel up at the top: the list stays at 0, the thumb at the track's top
			scroll.vrange, scroll.vscroll = 300, 0
			scroll.scripts.OnMouseWheel(scroll, 1)
			T.eq(scroll.vscroll, 0, "no offset above the top"); T.eq(thumb.point[5], 0, "the thumb at the top")
			scroll.vrange, scroll.vscroll = 0, 40
			ns.PreRaidUI.Refresh()
			T.eq(bar.shown, false, "no bar when the list fits"); T.eq(scroll.vscroll, 0, "offset back to 0")
		end },
		{ "pre-raid AtlasLoot: item, craft spell and boss npc pages are selected; missing page is said", function()
			local G = env(); local ns = loadAll(G)
			local UI = ns.PreRaidUI
			UI.OpenAtlas({ module = "AtlasLootClassic_DungeonsAndRaids", item = 13340 }, "Плащ")
			T.eq(G.atlasSel.module, "AtlasLootClassic_DungeonsAndRaids"); T.eq(G.atlasSel.inst, "Stratholme"); T.eq(G.atlasSel.boss, 2)
			T.truthy(G.atlasFrame.shown, "AtlasLoot shown")
			UI.OpenAtlas({ module = "AtlasLootClassic_Crafting", spell = 1255015 }, "Броня")
			T.eq(G.atlasSel.inst, "Leatherworking"); T.eq(G.atlasSel.boss, 1)
			UI.OpenAtlas({ module = "AtlasLootClassic_DungeonsAndRaids", npc = 10429 }, "Пластина")
			T.eq(G.atlasSel.inst, "UpperBlackrockSpire")
			G.atlasSel.boss = nil
			UI.OpenAtlas({ module = "AtlasLootClassic_DungeonsAndRaids", item = 18296 }, "Наручи")
			T.eq(G.atlasSel.inst, "DireMaulEast"); T.eq(G.atlasSel.extra, 2, "trash goes to the extra list"); T.eq(G.atlasSel.boss, nil, "not the boss list")
			G.atlasRefuse = true
			UI.OpenAtlas({ module = "AtlasLootClassic_DungeonsAndRaids", item = 13340 }, "Плащ")
			T.truthy(G.printed[#G.printed]:find("не выбрал страницу", 1, true), "a refused selection is printed")
			G.atlasRefuse = nil
			G.AtlasLoot.Loader.LoadModule = function() return "InCombat" end
			UI.OpenAtlas({ module = "AtlasLootClassic_DungeonsAndRaids", item = 13340 }, "Плащ")
			T.truthy(G.printed[#G.printed]:find("откроет страницу сам", 1, true), "combat text")
			G.AtlasLoot.Loader.LoadModule = function() return nil end
			UI.OpenAtlas({ module = "AtlasLootClassic_DungeonsAndRaids", item = 13340 }, "Плащ")
			T.truthy(G.printed[#G.printed]:find("не загружен или не установлен", 1, true), "nil from LoadModule is printed")
			G.AtlasLoot.Loader.LoadModule = function(_, m, fn) fn(m); return true end
			local before = #G.printed
			UI.OpenAtlas({ module = "AtlasLootClassic_PvP", item = 22673 }, "Поножи")
			T.truthy(#G.printed > before and G.printed[#G.printed]:find("нет страницы", 1, true), "not found is printed")
			G.AtlasLoot = nil
			UI.OpenAtlas({ module = "AtlasLootClassic_PvP", item = 22673 }, "Поножи")
			T.truthy(G.printed[#G.printed]:find("AtlasLoot не загружен", 1, true), "no AtlasLoot is printed")
		end },
		{ "pre-raid Shift-click: searches the open auction house (Forever's and the classic window), else the game's click", function()
			local G = env(); loadAll(G)
			local made = {}
			local create = G.CreateFrame
			G.CreateFrame = function(...) local f = create(...); made[#made + 1] = f; return f end
			local base = G.C_Item.GetItemInfo
			G.C_Item.GetItemInfo = function(id)
				if id == 252939 then return "Выкройка: шлем", "|Hitem:252939|h[Выкройка: шлем]|h" end
				if id == 252605 then return "Шлем", "|Hitem:252605|h[Шлем]|h" end
				return base(id)
			end
			G.shift = true
			G.IsShiftKeyDown = function() return G.shift end
			G.IsModifiedClick = function() return G.shift end
			G.clicked = {}
			G.HandleModifiedItemClick = function(link) table.insert(G.clicked, link); return true end
			G.SlashCmdList.HUNTERGEARADVISOR("preraid")
			G.HunterGearAdvisorPreRaid.scripts.OnShow(G.HunterGearAdvisorPreRaid)
			local recipe, icon
			for _, f in ipairs(made) do
				if f.itemID == 252939 and f.scripts.OnClick then recipe = f end
				if f.itemID == 252605 and f.scripts.OnClick then icon = f end
			end
			T.truthy(recipe and icon, "recipe button and icon found")
			-- auction house closed: the game's own modified click (link into chat)
			recipe.scripts.OnClick(recipe)
			T.eq(G.clicked[1], "|Hitem:252939|h[Выкройка: шлем]|h", "chat link when the AH is closed")
			-- Forever's auction house (Blizzard_AuctionHouseFrame.lua): the frame's SetSearchText fills the search bar on
			-- the four buy pages and returns true, elsewhere it returns false; the bar's own SetSearchText writes its box
			-- on any page (Blizzard_AuctionHouseSearchBar.lua); the bar's button starts the search
			local M = { Buy = {}, ItemBuy = {}, CommoditiesBuy = {}, WoWTokenBuy = {}, ItemSell = {}, Auctions = {} }
			G.AuctionHouseFrameDisplayMode = M
			local function reset() G.searchText, G.searched = nil, nil end
			G.AuctionHouseFrame = { visible = true, IsVisible = function(f) return f.visible end,
				GetDisplayMode = function() return G.ahMode end,
				SetSearchText = function(_, text)
					local m = G.ahMode
					if m == M.Buy or m == M.ItemBuy or m == M.CommoditiesBuy or m == M.WoWTokenBuy then
						G.AuctionHouseFrame.SearchBar:SetSearchText(text)
						return true
					end
					return false
				end,
				SearchBar = { SetSearchText = function(_, text) G.searchText = text end,
					SearchButton = { Click = function() G.searched = true end } } }
			-- the Buy page: the name goes in and the search starts
			G.ahMode = M.Buy
			recipe.scripts.OnClick(recipe)
			T.eq(G.searchText, "Выкройка: шлем"); T.eq(G.searched, true, "search started")
			T.eq(#G.clicked, 1, "no chat link while searching")
			-- another buy page (an item's auctions): the name goes in, no search (it would change the page), the player is told
			reset(); G.ahMode = M.ItemBuy
			local printed = #G.printed
			icon.scripts.OnClick(icon)
			T.eq(G.searchText, "Шлем"); T.eq(G.searched, nil, "no search off the Buy page")
			T.eq(#G.printed, printed + 1, "one line")
			T.truthy(G.printed[#G.printed]:find("«Шлем» в строке поиска аукциона — нажми «Поиск».", 1, true), "told to search")
			-- the sell page has no search bar: nothing goes in, the player is told to go to the buy page
			reset(); G.ahMode = M.ItemSell
			icon.scripts.OnClick(icon)
			T.eq(G.searchText, nil, "no name in a hidden bar"); T.eq(G.searched, nil, "no search")
			T.truthy(G.printed[#G.printed]:find("открой страницу покупки и снова Shift-клик", 1, true), "told to open the buy page")
			T.eq(#G.clicked, 1, "no chat link at the auction house")
			-- a hidden auction house frame is not open: the game's click
			G.AuctionHouseFrame.visible = false
			icon.scripts.OnClick(icon)
			T.eq(#G.clicked, 2, "chat link when the frame is hidden")
			-- the classic window (Blizzard_AuctionUI): BrowseName keeps the name; AuctionFrameBrowse_Search on the Browse tab
			G.AuctionHouseFrame = nil
			G.AuctionFrame = { visible = true, IsVisible = function(f) return f.visible end }
			G.AuctionFrameBrowse = { visible = true, IsVisible = function(f) return f.visible end }
			G.BrowseName = { SetText = function(_, t) G.browseText = t end }
			G.AuctionFrameBrowse_Search = function() G.browsed = true end
			icon.scripts.OnClick(icon)
			T.eq(G.browseText, "Шлем"); T.eq(G.browsed, true, "classic search on the Browse tab")
			-- Browse hidden (another tab open): BrowseName gets the text, AuctionFrameBrowse_Search is not called, a chat line
			-- names the tab
			G.browseText, G.browsed = nil, nil
			G.AuctionFrameBrowse.visible = false
			recipe.scripts.OnClick(recipe)
			T.eq(G.browseText, "Выкройка: шлем"); T.eq(G.browsed, nil, "no search off the Browse tab")
			T.truthy(G.printed[#G.printed]:find("открой вкладку «Просмотр» и нажми «Поиск»", 1, true), "told to open Browse")
			-- a plain click on the recipe prints its link
			G.shift = false
			recipe.scripts.OnClick(recipe)
			T.truthy(G.printed[#G.printed]:find("Рецепт:", 1, true), "plain click prints the link")
			T.eq(#G.reportedErrors, 0, "no errors: " .. tostring(G.reportedErrors[1]))
		end },
		-- ns.ShowTooltip (Init.lua): hovering an item of the pre-raid window or of the swap list shows the game tooltip to
		-- its right with that item, leaving hides it; a click on an item whose data the client has not loaded asks for it
		{ "item tooltips of the pre-raid window and the swap list; a click on an item not loaded asks the client", function()
			local G = env(); local ns = loadAll(G)
			local made = {}
			local create = G.CreateFrame
			G.CreateFrame = function(...) local f = create(...); made[#made + 1] = f; return f end
			local tip = {}
			G.GameTooltip = {
				SetOwner = function(_, owner, anchor) tip.owner, tip.anchor = owner, anchor end,
				SetItemByID = function(_, id) tip.item = id end,
				SetHyperlink = function(_, link) tip.link = link end,
				Show = function() tip.shown = true end,
				Hide = function() tip.shown = false end,
			}
			G.SlashCmdList.HUNTERGEARADVISOR("preraid")
			G.HunterGearAdvisorPreRaid.scripts.OnShow(G.HunterGearAdvisorPreRaid)
			local icon
			for _, f in ipairs(made) do if f.itemID == 252605 and f.scripts.OnEnter then icon = f end end
			icon.scripts.OnEnter(icon)
			T.eq(tip.owner, icon); T.eq(tip.anchor, "ANCHOR_RIGHT"); T.eq(tip.item, 252605); T.eq(tip.shown, true)
			icon.scripts.OnLeave(icon)
			T.eq(tip.shown, false, "hidden on leave")
			tip = {}
			local none = { itemID = nil }
			icon.scripts.OnEnter(none)
			T.eq(tip.owner, nil, "no item: no tooltip")
			-- the swap list's row icon: the item's link
			ns.Invalidate()
			local banner = G.HunterGearAdvisorSwapBanner
			banner:Click()
			local row
			for _, rf in ipairs(banner.panel.rows) do if rf.shown and rf.data.slot == 18 then row = rf end end
			row.icon.scripts.OnEnter(row.icon)
			T.eq(tip.owner, row.icon); T.eq(tip.anchor, "ANCHOR_RIGHT"); T.eq(tip.link, "newbow"); T.eq(tip.shown, true)
			-- a click on an item the client has not loaded: asked for, the player told; the answer redraws, no error
			G.C_Item.GetItemInfo = function() return nil end
			G.requested = {}
			icon.scripts.OnClick(icon)
			T.truthy(G.requested[252605], "asked for")
			T.truthy(G.printed[#G.printed]:find("Данные предмета ещё не загружены", 1, true), "told")
			G.fire("ITEM_DATA_LOAD_RESULT", 252605, true)
			T.eq(#G.reportedErrors, 0, "no errors: " .. tostring(G.reportedErrors[1]))
		end },
		{ "pre-raid map button: user waypoint + super-track + world map on that zone", function()
			local G = env(); local ns = loadAll(G)
			ns.PreRaidUI.ShowOnMap({ name = "Криг Ботмяс", map = 1413, x = 65.0, y = 34.6 })
			T.eq(G.waypoint.m, 1413); T.near(G.waypoint.x, 0.65, 1e-9); T.near(G.waypoint.y, 0.346, 1e-9)
			T.eq(G.superTracked, true); T.eq(G.openedMap, 1413)
		end },
		-- /hga dump's target and caps follow the mode (Player.Snapshot: the target 0 below 60, +3 at 60): the expertise cap
		-- is the mob's dodge (Model.MobAvoid: Forever UI Camelot/PaperDollFrameStats.lua:15-20 BASE_ENEMY_DODGE_CHANCE, 5.0
		-- at +0, 6.5 at +3), the hit cap Model.HitCap (Core/Model.lua baseMiss: 5 at +0; 8 at +3, 5 + 0.2 x 15)
		-- The raid fight in /hga weights and /hga dump (raid-mode design 8, 6.7): after the mode line, Serpent Sting's and the
		-- hawks' uptime (Model.Fight's means) and the windows of Rapid Fire (5-20 s) and Bestial Wrath (5-23 and 125-143 s, the
		-- env's BM build with its pet); /hga dump's fight is the worn set's, with its Use buffs (the worn Earthstrike 21180,
		-- spell 25891: 5-25 and 125-145 s), its segments with their states, weights and the buffs' spells up, the windows and
		-- the means: the segments 0-5, 5-20, 20-23, 23-25, 25-35, 35-98, 98-125, 125-143, 143-145, 145-155 and 155-185 s, the last
		-- one 20 s at weight 1 and 10 s fading out to 0 (5 weighted seconds): 25. Levelling has neither line nor fight
		-- The mana never runs out here (GetManaRegen 300 a second in the casts and out of them: raid-mode design 7.5's rich
		-- regime, every cast at its rate and the second Bestial Wrath at 125 s)
		{ "/hga weights in raid names the fight's uptimes and windows; /hga dump has the worn set's fight; levelling neither", function()
			local G = env()
			raidLevel(G)
			G.GetManaRegen = function() return 300, 300 end
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.earthstrike = { info = { 21180, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Земной удар"), ln("Аксессуар"),
				ln("Использование: Увеличивает силу атаки на 280 ед. на 20 сек.") }, api = {} }
			G.equippedLinks[13] = "earthstrike"
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			local f = ns.Model.Fight(st.model)
			T.truthy(f.means.hawkUptime > 0.9 and f.means.serpentUptime > 0.9, "the env's hawks and Serpent Sting")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.eq(G.printed[2], string.format("|cff7fbf3fHGA:|r Serpent Sting висит %.0f%% боя, ястребы %.0f%%, Rapid Fire 5–20 с, Bestial Wrath 5–23 с, 125–143 с",
				f.means.serpentUptime * 100, f.means.hawkUptime * 100))
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump.fight
			T.truthy(d, "the dump's fight")
			local times = {}
			for i, s in ipairs(d.segments) do times[i] = s.t0 .. "-" .. s.t1 end
			-- Hunter's Mark's recast at 98 s (its 60 mana, raid-mode design 7.6) cuts a segment; the Major Frenzy Potion (O2 = (a),
			-- 7.4) is up 5-35 s and, the mana potion not fitting under the full pool at 125 s, 125-155 s
			T.eq(table.concat(times, ","), "0-5,5-20,20-23,23-25,25-35,35-98,98-125,125-143,143-145,145-155,155-185", "the segments")
			T.eq(d.segments[2].rf, true); T.eq(d.segments[2].bw, true, "5-20 s: Rapid Fire and Bestial Wrath")
			T.eq(#d.segments[2].uses, 2); T.eq(d.segments[2].uses[1], 25891, "5-20 s: Earthstrike's spell up")
			T.eq(d.segments[2].uses[2], 1251940, "and the Frenzy Potion's")
			T.eq(#d.segments[5].uses, 1); T.eq(d.segments[5].uses[1], 1251940, "25-35 s: the Frenzy Potion alone")
			T.eq(#d.segments[6].uses, 0, "35-98 s: no buff up"); T.eq(#d.segments[7].uses, 0, "98-125 s: no buff up")
			T.eq(d.segments[1].weight, 5); T.near(d.segments[11].weight, 25, 1e-12, "155-185 s: 20 + 5 weighted seconds")
			T.eq(d.uses[1][1][1], 5); T.eq(d.uses[1][2][1], 125, "Earthstrike's windows")
			T.eq(d.rapidFire[1][1], 5); T.eq(d.bestialWrath[2][1], 125)
			T.near(d.means.serpentUptime, f.means.serpentUptime, 1e-12, "an attack power buff moves no uptime")
			local G2 = env()
			G2.UnitLevel = function() return 59 end
			local ns2 = loadAll(G2)
			G2.printed = {}
			G2.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.eq(G2.printed[2]:find("Serpent Sting висит", 1, true), nil, "levelling: no fight line")
			G2.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.eq(ns2.db.dump.fight, nil, "levelling: no fight")
			T.eq(#G.reportedErrors, 0)
		end },
		-- The mana in /hga weights and /hga dump (raid-mode design 8, 7): after the fight's line, the mana line: the pool
		-- (UnitPowerMax 1725), the casting regen with the shares that come in combat (Model.Fight's mean: the env's live 3.15,
		-- Bestial Discipline 2/2 and no Rapid Recuperation or Resourcefulness), the regen out of the five-second rule (12.6),
		-- Judgement of Wisdom's mean income (O7 = (a)), the first time the mana runs out, the consumables (O2 = (a)): the mana
		-- potion's 2250 does not fit under 1725, so a second Frenzy Potion at 125 s; the rune's 1500 does, at its fit and 120 s
		-- later; what the first starved stretch buys (the HHA elements in part, no Serpent Sting, no Aimed Shot); the second
		-- Bestial Wrath bought from the second rune. The weights line names MP5, Spirit and mana beside Intellect, the
		-- tie-break line drops the mana. A pool of 1400 takes no rune and no second Bestial Wrath; regen 300 never runs out
		{ "/hga weights in raid names the mana, the consumables and what the starved regime buys; the mana weights; the raid tie-break; /hga dump has the fight's mana", function()
			local G = env()
			raidLevel(G)
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			local f = ns.Model.Fight(st.model)
			T.eq(f.manaPotion, nil, "1725: no room for the mana potion")
			T.eq(#f.runes, 2, "two runes")
			T.near(f.means.regenCast, 3.15, 1e-12, "the live casting regen, no share in combat past Bestial Discipline's")
			local starved
			for _, s in ipairs(f.segments) do
				if not starved and s.state.regime == "starved" and s.state.phase ~= "debt" then starved = s.state end
			end
			local share = starved.shares.hha
			T.truthy(share > 0 and share < 1, "the HHA elements in part")
			T.eq(starved.shares.serpent, 0); T.eq(starved.shares.aimed, 0)
			T.eq(#f.bestialWrath, 2); T.near(f.bestialWrath[2][1], f.runes[2], 1e-12, "the second Bestial Wrath with the second rune")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.eq(G.printed[2], string.format("|cff7fbf3fHGA:|r Serpent Sting висит %.0f%% боя, ястребы %.0f%%, Rapid Fire 5–20 с, Bestial Wrath 5–23 с, %.0f–%.0f с",
				f.means.serpentUptime * 100, f.means.hawkUptime * 100, f.bestialWrath[2][1], f.bestialWrath[2][2]))
			T.eq(G.printed[3], string.format("|cff7fbf3fHGA:|r мана: запас 1725, реген %.1f/с при кастах, 12.6/с без кастов 5 с, Judgement of Wisdom +%.1f/с; мана кончается на %.0f с; зелье маны не помещается на 125-й секунде — вместо него второй Frenzy Potion, руна на %.0f и %.0f с, Frenzy Potion 5–35 с, 125–155 с; без маны — только ястребы и Arcane (%.0f%% темпа), без Serpent Sting и Aimed Shot",
				f.means.regenCast, f.means.jow, f.oom[1], f.runes[1], f.runes[2], share * 100))
			local W = st.W
			local wl
			for _, l in ipairs(G.printed) do if l:find("урон (", 1, true) then wl = l end end
			T.truthy(wl:find(string.format("Инт %.2f, MP5 %.2f, Дух %.2f, мана %.2f,", W.INT, W.MP5, W.SPI, W.MANA), 1, true), wl)
			T.truthy(W.MP5 > 0 and W.SPI > 0 and W.MANA > 0, "the mana stats' raid weights")
			T.eq(G.printed[10], "|cff7fbf3fHGA:|r здоровье и броня — только при равном уроне; мана считается в уроне")
			-- the dump's fight: the mana's events and each segment's regime and pool
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump.fight
			T.near(d.oom[1], f.oom[1], 1e-12); T.eq(#d.runes, 2); T.eq(d.manaPotion, nil)
			T.eq(d.frenzyPotion[2][1], 125, "the second Frenzy Potion"); T.eq(d.costs.arcane, 189); T.near(d.means.jow, f.means.jow, 1e-12)
			T.eq(d.segments[1].regime, "rich"); T.eq(d.segments[1].m0, 1725, "the pool full at the start")
			local seen
			for _, s in ipairs(d.segments) do
				if s.regime == "starved" and s.phase == "buy" then seen = s end
			end
			T.near(seen.shares.hha, share, 1e-12, "a starved segment's shares"); T.truthy(seen.income > 0, "its income")
			T.eq(seen.m0, 0); T.truthy(d.segments[1].D > 0 and d.segments[1].J > 0 and d.segments[1].rc > 0, "the state's drain, income, regen")
			-- a pool of 1400: no rune fits (1500 and 5 s of regen), the income is all the HHA elements': one Bestial Wrath
			local G2 = env()
			raidLevel(G2)
			G2.UnitPowerMax = function() return 1400 end
			loadAll(G2)
			settlePet(G2)
			G2.printed = {}
			G2.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.truthy(G2.printed[2]:find("Bestial Wrath 5–23 с; второго не будет — нет маны", 1, true), G2.printed[2])
			T.truthy(G2.printed[3]:find("руна не помещается, Frenzy Potion 5–35 с, 125–155 с", 1, true), G2.printed[3])
			-- regen 300: the mana never runs out, no rune and no mana potion under a full pool
			local G3 = env()
			raidLevel(G3)
			G3.GetManaRegen = function() return 300, 300 end
			local ns3 = loadAll(G3)
			settlePet(G3)
			local f3 = ns3.Model.Fight(ns3.Advisor.State().model)
			G3.printed = {}
			G3.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.eq(G3.printed[3], string.format("|cff7fbf3fHGA:|r мана: запас 1725, реген %.1f/с при кастах, 300.0/с без кастов 5 с, Judgement of Wisdom +%.1f/с; мана не кончается; зелье маны не помещается на 125-й секунде — вместо него второй Frenzy Potion, руна не помещается, Frenzy Potion 5–35 с, 125–155 с",
				f3.means.regenCast, f3.means.jow))
			-- levelling: no mana line, no mana weight, the tie-break with the mana
			local G4 = env()
			G4.UnitLevel = function() return 59 end
			loadAll(G4)
			settlePet(G4)
			G4.printed = {}
			G4.SlashCmdList.HUNTERGEARADVISOR("weights")
			for _, l in ipairs(G4.printed) do
				T.eq(l:find("мана: запас", 1, true), nil, "levelling: no mana line")
				T.eq(l:find("MP5", 1, true), nil, "levelling: no MP5 weight")
			end
			T.truthy(G4.printed[#G4.printed - 1]:find("здоровье, броня, мана — только при равном уроне", 1, true), G4.printed[#G4.printed - 1])
			-- the env at 60 with a changed input, its /hga weights' fight line and mana line
			local function weights(mod)
				local Gx = env()
				raidLevel(Gx)
				mod(Gx)
				local nsx = loadAll(Gx)
				settlePet(Gx)
				local fx = nsx.Model.Fight(nsx.Advisor.State().model)
				Gx.printed = {}
				Gx.SlashCmdList.HUNTERGEARADVISOR("weights")
				T.eq(#Gx.reportedErrors, 0)
				return fx, Gx.printed[2], Gx.printed[3]
			end
			-- a pool of 2300, out of mana before 125 s: the mana potion's 2250 fits with 5 s of regen at 0
			local f5, _, l5 = weights(function(Gx) Gx.UnitPowerMax = function() return 2300 end end)
			T.eq(f5.manaPotion, 125)
			T.truthy(l5:find("; зелье маны на 125 с, руна на ", 1, true) and l5:find("Frenzy Potion 5–35 с;", 1, true), l5)
			-- no Summon Hawk (node 104966): Arcane Shot alone
			local f6, w6, l6 = weights(function(Gx) Gx.talentRanks[104966] = nil end)
			T.eq(f6.means.hawkUptime, 0)
			T.truthy(w6:find(", ястребов нет,", 1, true), w6)
			T.truthy(l6:find("без маны — только Arcane (", 1, true), l6)
			local _, _, l6b = weights(function(Gx) Gx.talentRanks[104966] = nil; Gx.GetManaRegen = function() return 12.6, 20 end end)
			T.truthy(l6b:find("без маны — только Arcane и Serpent Sting (", 1, true), l6b)
			-- no Bestial Wrath (node 104961): none, and no word of a second one
			local f7, w7 = weights(function(Gx) Gx.talentRanks[104961] = nil end)
			T.eq(#f7.bestialWrath, 0)
			T.truthy(w7:find("Bestial Wrath нет (нет таланта или пета)", 1, true), w7)
			T.eq(w7:find("второго не будет", 1, true), nil, w7)
			-- a pool of 200 (a made-up input below any level-60 pool, which the model takes) with 300 a second of regen: out of
			-- mana at 5 s by Rapid Fire's and Bestial Wrath's 306, the debt repaid at once and the regime rich after it, so the
			-- only starved stretch is a debt, which buys nothing
			local f8, _, l8 = weights(function(Gx) Gx.UnitPowerMax = function() return 200 end; Gx.GetManaRegen = function() return 300, 300 end end)
			T.eq(f8.oom[1], 5)
			T.truthy(l8:find("; мана кончается на 5 с;", 1, true), l8)
			T.truthy(l8:find("; без маны — ничего, только автоатаки и пет, без ястребов и Arcane, Serpent Sting и Aimed Shot", 1, true), l8)
			-- a pool of 1740 with 48 a second of regen in the casts: the mana reaches 0 where the rune fits at 0 mana, so it
			-- comes back at that instant and no stretch is starved
			local f9, _, l9 = weights(function(Gx) Gx.UnitPowerMax = function() return 1740 end; Gx.GetManaRegen = function() return 57.45, 48 end end)
			T.truthy(#f9.oom > 0 and f9.runes[#f9.runes] == f9.oom[1], "the rune at the instant the mana runs out")
			for _, s in ipairs(f9.segments) do T.eq(s.state.regime, "rich", "no starved stretch") end
			T.truthy(l9:find(string.format("; мана доходит до 0 на %.0f с и сразу возвращается (руна, зелье маны или реген баффа); зелье маны", f9.oom[1]), 1, true), l9)
			-- a pool of 1730 with 46 in the casts: the rune answers the first time the mana reaches 0, the second starves: the
			-- mana runs out there
			local f12, _, l12 = weights(function(Gx) Gx.UnitPowerMax = function() return 1730 end; Gx.GetManaRegen = function() return 55.45, 46 end end)
			local out12
			for _, s in ipairs(f12.segments) do
				if s.state.regime == "starved" then out12 = out12 or s.t0 end
			end
			T.truthy(f12.runes[1] == f12.oom[1] and out12 > f12.oom[1] + 1 and out12 == f12.oom[2], "the second time starves")
			T.truthy(l12:find(string.format("; мана кончается на %.0f с;", out12), 1, true), l12)
			-- a part of the rate under 1% or above 99% (whole percent would print 1% and 99%): the casting regen at 11.475
			-- (Serpent Sting just bought, 0.58%) and 11.15 (the HHA elements just short of whole, 99.34%)
			local function firstBuy(fx)
				for _, s in ipairs(fx.segments) do
					if s.state.regime == "starved" and s.state.phase ~= "debt" then return s.state end
				end
			end
			local f10, _, l10 = weights(function(Gx) Gx.GetManaRegen = function() return 12.6, 11.475 end end)
			local s10 = firstBuy(f10)
			T.truthy(s10.shares.hha == 1 and s10.shares.serpent > 0.005 and s10.shares.serpent < 0.01, "Serpent Sting under 1%")
			T.truthy(l10:find("без маны — только ястребы и Arcane и Serpent Sting (<1% темпа), без Aimed Shot", 1, true), l10)
			local f11, _, l11 = weights(function(Gx) Gx.GetManaRegen = function() return 12.6, 11.15 end end)
			local s11 = firstBuy(f11)
			T.truthy(s11.shares.hha > 0.99 and s11.shares.hha < 0.995, "the HHA elements above 99%")
			T.truthy(l11:find("только ястребы и Arcane (>99% темпа), без Serpent Sting и Aimed Shot", 1, true), l11)
			T.eq(#G.reportedErrors + #G2.reportedErrors + #G3.reportedErrors + #G4.reportedErrors, 0)
		end },
		{ "/hga dump: the target and the caps follow the mode: 0, expertise 5 and hit 5 at 59; 3, expertise 6.5 and hit 8 at 60", function()
			for _, case in ipairs({ { 59, 0, 5, 5 }, { 60, 3, 6.5, 8 } }) do
				local G = env()
				G.UnitLevel = function() return case[1] end
				local ns = loadAll(G)
				G.SlashCmdList.HUNTERGEARADVISOR("dump")
				T.eq(ns.db.dump.target, case[2], "dump: the target at level " .. case[1])
				T.near(ns.db.dump.expertiseCap, case[3], 1e-12, "dump: the expertise cap at level " .. case[1])
				T.near(ns.db.dump.hitCap, case[4], 1e-12, "dump: the hit cap at level " .. case[1])
			end
		end },
		-- The model point's ranged skill (Advisor A.State; raid-mode W1 design 3.3): p.rangedSkill = the worn bow's skill less
		-- 5 x level, p.rangedHit = Model.SkillHit at the mode's target (0 below 60, +3 at 60), p.crit the sheet's ranged crit.
		-- Level 43, the bows at 205 of 215: the gap 10, -1% (my arithmetic); level 60, at 297 of 300 against +3: the gap 18,
		-- 8.6% against 8%, -0.6%. Mutants: the 0.04 slope on the hit; the skill's crit added to p.crit
		{ "model point: p.crit is the live crit, p.rangedHit = Model.SkillHit(model.mobDiff, worn bonus), p.rangedSkill the worn bonus", function()
			for _, case in ipairs({ { 43, 205, 0, -10, -1.0 }, { 60, 297, 3, -3, -0.6 } }) do
				local G = env()
				G.UnitLevel = function() return case[1] end
				G.GetRangedCritChance = function() return 9.10 end
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 45 then return { rank = case[2], maxRank = 5 * case[1], modifier = 0 } end
					return base(id)
				end
				local ns = loadAll(G)
				local st = ns.Advisor.State()
				T.eq(st.model.mobDiff, case[3], "the target at " .. case[1])
				T.eq(st.model.rangedSkill, case[4], "the worn bonus at " .. case[1])
				T.near(st.model.rangedHit, case[5], 1e-12, "the shots' skill hit at " .. case[1])
				T.near(st.model.rangedHit, ns.Model.SkillHit(case[3], case[4]), 1e-12)
				T.eq(st.model.crit, 9.10, "the sheet's ranged crit at " .. case[1]); T.eq(st.snap.model.crit, 9.10)
				T.eq(st.ctx.skillBase, case[4]); T.eq(st.ctx.mobDiff, case[3])
			end
		end },
		-- /hga weights at level 60 against the raid boss: the bows at 295 of 300, the gap 20 (+3): 9% miss against 8%, the
		-- shots' -1%; 5 points below the maximum: 1% crit suppression; the crit field the model's, the sheet's ranged crit,
		-- once. Mutants: the skill line with a "(против навыка уровня) %+.2f%%" text; the crit printed a second time as
		-- "(в листе ...)"
		{ "/hga weights: the skill line names the shots' hit and crit by wowsims' table; the crit field is printed once", function()
			local G = env()
			G.UnitLevel = function() return 60 end
			G.GetRangedCritChance = function() return 9.10 end
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 45 then return { rank = 295, maxRank = 300, modifier = 0 } end
				return base(id)
			end
			loadAll(G)
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local line
			for _, l in ipairs(G.printed) do if l:find("ур. 60, RAP", 1, true) then line = l end end
			T.truthy(line, table.concat(G.printed, " | "))
			T.truthy(line:find("крит 9.10%, меткость 0.00% (кап 8.0%; в листе 1.00%, навык Луки 295/295 против 300 по уровню: меткость выстрелов -1.0%, крит выстрелов -1.0%)", 1, true), line)
			T.eq(line:find("в листе 9.10", 1, true), nil, line)
			T.eq(line:find("против навыка уровня", 1, true), nil, line)
		end },
		-- The weapon run takes each set's melee weapon skills (Advisor weaponModelFor, Score.MeleeSkills; raid-mode W1 design
		-- 3.4): a ring of +5 Swords with the worn swords in both hands gives the run p.mhSkill 5 and p.ohSkill 5 with the same
		-- weapons; one run per (ranged, main hand, off hand, main hand's skill, off hand's skill); the worn set gives exactly 0.
		-- Mutant: the skills not in the run's cache key
		{ "melee skill: the weapon run takes each set's melee skills; one run per (ranged, MH, OH, mhSkill, ohSkill); the worn set gives exactly 0", function()
			local G = env()
			survivalTree(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.swordring = { info = { 73, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо мечника"), ln("Палец"),
				ln("Если на персонаже: повышение навыка владения мечом на 5.") }, api = {} }
			G.items.daggerring = { info = { 74, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо кинжальщика"), ln("Палец"),
				ln("Если на персонаже: повышение навыка владения кинжалом на 5.") }, api = {} }
			G.bags[0] = { "swordring", "daggerring" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(ns.Items.Get("swordring").stats.SKILL_SWORDS, 5)
			local runs = 0
			local tah = ns.Model.TotalAndHits
			ns.Model.TotalAndHits = function(p) runs = runs + 1; return tah(p) end
			T.eq(st.ctx.weaponGain(st.snap.equipped), 0, "the worn set: exactly 0")
			T.eq(runs, 0, "the worn set's run is A.State's")
			local swordSet = ns.Score.CopySet(st.snap.equipped); swordSet[11] = ns.Items.Piece(ns.Items.Get("swordring"), { kind = "new" })
			local mh, oh = ns.Score.MeleeSkills(swordSet, st.ctx)
			T.eq(mh, 5); T.eq(oh, 5)
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			p.mhSkill, p.ohSkill = 5, 5
			local gain = st.ctx.weaponGain(swordSet)
			T.near(gain, (ns.Model.Total(p) - st.total) / st.unitDps, 1e-12, "the run at the set's skills")
			T.truthy(gain > 0, "5 Swords add glance and dodge in the weave: " .. gain)
			T.eq(runs, 1, "one run for the set")
			st.ctx.weaponGain(swordSet)
			T.eq(runs, 1, "the same set: no run")
			local daggerSet = ns.Score.CopySet(st.snap.equipped); daggerSet[11] = ns.Items.Piece(ns.Items.Get("daggerring"), { kind = "new" })
			T.eq(st.ctx.weaponGain(daggerSet), 0, "+5 Daggers with swords: the worn skills, the worn run")
			T.eq(runs, 1, "no run")
			ns.Model.TotalAndHits = tah
			-- the ring worn: the swords line's live skill holds its 5 (the client counts worn gear in the modifier), the trained
			-- skill the level's; the worn set's skills are the model point's and its run gives exactly 0
			local G2 = env()
			survivalTree(G2)
			G2.items.swordring = G.items.swordring
			G2.equippedLinks[11] = "swordring"
			local base = G2.C_SkillInfo.GetSkillLineInfoByID
			G2.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 43 then return { rank = 215, maxRank = 215, modifier = 5 } end
				return base(id)
			end
			local ns2 = loadAll(G2)
			local st2 = ns2.Advisor.State()
			T.eq(st2.model.mhSkill, 5); T.eq(st2.model.ohSkill, 5); T.near(st2.model.meleeHit, 0.5, 1e-12)
			T.eq(st2.ctx.wornMeleeHit, st2.model.meleeHit, "the worn main hand's skill hit the run holds")
			T.eq(st2.meleeSkill.mh.trained, 215, "the trained skill less the worn ring's 5")
			local wmh, woh = ns2.Score.MeleeSkills(st2.snap.equipped, st2.ctx)
			T.eq(wmh, 5); T.eq(woh, 5)
			T.eq(st2.ctx.weaponGain(st2.snap.equipped), 0, "the worn set: exactly 0")
		end },
		-- a set bonus's melee skill reaches the run: The Twin Blades of Hakkari 461 (ItemSet.csv: 19865, 19866), 2 pieces:
		-- spell 15763, +6 Swords (Game/SetData.lua). One blade worn in the main hand, the other from the bags in the off hand:
		-- both hands at +6. Mutant: the set bonuses left out of Score.MeleeSkills
		{ "melee skill: a set's +Swords set bonus reaches the run's mhSkill", function()
			local G = env()
			survivalTree(G)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.blade1 = { info = { 19865, "INVTYPE_WEAPONMAINHAND", 2, 7 }, setID = 461, lines = { ln("Клинок Хаккари"),
				ln("Правая рука", "Меч"), ln("Урон: 40-75", "Скорость 2,60"), ln("(22,1 ед. урона в секунду)") }, api = {} }
			G.items.blade2 = { info = { 19866, "INVTYPE_WEAPONOFFHAND", 2, 7 }, setID = 461, lines = { ln("Клинок Хаккари"),
				ln("Левая рука", "Меч"), ln("Урон: 25-40", "Скорость 1,80"), ln("(18,0 ед. урона в секунду)") }, api = {} }
			G.equippedLinks[16] = "blade1"
			G.bags[0] = { "blade2" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(ns.SetData[461][1].stats.SKILL_SWORDS, 6)
			T.eq(st.model.mhSkill, 0, "one piece worn: no bonus")
			local r = ns.Advisor.Evaluate("blade2", { kind = "bag", bag = 0, slot = 1 })
			T.eq(r.newSet[16].name, "Клинок Хаккари"); T.eq(r.newSet[17].name, "Клинок Хаккари")
			local mh, oh = ns.Score.MeleeSkills(r.newSet, st.ctx)
			T.eq(mh, 6, "the main hand at +6"); T.eq(oh, 6, "the off hand at +6")
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			for k, v in pairs(ns.Player.WeaponInputs(r.newSet)) do p[k] = v end
			p.mhSkill, p.ohSkill = 6, 6
			T.near(st.ctx.weaponGain(r.newSet), (ns.Model.Total(p) - st.total) / st.unitDps, 1e-12, "the run at +6 on both hands")
		end },
		-- Each hand at its own line's skill (raid-mode W1 design 3.4; Advisor A.State, weaponModelFor, Score.MeleeSkills): a
		-- Survival build with the sword main hand at -10 and the dagger off hand at -20 (twoLines). The model point holds
		-- mhSkill -10, ohSkill -20, /hga dump the off hand's daggers line; the worn set gives exactly 0, the worn dagger's
		-- evaluation 0. A bag ring of +5 Daggers moves the off hand alone to -15: its run is its own (the off hand's skill is in
		-- the run's key), the model point with ohSkill -15, and its delta is that gain (Score.SetValue passes the set's skills
		-- to the run); without ctx.weaponGain it is an error. Its tooltip names the off hand's line, 200 against 195: the miss
		-- 8% against 9% (-1.0, the gaps 15 and 20 at +0: 5% + 0.2% a point), the glance 10% + 2% x 15 = 40% at (0.55 + 0.75) /
		-- 2 = 65%, the crit suppression 3% against 4% (+1.0) (my arithmetic); a bag off-hand dagger of +5 Daggers, which only
		-- the off hand takes, names the same. Mutants: the model's ohSkill from the main hand's line; the worn off hand read
		-- from the main hand's slot; the run's cache without the off hand's skill; the check of the main hand's skill alone;
		-- the tooltip's off-hand branch removed; its worn skill or its skill with the item from the main hand; a weapon's hand
		-- always the main hand; Score.SetValue passing the skills swapped (to the run, to the landed hits); Score.LandedHitsOf or
		-- ctx.landedHitsFor passing them swapped; the run's check of one hand's skill alone removed
		{ "melee skill: each hand at its own line; an off hand's skill item gets its own run, its tooltip line, the error without weaponGain", function()
			local G = env()
			survivalTree(G)
			local ln = twoLines(G)
			G.items.daggerring = { info = { 74, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо кинжальщика"), ln("Палец"),
				ln("Если на персонаже: повышение навыка владения кинжалом на 5.") }, api = {} }
			G.items.ohdagger = { info = { 80, "INVTYPE_WEAPONOFFHAND", 2, 15 }, lines = { ln("Левый кинжал"), ln("Левая рука", "Кинжал"),
				ln("Урон: 25-40", "Скорость 1,80"), ln("(18,0 ед. урона в секунду)"),
				ln("Если на персонаже: повышение навыка владения кинжалом на 5.") }, api = {} }
			G.bags[0] = { "daggerring", "ohdagger" }
			addTablet(G)
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.mhSkill, -10, "the main hand: swords 205 of 215"); T.eq(st.model.ohSkill, -20, "the off hand: daggers 195 of 215")
			T.near(st.model.meleeHit, -1, 1e-12, "the main hand's skill hit")
			T.truthy(ns.Model.Weave(st.model).average.rates.oh > 0, "the off hand swings")
			T.eq(st.ctx.weaponGain(st.snap.equipped), 0, "the worn set: exactly 0")
			T.eq(ns.Advisor.Evaluate("wdagger", { kind = "equipped", slot = 17 }).delta, 0, "the worn dagger: 0")
			local runs = 0
			local tah = ns.Model.TotalAndHits
			ns.Model.TotalAndHits = function(p) runs = runs + 1; return tah(p) end
			local ringSet = ns.Score.CopySet(st.snap.equipped); ringSet[11] = ns.Items.Piece(ns.Items.Get("daggerring"), { kind = "new" })
			local mh, oh = ns.Score.MeleeSkills(ringSet, st.ctx)
			T.eq(mh, -10); T.eq(oh, -15)
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			p.ohSkill = -15
			local gain = st.ctx.weaponGain(ringSet)
			T.near(gain, (ns.Model.Total(p) - st.total) / st.unitDps, 1e-12, "the run at the off hand's -15")
			T.truthy(gain > 0, "5 Daggers on the swinging off hand: " .. gain)
			T.eq(runs, 1, "a run of its own")
			ns.Model.TotalAndHits = tah
			local where = { kind = "bag", bag = 0, slot = 1 }
			T.near(ns.Advisor.Evaluate("daggerring", where).delta, gain, 1e-9, "the ring's delta: its run")
			local plain = {}
			for k, v in pairs(st.ctx) do plain[k] = v end
			plain.weaponGain = nil
			local ok, err = pcall(ns.Score.SetValue, ringSet, st.W, plain)
			T.eq(ok, false, "the off hand's skill without weaponGain")
			T.truthy(tostring(err):find("melee weapon skill differs from the worn set's without ctx.weaponGain", 1, true), tostring(err))
			-- the run takes both hands' skills from its caller, or neither
			T.near(st.ctx.weaponGain(ringSet, -10, -15), gain, 1e-12, "the skills given: the same run")
			ok, err = pcall(st.ctx.weaponGain, ringSet, -10, nil)
			T.eq(ok, false); T.truthy(tostring(err):find("a weapon run with one hand's melee skill", 1, true), tostring(err))
			-- the landed hits a set's procs roll on take the skills passed with it (each hand's swings land by its skill), and
			-- Score.SetValue passes the set's own: the Tablet's proc in the ring's set is priced as with the skills computed
			-- by the run itself
			local own = ns.Score.LandedHitsOf(ringSet, st.ctx)
			local given = ns.Score.LandedHitsOf(ringSet, st.ctx, -10, -15)
			T.eq(given.mh.swings, own.mh.swings); T.eq(given.oh.swings, own.oh.swings)
			T.truthy(math.abs(ns.Score.LandedHitsOf(ringSet, st.ctx, -15, -10).oh.swings - own.oh.swings) > 1e-6, "the off hand's swings by its skill")
			local procSet = ns.Score.CopySet(ringSet); procSet[13] = ns.Items.Piece(ns.Items.Get("tablet"), { kind = "new" })
			local selfRun = {}
			for k, v in pairs(st.ctx) do selfRun[k] = v end
			selfRun.landedHitsFor = function(set) return st.ctx.landedHitsFor(set) end
			selfRun.weaponGain = function(set) return st.ctx.weaponGain(set) end
			T.near(ns.Score.SetValue(procSet, st.W, st.ctx), ns.Score.SetValue(procSet, st.W, selfRun), 1e-12, "the skills Score.SetValue passes")
			local want = "HGA: навык Кинжалы 200/195 — в ближнем бою (ветка Выживания): промах -1.0%, скользящие 40% по 65%, крит +1.0%"
			local function text(link, w)
				local out = {}
				for i, l in ipairs(ns.Advisor.Explain(link, w)) do out[i] = l[1] end
				return table.concat(out, "\n")
			end
			local ringText = text("daggerring", where)
			T.truthy(ringText:find(want, 1, true), ringText)
			local ohWhere = { kind = "bag", bag = 0, slot = 2 }
			T.eq(ns.Advisor.Evaluate("ohdagger", ohWhere).hand, "oh", "the off-hand dagger in the off hand")
			local ohText = text("ohdagger", ohWhere)
			T.truthy(ohText:find(want, 1, true), ohText)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump
			T.eq(d.meleeSkill.mh.line, 43); T.eq(d.meleeSkill.oh.line, 173, "the off hand's own line")
			T.eq(d.meleeSkill.oh.shown, 195); T.eq(d.meleeSkill.oh.trained, 195)
			T.eq(#G.reportedErrors, 0, tostring(G.reportedErrors[1]))
		end },
		-- A skill item of several lines names the line of the hand it reaches (A.Explain; raid-mode W1 design 3.4: the main
		-- hand first): with the sword main hand at -10 and the dagger off hand at -20 (twoLines), gloves of +7 Axes, +7
		-- Daggers and +7 Swords (the three lines Edgemaster's Handguards 14551 holds in wowsims' Forever database,
		-- assets/database/db.json; the amounts are the test's) name the main hand's Swords, 212 against 205: the miss 5.3%
		-- against 6% (-0.7), the glance 10% + 2% x 3 = 16% at 95%, the crit +1.4%; a ring of +7 Axes and +7 Daggers the off
		-- hand's Daggers, 202 against 195: the miss 7.6% against 9% (-1.4), the glance 36% at (0.65 + 0.81) / 2 = 73%, the crit
		-- +1.4% (my arithmetic). Out of the Survival branch the lines name the same, not counted; a ring of +7 Axes alone names
		-- a line no hand holds; a ring of +12 Swords takes the main hand past the maximum, 217 of 215, which moves the pet's
		-- branch only up to the maximum, 0.04% x 10 = +0.40% (pets.go:147-153: the penalty of a skill below the maximum; my
		-- arithmetic). Mutants: the item's first line in subclass order (Axes, which no hand holds); the off hand before the
		-- main hand; the main hand alone; the pet's branch past the maximum; the line no hand holds dropped
		{ "tooltip: a melee skill item of several lines names the line of the hand it reaches, the main hand first", function()
			local function texts(survival)
				local G = env()
				if survival then survivalTree(G) end
				local ln = twoLines(G)
				G.items.edgegloves = { info = { 81, "INVTYPE_HAND", 4, 2 }, lines = { ln("Перчатки"), ln("Кисти рук", "Кожа"),
					ln("Если на персонаже: повышение навыка использования топоров на 7."),
					ln("Если на персонаже: повышение навыка владения кинжалом на 7."),
					ln("Если на персонаже: повышение навыка владения мечом на 7.") }, api = {} }
				G.items.adring = { info = { 82, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо"), ln("Палец"),
					ln("Если на персонаже: повышение навыка использования топоров на 7."),
					ln("Если на персонаже: повышение навыка владения кинжалом на 7.") }, api = {} }
				G.items.axering = { info = { 83, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо топорщика"), ln("Палец"),
					ln("Если на персонаже: повышение навыка использования топоров на 7.") }, api = {} }
				G.items.swordring = { info = { 84, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо мечника"), ln("Палец"),
					ln("Если на персонаже: повышение навыка владения мечом на 12.") }, api = {} }
				G.bags[0] = { "edgegloves", "adring", "axering", "swordring" }
				local ns = loadAll(G)
				local stats = ns.Items.Get("edgegloves").stats
				T.eq(stats.SKILL_AXES, 7); T.eq(stats.SKILL_DAGGERS, 7); T.eq(stats.SKILL_SWORDS, 7)
				local out = {}
				for slot = 1, 4 do
					local t = {}
					for i, l in ipairs(ns.Advisor.Explain(G.bags[0][slot], { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
					out[slot] = table.concat(t, "\n")
				end
				return out[1], out[2], out[3], out[4]
			end
			local gloves, ring = texts(true)
			T.truthy(gloves:find("HGA: навык Мечи 212/205 — в ближнем бою (ветка Выживания): промах -0.7%, скользящие 16% по 95%, крит +1.4%", 1, true), gloves)
			T.truthy(ring:find("HGA: навык Кинжалы 202/195 — в ближнем бою (ветка Выживания): промах -1.4%, скользящие 36% по 73%, крит +1.4%", 1, true), ring)
			local axes, swords
			gloves, ring, axes, swords = texts(false)
			-- the BM build: no melee of its own; the main hand's swords at 212 of 215 against the worn 205 move the pet's melee
			-- crit branch 0.04% a point, +0.28% (my arithmetic), and the proc tables; the off hand's daggers nothing
			T.truthy(gloves:find("HGA: навык Мечи 212/205 — своего ближнего боя нет (не ветка Выживания); правой рукой он двигает ветку ближнего боя крита пета (+0.28%, в счёт, пока она выше ветки дальнего боя) и таблицу эффектов при попадании", 1, true), gloves)
			T.truthy(ring:find("HGA: навык Кинжалы 202/195 — своего ближнего боя нет (не ветка Выживания); в левой руке он ни на что не влияет", 1, true), ring)
			T.truthy(axes:find("HGA: навык Топоры — ни одна рука набора не держит оружие этой линии: не в счёт", 1, true), axes)
			T.truthy(swords:find("HGA: навык Мечи 217/205 — своего ближнего боя нет (не ветка Выживания); правой рукой он двигает ветку ближнего боя крита пета (+0.40%, в счёт, пока она выше ветки дальнего боя)", 1, true), swords)
		end },
		-- Outside the Survival branch no melee is counted (Model.Parts), and while the pet's ranged crit branch leads (the
		-- sheet's ranged crit 9.5% over the melee 8.66%) a main hand's skill reaches nothing: a ring of +5 Swords gains
		-- exactly 0 through the run, and the main hand's skill hit is priced at W.HIT_MELEE, 0 there. Mutant: the melee skill
		-- priced outside the run (its hit at W.HIT)
		{ "melee skill: zero outside the Survival branch while the pet's ranged crit branch wins", function()
			local G = env()
			G.GetRangedCritChance = function() return 9.5 end
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.swordring = { info = { 73, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо мечника"), ln("Палец"),
				ln("Если на персонаже: повышение навыка владения мечом на 5.") }, api = {} }
			G.bags[0] = { "swordring" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.survival, false); T.eq(st.W.HIT_MELEE, 0)
			local r = ns.Advisor.Evaluate("swordring", { kind = "bag", bag = 0, slot = 1 })
			T.eq(ns.Score.MeleeSkills(r.newSet, st.ctx), 5, "the run's main hand at +5")
			T.eq(st.ctx.weaponGain(r.newSet), 0, "the run: nothing")
			T.eq(r.delta, 0, "the ring: nothing")
		end },
		-- The tooltip of a melee weapon names its hand's melee skill by wowsims' table in the Survival branch (raid-mode W1
		-- design 3.4): the swords line at 205 of the level's 215, a bag sword with +5 Swords: the hand at 210 against the worn
		-- 205, its miss 5.5% against 6% (-0.5), its glance 10% + 2% x 5 = 20% at (0.91 + 0.99) / 2 = 95%, its crit 1% of
		-- suppression less (my arithmetic). With the swords line at the level's 215, the hand at 220: the miss 4.5% against 5%
		-- (-0.5), the glance 10% at 95%, no crit change (no suppression at or above the maximum). Out of the Survival branch
		-- the hunter has no melee. Mutants: the Survival line out of the Survival branch; the line missing in it; the
		-- crit change without the floor at the maximum (0.2 x the skill change). Out of the Survival branch the line says what
		-- the hand's skill still reaches (raid-mode design 18.9)
		{ "tooltip: a melee weapon in a Survival build names its miss, glance and crit; out of Survival what its hand's skill reaches", function()
			local function text(survival, rank)
				local G = env()
				if survival then survivalTree(G) end
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 43 then return { rank = rank or 205, maxRank = 215, modifier = 0 } end
					return base(id)
				end
				local lines = {}
				for i, l in ipairs(G.items.sword.lines) do lines[i] = l end
				lines[#lines + 1] = { leftText = "Если на персонаже: повышение навыка владения мечом на 5.", leftColor = { r = 1, g = 1, b = 1 } }
				G.items.skillsword = { info = { 76, "INVTYPE_WEAPON", 2, 7 }, lines = lines, api = G.items.sword.api }
				G.bags[0] = { "skillsword" }
				local ns = loadAll(G)
				local out = {}
				for i, l in ipairs(ns.Advisor.Explain("skillsword", { kind = "bag", bag = 0, slot = 1 })) do out[i] = l[1] end
				return table.concat(out, "\n")
			end
			local sv = text(true)
			T.truthy(sv:find("HGA: навык Мечи 210/205 — в ближнем бою (ветка Выживания): промах -0.5%, скользящие 20% по 95%, крит +1.0%", 1, true), sv)
			T.eq(sv:find("не в счёт", 1, true), nil, sv)
			local top = text(true, 215)
			T.truthy(top:find("HGA: навык Мечи 220/215 — в ближнем бою (ветка Выживания): промах -0.5%, скользящие 10% по 95%, крит +0.0%", 1, true), top)
			local bm = text(false)
			-- the BM build puts the bag sword in the off hand next to the worn sword: its skill there reaches nothing
			T.truthy(bm:find("HGA: надеть в левую руку", 1, true), bm)
			T.truthy(bm:find("HGA: навык Мечи 210/205 — своего ближнего боя нет (не ветка Выживания); в левой руке он ни на что не влияет", 1, true), bm)
			T.eq(bm:find("в ближнем бою (ветка Выживания)", 1, true), nil, bm)
		end },
		-- /hga dump: the worn hands' melee skill lines, live skills and trained skills (as rangedSkill), the model point's
		-- mhSkill, ohSkill and meleeHit: the swords line at 205 of 215 in both hands, the main hand's skill hit -1% (the gap 10
		-- at +0). Mutant: meleeSkill missing
		{ "/hga dump: meleeSkill for the worn hands; the model holds mhSkill, ohSkill, meleeHit", function()
			local G = env()
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 43 then return { rank = 205, maxRank = 215, modifier = 0 } end
				return base(id)
			end
			local ns = loadAll(G)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump
			for _, hand in ipairs({ "mh", "oh" }) do
				T.eq(d.meleeSkill[hand].line, 43, hand); T.eq(d.meleeSkill[hand].shown, 205, hand); T.eq(d.meleeSkill[hand].trained, 205, hand)
			end
			T.eq(d.model.mhSkill, -10); T.eq(d.model.ohSkill, -10); T.near(d.model.meleeHit, -1, 1e-12)
		end },
		-- /hga dump: the worn ranged line's trained skill over 5 x level and the target Score prices the ranged skill against
		-- (ctx.skillBase, ctx.mobDiff); the model point's rangedSkill comes with the model. Mutant: the dump keeps skillShift
		{ "/hga dump: skillBase and mobDiff, no skillShift; the model holds rangedSkill", function()
			local G = env()
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 45 then return { rank = 205, maxRank = 215, modifier = 0 } end
				return base(id)
			end
			local ns = loadAll(G)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			local d = ns.db.dump
			T.eq(d.skillBase, -10); T.eq(d.mobDiff, 0); T.eq(d.skillShift, nil, "no skillShift")
			T.eq(d.model.rangedSkill, -10); T.near(d.model.rangedHit, -1, 1e-12)
		end },
		-- /hga dump's ammo fields pass on what the client's ammo API answers (Forever UI: GetInventoryItemID and
		-- GetInventoryItemCount as Camelot/PaperDollFrame.lua calls them for the ammo slot, C_PaperDollInfo.AmmoNeeded,
		-- UnitUsesAmmo), in two states of the fake env's answers
		{ "/hga dump: the ammo slot's item id and stack, AmmoNeeded and UnitUsesAmmo are the client API's answers", function()
			local G = env(); local ns = loadAll(G)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			-- the fake env: id 13, a stack of 2790, AmmoNeeded and UnitUsesAmmo true
			local ammo = ns.db.dump.ammo
			T.eq(ammo.slotID, 13); T.eq(ammo.slotCount, 2790); T.eq(ammo.ammoNeeded, true); T.eq(ammo.unitUsesAmmo, true)
			-- other answers: an empty ammo slot, and AmmoNeeded and UnitUsesAmmo apart (false / true, then true / false), so
			-- each field is its own call's answer
			local itemID, itemCount = G.GetInventoryItemID, G.GetInventoryItemCount
			G.GetInventoryItemID = function(u, slot) if slot == 0 then return nil end return itemID(u, slot) end
			G.GetInventoryItemCount = function(u, slot) if slot == 0 then return 0 end return itemCount(u, slot) end
			G.ammoNeeded, G.unitUsesAmmo = false, true
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			ammo = ns.db.dump.ammo
			T.eq(ammo.slotID, nil, "an empty ammo slot: no id"); T.eq(ammo.slotCount, 0, "an empty ammo slot: a stack of 0")
			T.eq(ammo.ammoNeeded, false, "AmmoNeeded false"); T.eq(ammo.unitUsesAmmo, true, "UnitUsesAmmo true")
			G.ammoNeeded, G.unitUsesAmmo = true, false
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			ammo = ns.db.dump.ammo
			T.eq(ammo.ammoNeeded, true, "AmmoNeeded true"); T.eq(ammo.unitUsesAmmo, false, "UnitUsesAmmo false")
		end },
		-- the pet's own swing time: Player.PetSwing, the snapshot, Player.PetCheck and /hga weights
		{ "pet swing: read once the hunter's melee speed has held a pet heartbeat, re-checked by one timer", function()
			local G = env(); local ns = loadAll(G)
			local P = ns.Player
			T.eq(#G.timers, 0, "nothing reads the pet at load")
			T.eq(ns.Advisor.State().snap.model.petSwing, nil, "the hunter's melee speed just seen: no read yet")
			T.eq(#G.timers, 1, "one re-check for the end of the wait")
			T.eq(P.PetSwing(), nil)
			T.eq(#G.timers, 1, "no second timer while one waits")
			G.advance(5.2)
			T.eq(P.PetSwing(), nil, "5.2 s: still waiting")
			G.advance(0.1)
			T.eq(#G.timers, 0, "the re-check ran")
			T.eq(ns.Advisor.State().snap.model.petSwing, 1.2, "the re-check read the cat's swing and re-evaluated")
			-- Frenzy on the pet: its own haste is on the swing at once, nothing is read
			G.auras.pet[19615] = true; G.petSpeed = 1.2 / 1.3
			T.eq(P.PetSwing(), 1.2, "Frenzy up: kept")
			G.auras.pet[19615] = nil; G.secretAuras[19615] = true
			T.eq(P.PetSwing(), 1.2, "Frenzy's aura secret: kept")
			G.secretAuras[19615] = nil
			G.petSpeed = 0.9
			G.secretValues = { [0.9] = true }
			T.eq(P.PetSwing(), 1.2, "secret pet swing: kept")
			G.secretValues = nil
			T.eq(P.PetSwing(), 0.9, "readable, no Frenzy, the hunter's speed held: read")
			G.petSpeed = 1.2
			T.eq(P.PetSwing(), 1.2)
			-- dismissed: the last swing stays
			G.petOut = false
			T.eq(P.PetSwing(), 1.2, "kept while dismissed")
			-- another pet (new GUID) out under Frenzy: the old pet's swing is dropped
			G.petOut = true; G.petGUID = "Pet-0-2"; G.auras.pet[19615] = true
			T.eq(P.PetSwing(), nil, "another GUID: dropped")
			G.auras.pet[19615] = nil; G.petSpeed = 1.5
			T.eq(P.PetSwing(), 1.5, "the new pet's swing")
			-- another family, GUID secret: dropped by the family
			G.petGUID = "Pet-0-3"; G.secretValues = { ["Pet-0-3"] = true }
			G.petFamilyID = 1; G.auras.pet[19615] = true
			T.eq(P.PetSwing(), nil, "another family: dropped")
			G.auras.pet[19615] = nil; G.petSpeed = 2.0
			T.eq(P.PetSwing(), 2.0)
			-- a secret GUID with the same family says nothing about another pet: kept
			G.petGUID = "Pet-0-4"; G.secretValues = { ["Pet-0-4"] = true }; G.auras.pet[19615] = true
			T.eq(P.PetSwing(), 2.0, "secret GUID, same family: kept")
			T.eq(#G.reportedErrors, 0)
			-- a swing time that is no positive number is reported, the last good one stays
			G.auras.pet[19615] = nil; G.petSpeed = 0
			T.eq(P.PetSwing(), 2.0, "invalid swing: kept")
			T.eq(#G.reportedErrors, 1); T.truthy(G.reportedErrors[1]:find("UnitAttackSpeed"), G.reportedErrors[1])
		end },
		-- the pet inherits the hunter's melee haste at its next heartbeat (wowsims pet.go:35,
		-- PetUpdateInterval 5250 ms)
		{ "pet swing: Rapid Fire ending leaves the pet hasted until its heartbeat; its own swing stays 1.2", function()
			local G = env(); local ns = loadAll(G)
			local P = ns.Player
			settlePet(G)
			T.eq(ns.Advisor.State().snap.model.petSwing, 1.2, "the cat's own swing")
			-- Rapid Fire 3045 (aura 319 +40): the hunter's melee swing 40% faster at once, the pet's at its heartbeat
			G.auras.player[3045] = true; G.ownerSpeed = 2.6 / 1.4
			G.fire("UNIT_ATTACK_SPEED", "player")
			T.eq(P.PetSwing(), 1.2, "the hunter's melee speed up at once: kept")
			G.advance(2)
			G.petSpeed = 1.2 / 1.4
			G.fire("UNIT_ATTACK_SPEED", "pet")
			T.eq(P.PetSwing(), 1.2, "the pet's heartbeat came, the wait is not over: kept")
			G.advance(3.3)
			T.near(P.PetSwing(), 1.2, 1e-9, "a heartbeat after the change: Rapid Fire divided out")
			-- Rapid Fire leaves the hunter: the pet swings at 1.2 / 1.4 until its heartbeat
			G.auras.player[3045] = nil; G.ownerSpeed = 2.6
			G.fire("UNIT_ATTACK_SPEED", "player")
			T.near(ns.Advisor.State().snap.model.petSwing, 1.2, 1e-9, "Rapid Fire ended: kept, not 1.2 / 1.4")
			G.advance(3)
			T.near(P.PetSwing(), 1.2, 1e-9, "3 s later, the pet not at its heartbeat yet: kept")
			G.petSpeed = 1.2
			G.fire("UNIT_ATTACK_SPEED", "pet")
			G.advance(2.3)
			T.near(P.PetSwing(), 1.2, 1e-9, "read again after the wait")
			T.eq(#G.timers, 0)
		end },
		{ "pet swing: any melee haste of the hunter is divided out; nothing is read unarmed", function()
			local G = env()
			G.equippedLinks[16] = "bagsword" -- a 2.40 one-hander
			local ns = loadAll(G)
			local P = ns.Player
			-- Quick Strikes 1299448 (aura 319 +30, from Aspect of the Beast's melee procs) on the hunter, on the pet
			-- since its heartbeat
			G.auras.player[1299448] = true
			G.ownerSpeed, G.petSpeed = 2.4 / 1.3, 1.2 / 1.3
			settlePet(G)
			T.near(P.PetSwing(), 1.2, 1e-9, "pet 1.2 / 1.3, hunter 2.4 / 1.3: the pet's own 1.2")
			-- Wind Blessed (2% haste) in place of Quick Strikes
			G.auras.player[1299448] = nil
			G.ownerSpeed, G.petSpeed = 2.4 / 1.02, 1.2 / 1.02
			G.fire("UNIT_ATTACK_SPEED", "player")
			G.advance(5.3)
			T.near(P.PetSwing(), 1.2, 1e-9, "pet 1.2 / 1.02, hunter 2.4 / 1.02: 1.2")
			-- unarmed: the hunter's base swing is unknown, nothing is read and no re-check is asked
			G.equippedLinks[16] = nil
			G.ownerSpeed, G.petSpeed = 2.0, 1.0
			G.fire("UNIT_ATTACK_SPEED", "player")
			G.advance(10)
			T.near(P.PetSwing(), 1.2, 1e-9, "unarmed: kept"); T.eq(#G.timers, 0, "unarmed: no re-check")
			-- a main hand that is no weapon (another class in a two-hand slot): unarmed too
			G.equippedLinks[16] = "torch"
			G.advance(10)
			T.near(P.PetSwing(), 1.2, 1e-9, "no weapon in the main hand: kept"); T.eq(#G.timers, 0)
			T.eq(#G.reportedErrors, 0)
			-- armed again: the wait starts over
			G.equippedLinks[16] = "bagsword"; G.ownerSpeed, G.petSpeed = 2.4, 1.25
			T.near(P.PetSwing(), 1.2, 1e-9, "armed again: the wait starts over"); T.eq(#G.timers, 1)
			G.advance(5.3)
			T.near(P.PetSwing(), 1.25, 1e-9, "read after the wait")
		end },
		{ "pet swing: the wait counts from the last change beyond 0.1%; an unseen stretch of the hunter's speed restarts it", function()
			local G = env(); local ns = loadAll(G)
			local P = ns.Player
			G.fire("UNIT_PET", "player")
			-- a change within the tolerance (0.05%) is no change
			G.advance(3)
			G.ownerSpeed, G.petSpeed = 2.6 / 1.0005, 1.2 / 1.0005
			G.fire("UNIT_ATTACK_SPEED", "player")
			G.advance(2.3)
			T.near(P.PetSwing(), 1.2, 1e-9, "5.3 s after the first sight: read")
			-- a change beyond it (0.2%) holds the read back again
			G.ownerSpeed = 2.6 / 1.002
			G.fire("UNIT_ATTACK_SPEED", "player")
			T.near(P.PetSwing(), 1.2, 1e-12, "0.2%: the wait restarts, the last swing stays")
			G.ownerSpeed, G.petSpeed = 2.6, 1.2
			G.advance(5.3)
			T.near(P.PetSwing(), 1.2, 1e-12)
			-- combat: the hunter's swing is secret while Rapid Fire comes and goes; when it is readable again the
			-- pet still has the haste until its next heartbeat
			G.secretValues = { [2.6] = true, [2.6 / 1.4] = true }
			G.ownerSpeed = 2.6 / 1.4
			G.fire("UNIT_ATTACK_SPEED", "player")
			G.advance(3)
			G.petSpeed = 1.2 / 1.4
			G.fire("UNIT_ATTACK_SPEED", "pet")
			T.near(P.PetSwing(), 1.2, 1e-12, "the hunter's swing secret: kept")
			G.advance(12)
			G.ownerSpeed = 2.6
			G.fire("UNIT_ATTACK_SPEED", "player")
			T.eq(#G.timers, 0, "secret: no re-check")
			G.secretValues = nil
			G.fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
			T.near(ns.Advisor.State().snap.model.petSwing, 1.2, 1e-12, "readable again: the wait starts over, kept")
			G.advance(2)
			G.petSpeed = 1.2
			G.fire("UNIT_ATTACK_SPEED", "pet")
			G.advance(3.3)
			T.near(P.PetSwing(), 1.2, 1e-12, "read after the wait")
			-- the hunter's swing secret from the start: nothing is read however long
			local G2 = env()
			G2.secretValues = { [2.6] = true }
			local ns2 = loadAll(G2)
			settlePet(G2)
			G2.advance(10)
			T.eq(ns2.Player.PetSwing(), nil, "never readable: never read"); T.eq(#G2.timers, 0)
		end },
		{ "pet swing: a pet change seen while the new GUID is secret takes the new pet's family and GUID", function()
			local G = env(); local ns = loadAll(G)
			local P = ns.Player
			settlePet(G)
			T.eq(P.PetSwing(), 1.2, "pet A")
			-- pet B: another family (Wolf), GUID secret: the reset, then B's swing
			G.petGUID = "Pet-0-B"; G.secretValues = { ["Pet-0-B"] = true }
			G.petFamilyID = 1; G.petSpeed = 2.0
			T.eq(P.PetSwing(), 2.0, "pet B read after the reset")
			-- B's GUID becomes readable while Frenzy is up (nothing can be read then): B's swing stays
			G.secretValues = nil; G.auras.pet[19615] = true
			T.eq(P.PetSwing(), 2.0, "the same pet B: kept")
		end },
		-- the keys a pet's swing is kept with are its own family id and GUID as read with it (nil
		-- where secret); the model's family (Player.PetFamily) is the previous pet's while the new one's id is secret
		{ "pet swing: a new pet read while its family id is secret keeps its swing once the id is readable", function()
			local G = env(); local ns = loadAll(G)
			local P = ns.Player
			settlePet(G)
			T.eq(P.PetSwing(), 1.2, "pet A (Cat)")
			-- pet B (Wolf, own swing 1.5): GUID readable, family id secret
			G.petGUID = "Pet-0-B"; G.petFamilyID = 1; G.petSpeed = 1.5
			G.secretValues = { [1] = true }
			G.fire("UNIT_PET", "player")
			T.eq(P.PetSwing(), 1.5, "pet B read after the reset by its GUID")
			T.eq(P.PetFamily(), 2, "the model's family: the last one seen")
			-- B's family id readable while Frenzy is up on B (nothing can be read): B's swing stays
			G.secretValues = nil; G.auras.pet[19615] = true
			T.eq(P.PetSwing(), 1.5, "the same pet B: kept")
			-- PetSwing keeps the model's family up to date: B's id, read with it (no pet out: PetFamily reads nothing)
			G.petOut = false
			T.eq(P.PetFamily(), 1, "the model's family: B's")
		end },
		{ "pet swing: a new pet read while its family id and GUID are both secret keeps its swing once they are readable", function()
			local G = env(); local ns = loadAll(G)
			local P = ns.Player
			settlePet(G)
			T.eq(P.PetSwing(), 1.2, "pet A (Cat)")
			-- pet B (Wolf, own swing 1.5): family id and GUID both secret (both SecretWhenUnitIdentityRestricted)
			G.petGUID = "Pet-0-B"; G.petFamilyID = 1; G.petSpeed = 1.5
			G.secretValues = { ["Pet-0-B"] = true, [1] = true }
			G.fire("UNIT_PET", "player")
			T.eq(P.PetSwing(), 1.5, "pet B read: no key known on both sides, no reset")
			-- B's identity readable while Frenzy is up on B: B's read has no keys to differ from
			G.secretValues = nil; G.auras.pet[19615] = true
			T.eq(P.PetSwing(), 1.5, "the same pet B: kept")
			-- B read again with its identity readable: the keys are B's, so pet C (Cat, readable) drops B's swing
			G.auras.pet[19615] = nil
			T.eq(P.PetSwing(), 1.5, "B read again")
			G.petGUID = "Pet-0-C"; G.petFamilyID = 2; G.auras.pet[19615] = true
			T.eq(P.PetSwing(), nil, "pet C under Frenzy: B's swing dropped")
		end },
		-- the re-check waits for the rest of the pet heartbeat, not a whole one
		{ "pet swing: a read held back by Frenzy and then by the wait is re-checked when the rest of the wait is over", function()
			local G = env()
			G.auras.pet[19615] = true
			local ns = loadAll(G)
			-- Rapid Fire 3045: the hunter's melee swing 40% faster; Frenzy up on the pet: nothing is read, no re-check
			G.auras.player[3045] = true; G.ownerSpeed = 2.6 / 1.4
			G.fire("UNIT_ATTACK_SPEED", "player")
			T.eq(#G.timers, 0, "Frenzy up: no re-check")
			-- 3 s later Frenzy drops (the pet inherited Rapid Fire at its heartbeat): 2.25 s of the wait are left
			G.advance(3)
			G.auras.pet[19615] = nil; G.petSpeed = 1.2 / 1.4
			G.fire("UNIT_ATTACK_SPEED", "pet")
			T.eq(#G.timers, 1, "one re-check")
			T.eq(ns.Advisor.State().snap.model.petSwing, nil, "not read yet")
			G.advance(2.3)
			T.eq(#G.timers, 0, "the re-check ran at the end of the wait")
			T.near(ns.Advisor.State().snap.model.petSwing, 1.2, 1e-9, "read: 1.2 / 1.4 x the hunter's 1.4")
		end },
		-- the hunter's melee speed multiplier is followed with no pet out: a pet takes the owner's multipliers when it
		-- comes out (wowsims sim/core/pet.go enableDynamicMeleeSpeed, run when the pet is enabled)
		{ "pet swing: the hunter's melee speed is followed with no pet out; a pet out after a heartbeat is read at once", function()
			local G = env()
			G.petOut = false
			local ns = loadAll(G)
			local P = ns.Player
			-- a 2% melee haste of the hunter comes with no pet out
			G.ownerSpeed = 2.6 / 1.02
			G.fire("UNIT_ATTACK_SPEED", "player")
			G.advance(5.3)
			T.eq(P.PetSwing(), nil, "no pet: nothing read")
			-- the pet comes out with the hunter's multiplier on its swing
			G.petOut = true; G.petSpeed = 1.2 / 1.02
			G.fire("UNIT_PET", "player")
			T.eq(#G.timers, 0, "read at once: no re-check")
			T.near(P.PetSwing(), 1.2, 1e-9, "the pet's 1.2 / 1.02 x the hunter's 1.02")
			T.near(ns.Advisor.State().snap.model.petSwing, 1.2, 1e-9)
		end },
		-- the pet does not inherit the owner's haste rating (wowsims sim/core/pet.go:381-398: the melee and attack speed
		-- multipliers; hasteRatingMultiplier sits on the owner's totals, sim/core/unit.go:564-566, 610-638): with a worn 2%
		-- haste rating the hunter's swing holds it and the pet's does not, and Player.PetSwing divides the owner's multiplier
		-- less the rating out of the pet's swing
		{ "pet swing: the owner's haste rating is in his swing, not the pet's; PetSwing divides out the multiplier the pet inherits", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.ratinghelm = { info = { 40, "INVTYPE_HEAD", 4, 3 }, lines = { ln("Шлем рейтинга"), ln("Голова", "Кольчуга"),
				ln("Броня: 200"), ln("Повышает рейтинг скорости боя на 20.") }, api = {} }
			G.equippedLinks[1] = "ratinghelm"
			-- the hunter's swing: 2.6 / (1.02 rating x 1.03 melee speed); the pet's: 1.2 / 1.03 (the melee speed alone)
			G.auras.player[3045] = nil
			G.ownerSpeed, G.ownerOffSpeed, G.petSpeed = 2.6 / (1.02 * 1.03), 1.8 / (1.02 * 1.03), 1.2 / 1.03
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			T.near(st.snap.model.hasteRating, 2, 1e-12, "the helm's 2% haste rating")
			T.near(st.snap.model.petSwing, 1.2, 1e-9, "the pet's own swing: 1.2 / 1.03 x the 1.03 it inherits")
		end },
		-- the worn state's permanent attack speed by source (Player.Snapshot, wornHaste; raid-mode W1 design 7.3): the worn
		-- items' haste rating (the helm's equip line, TOOLTIP_ITEM_STAT_HASTE_PCT_INCREASE: HASTE_RATING) in model.hasteRating,
		-- the worn set bonuses' ATTACK_SPEED (Wildstalker Armor 2101: pieces 280896 chest, 280893 hands; 2 pieces 1300945,
		-- aura 342 bp 1) and Wind Blessed 1259710 (aura 342 bp 2), one product, in model.attackSpeed; model.haste (an item's or
		-- enchant's aura 342) holds none of them
		{ "haste: the worn items' haste rating, a worn Tier-1 two-piece bonus and Wind Blessed reach the model by source", function()
			local W = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W, rightColor = W } end
			local function state(helm, pieces, windBlessed)
				local G = env()
				G.items.hastehelm = { info = { 26, "INVTYPE_HEAD", 4, 3 }, lines = { ln("Быстрый шлем"), ln("Голова", "Кольчуга"),
					ln("Броня: 200"), ln("Если на персонаже: повышает скорость атаки и применения заклинаний на 1,0%.") }, api = {} }
				G.items.wschest = { info = { 280896, "INVTYPE_CHEST", 4, 3 }, setID = 2101, lines = { ln("Кольчуга ловчего"), ln("Грудь", "Кольчуга") }, api = {} }
				G.items.wshands = { info = { 280893, "INVTYPE_HAND", 4, 3 }, setID = 2101, lines = { ln("Перчатки ловчего"), ln("Кисти рук", "Кольчуга") }, api = {} }
				if helm then G.equippedLinks[1] = "hastehelm" end
				if pieces >= 1 then G.equippedLinks[5] = "wschest" end
				if pieces >= 2 then G.equippedLinks[10] = "wshands"; table.insert(G.bags[0], "gloves") end
				if windBlessed then G.IsPlayerSpell = function(id) return id == 1259710 end end
				local ns = loadAll(G)
				return ns.Advisor.State(), ns, G
			end
			local function speeds(m) return { m.haste, m.attackSpeed, m.hasteRating } end
			local function same(m, want, msg)
				local got = speeds(m)
				for i = 1, 3 do T.near(got[i], want[i], 1e-9, msg .. " (" .. ({ "haste", "attackSpeed", "hasteRating" })[i] .. ")") end
			end
			same(state(false, 0, false).snap.model, { 0, 0, 0 }, "no source")
			local helm = state(true, 0, false).snap
			T.eq(helm.equipped[1].stats.HASTE_RATING, 1, "Parse: the helm's line is 1% HASTE_RATING")
			T.eq(helm.equipped[1].stats.HASTE, nil, "and no HASTE")
			same(helm.model, { 0, 0, 1 }, "the helm's 1% haste rating")
			same(state(false, 1, false).snap.model, { 0, 0, 0 }, "one piece of the set: no bonus")
			same(state(false, 2, false).snap.model, { 0, 1, 0 }, "Wildstalker Armor's two-piece bonus")
			same(state(false, 0, true).snap.model, { 0, 2, 0 }, "Wind Blessed")
			same(state(true, 2, true).snap.model, { 0, (1.01 * 1.02 - 1) * 100, 1 }, "the set's and Wind Blessed's multiply; the rating apart")
			-- Score prices a set bonus's attack speed at W.ATTACK_SPEED a percent: the worn weapons gain 0 at the worn speeds,
			-- and taking the set's hands off for the bag gloves loses the pair's 1%
			local st, ns, G = state(false, 2, true)
			T.near(st.snap.model.attackSpeed, (1.01 * 1.02 - 1) * 100, 1e-9)
			T.near(st.ctx.weaponGain(st.snap.equipped), 0, 1e-12, "the worn weapons at the worn speeds")
			local gloves = ns.Advisor.Evaluate("gloves", { kind = "bag", bag = 0, slot = #G.bags[0] })
			T.truthy(st.W.ATTACK_SPEED > 0, "the set bonus's attack speed has a damage weight")
			T.truthy(st.W.ATTACK_SPEED < st.W.HASTE - 1e-9, "below W.HASTE: the hawks do not take it")
			T.near(gloves.delta, 24 * st.W.AP + 21 * st.W.AP_VS_BEAST - st.W.ATTACK_SPEED, 1e-6,
				"the gloves' attack power less the pair's 1% attack speed")
			-- /hga weights names each weight of its own (hawks out: W.ATTACK_SPEED below W.HASTE)
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local text = table.concat(G.printed, "\n")
			local W = st.W
			local want = string.format("скорость атаки 1%% %.2f (скорость атаки (комплект, раса) %.2f, рейтинг скорости %.2f,",
				W.HASTE, W.ATTACK_SPEED, W.HASTE_RATING)
			T.truthy(string.format("%.2f", W.HASTE) ~= string.format("%.2f", W.ATTACK_SPEED), "two weights apart")
			T.truthy(text:find(want, 1, true), want .. "\n" .. text)
			-- the helm's haste rating at W.HASTE_RATING: the same helm without the line in the bags loses it
			local G2 = env()
			G2.items.hastehelm = G.items.hastehelm
			G2.items.plainhelm = { info = { 27, "INVTYPE_HEAD", 4, 3 }, lines = { ln("Простой шлем"), ln("Голова", "Кольчуга"),
				ln("Броня: 200") }, api = {} }
			G2.equippedLinks[1] = "hastehelm"
			G2.bags[0] = { "plainhelm" }
			local ns2 = loadAll(G2)
			local st2 = ns2.Advisor.State()
			T.truthy(st2.W.HASTE_RATING > 0 and st2.W.HASTE_RATING < st2.W.ATTACK_SPEED - 1e-9, "below W.ATTACK_SPEED: the pet does not take it")
			T.near(ns2.Advisor.Evaluate("plainhelm", { kind = "bag", bag = 0, slot = 1 }).delta, -st2.W.HASTE_RATING, 1e-9,
				"the helm without its haste rating")
			-- two worn items of each: each item's aura 342 a factor of its own (wowsims registers each item's and enchant's
			-- speed aura apart, sim/core/enchant_speed.go:13-41), the haste rating summed (hasteRatingMultiplier = 1 + the
			-- rating / 1000, sim/core/unit.go:564-566); the stub's items carry the lines on head and hands alike
			local G4 = env()
			G4.items.hastehelm = G.items.hastehelm
			G4.items.ratinggloves = { info = { 28, "INVTYPE_HAND", 4, 3 }, lines = { ln("Перчатки рейтинга"), ln("Кисти рук", "Кольчуга"),
				ln("Броня: 100"), ln("Если на персонаже: повышает скорость атаки и применения заклинаний на 1,0%.") }, api = {} }
			G4.items.mhhelm = { info = { 29, "INVTYPE_HEAD", 4, 3 }, lines = { ln("Шлем скорости"), ln("Голова", "Кольчуга"),
				ln("Броня: 200"), ln("Чары: +1% к скорости") }, api = {} }
			G4.items.mhgloves = { info = { 41, "INVTYPE_HAND", 4, 3 }, lines = { ln("Перчатки скорости"), ln("Кисти рук", "Кольчуга"),
				ln("Броня: 100"), ln("Чары: +1% к скорости") }, api = {} }
			G4.equippedLinks[1], G4.equippedLinks[10] = "hastehelm", "ratinggloves"
			same(loadAll(G4).Advisor.State().snap.model, { 0, 0, 2 }, "two items' haste rating: 1 + 1, summed")
			local G5 = env()
			G5.items.mhhelm, G5.items.mhgloves = G4.items.mhhelm, G4.items.mhgloves
			G5.equippedLinks[1], G5.equippedLinks[10] = "mhhelm", "mhgloves"
			same(loadAll(G5).Advisor.State().snap.model, { (1.01 * 1.01 - 1) * 100, 0, 0 }, "two items' aura 342: 1.01 x 1.01")
			-- a set bonus of HASTE or HASTE_RATING is an error (Game/SetData.lua writes a set bonus's speed as ATTACK_SPEED)
			for _, key in ipairs({ "HASTE", "HASTE_RATING" }) do
				local G3 = env()
				G3.items.wschest, G3.items.wshands = G.items.wschest, G.items.wshands
				G3.equippedLinks[5], G3.equippedLinks[10] = "wschest", "wshands"
				local ns3 = loadAll(G3)
				ns3.SetData[2101] = { name = "test", { n = 2, stats = { [key] = 1 } } }
				ns3.Advisor.Reset()
				local ok, err = pcall(ns3.Player.Snapshot)
				T.eq(ok, false, "a set bonus of " .. key)
				T.truthy(tostring(err):find("a worn set bonus of HASTE or HASTE_RATING", 1, true), tostring(err))
			end
		end },
		-- the worn attack speed enchants by scope (Parse's attack speed enchants; Player wornHaste): Minor Haste 931 on
		-- gloves (aura 342: haste), Iron Counterweight 34 on a two-handed axe (aura 319: melee-only), Arcanum of Rapidity
		-- 2543 on head and legs (aura 319 + 140: melee-only and ranged-only), Automatic Crowd Pummeler 7123 on shoulders
		-- (aura 319 bp 50); each factor multiplies with the other sources of its scope (Wind Blessed for haste)
		{ "attack speed enchants: the worn ones reach the model by scope and multiply; bag items are priced with theirs; worn 0", function()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function setup(G)
				local skill = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 172 then return { rank = 215, maxRank = 215, modifier = 0 } end -- two-handed axes
					return skill(id)
				end
				local function axe(id, enchant)
					local lines = { ln("Секира"), ln("Двуручное", "Топор"), ln("Урон: 112-168", "Скорость 3,60"),
						ln("(38,9 ед. урона в секунду)"), ln("+10 к ловкости") }
					if enchant then lines[#lines + 1] = ln("Чары: Противовес (+3% к скорости атаки)") end
					return { info = { id, "INVTYPE_2HWEAPON", 2, 1 }, lines = lines, api = {} }
				end
				G.items.cwaxe, G.items.plainaxe = axe(30, true), axe(31, false)
				local function armor(id, loc, slotText, enchant)
					local lines = { ln("Доспех " .. id), ln(slotText, "Кожа"), ln("Броня: 100"), ln("+8 к ловкости") }
					if enchant then lines[#lines + 1] = ln("Чары: " .. enchant) end
					return { info = { id, loc, 4, 2 }, lines = lines, api = {} }
				end
				G.items.rapidhelm = armor(32, "INVTYPE_HEAD", "Голова", "+1% к скорости атаки")
				G.items.plainhelm = armor(33, "INVTYPE_HEAD", "Голова")
				G.items.rapidlegs = armor(34, "INVTYPE_LEGS", "Ноги", "+1% к скорости атаки")
				G.items.hastegloves = armor(35, "INVTYPE_HAND", "Кисти рук", "+1% к скорости")
				G.items.plaingloves = armor(36, "INVTYPE_HAND", "Кисти рук")
				G.items.pummelshoulders = armor(37, "INVTYPE_SHOULDER", "Плечи", "Автоматический пробойник толпы")
			end
			local G = env()
			setup(G)
			G.equippedLinks[16], G.equippedLinks[17] = "cwaxe", nil
			G.equippedLinks[1], G.equippedLinks[7], G.equippedLinks[10] = "rapidhelm", "rapidlegs", "hastegloves"
			G.IsPlayerSpell = function(id) return id == 1259710 end -- Wind Blessed
			G.bags[0] = { "plainaxe", "plainhelm", "plaingloves", "cwaxe" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local m = st.snap.model
			T.near(m.haste, 1, 1e-9, "Minor Haste, an enchant's aura 342")
			T.near(m.attackSpeed, 2, 1e-9, "Wind Blessed")
			T.near(m.meleeHaste, (1.03 * 1.01 * 1.01 - 1) * 100, 1e-9, "the counterweight x two Arcanums")
			T.near(m.rangedHaste, (1.01 * 1.01 - 1) * 100, 1e-9, "two Arcanums' ranged halves")
			T.eq(st.model.meleeHaste, m.meleeHaste); T.eq(st.model.rangedHaste, m.rangedHaste)
			-- the bag items: the same pieces without the enchant lose exactly the enchant's scope weights
			local W = st.W
			T.truthy(W.MELEE_HASTE > 0 and W.RANGED_HASTE > 0 and W.HASTE > 0, "every scope has a damage weight")
			T.near(ns.Advisor.Evaluate("plainaxe", { kind = "bag", bag = 0, slot = 1 }).delta, -3 * W.MELEE_HASTE, 1e-9,
				"the axe without its counterweight")
			T.near(ns.Advisor.Evaluate("plainhelm", { kind = "bag", bag = 0, slot = 2 }).delta, -(W.MELEE_HASTE + W.RANGED_HASTE), 1e-9,
				"the helm without Arcanum: both scopes")
			T.near(ns.Advisor.Evaluate("plaingloves", { kind = "bag", bag = 0, slot = 3 }).delta, -W.HASTE, 1e-9,
				"the gloves without Minor Haste")
			-- the worn set gives 0: its weapons at the worn attack speed, a bag copy of the worn axe
			T.eq(st.ctx.weaponGain(st.snap.equipped), 0, "the worn weapons")
			T.near(ns.Advisor.Evaluate("cwaxe", { kind = "bag", bag = 0, slot = 4 }).delta, 0, 1e-12, "the bag copy of the worn axe")
			-- a bag two-hander with a counterweight is priced with it: the worn axe plain, the enchanted one in the bags
			local G2 = env()
			setup(G2)
			G2.equippedLinks[16], G2.equippedLinks[17] = "plainaxe", nil
			G2.bags[0] = { "cwaxe" }
			local ns2 = loadAll(G2)
			local st2 = ns2.Advisor.State()
			T.near(st2.snap.model.meleeHaste, 0, 1e-12, "nothing worn")
			T.near(ns2.Advisor.Evaluate("cwaxe", { kind = "bag", bag = 0, slot = 1 }).delta, 3 * st2.W.MELEE_HASTE, 1e-9,
				"the bag axe's counterweight")
			-- the shoulders: 50% melee speed (spell 432137)
			local G3 = env()
			setup(G3)
			G3.equippedLinks[3] = "pummelshoulders"
			local st3 = loadAll(G3).Advisor.State()
			T.near(st3.snap.model.meleeHaste, 50, 1e-9, "Automatic Crowd Pummeler")
			T.near(st3.snap.model.rangedHaste, 0, 1e-12); T.near(st3.snap.model.haste, 0, 1e-12)
			-- a set bonus of each scope (no Game/SetData.lua bonus has aura 319 or 140; a test set 9101) multiplies with the
			-- worn items' factors of its scope
			local G5 = env()
			setup(G5)
			G5.items.rapidhelm.setID, G5.items.rapidlegs.setID = 9101, 9101
			G5.equippedLinks[1], G5.equippedLinks[7] = "rapidhelm", "rapidlegs"
			local ns5 = loadAll(G5)
			ns5.SetData[9101] = { name = "test", { n = 2, stats = { MELEE_HASTE = 2, RANGED_HASTE = 4 } } }
			ns5.Advisor.Reset()
			local m5 = ns5.Advisor.State().snap.model
			T.near(m5.meleeHaste, (1.01 * 1.01 * 1.02 - 1) * 100, 1e-9, "two Arcanums x the set's melee-only 2%")
			T.near(m5.rangedHaste, (1.01 * 1.01 * 1.04 - 1) * 100, 1e-9, "two Arcanums x the set's ranged-only 4%")
			T.near(m5.haste, 0, 1e-12)
			-- the pet: the counterweight's 3% is in the hunter's swing (3.60 / 1.03) and, after its heartbeat, in the
			-- pet's (1.2 / 1.03); PetSwing divides it out, and the model's meleeHaste puts it back on the pet
			local G4 = env()
			setup(G4)
			G4.equippedLinks[16], G4.equippedLinks[17] = "cwaxe", nil
			G4.ownerSpeed, G4.ownerOffSpeed, G4.petSpeed = 3.6 / 1.03, nil, 1.2 / 1.03
			local ns4 = loadAll(G4)
			settlePet(G4)
			local st4 = ns4.Advisor.State()
			T.near(st4.snap.model.petSwing, 1.2, 1e-9, "the pet's own swing")
			T.near(st4.snap.model.meleeHaste, 3, 1e-9)
			local p = {}
			for k, v in pairs(st4.model) do p[k] = v end
			local withIt = ns4.Model.Parts(p).pet
			p.meleeHaste = 0
			T.truthy(withIt > ns4.Model.Parts(p).pet + 1e-9, "the pet takes the counterweight's 3%")
			p.haste = (1 + p.haste / 100) * 1.03 * 100 - 100
			T.near(ns4.Model.Parts(p).pet, withIt, 1e-9, "as it takes the same 3% of p.haste")
			T.eq(#G.reportedErrors + #G2.reportedErrors + #G3.reportedErrors + #G4.reportedErrors + #G5.reportedErrors, 0)
		end },
		-- /hga weights: the model's attack speed inputs, their weights and W.HIT_DW; a stale reading for a Use buff
		-- (Player.ReadStats staleBy "useBuff": a worn item's Use buff up, Nat Pagle's Broken Reel 231271, spell 468164) is
		-- said with that reason; /hga dump lists statsStale
		{ "/hga weights prints the attack speed inputs and weights and W.HIT_DW; a stale reading for a Use buff says so; dump has statsStale", function()
			local G = env()
			survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			-- Arcanum of Rapidity on the legs (SpellEquippedItems 181984: head and legs)
			G.items.rapidlegs = { info = { 38, "INVTYPE_LEGS", 4, 2 }, lines = { ln("Поножи"), ln("Ноги"), ln("Броня: 100"),
				ln("Чары: +1% к скорости атаки") }, api = {} }
			G.equippedLinks[7] = "rapidlegs"
			-- Automatic Crowd Pummeler on the shoulders (SpellEquippedItems 252250: shoulders): 50% melee-only
			G.items.pummelshoulders = { info = { 39, "INVTYPE_SHOULDER", 4, 2 }, lines = { ln("Наплечники"), ln("Плечи"),
				ln("Броня: 80"), ln("Чары: Автоматический пробойник толпы") }, api = {} }
			G.equippedLinks[3] = "pummelshoulders"
			G.IsPlayerSpell = function(id) return id == 1259710 end
			local ns = loadAll(G)
			local function weights()
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR("weights")
				return table.concat(G.printed, "\n")
			end
			local text = weights()
			local st = ns.Advisor.State()
			local W = st.W
			-- the inputs by source (Player wornHaste): Wind Blessed's 2% is attack speed, which the hawks do not take
			T.truthy(text:find("скорость атаки (надетое): общая 0.00% (выстрелы, ближний бой, пет, ястребы), скорость атаки (комплект, раса) 2.00% (выстрелы, ближний бой, пет), рейтинг скорости 0.00% (выстрелы, ближний бой), только ближний бой 51.50% (ближний бой, пет), только дальний бой 1.00% (выстрелы, ястребы)", 1, true), text)
			local want = string.format("скорость атаки 1%% %.2f (скорость атаки (комплект, раса) %.2f, рейтинг скорости %.2f, только ближний бой %.2f, только дальний бой %.2f)",
				W.HASTE, W.ATTACK_SPEED, W.HASTE_RATING, W.MELEE_HASTE, W.RANGED_HASTE)
			T.truthy(text:find(want, 1, true), want .. "\n" .. text)
			T.truthy(W.HIT_DW > 0, "the weave and dual wield: W.HIT_DW has a value")
			-- W.HIT_DW and the main hand's part of it, W.HIT_DW_MH (Model.Weights, raid-mode W1 design 3.4)
			local dw = string.format("сверх капа с двумя оружиями %.2f, из них правая рука %.2f)", W.HIT_DW, W.HIT_DW_MH)
			T.truthy(text:find(dw, 1, true), dw .. "\n" .. text)
			T.truthy(W.HIT_DW_MH > 0 and W.HIT_DW_MH <= W.HIT_DW + 1e-12, "the main hand's part: " .. W.HIT_DW_MH .. " of " .. W.HIT_DW)
			T.eq(text:find("последнее чтение", 1, true), nil, "a live reading: no stale line")
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.eq(ns.db.dump.statsStale, false, "dump: a live reading")
			T.near(ns.db.dump.model.meleeHaste, (1.01 * 1.5 - 1) * 100, 1e-9, "dump: the model's melee-only haste")
			-- the Reel's buff comes up: the last reading of this gear serves, and /hga says so, for the buff
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			G.fire("PLAYER_REGEN_ENABLED")
			T.eq(ns.Advisor.State().snap.statsStaleBy, "useBuff")
			text = weights()
			T.truthy(text:find("статы — последнее чтение с этой же экипировкой и талантами: сейчас действует бафф «Использования» вещи (или игра его скрывает)", 1, true), text)
			T.eq(text:find("игра скрывает статы", 1, true), nil, "the Use buff's reason alone")
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.eq(ns.db.dump.statsStale, true, "dump: the last reading")
			T.eq(#G.reportedErrors, 0)
		end },
		-- /hga weights: a stale reading for hidden stats (Player.ReadStats staleBy "hidden": the stats secret, Aspect of the
		-- Hawk's state unknown, or Trueshot Aura's, which ReadStats reads only with the Trueshot Aura talent, node 105004, or a
		-- stat multiplier's) names the stats and the aura states that cause it, never the Use buff.
		{ "/hga weights: a stale reading for hidden stats names the stats and Aspect of the Hawk, Trueshot Aura with its talent", function()
			local USE_TEXT = "сейчас действует бафф «Использования» вещи"
			local function weights(G)
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR("weights")
				return table.concat(G.printed, "\n")
			end
			-- without the Trueshot Aura talent: the stats or Aspect of the Hawk's state
			local G = env(); local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.statsStale, nil)
			T.eq(weights(G):find("последнее чтение", 1, true), nil, "a live reading: no stale line")
			local HAWK_ONLY = "статы — последнее чтение с этой же экипировкой и талантами: игра скрывает статы, состояние Aspect of the Hawk или баффов, умножающих статы (Kings и т. п.)"
			G.secretValues = { [413] = true }
			ns.Invalidate()
			T.eq(ns.Advisor.State().snap.statsStaleBy, "hidden", "secret stats")
			local text = weights(G)
			T.truthy(text:find(HAWK_ONLY, 1, true), text)
			T.eq(text:find("Trueshot Aura", 1, true), nil, "no Trueshot Aura talent: its state is not read, not named")
			T.eq(text:find(USE_TEXT, 1, true), nil, "hidden stats: no Use buff text")
			-- Aspect of the Hawk V (14321) up and its aura secret: its state unknown
			G.secretValues = nil; G.secretAuras[14321] = true
			ns.Invalidate()
			T.eq(ns.Advisor.State().snap.statsStaleBy, "hidden", "the aspect's state unknown")
			text = weights(G)
			T.truthy(text:find(HAWK_ONLY, 1, true), text)
			T.eq(text:find(USE_TEXT, 1, true), nil)
			-- with the Trueshot Aura talent: its state is read too and named
			local G2 = env()
			G2.talentRanks[105004] = 1
			local ns2 = loadAll(G2)
			local st = ns2.Advisor.State()
			T.eq(st.snap.statsStale, nil); T.eq(st.snap.model.tal.trueshotAura, 1)
			local BOTH = "статы — последнее чтение с этой же экипировкой и талантами: игра скрывает статы, состояние Aspect of the Hawk, Trueshot Aura или баффов, умножающих статы (Kings и т. п.)"
			-- Trueshot Aura rank 5 (20906; ruRU Spell.csv NameSubtext "Уровень 5") secret: its state unknown
			G2.secretAuras[20906] = true
			ns2.Invalidate()
			T.eq(ns2.Advisor.State().snap.statsStaleBy, "hidden", "Trueshot Aura's state unknown")
			text = weights(G2)
			T.truthy(text:find(BOTH, 1, true), text)
			T.eq(text:find(USE_TEXT, 1, true), nil)
			-- the stats secret with the talent: the same line
			G2.secretAuras[20906] = nil; G2.secretValues = { [413] = true }
			ns2.Invalidate()
			T.eq(ns2.Advisor.State().snap.statsStaleBy, "hidden", "secret stats with the talent")
			text = weights(G2)
			T.truthy(text:find(BOTH, 1, true), text)
			T.eq(#G.reportedErrors + #G2.reportedErrors, 0)
		end },
		-- The live sheet's stat multipliers (the user's answer O8 = (a), raid-mode design 4.8): Player.ReadStats multiplies
		-- 1 + percent / 100 of each aura of Game/StatMultData.lua up on the player into the reading's statMult (Snapshot:
		-- model.statMult), each attribute by the client stat index the aura names (0 Strength, 1 Agility, 3 Intellect, 4
		-- Spirit); an aura whose state the client keeps secret hides the reading (the last one of the same gear and talents
		-- serves, with its multipliers). The generated data: Greater Blessing of Kings 25898 all five stats 10, Lightning
		-- Reflexes 19168 (read as a talent rank) left out
		{ "stat multipliers: Snapshot multiplies the live auras of Game/StatMultData.lua; an unknown aura state hides the reading; the data", function()
			local G = env(); local ns = loadAll(G)
			local SM = ns.StatMultData
			for i = 0, 4 do T.eq(SM[25898][i], 10, "Greater Blessing of Kings, stat " .. i) end
			T.eq(SM[19168], nil, "Lightning Reflexes: the model reads its rank")
			T.eq(SM[24425][1], 15, "Spirit of Zandalar"); T.eq(SM[1299796][4], 100); T.eq(SM[1299796][1], nil, "Insight: Spirit alone")
			local function mult() return ns.Advisor.State().snap.model.statMult end
			local function same(m, want, msg)
				for k, v in pairs(want) do T.near(m[k], v, 1e-12, msg .. " " .. k) end
			end
			same(mult(), { AGI = 1, STR = 1, INT = 1, SPI = 1 }, "no aura")
			local W0 = ns.Advisor.State().W
			G.auras.player[25898] = true
			ns.Invalidate()
			same(mult(), { AGI = 1.1, STR = 1.1, INT = 1.1, SPI = 1.1 }, "Greater Blessing of Kings")
			T.truthy(ns.Advisor.State().W.AGI > W0.AGI * 1.05, "W.AGI under Kings")
			-- two auras multiply; an aura of Spirit alone moves Spirit alone
			G.auras.player[24425] = true; G.auras.player[1299796] = true
			ns.Invalidate()
			same(mult(), { AGI = 1.1 * 1.15, STR = 1.1 * 1.15, INT = 1.1 * 1.15, SPI = 1.1 * 1.15 * 2 }, "Kings, Zandalar and Insight")
			-- Divine Strength 20262 (Strength 2%) and Heart of the Wild 17003 (Intellect 10%): each its own stat
			G.auras.player = { [14321] = true, [20262] = true, [17003] = true }
			ns.Invalidate()
			same(mult(), { AGI = 1, STR = 1.02, INT = 1.1, SPI = 1 }, "Strength and Intellect apart")
			-- aura 80 A_MOD_PERCENT_STAT (raid-mode design 24.3): Sayge's Dark Fortune of Agility 1304780 (Agility 10%) on its
			-- own, then with Elune's Blessing 26393 (all five 10%)
			T.eq(SM[1304780][1], 10, "Sayge's Dark Fortune of Agility"); T.eq(SM[1304780][0], nil)
			for i = 0, 4 do T.eq(SM[26393][i], 10, "Elune's Blessing, stat " .. i) end
			G.auras.player = { [14321] = true, [1304780] = true }
			ns.Invalidate()
			same(mult(), { AGI = 1.1, STR = 1, INT = 1, SPI = 1 }, "Sayge's Agility")
			G.auras.player[26393] = true
			ns.Invalidate()
			same(mult(), { AGI = 1.1 * 1.1, STR = 1.1, INT = 1.1, SPI = 1.1 }, "Sayge's Agility and Elune's Blessing")
			G.auras.player = { [14321] = true, [20262] = true, [17003] = true }
			ns.Invalidate()
			-- an aura's state secret: the reading hides, the last one serves with its own multipliers
			G.secretAuras[25898] = true
			ns.Invalidate()
			local st = ns.Advisor.State()
			T.eq(st.snap.statsStaleBy, "hidden", "a stat multiplier's state unknown")
			same(st.snap.model.statMult, { AGI = 1, STR = 1.02, INT = 1.1, SPI = 1 }, "the last reading's")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local text = table.concat(G.printed, "\n")
			T.truthy(text:find("игра скрывает статы, состояние Aspect of the Hawk или баффов, умножающих статы (Kings и т. п.)", 1, true), text)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.near(ns.db.dump.model.statMult.INT, 1.1, 1e-12, "dump: the model's statMult")
			T.eq(#G.reportedErrors, 0)
		end },
		{ "pet family: a secret family id is not taken, the last one seen stays", function()
			local G = env(); local ns = loadAll(G)
			local P = ns.Player
			T.eq(P.PetFamily(), 2)
			G.petFamilyID = 1; G.secretValues = { [1] = true }
			T.eq(P.PetFamily(), 2, "secret id: the last family stays")
			G.secretValues = nil
			T.eq(P.PetFamily(), 1)
			G.petFamilyID = nil
			T.eq(P.PetFamily(), 1, "no id: the last family stays")
		end },
		{ "pet swing: not seen under Frenzy; Frenzy ending (UNIT_ATTACK_SPEED of the pet) reads it; /hga weights and dump show it", function()
			local G = env()
			G.auras.pet[19615] = true
			local ns = loadAll(G)
			settlePet(G)
			T.eq(ns.Advisor.State().snap.model.petSwing, nil, "Frenzy up since login: not seen")
			T.eq(#G.timers, 0, "held back by Frenzy, not by the wait: no re-check")
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local text = table.concat(G.printed, "\n")
			T.truthy(text:find("семейство +10% урона, Claw + Bite), удар ещё не виден — считается 2.0 с", 1, true), text)
			-- Frenzy ends: the pet's attack speed changes, the swing is read and the weights follow
			G.auras.pet[19615] = nil
			G.fire("UNIT_ATTACK_SPEED", "pet")
			T.eq(ns.Advisor.State().snap.model.petSwing, 1.2, "re-evaluated with the swing read")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			text = table.concat(G.printed, "\n")
			T.truthy(text:find("семейство +10% урона, Claw + Bite), удар 1.20 с", 1, true), text)
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.eq(ns.db.dump.model.petSwing, 1.2, "the dump lists the model input")
			-- Lone Wolf with the pet out: the pet counts, so its swing is shown too
			G.talentRanks[105007] = 1
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			text = table.concat(G.printed, "\n")
			T.truthy(text:find("урон пета −17%, удар 1.20 с", 1, true), text)
		end },
		{ "pet swing: a restriction ending (ADDON_RESTRICTION_STATE_CHANGED) reads it", function()
			local G = env()
			G.secretAuras[19615] = true
			local ns = loadAll(G)
			settlePet(G)
			T.eq(ns.Advisor.State().snap.model.petSwing, nil, "Frenzy's aura secret: not seen")
			G.secretAuras = {}
			G.fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
			T.eq(ns.Advisor.State().snap.model.petSwing, 1.2, "restriction ended: read")
		end },
		-- Aspect of the Hawk and Trueshot Aura can be secret (GetPlayerAuraBySpellID:
		-- SecretWhenUnitAuraRestricted, RequiresNonSecretAura); a secret aura returns nothing, which is no "off"
		{ "secret aura: a secret Aspect of the Hawk or Trueshot Aura does not add its RAP a second time", function()
			-- no reading yet and the aspect's state unknown: stats hidden
			local G = env()
			G.secretAuras[14321] = true
			local ns = loadAll(G)
			T.eq(ns.Advisor.State(), nil, "aspect unknown, nothing read before"); T.eq(ns.Advisor.notReadyReason, "hidden")
			-- read with the aspect up, then the aura turns secret: the last reading, not + the aspect's RAP
			local G2 = env(); local ns2 = loadAll(G2)
			local rap0 = ns2.Advisor.State().snap.model.rap
			T.eq(rap0, 413 + 70, "aspect up: its RAP is in the sheet, nothing added")
			G2.secretAuras[14321] = true
			ns2.Invalidate()
			local st = ns2.Advisor.State()
			T.eq(st.snap.model.rap, rap0, "aspect secret: the last reading")
			T.eq(st.snap.statsStale, true, "marked as the last reading")
			-- the stats secret and the aspect off since: the last reading with the aspect state read with it
			G2.secretAuras = {}; G2.auras.player[14321] = nil
			G2.secretValues = { [413] = true }
			ns2.Invalidate()
			T.eq(ns2.Advisor.State().snap.model.rap, rap0, "the last RAP goes with the aspect state of its reading")
			-- Trueshot Aura taken and up (rank of 40: 19506, +50 RAP in the sheet), then secret
			local G3 = env()
			G3.talentRanks[105004] = 1; G3.auras.player[19506] = true
			G3.UnitRangedAttackPower = function() return 413, 70 + 50, 0 end
			local ns3 = loadAll(G3)
			local rap3 = ns3.Advisor.State().snap.model.rap
			T.eq(rap3, 413 + 120, "Trueshot Aura up: nothing added")
			G3.secretAuras[19506] = true
			ns3.Invalidate()
			T.eq(ns3.Advisor.State().snap.model.rap, rap3, "Trueshot Aura secret: not +50")
			-- the talent not taken: Trueshot Aura's state is not needed, a secret one (another hunter's) hides nothing
			local G4 = env()
			for _, id in ipairs({ 1299346, 1299348, 19506, 20905, 20906 }) do G4.secretAuras[id] = true end
			local ns4 = loadAll(G4)
			local st4 = ns4.Advisor.State()
			T.truthy(st4, "stats read without the talent")
			T.eq(st4.snap.statsStale, nil, "a fresh reading"); T.eq(st4.snap.model.rap, 413 + 70)
			-- the talent taken while the aura is secret: the last reading has no Trueshot state, none is used
			G4.talentRanks[105004] = 1
			G4.fire("TRAIT_CONFIG_UPDATED", 7)
			T.eq(ns4.Advisor.State(), nil, "no reading with the aura's state"); T.eq(ns4.Advisor.notReadyReason, "hidden")
		end },
		-- Player.ReadStats: a worn item's Use buff that is up is in the sheet values, and Score.SetValue prices it over
		-- its uptime. Nat Pagle's Broken Reel 231271 (Game/UseData.lua: spell 468164, HIT 10; DB2 SpellEffect 468164
		-- index 1: APPLY_AURA 54 A_MOD_HIT_CHANCE bp 10 on the caster) puts 10% into the ranged hit modifier.
		{ "use buff: up, the last reading of the same gear is taken; all known off, the live reading", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			local ns = loadAll(G)
			local st0 = ns.Advisor.State()
			T.eq(st0.snap.statsStale, nil, "buff off: the live reading")
			T.near(st0.ctx.baseHit, 1, 1e-9)
			local helm0 = ns.Advisor.Evaluate("newhelm").delta
			-- the buff comes up (the trinket used in the fight that just ended): +10% in the ranged hit modifier
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			G.fire("PLAYER_REGEN_ENABLED")
			local st = ns.Advisor.State()
			T.truthy(st, "the last reading of this gear serves")
			T.eq(st.snap.statsStale, true, "marked as the last reading")
			T.near(st.snap.liveHit, 1, 1e-9, "the hit read without the buff")
			T.near(st.ctx.baseHit, 1, 1e-9, "the base hit leaves the buff's 10% out")
			T.near(st.snap.model.hit, 1, 1e-9, "the model's hit as well")
			T.near(ns.Advisor.Evaluate("newhelm").delta, helm0, 1e-9, "a 1% hit helm scores as with the buff off")
			-- the buff falls: every worn Use buff known off, the live reading counts (a newer RAP)
			G.auras.player[468164] = nil
			G.GetRangedHitModifier = function() return 0 end
			G.UnitRangedAttackPower = function() return 420, 70, 0 end
			ns.Invalidate()
			local st2 = ns.Advisor.State()
			T.eq(st2.snap.statsStale, nil, "the live reading again")
			T.eq(st2.snap.model.rap, 420 + 70, "the newer RAP")
		end },
		{ "use buff: up with no reading of this gear, no evaluation and said; the stats read once it falls", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			local ns = loadAll(G)
			T.eq(ns.Advisor.State(), nil, "no reading without the buff")
			T.eq(ns.Advisor.notReadyReason, "useBuff")
			local lines = ns.Advisor.Explain("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(lines[1][1], "HGA: действует бафф «Использования» вещи (или игра его скрывает) — оценка появится, когда он спадёт")
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.truthy(G.printed[#G.printed]:find("действует бафф «Использования» вещи", 1, true), G.printed[#G.printed])
			local banner = G.HunterGearAdvisorSwapBanner
			T.eq(banner.shown, false, "no banner without an evaluation")
			-- still up a second later: still refused
			G.advance(1)
			T.eq(ns.Advisor.notReadyReason, "useBuff"); T.eq(banner.shown, false)
			-- the buff falls: the Use-buff check reads the stats and the banner comes back on its own
			G.auras.player[468164] = nil
			G.GetRangedHitModifier = function() return 0 end
			G.advance(1)
			T.eq(banner.shown, true, "re-evaluated once the buff is gone")
			local st = ns.Advisor.State()
			T.eq(st.snap.statsStale, nil); T.near(st.ctx.baseHit, 1, 1e-9)
			T.eq(ns.Advisor.notReadyReason, nil)
		end },
		-- A stat-lowering aura on the sheet (raid-mode design 25.6; Game/StatMultData.lua StatDebuffData: Resurrection Sickness
		-- 15007, aura 80 -75% to every stat; Coward! 422978, aura 137 -20%): the sheet under it is not the character's, so,
		-- as for a Use buff, Player.ReadStats takes the last reading of the same gear and talents (statsStaleBy "debuff") and
		-- the weights stay those of the reading before; the aura up or kept secret with no such reading, no evaluation, and
		-- the tooltip and /hga weights say why; the aura's state is checked every second and the stats are read once it falls
		{ "debuff: a reading under Resurrection Sickness keeps the previous weights; with no earlier reading none, said; the stats read once it falls", function()
			local G = env()
			local ns1 = loadAll(G)
			settlePet(G)
			T.eq(ns1.StatDebuffData[15007], true, "Resurrection Sickness"); T.eq(ns1.StatDebuffData[422978], true, "Coward!")
			T.eq(ns1.StatMultData[15007], nil, "not a stat multiplier")
			local st0 = ns1.Advisor.State()
			T.eq(st0.snap.statsStale, nil)
			local W0 = st0.W
			-- Resurrection Sickness: the sheet's attack power and crit fall
			G.auras.player[15007] = true
			local rap = G.UnitRangedAttackPower
			G.UnitRangedAttackPower = function(u) local b, p, n = rap(u); return b / 4, p, n end
			G.GetRangedCritChance = function() return 3 end
			ns1.Invalidate()
			local st = ns1.Advisor.State()
			T.eq(st.snap.statsStaleBy, "debuff"); T.eq(st.snap.model.crit, st0.snap.model.crit, "the last reading's crit")
			T.eq(st.snap.model.rap, st0.snap.model.rap, "the last reading's attack power")
			for _, k in ipairs({ "AGI", "AP", "CRIT", "HIT", "HASTE" }) do T.eq(st.W[k], W0[k], "W." .. k .. " as before") end
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local said
			for _, l in ipairs(G.printed) do if l:find("на персонаже аура, снижающая статы", 1, true) then said = l end end
			T.truthy(said, "the weights say the reading is the last one")
			-- the aura kept secret: the same
			G.auras.player[15007] = nil; G.secretAuras[422978] = true
			ns1.Invalidate()
			T.eq(ns1.Advisor.State().snap.statsStaleBy, "debuff", "a stat-lowering aura's state unknown")
			-- it falls: the check reads the stats, the sheet's own values
			G.secretAuras[422978] = nil
			G.advance(1)
			st = ns1.Advisor.State()
			T.eq(st.snap.statsStale, nil, "the live reading"); T.eq(st.snap.model.crit, 3, "the sheet's crit now")
			-- a stat-lowering aura and a Use buff (Nat Pagle's Broken Reel's 468164) up together: the reason "debuff" (ReadStats'
			-- order "hidden", "debuff", "useBuff"), so the check waits on the stat-lowering auras; once they fall the Use buff
			-- keeps the reading the last one, and once it falls too the stats are read
			G.auras.player[15007] = true; G.auras.player[468164] = true
			ns1.Invalidate()
			T.eq(ns1.Advisor.State().snap.statsStaleBy, "debuff", "both up: the stat-lowering aura first")
			G.auras.player[15007] = nil
			G.advance(1)
			T.eq(ns1.Advisor.State().snap.statsStaleBy, "useBuff", "the stat-lowering aura gone: the Use buff's turn")
			G.auras.player[468164] = nil
			G.advance(1)
			T.eq(ns1.Advisor.State().snap.statsStale, nil, "both gone: the live reading")
			-- both up at login, no earlier reading: none, for the stat-lowering aura
			local G3 = env()
			G3.auras.player[15007] = true; G3.auras.player[468164] = true
			local ns3 = loadAll(G3)
			T.eq(ns3.Advisor.State(), nil); T.eq(ns3.Advisor.notReadyReason, "debuff", "both up at login: the stat-lowering aura first")
			-- up at login, no earlier reading: no evaluation, said
			local G2 = env()
			G2.auras.player[422978] = true
			local ns2 = loadAll(G2)
			T.eq(ns2.Advisor.State(), nil, "no reading without the aura")
			T.eq(ns2.Advisor.notReadyReason, "debuff")
			local lines = ns2.Advisor.Explain("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(lines[1][1], "HGA: на персонаже аура, снижающая статы (Resurrection Sickness и т. п., или игра её скрывает) — оценка появится, когда она спадёт")
			local calls = 0
			local invalidate = ns2.Invalidate
			ns2.Invalidate = function() calls = calls + 1; invalidate() end
			G2.advance(1); G2.advance(1)
			T.eq(ns2.Advisor.notReadyReason, "debuff", "still up")
			T.eq(calls, 0, "no re-read while it is up (the check reads the stat-lowering auras, not the Use buffs)")
			G2.auras.player[422978] = nil
			G2.advance(1)
			T.truthy(ns2.Advisor.State() ~= nil, "read once it falls"); T.eq(ns2.Advisor.notReadyReason, nil)
			T.eq(#G.reportedErrors, 0); T.eq(#G2.reportedErrors, 0); T.eq(#G3.reportedErrors, 0)
		end },
		-- the worn items a reading is taken with: per slot the item id, enchant id and suffix id of the link's item
		-- string (item:itemID:enchantID:gemID1:gemID2:gemID3:gemID4:suffixID:uniqueID:linkLevel:..., Forever UI
		-- Blizzard_PTRFeedback/Blizzard_Reports.lua)
		{ "use buff: a last reading of other gear is not used; the link's item id, enchant and suffix tell the gear", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			local function talisman(link, id)
				G.items[link] = { info = { id, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Талисман"), ln("Аксессуар"), ln("+10 к выносливости") },
					api = { ITEM_MOD_STAMINA_SHORT = 10 } }
				return link
			end
			local base = talisman("|cff1eff00|Hitem:60010::::::::43:::::|h[Талисман]|h|r", 60010)
			local otherCopy = talisman("|cff1eff00|Hitem:60010:::::::777:43:::::|h[Талисман]|h|r", 60010) -- another uniqueID
			local enchanted = talisman("|cff1eff00|Hitem:60010:15:::::::43:::::|h[Талисман]|h|r", 60010)
			local suffixed = talisman("|cff1eff00|Hitem:60010::::::1200::43:::::|h[Талисман]|h|r", 60010)
			local otherItem = talisman("|cff1eff00|Hitem:60011::::::::43:::::|h[Талисман]|h|r", 60011)
			G.equippedLinks[13], G.equippedLinks[14] = "reel", base
			local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.statsStale, nil, "read with the buff off")
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			local function stateWith(link)
				G.equippedLinks[14] = link
				G.fire("PLAYER_EQUIPMENT_CHANGED")
				return ns.Advisor.State()
			end
			local st = stateWith(otherCopy)
			T.truthy(st and st.snap.statsStale, "another copy of the same item: the same gear")
			T.near(st.ctx.baseHit, 1, 1e-9)
			T.eq(stateWith(enchanted), nil, "another enchant: other gear"); T.eq(ns.Advisor.notReadyReason, "useBuff")
			T.truthy(stateWith(base), "the reading's own gear again")
			T.eq(stateWith(suffixed), nil, "another suffix: other gear")
			T.eq(stateWith(otherItem), nil, "another item: other gear")
			T.eq(stateWith(nil), nil, "the slot emptied: other gear")
			stateWith(base)
			G.equippedLinks[2] = otherItem
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			T.eq(ns.Advisor.State(), nil, "a slot filled: other gear")
		end },
		-- the item string states every field up to numBonusIDs at a fixed place (Forever UI
		-- Blizzard_PTRFeedback/Blizzard_Reports.lua:391): a worn link whose item string ends before its suffixID (field 7)
		-- is no link the client gives, an error, never a link whose missing fields read as empty
		{ "use buff: a worn item link whose item string ends before its suffixID is an error", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			local function talisman(link)
				G.items[link] = { info = { 60010, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Талисман"), ln("Аксессуар"), ln("+10 к выносливости") },
					api = { ITEM_MOD_STAMINA_SHORT = 10 } }
				return link
			end
			local base = talisman("|cff1eff00|Hitem:60010::::::::43:::::|h[Талисман]|h|r")
			local short = talisman("|cff1eff00|Hitem:60010:15|h[Талисман]|h|r")
			G.equippedLinks[13], G.equippedLinks[14] = "reel", base
			local ns = loadAll(G)
			T.eq(ns.Advisor.State().snap.statsStale, nil, "read with the buff off")
			G.auras.player[468164] = true
			G.equippedLinks[14] = short
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			local ok, err = pcall(ns.Advisor.State)
			T.eq(ok, false); T.truthy(tostring(err):find("whose item string ends before its suffixID", 1, true), tostring(err))
		end },
		{ "use buff: a Use buff whose state cannot be known counts as up", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			local function reel(g)
				g.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
					ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
				g.equippedLinks[13] = "reel"
			end
			reel(G)
			G.secretAuras[468164] = true
			local ns = loadAll(G)
			T.eq(ns.Advisor.State(), nil, "unknown and nothing read before"); T.eq(ns.Advisor.notReadyReason, "useBuff")
			-- read with the buff known off, then its aura turns secret while the sheet holds 10% more hit
			local G2 = env(); reel(G2)
			local ns2 = loadAll(G2)
			T.eq(ns2.Advisor.State().snap.statsStale, nil)
			G2.secretAuras[468164] = true
			G2.GetRangedHitModifier = function() return 10 end
			ns2.Invalidate()
			local st = ns2.Advisor.State()
			T.eq(st.snap.statsStale, true, "the last reading"); T.near(st.ctx.baseHit, 1, 1e-9, "not the sheet's 11%")
		end },
		{ "secret stats: a last reading of other gear is not used; hidden is said before a Use buff", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			local A = "|cff1eff00|Hitem:60010::::::::43:::::|h[Талисман]|h|r"
			local B = "|cff1eff00|Hitem:60011::::::::43:::::|h[Талисман]|h|r"
			for link, id in pairs({ [A] = 60010, [B] = 60011 }) do
				G.items[link] = { info = { id, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Талисман"), ln("Аксессуар"), ln("+10 к выносливости") }, api = {} }
			end
			G.equippedLinks[13], G.equippedLinks[14] = "reel", A
			local ns = loadAll(G)
			T.truthy(ns.Advisor.State(), "read with this gear")
			-- the stats turn secret (combat) and another trinket goes on
			G.secretValues = { [413] = true }
			G.equippedLinks[14] = B
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			T.eq(ns.Advisor.State(), nil, "the reading of the other trinket is not this gear's")
			T.eq(ns.Advisor.notReadyReason, "hidden")
			-- the Use buff up as well: the stats being hidden is said first
			G.auras.player[468164] = true
			ns.Invalidate()
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "hidden")
			-- the Aspect of the Hawk's state unknown with readable stats and other gear: hidden as well
			G.secretValues = nil; G.auras.player[468164] = nil; G.secretAuras[14321] = true
			ns.Invalidate()
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "hidden")
			-- the reading's own trinket back on: the last reading serves the secret stats
			G.secretAuras[14321] = nil; G.secretValues = { [413] = true }
			G.equippedLinks[14] = A
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			T.eq(ns.Advisor.State().snap.statsStale, true)
		end },
		-- A last reading serves only the applied talents it is taken with (Player.ReadStats: the ranks and branch points
		-- of Player.ReadTalents). Lightning Reflexes 5/5 (node 110859) applied out of combat while the Reel's buff (spell
		-- 468164) is up raises the sheet's Agility: RAP 483 -> 510, crit 8.66 -> 9.5.
		{ "use buff: a last reading serves only the applied talents it is taken with; the live one once the buff falls", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			local ns = loadAll(G)
			settlePet(G)
			local st0 = ns.Advisor.State()
			T.eq(st0.snap.statsStale, nil); T.eq(st0.snap.model.rap, 483); T.eq(st0.snap.model.crit, 8.66)
			-- the buff up and Lightning Reflexes clicked but not applied: the applied talents are the reading's
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			G.staged = true; G.talentRanks[110859] = 5
			G.fire("TRAIT_NODE_CHANGED")
			local st1 = ns.Advisor.State()
			T.truthy(st1 and st1.snap.statsStale, "staged clicks: the applied talents, so the last reading serves")
			T.eq(st1.snap.model.tal.lightningReflexes, 0)
			-- Apply: the sheet's Agility rises with the buff still up; the last reading is of other talents
			G.staged = false
			G.UnitRangedAttackPower = function() return 440, 70, 0 end
			G.GetRangedCritChance = function() return 9.5 end
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			T.eq(ns.Advisor.State(), nil, "other talents: no last reading serves")
			T.eq(ns.Advisor.notReadyReason, "useBuff")
			-- the stats secret too (the combat path): the same rule, and hidden is said first
			G.secretValues = { [440] = true }
			ns.Invalidate()
			T.eq(ns.Advisor.State(), nil, "secret stats, other talents: no last reading serves")
			T.eq(ns.Advisor.notReadyReason, "hidden")
			G.secretValues = nil
			ns.Invalidate()
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "useBuff")
			-- the buff falls: the Use-buff check reads the stats with the new talents
			G.auras.player[468164] = nil
			G.GetRangedHitModifier = function() return 0 end
			G.advance(1)
			local st = ns.Advisor.State()
			T.eq(st.snap.statsStale, nil, "the live reading")
			T.eq(st.snap.model.rap, 510); T.eq(st.snap.model.crit, 9.5); T.eq(st.snap.model.tal.lightningReflexes, 5)
			T.eq(#G.reportedErrors, 0)
		end },
		-- One talent on two nodes (Player SAME_TALENT): Lightning Reflexes' old node 104982 at 5 and the node 110859 put to 5
		-- leave ranks.lightningReflexes at 5; the SV points (5 -> 10) tell the talent states apart.
		{ "use buff: a last reading of the same talent ranks but other branch points does not serve", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			G.talentRanks[104982] = 5
			local ns = loadAll(G)
			local st0 = ns.Advisor.State()
			T.eq(st0.snap.statsStale, nil); T.eq(st0.snap.model.tal.lightningReflexes, 5); T.eq(st0.snap.points.SV, 5)
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			G.talentRanks[110859] = 5
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			T.eq(ns.Advisor.State(), nil, "the same ranks, other points: no last reading serves")
			T.eq(ns.Advisor.notReadyReason, "useBuff")
		end },
		-- A respec inside one branch keeps its points: Frenzy (node 104962) 4 -> 0 and Improved Aspect of the Monkey (node
		-- 104974) 0 -> 4 leave BM at 26 points, and only the ranks (Player.ReadStats sameTalents of ranks) tell the talent
		-- states apart. Applied while the Reel's buff (spell 468164) is up, with the sheet's crit at 9.9.
		{ "use buff: a last reading of the same branch points but other talent ranks does not serve", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			local ns = loadAll(G)
			settlePet(G)
			local st0 = ns.Advisor.State()
			T.eq(st0.snap.statsStale, nil); T.eq(st0.snap.points.BM, 26)
			T.eq(st0.snap.model.tal.frenzy, 4); T.eq(st0.snap.model.tal.improvedAspectOfTheMonkey, 0); T.eq(st0.snap.model.crit, 8.66)
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			G.talentRanks[104962] = 0; G.talentRanks[104974] = 4
			G.GetRangedCritChance = function() return 9.9 end
			G.fire("TRAIT_CONFIG_UPDATED", 7)
			T.eq(ns.Advisor.State(), nil, "the same points, other ranks: no last reading serves")
			T.eq(ns.Advisor.notReadyReason, "useBuff")
			-- the stats secret too (the combat path): the same rule, and hidden is said first
			G.secretValues = { [413] = true }
			ns.Invalidate()
			T.eq(ns.Advisor.State(), nil, "secret stats, the same points, other ranks: no last reading serves")
			T.eq(ns.Advisor.notReadyReason, "hidden")
			G.secretValues = nil
			ns.Invalidate()
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "useBuff")
			-- the buff falls: the Use-buff check reads the stats with the new ranks
			G.auras.player[468164] = nil
			G.GetRangedHitModifier = function() return 0 end
			G.advance(1)
			local st = ns.Advisor.State()
			T.eq(st.snap.statsStale, nil, "the live reading"); T.eq(st.snap.points.BM, 26)
			T.eq(st.snap.model.tal.frenzy, 0); T.eq(st.snap.model.tal.improvedAspectOfTheMonkey, 4)
			T.eq(st.snap.model.crit, 9.9); T.near(st.ctx.baseHit, 1, 1e-9)
			T.eq(#G.reportedErrors, 0)
		end },
		-- A reading taken while the client has no talent data (Player.ReadTalents "talents") has unknown talents: it serves
		-- unknown talents only, never the talents that arrive later.
		{ "use buff: a reading taken while the talents are unknown does not serve the talents that arrive", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			G.noTalentConfig = true
			local ns = loadAll(G)
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "talents")
			-- the buff up with the talents still unknown: the reading serves, and the talents are what is missing
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			ns.Invalidate()
			T.eq(ns.Advisor.State(), nil); T.eq(ns.Advisor.notReadyReason, "talents")
			-- the talents arrive with the buff still up: the reading is of unknown talents
			G.noTalentConfig = false
			G.fire("TRAIT_CONFIG_LIST_UPDATED")
			T.eq(ns.Advisor.State(), nil, "known talents: the reading of unknown ones does not serve")
			T.eq(ns.Advisor.notReadyReason, "useBuff")
			T.eq(#G.reportedErrors, 0)
		end },
		-- A state built from the last reading because of a Use buff (snap.statsStaleBy "useBuff") holds until the buff falls,
		-- which no event marks: Advisor checks the Use buffs' aura state every RETRY_AFTER (1 s) and re-reads the stats
		-- when it falls.
		{ "use buff: a state built from the last reading stays while the buff is up; the live reading once it falls", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.equippedLinks[13] = "reel"
			local ns = loadAll(G)
			settlePet(G)
			T.eq(ns.Advisor.State().snap.statsStale, nil)
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			G.fire("PLAYER_REGEN_ENABLED")
			T.eq(ns.Advisor.State().snap.statsStaleBy, "useBuff")
			-- the sheet's crit rises while the buff is up: the last reading stays
			G.GetRangedCritChance = function() return 11.66 end
			G.advance(1)
			local st = ns.Advisor.State()
			T.eq(st.snap.statsStaleBy, "useBuff", "still up: the last reading"); T.eq(st.snap.model.crit, 8.66)
			-- the buff falls: the Use-buff check takes the live reading, with no event
			G.auras.player[468164] = nil
			G.GetRangedHitModifier = function() return 0 end
			G.advance(1)
			st = ns.Advisor.State()
			T.eq(st.snap.statsStale, nil, "the live reading"); T.eq(st.snap.statsStaleBy, nil)
			T.eq(st.snap.model.crit, 11.66); T.near(st.ctx.baseHit, 1, 1e-9)
		end },
		-- Advisor's Use-buff check (checkUseBuff): while the last A.State waits on a Use buff (refused with "useBuff", or
		-- built from a reading with statsStaleBy "useBuff") it reads Player.UseBuffState every second and calls
		-- ns.Invalidate only once every Use buff is known to be off; a Use buff up or unknown (an aura the client keeps
		-- secret) keeps it waiting with the state as built. Once A.State ends otherwise (the stats hidden, the live reading
		-- used) the check calls nothing, the buff falling included. One check is pending at a time (useBuffCheck: one
		-- C_Timer.After), and its ns.Invalidate ends it: an A.State that waits again starts the next one.
		{ "use buff: the aura state is checked every second while A.State waits on a Use buff, one re-read when it falls", function()
			-- buff: "up" (the Reel's buff 468164 up at login), "secret" (its aura secret at login), nil (off)
			local function setup(buff)
				local G = env()
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
				G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
					ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
				G.equippedLinks[13] = "reel"
				if buff == "up" then G.auras.player[468164] = true end
				if buff == "secret" then G.secretAuras[468164] = true end
				if buff then G.GetRangedHitModifier = function() return 10 end end
				local ns = loadAll(G)
				settlePet(G)
				local calls = 0
				local invalidate = ns.Invalidate
				ns.Invalidate = function() calls = calls + 1; invalidate() end
				local function taken() local n = calls; calls = 0; return n end
				return G, ns, taken
			end
			local function buffFalls(G)
				G.auras.player[468164] = nil; G.secretAuras[468164] = nil
				G.GetRangedHitModifier = function() return 0 end
			end
			-- refused ("useBuff", no reading before), the buff up or its aura secret: nothing re-read while that holds, one
			-- re-read when it falls, then the live reading and no more
			for _, buff in ipairs({ "up", "secret" }) do
				local G, ns, taken = setup(buff)
				T.eq(ns.Advisor.State(), nil, buff); T.eq(ns.Advisor.notReadyReason, "useBuff", buff)
				taken()
				for s = 1, 4 do
					G.advance(1)
					T.eq(taken(), 0, "refused, the buff " .. buff .. ": no re-read at second " .. s)
				end
				T.eq(ns.Advisor.State(), nil, buff); T.eq(ns.Advisor.notReadyReason, "useBuff", buff)
				buffFalls(G)
				G.advance(1)
				T.eq(taken(), 1, "refused, the buff " .. buff .. " falls: one re-read")
				local st = ns.Advisor.State()
				T.truthy(st and st.snap.statsStale == nil, "refused, the buff " .. buff .. " falls: the live reading")
				T.near(st.ctx.baseHit, 1, 1e-9)
				G.advance(3)
				T.eq(taken(), 0, "the live reading: the check ends")
				T.eq(#G.reportedErrors, 0)
			end
			-- refused for the buff, then the stats turn secret: refused as hidden, so the check calls nothing when the buff falls
			local G1, ns1, taken1 = setup("up")
			T.eq(ns1.Advisor.State(), nil); T.eq(ns1.Advisor.notReadyReason, "useBuff")
			G1.secretValues = { [413] = true }
			ns1.Invalidate()
			T.eq(ns1.Advisor.State(), nil); T.eq(ns1.Advisor.notReadyReason, "hidden")
			taken1()
			buffFalls(G1)
			G1.advance(3)
			T.eq(taken1(), 0, "hidden: the check calls nothing, the buff falling included")
			T.eq(#G1.timers, 0, "hidden: no timer of the env pending (the Use-buff check ended, the pet's re-check settled in setup)")
			-- built from the last reading because of the buff, up or with its aura secret: the same state while that holds,
			-- one re-read when it falls
			for _, buff in ipairs({ "up", "secret" }) do
				local G2, ns2, taken2 = setup(nil)
				T.eq(ns2.Advisor.State().snap.statsStale, nil)
				if buff == "up" then G2.auras.player[468164] = true else G2.secretAuras[468164] = true end
				G2.GetRangedHitModifier = function() return 10 end
				ns2.Invalidate()
				local st = ns2.Advisor.State()
				T.eq(st.snap.statsStaleBy, "useBuff", buff)
				taken2()
				for s = 1, 4 do
					G2.advance(1)
					T.eq(taken2(), 0, "the last reading, the buff " .. buff .. ": no re-read at second " .. s)
					T.eq(ns2.Advisor.State(), st, "the state as built")
				end
				buffFalls(G2)
				G2.advance(1)
				T.eq(taken2(), 1, "the last reading, the buff " .. buff .. " falls: one re-read")
				T.eq(ns2.Advisor.State().snap.statsStale, nil, "the live reading")
				G2.advance(3)
				T.eq(taken2(), 0, "the live reading: the check ends")
				T.eq(#G2.reportedErrors, 0)
			end
			-- an aura state that turns unknown and then known up keeps waiting; known off, one re-read
			local G3, ns3, taken3 = setup(nil)
			G3.auras.player[468164] = true
			G3.GetRangedHitModifier = function() return 10 end
			ns3.Invalidate()
			T.eq(ns3.Advisor.State().snap.statsStaleBy, "useBuff")
			taken3()
			G3.secretAuras[468164] = true
			G3.advance(2)
			T.eq(taken3(), 0, "up, then unknown: waits")
			G3.secretAuras[468164] = nil
			G3.advance(2)
			T.eq(taken3(), 0, "known up again: waits")
			buffFalls(G3)
			G3.advance(1)
			T.eq(taken3(), 1, "known off: one re-read")
			-- built from the last reading because of the buff, then the stats turn secret: the last reading for hidden
			-- stats, so the check calls nothing when the buff falls
			local G4, ns4, taken4 = setup(nil)
			G4.auras.player[468164] = true
			G4.GetRangedHitModifier = function() return 10 end
			ns4.Invalidate()
			T.eq(ns4.Advisor.State().snap.statsStaleBy, "useBuff")
			G4.secretValues = { [413] = true }
			ns4.Invalidate()
			T.eq(ns4.Advisor.State().snap.statsStaleBy, "hidden")
			taken4()
			buffFalls(G4)
			G4.advance(3)
			T.eq(taken4(), 0, "the last reading for hidden stats: the check calls nothing, the buff falling included")
			-- readable again with the buff up, then the buff falls and an event re-evaluates: the live reading, so the
			-- pending check calls nothing
			G4.secretValues = nil
			G4.auras.player[468164] = true
			ns4.Invalidate()
			T.eq(ns4.Advisor.State().snap.statsStaleBy, "useBuff")
			buffFalls(G4)
			G4.fire("BAG_UPDATE_DELAYED")
			T.eq(ns4.Advisor.State().snap.statsStale, nil)
			taken4()
			G4.advance(3)
			T.eq(taken4(), 0, "the live reading: the check calls nothing")
			T.eq(#G4.timers, 0, "the live reading: no timer of the env pending (the Use-buff check ended, the pet's re-check settled in setup)")
			-- the cases above run out of combat, where the swap banner's Swap.Refresh builds A.State inside ns.Invalidate; below
			-- nothing builds it after ns.Invalidate (in combat Swap.Refresh builds no plan; this env opens no bag frame and no
			-- quest frame), so the check itself ends the waiting: refused or built from the last reading,
			-- the buff held 4 s keeps one check pending; when it falls, one ns.Invalidate and no check pending after it,
			-- and the next A.State takes the live reading
			for _, mode in ipairs({ "refused", "last reading" }) do
				local G5, ns5, taken5 = setup(mode == "refused" and "up" or nil)
				G5.inCombat = true
				local builds = 0
				local snapshot = ns5.Player.Snapshot
				ns5.Player.Snapshot = function(...) builds = builds + 1; return snapshot(...) end
				if mode == "last reading" then
					G5.auras.player[468164] = true
					G5.GetRangedHitModifier = function() return 10 end
				end
				ns5.Invalidate()
				T.eq(builds, 0, mode .. ": nothing builds A.State after ns.Invalidate")
				local st = ns5.Advisor.State()
				if mode == "refused" then
					T.eq(st, nil); T.eq(ns5.Advisor.notReadyReason, "useBuff")
				else
					T.eq(st.snap.statsStaleBy, "useBuff")
				end
				taken5()
				G5.advance(4)
				T.eq(taken5(), 0, mode .. ", the buff held: no re-read"); T.eq(#G5.timers, 1, mode .. ", the buff held: one timer of the env pending, the Use-buff check (the pet's re-check settled in setup)")
				buffFalls(G5)
				G5.advance(10)
				T.eq(taken5(), 1, mode .. ", the buff falls with nothing building A.State: one re-read in 10 s")
				T.eq(#G5.timers, 0, mode .. ", the buff falls with nothing building A.State: no timer of the env pending (the Use-buff check ended, the pet's re-check settled in setup)")
				st = ns5.Advisor.State()
				T.truthy(st and st.snap.statsStale == nil, mode .. ": the next A.State takes the live reading")
				T.near(st.ctx.baseHit, 1, 1e-9)
				T.eq(#G5.reportedErrors, 0)
			end
			-- with nothing building A.State after ns.Invalidate, events while the buff holds (a bag update, then an A.State
			-- as a hover asks for it) start no second check: one check pending through them, one ns.Invalidate in the second
			-- the buff falls
			for _, mode in ipairs({ "refused", "last reading" }) do
				local G6, ns6, taken6 = setup(mode == "refused" and "up" or nil)
				G6.inCombat = true
				if mode == "last reading" then
					G6.auras.player[468164] = true
					G6.GetRangedHitModifier = function() return 10 end
					ns6.Invalidate()
				end
				ns6.Advisor.State()
				G6.advance(1.5)
				for i = 1, 3 do
					G6.fire("BAG_UPDATE_DELAYED")
					local st = ns6.Advisor.State()
					if mode == "refused" then
						T.eq(st, nil); T.eq(ns6.Advisor.notReadyReason, "useBuff")
					else
						T.eq(st.snap.statsStaleBy, "useBuff")
					end
					T.eq(#G6.timers, 1, mode .. ": one timer of the env pending after event " .. i .. ", the Use-buff check (the pet's re-check settled in setup)")
					G6.advance(1.3)
				end
				taken6()
				buffFalls(G6)
				G6.advance(1)
				T.eq(taken6(), 1, mode .. ", events while the buff held: one re-read in the second it falls")
				T.eq(#G6.timers, 0, mode .. ": no timer of the env pending after the re-read (the Use-buff check ended, the pet's re-check settled in setup)")
				G6.advance(5)
				T.eq(taken6(), 0, mode .. ": nothing after the re-read")
				local st = ns6.Advisor.State()
				T.truthy(st and st.snap.statsStale == nil, mode .. ": the next A.State takes the live reading")
				T.eq(#G6.reportedErrors, 0)
			end
		end },
		-- Every Use buff of Game/UseData.lua keeps the live reading out, the worn items' and the others': Nat Pagle's Broken
		-- Reel 231271 in the bags with its buff (spell 468164) up, the bag Reel a candidate whose buff Score.SetValue prices
		-- over its uptime; Earthstrike 21180's buff (spell 25891, +280 attack power) up with no Earthstrike worn or in the
		-- bags.
		{ "use buff: a Use buff of an item not worn keeps the live reading out", function()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			local function reelInBags(G)
				G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
					ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
				G.bags[0] = { "reel" }
			end
			local G = env()
			reelInBags(G)
			local ns = loadAll(G)
			local st0 = ns.Advisor.State()
			T.eq(st0.snap.statsStale, nil); T.near(st0.ctx.baseHit, 1, 1e-9)
			local reel0 = ns.Advisor.Evaluate("reel", { kind = "bag", bag = 0, slot = 1 }).delta
			-- the Reel's buff up with the trinket in the bags: the sheet's hit holds its 10%
			G.auras.player[468164] = true
			G.GetRangedHitModifier = function() return 10 end
			G.fire("BAG_UPDATE_DELAYED")
			local st = ns.Advisor.State()
			T.eq(st.snap.statsStaleBy, "useBuff", "the last reading of this gear")
			T.near(st.ctx.baseHit, 1, 1e-9, "the base hit without the buff")
			T.near(ns.Advisor.Evaluate("reel", { kind = "bag", bag = 0, slot = 1 }).delta, reel0, 1e-9,
				"the bag Reel priced from the reading without its buff")
			-- no reading before: no evaluation, the reason said
			local G2 = env()
			reelInBags(G2)
			G2.auras.player[468164] = true
			G2.GetRangedHitModifier = function() return 10 end
			local ns2 = loadAll(G2)
			T.eq(ns2.Advisor.State(), nil); T.eq(ns2.Advisor.notReadyReason, "useBuff")
			-- an Earthstrike buff with no Earthstrike anywhere
			local G3 = env()
			G3.auras.player[25891] = true
			local ns3 = loadAll(G3)
			T.eq(ns3.Advisor.State(), nil); T.eq(ns3.Advisor.notReadyReason, "useBuff")
		end },
		{ "gear: the quiver's bag slot is part of the gear a reading is taken with", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			local Q13 = "|cff1eff00|Hitem:60020::::::::43:::::|h[Колчан 13]|h|r"
			local Q15 = "|cff1eff00|Hitem:60021::::::::43:::::|h[Колчан 15]|h|r"
			G.items[Q13] = { info = { 60020, "INVTYPE_BAG", 11, 2 }, lines = { ln("Колчан 13"), ln("Колчан"),
				ln("Если на персонаже: Увеличение скорости дальней атаки на 13%.") }, api = {} }
			G.items[Q15] = { info = { 60021, "INVTYPE_BAG", 11, 2 }, lines = { ln("Колчан 15"), ln("Колчан"),
				ln("Если на персонаже: Увеличение скорости дальней атаки на 15%.") }, api = {} }
			local quiver = Q13
			local invLink = G.GetInventoryItemLink
			G.GetInventoryItemLink = function(u, slot) if slot == 20 then return quiver end return invLink(u, slot) end
			local ns = loadAll(G)
			T.truthy(ns.Advisor.State(), "read with the 13% quiver")
			-- the stats secret: another quiver's reading holds another ranged haste
			G.secretValues = { [413] = true }
			quiver = Q15
			G.fire("BAG_UPDATE_DELAYED")
			T.eq(ns.Advisor.State(), nil, "another quiver: other gear"); T.eq(ns.Advisor.notReadyReason, "hidden")
			quiver = Q13
			G.fire("BAG_UPDATE_DELAYED")
			T.eq(ns.Advisor.State().snap.statsStale, true, "the reading's own quiver")
		end },
		{ "gear: a worn link without an item string, compared with another link, is an error", function()
			local G = env(); local ns = loadAll(G)
			T.truthy(ns.Advisor.State())
			G.secretValues = { [413] = true }
			G.equippedLinks[1] = "newhelm"
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			local ok, err = pcall(ns.Advisor.State)
			T.eq(ok, false); T.truthy(tostring(err):find("worn item link without an item string", 1, true), tostring(err))
		end },
		-- Grovekeeper Rage 2113 (Forever ItemSet: 280986 head, 280987 shoulders, 280988 chest, 280989 legs,
		-- 280990 feet, 280991 hands; Item.csv class 4 subclass 2, leather): the 4-piece bonus 1301076 is
		-- EXPERTISE 1.2 (Game/SetData.lua; SpellEffect aura 189 A_MOD_RATING bp 12 on the expertise rating)
		{ "set: the worn set bonuses' expertise is in the model's expertise with the items' own", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function piece(link, id, loc, extra)
				local lines = { ln("Ярость хранителя рощи"), ln("Кожа"), ln("+5 к ловкости") }
				if extra then lines[#lines + 1] = ln(extra) end
				G.items[link] = { info = { id, loc, 4, 2 }, setID = 2113, lines = lines, api = {} }
			end
			piece("gkhead", 280986, "INVTYPE_HEAD", "Если на персонаже: снижает вероятность, что противник уклонится или парирует ваш удар, на 1,0%.")
			piece("gkchest", 280988, "INVTYPE_CHEST"); piece("gkfeet", 280990, "INVTYPE_FEET"); piece("gkhands", 280991, "INVTYPE_HAND")
			G.equippedLinks[1], G.equippedLinks[5], G.equippedLinks[8] = "gkhead", "gkchest", "gkfeet"
			local ns = loadAll(G)
			T.near(ns.Items.Get("gkhead").stats.EXPERTISE, 1, 1e-9, "the head's own expertise")
			T.near(ns.Advisor.State().snap.model.expertise, 1, 1e-9, "3 pieces: the items' expertise only")
			G.equippedLinks[10] = "gkhands"
			G.fire("PLAYER_EQUIPMENT_CHANGED")
			T.near(ns.Advisor.State().snap.model.expertise, 1 + 1.2, 1e-9, "4 pieces: + the bonus' 1.2")
		end },
		-- Expertise lowers the mob's dodge up to the dodge itself (Model.MobAvoid: 5% at an equal-level mob, 6.5% at +3),
		-- where the hawks, the pet and the melee swings clamp it (Model.Parts). Score.SetValue prices the set's expertise up
		-- to that cap (ctx.expertiseCap) at the slope below it (Model.Weights), so each gain or loss is the model's own
		-- change; /hga weights prints the worn set's expertise and the cap
		{ "expertise: an item crossing the mob's dodge gets the part below it; a worn one past it is priced when it comes off", function()
			local EXP = "Если на персонаже: снижает вероятность, что противник уклонится или парирует ваш удар, на %s%%."
			local function setup(worn)
				local G = env()
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(t, r) return { leftText = t, rightText = r, leftColor = Wc, rightColor = Wc } end
				-- the expertise helm has the worn helm's 18 Agility, the plain belt nothing
				G.items.exphelm = { info = { 11, "INVTYPE_HEAD", 4, 3 }, lines = { ln("Шлем мастерства"), ln("Голова", "Кольчуга"),
					ln("+18 к ловкости"), ln(EXP:format("4,0")) }, api = {} }
				G.items.expbelt = { info = { 12, "INVTYPE_WAIST", 4, 3 }, lines = { ln("Пояс мастерства"), ln("Пояс", "Кольчуга"),
					ln(EXP:format("3,0")) }, api = {} }
				G.items.plainbelt = { info = { 13, "INVTYPE_WAIST", 4, 3 }, lines = { ln("Пояс"), ln("Пояс", "Кольчуга") }, api = {} }
				G.items.plainhelm = { info = { 14, "INVTYPE_HEAD", 4, 3 }, lines = { ln("Шлем ловкости"), ln("Голова", "Кольчуга"),
					ln("+18 к ловкости") }, api = {} }
				for slot, link in pairs(worn) do G.equippedLinks[slot] = link end
				G.bags[0] = { "exphelm", "expbelt", "plainbelt", "plainhelm" }
				local ns = loadAll(G)
				settlePet(G)
				return G, ns
			end
			local function evaluate(ns, slot) return ns.Advisor.Evaluate(({ "exphelm", "expbelt", "plainbelt", "plainhelm" })[slot], { kind = "bag", bag = 0, slot = slot }) end
			local G, ns = setup({ [1] = "plainhelm", [6] = "expbelt" })
			-- the model's change with the expertise at e, in the weights' unit
			local function modelGain(st, e)
				local p = {}
				for k, v in pairs(st.model) do p[k] = v end
				p.expertise = e
				return (ns.Model.Total(p) - st.total) / st.unitDps
			end
			local st = ns.Advisor.State()
			T.near(st.snap.model.expertise, 3, 1e-12); T.eq(st.ctx.expertiseCap, 5)
			-- 3% worn: the expertise helm for the plain one, 3 -> 7 at a 5% cap: 2% of it, the model's change
			local r = evaluate(ns, 1)
			T.near(r.delta, modelGain(st, 7), 1e-9, "3 -> 7: the model's change")
			T.near(r.delta, 2 * st.W.EXPERTISE, 1e-9, "3 -> 7: 2% at W.EXPERTISE")
			-- 7% worn (past the cap): the plain belt for the expertise belt, 7 -> 4, and the plain helm for the expertise
			-- helm, 7 -> 3: each the model's change
			G, ns = setup({ [1] = "exphelm", [6] = "expbelt" })
			st = ns.Advisor.State()
			T.near(st.snap.model.expertise, 7, 1e-12)
			T.truthy(st.W.EXPERTISE > 1, "the slope below the cap: " .. st.W.EXPERTISE)
			T.near(evaluate(ns, 3).delta, modelGain(st, 4), 1e-9, "7 -> 4: the model's change")
			T.near(evaluate(ns, 3).delta, -1 * st.W.EXPERTISE, 1e-9, "7 -> 4: 1% below the cap")
			T.near(evaluate(ns, 4).delta, modelGain(st, 3), 1e-9, "7 -> 3: the model's change")
			T.near(evaluate(ns, 1).delta, 0, 1e-12, "a bag copy of the worn helm: 0"); T.near(evaluate(ns, 2).delta, 0, 1e-12, "the belt's copy")
			for slot, piece in pairs(st.snap.equipped) do
				T.eq(ns.Advisor.Evaluate(piece.link, { kind = "equipped", slot = slot }).delta, 0, "worn " .. piece.link)
			end
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local all = table.concat(G.printed, "\n")
			T.truthy(all:find("), мастерство 7.00% (кап 5.0%; с вещей и комплектов), лук 21.2 DPS", 1, true), all)
			-- at level 60 the raid boss, 3 levels up (Player.Snapshot): the dodge 6.5% (Model.MobAvoid(3)); the pet is behind the
			-- boss (Model.PetTanks "raid" 0, raid-mode design 5.2: no parry; the levelling mode's tanking pet does not apply), so
			-- the parry cap is the dodge and 7 -> 4 loses 2.5% below the dodge at W.EXPERTISE alone
			G.UnitLevel = function() return 60 end
			G.fire("PLAYER_LEVEL_UP", 60)
			st = ns.Advisor.State()
			T.eq(st.model.mode, "raid"); T.eq(st.model.mobDiff, 3)
			T.eq(st.ctx.expertiseCap, 6.5); T.eq(st.ctx.parryCap, 6.5, "the pet behind: the dodge")
			T.near(st.W.EXPERTISE_PARRY, 0, 1e-12, "no parry past the dodge")
			T.near(evaluate(ns, 3).delta, modelGain(st, 4), 1e-9, "+3: 7 -> 4, the model's change")
			T.near(evaluate(ns, 3).delta, -2.5 * st.W.EXPERTISE, 1e-9, "+3: 7 -> 4, 2.5% below the 6.5% dodge")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			T.truthy(table.concat(G.printed, "\n"):find("мастерство 7.00% (кап 6.5%; с вещей и комплектов)", 1, true), table.concat(G.printed, "\n"))
			T.eq(#G.reportedErrors, 0)
		end },
		-- /hga weights: the hit is the one Score.SetValue meets the cap with for the worn set: base + items + set
		-- bonuses + the worn ranged skill's hit against the level's skill (Model.SkillHit at the model point's rangedSkill, the
		-- skill shown less 5 x level). Mutant: the cap at the trained skill's hit (ctx.skillBase)
		{ "/hga weights prints the hit Score meets the cap with, the sheet hit and the ranged skill against the level's", function()
			local function weightsLine(setup)
				local G = env()
				-- the sheet's ranged crit 9.10%, its melee crit 8.66% (env): the line prints the ranged one
				G.GetRangedCritChance = function() return 9.10 end
				setup(G)
				loadAll(G)
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR("weights")
				for _, l in ipairs(G.printed) do
					if l:find("ур. 43, RAP", 1, true) then return l end
				end
				error("no stats line: " .. table.concat(G.printed, " | "))
			end
			local function bowSkill(G, modifier)
				local skill = G.C_SkillInfo.GetSkillLineInfoByID
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 45 then return { rank = 215, maxRank = 215, modifier = modifier } end
					return skill(id)
				end
			end
			-- the worn bow at 218 against 215 (5 x 43): the gap -3, +0.3% toward the cap (Model.SkillHit(0, 3)); the modifier
			-- is no gear's, so the trained skill is 218 too
			local l = weightsLine(function(G) bowSkill(G, 3) end)
			T.truthy(l:find("меткость 1.30% (кап 5.0%; в листе 1.00%, навык Луки 218/218 против 215 по уровню: меткость выстрелов +0.3%, крит выстрелов +0.0%)", 1, true), l)
			-- the worn bow's own +5 Bows, which the bows line's modifier holds (the client counts worn gear there): shown 220,
			-- trained 215; the shots meet the cap with the shown skill's +0.5% (Model.SkillHit(0, 5)), no crit above the maximum
			l = weightsLine(function(G)
				bowSkill(G, 5)
				table.insert(G.items.bow.lines, { leftText = "Если на персонаже: повышение навыка владения луком на 5.", leftColor = { r = 1, g = 1, b = 1 } })
			end)
			T.truthy(l:find("меткость 1.50% (кап 5.0%; в листе 1.00%, навык Луки 220/215 против 215 по уровню: меткость выстрелов +0.5%, крит выстрелов +0.0%)", 1, true), l)
			-- the bow at 210: the gap 5, -0.5% toward the cap, 1% crit suppression
			l = weightsLine(function(G) bowSkill(G, -5) end)
			T.truthy(l:find("меткость 0.50% (кап 5.0%; в листе 1.00%, навык Луки 210/210 против 215 по уровню: меткость выстрелов -0.5%, крит выстрелов -1.0%)", 1, true), l)
			-- the sheet's 0.5% under the worn helm's 1% hit: the base is -0.5% as it is, so Score meets the cap with the
			-- sheet's 0.5% and the skill's 0.3%
			l = weightsLine(function(G)
				bowSkill(G, 3)
				G.equippedLinks[1] = "newhelm"
				G.GetCombatRatingBonus = function() return 0.5 end
			end)
			T.truthy(l:find("меткость 0.80% (кап 5.0%; в листе 0.50%,", 1, true), l)
			-- Devilsaur Armor worn (ItemSet 143: Devilsaur Leggings 15062, Devilsaur Gauntlets 15063; Game/SetData.lua: 2
			-- pieces, spell 460230, HIT 2): the sheet's 3% holds the set's 2% (the pieces have no hit of their own), so the
			-- hit Score meets the cap with is the sheet's 3% and the skill's 0.3%
			l = weightsLine(function(G)
				bowSkill(G, 3)
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(t, r) return { leftText = t, rightText = r, leftColor = Wc, rightColor = Wc } end
				G.items.devlegs = { info = { 15062, "INVTYPE_LEGS", 4, 2 }, setID = 143, lines = { ln("Штаны девизавра"), ln("Ноги", "Кожа") }, api = {} }
				G.items.devgloves = { info = { 15063, "INVTYPE_HAND", 4, 2 }, setID = 143, lines = { ln("Рукавицы девизавра"), ln("Кисти рук", "Кожа") }, api = {} }
				G.equippedLinks[7], G.equippedLinks[10] = "devlegs", "devgloves"
				G.GetCombatRatingBonus = function() return 3 end
			end)
			T.truthy(l:find("меткость 3.30% (кап 5.0%; в листе 3.00%, навык Луки 218/218 против 215 по уровню: меткость выстрелов +0.3%, крит выстрелов +0.0%)", 1, true), l)
			-- no ranged weapon: the level's skill, no skill hit
			l = weightsLine(function(G) G.equippedLinks[18] = nil end)
			T.truthy(l:find("меткость 1.00% (кап 5.0%; в листе 1.00%, нет лука, ружья или арбалета — навык как у уровня)", 1, true), l)
		end },
		-- A.State: the model runs at the worn ranged skill (Score.SetValue takes the live hit and crit to leave the skill
		-- out): p.rangedSkill = the worn bonus over 5 x level, p.rangedHit = Model.SkillHit of it, p.crit the sheet's; the
		-- weights, weaponGain and the quiver's modelGain all run at that point
		{ "the model point holds the worn skill; the worn set and its copies give exactly 0 with skill, scope and a Use hit buff", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
			-- the bows line at 195 trained + the worn ring's 5 (the client counts worn gear in the modifier): 200 of 215
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 45 then return { rank = 195, maxRank = 215, modifier = 5 } end
				return base(id)
			end
			G.items.bowring = { info = { 70, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо лучника"), ln("Палец"),
				ln("Если на персонаже: повышение навыка владения луком на 5.") }, api = {} }
			G.items.reel = { info = { 231271, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Сломанная катушка Ната Пэгла"), ln("Аксессуар"),
				ln("Использование: Повышает вероятность попадания на 10% на 15 сек.") }, api = {} }
			G.items.bow.lines[#G.items.bow.lines + 1] = ln("Чары: +2% к вероятности критического удара")
			G.equippedLinks[11], G.equippedLinks[13] = "bowring", "reel"
			G.bags[0] = { "bow" } -- a copy of the worn bow
			-- the sheet's ranged crit 9.10%, its melee crit 8.66% (env)
			G.GetRangedCritChance = function() return 9.10 end
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			-- 200 of 215: the bonus -15, the gap 15, 8% miss: the shots' -3% (my arithmetic)
			T.eq(st.ctx.skillBase, 195 - 215, "the trained bows less 5 x level")
			T.eq(st.model.rangedSkill, -15)
			T.near(st.model.rangedHit, -3, 1e-12, "the shots' own hit")
			T.eq(st.model.crit, 9.10, "the ranged crit: the sheet's")
			T.eq(st.model.meleeCrit, 8.66, "melee crit without it"); T.eq(st.model.hit, st.snap.model.hit, "the hit of every attack: the sheet's")
			T.eq(st.snap.model.crit, 9.10, "the reading stays as read"); T.eq(st.snap.model.meleeCrit, 8.66)
			local W, unitDps, total = ns.Model.Weights(st.model)
			T.eq(st.total, total); T.eq(st.unitDps, unitDps)
			for _, k in ipairs({ "HIT", "HIT_RANGED", "CRIT", "CRIT_RANGED", "SKILL_CRIT", "AGI", "HIT_DW" }) do T.eq(st.W[k], W[k], k) end
			-- the worn set, a fresh copy of every worn piece, and the bag copy of the worn bow: exactly 0
			T.eq(st.ctx.weaponGain(st.snap.equipped), 0, "the worn weapons")
			local copy = {}
			for slot, it in pairs(st.snap.equipped) do copy[slot] = setmetatable({}, { __index = it }) end
			T.near(ns.Score.SetValue(copy, st.W, st.ctx), ns.Score.SetValue(st.snap.equipped, st.W, st.ctx), 1e-12,
				"a copy of the worn set: its weapons through the model at the same point, its skill, scope and Reel")
			local r = ns.Advisor.Evaluate("bow", { kind = "bag", bag = 0, slot = 1 })
			T.near(r.delta, 0, 1e-12, "the bag copy of the worn bow")
			T.eq(#ns.Advisor.Plan().rows, 0, "nothing to put on")
			-- a quiver's gain runs from the same point
			G.bags[0] = { "quiver15" }
			ns.Advisor.Reset()
			local st2 = ns.Advisor.State()
			local q = ns.Advisor.Evaluate("quiver15", { kind = "bag", bag = 0, slot = 1 })
			local p = {}
			for k, v in pairs(st2.model) do p[k] = v end
			p.quiver = 0.15
			T.near(q.delta, (ns.Model.Total(p) - st2.total) / st2.unitDps, 1e-12, "the quiver from the model point")
		end },
		-- the base hit is the live hit less the worn items' and set bonuses' hit, as it is: a live hit of 2% under the
		-- worn items' 3% and Devilsaur Armor's 2% (set 143, 2 pieces) is a -3% base every set carries
		{ "a live hit under the worn gear's hit: the base goes negative and +2% hit is priced under the cap", function()
			local G = env()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			G.items.devlegs = { info = { 15062, "INVTYPE_LEGS", 4, 2 }, setID = 143, lines = { ln("Штаны девизавра"), ln("Ноги", "Кожа") }, api = {} }
			G.items.devgloves = { info = { 15063, "INVTYPE_HAND", 4, 2 }, setID = 143, lines = { ln("Рукавицы девизавра"), ln("Кисти рук", "Кожа") }, api = {} }
			G.items.hitring3 = { info = { 71, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо меткости"), ln("Палец"),
				ln("Если на персонаже: повышает вероятность попадания на 3,0%.") }, api = {} }
			G.items.hitring2 = { info = { 72, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо точности"), ln("Палец"),
				ln("Если на персонаже: повышает вероятность попадания на 2,0%.") }, api = {} }
			G.equippedLinks[7], G.equippedLinks[10], G.equippedLinks[11] = "devlegs", "devgloves", "hitring3"
			G.GetCombatRatingBonus = function() return 2 end -- a hit debuff: the sheet reads 2%
			G.bags[0] = { "hitring2" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.near(st.snap.liveHit, 2, 1e-12); T.near(st.snap.gearHit, 3, 1e-12); T.near(st.snap.setHit, 2, 1e-12)
			T.near(st.ctx.baseHit, -3, 1e-12, "the base as it is")
			T.near(st.ctx.baseHit + st.snap.gearHit + st.snap.setHit, st.ctx.wornHit, 1e-12, "the worn set's hit in Score: the live hit")
			T.eq(st.ctx.skillBase, 0); T.eq(st.model.rangedHit, 0)
			-- the env's BM build is no Survival branch: no melee (Player.Snapshot), so hit past the cap lowers no dual-wield miss
			T.eq(st.model.survival, false); T.eq(st.W.HIT_DW, 0, "no melee: no dual-wield value")
			local r = ns.Advisor.Evaluate("hitring2", { kind = "bag", bag = 0, slot = 1 })
			T.eq(r.slot, 12)
			T.near(r.delta, 2 * st.W.HIT, 1e-9, "2% to 4% of the 5% cap: the under-cap value")
		end },
		-- ctx.wornHit is the hit of every attack the model runs the weapons at (the sheet's, snap.model.hit), never with
		-- the worn ranged skill's hit, which is the shots' own (p.rangedHit)
		{ "dual wield past the cap at a worn bow skill off the level's: ctx.wornHit is the sheet hit; a two-hander has no dual-wield part", function()
			local G = env()
			survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
			G.GetCombatRatingBonus = function() return 7 end -- the sheet: 7% hit, 2% past the 5% cap
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 45 then return { rank = 200, maxRank = 215, modifier = 0 } end
				return base(id)
			end
			G.bags[0] = { "staff" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.rangedSkill, -15, "the bow at 200 of the level's 215"); T.near(st.model.rangedHit, -3, 1e-12)
			T.eq(st.snap.dualWield, true); T.truthy(st.W.HIT_DW > 0, "melee 5%: dual-wield hit has a value")
			T.near(st.snap.model.hit, 7, 1e-12)
			T.eq(st.ctx.wornHit, st.snap.model.hit, "the hit of every attack, without the skill's")
			local r = ns.Advisor.Evaluate("staff", { kind = "bag", bag = 0, slot = 1 })
			local set = r.newSet
			T.eq(set[16].name, "Посох"); T.eq(set[17], nil)
			-- the worn pair's dual-wield part sits at ctx.wornHit (0), the staff has none, and no piece has hit: the delta is
			-- the weapons through the model and the items' own stats
			local items = 0
			for slot, it in pairs(set) do items = items + ns.Score.ItemValue(it, ns.Score.SlotKind(slot, it), st.W, true) end
			for slot, it in pairs(st.snap.equipped) do items = items - ns.Score.ItemValue(it, ns.Score.SlotKind(slot, it), st.W, true) end
			T.near(r.delta, st.ctx.weaponGain(set) + items, 1e-9, "no dual-wield part on either side")
		end },
		-- a set without a bow, gun or crossbow has its ranged hand at bonus 0 (Score.SetValue; wowsims
		-- sim/core/weapon_skill.go:17-19): against the worn bow's skill only the crit of the pet, the dive and the hawks
		-- moves, by the worn deficit at W.SKILL_CRIT_NO_SHOTS; weaponGain already takes every shot away
		{ "Egan's Blaster against a worn bow off the level's skill: bonus 0, the crit of what still attacks only", function()
			local function run(rank)
				local G = env()
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(l) return { leftText = l, leftColor = Wc, rightColor = Wc } end
				local base = G.C_SkillInfo.GetSkillLineInfoByID
				-- the bows line: the trained rank and the worn ring's 5 (the client counts worn gear in the modifier)
				G.C_SkillInfo.GetSkillLineInfoByID = function(id)
					if id == 45 then return { rank = rank, maxRank = 215, modifier = 5 } end
					return base(id)
				end
				G.items.bowring = { info = { 70, "INVTYPE_FINGER", 4, 0 }, lines = { ln("Кольцо лучника"), ln("Палец"),
					ln("Если на персонаже: повышение навыка владения луком на 5.") }, api = {} }
				-- Egan's Blaster 13289: Forever Item.csv build 70888 class 12, InventoryType 26
				G.items.blaster = { info = { 13289, "INVTYPE_RANGEDRIGHT", 12, 0 }, lines = { ln("Бластер Игана"), ln("Дальний бой") }, api = {} }
				G.equippedLinks[11] = "bowring"
				G.bags[0] = { "blaster" }
				local ns = loadAll(G)
				local st = ns.Advisor.State()
				local r = ns.Advisor.Evaluate("blaster", { kind = "bag", bag = 0, slot = 1 })
				local set = r.newSet
				T.eq(set[18].name, "Бластер Игана")
				local items = 0
				for slot, it in pairs(set) do items = items + ns.Score.ItemValue(it, ns.Score.SlotKind(slot, it), st.W, true) end
				for slot, it in pairs(st.snap.equipped) do items = items - ns.Score.ItemValue(it, ns.Score.SlotKind(slot, it), st.W, true) end
				-- the model's own change when the set's ranged hand goes to bonus 0, at the set's weapon inputs
				local p = {}
				for k, v in pairs(st.model) do p[k] = v end
				for k, v in pairs(ns.Player.WeaponInputs(set)) do p[k] = v end
				local t1 = ns.Model.Total(p)
				p.rangedSkill = 0
				return r.delta - st.ctx.weaponGain(set) - items, st, (ns.Model.Total(p) - t1) / st.unitDps
			end
			-- 215 trained + 5: 220 of the level's 215, 5 over it; the set at bonus 0 changes nothing above the maximum
			local rest, st, model = run(215)
			T.eq(st.model.rangedSkill, 5)
			T.near(rest, 0, 1e-9, "no deficit worn: nothing"); T.near(model, 0, 1e-12, "the model's own: nothing")
			T.truthy(st.W.SKILL_CRIT_NO_SHOTS < st.W.SKILL_CRIT - 1e-6, "below the skill crit the shots take too")
			-- 200 trained + 5: 205, 10 under the level's 215; the set at bonus 0 gains 10 points of crit there
			rest, st, model = run(200)
			T.eq(st.model.rangedSkill, -10)
			T.near(rest, 10 * st.W.SKILL_CRIT_NO_SHOTS, 1e-9, "the 10 points at W.SKILL_CRIT_NO_SHOTS")
			T.truthy(math.abs(rest - model) < 0.02 * math.abs(model), string.format("the model's own: %.4f vs %.4f", rest, model))
		end },
		-- a worn thrown weapon casts no shot (Model.Parts noShots), so the worn set has the level's skill, as every set
		-- without a bow, gun or crossbow (Score.SetValue): its own line's skill reaches neither the model point nor the cap
		{ "a worn thrown weapon: no shots, the level's skill (skillBase 0, rangedSkill 0) whatever the thrown line's skill", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = W1, rightColor = W1 } end
			-- Heavy Throwing Dagger 3108: Item.csv class 2, subclass 16 (Thrown), InventoryType 25; ItemSparse ItemDelay 2100
			G.items.throwing = { info = { 3108, "INVTYPE_THROWN", 2, 16 }, lines = { ln("Heavy Throwing Dagger"),
				ln("Метательное", "Метательное оружие"), ln("Урон: 17-32", "Скорость 2,10"), ln("(11,6 ед. урона в секунду)") }, api = {} }
			local base = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 176 then return { rank = 150, maxRank = 215, modifier = 0 } end -- Thrown, 65 points under 215
				return base(id)
			end
			G.equippedLinks[18] = "throwing"
			G.bags[0] = { "newbow" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.snap.model.noShots, true)
			T.eq(st.rangedSkill.line, nil); T.eq(st.rangedSkill.shown, 215); T.eq(st.rangedSkill.skill, 215)
			T.eq(st.ctx.skillBase, 0); T.eq(st.model.rangedSkill, 0)
			T.eq(st.model.crit, st.snap.model.crit, "the model point's crit: the sheet's"); T.eq(st.model.rangedHit, 0)
			local bow = ns.Advisor.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(bow.skillGap, nil, "the bows line at 215 against the level's 215")
			T.truthy(bow.isUpgrade, "the bow's shots")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local line
			for _, l in ipairs(G.printed) do if l:find("ур. 43, RAP", 1, true) then line = l end end
			T.truthy(line and line:find("меткость 1.00% (кап 5.0%; в листе 1.00%, нет лука, ружья или арбалета — навык как у уровня)", 1, true), tostring(line))
		end },
		-- Score's set without shots (Score.RangedSkillStat nil: the level's skill in Score.SetValue) and the model's
		-- (Player.WeaponInputs noShots) are one rule: a bow, gun or crossbow (item class 2, subclass 2 / 3 / 18) shoots
		{ "no shots: Score.RangedSkillStat is nil exactly where Player.WeaponInputs gives noShots", function()
			local G = env()
			local ns = loadAll(G)
			local function same(item, what)
				T.eq(ns.Player.WeaponInputs({ [18] = item }).noShots, ns.Score.RangedSkillStat(item) == nil, what)
			end
			same(nil, "an empty ranged slot")
			local shooting = 0
			for sub = 0, 20 do
				local it = { classID = 2, subclassID = sub, equipLoc = sub == 16 and "INVTYPE_THROWN" or "INVTYPE_RANGED", speed = 2.6,
					stats = { DPS = 20 }, name = "weapon subclass " .. sub }
				same(it, it.name)
				if not ns.Player.WeaponInputs({ [18] = it }).noShots then shooting = shooting + 1 end
			end
			T.eq(shooting, 3, "bows, guns and crossbows")
			same({ classID = 12, subclassID = 0, equipLoc = "INVTYPE_RANGEDRIGHT", stats = {}, name = "Бластер Игана" }, "class 12")
			same({ classID = 15, subclassID = 4, equipLoc = "INVTYPE_RANGEDRIGHT", stats = {}, name = "Replica Ironforge Air Rifle" }, "class 15")
		end },
		-- One worn set with every mechanism the scorer prices, at once: both hands through ctx.weaponGain, Ripsaw 9478
		-- (Item.csv class 2 subclass 0 InventoryType 21, a main-hand one-handed axe; Era ItemSparse ItemDelay 2700) with its
		-- measured 2 procs a minute (MEASURED_PPM, EV-0022) and Beastslaying +6 (SpellItemEnchantment 853) in the model
		-- point (the hunter's weapon strikes and shots); Cadaverous Garb 121, all five pieces (ItemSet.csv: 14637 chest, 14636 waist, 14638 legs, 14641
		-- feet, 14640 hands by Item.csv InventoryType; Game/SetData.lua 3 pieces AP 10, 5 pieces HIT 2); Wildstalker Armor
		-- 2101, two pieces (280898 head, 280897 shoulders; 2 pieces ATTACK_SPEED 1); a 1% haste rating amulet (HASTE_RATING);
		-- Wind Blessed 1259710 (2% attack speed); an attack speed enchant of each scope Parse reads: Minor Haste 931 on the
		-- gloves (HASTE, a factor of its own), Arcanum of Rapidity 2543 on the head and the legs (MELEE_HASTE and RANGED_HASTE, a
		-- factor each), Automatic Crowd Pummeler 7123 on the shoulders (MELEE_HASTE 50); a bow at 218 of the level's 215 through a
		-- +3 Bows ring (p.rangedSkill 3, the shots' 0.3%) with the +2% crit scope (CRIT_RANGED); Nat Pagle's Broken Reel 231271 and
		-- Earthstrike 21180 (Game/UseData.lua); a 6% sheet hit at the 5% cap, dual wield (W.HIT_DW past the cap); the pet's
		-- own swing 1.2 under every melee speed of its owner it inherits (Player.PetSwing). The ids the rules key on are
		-- Forever's; the other items and every stat are made up.
		{ "one worn set with every mechanism: it and its copies give 0, the attack speed inputs are their sources' product, a Use buff's last reading and Rapid Fire keep it", function()
			local G = env()
			survivalTree(G) -- a melee mechanism: the Survival branch's weave (Player.SurvivalBranch)
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function add(link, id, loc, class, sub, lines, setID)
				for i, l in ipairs(lines) do lines[i] = type(l) == "table" and ln(l[1], l[2]) or ln(l) end
				G.items[link] = { info = { id, loc, class, sub }, lines = lines, api = {}, setID = setID }
			end
			local ARCANUM, HIT2 = "Чары: +1% к скорости атаки", "Если на персонаже: повышает вероятность попадания на 2,0%."
			add("scoutbow", 80, "INVTYPE_RANGED", 2, 2, { "Лук разведчика", { "Дальний бой", "Лук" }, { "Урон: 40-70", "Скорость 2,60" },
				"(21,2 ед. урона в секунду)", "+5 к ловкости", "Чары: +2% к вероятности критического удара" })
			add("ripsaw", 9478, "INVTYPE_WEAPONMAINHAND", 2, 0, { "Пила", { "Правая рука", "Топор" }, { "Урон: 40-79", "Скорость 2,70" },
				"(22,0 ед. урона в секунду)", "+4 к ловкости", "Возможный эффект при попадании: наносит 30 - 50 ед. урона.",
				"Чары: +6 к убийству животных" })
			add("ohsword", 81, "INVTYPE_WEAPON", 2, 7, { "Заточка", { "Одноручное", "Меч" }, { "Урон: 25-40", "Скорость 1,80" },
				"(18,0 ед. урона в секунду)", "Если на персонаже: повышает вероятность попадания на 1,0%." })
			-- the rings are unique-equipped, so a bag copy goes into its own slot alone (a copy of the better of two rings
			-- that are not is a gain in the other slot)
			add("bowring", 82, "INVTYPE_FINGER", 4, 0, { "Кольцо лучника", "Уникальный использующийся", "Палец", "+3 к ловкости",
				"Если на персонаже: повышение навыка владения луком на 3." })
			add("agiring", 83, "INVTYPE_FINGER", 4, 0, { "Кольцо ловкости", "Уникальный использующийся", "Палец", "+6 к ловкости" })
			-- Era ItemSparse (an Era row; the build 70888 export has no row 231271): Nat Pagle's Broken Reel Flags_0 0x80000
			-- (unique-equipped); ItemSparse 70888: Earthstrike 21180 MaxCount 1 (unique: one in the bags and on the body
			-- together, so no bag copy of the worn one)
			add("reel", 231271, "INVTYPE_TRINKET", 4, 0, { "Сломанная катушка Ната Пэгла", "Уникальный использующийся", "Аксессуар",
				"Использование: Повышает вероятность попадания на 10% на 15 сек." })
			add("earthstrike", 21180, "INVTYPE_TRINKET", 4, 0, { "Удар земли", "Уникальный", "Аксессуар",
				"Использование: +280 к силе атаки на 20 сек." })
			add("hasteneck", 84, "INVTYPE_NECK", 4, 0, { "Амулет скорости", "Шея", "+8 к выносливости",
				"Если на персонаже: повышает скорость атаки и применения заклинаний на 1,0%." })
			add("hitbracers", 85, "INVTYPE_WRIST", 4, 2, { "Наручи меткости", { "Запястья", "Кожа" }, "Броня: 40", HIT2 })
			add("plainbracers", 86, "INVTYPE_WRIST", 4, 2, { "Наручи", { "Запястья", "Кожа" }, "Броня: 40" })
			add("wshead", 280898, "INVTYPE_HEAD", 4, 3, { "Шлем ловчего", { "Голова", "Кольчуга" }, "Броня: 150", "+8 к ловкости", ARCANUM }, 2101)
			add("wsshoulder", 280897, "INVTYPE_SHOULDER", 4, 3, { "Наплечники ловчего", { "Плечи", "Кольчуга" }, "Броня: 120",
				"+5 к ловкости", "Чары: Автоматический пробойник толпы" }, 2101)
			add("cadchest", 14637, "INVTYPE_CHEST", 4, 2, { "Трупный доспех", { "Грудь", "Кожа" }, "Броня: 90", "+9 к ловкости" }, 121)
			add("cadbelt", 14636, "INVTYPE_WAIST", 4, 2, { "Трупный пояс", { "Пояс", "Кожа" }, "Броня: 50", "+5 к ловкости" }, 121)
			add("cadlegs", 14638, "INVTYPE_LEGS", 4, 2, { "Трупные поножи", { "Ноги", "Кожа" }, "Броня: 80", "+7 к ловкости", ARCANUM }, 121)
			add("cadfeet", 14641, "INVTYPE_FEET", 4, 2, { "Трупные сапоги", { "Ступни", "Кожа" }, "Броня: 60", "+5 к ловкости" }, 121)
			add("cadhands", 14640, "INVTYPE_HAND", 4, 2, { "Трупные перчатки", { "Кисти рук", "Кожа" }, "Броня: 55", "+4 к ловкости",
				"Чары: +1% к скорости" }, 121)
			local worn = { [1] = "wshead", [2] = "hasteneck", [3] = "wsshoulder", [5] = "cadchest", [6] = "cadbelt", [7] = "cadlegs",
				[8] = "cadfeet", [9] = "hitbracers", [10] = "cadhands", [11] = "bowring", [12] = "agiring", [13] = "reel", [14] = "earthstrike",
				[16] = "ripsaw", [17] = "ohsword", [18] = "scoutbow" }
			for k in pairs(G.equippedLinks) do G.equippedLinks[k] = nil end
			for slot, link in pairs(worn) do G.equippedLinks[slot] = link end
			-- the bags: a copy of every worn piece of armor and jewelry but Earthstrike, and the worn bracers without their hit
			G.bags[0] = {}
			for slot = 1, 13 do if worn[slot] then table.insert(G.bags[0], worn[slot]) end end
			table.insert(G.bags[0], "plainbracers")
			-- the bows line at 215 trained + the worn ring's 3 (the client counts worn gear in the modifier)
			local skill = G.C_SkillInfo.GetSkillLineInfoByID
			G.C_SkillInfo.GetSkillLineInfoByID = function(id)
				if id == 45 then return { rank = 215, maxRank = 215, modifier = 3 } end
				return skill(id)
			end
			G.GetCombatRatingBonus = function() return 6 end
			G.IsPlayerSpell = function(id) return id == 1259710 end
			-- the owner's permanent attack speed (every source) and melee-only speed (aura 319) are in his swings and, after a
			-- heartbeat, in the pet's, without the haste rating (Player.PetSwing; wowsims sim/core/pet.go:381-398)
			local HI = 1.01 -- Minor Haste, an enchant's aura 342 (haste)
			local AS = 1.01 * 1.02 -- the set's 1%, Wind Blessed's 2% (attackSpeed)
			local HR = 1.01 -- the amulet's 1% haste rating (hasteRating)
			local H = HI * AS * HR -- the owner's
			local HP = HI * AS -- the part the pet inherits
			local M = 1.01 * 1.01 * 1.5 -- two Arcanums, the Pummeler
			local R = 1.01 * 1.01 -- two Arcanums
			G.ownerSpeed, G.ownerOffSpeed, G.petSpeed = 2.7 / (H * M), 1.8 / (H * M), 1.2 / (HP * M)
			local ns = loadAll(G)
			settlePet(G)
			local A, Sc = ns.Advisor, ns.Score
			local st = A.State()
			T.truthy(st, "state: " .. tostring(A.notReadyReason))
			local eq, W, ctx, m = st.snap.equipped, st.W, st.ctx, st.snap.model
			-- every mechanism is in play
			local bonus = Sc.SetBonuses(eq, ns.SetData, ns.Player.HasSkillRank)
			T.eq(bonus.AP, 10, "Cadaverous Garb 3 pieces"); T.eq(bonus.HIT, 2, "5 pieces"); T.eq(bonus.ATTACK_SPEED, 1, "Wildstalker Armor 2 pieces")
			T.eq(eq[16].stats.BEAST_SLAYING, 6); T.eq(Sc.ProcRateSource(eq[16], eq[16].procs[1]), 2, "Ripsaw's measured rate")
			T.eq(eq[18].stats.CRIT_RANGED, 2, "the crit scope"); T.truthy(eq[13].use and eq[14].use, "two Use buffs")
			T.eq(ctx.skillBase, 0); T.eq(st.model.rangedSkill, 3, "the bow at 218 of 215"); T.near(st.model.rangedHit, 0.3, 1e-12)
			T.eq(st.rangedSkill.shown, 218); T.eq(st.rangedSkill.skill, 215)
			T.near(st.snap.liveHit, 6, 1e-12); T.near(ctx.baseHit, 6 - 3 - 2, 1e-12, "the sheet less the items' 3% and the set's 2%")
			T.eq(ctx.wornHit, 6); T.eq(st.snap.dualWield, true); T.truthy(W.HIT_DW > 0, "hit past the cap has a dual-wield value")
			T.near(m.petSwing, 1.2, 1e-9, "the pet's own swing")
			-- the model's attack speed inputs: the product of their sources, by source (Player wornHaste)
			T.near(m.haste, (HI - 1) * 100, 1e-9, "haste: Minor Haste's 1%")
			T.near(m.attackSpeed, (AS - 1) * 100, 1e-9, "attack speed: the set's 1% x Wind Blessed's 2%")
			T.near(m.hasteRating, (HR - 1) * 100, 1e-9, "haste rating: the amulet's 1%")
			T.near(m.meleeHaste, (M - 1) * 100, 1e-9, "melee-only: two Arcanums x the Pummeler")
			T.near(m.rangedHaste, (R - 1) * 100, 1e-9, "ranged-only: two Arcanums")
			T.eq(st.model.haste, m.haste); T.eq(st.model.meleeHaste, m.meleeHaste); T.eq(st.model.rangedHaste, m.rangedHaste)
			T.eq(st.model.attackSpeed, m.attackSpeed); T.eq(st.model.hasteRating, m.hasteRating)
			T.eq(m.beastSlaying, 6, "Ripsaw's Beastslaying in the model point (Player.WeaponInputs)")
			-- the procs' hits: the model point's (the worn bow's +0.3% hit on the shots in it), not the sheet's; Ripsaw's
			-- 2 a minute at its own 2.7 s on its main hand's landed swings and specials (Score.ProcRate)
			local lh = ctx.landedHits
			T.eq(lh.ranged.swings, ns.Model.LandedHits(st.model).ranged.swings, "the model point's shots")
			T.eq(lh.mh.speed, 2.7); T.eq(lh.oh.speed, 1.8)
			T.eq(lh.oh.swings, 0, "the off hand swings in no visit of the weave: the ranged path sets the cycle")
			local ripsawRate = 2 * 2.7 * (lh.mh.swings + lh.mh.specials)
			T.eq(ctx.landedHitsFor(eq), lh, "the worn set's own hits")
			T.near(Sc.ProcRate(eq[16], "mh", eq[16].procs[1], lh, ctx), ripsawRate, 1e-12, "Ripsaw at the model point")
			-- 40 average damage, unlinked (its made-up text's 40 is not Game/ProcData.lua's 70): physical by its text, the melee table
			T.near(Sc.ProcValue(eq[16], "mh", W, lh, ctx), 40 * procFactor(ns.Model, st.model, 0, "physical", true) * ripsawRate / 60 * W.EXTRA_DPS,
				1e-12, "Ripsaw's proc: 40 average damage")
			-- the worn set: its weapons gain exactly 0, every worn item 0; the off-hand sword comes off (in the weave it swings in
			-- no visit behind the main hand, and dual wield adds 19% miss to the main hand's white swings, Model weaveParts)
			T.eq(ctx.weaponGain(eq), 0, "the worn weapons")
			local cur = Sc.SetValue(eq, W, ctx)
			local bh = Sc.BestHands(nil, eq, {}, W, ctx)
			T.eq(bh.mh, eq[16]); T.eq(bh.oh, nil, "the off hand off"); T.truthy(bh.value > cur, "above the worn set")
			local rows = Sc.PlanRows(eq, Sc.Plan(eq, {}, W, ctx))
			T.eq(#rows, 1, "a plan with no candidates: the off hand off"); T.eq(rows[1].slot, 17); T.eq(rows[1].new, nil)
			for slot, p in pairs(eq) do
				local r = A.Evaluate(p.link, { kind = "equipped", slot = slot })
				T.eq(r.delta, 0, "worn " .. p.name); T.eq(r.verdict, "same", "worn " .. p.name)
			end
			-- a bag copy of a worn piece of armor or jewelry scores 0 on damage and survival; the plan takes none
			local copies = 0
			for i, link in ipairs(G.bags[0]) do
				if st.snap.links[link] then
					local r = A.Evaluate(link, { kind = "bag", bag = 0, slot = i })
					T.truthy(math.abs(r.delta) < 1e-9 and math.abs(r.sec) < 1e-9 and not r.isUpgrade,
						string.format("bag copy of %s: %s %s %s", link, tostring(r.delta), tostring(r.sec), tostring(r.verdict)))
					copies = copies + 1
				end
			end
			T.eq(copies, 12)
			local planRows = A.Plan().rows
			T.eq(#planRows, 1, "the plan over the bags: the off hand off"); T.eq(planRows[1].slot, 17); T.eq(planRows[1].new, nil)
			-- the bracers without the worn ones' 2% hit: the set's hit falls from 6% to 4%. Under the cap that is 1% at W.HIT,
			-- less the room the worn bow's +0.3% leaves the shots under the cap (W.HIT_RANGED); past it 1% of dual-wield hit
			-- (W.HIT_DW from the worn hit, dwFrom). The Reel's 10% (15 s every 90 s) on top of 4% gives the 1% under the cap
			-- and the shots' room back and reaches 1% less past the cap than on top of 6%.
			local u = 15 / 90
			local plain = A.Evaluate("plainbracers", { kind = "bag", bag = 0, slot = #G.bags[0] })
			T.near(plain.delta, -(1 - u) * (W.HIT - st.model.rangedHit * W.HIT_RANGED) - (1 + u) * W.HIT_DW, 1e-9, "the bracers' 2% hit")
			-- the Reel's buff up with the sheet's hit +10%: the last reading of this gear and talents, the same weights and value
			G.auras.player[468164] = true
			G.GetCombatRatingBonus = function() return 16 end
			ns.Invalidate()
			local st2 = A.State()
			T.eq(st2.snap.statsStale, true); T.eq(st2.snap.statsStaleBy, "useBuff")
			for k, v in pairs(W) do T.eq(st2.W[k], v, "W." .. k) end
			T.eq(Sc.SetValue(st2.snap.equipped, st2.W, st2.ctx), cur, "the worn set's value")
			G.auras.player[468164] = nil
			G.GetCombatRatingBonus = function() return 6 end
			-- Rapid Fire 3045 (aura 319 +40): the owner's swings at once, the pet's at its heartbeat; the pet's own swing
			-- stays 1.2 through its start and its end
			local function petSwing()
				ns.Invalidate()
				return A.State().snap.model.petSwing
			end
			G.auras.player[3045] = true
			G.ownerSpeed, G.ownerOffSpeed = 2.7 / (H * M * 1.4), 1.8 / (H * M * 1.4)
			G.fire("UNIT_ATTACK_SPEED", "player")
			T.near(petSwing(), 1.2, 1e-9, "Rapid Fire starts: kept")
			G.advance(2)
			G.petSpeed = 1.2 / (HP * M * 1.4)
			G.fire("UNIT_ATTACK_SPEED", "pet")
			G.advance(3.3)
			T.near(petSwing(), 1.2, 1e-9, "a heartbeat into Rapid Fire: read with it divided out")
			G.auras.player[3045] = nil
			G.ownerSpeed, G.ownerOffSpeed = 2.7 / (H * M), 1.8 / (H * M)
			G.fire("UNIT_ATTACK_SPEED", "player")
			T.near(petSwing(), 1.2, 1e-9, "Rapid Fire ends: kept, not 1.2 / 1.4")
			G.advance(3)
			G.petSpeed = 1.2 / (HP * M)
			G.fire("UNIT_ATTACK_SPEED", "pet")
			G.advance(2.3)
			T.near(petSwing(), 1.2, 1e-9, "read again after the wait")
			T.eq(#G.reportedErrors, 0)
		end },
		-- Model.Weights' unit where neither RAP nor melee attack power adds damage: a level-8 hunter has no talent point
		-- (the empty tree), so no Survival branch and no melee (Player.Snapshot, Player.SurvivalBranch), no pet below
		-- level 10 and, with the ranged slot empty, no shot: nothing attacks, the unit is 1 DPS and every weight but
		-- EXTRA_DPS is 0. A bag bow brings the shots back as a gain with a tick and a plan row, and the DPS of a gain is the
		-- gain times the DPS of one unit (1).
		{ "weights' unit: level 8 with an empty ranged slot and no talent point is 1 DPS; the bag bow is an upgrade, in the plan; /hga weights says so", function()
			local G = env()
			G.UnitLevel = function() return 8 end
			G.UnitRangedAttackPower = function() return 30, 0, 0 end
			G.UnitAttackPower = function() return 40, 0, 0 end
			G.talentRanks = {}
			G.equippedLinks[18] = nil
			G.bags[0] = { "newbow" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.noShots, true, "no bow worn")
			T.eq(st.snap.points.BM + st.snap.points.MM + st.snap.points.SV, 0, "no talent point")
			T.eq(st.snap.survival, false); T.eq(st.model.survival, false, "no melee without the Survival branch")
			T.eq(st.total, 0, "nothing attacks")
			T.eq(st.unit, "DPS"); T.eq(st.unitDps, 1)
			local function model(over)
				local p = {}
				for k, v in pairs(st.model) do p[k] = v end
				for k, v in pairs(over) do p[k] = v end
				return p
			end
			for k, v in pairs(st.W) do T.eq(v, k == "EXTRA_DPS" and 1 or 0, k) end
			-- the bow's weapon gain is the model's DPS with its shots, in DPS
			local withBow = ns.Score.CopySet(st.snap.equipped)
			withBow[18] = st.snap.bagPieces[1]
			local shots = ns.Model.Total(model(ns.Player.WeaponInputs(withBow))) - st.total
			T.truthy(shots > 1, "the shots' DPS: " .. shots)
			T.near(st.ctx.weaponGain(withBow) * st.unitDps, shots, 1e-9, "the weapon gain in DPS")
			local r = ns.Advisor.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(r.verdict, "better"); T.eq(r.isUpgrade, true, "the tick")
			T.near(r.dps, r.delta * st.unitDps, 1e-9)
			local first = ns.Advisor.Explain("newbow", { kind = "bag", bag = 0, slot = 1 })[1][1]
			T.eq(first, string.format("HGA: усиление +%.1f (~ +%.1f DPS)", r.delta, r.dps))
			local plan = ns.Advisor.Plan()
			T.eq(#plan.rows, 1); T.eq(plan.rows[1].slot, 18); T.eq(plan.rows[1].new.link, "newbow"); T.eq(plan.verdict, "better")
			-- the plan's DPS and its row's: the gain times the DPS of one unit (A.Plan), as the swap banner's list
			-- says them (Swap.lua fillPanel and fillRow through A.GainLines)
			local row = plan.rows[1]
			T.eq(row.gain.verdict, "better")
			T.eq(plan.dps, plan.delta * st.unitDps, "the plan's DPS"); T.eq(row.gain.dps, row.gain.delta * st.unitDps, "the row's DPS")
			G.SlashCmdList.HUNTERGEARADVISOR("swap")
			local panel = G.HunterGearAdvisorSwapBanner.panel
			T.eq(panel.shown, true); T.eq(panel.rows[1].data, row, "the list shows this plan")
			T.eq(panel.total.text, string.format("всё вместе: усиление +%.1f (~ +%.1f DPS)", plan.delta, plan.delta * st.unitDps))
			T.eq(panel.rows[1].gain.text, string.format("усиление +%.1f (~ +%.1f DPS)", row.gain.delta, row.gain.delta * st.unitDps))
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local header
			for _, l in ipairs(G.printed) do if l:find("урон (", 1, true) then header = l end end
			local want = "урон (1 = 1 DPS; ни RAP, ни AP ближнего боя сейчас урона не дают): Ловк 0.00,"
			T.truthy(header and header:find(want, 1, true), tostring(header))
			-- /hga dump names the unit
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.eq(ns.db.dump.weightUnit, "DPS"); T.eq(ns.db.dump.dpsPerUnit, 1)
			T.eq(#G.reportedErrors, 0)
		end },
		-- the Survival branch with no bow, gun or crossbow neither shoots nor melees (Model weaveParts), so with Lone Wolf, no
		-- Summon Hawk and no pet out nothing attacks: the unit is 1 DPS, every weight 0, and the bag bow's gain is its DPS
		{ "weights' unit: the Survival branch with Lone Wolf, no Summon Hawk, no pet out and no bow at 40: 1 DPS; the bag bow's gain is its DPS", function()
			local G = env()
			survivalTree(G) -- the Survival branch's weave (Player.SurvivalBranch), which needs a bow
			G.UnitLevel = function() return 40 end
			G.talentRanks[105007] = 1 -- Lone Wolf
			G.talentRanks[104966] = 0 -- Summon Hawk
			G.petOut = false
			G.equippedLinks[18] = nil
			G.bags[0] = { "newbow" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.tal.loneWolf, 1); T.eq(st.model.tal.summonHawk, 0); T.eq(st.model.petOut, false); T.eq(st.model.noShots, true)
			T.eq(st.snap.survival, true)
			T.eq(st.total, 0, "nothing attacks"); T.eq(st.unit, "DPS"); T.eq(st.unitDps, 1)
			for k, v in pairs(st.W) do T.eq(v, k == "EXTRA_DPS" and 1 or 0, k) end
			local r = ns.Advisor.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(r.isUpgrade, true, "the bow's shots and the weave it brings")
			T.eq(r.dps, r.delta, "a gain's DPS: the gain in DPS")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local header
			for _, l in ipairs(G.printed) do if l:find("урон (", 1, true) then header = l end end
			T.truthy(header and header:find("урон (1 = 1 DPS; ни RAP, ни AP ближнего боя сейчас урона не дают): Ловк 0.00,", 1, true), tostring(header))
			G.SlashCmdList.HUNTERGEARADVISOR("dump")
			T.eq(ns.db.dump.weightUnit, "DPS"); T.eq(ns.db.dump.dpsPerUnit, 1)
		end },
		-- nothing attacks with no shot, no hawks, no pet and no melee (the env's BM build at level 8): the unit is 1 DPS,
		-- every weight 0, and a gain is the model's DPS change
		{ "weights' unit: the BM build at level 8, no bow: 1 DPS; the bag bow's gain is its DPS; /hga weights says so", function()
			local G = env()
			G.UnitLevel = function() return 8 end
			G.UnitRangedAttackPower = function() return 30, 0, 0 end
			G.UnitAttackPower = function() return 40, 0, 0 end
			G.equippedLinks[18] = nil
			G.bags[0] = { "newbow" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			T.eq(st.model.survival, false); T.eq(st.total, 0)
			T.eq(st.unit, "DPS"); T.eq(st.unitDps, 1)
			for k, v in pairs(st.W) do T.eq(v, k == "EXTRA_DPS" and 1 or 0, k) end
			local withBow = ns.Score.CopySet(st.snap.equipped)
			withBow[18] = st.snap.bagPieces[1]
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			for k, v in pairs(ns.Player.WeaponInputs(withBow)) do p[k] = v end
			T.near(st.ctx.weaponGain(withBow), ns.Model.Total(p), 1e-12, "the bow's gain: the model's DPS with it")
			local r = ns.Advisor.Evaluate("newbow", { kind = "bag", bag = 0, slot = 1 })
			T.eq(r.isUpgrade, true); T.eq(r.dps, r.delta)
			local plan = ns.Advisor.Plan()
			T.eq(#plan.rows, 1); T.eq(plan.rows[1].new.link, "newbow")
			G.printed = {}
			G.SlashCmdList.HUNTERGEARADVISOR("weights")
			local header, shares
			for _, l in ipairs(G.printed) do
				if l:find("урон (", 1, true) then header = l end
				if l:find("кому идёт урон: ", 1, true) then shares = l end
			end
			T.truthy(header and header:find("урон (1 = 1 DPS; ни RAP, ни AP ближнего боя сейчас урона не дают): Ловк 0.00,", 1, true), tostring(header))
			T.truthy(shares and shares:find("кому идёт урон: никому — нет ни выстрелов, ни ястребов, ни пета, ни ближнего боя", 1, true), tostring(shares))
			T.eq(#G.reportedErrors, 0)
		end },
		-- /hga weights: with no bow, gun or crossbow (Model.Parts noShots) no shot is cast and the model's bowSpeed is no
		-- bow's, so the line says there is none in place of the bow's DPS and speed; a thrown weapon casts no shot either,
		-- while its DPS is the model's bowDPS (Player.WeaponInputs), which the hawks' AP reads (Model.Parts hawkAP): the
		-- line says where it goes, the hawks' AP with Summon Hawk (node 104966) and no damage without
		{ "/hga weights: no bow, gun or crossbow is said in place of the bow's DPS and speed; a thrown weapon's DPS goes to the hawks' AP", function()
			local function line(setup)
				local G = env()
				if setup then setup(G) end
				local ns = loadAll(G)
				G.printed = {}
				G.SlashCmdList.HUNTERGEARADVISOR("weights")
				for _, l in ipairs(G.printed) do if l:find("ур. 43, RAP", 1, true) then return l, ns end end
				return "no line", ns
			end
			local l = line()
			T.truthy(l:find("), лук 21.2 DPS / 2.60 с, патроны 16.0, колчан 13%", 1, true), l)
			l = line(function(G) G.equippedLinks[18] = nil end)
			T.truthy(l:find("), нет лука, ружья или арбалета, патроны 0.0, колчан 13%", 1, true), l)
			T.eq(l:find("лук 0.0", 1, true), nil, l)
			-- a thrown weapon: no shot either (Heavy Throwing Dagger 3108: Item.csv class 2, subclass 16, InventoryType 25)
			local function thrown(hawk)
				return function(G)
					local W1 = { r = 1, g = 1, b = 1 }
					local function ln(t, r) return { leftText = t, rightText = r, leftColor = W1, rightColor = W1 } end
					G.items.throwing = { info = { 3108, "INVTYPE_THROWN", 2, 16 }, lines = { ln("Heavy Throwing Dagger"),
						ln("Метательное", "Метательное оружие"), ln("Урон: 17-32", "Скорость 2,10"), ln("(11,6 ед. урона в секунду)") }, api = {} }
					G.equippedLinks[18] = "throwing"
					G.talentRanks[104966] = hawk and 1 or 0
				end
			end
			-- the model: the thrown weapon's DPS in bowDPS with no shot; the hawks' part moves with it, and nothing else
			local function bowDpsMoves(ns)
				local m = ns.Advisor.State().model
				local q = {}
				for k, v in pairs(m) do q[k] = v end
				q.bowDPS = 0
				local a, b = ns.Model.Parts(m), ns.Model.Parts(q)
				for k, v in pairs(a) do if k ~= "hawks" then T.eq(b[k], v, k .. " leaves bowDPS out") end end
				return m, a.hawks - b.hawks
			end
			local ns
			l, ns = line(thrown(true))
			T.truthy(l:find("), не лук, ружьё или арбалет — выстрелов нет, DPS оружия 11.6 идёт только в AP ястребов, патроны 0.0", 1, true), l)
			local m, hawkGain = bowDpsMoves(ns)
			T.eq(m.noShots, true); T.near(m.bowDPS, 11.6, 1e-9)
			T.truthy(hawkGain > 1, "the hawks take the thrown weapon's DPS: " .. hawkGain)
			l, ns = line(thrown(false))
			T.truthy(l:find("), не лук, ружьё или арбалет — выстрелов нет, DPS оружия 11.6 урона не даёт (ястребов нет), патроны 0.0", 1, true), l)
			m, hawkGain = bowDpsMoves(ns)
			T.eq(m.tal.summonHawk, 0); T.near(m.bowDPS, 11.6, 1e-9)
			T.eq(hawkGain, 0, "no hawks: the thrown weapon's DPS adds nothing")
		end },
		-- One Use buff per Use spell a set (Score.SetValue): Accursed Chalice 228078 (ItemEffect 189379: CoolDownMSec 120000,
		-- SpellID 461224) worn, its bag copy into the empty trinket slot shares the worn one's cooldown and aura
		{ "two copies of a Use trinket: the bag copy into the empty trinket slot adds no second buff and is no plan row", function()
			local G = env()
			local W1 = { r = 1, g = 1, b = 1 }
			local function ln(t) return { leftText = t, leftColor = W1, rightColor = W1 } end
			G.items.chalice = { info = { 228078, "INVTYPE_TRINKET", 4, 0 }, lines = { ln("Проклятая чаша"), ln("Аксессуар"),
				ln("Использование: +80 к силе на 20 сек.") }, api = {} }
			G.equippedLinks[13] = "chalice"
			G.bags[0] = { "chalice" }
			-- Strength adds damage through the melee swings alone (the pet reads the higher of RAP and melee AP), which the
			-- Survival branch's weave counts (Player.SurvivalBranch)
			survivalTree(G)
			local ns = loadAll(G)
			settlePet(G)
			local st = ns.Advisor.State()
			T.eq(st.snap.equipped[13].use.spell, 461224); T.eq(st.snap.equipped[14], nil)
			T.truthy(st.W.STR > 0, "Strength adds damage: " .. st.W.STR)
			local r = ns.Advisor.Evaluate("chalice", { kind = "bag", bag = 0, slot = 1 })
			T.near(r.delta, 0, 1e-12, "no second buff"); T.eq(r.verdict, "same"); T.eq(r.isUpgrade, false)
			local both = ns.Score.CopySet(st.snap.equipped)
			both[14] = st.snap.bagPieces[1]
			T.near(ns.Score.SetValue(both, st.W, st.ctx), ns.Score.SetValue(st.snap.equipped, st.W, st.ctx), 1e-12, "both slots: one buff")
			-- no plan row puts the copy on (the plan takes the env's off-hand sword off: in the weave it swings in no visit
			-- behind the 2.6 s main hand, and dual wield adds 19% miss to the main hand's white swings)
			for _, row in ipairs(ns.Advisor.Plan().rows) do T.truthy(row.new ~= st.snap.bagPieces[1], "the copy is no plan row") end
		end },
		-- the tooltip of a melee weapon in the Survival branch names the weave's cycle with it when it changes the cycle
		-- (raid-mode design 15.6: Model.Weave at the model point with the set's weapons, the cycle outside Rapid Fire): a
		-- made-up 5.0 s main-hand sword and a made-up 5.0 s two-handed staff set the cycle by their swing timer; the env's 2.4 s
		-- bag sword leaves the cycle the ranged path sets; outside the Survival branch no line
		{ "weave tooltip: a melee weapon, a two-hander too, that changes the cycle names it; one that does not says nothing; none outside the Survival branch", function()
			local function setup(survival)
				local G = env()
				if survival then survivalTree(G) end
				local Wc = { r = 1, g = 1, b = 1 }
				local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
				G.items.slowmh = { info = { 99511, "INVTYPE_WEAPONMAINHAND", 2, 7 }, lines = { ln("Медленный меч"), ln("Правая рука", "Меч"),
					ln("Урон: 90-130", "Скорость 5,00"), ln("(22,0 ед. урона в секунду)") }, api = {} }
				G.items.slow2h = { info = { 99513, "INVTYPE_2HWEAPON", 2, 10 }, lines = { ln("Медленный посох"), ln("Двуручное", "Посох"),
					ln("Урон: 150-220", "Скорость 5,00"), ln("(37,0 ед. урона в секунду)") }, api = {} }
				G.bags[0] = { "slowmh", "bagsword", "slow2h" }
				local ns = loadAll(G)
				local function text(slot, link)
					local t = {}
					for i, l in ipairs(ns.Advisor.Explain(link, { kind = "bag", bag = 0, slot = slot })) do t[i] = l[1] end
					return table.concat(t, "\n")
				end
				return ns, text(1, "slowmh"), text(2, "bagsword"), text(3, "slow2h")
			end
			local ns, slow, plain, slow2h = setup(true)
			local st = ns.Advisor.State()
			for _, case in ipairs({ { "slowmh", 1, slow, "the slow sword" }, { "slow2h", 3, slow2h, "the slow staff" } }) do
				local res = ns.Advisor.Evaluate(case[1], { kind = "bag", bag = 0, slot = case[2] })
				T.eq(res.newSet[16].link, case[1])
				local q = {}
				for k, v in pairs(st.model) do q[k] = v end
				for k, v in pairs(ns.Player.WeaponInputs(res.newSet)) do q[k] = v end
				local now, with = ns.Model.Weave(st.model).base.C, ns.Model.Weave(q).base.C
				T.near(with, 5.0, 1e-12, case[4] .. ": its swing timer sets the cycle")
				T.truthy(case[3]:find(string.format("HGA: плетение — цикл %.2f с с этим оружием (было %.2f с)", with, now), 1, true), case[3])
			end
			T.eq(plain:find("HGA: плетение", 1, true), nil, plain)
			local _, bmSlow, _, bmSlow2h = setup(false)
			T.eq(bmSlow:find("HGA: плетение", 1, true), nil, bmSlow)
			T.eq(bmSlow2h:find("HGA: плетение", 1, true), nil, bmSlow2h)
		end },
		-- the tooltip's placement line names what happens to the other hand in the set the evaluation places a weapon in
		-- (res.newSet): emptied where an item is worn, as the gain holds it ("левую руку — снять", "правую руку — снять"), or
		-- nothing more where the worn item stays. Made-up items: a 30 DPS 2.6 s bag one-hander with +10 Agility; a 5.0 s 1 DPS
		-- sword and a +1 Agility held item worn, a +5 Agility held item in the bag; a +40 Agility held item; a worn pair of a 2.6 s
		-- and a 1.8 s sword without stats. In the Survival branch the weave takes the off hand off (it swings in no visit behind a 2.6 s main
		-- hand and adds dual wield's 19% miss to the main hand's white swings), and an empty main hand (1.0 s) beats the 5.0 s sword, whose swing
		-- timer sets a 5 s cycle; with the BM build (no melee) a worn +40 Agility held item stays next to the bag one-hander, and
		-- the env's bag sword goes into the off hand next to the worn main hand; a hand that is empty already says nothing
		{ "tooltip placement: the other hand emptied says \"снять\", the worn one kept says nothing more", function()
			local Wc = { r = 1, g = 1, b = 1 }
			local function ln(l, r) return { leftText = l, rightText = r, leftColor = Wc, rightColor = Wc } end
			local function linesOf(survival, worn, bag)
				local G = env()
				if survival then survivalTree(G) end
				G.items.bigsword = { info = { 99521, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Большой меч"), ln("Одноручное", "Меч"),
					ln("Урон: 60-96", "Скорость 2,60"), ln("(30,0 ед. урона в секунду)"), ln("+10 к ловкости") }, api = {} }
				G.items.junk = { info = { 99522, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Ржавый меч"), ln("Одноручное", "Меч"),
					ln("Урон: 4-6", "Скорость 5,00"), ln("(1,0 ед. урона в секунду)") }, api = {} }
				G.items.frill = { info = { 99523, "INVTYPE_HOLDABLE", 4, 0 }, lines = { ln("Безделушка"), ln("Левая рука"), ln("+1 к ловкости") }, api = {} }
				G.items.frill2 = { info = { 99524, "INVTYPE_HOLDABLE", 4, 0 }, lines = { ln("Новая безделушка"), ln("Левая рука"), ln("+5 к ловкости") }, api = {} }
				G.items.frill40 = { info = { 99525, "INVTYPE_HOLDABLE", 4, 0 }, lines = { ln("Сфера"), ln("Левая рука"), ln("+40 к ловкости") }, api = {} }
				G.items.plainoh = { info = { 99526, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Простой меч"), ln("Одноручное", "Меч"),
					ln("Урон: 25-40", "Скорость 1,80"), ln("(18,0 ед. урона в секунду)") }, api = {} }
				G.items.plainmh = { info = { 99527, "INVTYPE_WEAPON", 2, 7 }, lines = { ln("Простой длинный меч"), ln("Одноручное", "Меч"),
					ln("Урон: 40-75", "Скорость 2,60"), ln("(22,1 ед. урона в секунду)") }, api = {} }
				if worn then G.equippedLinks[16], G.equippedLinks[17] = worn[1], worn[2] end
				G.bags[0] = { bag }
				local ns = loadAll(G)
				local res = ns.Advisor.Evaluate(bag, { kind = "bag", bag = 0, slot = 1 })
				local set = {}
				for _, l in ipairs(ns.Advisor.Explain(bag, { kind = "bag", bag = 0, slot = 1 })) do set[l[1]] = true end
				return res, set
			end
			local res, set = linesOf(true, { "plainmh", "plainoh" }, "bigsword")
			T.eq(res.hand, "mh"); T.eq(res.oh, nil, "the Survival weave takes the off hand off")
			T.truthy(set["HGA: надеть в правую руку, левую руку — снять"], "the main hand with the off hand emptied")
			res, set = linesOf(true, { "junk", "frill" }, "frill2")
			T.eq(res.hand, "oh"); T.eq(res.mh, nil, "an empty main hand beats the 5.0 s sword")
			T.truthy(set["HGA: надеть в левую руку, правую руку — снять"], "the off hand with the main hand emptied")
			res, set = linesOf(false, { "sword", "frill40" }, "bigsword")
			T.eq(res.hand, "mh"); T.eq(res.oh.link, "frill40", "BM: the worn held item stays")
			T.truthy(set["HGA: надеть в правую руку"], "the main hand, the worn off hand kept")
			res, set = linesOf(true, nil, "bagsword")
			T.eq(res.hand, "oh"); T.eq(res.mh.link, "sword", "the worn main hand stays")
			T.truthy(set["HGA: надеть в левую руку"], "the off hand, the worn main hand kept")
			res, set = linesOf(true, { "offsword", nil }, "bigsword")
			T.eq(res.hand, "mh"); T.eq(res.oh, nil)
			T.truthy(set["HGA: надеть в правую руку"], "the main hand, no off hand worn")
			res, set = linesOf(true, { nil, "frill" }, "frill2")
			T.eq(res.hand, "oh"); T.eq(res.mh, nil)
			T.truthy(set["HGA: надеть в левую руку"], "the off hand, no main hand worn")
		end },
		-- the unarmed main hand as wowsims has it (raid-mode design section 16; wowsims sim/core/attack.go:35-45, 95-102):
		-- an empty main hand swings at 1.0 s with normalized 1.0, everywhere: the weave's swing (the model point's mhSpeed) and
		-- Strider Kick's normalized hit; an empty off hand and ranged slot are no weapon, 0 DPS (attack.go:104-120)
		{ "unarmed: an empty main hand swings at 1.0 s with normalized 1.0; the empty off hand and ranged slot keep 0 DPS", function()
			local G = env()
			survivalTree(G)
			G.talentRanks[104981] = 1 -- Strider Kick
			G.equippedLinks[16], G.equippedLinks[17] = nil, nil
			local ns = loadAll(G)
			local m = ns.Advisor.State().model
			T.eq(m.unarmed, true); T.eq(m.mhSpeed, 1.0); T.eq(m.mhNorm, 1.0); T.eq(m.mhDPS, 0); T.eq(m.ohDPS, 0)
			local w = ns.Model.Weave(m)
			T.near(w.base.M, 1.0, 1e-12, "the weave's swing: 1.0 s at no attack speed")
			-- Strider Kick's normalized hit: the melee attack power / 14 x 1.0
			local p = {}
			for k, v in pairs(m) do p[k] = v end
			p.mhNorm = 2.4
			T.truthy(ns.Model.Parts(p).melee > ns.Model.Parts(m).melee + 1e-6, "a normalized 2.4 would hit harder")
			local bare = ns.Player.WeaponInputs({})
			T.eq(bare.ohDPS, 0); T.eq(bare.bowDPS, 0); T.eq(bare.noShots, true)
		end },
		-- the Highborne Research Tablet's dives with no weapon at all (the BM build, Summon Hawk): its ranged specials roll at
		-- the main hand's speed (Score.PROC_OVERRIDES spellsAtMainHand: wowsims NewLegacyPPMManagerWithSpells), the unarmed
		-- 1.0 s: 2.6 a minute x 1.0 on the two dives of 18 s
		{ "unarmed: the Tablet's dives with no weapons roll at 1.0 s", function()
			local G = env()
			addTablet(G)
			G.equippedLinks[16], G.equippedLinks[17], G.equippedLinks[18] = nil, nil, nil
			G.bags[0] = { "tablet" }
			local ns = loadAll(G)
			local st = ns.Advisor.State()
			local lh = st.ctx.landedHits
			T.eq(lh.mh.speed, 1.0); T.eq(lh.ranged.speed, 0); T.near(lh.ranged.specials, 2 / 18, 1e-15, "the dives")
			T.eq(lh.mh.swings + lh.mh.specials + lh.oh.swings + lh.ranged.swings, 0, "no other hit")
			local r = ns.Advisor.Evaluate("tablet", { kind = "bag", bag = 0, slot = 1 })
			T.near(ns.Advisor.ModelProcRates(r)[1], 2.6 * 1.0 * 2 / 18, 1e-12, "the dives at the unarmed 1.0 s")
		end },
	}
end
