-- Re-scores the pre-raid set of docs/research/preraid-bis-60.md with HunterGearAdvisor's damage model (read only from
-- ADDON below) for a level-60 Orc BM 31/20/0 hunter with a pet.
-- Run: bash tools/preraid/rescore/run.sh   (see README.md; out/items.lua comes from avail.py + convert.py)
--
-- Two scorers:
--  * D(set): the model's DPS of the whole set in the raid fight (Model.Total at the model point built from that set's
--    stats, raid mode: the boss +3, the mana, the consumables), the set's Use buffs of Game/UseData.lua in the fight's
--    windows (p.uses = Score.SetUses) and their hit at their share of the fight (Score.SetValue's raid rule). This is the
--    decider.
--  * Score.SetValue(set, W, ctx) with W = Model.Weights(p) and ctx built as Game/Advisor.lua A.State builds it, iterated
--    (best set at p -> new p at that set -> ...) until stable: what the addon's own upgrade logic converges to.
-- Both searches: coordinate ascent over every candidate of every slot, then pair swaps over the top PAIR_K candidates of
-- each slot (by single-swap gain at the current optimum), restarts from the current A / B sets and from every
-- combination of set pieces that reaches a damage set bonus; repeated until no single or pair swap improves.
unpack = unpack or table.unpack
local HERE = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "."
-- the addon whose model is scored: env HGA_ADDON (a checkout of HunterGearAdvisor), else this repo (tools/preraid/rescore -> ../../..)
local ADDON = os.getenv("HGA_ADDON") or (HERE .. "/../../..")
print("addon: " .. ADDON)

local ns = { On = function() end } -- Player.lua registers two events at load; nothing here fires them
local function load(path)
	local chunk = assert(loadfile(ADDON .. "/" .. path))
	chunk("HunterGearAdvisor", ns)
end
load("Core/Model.lua")
load("Core/Score.lua")
load("Game/SetData.lua")
load("Game/UseData.lua")
load("Game/StatMultData.lua") -- Player.lua lists its spells at load (the live sheet's stat multipliers, unused here)
load("Game/Player.lua") -- for Player.WeaponInputs only (pure); its WoW API calls are inside functions not used here
local Model, Score, Player = ns.Model, ns.Score, ns.Player
-- `lua rescore.lua nocreature`: Model.AP_CREATURE_SHARE, the levelling mode's share of a creature type, set to 0. The
-- raid pass counts "+N Attack Power vs <creature type>" at the raid's share already (Model.TargetShare: the boss is
-- dragonkin; convert.py's untyped AP_CREATURE at UNTYPED_SHARE, 0), so the two outputs agree (raid-mode design 23.1)
if arg and arg[1] == "nocreature" then Model.AP_CREATURE_SHARE = 0; print("AP vs creature type counted at 0") end
local S = Score.SLOT

------------------------------------------------------------------------------------------------------------------------
-- Model point assumptions (each with its source; see the report)
------------------------------------------------------------------------------------------------------------------------
-- BM 31/20/0 of preraid-bis-60.md section 1, in Player.lua BRANCHES keys (the keys p.tal is read with)
local TAL = {
	deadlyAspects = 5, enduranceTraining = 3, focusedFire = 2, bestialSwiftness = 1, unleashedFury = 5, ferocity = 5,
	summonHawk = 1, intimidation = 1, bestialDiscipline = 2, frenzy = 5, bestialWrath = 1,
	lethalAttacks = 5, improvedStings = 3, carefulAim = 5, improvedArcaneShot = 2, trueshotAura = 1, mortalShots = 4,
}
do
	-- Player.ReadTalents gives every talent of BRANCHES a rank, 0 for one not taken (SAME_TALENT: lightningReflexesOld
	-- counts under lightningReflexes); Model errors on a missing one
	for _, b in ipairs(Player.BRANCHES) do
		for name in pairs(b.nodes) do
			local key = name == "lightningReflexesOld" and "lightningReflexes" or name
			if TAL[key] == nil then TAL[key] = 0 end
		end
	end
end
-- the build's points by branch (Player.ReadTalents' points)
local POINTS = { BM = 0, MM = 0, SV = 0 }
do
	for _, b in ipairs(Player.BRANCHES) do
		for name in pairs(b.nodes) do
			if TAL[name] then POINTS[b.key] = POINTS[b.key] + TAL[name] end
		end
	end
	for name in pairs(TAL) do
		local found = false
		for _, b in ipairs(Player.BRANCHES) do if b.nodes[name] then found = true end end
		if not found then error("talent key not in Player.BRANCHES: " .. name) end
	end
	assert(POINTS.BM == 31 and POINTS.MM == 20 and POINTS.SV == 0, "talent points " .. POINTS.BM .. "/" .. POINTS.MM .. "/" .. POINTS.SV)
end
-- level 60 hunter base (wowsims sim/core/base_stats.go ClassBaseStats Hunter: Agi 125, Str 55, Int 65, AP 100, RAP 110
-- "Level x 2 - 10, before 2 per Agility") + RaceOffsets Orc (Agi -3, Str +3, Int -3); physical crit 0
-- (base_stats_auto_gen.go ExtraClassBaseStats Hunter PhysicalCritPercent 0). Hunter AP: +1 per Str and Agi, RAP +2 per Agi
-- (sim/hunter/hunter.go:111-113); crit per Agi: Model.CritPerAgility(60).
local BASE = { AGI = 122, STR = 58, INT = 62, MAP = 100, RAP = 110, CRIT = 0 }
-- The raid fight's mana inputs (raid-mode design step 12; Player.Snapshot reads them live): the pool 1720 base mana + 20 +
-- 15 an Intellect point past 20 (wowsims sim/core/mana.go:59-71 AddStat(Mana, 20 - 15 x 20) and 15 a point, base mana 1720
-- base_stats_auto_gen.go:62-66); Spirit the hunter's 70 and the orc's +3 (sim/core/base_stats.go:52-56, 138-147) with the
-- gear's; the regen 6.25 + Spirit / 8 a second (mana.go:77-78) and MP5 / 5 (mana.go:166-169), whole out of the five-second
-- rule and at Bestial Discipline's 25% a rank inside it (talents_beast_mastery.go:174-182)
local BASE_MANA, BASE_SPIRIT = 1720, 73
local LEVEL = 60
local CPA = Model.CritPerAgility(LEVEL)
local CAREFUL_AIM = 0.20 * TAL.carefulAim          -- AP per Intellect, melee and ranged (Model.Weights W.INT)
local LETHAL = 1 * TAL.lethalAttacks               -- % crit, all attacks (spell 19426 aura 290, 1 per rank)
-- Player.Snapshot adds the RAP of Aspect of the Hawk (trainer rank at 60: Model.Rank; the book rank VII is assumed not
-- known) and of Trueshot Aura (talent taken) as always up
local ASPECT = Model.Rank("aspectHawk", LEVEL)
local TRUESHOT = Model.Rank("trueshot", LEVEL)
local PET_FAMILY = 11                               -- Raptor: wowsims ui/specs/hunter/dps/builds/bm.siml pet_type raptor
local PET_SWING = 2.0 / 1.25                        -- Faster Attack II (bm.siml), spell 1263100 aura 9 bp 25: 2.0 s / 1.25
local AMMO_DPS = 17.5                               -- Thorium Headed Arrow 18042 (bm.siml ammo; wowsims ammo_auto_gen.go)
local QUIVER = 0.13                                 -- Quickdraw Quiver 8217, 13% (wowsims ammo_auto_gen.go; on the user's AH)
-- the Survival branch weaves (Player.Snapshot, Player.SurvivalBranch): not this BM 31/20 build
local SURVIVAL = Player.SurvivalBranch(POINTS)
local LW = 165                                      -- Leatherworking skill line; the user has it at 300
local function hasSkill(line, rank) return line == LW and rank <= 300 end

------------------------------------------------------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------------------------------------------------------
local ITEMS = dofile(HERE .. "/out/items.lua")
local byId = {}
for _, it in ipairs(ITEMS) do
	-- the addon's item: the converted stats, the Use buff by id as Items.Get attaches it, no parsed damage procs
	it.use = ns.UseData[it.id]
	it.procs = {}
	byId[it.id] = it
end

local SLOTS = { S.HEAD, S.NECK, S.SHOULDER, S.BACK, S.CHEST, S.WRIST, S.HANDS, S.WAIST, S.LEGS, S.FEET,
	S.FINGER1, S.FINGER2, S.TRINKET1, S.TRINKET2, S.MAINHAND, S.OFFHAND, S.RANGED }
local SLOT_NAME = { [S.HEAD] = "head", [S.NECK] = "neck", [S.SHOULDER] = "shoulder", [S.BACK] = "back", [S.CHEST] = "chest",
	[S.WRIST] = "wrist", [S.HANDS] = "hands", [S.WAIST] = "waist", [S.LEGS] = "legs", [S.FEET] = "feet",
	[S.FINGER1] = "finger1", [S.FINGER2] = "finger2", [S.TRINKET1] = "trinket1", [S.TRINKET2] = "trinket2",
	[S.MAINHAND] = "mainhand", [S.OFFHAND] = "offhand", [S.RANGED] = "ranged" }
local GRP_SLOTS = { head = { S.HEAD }, neck = { S.NECK }, shoulder = { S.SHOULDER }, back = { S.BACK }, chest = { S.CHEST },
	wrist = { S.WRIST }, hands = { S.HANDS }, waist = { S.WAIST }, legs = { S.LEGS }, feet = { S.FEET },
	finger = { S.FINGER1, S.FINGER2 }, trinket = { S.TRINKET1, S.TRINKET2 }, ranged = { S.RANGED } }

local function listsFor(exclude)
	local L = {}
	for _, s in ipairs(SLOTS) do L[s] = {} end
	for _, it in ipairs(ITEMS) do
		if not exclude(it) then
			if it.grp == "weapon" then
				if Score.CanMH(it) then table.insert(L[S.MAINHAND], it) end
				if Score.CanOH(it, true) then table.insert(L[S.OFFHAND], it) end
			else
				for _, s in ipairs(GRP_SLOTS[it.grp]) do table.insert(L[s], it) end
			end
		end
	end
	return L
end

local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end

local function legal(set)
	local mh, oh = set[S.MAINHAND], set[S.OFFHAND]
	if oh and (not mh or Score.IsTwoHand(mh)) then return false end
	if mh and oh and mh.id == oh.id and (mh.uniqueEquipped or oh.uniqueEquipped) then return false end
	for _, pr in ipairs({ { S.FINGER1, S.FINGER2 }, { S.TRINKET1, S.TRINKET2 } }) do
		local a, b = set[pr[1]], set[pr[2]]
		if a and b and a.id == b.id and (a.uniqueEquipped or b.uniqueEquipped) then return false end
	end
	return true
end

------------------------------------------------------------------------------------------------------------------------
-- The model point of a set (Player.Snapshot + Advisor A.State, with the character sheet computed from base + gear)
------------------------------------------------------------------------------------------------------------------------
-- An item's ranged-only hit (stats.RHIT, convert.py) and a set bonus's (Game/SetData.lua RANGED_HIT) are the model's
-- p.rangedGearHit, the worn gear's ranged-only hit (Player.Snapshot: the shots, the pet and the hawks take it).
local function sums(set)
	local t = { AGI = 0, STR = 0, INT = 0, AP = 0, RAP = 0, MAP = 0, CRIT = 0, CRIT_RANGED = 0, HIT = 0, RHIT = 0,
		EXPERTISE = 0, AP_CREATURE = 0, SPI = 0, MP5 = 0, MANA = 0, ARMOR_PEN = 0 }
	for _, it in pairs(set) do
		for k, v in pairs(it.stats) do if t[k] then t[k] = t[k] + v end end
	end
	local bonus = Score.SetBonuses(set, ns.SetData, hasSkill)
	for k, v in pairs(bonus) do
		local key = k == "RANGED_HIT" and "RHIT" or k
		if t[key] then t[key] = t[key] + v end
	end
	return t, bonus
end

-- Player.lua wornHaste without Wind Blessed (an orc has none): an item's HASTE (an enchant's aura 342) a factor each, the
-- set bonuses' ATTACK_SPEED, the items' HASTE_RATING summed, MELEE_HASTE and RANGED_HASTE a factor each
local function wornHaste(set, bonus)
	if bonus.HASTE ~= nil or bonus.HASTE_RATING ~= nil then error("a set bonus of HASTE or HASTE_RATING (Player.lua wornHaste)") end
	local items, rating, melee, ranged = 1, 0, 1, 1
	for _, it in pairs(set) do
		items = items * (1 + (it.stats.HASTE or 0) / 100)
		rating = rating + (it.stats.HASTE_RATING or 0)
		melee = melee * (1 + (it.stats.MELEE_HASTE or 0) / 100)
		ranged = ranged * (1 + (it.stats.RANGED_HASTE or 0) / 100)
	end
	local attack = 1 + (bonus.ATTACK_SPEED or 0) / 100
	melee = melee * (1 + (bonus.MELEE_HASTE or 0) / 100)
	ranged = ranged * (1 + (bonus.RANGED_HASTE or 0) / 100)
	return (items - 1) * 100, (attack - 1) * 100, rating, (melee - 1) * 100, (ranged - 1) * 100
end

-- the share of the raid's targets that convert.py's untyped "+N Attack Power vs <creature type>" (AP_CREATURE) is worth:
-- the raid boss is dragonkin (Model.TargetShare in raid mode), and AP_CREATURE names no type, so it counts at 0
local UNTYPED_SHARE = 0
local function pointFor(set, mobDiff)
	local t, bonus = sums(set)
	local agi, str, int = BASE.AGI + t.AGI, BASE.STR + t.STR, BASE.INT + t.INT
	local rap = BASE.RAP + 2 * agi + t.AP + t.RAP + CAREFUL_AIM * int + ASPECT + TRUESHOT
	local map = BASE.MAP + str + agi + t.AP + t.MAP + CAREFUL_AIM * int
	local crit = BASE.CRIT + LETHAL + CPA * agi + t.CRIT
	local haste, attackSpeed, hasteRating, meleeHaste, rangedHaste = wornHaste(set, bonus)
	-- mode: raid, the level-60 hunter against the raid boss +3 (Player.Snapshot: the mode by the level, the user's «на 60 на
	-- рейды»), with the raid inputs: the mana pool, the regen and Spirit (BASE_MANA, BASE_SPIRIT) and the gear's armor
	-- penetration (Model.BossArmor).
	-- agi: the sheet's Agility; hit: the hit of every attack, rangedGearHit: the gear's ranged-only hit, rangedSkill 0 and
	-- rangedHit 0: the worn ranged skill over 5 x level and its hit, a bow at 300 = 5 x 60; mhSkill, ohSkill and meleeHit 0:
	-- every melee line at 300 too (Advisor A.State sets them: stateAt); apVsTarget: the gear's attack power against a creature
	-- type (convert.py's AP_CREATURE) at the raid's share of its type, which convert.py does not name: counted at 0 (the raid
	-- boss is dragonkin, Model.TargetShare; UNTYPED_SHARE); spellHit 0 (no spell hit on the gear here); spellCrit: the
	-- hunter's base 3.6% and 0.0165% an Intellect point (wowsims
	-- sim/core/base_stats_auto_gen.go:38-42 CritPerIntMaxLevel, :62-66 SpellCritPercent); statMult 1 each: the tool's
	-- point is the gear's stats on the base character, no stat multiplier aura on it (the game reads the live sheet's,
	-- Player.ReadStats; raid-mode design 4.8). Player.WeaponInputs gives beastSlaying with the weapon fields.
	local spirit = BASE_SPIRIT + t.SPI
	local spiritRegen = 6.25 + spirit / 8
	local p = {
		mode = "raid", agi = agi, rangedGearHit = t.RHIT, apVsTarget = UNTYPED_SHARE * t.AP_CREATURE, spellHit = 0,
		spellCrit = 3.6 + 0.0165 * int, statMult = { AGI = 1, STR = 1, INT = 1, SPI = 1 },
		manaMax = BASE_MANA + 20 + 15 * (int - 20) + t.MANA, spirit = spirit, armorPen = t.ARMOR_PEN,
		regenRest = t.MP5 / 5 + spiritRegen, regenCast = t.MP5 / 5 + 0.25 * TAL.bestialDiscipline * spiritRegen,
		tal = TAL, orc = true, petOut = true, petFamily = PET_FAMILY, petSwing = PET_SWING, serpentTick = nil,
		level = LEVEL, rap = rap, map = map, crit = crit + t.CRIT_RANGED, meleeCrit = crit,
		hit = t.HIT, rangedHit = 0, rangedSkill = 0, meleeHit = 0, mhSkill = 0, ohSkill = 0,
		expertise = t.EXPERTISE, haste = haste, attackSpeed = attackSpeed, hasteRating = hasteRating, meleeHaste = meleeHaste,
		rangedHaste = rangedHaste,
		ammoDPS = AMMO_DPS, quiver = QUIVER, mobDiff = mobDiff, survival = SURVIVAL,
	}
	for k, v in pairs(Player.WeaponInputs(set)) do p[k] = v end
	return p
