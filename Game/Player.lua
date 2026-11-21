-- Live player state: proficiencies, equipped set, bag weapons, model inputs.
local _, ns = ...
local P = {}
ns.Player = P

local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local AMMO_SLOT = 0

-- weapon subclass -> skill line (Forever SkillLine ids)
local WEAPON_SKILL = {
	[0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43, [8] = 55,
	[10] = 136, [13] = 473, [15] = 173, [16] = 176, [18] = 226, [19] = 228,
}
-- armor subclass -> skill line
local ARMOR_SKILL = { [1] = 415, [2] = 414, [3] = 413, [4] = 293, [6] = 433 }
local SKILL_NAME = {
	[44] = "Топоры", [172] = "Двуручные топоры", [45] = "Луки", [46] = "Ружья", [54] = "Дробящее оружие",
	[160] = "Двуручное дробящее", [229] = "Древковое оружие", [43] = "Мечи", [55] = "Двуручные мечи",
	[136] = "Посохи", [473] = "Кистевое оружие", [173] = "Кинжалы", [176] = "Метательное оружие",
	[226] = "Арбалеты", [228] = "Жезлы", [415] = "Ткань", [414] = "Кожа", [413] = "Кольчуга",
	[293] = "Латы", [433] = "Щиты",
}
-- What a hunter can learn at all (Forever SkillRaceClassInfo); used when the skill API is missing.
local HUNTER_SKILLS = {
	[44] = true, [172] = true, [45] = true, [46] = true, [229] = true, [43] = true, [55] = true,
	[136] = true, [473] = true, [173] = true, [176] = true, [226] = true, [415] = true, [414] = true,
}
local DUAL_WIELD_SKILL, DUAL_WIELD_SPELL, MAIL_SKILL, MAIL_SPELL = 118, 674, 413, 8737

-- Aspect of the Hawk ranks (spell ids) to know whether its RAP is already in the sheet value.
local ASPECT_HAWK = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }
-- Ranks taught by books, not the trainer (ItemSparse 21307 "Guide: Aspect of the Hawk VII",
-- 21306 "Guide: Serpent Sting IX")
local ASPECT_HAWK_BOOK, SERPENT_STING_BOOK = 25296, 25295

local AMMO_FOR_RANGED = { [2] = 2, [18] = 2, [3] = 3 } -- bow/crossbow -> arrows, gun -> bullets

function P.HasSkill(skillID)
	if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
		local info = C_SkillInfo.GetSkillLineInfoByID(skillID)
		if info then return (info.maxRank or 0) > 0 or (info.rank or 0) > 0 end
		return false
	end
	if skillID == MAIL_SKILL then return IsPlayerSpell(MAIL_SPELL) end
	return HUNTER_SKILLS[skillID] == true
end

-- Skill line of a weapon (WEAPON_SKILL by subclass), nil for an item that is not a weapon of a known type.
function P.WeaponSkillLine(item)
	if item.classID ~= 2 then return nil end
	return WEAPON_SKILL[item.subclassID]
end

-- Skill of a skill line as the Skills frame computes it: rank + modifier (Forever UI Camelot/SkillsFrame.lua:268,
-- AddWeaponSkillRows: weaponSkill = rank + modifier; Camelot/PaperDollFrameStats.lua:710 reads the worn weapon's
-- line with this same C_SkillInfo.GetSkillLineInfoByID; SkillLineAttributes rank and modifier are not nilable in
-- Blizzard_APIDocumentationGenerated/SkillInfoDocumentation.lua). nil when the call returns no info (its result,
-- skillLineAttributes, is Nilable = true in SkillInfoDocumentation.lua).
function P.SkillRank(skillLine)
	local info = C_SkillInfo.GetSkillLineInfoByID(skillLine)
	if not info then return nil end
	return info.rank + info.modifier
end

-- Whether the player's skill in a line (P.SkillRank: rank + modifier) reaches rank: an item set's profession
-- requirement (ItemSet RequiredSkill / RequiredSkillRank, Score.SetBonuses). The Forever UI source does not show
-- which rank the game compares with RequiredSkillRank; HGA takes the skill the Skills frame computes, the modifier
-- included.
function P.HasSkillRank(skillLine, rank)
	local have = P.SkillRank(skillLine)
	return have ~= nil and have >= rank
end

-- Weapon skill of a skill line (P.SkillRank). The modifier is the bonus on top of the trained rank the UI shows
-- as "rank (+modifier)"; HGA takes it to hold the worn gear's skill bonuses (equip spells with aura 30
-- A_MOD_SKILL, "Increased Bows +N"), which these UI files do not state. Only asked for a line the player has (a
-- usable weapon): no info is an error.
function P.WeaponSkill(skillLine)
	local skill = P.SkillRank(skillLine)
	if skill == nil then error("HunterGearAdvisor: no skill info for weapon skill line " .. tostring(skillLine), 2) end
	return skill
end

P.SKILL_NAME = SKILL_NAME

function P.DualWield()
	if P.HasSkill(DUAL_WIELD_SKILL) then return true end
	return IsPlayerSpell(DUAL_WIELD_SPELL)
end

-- Returns ok, reason. ok=false means no checkmark and the reason goes to the tooltip.
function P.CanUse(item, equippedRanged)
	if item.restricted then return false, item.restrictText end
	local loc = item.equipLoc
	if loc == "INVTYPE_THROWN" then return false, "метательное оружие отключает Auto Shot и все выстрелы" end
	if loc == "INVTYPE_SHIELD" then return false, "щиты хантеру недоступны" end
	if item.classID == 2 then
		local skill = WEAPON_SKILL[item.subclassID]
		if skill and not P.HasSkill(skill) then
			return false, "навык не изучен: " .. (SKILL_NAME[skill] or skill)
		end
	elseif item.classID == 4 then
		local skill = ARMOR_SKILL[item.subclassID]
		if skill and not P.HasSkill(skill) then
			return false, "навык не изучен: " .. (SKILL_NAME[skill] or skill)
		end
		if item.subclassID and item.subclassID > 6 then return false, "реликвия другого класса" end
	elseif item.classID == 6 then
		local need = equippedRanged and AMMO_FOR_RANGED[equippedRanged.subclassID]
		if not need then return false, "нет подходящего оружия дальнего боя" end
		if item.subclassID ~= need then return false, "не подходит к текущему оружию дальнего боя" end
	elseif item.classID == 11 then
		local need = equippedRanged and AMMO_FOR_RANGED[equippedRanged.subclassID]
		if not need then return false, "нет оружия дальнего боя" end
		if item.subclassID ~= need then
			return false, need == 2 and "к луку и арбалету нужен колчан, не подсумок" or "к ружью нужен подсумок, не колчан"
		end
	end
	return true
end

-- Trueshot Aura ranks (spell ids): its RAP is in the sheet only while the aura is up.
local TRUESHOT = { 1299346, 1299348, 19506, 20905, 20906 }

-- The unarmed main hand as wowsims has it, everywhere (the user, 2026-11-17: "as wowsims"; raid-mode design section 16):
-- its weapon SwingSpeed 1 and NormalizedSwingSpeed 1 with no damage (wowsims sim/core/attack.go:35-45
-- newWeaponFromUnarmed, which its comment calls probably wrong), taken by WeaponFromMainHand when the main hand holds no
-- weapon (attack.go:95-102). So an empty main hand swings at 1.0 s and the normalized hit of Strider Kick and Mongoose
-- Bite reads 1.0.
local UNARMED_SPEED = 1.0

-- Normalized weapon speed for Strider Kick / Mongoose Bite: dagger 1.7, two-hander 3.3, else 2.4
-- (docs/research/R3-core-formulas.md, normalized abilities); unarmed UNARMED_SPEED.
local function normSpeed(mh)
	if not mh then return UNARMED_SPEED end
	if mh.classID == 2 and mh.subclassID == 15 then return 1.7 end
	if ns.Score.IsTwoHand(mh) then return 3.3 end
	return 2.4
end
P.NormSpeed = normSpeed

-- A weapon for the damage model: an item of class 2 (Weapon) that is not held in the off hand (Score.IsWeapon, the
-- rule the procs read too). A few items of other classes carry a weapon inventory type (Forever Item.csv, build
-- 70888: Egan's Blaster 13289, class 12, ranged right; Torch of Retribution 10515, class 4, two-hand; Replica
-- Ironforge Air Rifle 281060, class 15): they deal no weapon damage.
local isWeapon = ns.Score.IsWeapon

