-- Glue between live state and the pure scorer: weights, evaluation cache, explanations.
--
-- `where` tells where the hovered/marked item is:
--   { kind = "equipped", slot }  worn now
--   { kind = "bag", bag, slot }  in a bag
--   { kind = "new" }             quest reward, loot, merchant: never "already worn"
--   nil                          unknown (a chat link): worn if the link matches a worn item
local _, ns = ...
local A = {}
ns.Advisor = A

local S = ns.Score.SLOT
local state        -- { snap, model (the model point, A.State), W, unitDps, unit, total, ctx, rangedSkill, plan }
local results = {} -- key -> result
local failedAt     -- GetTime() of the last failed snapshot (the reason stays in A.notReadyReason)
local RETRY_AFTER = 1 -- s: a bag refresh of many buttons takes one snapshot, not one per button

function A.Reset()
	state = nil
	results = {}
	failedAt = nil
end

local QUIVER_NAME = { [2] = "колчан", [3] = "подсумок" }

-- The ruRU words of the creature types of AP_VS_<TYPE> (Model.CREATURE_TYPES), as the equip texts name them (Forever DB2
-- db2_ru Spell.csv: 13492 "против животных", 24291 "драконов", 12822 "демонов", 22836 "элементалей", 21937
-- "великанов", 12981 "нежити", 1292025 "гуманоидов", 435360 "механизмов")
local CREATURE_WORDS = {
	BEAST = "животных", DRAGONKIN = "драконов", DEMON = "демонов", ELEMENTAL = "элементалей", GIANT = "великанов",
	UNDEAD = "нежити", HUMANOID = "гуманоидов", MECHANICAL = "механизмов",
}