end

-- D(set): the model's DPS of the set in the raid fight, its Use buffs in their windows (p.uses, Score.SetUses' order: the
-- fight applies their stats but HIT, SPELL_HIT and EXPERTISE, the pet's attack power held) and each buff's hit at its share
-- of the fight (Model.UseUptimes) as the model's gain of that hit, as Score.SetValue's raid rule prices it (the cap there)
local function D(set, mobDiff)
	local p = pointFor(set, mobDiff)
	local uses = Score.SetUses(set)
	if not uses[1] then return Model.Total(p) end
	local q = copy(p)
	q.uses = uses
	local d = Model.Total(q)
	local shares = Model.UseUptimes(uses)
	local t = Model.Total(p)
	for _, use in ipairs(uses) do
		local hit = use.stats.HIT
		if hit then
			local qh = copy(p)
			qh.hit = qh.hit + hit
			d = d + shares[use.spell] * (Model.Total(qh) - t)
		end
	end
	return d
end

------------------------------------------------------------------------------------------------------------------------
-- Advisor A.State at a set: the model point, W and ctx exactly as Game/Advisor.lua builds them
------------------------------------------------------------------------------------------------------------------------
-- The addon's item stats (Game/Items.lua Items.Get): Parse over the tooltip lines, then C_Item.GetItemStats fills any
-- stat the text gave none for, through Items.API_MAP (which has no hit key at all). Two converted stats are not what
-- the addon reads:
--  * RHIT, ranged-only hit: every client spell with that effect reads "Improves your chance to hit with ranged weapons
--    by X%" / "Повышает вероятность попадания в дальнем бою на X%" (Spell.csv 22780, SpellRu.csv 22780 / 1294769 /
--    1301125 / 1301127); Parse reads it as RANGED_HIT (Core/Parse.lua EXTRA_STAT_PATTERNS), so the Score item carries
--    RANGED_HIT. The live hit (Snapshot: GetCombatRatingBonus(CR_HIT_RANGED) + GetRangedHitModifier) is assumed to hold
--    it, and Snapshot takes the worn gear's out of the hit of every attack (the model's p.rangedGearHit), so the worn
--    set's is out of ctx.baseHit, as in the addon (stateAt).
--  * AP_CREATURE, convert.py's attack power against a creature type, names no type, where the addon's item has the
--    AP_VS_<TYPE> key of the type its text names (Core/Parse.lua CREATURE_AP_PATTERNS); Model.Weights prices every
--    AP_VS_<TYPE> at W.AP_VS x Model.TargetShare(type, mode) (raid mode: 1 for dragonkin, 0 for any other type), and
--    the tool prices AP_CREATURE at W.AP_VS x UNTYPED_SHARE (0: its type is not named).
--  * Counterattack Lodestone 18537: its equip spell 1318938 reads "+$s1 Attack Power, doubled against Mechanical
--    units." / "+$s1 к силе атаки. Бонус удваивается против механизмов." (Spell.csv / SpellRu.csv); Parse reads AP 30
--    and AP_VS_MECHANICAL 30 from it (CREATURE_AP_PATTERNS), the Score item carries those. Whether GetItemStats reports
--    its 30 AP (ATTACK_POWER is in API_MAP) can only be seen in game; it would be the parsed AP again (Items.Get keeps
--    the text's value), so both readings give the Lodestone AP 30 and AP_VS_MECHANICAL 30:
--      "parse":   Parse only, GetItemStats gives nothing
--      "api_ap":  AP 30 from GetItemStats as well
local LODESTONE = 18537
local READINGS = { "parse", "api_ap" }
local function scoreItem(it, reading)
	if not it.stats.RHIT and it.id ~= LODESTONE then return it end
	local c = setmetatable({ stats = copy(it.stats) }, { __index = it })
	c.stats.RANGED_HIT, c.stats.RHIT = it.stats.RHIT, nil
	if it.id == LODESTONE then
		if reading ~= "parse" and reading ~= "api_ap" then error("unknown Score reading " .. tostring(reading)) end
		c.stats.AP_VS_MECHANICAL, c.stats.AP_CREATURE = it.stats.AP_CREATURE, nil
	end
	return c
end
local scoreCache = { parse = {}, api_ap = {} }
local function SI(it, reading)
	local cache = scoreCache[reading] or error("unknown Score reading " .. tostring(reading))
	local c = cache[it]; if not c then c = scoreItem(it, reading); cache[it] = c end; return c
end
local function scoreSet(set, reading) local c = {}; for s, it in pairs(set) do c[s] = SI(it, reading) end; return c end

local function stateAt(worn, mobDiff, reading)
	local equipped = scoreSet(worn, reading)
	local snapModel = pointFor(worn, mobDiff)
	-- a bow at 300 skill = 5 x level (Advisor A.State: rangedSkill = rangedSkill.shown - 5 x level, rangedHit =
	-- Model.SkillHit of it; skillBase = the trained skill - 5 x level, 0 here: no gear bonus to the line)
	local rangedBonus = 0
	local model = copy(snapModel)
	model.rangedSkill = rangedBonus
	model.rangedHit = Model.SkillHit(mobDiff, rangedBonus)
	-- every melee line at 300 = 5 x 60 (wowsims' racials hold no weapon skill: sim/core/racials.go has no skill term, so
	-- the orc it models has none): a hand's skill bonus is its set's bonuses to its line alone (Score.MeleeSkills with
	-- meleeTrained 0), the worn hands' the model point's (0 without a worn melee skill bonus), so the worn set's weapon
	-- run is the model point itself
	local function meleeTrained() return 0 end
	model.mhSkill, model.ohSkill = Score.MeleeSkills(equipped, { sets = ns.SetData, hasSkill = hasSkill, meleeTrained = meleeTrained })
	model.meleeHit = Model.SkillHit(mobDiff, model.mhSkill)
	local W, unitDps, total, unit = Model.Weights(model)
	-- convert.py's untyped AP_CREATURE at the raid's share of its type (UNTYPED_SHARE, pointFor)
	W.AP_CREATURE = W.AP_VS * UNTYPED_SHARE
	local cap = Model.HitCap(mobDiff)
	-- Advisor weaponModelFor: one run per (ranged, main hand, off hand, the hands' melee skills)
	local cache = {}
	local ctx
	local function weaponModel(set)
		local mhSkill, ohSkill = Score.MeleeSkills(set, ctx)
		local key = tostring(set[S.RANGED]) .. "|" .. tostring(set[S.MAINHAND]) .. "|" .. tostring(set[S.OFFHAND]) .. "|"
			.. mhSkill .. "|" .. ohSkill
		local run = cache[key]
		if not run then
			local p = copy(model)
			for k, v in pairs(Player.WeaponInputs(set)) do p[k] = v end
			p.mhSkill, p.ohSkill = mhSkill, ohSkill
			local t, hits = Model.TotalAndHits(p)
			run = { (t - total) / unitDps, hits }
			cache[key] = run
		end
		return run[1], run[2]
	end
	local _, setBonus = sums(equipped)
	local gearHit = 0
	for _, it in pairs(equipped) do gearHit = gearHit + (it.stats.HIT or 0) end
	-- the live hit holds the worn gear's ranged-only hit (Player.Snapshot); the base hit is the live hit less it and the
	-- worn items' and set bonuses' hit (Advisor A.State)
	local liveHit = snapModel.hit + snapModel.rangedGearHit
	ctx = {
		-- the mode of the point (raid, pointFor: Score.SetValue prices the Use buffs through the raid fight, ctx.useGain below)
		mode = model.mode,
		equipped = equipped, pool = {}, dualWield = true,
		hitCap = cap, baseHit = liveHit - snapModel.rangedGearHit - gearHit - (setBonus.HIT or 0),
		wornHit = snapModel.hit,
		-- the base spell hit (Advisor A.State: the point's spell hit less the worn items' and set bonuses' SPELL_HIT) and the
		-- trap's spell hit cap (Model.TrapHitCap)
		baseSpellHit = snapModel.spellHit - (function()
			local x = setBonus.SPELL_HIT or 0
			for _, it in pairs(equipped) do x = x + (it.stats.SPELL_HIT or 0) end
			return x
		end)(),
		spellHitCap = Model.TrapHitCap(model.mobDiff, TAL.survivalTactics),
		secondaryRates = Model.SecondaryRates(TAL),
		weaponGain = function(set) return (weaponModel(set)) end,
		landedHitsFor = function(set) local _, h = weaponModel(set); return h end,
		sets = ns.SetData, hasSkill = hasSkill,
		skillBase = 0, mobDiff = model.mobDiff,
		meleeTrained = meleeTrained, wornMeleeHit = model.meleeHit,
		expertiseCap = Model.MobAvoid(model.mobDiff),
		parryCap = Model.PetTanks(model.mode) > 0 and Model.PetParry(model.mobDiff) or Model.MobAvoid(model.mobDiff),
	}
	ctx.landedHits = ctx.landedHitsFor(equipped)
	-- the raid mode's Use buffs through the fight (Advisor A.State ctx.useGain, ctx.useUptime): one run a distinct list of
	-- buffs in their firing order (Score.SetUses), a set with none 0 and no share
	local useRuns = {}
	local function useRun(set)
		local uses = Score.SetUses(set)
		local spells = {}
		for i, use in ipairs(uses) do spells[i] = use.spell end
		local key = table.concat(spells, ",")
		local r = useRuns[key]
		if r == nil then
			if uses[1] then
				local q = copy(model)
				q.uses = uses
				r = { (Model.Total(q) - total) / unitDps, Model.UseUptimes(uses) }
			else
				r = { 0, {} }
			end
			useRuns[key] = r
		end
		return r
	end
	ctx.useGain = function(set) return useRun(set)[1] end
	ctx.useUptime = function(set) return useRun(set)[2] end
	-- the change of the fight's consumables' events a set's stats make (Advisor A.State ctx.eventGain; raid-mode design 25.1):
	-- Model.EventGain at the point with the stats applied against the point's events, in the weights' unit, one run a
	-- distinct stats table
	local events = Model.FightEvents(model)
	local eventRuns = {}
	ctx.eventGain = function(stats)
		local keys = {}
		for k in pairs(stats) do keys[#keys + 1] = k end
		if #keys == 0 then return 0 end
		table.sort(keys)
		local parts = {}
		for i, k in ipairs(keys) do parts[i] = k .. "=" .. string.format("%.17g", stats[k]) end
		local key = table.concat(parts, ",")
		local g = eventRuns[key]
		if g == nil then
			local q = copy(model)
			Model.ApplyStats(q, stats)
			g = Model.EventGain(q, events) / unitDps
			eventRuns[key] = g
		end
		return g
	end
	return { model = model, W = W, unitDps = unitDps, total = total, unit = unit, ctx = ctx }
end

------------------------------------------------------------------------------------------------------------------------
-- Search
------------------------------------------------------------------------------------------------------------------------
local PAIR_K = 40
local EPS = 1e-9

local function place(set, s, it)
	local t = copy(set)
	t[s] = it
	if s == S.MAINHAND and it and Score.IsTwoHand(it) then t[S.OFFHAND] = nil end
	return t
end

local function ascend(f, set, L)
	local best = f(set)
	local changed = true
	while changed do
		changed = false
		for _, s in ipairs(SLOTS) do
			local opts = L[s]
			local bestT, bestV = nil, best
			for i = 0, #opts do
				local it = opts[i] -- i = 0: empty (only the off hand may be empty)
				if (i > 0 or s == S.OFFHAND) and it ~= set[s] then
					local t = place(set, s, it)
					if legal(t) then
						local v = f(t)
						if v > bestV + EPS then bestT, bestV = t, v end
					end
				end
			end
			if bestT then set, best, changed = bestT, bestV, true end
		end
	end
	return set, best
end

-- the k candidates of slot s with the highest single-swap value at `set`. For the off hand next to a worn two-hander
-- (where no off hand is legal) they are ranked next to the best one-handed main hand instead, and for the main hand
-- the one-handers are ranked with the off hand emptied when a two-hander is worn; the pair search then tries them
-- together.
local function topK(f, set, L, s, k)
	local ref = set
	if s == S.OFFHAND and Score.IsTwoHand(set[S.MAINHAND]) then
		local bestMH, bv = nil, -math.huge
		for _, it in ipairs(L[S.MAINHAND]) do
			if not Score.IsTwoHand(it) then
				local t = place(set, S.MAINHAND, it); t[S.OFFHAND] = nil
				local v = f(t); if v > bv then bestMH, bv = it, v end
			end
		end
		if not bestMH then return {} end
		ref = place(set, S.MAINHAND, bestMH); ref[S.OFFHAND] = nil
	end
	local scored = {}
	for _, it in ipairs(L[s]) do
		local t = place(ref, s, it)
		if legal(t) then scored[#scored + 1] = { it = it, v = f(t) } end
	end
	table.sort(scored, function(a, b) return a.v > b.v end)
	local out = {}
	for i = 1, math.min(k, #scored) do out[i] = scored[i].it end
	return out
end

-- pair swaps over the top-K lists; returns an improved set or nil
local function pairPass(f, set, L)
	local best = f(set)
	local tops = {}
	for _, s in ipairs(SLOTS) do tops[s] = topK(f, set, L, s, PAIR_K) end
	-- off hand: the empty option too
	table.insert(tops[S.OFFHAND], false)
	local bestT, bestV = nil, best
	for i = 1, #SLOTS do
		for j = i + 1, #SLOTS do
			local a, b = SLOTS[i], SLOTS[j]
			for _, x in ipairs(tops[a]) do
				for _, y in ipairs(tops[b]) do
					local t = copy(set)
					t[a] = x or nil
					t[b] = y or nil
					if a == S.MAINHAND and x and Score.IsTwoHand(x) and b ~= S.OFFHAND then t[S.OFFHAND] = nil end
					if b == S.MAINHAND and y and Score.IsTwoHand(y) and a ~= S.OFFHAND then t[S.OFFHAND] = nil end
					if t[S.MAINHAND] and legal(t) then
						local v = f(t)
						if v > bestV + EPS then bestT, bestV = t, v end
					end
				end
			end
		end
	end
	return bestT, bestV
end

local function optimize(f, start, L)
	local set, v = ascend(f, start, L)
	while true do
		local t, tv = pairPass(f, set, L)
		if not t then return set, v end
		set, v = ascend(f, t, L)
	end
end

-- restarts: the given starts plus, for every damage set bonus, every way to wear its pieces at that count
local function setStarts(base, L)
	local starts = {}
	local bySet = {}
	for _, s in ipairs(SLOTS) do
		for _, it in ipairs(L[s]) do
			if it.setID and ns.SetData[it.setID] then
				bySet[it.setID] = bySet[it.setID] or {}
				bySet[it.setID][s] = bySet[it.setID][s] or {}
				table.insert(bySet[it.setID][s], it)
			end
		end
	end
	local DMG = { AGI = 1, AP = 1, RAP = 1, HIT = 1, CRIT = 1, CRIT_RANGED = 1, HASTE = 1, ATTACK_SPEED = 1, HASTE_RATING = 1,
		MELEE_HASTE = 1, RANGED_HASTE = 1,
		EXPERTISE = 1, AP_CREATURE = 1, INT = 1, STR = 1 }
	for sid, slots in pairs(bySet) do
		local def = ns.SetData[sid]
		local useful = false
		for _, b in ipairs(def) do
			if b.stats then for k in pairs(b.stats) do if DMG[k] then useful = true end end end
		end
		if useful and (not def.skill or hasSkill(def.skill, def.skillRank)) then
			-- one start: every piece of the set in its slot (the first listed item per slot); ascent drops what does not pay
			local t = copy(base)
			for s, its in pairs(slots) do
				if not (s == S.FINGER2 or s == S.TRINKET2 or s == S.OFFHAND) then t[s] = its[1] end
			end
			if legal(t) then starts[#starts + 1] = { name = "set " .. sid .. " " .. def.name, set = t } end
		end
	end
	return starts
end

-- coordinate ascent from every start; the TOP_STARTS best local optima then get the pair-swap passes
local TOP_STARTS = 3
local function bestSet(f, starts, L)
	local asc = {}
	for _, st in ipairs(starts) do
		local s, v = ascend(f, st.set, L)
		asc[#asc + 1] = { set = s, v = v, name = st.name }
	end
	table.sort(asc, function(a, b) return a.v > b.v end)
	local best, bestV, from = nil, -math.huge, nil
	for i = 1, math.min(TOP_STARTS, #asc) do
		local s, v = optimize(f, asc[i].set, L)
		if v > bestV + EPS then best, bestV, from = s, v, asc[i].name end
	end
	return best, bestV, from
end

------------------------------------------------------------------------------------------------------------------------
-- Current sets (preraid-bis-60.md section 2; variant A = Game/PreRaidData.lua). 2026-11-17: Peacemaker 18725 replaced
-- Bear Poking Stick 274419 (Barkskin Revered grind); the out/out_*2026-11-16.txt runs still have the stick
------------------------------------------------------------------------------------------------------------------------
local function setOf(ids)
	local t = {}
	for s, id in pairs(ids) do
		local it = byId[id]
		if not it then error("current-set item not among the candidates: " .. id) end
		t[s] = it
	end
	assert(legal(t))
	return t
end
local CUR_A = setOf({ [S.HEAD] = 252605, [S.NECK] = 15411, [S.SHOULDER] = 272105, [S.BACK] = 13340, [S.CHEST] = 252483,
	[S.WRIST] = 18296, [S.HANDS] = 272099, [S.WAIST] = 22232, [S.LEGS] = 22673, [S.FEET] = 13967,
	[S.FINGER1] = 19325, [S.FINGER2] = 272408, [S.TRINKET1] = 13965, [S.TRINKET2] = 19120, [S.MAINHAND] = 18725,
	[S.RANGED] = 13023 })
local CUR_B = setOf({ [S.HEAD] = 252605, [S.NECK] = 15411, [S.SHOULDER] = 18742, [S.BACK] = 13340, [S.CHEST] = 252483,
	[S.WRIST] = 18296, [S.HANDS] = 15063, [S.WAIST] = 22232, [S.LEGS] = 15062, [S.FEET] = 13967,
	[S.FINGER1] = 272408, [S.FINGER2] = 18500, [S.TRINKET1] = 13965, [S.TRINKET2] = 280065, [S.MAINHAND] = 18725,
	[S.RANGED] = 13023 })

------------------------------------------------------------------------------------------------------------------------
-- Report helpers
------------------------------------------------------------------------------------------------------------------------
local function fmtItem(it)
	if not it then return "-" end
	local flags = (it.exalted and " [Exalted]" or "") .. (it.orig and "" or " [not in opt/cands.json]")
		.. (it.hasProc and " [has proc: not modelled]" or "") .. (it.use and " [Use: UseData]" or "")
		.. ((it.hasUse and not it.use) and " [Use: not in UseData]" or "")
	return string.format("%d %s%s", it.id, it.name, flags)
end

-- the pair slots are compared as sets of ids (finger1/finger2 order does not matter)
local function canon(set)
	local c = copy(set)
	for _, pr in ipairs({ { S.FINGER1, S.FINGER2 }, { S.TRINKET1, S.TRINKET2 } }) do
		local a, b = c[pr[1]], c[pr[2]]
		if a and b and a.id > b.id then c[pr[1]], c[pr[2]] = b, a end
	end
	return c
end
local function sameSet(a, b)
	a, b = canon(a), canon(b)
	for _, s in ipairs(SLOTS) do
		if (a[s] and a[s].id) ~= (b[s] and b[s].id) then return false end
	end
	return true
end
-- align the new set's pair slots to the current set's, so a kept ring stays in its slot
local function align(new, cur)
	local n = copy(new)
	for _, pr in ipairs({ { S.FINGER1, S.FINGER2 }, { S.TRINKET1, S.TRINKET2 } }) do
		local a, b = n[pr[1]], n[pr[2]]
		local ca, cb = cur[pr[1]], cur[pr[2]]
		if (a and cb and a.id == cb.id) or (b and ca and b.id == ca.id) then n[pr[1]], n[pr[2]] = b, a end
	end
	return n
end

local function setStats(set, mobDiff)
	local p = pointFor(set, mobDiff)
	local t = sums(set)
	return string.format("hit %.2f%% (+%.2f%% ranged-only), crit %.2f%%, RAP %.0f, MAP %.0f, Agi %d, bow DPS %.1f @%.2f",
		p.hit, p.rangedGearHit, p.crit, p.rap, p.map, BASE.AGI + t.AGI, p.bowDPS, p.bowSpeed)
end

local function printSet(title, set, cur, mobDiff)
	print(title)
	print("  " .. setStats(set, mobDiff))
	for _, s in ipairs(SLOTS) do
		local mark = ""
		if cur then
			local a, b = set[s] and set[s].id, cur[s] and cur[s].id
			if a ~= b then mark = "   <- was " .. fmtItem(cur[s]) end
		end
		print(string.format("  %-9s %s%s", SLOT_NAME[s], fmtItem(set[s]), mark))
	end
end

local function printWeights(st, label)
	local W = st.W
	print(string.format("  W at %s (unit %s = %.4f DPS; model DPS at the point %.1f):", label, st.unit, st.unitDps, st.total))
	local a = W.AGI
	print(string.format("    per point (RAP units): AGI %.3f  AP %.3f  RAP %.3f  INT %.3f  STR %.3f  HIT/1%% %.2f  HIT_RANGED/1%% %.2f  CRIT/1%% %.2f  RANGED_DPS %.2f  HASTE/1%% %.2f  EXPERTISE/1%% %.2f",
		W.AGI, W.AP, W.RAP, W.INT, W.STR, W.HIT, W.HIT_RANGED, W.CRIT, W.RANGED_DPS, W.HASTE, W.EXPERTISE))
	print(string.format("    normalized to Agi = 1:  AP %.3f  RAP %.3f  INT %.3f  hit/rating %.3f  crit/rating %.3f  ranged DPS %.3f",
		W.AP / a, W.RAP / a, W.INT / a, W.HIT / 10 / a, W.CRIT / 14 / a, W.RANGED_DPS / a))
	print("    old Turret EP (Agi = 1):  AP/RAP 0.340  INT 0.420  hit/rating 1.140  crit/rating 0.840  ranged DPS 2.870")
end

------------------------------------------------------------------------------------------------------------------------
-- Run
------------------------------------------------------------------------------------------------------------------------
local function run(variant, cur, L, mobDiff)
	print(string.rep("=", 118))
	print(string.format("VARIANT %s, target +%d (hit cap %.1f%%)", variant, mobDiff, Model.HitCap(mobDiff)))
	local nC = 0; for _, s in ipairs(SLOTS) do nC = nC + #L[s] end
	print(string.format("  candidates over the 17 slots: %d", nC))
	local fD = function(set) return D(set, mobDiff) end

	-- 1) the addon's own logic: best set by Score.SetValue at W of the worn set, worn set <- best, until stable;
	-- once per Score reading of the item stats (scoreItem)
	local fixed = {}
	for _, reading in ipairs(READINGS) do
		local worn = cur
		local seenSets = {}
		local iter = 0
		while true do
			iter = iter + 1
			local st = stateAt(worn, mobDiff, reading)
			local fS = function(set) return Score.SetValue(scoreSet(set, reading), st.W, st.ctx) end
			local starts = { { name = "worn", set = worn } }
			for _, x in ipairs(setStarts(worn, L)) do starts[#starts + 1] = x end
			local nb = bestSet(fS, starts, L)
			local gain = fS(nb) - fS(worn)
			print(string.format("  [%s] SetValue iteration %d: best set's SetValue gain over the worn set %.3f (%.2f DPS by W)", reading, iter, gain, gain * st.unitDps))
			if sameSet(nb, worn) then break end
			local key = {}
			for _, s in ipairs(SLOTS) do key[#key + 1] = tostring(canon(nb)[s] and canon(nb)[s].id) end
			key = table.concat(key, ",")
			if seenSets[key] then print("  SetValue iteration cycles; stopping"); worn = nb; break end
			seenSets[key] = true
			worn = nb
			if iter >= 10 then print("  SetValue iteration: 10 rounds, stopping"); break end
		end
		fixed[reading] = align(worn, cur)
	end

	-- 2) the model's DPS of whole sets
	local starts = { { name = "current", set = cur } }
	for _, reading in ipairs(READINGS) do starts[#starts + 1] = { name = "SetValue fixed point [" .. reading .. "]", set = fixed[reading] } end
	for _, x in ipairs(setStarts(cur, L)) do starts[#starts + 1] = x end
	local setD, vD, from = bestSet(fD, starts, L)
	setD = align(setD, cur)

	local dCur = fD(cur)
	print(string.format("  D(current %s) = %.2f DPS   [%s]", variant, dCur, setStats(cur, mobDiff)))
	print(string.format("  D(best by D) = %.2f DPS  (found from start: %s; %s current)", vD, from,
		sameSet(setD, cur) and "same as" or "differs from"))
	printSet("  BEST SET BY D (model DPS):", setD, cur, mobDiff)
	-- the addon's fixed points: D, and the exact slot changes vs the current set (only the changed slots)
	for _, reading in ipairs(READINGS) do
		local setS = fixed[reading]
		print(string.format("  SetValue fixed point [%s]: D = %.2f DPS (%+.2f vs current); %s current; %s best by D", reading,
			fD(setS), fD(setS) - dCur, sameSet(setS, cur) and "same as" or "differs from",
			sameSet(setS, setD) and "same as" or "differs from"))
		local any = false
		for _, s in ipairs(SLOTS) do
			if (setS[s] and setS[s].id) ~= (cur[s] and cur[s].id) then
				any = true
				print(string.format("    %-9s %s   <- was %s", SLOT_NAME[s], fmtItem(setS[s]), fmtItem(cur[s])))
			end
		end
		if not any then print("    (no slot changed)") end
	end
	print("  single-slot swaps, current set -> best-by-D item in that slot alone (D gain):")
	for _, s in ipairs(SLOTS) do
		local a, b = setD[s], cur[s]
		if (a and a.id) ~= (b and b.id) then
			local t = place(cur, s, a)
			if not legal(t) then
				print(string.format("    %-9s %s: alone not legal with the current set", SLOT_NAME[s], fmtItem(a)))
			else
				print(string.format("    %-9s %+7.2f DPS  %s", SLOT_NAME[s], fD(t) - dCur, fmtItem(a)))
			end
		end
	end
	-- sensitivity: ranged-only hit at 0 (how the game renders the line and whether the live hit holds it are unchecked in
	-- game: /hga dump writes the parsed stats and the hit modifiers)
	do
		local L0 = {}
		local zero = {}
		local f0 = function(set)
			local c = {}
			for s, it in pairs(set) do
				if it.stats.RHIT then
					local z = zero[it]
					if not z then z = setmetatable({ stats = copy(it.stats) }, { __index = it }); z.stats.RHIT = nil; zero[it] = z end
					c[s] = z
				else c[s] = it end
			end
			return D(c, mobDiff)
		end
		local s0, v0 = bestSet(f0, { { name = "best by D", set = setD }, { name = "current", set = cur } }, L)
		s0 = align(s0, cur)
		if sameSet(s0, setD) then
			print("  sensitivity, ranged-only hit counted as 0: the same best set")
		else
			printSet(string.format("  sensitivity, ranged-only hit counted as 0 (best %.2f DPS by that count):", v0), s0, setD, mobDiff)
		end
	end
	-- items with a damage proc or an unmodelled Use near the top of each slot of the best set (pruning list)
	print("  not-modelled effects near the top (within 15 DPS of the chosen item, by D without the effect):")
	local base = fD(setD)
	for _, s in ipairs(SLOTS) do
		local rows = {}
		for _, it in ipairs(L[s]) do
			if (it.hasProc or (it.hasUse and not it.use)) and it ~= setD[s] then
				local t = place(setD, s, it)
				if legal(t) then
					local g = fD(t) - base
					if g > -15 then rows[#rows + 1] = { it = it, g = g } end
				end
			end
		end
		table.sort(rows, function(a, b) return a.g > b.g end)
		for i = 1, math.min(5, #rows) do
			print(string.format("    %-9s %+7.2f  %s :: %s", SLOT_NAME[s], rows[i].g, fmtItem(rows[i].it), rows[i].it.effects))
		end
	end
	local stCur = stateAt(cur, mobDiff, "parse")
	printWeights(stCur, "current " .. variant)
	local stD = stateAt(setD, mobDiff, "parse")
	printWeights(stD, "best-by-D set")
	local fx = {}
	for _, reading in ipairs(READINGS) do fx[reading] = { set = fixed[reading], d = fD(fixed[reading]) } end
	return { cur = cur, setD = setD, fixed = fx, dCur = dCur, vD = vD }
end

local LA = listsFor(function(it) return false end)
-- variant B: no Exalted item, no battleground reputation, no Barkskin Burrow (convert.py repB)
local LB = listsFor(function(it) return it.exalted or it.repB end)
local results = {}
-- target level - player level: the point is a level-60 hunter, whose target is the raid boss +3 (8% cap: Player.Snapshot
-- takes the target by the mode, the user's «на 60 на рейды»; no setting picks another). The pass runs in raid mode
-- (pointFor: the raid inputs, the fight with the mana)
local MOB_DIFFS = { 3 }
-- env RESCORE_VARIANTS ("A", "B" or "AB", default AB) narrows a run to one variant
local VARS = os.getenv("RESCORE_VARIANTS") or "AB"
for _, md in ipairs(MOB_DIFFS) do
	if VARS:find("A") then results["A" .. md] = run("A", CUR_A, LA, md) end
	if VARS:find("B") then results["B" .. md] = run("B", CUR_B, LB, md) end
end
print(string.rep("=", 118))
print("SUMMARY (model DPS D):")
for _, md in ipairs(MOB_DIFFS) do
	for _, v in ipairs({ "A", "B" }) do
		local r = results[v .. md]
		if r then
		print(string.format("  +%d %s: current %.2f  best %.2f  (+%.2f, %s)", md, v, r.dCur, r.vD, r.vD - r.dCur,
			sameSet(r.setD, r.cur) and "unchanged" or "CHANGED"))
		for _, reading in ipairs(READINGS) do
			local f = r.fixed[reading]
			print(string.format("      addon SetValue fixed point [%s]: D %.2f (%+.2f), %s current, %s best by D", reading, f.d,
				f.d - r.dCur, sameSet(f.set, r.cur) and "same as" or "differs from", sameSet(f.set, r.setD) and "same as" or "differs from"))
		end
		end
	end
end