-- Speed and DPS of a weapon in slot `slot`. A weapon's tooltip shows its speed on the damage line (client
-- string SPEED) and its DPS line (DPS_TEMPLATE; GetItemStats' DPS when the text lacks it), both read by Parse
-- (Game/Templates.lua, Game/Items.lua). In the build 70888 ItemSparse export every class-2 item (Item.csv)
-- outside the held-in-off-hand slot has an ItemDelay but test and monster rows: 16 "Monster -" rows, 4 "(TEST)"
-- rows and Test Item 1 4996. That export has no row for 2086 of Item.csv's 3871 class-2 items; the Era export
-- lacks 786 of them, and its class-2 rows without an ItemDelay are test and monster rows as well (also Alex's
-- Test Beatdown Staff 19879). So a weapon without either is a parse failure: an error, not a weapon priced at
-- a made-up speed.
local function weaponSpeedDPS(item, slot)
	local speed, dps = item.speed, item.stats.DPS
	if speed == nil or dps == nil then
		error(string.format("HunterGearAdvisor: weapon in slot %d without a parsed %s: %s", slot,
			speed == nil and "speed" or "DPS", tostring(item.name)), 3)
	end
	return speed, dps
end

-- Speed of an off-hand or ranged slot that holds no weapon (empty, a held-in-off-hand item, a non-weapon item), with 0
-- DPS: no swing reads it (dual wield needs ohDPS above 0, the shots a bow, gun or crossbow: Model.Parts), so its value
-- reaches no damage, and wowsims has no weapon there either (attack.go:104-120: Weapon{}, no swing). The main hand takes
-- UNARMED_SPEED.
local NO_WEAPON_SPEED = 2.6

-- The weapons the shots need: every shot the model counts has a SpellEquippedItems row with EquippedItemClass 2
-- and EquippedItemSubclass 262156, bits 2 (Bows), 3 (Guns) and 18 (Crossbows) (Forever DB2 build 70888; the
-- spells in Model.Parts, noShots).
local SHOT_WEAPON = { [2] = true, [3] = true, [18] = true }
-- The weapons the melee strikes need: Raptor Strike, Wing Clip and Mongoose Bite ranks 1-3 have a SpellEquippedItems row
-- with EquippedItemClass 2 and EquippedItemSubclass 173555 (Forever DB2 build 70888, db2_R5-weapons-gear
-- SpellEquippedItems.csv: 166357 / 175525 Raptor Strike 2973 / 14266, 166400 / 174762 Wing Clip 2974 / 14268, 254988 /
-- 254990 Mongoose Bite 1495 / 14270), bits 0 axes, 1 two-handed axes, 4 maces, 5 two-handed maces, 6 polearms, 7 swords,
-- 8 two-handed swords, 10 staves, 13 fist weapons, 15 daggers and 17 spears: not 14 (miscellaneous) and not 20 (fishing
-- poles). wowsims checks a spell's weapon requirement before it casts (sim/core/spelldata/resolve_spell.go:281-283
-- EquipRequirement, sim/core/equip_requirement.go:26-31), so a fishing pole or a miscellaneous weapon in the main hand
-- swings at its speed but takes no strike.
local STRIKE_WEAPON = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true,
	[13] = true, [15] = true, [17] = true }

-- Damage-model inputs of the weapons in a set ({ [slot] = piece }): the ranged weapon (18) and the
-- hands (16, 17). Snapshot builds the worn set's model with it and Advisor's weaponGain every other
-- set's, so the worn set gives the same model both ways. A scope's flat damage per shot
-- (stats.RANGED_FLAT) is that much / weapon speed more weapon DPS. An off-hand or ranged slot with no weapon has 0
-- weapon DPS at NO_WEAPON_SPEED; a main hand with no weapon fights unarmed at UNARMED_SPEED, its swing and its normalized
-- speed. unarmed: the main hand holds no weapon the melee strikes take (STRIKE_WEAPON: no weapon, or a fishing pole or a
-- miscellaneous weapon, which swing at their own speed and DPS), so Raptor Strike, Wing Clip and Mongoose Bite below rank
-- 4 are not cast (Model weaveParts). noShots: the ranged slot holds no bow, gun or crossbow (SHOT_WEAPON), so no shot is
-- cast.
function P.WeaponInputs(set)
	local bow, mh, oh = set[18], set[16], set[17]
	local bowSpeed, bowDPS = NO_WEAPON_SPEED, 0
	if isWeapon(bow) then
		local dps
		bowSpeed, dps = weaponSpeedDPS(bow, 18)
		bowDPS = dps + (bow.stats.RANGED_FLAT or 0) / bowSpeed
	end
	local mhSpeed, mhDPS = UNARMED_SPEED, 0
	local armed = isWeapon(mh)
	if armed then mhSpeed, mhDPS = weaponSpeedDPS(mh, 16) end
	local ohSpeed, ohDPS = NO_WEAPON_SPEED, 0
	if isWeapon(oh) then ohSpeed, ohDPS = weaponSpeedDPS(oh, 17) end
	-- Beastslaying (Parse stats.BEAST_SLAYING, the enchant of a melee weapon): its flat damage per hit, the main hand's
	-- and the off hand's summed. Its aura is the player's (spells 7784 / 13650 have no SpellEquippedItems row), so the
	-- model adds it to every weapon strike and shot of the hunter (Model.Parts flat), whichever hand carries it
	local beastSlaying = (mh and mh.stats.BEAST_SLAYING or 0) + (oh and oh.stats.BEAST_SLAYING or 0)
	return {
		bowDPS = bowDPS, bowSpeed = bowSpeed, noShots = not (isWeapon(bow) and SHOT_WEAPON[bow.subclassID] == true),
		mhDPS = mhDPS, mhSpeed = mhSpeed, mhNorm = normSpeed(armed and mh or nil),
		ohDPS = ohDPS, ohSpeed = ohSpeed,
		twoH = ns.Score.IsTwoHand(mh), unarmed = not (armed and STRIKE_WEAPON[mh.subclassID] == true), beastSlaying = beastSlaying,
	}
end

-- Arrows (projectile subclass 2) for bows and crossbows, bullets (3) for guns.
function P.AmmoFamily(rangedItem)
	return rangedItem and AMMO_FOR_RANGED[rangedItem.subclassID]
end
-- Quiver (container class 11 subclass 2) holds arrows, ammo pouch (subclass 3) bullets.
function P.QuiverFamily(item)
	if item and item.classID == 11 then return item.subclassID end
end

-- Character stats. The client can return them as "secret" values (API flag
-- SecretWhenUnitStatsRestricted; seen in game: arithmetic on UnitRangedAttackPower's result
-- failed with "a secret number value" inside a Baganator refresh). Arithmetic on a secret
-- value is an error, so each value is checked first; while they are secret the last reading of the
-- same worn items and the same applied talents is used (gear and talents are not secret), and with none the
-- caller is told stats are hidden.
local lastStats

