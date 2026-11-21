return function(ns, T)
	local M = ns.Model
	-- Reference state = the user's character of 2026-11-12 (agi 167, gear AP 81, BM: no melee,
	-- mh 26 / oh 26). The expected numbers below are Core/Model.lua's at this state, with the rules each test
	-- names (Aimed cooldown after the cast, Rapid Fire by level and Rapid Killing, targets dodge the hawks, pet
	-- passives add up, Bestial Discipline Claw/Bite, Raptor replaces a swing: docs/research/*.md).
	-- Every input the model requires (Core/Model.lua checkInputs) as the game side sets it: melee crit at the ranged crit,
	-- the ranged and the melee skills at the level's (rangedSkill, mhSkill, ohSkill 0, their hits 0), no attack speed,
	-- one-handers at the normalized 2.4 s, the off hand at the main hand's speed;
	-- levelling mode (level 43), no ranged-only gear hit, Beastslaying or attack power against a creature type, no spell
	-- hit and the hunter's base spell crit 3.6% (wowsims sim/core/base_stats_auto_gen.go:62-66), no stat multiplier aura on
	-- the sheet (statMult 1 each).
	local ref = {
		mode = "level", agi = 167, rangedGearHit = 0, beastSlaying = 0, apVsTarget = 0, spellHit = 0, spellCrit = 3.6,
		statMult = { AGI = 1, STR = 1, INT = 1, SPI = 1 },
		level = 43, rap = 2 * 43 - 10 + 2 * 167 + 81 + 70, map = 2 * 43 - 20 + 167 + 81,
		crit = 167 / 35.84 + 2 + 2, meleeCrit = 167 / 35.84 + 2 + 2, hit = 1, rangedHit = 0, rangedSkill = 0, expertise = 0,
		meleeHit = 0, mhSkill = 0, ohSkill = 0,
		haste = 0, attackSpeed = 0, hasteRating = 0, meleeHaste = 0, rangedHaste = 0,
		bowDPS = 21, bowSpeed = 2.6, ammoDPS = 13, quiver = 0.13, mobDiff = 0, noShots = false,
		survival = false, mhDPS = 26, mhSpeed = 2.6, mhNorm = 2.4, ohDPS = 26, ohSpeed = 2.6, twoH = false,
		unarmed = false, petOut = true,
		tal = M.DEFAULT_TALENTS,
	}
	-- Crit suppression (wowsims sim/core/target.go:562-597, 504-512; sim/core/spell_result.go:208-231): a physical
	-- crit roll loses 0.2% a point of the skill gap 5 x the level difference, 1 / 2 / 3% at +1 / +2 / +3, and at +3 the
	-- aura crit up to 1.8% (EV-0090, Classic Era logs), the aura crit being the attack's crit less the Agility crit (the
	-- hunter's base physical crit is 0). Each shot part is K x (1 + suppressed crit) with K free of crit (no Mortal
	-- Shots), so two points one crit point apart with the aura crit held (Agility raised with it) measure the
	-- suppression: K = the difference x 100, suppression = 1 + crit - part / K.
	local function critPoint(d, aura, over, tover)
		local p = {}
		for k, v in pairs(ref) do p[k] = v end
		local tal = {}
		for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
		for k, v in pairs(tover or {}) do tal[k] = v end
		p.tal, p.level, p.mobDiff, p.agi = tal, 60, d, 300
		p.crit = M.CritPerAgility(60) * p.agi + aura
		p.meleeCrit = p.crit
		for k, v in pairs(over or {}) do p[k] = v end
		return p
	end
	local function measured(d, aura, part)
		local p1 = critPoint(d, aura)
		local p2 = critPoint(d, aura, { agi = 300 + 1 / M.CritPerAgility(60) })
		p2.crit, p2.meleeCrit = p1.crit + 1, p1.meleeCrit + 1
		local a1, a2 = M.Parts(p1)[part], M.Parts(p2)[part]
		local K = (a2 - a1) * 100
		return 1 + p1.crit / 100 - a1 / K
	end
	-- A raid point (raid mode, raid-mode design section 5): the reference state at level 60 in raid mode against the +3
	-- boss, with the raid inputs (a 4000 mana pool, 15 / 7.5 mana a second, 70 Spirit, no armor penetration), every attack's
	-- hit at the 8% cap (hit 8), ranged and melee crit 10% with no Agility (all of it aura crit: the clamp's 1.8% at +3), over
	-- and the talents tover on it
	local function raidPoint(over, tover)
		local p = {}
		for k, v in pairs(ref) do p[k] = v end
		local tal = {}
		for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
		for k, v in pairs(tover or {}) do tal[k] = v end
		p.tal, p.mode, p.level, p.mobDiff = tal, "raid", 60, 3
		p.manaMax, p.regenRest, p.regenCast, p.spirit, p.armorPen = 4000, 15, 7.5, 70, 0
		p.hit, p.crit, p.meleeCrit, p.agi = 8, 10, 10, 0
		for k, v in pairs(over or {}) do p[k] = v end
		return p
	end
	-- A raid point whose mana never runs out (raid-mode design 7.5's rich regime: the casts fully paid, each at its rate):
	-- the raid point with 200 mana a second of regen in the casts and out of them, which pays every build's casts with
	-- Judgement of Wisdom's income besides; the tests of the fight's other mechanics run at it
	local function richPoint(over, tover)
		local o = { regenCast = 200, regenRest = 200 }
		for k, v in pairs(over or {}) do o[k] = v end
		return raidPoint(o, tover)
	end
	-- The Major Frenzy Potion (CONST.mana.frenzyPotion: in the raid fight always, the user's answer O2 = (a)) with its attack
	-- power taken off while fn runs: the tests of a part's damage a cast that its +80 would make differ from state to state
	local function noPotionAP(fn)
		local stats = M.CONST.mana.frenzyPotion.stats
		local keep = stats.AP
		stats.AP = 0
		local ok, err = pcall(fn)
		stats.AP = keep
		if not ok then error(err, 0) end
	end
	-- a list of windows { { t0, t1 }, ... } (Model.Fight) as text: "t0-t1,..."
	local function windowsText(list)
		local t = {}
		for _, w in ipairs(list) do t[#t + 1] = string.format("%g-%g", w[1], w[2]) end
		return table.concat(t, ",")
	end
	-- the states of a raid fight (Model.Fight) without Use buffs by their Rapid Fire and Bestial Wrath: "rb", "r-", "-b", "--"
	local function statesByKey(f)
		local r = {}
		for _, s in ipairs(f.states) do r[(s.rf and "r" or "-") .. (s.bw and "b" or "-")] = s end
		return r
	end
	-- The raid fight's cast tempo of the build that shoots from range (raid-mode design 6.4-6.5) by hand: an action X waits
	-- for the other GCD actions' holds, delta_X = sum f h^2 / 2 + (1 - sum f h) x r_poll over the others, r_poll = (0.15^2 +
	-- 0.15 x 0.35 + 0.35^2) / 3 / 0.5 = 0.1317 s; acts = { name = { f, h } }. turretActs: the BM build's GCD actions at the
	-- shots' speed hR, the HHA elements 3 / C0, Serpent Sting 1 / 15, Aimed Shot at its use share (its hold the larger of the
	-- GCD and its 2 / hR cast), Sniper Shot (0.95 / (15 + 4 / hR), its hold the larger of the GCD and its 4 / hR cast) with
	-- the talent; hhaCycle C = C0 + 3 delta_H
	local R_POLL = (0.15 ^ 2 + 0.15 * 0.35 + 0.35 ^ 2) / 3 / 0.5
	local function tempoWait(acts, x)
		local held, rest = 0, 0
		for name, a in pairs(acts) do
			if name ~= x then held = held + a[1] * a[2]; rest = rest + a[1] * a[2] ^ 2 / 2 end
		end
		return rest + (1 - held) * R_POLL
	end
	local function turretActs(hR, c0, aimedUse, sniper)
		local acts = { hha = { 3 / c0, 1.5 }, serpent = { 1 / 15, 1.5 }, aimed = { aimedUse / (6 + 2 / hR), math.max(1.5, 2 / hR) } }
		if sniper then acts.sniper = { 0.95 / (15 + 4 / hR), math.max(1.5, 4 / hR) } end
		return acts
	end
	local function hhaCycle(hR, c0, aimedUse, sniper) return c0 + 3 * tempoWait(turretActs(hR, c0, aimedUse, sniper), "hha") end
	-- The raid fight's mean of a part f(rf) at Rapid Fire's speed rf (raid-mode design 6.2-6.3) for a build with no Rapid
	-- Killing: Rapid Fire's one window 5-20 s (its 300 s cooldown brings no second before 185 s) lies where the time weight is
	-- 1, so 15 of the fight's 180 weighted seconds run at its +40% and 165 without (my arithmetic)
	local function fightMean(f) return (165 * f(0) + 15 * f(0.40)) / 180 end
	-- A Survival point: the reference state in the weave (p.survival: the Survival branch weaves as wowsims' SV Weave,
	-- Core/Model.lua weaveParts; raid-mode design section 15), over and the talents tover on it
	local function svPoint(over, tover)
		local p = {}
		for k, v in pairs(ref) do p[k] = v end
		local tal = {}
		for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
		for k, v in pairs(tover or {}) do tal[k] = v end
		p.tal, p.survival = tal, true
		for k, v in pairs(over or {}) do p[k] = v end
		return p
	end
	-- the weave's counts a second averaged over Rapid Fire (Model.Weave): auto, mhWhite, raptor, oh, strider, bite, trap,
	-- wingClip, arcane, serpent
	local function weaveRates(p) return M.Weave(p).average.rates end
	-- raid-mode design 15.8's point in the weave: level 60, a 3.8 s two-hander, a 3.0 s bow, quiver 15%, no other speed, +3
	-- with no hit; every talent 0 but tover's (default: Strider Kick)
	local function p158(over, tover)
		local p = {}
		for k, v in pairs(ref) do p[k] = v end
		local tal = {}
		for k in pairs(M.DEFAULT_TALENTS) do tal[k] = 0 end
		for k, v in pairs(tover or { striderKick = 1 }) do tal[k] = v end
		p.tal, p.level, p.mobDiff, p.hit, p.survival = tal, 60, 3, 0, true
		p.mhDPS, p.mhSpeed, p.mhNorm, p.twoH, p.ohDPS = 50, 3.8, 3.3, true, 0
		p.bowDPS, p.bowSpeed, p.quiver = 40, 3.0, 0.15
		for k, v in pairs(over or {}) do p[k] = v end
		return p
	end
	return {
		{ "ranks by level", function()
			T.eq(M.Rank("aspectHawk", 43), 70); T.eq(M.Rank("aspectHawk", 48), 90)
			T.eq(M.Rank("aimedBonus", 43), 115); T.eq(M.Rank("aimedBonus", 44), 185)
			T.eq(M.Rank("huntersMark", 43), 98); T.eq(M.Rank("hawkDive", 43), 47)
			T.near(M.CritPerAgility(43), 0.0279, 1e-6, "crit per agi")
		end },
		{ "hit caps", function()
			T.near(M.HitCap(0), 5, 1e-9); T.near(M.HitCap(2), 6, 1e-9); T.near(M.HitCap(3), 8, 1e-9)
		end },
		-- the expected numbers include the rules of the wowsims comparison of 2026-11-16 (creature armor by level, pet
		-- and hawk curves from ExpectedStat, hawk AP without ammo, pet parry, glancing, shot shares)
		-- the hawks swing at the owner's ranged speed (wowsims summon_hawk.go:63-65), which Rapid Fire's aura 140 and
		-- the permanent attack speed of aura 342 raise, and take the owner's expertise against dodge (summon_hawk.go:85)
		-- The white swings of the pet, the hawks and the hunter are one roll on the white table (wowsims
		-- spell_outcome.go:852-875; raid-mode design 4.3): 1 - miss - dodge - parry + min(crit, the room left) - glance x
		-- (1 - its average), the specials (1 - miss - dodge - parry)(1 + crit). At this point (+0; my arithmetic): miss 4%,
		-- dodge 5%, the tanking pet's parry 5%, glance 10% at 0.95, so the pet's white swings take 0.855 + c, c = the ranged
		-- crit 8.66% + 10% Ferocity, and its Claw and Bite 0.86 x (1 + c); a hawk's swings 0.905 + c, c = half the crit + 10%.
		-- The BM build melees not (the Survival branch alone does, raid-mode design section 3): the shots whole, no melee
		-- part, and W.MH_DPS, W.OH_DPS and W.TH_DPS 0 (the derivative of a part that is absent). The dive's base holds Unleashed
		-- Fury's 3 and Ferocity's 2 a rank (raid-mode W1 design section 5: 47 + 15 + 10 at 43). The expected numbers are the
		-- model's at this point, each within its tolerance.
		{ "reference BM 32/2 build: weights of the current model", function()
			local W, dRap, total = M.Weights(ref)
			T.near(total, 250.40, 0.2, "total")
			T.near(dRap, 0.1372, 0.0005, "dps per rap")
			T.near(W.AGI, 2.51, 0.02, "agi")
			T.near(W.CRIT, 17.94, 0.05, "crit")
			T.near(W.HIT, 18.02, 0.05, "hit")
			T.near(W.RANGED_DPS, 10.15, 0.02, "ranged dps")
			T.near(W.AMMO_DPS, 8.01, 0.02, "ammo dps (hawks take the bow's DPS only)")
			T.eq(W.MH_DPS, 0, "mh dps: no melee"); T.eq(W.OH_DPS, 0, "oh dps: no melee"); T.eq(W.TH_DPS, 0, "two-hander: no melee")
			T.eq(M.Parts(ref).melee, 0, "no melee part")
			T.near(W.AP, 1.00, 0.02, "ap")
			T.near(W.EXPERTISE, 12.93, 0.05, "expertise (the pet: dodge and parry; the hawks: dodge)")
			T.near(W.HASTE, 12.90, 0.05, "attack speed (shots, pet, hawks)")
			T.near(W.MELEE_HASTE, 4.40, 0.05, "melee speed (the pet)")
			T.near(W.RANGED_HASTE, 8.50, 0.05, "ranged speed (shots, hawks)")
		end },
		-- the wowsims comparison of 2026-11-16, each confirmed rule as a test
		{ "wowsims check: armor, glancing and avoidance follow the mob's level", function()
			T.near(M.PhysMult(43, 0), 1 - 2414 / (2414 + 400 + 85 * 43), 1e-9, "ExpectedStat armor at 43")
			T.near(M.PhysMult(35, 0), 1 - 1387 / (1387 + 400 + 85 * 35), 1e-9, "at 35")
			T.near(M.PhysMult(60, 3), 1 - 3731 / (3731 + 400 + 85 * 60), 1e-9, "boss at 63")
			T.truthy(M.PhysMult(30, 0) > M.PhysMult(50, 0) + 0.08, "armor bites harder from the 40s on")
			T.near(M.GlanceMult(0), 0.995, 1e-9); T.near(M.GlanceMult(3), 0.86, 1e-9); T.eq(M.GlanceMult(-1), 1)
			local function at(diff)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.mobDiff = diff
				return M.Parts(p)
			end
			-- a higher mob dodges and parries more: the pet loses more than Serpent Sting (no avoidance)
			local p0, p3 = at(0), at(3)
			T.truthy(p3.pet / p0.pet < p3.serpent / p0.serpent, "pet hit harder by +3 than Serpent Sting")
		end },
		-- the level difference of every attack table is capped at +3 (wowsims sim/core/target.go:536-538 combatLevelDiff,
		-- docs/rulings/R-0032-combat-model-level-60-targets.md): +4 and +5 miss, dodge and glance as +3; the creature's armor
		-- stays its own level's (Model.PhysMult), so the parts that take no armor equal +3's and the physical ones differ from
		-- +3's by the armor multiplier alone
		{ "level cap: HitCap, MobAvoid and GlanceMult at +4 and +5 equal +3; the parts move by the creature's armor alone", function()
			for _, d in ipairs({ 4, 5 }) do
				T.near(M.HitCap(d), 8, 1e-12, "hit cap at +" .. d)
				T.near(M.MobAvoid(d), 6.5, 1e-12, "dodge at +" .. d)
				T.near(M.GlanceMult(d), M.GlanceMult(3), 1e-12, "glancing at +" .. d)
			end
			-- the BM build shooting from range, and the Survival weave (its melee and Immolation Trap, whose spell table caps at
			-- +3 too and which takes no armor)
			local function parts(d, survival)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.mobDiff, p.survival, p.expertise = d, survival, 1
				return M.Parts(p)
			end
			for _, case in ipairs({ { false, { "arcane", "serpent" }, { "auto", "aimed", "dive", "hawks", "pet" } },
				{ true, { "arcane", "serpent", "trap" }, { "auto", "pet", "melee" } } }) do
				local p3 = parts(3, case[1])
				for _, d in ipairs({ 4, 5 }) do
					local pd = parts(d, case[1])
					local armor = M.PhysMult(43, d) / M.PhysMult(43, 3)
					T.truthy(armor < 1, "the creature's armor grows with its level: " .. armor)
					local build = case[1] and "Survival " or "BM "
					for _, k in ipairs(case[2]) do
						T.truthy(p3[k] > 0, build .. k .. " counted")
						T.near(pd[k], p3[k], 1e-9, build .. k .. " (no armor) at +" .. d)
					end
					for _, k in ipairs(case[3]) do
						T.truthy(p3[k] > 0, build .. k .. " counted")
						T.near(pd[k] / p3[k], armor, 1e-9, build .. k .. " at +" .. d .. ": the armor alone")
					end
				end
			end
		end },
		-- the worn gear's ranged-only hit (p.rangedGearHit): wowsims gives the pet and the hawks the owner's physical and
		-- ranged-only hit (sim/hunter/pets.go:155-158 inheritedHit), the shots land with it, the hunter's melee does not
		{ "ranged gear hit reaches the shots, the pet and the hawks, not the hunter's melee; W.RANGED_HIT between W.HIT and W.HIT_RANGED", function()
			local function parts(over, survival)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.survival, p.hit = survival or false, 0
				for k, v in pairs(over) do p[k] = v end
				return M.Parts(p)
			end
			local base, gear, all = parts({}), parts({ rangedGearHit = 2 }), parts({ hit = 2 })
			for _, k in ipairs({ "auto", "aimed", "arcane", "serpent", "pet", "hawks" }) do
				T.truthy(gear[k] > base[k], k .. " lands more with the ranged gear hit")
				T.near(gear[k], all[k], 1e-9, k .. ": 2% ranged gear hit = 2% hit")
			end
			T.near(gear.dive, base.dive, 1e-12, "the dive rolls no hit")
			-- the Survival weave's melee lands with the hit of every attack alone
			local sBase, sGear, sAll = parts({}, true), parts({ rangedGearHit = 2 }, true), parts({ hit = 2 }, true)
			T.truthy(sBase.melee > 0, "the weave's melee")
			T.near(sGear.melee, sBase.melee, 1e-12, "the hunter's melee takes none of it")
			T.truthy(sAll.melee > sBase.melee, "the hit of every attack reaches melee")
			-- W.RANGED_HIT: the derivative by p.rangedGearHit with every hit at 0, in the weights' unit
			local W, unitDps = M.Weights(ref)
			local q0 = {}
			for k, v in pairs(ref) do q0[k] = v end
			q0.hit, q0.rangedHit, q0.rangedGearHit = 0, 0, 0
			local q1 = {}
			for k, v in pairs(q0) do q1[k] = v end
			q1.rangedGearHit = 0.5
			T.near(W.RANGED_HIT, (M.Total(q1) - M.Total(q0)) / 0.5 / unitDps, 1e-9, "W.RANGED_HIT")
			-- nested consumers: every attack, then the shots, the pet and the hawks, then the shots. With no melee (the BM build)
			-- the first two are the same attacks; in the Survival weave the melee takes the hit of every attack alone
			T.near(W.HIT, W.RANGED_HIT, 1e-9, "no melee: W.HIT = W.RANGED_HIT")
			T.truthy(W.RANGED_HIT > W.HIT_RANGED, "the pet and the hawks: " .. W.RANGED_HIT .. " / " .. W.HIT_RANGED)
			local Ws = M.Weights(svPoint())
			T.truthy(Ws.HIT > Ws.RANGED_HIT and Ws.RANGED_HIT > Ws.HIT_RANGED, "the weave: " .. Ws.HIT .. " / " .. Ws.RANGED_HIT .. " / " .. Ws.HIT_RANGED)
		end },
		-- Model.Weights takes W.HIT, W.RANGED_HIT and W.HIT_RANGED with p.hit, p.rangedGearHit and p.rangedHit all at 0, so a
		-- character whose worn hit already passes the cap (levelling at +0, cap 5%: the +3% scope of SpellItemEnchantment 2523
		-- and 2% more from items of the ranged-hit line) still prices hit below the cap; Score applies the cap to a whole set
		{ "hit weights at a point past the cap: each taken with every hit at 0", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.hit, p.rangedHit, p.rangedGearHit = 6, 2, 6
			T.truthy(p.hit >= M.HitCap(p.mobDiff) and p.rangedGearHit >= M.HitCap(p.mobDiff), "every hit past the cap")
			local W, unitDps = M.Weights(p)
			local q0 = {}
			for k, v in pairs(p) do q0[k] = v end
			q0.hit, q0.rangedHit, q0.rangedGearHit = 0, 0, 0
			local t0 = M.Total(q0)
			for key, input in pairs({ HIT = "hit", RANGED_HIT = "rangedGearHit", HIT_RANGED = "rangedHit" }) do
				local q1 = {}
				for k, v in pairs(q0) do q1[k] = v end
				q1[input] = 0.5
				local want = (M.Total(q1) - t0) / 0.5 / unitDps
				T.truthy(want > 0, key .. " below the cap adds damage")
				T.near(W[key], want, 1e-9, "W." .. key .. " at 0 hit")
			end
		end },
		-- attack power against the target's creature type (p.apVsTarget) reaches the hunter's own attacks alone: wowsims adds it
		-- to the unit's own attack tables (sim/core/attack_table_helpers.go:46-54), which the hunter's ranged and melee
		-- attack power read (spell_result.go:185-187, unit.go:265-267); the pet's and the hawks' attack power come from the
		-- owner's stats (pets.go:122-128, summon_hawk.go:79-81)
		{ "AP vs type reaches the shots, Serpent, the dive and melee, not the pet or the hawks; W.AP_VS_<TYPE> = W.AP_VS x the share", function()
			local function parts(over, survival)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.survival = survival or false
				for k, v in pairs(over) do p[k] = v end
				return M.Parts(p)
			end
			local base, vs = parts({}), parts({ apVsTarget = 100 })
			local rap = parts({ rap = ref.rap + 100 })
			for _, k in ipairs({ "auto", "aimed", "arcane", "serpent", "dive" }) do
				T.truthy(vs[k] > base[k], k .. " gains")
				T.near(vs[k], rap[k], 1e-9, k .. ": as 100 RAP")
			end
			T.near(vs.pet, base.pet, 1e-12, "not the pet"); T.near(vs.hawks, base.hawks, 1e-12, "not the hawks")
			T.truthy(rap.hawks > base.hawks, "the hawks read RAP")
			-- the Survival weave's melee: as 100 melee AP
			local mBase, mVs, mMap = parts({}, true), parts({ apVsTarget = 100 }, true), parts({ map = ref.map + 100 }, true)
			T.truthy(mVs.melee > mBase.melee, "melee gains"); T.near(mVs.melee, mMap.melee, 1e-9, "melee: as 100 melee AP")
			-- the normalized melee abilities: Strider Kick (from 30) and Mongoose Bite (Expose Prey), each on the normalized
			-- weapon hit of the main hand
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			tal.striderKick, tal.exposePrey = 1, 3
			local sBase, sVs, sMap = parts({ tal = tal }, true), parts({ tal = tal, apVsTarget = 100 }, true),
				parts({ tal = tal, map = ref.map + 100 }, true)
			T.truthy(sBase.melee > mBase.melee, "Strider Kick and Mongoose Bite counted at level " .. ref.level)
			T.truthy(sVs.melee > sBase.melee, "melee with the normalized abilities gains")
			T.near(sVs.melee, sMap.melee, 1e-9, "melee with Strider Kick and Mongoose Bite: as 100 melee AP")
			-- the weight: the derivative by p.apVsTarget; each type's key at the share of mobs of that type
			local W, unitDps, t0 = M.Weights(ref)
			local q = {}
			for k, v in pairs(ref) do q[k] = v end
			q.apVsTarget = q.apVsTarget + 10
			T.near(W.AP_VS, (M.Total(q) - t0) / 10 / unitDps, 1e-9, "W.AP_VS")
			T.truthy(W.AP_VS < W.AP, "below W.AP with a pet and hawks out: " .. W.AP_VS .. " < " .. W.AP)
			for _, t in ipairs(M.CREATURE_TYPES) do
				T.near(W["AP_VS_" .. t], W.AP_VS * M.AP_CREATURE_SHARE, 1e-12, t)
			end
			T.eq(#M.CREATURE_TYPES, 8); T.eq(W.AP_CREATURE, nil, "no untyped key")
		end },
		-- Beastslaying (Model.Parts flat): flat damage per hit of each of the hunter's weapon strikes, added to the base damage
		-- before the attacker's multipliers, the armor and the outcome (wowsims sim/core/spell_result.go:445-462), at the
		-- share of mobs that are beasts, 0.3. So p.beastSlaying = B gives each strike what 0.3 B more weapon damage a hit
		-- gives it: the bow's DPS + 0.3 B / its speed for Auto Shot, Aimed Shot, Multi-Shot and Sniper Shot (the weapon
		-- damage w x speed a hit), the main hand's DPS + 0.3 B / its speed for the white swings, Raptor Strike (its own hit
		-- and the white swing it replaces), Strider Kick and Mongoose Bite (the swing and the normalized hit), and the off
		-- hand's DPS + 2 x 0.3 B / its speed for its white swings: the off hand's 0.5 is on its weapon damage alone
		-- (sim/core/attack.go:174-176), so it takes the flat whole. Multi-Shot is cast at 18-19 alone (Aimed Shot shares its
		-- cooldown from 20), Sniper Shot from 40, Strider Kick from 30. The shots from range are the BM build's; the melee
		-- strikes the Survival weave's (its counts follow the weapons' speeds, not their DPS). Wing Clip has no weapon damage:
		-- it takes the flat whole on the special table (its rank's base + 0.3 B; raid-mode design 15.4), so the weave's melee
		-- part is the weapon damage's plus 0.3 B x (1 - miss - dodge) x (1 + crit) x the armor x Focused Fire 2/2 a Wing Clip
		-- (at +0, 1% hit: 0.91; no suppression)
		{ "beastslaying: flat on Auto, Aimed, Multi, Sniper, Raptor, Mongoose, Strider, white MH and OH whole, at 0.3", function()
			local function point(level, survival, over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.sniperShot, tal.striderKick, tal.exposePrey = 1, 1, 3
				p.tal, p.level, p.survival, p.ohSpeed = tal, level, survival, 1.8
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			local B = 10
			local function asWeapon(base) return { bowDPS = base.bowDPS + 0.3 * B / base.bowSpeed,
				mhDPS = base.mhDPS + 0.3 * B / base.mhSpeed, ohDPS = base.ohDPS + 2 * 0.3 * B / base.ohSpeed } end
			for _, case in ipairs({ { 19, { "auto", "multi" } }, { 60, { "auto", "aimed", "sniper" } } }) do
				local lvl = case[1]
				local base = point(lvl, false)
				local pb, pf = M.Parts(base), M.Parts(point(lvl, false, { beastSlaying = B }))
				local ps = M.Parts(point(lvl, false, asWeapon(base)))
				for _, k in ipairs({ "auto", "aimed", "multi", "sniper" }) do
					T.near(pf[k], ps[k], 1e-9, lvl .. " " .. k .. ": as 0.3 B more weapon damage a hit")
				end
				for _, k in ipairs(case[2]) do T.truthy(pf[k] > pb[k], lvl .. " " .. k .. " gains") end
			end
			for _, lvl in ipairs({ 19, 60 }) do
				local base = point(lvl, true)
				local pb, pf = M.Parts(base), M.Parts(point(lvl, true, { beastSlaying = B }))
				local ps = M.Parts(point(lvl, true, asWeapon(base)))
				T.near(pf.auto, ps.auto, 1e-9, lvl .. " the weave's Auto Shot: as 0.3 B more weapon damage a hit")
				local wc = weaveRates(base).wingClip
				T.truthy(wc > 0, lvl .. ": Wing Clip in the weave")
				T.near(pf.melee - ps.melee, 0.3 * B * 0.91 * (1 + ref.meleeCrit / 100) * wc * M.PhysMult(lvl, 0) * 1.02, 1e-9,
					lvl .. " the weave's melee: the weapon strikes as 0.3 B more weapon damage, Wing Clip the flat whole")
				T.truthy(pf.melee > pb.melee + 1e-9, lvl .. " melee gains")
			end
		end },
		-- the hunter's other damage takes no Beastslaying: Arcane Shot 14287 and the dive 1293527 are school damage rows with
		-- EffectBonusCoefficient 0 (Forever DB2 SpellEffect 691069, 1314239), Serpent Sting's ticks have no dot coefficient
		-- (spell_result.go:464-480), and the pet and the hawks are other units (the bonus is on the hunter's own attack
		-- tables, sim/core/attack_table_helpers.go:47-54)
		{ "beastslaying: none on Arcane, Serpent, the dive, the pet and the hawks", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.level = 60
			local base = M.Parts(p)
			p.beastSlaying = 10
			local bs = M.Parts(p)
			for _, k in ipairs({ "arcane", "serpent", "dive", "hawks", "pet" }) do
				T.truthy(base[k] > 0, k .. " counted")
				T.near(bs[k], base[k], 1e-12, k)
			end
			T.truthy(bs.auto > base.auto, "Auto Shot takes it")
		end },
		-- before the crit and the armor: each landed Auto Shot deals 0.3 B more, x the shots' crit (1 + crit, no Mortal
		-- Shots), x the armor multiplier of the target's level (Model.PhysMult) and x the hunter's own multiplier (Focused Fire
		-- 2/2 with the pet out: 1.02); the landed Auto Shots are Model.LandedHits' ranged swings. At an equal-level mob, two
		-- levels with two armors
		{ "beastslaying: before the crit and the armor of each landed Auto Shot", function()
			for _, lvl in ipairs({ 43, 60 }) do
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.level = lvl
				local base = M.Parts(p).auto
				local swings = M.LandedHits(p).ranged.swings
				p.beastSlaying = 10
				T.near(M.Parts(p).auto - base, 0.3 * 10 * swings * (1 + p.crit / 100) * M.PhysMult(lvl, 0) * 1.02, 1e-9, "level " .. lvl)
			end
		end },
		-- outside melee (no melee: every build but the Survival branch, Player.Snapshot) a two-hander's Beastslaying
		-- still raises the shots; W.BEAST_SLAYING is the derivative of Model.Total by p.beastSlaying in the weights' unit,
		-- the model linear in it
		{ "beastslaying on a two-hander outside the Survival branch still raises the shots; W.BEAST_SLAYING its derivative", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.survival, p.twoH, p.ohDPS, p.mhSpeed, p.mhNorm = false, true, 0, 3.3, 3.3
			local base = M.Parts(p)
			local W, unitDps, t0 = M.Weights(p)
			local q = {}
			for k, v in pairs(p) do q[k] = v end
			q.beastSlaying = 10
			local bs = M.Parts(q)
			T.truthy(bs.auto > base.auto and bs.aimed > base.aimed, "the shots gain"); T.eq(bs.melee, 0, "no melee part")
			T.truthy(W.BEAST_SLAYING > 0, "W.BEAST_SLAYING " .. W.BEAST_SLAYING)
			T.near(W.BEAST_SLAYING, (M.Total(q) - t0) / 10 / unitDps, 1e-9, "the derivative, linear")
		end },
		{ "crit suppression: the skill part 0 / 1 / 2 / 3% at +0..+3 on the shots, the dive and Serpent Sting's ticks", function()
			for d = 0, 3 do
				T.near(measured(d, 0, "auto"), 0.01 * d, 1e-9, "Auto Shot at +" .. d)
			end
			for _, part in ipairs({ "aimed", "arcane", "serpent", "dive" }) do
				T.near(measured(3, 0, part), 0.03, 1e-9, part .. " at +3")
			end
			-- +4 and +5 suppress as +3 (the level difference capped at +3, Model capDiff)
			T.near(measured(5, 0, "auto"), 0.03, 1e-9, "Auto Shot at +5")
		end },
		{ "crit suppression: the aura part at +3 alone, up to 1.8%; the hunter's melee keeps its Agility crit out of it", function()
			T.near(measured(2, 0.5, "auto"), 0.02, 1e-9, "+2: no aura part")
			T.near(measured(3, 0.5, "auto"), 0.035, 1e-9, "+3: 3% and the 0.5% aura crit")
			T.near(measured(3, 3, "auto"), 0.048, 1e-9, "+3: 3% and 1.8% of the 3% aura crit")
			-- the white swings and the melee abilities: their aura crit below 1.8% is suppressed whole, so 0.5% and 1% of it
			-- give the same melee part; past 1.8% more of it counts
			local function melee(aura) return M.Parts(critPoint(3, aura, { survival = true }, { striderKick = 1, exposePrey = 3 })).melee end
			T.truthy(melee(0.5) > 0, "the weave's melee")
			T.near(melee(1), melee(0.5), 1e-9, "melee: aura crit below 1.8% suppressed whole")
			T.truthy(melee(2.5) > melee(2) + 1e-6, "melee: past 1.8% the aura crit counts")
		end },
		-- Savage Strikes (+2% a rank on the melee abilities' crit) is a spell modifier on the abilities (wowsims
		-- sim/hunter/talents_survival.go:76-82 ParseStatic), so it is aura crit of the ability's whole crit
		-- (sim/core/spell_result.go:221-231: the crit less the base crit and the Agility crit). Strider Kick alone of the
		-- abilities (unarmed: no Raptor Strike; no Expose Prey: no Mongoose Bite), all in melee at +3, level 60, 300 Agility,
		-- the melee crit c 0.5% over the Agility crit: without the talent 0.5% of aura crit, all of it suppressed (c - 3.5%);
		-- with Savage Strikes 2/2 4.5% of it, 1.8% suppressed (c + 4% - 4.8%), so the talent adds 2.7% to the kick's crit
		-- (my arithmetic). Strider Kick in the Survival weave: the normalized hit 314 / 14 x 2.4 (no weapon damage) at the
		-- weave's kicks a second (Model.Weave), landing with 1 - 7% - 6.5%, x the armor at +3 and Focused Fire 2/2
		{ "crit suppression: Savage Strikes is aura crit of the melee abilities' whole crit", function()
			local function point(ss)
				return critPoint(3, 0.5, { survival = true, unarmed = true, mhDPS = 0, ohDPS = 0 }, { striderKick = 1, savageStrikes = ss })
			end
			local kicks = weaveRates(point(0)).strider
			T.truthy(kicks > 0, "Strider Kick in the weave")
			local strider = 314 / 14 * 2.4 * kicks * 0.865 * M.PhysMult(60, 3) * 1.02
			T.near(M.Parts(point(2)).melee - M.Parts(point(0)).melee, strider * 0.027, 1e-9, "Savage Strikes 2/2: 2.7% more crit on Strider Kick")
		end },
		-- The Agility crit the aura part leaves out is the character's level's (Model.CritPerAgility(p.level)): at 44, 167
		-- Agility give 167 x the crit per Agility at 44; with the ranged and melee crit 1% over it the aura crit is 1%, so the
		-- shots lose 3% + 1% at +3 (measured as above: two points one crit point apart, the Agility raised with the crit).
		-- At level 60's crit per Agility the aura crit would pass 1.8%
		{ "crit suppression: the Agility crit at the character's level", function()
			local cpa = M.CritPerAgility(44)
			local function point(agi, crit)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.level, p.mobDiff, p.agi, p.crit, p.meleeCrit = 44, 3, agi, crit, crit
				return p
			end
			local p1, p2 = point(167, cpa * 167 + 1), point(167 + 1 / cpa, cpa * 167 + 2)
			local a1, a2 = M.Parts(p1).auto, M.Parts(p2).auto
			local K = (a2 - a1) * 100
			T.near(1 + p1.crit / 100 - a1 / K, 0.04, 1e-9, "Auto Shot at 44: 3% and the 1% aura crit")
			T.truthy(167 * (cpa - M.CritPerAgility(60)) + 1 > 1.8, "at level 60's crit per Agility the aura crit passes 1.8%")
		end },
		-- At +3 with the aura crit below 1.8% (no talent crit, no crit gear: 0.5% over the Agility crit), and nothing but the
		-- shots attacking (no pet, no hawks, no melee): an item's crit is aura crit and suppressed whole, so W.CRIT is 0; an
		-- item's Agility gives 2 RAP and Agility crit, which is not suppressed (Model.ApplyStats AGI raises p.agi with it).
		-- The shots are B(rap) x (1 + x), B linear in RAP (slope b) and x the suppressed crit, here the Agility crit less the
		-- 3% skill part (the 0.5% aura crit suppressed whole). 10 Agility: 20 RAP and d = 10 x the crit per Agility / 100
		-- more x, so (my arithmetic) 10 x (W.AGI x unitDps - 2 b (1 + x)) = B d + 20 b d, with unitDps = b (1 + x), and B / 100
		-- is W.CRIT x unitDps at the same point with the aura crit saturated (2.5%, where 0.5% more crit is 0.5% more x):
		-- (W.AGI - 2) x unitDps = the crit per Agility x W.CRIT(saturated) x its unitDps + 0.2 x the crit per Agility x b
		{ "crit suppression: Agility crit is not aura crit (W.AGI against W.CRIT at aura crit below 1.8%)", function()
			local over = { survival = false, petOut = false }
			local tover = { summonHawk = 0 }
			local Wa, ua = M.Weights(critPoint(3, 0.5, over, tover))
			local Wb, ub = M.Weights(critPoint(3, 2.5, over, tover))
			T.near(Wa.CRIT, 0, 1e-9, "an item's crit: aura crit, suppressed whole")
			T.truthy(Wb.CRIT > 0, "past 1.8% of aura crit an item's crit counts")
			T.truthy(Wa.AGI > 2 + 0.01, "W.AGI " .. Wa.AGI)
			local cpa = M.CritPerAgility(60)
			local x = cpa * 300 / 100 - 0.03
			T.near((Wa.AGI - 2) * ua, cpa * Wb.CRIT * ub + 0.2 * cpa * ua / (1 + x), 1e-9, "the Agility crit, unsuppressed")
		end },
		-- Lightning Reflexes +3% Agility a rank: Model.ApplyStats turns an item's Agility into 1.15 x as much effective
		-- Agility at 5/5, every input it moves (RAP, melee attack power, crit, p.agi) with it, the crit as Agility crit. So
		-- W.AGI at 5/5 is the model's change for 11.5 Agility without the talent over 10 (the step), with no factor outside;
		-- W.AGI is not linear in Agility (attack power times crit), so it is 1.15 x W.AGI without the talent to about 1%
		{ "W.AGI with Lightning Reflexes 5/5 at aura crit below 1.8% is 1.15 x W.AGI without", function()
			local function point(lr) return critPoint(3, 0.5, { survival = true }, { lightningReflexes = lr }) end
			local W5, unitDps = M.Weights(point(5))
			local W0 = M.Weights(point(0))
			local p0 = point(0)
			local q = {}
			for k, v in pairs(p0) do q[k] = v end
			M.ApplyStats(q, { AGI = 11.5 })
			T.near(W5.AGI, (M.Total(q) - M.Total(p0)) / 10 / unitDps, 1e-9, "11.5 Agility without the talent")
			T.near(W5.AGI / W0.AGI, 1.15, 0.01, "about 1.15 x")
		end },
		-- The pet's and the hawks' crit is all aura crit (no base crit and no Agility in their base stats, wowsims
		-- sim/hunter/pets.go:38-42, summon_hawk.go:39-41): at +3 it loses 3% and 1.8% whatever the owner's Agility. With no
		-- Ferocity the pet takes the owner's crit and a hawk half of it: an owner's 4% (all of it Agility crit) leaves the
		-- pet none (4 - 4.8 < 0), so 4.5% changes nothing; an owner's 8% leaves a hawk none (4 - 4.8). Past those the
		-- crit counts
		{ "crit suppression: the pet and the hawks lose all their crit as aura crit", function()
			local function part(ownerCrit, name)
				local p = critPoint(3, 0, { agi = ownerCrit / M.CritPerAgility(60) }, { ferocity = 0 })
				p.crit, p.meleeCrit = ownerCrit, ownerCrit
				return M.Parts(p)[name]
			end
			T.near(part(4.5, "pet"), part(4, "pet"), 1e-9, "the pet at 4% and 4.5%: no crit left")
			T.truthy(part(6.5, "pet") > part(6, "pet") + 1e-6, "the pet at 6%: 1.2% left")
			T.near(part(8.5, "hawks"), part(8, "hawks"), 1e-9, "a hawk at 4% and 4.25%: no crit left")
			T.truthy(part(12.5, "hawks") > part(12, "hawks") + 1e-6, "a hawk at 6%: 1.2% left")
		end },
		-- Weapon skill by wowsims' attack table (sim/core/target.go:561-597 newAttackTableHand; raid-mode W1 design 3.1):
		-- a hand's miss 5% + 0.1% a point of the skill gap 5 x the level difference - bonus while the gap is 10 points or
		-- less, 5% + 0.2% a point of the whole gap past it. The +3 values are wowsims' own test
		-- (sim/core/attack_table_test.go:87-137: the sword hand at 285 / 300 / 305 / 315 skill, 11 / 8 / 6 / 5%); +0 my
		-- arithmetic. Mutants: 0.1 a point past the 10-point gap (285: 6.5); the kink at a gap of 10 (305: 7); the bonus taken
		-- as 0 (8 everywhere at +3)
		{ "skill: Model.SkillMiss is wowsims' hand miss: +3 at 285 / 300 / 305 / 315 -> 11 / 8 / 6 / 5%; +0 at -5 / +5 -> 5.5 / 4.5%", function()
			for _, c in ipairs({ { 285, 11 }, { 300, 8 }, { 305, 6 }, { 315, 5 } }) do
				T.near(M.SkillMiss(3, c[1] - 300), c[2], 1e-12, "+3 at " .. c[1])
			end
			T.near(M.SkillMiss(0, -5), 5.5, 1e-12, "+0, 5 points below the maximum")
			T.near(M.SkillMiss(0, 5), 4.5, 1e-12, "+0, 5 points above it")
			-- the level difference capped at +3 (capDiff), the hit cap the level's skill
			T.near(M.SkillMiss(5, -15), 11, 1e-12, "+5 as +3")
			for d = 0, 3 do T.near(M.HitCap(d), M.SkillMiss(d, 0), 1e-12, "the hit cap at +" .. d) end
			local ok, err = pcall(M.SkillMiss, 3, nil)
			T.eq(ok, false); T.truthy(tostring(err):find("without a skill bonus", 1, true), tostring(err))
		end },
		-- the hit a skill gives against the level's skill (my arithmetic from the table above). Mutant: 0.04 a point (the
		-- Forever UI Skills frame's slope, Camelot/SkillsFrame.lua:44-55)
		{ "skill: Model.SkillHit is 0 at bonus 0 and jumps at the 10-point gap (+3: bonus 4 -> 0.8, 5 -> 2.0)", function()
			for d = 0, 3 do T.eq(M.SkillHit(d, 0), 0, "bonus 0 at +" .. d) end
			T.near(M.SkillHit(3, 4), 0.8, 1e-12, "+3, bonus 4: the gap 11 past 10")
			T.near(M.SkillHit(3, 5), 2.0, 1e-12, "+3, bonus 5: the gap 10")
			T.near(M.SkillHit(3, -15), -3.0, 1e-12, "+3, 285")
			T.near(M.SkillHit(0, -10), -1.0, 1e-12, "+0, bonus -10: the gap 10")
			T.near(M.SkillHit(0, -11), -2.2, 1e-12, "+0, bonus -11: the gap 11")
			T.near(M.SkillHit(0, 5), 0.5, 1e-12, "+0, bonus 5")
		end },
		-- The ranged hand's crit suppression (sim/core/target.go:591-595, spell_result.go:224-231): 0.2% a point of
		-- baseSkillDiff = 5 x the level difference - min(bonus, 0); the shots, Serpent Sting's ticks and the dive take the
		-- ranged hand's entry (target.go:606-615; summon_hawk.go:135 ProcMaskRangedSpecial; serpent_sting.go:28). Measured as
		-- the level part above, at no aura crit: +3 at 295 (bonus -5) 0.002 x 20 = 4%, at 305 the level's 3%; +0 at 205 of
		-- 215 (level 60 here: bonus -10) 2%, above the maximum 0 (my arithmetic). Mutants: the dive at bonus 0; a crit gain
		-- above the maximum (0.0004 x baseSkillDiff for bonus > 0, or the bonus in the gap); 0.04 a point
		{ "skill suppression: the shots, Serpent Sting's ticks and the dive lose 0.2% crit a point below the maximum on top of the level part (+3 at 295: 4%); none above it", function()
			local function supp(d, bonus, part)
				local p1 = critPoint(d, 0, { rangedSkill = bonus })
				local p2 = critPoint(d, 0, { rangedSkill = bonus, agi = 300 + 1 / M.CritPerAgility(60) })
				p2.crit, p2.meleeCrit = p1.crit + 1, p1.meleeCrit + 1
				local a1, a2 = M.Parts(p1)[part], M.Parts(p2)[part]
				local K = (a2 - a1) * 100
				return 1 + p1.crit / 100 - a1 / K
			end
			for _, part in ipairs({ "auto", "aimed", "arcane", "serpent", "dive" }) do
				T.near(supp(3, -5, part), 0.04, 1e-9, part .. " at +3, 295")
				T.near(supp(3, 5, part), 0.03, 1e-9, part .. " at +3, 305: the level part alone")
				T.near(supp(0, -10, part), 0.02, 1e-9, part .. " at +0, 10 points below")
				T.near(supp(0, 10, part), 0, 1e-9, part .. " at +0, 10 points above: no gain")
			end
			-- the pet and the hawks keep their own tables at bonus 0: their suppression does not move with the ranged skill
			-- (their crit's 0.04% a point is the pet's ranged branch, "pet crit: ..."), the melee part neither
			local function parts(bonus)
				return M.Parts(critPoint(3, 0, { rangedSkill = bonus, survival = true }, { striderKick = 1 }))
			end
			local at, above = parts(0), parts(10)
			for _, k in ipairs({ "pet", "melee" }) do T.near(above[k], at[k], 1e-9, k .. ": not the ranged hand") end
		end },
		-- The pet's crit (wowsims sim/hunter/pets.go:142-153 inheritedCrit; raid-mode W1 design section 4): the ranged branch
		-- p.crit + 0.04 a point of min(rangedSkill, 0), the hawks half of it (summon_hawk.go:83), Ferocity whole on both. A
		-- fixture with the ranged crit 2% over the melee crit (the ranged branch leads by more than the penalty): the pet at
		-- rangedSkill -10 is the pet at rangedSkill 0 with 0.4% less ranged crit, the hawks likewise; +10 gives nothing.
		-- Mutants: 0.04 a point above the maximum too; 0.2% a point
		{ "pet crit: 0.04% a point below the maximum of the ranged skill, nothing above", function()
			for _, d in ipairs({ 0, 3 }) do
				local function parts(bonus, critLess)
					local p = critPoint(d, 4, { rangedSkill = bonus })
					p.meleeCrit = p.crit - 2
					p.crit = p.crit - critLess
					return M.Parts(p)
				end
				local below, lower, at, above = parts(-10, 0), parts(0, 0.4), parts(0, 0), parts(10, 0)
				for _, k in ipairs({ "pet", "hawks" }) do
					T.near(below[k], lower[k], 1e-9, k .. " at -10 = 0.4% less crit, +" .. d)
					T.truthy(below[k] < at[k] - 1e-6, k .. " loses at -10, +" .. d)
					T.near(above[k], at[k], 1e-9, k .. " at +10: nothing, +" .. d)
				end
			end
		end },
		-- Model.ApplyStats: the one map from item stat keys to model inputs (Core/Model.lua applyStats), which Model.Weights'
		-- stat mutations and the raid fight's Use buffs go through
		{ "Model.ApplyStats: each stat key to its inputs; HIT, SPELL_HIT, EXPERTISE, the survival and the levelling mana stats not applied; raid the mana stats; another key is an error", function()
			local function applied(stats, tover)
				local q = {}
				for k, v in pairs(ref) do q[k] = v end
				q.haste, q.meleeHaste, q.rangedHaste = 3, 4, 5
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				q.tal = tal
				local before = {}
				for k, v in pairs(q) do before[k] = v end
				M.ApplyStats(q, stats)
				local moved = {}
				for k, v in pairs(q) do if v ~= before[k] then moved[k] = v - before[k] end end
				return moved
			end
			local function same(moved, want, msg)
				for k, v in pairs(want) do T.near(moved[k] or 0, v, 1e-12, msg .. " " .. k) end
				for k in pairs(moved) do T.truthy(want[k] ~= nil, msg .. ": " .. k .. " moved") end
			end
			local cpa = M.CritPerAgility(ref.level)
			same(applied({ AP = 10 }), { rap = 10, map = 10 }, "AP")
			same(applied({ RAP = 10 }), { rap = 10 }, "RAP")
			same(applied({ MAP = 10 }), { map = 10 }, "MAP")
			same(applied({ STR = 10 }), { map = 10 }, "STR")
			same(applied({ AGI = 10 }), { rap = 20, map = 10, agi = 10, crit = 10 * cpa, meleeCrit = 10 * cpa }, "AGI")
			same(applied({ AGI = 10 }, { lightningReflexes = 5 }), { rap = 23, map = 11.5, agi = 11.5, crit = 11.5 * cpa,
				meleeCrit = 11.5 * cpa }, "AGI with Lightning Reflexes 5/5")
			same(applied({ CRIT = 1 }), { crit = 1, meleeCrit = 1 }, "CRIT")
			same(applied({ CRIT_RANGED = 1 }), { crit = 1 }, "CRIT_RANGED")
			same(applied({ HASTE = 2 }), { haste = (1.03 * 1.02 - 1) * 100 - 3 }, "HASTE")
			same(applied({ MELEE_HASTE = 2 }), { meleeHaste = (1.04 * 1.02 - 1) * 100 - 4 }, "MELEE_HASTE")
			same(applied({ RANGED_HASTE = 2 }), { rangedHaste = (1.05 * 1.02 - 1) * 100 - 5 }, "RANGED_HASTE")
			same(applied({ INT = 10 }), {}, "INT without Careful Aim")
			same(applied({ INT = 10 }, { carefulAim = 5 }), { rap = 10, map = 10 }, "INT with Careful Aim 5/5")
			for _, t in ipairs(M.CREATURE_TYPES) do
				same(applied({ ["AP_VS_" .. t] = 10 }), { apVsTarget = 10 * M.AP_CREATURE_SHARE }, "AP_VS_" .. t)
			end
			same(applied({ HIT = 1, SPELL_HIT = 1, EXPERTISE = 1 }), {}, "HIT, SPELL_HIT, EXPERTISE")
			same(applied({ AP = 10, CRIT = 1 }), { rap = 10, map = 10, crit = 1, meleeCrit = 1 }, "two keys")
			-- the survival and tank stats, and in levelling mode the mana stats: no damage input (a Use buff's Stamina)
			same(applied({ STA = 16, ARMOR = 100, HEALTH = 50, HP5 = 3, DEFENSE = 5, DODGE = 1, PARRY = 1, BLOCK = 1, SPELL_POWER = 9,
				SPI = 16, MP5 = 4, MANA = 100 }), {}, "survival, tank and (levelling) mana stats")
			-- raid mode: Intellect 15 mana of the pool a point besides Careful Aim; Spirit, its 1/8 a second in the regen out of
			-- the five-second rule and Bestial Discipline's 25% a rank of it in the regen while casting (the env's 2 ranks: 50%);
			-- MP5 a fifth a second in both; MANA the pool (raid-mode design 6.8, 7.3)
			local function appliedRaid(stats, tover)
				local q = raidPoint({}, tover)
				local before = {}
				for k, v in pairs(q) do before[k] = v end
				M.ApplyStats(q, stats)
				local moved = {}
				for k, v in pairs(q) do if v ~= before[k] then moved[k] = v - before[k] end end
				return moved
			end
			same(appliedRaid({ INT = 10 }), { manaMax = 150 }, "raid INT without Careful Aim")
			same(appliedRaid({ INT = 10 }, { carefulAim = 5 }), { manaMax = 150, rap = 10, map = 10 }, "raid INT with Careful Aim 5/5")
			same(appliedRaid({ SPI = 16 }), { spirit = 16, regenRest = 2, regenCast = 0.5 * 2 }, "raid SPI, Bestial Discipline 2/2")
			same(appliedRaid({ SPI = 16 }, { bestialDiscipline = 0 }), { spirit = 16, regenRest = 2 }, "raid SPI, no Bestial Discipline")
			same(appliedRaid({ MP5 = 10 }), { regenRest = 2, regenCast = 2 }, "raid MP5")
			same(appliedRaid({ MANA = 100 }), { manaMax = 100 }, "raid MANA")
			same(appliedRaid({ STA = 16 }), {}, "raid STA")
			local q = {}
			for k, v in pairs(ref) do q[k] = v end
			local ok, err = pcall(M.ApplyStats, q, { NO_SUCH_STAT = 1 })
			T.eq(ok, false); T.truthy(tostring(err):find("no model input takes the stat NO_SUCH_STAT", 1, true), tostring(err))
			q.tal = nil
			T.eq(pcall(M.ApplyStats, q, { AGI = 1 }), false, "no talent ranks")
		end },
		-- The live sheet's stat multipliers (the user's answer O8 = (a), raid-mode design 4.8): p.statMult { AGI, STR, INT, SPI }
		-- multiplies an item's and a Use buff's attributes in Model.ApplyStats (wowsims multiplies a stat by every aura of
		-- A_MOD_TOTAL_STAT_PERCENTAGE on it, sim/core/stats/deps.go:232-237, 279-283), Lightning Reflexes' factor among them; so
		-- on a sheet under Greater Blessing of Kings (+10% each) 10 item Agility is 11 sheet Agility and W.AGI prices it so;
		-- Strength, Intellect (Careful Aim's attack power, the raid pool) and Spirit at theirs; a melee-only attack power at no
		-- multiplier (W.MAP); a point without statMult, or a factor below 1, is an error
		{ "stat multipliers: Kings on the sheet makes 10 item Agility 11 in W.AGI; Strength, Intellect and Spirit at theirs; W.MAP at none; statMult required", function()
			local KINGS = { AGI = 1.1, STR = 1.1, INT = 1.1, SPI = 1.1 }
			local function with(p, m)
				local q = {}
				for k, v in pairs(p) do q[k] = v end
				q.statMult = m
				return q
			end
			local function moved(q, stats)
				local before = {}
				for k, v in pairs(q) do before[k] = v end
				M.ApplyStats(q, stats)
				local d = {}
				for k, v in pairs(q) do if type(v) == "number" and v ~= before[k] then d[k] = v - before[k] end end
				return d
			end
			local function same(a, b, msg)
				for k, v in pairs(b) do T.near(a[k] or 0, v, 1e-9, msg .. " " .. k) end
				for k, v in pairs(a) do T.near(v, b[k] or 0, 1e-9, msg .. " " .. k) end
			end
			-- Model.ApplyStats: 10 of each attribute under Kings moves the inputs as 11 at no multiplier (raid: the pool, the regens)
			local cpa = M.CritPerAgility(60)
			local rk = with(raidPoint({}, { carefulAim = 5 }), KINGS)
			local r1 = with(raidPoint({}, { carefulAim = 5 }), ref.statMult)
			same(moved(rk, { AGI = 10, STR = 10, INT = 10, SPI = 10 }), moved(r1, { AGI = 11, STR = 11, INT = 11, SPI = 11 }), "raid, Kings")
			same(moved(with(raidPoint({}, { carefulAim = 5 }), KINGS), { INT = 10 }), { manaMax = 165, rap = 11, map = 11 }, "INT under Kings")
			same(moved(with(raidPoint({}), KINGS), { SPI = 16 }), { spirit = 17.6, regenRest = 2.2, regenCast = 0.5 * 2.2 }, "SPI under Kings")
			same(moved(with(raidPoint({}), { AGI = 1, STR = 1.15, INT = 1, SPI = 1 }), { STR = 20 }), { map = 23 }, "STR at its own factor")
			same(moved(with(raidPoint({}), KINGS), { MAP = 10, AP = 10, RAP = 10 }), { rap = 20, map = 20 }, "attack power: no multiplier")
			-- Lightning Reflexes 5/5 and Kings multiply: 10 x 1.15 x 1.1
			local e = 10 * 1.15 * 1.1
			same(moved(with(raidPoint({}, { lightningReflexes = 5 }), KINGS), { AGI = 10 }),
				{ rap = 2 * e, map = e, agi = e, crit = e * cpa, meleeCrit = e * cpa }, "AGI, Lightning Reflexes 5/5 and Kings")
			-- W.AGI under Kings: the value of 11 Agility at no multiplier, over 10 (levelling and raid)
			for _, base in ipairs({ ref, richPoint({}) }) do
				local pk, p1 = with(base, KINGS), with(base, ref.statMult)
				local Wk, uk, tk = M.Weights(pk)
				local _, u1, t1 = M.Weights(p1)
				T.near(uk, u1, 1e-12, base.mode .. ": the unit holds"); T.near(tk, t1, 1e-12, base.mode .. ": the total holds")
				local q = with(base, ref.statMult)
				M.ApplyStats(q, { AGI = 11 })
				T.near(Wk.AGI, (M.Total(q) - t1) / 10 / u1, 1e-9, base.mode .. ": W.AGI under Kings")
				T.truthy(Wk.AGI > M.Weights(p1).AGI * 1.05, base.mode .. ": W.AGI rises with Kings")
			end
			-- levelling Intellect: Careful Aim's share of W.AP at the Intellect multiplier; the Use weight likewise
			local lk = with(ref, KINGS)
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			tal.carefulAim = 5
			lk.tal = tal
			local Wl = M.Weights(lk)
			T.near(Wl.INT, 0.20 * 5 * Wl.AP * 1.1, 1e-12, "levelling W.INT under Kings")
			T.near(Wl.INT_USE, 0.20 * 5 * Wl.AP_USE * 1.1, 1e-12, "levelling W.INT_USE under Kings")
			-- Strength in the Survival weave (the melee attack power counts): W.STR at the multiplier, W.MAP at none; the levelling
			-- Use weight of Strength likewise against the melee attack power's
			local sv = with(svPoint({}), { AGI = 1, STR = 1.2, INT = 1, SPI = 1 })
			local Ws, us, ts = M.Weights(sv)
			local q = with(svPoint({}), ref.statMult)
			M.ApplyStats(q, { MAP = 12 })
			T.near(Ws.STR, (M.Total(q) - ts) / 10 / us, 1e-9, "W.STR: 10 Strength x 1.2 = 12 melee attack power")
			T.truthy(Ws.MAP > 0 and Ws.STR > Ws.MAP * 1.1, "W.MAP at no multiplier: " .. Ws.MAP .. " / " .. Ws.STR)
			T.truthy(Ws.STR_USE > Ws.MAP_USE * 1.1, "W.STR_USE at the multiplier: " .. Ws.STR_USE .. " / " .. Ws.MAP_USE)
			-- a Use buff's Agility in the raid fight under Kings: as 1.1 x as much at no multiplier
			local buff = { spell = 1, stats = { AGI = 100 }, duration = 20, cooldown = 120 }
			local buff1 = { spell = 1, stats = { AGI = 110 }, duration = 20, cooldown = 120 }
			T.near(M.Total(with(richPoint({ uses = { buff } }), KINGS)), M.Total(with(richPoint({ uses = { buff1 } }), ref.statMult)), 1e-9,
				"a Use buff's Agility in the fight under Kings")
			-- statMult required in both modes, each factor 1 or more
			for _, base in ipairs({ ref, richPoint({}) }) do
				local ok, err = pcall(M.Total, with(base, nil))
				T.eq(ok, false); T.truthy(tostring(err):find("p.statMult missing", 1, true), tostring(err))
				ok, err = pcall(M.Total, with(base, { AGI = 1, STR = 1, INT = 1 }))
				T.eq(ok, false); T.truthy(tostring(err):find("p.statMult.SPI missing or below 1", 1, true), tostring(err))
				ok, err = pcall(M.Total, with(base, { AGI = 0.9, STR = 1, INT = 1, SPI = 1 }))
				T.eq(ok, false); T.truthy(tostring(err):find("p.statMult.AGI missing or below 1", 1, true), tostring(err))
				ok, err = pcall(M.ProcOutcomes, with(base, nil))
				T.eq(ok, false, base.mode .. ": ProcOutcomes checks it too")
			end
			local ok, err = pcall(M.ApplyStats, with(ref, nil), { STR = 1 })
			T.eq(ok, false); T.truthy(tostring(err):find("p.statMult.STR missing", 1, true), tostring(err))
		end },
		-- The white table (wowsims sim/core/spell_outcome.go:852-875 OutcomeExpectedMeleeWhite): a white swing is one roll,
		-- 1 - miss - dodge - parry + min(crit, the room left) - glance x (1 - its average), the room left being 1 - miss -
		-- dodge - parry - glance. The hunter's white swings alone (an unarmed main hand: no Raptor Strike or Wing Clip; one
		-- hand: no dual-wield miss; no Strider Kick or Mongoose Bite), in the Survival weave at +3 (level 43, 1% hit): miss 7%,
		-- dodge 6.5%, no parry from behind, glance 40% at 0.65, so the factor is 0.725 + min(crit, 0.465), the melee crit less
		-- 3% and 1.8% of aura crit (the 167 Agility's 4.66% crit is under 20%); the weave's cycle takes no crit
		{ "white table: one roll, crit capped by the room left; the glance takes chance x (1 - avg) off, not a factor", function()
			local function melee(meleeCrit)
				return M.Parts(svPoint({ mobDiff = 3, unarmed = true, mhDPS = 0, ohDPS = 0, meleeCrit = meleeCrit })).melee
			end
			local function factor(meleeCrit) return 0.725 + math.min((meleeCrit - 4.8) / 100, 0.465) end
			T.truthy(melee(20) > 0, "the weave's white swings")
			T.near(melee(30) / melee(20), factor(30) / factor(20), 1e-12, "the crit adds to the roll's factor")
			T.near(melee(70), melee(60), 1e-12, "past the room left the crit adds nothing")
			T.near(melee(60) / melee(20), factor(60) / factor(20), 1e-12, "capped at 0.465")
		end },
		-- Raptor Strike goes off in place of a main-hand swing (Model weaveParts): its own hit rolls hit, then crit, and the
		-- white swings are the cycle's main-hand swings less Raptor Strike's. One hand at +3 in the Survival weave (level 43,
		-- 1% hit, no expertise, no attack speed): miss 7%, dodge 6.5%, glance 40% at 0.65, the melee crit 20% less 3% and 1.8%
		-- of aura crit; the white factor 0.725 + crit, the special's 0.865 x (1 + crit). The swing 26 x 2.6 + 314 / 14 x 2.6,
		-- Raptor's +40 at 43 and Wing Clip's 25 (rank 2, from 38) on the special table, each at the weave's count a second
		-- (Model.Weave, averaged over Rapid Fire); x the armor at +3 and Focused Fire 2/2 (my arithmetic)
		{ "white table: Raptor Strike takes the white swing it replaces at the white table's factor", function()
			local p = svPoint({ mobDiff = 3, ohDPS = 0, meleeCrit = 20 })
			local c = (20 - 4.8) / 100
			local whiteF = 0.725 + c
			local swing = 26 * 2.6 + 314 / 14 * 2.6
			local r = weaveRates(p)
			T.truthy(r.raptor > 0 and r.mhWhite > 0 and r.wingClip > 0, "Raptor Strike, white swings and Wing Clip")
			T.near(r.mhWhite + r.raptor, r.auto, 1e-12, "one main-hand swing a cycle: the white ones and Raptor Strike's")
			local melee = swing * whiteF * r.mhWhite + (swing + 40) * 0.865 * (1 + c) * r.raptor + 25 * 0.865 * (1 + c) * r.wingClip
			T.near(M.Parts(p).melee, melee * M.PhysMult(43, 3) * 1.02, 1e-9)
		end },
		-- The hunter's off hand swings on the white table too (one roll, crit capped by the room left), and Strider Kick and
		-- Mongoose Bite roll hit, then crit, never capped (spell_outcome.go:852-883). At +3 in the Survival weave (level 43, 1%
		-- hit, no expertise, no attack speed), each at the weave's count a second (Model.Weave, averaged over Rapid Fire), x
		-- the armor at +3 and Focused Fire 2/2 (my arithmetic):
		-- - dual wield: the white miss 8% + 19% - 1% = 26%, dodge 6.5%, glance 40% at 0.65: the room left 27.5%, the factor
		--   0.535 + min(crit, 0.275); 10 more off-hand DPS add half of themselves a swing at that factor (the melee crit 20%:
		--   15.2% left after 3% and 1.8% of aura crit; 40% and 50%: past the room). The off hand swings where the swing timer
		--   holds the hunter in melee: a 5.0 s main hand;
		-- - unarmed, one hand: the white swings 314 / 14 x 2.6 at the white factor (capped: the melee crit 60% and 70% less
		--   4.8%, past the room of 46.5%) and Strider Kick's normalized hit 314 / 14 x 2.4 at 0.865 x (1 + crit);
		-- - one weapon with Expose Prey 3/3: the white swings, Raptor Strike (swing + 40), Wing Clip (25) and Mongoose Bite's
		--   normalized hit 26 x 2.6 + 314 / 14 x 2.4 and its rank bonus, the specials at 0.865 x (1 + crit), never capped
		-- Each melee hand rolls its own entry of the attack table by its skill (wowsims sim/core/target.go:549-615; raid-mode
		-- W1 design 3.4), the sword hand at +3 as wowsims' test has it (attack_table_test.go:87-157): 285 / 300 / 305 / 315
		-- skill miss 11 / 8 / 6 / 5%, dodge 8 / 6.5 / 6 / 5%, glance 70% at 0.01-0.30, 40% at 0.55-0.75, 0.80-0.90, 0.91-0.99,
		-- crit suppression 6 / 3 / 3 / 3%. In the weave at level 60, +3, 9% hit, no expertise, a 5.0 s main hand (the swing
		-- timer holds the hunter in melee, so the 1.8 s off hand swings in visits), dual wield (white miss + 19%), the melee crit
		-- 20% all Agility crit (no aura part). Each hand's white factor (my arithmetic): 285: miss 21%, dodge 8%, the room left
		-- 1% caps the crit 14%: 1 - 0.29 + 0.01 - 0.7 x 0.845 = 0.1285; 300: 0.755 + 0.17 - 0.4 x 0.35 = 0.785; 305: 0.78 +
		-- 0.17 - 0.4 x 0.15 = 0.89; 315: 0.80 + 0.17 - 0.4 x 0.05 = 0.95. The main hand's specials (Raptor Strike) at the model
		-- point's p.meleeHit = Model.SkillHit(3, its skill): their miss 2 / 0 / 0 / 0%, so 0.90 / 0.935 / 0.94 / 0.95 x (1 +
		-- 0.14 / 0.17 / 0.17 / 0.17). At 295 (bonus -5, my arithmetic from the same rules): miss 9%, dodge 7%, glance 50% at
		-- (0.30 + 0.60) / 2, the crit 20% - 4% under the room left 24%: 0.74 + 0.16 - 0.5 x 0.55 = 0.625, the specials 0.93 x
		-- 1.16. Ten DPS more on a hand add, a second, 10 x its speed (x 0.5 the off hand's) x its white
		-- factor x its white swings, and for the main hand Raptor Strike's hit at its count, x the armor at +3 and Focused Fire
		-- 2/2. Each hand's white swings land 1 - its miss - its dodge (Model.LandedHits), and the off hand's landed swings open
		-- Expose Prey's windows with its own miss. Mutants: the glance chance from the whole skill gap (5d - bonus); the off
		-- hand at the main hand's skill (one white roll); the dodge without the skill (Model.MobAvoid); a hand's white crit at
		-- the level's skill; the off hand's landed swings at the main hand's miss
		{ "melee skill: each hand's miss, dodge, glance and crit by its own skill (the sword hand at +3: 285 / 300 / 305 / 315 as wowsims)", function()
			local cases = { { -15, 0.1285, 0.90, 0.14 }, { -5, 0.625, 0.93, 0.16 }, { 0, 0.785, 0.935, 0.17 }, { 5, 0.89, 0.94, 0.17 },
				{ 15, 0.95, 0.95, 0.17 } }
			for _, c in ipairs(cases) do
				local b = c[1]
				if b ~= -5 then
				T.near(M.SkillDodge(3, b), ({ [-15] = 8, [0] = 6.5, [5] = 6, [15] = 5 })[b], 1e-12, "dodge at " .. (300 + b))
				local gc, ga = M.Glance(3, b)
				T.near(gc, b < 0 and 0.7 or 0.4, 1e-12, "glance chance at " .. (300 + b))
				T.near(ga, ({ [-15] = 0.155, [0] = 0.65, [5] = 0.85, [15] = 0.95 })[b], 1e-12, "glance damage at " .. (300 + b))
				end
			end
			-- the pet's and the hawks' table, bonus 0, at +0: 10% at 0.95; none below the player's level
			local gc0, ga0 = M.Glance(0, 0)
			T.near(gc0, 0.1, 1e-12); T.near(ga0, 0.95, 1e-12); T.near(M.GlanceMult(3), 1 - 0.4 * 0.35, 1e-12)
			for _, fn in ipairs({ "Glance", "SkillDodge" }) do
				local ok, err = pcall(M[fn], 3, nil)
				T.eq(ok, false, fn); T.truthy(tostring(err):find("Model." .. fn .. " without a skill bonus", 1, true), tostring(err))
			end
			local scale = M.PhysMult(60, 3) * 1.02
			local function point(over)
				local o = { level = 60, mobDiff = 3, hit = 9, agi = 20 / M.CritPerAgility(60), crit = 20, meleeCrit = 20,
					mhSpeed = 5.0, ohSpeed = 1.8 }
				for k, v in pairs(over) do o[k] = v end
				return svPoint(o)
			end
			-- both hands 26 DPS (the reference state); 10 more on one
			local function slope(over, key)
				local up = {}
				for k, v in pairs(over) do up[k] = v end
				up[key] = 26 + 10
				return (M.Parts(point(up)).melee - M.Parts(point(over)).melee) / 10
			end
			local r = weaveRates(point({}))
			T.truthy(r.oh > 0 and r.raptor > 0, "the off hand swings, Raptor Strike in the weave")
			for _, c in ipairs(cases) do
				local b, roll, hitSpecial, crit = c[1], c[2], c[3], c[4]
				-- the off hand at its skill, the main hand at the level's
				T.near(slope({ ohSkill = b }, "ohDPS"), 0.5 * 1.8 * roll * r.oh * scale, 1e-9, "the off hand at " .. (300 + b))
				-- the main hand at its skill (its skill hit at the model point), the off hand at the level's
				T.near(slope({ mhSkill = b, meleeHit = M.SkillHit(3, b) }, "mhDPS"),
					5.0 * (roll * r.mhWhite + hitSpecial * (1 + crit) * r.raptor) * scale, 1e-9, "the main hand at " .. (300 + b))
				-- the off hand's roll is its own: the main hand's skill leaves it
				T.near(slope({ mhSkill = b, meleeHit = M.SkillHit(3, b) }, "ohDPS"), 0.5 * 1.8 * 0.785 * r.oh * scale, 1e-9,
					"the off hand at 300, the main hand at " .. (300 + b))
				-- each hand's landed white swings: 1 - its white miss (its skill's + 19% - 9%) - its dodge
				local wmiss = (M.SkillMiss(3, b) + 19 - 9 + M.SkillDodge(3, b)) / 100
				local hOH = M.LandedHits(point({ ohSkill = b }))
				T.near(hOH.oh.swings, r.oh * (1 - wmiss), 1e-12, "the off hand's landed swings at " .. (300 + b))
				T.near(hOH.mh.swings, r.mhWhite * (1 - 0.245), 1e-12, "the main hand's at 300 with the off hand at " .. (300 + b))
				local hMH = M.LandedHits(point({ mhSkill = b, meleeHit = M.SkillHit(3, b) }))
				T.near(hMH.mh.swings, r.mhWhite * (1 - wmiss), 1e-12, "the main hand's landed swings at " .. (300 + b))
			end
			-- Expose Prey's windows from the off hand's landed swings: fewer at 285 than at 300
			local function epPoint(ohSkill)
				local o = { level = 60, mobDiff = 3, hit = 9, agi = 20 / M.CritPerAgility(60), crit = 20, meleeCrit = 20,
					mhSpeed = 5.0, ohSpeed = 1.8, ohSkill = ohSkill }
				return svPoint(o, { exposePrey = 2 })
			end
			T.truthy(weaveRates(epPoint(-15)).bite < weaveRates(epPoint(0)).bite - 1e-9, "the off hand's misses open fewer windows")
		end },
		-- The main hand's specials miss by the level's skill less p.hit and p.meleeHit, the skill hit of the model point
		-- (Model.SkillHit of the worn main hand's skill, which a set's weapon run holds while p.mhSkill moves: Score prices the
		-- set's skill hit through the cap, raid-mode W1 design 3.4); p.mhSkill moves their dodge. At +3 with 9% hit and one 5.0
		-- s main hand, 15 below its maximum: with p.meleeHit 0 Raptor Strike and Wing Clip land 1 - 0 - 8% (the miss 8% - 9%
		-- floored at 0, the dodge 5% + 0.1% x 30), against 1 - 0 - 6.5% at the level's skill; with p.meleeHit -3
		-- (Model.SkillHit(3, -15)) 1 - 2% - 8% (my arithmetic). Mutant: the specials' miss from p.mhSkill (Model.SkillMiss(d,
		-- p.mhSkill) - p.hit)
		{ "melee skill: the main hand's specials miss by p.meleeHit, their dodge by p.mhSkill", function()
			local function specials(over)
				local o = { level = 60, mobDiff = 3, hit = 9, mhSpeed = 5.0, ohDPS = 0 }
				for k, v in pairs(over) do o[k] = v end
				return M.LandedHits(svPoint(o)).mh.specials
			end
			local level = specials({})
			T.truthy(level > 0, "Raptor Strike and Wing Clip land")
			T.near(specials({ mhSkill = -15 }), level * 0.92 / 0.935, 1e-12, "p.meleeHit 0: the dodge alone")
			T.near(specials({ mhSkill = -15, meleeHit = M.SkillHit(3, -15) }), level * 0.90 / 0.935, 1e-12, "p.meleeHit -3: 2% miss")
		end },
		{ "white table: the hunter's off hand; Strider Kick and Mongoose Bite roll hit, then crit, uncapped", function()
			local scale = M.PhysMult(43, 3) * 1.02
			local slow = { mobDiff = 3, mhSpeed = 5.0 }
			local function with(over, add)
				local o = {}
				for k, v in pairs(over) do o[k] = v end
				for k, v in pairs(add) do o[k] = v end
				return o
			end
			local oh = weaveRates(svPoint(slow)).oh
			T.truthy(oh > 0, "the off hand swings while the swing timer holds the hunter in melee")
			local function ohGain(crit)
				return M.Parts(svPoint(with(slow, { meleeCrit = crit, ohDPS = 36 }))).melee
					- M.Parts(svPoint(with(slow, { meleeCrit = crit }))).melee
			end
			T.near(ohGain(20), 0.5 * 10 * 2.6 * (0.535 + 0.152) * oh * scale, 1e-9, "the off hand's white factor")
			T.near(ohGain(40), 0.5 * 10 * 2.6 * (0.535 + 0.275) * oh * scale, 1e-9, "the off hand's crit capped by the room left")
			T.near(ohGain(50), ohGain(40), 1e-9, "nothing past the room")
			-- Strider Kick, unarmed: the white swings capped, the kick hit then crit
			local function kickPoint(crit) return svPoint({ mobDiff = 3, meleeCrit = crit, unarmed = true, mhDPS = 0, ohDPS = 0 }, { striderKick = 1 }) end
			local rk = weaveRates(kickPoint(60))
			T.truthy(rk.strider > 0, "Strider Kick in the weave")
			local kick = 314 / 14 * 2.4 * 0.865 * rk.strider
			T.near(M.Parts(kickPoint(60)).melee, (314 / 14 * 2.6 * (0.725 + 0.465) * rk.mhWhite + kick * (1 + 0.552)) * scale, 1e-9,
				"Strider Kick: hit, then crit")
			T.near(M.Parts(kickPoint(70)).melee - M.Parts(kickPoint(60)).melee, kick * 0.10 * scale, 1e-9, "Strider Kick: no cap")
			-- Mongoose Bite with a weapon
			local function bitePoint(crit) return svPoint({ mobDiff = 3, meleeCrit = crit, ohDPS = 0 }, { exposePrey = 3 }) end
			local rb = weaveRates(bitePoint(60))
			T.truthy(rb.bite > 0, "Mongoose Bite in the weave")
			local swing = 26 * 2.6 + 314 / 14 * 2.6
			local norm = 26 * 2.6 + 314 / 14 * 2.4
			local specials = (swing + 40) * rb.raptor + 25 * rb.wingClip + (norm + M.Rank("mongooseBonus", 43)) * rb.bite
			T.near(M.Parts(bitePoint(60)).melee, (swing * (0.725 + 0.465) * rb.mhWhite + specials * 0.865 * (1 + 0.552)) * scale, 1e-9,
				"Mongoose Bite: hit, then crit")
			T.near(M.Parts(bitePoint(70)).melee - M.Parts(bitePoint(60)).melee, specials * 0.865 * 0.10 * scale, 1e-9, "Mongoose Bite: no cap")
		end },
		-- The pet's Claw and Bite roll hit, then crit (spell_outcome.go:876-883): (1 - miss - dodge - parry) x (1 + crit),
		-- never capped by the white table's room. With the pet's white swings capped (+3, the pet tanking: miss 7%, dodge
		-- 6.5%, parry 14%, glance 40%: room 32.5%) and no Frenzy (its crit chance per attack would move the swings), more crit
		-- adds that much of the specials' landed damage alone: Claw and Bite of an unknown family at 43 (Bite 54 every 10 s,
		-- (120 - 35) / 25 Claws of 31: 15.94 a second) x the pet's multipliers (happiness 1.25, Unleashed Fury 15% and the orc's
		-- 5%, Focused Fire 2%, Bestial Wrath's average 1.075) x the armor at +3. The room left takes the parry off: the owner's
		-- 30% and 35% of crit leave the pet 35.2% and 40.2% (with 10% Ferocity, less 3% and 1.8% of aura crit), past the room
		-- with the parry (32.5%) and under the room without it (46.5%), so the white swings stay capped there too
		{ "pet specials: two rolls, hit then crit, no cap; the white swings capped by the room", function()
			local function pet(crit)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.frenzy = 0
				p.tal, p.mobDiff, p.crit, p.meleeCrit = tal, 3, crit, crit
				return M.Parts(p).pet
			end
			local special = 15.94 * 1.25 * 1.20 * 1.02 * 1.075 * M.PhysMult(43, 3)
			T.near(pet(60) - pet(50), special * (1 - 0.07 - 0.065 - 0.14) * 0.10, 1e-9, "the specials' 10% crit")
			T.near(pet(35) - pet(30), special * (1 - 0.07 - 0.065 - 0.14) * 0.05, 1e-9, "the white swings capped at the room left less the parry")
		end },
		-- Parry (wowsims sim/core/target.go:585-590): 5% + 0.1% a point of the skill gap 5 x the level difference up to 10
		-- points, 5% + 0.6% a point past it: 5 / 5.5 / 6 / 14% at +0..+3, +4 and +5 as +3
		{ "parry: 5 / 5.5 / 6 / 14% at +0..+3", function()
			for d, want in pairs({ [0] = 5, [1] = 5.5, [2] = 6, [3] = 14, [4] = 14, [5] = 14 }) do
				T.near(M.PetParry(d), want, 1e-12, "+" .. d)
			end
			T.eq(pcall(M.PetParry, nil), false, "without a mob level difference")
		end },
		-- Parry only from the front (spell_outcome.go:885-893): with the pet behind the target (CONST.petTanks 0) expertise
		-- past the dodge adds nothing to the pet, and W.EXPERTISE_PARRY is 0
		{ "parry: none from behind; the tanking pet gains past the dodge up to the parry", function()
			local function pet(e)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.mobDiff, p.expertise = 3, e
				return M.Parts(p).pet
			end
			T.truthy(pet(10) > pet(6.5) + 1e-6, "tanking: the parry past the dodge")
			T.near(pet(16), pet(14), 1e-12, "tanking: nothing past the 14% parry")
			local p3 = {}
			for k, v in pairs(ref) do p3[k] = v end
			p3.mobDiff = 3
			T.truthy(M.Weights(p3).EXPERTISE_PARRY > 0, "W.EXPERTISE_PARRY while the pet tanks")
			M.CONST.petTanks = 0
			local behind, behindW = pet(10) - pet(6.5), M.Weights(p3).EXPERTISE_PARRY
			M.CONST.petTanks = 1
			T.near(behind, 0, 1e-12, "behind: no parry")
			T.near(behindW, 0, 1e-12, "behind: W.EXPERTISE_PARRY 0")
		end },
		-- The outcome of a proc's damage by its table (Model.ProcOutcomes; wowsims sim/common/shared/shared_utils.go:76-119,
		-- target.go:540-547, spell_result.go:196-231, 287-318, spell.go:959-975): magic, 1 - max(0, the spell miss - spell
		-- hit), the spell miss 4% + 1% a level of the difference and 17% at +3, no floor; crit x1.5 at the spell crit, never
		-- suppressed. melee and ranged: the main hand's table (the proc spell's ProcMaskEmpty) with the physical hit alone
		-- (p.hit: no ranged gear hit, no ranged skill hit), the melee crit (the physical crit, no ranged crit) suppressed as the
		-- melee crit, crit x2; melee less the dodge (expertise lowers it), from behind no parry. No DefenseType by the school.
		{ "proc outcome: magic 17% at +3, 4% at +0, less spell hit, x1.5 crit never suppressed; melee and ranged on the main hand", function()
			local function point(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.level, p.agi, p.spellCrit = 60, 300, 5
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			for d, miss in pairs({ [0] = 0.04, [1] = 0.05, [2] = 0.06, [3] = 0.17, [5] = 0.17 }) do
				local o = M.ProcOutcomes(point({ mobDiff = d }))
				T.near(o[1].hit, 1 - miss, 1e-12, "magic at +" .. d)
				T.near(o[1].critMult, 1 + 0.5 * 0.05, 1e-12, "x1.5 at the whole spell crit at +" .. d)
				T.eq(o[0].magic, o[1], "no DefenseType, magic school: the spell table"); T.eq(o[0].physical, o[2], "physical: the melee table")
			end
			T.near(M.ProcOutcomes(point({ mobDiff = 3, spellHit = 5 }))[1].hit, 0.88, 1e-12, "+3 less 5% spell hit")
			T.near(M.ProcOutcomes(point({ mobDiff = 3, spellHit = 20 }))[1].hit, 1, 1e-12, "no miss past 17% spell hit")
			-- +3, 3% hit, 4% ranged gear hit, 2% ranged skill hit, 1% expertise; melee crit 12% (Agility's 300 x the crit per
			-- Agility, the rest aura crit, more than 1.8%), ranged crit 20%
			local cpa = M.CritPerAgility(60)
			local p = point({ mobDiff = 3, hit = 3, rangedGearHit = 4, rangedHit = 2, expertise = 1, meleeCrit = 12, crit = 20 })
			local o = M.ProcOutcomes(p)
			T.truthy(12 - cpa * 300 > 1.8, "the aura crit past 1.8%")
			local critM = (12 - 3 - 1.8) / 100
			T.near(o[2].hit, 1 - 0.05 - (0.065 - 0.01), 1e-12, "melee: 8% - 3% hit, 6.5% - 1% dodge")
			T.near(o[3].hit, 1 - 0.05, 1e-12, "ranged: 8% - 3% hit, no ranged gear or skill hit, no dodge")
			T.near(o[2].critMult, 1 + critM, 1e-12, "melee: the melee crit less 3% and 1.8%")
			T.near(o[3].critMult, 1 + critM, 1e-12, "ranged: the melee crit, not the ranged crit")
			T.near(o.phys, M.PhysMult(60, 3), 1e-12, "the armor of the target")
			-- a damage over time (raid-mode design 17): its application rolls the table once without crit (land, the share that
			-- lands: shared_utils.go:730), its ticks crit by the table's crit (tickCrit: the spell crit x1.5 of the magic table,
			-- the physical crit x2 of the melee and ranged ones, spell.go:368-377)
			for i, want in pairs({ [1] = { 1 - 0.17, 1 + 0.5 * 0.05 }, [2] = { 1 - 0.05 - 0.055, 1 + critM }, [3] = { 0.95, 1 + critM } }) do
				T.near(o[i].land, want[1], 1e-12, "table " .. i .. ": the application's chance, no crit")
				T.near(o[i].tickCrit, want[2], 1e-12, "table " .. i .. ": the ticks' crit")
			end
			T.eq(o[0].magic.land, o[1].land); T.eq(o[0].physical.tickCrit, o[2].tickCrit)
		end },
		-- A proc's melee or ranged table is the main hand's entry (ProcMaskEmpty, wowsims sim/core/target.go:606-615) at the
		-- main hand's skill (raid-mode W1 design 3.4); a magic proc's spell miss is the table's level-based one, no hand's
		-- (spell_result.go:287-288). +3, the main hand at 285 (bonus -15), 3% hit, 1% expertise, the melee crit 10% all Agility
		-- crit: melee 1 - (11 - 3)% - (8 - 1)% = 0.85, ranged 1 - 8% = 0.92, each crit 10% - 6% (my arithmetic); magic 17%
		-- whatever the hand. Mutants: the level's skill for the physical tables; the dodge at Model.MobAvoid; the hand's skill
		-- on the spell miss
		{ "proc outcome: a melee-defense proc rolls the main hand's skill table (miss, dodge and crit suppression), a ranged-defense one its miss and crit, a magic one the level's spell miss", function()
			local function point(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.level, p.mobDiff, p.hit, p.expertise, p.agi = 60, 3, 3, 1, 10 / M.CritPerAgility(60)
				p.crit, p.meleeCrit = 10, 10
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			local o = M.ProcOutcomes(point({ mhSkill = -15 }))
			T.near(o[2].hit, 1 - 0.08 - 0.07, 1e-12, "melee: the hand's 11% miss less 3%, its 8% dodge less 1%")
			T.near(o[3].hit, 1 - 0.08, 1e-12, "ranged: the hand's miss, no dodge")
			T.near(o[2].critMult, 1 + 0.10 - 0.06, 1e-12, "melee: the hand's 6% suppression")
			T.near(o[3].critMult, 1 + 0.10 - 0.06, 1e-12, "ranged: the same")
			local o0 = M.ProcOutcomes(point({ mhSkill = 0 }))
			T.near(o0[2].hit, 1 - 0.05 - 0.055, 1e-12, "melee at 300"); T.near(o0[2].critMult, 1.07, 1e-12)
			T.near(o[1].hit, 0.83, 1e-12, "magic: 17% at +3"); T.eq(o[1].hit, o0[1].hit, "magic: no hand's skill")
			local above = M.ProcOutcomes(point({ mhSkill = 15 }))
			T.near(above[2].hit, 1 - 0.02 - 0.04, 1e-12, "melee at 315: 5% - 3%, 5% - 1%"); T.near(above[2].critMult, 1.07, 1e-12)
			-- at +0 the level's 4%, whatever the hand
			T.near(M.ProcOutcomes(point({ mobDiff = 0, mhSkill = -15 }))[1].hit, 0.96, 1e-12, "magic at +0, the hand 15 below")
		end },
		-- a proc spell takes the hunter's damage multipliers (no SpellFlagIgnoreAttackerModifiers, wowsims
		-- sim/core/spelldata/resolve_spell.go:221-233; spell_result.go:916-927): Focused Fire with the pet out, Lone Wolf with
		-- none, Improved Tracking; not Ranged Weapon Specialization (bound to the ranged proc mask)
		{ "proc outcome: own = Focused Fire x Lone Wolf x Improved Tracking, no Ranged Weapon Specialization", function()
			local function own(tover, over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return M.ProcOutcomes(p).own
			end
			T.near(own({}), 1.02, 1e-12, "Focused Fire 2/2 with the pet out")
			T.near(own({ improvedTracking = 3 }), 1.02 * 1.03, 1e-12, "and Improved Tracking 3/5")
			T.near(own({ loneWolf = 1, focusedFire = 2 }, { petOut = false }), 1.2, 1e-12, "Lone Wolf with no pet: no Focused Fire")
			T.near(own({ rangedWeaponSpec = 5 }), 1.02, 1e-12, "no Ranged Weapon Specialization")
		end },
		-- The dives in the landed hits (Model.LandedHits): Summon Hawk's dive is the hunter's spell with
		-- ProcMaskRangedSpecial that always lands (wowsims sim/hunter/summon_hawk.go:130-139), two a 18 s with hawks, without a
		-- ranged weapon too (Summon Hawk has no SpellEquippedItems row), none in the Survival weave (its preset casts no
		-- Summon Hawk); the ranged hand's speed is 0 with no weapon in the ranged slot (p.bowDPS 0), the bow's with one (a
		-- thrown weapon's too: bowDPS above 0)
		{ "landed hits: the dives in the ranged specials with hawks; the ranged speed 0 without a ranged weapon", function()
			local function hits(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return M.LandedHits(p).ranged
			end
			local with = hits({})
			T.eq(hits({ noShots = true, bowDPS = 0 }, { summonHawk = 0 }).specials, 0, "no Summon Hawk: no dive")
			T.eq(hits({ survival = true, noShots = true, bowDPS = 0 }).specials, 0, "the Survival branch: no Summon Hawk, no dive")
			T.eq(hits({ level = 24 }).specials, hits({ level = 24 }, { summonHawk = 0 }).specials, "no hawks before 25")
			local bare = hits({ noShots = true, bowDPS = 0 })
			T.near(bare.specials, 2 / 18, 1e-12, "no ranged weapon: the dives alone"); T.eq(bare.swings, 0); T.eq(bare.speed, 0)
			T.eq(hits({ noShots = true, bowDPS = 15, bowSpeed = 2.1 }).speed, 2.1, "a thrown weapon: its speed")
			T.eq(with.speed, ref.bowSpeed)
		end },
		{ "wowsims check: hawks take the bow's DPS, not the ammo's", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			local before = M.Parts(p).hawks
			p.ammoDPS = p.ammoDPS + 5
			T.near(M.Parts(p).hawks, before, 1e-9, "ammo leaves the hawks alone")
			p.bowDPS = p.bowDPS + 5
			T.truthy(M.Parts(p).hawks > before, "the bow raises hawk AP")
		end },
		{ "wowsims check: pet family passive and abilities, parry when the pet tanks", function()
			local function pet(family, bd)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.bestialDiscipline = bd or tal.bestialDiscipline
				p.tal, p.petFamily = tal, family
				return M.Parts(p).pet
			end
			-- Cat and Raptor +10%, Boar and Turtle -10%; Wolf learns Bite but no Claw
			T.truthy(pet(2) > pet(nil), "Cat above an unknown family")
			T.truthy(pet(5) < pet(1), "Boar below Wolf")
			T.near(pet(11) / pet(2), 1, 1e-9, "Raptor = Cat")
			-- Bestial Discipline adds focus, which only Claw spends: a Wolf gains nothing from it
			T.near(pet(1, 2), pet(1, 0), 1e-9, "Wolf: Bestial Discipline does not add Bites")
			T.truthy(pet(2, 2) > pet(2, 0), "Cat: more Claws")
			-- the pet tanks, so expertise lowers parry too: the pet's part moves twice as much as with dodge alone (the
			-- hawks and the hunter's melee take expertise against dodge alone)
			local function petByExpertise()
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local before = M.Parts(p).pet
				p.expertise = 0.5
				return M.Parts(p).pet - before
			end
			local e1 = petByExpertise()
			M.CONST.petTanks = 0
			local e0 = petByExpertise()
			M.CONST.petTanks = 1
			T.truthy(e0 > 0, "dodge alone moves the pet")
			T.near(e1 / e0, 2, 1e-9, "dodge and parry")
		end },
		{ "wowsims check: shot shares, Multi-Shot before Aimed, book ranks, Rapid Killing", function()
			local function parts(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.survival = false
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return M.Parts(p)
			end
			T.truthy(parts({ level = 18 }).multi > 0 and parts({ level = 19 }).multi > 0, "Multi-Shot at 18-19")
			T.eq(parts({ level = 17 }).multi, 0); T.eq(parts({ level = 20 }).multi, 0, "Aimed takes its cooldown at 20")
			T.eq(parts({ level = 19 }).aimed, 0)
			-- next to Sniper Shot, Aimed Shot uses less of its cooldown
			local alone, withSniper = parts({ level = 48 }), parts({ level = 48 }, { sniperShot = 1 })
			T.near(withSniper.aimed / alone.aimed, M.CONST.aimedUseSniper / M.CONST.aimedUse, 1e-9)
			-- Serpent Sting IX and Aspect of the Hawk VII are books: the trainer ranks stop at 58
			T.eq(M.Rank("serpentTick", 60), 100); T.eq(M.Rank("aspectHawk", 60), 110)
			local book = parts({ level = 60, serpentTick = 135 }).serpent
			T.truthy(book > parts({ level = 60 }).serpent, "the book rank counts when the spell is known")
			-- Rapid Killing: the next Aimed Shot after each kill hits harder
			T.truthy(parts({}, { rapidKilling = 2 }).aimed > parts({}).aimed)
		end },
		{ "wowsims check: Raptor waits for a swing; dual-wield hit past the cap; Expose Prey in a weave", function()
			-- the Survival weave (Model weaveParts)
			local function melee(over, tover) return svPoint(over, tover) end
			-- hit above the 5% cap still lowers dual-wield white misses
			T.truthy(M.Parts(melee({ hit = 7 })).melee > M.Parts(melee({ hit = 6 })).melee, "DW: 7% hit beats 6%")
			local th = { twoH = true, ohDPS = 0, mhDPS = 34, mhSpeed = 3.3 }
			local th6, th7 = melee(th), melee(th)
			th6.hit, th7.hit = 6, 7
			T.near(M.Parts(th7).melee, M.Parts(th6).melee, 1e-9, "two-hander: nothing past the cap")
			T.truthy(M.Weights(melee()).HIT_DW > 0, "HIT_DW in the weave")
			T.eq(M.Weights(melee({ survival = false })).HIT_DW, 0, "no melee, no HIT_DW")
			-- Raptor Strike goes off in a main-hand swing's place once a cycle at most, and the cycle is set by the ranged path
			-- here (a 2.6 s bow): at equal DPS the 3.0 s weapon hits harder at the same count
			local fast = M.Parts(melee({ mhSpeed = 2.6 })).melee
			local slow = M.Parts(melee({ mhSpeed = 3.0 })).melee
			T.truthy(slow > fast, "3.0 s weapon: the same swings, each harder than the 2.6 s weapon's")
			local sv = { exposePrey = 2 }
			-- Lacerating Strikes: the next bite replaces the bleed, so frequent bites keep less of it
			local lsGain = M.Parts(melee({}, { exposePrey = 2, laceratingStrikes = 1 })).melee - M.Parts(melee({}, sv)).melee
			local biteGain = M.Parts(melee({}, sv)).melee - M.Parts(melee()).melee
			T.truthy(lsGain / biteGain < 0.40, "less than the full 40% of each bite: " .. lsGain / biteGain)
		end },
		-- the spec research of 2026-11-14 (MM / SV / BM / client API), each rule as a test
		{ "spec: Lone Wolf without a pet: no pet, hunter +20%, Focused Fire off, expertise the hawks' alone", function()
			local function build(lw, petOut)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.loneWolf = lw
				p.tal, p.petOut, p.survival = tal, petOut, false
				return p
			end
			local withPet = M.Parts(build(0, true))
			local lwAlone = M.Parts(build(1, false))
			local lwPet = M.Parts(build(1, true))
			T.eq(lwAlone.pet, 0, "no pet out")
			-- Focused Fire 2/2 goes away with the pet, Lone Wolf +20% comes
			T.near(lwAlone.auto / withPet.auto, 1.2 / 1.02, 1e-9, "Auto Shot x1.2 / Focused Fire")
			T.near(lwPet.auto, withPet.auto, 1e-9, "Lone Wolf with a pet out: hunter unchanged")
			T.near(lwPet.pet / withPet.pet, 1 / 1.2, 1e-9, "Lone Wolf with a pet out: pet / 1.2")
			-- no pet and no melee (the BM build): expertise feeds the hawks alone, and nothing without Summon Hawk
			local alone = build(1, false)
			local W, dRap = M.Weights(alone)
			local hawksAt = function(e) local q = {} for k, v in pairs(alone) do q[k] = v end q.expertise = e return M.Parts(q).hawks end
			T.truthy(W.EXPERTISE > 0.5, "the hawks take the owner's expertise: " .. W.EXPERTISE)
			T.near(W.EXPERTISE, (hawksAt(0.5) - hawksAt(0)) / 0.5 / dRap, 1e-9, "expertise is the hawks' alone")
			alone.tal.summonHawk = 0
			T.eq(M.Weights(alone).EXPERTISE, 0, "no pet, no hawks, no melee: expertise worthless")
			-- hawks take the hunter's all-school multiplier: Lone Wolf like Focused Fire
			T.near(lwAlone.hawks / withPet.hawks, 1.2 / 1.02, 1e-9, "hawks x1.2 / Focused Fire")
			local low = build(0, true); low.level = 9
			T.eq(M.Parts(low).pet, 0, "no pet before level 10")
		end },
		{ "spec: Arcane Shot every 6 s (Improved Arcane Shot) without hawks, 1 per 18 s with them", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.survival = false
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			p.tal = tal
			local hawks = M.Parts(p).arcane
			tal.summonHawk = 0
			local own = M.Parts(p).arcane
			T.near(own / hawks, M.CONST.arcaneUse * 18 / 6, 1e-9, "cooldown 6 s, used ~90%")
			tal.improvedArcaneShot = 5
			T.near(M.Parts(p).arcane / own, 6 / 4.5, 1e-9, "Improved Arcane Shot 5/5: 4.5 s")
			-- weapon DPS is worth less when a weapon-independent shot carries more damage
			T.truthy(M.Weights(p).RANGED_DPS < M.Weights(ref).RANGED_DPS)
		end },
		{ "spec: Sniper Shot only with the talent and from level 40, not raised by Barrage", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			p.tal = tal
			T.eq(M.Parts(p).sniper, 0, "not talented")
			tal.sniperShot = 1
			T.truthy(M.Parts(p).sniper > 0)
			local p39 = {}
			for k, v in pairs(p) do p39[k] = v end
			p39.level = 39
			T.eq(M.Parts(p39).sniper, 0, "learned at 40")
			T.eq(M.Rank("sniperBonus", 48), 450)
			local before = M.Parts(p).sniper
			tal.barrage = 3
			T.near(M.Parts(p).sniper, before, 1e-9, "Barrage: Aimed / Multi / Volley only")
		end },
		{ "spec: Rapid Fire average from 26, Rapid Killing shortens its cooldown", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.survival = false
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			p.tal = tal
			local a0 = M.Parts(p)
			tal.rapidKilling = 2
			local a2 = M.Parts(p)
			T.near(a2.auto / a0.auto, (1 + 0.4 * 15 / 180) / (1 + 0.4 * 15 / 300), 1e-9)
			local low = {}
			for k, v in pairs(p) do low[k] = v end
			low.level = 25
			local l0 = M.Parts(low)
			low.tal = M.DEFAULT_TALENTS
			T.near(M.Parts(low).auto, l0.auto, 1e-9, "no Rapid Fire below 26: Rapid Killing changes nothing")
		end },
		{ "spec: survival melee: Strider Kick, Expose Prey + Lacerating Strikes, Improved Tracking", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.survival = true
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			p.tal = tal
			local W0 = M.Weights(p)
			tal.striderKick = 1; tal.exposePrey = 2; tal.laceratingStrikes = 1; tal.savageStrikes = 2; tal.predatorsEdge = 5
			local W1 = M.Weights(p)
			T.truthy(W1.MH_DPS > W0.MH_DPS * 1.2, "main-hand DPS worth more: " .. W0.MH_DPS .. " -> " .. W1.MH_DPS)
			T.truthy(W1.TH_DPS > W0.TH_DPS, "two-hander too")
			local function melee(over)
				local q = {}
				for k, v in pairs(p) do q[k] = v end
				local t = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do t[k] = v end
				for k, v in pairs(over) do t[k] = v end
				q.tal = t
				return M.Parts(q).melee
			end
			-- the Lacerating bleed can crit: Savage Strikes raises its value
			local lsPlain = melee({ exposePrey = 2, laceratingStrikes = 1 }) - melee({ exposePrey = 2 })
			local lsSS = melee({ exposePrey = 2, laceratingStrikes = 1, savageStrikes = 2 }) - melee({ exposePrey = 2, savageStrikes = 2 })
			local biteSS = melee({ exposePrey = 2, savageStrikes = 2 }) - melee({ savageStrikes = 2 })
			local bitePlain = melee({ exposePrey = 2 }) - melee({})
			T.truthy(lsSS / biteSS > lsPlain / bitePlain + 1e-6, "bleed share grows with ability crit")
			-- Model without talent ranks is a bug, not a default build
			local bad = {}
			for k, v in pairs(ref) do bad[k] = v end
			bad.tal = nil
			T.truthy(not pcall(M.Parts, bad), "no p.tal -> error")
			T.truthy(not pcall(M.SecondaryRates, nil), "no ranks -> error")
			-- shots not learned yet do not count: Serpent Sting from 4, Arcane Shot from 6
			local young = {}
			for k, v in pairs(ref) do young[k] = v end
			young.level = 3
			local yp = M.Parts(young)
			T.eq(yp.serpent, 0); T.eq(yp.arcane, 0)
			-- Improved Tracking: the hunter's own damage only (the pet and hawks keep theirs)
			local q = {}
			for k, v in pairs(ref) do q[k] = v end
			local t2 = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do t2[k] = v end
			q.tal = t2
			local base = M.Parts(q)
			t2.improvedTracking = 5
			local tr = M.Parts(q)
			T.near(tr.auto / base.auto, 1.05, 1e-9); T.near(tr.pet, base.pet, 1e-9); T.near(tr.hawks, base.hawks, 1e-9)
		end },
		-- ranks without a talent the model reads are a bug (Player.ReadTalents names every talent of Player.BRANCHES): Lone
		-- Wolf in Model.Parts and Model.Weights, Rapid Killing in Model.Parts, Survivalist in Model.SecondaryRates
		{ "talent ranks without a talent the model reads are an error in Parts, Weights and SecondaryRates", function()
			for _, case in ipairs({ { "loneWolf", M.Parts }, { "loneWolf", M.Weights }, { "rapidKilling", M.Parts },
				{ "survivalist", function(p) return M.SecondaryRates(p.tal) end } }) do
				local short = {}
				for k, v in pairs(ref) do short[k] = v end
				short.tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do short.tal[k] = v end
				short.tal[case[1]] = nil
				local ok, err = pcall(case[2], short)
				T.eq(ok, false, "ranks without " .. case[1])
				T.truthy(tostring(err):find("talent ranks without " .. case[1], 1, true), tostring(err))
			end
		end },
		-- Every input Player.Snapshot, Player.WeaponInputs and Advisor A.State always set is required (Core/Model.lua
		-- checkInputs): one missing is an error naming it, in every entry that runs a pass (Parts, LandedHits, Total,
		-- TotalAndHits, Weights); PhysMult, GlanceMult and MobAvoid need a mob level difference. The inputs a real state leaves nil (serpentTick, petFamily, petSwing, orc) are no error; an input of
		-- the wrong type (a number given as a string, a flag given as a number or a string) is an error naming it as well.
		{ "a model input every producer sets is required: one missing or of the wrong type is an error naming it; the optional ones may be nil", function()
			local REQUIRED = { "level", "rap", "map", "agi", "crit", "meleeCrit", "hit", "rangedHit", "rangedSkill", "meleeHit",
				"mhSkill", "ohSkill", "rangedGearHit", "expertise",
				"haste", "attackSpeed", "hasteRating", "meleeHaste", "rangedHaste", "bowDPS", "bowSpeed", "ammoDPS", "quiver", "mobDiff", "mhDPS",
				"mhSpeed", "mhNorm", "ohDPS", "ohSpeed", "beastSlaying", "apVsTarget", "spellHit", "spellCrit", "twoH", "unarmed",
				"noShots", "survival", "petOut" }
			local entries = { Parts = M.Parts, LandedHits = M.LandedHits, Total = M.Total, TotalAndHits = M.TotalAndHits, Weights = M.Weights }
			for _, key in ipairs(REQUIRED) do
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p[key] = nil
				for name, fn in pairs(entries) do
					local ok, err = pcall(fn, p)
					T.eq(ok, false, name .. " without p." .. key)
					T.truthy(tostring(err):find("Model input p." .. key .. " missing", 1, true), name .. ": " .. tostring(err))
				end
			end
			-- a flag given as nil is no false: the shots, the Survival branch and the hands are each read as given
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.noShots = nil
			T.eq(pcall(M.Parts, p), false, "noShots nil is not 'shoots'")
			for _, fn in ipairs({ "PhysMult", "GlanceMult", "MobAvoid" }) do
				local ok, err = pcall(fn == "PhysMult" and function() return M.PhysMult(43, nil) end or M[fn], nil)
				T.eq(ok, false, fn .. " without mobDiff")
				T.truthy(tostring(err):find("Model." .. fn .. " without a mob level difference", 1, true), tostring(err))
			end
			-- a wrong type: Lua reads 0 and a string as true, so a flag that is no boolean, or a number given as a string, raises
			for _, bad in ipairs({ { "rap", "500", "missing or not a number" }, { "survival", 0, "missing or not true / false" },
				{ "noShots", "no", "missing or not true / false" }, { "petOut", 1, "missing or not true / false" } }) do
				local q = {}
				for k, v in pairs(ref) do q[k] = v end
				q[bad[1]] = bad[2]
				local ok, err = pcall(M.Total, q)
				T.eq(ok, false, "p." .. bad[1] .. " = " .. tostring(bad[2]))
				T.truthy(tostring(err):find("Model input p." .. bad[1] .. " " .. bad[3], 1, true), tostring(err))
			end
			-- the optional inputs: nil is a real state (no book rank, no pet seen, no swing read, a secret race)
			local opt = {}
			for k, v in pairs(ref) do opt[k] = v end
			opt.serpentTick, opt.petFamily, opt.petSwing, opt.orc = nil, nil, nil, nil
			T.truthy(M.Total(opt) > 0, "the optional inputs nil")
			T.truthy(M.Weights(opt).RAP == 1, "Weights with the optional inputs nil")
		end },
		-- p.mode (Core/Model.lua checkMode): "level" or "raid", anything else an error in every entry that runs a pass
		{ "mode: p.mode other than raid / level is an error", function()
			local entries = { Parts = M.Parts, LandedHits = M.LandedHits, Total = M.Total, TotalAndHits = M.TotalAndHits, Weights = M.Weights }
			for _, bad in ipairs({ false, "levelling", "Raid", 1 }) do
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.mode = bad
				for name, fn in pairs(entries) do
					local ok, err = pcall(fn, p)
					T.eq(ok, false, name .. " with p.mode " .. tostring(bad))
					T.truthy(tostring(err):find("Model input p.mode must be 'raid' or 'level'", 1, true), name .. ": " .. tostring(err))
				end
			end
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.mode = nil
			local ok, err = pcall(M.Total, p)
			T.eq(ok, false, "p.mode nil")
			T.truthy(tostring(err):find("Model input p.mode must be 'raid' or 'level'", 1, true), tostring(err))
		end },
		-- raid mode is defined for the level-60 hunter alone (Model.RAID_LEVEL; the raid boss is 63, Forever UI
		-- Camelot/SkillsFrame.lua:57-58), and it requires the raid inputs; levelling mode needs none of them, at any level
		{ "mode: raid at a level other than 60 is an error; the raid inputs are required in raid mode only", function()
			T.eq(M.RAID_LEVEL, 60)
			local RAID = { manaMax = 4000, regenRest = 15, regenCast = 7.5, spirit = 70, armorPen = 0 }
			local function point(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.level = 60
				for k, v in pairs(over) do p[k] = v end
				return p
			end
			local raid = point({ mode = "raid" })
			for k, v in pairs(RAID) do raid[k] = v end
			T.truthy(M.Total(raid) > 0, "raid at 60 with the raid inputs")
			for _, level in ipairs({ 59, 43, 61 }) do
				local q = {}
				for k, v in pairs(raid) do q[k] = v end
				q.level = level
				local ok, err = pcall(M.Total, q)
				T.eq(ok, false, "raid at " .. level)
				T.truthy(tostring(err):find("Model input p.mode 'raid' is defined at level 60 alone: p.level " .. level, 1, true), tostring(err))
			end
			local entries = { Parts = M.Parts, LandedHits = M.LandedHits, Total = M.Total, TotalAndHits = M.TotalAndHits, Weights = M.Weights }
			for key in pairs(RAID) do
				local q = {}
				for k, v in pairs(raid) do q[k] = v end
				q[key] = nil
				for name, fn in pairs(entries) do
					local ok, err = pcall(fn, q)
					T.eq(ok, false, name .. ": raid without p." .. key)
					T.truthy(tostring(err):find("Model input p." .. key .. " missing", 1, true), name .. ": " .. tostring(err))
				end
				q[key] = tostring(RAID[key])
				local ok, err = pcall(M.Total, q)
				T.eq(ok, false, "raid with p." .. key .. " a string")
				T.truthy(tostring(err):find("Model input p." .. key .. " missing or not a number", 1, true), tostring(err))
			end
			-- levelling mode: no raid input, at 60 and at 43
			for _, p in ipairs({ point({ mode = "level" }), ref }) do
				for key in pairs(RAID) do T.eq(p[key], nil, "no p." .. key) end
				T.truthy(M.Total(p) > 0, "levelling without the raid inputs at " .. p.level)
				T.truthy(M.Weights(p).RAP == 1, "Weights in levelling without the raid inputs at " .. p.level)
			end
		end },
		-- The raid target (raid mode, raid-mode design section 5): wowsims' boss armor 3731 less one Major (Sunder Armor or
		-- Expose Armor, 2250) and one Minor (Faerie Fire or Curse of Recklessness, 505) armor reduction, 976 (CONST.raid), its
		-- multiplier at level 60 1 - 976 / (976 + 400 + 85 x 60) = 0.84929 (my arithmetic); the worn armor penetration off it,
		-- floored at 0 (the user's answer O5; wowsims sim/core/spell_resistances.go:147-150). Levelling keeps the creature's own
		-- armor (Model.PhysMult)
		{ "raid armor: 976 and 0.8493; 100 armor penetration makes 876, floored at 0", function()
			T.eq(M.BossArmor(0), 976)
			T.near(M.ArmorMult(976, 60), 1 - 976 / (976 + 400 + 85 * 60), 1e-12)
			T.near(M.ArmorMult(976, 60), 0.84929, 1e-5)
			T.eq(M.BossArmor(100), 876, "100 armor penetration")
			T.eq(M.BossArmor(976), 0); T.eq(M.BossArmor(2000), 0, "floored at 0")
			local ok, err = pcall(M.BossArmor, nil)
			T.eq(ok, false); T.truthy(tostring(err):find("Model.BossArmor without the armor penetration", 1, true), tostring(err))
			local function point(over)
				local p = raidPoint(over)
				return M.ProcOutcomes(p).phys
			end
			T.near(point({}), M.ArmorMult(976, 60), 1e-12, "the raid point's armor")
			T.near(point({ armorPen = 100 }), M.ArmorMult(876, 60), 1e-12, "with 100 armor penetration")
			T.near(point({ armorPen = 2000 }), 1, 1e-12, "no armor left")
			local lvl = raidPoint({ mode = "level" })
			T.near(M.ProcOutcomes(lvl).phys, M.PhysMult(60, 3), 1e-12, "levelling at 60, +3: the creature's 3731")
			-- the parts: the hunter's own physical ones scale with the armor multiplier of his armor penetration (Gift of Arthas
			-- off, below), the Survival weave's melee and Auto Shots too; the pet and the hawks have no armor penetration of their
			-- own (wowsims spell_resistances.go:150 takes the attacker's own stat; sim/hunter/pets.go:122-140 and
			-- summon_hawk.go:79-87 pass none to them): they keep the whole 976; the magic ones take no armor
			local keep = M.CONST.raid.giftOfArthas
			M.CONST.raid.giftOfArthas = 0
			local a, b = M.Parts(raidPoint({})), M.Parts(raidPoint({ armorPen = 100 }))
			local sa, sb = M.Parts(raidPoint({ survival = true })), M.Parts(raidPoint({ survival = true, armorPen = 100 }))
			M.CONST.raid.giftOfArthas = keep
			local ratio = M.ArmorMult(876, 60) / M.ArmorMult(976, 60)
			for _, k in ipairs({ "auto", "aimed", "dive" }) do
				T.truthy(a[k] > 0, k .. " deals damage"); T.near(b[k] / a[k], ratio, 1e-12, k .. ": x the armor's ratio")
			end
			for _, k in ipairs({ "melee", "auto" }) do
				T.truthy(sa[k] > 0, "the weave's " .. k .. " deals damage")
				T.near(sb[k] / sa[k], ratio, 1e-12, "the weave's " .. k .. ": x the armor's ratio")
			end
			for _, k in ipairs({ "hawks", "pet" }) do
				T.truthy(a[k] > 0, k .. " deals damage"); T.near(b[k], a[k], 1e-12, k .. ": the whole 976, no armor penetration")
			end
			-- the pet and the hawks do face the boss's armor: 100 less of it (a Minor reduction of 605 for the test) scales them
			-- by the same ratio
			local keepMinor = M.CONST.raid.minorArmorReduction
			M.CONST.raid.giftOfArthas, M.CONST.raid.minorArmorReduction = 0, keepMinor + 100
			local c = M.Parts(raidPoint({}))
			M.CONST.raid.giftOfArthas, M.CONST.raid.minorArmorReduction = keep, keepMinor
			for _, k in ipairs({ "hawks", "pet" }) do T.near(c[k] / a[k], ratio, 1e-12, k .. ": x the boss armor's ratio") end
			for _, k in ipairs({ "arcane", "serpent" }) do T.near(b[k], a[k], 1e-12, k .. ": magic, no armor") end
			-- the raid inputs: armor penetration required in raid mode (Model checkMode)
			local q = raidPoint({}); q.armorPen = nil
			local ok, err = pcall(M.Total, q)
			T.eq(ok, false); T.truthy(tostring(err):find("Model input p.armorPen missing", 1, true), tostring(err))
		end },
		-- W.ARMOR_PEN (the user's answer O5): in raid mode the derivative of the total by p.armorPen (10 points, through
		-- Model.ApplyStats ARMOR_PEN), 0 where the armor is gone (floored at 0); levelling has no input of it: 0
		{ "raid armor penetration: W.ARMOR_PEN is the slope by p.armorPen in raid, 0 past the armor and in levelling", function()
			local p = raidPoint({})
			local W, dRap, t0 = M.Weights(p)
			local q = raidPoint({ armorPen = 10 })
			T.truthy(W.ARMOR_PEN > 0, "raid: armor penetration has a damage weight")
			T.near(W.ARMOR_PEN, (M.Total(q) - t0) / 10 / dRap, 1e-12, "the slope over 10 points")
			local applied = raidPoint({})
			M.ApplyStats(applied, { ARMOR_PEN = 25 })
			T.eq(applied.armorPen, 25, "ApplyStats: ARMOR_PEN to p.armorPen")
			T.eq(M.Weights(raidPoint({ armorPen = 1000 })).ARMOR_PEN, 0, "past the boss's armor: nothing")
			T.eq(M.Weights(raidPoint({ mode = "level" })).ARMOR_PEN, 0, "levelling: 0")
		end },
		-- Curse of the Elements (O7 = (a), CONST.raid.coe 1.10): every magic-school hit on the boss x1.10, Arcane Shot,
		-- Serpent Sting's nature ticks, Immolation Trap's fire ticks (the weave) and the magic procs (Model.ProcOutcomes);
		-- no physical one. Measured against the same raid point with the curse taken off (CONST.raid.coe 1)
		{ "raid CoE: x1.10 on Arcane, Serpent, Immolation Trap and magic procs, not on physical", function()
			local function parts(p, coe)
				local keep = M.CONST.raid.coe
				M.CONST.raid.coe = coe
				local r = M.Parts(p)
				M.CONST.raid.coe = keep
				return r
			end
			for _, p in ipairs({ raidPoint({}), raidPoint({ survival = true }) }) do
				local with, without = parts(p, 1.10), parts(p, 1)
				for k, v in pairs(with) do
					if k == "arcane" or k == "serpent" or k == "trap" then
						if without[k] > 0 then T.near(v / without[k], 1.10, 1e-12, k .. " x1.10") end
					else
						T.near(v, without[k], 1e-12, k .. ": physical, no curse")
					end
				end
				T.truthy(with.arcane > 0 and with.serpent > 0, "Arcane and Serpent deal damage")
			end
			T.truthy(parts(raidPoint({ survival = true }), 1).trap > 0, "the weave's trap deals damage")
			T.near(M.ProcOutcomes(raidPoint({})).coe, 1.10, 1e-12, "the magic procs' multiplier")
			T.eq(M.ProcOutcomes(raidPoint({ mode = "level" })).coe, 1, "levelling: no curse")
			T.eq(M.Parts(raidPoint({ mode = "level" })).arcane > 0, true)
		end },
		-- Gift of Arthas (O7 = (a), CONST.raid.giftOfArthas 8): +8 on every physical-school hit after the attacker's
		-- multipliers and the armor, before the outcome (wowsims sim/core/spell_result.go:391-401, 928-936), so a part gains
		-- 8 x its attempts a second x its outcome factor, no armor, no multiplier. The raid point (raidPoint: hit 8, the cap;
		-- crit 10% with no Agility, so the aura part is clamped at 1.8%; no Quick Shots, Frenzy, Ferocity or Bestial
		-- Discipline; the quiver's 13%; level 60) in the raid fight, each part at its mean over the fight (fightMean: Rapid
		-- Fire's +40% for 15 of the 180 weighted seconds) by hand (my arithmetic):
		-- - the shots' and the dive's crit 0.10 - 0.03 - 0.018 = 0.052, the shots' speed 1.13 x (1 + rf);
		-- - Auto Shot 8 x 1.13 x (1 + rf) / 2.6 x 1.052; Aimed 8 x 0.92 / (6 + 2 / (1.13 x (1 + rf))) x 1.052; the dive 8 x 2 / C
		--   x 1.052, C the HHA cycle of the tempo at the shots' speed (hhaCycle: 18 + 3 delta_H);
		-- - the hawks 8 x 2 x min(1, 18 / C) x 1.13 x (1 + rf) / 2.5 (their swing, CONST.hawkSwing) x their white roll 1 - 0.065 +
		--   0.002 - 0.4 x 0.35 = 0.797 (crit 0.5 x 0.10 - 0.03 - 0.018, dodge 6.5%, glance 40% at 0.65);
		-- - the pet 8 x ((1 + rf) / 2.0 x its white roll 1 - 0.065 + 0.052 - 0.14 = 0.847 + 3.6 / 10 x its special roll (1 - 0.065)
		--   x 1.052): its swings at the inherited 1 + rf over the 2.0 s base swing, Bite and 2.6 Claws a 10 s (Bestial Wrath
		--   multiplies its damage, not the gift);
		-- - Arcane Shot and Serpent Sting none (magic).
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid Gift of Arthas: +8 per physical hit after armor, before the outcome; none on Arcane or Serpent", function()
			local tal = { deadlyAspects = 0, frenzy = 0, ferocity = 0, bestialDiscipline = 0 }
			local function diff(over)
				local keep = M.CONST.raid.giftOfArthas
				M.CONST.raid.giftOfArthas = 0
				local without = M.Parts(richPoint(over, tal))
				M.CONST.raid.giftOfArthas = keep
				local with = M.Parts(richPoint(over, tal))
				local d = {}
				for k, v in pairs(with) do d[k] = v - without[k] end
				return d
			end
			local d = diff({})
			local crit = 0.052
			T.near(d.auto, fightMean(function(rf) return 8 * 1.13 * (1 + rf) / 2.6 * (1 + crit) end), 1e-9, "Auto Shot")
			T.near(d.aimed, fightMean(function(rf) return 8 * 0.92 / (6 + 2 / (1.13 * (1 + rf))) * (1 + crit) end), 1e-9, "Aimed Shot")
			local function C(rf) return hhaCycle(1.13 * (1 + rf), 18, 0.92) end
			T.near(d.dive, fightMean(function(rf) return 8 * 2 / C(rf) * (1 + crit) end), 1e-9, "the dive")
			T.near(d.hawks, fightMean(function(rf)
				return 8 * 2 * math.min(1, 18 / C(rf)) * 1.13 * (1 + rf) / 2.5 * (1 - 0.065 + 0.002 - 0.4 * 0.35)
			end), 1e-9, "the hawks")
			T.near(d.pet, fightMean(function(rf)
				return 8 * ((1 + rf) / 2.0 * (1 - 0.065 + 0.052 - 0.4 * 0.35) + 3.6 / 10 * (1 - 0.065) * (1 + 0.052))
			end), 1e-9, "the pet")
			T.eq(d.arcane, 0, "Arcane: magic"); T.eq(d.serpent, 0, "Serpent Sting: nature")
			-- Sniper Shot (its talent, from 40): 8 x 0.95 / (15 + 4 / (1.13 x (1 + rf))) x 1.052, and Aimed at its 0.80 share next
			-- to it
			local tsn = {} for k, v in pairs(tal) do tsn[k] = v end
			tsn.sniperShot = 1
			local keepG = M.CONST.raid.giftOfArthas
			M.CONST.raid.giftOfArthas = 0
			local sn0 = M.Parts(richPoint({}, tsn))
			M.CONST.raid.giftOfArthas = keepG
			local sn8 = M.Parts(richPoint({}, tsn))
			T.near(sn8.sniper - sn0.sniper, fightMean(function(rf) return 8 * 0.95 / (15 + 4 / (1.13 * (1 + rf))) * (1 + crit) end),
				1e-9, "Sniper Shot")
			T.near(sn8.aimed - sn0.aimed, fightMean(function(rf) return 8 * 0.80 / (6 + 2 / (1.13 * (1 + rf))) * (1 + crit) end),
				1e-9, "Aimed next to Sniper Shot")
			-- after the armor: the same gift at any armor penetration
			local d2 = diff({ armorPen = 500 })
			for _, k in ipairs({ "auto", "aimed", "dive", "hawks", "pet" }) do T.near(d2[k], d[k], 1e-12, k .. ": no armor on the gift") end
			-- levelling has none
			local lvl = M.Parts(richPoint({ mode = "level" }, tal))
			local keep = M.CONST.raid.giftOfArthas
			M.CONST.raid.giftOfArthas = 0
			local lvl0 = M.Parts(richPoint({ mode = "level" }, tal))
			M.CONST.raid.giftOfArthas = keep
			for k, v in pairs(lvl) do T.eq(v, lvl0[k], "levelling: " .. k) end
			T.eq(M.ProcOutcomes(richPoint({})).gift, 8); T.eq(M.ProcOutcomes(richPoint({ mode = "level" })).gift, 0)
		end },
		-- Gift of Arthas' attempts follow each attacker's speed and its outcome takes the whole crit factor, and no multiplier of
		-- the attacker touches it (wowsims sim/core/spell_result.go:391-401: the flat damage after the attacker's multipliers
		-- and the armor; spell_outcome.go:66: the crit multiplies the whole damage). The raid point of the previous test with
		-- Quick Shots (Deadly Aspects 5: 10% an Auto Shot), Frenzy 4, Mortal Shots 2, Ranged Weapon Specialization 5, Barrage
		-- 3, Sniper Shot and a pet swing of 1.2 s, each part at its mean over the fight (fightMean), by hand (my arithmetic):
		-- - Quick Shots' uptime 1 - 0.9 ^ (12 x 1.13 x 1.3 x (1 + rf) / 2.6) (its Auto Shots at the state's speed, Rapid Fire's
		--   in it inside its window, Model.Parts shots12; raid-mode design 25.4), the shots' and the hawks' speed 1.13 x (1 + 0.3
		--   x it) x (1 + rf);
		-- - the shots' crit factor 1 + 0.052 x (1 + 0.06 x 2) (Mortal Shots), the dive's 1 + 0.052 (the hunter's spell, no
		--   Mortal Shots); no Ranged Weapon Specialization, no Barrage on any gift;
		-- - Auto Shot 8 x speed / 2.6 x the shots' factor; Aimed at its 0.80 share next to Sniper Shot 8 x 0.80 / (6 + 2 / speed)
		--   x it; Sniper Shot 8 x 0.95 / (15 + 4 / speed) x it; the dive 8 x 2 / C x 1.052 and the hawks 8 x 2 x min(1, 18 / C) x
		--   speed / 2.5 x 0.797, C the HHA cycle of the tempo with Aimed Shot at 0.80 and Sniper Shot (hhaCycle);
		-- - the pet: Frenzy's uptime 1 - (1 - 0.8 x 0.052) ^ (8 / 1.2 x (1 + rf) x 1.3 + 3.6 x 0.8), its swings at (1 + 0.3 x it)
		--   x (1 + rf) over its own 1.2 s, 8 x (that x 0.847 + 3.6 / 10 x 0.935 x 1.052)
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid Gift of Arthas: attempts at Quick Shots, Frenzy and the pet's own swing; the whole crit factor; no attacker multiplier", function()
			local tal = { deadlyAspects = 5, frenzy = 4, ferocity = 0, bestialDiscipline = 0, mortalShots = 2, rangedWeaponSpec = 5,
				barrage = 3, sniperShot = 1 }
			local over = { petSwing = 1.2 }
			local keep = M.CONST.raid.giftOfArthas
			M.CONST.raid.giftOfArthas = 0
			local without = M.Parts(richPoint(over, tal))
			M.CONST.raid.giftOfArthas = keep
			local with = M.Parts(richPoint(over, tal))
			local d = {}
			for k, v in pairs(with) do d[k] = v - without[k] end
			local function qsUp(rf) return 1 - 0.9 ^ (12 * 1.13 * 1.3 * (1 + rf) / 2.6) end
			local function hR(rf) return 1.13 * (1 + 0.3 * qsUp(rf)) * (1 + rf) end
			local rcrit = 1 + 0.052 * (1 + 0.06 * 2)
			T.near(d.auto, fightMean(function(rf) return 8 * hR(rf) / 2.6 * rcrit end), 1e-9,
				"Auto Shot: Quick Shots' speed, Mortal Shots, no Ranged Weapon Specialization")
			T.near(d.aimed, fightMean(function(rf) return 8 * 0.80 / (6 + 2 / hR(rf)) * rcrit end), 1e-9, "Aimed Shot: no Barrage")
			T.near(d.sniper, fightMean(function(rf) return 8 * 0.95 / (15 + 4 / hR(rf)) * rcrit end), 1e-9, "Sniper Shot: Mortal Shots")
			local function C(rf) return hhaCycle(hR(rf), 18, 0.80, true) end
			T.near(d.dive, fightMean(function(rf) return 8 * 2 / C(rf) * 1.052 end), 1e-9,
				"the dive: no Mortal Shots, no Ranged Weapon Specialization")
			T.near(d.hawks, fightMean(function(rf)
				return 8 * 2 * math.min(1, 18 / C(rf)) * hR(rf) / 2.5 * (1 - 0.065 + 0.002 - 0.4 * 0.35)
			end), 1e-9, "the hawks: Quick Shots' speed")
			T.near(d.pet, fightMean(function(rf)
				local frenzyUp = 1 - (1 - 0.8 * 0.052) ^ (8 / 1.2 * (1 + rf) * 1.3 + 3.6 * 0.8)
				local petHaste = (1 + 0.3 * frenzyUp) * (1 + rf)
				return 8 * (petHaste / 1.2 * (1 - 0.065 + 0.052 - 0.4 * 0.35) + 3.6 / 10 * (1 - 0.065) * 1.052)
			end), 1e-9, "the pet: Frenzy's speed over its own 1.2 s swing")
		end },
		-- Quick Shots inside Rapid Fire (raid-mode design 25.4; wowsims rolls Quick Shots on each Auto Shot,
		-- sim/hunter/aspects.go): each state of the raid fight takes its uptime from its own Auto Shot rate, 1 - 0.9 ^ (12 x 1.13
		-- x 1.3 x (1 + rf) / 2.6) at Deadly Aspects 5 (10% an Auto Shot), so Rapid Fire's window, its Auto Shots 40% faster,
		-- holds more of it: 0.6322 against 0.5105 (my arithmetic), the Auto Shots there 1.4 x (1 + 0.3 x 0.6322) / (1 + 0.3 x
		-- 0.5105) = 1.4443 times those outside (the Frenzy Potion's attack power off, noPotionAP; Bestial Wrath moves only the pet). The
		-- Survival weave takes it from its cycle at the state's speed, 1 - 0.9 ^ (12 / C), C shorter inside Rapid Fire
		-- (weaveParts). Levelling's averaged pass keeps the Auto Shots at the speed without Rapid Fire: a Rapid Fire of 0 and
		-- of the levelling average give one uptime (the hawks, whose speed takes it, at the average's (1 + rf) alone)
		{ "raid Quick Shots: each state's uptime from its own Auto Shot rate, more inside Rapid Fire; the weave's from its cycle at the state's speed; levelling at the speed without Rapid Fire", function()
			local function qs(rf) return 1 - 0.9 ^ (12 * 1.13 * 1.3 * (1 + rf) / 2.6) end
			T.near(qs(0.4), 0.6322, 1e-4); T.near(qs(0), 0.5105, 1e-4)
			noPotionAP(function()
				local f = M.Fight(richPoint({}, { deadlyAspects = 5 }))
				local inside, outside
				for _, st in ipairs(f.states) do
					if st.rf then inside = st else outside = outside or st end
				end
				T.near(inside.out.auto / outside.out.auto, 1.4 * (1 + 0.3 * qs(0.4)) / (1 + 0.3 * qs(0)), 1e-12,
					"the Auto Shots inside Rapid Fire at the state's own uptime")
			end)
			local wv = M.Weave(svPoint({ mode = "raid", level = 60, mobDiff = 3, manaMax = 4000, regenRest = 200, regenCast = 200,
				spirit = 70, armorPen = 0 }, { deadlyAspects = 5, striderKick = 1 }))
			T.near(wv.rapidFire.qsUp, 1 - 0.9 ^ (12 / wv.rapidFire.C), 1e-8, "the weave inside Rapid Fire: its own cycle")
			T.near(wv.base.qsUp, 1 - 0.9 ^ (12 / wv.base.C), 1e-8, "the weave outside it")
			T.truthy(wv.rapidFire.qsUp > wv.base.qsUp + 0.01, "more inside Rapid Fire")
			-- levelling: the hawks' part at the averaged pass is the same Quick Shots' uptime with Rapid Fire's average in their
			-- speed alone: two levels of Rapid Killing (another average) move the hawks by (1 + rf) alone
			local function hawks(rk)
				return M.Parts(svPoint({ survival = false, level = 60, mobDiff = 0 }, { deadlyAspects = 5, rapidKilling = rk })).hawks
			end
			local up0, up2 = 15 / 300, 15 / 180
			T.near(hawks(2) / hawks(0), (1 + 0.4 * up2) / (1 + 0.4 * up0), 1e-12, "levelling: the uptime at the speed without Rapid Fire")
		end },
		-- The HHA sequence with no bow, gun or crossbow (raid-mode design 25.5): wowsims' sequence waits at a step that is not
		-- ready (sim/core/apl_actions_sequences.go:63-87) and Arcane Shot needs a ranged weapon (its weapon requirement), so after
		-- its two Summon Hawks it stops for good (apls/turret_hawk.apl.siml:15-17): the first hawk at 0 s, the second at 6 s and
		-- the poll's wait, 6.1317 s, each 18 s; then no hawk and no dive. At the rich raid point: the hawks 1 up in 0-6.13 s, 2
		-- in 6.13-18 s, 1 in 18-24.13 s, none after, so their mean uptime (18 + 18) / 2 / 180 = 0.1; two dives, each its state's
		-- damage over 180, two landed ranged specials; each Summon Hawk a one-off cost, 189 less its dive's 29.5 of Judgement of
		-- Wisdom (the first paid before the first segment: 4000 - 159.5). With a bow the cycle stays; without Summon Hawk
		-- nothing; levelling's averaged pass keeps its HHA cycle (the dives at 2 / C0 there)
		{ "raid HHA with no bow, gun or crossbow: the sequence stops at Arcane Shot after its two hawks; two dives, one-off costs; with a bow the cycle; levelling's cycle", function()
			local p = richPoint({ noShots = true, bowDPS = 0 })
			local f = M.Fight(p)
			local wait = (0.15 * 0.15 + 0.15 * 0.35 + 0.35 * 0.35) / 3 / 0.5
			local function upAt(t)
				for _, s in ipairs(f.segments) do
					if t >= s.t0 and t < s.t1 then return s.state.tempo.hawkUptime, s end
				end
			end
			T.eq((upAt(3)), 0.5, "one hawk 0-6.13 s"); T.eq((upAt(10)), 1, "two hawks"); T.eq((upAt(20)), 0.5, "one again 18-24.13 s")
			T.eq((upAt(30)), 0, "none after"); T.eq((upAt(150)), 0, "none later")
			local _, s2 = upAt(6 + wait + 1e-9)
			T.near(s2.t0, 6 + wait, 1e-12, "the second hawk at 6 s and the poll's wait")
			local _, s24 = upAt(24 + wait + 1e-9)
			T.near(s24.t0, 24 + wait, 1e-12, "the second hawk gone 18 s later")
			T.near(f.means.hawkUptime, 36 / 2 / 180, 1e-12, "(18 + 18) / 2 / 180")
			T.eq(f.means.hawkWait, nil); T.eq(f.means.hhaCycle, nil)
			local _, s0 = upAt(0)
			T.near(f.parts.dive * 180, s0.state.tempo.diveHit + s2.state.tempo.diveHit, 1e-9, "two dives, each in its state")
			T.truthy(s0.state.tempo.diveHit > 0)
			T.near(f.hits.ranged.specials * 180, 2, 1e-9, "two landed ranged specials")
			T.near(f.segments[1].m0, 4000 - (M.ManaCosts(p).hawk - 29.5), 1e-9, "the first Summon Hawk's cost less its dive's Judgement of Wisdom")
			local _, s5 = upAt(5.5)
			T.near(s2.m0, s5.m1 - (M.ManaCosts(p).hawk - 29.5), 1e-9, "the second's at its instant")
			-- with a bow: the HHA cycle, the hawks' uptime min(1, 18 / C) throughout
			local fb = M.Fight(richPoint({}))
			T.truthy(fb.means.hawkUptime > 0.9 and fb.means.hhaCycle ~= nil, "with a bow the cycle")
			-- without Summon Hawk: no hawk
			T.eq(M.Fight(richPoint({ noShots = true, bowDPS = 0 }, { summonHawk = 0 })).means.hawkUptime, 0)
			-- levelling: the averaged pass's dives at 2 / C0 with no bow
			local lb = M.LandedHits(raidPoint({ mode = "level", noShots = true, bowDPS = 0 }))
			T.near(lb.ranged.specials, 2 / (18 - 0.3 * M.DEFAULT_TALENTS.improvedArcaneShot), 1e-12, "levelling: the dives of the cycle")
			T.truthy(M.Parts(raidPoint({ mode = "level", noShots = true, bowDPS = 0 })).hawks > 0, "levelling: the hawks")
			-- a debt with no cast to buy (a made-up pool of 200: the hawk and Rapid Fire's and Bestial Wrath's 306 at 5 s) repays
			-- at the regen out of the five-second rule (regen 15 / 7.5 at the raid point)
			local fd = M.Fight(raidPoint({ noShots = true, bowDPS = 0, manaMax = 200 }))
			local debt
			for _, s in ipairs(fd.segments) do
				if not debt and s.state.phase == "debt" then debt = s.state end
			end
			T.truthy(debt ~= nil, "a debt stretch")
			T.near(debt.income, 15 + 29.5 * debt.casts.free, 1e-9, "repaid at the regen out of the five-second rule and the free hits' Judgement of Wisdom")
		end },
		-- Gift of Arthas in the dual-wield weave with Strider Kick, Mongoose Bite (no Lacerating Strikes), Predator's Edge 3 and
		-- Mortal Shots 2 (the rates the weave's own, Model.Weave average), by hand (my arithmetic): each hand's white roll 1 -
		-- 0.19 - 0.065 + 0.052 - 0.14 = 0.657, the off hand's gift without Predator's Edge's +30% damage (a multiplier of the
		-- attacker); the specials' and the bite's factor (1 - 0.065) x (1 + 0.052 x (1 + 0.06 x 3)), Predator's Edge's crit
		-- damage in it; the Auto Shots' 1 + 0.052 x (1 + 0.06 x 2)
		{ "raid Gift of Arthas in the weave: Strider Kick, the bite's own hit, Predator's Edge's crit, not its off-hand damage", function()
			local tal = { deadlyAspects = 0, frenzy = 0, ferocity = 0, bestialDiscipline = 0, striderKick = 1, exposePrey = 3,
				laceratingStrikes = 0, predatorsEdge = 3, mortalShots = 2 }
			local over = { survival = true, mhDPS = 23, mhSpeed = 5.0, ohDPS = 18, ohSpeed = 1.8 }
			local keep = M.CONST.raid.giftOfArthas
			M.CONST.raid.giftOfArthas = 0
			local without = M.Parts(raidPoint(over, tal))
			M.CONST.raid.giftOfArthas = keep
			local with = M.Parts(raidPoint(over, tal))
			local r = M.Weave(raidPoint(over, tal)).average.rates
			T.truthy(r.strider > 0 and r.bite > 0 and r.oh > 0 and r.raptor > 0, "Strider Kick, the bites, the off hand, Raptor Strike")
			local white = 1 - 0.19 - 0.065 + 0.052 - 0.14
			local special = (1 - 0.065) * (1 + 0.052 * (1 + 0.06 * 3))
			T.near(with.melee - without.melee, 8 * (white * (r.mhWhite + r.oh) + special * (r.raptor + r.strider + r.wingClip + r.bite)),
				1e-9, "the melee's physical hits")
			T.near(with.auto - without.auto, 8 * r.auto * (1 + 0.052 * (1 + 0.06 * 2)), 1e-9, "the weave's Auto Shots: Mortal Shots")
		end },
		-- Gift of Arthas on the Survival weave's physical hits (Model weaveParts): the white swings at their roll, Raptor
		-- Strike, Strider Kick and Wing Clip at the special's two rolls, the bite with its Lacerating Strikes bleed (40% of the
		-- bite's dealt damage, the gift in it: wowsims sim/hunter/talents_survival.go:214-217), the Auto Shots at the shots'
		-- outcome; the rates the weave's own (Model.Weave average). One hand, no bites first: the white roll 1 - 0.065 + 0.052 -
		-- 0.14 = 0.847, the special's (1 - 0.065) x 1.052, the shots' 1.052 (my arithmetic, the raid point of the previous test)
		{ "raid Gift of Arthas in the weave: white swings, Raptor Strike, Wing Clip and the Auto Shots at their outcomes; the bite's bleed carries it", function()
			local tal = { deadlyAspects = 0, frenzy = 0, ferocity = 0, bestialDiscipline = 0, striderKick = 0, exposePrey = 0 }
			local over = { survival = true, ohDPS = 0 }
			local function parts(o, t, gift)
				local keep = M.CONST.raid.giftOfArthas
				M.CONST.raid.giftOfArthas = gift
				local r = M.Parts(raidPoint(o, t))
				M.CONST.raid.giftOfArthas = keep
				return r
			end
			local with, without = parts(over, tal, 8), parts(over, tal, 0)
			local r = M.Weave(raidPoint(over, tal)).average.rates
			T.truthy(r.raptor > 0 and r.wingClip > 0 and r.mhWhite > 0, "white swings, Raptor Strike and Wing Clip")
			T.near(with.melee - without.melee, 8 * ((1 - 0.065 + 0.052 - 0.14) * r.mhWhite + (1 - 0.065) * 1.052 * (r.raptor + r.wingClip)),
				1e-9, "the melee's physical hits")
			T.near(with.auto - without.auto, 8 * r.auto * 1.052, 1e-9, "the weave's Auto Shots")
			T.truthy(r.multi > 0, "the weave casts Multi-Shot at 60 (U3 = (a))")
			T.near(with.multi - without.multi, 8 * r.multi * 1.052, 1e-9, "the weave's Multi-Shots at the shots' outcome")
			T.eq(with.arcane - without.arcane, 0); T.eq(with.trap - without.trap, 0, "Immolation Trap: fire")
			-- dual wield: a slow 5.0 s main hand lets the 1.8 s off hand swing in the visits (Model weaveParts' shareOH); each
			-- hand's white roll 1 - 0.19 (19% more miss) - 0.065 + 0.052 - 0.14 = 0.657 (my arithmetic)
			local dwOver = { survival = true, mhDPS = 23, mhSpeed = 5.0, ohDPS = 18, ohSpeed = 1.8 }
			local dw8, dw0 = parts(dwOver, tal, 8), parts(dwOver, tal, 0)
			local rd = M.Weave(raidPoint(dwOver, tal)).average.rates
			T.truthy(rd.oh > 0, "the off hand swings")
			local dwRoll = 1 - 0.19 - 0.065 + 0.052 - 0.14
			T.near(dw8.melee - dw0.melee, 8 * (dwRoll * (rd.mhWhite + rd.oh) + (1 - 0.065) * 1.052 * (rd.raptor + rd.wingClip)), 1e-9,
				"dual wield: both hands' white swings")
			-- the bite's bleed: Lacerating Strikes 1 against 0 adds 40% x the bite's crit factor x its ticks / 7 of the bite's
			-- dealt damage, gift included, so the bleed's part with the gift less without it is 8 / (the bite's damage before
			-- its roll, phys and own) of the bleed's part without the gift (my arithmetic): the bite's damage before its roll
			-- is the main hand's 26 DPS x 2.6 s + its melee attack power / 14 x 2.4 + Mongoose Bite's 57 (rank 4, from 58)
			local bt = { deadlyAspects = 0, frenzy = 0, ferocity = 0, bestialDiscipline = 0, striderKick = 0, exposePrey = 3 }
			local function bleed(gift)
				local ls1 = {} for k, v in pairs(bt) do ls1[k] = v end
				ls1.laceratingStrikes = 1
				local ls0 = {} for k, v in pairs(bt) do ls0[k] = v end
				ls0.laceratingStrikes = 0
				return parts(over, ls1, gift).melee - parts(over, ls0, gift).melee
			end
			-- the Frenzy Potion's attack power off (noPotionAP): one bite's base in every state
			local b8, b0
			noPotionAP(function() b8, b0 = bleed(8), bleed(0) end)
			T.truthy(b0 > 0, "the bleed deals damage")
			local p = raidPoint(over, bt)
			local own = 1 + 0.01 * p.tal.focusedFire
			local biteBase = p.mhDPS * p.mhSpeed + p.map / 14 * p.mhNorm + 57
			T.near(b8 - b0, 8 * b0 / (biteBase * M.ArmorMult(976, 60) * own), 1e-9, "the bleed carries the bite's gift")
		end },
		-- The raid fight's cast tempo (raid-mode design 6.4, approximation A1): an action waits for the hold of the other GCD
		-- actions in progress, else for the next look, delta_X = b_X R_X + (1 - b_X) r_poll (tempoWait). The design's example
		-- (6.4-6.5: the shots' speed 1.15, Aimed Shot's use share 0.92, no Sniper Shot): Aimed f = 0.1189, its hold 1.739 s;
		-- delta_S = 0.439 s, delta_H = 0.346 s, the HHA cycle C = 19.04 s, the hawks' uptime 0.945 (my arithmetic there); here
		-- the raid point with the quiver's 15% and no Quick Shots, outside Rapid Fire (the state of no cooldown), and inside it
		-- (the shots at 1.15 x 1.4: Aimed's 1.24 s cast inside the GCD, its hold 1.5 s)
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid tempo: delta = b R + (1 - b) 0.1317 from the other GCD actions; the HHA cycle 18 + 3 delta_H; the hawks 18 / C", function()
			local tal = { deadlyAspects = 0 }
			local f = M.Fight(richPoint({ quiver = 0.15 }, tal))
			local st = statesByKey(f)
			local t0, t1 = st["--"].tempo, st["rb"].tempo
			T.near(t0.serpentWait, 0.439, 0.0005, "the design's delta_S"); T.near(t0.hawkWait, 0.346, 0.0005, "the design's delta_H")
			T.near(t0.hhaCycle, 19.04, 0.005, "the design's C"); T.near(t0.hawkUptime, 0.945, 0.0005, "the design's hawk uptime")
			for _, case in ipairs({ { t0, 1.15 }, { t1, 1.15 * 1.4 } }) do
				local t, acts = case[1], turretActs(case[2], 18, 0.92)
				T.near(t.serpentWait, tempoWait(acts, "serpent"), 1e-12, "delta_S at the shots' speed " .. case[2])
				T.near(t.hawkWait, tempoWait(acts, "hha"), 1e-12, "delta_H at the shots' speed " .. case[2])
				T.near(t.hhaCycle, 18 + 3 * t.hawkWait, 1e-12, "C = 18 + 3 delta_H")
				T.near(t.hawkUptime, math.min(1, 18 / t.hhaCycle), 1e-12, "a hawk lives 18 s a cycle")
			end
			-- the fight's dives and Arcane Shots: 2 / C and 1 / C of each state, at its weight (the no-Quick-Shots point's states
			-- the dive's and Arcane's alone); the dive lands always, in the ranged specials
			-- (the Frenzy Potion's attack power off, noPotionAP: Arcane Shot's cast the same in every state below)
			local P, P0
			noPotionAP(function()
				P = M.Parts(richPoint({ quiver = 0.15 }, tal))
				local keep = M.CONST.raid.giftOfArthas
				M.CONST.raid.giftOfArthas = 0
				P0 = M.Parts(richPoint({ quiver = 0.15 }, tal))
				M.CONST.raid.giftOfArthas = keep
			end)
			local rate = 0
			for _, s in ipairs(f.states) do rate = rate + s.weight / 180 * 2 / s.tempo.hhaCycle end
			T.near(P.dive - P0.dive, 8 * rate * 1.052, 1e-9, "the dives' gift at 2 / C of each state")
			-- Arcane Shot one a cycle: its damage a cast the same in every state (no armor, no speed in it), so the fight's Arcane
			-- part is a cast's damage x the mean of 1 / C, and the levelling one at the same point a cast's damage / 1.10 (no Curse
			-- of the Elements) x 1 / 18
			local lvl0 = M.Parts(richPoint({ mode = "level", quiver = 0.15 }, tal))
			T.near(P.arcane / (rate / 2), 1.10 * lvl0.arcane * 18, 1e-9, "Arcane Shot at 1 / C of each state")
			-- Improved Arcane Shot 5/5: C0 = 18 - 1.5 = 16.5 s, so C = 16.5 + 3 delta_H and the hawks up all the time (C < 18)
			local f5 = M.Fight(richPoint({ quiver = 0.15 }, { deadlyAspects = 0, improvedArcaneShot = 5 }))
			local t5 = statesByKey(f5)["--"].tempo
			T.near(t5.hawkWait, tempoWait(turretActs(1.15, 16.5, 0.92), "hha"), 1e-12, "delta_H")
			T.near(t5.serpentWait, tempoWait(turretActs(1.15, 16.5, 0.92), "serpent"), 1e-12, "delta_S with the HHA elements at 3 / 16.5")
			T.near(t5.hhaCycle, 16.5 + 3 * t5.hawkWait, 1e-12, "C = 18 - 0.3 x 5 + 3 delta_H")
			T.eq(t5.hawkUptime, 1, "a cycle under 18 s keeps the hawks up")
			-- without Summon Hawk Arcane Shot is cast alone at its use share, 0.9 / 6 a second, a GCD action for Serpent Sting to
			-- wait for; no hawks, no dive
			local tn = statesByKey(M.Fight(richPoint({ quiver = 0.15 }, { deadlyAspects = 0, summonHawk = 0 })))["--"].tempo
			local actsN = turretActs(1.15, 18, 0.92)
			actsN.hha = { 0.9 / 6, 1.5 }
			T.near(tn.serpentWait, tempoWait(actsN, "serpent"), 1e-12, "delta_S with Arcane Shot alone")
			T.eq(tn.hawkUptime, 0, "no hawks")
			T.eq(tn.hawkWait, nil, "no HHA sequence: no delta_H"); T.eq(tn.hhaCycle, nil, "no HHA cycle")
			-- the levelling mode keeps its averages: the hawks at CONST.hawkUptime, the dive at 2 / C0
			local lvl = M.Parts(richPoint({ mode = "level", quiver = 0.15 }, tal))
			T.truthy(lvl.dive > 0 and lvl.hawks > 0, "levelling: the dive and the hawks")
		end },
		-- Serpent Sting in the raid fight (raid-mode design 6.4): re-cast when its dot is gone, the cast rolling the ranged
		-- table (a miss q = 1 - shotHitf, the next try at its GCD's end) and the dot landing 12 / 40 = 0.3 s after it: from the
		-- dot's end to the next landed one g = delta_S + 0.3 + q / (1 - q) x 1.5, the landed applications aL = 1 / (15 + g), the
		-- uptime 15 aL and the casts aL / (1 - q). The raid point at hit 8 (q = 0: the cap) and at hit 4 (q = 0.04, my
		-- arithmetic: the 8% miss less 4%); the damage is the whole sting's at aL, the landed applications in the ranged hand's
		-- casts (Model.LandedHits)
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid serpent: U = 15 / (15 + delta_S + 0.3 + q / (1 - q) x 1.5); more hit raises U and lowers the casts", function()
			local tal = { deadlyAspects = 0 }
			local out = {}
			for _, hit in ipairs({ 8, 4 }) do
				local q = math.max(0, 8 - hit) / 100
				local f = M.Fight(richPoint({ hit = hit }, tal))
				local casts = 0
				for _, s in ipairs(f.states) do
					local t = s.tempo
					local aL = 1 / (15 + t.serpentWait + 0.3 + q / (1 - q) * 1.5)
					T.near(t.serpentUptime, 15 * aL, 1e-12, "the uptime at hit " .. hit)
					T.near(t.serpentCasts, aL / (1 - q), 1e-12, "the casts at hit " .. hit)
					T.near(s.hits.ranged.casts, aL, 1e-12, "the landed applications at hit " .. hit)
					casts = casts + s.weight / 180 * aL
				end
				T.near(M.LandedHits(richPoint({ hit = hit }, tal)).ranged.casts, casts, 1e-12, "the fight's landed applications")
				out[hit] = statesByKey(f)["--"].tempo
			end
			T.truthy(out[8].serpentUptime > out[4].serpentUptime + 1e-6, "more hit: a higher uptime")
			T.truthy(out[8].serpentCasts < out[4].serpentCasts - 1e-6, "more hit: fewer casts")
			T.truthy(out[8].serpentUptime > 0.94 and out[8].serpentUptime < 0.96, "the uptime near the design's 0.95")
		end },
		-- The Survival weave's Serpent Sting in the raid fight (raid-mode design 15.3): cast from the shooting spot when its dot
		-- is gone, landing 13.19 / 40 s later, a miss (q) retried at the next range look, so the landed applications come every
		-- I_S = (nCycles(15 + 13.19 / 40, C_R, sigma) + q / (1 - q)) x C_R, C_R = C / n_R the range looks' interval: the uptime 15 /
		-- I_S, the casts 1 / ((1 - q) I_S). 15.8's point in raid mode (hit 0 at +3: q = 0.08); levelling keeps CONST.serpentUptime
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid weave: Serpent Sting re-cast from the range looks, I_S = (nCycles(15.33, C_R, sigma) + q / (1 - q)) x C_R", function()
			local raid = { mode = "raid", manaMax = 4000, regenRest = 200, regenCast = 200, spirit = 70, armorPen = 0 }
			local wv = M.Weave(p158(raid))
			for _, cy in ipairs({ wv.base, wv.rapidFire }) do
				local CR = cy.C / cy.nR
				local IS = (M.NCycles(15 + 13.19 / 40, CR, cy.sigma) + 0.08 / 0.92) * CR
				T.near(cy.rates.serpentLanded, 1 / IS, 1e-12, "the landed applications every I_S")
				T.near(cy.rates.serpent, 1 / (0.92 * IS), 1e-12, "the casts over the hit chance")
			end
			T.near(wv.average.rates.serpentLanded, (165 * wv.base.rates.serpentLanded + 15 * wv.rapidFire.rates.serpentLanded) / 180,
				1e-12, "the fight's landed applications")
			T.near(M.LandedHits(p158(raid)).ranged.casts, wv.average.rates.serpentLanded, 1e-12, "Model.LandedHits' casts")
			-- the levelling weave: 0.8 / 15 landed, 0.8 / 15 / 0.92 cast
			local lv = M.Weave(p158({})).base.rates
			T.near(lv.serpentLanded, 0.8 / 15, 1e-12); T.near(lv.serpent, 0.8 / 15 / 0.92, 1e-12)
		end },
		-- Serpent Sting's damage in the raid fight (raid-mode design 6.4, 15.3): the whole sting, 5 ticks of its rank's 100 at 60
		-- and 0.25 x the shots' attack power (the raid point's 561 and Hunter's Mark's 143 at 60), times the ticks' crit factor
		-- 1 + 0.052 (crit 10% with no Agility: 0.10 - 0.03 - 0.018 at +3), Focused Fire 2 with the pet out 1.02, Improved Stings
		-- 3 1.20 and Curse of the Elements 1.10: (500 + 176) x 1.052 x 1.02 x 1.20 x 1.10 = 957.495 (my arithmetic), at its
		-- landed applications a second: the turret's aL of each state (6.4, no miss factor on the damage) and the weave's
		-- serpentLanded (15.3: a missed cast costs a range look, not damage), not their casts. The cast rolls the shots' table:
		-- its miss q = 1 - shotHitf, p.hit with the ranged weapon skill's p.rangedHit on top, so hit 4 with rangedHit 2 misses
		-- 2% (8 - 6) where the pet and the hawks miss 4%. In the Major Frenzy Potion's windows (O2 = (a), raid-mode design 7.4:
		-- 5-35 s and, the pool full at 125 s, 125-155 s) the shots' attack power is 80 more: (500 + 0.25 x 784) x ... = 985.823
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid serpent damage: the whole sting at the landed applications, the turret's aL and the weave's I_S; the cast's miss holds the ranged skill's hit", function()
			local tal = { deadlyAspects = 0, improvedStings = 3 }
			local function stingOf(s) return (5 * 100 + 0.25 * (561 + 143 + (#s.uses > 0 and 80 or 0))) * 1.052 * 1.02 * 1.20 * 1.10 end
			local perSting = stingOf({ uses = {} })
			T.near(perSting, 957.495, 0.0005, "the design's sting")
			T.near(stingOf({ uses = { 1 } }), 985.823, 0.0005, "with the Frenzy Potion")
			for _, over in ipairs({ { hit = 8 }, { hit = 4 }, { hit = 4, rangedHit = 2 } }) do
				local q = (8 - over.hit - (over.rangedHit or 0)) / 100
				local name = "hit " .. over.hit .. ", ranged skill hit " .. (over.rangedHit or 0)
				local f = M.Fight(richPoint(over, tal))
				local landed = 0
				for _, s in ipairs(f.states) do
					local t = s.tempo
					local aL = 1 / (15 + t.serpentWait + 0.3 + q / (1 - q) * 1.5)
					T.near(s.out.serpent, stingOf(s) * aL, 1e-9, "a state's sting at its aL, " .. name)
					T.near(t.serpentCasts, aL / (1 - q), 1e-12, "its casts at the shots' miss, " .. name)
					landed = landed + s.weight / 180 * stingOf(s) * aL
				end
				T.near(M.Parts(richPoint(over, tal)).serpent, landed, 1e-9, "the fight's sting, " .. name)
			end
			for _, over in ipairs({ { survival = true, hit = 4 }, { survival = true, hit = 4, rangedHit = 2 } }) do
				local q = (8 - over.hit - (over.rangedHit or 0)) / 100
				local name = "the weave at ranged skill hit " .. (over.rangedHit or 0)
				local wv = M.Weave(richPoint(over, tal))
				for _, cy in ipairs({ wv.base, wv.rapidFire }) do
					local CR = cy.C / cy.nR
					local IS = (M.NCycles(15 + 13.19 / 40, CR, cy.sigma) + q / (1 - q)) * CR
					T.near(cy.rates.serpentLanded, 1 / IS, 1e-12, "the landed applications every I_S, " .. name)
					T.near(cy.rates.serpent, 1 / ((1 - q) * IS), 1e-12, "the casts over the shots' hit, " .. name)
				end
				T.truthy(wv.average.rates.serpent > wv.average.rates.serpentLanded + 1e-6, "more casts than landed stings, " .. name)
				local sting = 0
				for _, s in ipairs(M.Fight(richPoint(over, tal)).states) do
					sting = sting + s.weight / 180 * stingOf(s) * s.weave.average.rates.serpentLanded
				end
				T.near(M.Parts(richPoint(over, tal)).serpent, sting, 1e-9, "the weave's sting, " .. name)
			end
		end },
		-- Model.Fight's means (raid-mode design 6.7): Serpent Sting's uptime 15 s x its landed applications a second over the
		-- fight (the turret's states' 15 aL at their weights), the hawks' uptime and the turret's delta_S, delta_H and C at the
		-- states' weights; the Survival weave has no turret tempo (nil) and no hawks, its Serpent Sting from its range looks
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid fight: Model.Fight's means of Serpent Sting's and the hawks' uptime and the tempo", function()
			local f = M.Fight(richPoint({}))
			local sums = { serpentUptime = 0, hawkUptime = 0, serpentWait = 0, hawkWait = 0, hhaCycle = 0 }
			for _, s in ipairs(f.states) do
				for k in pairs(sums) do sums[k] = sums[k] + s.weight / 180 * s.tempo[k] end
			end
			for k, v in pairs(sums) do T.near(f.means[k], v, 1e-12, k) end
			T.near(f.means.serpentUptime, 15 * M.LandedHits(richPoint({})).ranged.casts, 1e-12, "15 s a landed application")
			local raid = { mode = "raid", manaMax = 4000, regenRest = 200, regenCast = 200, spirit = 70, armorPen = 0 }
			local fw = M.Fight(p158(raid))
			T.eq(fw.means.serpentWait, nil, "the weave: no turret tempo"); T.eq(fw.means.hawkUptime, 0, "no hawks")
			-- the turret without Summon Hawk: its delta_S, no HHA cycle
			local fn = M.Fight(richPoint({}, { summonHawk = 0 }))
			T.truthy(fn.means.serpentWait > 0.1, "the turret's delta_S without hawks")
			T.eq(fn.means.hawkWait, nil, "no hawks: no delta_H"); T.eq(fn.means.hhaCycle, nil, "no hawks: no HHA cycle")
			T.eq(fn.means.hawkUptime, 0, "no hawks up")
			T.near(fw.means.serpentUptime, 15 * M.Weave(p158(raid)).average.rates.serpentLanded, 1e-12, "the weave's Serpent Sting")
			-- the mana's means (raid-mode design 6.7): Judgement of Wisdom's income and the casting regen at the states' weights,
			-- the starved states' share of the fight; at the raid point, which runs out of mana
			local fm = M.Fight(raidPoint({}))
			local jow, rc, starved = 0, 0, 0
			for _, s in ipairs(fm.states) do
				jow, rc = jow + s.weight / 180 * s.mana.J, rc + s.weight / 180 * s.mana.rc
				if s.regime == "starved" then starved = starved + s.weight / 180 end
			end
			T.near(fm.means.jow, jow, 1e-12, "Judgement of Wisdom's income"); T.truthy(jow > 15, "about 20 a second")
			T.near(fm.means.regenCast, rc, 1e-12, "the casting regen")
			T.near(fm.means.starved, starved, 1e-12, "the starved share"); T.truthy(starved > 0.1 and starved < 0.5, "starved part of the fight")
		end },
		-- Rapid Killing (raid-mode design 6.6): the raid boss dies once, at the fight's end, so the talent's Aimed bonus adds
		-- nothing in raid mode, whatever CONST.killInterval; levelling counts a kill every CONST.killInterval
		{ "raid: Rapid Killing adds nothing to Aimed; levelling follows CONST.killInterval", function()
			local tal = { rapidKilling = 2 }
			local function aimed(mode)
				local keep = M.CONST.killInterval
				local a = M.Parts(raidPoint({ mode = mode }, tal)).aimed
				M.CONST.killInterval = 2 * keep
				local b = M.Parts(raidPoint({ mode = mode }, tal)).aimed
				M.CONST.killInterval = keep
				return a, b
			end
			local r1, r2 = aimed("raid")
			T.truthy(r1 > 0, "Aimed deals damage"); T.eq(r1, r2, "raid: no kill interval read")
			local l1, l2 = aimed("level")
			T.truthy(l1 > l2 + 1e-9, "levelling: half the kills, a smaller bonus")
		end },
		-- The raid fight (raid-mode design 6.1-6.3, 6.7): wowsims draws the fight's length uniformly in 180 +- 5 s, so an instant
		-- counts with w(t) = 1 to 175 s, (185 - t) / 10 to 185 s and 0 after, whose integral (Model.FightIntegral) is 180 at 185 s
		-- (my arithmetic: 175 + 10 - 100 / 20); the BM rotation casts the major cooldowns from 5 s, Rapid Fire 15 s every 300 s
		-- (Rapid Killing -60 s a rank: 240 and 180 s bring no second cast before 185 s either) and Bestial Wrath 18 s every
		-- 120 s with the talent and the pet out. At the raid point (Bestial Wrath 1, no Rapid Killing) the states are: none 0-5,
		-- 23-125 and 143-185 s (5 + 102 + 37 weighted seconds = 144), Rapid Fire with Bestial Wrath 5-20 s (15), Bestial Wrath
		-- alone 20-23 and 125-143 s (21) (my arithmetic); the total is the states' damage a second at their weights over 180
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid fight: the time weight of 180 +- 5 s; Rapid Fire's and Bestial Wrath's windows from 5 s; the total the states' weighted mean", function()
			local F = M.FightIntegral
			T.eq(F(0), 0); T.near(F(100), 100, 1e-12); T.near(F(175), 175, 1e-12)
			T.near(F(180), 178.75, 1e-12, "w(t) = (185 - t) / 10 from 175 s")
			T.near(F(185), 180, 1e-12, "the mean length"); T.near(F(400), 180, 1e-12, "nothing after 185 s")
			local f = M.Fight(richPoint({}))
			T.eq(windowsText(f.rapidFire), "5-20", "Rapid Fire 15 s from 5 s")
			T.eq(windowsText(f.bestialWrath), "5-23,125-143", "Bestial Wrath 18 s from 5 s and again at 125 s")
			-- the Major Frenzy Potion (O2 = (a), raid-mode design 7.4) 5-35 s and, the mana potion not fitting under the full pool at
			-- 125 s, 125-155 s: no cooldown and no potion 0-5, 35-125 and 155-185 s (5 + 90 + 25 = 120), the potion alone 23-35 and
			-- 143-155 s (24), with Bestial Wrath 20-23 and 125-143 s (21), with both 5-20 s (15) (my arithmetic)
			T.eq(windowsText(f.frenzyPotion), "5-35,125-155", "the Frenzy Potion at 5 s and 125 s")
			local st = {}
			for _, s in ipairs(f.states) do st[(s.rf and "r" or "-") .. (s.bw and "b" or "-") .. (#s.uses > 0 and "p" or "")] = s end
			T.near(st["--"].weight, 120, 1e-9, "no cooldown"); T.near(st["rbp"].weight, 15, 1e-9, "Rapid Fire, Bestial Wrath, the potion")
			T.near(st["-bp"].weight, 21, 1e-9, "Bestial Wrath and the potion"); T.near(st["--p"].weight, 24, 1e-9, "the potion alone")
			T.eq(st["r-"], nil, "no Rapid Fire outside Bestial Wrath"); T.eq(#f.states, 4, "four states")
			local sum = 0
			for _, s in ipairs(f.states) do
				local dps = 0
				for _, v in pairs(s.out) do dps = dps + v end
				sum = sum + s.weight * dps
			end
			T.near(M.Total(richPoint({})), sum / 180, 1e-9, "the states at their weights over 180")
			for rk = 1, 2 do
				T.eq(windowsText(M.Fight(richPoint({}, { rapidKilling = rk })).rapidFire), "5-20", "Rapid Killing " .. rk .. ": one window")
			end
			T.eq(windowsText(M.Fight(richPoint({}, { bestialWrath = 0 })).bestialWrath), "", "no Bestial Wrath without the talent")
			T.eq(windowsText(M.Fight(richPoint({ petOut = false }, { loneWolf = 1 })).bestialWrath), "", "nor without a pet out")
			local ok, err = pcall(M.Fight, richPoint({ mode = "level" }))
			T.eq(ok, false); T.truthy(tostring(err):find("Model.Fight of a point not in raid mode", 1, true), tostring(err))
		end },
		-- The pet inside Rapid Fire and Bestial Wrath (raid-mode design 6.1): a state's Rapid Fire speeds the pet's swings (its
		-- aura 319, the pet's inherited melee speed) and its Bestial Wrath multiplies the pet's damage by 1.5, both in one state,
		-- so the pet deals the product of the two. Measured on the raid point without Frenzy and Gift of Arthas (the gift is no
		-- damage of the pet's multipliers), against the same fight with Bestial Wrath's duration 0 (no window: the states none
		-- and Rapid Fire alone)
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid fight: the pet inside Rapid Fire and Bestial Wrath deals the product of both", function()
			local tal = { frenzy = 0 }
			local keepG, keepD = M.CONST.raid.giftOfArthas, M.CONST.bestialWrathDuration
			local function pets()
				local r = {}
				for key, s in pairs(statesByKey(M.Fight(richPoint({}, tal)))) do r[key] = s.out.pet end
				return r
			end
			M.CONST.raid.giftOfArthas = 0
			local both = pets()
			M.CONST.bestialWrathDuration = 0
			local rfOnly = pets()
			M.CONST.raid.giftOfArthas, M.CONST.bestialWrathDuration = keepG, keepD
			T.near(both["-b"] / both["--"], 1.5, 1e-12, "Bestial Wrath: +50% pet damage")
			T.truthy(rfOnly["r-"] > 1.1 * rfOnly["--"], "Rapid Fire speeds the pet's swings")
			T.near(both["rb"] / both["--"], 1.5 * rfOnly["r-"] / rfOnly["--"], 1e-12, "both: the product")
			-- Bestial Wrath is the pet's alone (talents_beast_mastery.go:114-125, the pet's MCD): every other part of the state
			-- with it equals the state without it, the hawks' too
			local st = statesByKey(M.Fight(richPoint({}, tal)))
			for k, v in pairs(st["-b"].out) do
				if k ~= "pet" then T.near(v, st["--"].out[k], 1e-12, k .. ": no Bestial Wrath") end
			end
			T.truthy(st["-b"].out.hawks > 0, "the hawks deal damage")
		end },
		-- The Survival weave in the raid fight (raid-mode design 15.5): the cycle per state at that state's Rapid Fire, no
		-- average inside a state; the fight's rates are the states' at their weights (15.8's point in raid mode: Rapid Fire 15
		-- of the 180 weighted seconds), and the cycle outside and inside Rapid Fire is the levelling weave's at the same speeds
		-- (the cycle reads no armor or debuff)
		-- The mana never runs out here (richPoint, regen 200 a second: raid-mode design 7.5's rich regime, every cast at its rate)
		{ "raid weave: the cycle per state of the fight at its Rapid Fire; the fight's rates the states' weighted mean", function()
			local raid = { mode = "raid", manaMax = 4000, regenRest = 200, regenCast = 200, spirit = 70, armorPen = 0 }
			local wv, lv = M.Weave(p158(raid)), M.Weave(p158({}))
			T.near(wv.rfUp, 15 / 180, 1e-12, "Rapid Fire's share of the fight")
			T.near(wv.base.C, lv.base.C, 1e-12, "the cycle outside Rapid Fire"); T.near(wv.rapidFire.C, lv.rapidFire.C, 1e-12, "inside it")
			T.truthy(wv.rapidFire.C < wv.base.C - 0.1, "Rapid Fire shortens the cycle")
			T.near(wv.average.rates.auto, (165 / wv.base.C + 15 / wv.rapidFire.C) / 180, 1e-12, "one Auto Shot a cycle of each state")
			T.near(wv.average.rates.raptor, (165 * wv.base.rates.raptor + 15 * wv.rapidFire.rates.raptor) / 180, 1e-12, "Raptor Strike")
		end },
		-- The Use buffs' windows (raid-mode design 6.3, 6.8): each fires at 5 s and again when its cooldown is over; a buff of
		-- the burst category (1141) locks the others of it for its own duration, so a second one fires when the first ends; one
		-- of no category (Nat Pagle's Broken Reel 231271) is not locked; at one instant they fire in their order (Score.SetUses:
		-- wowsims' registration order): Cloudkeeper Legplates 14554 (30 s every 15 min) at 5 s, Earthstrike at the end of their
		-- lock, 35-55 and 155-175 s; a window near the end counts by the time weight (Model.UseUptimes: its integral of w over
		-- 180)
		{ "raid use: Earthstrike 20 s every 120 s fires at 5 and 125 s; two burst buffs do not overlap; the uptime by the time weight", function()
			local es, kiss, reel = ns.UseData[21180], ns.UseData[22954], ns.UseData[231271]
			local f = M.Fight(raidPoint({ uses = { es } }))
			T.eq(windowsText(f.uses[1]), "5-25,125-145", "Earthstrike")
			T.near(M.UseUptimes({ es })[es.spell], 40 / 180, 1e-12, "40 of the 180 weighted seconds")
			f = M.Fight(raidPoint({ uses = { es, kiss, reel } }))
			T.eq(windowsText(f.uses[1]), "5-25,125-145", "Earthstrike first")
			T.eq(windowsText(f.uses[2]), "25-40,145-160", "Kiss of the Spider when Earthstrike's 20 s end")
			T.eq(windowsText(f.uses[3]), "5-20,95-110", "Nat Pagle's Broken Reel: no category, at 5 s and every 90 s")
			local swapped = M.Fight(raidPoint({ uses = { kiss, es } }))
			T.eq(windowsText(swapped.uses[1]), "5-20,125-140", "Kiss of the Spider first")
			T.eq(windowsText(swapped.uses[2]), "20-40,140-160", "Earthstrike after it")
			local legsFirst = M.Fight(raidPoint({ uses = { ns.UseData[14554], es } }))
			T.eq(windowsText(legsFirst.uses[1]), "5-35", "the legs at 5 s, once in the fight")
			T.eq(windowsText(legsFirst.uses[2]), "35-55,155-175", "Earthstrike when the legs' 30 s end")
			-- a window that runs past 175 s counts by the weight: 5-35 s and 175-205 s, 30 + 5 weighted seconds
			local late = { spell = 1, stats = { AP = 10 }, duration = 30, cooldown = 170 }
			T.near(M.UseUptimes({ late })[1], 35 / 180, 1e-12, "the window from 175 s fades out")
			-- a cast at 182.5 s still counts: 182.5-185 s weighs 180 - (175 + 7.5 - 7.5^2 / 20) = 0.3125 s
			local edge = { spell = 3, stats = { AP = 10 }, duration = 10, cooldown = 177.5 }
			T.near(M.UseUptimes({ edge })[3], 10.3125 / 180, 1e-12, "a cast between 180 and 185 s")
			local bad = { spell = 2, stats = { AP = 10 }, duration = 30, cooldown = 20 }
			T.eq(pcall(M.Total, raidPoint({ uses = { bad } })), false, "a cooldown below the duration is an error")
			local noSpell = { stats = { AP = 10 }, duration = 10, cooldown = 100 }
			local okS, errS = pcall(M.Total, raidPoint({ uses = { noSpell } }))
			T.eq(okS, false, "a buff without its spell is an error")
			T.truthy(tostring(errS):find("a Use buff of the raid fight is not { spell, stats", 1, true), tostring(errS))
			local ok, err = pcall(M.Total, raidPoint({ mode = "level", uses = { es } }))
			T.eq(ok, false); T.truthy(tostring(err):find("p.uses in levelling mode", 1, true), tostring(err))
		end },
		-- A Use buff in the raid fight (raid-mode design 6.8): applied to its state's copy of the point (Model.ApplyStats) but
		-- for the pet's attack power, which keeps its summon's (wowsims sim/hunter/pets.go:160-171, EV-0072); the hawks follow
		-- the owner. Two made-up burst buffs of 200 attack power, 15 s every 300 s: the first fires at 5 s with Rapid Fire, the
		-- second when it ends, 20-35 s, outside Rapid Fire; without Quick Shots the Auto Shots' attack power part is in
		-- proportion to the shots' speed, so the first adds 1.4 times what the second adds to them (my arithmetic)
		{ "raid use: the pet keeps its summon's attack power, the hawks take the buff; an attack power buff inside Rapid Fire is worth more", function()
			local A = { spell = 1, stats = { AP = 200 }, duration = 15, cooldown = 300, category = M.BURST_CATEGORY }
			local B = { spell = 2, stats = { AP = 200 }, duration = 15, cooldown = 300, category = M.BURST_CATEGORY }
			local tal = { deadlyAspects = 0 }
			local P0, PA = M.Parts(raidPoint({}, tal)), M.Parts(raidPoint({ uses = { A } }, tal))
			local PAB = M.Parts(raidPoint({ uses = { A, B } }, tal))
			T.near(PA.pet, P0.pet, 1e-12, "the pet: its summon's attack power")
			T.truthy(PA.hawks > P0.hawks + 1e-6, "the hawks take the buff")
			T.near((PA.auto - P0.auto) / (PAB.auto - PA.auto), 1.4, 1e-9, "inside Rapid Fire 1.4 times outside")
			-- the pet reads the higher of the two attack powers (pets.go:126): at map 1500 over rap 900 the melee one, which a
			-- Strength buff raises (Accursed Chalice 228078: 80 Strength, Game/UseData.lua); held at the summon's too
			local hi = { map = 1500, rap = 900 }
			local Q0 = M.Parts(raidPoint(hi, tal))
			local QC = M.Parts(raidPoint({ map = 1500, rap = 900, uses = { ns.UseData[228078] } }, tal))
			T.truthy(Q0.pet > 0, "the pet deals damage")
			T.near(QC.pet, Q0.pet, 1e-12, "the pet: its summon's melee attack power")
			local ok, err = pcall(M.Total, raidPoint({ petRap = 100 }))
			T.eq(ok, false); T.truthy(tostring(err):find("p.petRap and p.petMap come together", 1, true), tostring(err))
		end },
		-- The levelling mode's Use weights (the user's answer O6; raid-mode design 6.8): a Use buff's attack power never reaches
		-- the pet (wowsims sim/hunter/pets.go:160-171 keepSummonStats), so W.AP_USE is the derivative of the total by 10
		-- attack power with the pet's attack powers held at the point's (p.petRap, p.petMap): below W.AP with a pet out, equal
		-- to it with none (Lone Wolf with no pet out); W.RAP_USE, W.MAP_USE (= W.STR_USE) and W.AGI_USE likewise, W.INT_USE
		-- Careful Aim's 20% a rank of W.AP_USE; raid mode has none of them (its fight runs the buffs)
		{ "levelling use: a Use buff's attack power is priced without the pet's share, W.AP_USE < W.AP with a pet out", function()
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			tal.carefulAim = 5
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			p.tal = tal
			local W, dRap, t0 = M.Weights(p)
			local function held(stats)
				local q = {}
				for k, v in pairs(p) do q[k] = v end
				q.petRap, q.petMap = p.rap, p.map
				M.ApplyStats(q, stats)
				return (M.Total(q) - t0) / 10 / dRap
			end
			T.near(W.AP_USE, held({ AP = 10 }), 1e-12, "AP"); T.near(W.RAP_USE, held({ RAP = 10 }), 1e-12, "RAP")
			T.near(W.MAP_USE, held({ MAP = 10 }), 1e-12, "MAP"); T.eq(W.STR_USE, W.MAP_USE, "STR")
			T.near(W.AGI_USE, held({ AGI = 10 }), 1e-12, "AGI"); T.near(W.INT_USE, W.AP_USE, 1e-12, "Careful Aim 5/5: 1 Int = 1 AP")
			T.truthy(W.AP_USE < W.AP - 0.01, "the pet's share left out of AP"); T.truthy(W.AGI_USE < W.AGI - 0.01, "and of AGI")
			local lone = {}
			for k, v in pairs(p) do lone[k] = v end
			local tl = {}
			for k, v in pairs(tal) do tl[k] = v end
			tl.loneWolf, lone.tal, lone.petOut = 1, tl, false
			local Wl = M.Weights(lone)
			T.near(Wl.AP_USE, Wl.AP, 1e-12, "no pet out: nothing to leave out")
			T.eq(M.Weights(raidPoint({})).AP_USE, nil, "raid mode: the fight runs the Use buffs")
			-- heldAt: the derivative of the total by 10 of a key at a point pt with the pet's attack powers held at pt's
			local function heldAt(pt, stats)
				local _, dR, t = M.Weights(pt)
				local q = {}
				for k, v in pairs(pt) do q[k] = v end
				q.petRap, q.petMap = pt.rap, pt.map
				M.ApplyStats(q, stats)
				return (M.Total(q) - t) / 10 / dR
			end
			-- where the pet reads the melee attack power (map 300 over rap: the higher of the two, pets.go:126), a Use buff's
			-- MAP and Strength reach nothing of the BM build: W.MAP_USE = W.STR_USE = 0, the held derivative, where W.MAP and
			-- W.STR are the pet's share
			local hm = {}
			for k, v in pairs(p) do hm[k] = v end
			hm.map = p.rap + 300
			local Wm = M.Weights(hm)
			T.truthy(Wm.MAP > 0.05 and Wm.STR > 0.05, "W.MAP and W.STR: the pet's share")
			T.near(Wm.MAP_USE, heldAt(hm, { MAP = 10 }), 1e-12, "MAP with the pet held")
			T.near(Wm.MAP_USE, 0, 1e-12, "the BM build: no attack of the hunter's reads the melee attack power")
			T.eq(Wm.STR_USE, Wm.MAP_USE, "STR as MAP")
			-- the Survival weave's melee reads the melee attack power (svPoint: rap over map, the pet reads rap): W.AP_USE holds
			-- the melee's share of a Use buff's attack power, W.RAP_USE not, and both leave the pet's out
			local sv = svPoint({}, {})
			local Ws = M.Weights(sv)
			T.near(Ws.RAP_USE, heldAt(sv, { RAP = 10 }), 1e-12, "the weave: RAP with the pet held")
			T.near(Ws.AP_USE, heldAt(sv, { AP = 10 }), 1e-12, "the weave: AP with the pet held")
			T.near(Ws.MAP_USE, heldAt(sv, { MAP = 10 }), 1e-12, "the weave: MAP with the pet held")
			T.truthy(Ws.AP_USE > Ws.RAP_USE + 0.1, "the weave's melee takes the attack power's melee part")
			T.truthy(Ws.MAP_USE > 0.1, "the weave's melee reads MAP")
			T.truthy(Ws.RAP_USE < Ws.RAP - 0.05, "the pet's share left out of RAP")
		end },
		-- the pet behind the boss in raid mode (CONST.raid.petTanks 0, Model.PetTanks): no parry, so expertise past the dodge
		-- (6.5% at +3) adds nothing and W.EXPERTISE_PARRY is 0; levelling's tanking pet at the same +3 point is parried up to
		-- 14% (Model.PetParry(3))
		{ "parry: none from behind in raid mode; the levelling pet tanks", function()
			T.eq(M.PetTanks("raid"), 0); T.eq(M.PetTanks("level"), M.CONST.petTanks)
			T.eq(pcall(M.PetTanks, "Raid"), false, "another mode is an error")
			local function total(mode, e) return M.Total(raidPoint({ mode = mode, expertise = e })) end
			T.near(total("raid", 10), total("raid", 6.5), 1e-12, "raid: nothing past the dodge")
			T.truthy(total("level", 10) > total("level", 6.5) + 1e-9, "levelling at +3: the tanking pet's parry")
			T.eq(M.Weights(raidPoint({})).EXPERTISE_PARRY, 0, "raid: W.EXPERTISE_PARRY 0")
			T.truthy(M.Weights(raidPoint({ mode = "level" })).EXPERTISE_PARRY > 0, "levelling: the parry's slope")
		end },
		-- The creature type of the mode's target (Model.TargetShare; the user's answer 5 = (a)): raid mode the boss's dragonkin
		-- (wowsims defaults.siml:65), share 1, every other type 0; levelling Model.AP_CREATURE_SHARE (0.3) for each. So
		-- Beastslaying (beasts) adds nothing in raid, W.AP_VS_DRAGONKIN is W.AP_VS and the other types' weights 0, and
		-- Model.ApplyStats puts an AP_VS key at its type's share
		{ "beastslaying and AP vs type: levelling 0.3 for every type; raid dragonkin 1, beast 0", function()
			T.eq(M.TargetShare("DRAGONKIN", "raid"), 1); T.eq(M.TargetShare("BEAST", "raid"), 0)
			T.eq(M.TargetShare("UNDEAD", "raid"), 0); T.eq(M.TargetShare("BEAST", "level"), M.AP_CREATURE_SHARE)
			T.eq(pcall(M.TargetShare, "BEAST", nil), false, "no mode is an error")
			T.eq(pcall(M.TargetShare, "BEASTS", "raid"), false, "a type outside Model.CREATURE_TYPES is an error")
			T.eq(pcall(M.TargetShare, "BEASTS", "level"), false, "in levelling too")
			local raid, lvl = raidPoint({ beastSlaying = 6 }), raidPoint({ mode = "level", beastSlaying = 6 })
			T.near(M.Total(raid), M.Total(raidPoint({})), 1e-12, "raid: Beastslaying adds nothing")
			T.truthy(M.Total(lvl) > M.Total(raidPoint({ mode = "level" })) + 1e-9, "levelling: Beastslaying adds")
			local W, Wl = M.Weights(raid), M.Weights(lvl)
			T.eq(W.BEAST_SLAYING, 0, "raid: W.BEAST_SLAYING 0"); T.truthy(Wl.BEAST_SLAYING > 0)
			T.truthy(W.AP_VS > 0, "raid: AP vs the target has a weight")
			T.near(W.AP_VS_DRAGONKIN, W.AP_VS, 1e-12, "raid: dragonkin whole")
			for _, t in ipairs(M.CREATURE_TYPES) do
				if t ~= "DRAGONKIN" then T.eq(W["AP_VS_" .. t], 0, "raid: " .. t .. " 0") end
				T.near(Wl["AP_VS_" .. t], Wl.AP_VS * M.AP_CREATURE_SHARE, 1e-12, "levelling: " .. t .. " at the share")
			end
			local q = raidPoint({})
			M.ApplyStats(q, { AP_VS_DRAGONKIN = 20, AP_VS_BEAST = 30 })
			T.eq(q.apVsTarget, 20, "raid: the dragonkin key whole, the beast key not at all")
			local ql = raidPoint({ mode = "level" })
			M.ApplyStats(ql, { AP_VS_DRAGONKIN = 20, AP_VS_BEAST = 30 })
			T.near(ql.apVsTarget, 50 * M.AP_CREATURE_SHARE, 1e-12, "levelling: both at the share")
		end },
		{ "spec: Spirit's mana value adds Rapid Recuperation and Resourcefulness, capped at 100% in combat", function()
			local t = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do t[k] = v end
			local base = M.SecondaryRates(t).manaPerSpi
			t.rapidRecuperation = 2
			T.truthy(M.SecondaryRates(t).manaPerSpi > base)
			t.resourcefulness = 2; t.bestialDiscipline = 2
			T.near(M.SecondaryRates(t).manaPerSpi, 1 + 6 * 1, 1e-9, "never more than all regen while casting")
		end },
		{ "talents: Careful Aim turns Intellect into damage, Lightning Reflexes scales Agility", function()
			local W0 = M.Weights(ref)
			T.eq(W0.INT, 0, "no Careful Aim: Intellect is mana only")
			T.eq(W0.STA, 0, "Stamina never counts as damage")
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			tal.carefulAim = 5; tal.lightningReflexes = 5
			p.tal = tal
			local W1 = M.Weights(p)
			T.near(W1.INT, W1.AP, 1e-9, "Careful Aim 5/5: 1 Int = 1 AP")
			T.near(W1.AGI / W0.AGI, 1.15, 0.01, "Lightning Reflexes 5/5: +15% Agility")
		end },
		{ "talents: Mortal Shots raises crit value, no Summon Hawk removes hawks", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			tal.mortalShots = 5
			p.tal = tal
			T.truthy(M.Weights(p).CRIT > M.Weights(ref).CRIT, "crit worth more with Mortal Shots")
			tal.summonHawk = 0
			T.eq(M.Parts(p).hawks, 0)
		end },
		-- weapons priced at their own speed: a set with the main hand empty goes through the model too
		{ "weapon speed: an empty main hand still weaves (unarmed), no Raptor Strike there", function()
			local function build(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal, p.survival = tal, true
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			local bare = { mhDPS = 0, ohDPS = 0, unarmed = true }
			local armed, unarmed = M.Parts(build()), M.Parts(build(bare))
			-- the weave keeps its cycle (the ranged path sets it here), so the shots keep their count
			T.near(unarmed.auto, armed.auto, 1e-9, "Auto Shot: one a cycle, unarmed too")
			T.truthy(unarmed.melee > 0, "fists + attack power still hit")
			T.truthy(M.Total(build(bare)) < M.Total(build()), "taking the weapons off is a loss")
			-- Raptor Strike needs a melee weapon: unarmed melee is below a 0-DPS weapon's
			local zeroWeapon = M.Parts(build({ mhDPS = 0, ohDPS = 0 })).melee
			T.truthy(unarmed.melee < zeroWeapon - 1e-6, "no Raptor unarmed: " .. unarmed.melee .. " vs " .. zeroWeapon)
			-- Mongoose Bite ranks 1-3 need a weapon (no bites unarmed at 43); rank 4 from 58 has no
			-- requirement row; Strider Kick has none at any level
			local ep = { exposePrey = 2 }
			T.near(M.Parts(build(bare, ep)).melee, unarmed.melee, 1e-9, "no Mongoose Bite unarmed at 43")
			local b58 = { mhDPS = 0, ohDPS = 0, unarmed = true, level = 58 }
			T.truthy(M.Parts(build(b58, ep)).melee > M.Parts(build(b58)).melee + 1e-6, "rank 4 bites unarmed at 58")
			T.truthy(M.Parts(build(bare, { striderKick = 1 })).melee > unarmed.melee + 1e-6, "Strider Kick unarmed")
			-- the melee weights price a held weapon even when the snapshot is unarmed (compared as DPS:
			-- the RAP unit itself differs, the unarmed model has no Raptor)
			local Wu, dU = M.Weights(build(bare))
			local Wz, dZ = M.Weights(build({ mhDPS = 0, ohDPS = 0 }))
			T.near(Wu.MH_DPS * dU, Wz.MH_DPS * dZ, 1e-9, "MH_DPS with the weapon held")
			T.near(Wu.TH_DPS * dU, Wz.TH_DPS * dZ, 1e-9, "TH_DPS with the weapon held")
		end },
		{ "weights stay sane at level 60 and level 20", function()
			for _, lvl in ipairs({ 20, 60 }) do
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.level = lvl
				local W = M.Weights(p)
				T.truthy(W.AGI > 1.5 and W.AGI < 4, "agi at " .. lvl .. " = " .. W.AGI)
				T.truthy(W.RANGED_DPS > 5 and W.RANGED_DPS < 16, "dps at " .. lvl .. " = " .. W.RANGED_DPS)
			end
		end },
		-- the pet's own swing time (p.petSwing): Frenzy's crit chances, the white DPS normalized
		{ "pet swing: Frenzy counts the pet's own swing; without Frenzy the pet's DPS stays the same", function()
			local function pet(swing, frenzy)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.frenzy = frenzy
				p.tal, p.petSwing, p.petFamily = tal, swing, 2 -- Cat: Claw + Bite
				return M.Parts(p).pet
			end
			T.near(pet(1.2, 0), pet(2.0, 0), 1e-9, "no Frenzy: a faster swing hits for less, same DPS")
			T.eq(M.PET_BASE_SWING, 2.0)
			T.near(pet(nil, 4), pet(2.0, 4), 1e-9, "not seen: the 2.0 s base swing")
			T.truthy(pet(1.2, 4) > pet(2.0, 4) + 1e-6, "Frenzy 4/4: more crit chances at 1.2 s")
			-- Frenzy's gain is the white damage x 0.3 x its uptime, so the gain ratio is the uptime ratio:
			-- uptime = 1 - (1 - 0.2 x rank x pet crit)^(8 / swing x (1 + rf) x haste x 1.3 + casts per 10 s x 0.8);
			-- the swings come at the owner-hasted rate petHaste applies: at level 43 Rapid Fire's average
			-- rf = 0.40 x 15 / 300 (Rapid Killing 0), haste 1 (ref.haste 0). A Cat with Bestial Discipline 2/2
			-- casts 1 Bite and (120 - 35) / 25 Claws per 10 s
			local petCrit = ref.crit / 100 + 0.02 * M.DEFAULT_TALENTS.ferocity
			local rf = 0.40 * 15 / 300
			local function up(swing, casts10) return 1 - (1 - 0.2 * 4 * petCrit) ^ (8 / swing * (1 + rf) * 1.3 + casts10 * 0.8) end
			local cat, white = 1 + 85 / 25, pet(2.0, 0)
			T.near((pet(1.2, 4) - white) / (pet(2.0, 4) - white), up(1.2, cat) / up(2.0, cat), 1e-9, "uptime at 1.2 s / 2.0 s")
			local bad = {}
			for k, v in pairs(ref) do bad[k] = v end
			bad.petSwing = 0
			T.truthy(not pcall(M.Parts, bad), "a swing time of 0 is an error")
		end },
		{ "pet swing: Claw / Bite casts follow the family (Bite only vs Claw + Bite)", function()
			local function gain(family, bd)
				local function pet(frenzy)
					local p = {}
					for k, v in pairs(ref) do p[k] = v end
					local tal = {}
					for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
					tal.frenzy, tal.bestialDiscipline = frenzy, bd
					p.tal, p.petSwing, p.petFamily = tal, 2.0, family
					return M.Parts(p).pet
				end
				return pet(4) - pet(0)
			end
			-- Wolf (1: Bite) and Carrion Bird (7: Claw + Bite) both carry no family damage bonus, so
			-- Frenzy's gain differs by its uptime alone; the 2.0 s swings come at the owner-hasted rate (level 43:
			-- Rapid Fire's average rf = 0.40 x 15 / 300, haste 1)
			local petCrit = ref.crit / 100 + 0.02 * M.DEFAULT_TALENTS.ferocity
			local rf = 0.40 * 15 / 300
			local function up(casts10) return 1 - (1 - 0.2 * 4 * petCrit) ^ (8 / 2.0 * (1 + rf) * 1.3 + casts10 * 0.8) end
			T.truthy(gain(7, 2) > gain(1, 2) + 1e-6, "Claw + Bite: more crit chances than Bite alone")
			T.near(gain(7, 2) / gain(1, 2), up(1 + 85 / 25) / up(1), 1e-9, "uptime: 4.4 vs 1 cast per 10 s")
			T.near(gain(1, 2), gain(1, 0), 1e-9, "Wolf: Bestial Discipline adds no casts without Claw")
			T.truthy(gain(7, 2) > gain(7, 0) + 1e-6, "Carrion Bird: more focus, more Claws, more crit chances")
		end },
		-- Frenzy counts the pet's swings at the owner-hasted rate petHaste puts on its white damage, (1 + rf) x haste
		{ "pet swing: Frenzy's swing count takes the owner's haste; with rf 0 and haste 0 it is 8 / swing x 1.3", function()
			local petCrit = ref.crit / 100 + 0.02 * M.DEFAULT_TALENTS.ferocity
			local cat = 1 + 85 / 25 -- a Cat's Bite and Claws per 10 s with Bestial Discipline 2/2
			local function pet(level, haste, swing, frenzy)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.frenzy = frenzy
				p.level, p.haste, p.tal, p.petSwing, p.petFamily = level, haste, tal, swing, 2
				return M.Parts(p).pet
			end
			-- Frenzy's gain is the white damage (x petHaste) x 0.3 x its uptime
			local function gain(level, haste, swing) return pet(level, haste, swing, 4) - pet(level, haste, swing, 0) end
			local function up(swings8) return 1 - (1 - 0.2 * 4 * petCrit) ^ (swings8 * 1.3 + cat * 0.8) end
			-- level 25: Rapid Fire not learned (rf 0); haste 0: 8 / swing swings in 8 s
			T.near(gain(25, 0, 1.2) / gain(25, 0, 2.0), up(8 / 1.2) / up(8 / 2.0), 1e-9, "rf 0, haste 0")
			-- 5% haste: the white damage x 1.05 and 1.05 x the swings, so Frenzy is up longer
			T.near(gain(25, 5, 1.2) / gain(25, 0, 1.2), 1.05 * up(8 / 1.2 * 1.05) / up(8 / 1.2), 1e-9, "haste 5%")
			T.truthy(up(8 / 1.2 * 1.05) > up(8 / 1.2) + 1e-6, "Frenzy's uptime rises with haste")
			-- level 43: Rapid Fire's average rf = 0.40 x 15 / 300 (Rapid Killing 0) on top of the haste
			local rf = 0.40 * 15 / 300
			T.near(gain(43, 5, 1.2) / gain(43, 0, 1.2), 1.05 * up(8 / 1.2 * (1 + rf) * 1.05) / up(8 / 1.2 * (1 + rf)), 1e-9,
				"rf and haste")
			-- the melee-only attack speed (aura 319, MeleeSpeedMultiplier, which the pet inherits: wowsims sim/core/pet.go
			-- enableDynamicMeleeSpeed) reaches the pet's white damage and Frenzy's swing count as p.haste does
			local function petM(level, meleeHaste, frenzy)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.frenzy = frenzy
				p.level, p.meleeHaste, p.tal, p.petSwing, p.petFamily = level, meleeHaste, tal, 1.2, 2
				return M.Parts(p).pet
			end
			local function gainM(level, meleeHaste) return petM(level, meleeHaste, 4) - petM(level, meleeHaste, 0) end
			T.near(gainM(25, 5) / gainM(25, 0), 1.05 * up(8 / 1.2 * 1.05) / up(8 / 1.2), 1e-9, "melee-only haste 5%")
			T.near(gainM(43, 5) / gainM(43, 0), 1.05 * up(8 / 1.2 * (1 + rf) * 1.05) / up(8 / 1.2 * (1 + rf)), 1e-9,
				"rf and the melee-only haste")
			T.near(petM(43, 5, 0) - petM(43, 0, 0), pet(43, 5, 1.2, 0) - pet(43, 0, 1.2, 0), 1e-12,
				"no Frenzy: the white damage as with p.haste")
		end },
		-- The hawks swing at the owner's ranged speed (wowsims sim/hunter/summon_hawk.go:63-65): the quiver, p.rangedHaste
		-- (aura 140), Quick Shots 6150 (aura 140 +30), Rapid Fire 3045's aura 140 +40 and p.haste (aura 342, which raises
		-- the ranged speed as well as the melee speed); the melee-only p.meleeHaste (aura 319) not at all
		{ "hawks: the owner's ranged speed (p.haste, ranged-only haste, quiver, Quick Shots, Rapid Fire), not melee-only", function()
			local function hawks(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return M.Parts(p).hawks
			end
			-- Deadly Aspects 0: no Quick Shots, so its uptime does not move with the shots' speed
			local noQS = { deadlyAspects = 0 }
			T.truthy(hawks({}, noQS) > 0, "hawks at 43")
			T.near(hawks({ haste = 5 }, noQS) / hawks({}, noQS), 1.05, 1e-12, "p.haste: x (1 + h/100)")
			T.near(hawks({ haste = 2 }, noQS) / hawks({ haste = 0 }, noQS), 1.02, 1e-12, "an enchant's 2%")
			T.near(hawks({ haste = 10, rangedHaste = 4 }, noQS) / hawks({}, noQS), 1.10 * 1.04, 1e-12,
				"p.haste and the ranged-only haste multiply")
			T.near(hawks({ meleeHaste = 5 }, noQS), hawks({}, noQS), 1e-12, "melee-only haste leaves them alone")
			T.near(hawks({ haste = 5, meleeHaste = 5 }, noQS), hawks({ haste = 5 }, noQS), 1e-12,
				"melee-only haste leaves them alone next to p.haste")
			T.near(hawks({ rangedHaste = 5 }, noQS) / hawks({}, noQS), 1.05, 1e-12, "the ranged-only haste")
			T.near(hawks({ quiver = 0.15 }, noQS) / hawks({ quiver = 0 }, noQS), 1.15, 1e-12, "the quiver")
			-- Rapid Fire's average: 0.40 x 15 / (300 - 60 x Rapid Killing) at level 43, none before 26
			T.near(hawks({}, { deadlyAspects = 0, rapidKilling = 1 }) / hawks({}, noQS), (1 + 0.40 * 15 / 240) / (1 + 0.40 * 15 / 300),
				1e-12, "Rapid Fire's aura 140")
			T.near(hawks({ haste = 5 }, { deadlyAspects = 0, rapidKilling = 1 }) / hawks({ haste = 5 }, noQS),
				(1 + 0.40 * 15 / 240) / (1 + 0.40 * 15 / 300), 1e-12, "Rapid Fire's aura 140 next to p.haste")
			T.near(hawks({ level = 25 }, { deadlyAspects = 0, rapidKilling = 1 }), hawks({ level = 25 }, noQS), 1e-12,
				"no Rapid Fire at 25")
			T.near(hawks({ level = 25, haste = 5 }, noQS) / hawks({ level = 25 }, noQS), 1.05, 1e-12, "p.haste at 25")
			-- with Deadly Aspects p.haste moves the hawks by its own factor and through Quick Shots' uptime: Auto Shots in
			-- 12 s at the shots' speed (the quiver, the ranged-only haste, x1.3 while it is up, p.haste) roll Quick Shots 2%
			-- a rank each
			local function qs(haste, rangedHaste) return 1 - (1 - 0.1) ^ (12 * 1.13 * (1 + rangedHaste / 100) * 1.3 * (1 + haste / 100) / 2.6) end
			T.near(hawks({ haste = 5 }) / hawks({}), 1.05 * (1 + 0.3 * qs(5, 0)) / (1 + 0.3 * qs(0, 0)), 1e-12,
				"p.haste and Quick Shots' uptime")
			T.near(hawks({ rangedHaste = 5 }) / hawks({}), 1.05 * (1 + 0.3 * qs(0, 5)) / (1 + 0.3 * qs(0, 0)), 1e-12,
				"the ranged-only haste and Quick Shots' uptime")
			T.near(hawks({ haste = 5 }), hawks({ rangedHaste = 5 }), 1e-12, "p.haste and the ranged-only haste alike")
		end },
		-- Who takes which owner speed (wowsims, raid-mode W1 design 7.1; Core/Model.lua, the p fields): an item's or
		-- enchant's aura 342 (p.haste: AttachHastePseudoStats, melee and ranged speed) reaches the shots, the melee swings,
		-- the pet and the hawks; a set bonus's aura 9 or 342 and Wind Blessed (p.attackSpeed: MultiplyAttackSpeed) the shots,
		-- the melee swings and the pet, not the hawks (they inherit RangedSpeedMultiplier alone, sim/core/pet.go:415-431);
		-- haste rating (p.hasteRating: hasteRatingMultiplier on the owner's totals) the shots and the melee swings, neither
		-- the pet nor the hawks (the pet inherits the melee and attack speed multipliers, pet.go:381-398). Deadly Aspects 0:
		-- no Quick Shots, whose uptime follows the shots' speed and reaches the hawks (aura 140) whichever source moves it
		{ "hawk speed: an item's or enchant's aura 342 reaches the hawks; a set bonus's and Wind Blessed's do not; haste rating reaches neither the pet nor the hawks", function()
			local function parts(over, survival)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.deadlyAspects = 0
				p.tal, p.survival = tal, survival or false
				for k, v in pairs(over) do p[k] = v end
				return M.Parts(p)
			end
			local base, h, a, r = parts({}), parts({ haste = 2 }), parts({ attackSpeed = 2 }), parts({ hasteRating = 2 })
			T.truthy(base.hawks > 0 and base.pet > 0, "hawks and a pet at 43")
			T.near(h.hawks / base.hawks, 1.02, 1e-12, "an item's aura 342: the hawks x1.02")
			T.near(a.hawks, base.hawks, 1e-12, "a set bonus's and Wind Blessed's attack speed: not the hawks")
			T.near(r.hawks, base.hawks, 1e-12, "haste rating: not the hawks")
			T.truthy(h.pet > base.pet + 1e-9, "an item's aura 342: the pet")
			T.near(a.pet, h.pet, 1e-12, "the attack speed reaches the pet as an item's aura 342 does")
			T.near(r.pet, base.pet, 1e-12, "haste rating: not the pet")
			-- the shots and their casts take all three alike: the owner's speed (TotalRangedHasteMultiplier)
			for _, k in ipairs({ "auto", "aimed", "arcane", "serpent", "dive" }) do
				T.near(a[k], h[k], 1e-12, k .. ": attack speed as aura 342"); T.near(r[k], h[k], 1e-12, k .. ": haste rating as aura 342")
			end
			T.truthy(r.auto > base.auto + 1e-9, "haste rating speeds Auto Shot")
			-- the Survival weave: the cycle, the shots and the melee swings take all three alike (the owner's speed)
			local sb, sh, sa, sr = parts({}, true), parts({ haste = 2 }, true), parts({ attackSpeed = 2 }, true), parts({ hasteRating = 2 }, true)
			T.truthy(sh.melee > sb.melee + 1e-9, "the weave's melee moves")
			for _, k in ipairs({ "melee", "auto", "arcane", "trap", "serpent" }) do
				T.near(sa[k], sh[k], 1e-12, "the weave's " .. k .. ": attack speed"); T.near(sr[k], sh[k], 1e-12, "the weave's " .. k .. ": haste rating")
			end
			T.near(sr.pet, sb.pet, 1e-12, "the weave: haste rating not on the pet"); T.near(sa.pet, sh.pet, 1e-12, "attack speed on the pet")
		end },
		-- W.ATTACK_SPEED and W.HASTE_RATING are each the value of one more 1% source of their input at the worn point (as
		-- W.HASTE, Model.Weights): (1 + x/100) times the derivative by the input's percent; the hawks take neither, the pet
		-- not the rating, so W.HASTE > W.ATTACK_SPEED > W.HASTE_RATING with a pet and hawks out
		{ "weights: W.ATTACK_SPEED and W.HASTE_RATING as one more source of their input", function()
			local function copy(t) local q = {} for k, v in pairs(t) do q[k] = v end return q end
			local p = copy(ref)
			p.haste, p.attackSpeed, p.hasteRating = 1, 3.02, 2
			local W, dRap, t0 = M.Weights(p)
			for key, wk in pairs({ attackSpeed = "ATTACK_SPEED", hasteRating = "HASTE_RATING" }) do
				local m = 1 + p[key] / 100
				local q = copy(p); q[key] = p[key] + m * 0.5
				local byInput = (M.Total(q) - t0) / (m * 0.5) / dRap
				T.truthy(byInput > 0.5, wk .. " moves the damage: " .. byInput)
				T.near(W[wk], m * byInput, 1e-9, wk .. " = (1 + " .. p[key] .. "/100) x the derivative by the input")
			end
			T.truthy(W.HASTE > W.ATTACK_SPEED + 1e-6, "W.HASTE above W.ATTACK_SPEED: the hawks")
			T.truthy(W.ATTACK_SPEED > W.HASTE_RATING + 1e-6, "W.ATTACK_SPEED above W.HASTE_RATING: the pet")
		end },
		-- The hawks take the owner's expertise against the mob's dodge (wowsims sim/hunter/summon_hawk.go:85
		-- StatInheritance ExpertisePercent), the pet's rule without the parry: Model.MobAvoid 5% at an equal-level mob,
		-- 6.5% at +3. A hawk's white swing is one roll (Model.Parts white): 1 - miss - max(0, dodge - expertise) + its crit -
		-- glance x (1 - the glance's average), the crit half the owner's and Ferocity's 10%, at +3 less 3% and 1.8% of aura
		-- crit (all of a hawk's crit is aura crit)
		{ "hawks: the owner's expertise lowers the mob's dodge, up to the dodge and not past it", function()
			local function hawks(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				for k, v in pairs(over or {}) do p[k] = v end
				return M.Parts(p).hawks
			end
			-- ref: 1% hit against 5% base miss, so 0.96 land before dodge; glance 10% at 0.95
			local c = 0.5 * ref.crit / 100 + 0.10
			local rest = 0.96 + c - 0.10 * 0.05
			T.near(hawks({ expertise = 2 }) / hawks({}), (rest - 0.03) / (rest - 0.05), 1e-12, "2% expertise: dodge 3%")
			T.near(hawks({ expertise = 5 }) / hawks({}), rest / (rest - 0.05), 1e-12, "5% expertise: no dodge")
			T.near(hawks({ expertise = 8 }), hawks({ expertise = 5 }), 1e-12, "past the dodge expertise does nothing")
			-- +3: 8% base miss (Model.HitCap), 6.5% dodge, glance 40% at 0.65
			local function at3(e) return hawks({ mobDiff = 3, expertise = e }) end
			local rest3 = 0.93 + (c - 0.03 - 0.018) - 0.40 * 0.35
			T.near(at3(6) / at3(0), (rest3 - 0.005) / (rest3 - 0.065), 1e-12, "+3: 6% expertise of the 6.5% dodge")
			T.near(at3(9), at3(6.5), 1e-12, "+3: past the 6.5% dodge expertise does nothing")
		end },
		-- Every consumer of expertise (the hawks, the pet's dodge and parry, the melee swings' dodge) clamps the dodge at
		-- Model.MobAvoid; below it the DPS is linear in expertise. W.EXPERTISE is that slope, taken at expertise 0 with the
		-- other inputs at p, so a worn expertise at or past the cap keeps it (Score.SetValue applies the cap). Past the dodge
		-- the tanking pet's parry is left (Model.PetParry: 5% = the dodge at +0, 14% at +3): W.EXPERTISE_PARRY is its slope,
		-- linear up to the parry, nothing past it
		{ "W.EXPERTISE: the slope below the cap, taken at expertise 0 whatever p's expertise", function()
			local function with(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.survival = true -- the weave's melee swings take it too
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			for _, mobDiff in ipairs({ 0, 3 }) do
				local cap, parry = M.MobAvoid(mobDiff), M.PetParry(mobDiff)
				local function total(e) return M.Total(with({ mobDiff = mobDiff, expertise = e })) end
				local slope = (total(0.5) - total(0)) / 0.5 -- DPS per 1% below the cap
				T.truthy(slope > 0, "expertise adds damage below the cap")
				-- linear below the dodge; past it the tanking pet's parry alone, linear up to the parry; nothing past that
				T.near(total(cap) - total(0), slope * cap, 1e-9, "linear up to the cap at +" .. mobDiff)
				local slope2 = (total(cap + 0.5) - total(cap)) / 0.5
				T.near(total(parry) - total(cap), slope2 * (parry - cap), 1e-9, "linear from the dodge to the parry at +" .. mobDiff)
				T.near(total(parry + 2), total(parry), 1e-12, "nothing past the parry at +" .. mobDiff)
				if mobDiff == 0 then T.near(slope2, 0, 1e-12, "+0: the parry is the dodge") else T.truthy(slope2 > 0, "+3: the pet's parry") end
				for _, e in ipairs({ 0, 2, cap, cap + 3 }) do
					local W, dRap = M.Weights(with({ mobDiff = mobDiff, expertise = e }))
					T.near(W.EXPERTISE * dRap, slope, 1e-9, string.format("+%d, %.1f%% worn: the slope below the cap", mobDiff, e))
					T.near(W.EXPERTISE_PARRY * dRap, slope2, 1e-9, string.format("+%d, %.1f%% worn: the parry's slope", mobDiff, e))
				end
			end
		end },
		-- the three attack speed multipliers by scope (wowsims sim/core/unit.go TotalMeleeHasteMultiplier = attack x melee,
		-- TotalRangedHasteMultiplier = attack x ranged; the pet inherits melee and attack speed, the hawks the ranged speed,
		-- which p.haste raises too). In the Survival weave the cycle is set by the ranged path here (the main hand's 2.6 s
		-- swing under K, Model weaveParts): melee-only haste moves nothing of the weave, ranged-only haste shortens the cycle
		-- as p.haste does, more Auto Shots and more swings (raid-mode design 15.7)
		{ "attack speed scopes: melee-only haste is p.haste for melee and the pet, ranged-only is p.haste for the shots", function()
			local function parts(over, level, survival)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.sniperShot = 1
				p.tal, p.level, p.survival = tal, level, survival or false
				for k, v in pairs(over or {}) do p[k] = v end
				return M.Parts(p)
			end
			local SHOTS = { "auto", "aimed", "multi", "arcane", "serpent", "sniper" }
			for _, level in ipairs({ 19, 43 }) do
				-- the weave
				local sBase, sH, sM, sR = parts({}, level, true), parts({ haste = 5 }, level, true), parts({ meleeHaste = 5 }, level, true),
					parts({ rangedHaste = 5 }, level, true)
				T.truthy(sBase.melee > 0, "the weave's melee at " .. level)
				for _, k in ipairs({ "melee", "trap", "auto", "arcane", "serpent" }) do
					T.near(sM[k], sBase[k], 1e-12, "the weave's " .. k .. ": melee-only haste moves nothing at " .. level)
					T.near(sR[k], sH[k], 1e-12, "the weave's " .. k .. ": ranged-only haste as p.haste at " .. level)
				end
				T.truthy(sR.melee > sBase.melee + 1e-9 and sR.auto > sBase.auto + 1e-9, "a shorter cycle: more swings and Auto Shots at " .. level)
				-- from range
				local base, h, m, r = parts({}, level), parts({ haste = 5 }, level), parts({ meleeHaste = 5 }, level),
					parts({ rangedHaste = 5 }, level)
				T.truthy(m.pet > base.pet + 1e-9, "melee-only haste raises the pet")
				T.near(m.pet, h.pet, 1e-12, "the pet as with p.haste at " .. level)
				T.near(r.pet, base.pet, 1e-12, "ranged-only haste leaves the pet alone at " .. level)
				for _, k in ipairs(SHOTS) do
					T.near(m[k], base[k], 1e-12, k .. ": melee-only haste leaves it alone at " .. level)
					T.near(r[k], h[k], 1e-12, k .. ": ranged-only haste as p.haste at " .. level)
				end
				T.truthy(r.auto > base.auto + 1e-9, "ranged-only haste raises Auto Shot at " .. level)
				T.truthy(level < 25 or h.hawks > base.hawks + 1e-9, "p.haste raises the hawks at " .. level)
				T.near(r.hawks, h.hawks, 1e-12, "the hawks take the ranged-only haste as p.haste at " .. level)
				T.near(m.hawks, base.hawks, 1e-12, "melee-only haste leaves the hawks alone at " .. level)
				T.eq(m.dive, base.dive); T.eq(r.dive, base.dive)
			end
		end },
		-- An attack speed input is the product of its scope's sources (Player wornHaste), so a weight is the value of one
		-- more 1% source at the worn point: a new d% source raises the input x to ((1 + x/100)(1 + d/100) - 1) x 100,
		-- by (1 + x/100) x d points, and the weight is (1 + x/100) times the derivative by the input's percent
		{ "attack speed weights: one more 1% source, (1 + x/100) x the derivative by the input's percent", function()
			local function copy(t) local q = {} for k, v in pairs(t) do q[k] = v end return q end
			local p = copy(ref)
			p.haste, p.meleeHaste, p.rangedHaste = 10, 51.5, 4
			local W, dRap, t0 = M.Weights(p)
			for key, wk in pairs({ haste = "HASTE", meleeHaste = "MELEE_HASTE", rangedHaste = "RANGED_HASTE" }) do
				local m = 1 + p[key] / 100
				-- the derivative by the input's percent, over the input's step of a 0.5% source: m x 0.5 points
				local q = copy(p); q[key] = p[key] + m * 0.5
				local byInput = (M.Total(q) - t0) / (m * 0.5) / dRap
				T.truthy(byInput > 0.5, wk .. " moves the damage: " .. byInput)
				T.near(W[wk], m * byInput, 1e-9, wk .. " = (1 + " .. p[key] .. "/100) x the derivative by the input")
			end
			-- one base for the three, so a source of each is the same step: every part takes p.haste and exactly one of
			-- the other two (melee and the pet the melee-only haste, the shots and the hawks the ranged-only haste)
			local e = copy(ref)
			e.haste, e.meleeHaste, e.rangedHaste = 2, 2, 2
			local We = M.Weights(e)
			T.truthy(We.MELEE_HASTE > 0 and We.RANGED_HASTE > 0, "both priced")
			T.near(We.HASTE, We.MELEE_HASTE + We.RANGED_HASTE, 1e-9, "W.HASTE = W.MELEE_HASTE + W.RANGED_HASTE")
			-- a source taken away next to the others: the price -W x amount is within second order (the source's 1% of
			-- the input) of the model's own change. Minor Haste's 1% next to Wind Blessed's 2% (worn haste 1.01 x 1.02):
			local worn = copy(ref); worn.haste = (1.01 * 1.02 - 1) * 100
			local Ww, dw, tw = M.Weights(worn)
			local off = copy(ref); off.haste = 2
			local modelA = (M.Total(off) - tw) / dw
			T.near(-Ww.HASTE / modelA, 1, 0.015, "Minor Haste next to Wind Blessed: " .. -Ww.HASTE .. " for " .. modelA)
			-- Arcanum of Rapidity (319 + 140, 1% each) next to the Automatic Crowd Pummeler's 50% melee speed
			local worn2 = copy(ref); worn2.meleeHaste, worn2.rangedHaste = (1.5 * 1.01 - 1) * 100, 1
			local W2, d2, t2 = M.Weights(worn2)
			local off2 = copy(ref); off2.meleeHaste, off2.rangedHaste = 50, 0
			local modelB = (M.Total(off2) - t2) / d2
			local priceB = -(W2.MELEE_HASTE + W2.RANGED_HASTE)
			T.near(priceB / modelB, 1, 0.015, "Arcanum next to the Pummeler: " .. priceB .. " for " .. modelB)
		end },
		-- the hunter's white swings in the Survival weave (Model weaveParts): one main-hand swing a cycle, each landing with the
		-- white hit chance (Model.LandedHits mh.swings; an unarmed main hand: no Raptor Strike takes a swing). Where the swing
		-- timer sets the cycle (a 6 s main hand: C = M, its swing time at the permanent attack speed p.haste x p.meleeHaste and
		-- Rapid Fire's 40%, 15 s every 300 s, Rapid Killing -60 s a rank, none before level 26) they come at that speed; where
		-- the ranged path sets it (the 2.6 s main hand) once a cycle, whatever the melee speed
		{ "the hunter's white swings at p.haste x p.meleeHaste x Rapid Fire's average", function()
			local function with(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			-- one hand (no dual-wield miss), level 43: miss 5% - 1% hit, dodge 5%
			local function swings(over, tover)
				local q = with(over, tover)
				q.ohDPS, q.unarmed, q.survival = 0, true, true
				return M.LandedHits(q).mh.swings
			end
			local land = 1 - 0.04 - 0.05
			local slow = { mhSpeed = 6.0, haste = 2, meleeHaste = 3 }
			T.near(swings(slow), 1.02 * 1.03 * (1 + 0.40 * 15 / 300) / 6.0 * land, 1e-12, "level 43")
			slow.level = 25
			T.near(swings(slow), 1.02 * 1.03 / 6.0 * land, 1e-12, "no Rapid Fire at 25")
			T.near(swings({ mhSpeed = 6.0 }, { rapidKilling = 1 }), (1 + 0.40 * 15 / 240) / 6.0 * land, 1e-12, "Rapid Killing 1/3")
			-- the 2.6 s main hand: once a cycle, the melee-only speed aside
			local q = with({ meleeHaste = 3, survival = true, ohDPS = 0, unarmed = true })
			T.near(swings({ meleeHaste = 3 }), weaveRates(q).auto * land, 1e-12, "once a cycle where the ranged path sets it")
			T.near(swings({ meleeHaste = 3 }), swings({}), 1e-12, "the melee-only speed moves nothing there")
			-- unarmed, no Raptor Strike, Strider Kick or Mongoose Bite: the melee part is the white main-hand swings alone
			local function white(over)
				local w = with(over)
				w.unarmed, w.mhDPS, w.ohDPS, w.survival, w.mhSpeed = true, 0, 0, true, 6.0
				return M.Parts(w).melee
			end
			T.near(white({ haste = 2, meleeHaste = 3 }) / white({}), 1.02 * 1.03, 1e-12, "the white swings' damage scales with it")
		end },
		-- rules of the wowsims comparison's model, each on its own: mob dodge by level, Raptor Strike's swing count,
		-- Rapid Killing before Rapid Fire, Expose Prey in a weave
		{ "mob dodge: 5% up to an equal-level mob, +0.5% per level above", function()
			local want = { [-1] = 5, [0] = 5, [1] = 5.5, [2] = 6, [3] = 6.5 }
			for d = -1, 3 do T.near(M.MobAvoid(d), want[d], 1e-12, "mob level +" .. d) end
		end },
		-- Raptor Strike in the Survival weave (raid-mode design 15.3): queued whenever its 6 s cooldown is up, it goes off in
		-- place of the next main-hand swing (sim/hunter/raptor_strike.go:24-71), one swing a cycle, so every nCycles(6) cycles
		-- from the swing it went off on: where the swing timer sets the cycle (C = M, no spread) every ceil(6 / M) swings, a
		-- 6.0 s swing each swing, a 5.9 s swing every 2 (level 20: no Rapid Fire; one weapon); where the ranged path sets it
		-- (the 2.6 s main hand) nCycles(6, C, sigma) at the cycle's spread
		{ "Raptor Strike: every nCycles(6) cycles; where the swing timer sets the cycle a 6.0 s swing each swing, a 5.9 s swing every 2", function()
			local function weave(speed) return M.Weave(svPoint({ level = 20, mhDPS = 15, mhSpeed = speed, ohDPS = 0 })).base end
			for _, case in ipairs({ { 6.0, 1 }, { 5.9, 2 } }) do
				local b = weave(case[1])
				T.near(b.C, case[1], 1e-12, case[1] .. " s: the swing timer sets the cycle")
				T.eq(b.sigma, 0, case[1] .. " s: no spread")
				T.near(b.rates.raptor, 1 / (case[2] * case[1]), 1e-12, case[1] .. " s: every " .. case[2] .. " swings")
				T.near(b.rates.mhWhite, 1 / case[1] - b.rates.raptor, 1e-12, case[1] .. " s: the white swings the rest")
			end
			local b = weave(2.6)
			T.truthy(b.sigma > 0, "the ranged path: a spread")
			T.near(b.rates.raptor, 1 / (M.NCycles(6, b.C, b.sigma) * b.C), 1e-12, "nCycles(6, C, sigma)")
			-- none unarmed (every rank needs a class-2 weapon)
			T.eq(M.Weave(svPoint({ level = 20, mhDPS = 0, ohDPS = 0, unarmed = true })).base.rates.raptor, 0, "none unarmed")
		end },
		{ "Rapid Killing at level 25 (no Rapid Fire yet): the Aimed Shot after each kill", function()
			local function parts(rk)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.level, p.survival = 25, false
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.rapidKilling = rk
				p.tal = tal
				return M.Parts(p)
			end
			local base, rk2 = parts(0), parts(2)
			T.near(rk2.auto, base.auto, 1e-9, "no Rapid Fire before 26: Auto Shot unchanged")
			local r25 = rk2.aimed / base.aimed
			-- one kill per CONST.killInterval: kills half as often, half the bonus share. The shared constant
			-- is restored before anything can raise, so a failure here does not leak into the later tests.
			local keep = M.CONST.killInterval
			M.CONST.killInterval = 2 * keep
			local ok, r50 = pcall(function() return parts(2).aimed / base.aimed end)
			M.CONST.killInterval = keep
			if not ok then error(r50, 0) end
			T.truthy(r25 > 1 + 1e-6, "the kill bonus raises Aimed Shot: " .. r25)
			T.near((r25 - 1) / (r50 - 1), 2, 1e-9, "+10%/rank on one Aimed Shot per kill")
		end },
		-- Mongoose Bite in the Survival weave (raid-mode design 15.3): Expose Prey's windows, 1 / (5 + e^(-5x) / x) a second in
		-- the melee looks the kick leaves, x = 10% (Expose Prey 2/2) of the landed hits of its mask a second (DB2 1310532
		-- ProcTypeMask 0x154: melee swings and abilities, Auto Shot and the ranged abilities, each hit that deals damage; wowsims
		-- proc_types.go:86-102): the white swings of both hands (dual wield at +0 with 1% hit: miss 5% + 19% - 1%, dodge 5%),
		-- Raptor Strike, Strider Kick and Wing Clip (wing_clip.go:15, 18: a main-hand special that deals damage) at 1 - 4% - 5%,
		-- the Auto Shots, Arcane Shot and Multi-Shot (1 - 4%; Multi-Shot ProcMaskRangedSpecial, multi_shot.go:14, U3 = (a)); the
		-- shots open windows too, so a faster bow (a shorter cycle) opens more.
		-- Two points with the bites below the looks the kick leaves: the reference's (Wing Clip every look left, no kick, no off
		-- hand behind the 2.6 s main hand) and a 3.7 s main hand with a 1.3 s off hand and a 2.4 s bow (the swing timer holds the
		-- hunter in melee long enough for the off hand; Strider Kick every third cycle, Wing Clip in the looks left)
		{ "Expose Prey in a weave: the off hand's, Strider Kick's and Wing Clip's hits open Mongoose Bite, the shots too, so ranged speed raises the melee part", function()
			local function check(p, name)
				local b = M.Weave(p).base
				local r = b.rates
				local x = ((r.mhWhite + r.oh) * (1 - 0.28) + (r.raptor + r.strider + r.wingClip) * 0.91 + (r.auto + r.arcane + r.multi) * 0.96) * 0.10
				T.truthy(r.multi > 0, name .. ": Multi-Shot in the range looks")
				T.truthy(r.bite > 0 and r.wingClip > 0, name .. ": bites and Wing Clip in the weave")
				T.truthy(r.bite < 1 / b.C - r.strider - 1e-6, name .. ": the bites below the looks the kick leaves")
				T.near(r.bite, 1 / (5 + math.exp(-5 * x) / x), 1e-9, name .. ": the bites at the cycle's landed hits")
				return r
			end
			check(svPoint({}, { exposePrey = 2 }), "the reference")
			local r = check(svPoint({ bowSpeed = 2.4, mhSpeed = 3.7, ohSpeed = 1.3 }, { exposePrey = 2, striderKick = 1 }), "3.7 s / 1.3 s")
			T.truthy(r.oh > 0 and r.strider > 0, "the off hand and Strider Kick in play")
			local function point(quiver) return svPoint({ quiver = quiver }, { exposePrey = 2 }) end
			T.truthy(M.Parts(point(0.15)).melee > M.Parts(point(0)).melee + 1e-6, "a faster quiver: a shorter cycle, more hits, more bites")
		end },
		-- the shots need a bow, gun or crossbow: Auto Shot 75, Aimed Shot 19434.., Multi-Shot 2643, Arcane Shot 3044..,
		-- Serpent Sting 1978.. and Sniper Shot 1310687.. have SpellEquippedItems rows with EquippedItemClass 2 and
		-- EquippedItemSubclass 262156; Summon Hawk 1293241.. has none
		{ "no bow, gun or crossbow (noShots): no shot is cast; the dive, the pet and the hawks without Quick Shots stay", function()
			local function parts(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return M.Parts(p)
			end
			-- each shot is cast with a bow at one of these levels (Multi-Shot at 19, Aimed Shot and Sniper Shot later)
			local shotAt = { auto = { 19, 43, 60 }, arcane = { 19, 43, 60 }, serpent = { 19, 43, 60 }, multi = { 19 },
				aimed = { 43, 60 }, sniper = { 43, 60 } }
			for _, level in ipairs({ 19, 43, 60 }) do
				local on = parts({ level = level }, { sniperShot = 1 })
				local off = parts({ level = level, noShots = true }, { sniperShot = 1 })
				for k, levels in pairs(shotAt) do
					T.eq(off[k], 0, k .. " without a ranged weapon at " .. level)
					for _, l in ipairs(levels) do
						if l == level then T.truthy(on[k] > 0, k .. " with a bow at " .. level) end
					end
				end
				T.eq(off.dive, on.dive, "the dive (Summon Hawk) at " .. level)
				T.eq(off.pet, on.pet, "the pet at " .. level)
				T.eq(off.melee, on.melee, "the melee part without Expose Prey at " .. level)
			end
			-- Quick Shots come from Auto Shots (Deadly Aspects): without shots the hawks swing as with Deadly Aspects 0
			T.near(parts({ noShots = true }).hawks, parts({}, { deadlyAspects = 0 }).hawks, 1e-12, "no Quick Shots")
			T.truthy(parts({}).hawks > parts({ noShots = true }).hawks + 1e-6, "Quick Shots speed up the hawks with a bow")
			-- the Survival branch without a bow, gun or crossbow: no Auto Shot comes, so the weave never walks back in (raid-mode
			-- design 15.3): no melee and no shot
			local svOff = parts({ survival = true, noShots = true }, { exposePrey = 2 })
			for _, k in ipairs({ "melee", "trap", "auto", "arcane", "serpent" }) do T.eq(svOff[k], 0, "Survival without a bow: " .. k) end
			T.truthy(parts({ survival = true }, { exposePrey = 2 }).melee > 0, "with a bow it weaves")
		end },
		-- Ranged Weapon Specialization: talent node 104998 -> TraitNodeEntry 129662 -> TraitDefinition 134463 -> spell
		-- 19507, SpellEquippedItems row 179969 (EquippedItemClass 2, EquippedItemSubclass 262156: bows, guns, crossbows)
		{ "noShots: the dive takes no Ranged Weapon Specialization; with a bow it grows 1% a rank", function()
			local function dive(noShots, rws)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.rangedWeaponSpec = rws
				p.tal, p.noShots = tal, noShots
				return M.Parts(p).dive
			end
			T.truthy(dive(false, 0) > 0 and dive(true, 0) > 0, "the dive at 43 with Summon Hawk, bow or not")
			T.near(dive(true, 5), dive(true, 0), 1e-12, "no bow, gun or crossbow: the talent is off")
			T.near(dive(false, 5) / dive(false, 0), 1.05, 1e-12, "a bow: +5% at 5/5")
			T.near(dive(false, 3) / dive(false, 0), 1.03, 1e-12, "a bow: +3% at 3/5")
		end },
		-- the ranged weapon skill's hit is the ranged weapon's (Forever UI Camelot/SkillsFrame.lua): p.rangedHit
		{ "ranged-only hit: p.rangedHit reaches the six shots alone; W.HIT_RANGED is their derivative under the cap, below W.HIT", function()
			local function with(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			local SHOTS = { auto = true, aimed = true, multi = true, arcane = true, serpent = true, sniper = true }
			-- Multi-Shot at 19, Aimed Shot and Sniper Shot at 43: each shot takes p.rangedHit, nothing else does
			for _, level in ipairs({ 19, 43 }) do
				local a = M.Parts(with({ level = level }, { sniperShot = 1 }))
				local b = M.Parts(with({ level = level, rangedHit = 1 }, { sniperShot = 1 }))
				for k, v in pairs(a) do
					if SHOTS[k] and v > 0 then
						T.near(b[k] / v, (1 - (5 - 2) / 100) / (1 - (5 - 1) / 100), 1e-12, k .. ": 1% more hit at " .. level)
					else
						T.eq(b[k], v, k .. " leaves p.rangedHit out at " .. level)
					end
				end
				T.truthy(a.multi > 0 or level ~= 19, "Multi-Shot at 19"); T.truthy(a.sniper > 0 or level ~= 43, "Sniper Shot at 43")
			end
			local p = with()
			local W, dRap = M.Weights(p)
			local function shots(q)
				local o = M.Parts(q)
				return o.auto + o.aimed + o.multi + o.arcane + o.serpent + o.sniper
			end
			-- the shots' derivative at every attack's 0% hit
			local d = (shots(with({ hit = 0.5 })) - shots(with({ hit = 0 }))) / 0.5 / dRap
			T.near(W.HIT_RANGED, d, 1e-9, "the shots-only derivative")
			T.truthy(W.HIT_RANGED > 0 and W.HIT_RANGED < W.HIT - 1e-6, string.format("below W.HIT: %.4f vs %.4f", W.HIT_RANGED, W.HIT))
			-- taken at 0% hit whatever the shots' own hit (dRap is taken at p, so compare per DPS)
			local p6 = with({ rangedHit = 6 })
			local W6, dRap6 = M.Weights(p6)
			T.near(W6.HIT_RANGED * dRap6, W.HIT_RANGED * dRap, 1e-9, "the shots past the cap at p: still under it at 0% hit")
			T.near(W6.HIT * dRap6, W.HIT * dRap, 1e-9, "W.HIT at 0% hit of every attack")
			-- no shots: no ranged-only hit to price
			T.eq(M.Weights(with({ noShots = true })).HIT_RANGED, 0, "noShots")
		end },
		{ "ranged-only hit: Expose Prey's shot hits in a weave land with it; dual-wield hit past the cap leaves it out", function()
			local function with(over, tover)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				for k, v in pairs(tover or {}) do tal[k] = v end
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			local function melee(rangedHit)
				return M.Parts(with({ survival = true, rangedHit = rangedHit }, { exposePrey = 2 })).melee
			end
			T.truthy(melee(2) > melee(0) + 1e-9, "the weave: more shots land, more bites open")
			-- W.HIT_DW is taken just past the cap with the shots past it too: the same per DPS at any p.rangedHit
			local W0, d0 = M.Weights(with({ survival = true }))
			local W8, d8 = M.Weights(with({ survival = true, rangedHit = -0.8 }))
			T.truthy(W0.HIT_DW > 0, "the weave: dual-wield hit has a value")
			T.near(W8.HIT_DW * d8, W0.HIT_DW * d0, 1e-9, "the shots' -0.8% leaves W.HIT_DW alone")
			-- at W.HIT_DW's own point (Model.Weights: two one-handers, the reference's 26 DPS at 2.6 s in each hand, every
			-- attack 0.5% past the cap, the shots' own hit 0) the six shots sit past the cap: 0.5% more hit leaves their
			-- sum where it is, and W.HIT_DW is the derivative of the melee part alone
			local qd = with({ survival = true, hit = M.HitCap(0) + 0.5, rangedHit = 0, twoH = false, unarmed = false, mhDPS = 26, mhSpeed = 2.6, ohDPS = 26 })
			local qd2 = with({ survival = true, hit = M.HitCap(0) + 1, rangedHit = 0, twoH = false, unarmed = false, mhDPS = 26, mhSpeed = 2.6, ohDPS = 26 })
			local function shots(o) return o.auto + o.aimed + o.multi + o.arcane + o.serpent + o.sniper + o.trap end
			local a, b = M.Parts(qd), M.Parts(qd2)
			T.truthy(shots(a) > 0, "the shots at the reference")
			T.eq(shots(b), shots(a), "the shots past the cap at W.HIT_DW's point")
			T.near(W0.HIT_DW, (b.melee - a.melee) / 0.5 / d0, 1e-9, "W.HIT_DW: the melee part alone")
		end },
		-- the six shots' hit (p.hit + p.rangedHit) meets the same cap as every attack's (Model.Parts missChance floors at 0)
		{ "ranged-only hit meets the cap: from 4.5% hit +1% of it gains each shot 0.5%; at 5% hit it adds nothing", function()
			local function with(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.sniperShot = 1
				p.tal = tal
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			local SHOTS = { auto = true, aimed = true, multi = true, arcane = true, serpent = true, sniper = true }
			-- Multi-Shot at 19, Aimed Shot and Sniper Shot at 43
			for _, level in ipairs({ 19, 43 }) do
				local a = M.Parts(with({ level = level, hit = 4.5 }))
				local b = M.Parts(with({ level = level, hit = 4.5, rangedHit = 1 }))
				local c = M.Parts(with({ level = level, hit = 5 }))
				local d = M.Parts(with({ level = level, hit = 5, rangedHit = 0.2 }))
				local seen = 0
				for k, v in pairs(a) do
					if SHOTS[k] and v > 0 then
						seen = seen + 1
						T.near(b[k] / v, 1 / (1 - 0.005), 1e-12, k .. ": 0.5% to the cap at " .. level)
					else
						T.eq(b[k], v, k .. " leaves p.rangedHit out at " .. level)
					end
				end
				T.eq(seen, level == 19 and 4 or 5, "the shots cast at " .. level)
				for k, v in pairs(c) do T.eq(d[k], v, k .. ": at the cap 0.2% more of the shots' hit adds nothing at " .. level) end
			end
		end },
		-- The ranged skill's crit weight (raid-mode W1 design 3.3, Model.Weights): Total at rangedSkill b0 = min(worn, 0)
		-- less Total at b0 - 1, one-sided because every crit part of the skill starts at the maximum (the suppression's
		-- max(0, -bonus), the pet's min(bonus, 0) x 0.04). A fixture with the ranged crit 1% over the melee crit, more than
		-- the pet's penalty at the points taken (0.04% x 13 = 0.52%), so the pet's ranged branch holds. Mutant: the
		-- two-sided difference at 0 (half the value there)
		{ "W.SKILL_CRIT: one point below min(worn, 0), one-sided at 0", function()
			local function with(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.meleeCrit = p.crit - 1
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			for _, case in ipairs({ { 0, 0 }, { 6, 0 }, { -12, -12 } }) do
				local worn, b0 = case[1], case[2]
				local W, dRap = M.Weights(with({ rangedSkill = worn }))
				local at, below = with({ rangedSkill = b0 }), with({ rangedSkill = b0 - 1 })
				T.near(W.SKILL_CRIT, (M.Total(at) - M.Total(below)) / dRap, 1e-9, "worn " .. worn)
				-- the shots, Serpent Sting's ticks, the dive, the pet and the hawks all take it
				local a, b = M.Parts(at), M.Parts(below)
				for _, k in ipairs({ "auto", "aimed", "arcane", "serpent", "dive", "pet", "hawks" }) do
					T.truthy(b[k] < a[k] - 1e-9, k .. " loses a point below, worn " .. worn)
				end
			end
			local W0 = M.Weights(with({ rangedSkill = 0 }))
			local W6 = M.Weights(with({ rangedSkill = 6 }))
			T.near(W6.SKILL_CRIT, W0.SKILL_CRIT, 1e-9, "above the maximum: the slope at the maximum")
			T.truthy(W0.SKILL_CRIT > 0, "W.SKILL_CRIT " .. W0.SKILL_CRIT)
		end },
		-- The pet's crit, both branches (wowsims sim/hunter/pets.go:142-153 inheritedCrit; raid-mode W1 design section 4):
		-- max(0, melee, ranged), the melee branch p.meleeCrit with the main hand's skill, the ranged branch p.crit with the
		-- ranged skill, each 0.04% a point below the maximum; the hawks half of it (summon_hawk.go:83), Ferocity whole on
		-- both (talents_beast_mastery.go:71-84). Compared on the pet's and the hawks' parts alone, at +0 and +3. Mutants: the
		-- ranged branch only; Ferocity halved on the hawks
		{ "pet crit: the higher of melee and ranged sheet crit; hawks half; Ferocity whole on both", function()
			for _, d in ipairs({ 0, 3 }) do
				local function parts(crit, meleeCrit, tover)
					local p = critPoint(d, 4, {}, tover)
					p.crit, p.meleeCrit = crit, meleeCrit
					return M.Parts(p)
				end
				local a, b, c = parts(12, 8), parts(8, 12), parts(12, 12)
				for _, k in ipairs({ "pet", "hawks" }) do
					T.near(a[k], c[k], 1e-9, k .. ": the ranged 12% leads, +" .. d)
					T.near(b[k], c[k], 1e-9, k .. ": the melee 12% leads, +" .. d)
				end
				-- Ferocity 5/5 (10%): the pet's crit + 10, a hawk's half of the base + 10, so a hawk at Ferocity 5/5 is a hawk
				-- at Ferocity 0 with the base 20% higher, the pet one with it 10% higher
				local f5, h0, p0 = parts(12, 12, { ferocity = 5 }), parts(32, 32, { ferocity = 0 }), parts(22, 22, { ferocity = 0 })
				T.near(f5.hawks, h0.hawks, 1e-9, "the hawks: Ferocity whole, +" .. d)
				T.near(f5.pet, p0.pet, 1e-9, "the pet: Ferocity whole, +" .. d)
			end
		end },
		-- At equal sheet crits the melee branch keeps the pet's crit whole at any bow deficit (the main hand at its maximum);
		-- with a ranged-only lead the deficit reaches it up to the lead: crit = meleeCrit + 0.1 at a 5-point deficit, the
		-- ranged branch 0.1 - 0.2 below the melee one, so the pet loses its 0.1% lead; at a 1-point deficit 0.04% of it (my
		-- arithmetic). Mutants: no max (the ranged branch only); the bow's penalty on both branches
		{ "pet crit: at equal sheet crits a bow deficit does not reach the pet or the hawks; with a ranged-only lead it does, up to the lead", function()
			local function parts(crit, meleeCrit, rangedSkill)
				local p = critPoint(0, 4, { rangedSkill = rangedSkill })
				p.crit, p.meleeCrit = crit, meleeCrit
				return M.Parts(p)
			end
			for _, k in ipairs({ "pet", "hawks" }) do
				T.near(parts(10, 10, -5)[k], parts(10, 10, 0)[k], 1e-9, k .. ": equal crits, 5 below")
				T.near(parts(10.1, 10, -5)[k], parts(10, 10, 0)[k], 1e-9, k .. ": a 0.1% lead, 5 below: the lead lost")
				T.near(parts(10.1, 10, -1)[k], parts(10.06, 10, 0)[k], 1e-9, k .. ": a 0.1% lead, 1 below: 0.04% of it")
				T.truthy(parts(10.1, 10, 0)[k] > parts(10, 10, 0)[k] + 1e-9, k .. ": the lead counts at the maximum")
			end
		end },
		-- The melee branch takes the main hand's skill below its maximum (0.04% a point): at equal sheet crits a main hand and a
		-- bow 10 below lower the pet by 0.4%; the main hand alone leaves the ranged branch whole; a melee lead of 1% loses 0.4%
		-- of it; a main hand 10 above its maximum adds nothing to a melee lead (wowsims pets.go:147-153: min(bonus, 0) x 0.04;
		-- raid-mode W1 design section 4: skill above the maximum gives the pet nothing). Both branches below 0 (a sheet crit of
		-- 0.2% with both hands 10 below: 0.2% - 0.4%) floor the base at 0, so the pet and the hawks keep Ferocity's 10% whole
		-- (my arithmetic). Mutants: the melee branch without its skill term; the melee branch with skill above the maximum
		-- (0.04 x bonus); no floor at 0
		{ "pet crit: a main hand below its maximum lowers the melee branch, above it adds nothing; the base floors at 0", function()
			local function parts(crit, meleeCrit, mhSkill, rangedSkill)
				local p = critPoint(0, 4, { mhSkill = mhSkill, rangedSkill = rangedSkill })
				p.crit, p.meleeCrit = crit, meleeCrit
				return M.Parts(p)
			end
			for _, k in ipairs({ "pet", "hawks" }) do
				T.near(parts(10, 10, -10, -10)[k], parts(9.6, 9.6, 0, 0)[k], 1e-9, k .. ": both 10 below")
				T.near(parts(10, 10, -10, 0)[k], parts(10, 10, 0, 0)[k], 1e-9, k .. ": the main hand alone: the ranged branch")
				T.near(parts(10, 11, -10, 0)[k], parts(10, 10.6, 0, 0)[k], 1e-9, k .. ": a 1% melee lead less 0.4%")
				T.near(parts(10, 11, 10, 0)[k], parts(10, 11, 0, 0)[k], 1e-9, k .. ": a main hand above its maximum: nothing")
				T.near(parts(0.2, 0.2, -10, -10)[k], parts(0, 0, 0, 0)[k], 1e-9, k .. ": both branches below 0: the base 0")
			end
		end },
		-- W.SKILL_CRIT at equal sheet crits (the main hand at its maximum): one bow point below leaves the pet and the hawks on
		-- the melee branch, so it holds the ranged hand's suppression alone (the shots, Serpent Sting's ticks, the dive).
		-- Mutant: no max (the ranged branch only)
		{ "W.SKILL_CRIT at equal sheet crits holds the shots' suppression alone", function()
			local p = {}
			for k, v in pairs(ref) do p[k] = v end
			local W, dRap = M.Weights(p)
			local below = {}
			for k, v in pairs(p) do below[k] = v end
			below.rangedSkill = -1
			local a, b = M.Parts(p), M.Parts(below)
			T.near(b.pet, a.pet, 1e-12, "the pet on the melee branch"); T.near(b.hawks, a.hawks, 1e-12, "the hawks too")
			local shots = 0
			for _, k in ipairs({ "auto", "aimed", "multi", "arcane", "serpent", "sniper", "dive" }) do shots = shots + a[k] - b[k] end
			T.truthy(shots > 0, "the ranged hand's suppression")
			T.near(W.SKILL_CRIT, shots / dRap, 1e-9, "W.SKILL_CRIT: the shots, Serpent Sting and the dive alone")
		end },
		-- W.HIT_DW is taken at qd: two one-handers, hit 0.5% past the cap, the shots past it too (rangedHit 0) and the main
		-- hand's skill hit at 0 (meleeHit 0), whatever the worn main hand's: a fixture with meleeHit -2 would leave the
		-- specials 1.5% short of the cap there. W.HIT_DW is its derivative by p.hit (both hands' white swings), W.HIT_DW_MH by
		-- p.meleeHit (the main hand's white swings alone): below W.HIT_DW where the off hand swings (a 5.0 s main hand and a
		-- 1.8 s off hand at level 20). W.HIT_MELEE is taken at q0 (every hit at 0), so a fixture past the cap keeps its slope.
		-- Mutants: qd.meleeHit = p.meleeHit; W.HIT_DW_MH = W.HIT_DW; W.HIT_MELEE at p
		{ "W.HIT_DW at qd with meleeHit 0; W.HIT_DW_MH the main hand's white part of it", function()
			local p = svPoint({ level = 20, mhSpeed = 5.0, ohSpeed = 1.8, meleeHit = -2 })
			local W, dRap = M.Weights(p)
			local qd = svPoint({ level = 20, mhSpeed = 5.0, ohSpeed = 1.8, meleeHit = 0, hit = M.HitCap(0) + 0.5 })
			local function at(over)
				local q = {}
				for k, v in pairs(qd) do q[k] = v end
				for k, v in pairs(over) do q[k] = v end
				return M.Total(q)
			end
			local t0 = at({})
			T.near(W.HIT_DW, (at({ hit = qd.hit + 0.5 }) - t0) / 0.5 / dRap, 1e-9, "by p.hit at meleeHit 0")
			T.near(W.HIT_DW_MH, (at({ meleeHit = 0.5 }) - t0) / 0.5 / dRap, 1e-9, "by p.meleeHit")
			T.truthy(W.HIT_DW_MH > 0 and W.HIT_DW_MH < W.HIT_DW - 1e-6, string.format("the main hand's part: %.4f of %.4f", W.HIT_DW_MH, W.HIT_DW))
			T.truthy(weaveRates(qd).oh > 0, "the off hand swings")
			-- W.HIT_MELEE: the main hand's skill hit under the cap, at q0 (every hit at 0)
			local q0 = svPoint({ level = 20, mhSpeed = 5.0, ohSpeed = 1.8, meleeHit = 0, hit = 0 })
			local function at0(over)
				local q = {}
				for k, v in pairs(q0) do q[k] = v end
				for k, v in pairs(over) do q[k] = v end
				return M.Total(q)
			end
			T.near(W.HIT_MELEE, (at0({ meleeHit = 0.5 }) - at0({})) / 0.5 / dRap, 1e-9, "W.HIT_MELEE at q0")
			T.truthy(W.HIT_MELEE > 0 and W.HIT_MELEE < W.HIT, "under W.HIT")
			-- a fixture past the cap (6% hit, one main hand): its own specials miss 0 there, W.HIT_MELEE stays q0's
			local over = svPoint({ level = 20, mhSpeed = 5.0, ohDPS = 0, hit = 6 })
			local Wo, dRapO = M.Weights(over)
			local qo = svPoint({ level = 20, mhSpeed = 5.0, ohDPS = 0, hit = 0 })
			local function atO(over2)
				local q = {}
				for k, v in pairs(qo) do q[k] = v end
				for k, v in pairs(over2) do q[k] = v end
				return M.Total(q)
			end
			T.truthy(Wo.HIT_MELEE > 0, "past the cap: q0's slope")
			T.near(Wo.HIT_MELEE, (atO({ meleeHit = 0.5 }) - atO({})) / 0.5 / dRapO, 1e-9, "W.HIT_MELEE at q0 past the cap")
			-- outside the Survival branch all three are 0
			local Wb = M.Weights(svPoint({ survival = false }))
			T.eq(Wb.HIT_DW, 0); T.eq(Wb.HIT_DW_MH, 0); T.eq(Wb.HIT_MELEE, 0)
		end },
		-- the same where no shot is cast: Score prices the skill change of a set without shots at it
		{ "W.SKILL_CRIT_NO_SHOTS: one point below min(worn, 0) without shots and without ranged weapon DPS; the pet, the dive and the hawks", function()
			local function with(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				p.meleeCrit = p.crit - 1
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			local SHOTS = { "auto", "aimed", "multi", "arcane", "serpent", "sniper" }
			for _, case in ipairs({ { 0, 0 }, { -12, -12 } }) do
				local worn, b0 = case[1], case[2]
				local W, dRap = M.Weights(with({ rangedSkill = worn }))
				local n0 = with({ rangedSkill = b0, noShots = true, bowDPS = 0 })
				local n1 = with({ rangedSkill = b0 - 1, noShots = true, bowDPS = 0 })
				T.near(W.SKILL_CRIT_NO_SHOTS, (M.Total(n0) - M.Total(n1)) / dRap, 1e-9, "worn " .. worn)
				local a, b = M.Parts(n0), M.Parts(n1)
				for _, k in ipairs({ "pet", "dive", "hawks" }) do T.truthy(b[k] < a[k] - 1e-9, k .. " takes it") end
				for _, k in ipairs(SHOTS) do T.eq(a[k], 0, k .. ": no shot") end
				T.eq(b.melee, a.melee, "the melee part does not take it")
				T.truthy(W.SKILL_CRIT_NO_SHOTS > 0 and W.SKILL_CRIT_NO_SHOTS < W.SKILL_CRIT - 1e-6,
					string.format("below W.SKILL_CRIT, which the shots take too: %.4f vs %.4f", W.SKILL_CRIT_NO_SHOTS, W.SKILL_CRIT))
			end
			-- the hawks' AP without a ranged weapon's DPS (bowDPS 0) whatever the worn bow's: the same per DPS
			local Wa, da = M.Weights(with())
			local Wb, db = M.Weights(with({ bowDPS = 40 }))
			T.near(Wb.SKILL_CRIT_NO_SHOTS * db, Wa.SKILL_CRIT_NO_SHOTS * da, 1e-9, "the worn bow's DPS leaves it alone")
			-- at a point without shots and without ranged weapon DPS it is W.SKILL_CRIT
			local Wn = M.Weights(with({ noShots = true, bowDPS = 0 }))
			T.near(Wn.SKILL_CRIT_NO_SHOTS, Wn.SKILL_CRIT, 1e-9, "no shots worn: the same as W.SKILL_CRIT")
		end },
		-- the crit of the ranged attacks: p.crit alone, which the pet, the dive and the hawks take from the owner (EV-0070)
		{ "ranged crit: W.CRIT_RANGED is the derivative of p.crit alone, melee crit held; the pet, the dive and the hawks take it", function()
			local function with(over)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				for k, v in pairs(over or {}) do p[k] = v end
				return p
			end
			-- in the Survival weave (its melee crit held), and from range, where the pet, the dive and the hawks take it
			for _, survival in ipairs({ true, false }) do
				for _, meleeCrit in ipairs({ 8, false }) do
					-- meleeCrit nil follows p.crit in the model: W.CRIT_RANGED still holds it where it is
					local p = with({ survival = survival, meleeCrit = meleeCrit or nil })
					local W, dRap, t0 = M.Weights(p)
					local q = with({ survival = survival, meleeCrit = meleeCrit or p.crit, crit = p.crit + 0.5 })
					T.near(W.CRIT_RANGED, (M.Total(q) - t0) / 0.5 / dRap, 1e-9, "p.crit alone, meleeCrit " .. tostring(meleeCrit))
					local a, b = M.Parts(p), M.Parts(q)
					if survival then
						T.truthy(W.CRIT_RANGED < W.CRIT - 1e-6, "melee crit left out: " .. W.CRIT_RANGED .. " vs " .. W.CRIT)
						T.truthy(a.melee > 0, "the weave's melee")
						T.eq(b.melee, a.melee, "the melee part does not")
					else
						-- more than the shots: the pet, the dive and the hawks
						for _, k in ipairs({ "pet", "dive", "hawks" }) do T.truthy(b[k] > a[k] + 1e-9, k .. " takes the ranged crit") end
						T.near(W.CRIT_RANGED, W.CRIT, 1e-9, "no melee: the same as W.CRIT")
					end
				end
			end
		end },
		-- Model.Weights' unit: 1 RAP where more RAP adds damage; 1 melee attack power where it adds none (no shot counted,
		-- no hawks, a pet that reads the melee AP; the Survival weave's melee needs a bow, whose shots read RAP); 1 DPS where
		-- neither adds any (Model.Total 0: no shot, no hawks, no pet)
		{ "weights' unit: 1 RAP where RAP adds damage, 1 melee AP where it adds none, 1 DPS where neither does", function()
			local function with(over, tal)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				for k, v in pairs(over or {}) do p[k] = v end
				if tal then
					p.tal = {}
					for k, v in pairs(M.DEFAULT_TALENTS) do p.tal[k] = v end
					for k, v in pairs(tal) do p.tal[k] = v end
				end
				return p
			end
			local function step(p, key)
				local q = with(p)
				q[key] = q[key] + 10
				return (M.Total(q) - M.Total(p)) / 10
			end
			local function finite(W, what)
				for k, v in pairs(W) do T.truthy(v == v and v > -math.huge and v < math.huge, what .. ", " .. k .. ": " .. tostring(v)) end
			end
			local function unitOf(p) local _, _, _, unit = M.Weights(p); return unit end
			local W, unitDps, _, unit = M.Weights(ref)
			T.eq(unit, "RAP"); T.near(unitDps, step(ref, "rap"), 1e-12, "the derivative by RAP")
			T.eq(W.RAP, 1); T.near(W.EXTRA_DPS, 1 / unitDps, 1e-12)
			-- a pet's AP is max(RAP, melee AP): melee AP 10 over RAP or more (the step) leaves RAP out; level 15, no shots
			local function pet(map) return with({ level = 15, noShots = true, bowDPS = 0, rap = 200, map = map }) end
			local low = pet(210)
			W, unitDps, _, unit = M.Weights(low)
			T.eq(unit, "MAP", "melee AP 10 over RAP"); T.near(unitDps, step(low, "map"), 1e-12, "the derivative by melee AP")
			T.eq(W.RAP, 0); T.near(W.STR, 1, 1e-12); T.near(W.AP, 1, 1e-12); T.near(W.EXTRA_DPS, 1 / unitDps, 1e-12)
			finite(W, "a pet on the melee AP")
			T.eq(unitOf(pet(205)), "RAP", "melee AP 5 over RAP: part of the step")
			T.eq(unitOf(pet(150)), "RAP", "RAP over melee AP")
			-- the Survival branch with a bow: the weave's Auto Shots read RAP, at level 3 too
			T.eq(unitOf(with({ level = 3, survival = true })), "RAP", "level 3, a bow, the weave")
			-- nothing attacks: no shot (no bow), no pet (level 8; Lone Wolf with no pet out at 40), no hawks, no melee (the
			-- Survival weave needs a bow)
			for _, case in ipairs({ { "level 8", with({ level = 8, noShots = true, bowDPS = 0 }) },
				{ "level 8, the Survival branch", with({ level = 8, noShots = true, bowDPS = 0, survival = true }) },
				{ "Lone Wolf, no hawks, no pet, no shots", with({ level = 40, noShots = true, bowDPS = 0, petOut = false }, { loneWolf = 1, summonHawk = 0 }) } }) do
				local t0
				W, unitDps, t0, unit = M.Weights(case[2])
				T.eq(t0, 0, case[1]); T.eq(unit, "DPS", case[1]); T.eq(unitDps, 1, case[1])
				for k, v in pairs(W) do T.eq(v, k == "EXTRA_DPS" and 1 or 0, case[1] .. ": " .. k) end
			end
			-- a derivative below 0 or not a number is an error
			local ok, err = pcall(M.Weights, with({ rap = 0 / 0 }))
			T.eq(ok, false); T.truthy(tostring(err):find("RAP", 1, true), tostring(err))
			-- the shots at a hit of -200 with no melee: Model.Total is below 0 and falls further with more RAP, so the
			-- derivative by RAP is below 0, and the melee AP, which adds nothing without melee, gives no unit
			local negRap = with({ hit = -200 })
			T.truthy(step(negRap, "rap") < 0, "the derivative by RAP: " .. step(negRap, "rap"))
			T.eq(step(negRap, "map"), 0, "the derivative by melee AP")
			ok, err = pcall(M.Weights, negRap)
			T.eq(ok, false); T.truthy(tostring(err):find("one more RAP changes the model's DPS by -", 1, true), tostring(err))
			-- a pet on the melee AP at a hit of -200: its white swings below 0, falling further with more melee AP
			local negMap = pet(300); negMap.hit = -200
			ok, err = pcall(M.Weights, negMap)
			T.eq(ok, false); T.truthy(tostring(err):find("one more melee attack power changes the model's DPS by -", 1, true), tostring(err))
		end },
		-- The Survival weave (raid-mode design section 15; Core/Model.lua weaveParts), its rules each on their own. The point of
		-- design 15.8: level 60, a 3.8 s two-hander, a 3.0 s bow, quiver 15%, no other speed (no Quick Shots), Strider Kick, no
		-- Expose Prey, Survivalist's Discipline or Improved Arcane Shot, +3 with no hit (the shots miss 8%). The cycle outside
		-- Rapid Fire (Model.Weave base) by the design's formulas at its converged kick share (my arithmetic): the shots at the
		-- quiver's 1.15, the walks at 7 yd/s (9.1 yd/s for 3 s after a kick) from the 13.19 yd spot to 4.99 yd and back in to
		-- 5 yd, the shot due after the walk out (no wait), the reaction's mean 0.25 s after the shot where the main hand's swing
		-- comes within 0.15 s of the walk in
		{ "weave cycle: the ranged path sets it: C = E[S] + W_in + 0.25 when M <= K + 0.15 (15.8's numbers)", function()
			local b = M.Weave(p158()).base
			local R, wu = 3.0 / 1.15, 0.5 / 1.15
			local k = b.k
			local Wout = (1 - k) * (13.19 - 4.99) / 7 + k * (13.19 - 4.99) / 9.1
			local u = R - wu - Wout
			T.truthy(u >= 0.35, "the shot is due after the walk: no wait")
			local t = 3 - R
			local Win = (1 - k) * 8.19 / 7 + k * (t + (8.19 - 9.1 * t) / 7)
			local K = R + Win
			T.truthy(3.8 <= K + 0.15, "M within 0.15 s of K")
			T.near(b.M, 3.8, 1e-12); T.near(b.R, R, 1e-12); T.near(b.wu, wu, 1e-12); T.near(b.Wout, Wout, 1e-12); T.near(b.u, u, 1e-12)
			T.near(b.ES, R, 1e-12); T.near(b.Win, Win, 1e-12); T.near(b.K, K, 1e-12)
			T.near(b.C, K + 0.25, 1e-12, "C = K + the mean reaction")
			T.near(b.sigma, math.sqrt(0.2 ^ 2 / 12), 1e-12, "the walk sets the swing, no held shot")
			T.near(k, 1 / M.NCycles(7.6, b.C, b.sigma), 1e-8, "the kick share at the cycle")
			-- 15.8's figures, to their 4 decimals
			for _, c in ipairs({ { k, 0.5, "k" }, { b.Wout, 1.0363, "W_out" }, { b.u, 1.1376, "u" }, { b.ES, 2.6087, "E[S]" },
				{ b.Win, 1.1113, "W_in" }, { b.K, 3.72, "K" }, { b.C, 3.97, "C" }, { b.sigma, 0.0577, "sigma" } }) do
				T.near(c[1], c[2], 5e-5, "15.8's " .. c[3])
			end
		end },
		-- the held shot (design 15.2 step 2): a shot whose windup comes due while the hunter walks out waits a reaction after
		-- the walk, so E[S] = R + h(u), u = R - wu - W_out; and the reaction's means e(c) = E[max(c, rho)] and P(rho3 - rho1 >= x)
		{ "weave cycle: the held shot's mean h(u) at u = 0.10, 0.25, 0.40", function()
			local h = M.WeaveMeans.heldShot
			T.near(h(0.10, 0.15, 0.35), 0.40, 1e-12, "u = 0.10: both reactions, less u")
			T.near(h(0.25, 0.15, 0.35), 0.15, 1e-12, "u = 0.25")
			T.eq(h(0.40, 0.15, 0.35), 0, "u = 0.40: due after the walk")
			-- through the cycle (no kick): a bow fast enough that its windup comes due during the walk out
			for _, bowSpeed in ipairs({ 1.6, 2.1346, 2.3 }) do
				local b = M.Weave(p158({ bowSpeed = bowSpeed }, {})).base
				local R, wu = bowSpeed / 1.15, 0.5 / 1.15
				local u = R - wu - 8.2 / 7
				T.near(b.u, u, 1e-12, bowSpeed .. " s: u")
				local want = u >= 0.35 and 0 or u <= 0.15 and 0.5 - u or ((0.35 - u) * (0.25 - u) + (0.35 ^ 2 - u ^ 2) / 2) / 0.2
				T.near(b.ES - R, want, 1e-12, bowSpeed .. " s bow: E[S] = R + h(u)")
			end
			local e, past = M.WeaveMeans.emax, M.WeaveMeans.pastBy
			T.near(e(0.1, 0.15, 0.35), 0.25, 1e-12); T.near(e(0.25, 0.15, 0.35), 0.275, 1e-12); T.near(e(0.5, 0.15, 0.35), 0.5, 1e-12)
			T.eq(past(-0.3, 0.15, 0.35), 1); T.near(past(-0.1, 0.15, 0.35), 1 - 0.1 ^ 2 / 0.08, 1e-12)
			T.near(past(0.1, 0.15, 0.35), 0.1 ^ 2 / 0.08, 1e-12); T.eq(past(0.25, 0.15, 0.35), 0)
		end },
		-- the swing timer sets the cycle where the main hand's swing comes a reaction or more after the walk in: C = M, no
		-- spread (design 15.2 steps 4 and 6); between, C = K + E[max(M - K, rho)]
		{ "weave cycle: the swing timer sets it: C = M when M >= K + 0.35, sigma = 0", function()
			local b = M.Weave(p158({ mhSpeed = 5.0 })).base
			T.truthy(5.0 >= b.K + 0.35, "the timer binds: K " .. b.K)
			T.near(b.C, 5.0, 1e-12); T.eq(b.sigma, 0)
			local m = M.Weave(p158({ mhSpeed = 3.95 })).base
			local c = 3.95 - m.K
			T.truthy(c > 0.15 and c < 0.35, "between: " .. c)
			T.near(m.C, m.K + M.WeaveMeans.emax(c, 0.15, 0.35), 1e-12)
			T.near(m.sigma, math.sqrt(0.2 ^ 2 / 12 * (m.K + 0.35 - 3.95) / 0.2), 1e-12, "the walk sets the swing in part of the cycles")
		end },
		-- the cycle's spread for nCycles (design 15.2 step 6, my arithmetic there, WA2): sigma^2 = 0.2^2 / 12 x P_arr x (1 + 2
		-- P_held), P_arr = clamp((K + 0.35 - M) / 0.2) the share of cycles whose walk sets the swing, P_held = clamp((0.35 - u) /
		-- 0.2) the share whose Auto Shot waits a reaction after the walk out. 15.8's point without the kick and with a 2.1346 s
		-- bow: u = 2.1346 / 1.15 - 0.5 / 1.15 - 8.2 / 7 = 0.25, P_held 0.5; a 3.0 s two-hander leaves every swing to the walk
		-- (P_arr 1), a 3.45 s one part of them
		{ "weave cycle: the spread with a held shot: sigma^2 = 0.2^2 / 12 x P_arr x (1 + 2 P_held)", function()
			for _, mh in ipairs({ 3.0, 3.45 }) do
				local b = M.Weave(p158({ bowSpeed = 2.1346, mhSpeed = mh }, {})).base
				local pHeld = (0.35 - b.u) / 0.2
				local pArr = math.max(0, math.min(1, (b.K + 0.35 - mh) / 0.2))
				T.near(b.u, 0.25, 1e-4, mh .. " s: u")
				T.near(b.sigma, math.sqrt(0.2 ^ 2 / 12 * pArr * (1 + 2 * pHeld)), 1e-12, mh .. " s: sigma")
				if mh == 3.0 then
					T.eq(pArr, 1, "3.0 s: the walk sets every swing")
				else
					T.truthy(pArr > 0.2 and pArr < 0.8, "3.45 s: the walk sets part of the swings: " .. pArr)
				end
			end
		end },
		-- nCycles(d, C, sigma) (design 15.3): 1 + the sum of Phi((d - nC) / (sigma sqrt n)); at sigma 0, ceil(d / C)
		{ "nCycles: ceil at sigma = 0; at sigma > 0 the normal smoothing just above and below an integer d/C", function()
			T.eq(M.NCycles(6, 3.0, 0), 2); T.eq(M.NCycles(6, 2.9, 0), 3); T.eq(M.NCycles(6, 6.0, 0), 1); T.eq(M.NCycles(30, 3.97, 0), 8)
			local Phi = M.NormalCdf
			T.near(Phi(0), 0.5, 1e-15); T.near(Phi(1), 0.8413447460685429, 1e-14); T.near(Phi(-2.5), 0.006209665325776132, 1e-15)
			T.near(Phi(-6), 9.865876450376981e-10, 1e-20); T.near(Phi(3.6), 0.9998408914098424, 1e-14)
			local s = 0.1
			T.near(M.NCycles(6, 2.9, s), 1 + Phi(3.1 / s) + Phi(0.2 / (s * math.sqrt(2))), 1e-12, "2.9 s: just above 2")
			T.near(M.NCycles(6, 3.0, s), 1 + Phi(3 / s) + 0.5, 1e-12, "3.0 s: half the pairs of cycles reach 6 s")
			T.near(M.NCycles(6, 3.1, s), 1 + Phi(2.9 / s) + Phi(-0.2 / (s * math.sqrt(2))), 1e-12, "3.1 s: just below 2")
			T.eq(pcall(M.NCycles, 6, 0, 0), false, "a cycle of 0 s is an error")
		end },
		-- the melee look's one GCD action a cycle (design 15.3), in default.apl.siml's order: Strider Kick at nCycles(8 - 0.4),
		-- Mongoose Bite in the looks it leaves, Immolation Trap at nCycles(30 x (1 - 0.2 x Survivalist's Discipline)) in the
		-- looks left, Wing Clip in every look left but the look before a kick due within 1.5 s (min(1, 1.1 / C) of a look a kick)
		{ "weave melee look: Strider Kick at nCycles(7.6); the bite in the slots left; the trap at nCycles(30 x (1 - 0.2 SD)); Wing Clip the rest but before a kick due within 1.5 s", function()
			for _, sd in ipairs({ 0, 1, 2 }) do
				local b = M.Weave(p158(nil, { striderKick = 1, survivalistsDiscipline = sd })).base
				local C, s, r = b.C, b.sigma, b.rates
				T.near(r.strider, 1 / (M.NCycles(7.6, C, s) * C), 1e-12, "the kick")
				T.near(r.trap, math.min(1 / (M.NCycles(30 * (1 - 0.2 * sd), C, s) * C), 1 / C - r.strider - r.bite), 1e-12, "the trap, SD " .. sd)
				T.near(r.wingClip, math.max(0, 1 / C - r.strider - r.bite - r.trap - r.strider * math.min(1, 1.1 / C)), 1e-12, "Wing Clip")
				T.truthy(r.strider + r.bite + r.trap + r.wingClip <= 1 / C + 1e-12, "one action a look")
			end
			local sd0 = M.Weave(p158()).base.rates
			T.truthy(M.Weave(p158(nil, { striderKick = 1, survivalistsDiscipline = 2 })).base.rates.trap > sd0.trap + 1e-6, "Survivalist's Discipline: more traps")
			-- 15.8's counts a second: Strider Kick 0.1259, Immolation Trap 0.0315 (every 8 cycles), Wing Clip 0.0596
			T.near(sd0.strider, 0.1259, 5e-5); T.near(sd0.trap, 0.0315, 5e-5); T.near(sd0.wingClip, 0.0596, 5e-5)
			-- with Expose Prey the bites take the looks the kick leaves, before the trap and Wing Clip
			local e = M.Weave(p158(nil, { striderKick = 1, exposePrey = 2 })).base
			T.truthy(e.rates.bite > 0, "bites")
			T.near(e.rates.trap, math.min(1 / (M.NCycles(30, e.C, e.sigma) * e.C), 1 / e.C - e.rates.strider - e.rates.bite), 1e-12)
			-- without Strider Kick, Wing Clip every look left
			local n = M.Weave(p158(nil, {})).base
			T.near(n.rates.wingClip, 1 / n.C - n.rates.trap, 1e-12, "no kick: Wing Clip the rest")
			-- a slow cycle (a 5.0 s main hand): the kick and the bites leave the trap less than its cooldown asks, no Wing Clip
			local f = M.Weave(p158({ mhSpeed = 5.0 }, { striderKick = 1, exposePrey = 2, survivalistsDiscipline = 2 })).base
			local left = 1 / f.C - f.rates.strider - f.rates.bite
			T.truthy(left < 1 / (M.NCycles(18, f.C, f.sigma) * f.C) - 1e-6, "the looks left are fewer than the trap asks")
			T.near(f.rates.trap, left, 1e-12, "the trap in the looks left"); T.eq(f.rates.wingClip, 0, "no look for Wing Clip")
			-- an 8.0 s main hand: the swing timer sets an 8 s cycle, so Strider Kick's 7.6 s comes due at every melee look and takes
			-- each, and Expose Prey's windows find no look left (r_B = min(bites, 1/C - r_K)): no bite, no trap, no Wing Clip
			local e8 = M.Weave(p158({ mhSpeed = 8.0 }, { striderKick = 1, exposePrey = 2 })).base
			T.near(e8.C, 8.0, 1e-12); T.near(e8.rates.strider, 1 / 8.0, 1e-12, "a kick every look")
			T.eq(e8.rates.bite, 0, "no look left for a bite")
			T.eq(e8.rates.trap, 0, "no look left for the trap"); T.eq(e8.rates.wingClip, 0, "no look left for Wing Clip")
		end },
		-- the range looks (design 15.3): one GCD slot a cycle and a second with P2 = f_M x P(rho3 - rho1 >= 3 - E[S]) + (1 - f_M)
		-- x P(rho3 - rho1 >= 1.5 + the walk out to 11.67 yd + r_poll - E[S]); Serpent Sting's casts first, then Arcane Shot at
		-- nCycles(6 - 0.3 x Improved Arcane Shot) of the range looks, then the shared category 2 shot, Multi-Shot (the SV Weave
		-- preset's Use Multi-Shot true, Use Aimed Shot false: default.apl.siml:6-7, 30-33; U3 = (a)), at nCycles(6 + 0.5 / hR)
		-- in the looks left: its 6 s cooldown starts when its 0.5 s cast at the cycle's ranged speed hR completes (wowsims
		-- cast.go:224-258, multi_shot.go:15-17; hR = the bow speed over the shot's time R). Multi-Shot's hit against Auto
		-- Shot's (Forever's one rank 2643: the normalized weapon hit w x s + RAP x 2.8 / 14 + 9, multi_shot.go:20,
		-- hunter.go:20; Auto Shot's (w + RAP / 14) x s, the same hit, crit, armor and Focused Fire): their ratio per hit (my
		-- arithmetic)
		{ "weave range looks: Serpent Sting first, then Arcane Shot, then Multi-Shot; a second slot by P2", function()
			local past = M.WeaveMeans.pastBy
			local rPoll = (0.15 ^ 2 + 0.15 * 0.35 + 0.35 ^ 2) / 3 / 0.5
			local function check(p, name)
				local b = M.Weave(p).base
				local C, s, r = b.C, b.sigma, b.rates
				local fM = math.min(1, (r.strider + r.bite + r.trap + r.wingClip) * C)
				local P2 = fM * past(3 - b.ES, 0.15, 0.35) + (1 - fM) * past(1.5 + (5 + 8 - 4 / 3 - 4.99) / 7 + rPoll - b.ES, 0.15, 0.35)
				T.near(b.P2, P2, 1e-12, name .. ": P2"); T.near(b.nR, 1 + P2, 1e-12, name .. ": the range slots")
				local CR = C / (1 + P2)
				T.near(r.arcane, math.min(1 / (M.NCycles(6 - 0.3 * p.tal.improvedArcaneShot, CR, s) * CR), 1 / CR - r.serpent), 1e-12,
					name .. ": Arcane Shot after Serpent Sting")
				T.near(b.hR, p.bowSpeed / b.R, 1e-12, name .. ": the cycle's ranged speed")
				T.near(r.multi, math.max(0, math.min(1 / (M.NCycles(6 + 0.5 / b.hR, CR, s) * CR), 1 / CR - r.serpent - r.arcane)), 1e-12,
					name .. ": Multi-Shot in the looks left")
				return b
			end
			local b = check(p158(), "15.8")
			T.truthy(b.P2 > 0, "a second slot now and then: " .. b.P2)
			-- Serpent Sting's casts: the landed sting's 0.8 uptime, 15 s, over the shots' hit (8% miss at +3)
			T.near(b.rates.serpent, 0.8 / 15 / 0.92, 1e-12)
			-- a slow cycle (a 6.6 s main hand sets it): Serpent Sting's casts leave Arcane Shot less than its cooldown asks
			local slow = check(p158({ mhSpeed = 6.6 }), "slow")
			local CR = slow.C / slow.nR
			T.truthy(slow.rates.arcane < 1 / (M.NCycles(6, CR, slow.sigma) * CR) - 1e-6, "Serpent Sting first")
			check(p158(nil, { striderKick = 1, improvedArcaneShot = 5 }), "Improved Arcane Shot")
			-- a 3.8 s bow at the reference (no kick, Wing Clip in every look left, so f_M 1): the shot path past 3 s gives a
			-- second range slot in most cycles, C_R about 2.34 s, where Improved Arcane Shot 5/5's 4.5 s cooldown takes 2 range
			-- looks and the plain 6 s takes 3
			local ias0 = check(svPoint({ bowSpeed = 3.8 }, { improvedArcaneShot = 0 }), "a 3.8 s bow")
			local ias5 = check(svPoint({ bowSpeed = 3.8 }, { improvedArcaneShot = 5 }), "a 3.8 s bow, Improved Arcane Shot 5/5")
			local CR5 = ias5.C / ias5.nR
			T.truthy(M.NCycles(4.5, CR5, ias5.sigma) < 2.1 and M.NCycles(6, CR5, ias5.sigma) > 2.9, "2 range looks against 3")
			T.truthy(ias5.rates.arcane > ias0.rates.arcane + 1e-3, "Improved Arcane Shot: more Arcane Shots")
			T.eq(M.Parts(p158()).aimed, 0, "no Aimed Shot")
			T.truthy(b.rates.multi > 0, "Multi-Shot at 15.8's point")
			local rapShot = ref.rap + M.Rank("huntersMark", 60)
			T.near(b.parts.multi / b.rates.multi, b.parts.auto / b.rates.auto * (53 * 3.0 + rapShot * 2.8 / 14 + 9) / ((53 + rapShot / 14) * 3.0), 1e-9,
				"Multi-Shot's hit: the normalized weapon hit + 9 against Auto Shot's")
			-- a 3.42 s bow at 15.8's point: C_R 3.02 s, so two range looks pass Multi-Shot's 6 s from the cast's start but not
			-- the 6.43 s from its end (0.5 s at the quiver's 15%): its cooldown takes three looks, not two (my arithmetic)
			local edge = check(p158({ bowSpeed = 3.42 }), "a 3.42 s bow")
			local CRe = edge.C / edge.nR
			T.truthy(2 * CRe > 6 and 2 * CRe < 6 + 0.5 / 1.15 - 0.2, "two looks between 6 and 6.43 s: " .. CRe)
			T.near(edge.hR, 1.15, 1e-12, "the quiver's 15%")
			T.near(edge.rates.multi, 1 / (M.NCycles(6 + 0.5 / 1.15, CRe, edge.sigma) * CRe), 1e-12, "its cooldown binds")
			T.truthy(edge.rates.multi < 1 / (M.NCycles(6, CRe, edge.sigma) * CRe) - 0.02, "fewer than from the cast's start")
			T.eq(M.Weave(p158({ level = 17 })).base.rates.multi, 0, "no Multi-Shot before 18")
			T.truthy(M.Weave(p158({ level = 18 })).base.rates.multi > 0, "Multi-Shot from 18")
		end },
		-- Multi-Shot's hit in the weave (raid-mode design 18.5): (w x s + RAP x 2.8 / 14 + 9 + flat) x shotHitf x rcrit x phys x
		-- own x rws x (1 + 5% a rank of Barrage) a cast. At 15.8's point (levelling: no Gift of Arthas) a cast's damage, the part
		-- over the rate: Barrage 3/3 (+15%, +5% a rank on Aimed Shot and Multi-Shot, Model.Parts' turret rule), Focused Fire 2/2
		-- with the pet out (+2%, ownDamage), Ranged Weapon Specialization 5/5 (+5%) each scale it alone; Beastslaying's flat
		-- (levelling: its beast share, Model.TargetShare) adds to a Multi-Shot what it adds to an Auto Shot, both the same
		-- physical shot of the bow (my arithmetic)
		{ "weave Multi-Shot's hit: Barrage, Focused Fire, Ranged Weapon Specialization and Beastslaying's flat reach it", function()
			local function perCast(over, tover)
				local t = { striderKick = 1 }
				for k, v in pairs(tover or {}) do t[k] = v end
				local b = M.Weave(p158(over, t)).base
				T.truthy(b.rates.multi > 0, "Multi-Shot is cast")
				return b.parts.multi / b.rates.multi, b.parts.auto / b.rates.auto
			end
			local m0, a0 = perCast()
			T.near(perCast(nil, { barrage = 3 }) / m0, 1.15, 1e-12, "Barrage 3/3")
			T.near(perCast(nil, { focusedFire = 2 }) / m0, 1.02, 1e-12, "Focused Fire 2/2")
			T.near(perCast(nil, { rangedWeaponSpec = 5 }) / m0, 1.05, 1e-12, "Ranged Weapon Specialization 5/5")
			local mf, af = perCast({ beastSlaying = 20 })
			T.truthy(af > a0 + 1e-6, "Beastslaying's flat on the Auto Shot")
			T.near(mf - m0, af - a0, 1e-9, "the same flat on a Multi-Shot")
			local mfb = perCast({ beastSlaying = 20 }, { barrage = 3 })
			T.near(mfb, 1.15 * mf, 1e-9, "Barrage on the flat too")
		end },
		{ "weave: Strider Kick's 30% for 3 s shortens the walk out and the next walk in", function()
			local with, without = M.Weave(p158()).base, M.Weave(p158(nil, {})).base
			T.eq(without.k, 0); T.near(without.Wout, 8.2 / 7, 1e-12); T.near(without.Win, 8.19 / 7, 1e-12)
			local k = with.k
			T.truthy(k > 0, "kicks")
			T.near(with.Wout, (1 - k) * 8.2 / 7 + k * 8.2 / 9.1, 1e-12, "the walk out after a kick at 9.1 yd/s")
			local t = math.max(0, 3 - with.ES)
			T.near(with.Win, (1 - k) * 8.19 / 7 + k * (t + (8.19 - 9.1 * t) / 7), 1e-12, "the walk in: 9.1 yd/s for what is left of 3 s")
			-- a fast bow: the walk in starts early enough to run all of it at 9.1 yd/s
			local fast = M.Weave(p158({ bowSpeed = 1.6 })).base
			T.truthy(9.1 * (3 - fast.ES) >= 8.19, "the whole walk in the kick's 3 s")
			T.near(fast.Win, (1 - fast.k) * 8.19 / 7 + fast.k * 8.19 / 9.1, 1e-12)
		end },
		{ "weave: no hawks, no dive and no Sniper Shot with the talents taken", function()
			local p = svPoint({ level = 60 }, { summonHawk = 1, sniperShot = 1 })
			local parts = M.Parts(p)
			for _, k in ipairs({ "hawks", "dive", "sniper", "aimed" }) do T.eq(parts[k], 0, k) end
			T.truthy(parts.auto > 0 and parts.arcane > 0 and parts.multi > 0 and parts.melee > 0 and parts.trap > 0, "the weave")
			local r = weaveRates(p)
			T.near(M.LandedHits(p).ranged.specials, (r.arcane + r.multi) * 0.96, 1e-12, "the ranged specials: Arcane Shot and Multi-Shot, no dive")
			local bm = M.Parts(svPoint({ level = 60, survival = false }, { summonHawk = 1, sniperShot = 1 }))
			T.truthy(bm.hawks > 0 and bm.dive > 0 and bm.sniper > 0, "outside the Survival branch they are cast")
		end },
		{ "weave: no bow, no melee and no shot", function()
			local p = svPoint({ noShots = true, bowDPS = 0 }, { exposePrey = 2, striderKick = 1 })
			local parts = M.Parts(p)
			for _, k in ipairs({ "melee", "trap", "auto", "arcane", "serpent", "aimed", "multi", "sniper", "dive", "hawks" }) do T.eq(parts[k], 0, k) end
			T.truthy(parts.pet > 0, "the pet")
			local h = M.LandedHits(p)
			T.eq(h.mh.swings + h.mh.specials + h.oh.swings + h.ranged.swings + h.ranged.specials + h.ranged.casts, 0, "no landed hit")
			T.eq(M.Weave(p), nil, "no weave")
		end },
		-- starting the melee attack puts the off hand's swing at least half its swing time out (attack.go:806-819): it swings in a
		-- visit only where half of it fits before the walk out, clamp((0.35 + max(0, M - K) - ohSwing / 2) / 0.2) a cycle
		-- (design 15.3); level 20: no Rapid Fire
		{ "weave: the off hand swings only while the swing timer holds the hunter in melee, by its share", function()
			local inBetween = false
			for _, case in ipairs({ { 2.6, 1.8 }, { 5.0, 1.8 }, { 4.05, 2.0 }, { 4.6, 2.6 } }) do
				local b = M.Weave(svPoint({ level = 20, mhSpeed = case[1], ohSpeed = case[2] })).base
				local share = math.max(0, math.min(1, (0.35 + math.max(0, b.M - b.K) - case[2] / 2) / 0.2))
				T.near(b.rates.oh, share / b.C, 1e-12, case[1] .. " / " .. case[2])
				if share > 0.1 and share < 0.9 then inBetween = true end
			end
			T.truthy(inBetween, "a share strictly between")
			T.eq(M.Weave(svPoint({ level = 20 })).base.rates.oh, 0, "behind the 2.6 s main hand: none")
			T.near(M.Weave(svPoint({ level = 20, mhSpeed = 5.0 })).base.rates.oh, 1 / 5.0, 1e-12, "behind a 5.0 s main hand: every visit")
		end },
		-- An off hand that swings in no visit (the 2.6 s off hand behind the 2.6 s main hand, which the walk sets: its swing comes
		-- at least 1.3 s after the attack starts on arrival, attack.go:806-819, 869-871) still makes the hunter dual wield: every
		-- main-hand white swing rolls 19% more miss (wowsims sim/core/spell_outcome.go:852-871 OutcomeExpectedMeleeWhite's table
		-- takes GetPhysicalMissChance, :546-554, with IsDualWielding = an off hand of a swing speed, sim/core/attack.go:560), the
		-- specials not (physicalMissChanceNoDWPenalty, :569-571). Level 20 (no Rapid Fire), +0, 1% hit: the main hand's white miss 5% + 19% - 1% = 23% against 4%, the dodge
		-- 5%, the glance 10% at 0.95, the crit under the room in both: the roll 0.19 lower (my arithmetic), the cycle the same.
		-- So taking the off hand off gains the main hand's white swings' 19%, as wowsims' weave plays it
		{ "weave: an off hand that swings in no visit still gives the main hand's white swings the dual-wield 19% more miss; taking it off gains", function()
			local worn, bare = svPoint({ level = 20 }), svPoint({ level = 20, ohDPS = 0 })
			local wb, bb = M.Weave(worn).base, M.Weave(bare).base
			T.eq(wb.rates.oh, 0, "the off hand swings in no visit"); T.eq(wb.C, bb.C, "the cycle without the off hand")
			T.eq(wb.rates.mhWhite, bb.rates.mhWhite)
			local swing = (26 + ref.map / 14) * 2.6
			T.near(M.Parts(bare).melee - M.Parts(worn).melee, 0.19 * swing * wb.rates.mhWhite * M.PhysMult(20, 0) * 1.02, 1e-9,
				"the main hand's white swings, 19% more of them landing")
			T.near(M.LandedHits(bare).mh.swings - M.LandedHits(worn).mh.swings, 0.19 * wb.rates.mhWhite, 1e-12, "the landed white swings")
			T.truthy(M.Total(bare) > M.Total(worn), "taking the off hand off gains")
		end },
		-- Wing Clip 14268 (from 60: 50; 14267 from 38: 25; 2974 from 12: 5): Effect 2 physical with EffectBonusCoefficient 1, so
		-- Beastslaying's flat comes whole; the melee special table (wing_clip.go:18); Savage Strikes and Predator's Edge reach
		-- it. Level 60, +0, 1% hit: the special roll 1 - 4% - 5%, Savage Strikes 2/2 +4% crit, Predator's Edge 5/5 +30% crit
		-- damage, Beastslaying +10 at 0.3 (my arithmetic); no Strider Kick or Expose Prey: the melee part is the white swings
		-- (glance 10% at 0.95), Raptor Strike and Wing Clip, each at the weave's count, x the armor and Focused Fire 2/2
		{ "weave: Wing Clip deals 50 + Beastslaying's flat on the special table with Savage Strikes and Predator's Edge, through armor; none unarmed", function()
			local p = svPoint({ level = 60, ohDPS = 0, beastSlaying = 10 }, { savageStrikes = 2, predatorsEdge = 5 })
			local r = weaveRates(p)
			T.truthy(r.wingClip > 0, "Wing Clip")
			local c = ref.meleeCrit / 100
			local critAbil = 1 + (c + 0.04) * 1.30
			local swing = 26 * 2.6 + 314 / 14 * 2.6 + 3
			local melee = swing * (0.905 + c) * r.mhWhite + (swing + M.Rank("raptorBonus", 60)) * 0.91 * critAbil * r.raptor
				+ (50 + 3) * 0.91 * critAbil * r.wingClip
			T.near(M.Parts(p).melee, melee * M.PhysMult(60, 0) * 1.02, 1e-9)
			T.eq(M.Rank("wingClip", 11), 0); T.eq(M.Rank("wingClip", 12), 5); T.eq(M.Rank("wingClip", 38), 25); T.eq(M.Rank("wingClip", 60), 50)
			T.eq(weaveRates(svPoint({ unarmed = true, mhDPS = 0, ohDPS = 0 })).wingClip, 0, "none unarmed")
			T.eq(weaveRates(svPoint({ level = 11 })).wingClip, 0, "none before 12")
		end },
		-- Immolation Trap 14305 / its tick 14301 (from 56: 138 every 3 s for 15 s), 10% of the ranged attack power over its five
		-- ticks (traps.go:10-14, 65-68); the application on the spell table (4% + 1% a level, 17% at +3, less the spell hit and
		-- 5% a rank of Survival Tactics), the ticks at spell crit x1.5, Clever Traps +15% a rank; fire, no armor; x Focused Fire
		-- 2/2 (my arithmetic); level 60
		{ "weave: Immolation Trap's five ticks of 138 + 2% RAP, its spell miss less Survival Tactics, x1.5 spell crit, Clever Traps, no armor", function()
			for _, case in ipairs({ { 0, 0, 0, 0 }, { 3, 0, 0, 0 }, { 3, 2, 2, 1 }, { 3, 1, 0, 6 }, { 2, 0, 1, 0 } }) do
				local d, st, ct, sh = case[1], case[2], case[3], case[4]
				local p = svPoint({ level = 60, mobDiff = d, spellHit = sh, spellCrit = 7 }, { survivalTactics = st, cleverTraps = ct })
				local r = weaveRates(p)
				T.truthy(r.trap > 0, "traps")
				local spellMiss = d >= 3 and 0.17 or 0.04 + 0.01 * d
				local miss = math.max(0, spellMiss - sh / 100 - 0.05 * st)
				local rapShot = ref.rap + M.Rank("huntersMark", 60)
				local want = 5 * (138 + 0.02 * rapShot) * (1 + 0.15 * ct) * (1 - miss) * (1 + 0.5 * 0.07) * 1.02 * r.trap
				T.near(M.Parts(p).trap, want, 1e-9, string.format("+%d, Survival Tactics %d, Clever Traps %d, spell hit %d", d, st, ct, sh))
			end
			T.eq(M.Rank("immolationTick", 15), 0); T.eq(M.Rank("immolationTick", 16), 21); T.eq(M.Rank("immolationTick", 26), 43)
			T.eq(M.Rank("immolationTick", 36), 68); T.eq(M.Rank("immolationTick", 46), 102); T.eq(M.Rank("immolationTick", 56), 138)
			T.eq(weaveRates(svPoint({ level = 15 })).trap, 0, "none before 16")
		end },
		-- the weave's landed hits (Model.LandedHits, design 15.4): the main hand's white swings, a cycle's swing less Raptor
		-- Strike's, at the white roll; Raptor Strike, Strider Kick, Mongoose Bite and Wing Clip in its specials at the special
		-- roll; the off hand's share; one Auto Shot a cycle and Arcane Shot at the shots' hit; Serpent Sting's landed
		-- applications. +0, 1% hit: 1 - 4% - 5%, dual wield 1 - 23% - 5%, the shots 1 - 4%
		{ "weave landed hits: white swings 1/C less Raptor Strike; Raptor, Strider, Mongoose and Wing Clip in the specials; one Auto Shot a cycle; Arcane and Multi-Shot", function()
			local p = svPoint({ mhSpeed = 5.0, ohSpeed = 1.8 }, { striderKick = 1, exposePrey = 2 })
			local r, h = weaveRates(p), M.LandedHits(p)
			T.truthy(r.raptor > 0 and r.strider > 0 and r.bite > 0 and r.wingClip > 0 and r.oh > 0, "every hit in play")
			T.near(h.mh.swings, r.mhWhite * 0.72, 1e-12, "the white swings")
			T.near(h.mh.specials, (r.raptor + r.strider + r.bite + r.wingClip) * 0.91, 1e-12, "the specials")
			T.near(h.oh.swings, r.oh * 0.72, 1e-12, "the off hand")
			T.near(h.ranged.swings, r.auto * 0.96, 1e-12, "one Auto Shot a cycle")
			T.near(h.ranged.specials, (r.arcane + r.multi) * 0.96, 1e-12, "Arcane Shot and Multi-Shot")
			T.near(h.ranged.casts, 0.8 / 15, 1e-15, "the landed applications")
			T.near(r.mhWhite + r.raptor, r.auto, 1e-12, "one main-hand swing a cycle")
			-- the Auto Shot part: one shot a cycle, its weapon and ammo damage over the bow's 2.6 s and the shots' RAP / 14 a
			-- second of it, at the shots' hit, crit (no suppression at +0), the armor and Focused Fire 2/2
			local rapShot = ref.rap + M.Rank("huntersMark", 43)
			T.near(M.Parts(p).auto, ((21 + 13 + rapShot / 14) * 2.6) * r.auto * 0.96 * (1 + ref.crit / 100) * M.PhysMult(43, 0) * 1.02, 1e-9,
				"Model.Parts' Auto Shots: one a cycle")
		end },
		-- where the ranged path sets the cycle a slower two-hander of equal DPS swings as often and hits harder (design 15.7)
		{ "weave weights: at equal DPS a slower two-hander gains while the ranged path sets the cycle", function()
			local function point(speed) return svPoint({ twoH = true, ohDPS = 0, mhDPS = 40, mhSpeed = speed, mhNorm = 3.3 }) end
			local fast, slow = M.Weave(point(3.0)).base, M.Weave(point(3.4)).base
			T.truthy(3.4 <= slow.K + 0.15, "the ranged path sets the cycle")
			T.near(slow.C, fast.C, 1e-12, "the same cycle"); T.near(slow.rates.raptor, fast.rates.raptor, 1e-12, "the same Raptor count")
			T.truthy(M.Parts(point(3.4)).melee > M.Parts(point(3.0)).melee + 1e-6, "more damage a swing")
		end },
		-- levelling (design 15.5): every rate and part averaged over Rapid Fire's 15 s of 300, the cycle at rf 0 and at its
		-- 40% (never the cycle at the average speed); Serpent Sting's landed sting at CONST.serpentUptime 0.8, its applications
		-- 0.8 / 15 a second, each (5 x the tick + 0.25 x RAP) x the shots' crit x Focused Fire 2/2, no hit factor
		-- Starting the melee attack puts the off hand's swing half its swing time out at the unit's whole melee speed (wowsims
		-- sim/core/attack.go:814-816 TotalMeleeHasteMultiplier, which holds Rapid Fire's melee speed, unit.go:610-612 and
		-- parse_effects_table.go:364-366): within Rapid Fire the off hand's half swing is shorter. Level 60, a 5.0 s main hand
		-- and a 1.8 s off hand: outside Rapid Fire 0.9 s of half a swing never fits (the share 0), inside it 0.643 s fits in
		-- part of the visits (my arithmetic)
		{ "weave: the off hand's half swing at Rapid Fire's melee speed: inside Rapid Fire it swings in part of the visits", function()
			local w = M.Weave(svPoint({ level = 60, mhSpeed = 5.0, ohSpeed = 1.8 }))
			local f = w.rapidFire
			local share = math.max(0, math.min(1, (0.35 + math.max(0, f.M - f.K) - 1.8 / 1.4 / 2) / 0.2))
			T.truthy(share > 0.1 and share < 0.9, "a share strictly between: " .. share)
			T.eq(math.max(0, math.min(1, (0.35 + math.max(0, f.M - f.K) - 1.8 / 2) / 0.2)), 0, "the half swing outside Rapid Fire's speed never fits")
			T.near(f.rates.oh, share / f.C, 1e-12, "the off hand inside Rapid Fire")
			local b = w.base
			T.near(b.rates.oh, math.max(0, math.min(1, (0.35 + math.max(0, b.M - b.K) - 1.8 / 2) / 0.2)) / b.C, 1e-12, "outside it")
		end },
		-- Strider Kick at the melee look whose cooldown is within 0.4 s (kick_soon, weave_common.apl.siml:13-19): its 8 s less
		-- 0.4 s, 7.6 s, against the cycles a kick waits. A cycle a little over 3.8 s kicks every second cycle, one under it every
		-- third; with the cycles' spread (WA2) the share k = 1 / nCycles(7.6, C, sigma) runs smoothly from 1/2 to 1/3 across
		-- 2C = 7.6 s. 15.8's point with a 2.85 s bow and a 3.7 s two-hander sits on that edge (C 3.83 s, my arithmetic): 0.5%
		-- more haste rating shortens the shots and the cycle, more kicks wait a third cycle and their looks go to Wing Clip, so
		-- the melee part and the total fall (the weight of haste rating is below 0 there: raid-mode design 18.3); past the edge
		-- (6% more) the kick is every third cycle and haste gains again
		{ "weave: at the edge of Strider Kick's 7.6 s (2C near 7.6 s) more haste rating moves kicks to every third cycle and lowers the total", function()
			local base = p158({ bowSpeed = 2.85, mhSpeed = 3.7 })
			local w = M.Weave(base).base
			T.truthy(w.k > 1 / 3 + 0.05 and w.k < 0.5 - 0.02, "on the edge: k " .. w.k)
			T.near(w.k, 1 / M.NCycles(7.6, w.C, w.sigma), 1e-8, "k by nCycles(7.6)")
			local fast = p158({ bowSpeed = 2.85, mhSpeed = 3.7, hasteRating = 0.5 })
			local f = M.Weave(fast).base
			T.truthy(f.C < w.C and f.k < w.k - 0.01 and f.rates.strider < w.rates.strider, "fewer kicks: k " .. f.k)
			T.truthy(f.rates.wingClip > w.rates.wingClip, "their looks go to Wing Clip")
			T.truthy(M.Parts(fast).melee < M.Parts(base).melee and M.Total(fast) < M.Total(base), "the melee part and the total fall")
			local past = p158({ bowSpeed = 2.85, mhSpeed = 3.7, hasteRating = 6 })
			T.near(M.Weave(past).base.k, 1 / 3, 1e-3, "every third cycle")
			T.truthy(M.Total(past) > M.Total(base), "past the edge haste gains again")
		end },
		-- Spell hit and spell crit (raid-mode design 18.8): Immolation Trap's application rolls the spell table (17% at +3, 4%
		-- at +0, less the spell hit and Survival Tactics' 5% a rank: Model.TrapHitCap), its ticks crit at spell crit x1.5, so
		-- in the weave W.SPELL_CRIT is the trap's part x 0.5% over its crit factor a point, and W.SPELL_HIT, taken at 0 spell
		-- hit, the trap's part there over its 83% that lands, 1% of it (my arithmetic); outside the weave both are 0
		{ "weights: spell hit below the trap's cap and spell crit price Immolation Trap in the weave; none outside it", function()
			T.eq(M.TrapHitCap(3, 0), 17); T.eq(M.TrapHitCap(3, 2), 7); T.eq(M.TrapHitCap(0, 0), 4); T.eq(M.TrapHitCap(0, 2), 0)
			T.eq(M.TrapHitCap(5, 0), 17, "+5 as +3")
			local p = p158(nil, { striderKick = 1 })
			local W, unitDps = M.Weights(p)
			local trap = M.Parts(p).trap
			T.truthy(trap > 0, "the trap in the weave")
			T.near(W.SPELL_CRIT * unitDps, trap * 0.005 / (1 + 0.005 * p.spellCrit), 1e-9, "spell crit: the ticks' x1.5")
			local q = {}
			for k, v in pairs(p) do q[k] = v end
			q.spellHit = 0
			T.near(W.SPELL_HIT * unitDps, M.Parts(q).trap / 0.83 * 0.01, 1e-9, "spell hit at 0: 1% of the application's 83%")
			-- past the cap at the model point the weight stays the slope below it (taken at 0)
			local past = p158({ spellHit = 20 }, { striderKick = 1 })
			local Wp, unitP = M.Weights(past)
			T.near(Wp.SPELL_HIT * unitP, M.Parts(q).trap / 0.83 * 0.01, 1e-9, "taken at 0 past the cap")
			local bm = M.Weights(svPoint({ survival = false }))
			T.eq(bm.SPELL_HIT, 0); T.eq(bm.SPELL_CRIT, 0)
		end },
		{ "weave levelling: Rapid Fire averaged over the two cycles; Serpent Sting at 0.8", function()
			local p = svPoint({}, { striderKick = 1 })
			local wv = M.Weave(p)
			local up = 15 / 300
			T.near(wv.rfUp, up, 1e-15)
			T.near(wv.rapidFire.M, 2.6 / 1.4, 1e-12, "the swing at Rapid Fire's 40%")
			T.near(wv.rapidFire.R, 2.6 / (1.13 * 1.4 * (1 + 0.3 * wv.rapidFire.qsUp)), 1e-12, "the shots at Rapid Fire's 40%")
			T.near(wv.average.rates.auto, (1 - up) / wv.base.C + up / wv.rapidFire.C, 1e-12, "the Auto Shots of the two cycles")
			for _, k in ipairs({ "auto", "melee", "trap", "arcane" }) do
				T.near(wv.average[k], (1 - up) * wv.base.parts[k] + up * wv.rapidFire.parts[k], 1e-12, k)
				T.near(M.Parts(p)[k], wv.average[k], 1e-12, k .. ": Model.Parts")
			end
			T.near(M.LandedHits(p).ranged.casts, 0.8 / 15, 1e-15)
			local rapShot = ref.rap + M.Rank("huntersMark", 43)
			T.near(M.Parts(p).serpent, (5 * M.Rank("serpentTick", 43) + 0.25 * rapShot) * (1 + ref.crit / 100) * 1.02 * 0.8 / 15, 1e-9,
				"Serpent Sting at 0.8, no hit factor")
			local young = M.Weave(svPoint({ level = 25 }))
			T.eq(young.rfUp, 0); T.near(young.average.rates.auto, 1 / young.base.C, 1e-15, "no Rapid Fire before 26")
		end },
		-- Predator's Edge: +10% a rank on the off hand's white swings in the weave (design 15.4), +6% a rank on the abilities'
		-- crit damage. With no melee crit the abilities gain nothing from it, so 5/5 adds half the off hand's white part: level
		-- 20 (no Rapid Fire), +0 with 1% hit, a 5.0 s main hand whose swing timer holds the hunter in melee for a swing of the
		-- 1.8 s off hand every visit, the off hand's 0.5 x (26 + 314 / 14) x 1.8 on the dual-wield white roll (miss 5% + 19% -
		-- 1%, dodge 5%, glancing), the armor and Focused Fire 2/2 (my arithmetic)
		{ "weave: Predator's Edge +10% a rank on the off hand's white swings", function()
			local function point(pe) return svPoint({ level = 20, mhSpeed = 5.0, ohSpeed = 1.8, meleeCrit = 0 }, { predatorsEdge = pe }) end
			local r = weaveRates(point(5))
			T.near(r.oh, 1 / 5.0, 1e-12, "the off hand every visit")
			local gChance, gAvg = M.Glance(0, 0) -- the off hand at the level's skill
			local whiteRoll = 1 - 0.23 - 0.05 - gChance * (1 - gAvg)
			local ohWhite = 0.5 * (26 + 314 / 14) * 1.8 * whiteRoll * r.oh * M.PhysMult(20, 0) * 1.02
			T.near(M.Parts(point(5)).melee - M.Parts(point(0)).melee, 0.5 * ohWhite, 1e-9)
		end },
		-- Ranged Weapon Specialization: +1% a rank on the Auto Shots and Arcane Shot in the weave (design 15.4), not on the melee
		-- part or the trap; the counts stay
		{ "weave: Ranged Weapon Specialization +1% a rank on the Auto Shots and Arcane Shot, not the melee or the trap", function()
			local a, b = M.Parts(svPoint({}, { rangedWeaponSpec = 0 })), M.Parts(svPoint({}, { rangedWeaponSpec = 5 }))
			T.near(b.auto / a.auto, 1.05, 1e-12, "the Auto Shots"); T.near(b.arcane / a.arcane, 1.05, 1e-12, "Arcane Shot")
			T.near(b.melee, a.melee, 1e-12, "the melee part"); T.near(b.trap, a.trap, 1e-12, "the trap")
		end },
		-- the weave's actions from the level they are learned (design 15.3): Strider Kick from 30 (the talent), Arcane Shot from 6
		{ "weave: Strider Kick from 30, Arcane Shot from 6", function()
			T.eq(weaveRates(svPoint({ level = 29 }, { striderKick = 1 })).strider, 0, "no kick at 29")
			T.truthy(weaveRates(svPoint({ level = 30 }, { striderKick = 1 })).strider > 0, "the kick at 30")
			T.eq(weaveRates(svPoint({ level = 5 })).arcane, 0, "no Arcane Shot at 5")
			T.truthy(weaveRates(svPoint({ level = 6 })).arcane > 0, "Arcane Shot at 6")
		end },
		-- Model.Weights' melee setups (W.MH_DPS, W.OH_DPS, W.TH_DPS and W.HIT_DW): each hand type at the worn main hand when it is
		-- a weapon of that type, else at a typical weapon of the type, a one-hander of 26 DPS at 2.6 s normalized at 2.4, a
		-- two-hander of 34 DPS at 3.3 s. An empty main hand is a weapon of neither type (its 1.0 s is the unarmed swing), so it
		-- takes both typical weapons; a worn two-hander's one-hander setup normalizes at 2.4, which W.HIT_DW reads through
		-- Mongoose Bite (Expose Prey 2/2). Compared per DPS (the weight x the unit's DPS: the unit, 1 RAP, is each point's own)
		{ "weights' melee setups: a typical weapon of each hand type, at its own speed and normalized speed for an empty main hand too", function()
			local function perDps(over)
				local W, unitDps = M.Weights(svPoint(over, { striderKick = 1, exposePrey = 2 }))
				return { mh = W.MH_DPS * unitDps, oh = W.OH_DPS * unitDps, th = W.TH_DPS * unitDps, dw = W.HIT_DW * unitDps }
			end
			local oneH = perDps({})
			local twoH = perDps({ twoH = true, mhDPS = 34, mhSpeed = 3.3, mhNorm = 3.3, ohDPS = 0 })
			local unarmed = perDps({ unarmed = true, mhDPS = 0, mhSpeed = 1.0, mhNorm = 1.0 })
			T.truthy(oneH.mh > 0 and oneH.th > 0 and oneH.dw > 0, "the weave prices the melee weapons")
			for _, k in ipairs({ "mh", "oh", "dw" }) do
				T.near(unarmed[k], oneH[k], 1e-9, "an empty main hand: the one-hander of 26 DPS at 2.6 s, " .. k)
				T.near(twoH[k], oneH[k], 1e-9, "a worn two-hander: the one-hander of 26 DPS at 2.6 s, " .. k)
			end
			T.near(unarmed.th, twoH.th, 1e-9, "an empty main hand: the two-hander of 34 DPS at 3.3 s")
			T.near(oneH.th, twoH.th, 1e-9, "a worn one-hander: the two-hander of 34 DPS at 3.3 s")
		end },
		-- the cycle, the kick share and Quick Shots' uptime (2% a rank of Deadly Aspects on each of the 12 / C Auto Shots of its
		-- 12 s) depend on each other: one fixed point; a cycle that never settles (a NaN swing) is an error
		{ "weave fixed point: Quick Shots and the kick share converge; no convergence is an error", function()
			local b = M.Weave(svPoint({}, { striderKick = 1, deadlyAspects = 5 })).base
			T.truthy(b.qsUp > 0 and b.k > 0, "Quick Shots and kicks")
			T.near(b.qsUp, 1 - (1 - 0.10) ^ (12 / b.C), 1e-8, "Quick Shots at the cycle")
			T.near(b.k, 1 / M.NCycles(7.6, b.C, b.sigma), 1e-8, "the kick share at the cycle")
			T.near(b.R, 2.6 / (1.13 * (1 + 0.3 * b.qsUp)), 1e-12, "the shots' speed with Quick Shots")
			local ok, err = pcall(M.Parts, svPoint({ mhSpeed = 0 / 0 }))
			T.eq(ok, false); T.truthy(tostring(err):find("does not converge in 100 iterations", 1, true), tostring(err))
		end },
		-- the dive's flat damage (raid-mode W1 design section 5): Unleashed Fury's 3 and Ferocity's 2 a rank on the dive's base,
		-- before its crit, the armor and the hunter's multiplier (wowsims spell.BonusBaseDamage, spell_result.go:445-463). The
		-- BM build at level 60, +0 (no suppression): the dive two a 18 s, x (1 + the ranged crit) x the armor x Focused Fire 2/2;
		-- Unleashed Fury's own multiplier and Ferocity's crit are the pet's and the hawks', not the dive's
		{ "dive: base + 3 a rank of Unleashed Fury + 2 a rank of Ferocity, before crit and armor", function()
			local function dive(uf, fer)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.unleashedFury, tal.ferocity = uf, fer
				p.tal, p.level = tal, 60
				return M.Parts(p).dive
			end
			local scale = 2 / 18 * (1 + ref.crit / 100) * M.PhysMult(60, 0) * 1.02
			local rapShot = ref.rap + M.Rank("huntersMark", 60)
			T.near(dive(0, 0), (108 + 0.05 * rapShot) * scale, 1e-9, "no talent: the rank's 108")
			T.near(dive(5, 0) - dive(0, 0), 15 * scale, 1e-9, "Unleashed Fury 5/5: +15")
			T.near(dive(0, 5) - dive(0, 0), 10 * scale, 1e-9, "Ferocity 5/5: +10")
			T.near(dive(3, 2) - dive(0, 0), (9 + 4) * scale, 1e-9, "3 and 2 a rank")
			T.near(dive(5, 5), (108 + 25 + 0.05 * rapShot) * scale, 1e-9, "133 at 5/5 and 5/5")
		end },
		-- every rank of the dive carries the class mask the flats name (approximation B4): at level 43 the rank of 47 with
		-- Unleashed Fury 5/5 and Ferocity 5/5 (the reference build), 47 + 15 + 10
		{ "dive: the flats at every rank (level 43: 47 + 15 + 10)", function()
			local rapShot = ref.rap + M.Rank("huntersMark", 43)
			T.eq(M.Rank("hawkDive", 43), 47)
			T.near(M.Parts(ref).dive, (47 + 15 + 10 + 0.05 * rapShot) * 2 / 18 * (1 + ref.crit / 100) * M.PhysMult(43, 0) * 1.02, 1e-9)
		end },
		-- ranged-7 (raid-mode W1 design section 6): Arcane Shot and Summon Hawk share category 1173's 6 s; Improved Arcane Shot
		-- takes 0.3 s a rank off Arcane Shot's own cooldown alone, so the HHA sequence (hawk, hawk, Arcane) cycles in C0 = 18 -
		-- 0.3 x rank s: Arcane Shot 1 / C0, the dives 2 / C0 a second (levelling; the BM build with Summon Hawk at 43)
		{ "ranged-7: with Summon Hawk, Improved Arcane Shot shortens the HHA cycle to 18 - 0.3 x rank s: Arcane 1 / C0, the dive 2 / C0", function()
			local function at(rank)
				local p = {}
				for k, v in pairs(ref) do p[k] = v end
				local tal = {}
				for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
				tal.improvedArcaneShot = rank
				p.tal = tal
				return M.Parts(p), M.LandedHits(p).ranged
			end
			local p0, h0 = at(0)
			T.truthy(p0.arcane > 0 and p0.dive > 0, "Arcane Shot and the dive with the hawks")
			local rapShot = ref.rap + M.Rank("huntersMark", 43)
			T.near(p0.arcane, (M.Rank("arcaneBase", 43) + 0.15 * rapShot) / 18 * 0.96 * (1 + ref.crit / 100) * 1.02, 1e-9, "1 / 18 at rank 0")
			for _, rank in ipairs({ 2, 5 }) do
				local C0 = 18 - 0.3 * rank
				local p, h = at(rank)
				T.near(p.arcane / p0.arcane, 18 / C0, 1e-12, "Arcane Shot 1 / C0 at rank " .. rank)
				T.near(p.dive / p0.dive, 18 / C0, 1e-12, "the dive 2 / C0 at rank " .. rank)
				T.near(h.specials - h0.specials, (2 + 0.96) * (1 / C0 - 1 / 18), 1e-12, "the landed dives and Arcane Shots at rank " .. rank)
				T.near(p.hawks, p0.hawks, 1e-12, "the hawks' uptime stays CONST.hawkUptime in levelling")
			end
		end },
		-- The mana costs of the raid fight (raid-mode design 7.2; CONST.mana): the level-60 ranks' DB2 SpellPower, a percent of
		-- base mana 1720 rounded to the whole mana as wowsims' newManaCost does (sim/core/mana.go:372): Arcane Shot and Summon
		-- Hawk 11% of 1720 = 189.2 -> 189, Bestial Wrath 12% = 206.4 -> 206, Strider Kick 5.81% = 99.93 -> 100, Multi-Shot
		-- 13.9% = 239.08 -> 239 (my arithmetic). Efficiency (19416) takes 3% a rank off the shots, Serpent Sting, the melee
		-- abilities and Summon Hawk, not Hunter's Mark, Rapid Fire, Bestial Wrath or the trap (its class mask); Resourcefulness
		-- (440529 effect 0) 30% a rank off the melee abilities and the trap; the two multiply (wowsims sim/core/spell_mod.go:
		-- 504-509) and the cost is not rounded after them; Serpent Sting IX (the book, p.serpentTick 135) costs 250
		{ "raid mana costs: the ranks' costs, a percent of base mana rounded; Efficiency and Resourcefulness by their masks, multiplied; Serpent Sting IX with the book", function()
			local function costs(tover, over) return M.ManaCosts(raidPoint(over or {}, tover)) end
			local function same(got, want, name)
				for k, v in pairs(want) do T.near(got[k], v, 1e-9, name .. ": " .. k) end
				for k in pairs(got) do T.truthy(want[k] ~= nil, name .. ": no cost expected for " .. k) end
			end
			local base = { serpent = 230, aimed = 310, arcane = 189, hawk = 189, huntersMark = 60, rapidFire = 100, bestialWrath = 206,
				sniper = 365, raptor = 100, bite = 65, strider = 100, wingClip = 80, trap = 245, multi = 239 }
			same(costs({}), base, "no cost talent")
			local eff = {}
			for k, v in pairs(base) do eff[k] = v end
			for _, k in ipairs({ "serpent", "aimed", "arcane", "hawk", "sniper", "raptor", "bite", "strider", "wingClip", "multi" }) do
				eff[k] = base[k] * 0.85
			end
			same(costs({ efficiency = 5 }), eff, "Efficiency 5/5")
			local res = {}
			for k, v in pairs(base) do res[k] = v end
			for _, k in ipairs({ "raptor", "bite", "strider", "wingClip", "trap" }) do res[k] = base[k] * 0.4 end
			same(costs({ resourcefulness = 2 }), res, "Resourcefulness 2/2")
			local both = costs({ efficiency = 2, resourcefulness = 1 })
			T.near(both.raptor, 100 * 0.94 * 0.7, 1e-9, "both on Raptor Strike, multiplied")
			T.near(both.trap, 245 * 0.7, 1e-9, "the trap: Resourcefulness alone")
			T.near(both.arcane, 189 * 0.94, 1e-9, "Arcane Shot: Efficiency alone")
			T.near(costs({}, { serpentTick = 135 }).serpent, 250, 1e-9, "Serpent Sting IX")
			T.near(costs({ efficiency = 5 }, { serpentTick = 135 }).serpent, 250 * 0.85, 1e-9, "Serpent Sting IX with Efficiency")
			local ok, err = pcall(M.ManaCosts, raidPoint({ serpentTick = 100 }))
			T.eq(ok, false, "a Serpent Sting tick that is not IX's")
			T.truthy(tostring(err):find("p.serpentTick is Serpent Sting IX's 135 or nil", 1, true), tostring(err))
		end },
		-- The casts of a state of the raid fight (raid-mode design 6.1: partsAndHits' casts, the mana spend's reader): every
		-- cast by action with its landed hits and the crit chance of a landed ability hit, and the landed hits that cost
		-- nothing. They are the landed hits' counts by another cut: the turret's Arcane, Aimed and the dives (which always land)
		-- are its ranged specials, Serpent Sting's landed applications its ranged casts and its casts those over the shots' hit
		-- (6.4); the weave's Raptor Strike, Strider Kick, Mongoose Bite and Wing Clip its main hand's specials, Arcane Shot and
		-- Multi-Shot its ranged specials; the free hits the Auto Shots and the white swings. The ability crit is the suppressed
		-- crit of the shots (10% at the raid point: 10 - 3 - 1.8 = 5.2%) and of the melee abilities (Savage Strikes' 2% a rank on
		-- top, all aura crit: 12 - 3 - 1.8 = 7.2% at rank 1; my arithmetic)
		{ "raid casts: each state's casts by action agree with its landed hits; free hits the Auto Shots and white swings; the ability crits", function()
			local f = M.Fight(raidPoint({ hit = 4 }))
			for _, s in ipairs(f.states) do
				local a, h = s.casts.acts, s.hits
				T.near(a.arcane.landed + a.aimed.landed + a.hawk.landed, h.ranged.specials, 1e-12, "the turret's ranged specials")
				T.near(a.hawk.landed, a.hawk.casts, 1e-15, "the dives always land")
				T.near(a.arcane.landed, a.arcane.casts * 0.96, 1e-15, "Arcane Shot lands with the shots' hit")
				T.near(a.serpent.landed, h.ranged.casts, 1e-15, "Serpent Sting's landed applications")
				T.near(a.serpent.casts, h.ranged.casts / 0.96, 1e-12, "Serpent Sting's casts over the shots' hit")
				T.eq(a.serpent.crit, nil, "no ability crit on Serpent Sting's application")
				T.near(a.aimed.crit, 0.052, 1e-12, "the shots' suppressed crit")
				T.near(a.arcane.crit, 0.052, 1e-12, "Arcane Shot at the shots' crit")
				T.near(a.hawk.crit, 0.052, 1e-12, "the dive at the ranged crit")
				T.near(s.casts.free, h.ranged.swings, 1e-15, "the turret's free hits: the Auto Shots")
				T.eq(a.raptor, nil, "no melee outside the Survival branch")
			end
			local fw = M.Fight(raidPoint({ survival = true, hit = 4 }, { striderKick = 1, exposePrey = 2, savageStrikes = 1 }))
			for _, s in ipairs(fw.states) do
				local a, h = s.casts.acts, s.hits
				T.near(a.raptor.landed + a.strider.landed + a.bite.landed + a.wingClip.landed, h.mh.specials, 1e-12, "the weave's main-hand specials")
				T.near(a.arcane.landed + a.multi.landed, h.ranged.specials, 1e-12, "the weave's ranged specials")
				T.near(a.serpent.landed, h.ranged.casts, 1e-15, "the weave's Serpent Sting")
				T.near(s.casts.free, h.mh.swings + h.oh.swings + h.ranged.swings, 1e-12, "the weave's free hits")
				for _, k in ipairs({ "raptor", "strider", "bite", "wingClip" }) do
					T.near(a[k].crit, 0.072, 1e-12, k .. ": the melee abilities' crit with Savage Strikes 1")
				end
				T.near(a.multi.crit, 0.052, 1e-12, "Multi-Shot at the shots' crit")
				T.near(a.arcane.crit, 0.052, 1e-12, "Arcane Shot at the shots' crit")
				T.eq(a.trap.crit, nil, "no ability crit on the trap's application")
				T.eq(a.serpent.crit, nil, "no ability crit on Serpent Sting's application")
				local w = s.weave.average.rates
				T.near(a.raptor.casts, w.raptor, 1e-15); T.near(a.trap.casts, w.trap, 1e-15); T.near(a.serpent.casts, w.serpent, 1e-15)
				if s.regime == "rich" then T.near(a.raptor.white * w.mhWhite, h.mh.swings, 1e-12, "a white swing lands as the main hand's do") end
				if a.trap.casts > 0 then T.truthy(a.trap.landed < a.trap.casts, "the trap's application misses as a spell") end
			end
			-- a slow main hand (3.8 s) keeps the hunter in melee for a 1.8 s off hand to swing (weaveParts shareOH): its white
			-- swings are free landed hits too
			local fd = M.Fight(raidPoint({ survival = true, hit = 4, mhSpeed = 3.8, ohSpeed = 1.8 }, { striderKick = 1, exposePrey = 2, savageStrikes = 1 }))
			T.truthy(fd.segments[1].state.hits.oh.swings > 0.05, "the off hand swings")
			for _, s in ipairs(fd.states) do
				local h = s.hits
				T.near(s.casts.free, h.mh.swings + h.oh.swings + h.ranged.swings, 1e-12, "the off hand's swings among the free hits")
			end
		end },
		-- The mana flow of a state of the raid fight (raid-mode design 7.5, 5.3; O7 = (a)): it spends S = the sum of each cast
		-- a second times its cost (Model.ManaCosts), a missed cast paying too; Judgement of Wisdom gives 59 mana at 50% a landed
		-- hunter hit, 29.5 a hit: every landed hit of the hunter's own hands (Model.LandedHits' counts: the Auto Shots, the white
		-- swings, the specials, the dives, Serpent Sting's landed applications) and, in the weave, Immolation Trap's landed
		-- applications (a harmful spell, ProcFlags 0x20000 TAKE_HARMFUL_SPELL); none for the pet and the hawks (no mana bar);
		-- the net drain D = S - rc - J. The design's example (7.5, my arithmetic there): the shots' speed 1.15 (quiver 15%, no
		-- Quick Shots), a 3.0 s bow, no hit at +3 (q = 0.08), regen 7.5 a second in the casts: landed hunter hits 0.678 a second
		-- (Auto 0.353, Aimed 0.109, Arcane 0.048, Serpent Sting 0.063, the dives 0.105), J = 20.0, S = 82.4 (the HHA elements 29.8,
		-- Serpent 15.8, Aimed 36.9; the hotfix's 11% here 189, not 189.2), D = 54.9
		{ "raid JoW and spend: S the casts at their costs, J 29.5 a landed hunter hit with Serpent's and the trap's applications, D = S - rc - J; the design's example", function()
			for _, case in ipairs({ { raidPoint({ hit = 4 }), false }, { raidPoint({ survival = true, hit = 4 }, { striderKick = 1, exposePrey = 2 }), true } }) do
				local f = M.Fight(case[1])
				local costs = M.ManaCosts(case[1])
				for _, s in ipairs(f.states) do
					local S = 0
					for name, a in pairs(s.casts.acts) do S = S + a.casts * costs[name] end
					local h = s.hits
					local landed = h.mh.swings + h.mh.specials + h.oh.swings + h.ranged.swings + h.ranged.specials + h.ranged.casts
					if case[2] then
						if s.regime == "rich" then T.truthy(s.casts.acts.trap.landed > 0, "the weave places the trap") end
						landed = landed + s.casts.acts.trap.landed
					end
					T.near(s.mana.S, S, 1e-9, "the spend")
					T.near(s.mana.J, 29.5 * landed, 1e-9, "29.5 a landed hunter hit")
					T.near(s.mana.D, s.mana.S - s.mana.rc - s.mana.J, 1e-12, "the net drain")
				end
			end
			local f = M.Fight(raidPoint({ quiver = 0.15, bowSpeed = 3.0, hit = 0 }, { deadlyAspects = 0 }))
			local m = f.segments[1].state.mana -- 0-5 s: no cooldown, the pool full
			T.near(m.landed, 0.678, 0.0005, "the design's landed hunter hits")
			T.near(m.J, 20.0, 0.05, "the design's Judgement of Wisdom income")
			T.near(m.S, 82.4, 0.1, "the design's spend")
			T.near(m.rc, 7.5, 1e-12, "no in-combat share past Bestial Discipline's: the live casting regen")
			T.near(m.D, 54.9, 0.1, "the design's net drain")
		end },
		-- The casting regen of a state of the raid fight (raid-mode design 7.3): the live casting regen (Bestial Discipline's
		-- share in it) plus the shares that come in combat, min(1 - 0.25 x Bestial Discipline, 0.25 x Rapid Recuperation x U +
		-- 0.5 x resUp) of the Spirit regen 6.25 + Spirit / 8 (70 Spirit at the raid point: 15 a second); U Serpent Sting's uptime
		-- (15 s x its landed applications), resUp Resourcefulness' buff uptime from the state's own landed ability hits and
		-- their crits, 1 - prod (1 - 0.5 x rank x crit)^(30 x landed) (not the levelling estimate CONST.resourcefulnessUptime)
		{ "raid regen: rc = regenCast + min(1 - 0.25 BD, 0.25 RR U + 0.5 resUp) x (6.25 + Spirit / 8); resUp from the state's ability crits", function()
			local function check(over, tover, name)
				local p = raidPoint(over, tover)
				local f = M.Fight(p)
				for _, s in ipairs(f.states) do
					local noBuff = 1
					for _, a in pairs(s.casts.acts) do
						if a.crit then noBuff = noBuff * (1 - 0.5 * p.tal.resourcefulness * a.crit) ^ (30 * a.landed) end
					end
					local U = 15 * s.hits.ranged.casts
					local share = math.min(1 - 0.25 * p.tal.bestialDiscipline, 0.25 * p.tal.rapidRecuperation * U + 0.5 * (1 - noBuff))
					T.near(s.mana.resUp, 1 - noBuff, 1e-12, name .. ": resUp")
					T.near(s.mana.U, U, 1e-12, name .. ": U")
					T.near(s.mana.rc, p.regenCast + share * (6.25 + p.spirit / 8), 1e-12, name .. ": rc")
				end
				return f
			end
			local f1 = check({}, { bestialDiscipline = 0, rapidRecuperation = 1, resourcefulness = 1 }, "the turret, RR 1, Res 1")
			-- below the hit cap a Serpent Sting cast can miss: U counts its landed applications, not its casts
			local fh = check({ hit = 0 }, { bestialDiscipline = 0, rapidRecuperation = 2 }, "hit 0, RR 2")
			for _, s in ipairs(fh.states) do
				local x = s.casts.acts.serpent
				if x.landed > 0 then T.truthy(x.casts > 1.05 * x.landed, "hit 0: more casts than landed applications") end
			end
			local m1 = f1.segments[1].state.mana -- 0-5 s: no cooldown, the pool full
			-- about 0.27 landed ability hits a second (Aimed, Arcane, the dives) at 5.2% crit and 50%: 1 - (1 - 0.026)^8 = 0.19 (my
			-- arithmetic)
			T.truthy(m1.resUp > 0.15 and m1.resUp < 0.25, "Resourcefulness' uptime from the ability crits: " .. m1.resUp)
			T.truthy(m1.rc > 7.5 + 0.25 * 0.9 * 15, "the in-combat shares above the live regen")
			-- more crit, a higher uptime of the buff
			local m2 = check({ crit = 14, meleeCrit = 14 }, { bestialDiscipline = 0, resourcefulness = 1 }, "crit 14").segments[1].state.mana
			local m0 = check({}, { bestialDiscipline = 0, resourcefulness = 1 }, "crit 10").segments[1].state.mana
			T.truthy(m2.resUp > m0.resUp + 1e-3, "more crit, more Resourcefulness")
			-- Bestial Discipline 2/2 leaves half for the rest: Rapid Recuperation 2/2 and Resourcefulness 2/2 capped there
			local fc = check({}, { bestialDiscipline = 2, rapidRecuperation = 2, resourcefulness = 2 }, "capped")
			for _, s in ipairs(fc.states) do
				if s.regime == "rich" then T.near(s.mana.rc, 7.5 + 0.5 * 15, 1e-12, "the cap at the whole") end
			end
			-- the weave: its melee abilities' crits with Savage Strikes reach Resourcefulness too
			check({ survival = true }, { striderKick = 1, exposePrey = 2, savageStrikes = 2, resourcefulness = 2, bestialDiscipline = 0 }, "the weave")
		end },
		-- The mana's walk through the raid fight (raid-mode design 7.6): the pool full at 0 s; in the rich regime the mana moves at
		-- -D (each state's net drain) and is held at the pool where the regen and Judgement of Wisdom pay the casts (D < 0); the
		-- one-off costs come off at their instants, Rapid Fire's 100 and Bestial Wrath's 206 (12% of 1720, rounded) at 5 s and
		-- Hunter's Mark's 60 at 98 s; the mana at 0 turns the regime starved, so a pool of 150 runs out at 150 / D before 5 s. The
		-- walks below run on a pool of 1500, under which neither the rune (1500 and 5 s of the casting regen) nor the mana potion
		-- (2250 and that) fits: the costs alone move the mana
		{ "raid mana: never out of mana when the regen pays the casts; else out at m / D; Rapid Fire and Bestial Wrath at 5 s, Hunter's Mark at 98 s", function()
			local fr = M.Fight(richPoint({}))
			T.eq(#fr.oom, 0, "the regen pays the casts: the mana never runs out")
			for _, s in ipairs(fr.segments) do
				T.eq(s.state.regime, "rich", "rich all fight")
				T.eq(s.m1, 4000, "held at the pool, " .. s.t0 .. " s")
			end
			local f0 = M.Fight(raidPoint({ manaMax = 150 }))
			T.near(f0.oom[1], 150 / f0.segments[1].state.mana.D, 1e-9, "a pool of 150 out at 150 / D")
			for _, case in ipairs({ { { manaMax = 1500 }, "a pool of 1500" }, { { manaMax = 1500, regenCast = 47 }, "regen 47 in the casts" } }) do
				local f = M.Fight(raidPoint(case[1]))
				local segs, name = f.segments, case[2]
				T.eq(#f.runes, 0, name .. ": no rune fits"); T.eq(f.manaPotion, nil, name .. ": no mana potion fits")
				T.near(segs[1].m1, 1500 - 5 * segs[1].state.mana.D, 1e-9, name .. ": 0-5 s at -D")
				T.eq(segs[2].t0, 5)
				T.near(segs[2].m0, segs[1].m1 - 100 - 206, 1e-9, name .. ": Rapid Fire's 100 and Bestial Wrath's 206 at 5 s")
				local last
				for i, s in ipairs(segs) do
					if s.state.regime == "rich" then
						T.near(s.m1, s.m0 - s.state.mana.D * (s.t1 - s.t0), 1e-9, name .. ": at -D, " .. s.t0 .. " s")
						last = s
					end
					if i > 1 and s.t0 == 98 and segs[i - 1].state.regime == "rich" then
						T.near(s.m0, segs[i - 1].m1 - 60, 1e-9, name .. ": Hunter's Mark's 60 at 98 s")
					elseif i > 1 and s.t0 ~= 5 and s.state.regime == "rich" and segs[i - 1].state.regime == "rich" then
						T.near(s.m0, segs[i - 1].m1, 1e-9, name .. ": no cost at " .. s.t0 .. " s")
					end
				end
				T.near(last.m1, 0, 1e-9, name .. ": the last rich stretch ends at 0")
				T.near(f.oom[1], last.t1, 1e-12, name .. ": out of mana there")
			end
			-- regen 47: out of mana after Hunter's Mark, which the pool paid
			T.truthy(M.Fight(raidPoint({ manaMax = 1500, regenCast = 47 })).oom[1] > 98, "regen 47: out after 98 s")
		end },
		-- The starved regime's income (raid-mode design 7.5): the hunter casts one element (an HHA element, Summon Hawk or Arcane
		-- Shot, 189 mana: 11% of 1720) as soon as it can pay it; the element returns Judgement of Wisdom's 29.5 a landed hit (the
		-- dives always, Arcane Shot at the shots' hit), so its net cost c = 189 - 29.5 x its landed share; the regen is the
		-- casting one g1 = rc + J_a for 5 s after the spend and g2 = regenRest + J_a after it, J_a = 29.5 x the free landed hits
		-- (the Auto Shots), so I = g1 where c <= 5 g1 and c / (5 + (c - 5 g1) / g2) above it (my arithmetic, the design's T).
		-- The raid point (regen 7.5 / 15: the cycle's branch) and regen 25 in the casts on a pool of 1000, which neither the rune nor
		-- the mana potion fits under (c below 5 g1: I = g1). Hunter's Mark at
		-- 98 s in the starved regime is a debt the income repays before any cast: 60 / I s with no cast bought
		{ "raid mana: the starved income by the five-second rule's cycle, both branches, Judgement of Wisdom in it; Hunter's Mark a debt", function()
			-- a starved state's rich pass (Model fight: its state's casts at their whole rates)
			local function richOf(_, s) return s.rich end
			local branches = {}
			-- with Rapid Recuperation and Resourcefulness the starved casting regen follows the shares bought (Serpent Sting's,
			-- the ability crits'), which the income sets: the state's own rc at its shares
			for _, case in ipairs({ { {}, "the raid point" }, { { manaMax = 1000, regenCast = 25 }, "regen 25" },
				{ {}, "Rapid Recuperation and Resourcefulness", { bestialDiscipline = 0, rapidRecuperation = 2, resourcefulness = 2 } } }) do
				local p = raidPoint(case[1], case[3])
				local f = M.Fight(p)
				local seen = 0
				for _, s in ipairs(f.states) do
					if s.regime == "starved" then
						local r = richOf(f, s)
						local a = r.casts.acts
						local casts = a.hawk.casts + a.arcane.casts
						local c = (casts * 189 - 29.5 * (a.hawk.landed + a.arcane.landed)) / casts
						local Ja = 29.5 * s.casts.free
						T.near(s.casts.free, r.casts.free, 1e-15, "the turret's free hits, the Auto Shots, go on")
						local g1, g2 = s.mana.rc + Ja, p.regenRest + Ja
						local I
						if c <= 5 * g1 then I = g1; branches.g1 = true else I = c / (5 + (c - 5 * g1) / g2); branches.cycle = true end
						T.near(s.income, I, 1e-9, case[2] .. ": the income, " .. s.phase)
						seen = seen + 1
					end
				end
				T.truthy(seen > 0, case[2] .. ": out of mana in the fight")
			end
			T.truthy(branches.g1 and branches.cycle, "both branches")
			-- the debt: out of mana before 98 s on a pool of 1500 (no rune, no mana potion), Hunter's Mark's 60 repaid in 60 / I
			-- with no cast; at the raid point the pool holds 51.3 at 98 s (the rune at 25.8 s), and the 8.7 short is the debt
			for _, case in ipairs({ { 1500, false }, { 4000, true } }) do
				local f = M.Fight(raidPoint({ manaMax = case[1] }))
				local found
				for i, s in ipairs(f.segments) do
					if s.t0 == 98 then
						found = true
						local prev = f.segments[i - 1]
						local owed = 60 - (prev.state.regime == "rich" and prev.m1 or 0)
						T.eq(prev.state.regime == "rich", case[2], "rich up to 98 s on a pool of " .. case[1])
						T.truthy(owed > 0, "something owed")
						T.eq(s.state.phase, "debt", "a debt from 98 s")
						T.near(s.t1 - s.t0, owed / s.state.income, 1e-9, "repaid in what is owed / I, a pool of " .. case[1])
						T.eq(s.m0, 0, "the pool empty")
						if case[2] then T.near(f.oom[1], 98, 1e-12, "the mana runs out at Hunter's Mark's cost") end
					end
				end
				T.truthy(found, "a segment from 98 s")
			end
			local f = M.Fight(raidPoint({ manaMax = 1500 }))
			for i, s in ipairs(f.segments) do
				if s.t0 == 98 then
					for name, v in pairs(s.state.shares) do T.eq(v, 0, "no cast while the debt runs: " .. name) end
					T.eq(s.state.out.aimed + s.state.out.arcane + s.state.out.serpent + s.state.out.dive, 0, "no cast's damage")
					T.truthy(s.state.out.auto > 0 and s.state.out.pet > 0, "the Auto Shots and the pet go on")
					T.eq(f.segments[i + 1].state.phase, "buy", "the casts after it")
				end
			end
		end },
		-- The starved regime buys cheapest ready first (raid-mode design 7.5): with mana rising from 0 the first ready action
		-- the mana reaches goes; each cast group at min(1, what is left / its whole net spend), the net spend of its casts at their
		-- costs less 29.5 a landed hit of its own. The raid point with a pool of 1500 (no rune, no mana potion fits) and regen 300
		-- out of the five-second rule: the HHA elements
		-- (189 each) whole, Serpent Sting (230) at the rest, Aimed Shot (310) none; from 125 s the second Bestial Wrath (206)
		-- comes before Serpent Sting and takes what the HHA elements leave until it is bought, at 125 + 206 / that rate, and
		-- Serpent Sting buys again after it; with Efficiency 5/5 Serpent Sting costs 195.5, under the Bestial Wrath's 206, and
		-- keeps its share from 125 s
		{ "raid mana: cheapest ready first: the HHA elements, the second Bestial Wrath, Serpent Sting, Aimed Shot; the second Bestial Wrath waits for the income", function()
			local function full(acts, names, cost)
				local spend, landed = 0, 0
				for _, n in ipairs(names) do spend, landed = spend + acts[n].casts * cost, landed + acts[n].landed end
				return spend - 29.5 * landed
			end
			local f = M.Fight(raidPoint({ manaMax = 1500, regenRest = 300 }))
			local rich = f.segments[1].state.casts.acts
			local before, wrathSeg, after
			for _, s in ipairs(f.segments) do
				if s.state.phase == "buy" and s.t1 <= 125 then before = s end
				if s.state.phase == "wrath" then wrathSeg = wrathSeg or s end
				if s.state.phase == "buy" and s.t0 > 125 then after = after or s end
			end
			local hha, serp = full(rich, { "hawk", "arcane" }, 189), full(rich, { "serpent" }, 230)
			local b = before.state
			T.eq(b.shares.hha, 1, "the HHA elements whole")
			T.near(b.shares.serpent, (b.income - hha) / serp, 1e-9, "Serpent Sting at the rest")
			T.truthy(b.shares.serpent > 0 and b.shares.serpent < 1, "Serpent Sting in part")
			T.eq(b.shares.aimed, 0, "Aimed Shot none")
			local w = wrathSeg.state
			T.eq(w.shares.hha, 1); T.eq(w.shares.serpent, 0, "Serpent Sting waits for the Bestial Wrath")
			T.near(w.wrathRate, w.income - hha, 1e-9, "the Bestial Wrath takes what the HHA elements leave")
			T.eq(wrathSeg.t0, 125)
			T.near(f.bestialWrath[2][1], 125 + 206 / w.wrathRate, 1e-9, "the second Bestial Wrath once bought")
			T.near(f.bestialWrath[2][2], f.bestialWrath[2][1] + 18, 1e-9)
			T.truthy(after and after.state.shares.serpent > 0, "Serpent Sting again after it")
			-- what the income saved for it carries over a change of state: a Use buff of 10 MP5 125-145 s (2 mana a second more), so
			-- the saving runs at one rate to 145 s and at another after it (my arithmetic: 145 + (206 - 20 x the first) / the second)
			local fu = M.Fight(raidPoint({ manaMax = 1500, regenRest = 300, uses = { { spell = 3, stats = { MP5 = 10 }, duration = 20, cooldown = 120 } } }))
			local r1, r2
			for _, s in ipairs(fu.segments) do
				if s.state.phase == "wrath" and s.t0 == 125 then r1 = s.state.wrathRate; T.eq(s.t1, 145) end
				if s.state.phase == "wrath" and s.t0 == 145 then r2 = s.state.wrathRate end
			end
			T.truthy(r1 and r2 and r1 ~= r2, "two saving rates")
			T.near(fu.bestialWrath[2][1], 145 + (206 - 20 * r1) / r2, 1e-9, "the saving carried over 145 s")
			-- Efficiency 5/5: Serpent Sting 195.5 before the Bestial Wrath's 206 (its cost not cut)
			local fe = M.Fight(raidPoint({ manaMax = 1500, regenRest = 300 }, { efficiency = 5 }))
			for _, s in ipairs(fe.segments) do
				if s.state.phase == "wrath" then
					T.truthy(s.state.shares.serpent > 0, "Efficiency: Serpent Sting before the Bestial Wrath")
					T.eq(s.state.shares.aimed, 0, "Aimed Shot after it")
				end
			end
			-- without the income for it, the second Bestial Wrath never comes: the starved income on a pool of 1500 is all the HHA
			-- elements', none left
			T.eq(#M.Fight(raidPoint({ manaMax = 1500 })).bestialWrath, 1, "one Bestial Wrath")
			-- rich at 125 s with the mana for it: at 125 s (regen 40 in the casts)
			local f25 = M.Fight(raidPoint({ regenCast = 40 }))
			T.eq(f25.bestialWrath[2][1], 125, "rich: the second Bestial Wrath at 125 s")
		end },
		-- What the starved shares do to the casts (raid-mode design 6.4, 6.5, 7.8): each cast at its share of its rate, its
		-- damage, landed hits and casts with it; the hawks' uptime min(1, 9 x the dives a second) below the whole share (each
		-- summon keeps a hawk 18 s, two hawks), min(1, 18 / C) at it; the Auto Shots and the pet go on. The raid point with regen
		-- 300 out of the five-second rule (Serpent Sting in part) and the raid point (the HHA elements in part)
		{ "raid starved: a share scales its casts' damage, landed hits and casts; the hawks at min(1, 9 rH) below the whole share; the Auto Shots and the pet go on", function()
			for _, over in ipairs({ { regenRest = 300 }, {} }) do
				local f = M.Fight(raidPoint(over))
				local r = f.segments[1].state
				for _, s in ipairs(f.states) do
					if s.regime == "starved" and s.phase ~= "debt" and not s.rf and not s.bw and #s.uses == 0 then
						local sh = s.shares
						T.near(s.out.serpent, sh.serpent * r.out.serpent, 1e-9, "Serpent Sting's damage")
						T.near(s.hits.ranged.casts, sh.serpent * r.hits.ranged.casts, 1e-12, "its landed applications")
						T.near(s.tempo.serpentCasts, sh.serpent * r.tempo.serpentCasts, 1e-12, "its casts")
						T.near(s.tempo.serpentUptime, sh.serpent * r.tempo.serpentUptime, 1e-12, "its uptime")
						T.near(s.out.arcane, sh.hha * r.out.arcane, 1e-9, "Arcane Shot")
						T.near(s.out.dive, sh.hha * r.out.dive, 1e-9, "the dives")
						T.near(s.out.aimed, sh.aimed * r.out.aimed, 1e-9, "Aimed Shot")
						local rH = 2 / r.tempo.hhaCycle * sh.hha
						local up = sh.hha < 1 and math.min(1, 9 * rH) or r.tempo.hawkUptime
						T.near(s.tempo.hawkUptime, up, 1e-12, "the hawks' uptime")
						T.near(s.out.hawks, r.out.hawks * up / r.tempo.hawkUptime, 1e-9, "the hawks' damage")
						T.near(s.out.auto, r.out.auto, 1e-12, "the Auto Shots go on")
						T.near(s.out.pet, r.out.pet, 1e-12, "the pet goes on")
					end
				end
			end
		end },
		-- The starved income solves I = F(I), F(I) the income at the shares I buys (raid-mode design 7.5, 20.5): F by hand for
		-- the turret below (each group's net spend at its costs less 29.5 a landed hit, cheapest first; rc at the shares bought,
		-- Rapid Recuperation's U = 15 x the landed applications x Serpent Sting's share under the cap 1 - 0.25 x Bestial
		-- Discipline; J_a of the Auto Shots; the HHA element's cycle). With Rapid Recuperation 2/2 and Spirit 152 F rises 0.86 mana
		-- a second a mana a second of income in the Serpent Sting part (its share raises the regen), so the iteration from the
		-- rich rc closes in by 0.86 a step and 100 steps do not reach 1e-12 (my arithmetic); at Spirit 200 F rises faster than I there up to the
		-- cap, and I = F(I) has three roots: the income is the highest (the iteration's limit: Serpent Sting bought whole, its
		-- regen paying it, Aimed Shot in part), none above it, the lowest under 25 with the HHA elements in part. With
		-- Resourcefulness 2/2 at Spirit 230 the in-combat share reaches its cap 0.5 inside the Serpent Sting part and F stops
		-- rising there: F lies under I at both ends of that part and above it between them, the high root there
		{ "raid starved: the income is the largest root of I = F(I); Rapid Recuperation's feedback, three roots at Spirit 200", function()
			local function oracle(p, s)
				local a, costs, tal = s.rich.casts.acts, M.ManaCosts(p), p.tal
				local items = {}
				for _, g in ipairs({ { "hha", { "hawk", "arcane" } }, { "serpent", { "serpent" } }, { "aimed", { "aimed" } } }) do
					local casts, spend, landed = 0, 0, 0
					for _, n in ipairs(g[2]) do casts, spend, landed = casts + a[n].casts, spend + a[n].casts * costs[n], landed + a[n].landed end
					items[#items + 1] = { name = g[1], gross = spend / casts, full = spend - 29.5 * landed, casts = casts }
				end
				T.truthy(items[1].gross < items[2].gross and items[2].gross < items[3].gross, "HHA, Serpent Sting, Aimed Shot by cost")
				local c = items[1].full / items[1].casts
				local function sharesAt(I)
					local sh, rem = {}, I
					for _, it in ipairs(items) do
						if rem >= it.full then sh[it.name], rem = 1, rem - it.full else sh[it.name], rem = rem / it.full, 0 end
					end
					return sh
				end
				local function F(I)
					local sh = sharesAt(I)
					local group = { hawk = sh.hha, arcane = sh.hha, serpent = sh.serpent, aimed = sh.aimed }
					local noBuff = 1
					for n, x in pairs(a) do
						if x.crit then noBuff = noBuff * (1 - 0.5 * tal.resourcefulness * x.crit) ^ (30 * x.landed * group[n]) end
					end
					local U = 15 * a.serpent.landed * sh.serpent
					local share = math.min(1 - 0.25 * tal.bestialDiscipline, 0.25 * tal.rapidRecuperation * U + 0.5 * (1 - noBuff))
					local Ja = 29.5 * s.rich.casts.free
					local g1, g2 = p.regenCast + share * (6.25 + p.spirit / 8) + Ja, p.regenRest + Ja
					return c <= 5 * g1 and g1 or c / (5 + (c - 5 * g1) / g2)
				end
				return F, sharesAt, items
			end
			local function firstBuy(f)
				for _, sg in ipairs(f.segments) do
					local s = sg.state
					if s.phase == "buy" and not s.rf and not s.bw and #s.uses == 0 then return s end
				end
			end
			local p = raidPoint({ spirit = 152, regenCast = 12, regenRest = 22, manaMax = 2400, serpentTick = 135 }, { rapidRecuperation = 2 })
			local ok, f = pcall(M.Fight, p)
			T.truthy(ok, "the fight runs: " .. tostring(not ok and f))
			local s = firstBuy(f)
			local F, sharesAt = oracle(p, s)
			T.near(F(s.income), s.income, 1e-9, "I = F(I)")
			T.near(s.shares.serpent, sharesAt(s.income).serpent, 1e-9, "the shares the income buys")
			T.truthy(s.shares.serpent > 0 and s.shares.serpent < 1, "Serpent Sting in part")
			local slope = (F(s.income + 1e-4) - F(s.income - 1e-4)) / 2e-4
			T.truthy(slope > 0.85 and slope < 0.87, "F rises 0.86 a step: " .. slope)
			local p3 = raidPoint({ spirit = 200, regenCast = 10, regenRest = 10, manaMax = 1725, serpentTick = 135 }, { rapidRecuperation = 2 })
			local s3 = firstBuy(M.Fight(p3))
			local F3, sharesAt3 = oracle(p3, s3)
			local I = s3.income
			T.near(F3(I), I, 1e-9, "I = F(I) at Spirit 200")
			T.truthy(s3.shares.hha == 1 and s3.shares.serpent == 1 and s3.shares.aimed > 0 and s3.shares.aimed < 1, "the high root: Aimed Shot in part")
			for k = 1, 600 do
				local x = I + k * 0.05
				T.truthy(F3(x) < x, "no root above the income: " .. x)
			end
			local below = 0
			for k = 1, 400 do
				local x = I * k / 400
				if F3(x) < x then below = below + 1 end
			end
			T.truthy(below > 0 and F3(0) > 0, "F below I somewhere under the income and above it at 0: two more roots")
			T.truthy(F3(20) > 20 and F3(25) < 25 and sharesAt3(25).hha < 1, "the low root between 20 and 25, the HHA elements in part")
			local p4 = raidPoint({ spirit = 230, regenCast = 6, regenRest = 10, manaMax = 1725, serpentTick = 135 }, { rapidRecuperation = 2, resourcefulness = 2 })
			local s4 = firstBuy(M.Fight(p4))
			local F4, _, items4 = oracle(p4, s4)
			local lo4, hi4 = items4[1].full, items4[1].full + items4[2].full
			T.near(F4(s4.income), s4.income, 1e-9, "I = F(I) with the cap")
			T.truthy(s4.income > lo4 and s4.income < hi4 and s4.shares.hha == 1 and s4.shares.serpent > 0 and s4.shares.serpent < 1, "Serpent Sting in part")
			T.truthy(F4(lo4) < lo4 and F4(hi4) < hi4, "F under I at both ends of the Serpent Sting part")
			for k = 1, 600 do
				local x = s4.income + k * 0.05
				T.truthy(F4(x) < x, "no root above the income with the cap: " .. x)
			end
		end },
		-- The Survival weave in the starved regime (raid-mode design 7.5, 15.5): its casts cheapest first, Mongoose Bite 65,
		-- Wing Clip 80, Raptor Strike 100 before Strider Kick 100 (5.81% of 1720 rounded: one cost, the rotation's row first),
		-- Arcane Shot 189, Serpent Sting 230, Multi-Shot 239, Immolation Trap 245; the income's element Wing Clip (a melee weapon:
		-- the cheapest cast any melee look can make), its net cost 80 - 29.5 x its landed share; a main-hand swing Raptor Strike
		-- does not take is a white swing, a free landed hit for Judgement of Wisdom in J_a at the white table's landing (casts'
		-- white), so the state's own free hits feed its income and its own D is 0 where I = g1 (S - J = rc + J_a: the state
		-- spends what comes in); the cycle stays the rich one (approximation A2). Regen 7 out of the five-second rule and none in
		-- it, no Bestial Discipline: Raptor Strike in part; Hunter's Mark's debt at 98 s buys nothing, every Raptor Strike white
		{ "raid weave starved: cheapest first, Raptor Strike before Strider Kick at one cost; Wing Clip the income's element; a Raptor Strike not bought is a white swing", function()
			local p = raidPoint({ survival = true, regenRest = 7, regenCast = 0 }, { striderKick = 1, exposePrey = 2, bestialWrath = 0, bestialDiscipline = 0 })
			local f = M.Fight(p)
			local r = f.segments[1].state
			local a = r.casts.acts
			local function net(n, cost) return a[n].casts * cost - 29.5 * a[n].landed end
			local c = 80 - 29.5 * a.wingClip.landed / a.wingClip.casts
			local function income(s)
				local Ja = 29.5 * s.casts.free
				local g1, g2 = s.mana.rc + Ja, p.regenRest + Ja
				return c <= 5 * g1 and g1 or c / (5 + (c - 5 * g1) / g2), c <= 5 * g1
			end
			local wr = r.weave.average.rates
			local white = r.hits.mh.swings / wr.mhWhite
			T.near(a.raptor.white, white, 1e-12, "a white swing lands as the main hand's white swings do")
			T.truthy(white > 0.5 and white < 1, "past the white table's miss and dodge")
			local seen, debt = false, false
			for _, s in ipairs(f.states) do
				if s.phase == "buy" and not s.rf and #s.uses == 0 then
					seen = true
					local sh = s.shares
					T.eq(sh.bite, 1); T.eq(sh.wingClip, 1)
					T.near(sh.raptor, (s.income - net("bite", 65) - net("wingClip", 80)) / net("raptor", 100), 1e-9, "Raptor Strike at the rest")
					T.truthy(sh.raptor > 0 and sh.raptor < 1, "Raptor Strike in part")
					for _, k in ipairs({ "strider", "arcane", "serpent", "multi", "trap" }) do T.eq(sh[k], 0, k .. " none") end
					T.near(s.casts.free, r.casts.free + (1 - sh.raptor) * a.raptor.casts * white, 1e-12, "the free hits with the white swings")
					local I, g1 = income(s)
					T.near(s.income, I, 1e-9, "Wing Clip the element, J_a of the state's own free hits")
					T.truthy(g1, "the point's income is g1")
					T.near(s.mana.D, 0, 1e-9, "the state spends what comes in")
					local sr = s.weave.average.rates
					T.near(sr.raptor, sh.raptor * wr.raptor, 1e-12, "Raptor Strike at its share")
					T.near(sr.mhWhite, wr.mhWhite + (1 - sh.raptor) * wr.raptor, 1e-12, "the rest of its swings white")
					T.near(s.weave.base.C, r.weave.base.C, 1e-12, "the cycle stays")
					T.near(sr.auto, wr.auto, 1e-12, "the Auto Shots go on")
				elseif s.phase == "debt" and not s.rf and #s.uses == 0 then
					debt = true
					T.near(s.casts.free, r.casts.free + a.raptor.casts * white, 1e-12, "the debt: every Raptor Strike white")
					T.near(s.income, (income(s)), 1e-9, "the debt's income of its own free hits")
				end
			end
			T.truthy(seen, "a starved stretch"); T.truthy(debt, "a debt")
			for _, s in ipairs(f.states) do
				if s.phase == "buy" then
					T.eq(s.casts.acts.serpent.landed, 0, "no Serpent Sting bought: no landed application")
					T.eq(s.out.serpent, 0, "nor its damage"); T.eq(s.mana.U, 0, "nor its uptime")
				end
			end
			-- regen 40 in the casts (a pool of 1500: no rune, no mana potion): Serpent Sting in part, its casts, landed
			-- applications, damage and uptime at its share
			local f40 = M.Fight(raidPoint({ survival = true, regenRest = 7, regenCast = 40, manaMax = 1500 }, { striderKick = 1, exposePrey = 2, bestialWrath = 0, bestialDiscipline = 0 }))
			local r40, seen40 = f40.segments[1].state, false
			for _, s in ipairs(f40.states) do
				if s.phase == "buy" and not s.rf and #s.uses == 0 then
					seen40 = true
					local sh = s.shares.serpent
					T.truthy(sh > 0 and sh < 1, "Serpent Sting in part")
					T.near(s.casts.acts.serpent.landed, sh * r40.casts.acts.serpent.landed, 1e-12, "its landed applications at its share")
					T.near(s.casts.acts.serpent.casts, sh * r40.casts.acts.serpent.casts, 1e-12, "its casts at its share")
					T.near(s.out.serpent, sh * r40.out.serpent, 1e-9, "its damage at its share")
					T.near(s.mana.U, sh * r40.mana.U, 1e-12, "its uptime at its share")
				end
			end
			T.truthy(seen40, "regen 40: a starved stretch")
			-- the element where it decides the income: no Strider Kick, a 5.0 s main hand and a 3.0 s bow (few free hits), so
			-- Wing Clip's net cost lies above 5 g1 (the cycle's branch) and Mongoose Bite's below it (I = g1 there): the income
			-- is Wing Clip's cycle
			local pe = raidPoint({ survival = true, regenRest = 7, regenCast = 0, mhSpeed = 5.0, bowSpeed = 3.0, twoH = true, ohDPS = 0, manaMax = 1500 },
				{ striderKick = 0, exposePrey = 2, bestialWrath = 0, bestialDiscipline = 0 })
			local fe, seenE = M.Fight(pe), false
			for _, s in ipairs(fe.states) do
				if s.phase == "buy" and not s.rf and #s.uses == 0 then
					seenE = true
					local x = s.rich.casts.acts
					local cw = 80 - 29.5 * x.wingClip.landed / x.wingClip.casts
					local cb = 65 - 29.5 * x.bite.landed / x.bite.casts
					local Ja = 29.5 * s.casts.free
					local g1, g2 = s.mana.rc + Ja, pe.regenRest + Ja
					T.truthy(cw > 5 * g1 and cb < 5 * g1, "Wing Clip's cost in the cycle's branch, Mongoose Bite's not")
					T.near(s.income, cw / (5 + (cw - 5 * g1) / g2), 1e-9, "Wing Clip's cycle")
				end
			end
			T.truthy(seenE, "the element's point: a starved stretch")
		end },
		-- A Use buff's Intellect in the raid fight (raid-mode design 7.6 item 7): it raises the ceiling for its window (15 mana a
		-- point, Model.ApplyStats) and leaves the mana as it is; the mana rises to it where D < 0, and at the window's end it is
		-- held at the lower ceiling (wowsims sim/core/mana.go:116: a gain capped at the maximum). richPoint: the mana at the pool
		-- when a buff of 100 Intellect for 20 s from 5 s comes; a buff of MP5 1000 (200 a second) at 125 s turns a starved
		-- regime rich, the mana rising from 0 (a pool of 1500: no rune, no mana potion), and the second Bestial Wrath, ready at
		-- 125 s without its 206, fires when the mana rising at -D reaches 206, the mana at 0 after it (raid-mode design 20.1); a
		-- debt comes first: on a pool of 150 out of mana before 5 s, Rapid Fire's and Bestial Wrath's 306 at 5 s are a debt,
		-- repaid in 306 / I of the buff's state before the regime turns rich from 0
		{ "raid mana: an Intellect buff raises the ceiling in its window, the mana held at its end; a regen buff turns the starved regime rich", function()
			local use = { spell = 1, stats = { INT = 100 }, duration = 20, cooldown = 120 }
			local f = M.Fight(richPoint({ uses = { use } }))
			local inWin, afterWin
			for _, s in ipairs(f.segments) do
				if s.t0 == 5 then inWin = s end
				if s.t0 == 25 then afterWin = s end
			end
			T.eq(inWin.m0, 4000 - 306, "the buff leaves the mana: the pool less 5 s's costs")
			T.truthy(inWin.m1 > 4000, "the mana rises past the old pool in the window")
			T.truthy(inWin.m1 <= 5500, "up to the raised ceiling")
			T.eq(afterWin.m0, 4000, "held at the pool at the window's end")
			local mp5 = { spell = 2, stats = { MP5 = 1000 }, duration = 20, cooldown = 120 }
			local fm = M.Fight(raidPoint({ manaMax = 1500, uses = { mp5 } }))
			local at125
			for i, s in ipairs(fm.segments) do
				if s.t0 == 125 then at125 = s; T.eq(fm.segments[i - 1].state.regime, "starved", "starved before 125 s") end
			end
			T.eq(at125.state.regime, "rich", "the regen buff turns it rich")
			T.eq(at125.m0, 0, "from 0")
			T.truthy(at125.m1 > 0, "the mana rises")
			local D = at125.state.mana.D
			T.truthy(D < 0, "the buff's state pays its casts")
			T.near(fm.bestialWrath[2][1], 125 + 206 / -D, 1e-9, "the second Bestial Wrath when the mana reaches 206")
			T.near(at125.t1, fm.bestialWrath[2][1], 1e-12); T.near(at125.m1, 206, 1e-9)
			for _, s in ipairs(fm.segments) do
				if s.t0 == fm.bestialWrath[2][1] then T.eq(s.m0, 0, "its 206 paid") end
			end
			local fd = M.Fight(raidPoint({ manaMax = 150, uses = { { spell = 2, stats = { MP5 = 1000 }, duration = 20, cooldown = 120 } } }))
			T.truthy(fd.oom[1] < 5, "out of mana before 5 s")
			local at5, after
			for i, s in ipairs(fd.segments) do
				if s.t0 == 5 then at5, after = s, fd.segments[i + 1] end
			end
			T.eq(at5.state.regime, "starved"); T.eq(at5.state.phase, "debt", "the debt first, the buff's state paying its casts")
			T.truthy(at5.state.rich.mana.D < 0, "the buff's state pays its casts")
			T.near(at5.t1, 5 + 306 / at5.state.income, 1e-9, "306 repaid in 306 / I")
			T.eq(after.state.regime, "rich", "then rich"); T.eq(after.m0, 0, "from 0")
		end },
		-- The in-fight consumables of wowsims' preset (raid-mode design 7.4; the user's answer O2 = (a): always on, no input):
		-- the Major Frenzy Potion at 5 s for 30 s; the potions share category 4 for 120 s, so at 125 s the Major Mana Potion
		-- (+1800, its maximum 2250) goes if its 2250 fits under the ceiling after 5 s of the casting regen, else a second
		-- Frenzy Potion, and nothing more before 185 s. Starved at 125 s (the mana at 0) the room is the whole ceiling, the
		-- casting regen 7.5 (Bestial Discipline's share in the live regen, nothing more): the threshold 2250 + 37.5 = 2287.5 (my
		-- arithmetic), so a pool of 2288.5 takes the mana potion and one of 2286.5 the Frenzy Potion; the full pool at 125 s
		-- (richPoint) has no room; the raid point (starved at 125 s, a pool of 4000) the mana potion, then the second Bestial
		-- Wrath from its 1800
		{ "raid consumables (O2 = (a)): the Frenzy Potion at 5 s; the mana potion only at 125 s and only if its 2250 fits with 5 s of regen, else a second Frenzy Potion", function()
			local f = M.Fight(raidPoint({}))
			T.eq(windowsText(f.frenzyPotion), "5-35", "the Frenzy Potion at 5 s alone")
			T.eq(f.manaPotion, 125, "the mana potion at 125 s, not at its fit time")
			for i, s in ipairs(f.segments) do
				if s.t0 == 125 then
					T.eq(f.segments[i - 1].state.regime, "starved", "starved up to 125 s")
					T.eq(s.state.regime, "rich", "the mana potion turns it rich")
					T.near(s.m0, 1800 - 206, 1e-9, "1800, the second Bestial Wrath's 206 paid from it")
				end
			end
			T.eq(windowsText(f.bestialWrath), "5-23,125-143", "the second Bestial Wrath at 125 s")
			local fr = M.Fight(richPoint({}))
			T.eq(fr.manaPotion, nil, "the full pool: no room"); T.eq(windowsText(fr.frenzyPotion), "5-35,125-155", "a second Frenzy Potion")
			local fit, nofit = M.Fight(raidPoint({ manaMax = 2288.5 })), M.Fight(raidPoint({ manaMax = 2286.5 }))
			T.eq(fit.manaPotion, 125, "2288.5: room for 2250 and 5 s of regen")
			T.eq(windowsText(fit.frenzyPotion), "5-35", "no second Frenzy Potion with the mana potion")
			T.eq(nofit.manaPotion, nil, "2286.5: no room")
			-- the ceiling of the state up to 125 s (A17): on a pool of 2200 a buff of 20 Intellect (300 mana) up from 105 to 135 s
			-- makes room, one from 125 s does not
			local function intAt(cooldown) return { { spell = 5, stats = { INT = 20 }, duration = 30, cooldown = cooldown } } end
			T.eq(M.Fight(raidPoint({ manaMax = 2200, uses = intAt(100) })).manaPotion, 125, "an Intellect buff up before 125 s: room")
			T.eq(M.Fight(raidPoint({ manaMax = 2200, uses = intAt(120) })).manaPotion, nil, "one from 125 s: no room")
			T.eq(windowsText(nofit.frenzyPotion), "5-35,125-155", "the Frenzy Potion in its place")
			-- the Frenzy Potion's +80 attack power and ranged attack power: the shots and the hawks take it, the pet keeps its
			-- summon's (EV-0072, raid-mode design 7.4), as a Use buff's; richPoint's states 0-5 s (none) and 23-35 s (the potion)
			local s0, s1
			for _, s in ipairs(fr.segments) do
				if s.t0 == 0 then s0 = s.state end
				if s.t0 == 23 then s1 = s.state end
			end
			T.eq(#s0.uses, 0); T.eq(#s1.uses, 1, "23-35 s: the potion up")
			T.truthy(s1.out.auto > s0.out.auto and s1.out.hawks > s0.out.hawks, "the shots and the hawks take the potion")
			T.near(s1.out.pet, s0.out.pet, 1e-12, "the pet does not")
			-- always on: no input switches them (no p.raidConsumables)
			local p = raidPoint({})
			p.raidConsumables = false
			T.eq(M.Total(p), M.Total(raidPoint({})), "an input of that name changes nothing")
			T.eq(windowsText(M.Fight(p).frenzyPotion), "5-35", "the potion stays")
		end },
		-- The Demonic Rune (raid-mode design 7.4, 7.6): from 5 s, whenever its 1500 fits under the ceiling after 5 s of the
		-- casting regen, +1200, then again 120 s later. Rich, the mana falling at D reaches the ceiling less 1537.5: at the raid
		-- point 4000 - 1537.5 = 2462.5 (my arithmetic), then 120 s later; starved at 0 it fits at once once ready. A mana gain
		-- repays a debt first and the saving for the second Bestial Wrath joins it: on a pool of 2000 (the mana potion does not
		-- fit) with regen 300 out of the five-second rule, starved from 125 s with the saving at the rate of its stretch, the
		-- rune at 120 s after the first gives 1200 + the saving, from which the second Bestial Wrath fires at once
		{ "raid consumables: the rune at room = 1500 + 5 x regenCast, +1200, next 120 s later; a gain repays the debt and takes the saving", function()
			local f = M.Fight(raidPoint({}))
			T.eq(#f.runes, 2, "two runes")
			local r1 = f.runes[1]
			for i, s in ipairs(f.segments) do
				if s.t0 == r1 then
					T.near(f.segments[i - 1].m1, 4000 - 1500 - 5 * 7.5, 1e-9, "at the room of 1500 and 5 s of regen")
					T.near(s.m0, 4000 - 1500 - 5 * 7.5 + 1200, 1e-9, "+1200")
				end
			end
			T.near(f.runes[2], r1 + 120, 1e-9, "120 s later")
			-- a pool of 2000: starved at 125 s, the saving for the Bestial Wrath at its rate until the rune 120 s after the first
			local f2 = M.Fight(raidPoint({ manaMax = 2000, regenRest = 300 }))
			T.eq(f2.manaPotion, nil, "2000: no room for the mana potion")
			local rate, t2 = nil, f2.runes[2]
			for i, s in ipairs(f2.segments) do
				if s.t0 == 125 then rate = s.state.wrathRate; T.eq(s.state.phase, "wrath") end
				if s.t0 == t2 then
					T.eq(f2.segments[i - 1].state.regime, "starved", "starved when the rune is ready")
					T.near(s.m0, 1200 + rate * (t2 - 125) - 206, 1e-9, "1200 and the saving, less the second Bestial Wrath")
				end
			end
			T.near(t2, f2.runes[1] + 120, 1e-9, "ready 120 s after the first, at once when starved")
			T.near(f2.bestialWrath[2][1], t2, 1e-12, "the second Bestial Wrath with the rune")
			-- no room: a pool of 1500 takes no rune
			T.eq(#M.Fight(raidPoint({ manaMax = 1500 })).runes, 0, "1500: no room for 1500 and 5 s of regen")
			-- the debt first: a pool of 200 runs out before 5 s, so Rapid Fire's 100 and Bestial Wrath's 206 at 5 s are a debt;
			-- a Use buff of 100 Intellect from 5 s lifts the ceiling to 1700, where the rune fits at once: 1200 - 306 = 894
			local fd = M.Fight(raidPoint({ manaMax = 200, uses = { { spell = 4, stats = { INT = 100 }, duration = 20, cooldown = 120 } } }))
			T.truthy(fd.oom[1] < 5, "out of mana before 5 s")
			T.eq(fd.runes[1], 5, "the rune at 5 s")
			for _, s in ipairs(fd.segments) do
				if s.t0 == 5 then T.eq(s.state.regime, "rich"); T.near(s.m0, 1200 - 306, 1e-9, "the rune repays the debt first") end
			end
		end },
		-- The weights of the mana stats in raid mode (raid-mode design 6.9, 7.7; the user's answer 4 = (b)): each the derivative
		-- of the fight by its stat through Model.ApplyStats (INT, MP5, Spirit a step of 10, MANA of 100). The oracle of 7.7 (my
		-- arithmetic): one more point of mana in the pool moves the out-of-mana time by 1 / D, the fight's damage by (DPS_rich
		-- - DPS_starved) / D and the total (its damage over 180) by that over 180, while the time lies where the weight is 1 and
		-- no other event moves. On a pool of 2000 the rune fits at the same instant (its room shifts with the pool) and the mana
		-- runs out at 59 s, the next state change at 98 s; 2150 still takes no mana potion at 125 s (2287.5): W.MANA x unitDps
		-- = (DPS_rich - DPS_starved) / (180 x D) of the state then. An Intellect point is 15 mana of the pool and, with Careful
		-- Aim, 20% a rank of it as attack power: W.INT = 15 x W.MANA + 0.20 x rank x W.AP. MP5 and Spirit raise the regen:
		-- above 0 in raid mode; levelling prices the three at 0 and Intellect at Careful Aim's share of W.AP alone
		{ "raid weights: W.MANA x unitDps = (DPS_rich - DPS_starved) / (180 D); W.INT = 15 W.MANA + Careful Aim's attack power; W.SPI and W.MP5 above 0, levelling 0", function()
			for _, ca in ipairs({ 0, 5 }) do
				local p = raidPoint({ manaMax = 2000 }, { carefulAim = ca })
				local f = M.Fight(p)
				local rich, starved
				for i, s in ipairs(f.segments) do
					if s.t1 == f.oom[1] then rich, starved = s.state, f.segments[i + 1].state end
				end
				T.truthy(f.oom[1] > 40 and f.oom[1] < 90, "out of mana in a stretch of weight 1: " .. f.oom[1])
				local function dps(st) local x = 0 for _, v in pairs(st.out) do x = x + v end return x end
				local W, unitDps = M.Weights(p)
				T.near(W.MANA * unitDps, (dps(rich) - dps(starved)) / (180 * rich.mana.D), 1e-9, "the oracle of 7.7, Careful Aim " .. ca)
				-- with Careful Aim the two parts cross a little (the attack power raises the damage the mana buys, my arithmetic):
				-- exact without it
				T.near(W.INT, 15 * W.MANA + 0.20 * ca * W.AP, ca == 0 and 1e-9 or 0.01, "Intellect: 15 mana and Careful Aim " .. ca)
				T.truthy(W.MP5 > 0 and W.SPI > 0, "MP5 and Spirit raise the regen")
				T.truthy(W.MP5 > W.SPI, "a point of MP5 (1/5 a second in both regens) above Spirit's (1/8 out of the casts)")
			end
			local Wl = M.Weights(raidPoint({ mode = "level" }, { carefulAim = 5 }))
			T.eq(Wl.MANA, 0); T.eq(Wl.MP5, 0); T.eq(Wl.SPI, 0)
			T.near(Wl.INT, 0.20 * 5 * Wl.AP, 1e-12, "levelling: Careful Aim's share of W.AP alone")
			-- a pool the regen keeps full: no mana stat adds damage
			local Wr = M.Weights(richPoint({}))
			T.eq(Wr.MANA, 0, "the mana never runs out: no value"); T.eq(Wr.MP5, 0); T.eq(Wr.SPI, 0)
		end },
		-- The consumables' events held (raid-mode design 25.1): the fight decides the mana potion at 125 s and the rune by their
		-- fits (wowsims sim/common/shared/consumable_potion.go:257-266, 382-388: the maximum and 5 s of the casting regen under
		-- the ceiling); p.events holds them, { manaPotion, runes = the rune's times } (Model.FightEvents). At the raid point
		-- (regen 15 / 7.5) the rune fits from a pool of 1537.5 (1500 + 5 x 7.5) and the potion from 2287.5 (2250 + 5 x 7.5).
		-- A point with its own events held is its fight to the bit (no held decision differs); events of another point
		-- override the fits and mark the fight deviated; the k-th held rune that does not fit fires at 0 mana from its held
		-- time (the limit of its fit time as the fit closes on the ceiling): at the pool of 1540 with 2 mana a second more
		-- casting regen (its fit 1547.5 above the ceiling) at the instant the mana runs out (27.05 s, after the held 25.92 s),
		-- at the pool of 1537 at the held 25.92 s (the mana out at 25.91 s), at the pool of 1400 held at 100 s at 100 s; a rune
		-- the events do not hold never fires (1545 holding the events of 1535, none). Model.EventGain is the fight less the
		-- held fight, 0 with no deviation. p.events in levelling mode, or of another form, is an error
		{ "raid events: Model.FightEvents; a point's own events held are its fight; held events override the fits, a held rune fires at 0 mana from its time; Model.EventGain", function()
			local p80 = raidPoint({ manaMax = 2280 })
			local e80 = M.FightEvents(p80)
			T.eq(e80.manaPotion, false, "2280: no room for the potion"); T.eq(#e80.runes, 2)
			local h80 = {}
			for k, v in pairs(p80) do h80[k] = v end
			h80.events = e80
			T.eq(M.Total(h80), M.Total(p80), "its own events held: the same fight to the bit")
			T.eq(M.Fight(h80).deviated, false)
			T.eq(M.EventGain(p80, e80), 0, "no deviation: no change")
			-- the potion: 2300 fits it; held at the events of 2280 it does not fire, a second Frenzy Potion at 125 s
			local p30 = raidPoint({ manaMax = 2300 })
			T.eq(M.Fight(p30).manaPotion, 125)
			local h30 = {}
			for k, v in pairs(p30) do h30[k] = v end
			h30.events = e80
			local f30 = M.Fight(h30)
			T.eq(f30.manaPotion, nil, "held: no potion"); T.eq(f30.deviated, true); T.eq(f30.frenzyPotion[2][1], 125, "the second Frenzy Potion")
			local g = M.EventGain(p30, e80)
			T.near(g, M.Total(p30) - M.Total(h30), 1e-12, "the fight less the held fight"); T.truthy(g > 20, "the potion's 1800 mana: " .. g)
			-- and the other way: the potion held at 2280, where it does not fit
			local hp = {}
			for k, v in pairs(p80) do hp[k] = v end
			hp.events = { manaPotion = true, runes = e80.runes }
			local fp = M.Fight(hp)
			T.eq(fp.manaPotion, 125, "held: the potion fires"); T.eq(fp.deviated, true)
			-- the runes: 1540 takes two (25.92 and 145.92 s)
			local e40 = M.FightEvents(raidPoint({ manaMax = 1540 }))
			T.eq(#e40.runes, 2); T.near(e40.runes[1], 25.9177, 1e-4)
			local function heldAt(over, events)
				local q = raidPoint(over)
				local h = {}
				for k, v in pairs(q) do h[k] = v end
				h.events = events
				return q, h, M.Fight(h)
			end
			local q1, _, f1 = heldAt({ manaMax = 1540, regenCast = 9.5 }, e40)
			T.eq(#M.Fight(q1).runes, 0, "a casting regen of 9.5: the fit 1547.5 above the ceiling, no rune")
			T.eq(#f1.runes, 2, "held: two"); T.eq(f1.deviated, true)
			T.eq(f1.runes[1], f1.oom[1], "the first at the instant the mana runs out, past its held time")
			T.truthy(f1.oom[1] > e40.runes[1], "the mana runs out after the held time")
			local _, h2, f2 = heldAt({ manaMax = 1537 }, e40)
			T.truthy(f2.oom[1] < e40.runes[1], "1537: the mana out before the held time")
			T.eq(f2.runes[1], e40.runes[1], "the rune at its held time, at 0 mana")
			T.near(M.Total(h2), M.Total(raidPoint({ manaMax = 1540 })), 0.1, "the held fight moves with the pool, no jump")
			local _, _, f3 = heldAt({ manaMax = 1400 }, { manaPotion = false, runes = { 100, 220 } })
			T.eq(#f3.runes, 1, "a held time past the fight's end: none"); T.eq(f3.runes[1], 100, "1400: at its held 100 s, at 0 mana")
			-- held at 10 s with mana left (2280: the mana out at 64.8 s): no use before its fit, at the fight's own 25.92 s (the
			-- cuts at 20 and 23 s, the ends of Rapid Fire and Bestial Wrath, are no instant of 0 mana)
			local _, _, f5 = heldAt({ manaMax = 2280 }, { manaPotion = false, runes = { 10, 130 } })
			T.eq(f5.runes[1], e80.runes[1], "with mana left the held rune waits for its fit")
			local q4, _, f4 = heldAt({ manaMax = 1545 }, M.FightEvents(raidPoint({ manaMax = 1535 })))
			T.eq(#M.Fight(q4).runes, 2); T.eq(#f4.runes, 0, "a rune the events do not hold never fires"); T.eq(f4.deviated, true)
			-- the input's checks
			local function fails(fn, q, text, msg)
				local ok, err = pcall(fn, q)
				T.eq(ok, false, msg); T.truthy(tostring(err):find(text, 1, true), msg .. ": " .. tostring(err))
			end
			local bad = {}
			for k, v in pairs(p80) do bad[k] = v end
			bad.events = { manaPotion = "no", runes = {} }
			fails(M.Total, bad, "p.events is not", "a potion that is not true / false")
			bad.events = { manaPotion = false, runes = { 50, 20 } }
			fails(M.Total, bad, "p.events is not", "times not rising")
			-- the rune's times a list of numbers, keyed 1..n
			for name, runes in pairs({ ["a time that is not a number"] = { "a" }, ["a key past the list"] = { [2] = 10 },
				["a key 0"] = { 10, [0] = 5 }, ["a key 1.5 inside the list"] = { 10, 20, [1.5] = 12 }, ["a key that is no number"] = { 10, x = 12 } }) do
				bad.events = { manaPotion = false, runes = runes }
				fails(M.Total, bad, "p.events is not", name)
			end
			local lv = {}
			for k, v in pairs(ref) do lv[k] = v end
			lv.events = e80
			fails(M.Total, lv, "p.events in levelling mode", "events in levelling mode")
			fails(M.FightEvents, h80, "Model.FightEvents of a point whose events are held", "the events of a point with held events")
			fails(M.Weights, h80, "Model.FightEvents of a point whose events are held", "the weights of a point with held events")
			-- Model.FightEvents and Model.EventGain: raid mode alone, never at a point with held events
			fails(M.FightEvents, ref, "Model.FightEvents of a point not in raid mode", "the events of a levelling point")
			fails(function(q) return M.EventGain(q, e80) end, ref, "Model.EventGain of a point not in raid mode", "the event gain of a levelling point")
			fails(function(q) return M.EventGain(q, e80) end, h80, "Model.EventGain of a point whose events are held", "the event gain of a point with held events")
			-- the fight checks its inputs where it starts, before it reads one (the stuck HHA sequence's level with no bow, the Use
			-- buffs' windows; Model.FightEvents, Model.EventGain and the weights' held points run it first): a missing input is
			-- the input's error, not an arithmetic one
			for _, case in ipairs({ { "manaMax", nil, "Model input p.manaMax missing" }, { "haste", nil, "Model input p.haste missing" },
				{ "level", nil, "Model input p.level missing", { noShots = true, bowDPS = 0 } },
				{ "uses", 5, "Model input p.uses is not a list of Use buffs" } }) do
				local key, value, text = case[1], case[2], case[3]
				local miss = {}
				for k, v in pairs(p80) do miss[k] = v end
				for k, v in pairs(case[4] or {}) do miss[k] = v end
				miss[key] = value
				fails(M.FightEvents, miss, text, "the events with p." .. key .. " " .. tostring(value))
				fails(function(q) return M.EventGain(q, e80) end, miss, text, "the event gain with p." .. key .. " " .. tostring(value))
				fails(M.Weights, miss, text, "the weights with p." .. key .. " " .. tostring(value))
			end
		end },
		-- The weights hold the point's events (raid-mode design 25.1, against 20.5's jumps): a step of 10 Intellect (150 mana) or
		-- 100 mana from a pool of 2140 or 1440 crosses the potion's or the rune's fit, a step of 10 MP5 or Spirit from 2290 or
		-- 1540 lifts the casting regen past it; the free fight priced those across the event (W.INT about 8 times its
		-- neighbours', W.MANA 18 times, W.MP5 and W.SPI below 0). Held, each weight stays near its neighbour's away from the
		-- fit (2000, 2350, 1400, 1600: within 15%, my runs of the scan), and the set that crosses gets the event's change
		-- apart: at 2140 the exact gain of 10 Intellect is W.INT x 10 + Model.EventGain over unitDps (the fight is linear in
		-- the pool on each side here: to 1e-6, my run)
		{ "raid weights hold the point's events: across the mana potion's and the rune's fits each mana weight stays near its neighbours; W x the step + Model.EventGain is the exact gain", function()
			local function W(mm) return (M.Weights(raidPoint({ manaMax = mm }))) end
			local function near(a, b, msg) T.truthy(math.abs(a - b) <= 0.15 * math.abs(b), msg .. ": " .. a .. " against " .. b) end
			local w2000, w2140, w2290, w2350 = W(2000), W(2140), W(2290), W(2350)
			near(w2140.INT, w2000.INT, "INT before the potion's fit"); near(w2140.MANA, w2000.MANA, "MANA before the potion's fit")
			near(w2290.MP5, w2350.MP5, "MP5 at the potion's fit"); near(w2290.SPI, w2350.SPI, "Spirit at the potion's fit")
			local w1400, w1440, w1540, w1600 = W(1400), W(1440), W(1540), W(1600)
			near(w1440.MANA, w1400.MANA, "MANA before the rune's fit"); near(w1440.INT, w1400.INT, "INT before the rune's fit")
			near(w1540.MP5, w1600.MP5, "MP5 at the rune's fit"); near(w1540.SPI, w1600.SPI, "Spirit at the rune's fit")
			local p = raidPoint({ manaMax = 2140 })
			local Wp, unitDps, t0 = M.Weights(p)
			local q = {}
			for k, v in pairs(p) do q[k] = v end
			M.ApplyStats(q, { INT = 10 })
			T.eq(M.Fight(q).manaPotion, 125, "10 Intellect more: the potion fits")
			local exact = (M.Total(q) - t0) / unitDps
			local eg = M.EventGain(q, M.FightEvents(p)) / unitDps
			T.truthy(eg > 50 * Wp.INT, "the potion's change: " .. eg)
			T.near(Wp.INT * 10 + eg, exact, 1e-6, "W.INT x 10 + the event's change")
			-- 10 Spirit at 2290: its share of the casting regen (Bestial Discipline 2: 2 x 25% of Spirit / 8 a second) lifts the
			-- potion's fit past the pool, so with it the potion does not fit: an event change below 0, the exact gain again W x
			-- the step + Model.EventGain (my run: to 1e-13)
			local ps = raidPoint({ manaMax = 2290 })
			local Ws, uS, tS = M.Weights(ps)
			local qs = {}
			for k, v in pairs(ps) do qs[k] = v end
			M.ApplyStats(qs, { SPI = 10 })
			T.eq(M.Fight(ps).manaPotion, 125); T.eq(M.Fight(qs).manaPotion, nil, "10 Spirit more: the potion does not fit")
			local egS = M.EventGain(qs, M.FightEvents(ps)) / uS
			T.truthy(egS < -50 * Ws.SPI, "the potion lost: " .. egS)
			T.near(Ws.SPI * 10 + egS, (M.Total(qs) - tS) / uS, 1e-9, "W.SPI x 10 + the event's change")
		end },
		-- The stats the raid fight reads (Model.FIGHT_KEYS; raid-mode design 25.1): Score.SetValue passes a set's amounts of
		-- them less the worn set's to ctx.eventGain, so a key that moves an input of the fight and is not in the list leaves
		-- its change of an event unpriced (a set's Spirit lifting the potion's fit past the pool, above). Every item stat key
		-- Model.ApplyStats takes moves an input at a raid point (the BM point with Careful Aim, and the Survival weave) exactly
		-- when it is in the list, but the attack power against a creature type: every AP_VS_<TYPE> is in it, and moves
		-- p.apVsTarget at its raid share (Model.TargetShare: the boss's dragonkin 1, any other type 0)
		{ "raid events: Model.FIGHT_KEYS holds every item stat key that moves an input of the raid fight, and no other", function()
			local keys = { "AP", "RAP", "MAP", "STR", "AGI", "CRIT", "CRIT_RANGED", "SPELL_CRIT", "HASTE", "ATTACK_SPEED", "HASTE_RATING",
				"MELEE_HASTE", "RANGED_HASTE", "INT", "SPI", "MP5", "MANA", "ARMOR_PEN", "HIT", "SPELL_HIT", "EXPERTISE", "STA", "ARMOR",
				"HEALTH", "HP5", "DEFENSE", "DODGE", "PARRY", "BLOCK", "SPELL_POWER" }
			for _, t in ipairs(M.CREATURE_TYPES) do keys[#keys + 1] = "AP_VS_" .. t end
			local function moved(p, key)
				local q = {}
				for k, v in pairs(p) do q[k] = v end
				M.ApplyStats(q, { [key] = 7 })
				for k, v in pairs(q) do
					if v ~= p[k] then return true end
				end
				return false
			end
			for _, p in ipairs({ raidPoint({}, { carefulAim = 5 }), raidPoint({ survival = true }, { striderKick = 1 }) }) do
				for _, key in ipairs(keys) do
					local vs = key:sub(1, 6) == "AP_VS_"
					local m = moved(p, key)
					T.eq(M.FIGHT_KEYS[key] == true, m or vs, key .. (m and " moves an input" or " moves none"))
					if vs then T.eq(m, M.TargetShare(key:sub(7), "raid") > 0, key .. " at its raid share") end
				end
			end
			local n = 0
			for k in pairs(M.FIGHT_KEYS) do
				n = n + 1
				local listed = false
				for _, key in ipairs(keys) do listed = listed or key == k end
				T.truthy(listed, "a key the test does not list: " .. k)
			end
			T.eq(n, 17 + 1 + #M.CREATURE_TYPES, "17 stats, the armor penetration and the creature types")
		end },
		-- Each weight taken at a point of its own (raid-mode design 25.1: hit 0, expertise 0, spell hit 0, the ranged skill at
		-- min(skill, 0), the dual-wield setup past the cap) holds that point's own events, so its step never jumps across a
		-- consumable's fit. Where the point sits just inside the potion's fit (found by bisection on the casting regen: the
		-- point and its step take different events), the weight is the derivative with the point's events held, and the
		-- free one differs by tens of units: the BM raid point's W.HIT (my run: the fit at a casting regen of 33.78, held 23.86
		-- against free 46.51), and at a Survival raid point with expertise 2, spell hit 3, a ranged skill 4 over the maximum
		-- and Resourcefulness 3 (whose buff the ranged crit feeds, so the skill's crit moves the casting regen) W.HIT,
		-- W.EXPERTISE, W.SPELL_HIT, W.SKILL_CRIT and W.HIT_DW (fits at 5.38, 3.04, 2.74, 2.71 and 2.69). The parry's point
		-- (past the dodge only the tanking pet's parry, and the raid pet stands behind the boss) and the melee weapons' (a
		-- weapon's DPS moves no input of the mana) hold theirs by the same rule, where no step crosses a fit
		{ "raid weights: each weight's own point holds its own events, so its step never jumps across a consumable's fit", function()
			local function copyOf(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
			local function evk(q) local e = M.FightEvents(q) return tostring(e.manaPotion) .. "/" .. #e.runes end
			local function bm(rc) return raidPoint({ regenCast = rc }) end
			local function sv(rc)
				return raidPoint({ regenCast = rc, survival = true, expertise = 2, spellHit = 3, rangedSkill = 4 },
					{ striderKick = 1, exposePrey = 2, savageStrikes = 2, resourcefulness = 3 })
			end
			local function hit0(p) local q = copyOf(p); q.hit, q.rangedHit, q.rangedGearHit, q.meleeHit = 0, 0, 0, 0; return q end
			local function dw(p)
				local q = copyOf(p)
				q.mhDPS, q.mhSpeed, q.mhNorm, q.twoH, q.unarmed, q.ohDPS = 26, 2.6, 2.4, false, false, 26
				q.hit, q.rangedHit, q.meleeHit = M.HitCap(p.mobDiff) + 0.5, 0, 0
				return q
			end
			local cases = {
				{ "W.HIT, BM", "HIT", bm, 30, 36, hit0, "hit", 0.5 },
				{ "W.HIT, SV", "HIT", sv, 2, 7, hit0, "hit", 0.5 },
				{ "W.EXPERTISE", "EXPERTISE", sv, 2, 7, function(p) local q = copyOf(p); q.expertise = 0; return q end, "expertise", 0.5 },
				{ "W.SPELL_HIT", "SPELL_HIT", sv, 2, 7, function(p) local q = copyOf(p); q.spellHit = 0; return q end, "spellHit", 0.5 },
				{ "W.SKILL_CRIT", "SKILL_CRIT", sv, 2, 7, function(p) local q = copyOf(p); q.rangedSkill = math.min(p.rangedSkill, 0); return q end,
					"rangedSkill", -1 },
				{ "W.HIT_DW", "HIT_DW", sv, 2, 7, dw, "hit", 0.5 },
			}
			for _, c in ipairs(cases) do
				local name, field, build, lo, hi, side, input, d = c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8]
				local kLo = evk(side(build(lo)))
				T.truthy(evk(side(build(hi))) ~= kLo, name .. ": a fit of its point between the casting regens " .. lo .. " and " .. hi)
				for _ = 1, 55 do
					local mid = (lo + hi) / 2
					if evk(side(build(mid))) == kLo then lo = mid else hi = mid end
				end
				local p, q0, q1
				for _, x in ipairs({ lo, hi }) do
					local px = build(x)
					local a = side(px)
					local b = copyOf(a); b[input] = b[input] + d
					if not p and evk(a) ~= evk(b) then p, q0, q1 = px, a, b end
				end
				T.truthy(p, name .. ": a point whose step crosses the fit")
				local W, unitDps = M.Weights(p)
				local h0 = copyOf(q0); h0.events = M.FightEvents(q0)
				local h1 = copyOf(h0); h1[input] = h1[input] + d
				local held = (M.Total(h1) - M.Total(h0)) / d / unitDps
				local free = (M.Total(q1) - M.Total(q0)) / d / unitDps
				T.near(W[field], held, 1e-9 * math.abs(held), name .. ": the derivative with its point's events held")
				T.truthy(math.abs(free - held) > 10, name .. ": the free derivative jumps (" .. free .. " against " .. held .. ")")
			end
		end },
		-- The keys by which a set's stats move the fight's consumables' events (Model.EventKeys; raid-mode design 26.3): the
		-- events are the mana's decisions, so a key whose inputs the mana does not read moves none. At the BM raid point at a
		-- pool of 2140 (the mana runs out, the potion's fit near) and at a Survival raid point at 2000, without and with
		-- Resourcefulness 3 and with a 3.8 s two-hander (whose swing the melee haste speeds), each key of Model.FIGHT_KEYS outside Model.EventKeys leaves the fight's mana bit for bit (each
		-- segment's times and mana, the potion, the runes, the instants the mana runs out) and each key in it moves the mana
		-- at one of the points: the attack speeds, Intellect, Spirit, MP5 and mana always, the crit (Agility's, CRIT,
		-- CRIT_RANGED) with Resourcefulness alone (its buff's uptime from the abilities' and shots' crits, castingRegen).
		-- Model.EventGain's second value is the fight's deviated
		{ "raid events: Model.EventKeys are the keys whose inputs the fight's mana reads, the crit with Resourcefulness alone; every other key leaves the mana bit for bit", function()
			local function manaPath(p)
				local f = M.Fight(p)
				local t = {}
				for _, s in ipairs(f.segments) do t[#t + 1] = string.format("%.17g/%.17g/%.17g/%.17g", s.t0, s.t1, s.m0, s.m1) end
				return table.concat(t, ";") .. "|" .. tostring(f.manaPotion) .. "|" .. table.concat(f.runes, ",") .. "|" .. table.concat(f.oom, ",")
			end
			local svTal = { striderKick = 1, exposePrey = 2, savageStrikes = 2 }
			local svRes = { striderKick = 1, exposePrey = 2, savageStrikes = 2, resourcefulness = 3 }
			local points = { bm = raidPoint({ manaMax = 2140 }), sv = raidPoint({ manaMax = 2000, survival = true }, svTal),
				svRes = raidPoint({ manaMax = 2000, survival = true }, svRes),
				svSlow = raidPoint({ manaMax = 2000, survival = true, mhSpeed = 3.8, mhDPS = 40, twoH = true, ohDPS = 0 }, svTal) }
			local always = { "HASTE", "ATTACK_SPEED", "HASTE_RATING", "MELEE_HASTE", "RANGED_HASTE", "INT", "SPI", "MP5", "MANA" }
			local function set(list) local s = {} for _, k in ipairs(list) do s[k] = true end return s end
			local want = { bm = set(always), sv = set(always), svRes = set(always), svSlow = set(always) }
			for _, k in ipairs({ "AGI", "CRIT", "CRIT_RANGED" }) do want.svRes[k] = true end
			local moves = {}
			for name, p in pairs(points) do
				local keys = M.EventKeys(p)
				for k in pairs(want[name]) do T.eq(keys[k], true, name .. ": " .. k .. " an event key") end
				for k in pairs(keys) do T.eq(want[name][k], true, name .. ": " .. k .. " listed") end
				local base = manaPath(p)
				for k in pairs(M.FIGHT_KEYS) do
					local q = {}
					for kk, v in pairs(p) do q[kk] = v end
					M.ApplyStats(q, { [k] = 25 })
					local moved = manaPath(q) ~= base
					if keys[k] then
						if moved then moves[k] = true end
					else
						T.eq(moved, false, name .. ": " .. k .. " moves the mana")
					end
				end
			end
			for _, k in ipairs({ "HASTE", "ATTACK_SPEED", "HASTE_RATING", "MELEE_HASTE", "RANGED_HASTE", "INT", "SPI", "MP5", "MANA", "AGI", "CRIT", "CRIT_RANGED" }) do
				T.eq(moves[k], true, k .. " moves the mana at a point")
			end
			local ok, err = pcall(M.EventKeys, ref)
			T.eq(ok, false); T.truthy(tostring(err):find("Model.EventKeys of a point not in raid mode", 1, true), tostring(err))
			-- Model.EventGain's second value
			local p = raidPoint({ manaMax = 2140 })
			local e = M.FightEvents(p)
			local q1, q2 = {}, {}
			for k, v in pairs(p) do q1[k] = v; q2[k] = v end
			M.ApplyStats(q1, { INT = 1 }); M.ApplyStats(q2, { INT = 10 })
			local g1, d1 = M.EventGain(q1, e)
			local g2, d2 = M.EventGain(q2, e)
			T.eq(g1, 0); T.eq(d1, false, "1 Intellect: no event changes")
			T.truthy(g2 > 0, "10 Intellect: the potion fits"); T.eq(d2, true, "10 Intellect: deviated")
		end },
	}
end
