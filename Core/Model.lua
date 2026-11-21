-- The damage model of a WoW Forever hunter, and its stat weights: Model.Parts / Model.Total give the damage per
-- second of the hunter, the pet, the dive and the hawks from the inputs p (the fields listed above Model.Parts:
-- mode, level, rap, map, agi, crit, meleeCrit, hit, rangedHit, rangedSkill, meleeHit, mhSkill, ohSkill, rangedGearHit,
-- expertise, haste, attackSpeed, hasteRating, meleeHaste, rangedHaste, the ranged weapon bowDPS and bowSpeed, ammoDPS,
-- quiver, the melee weapons
-- mhDPS, mhSpeed, mhNorm, ohDPS, ohSpeed, twoH, unarmed and beastSlaying, apVsTarget, spellHit, spellCrit, mobDiff,
-- survival, orc (the Command racial), the
-- pet's state petOut, family petFamily and swing time petSwing, serpentTick, noShots, the raid inputs manaMax, regenRest,
-- regenCast, spirit and armorPen, the raid fight's Use buffs uses, the pet's held attack powers petRap and petMap, and the
-- talent ranks p.tal); Model.LandedHits gives the hunter's own landed hits by
-- hand from the same pass (Score prices the chance-on-hit procs on them), Model.TotalAndHits the total and the hits from
-- one pass, Model.Weave the Survival branch's weave cycle, Model.Fight the raid fight; Model.Weights takes the derivatives of
-- Model.Total in the weights' unit (1 RAP; 1 melee attack power where RAP adds no damage; 1 DPS where neither does,
-- Model.Weights). Talent ranks are read live in game; the per-rank values are the Forever DB2
-- TraitDefinitionEffectPoints curves.
-- Formulas and sources: the comments here, project memory hunter-stat-weights.md and docs/research/*.md.
-- This file is the model. tools/weights_model.py is an outdated level-43 prototype of it (a fixed armor
-- multiplier 0.70, the pet's haste x1.02, glancing x0.95; no noShots, rangedHit, petSwing, attack speed inputs or
-- armor by level), which nothing in the addon reads.
-- Weights are DAMAGE ONLY (the weights' unit). Survival is compared separately, after damage (Score.Secondary), and so is
-- mana while levelling; in raid mode mana limits the casts of the fight and its stats have damage weights. Pure Lua 5.1: no
-- WoW API here.

local _, ns = ...
local Model = {}
ns.Model = Model

-- % crit per point of Agility for hunters, levels 1..60 (Forever DB2 PlayerExpectedStat ClassID 3).
local CRIT_PER_AGI = {
	0.002174, 0.002083, 0.002, 0.001852, 0.001786, 0.001724, 0.001667, 0.001613, 0.001515, 0.001471,
	0.001351, 0.00119, 0.001087, 0.001, 0.000909, 0.000862, 0.000806, 0.000746, 0.000704, 0.000658,
	0.000633, 0.000595, 0.000568, 0.000538, 0.000515, 0.000495, 0.000472, 0.000455, 0.000435, 0.000417,
	0.000407, 0.000391, 0.000376, 0.000365, 0.000352, 0.000342, 0.000331, 0.000321, 0.000311, 0.000303,
	0.000296, 0.000287, 0.000279, 0.000272, 0.000265, 0.000259, 0.000253, 0.000245, 0.000239, 0.000234,
	0.000229, 0.000224, 0.000219, 0.000214, 0.000209, 0.000206, 0.000201, 0.000197, 0.000192, 0.000189,
}

-- Creature auto-attack DPS by level 1..60 (Forever DB2 ExpectedStat, ExpansionID -2,
-- CreatureAutoAttackDps). A pet's white damage is tied to it: pet sheets at levels 11/17/30 read
-- floor(4.2 x this) as their own attack power, and the level-30 Cat's swings fit this DPS plus
-- inherited AP / 14 (wowsims docs/evidence EV-0070, EV-0071; pets.go). Hawks swing for 0.185 of it
-- (EV-0073, fitted at level 48).
local CREATURE_DPS = {
	0.770, 1.157, 1.629, 2.251, 3.006, 4.004, 5.184, 6.024, 6.906, 7.620,
	8.600, 9.836, 10.713, 11.808, 12.855, 13.587, 14.564, 15.253, 16.182, 17.103,
	17.745, 18.599, 19.227, 20.052, 20.828, 21.485, 22.348, 22.996, 23.822, 24.694,
	25.316, 26.084, 26.739, 27.511, 28.256, 28.944, 29.852, 30.626, 31.589, 32.586,
	34.143, 36.286, 38.707, 41.914, 43.993, 44.895, 46.021, 46.929, 48.030, 49.202,
	50.160, 51.385, 52.369, 53.563, 54.683, 55.763, 56.940, 58.032, 59.215, 60.453,
}

-- Creature armor by level 1..63 (Forever DB2 ExpectedStat, ExpansionID -2, CreatureArmor). The
-- armor constant there is 400 + 85 x level at every level. Open-world mobs may carry an
-- ExpectedStatMod armor factor (rows 0.51 / 0.81 / 1.0 exist; which one ordinary mobs get is not
-- known), so CONST.armorMod is 1.0, the value wowsims' level-63 target (3731) matches.
local CREATURE_ARMOR = {
	20, 21, 46, 82, 126, 180, 245, 322, 412, 518, 545, 580, 615, 650, 685, 721, 756, 791, 826, 861,
	897, 932, 967, 1002, 1037, 1072, 1108, 1142, 1177, 1212, 1247, 1283, 1317, 1353, 1387, 1494, 1607, 1724,
	1849, 1980, 2117, 2262, 2414, 2574, 2742, 2798, 2853, 2907, 2963, 3018, 3072, 3128, 3183, 3237, 3292,
	3348, 3402, 3457, 3512, 3566, 3622, 3677, 3731,
}

-- {learned at level, value} rank tables (Forever DB2 SpellLevels / SpellEffect). Serpent Sting IX
-- (135, spell 25295) and Aspect of the Hawk VII (120, spell 25296) come from books (Guide:
-- Serpent Sting IX / Guide: Aspect of the Hawk VII), not the trainer, so they are not here: the
-- game side passes them in only when the spell is known (p.serpentTick, Player's Aspect RAP).
local RANKS = {
	aspectHawk = { {10, 20}, {18, 35}, {28, 50}, {38, 70}, {48, 90}, {58, 110} },
	huntersMark = { {6, 26}, {22, 59}, {40, 98}, {58, 143} },
	aimedBonus = { {20, 40}, {28, 70}, {36, 115}, {44, 185}, {52, 260}, {60, 350} },
	arcaneBase = { {6, 25}, {12, 35}, {20, 50}, {28, 85}, {36, 120}, {44, 175}, {52, 220}, {60, 280} },
	serpentTick = { {4, 3}, {10, 7}, {18, 14}, {26, 26}, {34, 40}, {42, 58}, {50, 75}, {58, 100} },
	hawkDive = { {25, 32}, {36, 47}, {48, 85}, {60, 108} },
	raptorBonus = { {1, 5}, {8, 11}, {16, 21}, {24, 30}, {32, 35}, {40, 40}, {48, 55}, {56, 70} },
	sniperBonus = { {40, 320}, {48, 450}, {58, 590} },         -- Sniper Shot 1310687 / 1310785 / 1310786
	-- Wing Clip 2974 / 14267 / 14268: SpellEffect 680817 / 690318 / 690647 (Effect 2, physical, EffectBonusCoefficient 1)
	-- base points 5 / 25 / 50, SpellLevels 98126 / 101362 / 101488
	wingClip = { {12, 5}, {38, 25}, {60, 50} },
	-- Immolation Trap's tick (the trap spells 13797 / 14298 / 14299 / 14300 / 14301: SpellEffect 691012 / 691189 / 690934 /
	-- 690935 / 691047, aura 3 A_PERIODIC_DAMAGE every 3000 ms, base points 21 / 43 / 68 / 102 / 138), learned with the
	-- trap ranks 13795 / 14302 / 14303 / 14304 / 14305 (SpellLevels 101691 / 101800 / 101722 / 101758 / 101793)
	immolationTick = { {16, 21}, {26, 43}, {36, 68}, {46, 102}, {56, 138} },
	mongooseBonus = { {16, 15}, {30, 22}, {44, 37}, {58, 57} }, -- Mongoose Bite 1495 / 14269 / 14270 / 14271
	trueshot = { {25, 20}, {32, 35}, {40, 50}, {50, 75}, {60, 100} }, -- Trueshot Aura RAP (1299346 .. 20906)
	-- pet abilities: flat damage, no attack power share (BonusCoefficientFromAP 0); Claw 16827..3009
	-- costs 25 focus, Bite 17253..17261 35 focus with a 10 s cooldown (wowsims spell store)
	petClaw = { {1, 5}, {8, 10}, {16, 14}, {24, 19}, {32, 25}, {40, 31}, {48, 42}, {56, 51} },
	petBite = { {1, 8}, {8, 17}, {16, 26}, {24, 34}, {32, 44}, {40, 54}, {48, 73}, {56, 90} },
}

function Model.Rank(name, level)
	local value = 0
	for _, entry in ipairs(RANKS[name]) do
		if level >= entry[1] then value = entry[2] end
	end
	return value
end

function Model.CritPerAgility(level)
	local idx = math.max(1, math.min(60, level))
	return CRIT_PER_AGI[idx] * 100 -- in % per Agility
end

-- Pet families by the id UnitCreatureFamily returns (Forever DB2 CreatureFamily, build 70888):
-- the Tamed Pet Passive's damage (SpellEffect aura 79 misc 1) and which of Claw / Bite the family
-- learns (wowsims pet_families_auto_gen.go, generated from the game files' skill lines).
Model.PET_FAMILY = {
	[1] = { pct = 0, bite = true },                -- Wolf (17223)
	[2] = { pct = 10, claw = true, bite = true },  -- Cat (17210)
	[3] = { pct = 7, bite = true },                -- Spider (17219)
	[4] = { pct = -9, claw = true, bite = true },  -- Bear (17208)
	[5] = { pct = -10, bite = true },              -- Boar (7000)
	[6] = { pct = 0, bite = true },                -- Crocolisk (17212)
	[7] = { pct = 0, claw = true, bite = true },   -- Carrion Bird (17209)
	[8] = { pct = -5, claw = true },               -- Crab (17211)
	[9] = { pct = 2, bite = true },                -- Gorilla (17214)
	[11] = { pct = 10, claw = true, bite = true }, -- Raptor (17217)
	[12] = { pct = 0, bite = true },               -- Tallstrider (17220)
	[20] = { pct = -6, claw = true },              -- Scorpid (17218)
	[21] = { pct = -10, bite = true },             -- Turtle (17221)
	[24] = { pct = 7, bite = true },               -- Bat (17206)
	[25] = { pct = 0, bite = true },               -- Hyena (17215)
	[26] = { pct = 7, claw = true },               -- Bird of Prey (17216)
	[27] = { pct = 7, bite = true },               -- Wind Serpent (17222)
	[312] = { pct = 1, bite = true },              -- Core Hound (444831)
	[319] = { pct = 0, bite = true },              -- Fox (17223, as wowsims reads it)
}
-- No pet seen yet (dismissed since login): no family bonus, Claw and Bite both. The game side
-- says so in /hga weights.
Model.PET_FAMILY_UNKNOWN = { pct = 0, claw = true, bite = true }

Model.AP_CREATURE_SHARE = 0.3 -- "+N Attack Power vs <creature type>": share of mobs of that type
-- The creature types of the attack power against a type (item stats AP_VS_<TYPE>: Core/Parse.lua, Game/SetData.lua): the
-- types a versus aura's mask names, bit 1 << (type - 1) (wowsims sim/core/spelldata/mob_types.go:32-55; Critter has no mob
-- type there). Player.Snapshot sums the worn ones into p.apVsTarget at the mode's share of each (Model.TargetShare);
-- Model.Weights prices each key at W.AP_VS x that share.
Model.CREATURE_TYPES = { "BEAST", "DRAGONKIN", "DEMON", "ELEMENTAL", "GIANT", "UNDEAD", "HUMANOID", "MECHANICAL" }

-- The user's build from the 2026-11-12 screenshot (BM 32 / MM 2). Only the tests and the
-- reference numbers use it; in game the live talents are read, and while they cannot be read
-- the addon says so instead of assuming this build.
Model.DEFAULT_TALENTS = {
	deadlyAspects = 5, enduranceTraining = 1, focusedFire = 2, unleashedFury = 5, ferocity = 5,
	summonHawk = 1, frenzy = 4, bestialWrath = 1, bestialDiscipline = 2, lethalAttacks = 2,
	carefulAim = 0, mortalShots = 0, barrage = 0, rangedWeaponSpec = 0, improvedStings = 0, efficiency = 0,
	lightningReflexes = 0, survivalist = 0, predatorsEdge = 0, loneWolf = 0,
	sniperShot = 0, improvedArcaneShot = 0, rapidKilling = 0, trueshotAura = 0, rapidRecuperation = 0,
	improvedTracking = 0, savageStrikes = 0, surefooted = 0, striderKick = 0, exposePrey = 0,
	laceratingStrikes = 0, resourcefulness = 0, cleverTraps = 0, survivalTactics = 0, survivalistsDiscipline = 0,
}

-- per-rank values (Forever DB2 TraitDefinitionEffectPoints curves)
local IMPROVED_STINGS = { 0.06, 0.13, 0.20 }
-- No silent default build: a caller without talent ranks is a bug (the game side says
-- "talents not read yet" instead of calling the model). The ranks name every talent the model reads: Player.ReadTalents
-- gives every talent of Player.BRANCHES a rank, 0 for one not taken (the tests: Model.DEFAULT_TALENTS), so a talent
-- missing from them is an error too.
local function rankOf(t, name)
	local r = t[name]
	if r == nil then error("HunterGearAdvisor: talent ranks without " .. tostring(name), 3) end
	return r
end
local function talents(p)
	local t = p.tal
	if not t then error("HunterGearAdvisor: Model called without talent ranks (p.tal)", 3) end
	return function(name) return rankOf(t, name) end
end

-- The level of raid mode: the level cap of WoW Forever, 60, where the target is a raid boss of level 63
-- (Forever UI Camelot/SkillsFrame.lua:57-58: WEAPON_SKILL_BOSS_LEVEL_OFFSET = 3, RAID_BOSS_LEVEL = 63). The user (2026-11-17):
-- below 60 the gear is chosen for levelling, at 60 for the raid. Player.Snapshot sets p.mode by it.
Model.RAID_LEVEL = 60
-- The raid boss's level (Forever UI Camelot/SkillsFrame.lua:57-58 RAID_BOSS_LEVEL = 63; wowsims' hunter preset
-- ui/specs/hunter/dps/defaults.siml:64 level=63): the attacker whose hits the survival tie-break's armor reduces in raid
-- mode (Score.Secondary)
Model.RAID_BOSS_LEVEL = 63

-- The inputs (the p fields listed above Model.Parts) every producer sets, which the model reads directly: Player.Snapshot
-- gives the mode by the level (Model.RAID_LEVEL), the live reading (level, rap, map, agi, crit, meleeCrit, hit, spellHit,
-- spellCrit, the stat multipliers statMult and the raid inputs manaMax, regenRest, regenCast, spirit), the worn gear's ranged-only hit (rangedGearHit), the
-- worn items' and set bonuses' expertise, attack power against a creature type (apVsTarget) and armor penetration (the
-- raid input armorPen), the worn attack speed by
-- source (wornHaste: haste, attackSpeed, hasteRating, meleeHaste, rangedHaste), ammoDPS (0 without ammo), quiver, mobDiff by the mode (0 levelling, 3 raid), survival by the
-- talent points (Player.SurvivalBranch), and every weapon field through Player.WeaponInputs (bowDPS, bowSpeed, noShots, mhDPS, mhSpeed,
-- mhNorm, ohDPS, ohSpeed, twoH, unarmed: the main hand without a weapon at 0 DPS and the unarmed 1.0 s, another slot
-- at 0 DPS and NO_WEAPON_SPEED, unarmed without a weapon the melee strikes take; beastSlaying); Advisor
-- A.State adds rangedSkill (the worn ranged weapon's skill over 5 x level, 0 with no bow, gun or crossbow) and rangedHit
-- (Model.SkillHit of it, 0 at the level's skill), mhSkill and ohSkill (the worn hands' melee weapon skill over 5 x level,
-- 0 for a hand without a melee weapon) and meleeHit (Model.SkillHit of mhSkill), and its per-set weapon model takes that
-- point with Player.WeaponInputs and the melee skills of the set. So one missing is an error, raised once where a pass
-- starts (checkInputs).
-- The raid inputs (RAID_REQUIRED) are
-- required in raid mode alone (checkMode). The inputs a real state leaves nil are not here: serpentTick (Serpent Sting IX
-- from the book not known: the trainer rank), petFamily (no pet seen this session, or a family Model.PET_FAMILY lacks:
-- Model.PET_FAMILY_UNKNOWN), petSwing (no pet swing read yet: Model.PET_BASE_SWING) and orc (the race secret: counted
-- as an orc). petOut is required: Player.PetOut gives true without Lone Wolf and, with it, whether a living pet is out
-- (Forever UnitDocumentation.lua:1192 UnitExists and :1916 UnitIsDead: bool, Nilable = false).
local REQUIRED_NUMBERS = { "level", "rap", "map", "agi", "crit", "meleeCrit", "hit", "rangedHit", "rangedSkill", "meleeHit",
	"mhSkill", "ohSkill", "rangedGearHit", "expertise",
	"haste", "attackSpeed", "hasteRating", "meleeHaste", "rangedHaste", "bowDPS", "bowSpeed", "ammoDPS", "quiver", "mobDiff",
	"mhDPS", "mhSpeed", "mhNorm", "ohDPS", "ohSpeed", "beastSlaying", "apVsTarget", "spellHit", "spellCrit" }
local REQUIRED_FLAGS = { "twoH", "unarmed", "noShots", "survival", "petOut" }
local RAID_REQUIRED = { "manaMax", "regenRest", "regenCast", "spirit", "armorPen" }
local function checkInputs(p, numbers, flags)
	for _, k in ipairs(numbers) do
		if type(p[k]) ~= "number" then error("HunterGearAdvisor: Model input p." .. k .. " missing or not a number: " .. tostring(p[k]), 3) end
	end
	for _, k in ipairs(flags) do
		if type(p[k]) ~= "boolean" then error("HunterGearAdvisor: Model input p." .. k .. " missing or not true / false: " .. tostring(p[k]), 3) end
	end
end
-- p.mode: "level" (levelling) or "raid" (the raid boss), anything else an error. Raid mode is defined for the level-60
-- hunter alone (Model.RAID_LEVEL), so raid at another level is an error too, and it requires the raid inputs. The model
-- never takes the mode from p.level: a test may run levelling mode at level 60.
-- p.statMult: a factor of 1 or more for each of AGI, STR, INT and SPI (Player.ReadStats multiplies the positive percents
-- of Game/StatMultData.lua, so a factor below 1 or a missing one is no reading's).
local STAT_MULT_KEYS = { "AGI", "STR", "INT", "SPI" }
local function checkStatMult(p)
	local m = p.statMult
	if type(m) ~= "table" then
		error("HunterGearAdvisor: Model input p.statMult missing or not a table: " .. tostring(m), 4)
	end
	for _, k in ipairs(STAT_MULT_KEYS) do
		if type(m[k]) ~= "number" or not (m[k] >= 1) then
			error("HunterGearAdvisor: Model input p.statMult." .. k .. " missing or below 1: " .. tostring(m[k]), 4)
		end
	end
end
local function checkMode(p)
	if p.mode ~= "raid" and p.mode ~= "level" then
		error("HunterGearAdvisor: Model input p.mode must be 'raid' or 'level': " .. tostring(p.mode), 3)
	end
	checkStatMult(p)
	if p.mode == "raid" then
		if p.level ~= Model.RAID_LEVEL then
			error("HunterGearAdvisor: Model input p.mode 'raid' is defined at level " .. Model.RAID_LEVEL .. " alone: p.level " .. tostring(p.level), 3)
		end
		checkInputs(p, RAID_REQUIRED, {})
		if p.uses ~= nil and type(p.uses) ~= "table" then
			error("HunterGearAdvisor: Model input p.uses is not a list of Use buffs: " .. tostring(p.uses), 3)
		end
		-- the raid fight's consumables' events held (Model fight; raid-mode design 25.1): { manaPotion = true / false, runes =
		-- the rune's times, rising }, the form Model.FightEvents gives
		local ev = p.events
		if ev ~= nil then
			local ok = type(ev) == "table" and type(ev.manaPotion) == "boolean" and type(ev.runes) == "table"
			if ok then
				local last = -math.huge
				for i, t in ipairs(ev.runes) do
					if type(t) ~= "number" or t < last then ok = false end
					last = type(t) == "number" and t or last
				end
				for k in pairs(ev.runes) do
					if type(k) ~= "number" or k < 1 or k > #ev.runes or k % 1 ~= 0 then ok = false end
				end
			end
			if not ok then
				error("HunterGearAdvisor: Model input p.events is not { manaPotion = true / false, runes = rising times }: " .. tostring(ev), 3)
			end
		end
	elseif p.uses ~= nil then
		-- levelling prices a Use buff in Score over its average uptime (Score.SetValue), never through the model
		error("HunterGearAdvisor: Model input p.uses in levelling mode (the Use buffs run in the raid fight alone)", 3)
	elseif p.events ~= nil then
		-- levelling has no fight, no event to hold
		error("HunterGearAdvisor: Model input p.events in levelling mode (the raid fight alone has events)", 3)
	end
	-- the pet's attack powers held at a point's (Model fight, Model.Weights' Use weights): both or neither, numbers
	if (p.petRap == nil) ~= (p.petMap == nil) or (p.petRap ~= nil and (type(p.petRap) ~= "number" or type(p.petMap) ~= "number")) then
		error("HunterGearAdvisor: Model inputs p.petRap and p.petMap come together, as numbers: " .. tostring(p.petRap) .. ", " .. tostring(p.petMap), 3)
	end
end

-- A mob level difference (mobDiff) for PhysMult, GlanceMult and MobAvoid: every caller passes one (Model.Parts its
-- p.mobDiff; Advisor A.State the model point's), so a missing one is an error.
local function needMobDiff(mobDiff, fn)
	if type(mobDiff) ~= "number" then error("HunterGearAdvisor: Model." .. fn .. " without a mob level difference: " .. tostring(mobDiff), 3) end
end

local CONST = {
	armorMod = 1.0,       -- creature armor factor (see CREATURE_ARMOR)
	serpentUptime = 0.8,
	-- Serpent Sting's duration in s: every rank (1978, 13549-13555, 25295) has SpellMisc DurationIndex 8, SpellDuration 8
	-- Duration 15000 ms (Forever DB2 build 70888), 5 ticks of SpellEffect EffectAuraPeriod 3000 ms
	serpentDuration = 15,
	hawkUptime = 0.9,
	-- a hawk lives 18 s from its summon (Summon Hawk's 1293248: SpellMisc 840689 DurationIndex 85 = 18000 ms; wowsims
	-- sim/hunter/summon_hawk.go:14-15, 140-147): the raid fight's hawk uptime min(1, 18 / C) (Model.Parts)
	hawkDuration = 18,
	hawkLearnLevel = 25,
	-- a hawk's swing time in s, the 2.5 s its swing damage is fitted over (wowsims sim/hunter/summon_hawk.go:48-58 hawkSwing
	-- SwingSpeed 2.5, EV-0073): Model.Parts' hawk part is a damage a second, its swings a second hawkSpeed / hawkSwing
	hawkSwing = 2.5,
	happy = 1.25,
	-- the hawk fit (EV-0073 line 18) holds Unleashed Fury 5/5 (x1.15) and Focused Fire 2/2 (x1.02), which
	-- Model.Parts divides out of the hawks before it applies the live ranks
	hawkFitMult = 1.15 * 1.02,
	-- Shots that compete for the global cooldown and for cast time: the share of their cooldown
	-- actually used. Arcane from the wowsims turret APL (~93% at IAS 0, ~87% at 5/5); Aimed and
	-- Sniper from a rotation simulation of that APL's priorities (Serpent, Sniper, Aimed, Arcane;
	-- cooldowns start after the cast; GCD 1.5 s): Aimed 0.93-0.98 alone, 0.79-0.84 next to Sniper
	-- Shot, Sniper 0.91-1.0. Estimates, not measured in game.
	arcaneUse = 0.9,
	aimedUse = 0.92,
	aimedUseSniper = 0.80,
	sniperUse = 0.95,
	-- Rapid Killing: the levelling mode's seconds from one kill to the next (estimate); each kill gives the next Shot
	-- +10%/rank within 20 s (DB2 415405 / 415407). Raid mode has no kill inside the fight: the buff comes on a killing blow
	-- or when the enemy dies with the hunter's Serpent Sting on it (wowsims sim/hunter/talents_marksmanship.go:87-91), once,
	-- at the fight's end, on a single target, so it adds nothing to Aimed Shot there (raid-mode design 6.6)
	killInterval = 25,
	trackUptime = 1.0,    -- Improved Tracking: share of time the target's type is tracked
	-- the levelling mode's share of time the mob faces the pet (solo: the pet tanks), so the pet's attacks from the front
	-- can be parried as well as dodged (CR_PET_EXPERTISE_TOOLTIP: expertise lowers both; equal-level creature 5% dodge, 5%
	-- parry); raid mode: CONST.raid.petTanks, the pet behind the boss (Model.PetTanks)
	petTanks = 1.0,
	-- Resourcefulness (talent node 104983 -> TraitNodeEntry 129647, 2 ranks -> TraitDefinition 134448 -> spell 440529):
	-- a melee or ranged ability crit (SpellAuraOptions 242512 ProcTypeMask 0x110) triggers the buff 1242688 with the
	-- chance of effect 1 (SpellEffect 1134468, aura 42 A_PROC_TRIGGER_SPELL; TraitDefinitionEffectPoints 23260, curve
	-- 85425: 50 at rank 1, 100 at rank 2), so 50% a rank; 1242688 lasts 30 s (SpellMisc DurationIndex 9). This is the
	-- share of time 1242688 is up for each rank, an estimate: the DB2 gives the chance, not the crits it rolls on.
	resourcefulnessUptime = 0.4,
	-- Quick Shots 6150 lasts 12 s (SpellMisc 318442 DurationIndex 29 = 12000 ms): its uptime is the chance that one of
	-- the Auto Shots of the last 12 s rolled it
	quickShotsDuration = 12,
	-- The raid target of raid mode (raid-mode design section 5; the user's answers 3 = (b), 5 = (a) and O7 = (a)): wowsims'
	-- boss of the hunter preset (ui/specs/hunter/dps/defaults.siml:46-48 debuffs, 58-71 encounter) with the preset's debuffs
	raid = {
		-- the boss's armor (defaults.siml:66 armor=3731; Forever DB2 ExpectedStat ID 63, level 63, CreatureArmor 3731)
		bossArmor = 3731,
		-- one debuff of each armor category (sim/core/buffs/debuffs_auto_gen.go:85-147): MajorArmorReduction, Sunder Armor
		-- 11597 at five stacks (SpellEffect 688831 aura 674 -450 a stack, SpellAuraOptions 124201 CumulativeAura 5) or
		-- Expose Armor 11198 at five combo points (SpellEffect 688758 PointsPerResource -450): 2250
		majorArmorReduction = 2250,
		-- MinorArmorReduction, Faerie Fire 9907 (SpellEffect 687337 aura 674 -505) or Curse of Recklessness 11717 (SpellEffect
		-- 690026 aura 674 -505)
		minorArmorReduction = 505,
		-- the boss's creature type (defaults.siml:65 mob_type=dragonkin): AP and Beastslaying against a creature type count
		-- for it alone (Model.TargetShare)
		targetType = "DRAGONKIN",
		-- the pet behind the boss: wowsims' presets set no in_front_of_target (defaults.siml, builds/bm.siml), the pet takes
		-- its owner's place (sim/core/pet.go:145), and parry and block come from the front alone
		-- (sim/core/spell_outcome.go:884-893)
		petTanks = 0,
		-- Curse of the Elements 1311680 (rank 4): SpellEffect 1342154 aura 87 A_MOD_DAMAGE_PERCENT_TAKEN +10 on schools 126,
		-- every magic school: the target's school damage taken multiplier (sim/core/spelldata/parse_effects_table.go:196-199);
		-- its -75 resistance (SpellEffect 1342153) adds nothing, a resistance below 0 adding nothing
		-- (sim/core/spell_resistances.go:64-76)
		coe = 1.10,
		-- Gift of Arthas 11374: SpellEffect 689853 aura 14 A_MOD_DAMAGE_TAKEN +8 on the physical school (misc 1), wowsims'
		-- BonusPhysicalDamageTaken (parse_effects_table.go:221-224), added to every physical-school hit on the target after
		-- the attacker's multipliers and the armor, before the target's multipliers and the outcome
		-- (sim/core/spell_result.go:391-401, 928-936)
		giftOfArthas = 8,
		-- The fight (raid-mode design section 6): wowsims' encounter of the hunter preset, 180 s drawn uniformly in 180 +- 5 s
		-- each iteration (defaults.siml:58-59 duration 180, duration_variation 5; sim/core/sim.go:410-414), the time weight
		-- Model fightIntegral
		fight = 180,
		fightVariation = 5,
		-- the BM rotation casts every ready major cooldown from 5 s (apls/turret_hawk.apl.siml:12 autocast_other_cooldowns if
		-- current_time >= 5s; sim/core/apl_actions_casting.go:596-619): Rapid Fire, Bestial Wrath, the Use buffs of the gear
		cooldownsFrom = 5,
		-- The BM build's cast tempo (raid-mode design 6.4-6.5, approximation A1): the reaction drawn uniformly in 150-350 ms at
		-- every instant the rotation looks (ui/specs/hunter/dps/builds/bm.siml:8 reaction_time 150ms 350ms;
		-- sim/core/gcd.go:133-143), the global cooldown of 1500 ms (GCDMs 1500 of Summon Hawk 1293527, Arcane Shot 14287,
		-- Serpent Sting 13555, Aimed Shot 20904, Sniper Shot 1310786: wowsims spells_auto_gen.go), and Serpent Sting's travel
		-- from the hunter at 12 yd (bm.siml:9 distance_from_target 12) at its missile speed 40 yd/s (SpellMisc 324120 / 333617
		-- Speed 40; wowsims sim/core/spell.go:1005-1010 TravelTime): 0.3 s
		reactionMin = 0.15,
		reactionMax = 0.35,
		gcd = 1.5,
		distance = 12,
		serpentSpeed = 40,
		-- Summon Hawk's category cooldown, the shared 6 s of category 1173 (SpellCooldowns 54834 / 99423 CategoryRecoveryTime
		-- 6000; wowsims spells_auto_gen.go:35894): the HHA sequence's second Summon Hawk is ready 6 s after its first
		hawkCategory = 6,
	},
	-- Rapid Fire 3045 (from 26): 15 s (SpellMisc 314846 DurationIndex 8 = 15000 ms), its category cooldown 300 s
	-- (SpellCooldowns 53197 CategoryRecoveryTime 300000), Rapid Killing -60 s a rank (415405: SpellEffect 1085319, aura 107
	-- misc 11 SPELLMOD_COOLDOWN on Rapid Fire's class mask, -120000 ms at the top rank of two); +40% ranged and melee speed
	-- (SpellEffect 679813 index 0 aura 140 A_MOD_RANGED_HASTE, 1339717 index 3 aura 319 A_MOD_MELEE_HASTE_3)
	rapidFireDuration = 15,
	rapidFireCooldown = 300,
	rapidKillingCut = 60,
	rapidFireSpeed = 0.40,
	-- Bestial Wrath 19574 (the talent, with the pet out): 18 s (SpellMisc 329513 DurationIndex 85 = 18000 ms), its cooldown
	-- 120 s (SpellCooldowns 55448 RecoveryTime 120000), +50% pet damage (SpellEffect 697223, effect index 1, base points 50)
	bestialWrathDuration = 18,
	bestialWrathCooldown = 120,
	bestialWrathDamage = 0.50,
	-- The Survival branch's melee weave as wowsims' SV Weave preset plays it (raid-mode design section 15; the build
	-- ui/specs/hunter/dps/builds/sv_weave.siml, the rotation apls/default.apl.siml over weave_common.apl.siml), with the
	-- engine rules of sim/core it runs on (read, not run)
	weave = {
		shootSpot = 13.19,        -- the shooting spot, max($ranged_range 13.19, 11.67) (weave_common.apl.siml:3, 8)
		meleeSpot = 4.99,         -- the melee spot the walk in goes to (weave_common.apl.siml:9-10)
		meleeRange = 5,           -- melee range, where the walk in starts the swing (constants.go:24; movement.go:123-132, 216-224)
		minRanged = 5 + 8 - 4 / 3, -- the closest a bow fires from, 11.67 yd (constants.go:30; attack.go:61-69)
		runSpeed = 7,             -- a player's run speed in yd/s (movement.go:263-266)
		striderSpeed = 0.30,      -- Strider Kick's run speed +30% (DB2 SpellEffect 1357611: aura 31, base points 30;
		                          -- sim/hunter/talents_survival.go:155-163)
		striderDuration = 3,      -- for 3 s (SpellMisc 863136 DurationIndex 27 = 3000 ms)
		striderCooldown = 8,      -- Strider Kick's cooldown, 8000 ms (SpellCooldowns 101528 RecoveryTime)
		raptorCooldown = 6,       -- Raptor Strike's 6000 ms category cooldown (SpellCooldowns 53388, 54889)
		trapCooldown = 30,        -- the trap placements' 30000 ms category cooldown (Category 411, spells_auto_gen.go:10789)
		arcaneCooldown = 6,       -- Arcane Shot's 6 s category cooldown (category 1173, spells_auto_gen.go:10733)
		multiCooldown = 6,        -- Multi-Shot's 6 s category cooldown, the shared category 2 (spells_auto_gen.go:1796)
		multiCast = 0.5,          -- Multi-Shot's 0.5 s cast over the ranged speed (multi_shot.go:15-17, EV-0069;
		                          -- hunter.go:141-148 hasteRangedCast, unit.go:599-601 ApplyRangedSpeed); its cooldown
		                          -- starts when the cast completes (cast.go:224-258 Hardcast.OnComplete: triggerCooldown)
		windup = 0.5,             -- Auto Shot's windup, 500 ms over the ranged speed (constants.go:22; attack.go:353-362)
		reactionMin = 0.15,       -- the player's reaction, uniform in 150-350 ms (sv_weave.siml:8-10), drawn at every
		reactionMax = 0.35,       -- look (gcd.go:133-143)
		gcd = 1.5,                -- the global cooldown (StartRecoveryTime 1500 ms, SpellCooldowns 101528)
		kickSoon = 0.4,           -- kick_soon: in melee, Strider Kick ready within 400 ms (weave_common.apl.siml:13-19)
		kickWingClip = 1.5,       -- Wing Clip unless Strider Kick is known and ready within 1.5 s (default.apl.siml:24)
	},
	-- Mana in the raid fight (raid-mode design section 7; the user's answer 4 = (b): mana limits the casts as in wowsims)
	mana = {
		-- the hunter's base mana at 60 (Forever DB2 PlayerExpectedStat row 306; wowsims sim/core/base_stats_auto_gen.go:62-66):
		-- a cost stated as a percent of base mana is that percent of it rounded to the nearest whole mana (wowsims
		-- sim/core/mana.go:372 newManaCost, math.Round(BaseCostPercent x BaseMana / 100))
		baseMana = 1720,
		-- the costs of the level-60 ranks (Forever DB2 build 70888 SpellPower, its row named), flat or a percent of base mana;
		-- Arcane Shot and Summon Hawk by the server hotfix of 10-11 Nov (docs/research/R4-ability-formulas.md:105, 273), which
		-- wowsims carries as CostPct 11 (spells_auto_gen.go:10733-10737, 35894-35901), DB2 70888 still 190 flat
		costs = {
			serpent = { flat = 230 },      -- Serpent Sting VIII 13555: SpellPower 179175
			serpentIX = { flat = 250 },    -- Serpent Sting IX 25295, the book's rank (p.serpentTick 135): SpellPower 188672
			aimed = { flat = 310 },        -- Aimed Shot 20904: SpellPower 184990
			arcane = { pct = 11 },         -- Arcane Shot 14287 (SpellPower 179523: 190 before the hotfix)
			hawk = { pct = 11 },           -- Summon Hawk 1293527 (SpellPower 313592: 190 before the hotfix)
			huntersMark = { flat = 60 },   -- Hunter's Mark 14325: SpellPower 179455
			rapidFire = { flat = 100 },    -- Rapid Fire 3045: SpellPower 169901
			bestialWrath = { pct = 12 },   -- Bestial Wrath 19574: SpellPower 184568, PowerCostPct 12
			sniper = { flat = 365 },       -- Sniper Shot 1310786: SpellPower 314529
			raptor = { flat = 100 },       -- Raptor Strike 14266: SpellPower 179931
			bite = { flat = 65 },          -- Mongoose Bite 14271: SpellPower 178962
			strider = { pct = 5.81 },      -- Strider Kick 1317257: SpellPower 314743, PowerCostPct 5.81
			wingClip = { flat = 80 },      -- Wing Clip 14268: SpellPower 179168
			trap = { flat = 245 },         -- Immolation Trap 14305: SpellPower 179926
			multi = { pct = 13.9 },        -- Multi-Shot 2643: SpellPower 170887, PowerCostPct 13.9
		},
		-- Efficiency 19416 (MM, five ranks): A_ADD_PCT_MODIFIER SPELLMOD_COST (SpellEffect 696992, aura 108 misc 14), -3% a
		-- rank (TraitDefinitionEffectPoints 23304, curve 82809: -3 / -6 / -9 / -12 / -15), on the class mask 522818 /
		-- 2148012032 / 2105344 / 8388608, which holds (SpellClassOptions, db2_R4-ability-formulas) Serpent Sting 0:16384,
		-- Aimed Shot 0:131072, Arcane Shot 0:2048, Summon Hawk 2:8192, Sniper Shot 3:8388608, Raptor Strike and Mongoose Bite
		-- 0:2, Strider Kick 2:2097152, Wing Clip 0:64 and Multi-Shot 0:4096, not Hunter's Mark 0:1024, Rapid Fire 0:32,
		-- Bestial Wrath 1:33554432 or the trap placements 0:128; wowsims registers it (sim/hunter/talents_marksmanship.go:65-71
		-- ParseStatic)
		efficiency = { serpent = true, serpentIX = true, aimed = true, arcane = true, hawk = true, sniper = true, raptor = true,
			bite = true, strider = true, wingClip = true, multi = true },
		-- Resourcefulness 440529 (SV, two ranks): effect 0 SpellEffect 1134467, aura 108 misc 14, -30% a rank
		-- (TraitDefinitionEffectPoints 23261, curve 82781: -30 / -60) on the mask 194 / 524288 / 2097152: Raptor Strike and
		-- Mongoose Bite 0:2, Wing Clip 0:64, the trap placements 0:128 (Immolation Trap 14305) and Strider Kick 2:2097152;
		-- wowsims parses it (sim/hunter/talents_survival.go:110-116 ParseStatic, effect 1 in its count)
		resourcefulness = { raptor = true, bite = true, wingClip = true, trap = true, strider = true },
		-- Judgement of Wisdom 20355 on the boss (the user's answer O7 = (a); raid-mode design 5.3): each landed hit of the
		-- hunter's that its ProcFlags 0x222a8 hear (melee swing and ability, ranged auto and ability, harmful spell; wowsims
		-- sim/core/proc_types.go:110-132, dbcenums/proc_flags.go), a landed hit that deals no damage included, rolls 50% (wowsims'
		-- override ProcChancePct 50, spells_auto_gen.go:17776-17779) to give the striker 59 mana (20353: SpellEffect 698050
		-- ENERGIZE 59; sim/core/buffs/paladin.go:204-234), and only a unit with a mana bar gains (paladin.go:224-227): the
		-- hunter, not the pet or the hawks
		jowMana = 59,
		jowChance = 0.50,
		-- the hunter's Spirit regen, 6.25 + Spirit / 8 mana a second (wowsims sim/core/mana.go:77-78; approximation A3), the
		-- casting share of it capped at the whole (mana.go:185-189)
		spiritBase = 6.25,
		spiritPer = 1 / 8,
		-- the shares of the Spirit regen that go on while casting: Bestial Discipline 19590 effect 1, aura 134 25% a rank
		-- (TraitDefinitionEffectPoints of TraitDefinition 134425, curve 82816: 25 / 50), in the live reading (regenCast);
		-- Rapid Recuperation 1223987 effect 0, 25% a rank (curve 82802: 25 / 50) while its buff 1242512 is up, which a
		-- landed Serpent Sting puts up (wowsims sim/hunter/talents_marksmanship.go:183-231): Serpent Sting's uptime;
		-- Resourcefulness' buff 1242688 (SpellEffect 1242361, aura 134 bp 50) for 30 s (SpellMisc DurationIndex 9), which a
		-- melee or ranged ability crit triggers (SpellAuraOptions 242512 ProcTypeMask 0x110; wowsims talents_survival.go:110-131,
		-- Outcome OutcomeCrit) at 50% a rank (TraitDefinitionEffectPoints 23260, curve 85425: 50 / 100)
		disciplineShare = 0.25,
		recuperationShare = 0.25,
		resourcefulnessShare = 0.50,
		resourcefulnessChance = 0.50,
		resourcefulnessDuration = 30,
		-- the five-second rule: a spend keeps the regen at the casting rate for 5 s (wowsims sim/core/mana.go:403-411)
		fsr = 5,
		-- Hunter's Mark's recast: the prepull cast at -22 s (apls/pull.apl.siml:8) lasts 120 s (SpellMisc 324400 DurationIndex
		-- 4 = 120000 ms), and both rotations cast it when it is missing (turret_hawk.apl.siml:13, default.apl.siml:19): 98 s
		huntersMarkAt = 98,
		-- The in-fight consumables of wowsims' hunter preset (ui/specs/hunter/dps/defaults.siml:21, 30-31: conjured
		-- demonic_rune, resource_pot major_mana_potion, offensive_pot major_frenzy_potion), always on (the user's answer O2 =
		-- (a); raid-mode design 7.4), each a major cooldown (sim/common/shared/consumable_potion.go:255-281):
		-- - the Major Frenzy Potion 250943 (ItemXItemEffect 145798 -> ItemEffect 214812, which states no cooldown and no
		--   category, so the spell's apply, consumable_potion.go:283-300): spell 1251940, 30 s, +80 attack power and +80 ranged
		--   attack power (SpellEffect 1256847 aura 99, 1356023 aura 124), potion category 4 for 120 s (wowsims
		--   spells_auto_gen.go:34318; DB2 SpellCategories 176135, SpellCooldowns 95731); the pet keeps its summon's attack power
		--   (EV-0072), the hawks take it, as a Use buff's (Model fight);
		-- - the Major Mana Potion 13444 (ItemXItemEffect 115591 -> ItemEffect 99861: spell 17531, SpellCategoryID 4,
		--   CategoryCoolDownMSec 120000): SpellEffect 695996 ENERGIZE 1800, Variance 0.5, so 1350-2250 (wowsims
		--   sim/core/spelldata/effect.go:125-140: half the Variance either side), its mean 1800;
		-- - the Demonic Rune 12662 (ItemXItemEffect 124919 -> ItemEffect 99229: spell 16666, category 1153, CategoryCoolDownMSec
		--   120000): SpellEffect 694074 ENERGIZE 1200, Variance 0.5, 900-1500, mean 1200.
		-- A mana gain fires only when its whole maximum fits under the pool after 5 s of the casting regen
		-- (consumable_potion.go:257-266 ShouldActivate, :382-388 fits: max - current - 5 x ManaRegenPerSecondWhileCasting >=
		-- the maximum); the Frenzy Potion has no such condition
		frenzyPotion = { spell = 1251940, stats = { AP = 80 }, duration = 30 },
		potionCooldown = 120,
		manaPotion = { mean = 1800, max = 2250 },
		rune = { mean = 1200, max = 1500, cooldown = 120 },
	},
}
Model.CONST = CONST

-- The level difference of every attack table is capped at +3 (capDiff): wowsims sim/core/target.go:536-538
-- combatLevelDiff = min(defender level - attacker level, 3), docs/rulings/R-0032-combat-model-level-60-targets.md (the
-- combat model is level 60 against targets of 58 to 63). So +4 and +5 miss, dodge and glance as +3.
local function capDiff(mobDiff)
	return math.min(mobDiff, 3)
end

-- A hand's base miss in % against a mob mobDiff levels above (wowsims sim/core/target.go:561-585 newAttackTableHand):
-- the skill gap skillDiff = 5 x the level difference (capDiff) - bonus, bonus the hand's weapon skill over the level's
-- maximum 5 x level (sim/core/weapon_skill.go:10-29 GetWeaponSkill: 0 for an empty hand), and the miss 5% + 0.1% a
-- point of the gap while the gap is 10 points or less, else 5% + 0.2% a point of the whole gap. At bonus 0: 5 / 5.5 / 6
-- / 8% at +0..+3. The equal-level 5% and the +3 8% are the Forever client's own for the level's skill: GlobalStrings
-- 60052 CR_HUNTER_HIT_CAP_TOOLTIP (the db2_R3-core-formulas export), "5.00% Melee/Ranged" against targets of your level
-- and "8.00% Melee/Ranged" against raid bosses. No Forever source states the slope a skill point: it is wowsims' table
-- (sim/core/attack_table_test.go:87-157, the sword hand at +3: 285 / 300 / 305 / 315 skill miss 11 / 8 / 6 / 5%), taken
-- by the user's rule for W1's open questions (raid-mode W1 design section 3). The Forever UI's Skills frame computes
-- 0.04% a point (Camelot/SkillsFrame.lua:44-55), which at 300 against a raid boss gives 5.6%, not the client's 8%: it is
-- no rule of the game's miss. The Forever UI holds one more table, Camelot/PaperDollFrameStats.lua:460
-- meleeMissChances = { 5.0, 5.2, 5.4, 9.0 }: a local that CharacterHitFrame_OnEnter (lines 454-484) never reads.
function Model.SkillMiss(mobDiff, bonus)
	needMobDiff(mobDiff, "SkillMiss")
	if type(bonus) ~= "number" then error("HunterGearAdvisor: Model.SkillMiss without a skill bonus: " .. tostring(bonus), 2) end
	local gap = 5 * capDiff(mobDiff) - bonus
	if gap <= 10 then return 5.0 + 0.1 * gap end
	return 5.0 + 0.2 * gap
end
-- The hit a hand's skill bonus gives against the level's skill, in %: Model.SkillMiss at bonus 0 less at bonus, negative
-- below the maximum. It jumps where the gap crosses 10 points, as wowsims' table does (+3: bonus 4 gives 0.8%, bonus 5
-- 2.0%; +0: bonus -10 gives -1.0%, bonus -11 -2.2%).
function Model.SkillHit(mobDiff, bonus)
	return Model.SkillMiss(mobDiff, 0) - Model.SkillMiss(mobDiff, bonus)
end
-- the base miss at the level's skill (bonus 0), which every hit cap is
local function baseMiss(mobDiff)
	return Model.SkillMiss(mobDiff, 0)
end

local function missChance(mobDiff, hit)
	return math.max(0, baseMiss(mobDiff) - hit) / 100
end

function Model.HitCap(mobDiff)
	return baseMiss(mobDiff)
end

-- The spell table's base miss in % against a mob mobDiff levels above: 4% + 1% a level, 17% at +3 (wowsims
-- sim/core/target.go:540-547 spellMissChance; capDiff), the miss of Immolation Trap's application and of a magic proc
local function spellMissPct(mobDiff)
	local d = capDiff(mobDiff)
	return d >= 3 and 17 or math.max(0, 4 + d)
end
-- The spell hit in % past which Immolation Trap's application misses no more: its spell miss less Survival Tactics' 5% a
-- rank (Model weaveParts trapMiss), floored at 0. Score prices a set's spell hit (SPELL_HIT) up to it at W.SPELL_HIT.
function Model.TrapHitCap(mobDiff, survivalTactics)
	needMobDiff(mobDiff, "TrapHitCap")
	if type(survivalTactics) ~= "number" then error("HunterGearAdvisor: Model.TrapHitCap without the Survival Tactics rank", 2) end
	return math.max(0, spellMissPct(mobDiff) - 5 * survivalTactics)
end

-- The multiplier of a physical hit against a target's armor by the attacker's level: 1 - armor / (armor + 400 + 85 x
-- level), the reduction capped at 75% (wowsims sim/core/spell_resistances.go:140-153 GetArmorDamageModifier).
function Model.ArmorMult(armor, level)
	return math.max(0.25, 1 - armor / (armor + 400 + 85 * level))
end

-- Armor multiplier on physical damage against a mob of level + mobDiff (see CREATURE_ARMOR): the creature's own armor
-- at its level, not capped at +3 (capDiff caps the attack table, not the creature). The levelling mode's target.
function Model.PhysMult(level, mobDiff)
	needMobDiff(mobDiff, "PhysMult")
	local mobLevel = math.max(1, math.min(#CREATURE_ARMOR, level + mobDiff))
	return Model.ArmorMult(CREATURE_ARMOR[mobLevel] * CONST.armorMod, level)
end

-- The raid boss's armor against an attacker of flat armor penetration armorPen (raid mode; the user's answers 3 = (b) and
-- O5): wowsims' 3731 less the preset's Major and Minor armor reductions, 3731 - 2250 - 505 = 976 (my arithmetic), less the
-- armor penetration, floored at 0 (sim/core/spell_resistances.go:147-150).
function Model.BossArmor(armorPen)
	if type(armorPen) ~= "number" then error("HunterGearAdvisor: Model.BossArmor without the armor penetration: " .. tostring(armorPen), 2) end
	local r = CONST.raid
	return math.max(0, r.bossArmor - r.majorArmorReduction - r.minorArmorReduction - armorPen)
end

-- The armor multiplier of the mode's target against an attacker of flat armor penetration armorPen: raid mode the boss's
-- armor (Model.BossArmor) at level 60, levelling mode the creature's own at its level (Model.PhysMult; levelling has no
-- armor penetration input). wowsims takes the attacking unit's own ArmorPenetration off the defender's armor
-- (sim/core/spell_resistances.go:150, at.Attacker.stats), and the pet's and the hawks' stat inheritance carries none
-- (sim/hunter/pets.go:122-140 makeStatInheritance; sim/hunter/summon_hawk.go:79-87): the hunter's own attacks take
-- p.armorPen (the shots; the dive, the hunter's own spell, summon_hawk.go:135; the weave's melee; the procs,
-- Model.ProcOutcomes), the pet and the hawks 0. Model.Parts and Model.ProcOutcomes take it.
local function physOf(p, armorPen)
	if p.mode == "raid" then return Model.ArmorMult(Model.BossArmor(armorPen), p.level) end
	return Model.PhysMult(p.level, p.mobDiff)
end

-- The share of time the mob faces the pet, by the mode: levelling CONST.petTanks (the pet tanks), raid CONST.raid.petTanks
-- (the pet behind the boss). Model.Parts parries the pet by it; Advisor A.State sets the parry cap by it.
function Model.PetTanks(mode)
	if mode == "raid" then return CONST.raid.petTanks end
	if mode == "level" then return CONST.petTanks end
	error("HunterGearAdvisor: Model.PetTanks of a mode that is not 'raid' or 'level': " .. tostring(mode), 2)
end

-- The share of the mode's targets of a creature type (Model.CREATURE_TYPES), at which AP and Beastslaying against that type
-- count: raid mode 1 for the boss's type (CONST.raid.targetType, dragonkin: the user's answer 5 = (a), wowsims
-- defaults.siml:65) and 0 for every other; levelling mode Model.AP_CREATURE_SHARE for each type. A type outside
-- Model.CREATURE_TYPES is an error.
local IS_CREATURE_TYPE = {}
for _, t in ipairs(Model.CREATURE_TYPES) do IS_CREATURE_TYPE[t] = true end
function Model.TargetShare(creatureType, mode)
	if not IS_CREATURE_TYPE[creatureType] then
		error("HunterGearAdvisor: Model.TargetShare of a creature type outside Model.CREATURE_TYPES: " .. tostring(creatureType), 2)
	end
	if mode == "raid" then return creatureType == CONST.raid.targetType and 1 or 0 end
	if mode == "level" then return Model.AP_CREATURE_SHARE end
	error("HunterGearAdvisor: Model.TargetShare of a mode that is not 'raid' or 'level': " .. tostring(mode), 2)
end

-- Glancing blows of a white swing by the attacking hand's weapon skill bonus (bonus over the level's maximum 5 x level):
-- the chance 10% + 2% a point of the base skill gap 5 x the level difference + max(0, -bonus) (skill above the maximum
-- leaves it), and the average damage factor of a glance, between the bounds 1.3 - 0.05 and 1.2 - 0.03 a point of the
-- skill gap 5 x the level difference - bonus, clamped to [0.01, 0.91] and [0.2, 0.99] (wowsims sim/core/target.go:561-578
-- newAttackTableHand: BaseGlanceChance, GlanceMultiplierMin, GlanceMultiplierMax; attack_table_test.go:87-157, the sword
-- hand at +3: 285 skill 70% at 0.01-0.30, 300 40% at 0.55-0.75, 305 40% at 0.80-0.90, 315 40% at 0.91-0.99); none
-- against lower-level mobs. They hit the hunter's, the pet's and the hawks' white swings (pet and hawk glances are in
-- the logs: EV-0071, EV-0073), as one row of the white table (Model.Parts white); the pet and the hawks swing at bonus 0
-- (their own tables, no weapon: weapon_skill.go:17-19). The level difference is capped at +3 (capDiff).
function Model.Glance(mobDiff, bonus)
	needMobDiff(mobDiff, "Glance")
	if type(bonus) ~= "number" then error("HunterGearAdvisor: Model.Glance without a skill bonus: " .. tostring(bonus), 2) end
	local d = capDiff(mobDiff)
	if d < 0 then return 0, 1 end
	local chance = math.max(0, math.min(1, 0.10 + 0.02 * (5 * d + math.max(0, -bonus))))
	local lo = math.max(0.01, math.min(0.91, 1.3 - 0.05 * (5 * d - bonus)))
	local hi = math.max(0.20, math.min(0.99, 1.2 - 0.03 * (5 * d - bonus)))
	return chance, (lo + hi) / 2
end

-- Average factor of a white swing for glancing blows alone, 1 - chance x (1 - the glance's average factor): 0.995 at an
-- equal-level mob, 0.86 at +3, 1 against lower-level mobs.
function Model.GlanceMult(mobDiff)
	needMobDiff(mobDiff, "GlanceMult")
	local chance, avg = Model.Glance(mobDiff, 0)
	return 1 - chance * (1 - avg)
end

-- Mob dodge (and parry, the same base) in %: 5.0 / 5.5 / 6.0 / 6.5 at +0..+3 (Forever UI
-- Camelot/PaperDollFrameStats.lua BASE_ENEMY_DODGE_CHANCE; wowsims 0.1% per skill point). Lower-
-- level mobs stay at 5% (the table has no entry below 0); the level difference is capped at +3 (capDiff).
function Model.MobAvoid(mobDiff)
	needMobDiff(mobDiff, "MobAvoid")
	return 5.0 + 0.5 * math.max(0, capDiff(mobDiff))
end

-- A hand's mob dodge in % by its weapon skill bonus (bonus over the level's maximum 5 x level): 5% + 0.1% a point of the
-- skill gap 5 x the level difference - bonus (wowsims sim/core/target.go:574 BaseDodgeChance, read for the attack's hand,
-- unit.go:1179-1180), Model.MobAvoid at bonus 0 (lower-level mobs at the equal level's, as Model.MobAvoid).
function Model.SkillDodge(mobDiff, bonus)
	needMobDiff(mobDiff, "SkillDodge")
	if type(bonus) ~= "number" then error("HunterGearAdvisor: Model.SkillDodge without a skill bonus: " .. tostring(bonus), 2) end
	return 5.0 + 0.1 * (5 * math.max(0, capDiff(mobDiff)) - bonus)
end

-- Mob parry in %, against an attacker in front of it (the pet while it tanks, Model.PetTanks): 5% + 0.1% a point of the
-- skill gap 5 x the level difference up to a 10-point gap, 5% + 0.6% a point past it (wowsims sim/core/target.go:585-590
-- BaseParryChance): 5 / 5.5 / 6 / 14% at +0..+3. Lower-level mobs stay at 5%, as Model.MobAvoid; the level difference is
-- capped at +3 (capDiff).
function Model.PetParry(mobDiff)
	needMobDiff(mobDiff, "PetParry")
	local gap = 5 * math.max(0, capDiff(mobDiff))
	if gap <= 10 then return 5.0 + 0.1 * gap end
	return 5.0 + 0.6 * gap
end

-- The pet's swing time in s before Faster / Slower Attack: the 2 s creature swing those passives act
-- on (wowsims pets.go petSwing, SwingSpeed 2). Faster Attack VI (DB2 1263109: A_MOD_ATTACKSPEED +67
-- on TARGET_UNIT_PET) makes it 2.0 / 1.67 = 1.20 s, the swing the user's cat shows.
Model.PET_BASE_SWING = 2.0

-- p fields: level, rap (stat RAP incl. Aspect of the Hawk and Trueshot Aura), map, crit (ranged
-- crit %, the sheet's, without the weapon skill: the shots', and the pet, the dive and the hawks take it from the owner,
-- see petCritBase), meleeCrit (melee crit %, the sheet's GetCritChance), hit (%: the hit of every attack), rangedHit (%
-- hit of the six shots alone on top of hit: the ranged weapon skill's hit, Model.SkillHit of rangedSkill, see the shots
-- below), rangedSkill (the ranged hand's weapon skill bonus over the level's maximum 5 x level, signed: its crit
-- suppression, critSuppressor, and the pet's ranged crit branch, petCritBase), mhSkill and ohSkill (the main hand's and
-- the off hand's melee weapon skill bonus over 5 x level, signed, 0 for a hand without a melee weapon: each hand's
-- dodge, glance and crit suppression in the weave, the off hand's miss, the main hand's for a proc's table and the
-- pet's melee crit branch), meleeHit (the main hand's skill hit, Model.SkillHit of mhSkill at the model point: the main
-- hand's miss in the weave, the melee counterpart of rangedHit), expertise (%: lowers the dodge of the mob against
-- the hunter's melee, the pet and the hawks, and its parry against the pet, down to 0 at Model.MobAvoid),
-- haste, attackSpeed, hasteRating, meleeHaste, rangedHaste: the permanent attack speed of the worn state by source
-- (Player.Snapshot), each in % (the speed multiplier less 1, x 100). Each is the product of its sources (Player wornHaste:
-- each worn item's aura a factor of its own, the items' haste rating summed as ratings do, the worn set bonuses' as one
-- sum), and its weight is the value of one more such source (Model.Weights, where the sums' pricing is stated). Who takes
-- each follows wowsims' paths (raid-mode W1 design section 7; the auras of Forever DB2 SpellEffect):
-- - haste: the aura 342 A_MOD_MELEE_RANGED_HASTE_2 of a worn item or enchant (Minor Haste 13928 of enchant 931: aura 342
--   bp 1 and aura 65, casting speed, on the caster), which wowsims registers per item and enchant as melee and ranged
--   speed (sim/core/enchant_speed.go:13-41 registerEquipSpeedAuras, :65-79 AttachHastePseudoStats;
--   sim/core/spelldata/speed.go:14-20): MultiplyMeleeSpeed and MultiplyRangedSpeed, so the hunter's shots and their
--   casts (hBase), the melee swings and Raptor Strike's count (meleeSpeed), the tamed pet (petInherit: it inherits the
--   owner's MeleeSpeedMultiplier, sim/core/pet.go:381-398) and the hawks (they inherit the owner's RangedSpeedMultiplier,
--   pet.go:415-431, summon_hawk.go:88-91; hawkSpeed, below).
-- - attackSpeed: the aura 9 A_MOD_ATTACKSPEED or 342 of a worn set bonus (the Tier-1 two-piece bonuses 1300934 / 1300945 /
--   1300951 / 1300957 / 1300968, aura 342 bp 1: Game/SetData.lua ATTACK_SPEED) and Wind Blessed 1259710 (the Skyborne
--   racial, aura 342 bp 2), which wowsims applies as AttackSpeedMultiplier (a set bonus's row through attackSpeedRow,
--   sim/core/spelldata/parse_effects_table.go:367-368, 1048-1050; Wind Blessed x1.02, sim/core/racials.go:225-229):
--   MultiplyAttackSpeed (sim/core/unit.go:729-742), the shots, the melee swings and the tamed pet (pet.go:381-398 takes
--   the owner's AttackSpeedMultiplier; in game the pet swings 1.965 s with its owner's 2% Wind Blessed, wowsims commit
--   d729b139, docs/research/V1-verify-forever-pet.md section 5), not the hawks.
-- - hasteRating: haste rating (Parse HASTE_RATING: stat type 36, 10 rating a 1%), wowsims' hasteRatingMultiplier on the
--   owner's totals alone (sim/core/unit.go:564-566, 610-638): the shots and the melee swings, neither the pet nor the
--   hawks.
-- - meleeHaste: aura 319 A_MOD_MELEE_HASTE_3, the owner's melee speed (wowsims MeleeSpeedMultiplier,
--   MultiplyMeleeSpeed): the melee swings, Raptor Strike's count and the pet, not the shots and not the hawks.
-- - rangedHaste: aura 140 A_MOD_RANGED_HASTE, the owner's ranged speed (wowsims RangedSpeedMultiplier,
--   MultiplyRangedSpeed): the shots and their casts and the hawks (hawkSpeed), not the melee swings and not the pet.
-- bowDPS (the DPS of the weapon in the ranged slot, a scope's flat damage included, Player.WeaponInputs: the shots' weapon
-- damage and the hawks' AP; a thrown weapon's too, which casts no shot (noShots), so with one worn only the hawks' AP
-- reads it, see hawkAP below; 0 with no weapon there),
-- bowSpeed, ammoDPS, quiver (0..0.15), mobDiff, survival (the Survival branch, Player.SurvivalBranch: it weaves, see
-- weaveParts; every other build has no melee), mhDPS, mhSpeed, mhNorm (normalized speed: 2.4 one-hander, 3.3 two-hander,
-- 1.7 dagger),
-- ohDPS, ohSpeed, twoH, unarmed (true = no weapon in the main hand that the melee strikes take: none, or a fishing pole or a
-- miscellaneous weapon, Player STRIKE_WEAPON; Raptor Strike, Wing Clip and Mongoose Bite ranks 1-3 need one), orc (Orc Command, +5% pet damage: false = not
-- an orc; true and nil count it, Player.Snapshot passes nil while the race is secret), petOut (Player.PetOut: false
-- only with Lone Wolf taken and no living pet out, true otherwise),
-- petFamily (UnitCreatureFamily id, nil = not seen), petSwing (the pet's own main-hand swing time
-- in s: without Frenzy and without the owner's speeds it inherits, which Player.PetSwing divides out of
-- UnitAttackSpeed("pet") whole; the model applies those permanent speeds back, p.haste, p.attackSpeed and
-- p.meleeHaste (not p.hasteRating, which the pet does not inherit), with Rapid Fire's average rf (petInherit), both in
-- petHaste and in Frenzy's swing count (attacks8s); the owner's melee hastes that come and go are no input here (Quick Strikes
-- 1299448 is not counted; a worn item's Use buff of aura 319, Kiss of the Spider's, Score prices at W.MELEE_HASTE
-- over its uptime); nil = not seen: Model.PET_BASE_SWING),
-- serpentTick (Serpent Sting IX from the book: 135, nil = trainer rank), noShots (true = no bow, gun or
-- crossbow in the ranged slot: no shot is cast, see below), tal = { talent ranks },
-- mode ("level" or "raid", checkMode), agi (the effective Agility of the sheet, UnitStat), rangedGearHit (% hit of the
-- worn gear that reaches the ranged attacks alone: the worn items' and set bonuses' RANGED_HIT, Player.Snapshot; the shots,
-- the pet and the hawks take it, see the shots below),
-- beastSlaying (Beastslaying's flat damage per hit against beasts, the set's main hand's and off hand's summed,
-- Player.WeaponInputs: the hunter's own weapon strikes and shots take it, see flat below), apVsTarget
-- (the worn items' and set bonuses' attack power against a creature type, AP_VS_<TYPE>, times the mode's share of the
-- type, Model.TargetShare: the hunter's own attack power against the target, see rapOwn below), spellHit (% spell
-- hit, GetSpellHitModifier), spellCrit (% spell crit, GetSpellCritChance), and in raid mode manaMax (UnitPowerMax of
-- mana), regenRest and regenCast (GetManaRegen: mana per second out of and inside the five-second rule), spirit
-- (UnitStat) and armorPen (the worn items' and set bonuses' flat armor penetration, ARMOR_PEN, Player.Snapshot: off the
-- raid boss's armor against the hunter's own attacks, not the pet's or the hawks', physOf, Model.BossArmor); statMult
-- (both modes: the live sheet's stat multipliers { AGI, STR, INT, SPI }, each 1 or more, Player.ReadStats: the product of
-- the auras of Game/StatMultData.lua up on the player, Greater Blessing of Kings and the like; the user's answer O8 =
-- (a), raid-mode design 4.8), which Model.ApplyStats multiplies an item's or a Use buff's stats by. Model.Parts
-- reads agi for the crit suppression alone (the Agility crit, critSuppressor), spellHit and spellCrit for Immolation
-- Trap's spell miss and its ticks' spell crit in the Survival weave alone (weaveParts; Model.ProcOutcomes reads them for
-- the magic procs), of the raid inputs armorPen alone (the raid target, physOf). Levelling mode runs the one pass below
-- with the cooldowns at their averages; raid mode runs the fight (Model fight: the pass once a state of its segments, the
-- cooldown windows from 5 s, against the raid target, CONST.raid: the boss's armor, Curse of the Elements, Gift of Arthas,
-- its dragonkin type, the pet behind it, no kill for Rapid Killing).
-- uses (raid mode, optional: nil = none): the Use buffs of the set the fight runs, a list of Game/UseData.lua entries in
-- their order (Score.SetUses; Model useWindows); a levelling point with uses is an error (Score prices them there).
-- petRap and petMap (optional, both or neither): the pet's attack powers held at a point's, the pet keeping the attack
-- power of its summon (wowsims sim/hunter/pets.go:160-171): Model fight sets them on a state with a Use buff, Model.Weights
-- on its levelling Use weights; nil = p.rap and p.map.
-- Every field but orc, petFamily, petSwing, serpentTick, uses, petRap, petMap and the raid inputs is required
-- (checkInputs; statMult checkMode); the raid inputs are required in raid mode (checkMode).
-- Formulas, ranks and their sources: memory hunter-stat-weights.md, docs/research/*.md
-- (spec research of 2026-11-14: DB2, wowsims/forever, Forever UI source; the wowsims comparison
-- of 2026-11-16).

-- Rapid Fire 3045 (from 26; CONST.rapidFire*): aura 140 A_MOD_RANGED_HASTE +40 and aura 319 A_MOD_MELEE_HASTE_3 +40, so it
-- speeds the shots and the hawks (ranged speed) and the melee swings and the pet (melee speed) alike; 15 s every 5 min,
-- Rapid Killing -1 min/rank. The levelling mode's average: returns the share of time it is up and the average speed it
-- adds (0.40 x that share). The raid fight has its windows instead (Model fight).
local function rapidFire(level, T)
	local up = level >= 26 and CONST.rapidFireDuration / (CONST.rapidFireCooldown - CONST.rapidKillingCut * T("rapidKilling")) or 0
	return up, CONST.rapidFireSpeed * up
end

-- The multiplier of the tamed pet's swing rate from its owner: the owner's speed multipliers it inherits (wowsims
-- sim/core/pet.go:381-398 enableDynamicMeleeSpeed: the owner's MeleeSpeedMultiplier and AttackSpeedMultiplier, not haste
-- rating, which sits on the owner's totals alone, sim/core/unit.go:564-566, 610-638), so an item's or enchant's aura 342
-- (p.haste), the set bonuses' and Wind Blessed's attack speed (p.attackSpeed), the melee-only speed (p.meleeHaste), and
-- Rapid Fire's speed rf (its aura 319 is melee speed: the levelling average, or 0 / 0.40 in a segment of the raid fight).
-- Model.Parts swings the pet at it (petInherit).
local function petSpeedMult(p, rf)
	return (1 + p.haste / 100) * (1 + p.attackSpeed / 100) * (1 + p.meleeHaste / 100) * (1 + rf)
end

-- Crit suppression (wowsims): a physical attack's crit chance loses the attacking hand's MeleeCritSuppression, 0.2% a
-- point of the base skill gap baseSkillDiff = 5 x the level difference - min(bonus, 0), bonus the hand's weapon skill
-- over the level's maximum 5 x level (sim/core/target.go:561-597: skill above the maximum leaves it alone, skill below
-- it adds 0.2% a point; 1 / 2 / 3% at +1 / +2 / +3 at the level's skill), plus the aura crit up to AuraCritSuppression,
-- 1.8% against a target 3 or more levels above
-- (target.go:504-512; wowsims' evidence for it, docs/evidence/EV-0090, is Classic Era logs, not Forever). The aura crit
-- is the attack's whole crit less the base crit and the crit from Agility (sim/core/spell_result.go:224-231
-- physicalCritSuppression); the hunter's base physical crit is 0 (sim/core/base_stats_auto_gen.go:62-66), and the
-- Agility crit is p.agi x the level's crit per Agility (Model.CritPerAgility). The crit chance is floored at 0
-- (spell_result.go:208-210 PhysicalCritChance). It applies to every physical crit roll: the shots (Auto, Aimed, Multi,
-- Arcane, Sniper) and Serpent Sting's ticks (Model.Parts rcrit), the dive (OutcomeRangedCritOnly: the ranged crit), the
-- hunter's melee (whiteRollMH, whiteRollOH, critAbil), the melee and ranged tables of a proc (Model.ProcOutcomes) and
-- the pet and the
-- hawks, whose tables are their own at level 60 with skill 300 and whose crit is all aura crit (the pet's base stats
-- hold no crit and no Agility, sim/hunter/pets.go:38-42; the hawks' base stats hold health alone,
-- summon_hawk.go:39-41). Spell crit (a magic proc) is not suppressed (spell_result.go:309-318 SpellCritChance).
-- The hand: the shots, the dive (ProcMaskRangedSpecial, summon_hawk.go:135) and Serpent Sting's ticks
-- (serpent_sting.go:28) take the ranged hand's entry (target.go:606-615 Hand), whose bonus is p.rangedSkill; the pet and
-- the hawks have their own tables at bonus 0 (no weapon, weapon_skill.go:17-19); the hunter's melee takes each hand's
-- (weaveParts: p.mhSkill, p.ohSkill) and a proc's table the main hand's (p.mhSkill, Model.ProcOutcomes).
-- skillSupp(bonus) = 0.002 x (5 x d + max(0, -bonus)): wowsims' rule wherever d >= 0, which every producer's mobDiff
-- is (0 levelling, 3 raid): there baseSkillDiff >= 0, and at 0 (d = 0, bonus >= 0) both branches of target.go:591-595
-- give 0 (raid-mode W1 design 3.3).
-- Returns suppressed(crit, agiCrit, bonus), the crit chance left of a crit chance with agiCrit of it from Agility
-- (fractions) on the hand of skill bonus bonus, and the hunter's Agility crit at p.
local function critSuppressor(p)
	local d = capDiff(p.mobDiff)
	local function skillSupp(bonus)
		if type(bonus) ~= "number" then error("HunterGearAdvisor: crit suppression without the hand's skill bonus: " .. tostring(bonus), 3) end
		return 0.002 * (5 * d + math.max(0, -bonus))
	end
	local function suppressed(critFrac, agiCritFrac, bonus)
		local aura = d >= 3 and math.max(0, math.min(0.018, critFrac - agiCritFrac)) or 0
		return math.max(0, critFrac - skillSupp(bonus) - aura)
	end
	return suppressed, Model.CritPerAgility(p.level) / 100 * p.agi
end

-- The mana cost of each of the hunter's casts in the raid fight (CONST.mana): its rank's cost (a percent of base mana
-- rounded to the whole mana, wowsims sim/core/mana.go:372), Serpent Sting IX's with the book (p.serpentTick 135, the
-- tick the game side passes with it, Player.Snapshot), VIII's without, times Efficiency's and Resourcefulness' cost
-- modifiers where their masks hold the spell: two modifiers multiply (wowsims sim/core/spell_mod.go:504-509,
-- applyPowerCostPercent :901-910) and the cost after them is not rounded (sim/core/spell.go:1055-1063
-- ApplyCostModifiers). Returns { serpent, aimed, arcane, hawk, huntersMark, rapidFire, bestialWrath, sniper, raptor, bite,
-- strider, wingClip, trap, multi }.
local function manaCosts(p, T)
	local mn = CONST.mana
	local eff, res = 1 - 0.03 * T("efficiency"), 1 - 0.30 * T("resourcefulness")
	local out = {}
	for name, c in pairs(mn.costs) do
		local base = c.flat or math.floor(c.pct * mn.baseMana / 100 + 0.5)
		out[name] = base * (mn.efficiency[name] and eff or 1) * (mn.resourcefulness[name] and res or 1)
	end
	if p.serpentTick == 135 then
		out.serpent = out.serpentIX
	elseif p.serpentTick ~= nil then
		error("HunterGearAdvisor: p.serpentTick is Serpent Sting IX's 135 or nil: " .. tostring(p.serpentTick), 3)
	end
	out.serpentIX = nil
	return out
end
function Model.ManaCosts(p)
	return manaCosts(p, talents(p))
end

-- Who gets the damage, and the multiplier of the hunter's own damage (own): a pet is assumed from level 10 unless Lone
-- Wolf is taken and no pet is out (Player.PetOut reads the live pet only then, and gives true otherwise); Lone Wolf
-- +20% all damage without a pet, Focused Fire +1%/rank while the pet is out, Improved Tracking +1%/rank against the
-- tracked type (CONST.trackUptime). Returns own, hasPet, loneWolf, lone, ff.
local function ownDamage(p, T)
	local hasPet = p.level >= 10 and p.petOut
	local loneWolf = T("loneWolf") > 0
	local lone = (loneWolf and not hasPet) and 1.2 or 1
	local ff = hasPet and (1 + 0.01 * T("focusedFire")) or 1
	local track = 1 + 0.01 * T("improvedTracking") * CONST.trackUptime
	return ff * lone * track, hasPet, loneWolf, lone, ff
end

-- The standard normal distribution function, Phi(z) = erfc(-z / sqrt 2) / 2, to double precision: erf by its Taylor
-- series up to 2.5 (Abramowitz & Stegun 7.1.5) and erfc by its continued fraction above it (A&S 7.1.14). nCycles reads it.
local function erfc(x)
	if x < 0 then return 2 - erfc(-x) end
	if x <= 2.5 then
		local term, sum, n = x, x, 0
		repeat
			n = n + 1
			term = -term * x * x / n
			local add = term / (2 * n + 1)
			sum = sum + add
		until math.abs(add) < 1e-17
		return 1 - 2 / math.sqrt(math.pi) * sum
	end
	-- erfc(x) = e^(-x^2) / sqrt(pi) x 1 / (x + (1/2) / (x + 1 / (x + (3/2) / (x + 2 / (x + ...))))), summed from its 80th term
	local f = x
	for k = 80, 1, -1 do f = x + (k / 2) / f end
	return math.exp(-x * x) / math.sqrt(math.pi) / f
end
local function normalCdf(z)
	return 0.5 * erfc(-z / math.sqrt(2))
end
Model.NormalCdf = normalCdf

local function clamp01(x) return math.max(0, math.min(1, x)) end

-- nCycles(d, C, sigma): the mean number of weave cycles from an event to the first look at least d s later, cycle
-- lengths of mean C and spread sigma (raid-mode design 15.3; the sum of n cycles taken as a normal variable, approximation
-- WA2): 1 + the sum over n >= 1 of Phi((d - nC) / (sigma sqrt n)), summed until nC passes d by 8 sigma sqrt n. At sigma 0
-- each term is 1 while nC is below d (within 1e-9 s, the rounding Raptor Strike's count took: Model.Parts), else 0, so
-- nCycles is ceil(d / C). The interval of such an action is nCycles x C (Wald's identity).
local function nCycles(d, C, sigma)
	if not (C > 0) then error("HunterGearAdvisor: nCycles of a cycle that is not positive: " .. tostring(C), 2) end
	local sum, n = 1, 1
	while true do
		local nC = n * C
		if sigma == 0 then
			if nC >= d - 1e-9 then return sum end
			sum = sum + 1
		else
			local sd = sigma * math.sqrt(n)
			if nC > d + 8 * sd then return sum end
			sum = sum + normalCdf((d - nC) / sd)
		end
		n = n + 1
	end
end
Model.NCycles = nCycles

-- The weave's means over the uniform reaction rho in [a, b] (CONST.weave reactionMin, reactionMax; raid-mode design 15.2,
-- my arithmetic there, exact over the uniform reactions):
-- - heldShot(u), the mean delay of the Auto Shot past its swing time R when its windup comes due u s after the walk out
--   would end at a zero reaction: a shot due before the walk ends waits a second reaction after it (attack.go:946-958),
--   E[(rho1 + rho2 - u) 1{rho1 > u}]: 0 for u >= b, (a + b) - u for u <= a, ((b - u)(mean - u) + (b^2 - u^2) / 2) / (b - a)
--   between;
-- - emax(c) = E[max(c, rho)]: the mean for c <= a, c for c >= b, (c(c - a) + (b^2 - c^2) / 2) / (b - a) between;
-- - pastBy(x) = P(rho3 - rho1 >= x), the difference of two reactions, triangular on [a - b, b - a].
local function heldShot(u, a, b)
	local mean = (a + b) / 2
	if u >= b then return 0 end
	if u <= a then return 2 * mean - u end
	return ((b - u) * (mean - u) + (b * b - u * u) / 2) / (b - a)
end
local function emax(c, a, b)
	if c <= a then return (a + b) / 2 end
	if c >= b then return c end
	return (c * (c - a) + (b * b - c * c) / 2) / (b - a)
end
local function pastBy(x, a, b)
	local w = b - a
	if x <= -w then return 1 end
	if x >= w then return 0 end
	if x <= 0 then return 1 - (x + w) ^ 2 / (2 * w * w) end
	return (w - x) ^ 2 / (2 * w * w)
end
Model.WeaveMeans = { heldShot = heldShot, emax = emax, pastBy = pastBy }

-- The Survival branch's weave (raid-mode design section 15): wowsims' SV Weave preset (ui/specs/hunter/dps/builds/
-- sv_weave.siml, its rotation apls/default.apl.siml "Melee Weave (Max)" over weave_common.apl.siml) on the engine rules of
-- sim/core (read, not run; CONST.weave holds their numbers). "Once Auto Shot has gone off, walk in and swing; once I've
-- swung, hit or not, walk back out to the spot and shoot" (weave_common.apl.siml:6-7): the melee swing restarts the
-- ranged auto (attack.go:461-465, 1132-1140), so a cycle runs from one main-hand swing to the next and holds one Auto
-- Shot, one main-hand swing and one GCD action of the melee look, and the range looks share what is left.
-- The cycle at a Rapid Fire speed rf (0 or 0.40; the reaction rho uniform in [a, b], my arithmetic of design 15.2):
-- - M = p.mhSpeed / (meleeSpeed x (1 + rf)), the main hand's swing time; R = p.bowSpeed / hR and wu = windup / hR, the
--   ranged swing time and its windup at the shots' speed hR (the quiver, the ranged-only speed, Quick Shots, haste, rf);
-- - the walks at runSpeed: out from the melee spot to the shooting spot, W_out; in to melee range, W_in; Strider Kick's +30%
--   for 3 s shortens the walk out after a kick to 8.2 / 9.1 s and the next walk in by what is left of its 3 s,
--   t = max(0, 3 - E[S]): t + (8.19 - 9.1 t) / 7 while 9.1 t < 8.19, else 8.19 / 9.1; with k the share of cycles whose
--   melee look kicks, W_out and W_in are the k-weighted means (approximation WA6);
-- - the shot path: the swing's look walks out; the shot comes at R when its windup is due after the walk ends, else a
--   reaction after the walk (u = R - wu - W_out): E[S] = R + heldShot(u);
-- - the swing at max(the swing timer, the walk in after the shot's look): C = K + emax(M - K), K = E[S] + W_in (WA1);
-- - its spread for nCycles: sigma^2 = (b - a)^2 / 12 x P_arr x (1 + 2 P_held), P_arr = clamp((K + b - M) / (b - a)), the
--   walk setting the swing, P_held = clamp((b - u) / (b - a)), the shot waiting on the walk (WA2); 0 where the timer binds;
-- - C, k and Quick Shots' uptime (its 2% a rank on each Auto Shot, 12 / C shots in its 12 s) depend on each other: a
--   fixed-point iteration from k = 0 and no Quick Shots to |dC| < 1e-9 s; none in 100 iterations is an error (WA10).
-- What a cycle holds (design 15.3), at the cycle's spread:
-- - the Auto Shot, 1 / C a second, landing with shotHitf;
-- - the main-hand swing, 1 / C a second: Raptor Strike in its place every nCycles(6) cycles (armed: every rank needs a
--   class-2 weapon), the white swing in the others;
-- - the off hand: a swing in the visits where half its swing time (attack.go:806-819: starting the attack puts the off
--   hand's swing at least half its swing time out, at the unit's TotalMeleeHasteMultiplier, which Rapid Fire's melee
--   speed is in: unit.go:610-612, parse_effects_table.go:364-366) fits before the walk out, clamp((b + max(0, M - K) -
--   ohSwing / 2) / (b - a)) a cycle, ohSwing = p.ohSpeed / (the permanent melee speed x (1 + rf)) (the design's 15.3,
--   approximation WA7);
-- - the melee look's one GCD action (WA4), in default.apl.siml's order (rows 20-24): Strider Kick (from 30, the talent)
--   at nCycles(8 - 0.4) (kick_soon; its wait left out, WA3); Mongoose Bite (from 16 with Expose Prey: a melee weapon below
--   58, rank 4 bites unarmed) in the windows Expose Prey opens, 1 / (5 + e^(-5x) / x) a second, x = the landed hits of its
--   mask a second x 5% a rank (DB2 1310532 ProcTypeMask 0x154, spells_auto_gen.go:38066: melee swings and abilities, Auto
--   Shot and the ranged abilities, each hit that deals damage, proc_types.go:86-102; wowsims mongoose_bite.go:54-70): the
--   white swings, Raptor Strike, Strider Kick, Wing Clip (ProcMaskMeleeMHSpecial, wing_clip.go:15, a damage hit, :18), the
--   Auto Shots and Arcane Shot; not Mongoose Bite's own hit (its window opens in the bite's damage and the bite closes it
--   right after, mongoose_bite.go:37-42), not Serpent Sting's application (no damage, serpent_sting.go:25-28, and the
--   trigger needs damage dealt, aura_helpers.go:248), not Immolation Trap (ProcMaskSpellDamage, traps.go:57-59); in the
--   looks the kick leaves; Immolation Trap (from 16) at nCycles(30 x (1 - 0.2 x Survivalist's Discipline)) in the looks
--   left; Wing Clip (from 12, a melee weapon) in every look left but the look before a kick due within 1.5 s, taken as
--   min(1, 1.1 / C) of a look a kick;
-- - the range looks: one GCD slot a cycle and a second with P2 = f_M x pastBy(3 - E[S]) + (1 - f_M) x pastBy(1.5 +
--   W_range + r_poll - E[S]), f_M = min(1, the melee look's casts x C), W_range the walk out to minRanged, r_poll =
--   E[rho^2] / (2 E[rho]) the mean wait for the next look (WA5); in them Serpent Sting (levelling its casts a second from
--   the caller, CONST.serpentUptime; the raid fight re-casts it when its dot is gone, every I_S of the range looks: design
--   15.3), then Arcane Shot (from 6) at nCycles(6 - 0.3 x Improved Arcane Shot) of the range looks, then the shared
--   category 2 shot, Multi-Shot (from 18), at nCycles(6 + 0.5 / hR) of the range looks in the looks left (its 6 s
--   cooldown starts when its 0.5 s cast at the cycle's ranged speed hR completes, cast.go:224-258): the SV Weave preset
--   sets Use Aimed Shot false and Use Multi-Shot true (default.apl.siml:6-7, 30-33; the user's answer U3 = (a), design
--   15.11), its cast taken in the shooting spot's standing time (WA5); no Aimed Shot, no Summon Hawk, no dive, no hawks, no
--   Sniper Shot (no row in default.apl.siml).
-- Mongoose Bite's x includes Wing Clip's landed hits, which take the looks the bites leave, and Arcane Shot's and
-- Multi-Shot's (ProcMaskRangedSpecial, multi_shot.go:14: ranged abilities, in the mask), whose range slots follow the melee
-- look's casts (f_M), which follow the bites: the bites are solved at the cycle by a fixed-point iteration to 1e-12 a
-- second; none in 100 iterations is an error.
-- Damage (design 15.4), with the caller's phys, own, rws, rcrit, flat and the white and special rolls of the melee:
-- Auto Shot ((w + rapShot / 14) x s + flat) / C x shotHitf x rcrit x phys x own x rws; the white main hand ((mhDPS + mapOwn /
-- 14) x mhSpeed + flat) x whiteRollMH x (1 / C - r_R); the off hand (0.5 x (ohDPS + mapOwn / 14) x ohSpeed + flat) x
-- whiteRollOH x share_OH / C x (1 + 0.10 x Predator's Edge), each hand's white roll by its own skill (below); Raptor
-- Strike (swing + its rank bonus) x hitSpecial x critAbil
-- x r_R; Strider Kick normHit x hitSpecial x critAbil x r_K; Mongoose Bite with Lacerating Strikes x r_B; Wing Clip (its
-- rank's base + flat) x hitSpecial x critAbil x r_WC (Effect 2 physical with EffectBonusCoefficient 1, so Beastslaying
-- comes whole, spell_result.go:449-452; the melee special table, wing_clip.go:18; Savage Strikes and Predator's Edge
-- reach it, their masks 0:66 hold its 0:64), each melee hit x phys x own; Immolation Trap 5 x (its tick + 2% of the
-- shots' RAP) x (1 + 15% a rank of Clever Traps) x (1 - its spell miss) x (1 + 0.5 x spell crit) x own x r_T (fire, no
-- armor; 10% of the ranged attack power over five ticks, traps.go:10-14, 65-68; the application rolls the spell table,
-- traps.go:71-76, its miss less 5% a rank of Survival Tactics; the ticks crit at spell crit x1.5, Attributes_8 0x200 on
-- 14301, spelldata/spell.go:368-377), its own part (trap: fire, not the melee part's armor); Arcane Shot (its base +
-- 0.15 x rapShot) x shotHitf x rcrit x own x rws x r_A; Multi-Shot (the normalized weapon hit w x s + rapShot x 2.8 / 14 +
-- 9 + flat, multi_shot.go:20, hunter.go:20 normalizedShotBonus 9; Forever's one rank 2643) x shotHitf x rcrit x phys x own
-- x rws x (1 + 5% a rank of Barrage) x r_M, with Gift of Arthas on its hit (raid, O7).
-- Levelling averages every rate and part over Rapid Fire, (1 - rfUp) x at rf 0 + rfUp x at rf 0.40 (design 15.5); a state
-- of the raid fight is all outside Rapid Fire (rfUp 0) or all inside it (rfUp 1). Returns { base = the cycle at rf 0 (nil
-- at rfUp 1), rapidFire = at 0.40 (base at rfUp 0), average = the parts and landed hits a second, rfUp }; each cycle holds
-- C, sigma, k, qsUp, hR, M, R, wu, u, ES, K, Wout, Win, P2, nR and the rates a second (auto, mhWhite, raptor, oh, strider,
-- bite, trap, wingClip, arcane, multi, serpent: its casts, serpentLanded: its landed applications), and its casts by action
-- (acts: raptor, strider, bite, wingClip, trap, arcane, multi, serpent, each { casts, landed, crit } a second, crit the
-- chance a landed ability hit crits, nil for a cast that rolls no ability crit: partsAndHits' casts). average.acts is the
-- cycle's own where rfUp is 0 or 1 (a state of the raid fight), nil for a levelling average.
local function weaveParts(p, T, c)
	local wv = CONST.weave
	local a, b = wv.reactionMin, wv.reactionMax
	local lvl = c.lvl
	local armed = not p.unarmed
	local dw = p.ohDPS > 0 and not p.twoH
	-- Each hand rolls its own entry of the attack table, by the skill of the weapon it holds (wowsims
	-- sim/core/target.go:549-615 AttackTableHand, Hand; raid-mode W1 design 3.4): the main hand at p.mhSkill, the off hand
	-- at p.ohSkill (0 for an empty hand, weapon_skill.go:17-19). Raptor Strike, Strider Kick, Mongoose Bite and Wing Clip
	-- (ProcMaskMeleeMHSpecial, raptor_strike.go:13, talents_survival.go:153, mongoose_bite.go:31, wing_clip.go:15) and
	-- Lacerating Strikes' bleed (talents_survival.go:189) take the main hand's. The main hand's miss is the level's skill
	-- miss less p.hit and its skill's hit p.meleeHit (Model.SkillHit of p.mhSkill at the model point, which a set's weapon
	-- run holds while p.mhSkill moves: Score prices the main hand's skill hit through the cap, Score.SetValue hitValue);
	-- the off hand's is its own skill's miss less p.hit. Dodge, glance and crit suppression come from each hand's skill.
	local missMH = math.max(0, baseMiss(p.mobDiff) - p.hit - p.meleeHit) / 100
	local dodgeMH = math.max(0, Model.SkillDodge(p.mobDiff, p.mhSkill) - p.expertise) / 100
	local dodgeOH = math.max(0, Model.SkillDodge(p.mobDiff, p.ohSkill) - p.expertise) / 100
	-- dual wield: white swings miss 19% more, and hit keeps lowering that past the special cap
	local whiteMissMH = dw and math.max(0, baseMiss(p.mobDiff) + 19 - p.hit - p.meleeHit) / 100 or missMH
	local whiteMissOH = math.max(0, Model.SkillMiss(p.mobDiff, p.ohSkill) + 19 - p.hit) / 100
	local wmissMH, wmissOH = whiteMissMH + dodgeMH, whiteMissOH + dodgeOH
	-- the white table from behind (no parry), each hand at its glance and its crit
	local gChanceMH, gAvgMH = Model.Glance(p.mobDiff, p.mhSkill)
	local gChanceOH, gAvgOH = Model.Glance(p.mobDiff, p.ohSkill)
	local whiteRollMH = c.white(whiteMissMH, dodgeMH, 0, c.suppressed(c.meleeCrit, c.agiCrit, p.mhSkill), gChanceMH, gAvgMH)
	local whiteRollOH = c.white(whiteMissOH, dodgeOH, 0, c.suppressed(c.meleeCrit, c.agiCrit, p.ohSkill), gChanceOH, gAvgOH)
	-- melee abilities: Savage Strikes +2%/rank crit, Predator's Edge +6%/rank crit damage. Savage Strikes is a spell
	-- modifier on the abilities' crit (wowsims sim/hunter/talents_survival.go:76-82 ParseStatic), so it is aura crit of
	-- the ability's whole crit, suppressed with the rest on the main hand's entry
	local critAbil = 1 + c.suppressed(c.meleeCrit + 0.02 * T("savageStrikes"), c.agiCrit, p.mhSkill) * (1 + 0.06 * T("predatorsEdge"))
	local hitSpecial = 1 - missMH - dodgeMH
	-- a main-hand swing's damage, Beastslaying's flat included: Raptor Strike's own hit and the white swing
	local swing = p.mhDPS * p.mhSpeed + c.mapOwn / 14 * p.mhSpeed + c.flat
	-- the normalized main-hand hit of Strider Kick and Mongoose Bite, Beastslaying's flat included
	local normHit = p.mhDPS * p.mhSpeed + c.mapOwn / 14 * p.mhNorm + c.flat
	local strider = lvl >= 30 and T("striderKick") > 0
	-- Mongoose Bite ranks 1-3 (1495 / 14269 / 14270, SpellEquippedItems rows 254988-254990) need a melee weapon; rank 4
	-- (14271, from 58) has no row in build 70888, so from 58 it bites unarmed too
	local bites = lvl >= 16 and T("exposePrey") > 0 and (armed or lvl >= 58)
	local trapOn = lvl >= 16
	local wingClipOn = lvl >= 12 and armed
	local arcaneOn = lvl >= 6
	-- Multi-Shot 2643, learned at 18 (SpellLevel 18; Forever's one rank, wowsims spell_data_auto_gen.go:379 Ranked(2643))
	local multiOn = lvl >= 18
	-- the immolation trap's spell miss (Model.ProcOutcomes' magic table: 4% + 1% a level, 17% at +3) less the spell hit and
	-- Survival Tactics' 5% a rank (19376: SPELLMOD_RESIST_MISS_CHANCE, SpellEffect 695689; wowsims' curve 5 / 10,
	-- spells_auto_gen.go:39912)
	local spellMiss = spellMissPct(p.mobDiff) / 100
	local trapMiss = math.max(0, spellMiss - p.spellHit / 100 - 0.05 * T("survivalTactics"))
	-- Clever Traps 19239 effect 2: +15% a rank on the traps' damage (SpellEffect 695954, mask 0:4; curve 15 / 30,
	-- spells_auto_gen.go:39908; talents_survival.go:228-236)
	local trapHit = 5 * (Model.Rank("immolationTick", lvl) + 0.02 * c.rapShot) * (1 + 0.15 * T("cleverTraps"))
		* (1 - trapMiss) * (1 + 0.5 * p.spellCrit / 100) * c.own * c.coe
	-- Survivalist's Discipline 1310496: -20% a rank on the trap placements' cooldown (SpellEffect 1340058, aura 108 misc
	-- 11 mask 0:128; curve -20 / -40, spells_auto_gen.go:40027)
	local trapCooldown = wv.trapCooldown * (1 - 0.2 * T("survivalistsDiscipline"))
	local arcaneCooldown = wv.arcaneCooldown - 0.3 * T("improvedArcaneShot")
	local arcaneHit = (Model.Rank("arcaneBase", lvl) + 0.15 * c.rapShot) * c.shotHitf * c.rcrit * c.own * c.rws * c.coe
	local multiHit = (c.w * c.s + c.rapShot * 2.8 / 14 + 9 + c.flat) * c.shotHitf * c.rcrit * c.phys * c.own * c.rws
		* (1 + 0.05 * T("barrage")) + c.gift * c.shotHitf * c.rcrit
	local autoHit = ((c.w + c.rapShot / 14) * c.s + c.flat) * c.shotHitf * c.rcrit * c.phys * c.own * c.rws
		+ c.gift * c.shotHitf * c.rcrit
	local Wout0 = (wv.shootSpot - wv.meleeSpot) / wv.runSpeed
	local Win0 = (wv.shootSpot - wv.meleeRange) / wv.runSpeed
	local kickSpeed = wv.runSpeed * (1 + wv.striderSpeed)
	local WoutKick = (wv.shootSpot - wv.meleeSpot) / kickSpeed
	local dIn = wv.shootSpot - wv.meleeRange
	local Wrange = (wv.minRanged - wv.meleeSpot) / wv.runSpeed
	local rPoll = (a * a + a * b + b * b) / 3 / (a + b)
	local function cycleAt(rf)
		local M = p.mhSpeed / (c.meleeSpeed * (1 + rf))
		local k, qs, C = 0, 0, nil
		for _ = 1, 100 do
			local hR = c.rangedSpeed * (1 + 0.3 * qs) * c.haste * (1 + rf)
			local R, wu = c.s / hR, wv.windup / hR
			local Wout = (1 - k) * Wout0 + k * WoutKick
			local u = R - wu - Wout
			local ES = R + heldShot(u, a, b)
			local t = math.max(0, wv.striderDuration - ES)
			local WinKick = kickSpeed * t < dIn and t + (dIn - kickSpeed * t) / wv.runSpeed or dIn / kickSpeed
			local Win = (1 - k) * Win0 + k * WinKick
			local K = ES + Win
			local Cn = K + emax(M - K, a, b)
			local pArr = clamp01((K + b - M) / (b - a))
			local pHeld = clamp01((b - u) / (b - a))
			local sigma = math.sqrt((b - a) ^ 2 / 12 * pArr * (1 + 2 * pHeld))
			local done = C ~= nil and math.abs(Cn - C) < 1e-9
			C = Cn
			if done then
				return { C = Cn, sigma = sigma, k = k, qsUp = qs, hR = hR, M = M, R = R, wu = wu, u = u, ES = ES, K = K,
					Wout = Wout, Win = Win }
			end
			k = strider and 1 / nCycles(wv.striderCooldown - wv.kickSoon, Cn, sigma) or 0
			qs = 1 - (1 - c.qsChance) ^ (CONST.quickShotsDuration / Cn)
		end
		error("HunterGearAdvisor: the weave cycle does not converge in 100 iterations at mhSpeed " .. tostring(p.mhSpeed)
			.. ", bowSpeed " .. tostring(p.bowSpeed), 4)
	end
	local function at(rf)
		local cy = cycleAt(rf)
		local C, sigma = cy.C, cy.sigma
		local slot = 1 / C
		local rR = armed and 1 / (nCycles(wv.raptorCooldown, C, sigma) * C) or 0
		local rK = strider and 1 / (nCycles(wv.striderCooldown - wv.kickSoon, C, sigma) * C) or 0
		-- the off hand's swing time at the cycle's melee speed, Rapid Fire's in it (StartMeleeAttack takes the off hand's
		-- swing at TotalMeleeHasteMultiplier, attack.go:814-816)
		local ohSwing = p.ohSpeed / (c.meleeSpeed * (1 + rf))
		local shareOH = dw and clamp01((b + math.max(0, cy.M - cy.K) - ohSwing / 2) / (b - a)) or 0
		local trapDemand = trapOn and 1 / (nCycles(trapCooldown, C, sigma) * C) or 0
		-- Multi-Shot's cooldown counts from the end of its cast at the cycle's ranged speed (CONST.weave.multiCast)
		local multiCooldown = wv.multiCooldown + wv.multiCast / cy.hR
		-- the melee look's actions after the kick and the bite, then the range looks, for a bite rate rB
		local function looks(rB)
			local rT = math.min(trapDemand, slot - rK - rB)
			local rWC = 0
			if wingClipOn then
				if strider then
					rWC = math.max(0, slot - rK - rB - rT - rK * math.min(1, (wv.kickWingClip - wv.kickSoon) / C))
				else
					rWC = slot - rB - rT
				end
			end
			local fM = math.min(1, (rK + rB + rT + rWC) * C)
			local P2 = fM * pastBy(2 * wv.gcd - cy.ES, a, b) + (1 - fM) * pastBy(wv.gcd + Wrange + rPoll - cy.ES, a, b)
			local nR = 1 + P2
			local CR = C / nR
			-- Serpent Sting first in the range looks: levelling the caller's casts (CONST.serpentUptime); the raid fight re-casts
			-- it when its dot is gone (default.apl.siml:25; raid-mode design 15.3): the dot lands shootSpot / 40 s after the cast
			-- (CONST.raid serpentSpeed) and lasts 15 s, a miss (q, known at the cast) retried at the next range look, so the
			-- landed applications come every I_S = (nCycles(15 + travel, C_R, sigma) + q / (1 - q)) x C_R, the uptime 15 / I_S, the
			-- casts 1 / ((1 - q) I_S)
			local rS, landedS = c.serpentCastRate, c.serpentLanded
			if c.serpentRaid then
				local q = c.serpentRaid.q
				local IS = (nCycles(CONST.serpentDuration + wv.shootSpot / CONST.raid.serpentSpeed, CR, sigma) + q / (1 - q)) * CR
				rS, landedS = 1 / ((1 - q) * IS), 1 / IS
			end
			local rA = arcaneOn and math.min(1 / (nCycles(arcaneCooldown, CR, sigma) * CR), 1 / CR - rS) or 0
			local rM = multiOn and math.max(0, math.min(1 / (nCycles(multiCooldown, CR, sigma) * CR), 1 / CR - rS - rA)) or 0
			return rT, rWC, P2, nR, rA, rM, rS, landedS
		end
		-- the landed hits of Expose Prey's mask but Wing Clip's, Arcane Shot's and Multi-Shot's (which follow the bites,
		-- looks): the white swings, Raptor Strike, Strider Kick, the Auto Shots
		local meleeLanded = (slot - rR) * (1 - wmissMH) + shareOH * slot * (1 - wmissOH) + (rR + rK) * hitSpecial
		local autoLanded = c.shotHitf * slot
		local rB, x = 0, 0
		if bites then
			local chance = 0.05 * T("exposePrey")
			local settled = false
			for _ = 1, 100 do
				local _, rWC, _, _, rA, rM = looks(rB)
				x = (meleeLanded + rWC * hitSpecial + autoLanded + (rA + rM) * c.shotHitf) * chance
				local nb = math.min(1 / (5 + math.exp(-5 * x) / x), slot - rK)
				local diff = math.abs(nb - rB)
				rB = nb
				if diff < 1e-12 then settled = true; break end
			end
			if not settled then
				error("HunterGearAdvisor: the weave's Mongoose Bites do not settle in 100 iterations", 4)
			end
		end
		local rT, rWC, P2, nR, rA, rM, rS, landedS = looks(rB)
		-- the raid fight's starved regime (Model fight; raid-mode design 7.5, 15.5): each cast at its share of its rate, the
		-- cycle, Expose Prey's windows and the range looks as the rich regime has them (approximation A2); a main-hand swing
		-- Raptor Strike does not take is a white swing (the swings cost nothing and go on)
		if c.shares then
			local sh = c.shares
			for _, k in ipairs({ "raptor", "strider", "bite", "trap", "wingClip", "arcane", "multi", "serpent" }) do
				if type(sh[k]) ~= "number" then error("HunterGearAdvisor: a starved state of the weave without the share of " .. k, 4) end
			end
			rR, rK, rB, rT, rWC = rR * sh.raptor, rK * sh.strider, rB * sh.bite, rT * sh.trap, rWC * sh.wingClip
			rA, rM, rS, landedS = rA * sh.arcane, rM * sh.multi, rS * sh.serpent, landedS * sh.serpent
		end
		-- Lacerating Strikes: +40% of the bite as a bleed of 7 ticks, 3 s apart, whose ticks can crit (Attr8
		-- PERIODIC_CAN_CRIT). The next bite replaces the bleed and its unticked rest is lost (wowsims 774fc18; the row has
		-- no rolling-periodic attribute; not measured in game). Ticks that land before the next bite: P(gap >= 3k) =
		-- e^(-3kx) for k >= 2, one tick always.
		-- The bleed is 40% of the bite's dealt damage (wowsims sim/hunter/talents_survival.go:214-217, bleedDamage =
		-- result.Damage x share), so it carries 40% of the bite's Gift of Arthas as well, and its ticks take no modifier of
		-- their own (SpellFlagIgnoreModifiers, talents_survival.go:191; sim/core/flags.go:231): biteRoll is the bite's
		-- factor per attempt with its bleed, which its gift takes as the bite's damage does (my reading of the code, not run)
		local perBite, biteRoll = 0, 0
		if bites then
			local ticks = 1
			for k = 2, 7 do ticks = ticks + math.exp(-3 * k * x) end
			biteRoll = hitSpecial * critAbil * (1 + 0.40 * T("laceratingStrikes") * critAbil * ticks / 7)
			perBite = (normHit + Model.Rank("mongooseBonus", lvl)) * biteRoll
		end
		cy.P2, cy.nR = P2, nR
		cy.rates = { auto = slot, mhWhite = slot - rR, raptor = rR, oh = shareOH * slot, strider = rK, bite = rB, trap = rT,
			wingClip = rWC, arcane = rA, multi = rM, serpent = rS, serpentLanded = landedS }
		-- the casts by action: the melee abilities land with hitSpecial and crit at the abilities' crit (critAbil's chance), the
		-- range shots land with shotHitf and crit at the shots' (critR), Immolation Trap's application lands past its spell
		-- miss and Serpent Sting's application at its landed rate, neither rolling an ability crit (no damage of its own); a
		-- Raptor Strike not cast leaves its main-hand swing white, landing past the white table's miss and dodge (white)
		local abilCrit = c.suppressed(c.meleeCrit + 0.02 * T("savageStrikes"), c.agiCrit, p.mhSkill)
		cy.acts = {
			raptor = { casts = rR, landed = rR * hitSpecial, crit = abilCrit, white = 1 - wmissMH },
			strider = { casts = rK, landed = rK * hitSpecial, crit = abilCrit },
			bite = { casts = rB, landed = rB * hitSpecial, crit = abilCrit },
			wingClip = { casts = rWC, landed = rWC * hitSpecial, crit = abilCrit },
			trap = { casts = rT, landed = rT * (1 - trapMiss) },
			arcane = { casts = rA, landed = rA * c.shotHitf, crit = c.critR },
			multi = { casts = rM, landed = rM * c.shotHitf, crit = c.critR },
			serpent = { casts = rS, landed = landedS },
		}
		local mhWhite = ((p.mhDPS + c.mapOwn / 14) * p.mhSpeed + c.flat) * whiteRollMH * (slot - rR)
		local oh = dw and (0.5 * (p.ohDPS + c.mapOwn / 14) * p.ohSpeed + c.flat) * whiteRollOH * shareOH * slot
			* (1 + 0.10 * T("predatorsEdge")) or 0                        -- Predator's Edge +10%/rank off hand
		local raptor = (swing + Model.Rank("raptorBonus", lvl)) * hitSpecial * critAbil * rR
		local kick = normHit * hitSpecial * critAbil * rK
		local wingClip = (Model.Rank("wingClip", lvl) + c.flat) * hitSpecial * critAbil * rWC
		-- Gift of Arthas on the melee's physical hits (partsAndHits: gift), at each hit's roll without phys and own: the white
		-- swings of each hand, Raptor Strike, Strider Kick and Wing Clip, the bites with their bleed
		local meleeGift = c.gift * (whiteRollMH * (slot - rR) + (dw and whiteRollOH * shareOH * slot or 0)
			+ hitSpecial * critAbil * (rR + rK + rWC) + biteRoll * rB)
		cy.parts = {
			auto = autoHit * slot,
			arcane = arcaneHit * rA,
			multi = multiHit * rM,
			melee = (mhWhite + oh + raptor + kick + perBite * rB + wingClip) * c.phys * c.own + meleeGift,
			trap = trapHit * rT,
		}
		cy.hits = {
			mhSwings = (slot - rR) * (1 - wmissMH),
			mhSpecials = (rR + rK + rB + rWC) * hitSpecial,
			ohSwings = shareOH * slot * (1 - wmissOH),
			rangedSwings = c.shotHitf * slot,
			rangedSpecials = (rA + rM) * c.shotHitf,
		}
		return cy
	end
	local up = c.rfUp
	-- a segment of the raid fight is all outside Rapid Fire (up 0: base alone) or all inside it (up 1: rapidFire alone)
	local base = up < 1 and at(0) or nil
	local fast = up > 0 and at(CONST.rapidFireSpeed) or base
	local average = {}
	local one = base or fast
	for _, src in ipairs({ "parts", "hits" }) do
		for key in pairs(one[src]) do
			average[key] = up == 1 and fast[src][key] or (1 - up) * base[src][key] + up * fast[src][key]
		end
	end
	average.rates = {}
	for key in pairs(one.rates) do
		average.rates[key] = up == 1 and fast.rates[key] or (1 - up) * base.rates[key] + up * fast.rates[key]
	end
	if up == 0 or up == 1 then average.acts = one.acts end
	return { base = base, rapidFire = fast, average = average, rfUp = up }
end

-- The parts of the damage (Model.Parts) and the hunter's own landed hits by hand (Model.LandedHits), from one pass
-- over the same formulas. Levelling mode: one pass with seg nil, the cooldowns at their averages. Raid mode: one pass a
-- state of the fight (Model fight, raid-mode design 6.1), seg = { rf = Rapid Fire up, bw = Bestial Wrath up, shares = the
-- starved regime's share of each item of STARVED_ITEMS, nil in the rich regime }, the Use buffs of the state already
-- applied to p; a pass of the other mode's form is an error. Returns out (the parts), hits,
-- the weave (weaveParts, nil outside it), the raid tempo (nil while levelling) and, in raid mode, the casts (raid-mode
-- design 6.1, the mana spend's reader): { acts = { [action] = { casts, landed, crit, white } }, free }, every cast of the
-- state a second by action (the turret's serpent, aimed, arcane, hawk, sniper, multi; the weave's of weaveParts), each with
-- its landed hits a second, the crit chance of a landed ability hit (nil where it rolls no ability crit: Serpent Sting's
-- application, Immolation Trap's) and white, the landed white swing one cast of it not made leaves (the weave's Raptor
-- Strike: its main-hand swing goes on white at the white table's landing, weaveParts; nil for the others), and free, the
-- landed hits that cost no mana a second (the Auto Shots and the white swings); nil while levelling.
local function partsAndHits(p, seg)
	local T = talents(p)
	checkInputs(p, REQUIRED_NUMBERS, REQUIRED_FLAGS)
	checkMode(p)
	if (p.mode == "raid") ~= (seg ~= nil) then
		error("HunterGearAdvisor: a pass of the damage model in mode " .. tostring(p.mode) .. (seg and " with" or " without")
			.. " a segment of the raid fight", 3)
	end
	local lvl = p.level
	local mobDiff = p.mobDiff
	-- the starved regime's share of a cast's rate (Model fight; raid-mode design 7.5): the build that shoots from range buys
	-- the HHA elements (hha), Serpent Sting, Aimed Shot and Sniper Shot; 1 in the rich regime and while levelling
	local shares = seg and seg.shares
	local function share(name)
		if not shares then return 1 end
		local v = shares[name]
		if type(v) ~= "number" then error("HunterGearAdvisor: a starved state without the share of " .. tostring(name), 2) end
		return v
	end
	-- the armor of the mode's target (physOf): raid mode the boss's 976 less p.armorPen for the hunter's own attacks (phys)
	-- and the whole 976 for the pet's and the hawks' (petPhys: no armor penetration of their own), levelling the creature's
	-- own for all
	local phys = physOf(p, p.armorPen)
	local petPhys = physOf(p, 0)
	local raid = p.mode == "raid"
	-- The raid boss's other debuffs of the preset (raid-mode design 5.3, the user's answer O7 = (a); CONST.raid): Curse of
	-- the Elements multiplies every magic-school hit by coe (Arcane Shot, Serpent Sting's nature ticks, Immolation Trap's
	-- fire ticks; Model.ProcOutcomes the magic procs); Gift of Arthas adds gift to every physical-school hit after the
	-- attacker's multipliers and the armor, before the outcome, so a physical part gains gift x its attempts a second x its
	-- outcome factor (hit and crit, the glance of a white swing), without phys, own or any multiplier of the attacker: Auto
	-- Shot, Aimed, Sniper, the dive, the hawks', the pet's white swings and Claw / Bite, the weave's white swings, Raptor
	-- Strike, Strider Kick, Mongoose Bite and Wing Clip, Multi-Shot (the weave's at any level from 18, the turret's at 18 and
	-- 19 alone: not in raid mode outside the weave).
	-- Levelling mode: none (coe 1, gift 0)
	local coe = raid and CONST.raid.coe or 1
	local gift = raid and CONST.raid.giftOfArthas or 0
	-- the pet's and the hawks' glances: their own tables at bonus 0 (Model.Glance)
	local glanceChance, glanceAvg = Model.Glance(mobDiff, 0)
	local avoid = Model.MobAvoid(mobDiff) / 100
	-- A white melee swing (the hunter's, the pet's, a hawk's) is one roll on the white table (wowsims
	-- sim/core/spell_outcome.go:852-875 OutcomeExpectedMeleeWhite): miss, dodge, parry (from the front alone), glance,
	-- crit, hit; its expected damage factor is 1 - miss - dodge - parry + (crit multiplier - 1) x min(crit, the room left)
	-- - glance x (1 - its average factor), the room left being 1 - miss - dodge - parry - glance (no block: the pet's
	-- from the front is left out, no creature block value in the sources; behind the target there is none). The crit
	-- multiplier of a physical hit is 2 (sim/core/spell.go:959-975). A special (Raptor Strike, Strider Kick, Mongoose
	-- Bite, the pet's Claw and Bite) rolls hit, then crit (spell_outcome.go:876-883): (1 - miss - dodge - parry) x (1 + crit).
	-- gChance and gAvg: the attacker's glance chance and average factor (Model.Glance of its hand's skill).
	local function white(miss, dodge, parry, crit, gChance, gAvg)
		local room = 1 - miss - dodge - parry - gChance
		return 1 - miss - dodge - parry + math.min(crit, room) - gChance * (1 - gAvg)
	end
	local creatureDPS = CREATURE_DPS[math.max(1, math.min(60, lvl))]
	-- Attack power against the target's creature type (p.apVsTarget) reaches the hunter's own attacks alone: wowsims adds
	-- it to the unit's own attack tables (sim/core/attack_table_helpers.go:46-54 AddMobTypeBonusStats), which the hunter's
	-- ranged attack power (sim/core/spell_result.go:185-187 RangedAttackPower) and melee attack power (sim/core/unit.go:265-267)
	-- read; the pet and the hawks take theirs from the owner's stats, which hold no versus-type part (the pet max(AP, RAP) x
	-- 0.1, sim/hunter/pets.go:122-128; a hawk (RAP + its weapon AP) x 0.8, sim/hunter/summon_hawk.go:79-81). So rapOwn
	-- feeds the shots, Serpent Sting and the dive (the hunter's spell, summon_hawk.go:130-139), mapOwn the hunter's melee;
	-- the pet and the hawks keep p.rap and p.map.
	local rapOwn = p.rap + p.apVsTarget
	local mapOwn = p.map + p.apVsTarget
	local rapShot = rapOwn + Model.Rank("huntersMark", lvl)
	-- Beastslaying's flat damage per hit (p.beastSlaying) against the mode's share of targets that are beasts
	-- (Model.TargetShare: levelling Model.AP_CREATURE_SHARE, raid 0, the boss a dragonkin). wowsims: the enchant's aura
	-- 7784 / 13650, A_MOD_DAMAGE_DONE_CREATURE, gives the
	-- player PhysicalDamage and SpellDamage against the masked types (sim/core/spelldata/mob_types.go:9-16) on the
	-- unit's own attack tables (sim/core/attack_table_helpers.go:47-54 AddMobTypeBonusStats), so it reaches the hunter's
	-- own attacks alone, never the pet's or the hawks'. CalcDamage adds that bonus to the base damage before the
	-- attacker's multipliers, the armor and the outcome (sim/core/spell_result.go:445-462, BonusDamage 236-246) for a
	-- spell with a bonus coefficient or of the physical school without SpellFlagPhysicalSchoolDamage; a physical row that
	-- deals school damage takes that flag and its row's coefficient (sim/core/spelldata/resolve_spell.go:135-139), a
	-- periodic one only with a dot coefficient (spell_result.go:464-480). A physical weapon's auto attacks have
	-- coefficient 1 (sim/core/attack.go:131-136 GetBonusCoefficient), and the off hand's 0.5 is on its weapon damage alone
	-- (attack.go:174-176), so the off hand takes the bonus whole. In Forever DB2 build 70888 the weapon-damage rows
	-- (SpellEffect Effect 121 or 58) are Aimed Shot 20904 (697764), Multi-Shot 2643 (680907), Sniper Shot 1310786
	-- (1340619), Raptor Strike 14266 (691552, Effect 58), Mongoose Bite 14271 (690394) and Strider Kick 1317257 (1350273):
	-- with the white main hand, off hand and Auto Shot they take flat on each hit. Arcane Shot 14287 (691069) and the dive
	-- 1293527 (1314239) are Effect 2 school damage with EffectBonusCoefficient 0, and Serpent Sting's ticks have no dot
	-- coefficient: none.
	local flat = p.beastSlaying * Model.TargetShare("BEAST", p.mode)
	local crit = p.crit / 100
	local meleeCrit = p.meleeCrit / 100
	local suppressed, agiCrit = critSuppressor(p)
	-- the shots', the dive's and Serpent Sting's crit (critR: the ranged hand's entry at p.rangedSkill); the hunter's melee
	-- takes each hand's own (weaveParts)
	local critR = suppressed(crit, agiCrit, p.rangedSkill)
	-- The pet's crit before Ferocity, half of which the hawks take (wowsims sim/hunter/pets.go:142-153 inheritedCrit:
	-- max(0, melee, ranged), each the sheet's crit in percent less 0.04 a point of its hand's skill below the level's
	-- maximum, min(bonus, 0) x 0.04; summon_hawk.go:83 a hawk half of it; raid-mode W1 design section 4): the melee
	-- branch p.meleeCrit with the main hand's skill, the ranged branch p.crit, the sheet's ranged crit, with the ranged
	-- skill, each 0.04% a point below the maximum (0.0004 as a fraction), nothing above it. With equal sheet crits and the
	-- main hand at or above its maximum the melee branch holds, so a bow deficit reaches the pet only with a ranged-only
	-- crit lead (my reading of pets.go:147-153).
	local petCritBase = math.max(0, meleeCrit + 0.0004 * math.min(p.mhSkill, 0), crit + 0.0004 * math.min(p.rangedSkill, 0))
	-- the hunter's melee hit: p.hit and the main hand's skill hit p.meleeHit (weaveParts; see the shots below)
	-- the pet's and the hawks' hit: p.hit and the worn gear's ranged-only hit p.rangedGearHit
	local missPH = missChance(mobDiff, p.hit + p.rangedGearHit)
	-- the shots' hit: p.hit, p.rangedGearHit and the ranged weapon skill's p.rangedHit on top
	local shotHitf = 1 - missChance(mobDiff, p.hit + p.rangedGearHit + p.rangedHit)
	-- the owner's attack speed of every scope (wowsims sim/core/unit.go:610-638 TotalMeleeHasteMultiplier and
	-- TotalRangedHasteMultiplier: AttackSpeedMultiplier x the scope's multiplier x hasteRatingMultiplier; an item's or
	-- enchant's aura 342 is in the melee and the ranged multiplier both, enchant_speed.go:65-79): p.haste, p.attackSpeed and
	-- p.hasteRating, the hunter's shots and their casts and the melee swings
	local haste = (1 + p.haste / 100) * (1 + p.attackSpeed / 100) * (1 + p.hasteRating / 100)
	-- the permanent melee speed (no Rapid Fire): Raptor Strike's count is taken at it with and without Rapid Fire
	local meleeSpeed = haste * (1 + p.meleeHaste / 100)
	-- Rapid Fire: the share of time it is up and the speed it adds, levelling the averages (rapidFire), a segment of the raid
	-- fight 1 and 0.40 inside its window, 0 and 0 outside (raid-mode design 6.1)
	local rfUp, rf
	if seg then
		rfUp, rf = seg.rf and 1 or 0, seg.rf and CONST.rapidFireSpeed or 0
	else
		rfUp, rf = rapidFire(lvl, T)
	end
	-- the pet's swing rate from its owner with Rapid Fire's speed (petSpeedMult)
	local petInherit = petSpeedMult(p, rf)

	local own, hasPet, loneWolf, lone, ff = ownDamage(p, T)
	local rws = 1 + 0.01 * T("rangedWeaponSpec")                      -- Ranged Weapon Specialization +1%/rank
	local rcrit = 1 + critR * (1 + 0.06 * T("mortalShots"))           -- Mortal Shots: +6%/rank ranged crit damage
	local qsChance = 0.02 * T("deadlyAspects")                        -- Deadly Aspects: 2%/rank Quick Shots per Auto Shot

	-- The shots need a bow, gun or crossbow: Auto Shot 75, Aimed Shot (19434, 20900-20904), Multi-Shot 2643,
	-- Arcane Shot (3044, 14281-14287), Serpent Sting (1978, 13549-13555, 25295) and Sniper Shot (1310687,
	-- 1310785, 1310786) each have a SpellEquippedItems row with EquippedItemClass 2 and EquippedItemSubclass
	-- 262156 (bits 2 Bows, 3 Guns, 18 Crossbows), Forever DB2 build 70888. With p.noShots none is cast: they deal
	-- nothing, Auto Shot rolls no Quick Shots and no shot opens Expose Prey. Summon Hawk (1293241,
	-- 1293525-1293527: the dive and the hawks), Hunter's Mark (1130, 14323-14325) and Rapid Fire 3045 have no
	-- row: they stay. Ranged Weapon Specialization (talent node 104998 -> TraitNodeEntry 129662 ->
	-- TraitDefinition 134463 -> spell 19507: aura 79, misc 127, all schools) has SpellEquippedItems row 179969
	-- with the same EquippedItemClass 2 and EquippedItemSubclass 262156, so with p.noShots it is off: the dive
	-- takes none of it (diveRws).
	-- Hit by attack (wowsims): the pet and the hawks take the owner's physical hit plus the owner's ranged-only hit
	-- (sim/hunter/pets.go:155-158 inheritedHit, the pet's stat inheritance pets.go:122-145, the hawks'
	-- summon_hawk.go:79-86), the ranged-only hit being the RangedHitPercent pseudo-stat that wowsims' item and enchant
	-- fold fills from an aura 54 bound to ranged weapons (tools/database/dbc/util.go:356-373); weapon skill is no stat
	-- there, their attack tables are their own at level 60, skill 300. So the pet and the hawks land with missPH: p.hit
	-- and the worn gear's ranged-only hit p.rangedGearHit. The six shots, and the shot hits that open Expose Prey, land
	-- with shotHitf: p.hit, p.rangedGearHit and on top p.rangedHit, the ranged weapon skill's hit, the ranged hand's
	-- entry of the attack table (wowsims sim/core/target.go:606-615 Hand: a ranged proc mask; spell_outcome.go:566-571,
	-- no dual-wield penalty) against the level's skill, Model.SkillHit(mobDiff, p.rangedSkill), which Advisor A.State
	-- sets. The hunter's melee lands with p.hit and each hand's skill (weaveParts: the main hand's p.meleeHit, the off
	-- hand's p.ohSkill; the dual-wield white miss);
	-- the dive rolls no hit in this model (wowsims summon_hawk.go: OutcomeRangedCritOnly).
	local shoots = not p.noShots
	-- The Survival branch (p.survival: strictly the most talent points in Survival, Player.SurvivalBranch) fights as
	-- wowsims' SV Weave preset (raid-mode design section 15; the user, 2026-11-17): with a bow, gun or crossbow it weaves
	-- (weave below); without one no Auto Shot comes, so shot_since_swing (weave_common.apl.siml:20) stays false after the
	-- first swing and the weave never walks back in: no melee and no shot (my reading of the APL, not run). Every other
	-- build has no melee (the user: «мили атака вообще ни в учет хант ее избегает кроме сурв ветки») and shoots from range.
	local weave = p.survival and shoots
	local turret = shoots and not p.survival
	local s = p.bowSpeed
	-- The owner's ranged speed multiplier (wowsims RangedSpeedMultiplier) before Quick Shots and Rapid Fire: the
	-- quiver (sim/hunter/hunter.go: RangedSpeedMultiplier x the quiver's haste) and the ranged-only attack speed.
	local rangedSpeed = (1 + p.quiver) * (1 + p.rangedHaste / 100)
	-- Quick Shots' uptime: the chance that one of the Auto Shots of its last 12 s rolled it (wowsims rolls it on each Auto
	-- Shot, sim/hunter/aspects.go), those Auto Shots at the shots' speed with it up (x1.3); in a state of the raid fight at
	-- the state's own Auto Shot rate, Rapid Fire's 40% in it inside its window, so more of them roll it there (raid-mode
	-- design 25.4); the levelling mode's averaged pass at the speed without Rapid Fire (HGA's levelling estimate)
	local qsRf = seg and rf or 0
	local shots12 = CONST.quickShotsDuration * rangedSpeed * 1.3 * haste * (1 + qsRf) / s
	local qsUp = 0
	if turret then qsUp = 1 - (1 - qsChance) ^ shots12 end
	-- Quick Shots 6150 (Deadly Aspects' proc off Auto Shot, wowsims sim/hunter/aspects.go): aura 140 +30, ranged speed
	local ranged = rangedSpeed * (1 + 0.3 * qsUp)
	local hBase = ranged * haste       -- the shots' speed: TotalRangedHasteMultiplier without Rapid Fire
	local hRanged = hBase * (1 + rf)
	-- The hawks swing at the owner's ranged speed multiplier alone (wowsims, by the user's rule for W1's open questions,
	-- raid-mode W1 design section 7): a hawk inherits RangedSpeedMultiplier at its summon and each later
	-- MultiplyRangedSpeed (sim/core/pet.go:415-431, sim/core/unit.go:681-692; summon_hawk.go:88-91
	-- HasDynamicRangedSpeedInheritance), not the AttackSpeedMultiplier, the melee speed or haste rating; summon_hawk.go:63-65
	-- states it: a hawk's swing follows its owner's ranged speed, the quiver's and Quick Shots' included. So the hawks take
	-- the quiver (sim/hunter/hunter.go:90 RangedSpeedMultiplier), the aura 140 of the ranged-only speed (p.rangedHaste),
	-- Quick Shots and Rapid Fire (parse_effects_table.go:369-371 MultiplyRangedSpeed) and an item's or enchant's aura 342
	-- (p.haste: enchant_speed.go:65-79 AttachHastePseudoStats multiplies the ranged speed too), not the set bonuses' and
	-- Wind Blessed's attack speed (p.attackSpeed: MultiplyAttackSpeed, unit.go:729-742, reaches the DynamicMeleeSpeedPets
	-- alone) and not haste rating (p.hasteRating). In Forever DB2 SpellEffect, Wind Blessed 1259710, the Tier-1 two-piece
	-- bonuses and Minor Haste 13928 carry the same auras, 342 and 65; the paths are wowsims'. hawkSpeed = (1 + quiver) x
	-- (1 + rangedHaste/100) x (1 + 0.3 x qsUp) x (1 + haste/100) x (1 + rf). No EV file measures a hawk's swing speed.
	-- Berserking (the Forever Troll racial 20554) is not modelled: no gear changes it, and wowsims states that its speed
	-- does not reach a hawk (summon_hawk.go:63-65; AttachMultiplyAttackSpeed, sim/core/racials.go:165-171).
	local hawkSpeed = ranged * (1 + p.haste / 100) * (1 + rf)

	local w = p.bowDPS + p.ammoDPS
	local out = {}
	-- Auto Shots, Aimed, Multi-Shot, Arcane and Sniper Shots per second of the build that shoots from range (turret)
	local autoRate, aimedRate, multiRate, arcRate, sniperRate = 0, 0, 0, 0, 0
	out.auto, out.aimed, out.multi, out.arcane, out.sniper = 0, 0, 0, 0, 0
	if turret then
		autoRate = hRanged / s
		out.auto = (w + rapShot / 14 + flat / s) * hRanged * shotHitf * rcrit * phys * own * rws + gift * autoRate * shotHitf * rcrit
		if lvl >= 20 then
			-- the 6 s cooldown starts after the 2 s cast (cast sped up by ranged haste); next to Sniper
			-- Shot more of its cooldown is lost to the other casts
			local use = (lvl >= 40 and T("sniperShot") > 0) and CONST.aimedUseSniper or CONST.aimedUse
			aimedRate = use / (6 + 2.0 / hRanged) * share("aimed")
			out.aimed = (w * s + rapShot * 2.8 / 14 + Model.Rank("aimedBonus", lvl) + 9 + flat) * aimedRate * shotHitf * rcrit * phys
				* own * rws * (1 + 0.05 * T("barrage"))                       -- Barrage +5%/rank Aimed/Multi
			-- Rapid Killing: a kill gives the next Shot +10%/rank (taken as the next Aimed Shot), one kill
			-- per CONST.killInterval while levelling; the raid boss dies once, at the fight's end (CONST.killInterval)
			if T("rapidKilling") > 0 and not raid then
				out.aimed = out.aimed * (1 + 0.10 * T("rapidKilling") / (aimedRate * CONST.killInterval))
			end
			out.aimed = out.aimed + gift * aimedRate * shotHitf * rcrit
		end
		-- Multi-Shot (from 18): the same 6 s cooldown category as Aimed Shot (DB2 category 2), so only
		-- before Aimed Shot is learned at 20. Normalized weapon damage + 9 (EV-0068), a 0.5 s cast that
		-- ranged haste shortens (EV-0069), Barrage +5%/rank.
		if lvl >= 18 and lvl < 20 then
			multiRate = CONST.aimedUse / (6 + 0.5 / hRanged)
			out.multi = (w * s + rapShot * 2.8 / 14 + 9 + flat) * multiRate * shotHitf * rcrit * phys * own * rws
				* (1 + 0.05 * T("barrage"))
		end
	end
	-- Summon Hawk (the hawks and the dive) only outside the Survival weave: the SV Weave preset's Use Summon Hawk = false
	-- (default.apl.siml:9, rows 26-28) casts it never, with the talent taken or not
	local hawksOn = lvl >= CONST.hawkLearnLevel and T("summonHawk") > 0 and not p.survival
	-- Arcane Shot shares its 6 s category cooldown with Summon Hawk (category 1173: Arcane Shot 14287 and the dive 1293527
	-- each a 6 s CD on it, spells_auto_gen.go:10733 and :35894): with hawks the HHA sequence (turret_hawk.apl.siml:15-16)
	-- casts 2 hawks and 1 Arcane a cycle of C0 = 18 - 0.3 x Improved Arcane Shot s, the category ready 6 s after a Summon
	-- Hawk and 6 - 0.3 x rank s after an Arcane Shot (Improved Arcane Shot 19454: SPELLMOD_COOLDOWN -300 ms a rank on Arcane
	-- Shot's class mask, DB2 SpellEffect 696223; wowsims spell_mod.go:949-961, cast.go:321-333; raid-mode W1 design
	-- section 6); without hawks, Arcane on its own cooldown (Improved Arcane Shot -0.3 s/rank)
	local hhaCycle = 18 - 0.3 * T("improvedArcaneShot")
	-- The raid fight's cast tempo (raid-mode design 6.4-6.5, approximation A1) of the build that shoots from range (the
	-- Survival weave has its own range looks, weaveParts): wowsims' rotation looks again when the GCD ends after an action on
	-- it, at a hardcast's end when the cast outlasts the GCD (sim/core/gcd.go:93-115; apl.go:594-613), and a reaction later
	-- after a look that takes no action; the reaction drawn uniformly in 150-350 ms (CONST.raid reactionMin, reactionMax).
	-- So an action that becomes ready (Serpent Sting's dot gone, the HHA category over) waits for the hold in progress, if
	-- any, else for the next look: its mean wait delta_X = b_X R_X + (1 - b_X) r_poll, b_X = sum f_i h_i over the other GCD
	-- actions i at their full rates f_i (the HHA elements 3 / C0 with hawks, Arcane Shot alone at its use share without them,
	-- Serpent Sting 1 / 15, Aimed Shot aimedUse / (6 + 2 / hRanged), Sniper Shot sniperUse / (15 + 4 / hRanged)) and their
	-- holds h_i = max(GCD, cast) (Aimed's cast 2 / hRanged, Sniper's 4 / hRanged), b_X R_X = sum f_i h_i^2 / 2 (the mean rest of
	-- the hold in progress, length-biased), r_poll = E[R^2] / (2 E[R]) = 0.1317 s the mean rest of a look's reaction R (my
	-- arithmetic). Swings that bring a look earlier are left out. tempo: serpentWait (delta_S), hawkWait (delta_H) and the
	-- quantities they set below (the HHA cycle, the hawks' uptime, Serpent Sting's); a build without hawks has no HHA
	-- sequence (Arcane Shot on its own cooldown), so no hawkWait and no hhaCycle.
	local tempo
	if seg and not p.survival then
		local r = CONST.raid
		local a, b = r.reactionMin, r.reactionMax
		local rPoll = (a * a + a * b + b * b) / 3 / (a + b)
		local acts = {}
		if hawksOn then
			acts[#acts + 1] = { "hha", 3 / hhaCycle, r.gcd }
		elseif lvl >= 6 and turret then
			acts[#acts + 1] = { "hha", CONST.arcaneUse / (6 - 0.3 * T("improvedArcaneShot")), r.gcd }
		end
		if lvl >= 4 and turret then acts[#acts + 1] = { "serpent", 1 / CONST.serpentDuration, r.gcd } end
		if lvl >= 20 and turret then
			local use = (lvl >= 40 and T("sniperShot") > 0) and CONST.aimedUseSniper or CONST.aimedUse
			acts[#acts + 1] = { "aimed", use / (6 + 2.0 / hRanged), math.max(r.gcd, 2.0 / hRanged) }
		end
		if lvl >= 40 and T("sniperShot") > 0 and turret then
			acts[#acts + 1] = { "sniper", CONST.sniperUse / (15 + 4.0 / hRanged), math.max(r.gcd, 4.0 / hRanged) }
		end
		local function wait(x)
			local held, rest = 0, 0
			for _, act in ipairs(acts) do
				if act[1] ~= x then
					held = held + act[2] * act[3]
					rest = rest + act[2] * act[3] * act[3] / 2
				end
			end
			return rest + (1 - held) * rPoll
		end
		tempo = { serpentWait = wait("serpent"), hawkUptime = 0, serpentUptime = 0, serpentCasts = 0 }
		-- with hawks each of the three HHA elements ready 6 s after the one before it (Arcane Shot's own 6 - 0.3 x rank) and
		-- cast delta_H later: a cycle of C = C0 + 3 delta_H (raid-mode design 6.5; W1D 6), each hawk re-summoned once a cycle
		-- and living 18 s, so its uptime min(1, 18 / C) (my arithmetic)
		if hawksOn then
			tempo.hawkWait = wait("hha")
			tempo.hhaCycle = hhaCycle + 3 * tempo.hawkWait
			tempo.hawkUptime = math.min(1, CONST.hawkDuration / tempo.hhaCycle)
		end
	end
	if lvl >= 6 and turret then
		-- with hawks one Arcane Shot a cycle of the HHA sequence: C0 levelling, the tempo's C in the raid fight
		if hawksOn then
			arcRate = 1 / (tempo and tempo.hhaCycle or hhaCycle) * share("hha")
		else
			arcRate = CONST.arcaneUse / (6 - 0.3 * T("improvedArcaneShot")) * share("hha")
		end
		out.arcane = (Model.Rank("arcaneBase", lvl) + 0.15 * rapShot) * arcRate * shotHitf * rcrit * own * rws * coe
	end
	local stings = 1 + (IMPROVED_STINGS[T("improvedStings")] or 0)
	-- Serpent Sting's landed applications per wall-clock second (Model.LandedHits ranged.casts). Levelling, from range: one
	-- sting per CONST.serpentDuration for CONST.serpentUptime of the time, landing with shotHitf (HGA's levelling estimate);
	-- in the weave the sting is cast from the shooting spot, the uptime CONST.serpentUptime that of the landed sting: the SV
	-- Weave rotation casts it while its dot is down (default.apl.siml:25), so a sting that misses is cast again at the next
	-- range look and a miss costs a cast, not uptime (raid-mode design 15.3 and 18.3: its applications serpentUptime /
	-- serpentDuration a second, its casts that over shotHitf, which take range looks). The raid fight re-casts it when its
	-- dot is gone (turret_hawk.apl.siml:14 cast serpent_sting if not dot(serpent_sting).is_active; raid-mode design 6.4): the
	-- cast rolls the ranged table (serpent_sting.go:40 OutcomeRangedHit, a miss q = 1 - shotHitf known at the cast and the
	-- next try at its GCD's end) and the dot lands after its travel (serpent_sting.go:43-49; CONST.raid distance /
	-- serpentSpeed): from the dot's end to the next landed one g = delta_S + travel + q / (1 - q) x GCD, so the landed
	-- applications aL = 1 / (15 + g) a second, the uptime 15 aL and the casts aL / (1 - q); the weave's from its range looks
	-- (weaveParts)
	local serpentCasts, serpentCastRate, perSting = 0, 0, 0
	if lvl >= 4 and shoots then -- Serpent Sting is learned at 4
		local tick = p.serpentTick or Model.Rank("serpentTick", lvl)
		perSting = (5 * tick + 0.25 * rapShot) * rcrit * own * rws * stings * coe
		if weave then
			if not seg then
				serpentCasts = CONST.serpentUptime / CONST.serpentDuration
				serpentCastRate = serpentCasts / shotHitf
			end
		elseif seg then
			local r = CONST.raid
			local q = 1 - shotHitf
			serpentCasts = 1 / (CONST.serpentDuration + tempo.serpentWait + r.distance / r.serpentSpeed + q / (1 - q) * r.gcd)
				* share("serpent")
			tempo.serpentUptime = CONST.serpentDuration * serpentCasts
			tempo.serpentCasts = serpentCasts / (1 - q)
		else
			serpentCasts = CONST.serpentUptime / CONST.serpentDuration * shotHitf
		end
		out.serpent = perSting * serpentCasts
	else
		out.serpent = 0
	end
	-- Sniper Shot (MM 31 points, from 40): normalized weapon damage (2.8, ammo included) + rank
	-- bonus, 4 s cast then 15 s cooldown; Mortal Shots yes, Barrage no (wowsims sniper_shot.go)
	if lvl >= 40 and T("sniperShot") > 0 and turret then
		sniperRate = CONST.sniperUse / (15 + 4.0 / hRanged) * share("sniper")
		out.sniper = (Model.Rank("sniperBonus", lvl) + w * s + rapShot * 2.8 / 14 + flat) * sniperRate * shotHitf * rcrit * phys
			* own * rws + gift * sniperRate * shotHitf * rcrit
	end

	local uf = 1 + 0.03 * T("unleashedFury")                         -- Unleashed Fury +3%/rank pet and hawks
	-- the dives per second: two Summon Hawk casts a cycle of the HHA sequence (C0, hhaCycle above, levelling; the tempo's C in
	-- the raid fight), each a dive that always lands (wowsims summon_hawk.go:130-139 OutcomeRangedCritOnly)
	local diveRate = hawksOn and 2 / (tempo and tempo.hhaCycle or hhaCycle) * share("hha") or 0
	-- the hawks' uptime: levelling CONST.hawkUptime, the raid fight the tempo's min(1, 18 / C) at the whole share and, below
	-- it, min(1, 9 rH) at the dives' rate rH (each summon keeps a hawk 18 s, two hawks; raid-mode design 6.5)
	if tempo and share("hha") < 1 then tempo.hawkUptime = math.min(1, CONST.hawkDuration / 2 * diveRate) end
	-- With no bow, gun or crossbow the raid fight's HHA sequence stops at Arcane Shot after its first two hawks (Model fight;
	-- raid-mode design 25.5): a state holds seg.hawks of them up (0, 1 or 2) and no dive of its own, the two dives the
	-- fight's own events (fight: tempo.diveHit, the damage of one dive in the state)
	local stuck = seg and seg.hawks ~= nil
	if stuck then
		if not (hawksOn and p.noShots and (seg.hawks == 0 or seg.hawks == 1 or seg.hawks == 2)) then
			error("HunterGearAdvisor: a state's hawks (" .. tostring(seg.hawks) .. ") out of the HHA sequence with no bow, gun or crossbow", 2)
		end
		diveRate = 0
		tempo.hawkUptime = seg.hawks / 2
		tempo.hawkWait, tempo.hhaCycle = nil, nil
	end
	local hawkUp = tempo and tempo.hawkUptime or CONST.hawkUptime
	local fer = 0.02 * T("ferocity")                                  -- Ferocity +2%/rank crit pet and hawks
	if hawksOn then
		-- the dive is the hunter's spell (not a shot: no Mortal Shots). Hawks are guardians, not the
		-- pet (Lone Wolf does not need them gone); they take the hunter's all-school damage
		-- multiplier when summoned, so Focused Fire and Lone Wolf reach them alike (wowsims
		-- summon_hawk.go + parse_effects_table.go; not checked in game), Improved Tracking (a
		-- versus-creature-type modifier) does not. Targets dodge them; they glance. Ranged Weapon
		-- Specialization reaches the dive only with a bow, gun or crossbow worn (SpellEquippedItems 179969, above).
		local diveRws = shoots and rws or 1
		-- the dive's base: its rank's, with the flat damage of Unleashed Fury (3 a rank) and Ferocity (2 a rank) added
		-- (raid-mode W1 design section 5): each talent's A_ADD_FLAT_MODIFIER misc 3 (SPELLMOD_EFFECT1) on a class mask that
		-- holds the dive's (DB2 SpellEffect 697146 / 697447: mask 0x2000000 / 0 / 8192 / 0 and 0x40000000 / 0 / 8192 / 0; the
		-- dive's SpellClassOptions 83475: 0 / 0 / 8192 / 0), which wowsims parses onto the hunter's spells as BonusBaseDamage
		-- (sim/hunter/talents_beast_mastery.go:57-84; spelldata/parse_effects_table.go:660-662, 721-728; spell_mod.go:1300-1302;
		-- the rank curves 3 / 6 / 9 / 12 / 15 and 2 / 4 / 6 / 8 / 10, spells_auto_gen.go:39928-39929) and adds to the base
		-- before the attacker's multipliers, the armor and the outcome (spell_result.go:445-463). Every rank of the dive
		-- carries the class mask (approximation B4: wowsims registers the top rank alone)
		local diveBase = Model.Rank("hawkDive", lvl) + 3 * T("unleashedFury") + 2 * T("ferocity")
		out.dive = (diveBase + 0.05 * rapShot) * diveRate * (1 + critR) * phys * own * diveRws + gift * diveRate * (1 + critR)
		if stuck then tempo.diveHit = (diveBase + 0.05 * rapShot) * (1 + critR) * phys * own * diveRws + gift * (1 + critR) end
		-- hawk AP: 80% of the owner's RAP + 7 + 14 per point of the ranged WEAPON's DPS. EV-0073's
		-- rule reads the bow's own DPS (390 for a 27.32 DPS bow; a second hunter fits it to within
		-- 2); with ammo it would be about 570. wowsims' code adds the ammo, its evidence does not.
		-- It reads p.bowDPS with no shot condition: a worn thrown weapon's DPS (bowDPS with noShots, Player.WeaponInputs)
		-- raises the hawks' AP with no shot cast, as wowsims sim/hunter/summon_hawk.go hawkWeaponAP takes the DPS of the
		-- ranged slot's weapon (AutoAttacks.Ranged(), from sim/core/character.go GetRangedWeapon: the ranged slot's item
		-- but an idol, libram, totem or sigil); EV-0073 measures the rule with bows, a thrown weapon is unmeasured.
		local hawkAP = 0.8 * (p.rap + 7 + 14 * p.bowDPS)
		-- the hawks' crit: half the pet's before Ferocity, and Ferocity whole (sim/hunter/summon_hawk.go:83;
		-- talents_beast_mastery.go:71-84), all of it aura crit on their own table at bonus 0 (suppressed above)
		local hawkCrit = suppressed(0.5 * petCritBase + fer, 0, 0)
		-- The hawks take the owner's expertise against the mob's dodge, as the pet does: wowsims
		-- sim/hunter/summon_hawk.go:85 StatInheritance gives them ExpertisePercent = the owner's (summon_hawk.go:67: their
		-- melee hit and expertise are the tamed pet's; docs/research/R1-forever-ruleset.md section 2.4,
		-- R2-pet-scaling.md section 4, V1-verify-forever-pet.md section 4). Unmeasured: EV-0074 measures the hawks' hit
		-- alone (with 1% more hit, 1 miss in 32 swings against none in 515, at a target 8 levels below), and states
		-- that its commits record no count for the expertise.
		local hawkDodge = math.max(0, avoid - p.expertise / 100)
		local hawkRoll = white(missPH, hawkDodge, 0, hawkCrit, glanceChance, glanceAvg)
		out.hawks = 2 * hawkUp * (0.185 * creatureDPS + hawkAP / 60) * hawkSpeed * hawkRoll * petPhys
			* (uf * ff * lone / CONST.hawkFitMult) + gift * 2 * hawkUp * hawkSpeed / CONST.hawkSwing * hawkRoll
	else
		out.dive, out.hawks = 0, 0
	end

	if hasPet then
		-- the pet's crit with Ferocity, all of it aura crit on its own table at bonus 0 (suppressed above): its white swings,
		-- Claw and Bite, and Frenzy's chance
		local petCrit = suppressed(petCritBase + fer, 0, 0)
		-- expertise lowers the mob's dodge and its parry, each floored at 0 (wowsims sim/core/unit.go:1175-1196); the mob
		-- parries the pet while it faces it (Model.PetTanks: the levelling mode's tanking pet; behind the raid boss none),
		-- Model.PetParry
		local petDodge = math.max(0, avoid - p.expertise / 100)
		local petParry = Model.PetTanks(p.mode) > 0 and math.max(0, Model.PetParry(mobDiff) / 100 - p.expertise / 100) or 0
		-- Claw / Bite: 10 focus a second, +10%/rank with Bestial Discipline (EV-0072); Bite on its
		-- 10 s cooldown, the rest of the focus on Claw, for the abilities the family learns
		local fam = Model.PET_FAMILY[p.petFamily] or Model.PET_FAMILY_UNKNOWN
		local focus10 = 100 * (1 + 0.10 * T("bestialDiscipline"))
		local special10, casts10 = 0, 0                                     -- damage and casts per 10 s
		if fam.bite then special10 = Model.Rank("petBite", lvl); casts10 = 1; focus10 = focus10 - 35 end
		if fam.claw then
			special10 = special10 + focus10 / 25 * Model.Rank("petClaw", lvl)
			casts10 = casts10 + focus10 / 25
		end
		local petSpecial = special10 / 10
		-- Frenzy: 20%/rank on a pet crit (talent 19621: SPELLMOD_CHANCE_OF_SUCCESS +20 on SpellClassMask
		-- 0x80000000, the pet's proc aura 20784). 20784 procs on melee swings and melee abilities
		-- (SpellAuraOptions ProcTypeMask 0x11154), so Claw and Bite crits count. It casts 19615:
		-- +30% melee haste on the pet (A_MOD_MELEE_HASTE_3 30) for 8 s
		-- (DurationIndex 31 = 8000 ms). Its uptime is the chance of a crit among the pet's attacks of
		-- the last 8 s: the white swings and the Claw / Bite casts. The swings come at the pet's own swing
		-- time sped up by the owner's speeds it inherits, the same petInherit (haste x attackSpeed x meleeHaste x
		-- (1 + rf)) petHaste puts on its white damage (p.petSwing leaves those speeds out), and are
		-- counted at Frenzy's +30% (x1.3:
		-- a Frenzy that is up refreshes itself at the hasted rate; at a low uptime this counts too many
		-- swings, an estimate). A faster swing (Faster Attack) hits for
		-- less at the same DPS (normalized: wowsims pets.go applyAttackSpeed; EV-0071's Cat swings at
		-- 1.2 s for the 2 s swing scaled by the swing time), so the swing time changes the crit
		-- chances, not petWhite.
		if p.petSwing ~= nil and not (p.petSwing > 0) then
			error("HunterGearAdvisor: pet swing time must be positive, got " .. tostring(p.petSwing), 3)
		end
		local attacks8s = 8 / (p.petSwing or Model.PET_BASE_SWING) * petInherit * 1.3 + casts10 * 0.8
		local frenzyUp = 1 - (1 - 0.2 * T("frenzy") * petCrit) ^ attacks8s
		local petHaste = (1 + 0.3 * frenzyUp) * petInherit                  -- Rapid Fire's melee part reaches the pet
		local petRoll = white(missPH, petDodge, petParry, petCrit, glanceChance, glanceAvg)
		-- the pet's attack power: 10% of the higher of the owner's attack powers (pets.go:126), taken at the summon and kept
		-- (pets.go:160-171 keepSummonStats): p.petRap and p.petMap, the owner's before a Use buff (Model fight; Model.Weights'
		-- Use weights), else p.rap and p.map
		local petAP = 0.10 * math.max(p.petRap or p.rap, p.petMap or p.map)
		local petWhite = (creatureDPS + petAP / 14) * petHaste * petRoll
		-- Unleashed Fury and the orc Command racial add up on the pet; the family's passive is a
		-- separate aura
		local passive = 1 + 0.03 * T("unleashedFury") + (p.orc == false and 0 or 0.05)
		-- Bestial Wrath (the talent): +50% pet damage for 18 s (CONST.bestialWrath*), levelling its average 18 / 120 x 0.50 =
		-- 0.075 (my arithmetic), a segment of the raid fight x1.50 inside its window and nothing outside (raid-mode design 6.1)
		local bw
		if seg then
			bw = seg.bw and 1 + CONST.bestialWrathDamage or 1
		else
			bw = T("bestialWrath") > 0 and 1 + CONST.bestialWrathDuration / CONST.bestialWrathCooldown * CONST.bestialWrathDamage or 1
		end
		local petMult = CONST.happy * passive * (1 + fam.pct / 100) * ff * bw
			* (loneWolf and 1 / 1.2 or 1)                                 -- Lone Wolf with a pet out (wowsims)
		local petSpecialRoll = (1 - missPH - petDodge - petParry) * (1 + petCrit)
		local petSpecialDmg = petSpecial * petSpecialRoll
		-- Gift of Arthas on the pet's hits: its white swings at petHaste over its own swing time, Claw and Bite at casts10 a
		-- 10 s (the pet's swings are normalized, so the swing time sets the hits, not petWhite)
		local petGift = gift * (petHaste / (p.petSwing or Model.PET_BASE_SWING) * petRoll + casts10 / 10 * petSpecialRoll)
		out.pet = (petWhite + petSpecialDmg) * petMult * petPhys + petGift
	else
		out.pet = 0
	end

	out.melee, out.trap = 0, 0
	-- the hunter's landed hits per wall-clock second (Model.LandedHits): the main hand's white swings, its specials (Raptor
	-- Strike, Strider Kick, Mongoose Bite, Wing Clip), the off hand's swings, the Auto Shots and the ranged specials
	local mhSwings, mhSpecials, ohSwings = 0, 0, 0
	local rangedSwings = autoRate * shotHitf
	local rangedSpecials = (aimedRate + multiRate + arcRate + sniperRate) * shotHitf + diveRate
	local weaveInfo
	if weave then
		weaveInfo = weaveParts(p, T, {
			lvl = lvl, phys = phys, own = own, rws = rws, rcrit = rcrit, white = white, suppressed = suppressed,
			agiCrit = agiCrit, meleeCrit = meleeCrit, shotHitf = shotHitf,
			mapOwn = mapOwn, rapShot = rapShot, flat = flat, w = w, s = s, haste = haste, meleeSpeed = meleeSpeed,
				rangedSpeed = rangedSpeed, qsChance = qsChance, rfUp = rfUp, serpentCastRate = serpentCastRate,
			serpentLanded = serpentCasts, serpentRaid = seg and lvl >= 4 and { q = 1 - shotHitf } or nil, coe = coe, gift = gift,
			critR = critR, shares = seg and seg.shares,
		})
		local avg = weaveInfo.average
		if seg then
			-- the raid fight's Serpent Sting from the weave's range looks (weaveParts: its landed applications a second)
			serpentCasts = avg.rates.serpentLanded
			out.serpent = perSting * serpentCasts
		end
		out.auto, out.arcane, out.multi = avg.auto, avg.arcane, avg.multi
		out.melee, out.trap = avg.melee, avg.trap
		mhSwings, mhSpecials, ohSwings = avg.mhSwings, avg.mhSpecials, avg.ohSwings
		rangedSwings, rangedSpecials = avg.rangedSwings, avg.rangedSpecials
	end
	local hits = {
		mh = { swings = mhSwings, specials = mhSpecials, speed = p.mhSpeed },
		oh = { swings = ohSwings, specials = 0, speed = p.ohSpeed },
		ranged = { swings = rangedSwings, specials = rangedSpecials, casts = serpentCasts,
			speed = p.bowDPS > 0 and s or 0 },
	}
	-- the raid fight's casts (the mana spend, Judgement of Wisdom's landed hits, Resourcefulness' ability crits): the
	-- weave's by action (weaveParts), else each cast the turret's rotation holds, at its rate (0 where the starved regime buys
	-- none of it): Summon Hawk's casts are its dives, which always land and crit at critR (OutcomeRangedCritOnly); Arcane,
	-- Aimed, Sniper and Multi-Shot land with shotHitf and crit at critR; Serpent Sting's casts are the tempo's (a miss costs a
	-- cast) and its landed applications serpentCasts
	local casts
	if seg then
		local acts
		if weave then
			acts = weaveInfo.average.acts
		else
			acts = {}
			if hawksOn then acts.hawk = { casts = diveRate, landed = diveRate, crit = critR } end
			if lvl >= 6 and turret then acts.arcane = { casts = arcRate, landed = arcRate * shotHitf, crit = critR } end
			if lvl >= 20 and turret then acts.aimed = { casts = aimedRate, landed = aimedRate * shotHitf, crit = critR } end
			if lvl >= 40 and T("sniperShot") > 0 and turret then
				acts.sniper = { casts = sniperRate, landed = sniperRate * shotHitf, crit = critR }
			end
			if lvl >= 18 and lvl < 20 and turret then acts.multi = { casts = multiRate, landed = multiRate * shotHitf, crit = critR } end
			if lvl >= 4 and shoots then acts.serpent = { casts = tempo.serpentCasts, landed = serpentCasts } end
		end
		casts = { acts = acts, free = mhSwings + ohSwings + rangedSwings }
	end
	return out, hits, weaveInfo, tempo, casts
end

local function copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

-- The one map from item stat keys to model inputs (Model.ApplyStats), which every stat mutation of Model.Weights goes
-- through, so a stat key means one thing everywhere:
-- - the four attributes AGI, STR, INT and SPI count at the live sheet's stat multiplier of each (p.statMult: Greater
--   Blessing of Kings, Spirit of Zandalar and the like, Player.ReadStats; the user's answer O8 = (a), raid-mode design
--   4.8, 24.3): wowsims multiplies a stat by every aura of A_MOD_TOTAL_STAT_PERCENTAGE and A_MOD_PERCENT_STAT on it,
--   whatever adds the stat (sim/core/spelldata/parse_effects_table.go:807-813, 1149-1170 MultiplyStat;
--   sim/core/stats/deps.go:156-169, 232-237 multiplies the factors of one stat, 279-283 applies them to the stat's
--   whole), an item's and a Use buff's alike;
-- - AP: the melee and the ranged attack power (rap, map); RAP: rap; MAP: map; STR: map at the Strength multiplier (a
--   hunter's Strength is melee attack power alone);
-- - AGI: e = the amount x (1 + 0.03 x the Lightning Reflexes rank) x the Agility multiplier effective Agility (Lightning
--   Reflexes +3% Agility a rank, a factor wowsims multiplies with the others), which gives 2e RAP, e melee attack power,
--   e x the level's crit per Agility (Model.CritPerAgility) of ranged and melee crit, and e to p.agi, so that crit stays
--   Agility crit, out of the aura crit the crit suppression takes (Model.Parts);
-- - CRIT: the ranged and the melee crit alike; CRIT_RANGED (a crit scope's crit, SpellItemEnchantment 8720, ranged
--   weapons only): p.crit alone, melee crit held; SPELL_CRIT: p.spellCrit (Immolation Trap's ticks in the Survival weave);
-- - HASTE, ATTACK_SPEED, HASTE_RATING, MELEE_HASTE, RANGED_HASTE: one more source of the input (p.haste, p.attackSpeed,
--   p.hasteRating, p.meleeHaste, p.rangedHaste), which multiplies the input's speed multiplier by 1 + the amount / 100
--   (Player wornHaste: each aura multiplies the speed, wowsims sim/core/unit.go Multiply*Speed; Model.Weights states the
--   sums Score prices against it);
-- - INT (at the Intellect multiplier): Careful Aim, attack power and ranged attack power of 20% a rank of Intellect
--   (auras 580 + 598; wowsims sim/hunter/talents_marksmanship.go:73-83, a dependency on the multiplied Intellect); in raid
--   mode also 15 mana of the pool a point (p.manaMax: wowsims
--   sim/core/mana.go:59-71 AddStatDependency(Intellect, Mana, 15); the Forever UI's MANA_PER_INTELLECT = 15,
--   Camelot/PaperDollFrameConstants.lua:25-26);
-- - the raid mode's mana stats (raid-mode design 6.8, 7.3): SPI (at the Spirit multiplier), p.spirit, and the hunter's
--   Spirit regen 6.25 + Spirit / 8
--   mana a second (mana.go:77-78) in p.regenRest whole and in p.regenCast at the live sheet's casting share, Bestial
--   Discipline's 25% a rank (its effect 2 A_MOD_MANA_REGEN_INTERRUPT, sim/hunter/talents_beast_mastery.go:174-182; its 50%
--   at the top rank under wowsims' cap of all of it, mana.go:182-186): the shares that come in combat (Rapid
--   Recuperation, Resourcefulness) the raid fight adds itself from p.spirit, as the reading cannot hold them; MP5, a fifth
--   of it a second in both regens (mana.go:166-169);
--   MANA, p.manaMax;
-- - AP_VS_<TYPE> (Model.CREATURE_TYPES): attack power against that creature type, p.apVsTarget at the mode's share of
--   that type (Model.TargetShare);
-- - ARMOR_PEN: flat armor penetration, p.armorPen (raid mode reads it against the boss's armor, Model.BossArmor);
-- - HIT, SPELL_HIT, EXPERTISE: not applied here, Score prices each with its cap on the whole set (SPELL_HIT up to
--   Model.TrapHitCap);
-- - the survival and tank stats (STA, ARMOR, HEALTH, HP5, DEFENSE, DODGE, PARRY, BLOCK) and SPELL_POWER, and in levelling
--   mode the mana stats (SPI, MP5, MANA): no damage input reads them (Model.Weights prices them at 0; Score.Secondary
--   compares the survival and, while levelling, the mana after damage), so a Use buff's Stamina (Golden Banana 270226,
--   Game/UseData.lua) is not applied.
-- Any other key is an error: no input reads it.
local AP_VS_KEY = {}
for _, t in ipairs(Model.CREATURE_TYPES) do AP_VS_KEY["AP_VS_" .. t] = t end
local NOT_APPLIED = { HIT = true, SPELL_HIT = true, EXPERTISE = true, STA = true, ARMOR = true, HEALTH = true, HP5 = true,
	DEFENSE = true, DODGE = true, PARRY = true, BLOCK = true, SPELL_POWER = true }
local MANA_KEYS = { SPI = true, MP5 = true, MANA = true }
local function oneMoreSource(q, key, amount)
	q[key] = ((1 + q[key] / 100) * (1 + amount / 100) - 1) * 100
end
-- the live sheet's stat multiplier of one attribute (p.statMult, checkStatMult): an error where the point has none
local function statMultOf(q, key)
	local m = q.statMult
	if type(m) ~= "table" or type(m[key]) ~= "number" then
		error("HunterGearAdvisor: Model.ApplyStats: p.statMult." .. key .. " missing: " .. tostring(type(m) == "table" and m[key] or m), 4)
	end
	return m[key]
end
local function applyStats(q, stats, T)
	for k, a in pairs(stats) do
		if k == "AP" then
			q.rap, q.map = q.rap + a, q.map + a
		elseif k == "RAP" then
			q.rap = q.rap + a
		elseif k == "MAP" then
			q.map = q.map + a
		elseif k == "STR" then
			q.map = q.map + a * statMultOf(q, "STR")
		elseif k == "AGI" then
			local e = a * (1 + 0.03 * T("lightningReflexes")) * statMultOf(q, "AGI")
			local c = Model.CritPerAgility(q.level) * e
			q.rap, q.map, q.agi = q.rap + 2 * e, q.map + e, q.agi + e
			q.crit, q.meleeCrit = q.crit + c, q.meleeCrit + c
		elseif k == "CRIT" then
			q.crit, q.meleeCrit = q.crit + a, q.meleeCrit + a
		elseif k == "CRIT_RANGED" then
			q.crit = q.crit + a
		elseif k == "SPELL_CRIT" then
			q.spellCrit = q.spellCrit + a
		elseif k == "HASTE" then
			oneMoreSource(q, "haste", a)
		elseif k == "ATTACK_SPEED" then
			oneMoreSource(q, "attackSpeed", a)
		elseif k == "HASTE_RATING" then
			oneMoreSource(q, "hasteRating", a)
		elseif k == "MELEE_HASTE" then
			oneMoreSource(q, "meleeHaste", a)
		elseif k == "RANGED_HASTE" then
			oneMoreSource(q, "rangedHaste", a)
		elseif k == "INT" then
			local int = a * statMultOf(q, "INT")
			local ap = 0.20 * T("carefulAim") * int
			q.rap, q.map = q.rap + ap, q.map + ap
			if q.mode == "raid" then q.manaMax = q.manaMax + 15 * int end
		elseif MANA_KEYS[k] then
			if q.mode == "raid" then
				if k == "SPI" then
					local spi = a * statMultOf(q, "SPI")
					q.spirit = q.spirit + spi
					q.regenRest = q.regenRest + spi / 8
					q.regenCast = q.regenCast + 0.25 * T("bestialDiscipline") * spi / 8
				elseif k == "MP5" then
					q.regenRest, q.regenCast = q.regenRest + a / 5, q.regenCast + a / 5
				else
					q.manaMax = q.manaMax + a
				end
			end
		elseif AP_VS_KEY[k] then
			q.apVsTarget = q.apVsTarget + a * Model.TargetShare(AP_VS_KEY[k], q.mode)
		elseif k == "ARMOR_PEN" then
			q.armorPen = q.armorPen + a
		elseif not NOT_APPLIED[k] then
			error("HunterGearAdvisor: Model.ApplyStats: no model input takes the stat " .. tostring(k), 3)
		end
	end
end
-- Applies the item stats `stats` ({ key = amount }) to the model inputs q in place (applyStats above); q.tal gives the
-- talent ranks it reads.
function Model.ApplyStats(q, stats)
	applyStats(q, stats, talents(q))
end
-- The item stat keys applyStats moves an input by in raid mode, the stats the raid fight reads: Score.SetValue takes a set's
-- amounts of them less the worn set's for the change of the fight's events (Advisor ctx.eventGain, raid-mode design 25.1)
Model.FIGHT_KEYS = { AP = true, RAP = true, MAP = true, STR = true, AGI = true, CRIT = true, CRIT_RANGED = true, SPELL_CRIT = true,
	HASTE = true, ATTACK_SPEED = true, HASTE_RATING = true, MELEE_HASTE = true, RANGED_HASTE = true, INT = true, SPI = true,
	MP5 = true, MANA = true, ARMOR_PEN = true }
for k in pairs(AP_VS_KEY) do Model.FIGHT_KEYS[k] = true end
-- The keys of Model.FIGHT_KEYS whose inputs the raid fight's mana reads at p's talents, so the only ones by which a set's
-- stats move the fight's consumables' events (raid-mode design 26.3): the pool (INT's 15 mana a point, MANA), the regens
-- (SPI, MP5), the casts and the landed hits (the attack speeds: each cast's rate and Judgement of Wisdom's landed hits,
-- manaFlow) and, with Resourcefulness, the crit (AGI's, CRIT, CRIT_RANGED: its buff's uptime in the casting regen,
-- castingRegen; without the talent the mana reads no crit). The others move the damage alone: the attack powers (AP, RAP,
-- MAP, STR, AP_VS_<TYPE>), the armor penetration and SPELL_CRIT (Immolation Trap's ticks; the trap's cast rolls no crit
-- of Resourcefulness, partsAndHits casts). Advisor ctx.eventGain runs no fight for stats that hold none of them. Raid
-- mode alone.
local EVENT_KEYS = { HASTE = true, ATTACK_SPEED = true, HASTE_RATING = true, MELEE_HASTE = true, RANGED_HASTE = true, INT = true,
	SPI = true, MP5 = true, MANA = true }
local CRIT_EVENT_KEYS = { AGI = true, CRIT = true, CRIT_RANGED = true }
function Model.EventKeys(p)
	if p.mode ~= "raid" then error("HunterGearAdvisor: Model.EventKeys of a point not in raid mode: " .. tostring(p.mode), 2) end
	local out = {}
	for k in pairs(EVENT_KEYS) do out[k] = true end
	if talents(p)("resourcefulness") > 0 then
		for k in pairs(CRIT_EVENT_KEYS) do out[k] = true end
	end
	return out
end

-- The raid fight's time weight (raid-mode design 6.2): wowsims draws the fight's length uniformly in 180 +- 5 s
-- (CONST.raid fight, fightVariation), so an instant t counts with the share of fights still running at it, w(t) = 1 below
-- 175 s, (185 - t) / 10 from 175 to 185 s and 0 after. fightIntegral(t) is its integral from 0 to t (my arithmetic): t up to
-- 175 s, 175 + x - x^2 / 20 at x = t - 175 up to 185 s, then 180, the mean length. The fight's damage a second is the sum over
-- its segments of each one's damage a second x its integral of w, over 180: E[damage] / E[length] (approximation A7), in
-- which an event near the end fades out continuously.
local function fightIntegral(t)
	local r = CONST.raid
	local lo, hi = r.fight - r.fightVariation, r.fight + r.fightVariation
	if t <= lo then return t end
	if t >= hi then return r.fight end
	local x = t - lo
	return lo + x - x * x / (2 * (hi - lo))
end
Model.FightIntegral = fightIntegral

-- The windows [t, t + duration) of a cooldown cast at first and again each time it is ready, while a cast comes before
-- the fight's last instant (185 s: a later window weighs nothing)
local function cooldownWindows(first, duration, cooldown)
	local out, hi = {}, CONST.raid.fight + CONST.raid.fightVariation
	local t = first
	while t < hi do
		out[#out + 1] = { t, t + duration }
		t = t + cooldown
	end
	return out
end

-- The burst trinket category (SpellCategory 1141 "Item - Burst Trinket", Game/UseData.lua category): a buff of it locks the
-- other buffs of it for its own duration (Score.SetValue's rule; tools/gen_use_data.py)
Model.BURST_CATEGORY = 1141

-- The Use buffs' windows in the raid fight (raid-mode design 6.3, 6.8): each buff of uses (in their order, Score.SetUses:
-- wowsims' registration order, the legs before trinket 13 and 14) fires at 5 s (CONST.raid.cooldownsFrom) and again
-- whenever its cooldown is over; a buff of the burst category locks the other burst buffs for its own duration, so a
-- second burst buff fires when the first ends. At one instant the buffs fire in their order: wowsims fires the ready
-- cooldowns by ready time, then priority, then the order of its list, which a stable sort keeps from the registration
-- (sim/core/major_cooldown.go:369-420). At a later tie its list holds the order its re-sorts by ready time left; two burst
-- buffs tie again only where one's cooldown is the other's duration and cooldown, which no pair of Game/UseData.lua has
-- (my arithmetic; approximation A5). uses: a list of { spell, stats, duration, cooldown, category } (Game/UseData.lua
-- entries; category nil for a buff of no shared category). Returns windows[i] = { { t0, t1 }, ... } for uses[i].
local function useWindows(uses)
	local r = CONST.raid
	local hi = r.fight + r.fightVariation
	local ready, wins = {}, {}
	for i, u in ipairs(uses) do
		if type(u) ~= "table" or type(u.stats) ~= "table" or type(u.spell) ~= "number" or not (type(u.duration) == "number" and u.duration > 0)
			or not (type(u.cooldown) == "number" and u.cooldown >= u.duration) then
			error("HunterGearAdvisor: a Use buff of the raid fight is not { spell, stats, duration, cooldown >= duration }: use " .. i, 3)
		end
		ready[i], wins[i] = r.cooldownsFrom, {}
	end
	local lockUntil = -math.huge
	local t = r.cooldownsFrom
	while t < hi do
		for i, u in ipairs(uses) do
			local burst = u.category == Model.BURST_CATEGORY
			if ready[i] <= t and (not burst or lockUntil <= t) then
				wins[i][#wins[i] + 1] = { t, t + u.duration }
				ready[i] = t + u.cooldown
				if burst then lockUntil = t + u.duration end
			end
		end
		local nextT = math.huge
		for i, u in ipairs(uses) do
			local at = ready[i]
			if u.category == Model.BURST_CATEGORY then at = math.max(at, lockUntil) end
			if at > t and at < nextT then nextT = at end
		end
		t = nextT
	end
	return wins
end

-- The share of the raid fight a buff's windows cover, weighted by the fight's time weight: the sum of their integrals of
-- w (fightIntegral, each window cut at the fight's end) over 180
local function fightShare(windows)
	local sum = 0
	for _, w in ipairs(windows) do sum = sum + fightIntegral(w[2]) - fightIntegral(w[1]) end
	return sum / CONST.raid.fight
end

-- The Use buffs' share of the raid fight (ctx.useUptime: the uptime at which Score prices a Use buff's hit, spell hit and
-- expertise against their caps; the tooltip): { [spell] = share } of uses (useWindows' list)
function Model.UseUptimes(uses)
	local out = {}
	for i, w in ipairs(useWindows(uses)) do out[uses[i].spell] = fightShare(w) end
	return out
end

-- The casting regen of a state of the raid fight (raid-mode design 7.3): q.regenCast, the live casting regen with Bestial
-- Discipline's share in it, plus the shares that come in combat, which the live reading cannot hold: min(1 - 0.25 x
-- Bestial Discipline, 0.25 x Rapid Recuperation x U + 0.50 x resUp) x (6.25 + q.spirit / 8) (wowsims caps the shares at the
-- whole, sim/core/mana.go:185-189), U Serpent Sting's uptime, 15 s x its landed applications a second, and resUp
-- Resourcefulness' buff uptime, the chance that one of the last 30 s of landed ability hits triggered it, 1 - the product
-- over the casts that roll an ability crit of (1 - 0.5 x the rank x crit)^(30 x landed) (crits as independent events,
-- approximation A15; Frenzy's form, partsAndHits frenzyUp). acts: partsAndHits' casts by action; shareOf(action): the share
-- of its rate the state casts (1 for a pass's own casts; the starved regime's, fight). Returns rc, U, resUp.
local function castingRegen(q, T, acts, shareOf)
	local mn = CONST.mana
	local res = T("resourcefulness")
	local noBuff = 1
	for name, a in pairs(acts) do
		if a.crit then
			noBuff = noBuff * (1 - mn.resourcefulnessChance * res * a.crit) ^ (mn.resourcefulnessDuration * a.landed * shareOf(name))
		end
	end
	local resUp = 1 - noBuff
	local U = acts.serpent and CONST.serpentDuration * acts.serpent.landed * shareOf("serpent") or 0
	local share = math.min(1 - mn.disciplineShare * T("bestialDiscipline"),
		mn.recuperationShare * T("rapidRecuperation") * U + mn.resourcefulnessShare * resUp)
	return q.regenCast + share * (mn.spiritBase + mn.spiritPer * q.spirit), U, resUp
end
local function wholeShare() return 1 end

-- The mana flow of a pass of the raid fight (raid-mode design 7.3, 7.5; O7 = (a)), from its casts (partsAndHits) at q,
-- costs manaCosts': S, the mana it spends a second (each cast at its cost, a missed one too); J, Judgement of Wisdom's
-- income, 59 x 50% = 29.5 mana a landed hit of the hunter's (every cast's landed hits, Serpent Sting's and Immolation
-- Trap's applications among them, and the free ones: the Auto Shots and the white swings; CONST.mana jowMana); rc, U and
-- resUp, the casting regen with the shares that come in combat (castingRegen); and D = S - rc - J, the net drain of the
-- rich regime (7.5).
local function manaFlow(q, T, casts, costs)
	local mn = CONST.mana
	local S, landed = 0, casts.free
	for name, a in pairs(casts.acts) do
		local cost = costs[name]
		if cost == nil then error("HunterGearAdvisor: a cast of the raid fight without a mana cost: " .. tostring(name), 2) end
		S = S + a.casts * cost
		landed = landed + a.landed
	end
	local rc, U, resUp = castingRegen(q, T, casts.acts, wholeShare)
	local J = mn.jowMana * mn.jowChance * landed
	return { S = S, J = J, rc = rc, U = U, resUp = resUp, D = S - rc - J, landed = landed }
end

-- The casts the starved regime buys (raid-mode design 7.5), each a group of partsAndHits' casts that takes one share, and the
-- row of its rotation, which decides between two casts of one cost (the order of the list decides between two actions both
-- ready and affordable at one look): the build that shoots from range, apls/turret_hawk.apl.siml:14-19 (Serpent Sting, the
-- HHA sequence of Summon Hawk and Arcane Shot or Arcane Shot alone, Aimed Shot; Sniper Shot, of the MM rotation
-- turret.apl.siml, after them), the Survival weave apls/default.apl.siml:20-30 (Raptor Strike, Strider Kick, Mongoose Bite,
-- Immolation Trap, Wing Clip, Serpent Sting, Arcane Shot, Multi-Shot)
local STARVED_ITEMS = {
	turret = {
		{ name = "serpent", acts = { "serpent" }, row = 14 }, { name = "hha", acts = { "hawk", "arcane" }, row = 15 },
		{ name = "aimed", acts = { "aimed" }, row = 19 }, { name = "sniper", acts = { "sniper" }, row = 20 },
	},
	weave = {
		{ name = "raptor", acts = { "raptor" }, row = 20 }, { name = "strider", acts = { "strider" }, row = 21 },
		{ name = "bite", acts = { "bite" }, row = 22 }, { name = "trap", acts = { "trap" }, row = 23 },
		{ name = "wingClip", acts = { "wingClip" }, row = 24 }, { name = "serpent", acts = { "serpent" }, row = 25 },
		{ name = "arcane", acts = { "arcane" }, row = 29 }, { name = "multi", acts = { "multi" }, row = 30 },
	},
}
-- The element of the starved income's cycle (raid-mode design 7.5, 15.5): the cast the hunter makes as soon as it can pay
-- it, the first of the list the state casts. The turret: an HHA element (Summon Hawk or Arcane Shot, one cost), Arcane Shot
-- alone without hawks. The weave: the cheapest cast it can make at any melee look, Wing Clip with a melee weapon, else
-- Mongoose Bite while Expose Prey opens windows, else Strider Kick; Arcane Shot after them (a weave without any of the
-- three: the design names none, the range look's always-ready shot)
local STARVED_ELEMENT = { turret = { "hha" }, weave = { "wingClip", "bite", "strider", "arcane" } }

-- The raid fight at p (raid-mode design 6, 7): the time from 0 to 185 s walked with the mana (7.6), each stretch of one
-- state a segment, partsAndHits once a state.
-- The windows: Rapid Fire 15 s from 5 s every 300 - 60 x Rapid Killing s (one before 185 s at every rank); Bestial Wrath
-- (the talent, the pet out: its spell is the pet's, sim/hunter/talents_beast_mastery.go:114-125) 18 s from 5 s and again
-- 120 s later if the mana allows (below); the Use buffs' of p.uses (useWindows; nil: none), applied to a copy of p
-- (Model.ApplyStats, applyStats) but for the pet's attack power: the pet keeps the attack power it had at the summon
-- (wowsims sim/hunter/pets.go:160-171 keepSummonStats, EV-0072; its crit, hit and expertise follow the owner,
-- pets.go:121-137), so p.petRap and p.petMap hold the point's rap and map; the hawks follow the owner (summon_hawk.go:79-89).
-- The mana (raid-mode design 7.5-7.6): the fight starts with the pool full, p.manaMax (7.1); the ceiling of a state is its
-- copy's manaMax (an Intellect or mana Use buff raises it for its window and leaves the mana as it is; at the window's end
-- the mana is held at the lower ceiling, the next regen gain capped there: wowsims sim/core/mana.go:100-125, 116; my
-- reading). Two regimes (approximation A2, fluid):
-- - rich: every cast at its rate, the mana moving at -D (manaFlow), held at the ceiling where D < 0 (casts fully paid);
--   the mana at 0 (D > 0) turns it starved;
-- - starved (the mana at 0): the income I buys the casts cheapest ready first (wowsims' APL takes the first action of its
--   list that is ready and affordable, apl.go:617-631, spell.go:748-776: with mana rising from 0 the cheapest ready one
--   goes first; my reading, 7.5), each item of STARVED_ITEMS at min(1, what is left / its whole net spend), the net spend
--   of its casts at their costs less Judgement of Wisdom's 29.5 a landed hit of its own (a cast returns its own; one that
--   returns more than it costs is bought whole); I from the cycle of one element (STARVED_ELEMENT) bought as soon as it can
--   be paid, its net cost c a cast: the casting regen g1 = rc + J_a for the five-second rule's 5 s after a spend (wowsims
--   mana.go:403-411) and g2 = q.regenRest + J_a after it, J_a = 29.5 x the free landed hits at the state's shares (the
--   Auto Shots and white swings, which go on: in the weave each Raptor Strike not bought leaves its main-hand swing white,
--   partsAndHits casts' white), so I = g1 if c <= 5 g1, else c / (5 + (c - 5 g1) / g2); rc the state's casting regen at
--   its shares (castingRegen). The shares and I set each other: I solves I = F(I), F(I) the income at the shares I buys,
--   continuous in I; its largest root, the limit of the iteration from the rich rc where the shares raise F (Rapid
--   Recuperation's and Resourcefulness' shares can raise it faster than I and so make three roots: the high one keeps the
--   casts that pay their regen). Found at the points where a share turns and where the in-combat share bought reaches its
--   cap (castingRegen; between two such points one share moves linearly with I): the topmost point at which F(I) >= I and
--   the next above it bracket the root, taken as the one root between them, found there by the Illinois method to 1e-12 of
--   I mana a second (none in 100 steps is an error). My method; raid-mode design 20.5 names the probes that check it against
--   that iteration run to its end and look for two more roots between two points. The starved state casts each item at its
--   share (partsAndHits seg.shares); one that buys every cast at its rate stays starved with them all whole while its rich
--   D is above 0 (its casting cannot
--   both run whole and pause for the regen out of the five-second rule), and turns rich at a state whose rich D is 0 or
--   less (the mana rising from 0).
-- The costs at one instant (consumables before the cooldowns, 7.6; an MCD fires when it can be paid, major_cooldown.go:
-- 110-133): Rapid Fire 100 and Bestial Wrath 206 at 5 s, Hunter's Mark 60 at 98 s (its prepull cast at -22 s,
-- pull.apl.siml:8, lasts 120 s: SpellMisc 324400 DurationIndex 4; both rotations recast it when missing,
-- turret_hawk.apl.siml:13, default.apl.siml:19); a one-off cost is paid from the pool in the rich regime and its shortfall,
-- as every one-off cost in the starved regime, is a debt the income repays before any cast (7.6 item 2). The second
-- Bestial Wrath is ready at 125 s: rich with the mana for it, it fires at once; rich without it, when the mana rising at -D
-- reaches it (D < 0), else in the starved regime once the income bought it, after the cheaper casts and before the dearer
-- (its cost in the cheapest-first list; the dearer ones wait for it); none before 185 s, none.
-- The consumables (the user's answer O2 = (a), always on; 7.4, CONST.mana): the Major Frenzy Potion at 5 s, a buff of the
-- states as a Use buff's; at 125 s, the potions' shared category ready again, the Major Mana Potion (+1800) if its 2250 fits
-- under the ceiling after 5 s of the casting regen, else a second Frenzy Potion; the Demonic Rune (+1200) from 5 s whenever
-- its 1500 fits so, then 120 s later (the starved regime at 0 mana fits it at once where the ceiling holds it). A mana gain
-- repays a debt first and turns the regime rich.
-- Returns { segments = { { t0, t1, weight, state, m0, m1 } }, states = { { rf, bw, uses = { index into p.uses, then the
-- Frenzy Potion's }, regime, phase, shares, income, wrathRate, weight, out, hits, weave, tempo, casts, mana, rich (a starved
-- state's: the rich pass of its state, whose casts its shares scale) } }, rapidFire, bestialWrath, uses (the Use windows of
-- p.uses), useSpells (each buff's spell, p.uses' then the Frenzy Potion's), frenzyPotion (its windows), runes (the times the
-- rune is used), manaPotion (its time, nil where it does not fit), costs
-- (manaCosts), oom (the times the mana runs out), parts, hits, events (the consumables' events the fight took: manaPotion,
-- whether the mana potion fired at 125 s, and runes, the rune's times; the form p.events holds), deviated (p.events held a
-- decision the fight would have taken otherwise) }, parts and hits the weighted means a second: each state's at
-- its weight / 180 (the weights sum to 180). A state's phase: nil (rich), "debt" (the income repays a debt, no cast bought),
-- "wrath" (the second Bestial Wrath waits in the list), "buy".
local function fight(p)
	local T = talents(p)
	checkInputs(p, REQUIRED_NUMBERS, REQUIRED_FLAGS)
	checkMode(p)
	local r, mn = CONST.raid, CONST.mana
	local hi = r.fight + r.fightVariation
	local first = r.cooldownsFrom
	local costs = manaCosts(p, T)
	local jow = mn.jowMana * mn.jowChance
	local kind = p.survival and "weave" or "turret"
	-- The HHA sequence with no bow, gun or crossbow (raid-mode design 25.5): wowsims' sequence advances only past a step it
	-- casts and is ready only while its current step is (sim/core/apl_actions_sequences.go:63-87), and Arcane Shot, its third
	-- step, needs a bow, gun or crossbow (its SpellEquippedItems row: the cast's weapon requirement,
	-- sim/core/spelldata/resolve_spell.go:270-283, sim/core/equip_requirement.go:26-45), so after its two Summon Hawks it
	-- waits there for good: reset_sequence("HHA") wants it complete, and the preset's other Summon Hawk line wants Use Arcane
	-- Shot false (apls/turret_hawk.apl.siml:15-17). So the first hawk at 0 s, the second when the category's 6 s are over and
	-- the rotation looks (the tempo's wait delta_H with no other GCD action, the poll's 0.1317 s: approximation A1), each 18 s
	-- (CONST.hawkDuration); then no hawk and no dive. Their casts are one-off costs (Summon Hawk's, less the dive's own
	-- Judgement of Wisdom: the dive always lands), their dives the fight's own damage and landed hits. Levelling's averaged
	-- pass keeps its HHA cycle (HGA's levelling estimate).
	local hawkCasts = {}
	if kind == "turret" and p.noShots and p.level >= CONST.hawkLearnLevel and T("summonHawk") > 0 then
		local a, b = r.reactionMin, r.reactionMax
		hawkCasts = { 0, r.hawkCategory + (a * a + a * b + b * b) / 3 / (a + b) }
	end
	local stuckHawks = hawkCasts[1] ~= nil
	local function hawksUp(t)
		local n = 0
		for _, c in ipairs(hawkCasts) do
			if t >= c and t < c + CONST.hawkDuration then n = n + 1 end
		end
		return n
	end
	local rapid = cooldownWindows(first, CONST.rapidFireDuration,
		CONST.rapidFireCooldown - CONST.rapidKillingCut * T("rapidKilling"))
	local hasWrath = T("bestialWrath") > 0 and p.petOut
	local wrath = {}
	local uses = p.uses or {}
	local useWin = useWindows(uses)
	-- the buffs of the fight's states: the Use buffs of p.uses, then the Major Frenzy Potion (O2 = (a); CONST.mana): from 5 s,
	-- and at 125 s again when the mana potion does not fit then (below)
	local buffs, buffWin = {}, {}
	for i, u in ipairs(uses) do buffs[i], buffWin[i] = u, useWin[i] end
	local potion = #buffs + 1
	local frenzy = { { first, first + mn.frenzyPotion.duration } }
	buffs[potion], buffWin[potion] = mn.frenzyPotion, frenzy
	local cuts = {}
	local function cut(t) if t > 0 and t < hi then cuts[t] = true end end
	local function cutWindows(list) for _, w in ipairs(list) do cut(w[1]); cut(w[2]) end end
	cutWindows(rapid)
	for _, l in ipairs(buffWin) do cutWindows(l) end
	local function nextCut(t)
		local best = hi
		for c in pairs(cuts) do if c > t and c < best then best = c end end
		return best
	end
	local function inside(list, t)
		for _, w in ipairs(list) do
			if t >= w[1] and t < w[2] then return true end
		end
		return false
	end
	-- the rich pass of a state, once a state
	local passes = {}
	local function richPass(rf, bw, active, nh)
		local key = (rf and "r" or "-") .. (bw and "b" or "-") .. table.concat(active, ",") .. (nh and ("|h" .. nh) or "")
		local ps = passes[key]
		if ps then return ps end
		local q = p
		if #active > 0 then
			q = copy(p)
			if q.petRap == nil then q.petRap, q.petMap = p.rap, p.map end
			for _, k in ipairs(active) do applyStats(q, buffs[k].stats, T) end
		end
		local out, h, wv, tempo, casts = partsAndHits(q, { rf = rf, bw = bw, hawks = nh })
		ps = { key = key, q = q, rf = rf, bw = bw, hawks = nh, uses = active, regime = "rich", out = out, hits = h, weave = wv,
			tempo = tempo, casts = casts, mana = manaFlow(q, T, casts, costs) }
		passes[key] = ps
		return ps
	end
	-- the starved state of a rich pass in a phase, once each
	local starvedPasses = {}
	local function starvedOf(ps, phase)
		local key = ps.key .. "|" .. phase
		local sv = starvedPasses[key]
		if sv then return sv end
		local acts, q = ps.casts.acts, ps.q
		local items, itemOf = {}, {}
		for _, it in ipairs(STARVED_ITEMS[kind]) do
			local casts, spend, landed = 0, 0, 0
			for _, a in ipairs(it.acts) do
				itemOf[a] = it.name
				local x = acts[a]
				if x then casts, spend, landed = casts + x.casts, spend + x.casts * costs[a], landed + x.landed end
			end
			items[#items + 1] = { name = it.name, row = it.row, casts = casts, gross = casts > 0 and spend / casts or 0,
				full = spend - jow * landed }
		end
		for a, x in pairs(acts) do
			if x.casts > 0 and not itemOf[a] then error("HunterGearAdvisor: a cast the starved regime does not buy: " .. tostring(a), 2) end
		end
		local elem
		for _, name in ipairs(STARVED_ELEMENT[kind]) do
			for _, it in ipairs(items) do
				if not elem and it.name == name and it.casts > 0 then elem = it end
			end
		end
		-- a state with no cast at all (no bow, gun or crossbow: the stuck HHA sequence, 25.5) has no spend of its own, so its
		-- rich D is 0 or less and it starves only in a debt of one-off costs: the debt repays at the regen out of the
		-- five-second rule, nothing being cast (the one-off's own 5 s of casting regen left out: raid-mode design 25.5); any
		-- other starved phase of it is an error
		if not elem and phase ~= "debt" then error("HunterGearAdvisor: a starved state of the raid fight with no cast for its income's cycle", 2) end
		local cEff = elem and elem.full / elem.casts
		local order = {}
		for _, it in ipairs(items) do
			if it.casts > 0 then order[#order + 1] = it end
		end
		if phase == "wrath" then order[#order + 1] = { name = "bestialWrath", gross = costs.bestialWrath, row = 0, oneOff = true } end
		table.sort(order, function(a, b)
			if a.gross ~= b.gross then return a.gross < b.gross end
			return a.row < b.row
		end)
		-- the income at shares ({ [item] = share }): the casting regen at them, J_a of the free landed hits at them (the rich
		-- pass's and the white swing each cast not made leaves), the element's cycle; and the in-combat share of the Spirit
		-- regen before its cap (castingRegen: 0.25 x Rapid Recuperation x U + 0.5 x resUp)
		local function incomeAt(shares)
			local function shareOf(a) return shares[itemOf[a]] end
			local rc, U, resUp = castingRegen(q, T, acts, shareOf)
			local free = ps.casts.free
			for a, x in pairs(acts) do
				if x.white then free = free + (1 - shareOf(a)) * x.casts * x.white end
			end
			local Ja = jow * free
			local g1, g2 = rc + Ja, q.regenRest + Ja
			local inCombat = mn.recuperationShare * T("rapidRecuperation") * U + mn.resourcefulnessShare * resUp
			if not elem then return g2, inCombat end
			if cEff <= mn.fsr * g1 then return g1, inCombat end
			return cEff / (mn.fsr + (cEff - mn.fsr * g1) / g2), inCombat
		end
		-- what an income buys, cheapest ready first: the shares and the saving rate of the second Bestial Wrath
		local function buy(income)
			local shares, rem, blocked, wrathRate = {}, income, false, 0
			for _, it in ipairs(items) do shares[it.name] = 1 end
			for _, it in ipairs(order) do
				if it.oneOff then
					wrathRate, rem, blocked = rem, 0, true
				elseif blocked then
					shares[it.name] = 0
				elseif rem >= it.full then
					rem = rem - it.full
				else
					shares[it.name], rem = rem / it.full, 0
				end
			end
			return shares, wrathRate
		end
		local income, shares, wrathRate
		if phase == "debt" then
			shares = {}
			for _, it in ipairs(items) do shares[it.name] = 0 end
			income = incomeAt(shares)
		else
			-- G(I) = F(I) - I, and the in-combat share at what I buys
			local function excess(I)
				local F, inCombat = incomeAt((buy(I)))
				return F - I, inCombat
			end
			-- the cap of the in-combat share (castingRegen): where the share bought raises it to the cap, rc stops rising
			-- with I and F's slope drops, G's highest point between two turns
			local cap = 1 - mn.disciplineShare * T("bestialDiscipline")
			-- the incomes at which a share turns: before each item of the list what is left is max(left, I - spent) with
			-- left >= 0 (my arithmetic), so an item of net spend f > 0 is bought in part for I - spent between left and f, one
			-- of f <= 0 whole at any income; the second Bestial Wrath takes the rest and the items after it none
			local turns, left, spent = { 0 }, 0, 0
			for _, it in ipairs(order) do
				if it.oneOff then break end
				local f = it.full
				if f > 0 then
					if left < f then turns[#turns + 1] = spent + left; turns[#turns + 1] = spent + f end
					left = math.max(0, left - f)
				else
					left = left - f
				end
				spent = spent + f
			end
			table.sort(turns)
			-- the Illinois method in a bracket lo < hi with G(lo) >= 0 > G(hi)
			local function solve(lo, glo, hi, ghi)
				if glo == 0 then return lo end
				local side = 0
				for _ = 1, 100 do
					local x = (lo * ghi - hi * glo) / (ghi - glo)
					local gx = excess(x)
					if math.abs(gx) <= 1e-12 * math.max(1, x) then return x end
					if gx > 0 then
						lo, glo = x, gx
						if side > 0 then ghi = ghi / 2 end
						side = 1
					else
						hi, ghi = x, gx
						if side < 0 then glo = glo / 2 end
						side = -1
					end
					if hi - lo <= 1e-12 * math.max(1, hi) then return lo end
				end
				error("HunterGearAdvisor: the starved regime's income does not settle in 100 steps", 4)
			end
			-- past the last turn every share is whole or none, F constant: F there at or above it is the root
			local hi = turns[#turns]
			local ghi, chi = excess(hi)
			if ghi >= 0 then
				income = hi + ghi
			else
				for j = #turns - 1, 1, -1 do
					local x = turns[j]
					if x < hi then
						local gx, cx = excess(x)
						-- one share moves between x and hi, the in-combat share rises with it: where it crosses the cap
						-- (bisection), G there brackets the root with hi when at or above 0
						if cx < cap and chi > cap then
							local lo, up = x, hi
							while true do
								local mid = (lo + up) / 2
								if mid <= lo or mid >= up then break end
								if select(2, excess(mid)) < cap then lo = mid else up = mid end
							end
							local gz = excess(up)
							if gz >= 0 then income = solve(up, gz, hi, ghi); break end
							hi, ghi, chi = up, gz, cap
						end
						if gx >= 0 then income = solve(x, gx, hi, ghi); break end
						hi, ghi, chi = x, gx, cx
					end
				end
				-- F(0) >= 0, the income no less than 0
				if income == nil then error("HunterGearAdvisor: a starved state of the raid fight whose income at 0 is below 0", 2) end
			end
			shares, wrathRate = buy(income)
		end
		local out, h, wv, tempo, casts = partsAndHits(q, { rf = ps.rf, bw = ps.bw, shares = shares, hawks = ps.hawks })
		sv = { key = key, q = q, rf = ps.rf, bw = ps.bw, uses = ps.uses, regime = "starved", phase = phase, shares = shares,
			income = income, wrathRate = wrathRate, out = out, hits = h, weave = wv, tempo = tempo, casts = casts,
			mana = manaFlow(q, T, casts, costs), rich = ps }
		starvedPasses[key] = sv
		return sv
	end
	-- the one-off events at fixed times, in the order they apply at one instant (the consumables before the cooldowns)
	local t, m, regime, debt, acc = 0, p.manaMax, "rich", 0, 0
	local wrathPending = false
	local oom, runes, manaPotionAt, lastState = {}, {}, nil, nil
	-- the consumables' events held (p.events, checkMode: Model.Weights' points and Advisor ctx.eventGain; raid-mode design
	-- 25.1): the mana potion at 125 s fires as held.manaPotion says, and the rune is used held.runes' count of times, the
	-- k-th when it fits or else, from the k-th time of the point whose events they are (held.runes[k]), at an instant of
	-- 0 mana, where its room is the whole ceiling, the largest it reaches (the limit of its fit time as the fit closes on the
	-- ceiling); nil: the fight decides by the fits (7.4). deviated: a held decision differs from the one the fight would take
	-- there, so the fight at p with no held events runs otherwise
	local held = p.events
	local deviated = false
	-- the rune is ready from 5 s (the major cooldowns from 5 s, CONST.raid.cooldownsFrom), and 120 s after each use
	local runeReady = first
	-- a mana gain (the rune, the mana potion; 7.6 item 4): it repays a debt first, the saving for the second Bestial Wrath
	-- joins the mana, and the regime turns rich (the mana held at the ceiling at the next stretch)
	local function gain(amount)
		local v = m + amount + acc - debt
		if v >= 0 then
			m, debt, acc, regime = v, 0, 0, "rich"
		else
			m, debt, acc = 0, -v, 0
		end
	end
	local function pay(cost)
		if regime == "rich" and m >= cost then
			m = m - cost
		else
			if regime == "rich" then oom[#oom + 1] = t end
			debt = debt + cost - (regime == "rich" and m or 0)
			m, regime = 0, "starved"
		end
	end
	local function openWrath(at)
		wrath[#wrath + 1] = { at, at + CONST.bestialWrathDuration }
		cut(at + CONST.bestialWrathDuration)
	end
	-- the potions share category 4 for 120 s: the Frenzy Potion at 5 s locks the mana potion to 125 s, where both are ready
	-- and the resource potion goes first (registered first, consumes.go:105-107; the stable sort of major_cooldown.go:404-420):
	-- the mana potion if its whole maximum fits under the ceiling after 5 s of the casting regen of the state up to then, else
	-- the second Frenzy Potion; whichever fires locks the other past 185 s (7.4)
	local fixed = {
		{ at = first + mn.potionCooldown, fn = function()
			local fire = lastState.q.manaMax - m >= mn.manaPotion.max + mn.fsr * lastState.mana.rc
			if held then
				if held.manaPotion ~= fire then deviated = true end
				fire = held.manaPotion
			end
			if fire then
				manaPotionAt = t
				gain(mn.manaPotion.mean)
			else
				frenzy[#frenzy + 1] = { t, t + mn.frenzyPotion.duration }
				cut(t + mn.frenzyPotion.duration)
			end
		end },
	}
	for _, w in ipairs(rapid) do fixed[#fixed + 1] = { at = w[1], fn = function() pay(costs.rapidFire) end } end
	if hasWrath then
		fixed[#fixed + 1] = { at = first, fn = function() pay(costs.bestialWrath); openWrath(t) end }
		fixed[#fixed + 1] = { at = first + CONST.bestialWrathCooldown, fn = function() wrathPending, acc = true, 0 end }
	end
	fixed[#fixed + 1] = { at = mn.huntersMarkAt, fn = function() pay(costs.huntersMark) end }
	-- the stuck HHA sequence's two Summon Hawks, each its cost less its dive's Judgement of Wisdom
	for _, c in ipairs(hawkCasts) do
		fixed[#fixed + 1] = { at = c, fn = function() pay(costs.hawk - jow) end }
		cut(c + CONST.hawkDuration)
	end
	for _, e in ipairs(fixed) do cut(e.at) end
	local segments, states, byKey = {}, {}, {}
	local guard = 0
	while t < hi do
		guard = guard + 1
		if guard > 10000 then error("HunterGearAdvisor: the raid fight's timeline does not end", 2) end
		for _, e in ipairs(fixed) do
			if not e.done and e.at <= t then e.done = true; e.fn() end
		end
		local tc = nextCut(t)
		local mid = (t + tc) / 2
		local active = {}
		for k, l in ipairs(buffWin) do
			if inside(l, mid) then active[#active + 1] = k end
		end
		local ps = richPass(inside(rapid, mid), inside(wrath, mid), active, stuckHawks and hawksUp(mid) or nil)
		local ceiling = ps.q.manaMax
		if m > ceiling then m = ceiling end
		-- a starved regime turns rich at a state whose casts its regen and Judgement of Wisdom pay (D <= 0), with no debt:
		-- the mana rises from what it saved for the second Bestial Wrath
		if regime == "starved" and debt == 0 and ps.mana.D <= 0 then m, acc, regime = acc, 0, "rich" end
		local phase = regime == "starved" and (debt > 0 and "debt" or (wrathPending and "wrath" or "buy")) or nil
		-- the rune, ready and fitting now (7.6: its whole maximum 1500 under the ceiling after 5 s of the casting regen; the
		-- starved regime at 0 mana, the pool's room the whole ceiling); a rich stretch reaches the fit below
		local runeNow = false
		if t >= runeReady then
			local rc = regime == "rich" and ps.mana.rc or starvedOf(ps, phase).mana.rc
			local fire = ceiling - m >= mn.rune.max + mn.fsr * rc
			if held then
				local tk = held.runes[#runes + 1]
				local h = tk ~= nil and (fire or (m == 0 and t >= tk))
				if h ~= fire then deviated = true end
				fire = h
			end
			if fire then
				runes[#runes + 1] = t
				gain(mn.rune.mean)
				runeReady = t + mn.rune.cooldown
				cut(runeReady)
				runeNow = true
			end
		end
		local t1, ev, st = tc, nil, nil
		if runeNow then
			t1 = t
		elseif regime == "rich" then
			local D = ps.mana.D
			if wrathPending and m >= costs.bestialWrath then
				t1, ev = t, "wrath"
			else
				if D > 0 then
					local to = t + m / D
					if to <= t1 then t1, ev = math.max(t, to), "oom" end
				end
				if wrathPending and D < 0 then
					local tw = t + (costs.bestialWrath - m) / -D
					if tw < t1 then t1, ev = tw, "wrathRich" end
				end
				-- the rune's fit: the mana falling at D reaches the ceiling less 1500 and 5 s of the casting regen
				if D > 0 and t >= runeReady then
					local tr = t + (m - (ceiling - mn.rune.max - mn.fsr * ps.mana.rc)) / D
					if tr < t1 then
						-- held: no more uses than held.runes holds (the fight would use one more here)
						if held and held.runes[#runes + 1] == nil then deviated = true else t1, ev = tr, "rune" end
					end
				end
			end
			st = ps
		else
			st = starvedOf(ps, phase)
			if phase == "debt" and st.income > 0 then
				local td = t + debt / st.income
				if td < t1 then t1, ev = td, "debt" end
			elseif phase == "wrath" and st.wrathRate > 0 then
				local tw = t + (costs.bestialWrath - acc) / st.wrathRate
				if tw < t1 then t1, ev = tw, "wrath" end
			end
			-- held: the next use not fitting at 0 mana waits for its time held.runes[k], where the check above uses it
			if held and t >= runeReady then
				local tk = held.runes[#runes + 1]
				if tk ~= nil and tk > t and tk < t1 then t1, ev = tk, nil end
			end
		end
		if t1 > t then
			local key = st.key
			local rec = byKey[key]
			if not rec then
				rec = { rf = st.rf, bw = st.bw, uses = st.uses, regime = st.regime, phase = st.phase, shares = st.shares,
					income = st.income, wrathRate = st.wrathRate, weight = 0, out = st.out, hits = st.hits, weave = st.weave,
					tempo = st.tempo, casts = st.casts, mana = st.mana, rich = st.rich }
				byKey[key] = rec
				states[#states + 1] = rec
			end
			local weight = fightIntegral(t1) - fightIntegral(t)
			rec.weight = rec.weight + weight
			local m0 = m
			if regime == "rich" then
				m = m - st.mana.D * (t1 - t)
				if m > ceiling then m = ceiling end
			elseif st.phase == "debt" then
				debt = debt - st.income * (t1 - t)
			elseif st.phase == "wrath" then
				acc = acc + st.wrathRate * (t1 - t)
			end
			segments[#segments + 1] = { t0 = t, t1 = t1, weight = weight, state = rec, m0 = m0, m1 = m }
			lastState = st
		end
		t = t1
		if ev == "rune" then
			runes[#runes + 1] = t
			gain(mn.rune.mean)
			runeReady = t + mn.rune.cooldown
			cut(runeReady)
		elseif ev == "oom" then
			m, regime = 0, "starved"
			oom[#oom + 1] = t
		elseif ev == "debt" then
			debt = 0
		elseif ev == "wrath" or ev == "wrathRich" then
			if regime == "rich" then m = ev == "wrathRich" and 0 or m - costs.bestialWrath end
			wrathPending, acc = false, 0
			openWrath(t)
		end
	end
	local parts, hits = {}, nil
	for _, st in ipairs(states) do
		local share = st.weight / r.fight
		for k, v in pairs(st.out) do parts[k] = (parts[k] or 0) + share * v end
		local h = st.hits
		if not hits then
			hits = { mh = { swings = 0, specials = 0, speed = h.mh.speed }, oh = { swings = 0, specials = 0, speed = h.oh.speed },
				ranged = { swings = 0, specials = 0, casts = 0, speed = h.ranged.speed } }
		end
		for hand, tbl in pairs(hits) do
			for k in pairs(tbl) do
				if k ~= "speed" then tbl[k] = tbl[k] + share * h[hand][k] end
			end
		end
	end
	-- the stuck HHA sequence's dives: one each, in the state of its instant, a landed ranged special each (the dive always
	-- lands); both come before 175 s, where every fight still runs (the time weight 1, fightIntegral)
	for _, c in ipairs(hawkCasts) do
		local at
		for _, sg in ipairs(segments) do
			if not at and c >= sg.t0 and c < sg.t1 then at = sg end
		end
		parts.dive = parts.dive + at.state.tempo.diveHit / r.fight
		hits.ranged.specials = hits.ranged.specials + 1 / r.fight
	end
	local useSpells = {}
	for i, u in ipairs(buffs) do useSpells[i] = u.spell end
	return { segments = segments, states = states, rapidFire = rapid, bestialWrath = wrath, uses = useWin, useSpells = useSpells,
		frenzyPotion = frenzy, runes = runes, manaPotion = manaPotionAt, costs = costs, oom = oom, parts = parts, hits = hits,
		events = { manaPotion = manaPotionAt ~= nil, runes = runes }, deviated = deviated }
end

-- The parts, landed hits and weave of a pass of the mode at p: levelling the one averaged pass, raid the fight's means
local function run(p)
	if p.mode == "raid" then
		local f = fight(p)
		return f.parts, f.hits, f
	end
	local out, hits, wv = partsAndHits(p)
	return out, hits, nil, wv
end

function Model.Parts(p)
	return (run(p))
end

-- The raid fight at p (raid-mode design 6.7; /hga weights, /hga dump): fight's plan, its segments and states (each state's
-- out, hits, weave and tempo), the windows of Rapid Fire, Bestial Wrath and the Use buffs, the fight's parts and hits, and
-- means, the fight's weighted means of: serpentUptime, Serpent Sting's uptime (15 s x its landed applications a second,
-- the turret's 6.4 and the weave's 15.3 alike), hawkUptime (0 without hawks), and of the turret's tempo serpentWait
-- (delta_S), hawkWait (delta_H) and hhaCycle (C), each nil where the build has none (the Survival weave's range looks have
-- their own; a turret without hawks has no HHA cycle, partsAndHits' tempo), and of the mana (raid-mode design 6.7): jow,
-- Judgement of Wisdom's income a second, regenCast, the casting regen with the shares that come in combat (manaFlow),
-- starved, the share of the fight in the starved regime. Raid mode alone: a levelling point has no fight, an error.
function Model.Fight(p)
	if p.mode ~= "raid" then error("HunterGearAdvisor: Model.Fight of a point not in raid mode: " .. tostring(p.mode), 2) end
	local f = fight(p)
	local means = { serpentUptime = CONST.serpentDuration * f.hits.ranged.casts, hawkUptime = 0, jow = 0, regenCast = 0, starved = 0 }
	for _, st in ipairs(f.states) do
		local share, t = st.weight / CONST.raid.fight, st.tempo
		means.jow = means.jow + share * st.mana.J
		means.regenCast = means.regenCast + share * st.mana.rc
		if st.regime == "starved" then means.starved = means.starved + share end
		if t then
			means.hawkUptime = means.hawkUptime + share * t.hawkUptime
			for _, k in ipairs({ "serpentWait", "hawkWait", "hhaCycle" }) do
				if t[k] ~= nil then means[k] = (means[k] or 0) + share * t[k] end
			end
		end
	end
	f.means = means
	return f
end

-- The Survival branch's weave at p (raid-mode design 15.6: /hga weights, /hga dump and the tooltip of a melee weapon):
-- weaveParts' breakdown, the cycle at rf 0 (base), at Rapid Fire's 0.40 (rapidFire), the rates, parts and landed hits a
-- second (average) and Rapid Fire's share of the time (rfUp): levelling averaged over Rapid Fire; raid the cycles at p
-- outside and inside Rapid Fire with no Use buff, and the fight's means over its states (fight, their Use buffs in them)
-- and Rapid Fire's weighted share of the fight. nil where p does not weave (not the Survival branch, or no bow, gun or
-- crossbow).
function Model.Weave(p)
	if p.mode ~= "raid" then
		local _, _, _, wv = run(p)
		return wv
	end
	local f = fight(p)
	if not f.states[1].weave then return nil end
	local _, _, outside = partsAndHits(p, { rf = false, bw = false })
	local _, _, inside = partsAndHits(p, { rf = true, bw = false })
	local average, rfUp = { rates = {} }, 0
	for _, st in ipairs(f.states) do
		local share = st.weight / CONST.raid.fight
		local a = st.weave.average
		for k, v in pairs(a) do
			if k ~= "rates" and k ~= "acts" then average[k] = (average[k] or 0) + share * v end
		end
		for k, v in pairs(a.rates) do average.rates[k] = (average.rates[k] or 0) + share * v end
		if st.rf then rfUp = rfUp + share end
	end
	return { base = outside.base, rapidFire = inside.rapidFire, average = average, rfUp = rfUp }
end

-- The sum of the parts of the damage (Model.Parts' table), in its pairs order.
local function sumParts(parts)
	local sum = 0
	for _, v in pairs(parts) do sum = sum + v end
	return sum
end

-- The hunter's own landed hits per wall-clock second at p, by hand, the hits a chance-on-hit proc rolls on (Score
-- ProcRate): { mh = hand, oh = hand, ranged = hand }, each hand { swings, specials, speed }, the ranged hand with casts
-- as well. Every count is p's own: the weapons p swings (p.mhSpeed, p.ohSpeed, p.bowSpeed), p's attack speed, hit and
-- talents. Score prices each set's procs on the hits of the model point with that set's weapons (Advisor
-- ctx.landedHitsFor), so the hand a weapon sits in swings at that weapon's own speed there.
-- - swings: the hand's auto attacks. Shooting from range: the ranged slot's Auto Shots (autoRate: the shots' speed /
--   p.bowSpeed, landing with shotHitf); the shots' speed holds Quick Shots' uptime, which follows the Auto Shots at
--   p.bowSpeed (shots12), so a bow's Auto Shots are not in proportion to 1 / its speed alone. In the Survival weave
--   (weaveParts): one Auto Shot a cycle, the main hand's white swings (one a cycle less the cycles Raptor Strike takes)
--   and the off hand's (its share of the cycles), each landing with the white hit chance, the dual-wield miss in it.
-- - specials: in the weave the main hand's Raptor Strike (in place of a main-hand swing every nCycles(6) cycles, a melee
--   ability: wowsims' ProcMaskMeleeMHSpecial, sim/hunter/raptor_strike.go:13, 60-71), Strider Kick, Mongoose Bite (its
--   rate follows Expose Prey's landed hits) and Wing Clip (ProcMaskMeleeMHSpecial: mongoose_bite.go:31,
--   talents_survival.go:153, wing_clip.go:15), each landing with the special-attack hit chance, and Arcane Shot, landing
--   with shotHitf; from range the ranged slot's Aimed Shot, Multi-Shot, Arcane Shot and Sniper Shot, landing with
--   shotHitf, Aimed, Multi and Sniper at rates whose casts the shots' speed shortens. So the specials change with the
--   weapon's speed too. The
--   ranged slot's specials hold the dives too, with hawks (diveRate, two a 18 s): Summon Hawk's dive is the hunter's
--   spell with ProcMaskRangedSpecial and always lands (wowsims sim/hunter/summon_hawk.go:130-139), so it rolls a ranged
--   ability's equip proc and a ranged weapon's chance on hit; Summon Hawk needs no ranged weapon (no SpellEquippedItems
--   row), so the dives are there without one.
-- - casts (the ranged hand): Serpent Sting's landed applications (serpentCasts), the share Model.Parts counts its damage
--   in. A cast that lands without a damage event rolls a weapon's "Chance on hit" proc
--   (wowsims docs/evidence EV-0119 line 25; wowsims sim/core/spelldata/resolve_proc.go:95-110 WeaponProc:
--   RequireDamageDealt = false, a landed hit is enough; EV-0021 lines 32-33 and 49-50: Rend, Concussion Blow and Sunder
--   Armor applications roll Dragon's Call 10847 and Fiery Blaze), and never an equip aura's: only a hit that deals
--   damage rolls one (EV-0021 lines 18-19: never the Highborne Research Tablet 260205; lines 41-47: Dreadfrost Saber
--   274603, a weapon's equip aura, follows the aura's rules). So Score rolls on them a weapon's chance-on-hit procs
--   whose hits include the ranged hand, never a proc from an "Equip:" line (Parse proc.equip), on a weapon or not.
-- - speed: the speed the model swings that hand at (p.mhSpeed, unarmed too: Player.WeaponInputs passes the unarmed
--   1.0 s; the off hand at p.ohSpeed; the ranged slot at p.bowSpeed, and 0 with no weapon there, p.bowDPS 0 by
--   Player.WeaponInputs: wowsims' procs-per-minute managers skip the ranged entry of speed 0, sim/core/procs.go:183-227
--   mergeOrAppend, so a rate at a hand's speed finds no ranged speed to roll the dives at).
-- The counts are Model.Parts': no melee hit outside the Survival weave, no off-hand hit without dual wield (weaveParts
-- dw), no shot and no application with p.noShots, the weave's counts averaged over Rapid Fire. A melee-type hit rolls a melee
-- weapon's on-hit proc and a ranged-type hit never does (EV-0119 lines 5-7); the melee hits here are melee-type, the
-- shots and Serpent Sting ranged-type (Forever DB2 build 70888 SpellCategories DefenseType 2 for Raptor Strike 2973 /
-- 14266, Mongoose Bite 1495 / 14271 and Strider Kick 1317257; 3 for Auto Shot 75, Aimed Shot 19434, Multi-Shot 2643,
-- Arcane Shot 3044, Sniper Shot 1310687 and every Serpent Sting rank, 1978, 13549-13555, 25295). Not here: the pet's,
-- the hawks' and the dive's damage (not the hunter's weapon hits in this model), Lacerating Strikes' and Serpent Sting's
-- ticks (periodic).
function Model.LandedHits(p)
	local _, hits = run(p)
	return hits
end

function Model.Total(p)
	return sumParts((run(p)))
end

-- Model.Total(p) and Model.LandedHits(p) from one pass (Advisor's per-set weapon model: a set's weapon gain and the
-- landed hits its procs roll on). The total is Model.Total's to the bit: the same parts summed the same way.
function Model.TotalAndHits(p)
	local parts, hits = run(p)
	return sumParts(parts), hits
end

-- The raid fight's discrete events at p (raid-mode design 25.1): the consumables' fits of 7.4, which wowsims decides by a
-- threshold (the mana potion at 125 s when its 2250 fits under the ceiling after 5 s of the casting regen, else a second
-- Frenzy Potion; the rune whenever its 1500 fits so: sim/common/shared/consumable_potion.go:257-266, 382-388), so the fight's
-- damage jumps where a stat moves the pool, the regen or the spend across one. { manaPotion = whether it fired, runes =
-- the rune's times }, the form p.events holds (Model fight). Raid mode alone.
function Model.FightEvents(p)
	if p.mode ~= "raid" then error("HunterGearAdvisor: Model.FightEvents of a point not in raid mode: " .. tostring(p.mode), 2) end
	if p.events ~= nil then error("HunterGearAdvisor: Model.FightEvents of a point whose events are held", 2) end
	local ev = fight(p).events
	local runes = {}
	for i, t in ipairs(ev.runes) do runes[i] = t end
	return { manaPotion = ev.manaPotion, runes = runes }
end

-- The change of the raid fight's events at q against events, the events of another point (Advisor ctx.eventGain: the model
-- point's, with a set's stats applied at q; raid-mode design 25.1): Model.Total(q) less the fight at q with events held,
-- in DPS; 0, with no second run, where no held decision differs from the one the fight takes at q (the two fights are one).
-- The fight's weights hold the events of the point they are taken at (Model.Weights), so a set's stats priced at them
-- leave out a change of an event; this is that change, the jump of the fight's damage across a threshold. Returns it and
-- whether a held decision differs (the fight's deviated), which the mana's inputs alone decide (Model.EventKeys).
function Model.EventGain(q, events)
	if q.mode ~= "raid" then error("HunterGearAdvisor: Model.EventGain of a point not in raid mode: " .. tostring(q.mode), 2) end
	if q.events ~= nil then error("HunterGearAdvisor: Model.EventGain of a point whose events are held", 2) end
	local h = copy(q)
	h.events = events
	local f = fight(h)
	if not f.deviated then return 0, false end
	return Model.Total(q) - sumParts(f.parts), true
end

-- The outcome of a proc's damage at the model point (Score.ProcValue; Advisor ctx.procOutcome), by the table its damage
-- spell rolls (wowsims sim/common/shared/shared_utils.go:76-119: its DefenseType, and with none the melee table for the
-- physical school, the spell table for the others; the Tablet's OutcomeMagicHitAndCrit, items_trinkets.go:263-269;
-- Heartseeking's OutcomeRangedHitAndCrit, items_weapons.go:207-215). A proc spell is built with ProcMaskEmpty
-- (sim/common/forever/items_armor.go:311-317 procSpellConfig), so its melee or ranged table is the main hand's entry
-- (sim/core/target.go:606-615 Hand) at the main hand's skill p.mhSkill (its miss Model.SkillMiss, its dodge
-- Model.SkillDodge, its crit suppression critSuppressor; in every build, a hunter of any branch may hold a melee weapon
-- below its skill), with the physical hit alone (RangedHitPercent only under ProcMaskRanged, spell_result.go:196-204:
-- no p.rangedGearHit, no p.rangedHit) and the physical crit alone (no ranged crit, spell_result.go:215-219: the melee
-- sheet's crit); from behind the target, no parry and no block. A magic proc's spell miss is the table's level-based one,
-- no hand's (spell_result.go:287-288 SpellChanceToMiss reads attackTable.BaseSpellMissChance). Each table: hit, the
-- share that lands, and critMult, the factor of its crit:
-- - [1] magic: 1 - max(0, the spell miss - p.spellHit), the spell miss 4% + 1% a level of the difference, 17% at +3
--   (target.go:540-547 spellMissChance), with no 1% floor (spell_result.go:287-304); crit x1.5 of the magic table
--   (sim/core/spell.go:959-975) at p.spellCrit, which no defender suppresses (spell_result.go:309-318);
-- - [2] melee: 1 - the main hand's miss (p.hit) - its dodge (expertise lowers it), crit x2 at the suppressed melee crit;
-- - [3] ranged: 1 - the main hand's miss (p.hit), no dodge, crit x2 at the suppressed melee crit;
-- - [0] no DefenseType: { physical = [2], magic = [1] } by the school.
-- A spell that cannot crit drops critMult (Score.ProcValue). A damage over time of a proc (raid-mode design 17; wowsims
-- sim/common/shared/shared_utils.go:724-819 spellDataProcDamageSpell) takes from its table land, its application's chance
-- (the application rolls the table once, without the crit an application cannot deal: shared_utils.go:730, 771-776; a
-- direct damage of the same spell rolls hit and crit and the damage over time lands with its hit, 810-816: the same
-- share), and tickCrit, its ticks' crit factor where the spell's row states PERIODIC_CAN_CRIT (the ticks roll no hit;
-- sim/core/spelldata/spell.go:368-377 TickOutcome: the spell crit x1.5 of a magic DefenseType, OutcomeTickMagicCrit, else
-- the physical crit x2, OutcomeTickPhysicalCrit, the main hand's suppressed melee crit of a ProcMaskEmpty spell;
-- spell_outcome.go:171-199): each table's own crit factor, critMult. phys: the armor multiplier of the mode's target (physOf: the
-- creature's own while levelling, the raid boss's 976 less the hunter's p.armorPen in raid mode), which a
-- physical-school damage takes alone (spell_resistances.go:18-31; no level-based magic resistance,
-- spell_resistances.go:64-76); coe and gift: Curse of the Elements' multiplier on a magic-school damage and Gift of
-- Arthas' flat damage on a physical-school one, added after the armor and before the outcome (raid mode, CONST.raid;
-- levelling 1 and 0); own: the hunter's damage multiplier
-- (ownDamage: Focused Fire, Lone Wolf, Improved
-- Tracking), which a proc spell takes (no SpellFlagIgnoreAttackerModifiers, sim/core/spelldata/resolve_spell.go:221-233
-- Proc(); spell_result.go:916-927). Ranged Weapon Specialization does not reach a proc: its aura is bound to ranged
-- weapons and becomes a modifier of the ranged proc mask, which ProcMaskEmpty does not match
-- (sim/core/spelldata/weapon_scope.go:40-58). mode: p.mode, by which Score.VersusFactor takes a versus bonus's share of
-- the targets (Model.TargetShare). Left out: Intellect's spell crit (wowsims CritPerIntMaxLevel 0.0165% a point,
-- base_stats_auto_gen.go:38-42) and the Tablet's x2 against Naga and Satyrs (a creature family, which HGA does not model).
function Model.ProcOutcomes(p)
	local T = talents(p)
	checkInputs(p, REQUIRED_NUMBERS, REQUIRED_FLAGS)
	checkMode(p)
	local d = capDiff(p.mobDiff)
	local suppressed, agiCrit = critSuppressor(p)
	-- the main hand's entry (raid-mode W1 design 3.4): its skill's miss, dodge and crit suppression at p.mhSkill
	local critMult = 1 + suppressed(p.meleeCrit / 100, agiCrit, p.mhSkill)
	local miss = math.max(0, Model.SkillMiss(p.mobDiff, p.mhSkill) - p.hit) / 100
	local dodge = math.max(0, Model.SkillDodge(p.mobDiff, p.mhSkill) - p.expertise) / 100
	local spellMiss = d >= 3 and 0.17 or math.max(0, 0.04 + 0.01 * d)
	local magicHit, magicCrit = 1 - math.max(0, spellMiss - p.spellHit / 100), 1 + 0.5 * p.spellCrit / 100
	local magic = { hit = magicHit, critMult = magicCrit, land = magicHit, tickCrit = magicCrit }
	local melee = { hit = 1 - miss - dodge, critMult = critMult, land = 1 - miss - dodge, tickCrit = critMult }
	local ranged = { hit = 1 - miss, critMult = critMult, land = 1 - miss, tickCrit = critMult }
	return { [0] = { physical = melee, magic = magic }, [1] = magic, [2] = melee, [3] = ranged,
		phys = physOf(p, p.armorPen), own = (ownDamage(p, T)), coe = p.mode == "raid" and CONST.raid.coe or 1,
		gift = p.mode == "raid" and CONST.raid.giftOfArthas or 0, mode = p.mode }
end

local function deriv(p, t0, mutate, step)
	local q = copy(p)
	mutate(q, step)
	return (Model.Total(q) - t0) / step
end

-- Returns the damage weights in the weights' unit, the DPS one unit adds (unitDps), Model.Total(p) and the unit's
-- name ("RAP", "MAP" or "DPS"). Each weight is the DPS its stat adds over unitDps.
-- The unit is 1 RAP whenever more RAP adds damage (dRap > 0). Model.Parts reads p.rap in the shots (rapShot: Auto
-- Shot, Aimed, Multi, Arcane and Sniper, Serpent Sting from level 4, and in the Survival weave Immolation Trap's ticks),
-- in the dive and the hawks' AP (hawksOn) and in the pet's AP (max(p.rap, p.map)). So more RAP adds nothing with no shot
-- counted (noShots: no bow, gun or crossbow), no hawks (below CONST.hawkLearnLevel, without Summon Hawk or in the
-- Survival branch) and no pet that reads it (no pet: below level 10, or Lone Wolf with no pet out; or a pet whose AP is
-- the melee AP over the whole step, p.map >= p.rap + 10). The unit is then 1 melee attack power ("MAP", the derivative
-- by p.map), which a pet that does not read p.rap reads (the melee of the weave needs shots, weaveParts). With neither
-- (a hunter below level 10, or with Lone Wolf and no pet out, with no bow, gun or crossbow worn) nothing in Model.Parts
-- attacks and Model.Total is 0 whatever the stats: the unit is 1 DPS ("DPS"), every weight is 0 and a weapon's gain
-- (Advisor weaponGain) is the model's DPS change. A derivative below 0 or not a number (an input that is not a number)
-- is an error.
-- Raid mode: each derivative holds the consumables' events of the point it is taken at (Model.FightEvents, p.events;
-- raid-mode design 25.1), so a weight is the gain of its stat in that point's fight, not a jump across a consumable's fit
-- divided by the step (across the mana potion's fit a step of 10 Intellect, divided by it, gives 23.7 against 2.85 on
-- either side: raid-mode design 20.5, 25.1); Score.SetValue prices a set's own change of an event apart (Advisor
-- ctx.eventGain).
function Model.Weights(p0)
	local T = talents(p0)
	-- q with the events of its own fight held, and its total (that fight is the fight at q: a deviation is an error);
	-- levelling, q itself
	local function hold(q)
		if q.mode ~= "raid" then return q, Model.Total(q) end
		local h = copy(q)
		h.events = Model.FightEvents(q)
		local f = fight(h)
		if f.deviated then error("HunterGearAdvisor: the raid fight with its own events held runs otherwise", 2) end
		return h, sumParts(f.parts)
	end
	local p, t0 = hold(p0)
	-- the mutation of one stat key, through the one map from stat keys to inputs (applyStats)
	local function stat(key) return function(q, d) applyStats(q, { [key] = d }, T) end end
	local dRap = deriv(p, t0, stat("RAP"), 10)
	local unitDps, unit
	if dRap > 0 then
		unitDps, unit = dRap, "RAP"
	elseif dRap == 0 then
		local dMap = deriv(p, t0, stat("MAP"), 10)
		if dMap > 0 then
			unitDps, unit = dMap, "MAP"
		elseif dMap == 0 then
			unitDps, unit = 1, "DPS"
		else
			error("HunterGearAdvisor: one more melee attack power changes the model's DPS by " .. tostring(dMap), 2)
		end
	else
		error("HunterGearAdvisor: one more RAP changes the model's DPS by " .. tostring(dRap), 2)
	end
	local W = { RAP = dRap / unitDps }
	-- an item's Agility through Lightning Reflexes and the live sheet's Agility multiplier, its attack power and its crit
	-- (applyStats AGI): no factor outside; an item's Strength and Intellect likewise at their multipliers (applyStats)
	W.AGI = deriv(p, t0, stat("AGI"), 10) / unitDps
	W.AP = deriv(p, t0, stat("AP"), 10) / unitDps
	W.STR = deriv(p, t0, stat("STR"), 10) / unitDps
	-- crit from an item raises ranged and melee crit alike; as aura crit it grows the suppressed part too (Model.Parts)
	W.CRIT = deriv(p, t0, stat("CRIT"), 0.5) / unitDps
	-- crit of the ranged attacks alone: p.crit, melee crit held at p.meleeCrit. Score prices a crit scope's crit
	-- (SpellItemEnchantment 8720, ranged weapons only) at it. p.crit is the owner's ranged crit, which the shots, the dive
	-- and the pet's ranged branch take (petCritBase: wowsims sim/hunter/pets.go:142-153 inheritedCrit gives the pet, and
	-- half of it the hawks, the higher of the owner's melee and ranged crit; a level 17 pet sheet read the owner's ranged
	-- crit whole, wowsims docs/evidence EV-0070).
	W.CRIT_RANGED = deriv(p, t0, stat("CRIT_RANGED"), 0.5) / unitDps
	-- The ranged weapon skill's crit (raid-mode W1 design 3.3): the value of one skill point further below the level's
	-- maximum, taken one-sided at b0 = min(p.rangedSkill, 0), since every crit part of the skill starts at the maximum
	-- (the suppression's max(0, -bonus), critSuppressor; the pet's min(bonus, 0) x 0.04, petCritBase): W.SKILL_CRIT is
	-- Total at rangedSkill b0 less Total at b0 - 1, the ranged hand's suppression (the shots, Serpent Sting's ticks, the
	-- dive) and the pet's 0.04% and the hawks' 0.02% a point while the pet's ranged branch holds. Score prices a set's
	-- skill below the maximum at it against the worn set's (Score.SetValue). p.rangedSkill moves no hit (p.rangedHit
	-- holds the skill's hit).
	local function skillCrit(q)
		local b0 = math.min(q.rangedSkill, 0)
		local at = copy(q)
		at.rangedSkill = b0
		local ta
		at, ta = hold(at)
		local below = copy(at)
		below.rangedSkill = b0 - 1
		return (ta - Model.Total(below)) / unitDps
	end
	W.SKILL_CRIT = skillCrit(p0)
	-- the same where no shot is cast: at p with no bow, gun or crossbow (noShots) and no ranged weapon DPS (bowDPS 0: the
	-- ranged slot of a set without shots is empty or holds an item that is no weapon, Player.WeaponInputs; Player.CanUse
	-- keeps thrown weapons out of every candidate), so it is the crit of what still attacks: the pet, the hawks and the
	-- dive (the hawks without Quick Shots and with the AP of no ranged weapon, the dive without Ranged Weapon
	-- Specialization). Score prices at it the skill change of a set without shots, whose ranged hand is at bonus 0
	-- (wowsims sim/core/weapon_skill.go:17-19: no weapon, no bonus)
	local qn = copy(p0); qn.noShots = true; qn.bowDPS = 0
	W.SKILL_CRIT_NO_SHOTS = skillCrit(qn)
	-- expertise: the value of 1% below the cap, Model.MobAvoid(mobDiff), the mob's dodge. Every consumer in Model.Parts
	-- loses max(0, avoid - expertise / 100) of its hits to the dodge: the hawks (hawkDodge), the pet (petDodge) and the
	-- melee swings (dodge); the pet, while the mob faces it (Model.PetTanks), loses max(0, parry - expertise / 100) to the
	-- parry too (petParry, Model.PetParry). So below the dodge each point lands a point more of their hits (the pet's
	-- twice while it tanks): the DPS is linear in it there (Mongoose Bite's count aside, which follows Expose Prey's landed
	-- hits, Model.Parts; and the crit's room in the white table, Model.Parts white, while the crit is under it), its slope
	-- the same at any expertise below the dodge. The slope is taken at expertise 0 with the other inputs at p, a point
	-- below the dodge at every mobDiff (the dodge is 5% or more), so the cap never zeroes it, also for a worn expertise at
	-- or past it; it is 0 only where nothing in Model.Parts takes expertise (no pet, no hawks and no Survival weave).
	-- W.EXPERTISE_PARRY: past the dodge only the tanking pet's parry is left, up to Model.PetParry (14% at +3, the dodge
	-- itself at +0..+2): its slope taken at expertise = the dodge. The caps are applied when a whole set is scored
	-- (Score.SetValue prices W.EXPERTISE x min(e, ctx.expertiseCap) + W.EXPERTISE_PARRY x the part of e between
	-- ctx.expertiseCap and ctx.parryCap).
	local qe, te = copy(p0), nil
	qe.expertise = 0
	qe, te = hold(qe)
	W.EXPERTISE = deriv(qe, te, function(q, d) q.expertise = q.expertise + d end, 0.5) / unitDps
	local qp, tp = copy(p0), nil
	qp.expertise = Model.MobAvoid(p.mobDiff)
	qp, tp = hold(qp)
	W.EXPERTISE_PARRY = deriv(qp, tp, function(q, d) q.expertise = q.expertise + d end, 0.5) / unitDps
	-- attack speed by source (the p fields above): W.HASTE an item's or enchant's aura 342, the shots, the melee swings,
	-- the pet and the hawks (Minor Haste 931 on gloves); W.ATTACK_SPEED a set bonus's aura 9 or 342, the shots, the melee
	-- swings and the pet (the Tier-1 two-piece bonuses); W.HASTE_RATING haste rating, the shots and the melee swings;
	-- W.MELEE_HASTE the melee swings, Raptor Strike's count and the pet (aura 319: Iron Counterweight 34, the melee half of
	-- Arcanum of Rapidity 2543 and of Kiss of the Spider); W.RANGED_HASTE the shots and the hawks (aura 140: the ranged half
	-- of Arcanum of Rapidity and of Kiss of the Spider).
	-- Each is the value of one more 1% source of its input at the worn point. An input is the product of its sources
	-- (Player wornHaste: each aura multiplies the speed, wowsims sim/core/unit.go Multiply*Speed), so a new d% source
	-- raises it to ((1 + x/100) x (1 + d/100) - 1) x 100, by (1 + x/100) x d points, not d: the step below is that one
	-- (applyStats), and the weight is (1 + x/100) times the derivative by the input's percent. Score prices an item's
	-- HASTE / ATTACK_SPEED / HASTE_RATING / MELEE_HASTE / RANGED_HASTE, a set bonus's and a Use buff's as such a source
	-- (W x amount, a Use buff's times its uptime). Two sums are the exceptions (Player wornHaste): the worn items' haste
	-- rating sums before it multiplies (wowsims hasteRatingMultiplier = 1 + the rating / 1000, sim/core/unit.go:564-566:
	-- 1 + the sum R of the worn items' HASTE_RATING, one factor), and the worn set bonuses' ATTACK_SPEED comes as one sum S
	-- (Score.SetBonuses adds the bonuses' stats up; 1 + S/100, one factor). So a point of either multiplies the input's
	-- multiplier by 1 + 1 / (100 + R), or 1 + 1 / (100 + S), not 1 + 1 / 100: W.HASTE_RATING prices an item's rating point
	-- (1 + R/100) times its model value, and W.ATTACK_SPEED a set bonus's (1 + S/100) times, S the other worn bonuses'
	-- ATTACK_SPEED: 1% over for a second Tier-1 two-piece bonus next to a first (S = 1; the two give 2% where two factors
	-- give 2.01%).
	W.HASTE = deriv(p, t0, stat("HASTE"), 0.5) / unitDps
	W.ATTACK_SPEED = deriv(p, t0, stat("ATTACK_SPEED"), 0.5) / unitDps
	W.HASTE_RATING = deriv(p, t0, stat("HASTE_RATING"), 0.5) / unitDps
	W.MELEE_HASTE = deriv(p, t0, stat("MELEE_HASTE"), 0.5) / unitDps
	W.RANGED_HASTE = deriv(p, t0, stat("RANGED_HASTE"), 0.5) / unitDps
	W.RANGED_DPS = deriv(p, t0, function(q, d) q.bowDPS = q.bowDPS + d end, 1) / unitDps
	W.AMMO_DPS = deriv(p, t0, function(q, d) q.ammoDPS = q.ammoDPS + d end, 1) / unitDps
	-- Intellect: Careful Aim's attack power, +20%/rank of Intellect (auras 580 + 598: melee and ranged AP), applyStats INT.
	-- Levelling: the model is linear in it, so its weight is that share of W.AP at the live sheet's Intellect multiplier
	-- (applyStats; mana is the tie-break there). Raid mode
	-- (the user's answer 4 = (b); raid-mode design 6.9, 7.7): also 15 mana of the pool a point, so the derivative of the
	-- fight by applyStats INT (step 10), the mana pool and Careful Aim together; MP5 (both regens, step 10), Spirit (the
	-- Spirit regen in both regens at their shares, step 10) and MANA (the pool, step 100) likewise, each through the fight's
	-- regimes and consumables (Model fight); levelling prices the three at 0 (below)
	local raid = p.mode == "raid"
	if raid then
		W.INT = deriv(p, t0, stat("INT"), 10) / unitDps
		W.MP5 = deriv(p, t0, stat("MP5"), 10) / unitDps
		W.SPI = deriv(p, t0, stat("SPI"), 10) / unitDps
		W.MANA = deriv(p, t0, stat("MANA"), 100) / unitDps
	else
		W.INT = 0.20 * T("carefulAim") * W.AP * statMultOf(p, "INT")
	end
	-- A Use buff's attack power never reaches the pet (the user's answer O6, both modes; wowsims sim/hunter/pets.go:160-171
	-- keepSummonStats: the pet keeps its summon's attack power, EV-0072): levelling mode prices a Use buff over its uptime
	-- (Score.SetValue) at these weights, each the derivative of the total by the key with the pet's attack powers held at
	-- the point's (p.petRap, p.petMap), so a Use buff's AP, RAP, MAP, STR, AGI (its attack power; its crit reaches the pet,
	-- whose crit follows the owner, pets.go:121-137) and INT (Careful Aim's attack power) leave the pet's share out (raid-mode
	-- design 6.8). Raid mode runs the Use buffs through the fight (Score.SetValue ctx.useGain): none of these.
	if p.mode == "level" then
		local function useStat(key)
			return function(q, d)
				if q.petRap == nil then q.petRap, q.petMap = q.rap, q.map end
				applyStats(q, { [key] = d }, T)
			end
		end
		W.AP_USE = deriv(p, t0, useStat("AP"), 10) / unitDps
		W.RAP_USE = deriv(p, t0, useStat("RAP"), 10) / unitDps
		W.MAP_USE = deriv(p, t0, useStat("MAP"), 10) / unitDps
		W.STR_USE = deriv(p, t0, useStat("STR"), 10) / unitDps
		W.AGI_USE = deriv(p, t0, useStat("AGI"), 10) / unitDps
		W.INT_USE = 0.20 * T("carefulAim") * W.AP_USE * statMultOf(p, "INT")
	end

	-- hit: value of 1% below the cap, computed with every attack at 0% hit (p.hit, p.rangedGearHit, the shots'
	-- p.rangedHit and the main hand's p.meleeHit at 0) so it is never 0 here; the cap is applied when a whole equipped set
	-- is scored. W.HIT is the hit of every attack (p.hit: gear, set bonuses, buffs), W.RANGED_HIT the worn gear's
	-- ranged-only hit (p.rangedGearHit: the shots, the pet and the hawks), at which Score prices an item's and a set
	-- bonus's RANGED_HIT, W.HIT_RANGED the shots' own hit (p.rangedHit: the six shots and the shot hits that open Expose
	-- Prey), at which Score prices a ranged weapon's skill hit, W.HIT_MELEE the main hand's skill hit (p.meleeHit: its
	-- specials and white swings under the specials' cap in the Survival weave, 0 outside it), at which Score prices a set's
	-- main-hand skill hit (raid-mode W1 design 3.4). Their consumers nest (every attack, then the shots, the pet and the
	-- hawks, then the shots; every attack, then the main hand's melee), so W.HIT >= W.RANGED_HIT >= W.HIT_RANGED and
	-- W.HIT >= W.HIT_MELEE.
	local q0, th = copy(p0), nil
	q0.hit = 0; q0.rangedHit = 0; q0.rangedGearHit = 0; q0.meleeHit = 0
	q0, th = hold(q0)
	W.HIT = deriv(q0, th, function(q, d) q.hit = q.hit + d end, 0.5) / unitDps
	W.RANGED_HIT = deriv(q0, th, function(q, d) q.rangedGearHit = q.rangedGearHit + d end, 0.5) / unitDps
	W.HIT_RANGED = deriv(q0, th, function(q, d) q.rangedHit = q.rangedHit + d end, 0.5) / unitDps
	W.HIT_MELEE = deriv(q0, th, function(q, d) q.meleeHit = q.meleeHit + d end, 0.5) / unitDps
	-- Spell hit and spell crit, which wowsims rolls Immolation Trap on (its application the spell table, its ticks' crit the
	-- spell crit x1.5: Model weaveParts; raid-mode design 18.8): W.SPELL_CRIT the value of 1% more spell crit (the model is
	-- linear in it); W.SPELL_HIT the value of 1% below the trap's cap (Model.TrapHitCap), taken at spellHit 0 as W.HIT is,
	-- the cap applied when a whole set is scored (Score.SetValue). Both 0 outside the Survival weave (no trap). The magic
	-- procs' spell table is the worn point's (Score.ProcValue, approximation A6): no part of these weights
	W.SPELL_CRIT = deriv(p, t0, stat("SPELL_CRIT"), 0.5) / unitDps
	local qs, ts = copy(p0), nil
	qs.spellHit = 0
	qs, ts = hold(qs)
	W.SPELL_HIT = deriv(qs, ts, function(q, d) q.spellHit = q.spellHit + d end, 0.5) / unitDps

	-- melee weapon setups: each hand type at the worn main hand's DPS and speed when the worn main hand is a weapon of that
	-- type, else at a typical weapon of the type (a two-hander 34 DPS at 3.3 s, a one-hander 26 DPS at 2.6 s); an empty main
	-- hand is a weapon of neither type (its 1.0 s, Player UNARMED_SPEED, is the unarmed swing). The one-hander setup takes
	-- the worn one-hander's normalized speed, else a one-hander's 2.4 (Player normSpeed): W.HIT_DW reads it through Mongoose
	-- Bite's normalized hit; a derivative by the weapon's DPS does not read the normalized speed
	local function meleeSetup(twoH)
		local q = copy(p0)
		if twoH then
			q.mhDPS = (p.twoH and p.mhDPS > 0) and p.mhDPS or 34
			q.mhSpeed = (p.twoH and p.mhSpeed) or 3.3
		else
			local worn = not p.twoH and not p.unarmed
			q.mhDPS = (worn and p.mhDPS > 0) and p.mhDPS or 26
			q.mhSpeed = worn and p.mhSpeed or 2.6
			q.mhNorm = worn and p.mhNorm or 2.4
		end
		q.twoH = twoH
		q.unarmed = false -- the setup holds the weapon it prices
		if twoH then q.ohDPS = 0 else q.ohDPS = q.ohDPS > 0 and q.ohDPS or 26 end
		return q
	end
	-- melee weapon DPS per hand: the Survival weave's with that setup (weaveParts), 0 for every other build (no melee)
	local function meleeW(twoH, which)
		local q, t = hold(meleeSetup(twoH))
		local key = which == "oh" and "ohDPS" or "mhDPS"
		return deriv(q, t, function(r, d) r[key] = r[key] + d end, 1) / unitDps
	end
	W.MH_DPS = meleeW(false, "mh")
	W.OH_DPS = meleeW(false, "oh")
	W.TH_DPS = meleeW(true, "mh")

	-- hit above the special-attack cap: still lowers dual-wield white misses, up to 19% more
	-- (CR_HUNTER_HIT_CAP_TOOLTIP: 24% dual wielding vs same-level targets): the weave's white swings of the main hand and
	-- the off hand. Taken just above the cap with two one-handers, the shots past the cap too (p.rangedHit 0) and the main
	-- hand's skill hit at 0 (p.meleeHit 0: a worn main hand below its maximum would leave its specials missing there, and
	-- their slope would enter the weight); Score adds it only for a set that dual wields; 0 outside the Survival branch (no
	-- melee). W.HIT_DW is the derivative by p.hit (both hands' white swings), W.HIT_DW_MH by p.meleeHit (the main hand's
	-- white swings alone), so the off hand's part is W.HIT_DW - W.HIT_DW_MH (raid-mode W1 design 3.4).
	W.HIT_DW, W.HIT_DW_MH = 0, 0
	if p.survival then
		local qd = meleeSetup(false)
		qd.hit = Model.HitCap(p.mobDiff) + 0.5
		qd.rangedHit = 0
		qd.meleeHit = 0
		local td
		qd, td = hold(qd)
		W.HIT_DW = deriv(qd, td, function(q, d) q.hit = q.hit + d end, 0.5) / unitDps
		W.HIT_DW_MH = deriv(qd, td, function(q, d) q.meleeHit = q.meleeHit + d end, 0.5) / unitDps
	end

	-- attack power against a creature type (p.apVsTarget): the hunter's own attacks alone (Model.Parts rapOwn, mapOwn), so
	-- below W.AP whenever a pet or hawks are out; the model is linear in it. An item's AP_VS_<TYPE> counts at the mode's
	-- share of that type (Model.TargetShare): levelling Model.AP_CREATURE_SHARE for every type, raid 1 for the boss's
	-- dragonkin and 0 for the others
	W.AP_VS = deriv(p, t0, function(q, d) q.apVsTarget = q.apVsTarget + d end, 10) / unitDps
	for _, t in ipairs(Model.CREATURE_TYPES) do W["AP_VS_" .. t] = W.AP_VS * Model.TargetShare(t, p.mode) end
	-- Beastslaying, a point of flat damage per hit (p.beastSlaying): the hunter's weapon strikes and shots at the mode's
	-- share of targets that are beasts (Model.Parts flat: 0 in raid mode); the model is linear in it. Score prices an item's
	-- BEAST_SLAYING at it when no ctx.weaponGain runs the set's weapons (Score.ItemValue)
	W.BEAST_SLAYING = deriv(p, t0, function(q, d) q.beastSlaying = q.beastSlaying + d end, 1) / unitDps
	-- flat armor penetration (the user's answer O5: as wowsims, against the boss's armor; sim/core/spell_resistances.go:
	-- 147-150): in raid mode the value of one point of p.armorPen off the boss's 976 (Model.BossArmor, floored at 0; the
	-- slope taken over 10 points), at which Score prices an item's and a set bonus's ARMOR_PEN; levelling mode has no input
	-- of it (the answer names the boss's armor): 0
	W.ARMOR_PEN = p.mode == "raid" and deriv(p, t0, stat("ARMOR_PEN"), 10) / unitDps or 0
	-- melee-only attack power: Strength's value without the live sheet's Strength multiplier (applyStats MAP)
	W.MAP = deriv(p, t0, stat("MAP"), 10) / unitDps
	W.EXTRA_DPS = 1 / unitDps -- the value of 1 DPS of extra damage (procs) in the weights' unit
	-- no damage value (survival / tank stats are compared after damage, see Score.Secondary; the mana stats too while
	-- levelling, their raid weights above)
	for _, k in ipairs({ "STA", "ARMOR", "HEALTH", "HP5", "DEFENSE", "DODGE", "PARRY", "BLOCK", "SPELL_POWER" }) do
		W[k] = 0
	end
	if not raid then W.SPI, W.MP5, W.MANA = 0, 0, 0 end
	return W, unitDps, t0, unit
end

-- Mana-equivalent of mana stats for the secondary comparison (assumptions, see memory):
-- MP5 over one minute of combat = 12 mana per point; Spirit = 0.1 mana/s per point while its
-- regen keeps going in combat, over 60 s, plus 1 for faster drinking out of combat. Shares of
-- Spirit regen that keep going while casting (they add up to at most 100%): Bestial Discipline
-- 25%/rank, Rapid Recuperation 25%/rank while Serpent Sting is up (CONST.serpentUptime),
-- Resourcefulness 50% while its buff 1242688 is up (SpellEffect 1242361: aura 134 A_MOD_MANA_REGEN_INTERRUPT bp 50,
-- whatever the rank) x that buff's uptime, CONST.resourcefulnessUptime for each rank (the rank sets the chance a crit
-- triggers the buff, 50% a rank; an estimate). So a point of Spirit is 1 + 6 x min(1, that sum) mana.
function Model.SecondaryRates(tal)
	if not tal then error("HunterGearAdvisor: SecondaryRates called without talent ranks", 2) end
	local function T(name) return rankOf(tal, name) end
	local inCombat = 0.25 * T("bestialDiscipline")
		+ 0.25 * T("rapidRecuperation") * CONST.serpentUptime
		+ 0.5 * T("resourcefulness") * CONST.resourcefulnessUptime
	return {
		hpPerSta = 10 * (1 + 0.02 * T("survivalist")), -- Survivalist +2%/rank health
		hpMult = 1 + 0.02 * T("survivalist"),
		manaPerInt = 15,
		manaPerMp5 = 12,
		manaPerSpi = 1 + 6 * math.min(1, inCombat),
	}
end