-- The worn items a reading is taken with: { [inventory slot] = item link } (Snapshot: the equipment slots
-- and the four bag slots, where a quiver sits; its haste is in GetRangedHaste). Two readings are of the
-- same gear when every slot holds the same item id, enchant id and suffix id: fields 1, 2 and 7 of the
-- link's item string, "item:itemID:enchantID:gemID1:gemID2:gemID3:gemID4:suffixID:uniqueID:linkLevel:..."
-- (Forever UI Blizzard_PTRFeedback/Blizzard_Reports.lua:391, which states every field up to numBonusIDs at a fixed place,
-- an empty one as an empty string), compared as the link carries them. Two equal links carry equal fields. A worn
-- item's link without an item string, or with one shorter than its suffixID field, is an error.
local function gearFields(link)
	local s = link:match("|Hitem:([^|]*)|h")
	if not s then error("HunterGearAdvisor: worn item link without an item string: " .. link, 3) end
	local f = {}
	for v in (s .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
	if #f < 7 then error("HunterGearAdvisor: worn item link whose item string ends before its suffixID: " .. link, 3) end
	return f[1] .. ":" .. f[2] .. ":" .. f[7]
end
local function sameGear(a, b)
	for slot, la in pairs(a) do
		local lb = b[slot]
		if la ~= lb and (lb == nil or gearFields(la) ~= gearFields(lb)) then return false end
	end
	for slot in pairs(b) do
		if a[slot] == nil then return false end
	end
	return true
end

-- The applied talents a reading is taken with: the ranks and the branch points P.ReadTalents gives (the applied
-- snapshot while clicks are staged), nil both while they are unknown. Talents re-applied out of combat change the
-- sheet values (Lightning Reflexes' Agility: RAP and crit), so a reading serves only the talents it is taken with.
-- The points are compared with the ranks: one talent on two nodes (SAME_TALENT) has the higher node's rank in ranks,
-- and a rank on the other node shows in its branch's points. Two states are the same when both are unknown, or when
-- every key of one holds the same value in the other: known ranks have every talent of BRANCHES as a key, known points
-- every branch, so both tables of a kind have the same keys.
local function sameTalents(a, b)
	if a == nil or b == nil then return a == b end
	for k, v in pairs(a) do
		if b[k] ~= v then return false end
	end
	return true
end

-- Whether any of the values is one the client hides from addons, tested from the first value on. issecretvalue is a
-- global of the Forever client (Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua: issecretvalue(value)
-- -> bool) and is false for nil: the Forever UI passes it values that may be nil (Blizzard_SharedXML/Dump.lua:312,
-- DevTools_DumpValue, for every simple type, nil included).
local function isSecret(...)
	if select("#", ...) == 0 then return false end
	return issecretvalue((...)) or isSecret(select(2, ...))
end

-- Whether an aura of one of `spells` is up: true when one is, false when none is, nil when that cannot be
-- known. C_UnitAuras.GetPlayerAuraBySpellID / GetUnitAuraBySpellID return nothing for an aura that is
-- secret (predicate RequiresNonSecretAura, Forever SecretPredicatesDocumentation.lua), which looks like "no
-- aura", and under SecretWhenUnitAuraRestricted (combat, encounter, challenge mode, PvP match; a spell may
-- be flagged never or always secret) their result itself is secret (Forever UnitAuraDocumentation.lua). So
-- an aura is queried only when C_Secrets.ShouldSpellAuraBeSecret (Forever SecretPredicateAPIDocumentation.lua)
-- says it would not be secret; its result is then nil or a plain AuraData and may be tested. One rank found
-- up is enough; with none found up, a rank that could not be queried leaves the answer unknown.
local function auraState(spells, query)
	local unknown = false
	for _, id in ipairs(spells) do
		if C_Secrets.ShouldSpellAuraBeSecret(id) then
			unknown = true
		elseif query(id) then
			return true
		end
	end
	if unknown then return nil end
	return false
end
local function playerAura(id) return C_UnitAuras.GetPlayerAuraBySpellID(id) end
local function petAura(id) return C_UnitAuras.GetUnitAuraBySpellID("pet", id) end

-- The spells of every Use buff HGA prices (Game/UseData.lua, item.use.spell), each once. The buff is that spell's own
-- aura on the player: every effect of each UseData spell is Effect 6 APPLY_AURA on ImplicitTarget 1 TARGET_UNIT_CASTER,
-- none a triggered spell (Forever DB2 build 70888 SpellEffect; tools/gen_use_data.py checks it). ReadStats checks all
-- of them, the worn items' and the others': an item used and then taken off may leave its buff on the player, and the
-- item in the bags is a candidate whose buff Score.SetValue prices (over its uptime while levelling, in its windows of
-- the raid fight in raid mode). Whether the buff stays is not
-- settled by the sources at hand: none of these spells has a SpellEquippedItems row (no equipped item requirement,
-- Forever DB2 build 70888); the bits set in their SpellMisc attributes are Attributes_0 0x10 (ATTR_ABILITY in wowsims
-- sim/core/dbcenums/attributes.go) and Attributes_0 0x40000, Attributes_8 0x1000 and Attributes_15 0x2000, which that
-- file does not name; and wowsims' simulator ends an item's Use aura when the item is swapped (sim/core/item_swaps.go
-- RegisterActive) with no in-game log in its docs/evidence behind it. A reading taken while none of these buffs is up
-- holds none either way.
local USE_SPELLS = {}
do
	local seen = {}
	for _, use in pairs(ns.UseData) do
		if not seen[use.spell] then
			seen[use.spell] = true
			USE_SPELLS[#USE_SPELLS + 1] = use.spell
		end
	end
	table.sort(USE_SPELLS)
end

-- Whether a Use buff of USE_SPELLS is up on the player: true when one is, false when none is, nil when that cannot be
-- known (auraState: an aura C_Secrets.ShouldSpellAuraBeSecret says would be secret). The one answer for ReadStats and
-- for Advisor's Use-buff check, which reads it every second while an evaluation waits on a Use buff.
function P.UseBuffState()
	return auraState(USE_SPELLS, playerAura)
end

-- The auras that lower the player's stats (Game/StatMultData.lua StatDebuffData: Resurrection Sickness 15007, aura 80
-- -75%; Coward! 422978, aura 137 -20%; the like), each spell once in id order. The sheet under one is not the
-- character's: wowsims multiplies a stat by such a row as by any (sim/core/spelldata/parse_effects_table.go:807-813), and
-- the user's answer O8 names the buffs; HGA prices gear on the sheet without one (raid-mode design 25.6), as it does
-- without a Use buff.
local STAT_DEBUFF_SPELLS = {}
for id in pairs(ns.StatDebuffData) do STAT_DEBUFF_SPELLS[#STAT_DEBUFF_SPELLS + 1] = id end
table.sort(STAT_DEBUFF_SPELLS)

-- Whether a stat-lowering aura of STAT_DEBUFF_SPELLS is up on the player: true, false, or nil when that cannot be known
-- (auraState). The one answer for ReadStats and for Advisor's wait on it.
function P.StatDebuffState()
	return auraState(STAT_DEBUFF_SPELLS, playerAura)
end

-- The auras that multiply the player's stats (Game/StatMultData.lua, aura 137 A_MOD_TOTAL_STAT_PERCENTAGE and aura 80
-- A_MOD_PERCENT_STAT: Greater Blessing of Kings, Spirit of Zandalar, Sayge's Dark Fortune of Agility and the like; the
-- user's answer O8 = (a): the live sheet's stat multipliers count, raid-mode design 4.8, 24.3), each spell once in id
-- order, and the client stat index of each attribute the model multiplies an item's stats by (Model.ApplyStats): the
-- client order 0 Strength, 1 Agility, 2 Stamina, 3 Intellect, 4 Spirit (tools/gen_stat_mult_data.py; wowsims
-- sim/core/spelldata/parse_effects_table.go:52-54 clientStats).
local STAT_MULT_INDEX = { STR = 0, AGI = 1, INT = 3, SPI = 4 }
local STAT_MULT_SPELLS = {}
for id in pairs(ns.StatMultData) do STAT_MULT_SPELLS[#STAT_MULT_SPELLS + 1] = id end
table.sort(STAT_MULT_SPELLS)

-- The live sheet's stat multipliers { AGI, STR, INT, SPI }: each the product of 1 + percent / 100 of the auras of
-- STAT_MULT_SPELLS up on the player that name its stat (wowsims multiplies every factor of one stat,
-- sim/core/stats/deps.go:232-237), 1 with none up; nil when one aura's state cannot be known (auraState: the client says
-- it would be secret), which ReadStats handles as it handles an unknown Aspect of the Hawk.
local function statMultState()
	local m = { AGI = 1, STR = 1, INT = 1, SPI = 1 }
	for _, id in ipairs(STAT_MULT_SPELLS) do
		local up = auraState({ id }, playerAura)
		if up == nil then return nil end
		if up then
			local pcts = ns.StatMultData[id]
			for key, index in pairs(STAT_MULT_INDEX) do
				if pcts[index] then m[key] = m[key] * (1 + pcts[index] / 100) end
			end
		end
	end
	return m
end

-- The stats come with the state of Aspect of the Hawk and Trueshot Aura (hawk, trueshot): their RAP is in
-- UnitRangedAttackPower only while the aura is up, and Snapshot adds the RAP of the one that is not (the
-- model counts both as always up). The aura state is part of the same reading, because the correction is
-- right only for the RAP it is read with. The stat multipliers (statMult, statMultState) come with it as well: they
-- price an item's stats on the sheet the reading is taken on. An aura state that cannot be known (auraState nil, or
-- statMultState nil) is handled like secret stats: the last reading is used, or none (hidden). Taking it for "off" would add the aura's
-- RAP a second time; keeping the last aura state next to a newer RAP is wrong once the aura changes in
-- between. The last reading has both from one moment, so it is out of date at worst, never inconsistent.
-- ranks, points: the applied talents (P.ReadTalents; nil both while they are unknown). The Trueshot Aura talent
-- (ranks.trueshotAura) is the only case Snapshot adds the aura's RAP; without it the aura's state is not read
-- (trueshot nil), so a Trueshot Aura of another hunter that the client keeps secret does not hide the stats: every
-- rank's SpellEffect row has Effect 65, APPLY_AREA_AURA_RAID (wowsims sim/core/dbcenums/effects.go
-- E_APPLY_AREA_AURA_RAID), an area aura on the caster's raid.
-- Use buffs (USE_SPELLS): while one is up its stats are in these values (Nat Pagle's Broken Reel 468164: aura 54
-- A_MOD_HIT_CHANCE +10 in the ranged hit modifier), and Score.SetValue prices the item's buff again (over its uptime
-- while levelling, in its windows of the raid fight in raid mode).
-- So a reading counts only when every one is known to be off (P.UseBuffState false); with one up or unknown, the last
-- reading, taken with none up, is used. A stat-lowering aura (P.StatDebuffState: Resurrection Sickness and the like,
-- raid-mode design 25.6) likewise: the sheet under it is not the character's, so a reading counts only when every one is
-- known to be off.
-- A last reading serves only the same level, the same gear (gear: the worn items, { [slot] = link }, sameGear) and
-- the same applied talents (sameTalents), whatever made the new reading unusable: the stats secret in combat, an
-- unknown aura state, a stat-lowering aura or a Use buff. The same talents ask for the same aura states, so the reading
-- has the Trueshot Aura state whenever it is asked for.
-- Returns the reading, or nil and the reason: "hidden" (secret stats or an unknown Aspect / Trueshot / stat multiplier
-- state) before "debuff" (a stat-lowering aura up or unknown) before "useBuff" (a Use buff up or unknown). A last reading
-- comes back with stale = true and staleBy, the reason the new reading is not used (in the same order).
-- The values read, each SecretWhenUnitStatsRestricted in the Forever API documentation: UnitRangedAttackPower,
-- UnitAttackPower, UnitStat (effectiveStat, its second return: Agility and Spirit, the indices the Camelot paper doll
-- reads them by, Camelot/PaperDollFrame.lua:134 LE_UNIT_STAT_AGILITY and :143 LE_UNIT_STAT_SPIRIT; UnitDocumentation.lua:3198),
-- GetCombatRatingBonus, GetRangedHitModifier, GetRangedCritChance, GetCritChance, GetRangedHaste, UnitHealthMax,
-- UnitPowerMax, UnitArmor, GetManaRegen (baseManaRegen and castingManaRegen in mana a second, the values the paper doll
-- prints times 5, Camelot/PaperDollFrame.lua:1245-1248; PlayerScriptDocumentation.lua:571-580), GetSpellHitModifier
-- (:1113) and GetSpellCritChance (:1086, no argument, as Camelot/PaperDollFrameStats.lua:602 calls it).
function P.ReadStats(level, ranks, points, gear)
	local withTrueshot = ranks ~= nil and ranks.trueshotAura > 0
	local rb, rp, rn = UnitRangedAttackPower("player")
	local mb, mp, mn = UnitAttackPower("player")
	local _, agi = UnitStat("player", LE_UNIT_STAT_AGILITY)
	local _, spirit = UnitStat("player", LE_UNIT_STAT_SPIRIT)
	local hitRating, hitMod = GetCombatRatingBonus(CR_HIT_RANGED), GetRangedHitModifier()
	local crit = GetRangedCritChance()
	local meleeCrit = GetCritChance() -- melee abilities (Raptor, Mongoose, Strider Kick) use this one
	local _, ammoHaste = GetRangedHaste()
	local hp = UnitHealthMax("player")
	local mana = UnitPowerMax("player", Enum.PowerType.Mana)
	local _, armor = UnitArmor("player")
	local regenRest, regenCast = GetManaRegen()
	local spellHit, spellCrit = GetSpellHitModifier(), GetSpellCritChance()
	local hawk = auraState(ASPECT_HAWK, playerAura)
	local trueshot
	if withTrueshot then trueshot = auraState(TRUESHOT, playerAura) end
	local statMult = statMultState()
	local hidden = hawk == nil or (withTrueshot and trueshot == nil) or statMult == nil
		or isSecret(rb, rp, rn, mb, mp, mn, agi, spirit, hitRating, hitMod, crit, meleeCrit, ammoHaste, hp, mana, armor,
			regenRest, regenCast, spellHit, spellCrit)
	local useUp = P.UseBuffState()
	local debuffUp = P.StatDebuffState()
	local why = (hidden and "hidden") or (debuffUp ~= false and "debuff") or (useUp ~= false and "useBuff") or nil
	if why then
		if lastStats and lastStats.level == level and sameGear(lastStats.gear, gear)
			and sameTalents(lastStats.ranks, ranks) and sameTalents(lastStats.points, points) then
			local s = {}
			for k, v in pairs(lastStats) do s[k] = v end
			s.stale = true
			s.staleBy = why
			return s
		end
		return nil, why
	end
	lastStats = {
		level = level, rap = rb + rp + rn, map = mb + mp + mn, agi = agi, spirit = spirit, hit = hitRating + hitMod,
		crit = crit, meleeCrit = meleeCrit, ammoHaste = ammoHaste, hp = hp, mana = mana, armor = armor,
		regenRest = regenRest, regenCast = regenCast, spellHit = spellHit, spellCrit = spellCrit,
		hawk = hawk, trueshot = trueshot, statMult = statMult, gear = gear, ranks = ranks, points = points,
	}
	return lastStats
