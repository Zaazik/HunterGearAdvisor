-- Tooltip line parser: turns item tooltip lines into stats.
-- Patterns are built from the client's own localized templates (passed in), so the
-- same code reads ruRU and enUS tooltips. Pure Lua 5.1: no WoW API here.
--
-- A line is { left = "text", right = "text" or nil, leftRed = bool, rightRed = bool }.

local _, ns = ...
local Parse = {}
ns.Parse = Parse

-- Which template gives which stat. "pct" stats are in percent; "rating" templates are
-- converted with the Forever flat rating table (10 hit / 14 crit / 10 haste / 10 expertise per 1%).
local STAT_TEMPLATES = {
	{ key = "ITEM_MOD_AGILITY", stat = "AGI" },
	{ key = "ITEM_MOD_STRENGTH", stat = "STR" },
	{ key = "ITEM_MOD_STAMINA", stat = "STA" },
	{ key = "ITEM_MOD_INTELLECT", stat = "INT" },
	{ key = "ITEM_MOD_SPIRIT", stat = "SPI" },
	{ key = "ITEM_MOD_HEALTH", stat = "HEALTH" },
	{ key = "ITEM_MOD_MANA", stat = "MANA" },
	{ key = "TOOLTIP_ITEM_STAT_HIT_PERCENT_INCREASE", stat = "HIT" },
	{ key = "TOOLTIP_ITEM_STAT_HIT_PERCENT_DECREASE", stat = "HIT", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_CRIT_PERCENT_INCREASE", stat = "CRIT" },
	{ key = "TOOLTIP_ITEM_STAT_CRIT_PERCENT_DECREASE", stat = "CRIT", negate = true },
	-- haste rating (ItemSparse stat type 36, 10 rating a 1%, docs/research/R1-forever-ruleset.md section 2.1): the tooltip
	-- line "Equip: Increases your attack speed and casting speed by N%" states its percent; HASTE_RATING, which wowsims gives
	-- the hunter's own attacks alone (sim/core/unit.go:564-566 hasteRatingMultiplier, on the owner's totals; the pet and the
	-- hawks inherit speed multipliers, not the rating: sim/core/pet.go:381-431), unlike an enchant's aura 342 (HASTE, the
	-- attack speed enchants below)
	{ key = "TOOLTIP_ITEM_STAT_HASTE_PCT_INCREASE", stat = "HASTE_RATING" },
	{ key = "TOOLTIP_ITEM_STAT_HASTE_PCT_DECREASE", stat = "HASTE_RATING", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_EXPERTISE_PCT_INCREASE", stat = "EXPERTISE" },
	{ key = "TOOLTIP_ITEM_STAT_EXPERTISE_PCT_DECREASE", stat = "EXPERTISE", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_ATTACK_POWER_INCREASE", stat = "AP" },
	{ key = "TOOLTIP_ITEM_STAT_ATTACK_POWER_DECREASE", stat = "AP", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_RANGED_ATTACK_POWER_INCREASE", stat = "RAP" },
	{ key = "TOOLTIP_ITEM_STAT_RANGED_ATTACK_POWER_DECREASE", stat = "RAP", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_MANA_REGEN_INCREASE", stat = "MP5" },
	{ key = "TOOLTIP_ITEM_STAT_MANA_REGEN_DECREASE", stat = "MP5", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_HEALTH_REGEN_INCREASE", stat = "HP5" },
	{ key = "TOOLTIP_ITEM_STAT_DEFENSE_INCREASE", stat = "DEFENSE" },
	{ key = "TOOLTIP_ITEM_STAT_ARMOR_PENETRATION_INCREASE", stat = "ARMOR_PEN" },
	{ key = "TOOLTIP_ITEM_STAT_SPELL_POWER_INCREASE", stat = "SPELL_POWER" },
	{ key = "TOOLTIP_ITEM_STAT_SPELL_DAMAGE_INCREASE", stat = "SPELL_POWER" },
	{ key = "TOOLTIP_ITEM_STAT_SPELL_HEALING_INCREASE", stat = "SPELL_POWER" },
	-- ranged weapon skill ("Если на персонаже: повышение навыка владения луком на 3.")
	{ key = "TOOLTIP_ITEM_STAT_SKILL_BOWS_INCREASE", stat = "SKILL_BOWS" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_BOWS_DECREASE", stat = "SKILL_BOWS", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_GUNS_INCREASE", stat = "SKILL_GUNS" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_GUNS_DECREASE", stat = "SKILL_GUNS", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_CROSSBOWS_INCREASE", stat = "SKILL_CROSSBOWS" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_CROSSBOWS_DECREASE", stat = "SKILL_CROSSBOWS", negate = true },
	-- melee weapon skill (GlobalStrings 59290-59309: enUS "Equip: Increased Swords +%1$d." / "Equip: Decreased Swords
	-- -%1$d.", ruRU "Если на персонаже: повышение навыка владения мечом на %1$d." / "...понижение..."; Forever DB2 build
	-- 70888, db2_R3-core-formulas and db2_ru GlobalStrings.csv): SKILL_<LINE>, Score.MELEE_SKILL's keys
	{ key = "TOOLTIP_ITEM_STAT_SKILL_SWORDS_INCREASE", stat = "SKILL_SWORDS" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_SWORDS_DECREASE", stat = "SKILL_SWORDS", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_MACES_INCREASE", stat = "SKILL_MACES" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_MACES_DECREASE", stat = "SKILL_MACES", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_AXES_INCREASE", stat = "SKILL_AXES" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_AXES_DECREASE", stat = "SKILL_AXES", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_FIST_WEAPONS_INCREASE", stat = "SKILL_FIST" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_FIST_WEAPONS_DECREASE", stat = "SKILL_FIST", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_DAGGERS_INCREASE", stat = "SKILL_DAGGERS" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_DAGGERS_DECREASE", stat = "SKILL_DAGGERS", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_STAVES_INCREASE", stat = "SKILL_STAVES" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_STAVES_DECREASE", stat = "SKILL_STAVES", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_TWO-HANDED_SWORDS_INCREASE", stat = "SKILL_2H_SWORDS" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_TWO-HANDED_SWORDS_DECREASE", stat = "SKILL_2H_SWORDS", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_TWO-HANDED_MACES_INCREASE", stat = "SKILL_2H_MACES" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_TWO-HANDED_MACES_DECREASE", stat = "SKILL_2H_MACES", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_TWO-HANDED_AXES_INCREASE", stat = "SKILL_2H_AXES" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_TWO-HANDED_AXES_DECREASE", stat = "SKILL_2H_AXES", negate = true },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_POLEARMS_INCREASE", stat = "SKILL_POLEARMS" },
	{ key = "TOOLTIP_ITEM_STAT_SKILL_POLEARMS_DECREASE", stat = "SKILL_POLEARMS", negate = true },
	-- older "rating" wording, kept in case some items still use it
	{ key = "ITEM_MOD_HIT_RATING", stat = "HIT", rating = 10 },
	-- the ranged hit rating (GlobalStrings 16385 ITEM_MOD_HIT_RANGED_RATING: enUS "Improves ranged hit by %s.", ruRU
	-- "Меткость (оруж. дальн. боя) +%s."): the hit of the ranged attacks alone, RANGED_HIT (see EXTRA_STAT_PATTERNS)
	{ key = "ITEM_MOD_HIT_RANGED_RATING", stat = "RANGED_HIT", rating = 10 },
	{ key = "ITEM_MOD_CRIT_RATING", stat = "CRIT", rating = 14 },
	{ key = "ITEM_MOD_HASTE_RATING", stat = "HASTE_RATING", rating = 10 },
	{ key = "ITEM_MOD_EXPERTISE_RATING", stat = "EXPERTISE", rating = 10 },
	{ key = "ITEM_MOD_ATTACK_POWER", stat = "AP" },
	{ key = "ITEM_MOD_RANGED_ATTACK_POWER", stat = "RAP" },
	{ key = "ITEM_MOD_MANA_REGENERATION", stat = "MP5" },
	{ key = "ITEM_MOD_HEALTH_REGEN", stat = "HP5" },
	{ key = "ITEM_MOD_DEFENSE_SKILL_RATING", stat = "DEFENSE" },
	{ key = "ARMOR_TEMPLATE", stat = "ARMOR" },
	{ key = "AMMO_DAMAGE_TEMPLATE", stat = "AMMO_DPS" },
	{ key = "DPS_TEMPLATE", stat = "DPS" },
}

-- enUS enchant names use "Stat +N" ("Agility +5", "Stamina +3 and Armor +24"):
-- reversed patterns are built from these short names.
local SHORT_NAMES = {
	ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_STAMINA_SHORT = "STA",
	ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", RESISTANCE0_NAME = "ARMOR",
}

-- Attack power against creature types, a spell text, not a GlobalString: the equip spells of aura 102 + 131
-- (A_MOD_MELEE_ATTACK_POWER_VERSUS and A_MOD_RANGED_ATTACK_POWER_VERSUS of one creature-type mask, bit 1 << (type - 1):
-- 1 Beast, 2 Dragonkin, 4 Demon, 8 Elemental, 16 Giant, 32 Undead, 64 Humanoid, 256 Mechanical; wowsims
-- sim/core/spelldata/mob_types.go:32-55), whose Spell descriptions (Forever DB2 build 70888: db2 Spell.csv enUS, db2_ru
-- Spell.csv ruRU) the tooltip's equip line shows with the amount filled in. Each pattern captures the amount and names
-- the types; a match adds AP_VS_<TYPE> for each type it names, and with ap also plain attack power (AP): the two
-- "doubled" texts, whose spells add aura 99 + 124 attack power of the same amount as well (1318938: SpellEffect
-- 1352636-1352639; 1319047: 1352807-1352810). A line with another type word matches none and stays an equip effect
-- "not counted". The trailing period of a description is optional, as the templates' (Parse.TemplateToPattern).
local CREATURE_AP_PATTERNS = {
	{ pat = "^%+(%d+) к силе атаки против животных%.?$", types = { "BEAST" } },                     -- 13492
	{ pat = "^%+(%d+) Attack Power against Beasts%.?$", types = { "BEAST" } },
	{ pat = "^%+(%d+) к силе атаки против драконов%.?$", types = { "DRAGONKIN" } },                 -- 24291
	{ pat = "^%+(%d+) Attack Power against Dragonkin%.?$", types = { "DRAGONKIN" } },
	{ pat = "^%+(%d+) к силе атаки против демонов%.?$", types = { "DEMON" } },                      -- 12822
	{ pat = "^%+(%d+) Attack Power against Demons%.?$", types = { "DEMON" } },
	{ pat = "^%+(%d+) к силе атаки против элементалей%.?$", types = { "ELEMENTAL" } },              -- 22836
	{ pat = "^%+(%d+) Attack Power against Elementals%.?$", types = { "ELEMENTAL" } },
	{ pat = "^Увеличение силы атаки против великанов на (%d+) ед%.?$", types = { "GIANT" } },       -- 21937
	{ pat = "^%+(%d+) Attack Power against Giants%.?$", types = { "GIANT" } },
	{ pat = "^%+(%d+) к силе атаки против нежити%.?$", types = { "UNDEAD" } },                      -- 12981
	{ pat = "^%+(%d+) Attack Power against Undead%.?$", types = { "UNDEAD" } },
	{ pat = "^%+(%d+) к силе атаки против гуманоидов%.?$", types = { "HUMANOID" } },                -- 1292025
	{ pat = "^%+(%d+) Attack Power against Humanoids%.?$", types = { "HUMANOID" } },
	{ pat = "^Увеличивает силу атаки против механизмов на (%d+)%.?$", types = { "MECHANICAL" } },   -- 435360
	{ pat = "^%+(%d+) Attack Power against Mechanical units%.?$", types = { "MECHANICAL" } },
	-- the Argent Dawn texts, which go on after the amount (mask 36 Undead + Demon: 29112, 1219521; mask 32: 23930)
	{ pat = "^Повышает силу атаки против нежити и демонов на (%d+)%. Также позволяет", types = { "UNDEAD", "DEMON" } },
	{ pat = "^%+(%d+) Attack Power against Undead and Demons%.%s+Allows", types = { "UNDEAD", "DEMON" } },
	{ pat = "^Повышает силу атаки в бою против нежити и демонов на (%d+)%. Также позволяет", types = { "UNDEAD", "DEMON" } },
	{ pat = "^%+(%d+) Attack Power when fighting Undead and Demons%.%s+It also allows", types = { "UNDEAD", "DEMON" } },
	{ pat = "^Повышает силу атаки против нежити на (%d+)%. Также позволяет", types = { "UNDEAD" } },
	{ pat = "^%+(%d+) Attack Power against Undead%.%s+Allows", types = { "UNDEAD" } },
	-- "doubled against": Counterattack Lodestone 18537 (1318938, Mechanical) and item 273817 (1319047, Undead)
	{ pat = "^%+(%d+) к силе атаки%. Бонус удваивается против механизмов%.?$", types = { "MECHANICAL" }, ap = true },
	{ pat = "^%+(%d+) Attack Power, doubled against Mechanical units%.?$", types = { "MECHANICAL" }, ap = true },
	{ pat = "^%+(%d+) к силе атаки%. Бонус удваивается против нежити%.?$", types = { "UNDEAD" }, ap = true },
	{ pat = "^%+(%d+) Attack Power, doubled against Undead targets%.?$", types = { "UNDEAD" }, ap = true },
}

-- Spell texts (enchants, equip effects) that are plain stats but have no GlobalString.
-- Each pattern has one capture = the amount (or a fixed amount, when the text states none); sign gives its
-- direction; stats lists the keys of a text that gives one amount to several.
local EXTRA_STAT_PATTERNS = {
	{ pat = "^%+(%d+) к броне$", stat = "ARMOR" },   -- ruRU enchant "+24 к броне", seen in game
	{ pat = "^%-(%d+) к броне$", stat = "ARMOR", sign = -1 },
	{ pat = "^%+(%d+) [Aa]rmor$", stat = "ARMOR" },
	-- ranged scopes: Forever SpellItemEnchantment 30/32/33/663/664 ("Прицел (+5 к урону)")
	{ pat = "^Прицел %(%+(%d+) к урону%)$", stat = "RANGED_FLAT" },
	{ pat = "^Scope %(%+(%d+) Damage%)$", stat = "RANGED_FLAT" },
	-- Ranged-only hit, RANGED_HIT: the hit of the ranged attacks alone. Score.SetValue prices it at W.RANGED_HIT up to
	-- the cap, the hit of the shots, the pet and the hawks (Model.Parts rangedGearHit; wowsims sim/hunter/pets.go:155-158
	-- inheritedHit gives the pet and the hawks the owner's physical and ranged-only hit), never the hunter's melee.
	-- - the hit scopes SpellItemEnchantment 2523 (ruRU "+3% к рейтингу меткости", enUS "+3% Hit") and 8057 (ruRU
	--   "Птичий прицел (+3% к вероятности попадания)", enUS "Poultry Precision Scope (+3% Hit)") apply spell 22780: aura
	--   54 A_MOD_HIT_CHANCE bp 3 on the caster (SpellEffect 698524), bound to ranged weapons (SpellEquippedItems 181192:
	--   item class 2, subclass mask 262156, bows, guns and crossbows); 8057's second effect 1236217 is aura 4, a dummy.
	--   wowsims folds such an aura into the RangedHitPercent pseudo-stat (tools/database/dbc/util.go:356-373,
	--   tools/database/equip_pseudo_stats_test.go:88-105 for 2523). No other SpellItemEnchantment name of either export is
	--   "+N% к рейтингу меткости" or "+N% Hit" alone;
	{ pat = "^%+(%d+)%% к рейтингу меткости$", stat = "RANGED_HIT" },
	{ pat = "^%+(%d+)%% [Hh]it$", stat = "RANGED_HIT" },
	{ pat = "^Птичий прицел %(%+(%d+)%% к вероятности попадания%)$", stat = "RANGED_HIT" },
	{ pat = "^Poultry Precision Scope %(%+(%d+)%% Hit%)$", stat = "RANGED_HIT" },
	-- - the item equip spells of the same aura: 1294769 (SpellEffect 1316376, aura 54 bp 1; SpellEquippedItems 256232:
	--   class 2, subclass mask 262156) of Marksman Bands 18296, Sash of the Grand Hunt 22207, Stoneshatter 18388 and
	--   Infernal Trickster Leggings 17754, and 22780, 1301125, 1301127, whose descriptions read enUS "Improves your chance
	--   to hit with ranged weapons by ${$s1}.1%." (db2 Spell.csv 1294769, 22780), ruRU "Повышает вероятность попадания в
	--   дальнем бою на ${$s1}.1%." (db2_ru Spell.csv): one decimal, read with the client's decimal separator (MatchOne).
	{ pat = "^Повышает вероятность попадания в дальнем бою на ([%d%.,]+)%%$", stat = "RANGED_HIT" },
	{ pat = "^Improves your chance to hit with ranged weapons by ([%d%.,]+)%%$", stat = "RANGED_HIT" },
	-- crit scope: SpellItemEnchantment 8720 "+2% Crit" / ruRU "+2% к вероятности критического удара" (spell
	-- 1310308, aura 290 A_MOD_CRIT_PCT bp 2; SpellEquippedItems 256731: item class 2, subclass mask 262156, bows,
	-- guns and crossbows, so ranged attacks only; applied by 1307050 SAF-T Ultra Precision Scope, whose
	-- SpellEquippedItems row asks for the same). CRIT_RANGED: Score prices it at W.CRIT_RANGED, the ranged crit
	-- alone (Model.Weights). The same ruRU wording is SpellItemEnchantment 7664 (spell 1220596: aura 52, no item
	-- restriction), applied only by 1220623 Enchant Shield - Critical Strike (SpellEquippedItems: item class 4,
	-- InventoryType mask 16384, shields), and a shield is never scored (Score.Evaluate).
	{ pat = "^%+(%d+)%% к вероятности критического удара$", stat = "CRIT_RANGED" },
	{ pat = "^%+(%d+)%% [Cc]rit$", stat = "CRIT_RANGED" },
	-- Beastslaying: SpellItemEnchantment 249 "Beastslaying +2" / 853 "Beastslaying +6" (ruRU "+2 к убийству
	-- животных"), spells 7784 / 13650: aura 59 A_MOD_DAMAGE_DONE_CREATURE, misc 1 = Beasts. Flat damage per hit
	-- against beasts; Score.SetValue prices it.
	{ pat = "^%+(%d+) к убийству животных$", stat = "BEAST_SLAYING" },
	{ pat = "^Beastslaying %+(%d+)$", stat = "BEAST_SLAYING" },
	-- Attack speed enchants: every Forever SpellItemEnchantment row (build 70888; enUS Name_lang from the
	-- db2_V3-verify-gear-weights export, ruRU from the db2_ru export, the text the tooltip's enchant line shows) whose
	-- equip spell is an attack speed aura on the wearer (SpellEffect Effect 6 APPLY_AURA, ImplicitTarget 1), by the
	-- scope of its aura (Model.Parts p fields):
	-- - 931 "Haste +1%" / "+1% к скорости": spell 13928 Minor Haste, aura 342 bp 1 (and aura 65, casting speed, bp 1):
	--   HASTE. Applied by 13948 Enchant Gloves - Minor Haste (SpellEquippedItems 176220: item class 4, InventoryType
	--   mask 1024, gloves) and 22106 QAEnchant Gloves +1% Haste (181311: the same).
	-- - 34 "Counterweight +3% Attack Speed" / "Противовес (+3% к скорости атаки)": spell 7217 Weapon Counterweight, aura
	--   319 bp 3: MELEE_HASTE. Applied by 7218 (Iron Counterweight 6043; SpellEquippedItems 170914: item class 2,
	--   subclass mask 354: two-handed axes, maces and swords, polearms).
	-- - 2543 "Attack Speed +1%" / "+1% к скорости атаки": spell 22841 Arcanum of Rapidity, aura 319 bp 1 and aura 140
	--   bp 1: MELEE_HASTE and RANGED_HASTE. Applied by 22840 (Arcanum of Rapidity 18329; SpellEquippedItems 181984: item
	--   class 4, InventoryType mask 130, head and legs).
	-- - 7123 "Automatic Crowd Pummeler" / "Автоматический пробойник толпы": spell 432137, aura 319 bp 50, a text with
	--   no number: MELEE_HASTE 50. Applied by 432139 (ItemEffect 181780 of item 212546; SpellEquippedItems 252250: item
	--   class 4, InventoryType mask 8, shoulders).
	-- None of these spells has a SpellEquippedItems row of its own: the aura holds for every attack of its scope.
	{ pat = "^Haste %+(%d+)%%$", stat = "HASTE" },
	{ pat = "^%+(%d+)%% к скорости$", stat = "HASTE" },
	{ pat = "^Counterweight %+(%d+)%% Attack Speed$", stat = "MELEE_HASTE" },
	{ pat = "^Противовес %(%+(%d+)%% к скорости атаки%)$", stat = "MELEE_HASTE" },
	{ pat = "^Attack Speed %+(%d+)%%$", stats = { "MELEE_HASTE", "RANGED_HASTE" } },
	{ pat = "^%+(%d+)%% к скорости атаки$", stats = { "MELEE_HASTE", "RANGED_HASTE" } },
	{ pat = "^Automatic Crowd Pummeler$", stat = "MELEE_HASTE", amount = 50 },
	{ pat = "^Автоматический пробойник толпы$", stat = "MELEE_HASTE", amount = 50 },
	-- quiver / ammo pouch equip effect (spells 29413-29418, 14824-14829)
	{ pat = "^Увеличение скорости дальней атаки на (%d+)%%$", stat = "QUIVER_HASTE" },
	{ pat = "^Increases ranged attack speed by (%d+)%%$", stat = "QUIVER_HASTE" },
}

-- Equip effects known to do nothing for a hunter (shown as "no effect", not "not counted").
-- "Повышает силу зверя на N" = "Increases Feral Combat +N": druid-only weapon skill 3014
-- (Forever DB2 spell 1320726, SkillRaceClassInfo class mask 1024), seen in game 2026-11-12.
local USELESS_PATTERNS = {
	{ pat = "^Повышает силу зверя на", why = "навык друида (Feral Combat), хантеру ничего не даёт" },
	{ pat = "^Increases? Feral Combat", why = "druid-only Feral Combat skill" },
}

-- Damage range of a "Chance on hit" effect: only when the damage words follow the numbers,
-- so stat/armor debuff procs ("на 40 на 1 мин.") are not taken for damage. The damage's school as the words name it,
-- as the Forever DB2 Spell descriptions write it (db2 Spell.csv, db2_ru Spell.csv): ruRU "ед. урона от <the school>"
-- is magic, "ед. урона" and "ед. физического урона" (one optional word between "ед." and "урона", spells 13486, 18107 ...)
-- physical; enUS "<Arcane|Fire|Frost|Holy|Nature|Shadow> damage" magic, "damage" with no such word (none, "Physical")
-- physical. Items.Get prices a proc it finds no Game/ProcData.lua entry for by it (wowsims
-- sim/common/shared/shared_utils.go:76-90 damageDefenseType: no DefenseType, the melee table for the physical school,
-- the spell table for the others); tools/gen_proc_data.py checks the rule on the DB2 descriptions and lists those it
-- misreads (TEXT_SCHOOL_MISMATCHES). ru: the position after "урона"; en: the word before "damage".
local PROC_DAMAGE_PATTERNS = {
	{ pat = "(%d+)%s*%-%s*(%d+)%s+ед%.%s+[^%s%d]*%s*урона()", ru = true },
	{ pat = "от%s+(%d+)%s+до%s+(%d+)%s+ед%.%s+[^%s%d]*%s*урона()", ru = true },
	{ pat = "(%d+)%s*%-%s*(%d+)%s+(%a*)%s*[Dd]amage" },
	{ pat = "(%d+)%s+to%s+(%d+)%s+(%a*)%s*[Dd]amage" },
}
local MAGIC_SCHOOL_WORDS = { Arcane = true, Fire = true, Frost = true, Holy = true, Nature = true, Shadow = true }
-- A single damage amount in a proc text: a damage effect of Variance 0 shows one number where a range shows two (the
-- Forever DB2 Spell descriptions' "$s1", db2 Spell.csv / db2_ru Spell.csv: Demonshear 13348's Shadow Bolt 17483 "наносящей
-- $s1 ед. урона от темной магии и $s2 ед. урона раз в $t2 сек.", "causing $s1 Shadow damage and dealing $s2 damage every
-- $t2 sec"), the words after it as PROC_DAMAGE_PATTERNS reads them: ruRU "N ед. урона", "N ед. <word> урона"; enUS "N
-- damage", "N <word> damage". procDamage reads no such amount (it needs a range); Items.LinkProcs links an entry of a
-- fixed direct damage by it (Parse.StatesDamage).
local PROC_AMOUNT_PATTERNS = { "(%d+)%s+ед%.%s+[^%s%d]*%s*урона", "(%d+)%s+%a*%s*[Dd]amage" }

-- "Equip:" lines that are chance-on-hit damage: equip spells (ItemEffect TriggerType 1) that roll on the wearer's
-- attacks, as their Forever DB2 Spell descriptions read (build 70888, enUS Spell.csv and ruRU; spell ids below).
-- Heartseeking Crossbow 13040 is one (ItemEffect 99815, spell 29626). A line counts as a proc only with a damage
-- range (PROC_DAMAGE_PATTERNS); spell-cast triggers and "when struck" effects are not here (they do not roll on a
-- hunter's attacks). hits: which hits roll it — "ranged", "melee", "any" (melee and ranged), "weapon" (the hits
-- of the weapon that carries it, as a "Chance on hit:" line; every hit for a trinket). Left out, so they stay "not
-- counted": 15599 / 16982 ("on striking the enemy": which hits is not said, and 16982's ruRU text calls it a spell),
-- 1309322 (against Demons only), 1309550 (damage or Strength), 1311505 (damage to you or the target), 446389 (a
-- summon).
local EQUIP_PROC_PATTERNS = {
	{ pat = "^Chance to strike your ranged target", hits = "ranged" },                  -- 29625, 29626
	{ pat = "^Шанс поразить дальнюю цель", hits = "ranged" },                           -- 29625
	{ pat = "^Шанс поразить отдаленную цель", hits = "ranged" },                        -- 29626
	{ pat = "^Chance on ranged hit to", hits = "ranged" },                              -- 1214143
	{ pat = "^Атаки дальнего боя могут нанести", hits = "ranged" },                     -- 1214143
	{ pat = "^Chance to strike your melee target", hits = "melee" },                    -- 23686, 1213417
	{ pat = "^Вероятность поражения вашей цели в ближнем бою", hits = "melee" },        -- 23686
	{ pat = "^С некоторой вероятностью поражает цель в ближнем бою", hits = "melee" },  -- 1213417
	{ pat = "^Chance to bathe your melee target", hits = "melee" },                     -- 462385
	{ pat = "^Дается шанс поджечь выбранную вами цель в ближнем бою", hits = "melee" }, -- 462385
	{ pat = "^Chance to decapitate the target on a melee swing", hits = "melee" },      -- 25669, 467819
	{ pat = "^Шанс обезглавить цель при ближней атаке", hits = "melee" },               -- 25669
	{ pat = "^Атаки ближнего боя с некоторой вероятностью", hits = "melee" },           -- 467819, 1231258
	{ pat = "^Chance on melee attack to", hits = "melee" },                             -- 1231258
	{ pat = "^%d+%% chance of dealing .+ on a successful melee attack", hits = "melee" }, -- 9233
	{ pat = "^%d+%% вероятность на нанесение .+ при успешной атаке в ближнем бою", hits = "melee" }, -- 9233
	-- 1214125 rolls on direct spell damage too: a hunter's shots are not spells, so melee
	{ pat = "^Chance on direct spell damage or melee attack to", hits = "melee" },
	{ pat = "^Заклинания прямого действия и атаки ближнего боя могут нанести", hits = "melee" },
	{ pat = "^Melee and Ranged attacks have a chance to", hits = "any" },               -- 27656
	{ pat = "^Атаки в ближнем и дальнем бою с некоторой вероятностью", hits = "any" },  -- 27656
	{ pat = "^Chance to discharge electricity", hits = "weapon" },                      -- 29150, 1220536
	{ pat = "^Вероятность электрического разряда", hits = "weapon" },                   -- 29150
	{ pat = "^С некоторой вероятностью выпускает в вашу цель электрический разряд", hits = "weapon" }, -- 1220536
	{ pat = "^Chance on hit to", hits = "weapon" },                                     -- 1318159, 1291686
	{ pat = "^С некоторой вероятностью при попадании наносит", hits = "weapon" },       -- 1318159
	{ pat = "^Атаки с некоторой вероятностью наносят", hits = "weapon" },               -- 1291686
}

-- "Equip:" lines of a damage proc that fires on every hit it hears, which state no chance (raid-mode design 25.3): the
-- equip auras wowsims rolls at StatedChance 1 (ProcChanceAlways, an active "every time" registration of
-- sim/common/forever/stat_bonus_procs_auto_gen.go; Game/ProcData.lua always), as their Forever DB2 Spell descriptions read
-- (build 70888, enUS Spell.csv and ruRU, at their values: "$29502s1" is a range, "4" a number), with the hits their trigger's
-- mask names among Parse's (ProcTypeMask 64 ranged auto attacks: "ranged"; 20 the melee swings and abilities:
-- "melee", the main hand's alone for a linked aura of the main hand only, Game/ProcData.lua mainHand). A linked one rolls
-- on its mask (Score.ProcRate); the hits are an unlinked one's. Their damage a range (procDamage) or a single amount
-- (procAmount). Left out: 17495 Crest of Retribution (on a block: no hunter hit).
local ALWAYS_PROC_PATTERNS = {
	{ pat = "^Melee attacks with this weapon deal", hits = "melee" },                -- 1298413 Iceblade Hacker, 1298500 Warblade of Caer Darrow
	{ pat = "^Атаки этим оружием в ближнем бою наносят", hits = "melee" },           -- 1298413, 1298500
	{ pat = "^All ranged auto%-attacks conjure an icy bolt", hits = "ranged" },       -- 1316319 Hurricane
	{ pat = "^Автоатаки в дальнем бою призывают ледяные стрелы", hits = "ranged" },   -- 1316319
	{ pat = "^Thrown attacks explode on impact", hits = "ranged" },                   -- 1318069, 1318123 (thrown weapons)
	{ pat = "^Атаки метательным оружием вызывают взрывы", hits = "ranged" },          -- 1318069, 1318123
	{ pat = "^Adds %d+ %a+ damage to your weapon attack", hits = "melee" },           -- 7721 Fiery Plate Gauntlets
	{ pat = "^Атаки оружием наносят еще %d+ ед%. урона", hits = "melee" },            -- 7721
	{ pat = "^Adds %d+ %a+ damage to your melee attacks", hits = "melee" },           -- 7711, 16615, 1302248, 1294939
	{ pat = "^Повышение наносимого в ближнем бою урона", hits = "melee" },            -- 7711 Blazefury Medallion
	{ pat = "^Наделение оружия способностью наносить в атаках дополнительно", hits = "melee" }, -- 16615 Storm Gauntlets
	{ pat = "^Атаки ближнего боя также наносят", hits = "melee" },                    -- 1302248 Force Imbued Gauntlets, 1294939 Dreadfrost Saber
}
-- A single damage amount where a proc line puts the number after the damage words: 7711's ruRU "Повышение наносимого в
-- ближнем бою уронаот огня на $s1 ед." (db2_ru Spell.csv, "уронаот" as it stands there)
local AMOUNT_AFTER_PATTERN = "урона%s*от%s+[^%s%d]+%s+на%s+(%d+)%s+ед%."

-- Separators inside one line with several stats ("+3 к выносливости и +24 к броне").
local PART_SEPARATORS = { " и ", " and ", ", " }

-- Ordinary non-stat lines (binding, slot, crafter, ...): recognised so they are not reported
-- as "unparsed". Keys are GlobalStrings names; INVTYPE_* and ITEM_QUALITY*_DESC are exact texts.
Parse.INFO_KEYS = {
	"ITEM_BIND_ON_EQUIP", "ITEM_BIND_ON_PICKUP", "ITEM_BIND_ON_USE", "ITEM_BIND_QUEST", "ITEM_SOULBOUND",
	"ITEM_BIND_TO_ACCOUNT", "ITEM_BIND_TO_BNETACCOUNT", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND",
	"ITEM_UNIQUE", "ITEM_UNIQUE_EQUIPPABLE", "ITEM_UNIQUE_MULTIPLE", "ITEM_LIMIT_CATEGORY",
	"ITEM_LIMIT_CATEGORY_MULTIPLE", "ITEM_SET_NAME", "ITEM_CONJURED", "ITEM_STARTS_QUEST", "ITEM_CREATED_BY",
	"ITEM_WRAPPED_BY", "ITEM_READABLE", "ITEM_OPENABLE", "ITEM_HEROIC", "DAMAGE_TEMPLATE_WITH_SCHOOL",
	"CONTAINER_SLOTS", "ITEM_LEVEL", "ITEM_CLASSES_ALLOWED", "ITEM_RACES_ALLOWED", "ITEM_REQ_SKILL",
	"ITEM_MIN_SKILL", "ITEM_REQ_REPUTATION", "ITEM_RESIST_SINGLE", "ITEM_SPELL_CHARGES",
	"ITEM_DURATION_DAYS", "ITEM_COOLDOWN_TIME",
	-- shield block value ("Вероятность блока: 19"): a hunter cannot use shields
	"SHIELD_BLOCK_TEMPLATE",
}
-- Weapon damage lines: info only on the line that carries the weapon speed on the right,
-- otherwise "%s Damage" would swallow any "+N ... Damage" text.
Parse.WEAPON_DAMAGE_KEYS = { "DAMAGE_TEMPLATE", "SINGLE_DAMAGE_TEMPLATE" }
-- Lines that mark an item as unique-equipped (two copies cannot be worn).
local UNIQUE_EQUIPPED_KEYS = { "ITEM_UNIQUE_EQUIPPABLE", "ITEM_LIMIT_CATEGORY_MULTIPLE" }

-- Removes |cAARRGGBB ... |r colour codes.
function Parse.StripCodes(s)
	if not s then return s end
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Tooltip text can carry an unresolved plural marker (seen in game: "Сумка (10 |4ячейка:ячейки:ячеек;)"):
-- keep its first form, which is one of the variants the info patterns are built for.
local function resolvePlurals(s)
	if not s then return s end
	return (s:gsub("|4([^:;]*)[^;]*;", "%1"))
end

local function escapeMagic(s)
	return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

-- Turns a printf-style template into an anchored Lua pattern with captures.
-- Returns the pattern and the list of capture kinds ("sign" or "num").
function Parse.TemplateToPattern(template)
	local t = template:gsub("%.$", "") -- trailing period is optional (some Forever strings lack it)
	local kinds = {}
	local out = {}
	local i = 1
	local len = #t
	while i <= len do
		local c = t:sub(i, i)
		if c == "%" then
			-- %c, %s, %d, %1$d, %1$.1f, %.1f, %%
			local spec = t:match("^%%(%d*%$?%.?%d*[cdsfg%%])", i)
			if not spec then
				out[#out + 1] = "%%"
				i = i + 1
			else
				local conv = spec:sub(-1)
				if conv == "%" then
					out[#out + 1] = "%%"
				elseif conv == "c" then
					out[#out + 1] = "([%+%-])"
					kinds[#kinds + 1] = "sign"
				else
					out[#out + 1] = "([%d%.,]+)"
					kinds[#kinds + 1] = "num"
				end
				i = i + 1 + #spec
			end
		else
			-- copy literal run
			local j = t:find("%", i, true) or (len + 1)
			out[#out + 1] = escapeMagic(t:sub(i, j - 1))
			i = j
		end
	end
	return "^" .. table.concat(out) .. "%.?$", kinds
end

-- "|4a:b:c;" plural markers: one variant of the template per form.
local function expandPlurals(t)
	local a, b, forms = t:find("|4([^;]*);")
	if not a then return { t } end
	local out = {}
	for form in (forms .. ":"):gmatch("([^:]*):") do
		for _, rest in ipairs(expandPlurals(t:sub(b + 1))) do
			out[#out + 1] = t:sub(1, a - 1) .. form .. rest
		end
	end
	return out
end

-- Template with free text (%s = any text captured, %d = number) to anchored patterns,
-- one per plural form. Used for set bonus, enchant and info lines.
function Parse.TextTemplatePatterns(template)
	local pats = {}
	for _, variant in ipairs(expandPlurals(Parse.StripCodes(template))) do
		local t = variant:gsub("|3%-%d+%b()", "\1") -- grammatical case of an inserted word
		local out = {}
		local i, len = 1, #t
		while i <= len do
			local c = t:sub(i, i)
			if c == "\1" then
				out[#out + 1] = ".-"
				i = i + 1
			elseif c == "%" then
				local spec = t:match("^%%(%d*%$?%.?%d*[cdsfg%%])", i)
				if not spec then
					out[#out + 1] = "%%"; i = i + 1
				else
					local conv = spec:sub(-1)
					if conv == "s" then out[#out + 1] = "(.+)"
					elseif conv == "%" then out[#out + 1] = "%%"
					else out[#out + 1] = "[%d%.,%+%-]+" end
					i = i + 1 + #spec
				end
			else
				local j = t:find("[%%\1]", i) or (len + 1)
				out[#out + 1] = escapeMagic(t:sub(i, j - 1))
				i = j
			end
		end
		pats[#pats + 1] = "^" .. table.concat(out) .. "$"
	end
	return pats
end

function Parse.TextTemplateToPattern(template)
	return Parse.TextTemplatePatterns(template)[1]
end

function Parse.ToNumber(s, decimal)
	if not s then return nil end
	s = s:gsub("%s", "")
	if decimal and decimal ~= "." then
		-- in ruRU "," is the decimal separator and there is no thousands separator
		s = s:gsub(",", ".")
	else
		s = s:gsub(",", "")
	end
	return tonumber(s)
end

local function addPats(list, template)
	for _, p in ipairs(Parse.TextTemplatePatterns(template)) do list[#list + 1] = p end
end

-- Builds a parser from a template table T (keys = GlobalStrings names).
function Parse.New(T)
	local self = { T = T, decimal = T.DECIMAL_SEPERATOR or ".", stats = {}, reversed = {} }
	for _, def in ipairs(STAT_TEMPLATES) do
		local tpl = T[def.key]
		if tpl and tpl ~= "" then
			local pat, kinds = Parse.TemplateToPattern(tpl)
			self.stats[#self.stats + 1] = { pat = pat, kinds = kinds, def = def }
		end
	end
	for key, stat in pairs(SHORT_NAMES) do
		local name = T[key]
		if name and name ~= "" and not name:find("^к ") then -- ruRU short names are "к ловкости": no reversed form
			self.reversed[#self.reversed + 1] = { pat = "^" .. escapeMagic(name) .. " ([%+%-])(%d+)$", stat = stat }
		end
	end
	local function prefixPattern(key)
		local v = T[key]
		if v and v ~= "" then return "^" .. escapeMagic(v) .. "%s*" end
	end
	self.equipPrefix = prefixPattern("ITEM_SPELL_TRIGGER_ONEQUIP")
	self.procPrefix = prefixPattern("ITEM_SPELL_TRIGGER_ONPROC")
	self.usePrefix = prefixPattern("ITEM_SPELL_TRIGGER_ONUSE")
	if T.ENCHANTED_TOOLTIP_LINE then self.enchantPat = Parse.TextTemplateToPattern(T.ENCHANTED_TOOLTIP_LINE) end
	if T.ITEM_MIN_LEVEL then self.levelPat = Parse.TemplateToPattern(T.ITEM_MIN_LEVEL) end
	self.setPats = {}
	if T.ITEM_SET_BONUS then addPats(self.setPats, T.ITEM_SET_BONUS) end
	-- "(%d) Set: %s" / "Комплект (%d |4предмет:предмета:предметов;): %s"
	if T.ITEM_SET_BONUS_GRAY then addPats(self.setPats, T.ITEM_SET_BONUS_GRAY) end
	if T.DURABILITY_TEMPLATE then self.durabilityPat = Parse.TemplateToPattern(T.DURABILITY_TEMPLATE) end
	if T.SPEED then self.speedPat = "^" .. escapeMagic(T.SPEED) .. "%s+([%d%.,]+)$" end
	self.infoPats, self.infoExact, self.damagePats, self.uniquePats = {}, {}, {}, {}
	for _, key in ipairs(Parse.INFO_KEYS) do
		if T[key] and T[key] ~= "" then addPats(self.infoPats, T[key]) end
	end
	for _, key in ipairs(Parse.WEAPON_DAMAGE_KEYS) do
		if T[key] and T[key] ~= "" then addPats(self.damagePats, T[key]) end
	end
	for _, key in ipairs(UNIQUE_EQUIPPED_KEYS) do
		if T[key] and T[key] ~= "" then addPats(self.uniquePats, T[key]) end
	end
	for key, v in pairs(T) do
		if type(v) == "string" and (key:match("^INVTYPE_") or key:match("^ITEM_QUALITY%d_DESC$")) then
			self.infoExact[v] = true
		end
	end
	return setmetatable(self, { __index = Parse })
end

local function addStat(stats, key, value)
	stats[key] = (stats[key] or 0) + value
end

local function splitParts(text)
	local parts = { text }
	for _, sep in ipairs(PART_SEPARATORS) do
		local nextParts = {}
		for _, p in ipairs(parts) do
			local start = 1
			while true do
				local a, b = p:find(sep, start, true)
				if not a then
					nextParts[#nextParts + 1] = p:sub(start)
					break
				end
				nextParts[#nextParts + 1] = p:sub(start, a - 1)
				start = b + 1
			end
		end
		parts = nextParts
	end
	return parts
end

-- Average of the first damage range in a proc text and its school, "magic" or "physical" (PROC_DAMAGE_PATTERNS); nil
-- when it states none.
local function procDamage(text)
	for _, e in ipairs(PROC_DAMAGE_PATTERNS) do
		local lo, hi, after = text:match(e.pat)
		if lo then
			local magic
			if e.ru then magic = text:sub(after):match("^%s+от%s") ~= nil else magic = MAGIC_SCHOOL_WORDS[after] == true end
			return (tonumber(lo) + tonumber(hi)) / 2, magic and "magic" or "physical"
		end
	end
end

-- Whether a proc text states `amount` as a single damage amount (PROC_AMOUNT_PATTERNS), a whole number as the tooltip
-- shows it.
function Parse.StatesDamage(text, amount)
	for _, pat in ipairs(PROC_AMOUNT_PATTERNS) do
		for n in text:gmatch(pat) do
			if tonumber(n) == amount then return true end
		end
	end
	return false
end

-- The single damage amount of a proc text and its school (an always proc's line, ALWAYS_PROC_PATTERNS): the first of
-- PROC_AMOUNT_PATTERNS, ruRU "N ед. урона от <the school>" magic, "N ед. урона" physical, enUS "N <school> damage" magic
-- by MAGIC_SCHOOL_WORDS, else physical; or the number after "урона от <the school>" (AMOUNT_AFTER_PATTERN), magic; nil
-- when it states none.
local function procAmount(text)
	local n, rest = text:match("(%d+)%s+ед%.%s+[^%s%d]*%s*урона()")
	if n then return tonumber(n), text:sub(rest):match("^%s+от%s") and "magic" or "physical" end
	local m, word = text:match("(%d+)%s+(%a*)%s*[Dd]amage")
	if m then return tonumber(m), MAGIC_SCHOOL_WORDS[word] and "magic" or "physical" end
	local a = text:match(AMOUNT_AFTER_PATTERN)
	if a then return tonumber(a), "magic" end
end

-- The hits that roll an "Equip:" chance-on-hit line (EQUIP_PROC_PATTERNS); nil for any other equip text.
local function equipProcHits(body)
	for _, e in ipairs(EQUIP_PROC_PATTERNS) do
		if body:match(e.pat) then return e.hits end
	end
end
-- The hits of an "Equip:" line of a proc on every hit (ALWAYS_PROC_PATTERNS); nil for any other equip text.
local function alwaysProcHits(body)
	for _, e in ipairs(ALWAYS_PROC_PATTERNS) do
		if body:match(e.pat) then return e.hits end
	end
end

local function anyMatch(text, pats)
	for _, p in ipairs(pats) do
		if text:match(p) then return true end
	end
	return false
end

-- One stat in one piece of text: client templates first, then known spell-text forms. A captured amount is read with
-- the client's decimal separator (Parse.ToNumber), as the templates' are: the ranged hit's "1,0" in ruRU.
function Parse:MatchOne(text, stats)
	if self:MatchStat(text, stats) then return true end
	local t = text:gsub("%.$", "")
	for _, e in ipairs(EXTRA_STAT_PATTERNS) do
		local n = t:match(e.pat)
		if n then
			local amount = (e.sign or 1) * (e.amount or Parse.ToNumber(n, self.decimal))
			for _, key in ipairs(e.stats or { e.stat }) do addStat(stats, key, amount) end
			return true
		end
	end
	for _, e in ipairs(self.reversed) do
		local sign, n = t:match(e.pat)
		if sign then
			addStat(stats, e.stat, (sign == "-" and -1 or 1) * tonumber(n))
			return true
		end
	end
	return false
end

-- A line that may hold several stats ("+3 к выносливости и +24 к броне"). All parts must
-- parse, otherwise nothing is added (so a half-understood line is reported as unparsed).
function Parse:MatchMulti(text, stats)
	if self:MatchOne(text, stats) then return true end
	local parts = splitParts(text)
	if #parts < 2 then return false end
	local tmp = {}
	for _, p in ipairs(parts) do
		if not self:MatchOne(p, tmp) then return false end
	end
	for k, v in pairs(tmp) do addStat(stats, k, v) end
	return true
end

-- Tries every stat template on one text; returns true when something matched.
function Parse:MatchStat(text, stats)
	for _, entry in ipairs(self.stats) do
		local caps = { text:match(entry.pat) }
		if caps[1] then
			local sign, num = 1, nil
			for idx, kind in ipairs(entry.kinds) do
				if kind == "sign" then
					if caps[idx] == "-" then sign = -1 end
				elseif not num then
					num = Parse.ToNumber(caps[idx], self.decimal)
				end
			end
			if num then
				local def = entry.def
				if def.negate then sign = -sign end
				if def.rating then num = num / def.rating end
				addStat(stats, def.stat, sign * num)
				return true
			end
		end
	end
	return false
end

function Parse:IsInfo(text, right)
	if self.infoExact[text] then return true end
	if text:match('^".*"$') then return true end -- flavour text
	if right and anyMatch(text, self.damagePats) then return true end
	return anyMatch(text, self.infoPats)
end

-- Parses tooltip lines. Returns an item-stats record:
-- { stats = {...}, speed, reqLevel, restricted, restrictText, procs = { { avg, hits, equip, school } ... }, uniqueEquipped,
--   effects = {...}, unparsed = {...} }
-- procs: the damage procs, each its average damage, the school its words name ("magic" or "physical",
-- PROC_DAMAGE_PATTERNS) and the hits that roll it ("weapon" for a "Chance on hit:"
-- line, EQUIP_PROC_PATTERNS for an "Equip:" one); equip = true for a proc parsed from an "Equip:" line (an equip
-- aura, ItemEffect TriggerType 1: Heartseeking Crossbow 13040's ItemEffect 99815), absent for a "Chance on hit:" line
-- (ItemEffect TriggerType 2). Score.ProcRate reads it: a landed hit that deals no damage (Serpent Sting's
-- applications) rolls a weapon's chance-on-hit proc and never an equip aura's.
function Parse:Lines(lines)
	local res = { stats = {}, effects = {}, unparsed = {}, procs = {} }
	for i, line in ipairs(lines) do
		local text = resolvePlurals(Parse.StripCodes(line.left or ""))
		local right = resolvePlurals(Parse.StripCodes(line.right))
		local isLevelLine = self.levelPat and text:match(self.levelPat)
		if isLevelLine then
			res.reqLevel = Parse.ToNumber(isLevelLine, self.decimal)
		end
		local isDurability = self.durabilityPat and text:match(self.durabilityPat)
		if (line.leftRed and not isLevelLine and not isDurability) or line.rightRed then
			-- red text = something the player cannot use (weapon/armor type, class, profession)
			if i > 1 then
				res.restricted = true
				res.restrictText = res.restrictText or ((line.rightRed and right) or text)
			end
		end
		if anyMatch(text, self.uniquePats) then res.uniqueEquipped = true end

		if i == 1 or text == "" then
			-- item name / blank
		elseif isLevelLine or isDurability then
			-- handled above
		elseif anyMatch(text, self.setPats) then
			res.effects[#res.effects + 1] = { kind = "set", text = text }
		elseif self.procPrefix and text:match(self.procPrefix) then
			local avg, school = procDamage(text)
			local entry = { kind = "proc", text = text, hits = "weapon", avg = avg }
			if avg then res.procs[#res.procs + 1] = { avg = avg, hits = entry.hits, school = school } end
			res.effects[#res.effects + 1] = entry
		elseif self.usePrefix and text:match(self.usePrefix) then
			res.effects[#res.effects + 1] = { kind = "use", text = text }
		else
			local handled = false
			local inner, isEnchant = text, false
			if self.enchantPat then
				local e = text:match(self.enchantPat)
				if e then inner, isEnchant = e, true end
			end
			if self:MatchMulti(inner, res.stats) then
				handled = true
			elseif self.equipPrefix then
				local body = inner:gsub(self.equipPrefix, "", 1)
				if body ~= inner then
					for _, e in ipairs(CREATURE_AP_PATTERNS) do
						local n = body:match(e.pat)
						if n then
							local amount = tonumber(n)
							for _, t in ipairs(e.types) do addStat(res.stats, "AP_VS_" .. t, amount) end
							if e.ap then addStat(res.stats, "AP", amount) end
							handled = true
							break
						end
					end
					if not handled then
						for _, u in ipairs(USELESS_PATTERNS) do
							if body:match(u.pat) then
								res.effects[#res.effects + 1] = { kind = "useless", text = text, why = u.why }
								handled = true
								break
							end
						end
					end
					if not handled and self:MatchMulti(body, res.stats) then handled = true end
					if not handled then
						local hits = equipProcHits(body)
						local avg, school
						if hits then
							avg, school = procDamage(body)
						else
							-- a proc on every hit: its range, else its single amount (ALWAYS_PROC_PATTERNS)
							hits = alwaysProcHits(body)
							if hits then
								avg, school = procDamage(body)
								if not avg then avg, school = procAmount(body) end
							end
						end
						if avg then
							res.effects[#res.effects + 1] = { kind = "proc", text = text, avg = avg, hits = hits, equip = true }
							res.procs[#res.procs + 1] = { avg = avg, hits = hits, equip = true, school = school }
							handled = true
						end
					end
					if not handled then
						res.effects[#res.effects + 1] = { kind = "equip", text = text }
						handled = true
					end
				end
			end
			if right and self.speedPat then
				local sp = right:match(self.speedPat)
				if sp then res.speed = Parse.ToNumber(sp, self.decimal) end
			end
			-- an enchant line is never "just info": if it is not understood, report it
			if not handled and not isEnchant and self:IsInfo(text, right) then handled = true end
			-- only lines with a number can be a missed stat; other text is just description
			if not handled and text:find("%d") then res.unparsed[#res.unparsed + 1] = text end
		end
	end
	return res
end
