-- The best pre-raid set for the BM hunter on WoW Forever: variant B (no battleground reputation, no Barkskin Burrow
-- reputation; hit cap 8%) as tools/preraid/rescore picks it with the raid-mode model (the raid boss +3, the 180 s fight
-- with mana; docs/superpowers/specs/raid-mode-design.md), 2026-11-18. The window shows variant B (user 2026-11-17).
-- The sets before that model, variants A and B with their window data: docs/research/preraid-bis-60-before-raid-mode.md.
-- Sources of every fact are in that file. Names in Russian:
--   NPCs: warcraft-forever.ru (ru client data).
--   Quests: wow-pilot.cc ?lang=ru. Factions: client DB2 Faction ruRU. Dungeons: client AreaTable ruRU.
--   Bosses: AtlasLoot Forever ruRU locale; the Blackmaw Hold bosses (no ruRU name in AtlasLoot): client DB2
--   DungeonEncounter ruRU, build 70959 (tools/preraid/data/db2/DungeonEncounterRu.csv: 3316 Impaan the Imprisoner
--   "Бесаан Бесноватый", 3323 Blackmaw Behemoth "Исполин из клана Черночревов");
--   Blackmaw Hold: client AreaTable ruRU 1216 ("Крепость Черночревов").
--   Coordinates: warcraft-forever.ru / wow-pilot / classic-wow.com / icy-veins db; uiMapIDs: client UiMap.
-- Crafts: client DB2 from wago.tools, build 1.60.1.70888 (the same rows in 70959 and 71037): the craft spell that
--   creates the item (SpellEffect: Effect 24, EffectItemType), its reagents in their order (SpellReagents), the
--   pattern item that teaches the spell (ItemEffect with TriggerType 6 and that SpellID, joined by ItemXItemEffect),
--   the profession and skill the pattern needs (ItemSparse RequiredSkill 165 = Leatherworking, «Кожевничество» in
--   SkillLine ruRU; RequiredSkillRank), the specialization it needs (ItemSparse RequiredAbility 10660 = Tribal
--   Leatherworking, «Кожевничество: традиции предков» in SpellName ruRU), BoE (Bonding 2) and the item's level
--   (RequiredLevel); SkillLineAbility puts each craft spell on skill line 165. Where a pattern comes from:
--   foreverdb.net item pages (read 2026-11-21); the zone: client AreaTable ruRU 490 («Кратер Ун'Горо»).
-- costItem ids (Tarnished Undermine Real 226404): client DB2 ItemSparse.
-- atlas = where AtlasLoot lists it: { module, item | spell | npc } (found at click time).
local _, ns = ...

local NPC = {
	pix     = { name = "Пикс Ксиззикс", map = 1434, x = 28.4, y = 75.8, zoneRu = "Тернистая долина (Пиратская бухта)" },
	thrall  = { name = "Тралл", map = 1454, x = 31.7, y = 37.8, zoneRu = "Оргриммар" },
	taelan  = { name = "Верховный лорд Телан Фордринг", map = 1422, x = 42.0, y = 14.8, zoneRu = "Западные Чумные земли" },
	-- warcraft-forever.ru/npc/230317 (name and one of its spawns, the nearest to QuestieDB's 34.91, 38.06)
	mokvar  = { name = "Моквар", map = 1454, x = 35.0, y = 38.0, zoneRu = "Оргриммар" },
}

ns.PreRaidData = {
	items = {
		{ id = 252605, slotRu = "Голова", kind = "craft", boe = true, reqLevel = 56,
			prof = "Кожевничество", skill = 300, pattern = 252939,
			-- foreverdb.net/item/252939: new in Forever, "where it comes from isn't known yet"
			patternSource = "источник выкройки не найден",
			reagents = { { 8170, 20 }, { 15416, 40 }, { 12810, 12 }, { 15407, 4 }, { 249429, 10 }, { 14341, 2 }, { 248825, 20 } },
			atlas = { module = "AtlasLootClassic_Crafting", spell = 1254968 } },
		{ id = 15411, slotRu = "Шея", kind = "quest", quest = "Во сне", questId = 5944, npc = NPC.taelan, reqLevel = 52,
			note = "Это последний квест цепочки. Она начинается с «Псы-демоны» (5542) у Тириона Фордринга (Восточные Чумные земли 5.2, 35.6); один шаг в Стратхольме." },
		{ id = 18686, slotRu = "Плечи", kind = "drop", dungeon = "Некроситет", boss = "Громоклин",
			reqLevel = 57, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 18686 } },
		{ id = 13340, slotRu = "Спина", kind = "drop", dungeon = "Стратхольм", boss = "Барон Ривендер",
			reqLevel = 58, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 13340 } },
		{ id = 252483, slotRu = "Грудь", kind = "craft", boe = true, reqLevel = 56,
			prof = "Кожевничество", skill = 300, pattern = 252892,
			-- foreverdb.net/item/252892: new in Forever, "where it comes from isn't known yet"
			patternSource = "источник выкройки не найден",
			reagents = { { 12810, 6 }, { 12809, 10 }, { 7080, 20 }, { 249429, 10 }, { 15407, 4 }, { 14341, 10 }, { 248825, 20 } },
			atlas = { module = "AtlasLootClassic_Crafting", spell = 1255015 } },
		-- vendors: wowsims db.json soldBy Mokvar 230317 and Kor'kron Elite 230566 (Horde, Orgrimmar); 25 g by Wowhead Forever only
		{ id = 226885, slotRu = "Запястья", kind = "vendor", npc = NPC.mokvar, cost = "25з",
			note = "Только для охотника, персональная (BoP), на аукционе не бывает. Тот же товар за 25з у Кор'кронского гвардейца рядом (Оргриммар 34.8, 38.4). Её же дают за квест «Серьезное предложение» (84156, с 58 ур.); нужен ли он для покупки, неизвестно. Цена по Wowhead Forever, в игре не проверено." },
		{ id = 15063, slotRu = "Кисти рук", kind = "craft", boe = true, reqLevel = 53,
			prof = "Кожевничество", skill = 265, pattern = 15758,
			-- foreverdb.net/item/15758: sold by Nergal <General Goods Vendor>, Un'Goro Crater, 2g 20s, "seen in WoW Forever"
			patternSource = "торговец Nergal, Кратер Ун'Горо, 2з 20с; выкройка требует специализации «Кожевничество: традиции предков»",
			reagents = { { 8170, 30 }, { 15417, 8 }, { 14341, 1 } },
			note = "Сет с Devilsaur Leggings: 2 вещи дают +2% хита — носить только парой.",
			atlas = { module = "AtlasLootClassic_Crafting", spell = 19084 } },
		-- 100 Reals: conquestcapped.com Tarnished Undermine Real guide (updated 2026-11-17)
		{ id = 272397, slotRu = "Пояс", kind = "vendor", npc = NPC.pix, costItem = { 226404, 100 },
			reqLevel = 60, note = "Реалы падают раз в день с боссов подземелий 55+." },
		{ id = 15062, slotRu = "Ноги", kind = "craft", boe = true, reqLevel = 55,
			prof = "Кожевничество", skill = 290, pattern = 15772,
			-- foreverdb.net/item/15772: drops from Glutinous Ooze 1.1%, Primal Ooze 1%, Cloned Ooze 1%, Muculent Ooze 0.9%,
			-- marked Classic data (CMaNGOS classic-db, not yet seen in Forever); no zone given
			patternSource = "слизни Glutinous, Primal, Cloned и Muculent Ooze, 0.9–1.1% (данные Classic); выкройка требует специализации «Кожевничество: традиции предков»",
			reagents = { { 8170, 30 }, { 15417, 14 }, { 15407, 1 }, { 14341, 1 } },
			note = "Сет с Devilsaur Gauntlets: 2 вещи дают +2% хита — носить только парой.",
			atlas = { module = "AtlasLootClassic_Crafting", spell = 19097 } },
		{ id = 13967, slotRu = "Ступни", kind = "drop", dungeon = "Некроситет", boss = "Киртонос Глашатай",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 13967 } },
		{ id = 272408, slotRu = "Палец 1", kind = "vendor", npc = NPC.pix, costItem = { 226404, 75 },
			reqLevel = 60, note = "Реалы падают раз в день с боссов подземелий 55+." },
		{ id = 18314, slotRu = "Палец 2", kind = "drop", dungeon = "Забытый Город (Восток)", boss = "Алззин Перевертень",
			reqLevel = 54, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 18314 } },
		{ id = 13965, slotRu = "Аксессуар 1", kind = "quest", quest = "За Орду!", questId = 4974, npc = NPC.thrall, reqLevel = 55,
			note = "Нужна голова Вождя Ренда Чернорука (Вершина Черной горы, верхняя).",
			atlas = { module = "AtlasLootClassic_DungeonsAndRaids", npc = 10429 } },
		{ id = 280065, slotRu = "Аксессуар 2", kind = "drop", dungeon = "Крепость Черночревов", boss = "Исполин из клана Черночревов",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 280065 } },
		-- a two-handed axe (Item.csv 70959: class 2, subclass 1, InventoryType 17); boss level 57 and the path: conquestcapped
		-- Blackmaw Hold guide, Warcraft Tavern
		{ id = 280056, slotRu = "Двуручное", kind = "drop", dungeon = "Крепость Черночревов", boss = "Бесаан Бесноватый",
			reqLevel = 54, note = "Новый босс Forever (демон, элита, ур. 57): от входа по тропе вверх через Рощу Черночревов к Оскверненному пику. Шанс дропа не опубликован. В AtlasLoot подписан по-английски: Impaan the Imprisoner.",
			atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 280056 } },
		{ id = 13023, slotRu = "Дальний бой", kind = "world", boe = true, reqLevel = 58,
			note = "Чаще всего: Колосс Зоры (Силитус) и арена Забытого Города (данные Classic)." },
	},
}