end

-- Every node of the hunter tree (Forever trait tree 1091, node ids from the client DB2
-- TraitNode), by branch. Named ones feed the damage model; the rest only count points per
-- branch. Lightning Reflexes 104982 and Improved Serpent Sting 105003 are old nodes moved off
-- the grid (replaced by 110859 and Improved Stings 110870), read so a leftover rank still counts.
local BRANCHES = {
	{ key = "BM", nodes = {
		deadlyAspects = 104960, enduranceTraining = 104976, focusedFire = 104975, improvedAspectOfTheMonkey = 104974,
		improvedRevivePet = 104972, pathfinding = 104973, bestialSwiftness = 104970, unleashedFury = 104969,
		improvedMendPet = 104968, ferocity = 104967, summonHawk = 104966, spiritBond = 104965, intimidation = 104964,
		bestialDiscipline = 104963, frenzy = 104962, bestialWrath = 104961,
	} },
	{ key = "MM", nodes = {
		hawkEye = 105013, improvedConcussiveShot = 105012, lethalAttacks = 105011, improvedStings = 110870,
		efficiency = 105009, carefulAim = 105008, rapidKilling = 105005, improvedArcaneShot = 105006, loneWolf = 105007,
		trueshotAura = 105004, mortalShots = 105002, improvedSerpentSting = 105003, rapidRecuperation = 104999,
		barrage = 105001, scatterShot = 105000, rangedWeaponSpec = 104998, sniperShot = 104997,
	} },
	{ key = "SV", nodes = {
		improvedTracking = 104996, deflection = 104995, entrapment = 104994, savageStrikes = 104993,
		survivalist = 104992, improvedWingClip = 104990, cleverTraps = 104991, surefooted = 104987,
		deterrence = 104986, survivalTactics = 104988, predatorsEdge = 110861, counterattack = 104989,
		resourcefulness = 104983, exposePrey = 104985, survivalistsDiscipline = 110860, striderKick = 104981,
		lightningReflexes = 110859, lightningReflexesOld = 104982, laceratingStrikes = 104984,
	} },
}
P.BRANCHES = BRANCHES
-- talents that are one talent on two nodes (the old one off the grid): the higher rank counts
local SAME_TALENT = { lightningReflexesOld = "lightningReflexes" }

