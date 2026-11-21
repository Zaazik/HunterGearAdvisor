# Пререйд-наборы A и Б до рейдового режима (сохранено 2026-11-18)

Старые варианты A и Б из `docs/research/preraid-bis-60.md` (раздел 2, состояние на main 494b581) и данные окна
`/hga preraid` до пересчёта по модели рейдового режима (`docs/superpowers/specs/raid-mode-design.md`). Подобраны
стендом `tools/preraid/rescore` на модели прокачки (цель +3 без боя 180 с, маны и дебаффов босса).

## Варианты A и Б (текст из preraid-bis-60.md)

### Вариант А — с Exalted на полях боя (Darkspear Islands, Warsong, Frostwolf)
Хит 7.7%. Названия фракций и полей боя — из клиента ruRU (Faction, AreaTable). Четыре вещи за репутацию, все на «Превознесение» (42 000 от «Равнодушия»); как её набрать — таблица ниже (проверено 2026-11-17).

| Вещь | Фракция, поле боя | DPS вещи* | Как качается | Оценка |
|---|---|---|---|---|
| Darkspear Pauldrons / Epaulets (плечи) | Налетчики Черного Копья, Острова Черного Копья (15×15, 30–60) | +5.6 | Квест за победу +200; сдача 3 марок +150 (по conquestcapped повторно +100); марки: победа 3, поражение 1; в клиенте есть +10 за действие в матче, триггер неизвестен | ~120–420 побед |
| Raider Gloves (перчатки) | Налетчики Черного Копья | вместе с поножами +5.4 | та же репутация, что плечи | — |
| Outrider's Chain Leggings (поножи) | Всадники Песни Войны, Ущелье Песни Войны (10×10, с 10 ур.) | вместе с перчатками +5.4 | Рейты Forever не опубликованы; Classic: +35 за флаг всей команде, сдача 3 марок +50 (или +100); в клиенте спелл «+42 за победу», триггер неизвестен | ~170–400 побед 3:0 (≈270) |
| Don Julio's Band (кольцо) | Клан Северного Волка, Альтеракская долина (40×40, 51–60) | +2.8 | Classic: генерал ~300–389, лейтенанты по 125, бункеры/башни/кладбища по 12–24, сдача 3 марок +100; разовые квесты ~2 500 | ~40–100 побед (~100–120 игр при 50%) |

\* DPS — насколько набор А хуже, если вещь заменить вариантом без репутации (новая модель аддона, рейд-босс): плечи → Stratholme Militia; перчатки + поножи → пара Devilsaur (только парой: одни поножи без перчаток Devilsaur дают −11.7, теряется бонус сета); кольцо → Tarnished Elven Ring.

- Ранг «Превознесение»: Налетчики Черного Копья — данные клиента Forever (wowreputations). Всадники Песни Войны — подсказка Wowhead Forever, но в клиенте у вещи требования нет. Клан Северного Волка — только Classic; в клиенте Forever требования нет. Если окажется «Почтение» — нужно 21 000, вдвое меньше.
- Перк Diplomat: +2% репутации за ранг, до +10%. Квест на марки всех полей боя (For Great Honor, у боевого вестника в Оргриммаре) даёт репутацию сразу Всадникам Песни Войны и Клану Северного Волка.
- «Clear the Forest!» (+1 000 Всадникам Песни Войны, ежедневный) есть в данных клиента, но по Warcraft Wiki — только Season of Discovery; не рассчитывать.
- Источники: wowhead.com/forever (faction=2798, tooltip 22673 dataEnv=16), wowreputations.com/forever (darkspear-raiders, warsong-outriders, frostwolf-clan), conquestcapped (Darkspear Islands, Warsong Gulch), forever-codex.com/reputations/frostwolf-clan, foreverdb.net/reputation/warsong-outriders, worstguidesever (Classic-значения), форум Blizzard EU 14.11 (очереди AV).