-- A set's weapon model for Score.SetValue: the model point of A.State (model, whose Total is total) with the set's
-- weapon inputs (Player.WeaponInputs) and its hands' melee weapon skills (meleeSkillsOf(set): Score.MeleeSkills, the
-- model's p.mhSkill and p.ohSkill; p.meleeHit stays the model point's, Score prices the main hand's skill hit through the
-- cap, raid-mode W1 design 3.4), the other inputs the model point's (the worn hit, attack speed, crit). Returns
-- the gain in the weights' unit (Model.Weights) of the set's ranged weapon and hands over the worn ones, each weapon at
-- its own speed (ctx.weaponGain), and the landed hits of that point, the hits the set's procs roll on
-- (ctx.landedHitsFor; Score.LandedHitsOf). The damage model is not linear in weapon speed (Quick Shots uptime,
-- normalized shots, Raptor's swing count), so the set's weapons go through the whole model, and the gain and the hits
-- come from one Model.TotalAndHits run on one p. The worn set gives a gain of exactly 0 and the model point's own hits
-- (its melee skills are the model point's: Score.MeleeSkills of the worn set is each hand's live skill less 5 x level).
-- One model run per distinct (ranged, main hand, off hand, main hand's skill, off hand's skill) of one State: a set's set
-- bonuses move its hands' skills with the same weapons. The returned function takes the set and its hands' skills
-- (meleeSkillsOf(set)) when the caller has them (Score.SetValue computes them once a set); with nil, nil it computes them;
-- one of the two alone is an error.
local function weaponModelFor(model, total, unitDps, meleeSkillsOf)
	local NONE = {} -- key for an empty slot
	local cache = {} -- ranged -> main hand -> off hand -> main hand's skill -> off hand's skill -> { gain, hits }
	local function sub(t, k)
		local s = t[k]
		if not s then s = {}; t[k] = s end
		return s
	end
	return function(set, mhSkill, ohSkill)
		local r, mh, oh = set[S.RANGED] or NONE, set[S.MAINHAND] or NONE, set[S.OFFHAND] or NONE
		if mhSkill == nil and ohSkill == nil then
			mhSkill, ohSkill = meleeSkillsOf(set)
		elseif mhSkill == nil or ohSkill == nil then
			error("HunterGearAdvisor: a weapon run with one hand's melee skill: " .. tostring(mhSkill) .. ", " .. tostring(ohSkill), 2)
		end
		local bySkill = sub(sub(sub(sub(cache, r), mh), oh), mhSkill)
		local run = bySkill[ohSkill]
		if run == nil then
			local p = {}
			for k, v in pairs(model) do p[k] = v end
			for k, v in pairs(ns.Player.WeaponInputs(set)) do p[k] = v end
			p.mhSkill, p.ohSkill = mhSkill, ohSkill
			local t, hits = ns.Model.TotalAndHits(p)
			run = { (t - total) / unitDps, hits }
			bySkill[ohSkill] = run
		end
		return run[1], run[2]
	end
end

-- A Use buff up or unknown, or a stat-lowering aura up or unknown (Player.ReadStats; raid-mode design 25.6), gives a
-- state built from the last reading of the same gear and talents (snap.statsStaleBy "useBuff" or "debuff") or, with no
-- such reading, a refused snapshot (that reason). Either holds until the aura falls, which none of the events
-- Commands.lua re-evaluates on marks. So while the last A.State ended either way (useBuffWait: the reason), the aura
-- state of that reason is checked every RETRY_AFTER with C_Timer.After (Forever UITimerDocumentation.lua):
-- Player.UseBuffState or Player.StatDebuffState (WAIT_STATE), the answer ReadStats takes. With such an aura up or
-- unknown, ReadStats takes no new reading (it gives the last one or refuses), and the level, gear and talents it keys
-- the last reading on come with events Commands.lua re-evaluates on, so the check only waits another RETRY_AFTER; once
-- every aura of the reason is known to be off, ns.Invalidate re-reads the stats (it redraws the bag marks, the quest
-- marks and the swap banner, which build the state again; a reading that then waits on the other reason starts its own
-- check). The check ends with the first A.State that ends otherwise: the live reading used, the stats hidden, another
-- reason.
local WAIT_STATE = { useBuff = "UseBuffState", debuff = "StatDebuffState" }
local useBuffWait
local useBuffCheck -- a check is pending (one C_Timer.After at a time)
local function checkUseBuff()
	if useBuffCheck then return end
	useBuffCheck = true
	C_Timer.After(RETRY_AFTER, function()
		useBuffCheck = false
		if not useBuffWait then return end
		if ns.Player[WAIT_STATE[useBuffWait]]() == false then
			ns.Invalidate()
		else
			checkUseBuff()
		end
	end)
end

function A.State()
	if state then return state end
	if failedAt and GetTime() - failedAt < RETRY_AFTER then return nil end
	local snap, why = ns.Player.Snapshot()
	if not snap then
		A.notReadyReason = why
		failedAt = GetTime()
		useBuffWait = WAIT_STATE[why] and why or nil
		if useBuffWait then checkUseBuff() end
		return nil
	end
	failedAt = nil
	A.notReadyReason = nil
	useBuffWait = WAIT_STATE[snap.statsStaleBy] and snap.statsStaleBy or nil
	if useBuffWait then checkUseBuff() end
	-- the skill a ranged weapon of another type is measured against (rangedSkillPiece): the worn ranged
	-- weapon's line, its live skill (shown) and its trained skill (skill: the live skill less the worn set's
	-- bonuses to that line, which Score.SetValue counts on each set); with no bow, gun or crossbow worn, the
	-- model's own assumption of 5 skill points per level (Core/Model.lua baseMiss): no shot is cast (Model.Parts
	-- noShots), and a set without shots has the level's skill (Score.SetValue), the worn set too. That covers a
	-- worn thrown weapon (no shot is cast with it, and the model counts no thrown attack) and a ranged-slot item of
	-- another item class than 2 (Weapon), which is no ranged weapon (Player.isWeapon): Egan's Blaster 13289 (class
	-- 12) and Replica Ironforge Air Rifle 281060 (class 15), InventoryType 26 in Forever Item.csv build 70888, have no
	-- weapon skill line.
	local ranged = snap.equipped[S.RANGED]
	local rangedSkill
	if ranged and ranged.classID == 2 then
		local line = ns.Player.WeaponSkillLine(ranged)
		if not line then error("HunterGearAdvisor: worn ranged item without a weapon skill line: " .. tostring(ranged.name)) end
		local key = ns.Score.RangedSkillStat(ranged)
		if key then
			local live = ns.Player.WeaponSkill(line)
			rangedSkill = { line = line, shown = live, skill = live - ns.Score.SkillBonus(snap.equipped, key, ns.SetData, ns.Player.HasSkillRank) }
		end
	end
	if not rangedSkill then rangedSkill = { shown = 5 * snap.level, skill = 5 * snap.level } end
	-- the worn ranged weapon's skill bonus over the level's maximum 5 x level (wowsims sim/core/weapon_skill.go:10-29
	-- GetWeaponSkill; 0 with no bow, gun or crossbow worn, as above)
	local rangedBonus = rangedSkill.shown - 5 * snap.level
	-- The model point: the worn state as it fights. Score.SetValue takes the live hit and the live ranged crit to
	-- leave the worn ranged weapon skill out (the comment above its ranged weapon skill), so the model takes the skill
	-- apart, by wowsims' attack table (raid-mode W1 design 3.3): the ranged hand's bonus p.rangedSkill (its crit
	-- suppression and the pet's ranged crit branch, Model.Parts) and the shots' own hit against the level's skill,
	-- p.rangedHit = Model.SkillHit at the model point's mob level difference (the mode's target: 0 below 60, 3 at 60,
	-- Player.Snapshot); p.crit stays the sheet's. The weights, weaponGain and modelGain all run at this point.
	-- The weights come from the worn set: with no bow, gun or crossbow worn (an empty ranged slot, a thrown
	-- weapon, Egan's Blaster 13289) the model casts no shot (Model.Parts noShots), so every W prices a hunter
	-- without shots, for a bag bow's own stats and every other piece too. The swap plan's first step puts the bag
	-- bow on (Score.Plan takes the biggest single gain first, and the bow's weaponGain runs the model with the
	-- bow's shots, so its gain holds every shot); the next State, with the bow worn, prices with shots.
	local model = {}
	for k, v in pairs(snap.model) do model[k] = v end
	model.rangedSkill = rangedBonus
	model.rangedHit = ns.Model.SkillHit(model.mobDiff, rangedBonus)
	-- The worn hands' melee weapon skill (raid-mode W1 design 3.4): each hand's weapon of a melee line (Score.MeleeSkillStat)
	-- at its line's live skill (Player.WeaponSkill) less 5 x level, 0 for a hand without one (Score.MeleeSkills); the main
	-- hand's skill hit p.meleeHit = Model.SkillHit at the model point's mob level difference
	local meleeSkill = {}
	local function wornHand(slot)
		local weapon = snap.equipped[slot]
		if not ns.Score.MeleeSkillStat(weapon) then return { shown = 5 * snap.level, trained = 5 * snap.level } end
		local line = ns.Player.WeaponSkillLine(weapon)
		local key = ns.Score.MeleeSkillStat(weapon)
		local live = ns.Player.WeaponSkill(line)
		return { line = line, shown = live, trained = live - ns.Score.SkillBonus(snap.equipped, key, ns.SetData, ns.Player.HasSkillRank) }
	end
	meleeSkill.mh, meleeSkill.oh = wornHand(S.MAINHAND), wornHand(S.OFFHAND)
	model.mhSkill = meleeSkill.mh.shown - 5 * snap.level
	model.ohSkill = meleeSkill.oh.shown - 5 * snap.level
	model.meleeHit = ns.Model.SkillHit(model.mobDiff, model.mhSkill)
	local W, unitDps, total, unit = ns.Model.Weights(model)
	-- the hit cap follows the target (the user, 2026-11-17: no override): the base miss of the model point's mob level
	-- difference (Model.HitCap), 5% against the hunter's own level below 60, 8% against the raid boss at 60 (the client's
	-- CR_HUNTER_HIT_CAP_TOOLTIP, GlobalStrings 60052)
	local cap = ns.Model.HitCap(model.mobDiff)
	local ctx
	local weaponModel = weaponModelFor(model, total, unitDps, function(set) return ns.Score.MeleeSkills(set, ctx) end)
	local function landedHitsFor(set, mhSkill, ohSkill)
		local _, hits = weaponModel(set, mhSkill, ohSkill)
		return hits
	end
	-- the trained skill of a melee weapon's line over the level's maximum: its live skill less the worn set's bonuses to it
	-- (the rule the ranged line's trained skill follows), less 5 x level; one reading a line per State
	local trainedOf = {}
	local function meleeTrained(weapon)
		local line = ns.Player.WeaponSkillLine(weapon)
		local trained = trainedOf[line]
		if trained == nil then
			local key = ns.Score.MeleeSkillStat(weapon)
			trained = ns.Player.WeaponSkill(line) - ns.Score.SkillBonus(snap.equipped, key, ns.SetData, ns.Player.HasSkillRank)
				- 5 * snap.level
			trainedOf[line] = trained
		end
		return trained
	end
	ctx = {
		-- the mode of the model point (Player.Snapshot: raid at 60, levelling below), by which Score.SetValue prices the Use
		-- buffs: over their average uptime while levelling, through the raid fight in raid mode (ctx.useGain, ctx.useUptime)
		mode = model.mode,
		equipped = snap.equipped, pool = snap.pool, dualWield = snap.dualWield,
		-- the base hit: the live hit less the worn gear's ranged-only hit and the worn items' and the worn set bonuses'
		-- hit, as it is (a hit debuff, or hit HGA counts that the game does not apply, makes it negative). The live hit
		-- holds the worn items' hit, the worn set bonuses' hit and the worn gear's ranged-only hit (Player.Snapshot
		-- rangedGearHit), never a Use buff of Game/UseData.lua (Player.ReadStats); the rest (talents, racials, buffs) stays
		-- with any set, so the worn set's hit in Score.SetValue is the live hit; a set's ranged-only hit is its items'
		-- and set bonuses' alone
		hitCap = cap, baseHit = snap.liveHit - snap.rangedGearHit - snap.gearHit - snap.setHit,
		-- the hit of every attack the model runs every set's weapons at (weaponGain): the worn set's
		wornHit = snap.model.hit,
		-- the base spell hit (the live spell hit less the worn items' and set bonuses' SPELL_HIT, Player.Snapshot) and the
		-- trap's spell hit cap (Model.TrapHitCap), which Score prices each set's spell hit with
		baseSpellHit = snap.model.spellHit - snap.gearSpellHit,
		spellHitCap = ns.Model.TrapHitCap(model.mobDiff, model.tal.survivalTactics),
		pools = snap.pools, secondaryRates = ns.Model.SecondaryRates(snap.model.tal),
		weaponGain = function(set, mhSkill, ohSkill) return (weaponModel(set, mhSkill, ohSkill)) end,
		-- the landed hits of each set's own model point, which Score prices that set's procs on (Score.LandedHitsOf)
		landedHitsFor = landedHitsFor,
		-- set bonuses; a set whose ItemSet row requires a profession counts only at the row's rank of it
		sets = ns.SetData, hasSkill = ns.Player.HasSkillRank,
		-- the worn ranged line's trained skill over the level's maximum (0 with none worn) and the target, which Score prices
		-- each set's ranged skill against (Score.SetValue: b = skillBase + the set's points for its line)
		skillBase = rangedSkill.skill - 5 * snap.level, mobDiff = model.mobDiff,
		-- each set's melee weapon skills (Score.MeleeSkills): a line's trained skill over the level's maximum, and the worn
		-- main hand's skill hit the weapon run holds (Score.SetValue's dual-wield part beyond it)
		meleeTrained = meleeTrained, wornMeleeHit = model.meleeHit,
		-- the mob's dodge at this point's mob level (Model.MobAvoid), where the hawks, the pet and the melee swings clamp
		-- expertise, and the expertise past which the model adds nothing: the tanking pet's parry (Model.PetParry) while the
		-- pet tanks (Model.PetTanks: levelling; in raid mode the pet is behind the boss), else the dodge; Score prices every
		-- set's expertise in two slopes up to them
		expertiseCap = ns.Model.MobAvoid(model.mobDiff),
		parryCap = ns.Model.PetTanks(model.mode) > 0 and ns.Model.PetParry(model.mobDiff) or ns.Model.MobAvoid(model.mobDiff),
		-- the outcome of a proc's damage at this point by its table (Model.ProcOutcomes): the worn set's (/hga dump)
		procOutcome = ns.Model.ProcOutcomes(model),
	}
	-- The outcome of a set's procs (Score.SetValue, Score.ProcValue): a proc spell's melee and ranged tables are the main
	-- hand's entry of the weapons the hunter holds (wowsims sim/core/target.go:606-615 Hand; the attack tables rebuilt with
	-- each weapon change, sim/core/weapon_skill.go:85-94 UpdateAttackTableWeapons), so each set's procs roll at its own main
	-- hand's skill (Score.MeleeSkills), the other inputs the model point's (approximation A6): Model.ProcOutcomes at the
	-- model point with that skill, one run a skill. The worn main hand's skill gives ctx.procOutcome itself
	local outcomeOf = { [model.mhSkill] = ctx.procOutcome }
	ctx.procOutcomeFor = function(mhSkill)
		local o = outcomeOf[mhSkill]
		if o == nil then
			local p = {}
			for k, v in pairs(model) do p[k] = v end
			p.mhSkill = mhSkill
			o = ns.Model.ProcOutcomes(p)
			outcomeOf[mhSkill] = o
		end
		return o
	end
	-- the worn set's landed hits by hand and each hand's speed (the model point's own, Model.LandedHits(model)): the
	-- hits A.ModelProcRates prices a worn item in its slot and an item placed in no set on, and /hga dump lists
	ctx.landedHits = landedHitsFor(snap.equipped)
	-- Raid mode: a set's Use buffs through the raid fight at the model point (raid-mode design 6.8; approximation A6, the
	-- set's other stats left out): ctx.useGain(set), their gain in the weights' unit (Model.Total with p.uses, the buffs in
	-- their windows from 5 s, against the point's total), and ctx.useUptime(set), each buff's share of the fight's weighted
	-- time (Model.UseUptimes), which Score.SetValue prices their hit, spell hit and expertise at. One run a distinct list of
	-- buffs in their firing order (Score.SetUses: the order decides which burst buff waits for the other), a set with none
	-- 0 and no share
	if model.mode == "raid" then
		local useRuns = {}
		local function useRun(set)
			local uses = ns.Score.SetUses(set)
			local spells = {}
			for i, use in ipairs(uses) do spells[i] = use.spell end
			local key = table.concat(spells, ",")
			local run = useRuns[key]
			if run == nil then
				if uses[1] then
					local p = {}
					for k, v in pairs(model) do p[k] = v end
					p.uses = uses
					run = { (ns.Model.Total(p) - total) / unitDps, ns.Model.UseUptimes(uses) }
				else
					run = { 0, {} }
				end
				useRuns[key] = run
			end
			return run
		end
		ctx.useGain = function(set) return useRun(set)[1] end
		ctx.useUptime = function(set) return useRun(set)[2] end
		-- The change of the fight's consumables' events a set's stats make (raid-mode design 25.1): the weights hold the
		-- model point's events (Model.Weights), so Score.SetValue adds ctx.eventGain(stats), stats the set's amounts of the
		-- stats the fight reads less the worn set's: Model.EventGain at the model point with them applied (Model.ApplyStats)
		-- against its events (Model.FightEvents), in the weights' unit; none, 0. Whether an event changes is the mana's to
		-- decide, whose inputs the stats move by their keys of Model.EventKeys alone (raid-mode design 26.3): stats with none
		-- of them change no event (0, no run), and stats of one projection on them (their amounts of those keys) change one
		-- or none alike, so once a run of the projection found none, every stats table of it gives 0 with no run. Else one
		-- run a distinct stats table (two when an event changes), the gain the whole stats', their other keys in it.
		local events = ns.Model.FightEvents(model)
		local eventKeys = ns.Model.EventKeys(model)
		local eventRuns, deviates = {}, {}
		-- a stats table's keys in order, each with its amount: the key of a run
		local function keyOf(keys, stats)
			table.sort(keys)
			local parts = {}
			for i, k in ipairs(keys) do parts[i] = k .. "=" .. string.format("%.17g", stats[k]) end
			return table.concat(parts, ",")
		end
		ctx.eventGain = function(stats)
			local keys, manaKeys = {}, {}
			for k in pairs(stats) do
				keys[#keys + 1] = k
				if eventKeys[k] then manaKeys[#manaKeys + 1] = k end
			end
			if #manaKeys == 0 then return 0 end
			local manaKey = keyOf(manaKeys, stats)
			if deviates[manaKey] == false then return 0 end
			local key = keyOf(keys, stats)
			local gain = eventRuns[key]
			if gain == nil then
				local q = {}
				for k, v in pairs(model) do q[k] = v end
				ns.Model.ApplyStats(q, stats)
				local g, deviated = ns.Model.EventGain(q, events)
				gain = g / unitDps
				eventRuns[key] = gain
				deviates[manaKey] = deviated
			end
			return gain
		end
	end
	-- unitDps: the DPS one weights' unit adds; unit: its name (Model.Weights: "RAP", "MAP" or "DPS"); meleeSkill: the worn
	-- hands' lines, live skills and trained skills (/hga dump)
	state = { snap = snap, model = model, W = W, unitDps = unitDps, unit = unit, total = total, ctx = ctx, rangedSkill = rangedSkill,
		meleeSkill = meleeSkill }
	return state
end

-- Ranged weapon skill (wowsims' attack table, Model.SkillMiss; Score.SetValue). The
-- live sheet and the model price a set as the worn ranged weapon fights, and Score.SetValue counts the gear's
-- skill bonuses for the line of a set's own ranged weapon against the worn set's. A ranged weapon of another
-- type (bow 45 / gun 46 / crossbow 226) fights with the trained skill of its own line, so it is scored as a copy
-- of its piece with skillOffset = its line's trained skill - the reference's (Score.SetValue adds those points
-- to the set's ranged hit, before the cap, and crit). A line's trained skill: its live skill (Player.WeaponSkill:
-- rank + modifier, the modifier taken to hold the worn gear's skill bonuses) less the worn set's bonuses to that
-- line (Score.SkillBonus), the same rule as the reference's (A.State). A ranged weapon of the worn type fights
-- with the worn line: the piece itself (its own skill bonus counts once, in Score.SetValue). A ranged-slot item
-- of another item class than 2 (Weapon; Egan's Blaster 13289, Replica Ironforge Air Rifle 281060) is no weapon
-- (Player.isWeapon): it has no skill line and counts no skill, the piece itself.
-- The ranged skill's hit and crit are priced at the model's ranged-only weights (W.HIT_RANGED: the shots' hit;
-- W.SKILL_CRIT: a skill point below the level's maximum, Model.Weights). A melee weapon needs no such piece: Score.MeleeSkills
-- takes each hand's skill from its own weapon's line (ctx.meleeTrained), and every set's hands are priced at their skills
-- by the weapon run (weaponModelFor) and the main hand's skill hit at W.HIT_MELEE (Score.SetValue).
local function rangedSkillPiece(st, piece)
	if piece.equipLoc ~= "INVTYPE_RANGED" and piece.equipLoc ~= "INVTYPE_RANGEDRIGHT" then return piece end
	if piece.classID ~= 2 then return piece end
	local line = ns.Player.WeaponSkillLine(piece)
	if not line then error("HunterGearAdvisor: ranged item without a weapon skill line: " .. tostring(piece.name)) end
	local ref = st.rangedSkill
	if line == ref.line then return piece end
	local eq = st.snap.equipped
	local key = ns.Score.RangedSkillStat(piece)
	local function bonus(set) return key and ns.Score.SkillBonus(set, key, st.ctx.sets, st.ctx.hasSkill) or 0 end
	local trained = ns.Player.WeaponSkill(line) - bonus(eq)
	local gap = trained - ref.skill
	-- the skill the Skills frame shows with the piece in the ranged slot: its line's trained skill and that
	-- set's bonuses to the line (the piece's own among them)
	local withPiece = ns.Score.CopySet(eq)
	withPiece[S.RANGED] = piece
	local have = trained + bonus(withPiece)
	if gap == 0 and have == ref.shown then return piece end
	-- skillGap for the tooltip: the skill against the reference as the Skills frame shows them; with the
	-- bonuses Score.SetValue counts on each set, the set with the piece has the skill bonus have - 5 x level.
	-- vsWorn: the reference is the worn ranged weapon's skill (with no bow, gun or crossbow worn: 5 points per level)
	return setmetatable({ skillOffset = gap, skillGap = { line = line, have = have, shown = ref.shown, vsWorn = ref.line ~= nil } },
		{ __index = piece })
end

-- The change of the whole damage model in the weights' unit when some inputs change (from the model point, st.model).
local function modelGain(st, changes)
	local p = {}
	for k, v in pairs(st.model) do p[k] = v end
	for k, v in pairs(changes) do p[k] = v end
	return (ns.Model.Total(p) - st.total) / st.unitDps
end

local function pieceFor(st, rec, where)
	if where and where.kind == "bag" then
		for _, p in ipairs(st.snap.bagPieces) do
			if p.where.bag == where.bag and p.where.slot == where.slot and p.link == rec.link then return p end
		end
		return ns.Items.Piece(rec, where)
	end
	if not where then
		for _, p in ipairs(st.snap.bagPieces) do
			if p.link == rec.link then return p end
		end
	end
	return ns.Items.Piece(rec, where or { kind = "new" })
end

local function keyFor(link, where)
	if not where then return link end
	return link .. "@" .. (where.kind or "?") .. ":" .. tostring(where.bag) .. ":" .. tostring(where.slot)
end

local NOT_GEAR = {
	[""] = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
}

-- A bow/crossbow and a gun use different ammo and a different quiver. The weapon is scored as
-- if fitting ammo and a fitting quiver were there (user, 2026-11-12: "стрелы не должны влиять,
-- только пометка, что нет стрел; подсумок тоже — это уже моя забота"): only notes are added.
local function rangedSwitch(st, cand, res)
	local eqR = st.snap.equipped[S.RANGED]
	local fNew = ns.Player.AmmoFamily(cand)
	if not fNew then return end
	if eqR and ns.Player.AmmoFamily(eqR) == fNew then return end
	local qp = st.snap.quiverPiece
	res.familySwitch = {
		family = fNew,
		noAmmo = st.snap.bagAmmo[fNew] == nil,
		quiverMismatch = qp ~= nil and ns.Player.QuiverFamily(qp) ~= fNew,
	}
end

-- Result: { usable, reason, delta, dps, survival, isUpgrade, equippedSlot, hand, mh, oh, swapFrom2H,
--           betterOther, familySwitch, quiverHaste, aboveLevel, rec }. nil while data is not ready.
function A.Evaluate(link, where)
	if not link then return nil end
	local key = keyFor(link, where)
	local cached = results[key]
	if cached then return cached end

	local st = A.State()
	if not st then return nil end
	local rec = ns.Items.Get(link)
	if not rec then return nil end

	local res = { rec = rec }
	local eqSlot = st.snap.links[link]
	local worn = (where and where.kind == "equipped") or (not where and eqSlot ~= nil)
	-- quivers and ammo pouches: item class 11; in Forever their equipLoc is INVTYPE_BAG
	-- (Item.csv InventoryType 18 for all 41 of them), so the class decides, not the slot type
	local isQuiver = ns.Player.QuiverFamily(rec) ~= nil
	if worn then
		res.equippedSlot = (where and where.slot) or eqSlot
		res.usable = true
		res.delta = 0
	elseif NOT_GEAR[rec.equipLoc] and not isQuiver then
		res.notGear = true
	else
		local ok, reason = ns.Player.CanUse(rec, st.snap.equipped[S.RANGED])
		res.usable = ok
		res.reason = reason
		if ok and isQuiver then
			local haste = rec.stats.QUIVER_HASTE or 0
			res.quiverHaste = haste
			res.delta = modelGain(st, { quiver = math.min(0.15, haste / 100) })
			res.dmgAdjust = res.delta
		elseif ok then
			local cand = rangedSkillPiece(st, pieceFor(st, rec, where))
			res.skillGap = cand.skillGap
			local r = ns.Score.Evaluate(cand, st.W, st.ctx)
			if r then
				for k, v in pairs(r) do res[k] = v end
				if rec.equipLoc == "INVTYPE_RANGED" or rec.equipLoc == "INVTYPE_RANGEDRIGHT" then
					rangedSwitch(st, cand, res)
				end
			else
				res.usable = false
				res.reason = res.reason or "не надевается в доступный слот"
			end
		end
	end
	if res.delta then
		-- delta = damage only (the weights' unit, Model.Weights), dps = the DPS of it; survival / mana come apart, as %
		-- of the pools
		res.dps = res.delta * st.unitDps
		if res.newSet then
			res.sec, res.secHp, res.secMana = ns.Score.Secondary(res.newSet, st.ctx)
		else
			res.sec, res.secHp, res.secMana = 0, 0, 0
		end
		res.verdict = ns.Score.Verdict(res.delta, res.sec)
		res.isUpgrade = res.usable and not res.equippedSlot and (res.verdict == "better" or res.verdict == "better2")
	end
	res.aboveLevel = rec.reqLevel and rec.reqLevel > st.snap.level
	results[key] = res
	return res
end

-- The slot kind (Score.SlotKind) of an item's equipLoc, for an item the evaluation puts in no slot (one the character
-- cannot wear): the hand or slot it goes into, a one-hander the main hand. Every other equipLoc (armor, a trinket, a
-- quiver's INVTYPE_BAG) is "armor", the kind of every slot outside the hands, the ranged slot and the ammo slot. An item
-- record's equipLoc is C_Item.GetItemInfoInstant's itemEquipLoc (Items.Get), a string that is never nil (Forever
-- Blizzard_APIDocumentationGenerated/ItemDocumentation.lua: Nilable = false), "" for an item that is not worn.
local EQUIP_KIND = {
	INVTYPE_2HWEAPON = "2h", INVTYPE_WEAPON = "mh", INVTYPE_WEAPONMAINHAND = "mh", INVTYPE_WEAPONOFFHAND = "oh",
	INVTYPE_HOLDABLE = "oh", INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "ranged",
	INVTYPE_AMMO = "ammo",
}

-- The procs per minute of each damage proc of a result's item (Score.ProcRate, in rec.procs' order) in the set the
-- result scores it in, on that set's landed hits: a worn item in its slot of the worn set (ctx.landedHits); an item
-- A.Evaluate places (Score.Evaluate: a weapon in the hand of its best hands, res.newSet with res.slot its hand; any
-- other piece in res.slot of res.newSet) in that slot of res.newSet (Score.LandedHitsOf); an item placed in no set (one
-- the character cannot wear, one no slot takes, a quiver) in the slot its equipLoc names (EQUIP_KIND), on the worn
-- set's hits, each hand at the worn weapon's speed there. The second value names the hits: "worn", the worn set's (a
-- worn item, an item placed in no set), or "newSet", the hits of res.newSet, the set the item is placed in. The third is
-- the procs' outcome there (Model.ProcOutcomes, as Score.SetValue prices the set's procs: ctx.procOutcomeFor of the set's
-- main hand skill, Score.MeleeSkills; the worn set's, ctx.procOutcome, for the worn hits). nil for an item without a
-- damage proc, or while the state is not ready.
function A.ModelProcRates(res)
	local rec = res.rec
	if #rec.procs == 0 then return nil end
	local st = A.State()
	if not st then return nil end
	local slot, hits, hitsOf, outcome
	if res.equippedSlot then
		slot, hits, hitsOf, outcome = res.equippedSlot, st.ctx.landedHits, "worn", st.ctx.procOutcome
	elseif res.newSet then
		if not res.slot then error("HunterGearAdvisor: a result with a set and no slot: " .. tostring(rec.name)) end
		local mhSkill, ohSkill = ns.Score.MeleeSkills(res.newSet, st.ctx)
		slot, hits, hitsOf = res.slot, ns.Score.LandedHitsOf(res.newSet, st.ctx, mhSkill, ohSkill), "newSet"
		outcome = st.ctx.procOutcomeFor(mhSkill)
	else
		hits, hitsOf, outcome = st.ctx.landedHits, "worn", st.ctx.procOutcome
	end
	local kind = slot and ns.Score.SlotKind(slot, rec) or EQUIP_KIND[rec.equipLoc] or "armor"
	local rates = {}
	for i, p in ipairs(rec.procs) do rates[i] = ns.Score.ProcRate(rec, kind, p, hits) end
	return rates, hitsOf, outcome
end

-- With a 2H equipped: the best pair of one-handers from the bags versus the 2H.
function A.BestPairVs2H()
	local st = A.State()
	if not st then return nil end
	local eq = st.ctx.equipped
	if not ns.Score.IsTwoHand(eq[S.MAINHAND]) then return nil end
	local pool = {}
	for _, p in ipairs(st.ctx.pool) do
		if not ns.Score.IsTwoHand(p) then pool[#pool + 1] = p end
	end
	local noHands = {}
	for k, v in pairs(eq) do noHands[k] = v end
	noHands[S.MAINHAND], noHands[S.OFFHAND] = nil, nil
	local best = ns.Score.BestHands(nil, noHands, pool, st.W, st.ctx)
	if not best or (not best.mh and not best.oh) then return nil end
	local current = ns.Score.SetValue(eq, st.W, st.ctx)
	local delta = best.value - current
	local sec, secHp, secMana = ns.Score.Secondary(best.set, st.ctx)
	return { mh = best.mh, oh = best.oh, delta = delta, dps = delta * st.unitDps, sec = sec, secHp = secHp,
		secMana = secMana, verdict = ns.Score.Verdict(delta, sec) }
end

-- Bag items the swap banner may suggest: gear for a character slot that can be put on now.
-- Ammo is the user's own business (user, 2026-11-12) and quivers go into a bag slot, not here.
local function planCandidate(st, p)
	local loc = p.equipLoc
	if NOT_GEAR[loc] or loc == "INVTYPE_AMMO" then return false end
	if ns.Player.QuiverFamily(p) then return false end
	if p.reqLevel and p.reqLevel > st.snap.level then return false end
	return (ns.Player.CanUse(p, st.snap.equipped[S.RANGED]))
end

-- A plan row that takes its slot's item off by itself (row.takeOff): a slot the plan empties that the game does not empty
-- on its own when another row of the plan goes on. The game takes the off hand off when a two-hander goes into the main
-- hand, and a worn two-hander off when an item goes into the off hand (Swap's rows say so); a slot whose worn item another
-- row moves to another slot (row.movesTo) loses it by that row, which picks it up from there (Swap.EquipRow, as Blizzard's
-- EquipmentManager_EquipInventoryItem, Mainline/EquipmentManager.lua:118-131); every other emptied slot is the plan's own
-- step, part of what to wear (the Survival weave's off hand that swings in no visit, Core/Model.lua weaveParts; an empty
-- main hand that gives the pet its whole melee crit, Model petCritBase).
local function takesOff(eq, target, row)
	if row.new ~= nil or row.movesTo ~= nil then return false end
	if row.slot == S.OFFHAND then return not ns.Score.IsTwoHand(target[S.MAINHAND]) end
	if row.slot == S.MAINHAND then return not (ns.Score.IsTwoHand(eq[S.MAINHAND]) and target[S.OFFHAND] ~= nil) end
	return true
end

-- Swap plan for the banner: { rows = { { slot, new, old, gain | pairPart, key, familySwitch, takeOff } },
-- fromBags, takeOffs, delta, dps, sec, secHp, secMana, verdict }. rows is empty when nothing is worth putting on or taking
-- off. row.gain = what the row adds inside the plan (Score.RowGains; both hands as one unit); row.key = "slot=link" of
-- the item put on, "slot=-link" of the item a take-off row takes off (no bag position, so sorting the bags keeps it);
-- row.takeOff = the row takes its item off by itself (takesOff); row.movesTo = the slot another row moves the slot's worn
-- item to, on a row that puts nothing on (row.moveDisplaces: that slot holds an item now). fromBags = rows whose item comes
-- from the bags, takeOffs = take-off rows. nil while data is not ready.
function A.Plan()
	local st = A.State()
	if not st then return nil end
	if st.plan then return st.plan end
	local cands = {}
	for _, p in ipairs(st.snap.bagPieces) do
		-- a ranged weapon of another type is planned with its weapon skill (rangedSkillPiece)
		if planCandidate(st, p) then cands[#cands + 1] = rangedSkillPiece(st, p) end
	end
	local eq = st.ctx.equipped
	local target = ns.Score.Plan(eq, cands, st.W, st.ctx)
	local rows = ns.Score.PlanRows(eq, target)
	local plan = { rows = rows, fromBags = 0, takeOffs = 0 }
	if #rows > 0 then
		local delta = ns.Score.SetValue(target, st.W, st.ctx) - ns.Score.SetValue(eq, st.W, st.ctx)
		plan.delta, plan.dps = delta, delta * st.unitDps
		plan.sec, plan.secHp, plan.secMana = ns.Score.Secondary(target, st.ctx)
		plan.verdict = ns.Score.Verdict(delta, plan.sec)
		ns.Score.RowGains(eq, target, rows, st.W, st.ctx)
		-- the slot each worn item the plan moves goes to (a weapon to the other hand): its piece keeps the slot it is worn in
		local movedTo = {}
		for _, row in ipairs(rows) do
			if row.new and row.new.where.kind == "equipped" then movedTo[row.new.where.slot] = row.slot end
		end
		for _, row in ipairs(rows) do
			if row.gain then row.gain.dps = row.gain.delta * st.unitDps end
			if row.new == nil and movedTo[row.slot] then
				row.movesTo = movedTo[row.slot]
				row.moveDisplaces = eq[row.movesTo] ~= nil
			end
			row.takeOff = takesOff(eq, target, row)
			if row.takeOff then plan.takeOffs = plan.takeOffs + 1 end
			row.key = row.slot .. "=" .. (row.new and row.new.link or ("-" .. row.old.link))
			if row.new and row.new.where.kind == "bag" then
				plan.fromBags = plan.fromBags + 1
				-- bow <-> gun: notes about ammo and quiver, as in the tooltip
				if row.slot == S.RANGED then
					local res = A.Evaluate(row.new.link, row.new.where)
					if not res then return nil end
					row.familySwitch = res.familySwitch
				end
			end
		end
	end
	st.plan = plan
	return plan
end

-- the equipLocs of a melee weapon, whose tooltip names the Survival weave's cycle with it (A.Explain)
local MELEE_WEAPON_LOC = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true }
-- the skill line of a melee skill stat (Score.MELEE_SKILL's keys by weapon subclass, Player.WeaponSkillLine's lines), and
-- the keys in subclass order
local LINE_OF_SKILL, MELEE_SKILL_KEYS = {}, {}
for sub = 0, 20 do
	local key = ns.Score.MELEE_SKILL[sub]
	if key then
		LINE_OF_SKILL[key] = ns.Player.WeaponSkillLine({ classID = 2, subclassID = sub })
		MELEE_SKILL_KEYS[#MELEE_SKILL_KEYS + 1] = key
	end
end
local function fmt(v) return string.format("%.1f", v) end
local function signed(v) return (v >= 0 and "+" or "") .. fmt(v) end
local GREEN, RED, GREY = { 0.25, 1, 0.25 }, { 1, 0.45, 0.45 }, { 0.7, 0.7, 0.7 }

-- "здоровье +4.7%, мана +23.2%" (only the non-zero parts)
local function secText(hp, mana)
	local parts = {}
	if math.abs(hp or 0) >= 0.05 then parts[#parts + 1] = "здоровье " .. signed(hp) .. "%" end
	if math.abs(mana or 0) >= 0.05 then parts[#parts + 1] = "мана " .. signed(mana) .. "%" end
	return table.concat(parts, ", ")
end

-- Main verdict line(s) for a result with delta / sec / verdict (damage first).
local function verdictLines(add, r, prefix)
	local v = r.verdict
	local s = secText(r.secHp, r.secMana)
	if v == "better" then
		add(string.format("%sусиление +%s (~ %s DPS)", prefix, fmt(r.delta), signed(r.dps)), GREEN)
	elseif v == "worse" then
		add(string.format("%sхуже надетого на %s (~ %s DPS)", prefix, fmt(-r.delta), signed(r.dps)), RED)
	elseif v == "better2" then
		add(prefix .. "урон как у надетого, но лучше: " .. s, GREEN)
	elseif v == "worse2" then
		add(prefix .. "урон как у надетого, но хуже: " .. s, RED)
	else
		add(prefix .. "примерно как надетое", GREY)
	end
	if (v == "better" or v == "worse") and s ~= "" then
		add((prefix:match("^HGA: ") and "HGA: " or "") .. s .. " (решает только при равном уроне)", GREY)
	end
end

-- The same verdict lines for the swap banner: { { text, r, g, b } }.
function A.GainLines(r, prefix)
	local out = {}
	verdictLines(function(text, c) out[#out + 1] = { text, c[1], c[2], c[3] } end, r, prefix or "")
	return out
end
local function nameOf(item) return item and (item.name or "?") or "пусто" end
local function fromBag(item) return item and item.where and item.where.kind == "bag" end
local function wornIn(item, slot) return item and item.where and item.where.kind == "equipped" and item.where.slot == slot end

-- Why there is no evaluation right now (A.State() gave nil), for the tooltip and /hga (weights, dump, swap); the swap
-- banner stays hidden without a plan (Swap.Refresh).
local NOT_READY = {
	hidden = "игра сейчас скрывает статы персонажа — оценка появится после боя",
	talents = "таланты ещё не прочитаны из игры — оценка появится, когда клиент их отдаст",
	staged = "таланты изменены, но не применены — оценка появится после «Применить»",
	useBuff = "действует бафф «Использования» вещи (или игра его скрывает) — оценка появится, когда он спадёт",
	debuff = "на персонаже аура, снижающая статы (Resurrection Sickness и т. п., или игра её скрывает) — оценка появится, когда она спадёт",
}
function A.NotReadyText()
	return NOT_READY[A.notReadyReason] or "данные предметов ещё грузятся"
end

-- "(2), (3)": each piece count once, in list order (SetData lists bonuses in piece order); one piece count
-- can carry several bonus spells (Blood Tiger Harness 442: 7597 and 18384 at 2 pieces).
local function thresholds(list)
	local parts, seen = {}, {}
	for _, n in ipairs(list) do
		if not seen[n] then
			seen[n] = true
			parts[#parts + 1] = "(" .. n .. ")"
		end
	end
	return table.concat(parts, ", ")
end

-- The set line of an item that belongs to an item set: pieces worn (and with this item, for one that
-- is not worn), the bonuses HGA counts in the set the evaluation ends with, the bonuses it never
-- counts (Game/SetData.lua entries without stats). Returns the text and the number of bonuses not
-- counted (for the "эффекты не учтены" note). A set missing from SetData: every set bonus line of
-- the tooltip (Parse kind "set") is not counted. A set without bonuses (no ItemSetSpell row, e.g. 1969
-- Goliaths' Adaptive Garments) says so. A set whose profession rank the player lacks gives no bonus
-- (Score.SetBonuses needsSkill / needsRank); the line names the rank and the player's (Player.SkillRank), or says
-- the profession is not learned by the rule of Player.HasSkill (no info, or rank 0 and maxRank 0).
local function setLine(st, res)
	local rec = res.rec
	local ctx = st.ctx
	local def = ctx.sets[rec.setID]
	if not def then
		local lines = 0
		for _, e in ipairs(rec.effects) do
			if e.kind == "set" then lines = lines + 1 end
		end
		return "HGA: комплект неизвестен HGA — его бонусы не учтены (смотри сам)", lines
	end
	local _, worn = ns.Score.SetBonuses(st.snap.equipped, ctx.sets, ctx.hasSkill)
	local wornInfo = worn[rec.setID]
	local text = "HGA: комплект: надето " .. (wornInfo and wornInfo.count or 0)
	local info = wornInfo
	if res.newSet and not res.equippedSlot then
		local _, after = ns.Score.SetBonuses(res.newSet, ctx.sets, ctx.hasSkill)
		info = after[rec.setID]
		text = text .. ", с этой вещью " .. (info and info.count or 0)
	end
	if #def == 0 then
		text = text .. "; у комплекта нет бонусов"
	elseif def.skill and not ctx.hasSkill(def.skill, def.skillRank) then
		local have = ns.Player.HasSkill(def.skill) and ns.Player.SkillRank(def.skill) or nil
		text = text .. "; бонусы только с профессией комплекта на " .. def.skillRank
			.. (have == nil and " — она не изучена" or (" — у тебя " .. have))
	elseif info and #info.counted > 0 then
		text = text .. "; учтены бонусы " .. thresholds(info.counted)
	elseif not info or #info.notCounted == 0 then
		text = text .. "; бонусы ещё не действуют"
	end
	local never = {}
	for _, b in ipairs(def) do
		if not b.stats then never[#never + 1] = b.n end
	end
	if #never > 0 then text = text .. "; не учитываются " .. thresholds(never) end
	return text, #never
end

-- The lead of a proc line's procs per minute by the hits A.ModelProcRates prices them on (its second value): the worn
-- set's hits, as the character attacks now; the hits of res.newSet, the set the item is placed in, once it is put on.
local RATE_HITS_TEXT = { worn = "с твоими атаками сейчас ~", newSet = "если надеть — ~" }

-- The form of a Russian noun after a whole count n: one (1, 21, 31 ...: "1 тик"), few (2-4, 22-24 ...: "3 тика"), many
-- (0, 5-20, 25-30 ...: "7 тиков"; 11-14 take many), the three forms the ruRU client strings' plural markers name
-- ("|4ячейка:ячейки:ячеек;", Core/Parse.lua resolvePlurals: a marker seen unresolved in game, so the addon picks the
-- form itself)
local function ruPlural(n, one, few, many)
	local d10, d100 = n % 10, n % 100
	if d10 == 1 and d100 ~= 11 then return one end
	if d10 >= 2 and d10 <= 4 and (d100 < 12 or d100 > 14) then return few end
	return many
end
A.RuPlural = ruPlural

-- Lines for the tooltip: list of { text, r, g, b }.
function A.Explain(link, where)
	local res = A.Evaluate(link, where)
	if not res then
		if A.State() then return { { "HGA: данные предмета ещё грузятся", 0.6, 0.6, 0.6 } } end
		return { { "HGA: " .. A.NotReadyText(), 0.6, 0.6, 0.6 } }
	end
	if res.notGear then return {} end
	local st = A.State()
	local out = {}
	local function add(text, r, g, b)
		if type(r) == "table" then r, g, b = r[1], r[2], r[3] end
		out[#out + 1] = { text, r, g, b }
	end
	local yellow = { 0.9, 0.9, 0.6 }
	local function addY(text) add(text, yellow[1], yellow[2], yellow[3]) end

	if res.equippedSlot then
		if res.equippedSlot == S.MAINHAND and ns.Score.IsTwoHand(res.rec) then
			local pair = A.BestPairVs2H()
			if pair then
				addY(string.format("HGA: лучшая пара из сумок вместо двуручного: %s (ПР) + %s (ЛР)", nameOf(pair.mh), nameOf(pair.oh)))
				verdictLines(add, pair, "HGA: эта пара — ")
			else
				add("HGA: в сумках нет одноручного оружия для пары", 0.6, 0.6, 0.6)
			end
		end
	elseif not res.usable then
		add("HGA: нельзя надеть — " .. (res.reason or "?"), 0.6, 0.6, 0.6)
	elseif res.delta then
		verdictLines(add, res, "HGA: ")

		if res.hand == "2h" then
			addY("HGA: двуручное — вместо обеих рук")
		elseif res.hand == "mh" then
			-- the other hand of res.newSet: a bag item, the worn main hand moved over, empty where an item is worn (the
			-- evaluation's gain holds taking it off), or the worn item kept
			local extra = ""
			if fromBag(res.oh) then
				extra = ", в левую — " .. nameOf(res.oh) .. " из сумки"
			elseif wornIn(res.oh, S.MAINHAND) then
				extra = ", а текущее правое — в левую"
			elseif res.oh == nil and st.snap.equipped[S.OFFHAND] then
				extra = ", левую руку — снять"
			end
			addY("HGA: надеть в правую руку" .. extra)
		elseif res.hand == "oh" then
			local extra = ""
			if fromBag(res.mh) then
				extra = ", в правую — " .. nameOf(res.mh) .. " из сумки"
			elseif wornIn(res.mh, S.OFFHAND) then
				extra = ", а текущее левое — в правую"
			elseif res.mh == nil and st.snap.equipped[S.MAINHAND] then
				extra = ", правую руку — снять"
			end
			addY("HGA: надеть в левую руку" .. extra)
		end
		-- the Survival weave's cycle with this melee weapon's set against the worn set's, when it changes (Model.Weave at the
		-- model point with each set's weapon inputs, the run weaponModelFor prices the set with): the cycle outside Rapid Fire
		if st.snap.survival and res.newSet and MELEE_WEAPON_LOC[res.rec.equipLoc] then
			local function cycleOf(set)
				local p = {}
				for k, v in pairs(st.model) do p[k] = v end
				for k, v in pairs(ns.Player.WeaponInputs(set)) do p[k] = v end
				local wv = ns.Model.Weave(p)
				return wv and wv.base.C
			end
			local now, with = cycleOf(st.snap.equipped), cycleOf(res.newSet)
			if now and with and math.abs(with - now) > 1e-9 then
				add(string.format("HGA: плетение — цикл %.2f с с этим оружием (было %.2f с)", with, now), 0.7, 0.7, 0.9)
			end
		end
		-- Melee weapon skill (raid-mode W1 design 3.4) of a melee weapon, or of an item with a melee skill stat, in the set
		-- the evaluation puts it in. In the Survival branch the hand it reaches (the weapon's hand; for a skill item the
		-- hand whose weapon holds its line, the main hand first) by wowsims' attack table: that hand's skill with the item
		-- (Score.MeleeSkills of res.newSet) against the worn set's in that hand, its miss change (Model.SkillMiss), its
		-- glance chance and the glance's average damage there (Model.Glance) and its crit change (the suppression's 0.2% a
		-- point below the level's maximum, min(0, 0.2 x bonus)); out of it the hunter has no melee (Model.Parts), and the line
		-- says what the hand's skill still reaches (below)
		if res.newSet then
			local skillKey, line
			local weaponKey = MELEE_WEAPON_LOC[res.rec.equipLoc] and ns.Score.MeleeSkillStat(res.rec)
			if weaponKey then
				skillKey = weaponKey
			else
				-- a skill item's line: among its melee skill stats (an item may carry several: Edgemaster's Handguards 14551
				-- holds Axes, Daggers and Swords in wowsims' Forever database, assets/database/db.json) the line of the new
				-- set's main hand, else of its off hand, else its first in subclass order (a line no hand of the set holds)
				for _, slot in ipairs({ S.MAINHAND, S.OFFHAND }) do
					local key = ns.Score.MeleeSkillStat(res.newSet[slot])
					if not skillKey and key and (res.rec.stats[key] or 0) ~= 0 then skillKey = key end
				end
				for _, key in ipairs(MELEE_SKILL_KEYS) do
					if not skillKey and (res.rec.stats[key] or 0) ~= 0 then skillKey = key end
				end
			end
			if skillKey then line = LINE_OF_SKILL[skillKey] end
			local slot
			if line then
				if weaponKey then
					slot = res.hand == "oh" and S.OFFHAND or S.MAINHAND
				elseif ns.Score.MeleeSkillStat(res.newSet[S.MAINHAND]) == skillKey then
					slot = S.MAINHAND
				elseif ns.Score.MeleeSkillStat(res.newSet[S.OFFHAND]) == skillKey then
					slot = S.OFFHAND
				end
			end
			local L5 = 5 * st.snap.level
			local have, worn
			if slot then
				local newMH, newOH = ns.Score.MeleeSkills(res.newSet, st.ctx)
				have = slot == S.MAINHAND and newMH or newOH
				worn = slot == S.MAINHAND and st.model.mhSkill or st.model.ohSkill
			end
			if line and not st.snap.survival then
				-- Outside the Survival branch the hunter has no melee (Model.Parts), but the main hand's skill still sets the
				-- pet's melee crit branch, 0.04% a point below the level's maximum (wowsims sim/hunter/pets.go:147-153; the pet
				-- takes the higher branch, Model petCritBase), and the main hand's entry of a proc's tables (Model.ProcOutcomes,
				-- ctx.procOutcomeFor); the off hand's skill reaches nothing
				if slot == S.MAINHAND then
					add(string.format("HGA: навык %s %d/%d — своего ближнего боя нет (не ветка Выживания); правой рукой он двигает ветку ближнего боя крита пета (%+.2f%%, в счёт, пока она выше ветки дальнего боя) и таблицу эффектов при попадании",
						ns.Player.SKILL_NAME[line], have + L5, worn + L5, 0.04 * (math.min(have, 0) - math.min(worn, 0))), 0.7, 0.7, 0.9)
				elseif slot == S.OFFHAND then
					add(string.format("HGA: навык %s %d/%d — своего ближнего боя нет (не ветка Выживания); в левой руке он ни на что не влияет",
						ns.Player.SKILL_NAME[line], have + L5, worn + L5), 0.6, 0.6, 0.6)
				else
					add(string.format("HGA: навык %s — ни одна рука набора не держит оружие этой линии: не в счёт", ns.Player.SKILL_NAME[line]), 0.6, 0.6, 0.6)
				end
			elseif slot then
				local d = st.model.mobDiff
				local gChance, gAvg = ns.Model.Glance(d, have)
				add(string.format("HGA: навык %s %d/%d — в ближнем бою (ветка Выживания): промах %+.1f%%, скользящие %d%% по %.0f%%, крит %+.1f%%",
					ns.Player.SKILL_NAME[line], have + L5, worn + L5, ns.Model.SkillMiss(d, have) - ns.Model.SkillMiss(d, worn),
					math.floor(gChance * 100 + 0.5), gAvg * 100, math.min(0, 0.2 * have) - math.min(0, 0.2 * worn)), 0.7, 0.7, 0.9)
			end
		end
		if res.swapFrom2H then
			if res.mh and res.oh then
				addY("HGA: сравнение — эта пара вместо надетого двуручного")
			else
				addY("HGA: сравнение — вместо надетого двуручного, вторая рука пустая")
			end
		end
		if res.betterOther then
			local b = res.betterOther
			addY(string.format("HGA: ещё лучше без этой вещи: %s (ПР) + %s (ЛР): %s", nameOf(b.mh), nameOf(b.oh), signed(b.delta)))
		end
		if res.familySwitch then
			-- notes only: the score already assumes fitting ammo and quiver
			local f = res.familySwitch
			if f.noAmmo then addY("HGA: в сумках нет " .. (f.family == 2 and "стрел" or "пуль") .. " для него") end
			if f.quiverMismatch then addY("HGA: к нему нужен " .. QUIVER_NAME[f.family] .. ", твой не подходит") end
		end
		local g = res.skillGap
		if g and g.have ~= g.shown then
			-- the effective comparison (rangedSkillPiece): against the worn ranged weapon's skill, or with none
			-- worn against the level's 5 points per level; by wowsims' attack table (Model.SkillMiss): the shots' hit
			-- Model.SkillHit of the two bonuses over 5 x level, and their crit suppression's 0.2% a point below the maximum
			-- (Model critSuppressor), -0.2 x max(0, -bonus) = min(0, 0.2 x bonus) for each
			local L5 = 5 * st.snap.level
			local d = st.model.mobDiff
			addY(string.format("HGA: навык %s %d/%d (%s) — меткость выстрелов %+.1f%%, крит выстрелов %+.1f%% (по правилу wowsims)",
				ns.Player.SKILL_NAME[g.line], g.have, g.shown,
				g.vsWorn and "против надетого" or "против навыка уровня",
				ns.Model.SkillHit(d, g.have - L5) - ns.Model.SkillHit(d, g.shown - L5),
				math.min(0, 0.2 * (g.have - L5)) - math.min(0, 0.2 * (g.shown - L5))))
		end
		if res.quiverHaste then
			addY(string.format("HGA: скорость стрельбы %d%% (сейчас %d%%)", res.quiverHaste,
				math.floor(st.snap.model.quiver * 100 + 0.5)))
		end
	end

	local rec = res.rec
	local modelRates, hitsOf, procOutcome = A.ModelProcRates(res)
	if modelRates then
		-- One line a proc: where its rate comes from (Score.ProcRateSource: the measured rate, wowsims' override row with its
		-- source, the DB2's) and its procs per minute on the landed hits of the set the result scores the item in
		-- (A.ModelProcRates), led by the hits they are on (RATE_HITS_TEXT); a measured rate per minute at a weapon's base
		-- speed (a non-weapon item's at the speed of the hand that hits), a procs-per-minute rate of an equip aura or an
		-- override row at the speed of the hand that hits, a chance a hit, every hit for an aura wowsims rolls so
		-- (ProcChanceAlways, Game/ProcData.lua always), and an equip aura's internal cooldown. A proc with
		-- no rate is not priced (U4 = (a): as wowsims, no rate is made up), and its line says so. A priced proc with no
		-- Game/ProcData.lua entry (Items.Get) says so and that its outcome follows the school its text names. An override
		-- row's source names where its rate comes from (wowsims tools/database/overrides/weapon_procs.go:13 WeaponProc.Source:
		-- "EV-<n>" a measurement on Forever, "vanilla-carryover" Classic's rate, "tbc-carryover" The Burning Crusade's); any
		-- other source is an error. A priced proc's damage over time (proc.dot; raid-mode design 17.4) gets a line of its own
		-- with the same rate text: its tick, ticks and duration, and the ticks it deals between two landed applications
		-- (Score.DotTicks at the proc's rate there and its application's chance, Score.ProcTable land); a proc of a damage
		-- over time alone has that line in place of the direct damage's.
		local weapon = ns.Score.IsWeapon(rec)
		for i, p in ipairs(rec.procs) do
			local rate, kind = ns.Score.ProcRateSource(rec, p)
			local source
			if kind == "measured" then
				source = string.format(weapon and "%.2f/мин на базовой скорости оружия — замер по логам" or "%.2f/мин на скорости бьющей руки — замер по логам", rate)
			elseif kind == "wowsims" then
				local value = (p.ppm ~= nil and p.ppm > 0) and string.format("%.2f/мин на скорости бьющей руки", rate)
					or string.format("%g%% за попадание", rate)
				if p.source:match("^EV%-") then
					source = string.format("%s — замер по логам (данные wowsims, %s)", value, p.source)
				elseif p.source == "vanilla-carryover" or p.source == "tbc-carryover" then
					source = string.format("%s — перенос из %s (данные wowsims), в Forever не проверено", value,
						p.source == "vanilla-carryover" and "классики" or "TBC")
				else
					error("HunterGearAdvisor: a proc rate of an unknown override source: " .. tostring(p.source) .. " (" .. tostring(rec.name) .. ")")
				end
			elseif kind == "db2ppm" then
				source = string.format("%.2f/мин на скорости бьющей руки — данные DB2", rate)
			elseif kind == "db2chance" then
				source = string.format("%d%% за попадание — данные DB2", rate)
			elseif kind == "always" then
				-- wowsims rolls it on every hit of its mask (ProcChanceAlways; raid-mode design 25.3), an aura of the main hand
				-- only on the main hand's (Game/ProcData.lua mainHand; 26.2)
				source = p.mainHand and "на каждом попадании правой руки — как в wowsims" or "на каждом попадании — как в wowsims"
			end
			if source and p.equip and p.linked and p.icd > 0 then source = source .. string.format(", не чаще раза в %g с", p.icd / 1000) end
			if source then
				local rateText = string.format("%s; %s%.2f/мин", source, RATE_HITS_TEXT[hitsOf], modelRates[i])
				if p.avg ~= nil then
					add("HGA: эффект при попадании учтён как оценка (" .. rateText .. ")", 0.7, 0.7, 0.9)
				end
				if p.dot ~= nil then
					local land = ns.Score.ProcTable(rec, p, procOutcome).land
					add(string.format("HGA: урон со временем учтён: %d ед. × %d %s за %g с (%.1f тика между срабатываниями), %s",
						p.dot.tick, p.dot.ticks, ruPlural(p.dot.ticks, "тик", "тика", "тиков"), p.dot.ticks * p.dot.period / 1000,
						ns.Score.DotTicks(p.dot, modelRates[i], land, (p.equip and p.linked) and p.icd or 0), rateText), 0.7, 0.7, 0.9)
				end
				-- a versus bonus of a creature type (proc.versus; raid-mode design 25.2): the factor, the types (CREATURE_WORDS)
				-- and the mean factor over the mode's targets (Score.VersusFactor): the raid boss a dragonkin, levelling the
				-- share of the types
				if p.versus ~= nil then
					local words = {}
					for k, ty in ipairs(p.versus.types) do words[k] = CREATURE_WORDS[ty] end
					local vs = ns.Score.VersusFactor(p, st.model.mode)
					local head = string.format("HGA: урон эффекта ×%g против %s", p.versus.factor, table.concat(words, " и "))
					if st.model.mode == "raid" then
						add(head .. (vs > 1 and string.format(" — в рейд-режиме цель дракон: учтено ×%g", vs)
							or " — в рейд-режиме цель дракон: не учитывается"), 0.7, 0.7, 0.9)
					else
						add(head .. string.format(" — при прокачке доля таких целей %.0f%%: учтено ×%.2f",
							100 * (vs - 1) / (p.versus.factor - 1), vs), 0.7, 0.7, 0.9)
					end
				end
			else
				add("HGA: частота эффекта при попадании не замерена — не учитывается (как в wowsims)", 0.6, 0.6, 0.6)
			end
			if source and not p.linked then
				add("HGA: эффект при попадании не найден в данных DB2 (Game/ProcData.lua): исход по школе урона из текста (оценка)",
					0.7, 0.7, 0.9)
			end
		end
	end
	-- Beastslaying: flat damage on every weapon strike and shot of the hunter (Model.Parts flat, the wowsims rule), at the
	-- mode's share of targets that are beasts (Model.TargetShare): levelling Model.AP_CREATURE_SHARE; raid mode none, the
	-- boss a dragonkin (raid-mode design 4.5)
	local mode = st.model.mode
	if (rec.stats.BEAST_SLAYING or 0) ~= 0 then
		if mode == "raid" then
			add(string.format("HGA: «+%d к убийству животных» — в рейд-режиме цель дракон: не учитывается", rec.stats.BEAST_SLAYING),
				0.6, 0.6, 0.6)
		else
			add(string.format("HGA: «+%d к убийству животных» учтено по зверям (доля %d%%) на всех ударах оружием и выстрелах (оценка)",
				rec.stats.BEAST_SLAYING, math.floor(ns.Model.TargetShare("BEAST", mode) * 100 + 0.5)), 0.7, 0.7, 0.9)
		end
	end
	-- attack power against a creature type (AP_VS_<TYPE>): priced at the mode's share of that type (Model.TargetShare,
	-- Model.Weights AP_VS_<TYPE>), on the hunter's own attacks alone (Model.Parts rapOwn, mapOwn); a text that names two
	-- types gives one line, and one share, for each. Raid mode: the boss's dragonkin whole, every other type not at all.
	-- Every line names whose attacks it reaches (raid-mode design 4.5: «(только твои атаки: пету и ястребам не идёт)»)
	for _, t in ipairs(ns.Model.CREATURE_TYPES) do
		local amount = rec.stats["AP_VS_" .. t]
		if amount and amount ~= 0 then
			if mode == "raid" and ns.Model.TargetShare(t, mode) == 0 then
				add(string.format("HGA: «+%d к силе атаки против %s» — в рейд-режиме цель дракон: не учитывается (только твои атаки: пету и ястребам не идёт)",
					amount, CREATURE_WORDS[t]), 0.6, 0.6, 0.6)
			elseif mode == "raid" then
				add(string.format("HGA: «+%d к силе атаки против %s» учтено полностью: в рейд-режиме цель дракон (только твои атаки: пету и ястребам не идёт)",
					amount, CREATURE_WORDS[t]), 0.7, 0.7, 0.9)
			else
				add(string.format("HGA: «+%d к силе атаки против %s» учтено по доле таких существ %d%% (только твои атаки: пету и ястребам не идёт; оценка)",
					amount, CREATURE_WORDS[t], math.floor(ns.Model.TargetShare(t, mode) * 100 + 0.5)), 0.7, 0.7, 0.9)
			end
		end
	end
	local useLines = 0
	for _, e in ipairs(rec.effects) do
		if e.kind == "use" then useLines = useLines + 1 end
	end
	local use = rec.use
	if use then
		-- the DB2 gives the item a "Use:" stat buff (Game/UseData.lua): its tooltip must have the Use line
		if useLines == 0 then
			geterrorhandler()("HunterGearAdvisor: " .. tostring(rec.name) .. " has a Use buff in UseData but no Use line in its tooltip")
		end
		local cd = use.cooldown % 60 == 0 and string.format("%g мин.", use.cooldown / 60) or string.format("%g сек.", use.cooldown)
		if st.model.mode == "raid" then
			-- the raid fight (raid-mode design 6.3, 6.8): the buff's windows from 5 s in the set the evaluation puts the item in
			-- (res.newSet; the worn set for a worn item; the item alone where it goes into no set: one the character cannot
			-- wear), a burst buff after another one's of that set (Score.SetUses' order, Model.Fight), its casts and its share
			-- of the fight's weighted time (Model.UseUptimes); with Rapid Fire, and Bestial Wrath where the fight has it. A set
			-- holds the item's Use spell (Score.Evaluate puts the item into res.newSet, a worn item is in the worn set), so a set
			-- without it is an error
			local set = res.newSet or (res.equippedSlot and st.snap.equipped)
			local uses, at
			if set then
				uses = ns.Score.SetUses(set)
				for i, u in ipairs(uses) do
					if u.spell == use.spell then at = i end
				end
				if not at then
					error("HunterGearAdvisor: the set of " .. tostring(rec.name) .. " holds no Use spell " .. tostring(use.spell))
				end
			else
				uses, at = { use }, 1
			end
			local p = {}
			for k, v in pairs(st.model) do p[k] = v end
			p.uses = uses
			local f = ns.Model.Fight(p)
			local wins = f.uses[at]
			local first = wins[1][1]
			local withText
			if first == ns.Model.CONST.raid.cooldownsFrom then
				withText = string.format("с %d-й секунды вместе с Rapid Fire%s", first, f.bestialWrath[1] and " и Bestial Wrath" or "")
			else
				withText = string.format("с %g-й секунды, после «Использования» другой вещи (общий откат)", first)
			end
			add(string.format("HGA: «Использование» учтено как оценка: %g сек. раз в %s — в бою %d с %d раз(а), %.0f%% времени, %s",
				use.duration, cd, ns.Model.CONST.raid.fight, #wins, ns.Model.UseUptimes(uses)[use.spell] * 100, withText), 0.7, 0.7, 0.9)
		elseif ns.Score.UsePriced(use, st.model.mode) then
			add(string.format("HGA: «Использование» учтено как оценка: %g сек. раз в %s — в среднем %.0f%% времени",
				use.duration, cd, use.duration / use.cooldown * 100), 0.7, 0.7, 0.9)
		end
	end
	local notCounted = 0
	if rec.setID then
		local text, unknown = setLine(st, res)
		add(text, 0.7, 0.7, 0.9)
		notCounted = notCounted + unknown
	end
	-- a line Items.LinkProcs links to an entry by its amount or as a damage over time (effect.linked) has its proc lines above
	for _, e in ipairs(rec.effects) do
		if (e.kind == "equip" or e.kind == "use" or (e.kind == "proc" and not e.avg)) and not e.linked then notCounted = notCounted + 1 end
		if e.kind == "useless" then add("HGA: «" .. e.text:gsub("^.-:%s*", "") .. "» — " .. (e.why or "бесполезно"), 0.6, 0.6, 0.6) end
	end
	-- the Use line whose buff is counted above (a levelling buff of the mana stats alone is priced at 0: Score.UsePriced)
	if use and useLines > 0 and ns.Score.UsePriced(use, st.model.mode) then notCounted = notCounted - 1 end
	if notCounted > 0 then add("HGA: эффекты не учтены: " .. notCounted .. " (смотри сам)", 0.7, 0.7, 0.9) end
	if #rec.unparsed > 0 then
		add("HGA: нераспознанных строк: " .. #rec.unparsed .. " (/hga dump)", 1, 0.6, 0.2)
	end
	return out
end