-- Applied ranks per talent config. Clicks in the talent frame are staged on the active config
-- until "Apply" (TRAIT_CONFIG_UPDATED), and activeRank already shows them; while a config has
-- staged changes the last applied snapshot is used, so weights do not follow a build that is
-- not learned yet.
local applied = {} -- configID -> { ranks, points }

local function activeConfigID()
	local cfg = C_ClassTalents.GetActiveConfigID()
	if not cfg and C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
		-- the Camelot talent frame falls back the same way (dual spec: config of the active group)
		cfg = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(C_SpecializationInfo.GetActiveSpecGroup())
	end
	return cfg
end

-- Returns ranks (talent -> rank: every talent of BRANCHES a key, 0 for one not taken; a talent on two nodes,
-- SAME_TALENT, under its one key), points ({ BM =, MM =, SV = }), or nil and a reason:
-- "talents" while the client has no talent data yet, "staged" while talent clicks are staged
-- and not applied and no applied snapshot is known (fresh login with pending clicks).
function P.ReadTalents()
	local cfg = activeConfigID()
	if not cfg then return nil, "talents" end
	if C_Traits.ConfigHasStagedChanges(cfg) then
		local snap = applied[cfg]
		if snap then return snap.ranks, snap.points end
		return nil, "staged"
	end
	local ranks, points = {}, {}
	for _, branch in ipairs(BRANCHES) do
		local sum = 0
		for name, nodeID in pairs(branch.nodes) do
			local info = C_Traits.GetNodeInfo(cfg, nodeID)
			-- a node the client cannot answer yet comes back empty or with ID 0
			if not info or info.ID ~= nodeID then return nil, "talents" end
			-- activeRank is a number in every TraitNodeInfo (Forever Blizzard_APIDocumentationGenerated/
			-- SharedTraitsDocumentation.lua: Nilable = false; GetNodeInfo returns a TraitNodeInfo), 0 for a node not taken
			local rank = info.activeRank
			if isSecret(rank) then return nil, "talents" end
			if type(rank) ~= "number" then error("HunterGearAdvisor: talent node " .. nodeID .. " without an activeRank: " .. tostring(rank)) end
			sum = sum + rank
			local key = SAME_TALENT[name] or name
			if rank > (ranks[key] or 0) then ranks[key] = rank else ranks[key] = ranks[key] or 0 end
		end
		points[branch.key] = sum
	end
	applied[cfg] = { ranks = ranks, points = points }
	return ranks, points
end

P.ActiveConfigID = activeConfigID

-- The Survival branch: strictly more talent points in Survival than in Beast Mastery and than in Marksmanship (points:
-- P.ReadTalents' branch points). The user (2026-11-17): the hunter avoids melee in every build but the Survival branch,
-- the branch with the most points in Survival; a tie names no branch, and below level 10 no branch has a point.
function P.SurvivalBranch(points)
	return points.SV > points.BM and points.SV > points.MM
end

-- The applied snapshot is taken when the change happens, not on the next tooltip: otherwise new
-- clicks staged before any tooltip would leave the build from before "Apply" in use.
-- (Player.lua loads before Commands.lua, so these run before its ns.Invalidate handlers.)
ns.On("TRAIT_CONFIG_UPDATED", function(_, cfg)
	-- Camelot has other trait configs too (the Legacy Adventure tree)
	if cfg == activeConfigID() then P.ReadTalents() end
end)
ns.On("PLAYER_TALENT_UPDATE", function() P.ReadTalents() end) -- trainer wipe

-- Another config became active (dual spec switch): forget the old snapshots, read the new one.
function P.ForgetAppliedTalents()
	applied = {}
	P.ReadTalents()
end

-- The pet the model counts: with Lone Wolf what is out decides (+20% for the hunter without a
-- pet); otherwise a pet is assumed, so a dead or dismissed pet does not shake the weights.
-- ranks: P.ReadTalents' ranks, every talent of BRANCHES a key (Snapshot asks once they are known).
function P.PetOut(ranks)
	if ranks.loneWolf > 0 then
		return UnitExists("pet") and not UnitIsDead("pet")
	end
	return true
end

-- The family id (CreatureFamily) of the pet out now; nil with no pet out, or while the id is secret
-- (UnitCreatureFamily: SecretWhenUnitIdentityRestricted, Forever UnitDocumentation.lua).
local function petFamilyNow()
	if not UnitExists("pet") then return nil end
	local _, id = UnitCreatureFamily("pet")
	if isSecret(id) then return nil end
	return id
end

-- The pet's family (CreatureFamily id, Model.PET_FAMILY): the one out now, else the last one seen
-- this session, else nil (the model then counts no family bonus, Claw and Bite both).
local lastFamily
function P.PetFamily()
	local id = petFamilyNow()
	if id ~= nil then lastFamily = id end
	return lastFamily
end

-- Frenzy 19615, the pet's own haste: DB2 SpellEffect 19615 aura 319 (A_MOD_MELEE_HASTE_3) +30 on
-- TARGET_UNIT_CASTER, cast by the pet, so it is on the pet's swing at once.
local FRENZY = { 19615 }

-- The pet inherits the owner's melee speed: wowsims sim/core/pet.go:35 HasDynamicMeleeSpeedInheritance, "The
-- owner's melee and attack speed, each change at the next pet heartbeat" (unit.go MultiplyMeleeSpeed and
-- MultiplyAttackSpeed hand each change to TriggerDelayedPetInheritance, pet.go:553, which applies it at the
-- next heartbeat), and the heartbeat comes every PetUpdateInterval = 5250 ms (sim/core/constants.go:18). The
-- in-game log of wowsims commit d729b139 (docs/research/V1-verify-forever-pet.md section 5,
-- docs/research/R2-pet-scaling.md section 3): the pet swings at 1.965 s with the owner's 2% Wind Blessed,
-- 1.40 s under Rapid Fire and 1.08 s under Rapid Fire + Frenzy, and the owner's ranged-only Quick Shots
-- leaves it at 1.965 s. So every melee haste of the owner reaches the pet, among them Rapid Fire 3045
-- (SpellEffect index 3: aura 319 +40), Quick Strikes 1299448 (aura 319 +30, cast by the melee procs of
-- Aspect of the Beast 13161 / 1299445-1299447, effect index 2 aura 42), Kiss of the Spider 1219500
-- (aura 319 +20) and the enchants Iron Counterweight (spell 7217, aura 319 +3) and Arcanum of Rapidity (spell
-- 22841, aura 319 +1). The owner's melee speed multiplier is the main-hand weapon's speed over the main-hand
-- swing of UnitAttackSpeed("player"). The pet gets the owner's melee and attack speed multipliers
-- (sim/core/pet.go:381-398 enableDynamicMeleeSpeed), not haste rating (sim/core/unit.go:564-566, 610-638
-- TotalMeleeHasteMultiplier has it on top), so the multiplier the pet inherits is that one less the worn items' haste
-- rating (wornHasteRating; Forever has haste rating on 4 test items only, docs/research/R1-forever-ruleset.md, item
-- counts).
local PET_HEARTBEAT = 5.25
local OWNER_MULT_TOLERANCE = 1e-3 -- relative

-- The worn items' haste rating in % (their HASTE_RATING summed, as wornHaste sums it), or nil while an item's data is not
-- loaded (Items.Get).
local function wornHasteRating()
	local rating = 0
	for _, slot in ipairs(SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		if link then
			local rec = ns.Items.Get(link)
			if not rec then return nil end
			rating = rating + (rec.stats.HASTE_RATING or 0)
		end
	end
	return rating
end

-- The owner's melee speed multiplier the pet inherits, or nil when it cannot be known: no weapon in the main hand (an
-- unarmed swing has no base speed the client gives: WeaponInputs takes wowsims' UNARMED_SPEED, a modelling rule), an
-- item's data not loaded yet, or a secret UnitAttackSpeed (SecretWhenUnitStatsRestricted, Forever
-- UnitDocumentation.lua). The main-hand weapon's speed over the main-hand swing of UnitAttackSpeed("player") is the
-- owner's whole melee speed multiplier, the worn haste rating in it; the pet inherits it without the rating
-- (wornHasteRating). A weapon without a parsed speed is a parse failure (weaponSpeedDPS), an error.
local function ownerMeleeMult()
	local link = GetInventoryItemLink("player", 16)
	if not link then return nil end
	local mh = ns.Items.Get(link)
	if not mh or not isWeapon(mh) then return nil end
	if mh.speed == nil then
		error("HunterGearAdvisor: weapon in slot 16 without a parsed speed: " .. tostring(mh.name), 3)
	end
	local rating = wornHasteRating()
	if rating == nil then return nil end
	local swing = UnitAttackSpeed("player")
	if isSecret(swing) then return nil end
	if type(swing) ~= "number" or swing <= 0 then
		geterrorhandler()("HunterGearAdvisor: UnitAttackSpeed(\"player\") returned " .. tostring(swing))
		return nil
	end
	return mh.speed / swing / (1 + rating / 100)