| Слот | Предмет | Статы (Forever) | Где брать |
|---|---|---|---|
| Голова | Black Dragonscale Helm 252605 (кольчуга, BoE) | +21 Agi, +38 Int, +1% крита | Кожевничество 300. На твоём АХ: шлем 290.50g, выкройка 252939 53g |
| Шея | Mark of Fordring 15411 | +26 AP, +1% крита | Квест 5944 «In Dreams» (цепочка Тирион/Таэлан, WPL→EPL, шаг в Стратхольме) |
| Плечи | Darkspear Pauldrons 272105 (кожа) / Darkspear Epaulets 272106 (кольчуга) | +27 Agi, +12 Sta, +1% крита | Creeg Bothunk, Барренс 65.0,34.6, Darkspear Raiders Exalted, ~16g |
| Плащ | Cape of the Black Baron 13340 | +15 Agi, +20 AP | Барон Ривендер, Стратхольм |
| Грудь | Dawn Armor 252483 (кожа, BoE) | +37 Agi, +1% хита, +1% крита | Кожевничество 300. На твоём АХ: 300g, выкройка 252892 1176g |
| Запястья | Marksman Bands 18296 (кольчуга, BoE) | +12 Agi, +8 Sta, +1% хита | Трэш Dire Maul; на твоём АХ 49g |
| Руки | Raider Gloves 272099 (кожа) | +27 Agi, +11 Str, +15 Sta | Creeg Bothunk, Darkspear Raiders Exalted |
| Пояс | Marksman's Girdle 22232 | +21 Agi, +1% хита | Urok Doomhowl, LBRS |
| Ноги | Outrider's Chain Leggings 22673 | +35 Agi, +15 Sta, +1% хита, +1% крита | Kelm Hargunth, Mor'shan (Барренс 46.6,8.4), Warsong Outriders, ~25g |
| Ступни | Windreaver Greaves 13967 | +20 Agi, +4 Int, +1% хита | Kirtonos the Herald, Scholomance |
| Кольцо 1 | Don Julio's Band 19325 | +14 AP, +10 Sta, +1% хита, +1% крита | Frostwolf Supply Officer (Jekyll Flandring, Альтерак 62.8,59.3 / Grunnda Wolfheart в AV), ~75g |
| Кольцо 2 | Cutthroat's Signet 272408 | +14 Agi, +8 Sta, +1% хита | Pix Xizzix, Booty Bay 28.4,75.8, 75 Tarnished Undermine Real (раз в день с боссов данжей 55+) |
| Тринкет 1 | Blackhand's Breadth 13965 | +1% крита; on-use +5% крита по цели 20 с / 5 мин (x2 против орков и огров) | Квест 4974 «For The Horde!» (голова Ренда, UBRS) |
| Тринкет 2 | Rune of the Guard Captain 19120 | +14 AP (x3 в лесах и лугах), +7 рейтинга хита = 0.7% | Квест 7862, доска в Revantusk Village (Хинтерленд 79.1,79.0) |
| Оружие | Peacemaker 18725 (древковое, носитель статов) | +56 AP, +1% крита | Мировой судья Бартилас, Стратхольм. Заменил Bear Poking Stick 274419 (2026-11-17): тот требует Barkskin Burrow Revered, ~1030 Deadwood Tribal Beads (~2000 убийств), а по модели аддона лучше всего на 0.35 DPS |
| Дальний бой | Eaglehorn Long Bow 13023 (BoE) | 32.2 DPS @1.8, +10 Agi, +4 Sta | Мировой дроп; на твоём АХ 85.41g |

### Вариант Б — без репутации полей боя и без Норы Древокожих
Хит 8.0%. **Этот вариант показывает окно `/hga preraid`** (`Game/PreRaidData.lua`, с 2026-11-17). Перепроверен стендом с фильтром «без репутации полей боя и Норы Древокожих»: лучший, выигрыш стенда только от условности «сила атаки против типа существ» и неучтённого использования Blackhand's Breadth.