end

-- The pet's own swing time (main hand, s): its creature swing with Faster / Slower Attack (the user's cat:
-- Faster Attack VI, 1.20 s), without Frenzy and without any melee haste it inherits from the owner. The model
-- applies the owner's melee speed back (Model.Parts petHaste and Frenzy's swing count, ownerMelee): the
-- worn state's speeds the pet inherits (Snapshot's model.haste, model.attackSpeed and model.meleeHaste, wornHaste: an
-- Iron Counterweight's 3% is in the owner's swing that this divides out, and comes back through model.meleeHaste) and
-- Rapid Fire's average (rf). UnitAttackSpeed("pet") is the swing of the moment; times the owner's melee speed multiplier
-- the pet inherits (ownerMeleeMult) it gives the pet's own swing. It is read only when
-- - the pet is out and Frenzy is known to be off (auraState false);
-- - the owner's multiplier is known (ownerMeleeMult) and has held, within OWNER_MULT_TOLERANCE, for a whole
--   pet heartbeat (PET_HEARTBEAT): then the pet has inherited exactly it. Before that the pet may still
--   swing with the multiplier from before the change (Rapid Fire just ended: the pet still swings at
--   1.2 / 1.4 s, and the owner's multiplier is 1);
-- - neither swing is secret (SecretWhenUnitStatsRestricted).
-- The multiplier is followed whenever it is known, the pet out or not, and forgotten while it is not: a
-- change not seen restarts the wait. A pet that comes out takes the owner's multipliers at once (wowsims
-- pet.go enableDynamicMeleeSpeed, run when the pet is enabled), so another pet does not restart it. A read
-- held back only by the wait asks again with one C_Timer.After (Forever UITimerDocumentation.lua) when the
-- wait is over; P.PetCheck then re-evaluates if the swing differs.
-- The last good value is kept until another pet is out. The keys it is kept with are the family id and the
-- GUID of the pet it is read from, as the client gives them at that read: each one nil when it is secret
-- (UnitCreatureFamily and UnitGUID: SecretWhenUnitIdentityRestricted, Forever UnitDocumentation.lua; the
-- predicate makes a value secret for a unit that is neither player-controlled nor in the party or raid,
-- SecretPredicatesDocumentation.lua, so the hunter's own pet is documented as readable). Another pet is out
-- when a key of the pet out now is known and differs from the same key known at the read; an unknown key on
-- either side says nothing. The family compared is the pet's own (petFamilyNow), never the model's last
-- family seen (P.PetFamily), which is the previous pet's while the new one's id is secret.
-- nil = never read (the model then uses Model.PET_BASE_SWING).
local lastSwing, swingFamily, swingGUID
local ownerMult, ownerMultSince -- the owner's melee speed multiplier followed, and GetTime() since it holds
local recheckPending
function P.PetSwing()
	local now = GetTime()
	local mult = ownerMeleeMult()
	if mult == nil then
		ownerMult, ownerMultSince = nil, nil
	elseif ownerMult == nil or math.abs(mult - ownerMult) > OWNER_MULT_TOLERANCE * ownerMult then
		ownerMult, ownerMultSince = mult, now
	end
	if not UnitExists("pet") then return lastSwing end
	P.PetFamily() -- keeps the model's family (lastFamily) up to date
	local family = petFamilyNow()
	local guid = UnitGUID("pet")
	if isSecret(guid) then guid = nil end
	if (family ~= nil and swingFamily ~= nil and family ~= swingFamily)
		or (guid ~= nil and swingGUID ~= nil and guid ~= swingGUID) then
		lastSwing = nil
	end
	if mult == nil or auraState(FRENZY, petAura) ~= false then return lastSwing end
	local speed = UnitAttackSpeed("pet")
	if isSecret(speed) then return lastSwing end
	if type(speed) ~= "number" or speed <= 0 then
		geterrorhandler()("HunterGearAdvisor: UnitAttackSpeed(\"pet\") returned " .. tostring(speed))
		return lastSwing
	end
	local wait = ownerMultSince + PET_HEARTBEAT - now
	if wait > 0 then
		if not recheckPending then
			recheckPending = true
			C_Timer.After(wait, function()
				recheckPending = false
				P.PetCheck()
			end)
		end
		return lastSwing
	end
	lastSwing, swingFamily, swingGUID = speed * mult, family, guid
	return lastSwing
end

-- Pet out or not (it matters with Lone Wolf), its family (damage passive, Claw / Bite) and its swing time
-- (Frenzy's uptime). Commands.lua calls it on the events that change them, PetSwing when a heartbeat wait
-- is over. Only a change re-evaluates.
local petWasOut, familyWas, swingWas
function P.PetCheck()
	local out = UnitExists("pet") and not UnitIsDead("pet")
	local family = P.PetFamily()
	local swing = P.PetSwing()
	if out ~= petWasOut or family ~= familyWas or swing ~= swingWas then
		petWasOut, familyWas, swingWas = out, family, swing
		ns.Invalidate()
	end
end

-- Wind Blessed 1259710, the Skyborne racial passive (Forever DB2 build 70888: SkillLineAbility 55326, SkillLine
-- 2980 "Skyborne Racial", AcquireMethod 2): SpellEffect index 0 Effect 6 APPLY_AURA, Aura 342
-- A_MOD_MELEE_RANGED_HASTE_2, bp 2, on the caster; index 1 Aura 65 (casting speed) bp 2.
local WIND_BLESSED, WIND_BLESSED_HASTE = 1259710, 2

-- The permanent attack speed of the worn state by source, each in % (the multiplier less 1, x 100): haste, attackSpeed,
-- hasteRating, meleeHaste and rangedHaste, Model p.haste / p.attackSpeed / p.hasteRating / p.meleeHaste / p.rangedHaste.
-- Who takes each follows wowsims' paths (raid-mode W1 design section 7; Model.Parts, the p fields):
-- - haste: the worn items' HASTE, the aura 342 of an item or enchant (Minor Haste 931 on gloves: spell 13928, aura 342
--   bp 1; Parse's attack speed enchants), each a factor of its own (wowsims sim/core/enchant_speed.go:13-41
--   registerEquipSpeedAuras registers each item's and enchant's speed aura apart, :65-79 AttachHastePseudoStats
--   multiplies the melee and the ranged speed): the shots, the melee swings, the pet and the hawks.
-- - attackSpeed: the worn set bonuses' ATTACK_SPEED (Score.SetBonuses; in Game/SetData.lua the five Tier-1 two-piece
--   bonuses with aura 342 bp 1, 1300934, 1300945, 1300951, 1300957, 1300968) and Wind Blessed (WIND_BLESSED), when the
--   player knows it (IsPlayerSpell), one product (wowsims: a set bonus's row is attackSpeedRow,
--   sim/core/spelldata/parse_effects_table.go:367-368, Wind Blessed AttackSpeedMultiplier x 1.02,
--   sim/core/racials.go:225-229; both MultiplyAttackSpeed): the shots, the melee swings and the pet, not the hawks. In
--   game the pet swings 1.965 s with its owner's 2% Wind Blessed (wowsims commit d729b139,
--   docs/research/V1-verify-forever-pet.md section 5).
-- - hasteRating: the worn items' HASTE_RATING (Core/Parse.lua): TOOLTIP_ITEM_STAT_HASTE_PCT_INCREASE "Equip: Increases
--   your attack speed and casting speed by N%", the tooltip's percent for haste rating (stat type 36, 10 rating a 1%,
--   docs/research/R1-forever-ruleset.md section 2.1), and ITEM_MOD_HASTE_RATING / 10, summed as ratings do (wowsims
--   hasteRatingMultiplier = 1 + the rating / 1000, sim/core/unit.go:564-566): the shots and the melee swings alone. In the
--   build 70888 ItemSparse export four test items carry stat 36: 13716, 17142, 18582, 19226.
-- - meleeHaste: the worn items' MELEE_HASTE, aura 319, the owner's melee speed (wowsims MeleeSpeedMultiplier,
--   MultiplyMeleeSpeed): the enchants Iron Counterweight 34 (aura 319 bp 3, two-handers), Arcanum of Rapidity 2543 (aura
--   319 + 140 bp 1, head and legs) and Automatic Crowd Pummeler 7123 (aura 319 bp 50, shoulders); the melee swings and the
--   pet. In game the pet swings 1.40 s for 1.965 s under Rapid Fire (aura 140 + 319) and keeps 1.965 s under Quick Shots
--   (aura 140 alone), so it takes aura 319 (the same V1 section 5).
-- - rangedHaste: the worn items' RANGED_HASTE, aura 140, the owner's ranged speed (wowsims RangedSpeedMultiplier,
--   MultiplyRangedSpeed): Arcanum of Rapidity's ranged half; the shots and the hawks.
-- - the worn set bonuses' MELEE_HASTE / RANGED_HASTE (no set bonus of Game/SetData.lua has aura 319 or 140) join their
--   scope as one factor each. A set bonus's HASTE or HASTE_RATING is an error: Game/SetData.lua writes a set bonus's aura
--   9 or 342 as ATTACK_SPEED (tools/gen_set_data.py), and no set bonus of build 70888 carries haste rating.
-- What is not counted: the hastes that come and go (Rapid Fire, which the model averages while levelling and runs in its
-- windows in the raid fight; Quick Shots, which the model counts from Deadly Aspects; Frenzy; a worn item's Use buff,
-- which Score prices over its uptime while levelling and the raid fight runs in its windows, and which ReadStats keeps
-- out of the reading; procs), and the quiver, which the model takes from GetRangedHaste (p.quiver).
-- The sources of one input multiply (wowsims: each Multiply*Speed multiplies for each aura), with two exceptions: the
-- items' haste rating adds up as ratings do, and the set bonuses come as the one sum Score.SetBonuses gives, one factor
-- per input (more than one bonus only with the two pieces of two Tier-1 sets worn: 2% for 2.01%).
-- Score.SetValue prices each input's stats, items, set bonuses and levelling Use buffs alike (a raid mode's Use buff runs
-- through the fight, ctx.useGain), at its weight a percent: the
-- value of one more 1% source of the input at this point (Model.Weights), against the worn set's, which stays at a
-- delta of 0. Since the items' haste rating sums here, a point of it multiplies the input's multiplier by
-- 1 + 1 / (100 + R), R the worn items' HASTE_RATING, and is priced (1 + R/100) times that; since the set bonuses'
-- ATTACK_SPEED sums too, a point of a set bonus's multiplies it by 1 + 1 / (100 + S), S the other worn set bonuses'
-- ATTACK_SPEED, and is priced (1 + S/100) times that (1% over for a second Tier-1 two-piece bonus, S = 1). Advisor's
-- weaponGain runs every set's weapons at this attack speed (the worn ones gain 0).
local function wornHaste(equipped, setBonus)
	if setBonus.HASTE ~= nil or setBonus.HASTE_RATING ~= nil then
		error("HunterGearAdvisor: a worn set bonus of HASTE or HASTE_RATING: Game/SetData.lua writes a set bonus's attack speed as ATTACK_SPEED", 2)
	end
	local items, rating, melee, ranged = 1, 0, 1, 1
	for _, it in pairs(equipped) do
		items = items * (1 + (it.stats.HASTE or 0) / 100)
		rating = rating + (it.stats.HASTE_RATING or 0)
		melee = melee * (1 + (it.stats.MELEE_HASTE or 0) / 100)
		ranged = ranged * (1 + (it.stats.RANGED_HASTE or 0) / 100)
	end
	local attack = 1 + (setBonus.ATTACK_SPEED or 0) / 100
	if IsPlayerSpell(WIND_BLESSED) then attack = attack * (1 + WIND_BLESSED_HASTE / 100) end
	melee = melee * (1 + (setBonus.MELEE_HASTE or 0) / 100)
	ranged = ranged * (1 + (setBonus.RANGED_HASTE or 0) / 100)
	return (items - 1) * 100, (attack - 1) * 100, rating, (melee - 1) * 100, (ranged - 1) * 100
end

-- Builds the equipped set, the bag weapon pool and the model inputs.
-- Returns nil, reason (nil while item data is missing, "talents" / "staged" from ReadTalents, "hidden" / "debuff" /
-- "useBuff" from ReadStats).
function P.Snapshot()
	local level = UnitLevel("player")
	local equipped, links = {}, {}
	local gear = {} -- the worn items a stats reading is taken with (ReadStats)
	for _, slot in ipairs(SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		if link then
			local rec = ns.Items.Get(link)
			if not rec then return nil end
			equipped[slot] = ns.Items.Piece(rec, { kind = "equipped", slot = slot })
			links[link] = slot
			gear[slot] = link
		end
	end
	-- Forever: GetInventoryItemLink returns nil for the ammo slot while GetInventoryItemID
	-- returns the ammo (seen in game 2026-11-12: link nil, id 11284, count 2790).
	local ammoLink = GetInventoryItemLink("player", AMMO_SLOT)
	if not ammoLink then
		local ammoID = GetInventoryItemID("player", AMMO_SLOT)
		if ammoID then
			ammoLink = select(2, C_Item.GetItemInfo(ammoID))
			if not ammoLink then
				ns.Items.Request(ammoID)
				return nil
			end
		end
	end
	if ammoLink then
		local rec = ns.Items.Get(ammoLink)
		if not rec then return nil end
		-- ammo that does not fit the ranged weapon is not in use (e.g. bullets left in the
		-- slot after switching to a bow)
		if P.CanUse(rec, equipped[18]) then
			equipped[AMMO_SLOT] = ns.Items.Piece(rec, { kind = "equipped", slot = AMMO_SLOT })
			links[ammoLink] = AMMO_SLOT
		end
	end

	-- quiver / ammo pouch sit in the bag slots (inventory ids of bags 1-4)
	local quiverPiece
	for bag = 1, 4 do
		local inv = C_Container.ContainerIDToInventoryID(bag)
		local link = inv and GetInventoryItemLink("player", inv)
		if link then
			gear[inv] = link
			local rec = ns.Items.Get(link)
			if rec and P.QuiverFamily(rec) then
				quiverPiece = ns.Items.Piece(rec, { kind = "equipped", slot = inv })
				links[link] = inv
			end
		end
	end

	local pool, bagPieces, bagAmmo = {}, {}, {}
	for bag = 0, 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local link = C_Container.GetContainerItemLink(bag, slot)
			if link then
				local rec = ns.Items.Get(link)
				if rec then
					local piece = ns.Items.Piece(rec, { kind = "bag", bag = bag, slot = slot })
					bagPieces[#bagPieces + 1] = piece
					-- partners and ammo must be wearable now (an above-level item keeps its own
					-- checkmark, but is never suggested as the other hand)
					local wearableNow = not (rec.reqLevel and rec.reqLevel > level)
					if wearableNow and ns.Score.WEAPON_LOCS[rec.equipLoc] and P.CanUse(rec, equipped[18]) then
						pool[#pool + 1] = piece
					end
					if wearableNow and rec.equipLoc == "INVTYPE_AMMO" and rec.subclassID then
						local best = bagAmmo[rec.subclassID]
						if not best or (rec.stats.AMMO_DPS or 0) > (best.stats.AMMO_DPS or 0) then
							bagAmmo[rec.subclassID] = piece
						end
					end
				end
			end
		end
	end
	-- The ammo slot can be empty in the API: then the best matching ammo in the bags counts
	-- as the ammo in use.
	local ammoFromBag = false
	local family = P.AmmoFamily(equipped[18])
	if not equipped[AMMO_SLOT] and family and bagAmmo[family] then
		equipped[AMMO_SLOT] = bagAmmo[family]
		ammoFromBag = true
	end

	-- the talents are read before the stats: a last reading serves only the applied talents it is taken with
	-- (ReadStats); on a failure points holds ReadTalents' reason, and the talents count as unknown
	local tal, points = P.ReadTalents()
	local live, why = P.ReadStats(level, tal, tal and points or nil, gear)
	if not live then return nil, why end -- "hidden" / "debuff" / "useBuff"
	if not tal then return nil, points end -- "talents" / "staged"
	-- the model counts the RAP of the hunter's own aspect and aura as always up; the aura state read
	-- with the RAP (ReadStats: hawk, trueshot) says which is in it; rank VII of the aspect (120) comes
	-- from a book, so it counts only when it is known
	local rap = live.rap
	if not live.hawk then
		rap = rap + (IsPlayerSpell(ASPECT_HAWK_BOOK) and 120 or ns.Model.Rank("aspectHawk", level))
	end
	if tal.trueshotAura > 0 and not live.trueshot then rap = rap + ns.Model.Rank("trueshot", level) end
	local liveHit = live.hit

	local gearHit, gearRangedHit, gearExp, gearApVs, gearArmorPen, gearSpellHit = 0, 0, 0, 0, 0, 0
	for _, it in pairs(equipped) do
		gearHit = gearHit + (it.stats.HIT or 0)
		gearSpellHit = gearSpellHit + (it.stats.SPELL_HIT or 0)
		gearRangedHit = gearRangedHit + (it.stats.RANGED_HIT or 0)
		gearExp = gearExp + (it.stats.EXPERTISE or 0)
		gearArmorPen = gearArmorPen + (it.stats.ARMOR_PEN or 0)
	end
	-- the mode by the level (the user, 2026-11-17: below 60 levelling, at 60 the raid; Model.RAID_LEVEL), and the target by
	-- the mode (the user: «на прокачке на мой уровень на 60 на рейды»): below 60 a mob of the hunter's own level, at 60 the
	-- raid boss three levels above (wowsims' target level 63, ui/specs/hunter/dps/defaults.siml:64; the Forever client's
	-- RAID_BOSS_LEVEL = 63, Camelot/SkillsFrame.lua:57-58). No setting changes either.
	local mode = level >= ns.Model.RAID_LEVEL and "raid" or "level"
	-- the hit of the worn set bonuses is in the live hit too (Devilsaur Armor's 2% is an aura on the
	-- player, spell 460230); Advisor takes it out of the base hit with the items' own. Their attack speed is in the
	-- model's attack speed inputs (wornHaste), their expertise in the model's expertise with the items' own (no live
	-- expertise is read; Grovekeeper Rage 2113's 4-piece bonus 1301076: EXPERTISE 1.2, Game/SetData.lua).
	local setBonus = ns.Score.SetBonuses(equipped, ns.SetData, P.HasSkillRank)
	local setHit = setBonus.HIT or 0
	-- The worn gear's ranged-only hit (RANGED_HIT: Marksman Bands' line, the +3% hit scopes; Core/Parse.lua) of the items
	-- and the set bonuses. The live hit is the ranged reading (GetCombatRatingBonus(CR_HIT_RANGED) +
	-- GetRangedHitModifier), which holds it, so the hit of every attack is the live hit less it (/hga dump writes the
	-- melee, ranged and spell hit modifiers to check this in game).
	local rangedGearHit = gearRangedHit + (setBonus.RANGED_HIT or 0)
	-- The worn items' and set bonuses' attack power against each creature type (AP_VS_<TYPE>, Model.CREATURE_TYPES; the
	-- live sheet holds none of it), each at the mode's share of that type (Model.TargetShare: levelling
	-- Model.AP_CREATURE_SHARE, raid 1 for the boss's dragonkin and 0 for the others): the model's apVsTarget, the hunter's
	-- own attack power against the target
	for _, t in ipairs(ns.Model.CREATURE_TYPES) do
		local key = "AP_VS_" .. t
		local amount = setBonus[key] or 0
		for _, it in pairs(equipped) do amount = amount + (it.stats[key] or 0) end
		gearApVs = gearApVs + amount * ns.Model.TargetShare(t, mode)
	end
	-- the worn items' and set bonuses' flat armor penetration (ARMOR_PEN, Core/Parse.lua; raid-mode design 2.4 and 5.1),
	-- which raid mode takes off the boss's armor against the hunter's own attacks (Model.BossArmor; the user's answer O5).
	-- The client has a live value too, GetArmorPenetration (Forever UI Blizzard_APIDocumentationGenerated/
	-- PlayerScriptDocumentation.lua:211; the character sheet's Camelot/PaperDollFrameStats.lua:171-180), which HGA does
	-- not read: the model takes the worn gear's sum. tools/gen_set_data.py writes no ARMOR_PEN: in the Forever DB2 (build
	-- 70888, SpellEffect.csv) aura 123 on the physical school is on spells 21153, 26481, 461252, 1231894 and 1231896, none
	-- a set bonus (ItemSetSpell.csv); the two set bonuses with aura 123, 26175 and 26283, pierce the magic schools (misc
	-- 124) and stay unknown in Game/SetData.lua
	local armorPen = gearArmorPen + (setBonus.ARMOR_PEN or 0)

	local ammo = equipped[AMMO_SLOT]
	local ammoHaste = live.ammoHaste
	local quiver = math.max(0, math.min(0.15, (ammoHaste or 0) / 100))
	local _, race = UnitRace("player")
	local orc
	if not isSecret(race) then orc = race == "Orc" end -- Orc Command: +5% pet damage
	local petOut = P.PetOut(tal)
	local petFamily = P.PetFamily()
	local petSwing = P.PetSwing()
	local haste, attackSpeed, hasteRating, meleeHaste, rangedHaste = wornHaste(equipped, setBonus)
	-- the Survival branch weaves as wowsims' SV Weave preset (Model weaveParts); every other build has no melee
	-- (P.SurvivalBranch; the user, 2026-11-17)
	local survival = P.SurvivalBranch(points)

	local model = {
		mode = mode,
		tal = tal, orc = orc, petOut = petOut, petFamily = petFamily, petSwing = petSwing,
		serpentTick = IsPlayerSpell(SERPENT_STING_BOOK) and 135 or nil,
		level = level, rap = rap, map = live.map, agi = live.agi, crit = live.crit, meleeCrit = live.meleeCrit,
		hit = liveHit - rangedGearHit, expertise = gearExp + (setBonus.EXPERTISE or 0),
		rangedGearHit = rangedGearHit,
		apVsTarget = gearApVs, armorPen = armorPen,
		spellHit = live.spellHit, spellCrit = live.spellCrit, statMult = live.statMult,
		manaMax = live.mana, regenRest = live.regenRest, regenCast = live.regenCast, spirit = live.spirit,
		haste = haste, attackSpeed = attackSpeed, hasteRating = hasteRating, meleeHaste = meleeHaste, rangedHaste = rangedHaste,
		ammoDPS = (ammo and ammo.stats.AMMO_DPS) or 0,
		quiver = quiver, mobDiff = mode == "raid" and 3 or 0, survival = survival,
	}
	for k, v in pairs(P.WeaponInputs(equipped)) do model[k] = v end

	return {
		equipped = equipped, links = links, pool = pool, bagPieces = bagPieces, ammoFromBag = ammoFromBag,
		bagAmmo = bagAmmo, quiverPiece = quiverPiece, ammoHaste = ammoHaste,
		statsStale = live.stale, statsStaleBy = live.staleBy,
		dualWield = P.DualWield(), level = level, liveHit = liveHit, gearHit = gearHit, setHit = setHit,
		rangedGearHit = rangedGearHit,
		-- the worn items' and set bonuses' spell hit (SPELL_HIT), which the live spell hit holds (GetSpellHitModifier:
		-- the set bonuses' auras are on the player); Advisor takes it out of the base spell hit
		gearSpellHit = gearSpellHit + (setBonus.SPELL_HIT or 0),
		points = points, survival = survival, petOut = petOut,
		pools = { hp = live.hp, mana = live.mana, armor = live.armor, level = level },
		model = model,
	}
end