| Слот | Предмет | Статы (Forever) | Где брать |
|---|---|---|---|
| Голова | Black Dragonscale Helm 252605 | как в А | как в А |
| Шея | Mark of Fordring 15411 | как в А | как в А |
| Плечи | Stratholme Militia Shoulderguard 18742 (кольчуга, BoE) | +22 Agi, +6 Int, +9 Sta | Трэш Стратхольма (очень редко); на твоём АХ не видели, на других Horde-серверах 38–50g |
| Плащ | Cape of the Black Baron 13340 | как в А | как в А |
| Грудь | Dawn Armor 252483 | как в А | как в А |
| Запястья | Marksman Bands 18296 | как в А | как в А |
| Руки | Devilsaur Gauntlets 15063 (кожа, BoE) | +28 AP, +9 Sta, +1% крита; сет 2 шт. +2% хита | Кожевничество 265 и специализация «Кожевничество: традиции предков» (DB2 клиента: ItemSparse выкройки 15758, RequiredAbility 10660); выкройка у торговца Nergal, Кратер Ун'Горо, 2з 20с (foreverdb.net). На твоём АХ 13.77g |
| Пояс | Marksman's Girdle 22232 | как в А | как в А |
| Ноги | Devilsaur Leggings 15062 (кожа, BoE) | +46 AP, +12 Sta, +1% крита; сет | Кожевничество 290 и специализация «Кожевничество: традиции предков» (DB2 клиента: ItemSparse выкройки 15772, RequiredAbility 10660); выкройка падает со слизней Glutinous, Primal, Cloned и Muculent Ooze, 0.9–1.1% (foreverdb.net, данные Classic). На твоём АХ 54g |
| Ступни | Windreaver Greaves 13967 | как в А | как в А |
| Кольцо 1 | Cutthroat's Signet 272408 | как в А | как в А |
| Кольцо 2 | Tarnished Elven Ring 18500 | +10 Agi, +1% хита, +10 к сопр. тайной магии | DM North, Gordok Tribute |
| Тринкет 1 | Blackhand's Breadth 13965 | как в А | как в А |
| Тринкет 2 | Behemoth Bones 280065 | +34 AP; on-use хил себя и союзника, 5 мин | Blackmaw Behemoth, Blackmaw Hold (новый данж 55–60, Азшара) |
| Оружие | Peacemaker 18725 | как в А | как в А |
| Дальний бой | Eaglehorn Long Bow 13023 | как в А | как в А |

Перебор для обоих вариантов: `tools/preraid/opt.py` (кандидаты и фильтры) и `tools/preraid/solve.py` (DP по слотам с хитом как состоянием, бонусы сетов перебором слотов).

## Данные окна: вариант Б (`Game/PreRaidData.lua` на main 494b581)

Строки об источниках крафта (откуда реагенты и номера выкроек, где выкройка падает или продаётся) приведены к DB2 клиента и foreverdb.net, как в `Game/PreRaidData.lua` (2026-11-21); остальное — как в том коммите.

```lua
-- The best pre-raid set for the BM hunter on WoW Forever (variant B of
-- docs/research/preraid-bis-60.md: no battleground reputation, no Barkskin Burrow reputation; hit cap 8%).
-- User 2026-11-17: the window shows variant B (variant A = git history before this change, commit 40beb7b).
-- Sources of every fact are in that file. Names in Russian:
--   NPCs: warcraft-forever.ru (ru client data).
--   Quests: wow-pilot.cc ?lang=ru. Factions: client DB2 Faction ruRU. Dungeons: client AreaTable ruRU.
--   Bosses: AtlasLoot Forever ruRU locale; Blackmaw Behemoth: ForeverGuide NewDungeonData ("Исполин Чёрной Пасти");
--   Blackmaw Hold: client AreaTable ruRU 1216 ("Крепость Черночревов").
--   Coordinates: warcraft-forever.ru / wow-pilot / classic-wow.com / icy-veins db; uiMapIDs: client UiMap.
-- Reagents and pattern ids of crafts: client DB2 (SpellReagents; ItemEffect / ItemXItemEffect), build 1.60.1.70888.
-- Pattern sources: foreverdb.net item pages.
-- costItem ids (Tarnished Undermine Real 226404): client DB2 ItemSparse.
-- atlas = where AtlasLoot lists it: { module, item | spell | npc } (found at click time).
local _, ns = ...

local NPC = {
	pix     = { name = "Пикс Ксиззикс", map = 1434, x = 28.4, y = 75.8, zoneRu = "Тернистая долина (Пиратская бухта)" },
	thrall  = { name = "Тралл", map = 1454, x = 31.7, y = 37.8, zoneRu = "Оргриммар" },
	taelan  = { name = "Верховный лорд Телан Фордринг", map = 1422, x = 42.0, y = 14.8, zoneRu = "Западные Чумные земли" },
}

ns.PreRaidData = {
	items = {
		{ id = 252605, slotRu = "Голова", kind = "craft", boe = true, reqLevel = 56,
			prof = "Кожевничество", skill = 300, pattern = 252939,
			patternSource = "источник выкройки не найден",
			reagents = { { 8170, 20 }, { 15416, 40 }, { 12810, 12 }, { 15407, 4 }, { 249429, 10 }, { 14341, 2 }, { 248825, 20 } },
			atlas = { module = "AtlasLootClassic_Crafting", spell = 1254968 } },
		{ id = 15411, slotRu = "Шея", kind = "quest", quest = "Во сне", questId = 5944, npc = NPC.taelan, reqLevel = 52,
			note = "Это последний квест цепочки. Она начинается с «Псы-демоны» (5542) у Тириона Фордринга (Восточные Чумные земли 5.2, 35.6); один шаг в Стратхольме." },
		{ id = 18742, slotRu = "Плечи", kind = "trash", dungeon = "Стратхольм", boss = "треш", boe = true, reqLevel = 55,
			note = "Падает очень редко (данные Classic); на твоём аукционе не видели.",
			atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 18742 } },
		{ id = 13340, slotRu = "Спина", kind = "drop", dungeon = "Стратхольм", boss = "Барон Ривендер",
			reqLevel = 58, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 13340 } },
		{ id = 252483, slotRu = "Грудь", kind = "craft", boe = true, reqLevel = 56,
			prof = "Кожевничество", skill = 300, pattern = 252892,
			patternSource = "неизвестно ни одному сайту",
			reagents = { { 12810, 6 }, { 12809, 10 }, { 7080, 20 }, { 249429, 10 }, { 15407, 4 }, { 14341, 10 }, { 248825, 20 } },
			atlas = { module = "AtlasLootClassic_Crafting", spell = 1255015 } },
		{ id = 18296, slotRu = "Запястья", kind = "trash", dungeon = "Забытый Город (Восток)", boss = "треш", boe = true,
			note = "Падает с сатиров Wildspawn, редко (данные Classic).",
			reqLevel = 51, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 18296 } },
		{ id = 15063, slotRu = "Кисти рук", kind = "craft", boe = true, reqLevel = 53,
			prof = "Кожевничество", skill = 265, pattern = 15758,
			patternSource = "торговец Nergal, Кратер Ун'Горо, 2з 20с; выкройка требует специализации «Кожевничество: традиции предков»",
			reagents = { { 8170, 30 }, { 15417, 8 }, { 14341, 1 } },
			note = "Сет с Devilsaur Leggings: 2 вещи дают +2% хита — носить только парой.",
			atlas = { module = "AtlasLootClassic_Crafting", spell = 19084 } },
		{ id = 22232, slotRu = "Пояс", kind = "drop", dungeon = "Вершина Черной горы (нижняя)", boss = "Аррок Смертный Вопль",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 22232 } },
		{ id = 15062, slotRu = "Ноги", kind = "craft", boe = true, reqLevel = 55,
			prof = "Кожевничество", skill = 290, pattern = 15772,
			patternSource = "слизни Glutinous, Primal, Cloned и Muculent Ooze, 0.9–1.1% (данные Classic); выкройка требует специализации «Кожевничество: традиции предков»",
			reagents = { { 8170, 30 }, { 15417, 14 }, { 15407, 1 }, { 14341, 1 } },
			note = "Сет с Devilsaur Gauntlets: 2 вещи дают +2% хита — носить только парой.",
			atlas = { module = "AtlasLootClassic_Crafting", spell = 19097 } },
		{ id = 13967, slotRu = "Ступни", kind = "drop", dungeon = "Некроситет", boss = "Киртонос Глашатай",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 13967 } },
		{ id = 272408, slotRu = "Палец 1", kind = "vendor", npc = NPC.pix, costItem = { 226404, 75 },
			reqLevel = 60, note = "Реалы падают раз в день с боссов подземелий 55+." },
		{ id = 18500, slotRu = "Палец 2", kind = "drop", dungeon = "Забытый Город (Север)", boss = "Приношения Гордока",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 18500 } },
		{ id = 13965, slotRu = "Аксессуар 1", kind = "quest", quest = "За Орду!", questId = 4974, npc = NPC.thrall, reqLevel = 55,
			note = "Нужна голова Вождя Ренда Чернорука (Вершина Черной горы, верхняя).",
			atlas = { module = "AtlasLootClassic_DungeonsAndRaids", npc = 10429 } },
		{ id = 280065, slotRu = "Аксессуар 2", kind = "drop", dungeon = "Крепость Черночревов", boss = "Исполин Чёрной Пасти",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 280065 } },
		-- Peacemaker instead of Bear Poking Stick 274419 (user 2026-11-17): the stick needs Barkskin Burrow Revered,
		-- ~1030 Deadwood Tribal Beads (~2000 kills, conquestcapped Barkskin guide), for 0.35 DPS more in the model
		-- (tools/preraid/rescore, set A, raid boss).
		{ id = 18725, slotRu = "Двуручное", kind = "drop", dungeon = "Стратхольм", boss = "Мировой судья Бартилас",
			reqLevel = 54, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", npc = 10435 } },
		{ id = 13023, slotRu = "Дальний бой", kind = "world", boe = true, reqLevel = 58,
			note = "Чаще всего: Колосс Зоры (Силитус) и арена Забытого Города (данные Classic)." },
	},
}
```

## Данные окна: вариант A (`Game/PreRaidData.lua` на коммите 40beb7b)

Строки об источниках крафта (откуда реагенты и номера выкроек, где выкройка падает или продаётся) приведены к DB2 клиента и foreverdb.net, как в `Game/PreRaidData.lua` (2026-11-21); остальное — как в том коммите.

```lua
-- The best pre-raid set for the BM hunter on WoW Forever (variant A of
-- docs/research/preraid-bis-60.md: with the Exalted battleground reputations; hit cap 8%).
-- Sources of every fact are in that file. Names in Russian:
--   NPCs: warcraft-forever.ru (ru client data).
--   Quests: wow-pilot.cc ?lang=ru. Factions: client DB2 Faction ruRU. Dungeons: client AreaTable ruRU.
--   Bosses: AtlasLoot Forever ruRU locale; Blackmaw Behemoth: ForeverGuide NewDungeonData.
--   Coordinates: warcraft-forever.ru / wow-pilot / classic-wow.com / icy-veins db; uiMapIDs: client UiMap.
-- Reagents and pattern ids of crafts: client DB2 (SpellReagents; ItemEffect / ItemXItemEffect), build 1.60.1.70888.
-- Pattern sources: foreverdb.net item pages.
-- costItem ids (Tarnished Undermine Real 226404): client DB2 ItemSparse.
-- atlas = where AtlasLoot lists it: { module, item | spell | npc } (found at click time).
local _, ns = ...

local NPC = {
	creeg   = { name = "Криг Ботмяс", map = 1413, x = 65.0, y = 34.6, zoneRu = "Степи" },
	kelm    = { name = "Кельм Харгюнт", map = 1413, x = 46.6, y = 8.4, zoneRu = "Степи" },
	jekyll  = { name = "Джекилл Флендринг", map = 1416, x = 62.8, y = 59.3, zoneRu = "Альтеракские горы" },
	pix     = { name = "Пикс Ксиззикс", map = 1434, x = 28.4, y = 75.8, zoneRu = "Тернистая долина (Пиратская бухта)" },
	thrall  = { name = "Тралл", map = 1454, x = 31.7, y = 37.8, zoneRu = "Оргриммар" },
	taelan  = { name = "Верховный лорд Телан Фордринг", map = 1422, x = 42.0, y = 14.8, zoneRu = "Западные Чумные земли" },
	board   = { name = "доска «Call to Arms!» у Старейшины племени Сломанного Клыка", map = 1425, x = 79.1, y = 79.0, zoneRu = "Внутренние земли" },
}

ns.PreRaidData = {
	items = {
		{ id = 252605, slotRu = "Голова", kind = "craft", boe = true, reqLevel = 56,
			prof = "Кожевничество", skill = 300, pattern = 252939,
			patternSource = "источник выкройки не найден",
			reagents = { { 8170, 20 }, { 15416, 40 }, { 12810, 12 }, { 15407, 4 }, { 249429, 10 }, { 14341, 2 }, { 248825, 20 } },
			atlas = { module = "AtlasLootClassic_Crafting", spell = 1254968 } },
		{ id = 15411, slotRu = "Шея", kind = "quest", quest = "Во сне", questId = 5944, npc = NPC.taelan, reqLevel = 52,
			note = "Это последний квест цепочки. Она начинается с «Псы-демоны» (5542) у Тириона Фордринга (Восточные Чумные земли 5.2, 35.6); один шаг в Стратхольме." },
		{ id = 272105, slotRu = "Плечи", kind = "rep", faction = "Налетчики Черного Копья", factionId = 2798, standing = 8,
			npc = NPC.creeg, cost = "~16з", reqLevel = 60,
			note = "Репутация — поле боя Острова Черного Копья. Кольчужная версия с теми же статами: Darkspear Epaulets (272106)." },
		{ id = 13340, slotRu = "Спина", kind = "drop", dungeon = "Стратхольм", boss = "Барон Ривендер",
			reqLevel = 58, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 13340 } },
		{ id = 252483, slotRu = "Грудь", kind = "craft", boe = true, reqLevel = 56,
			prof = "Кожевничество", skill = 300, pattern = 252892,
			patternSource = "неизвестно ни одному сайту",
			reagents = { { 12810, 6 }, { 12809, 10 }, { 7080, 20 }, { 249429, 10 }, { 15407, 4 }, { 14341, 10 }, { 248825, 20 } },
			atlas = { module = "AtlasLootClassic_Crafting", spell = 1255015 } },
		{ id = 18296, slotRu = "Запястья", kind = "trash", dungeon = "Забытый Город (Восток)", boss = "треш", boe = true,
			note = "Падает с сатиров Wildspawn, редко (данные Classic).",
			reqLevel = 51, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 18296 } },
		{ id = 272099, slotRu = "Кисти рук", kind = "rep", faction = "Налетчики Черного Копья", factionId = 2798, standing = 8,
			npc = NPC.creeg, reqLevel = 60 },
		{ id = 22232, slotRu = "Пояс", kind = "drop", dungeon = "Вершина Черной горы (нижняя)", boss = "Аррок Смертный Вопль",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 22232 } },
		{ id = 22673, slotRu = "Ноги", kind = "rep", faction = "Всадники Песни Войны", factionId = 889, standing = 8,
			npc = NPC.kelm, cost = "~25з", reqLevel = 60,
			note = "Ранг «Превознесение» — данные Classic, в Forever не подтверждён.",
			atlas = { module = "AtlasLootClassic_PvP", item = 22673 } },
		{ id = 13967, slotRu = "Ступни", kind = "drop", dungeon = "Некроситет", boss = "Киртонос Глашатай",
			reqLevel = 56, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", item = 13967 } },
		{ id = 19325, slotRu = "Палец 1", kind = "rep", faction = "Клан Северного Волка", factionId = 729, standing = 8,
			npc = NPC.jekyll, cost = "~75з", reqLevel = 55,
			note = "Ранг «Превознесение» — данные Classic, в Forever не подтверждён. Второй продавец — Grunnda Wolfheart внутри Альтеракской долины.",
			atlas = { module = "AtlasLootClassic_PvP", item = 19325 } },
		{ id = 272408, slotRu = "Палец 2", kind = "vendor", npc = NPC.pix, costItem = { 226404, 75 },
			reqLevel = 60, note = "Реалы падают раз в день с боссов подземелий 55+." },
		{ id = 13965, slotRu = "Аксессуар 1", kind = "quest", quest = "За Орду!", questId = 4974, npc = NPC.thrall, reqLevel = 55,
			note = "Нужна голова Вождя Ренда Чернорука (Вершина Черной горы, верхняя).",
			atlas = { module = "AtlasLootClassic_DungeonsAndRaids", npc = 10429 } },
		{ id = 19120, slotRu = "Аксессуар 2", kind = "quest", quest = "Требуется: капитан стражи в деревню Сломанного Клыка",
			questId = 7862, npc = NPC.board, npcRole = "Взять",
			note = "Сдать Старейшине племени Сломанного Клыка (78.2, 81.2)." },
		-- Peacemaker instead of Bear Poking Stick 274419 (user 2026-11-17): the stick needs Barkskin Burrow Revered,
		-- ~1030 Deadwood Tribal Beads (~2000 kills, conquestcapped Barkskin guide), for 0.35 DPS more in the model
		-- (tools/preraid/rescore, set A, raid boss).
		{ id = 18725, slotRu = "Двуручное", kind = "drop", dungeon = "Стратхольм", boss = "Мировой судья Бартилас",
			reqLevel = 54, atlas = { module = "AtlasLootClassic_DungeonsAndRaids", npc = 10435 } },
		{ id = 13023, slotRu = "Дальний бой", kind = "world", boe = true, reqLevel = 58,
			note = "Чаще всего: Колосс Зоры (Силитус) и арена Забытого Города (данные Classic)." },
	},
}
```
