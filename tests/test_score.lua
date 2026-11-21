return function(ns, T)
	local Sc = ns.Score
	local S = Sc.SLOT
	-- A model point with every input the model requires (Core/Model.lua checkInputs) from the fields t gives: what t leaves
	-- out is set as the game side sets it with nothing worn that changes it, melee crit at the ranged crit, the ranged and
	-- the melee skills at the level's (rangedSkill, mhSkill, ohSkill 0, their hits 0), no expertise or attack speed, a bow that shoots, not the Survival branch (no melee), a pet out, an armed main hand at the normalized speed of
	-- its hand type (Player.WeaponInputs: 3.3 s a two-hander, 2.4 s a one-hander) and the off hand at the main hand's speed;
	-- levelling mode, the reference character's 167 Agility (tests/test_model.lua ref), no ranged-only gear hit, Beastslaying
	-- or attack power against a creature type, no spell hit and the hunter's base spell crit 3.6% (wowsims
	-- sim/core/base_stats_auto_gen.go:62-66), no stat multiplier aura on the sheet (statMult 1 each).
	local function fullP(t)
		local p = {}
		for k, v in pairs(t) do p[k] = v end
		local function fill(k, v) if p[k] == nil then p[k] = v end end
		fill("meleeCrit", p.crit); fill("rangedHit", 0); fill("rangedSkill", 0); fill("expertise", 0)
		fill("meleeHit", 0); fill("mhSkill", 0); fill("ohSkill", 0)
		fill("haste", 0); fill("attackSpeed", 0); fill("hasteRating", 0); fill("meleeHaste", 0); fill("rangedHaste", 0)
		fill("twoH", false); fill("mhNorm", p.twoH and 3.3 or 2.4); fill("ohSpeed", p.mhSpeed)
		fill("unarmed", false); fill("noShots", false); fill("survival", false); fill("petOut", true)
		fill("mode", "level"); fill("agi", 167); fill("rangedGearHit", 0); fill("beastSlaying", 0); fill("apVsTarget", 0)
		fill("spellHit", 0); fill("spellCrit", 3.6); fill("statMult", { AGI = 1, STR = 1, INT = 1, SPI = 1 })
		return p
	end
	-- A weight table as Model.Weights returns one: every key it sets, 0 unless t gives it. The scorer reads the
	-- weights it names directly (Score.ItemValue), so a test W holds them all; a key Model.Weights never sets is a typo.
	local WEIGHT_KEYS = {}
	for k in pairs((ns.Model.Weights(fullP({ level = 43, rap = 500, map = 300, crit = 8, hit = 1, bowDPS = 21, bowSpeed = 2.6,
		ammoDPS = 13, quiver = 0.1, mobDiff = 0, mhDPS = 26, mhSpeed = 2.6, ohDPS = 26,
		tal = ns.Model.DEFAULT_TALENTS })))) do WEIGHT_KEYS[k] = true end
	local function fullW(t)
		local w = {}
		for k in pairs(WEIGHT_KEYS) do w[k] = 0 end
		for k, v in pairs(t) do
			if not WEIGHT_KEYS[k] then error("not a Model.Weights key: " .. tostring(k), 2) end
			w[k] = v
		end
		return w
	end
	local W = fullW({ RAP = 1, AGI = 2.5, AP = 1, STA = 0.4, HIT = 18, CRIT = 17, RANGED_DPS = 10.4,
		MH_DPS = 0.27, OH_DPS = 0.09, TH_DPS = 0.35, AMMO_DPS = 10.4, EXTRA_DPS = 6.5, ARMOR = 0.01 })
	-- Item records as Items.Get builds them for the scorer: an item id (C_Item.GetItemInfoInstant's itemID; each item() its
	-- own made-up id from 900001 on, so no two are copies of one item), stats (a stat the item lacks is absent), procs (empty
	-- without a damage proc, Parse:Lines)
	local lastItemId = 900000
	local function item(loc, stats, name)
		lastItemId = lastItemId + 1
		return { equipLoc = loc, id = lastItemId, stats = stats or {}, procs = {}, name = name or loc }
	end
	-- an item with an id and, for a set piece, its set id (Items.Get's rec.setID)
	local function piece(loc, id, setID, stats) return { equipLoc = loc, id = id, setID = setID, stats = stats or {}, procs = {}, name = loc .. id } end
	-- A proc as Items.Get leaves one it finds no Game/ProcData.lua entry for (Items.LinkProcs): defense 0 (its table by its
	-- school), crit allowed, the school its text names ("magic" unless given), and its hits (Parse)
	local function proc(avg, hits, equip, school)
		return { avg = avg, hits = hits, equip = equip, school = school or "magic", linked = false, defense = 0, crit = true }
	end
	-- A proc's rate (U4 = (a), Score.ProcRateSource): the item's measured rate (Score.MEASURED_PPM), else the rate wowsims'
	-- override row gives its linked entry (Game/ProcData.lua source), else the DB2's; a proc with none is not priced. The
	-- rate tests give their made-up items a measured rate of 1.5 a minute (per minute at the speed of the hand that hits),
	-- registered for the test and taken back by the function measuredFor returns (an item with a measured rate of its own
	-- is an error); onHit is a chance-on-hit proc linked to an entry with a carried-over rate of wowsims' override data
	local function measuredFor(rate, ...)
		local items = { ... }
		for _, it in ipairs(items) do
			if Sc.MEASURED_PPM[it.id] ~= nil then error("a test's rate on an item measured in the logs: " .. it.id) end
			Sc.MEASURED_PPM[it.id] = rate
		end
		return function() for _, it in ipairs(items) do Sc.MEASURED_PPM[it.id] = nil end end
	end
	local function onHit(avg, hits, ppm, source)
		local p = proc(avg, hits)
		p.linked, p.ppm, p.source = true, ppm or 1.5, source or "vanilla-carryover"
		return p
	end
	-- An outcome table in Model.ProcOutcomes' form where every proc lands whole and never crits, with no armor, no
	-- multiplier and no debuff of the raid boss (coe 1, gift 0, the levelling mode's): the tests of the rates price a proc at
	-- its average damage alone (the outcomes have their own tests)
	local WHOLE = { hit = 1, critMult = 1, land = 1, tickCrit = 1 }
	local WHOLE_OUTCOME = { [0] = { physical = WHOLE, magic = WHOLE }, [1] = WHOLE, [2] = WHOLE, [3] = WHOLE, phys = 1, own = 1,
		coe = 1, gift = 0 }
	local function ctx(eq, pool, extra)
		-- levelling mode (the Use buffs over their average uptime, Score.SetValue); an equal-level mob (mobDiff 0: the 5% hit
		-- cap, Model.HitCap(0)); skillBase 0: the worn ranged line's trained skill
		-- at the level's 5 points a level; every melee line trained at the level's too (meleeTrained 0) and the worn main
		-- hand's skill hit 0 (wornMeleeHit); expertiseCap 5: an equal-level mob's dodge (Model.MobAvoid(0)), and its parry no
		-- higher (parryCap 5: Model.PetParry(0)); every proc whole (WHOLE_OUTCOME)
		local c = { mode = "level", equipped = eq, pool = pool or {}, dualWield = true, hitCap = 5, baseHit = 0, skillBase = 0, mobDiff = 0,
			meleeTrained = function() return 0 end, wornMeleeHit = 0, expertiseCap = 5, parryCap = 5, procOutcome = WHOLE_OUTCOME,
			procOutcomeFor = function() return WHOLE_OUTCOME end, baseSpellHit = 0, spellHitCap = 4 }
		for k, v in pairs(extra or {}) do c[k] = v end
		return c
	end
	-- landed hits in Model.LandedHits' form: each hand's landed swings and specials per second and its speed, the ranged
	-- hand's Serpent Sting applications (casts)
	local function hitsOf(mh, oh, ranged)
		return { mh = { swings = mh[1], specials = mh[2], speed = mh[3] }, oh = { swings = oh[1], specials = 0, speed = oh[2] },
			ranged = { swings = ranged[1], specials = ranged[2], casts = ranged[4] or 0, speed = ranged[3] } }
	end
	-- made-up landed hits of a set in ctx.landedHitsFor's form: fixed counts, each hand at the speed of the set's weapon
	-- there, as the set's own model point swings it (Score.LandedHitsOf checks it), else a 2.6 s main hand, a 1.8 s off
	-- hand and a 2.5 s bow
	local function madeUpHits(set)
		local function speed(slot, none) local it = set[slot]; return (it and it.speed) or none end
		return hitsOf({ 0.02, 0.003, speed(S.MAINHAND, 2.6) }, { 0.03, speed(S.OFFHAND, 1.8) },
			{ 0.5, 0.17, speed(S.RANGED, 2.5), 0.04 })
	end
	local function weaponOf(loc, id, speed, stats)
		return { equipLoc = loc, id = id, classID = 2, subclassID = loc == "INVTYPE_RANGED" and 2 or 0, speed = speed,
			stats = stats or {}, procs = {}, name = loc .. tostring(id) }
	end
	-- a model point: tests/test_model.lua's reference state (level 43, BM 32/2: no melee, two 26 DPS one-handers) with the
	-- off hand at 1.8 s
	local function refPoint(extra)
		local p = { mode = "level", agi = 167, rangedGearHit = 0, beastSlaying = 0, apVsTarget = 0, spellHit = 0, spellCrit = 3.6,
			level = 43, rap = 2 * 43 - 10 + 2 * 167 + 81 + 70, map = 2 * 43 - 20 + 167 + 81,
			crit = 167 / 35.84 + 2 + 2, hit = 1, expertise = 0, haste = 0,
			bowDPS = 21, bowSpeed = 2.6, ammoDPS = 13, quiver = 0.13, mobDiff = 0,
			mhDPS = 26, mhSpeed = 2.6, ohDPS = 26, ohSpeed = 1.8, twoH = false, tal = ns.Model.DEFAULT_TALENTS }
		for k, v in pairs(extra or {}) do p[k] = v end
		return fullP(p)
	end

	-- Properties of a swap plan: it settles; no row is a loss; no worn item moves to another slot (a worn
	-- weapon may move to the other hand); no item is worn twice and no two copies of a unique item are worn;
	-- the total gains (Score.Verdict "better" or "better2": any damage gain counts, Score.Plan); planning again from
	-- the result finds no damage gain (otherwise the next banner undoes what this one asked for); and BestHands over
	-- the result's hands and every weapon off the body finds nothing that beats the plan's hands. Returns the problems
	-- and the kinds of the steps the plan took.
	local function planProblems(eq, cands, Wx, c)
		local out = {}
		local ok, target, kinds = pcall(Sc.Plan, eq, cands, Wx, c)
		if not ok then return { tostring(target) }, {} end
		local worn = {}
		for slot, it in pairs(eq) do worn[it] = slot end
		local rows = Sc.PlanRows(eq, target)
		Sc.RowGains(eq, target, rows, Wx, c)
		local function hand(slot) return slot == S.MAINHAND or slot == S.OFFHAND end
		for _, r in ipairs(rows) do
			if r.gain and (r.gain.verdict == "worse" or r.gain.verdict == "worse2") then out[#out + 1] = "slot " .. r.slot .. " " .. r.gain.verdict end
			local from = r.new and worn[r.new]
			if from and not (hand(from) and hand(r.slot)) then out[#out + 1] = "worn item moved to slot " .. r.slot end
		end
		local items = {}
		for _, it in pairs(target) do items[#items + 1] = it end
		for i = 1, #items do for j = i + 1, #items do
			local a, b = items[i], items[j]
			if a == b then out[#out + 1] = "one item worn twice: " .. tostring(a.name) end
			if a.id and a.id == b.id and (a.uniqueEquipped or b.uniqueEquipped) then out[#out + 1] = "two copies of unique " .. a.id end
		end end
		local vT, sT = Sc.SetValue(target, Wx, c), Sc.Secondary(target, c)
		if #rows > 0 then
			local d = vT - Sc.SetValue(eq, Wx, c)
			local v = Sc.Verdict(d, sT)
			if v ~= "better" and v ~= "better2" then out[#out + 1] = "total " .. v end
		end
		local inT = {}
		for _, it in pairs(target) do inT[it] = true end
		local left, weapons = {}, {}
		for _, it in ipairs(cands) do if not inT[it] then left[#left + 1] = it end end
		for it in pairs(worn) do if not inT[it] then left[#left + 1] = it end end
		for _, it in ipairs(left) do if Sc.WEAPON_LOCS[it.equipLoc] then weapons[#weapons + 1] = it end end
		local c2 = Sc.CopySet(c); c2.equipped = target
		local ok2, again = pcall(Sc.Plan, target, left, Wx, c2)
		if not ok2 then out[#out + 1] = "replan: " .. tostring(again) else
			local d2 = Sc.SetValue(again, Wx, c2) - Sc.SetValue(target, Wx, c2)
			if d2 > Sc.EPS then out[#out + 1] = string.format("replan finds +%.2f damage", d2) end
		end
		local bh = Sc.BestHands(nil, target, weapons, Wx, c)
		if bh then
			if Sc.Better(bh.value, bh.sec, vT, sT) then out[#out + 1] = "BestHands beats the plan's hands" end
		end
		return out, kinds
	end
	-- whether the plan took a step of this kind ("item", "hands", "set": Score.Plan's second result)
	local function took(kinds, kind)
		for _, k in ipairs(kinds or {}) do if k == kind then return true end end
		return false
	end

	return {
		{ "armor slot delta", function()
			local eq = { [S.HEAD] = item("INVTYPE_HEAD", { AGI = 10 }) }
			local r = Sc.Evaluate(item("INVTYPE_HEAD", { AGI = 14 }), W, ctx(eq))
			T.near(r.delta, 10, 1e-9); T.eq(r.slot, S.HEAD)
		end },
		{ "ring replaces the weaker ring", function()
			local eq = { [S.FINGER1] = item("INVTYPE_FINGER", { AGI = 10 }), [S.FINGER2] = item("INVTYPE_FINGER", { AGI = 2 }) }
			local r = Sc.Evaluate(item("INVTYPE_FINGER", { AGI = 6 }), W, ctx(eq))
			T.eq(r.slot, S.FINGER2); T.near(r.delta, 10, 1e-9)
		end },
		{ "hit above the cap is worth nothing", function()
			local eq = { [S.HEAD] = item("INVTYPE_HEAD", { HIT = 5 }) }
			local r = Sc.Evaluate(item("INVTYPE_HANDS", {}), W, ctx(eq)) -- unknown loc -> nil
			T.eq(r, nil)
			local eq2 = { [S.HEAD] = item("INVTYPE_HEAD", { HIT = 5 }), [S.HANDS] = item("INVTYPE_HAND", {}) }
			local r2 = Sc.Evaluate(item("INVTYPE_HAND", { HIT = 1 }), W, ctx(eq2))
			T.near(r2.delta, 0, 1e-9, "capped hit")
			local r3 = Sc.Evaluate(item("INVTYPE_HAND", { HIT = 1 }), W, ctx(eq2, nil, { hitCap = 6 }))
			T.near(r3.delta, 18, 1e-9, "hit up to cap 6")
		end },
		{ "ranged weapon dps", function()
			local eq = { [S.RANGED] = item("INVTYPE_RANGED", { DPS = 20 }) }
			local r = Sc.Evaluate(item("INVTYPE_RANGED", { DPS = 24.6 }), W, ctx(eq))
			T.near(r.delta, 4.6 * 10.4, 1e-6)
		end },
		{ "proc adds extra dps value: its procs on the landed hits of the set it is in", function()
			local eq = { [S.RANGED] = weaponOf("INVTYPE_RANGED", 1, 2.5, { DPS = 20 }) }
			local cand = weaponOf("INVTYPE_RANGED", 2, 3.0, { DPS = 20 }); cand.procs = { onHit(28, "weapon") }
			local r = Sc.Evaluate(cand, W, ctx(eq, nil, { landedHitsFor = madeUpHits }))
			-- the bow's own hits in its own set, at its own 3.0 s: the Auto Shots, the special shots and Serpent Sting's
			-- applications
			T.near(r.delta, 28 * 1.5 * 3.0 * (0.5 + 0.17 + 0.04) / 60 * 6.5, 1e-9)
		end },
		{ "1H in main hand moves the old main hand to the off hand", function()
			local mh = item("INVTYPE_WEAPON", { AGI = 4, DPS = 26 }, "oldMH")
			local oh = item("INVTYPE_WEAPON", { AGI = 0, DPS = 20 }, "oldOH")
			local eq = { [S.MAINHAND] = mh, [S.OFFHAND] = oh }
			local cand = item("INVTYPE_WEAPON", { AGI = 8, DPS = 28 }, "new")
			local r = Sc.Evaluate(cand, W, ctx(eq))
			T.eq(r.mh, cand); T.eq(r.oh, mh, "old main hand goes to off hand")
			T.near(r.delta, 8 * 2.5 + 28 * 0.27 + 26 * 0.09 - (26 * 0.27 + 20 * 0.09), 1e-6)
		end },
		{ "with a 2H equipped, a 1H finds its best partner in the bags", function()
			local th = item("INVTYPE_2HWEAPON", { AGI = 15, DPS = 34 }, "2H")
			local eq = { [S.MAINHAND] = th }
			local bagA = item("INVTYPE_WEAPON", { AGI = 9, DPS = 26 }, "bagA")
			local bagB = item("INVTYPE_WEAPON", { AGI = 3, DPS = 26 }, "bagB")
			local cand = item("INVTYPE_WEAPON", { AGI = 8, DPS = 27 }, "cand")
			local r = Sc.Evaluate(cand, W, ctx(eq, { bagA, bagB }))
			T.eq(r.swapFrom2H, true)
			T.truthy((r.mh == cand and r.oh == bagA) or (r.mh == bagA and r.oh == cand), "pairs with the best partner")
			T.truthy(r.delta > 0, "17 agi beats 15 agi")
		end },
		{ "2H candidate against a dual-wield pair", function()
			local eq = { [S.MAINHAND] = item("INVTYPE_WEAPON", { AGI = 5, DPS = 26 }), [S.OFFHAND] = item("INVTYPE_WEAPON", { AGI = 5, DPS = 26 }) }
			local r = Sc.Evaluate(item("INVTYPE_2HWEAPON", { AGI = 8, DPS = 34 }), W, ctx(eq))
			T.eq(r.hand, "2h"); T.eq(r.oh, nil); T.truthy(r.delta < 0, "8 agi loses to 10 agi")
		end },
		{ "off-hand weapon needs dual wield, holdable does not", function()
			local eq = { [S.MAINHAND] = item("INVTYPE_WEAPON", { DPS = 26 }) }
			local ohw = item("INVTYPE_WEAPONOFFHAND", { AGI = 5 })
			T.eq(Sc.Evaluate(ohw, W, ctx(eq, nil, { dualWield = false })), nil, "no dual wield")
			local r = Sc.Evaluate(ohw, W, ctx(eq))
			T.eq(r.hand, "oh")
			local hold = item("INVTYPE_HOLDABLE", { AGI = 5 })
			local r2 = Sc.Evaluate(hold, W, ctx(eq, nil, { dualWield = false }))
			T.eq(r2.hand, "oh"); T.near(r2.delta, 12.5, 1e-9)
		end },
		{ "a junk one-hander does not borrow a good bag weapon's gain", function()
			local A = item("INVTYPE_WEAPON", { AGI = 12, DPS = 26 }, "A")
			local C = item("INVTYPE_WEAPON", { AGI = 10, DPS = 26 }, "C")
			local eq = { [S.MAINHAND] = item("INVTYPE_WEAPON", { AGI = 2, DPS = 26 }, "oldMH"),
				[S.OFFHAND] = item("INVTYPE_WEAPON", { AGI = 2, DPS = 26 }, "oldOH") }
			local junk = item("INVTYPE_WEAPON", { DPS = 10 }, "junk")
			local r = Sc.Evaluate(junk, W, ctx(eq, { A, C, junk }))
			T.truthy(r.delta < 0, "junk on its own is a loss: " .. r.delta)
			T.truthy(r.betterOther, "the better setup is named")
			local rc = Sc.Evaluate(C, W, ctx(eq, { A, C, junk }))
			T.truthy(rc.delta > 0 and (rc.mh == A or rc.oh == A), "C pairs with A")
		end },
		-- the better setup is named for any damage gain (Score.Better: the user's rule, any damage gain gets the checkmark, no
		-- threshold): a bag one-hander with 0.1 Agility more than either worn one gains 0.1 x 2.5
		{ "a junk weapon names the better setup for any damage gain, a fraction of a point too, and not for a tie", function()
			local A = item("INVTYPE_WEAPON", { AGI = 2.1, DPS = 26 }, "A")
			local eq = { [S.MAINHAND] = item("INVTYPE_WEAPON", { AGI = 2, DPS = 26 }, "oldMH"),
				[S.OFFHAND] = item("INVTYPE_WEAPON", { AGI = 2, DPS = 26 }, "oldOH") }
			local junk = item("INVTYPE_WEAPON", { DPS = 10 }, "junk")
			local r = Sc.Evaluate(junk, W, ctx(eq, { A, junk }))
			T.truthy(r.delta < 0, "junk on its own is a loss: " .. r.delta)
			T.truthy(r.betterOther, "the better setup is named")
			T.truthy(r.betterOther.mh == A or r.betterOther.oh == A, "with A")
			T.near(r.betterOther.delta, 0.1 * 2.5, 1e-9, "A in place of an Agility 2 one-hander")
			-- a setup that only ties the worn hands is not named: an off-hand item that adds nothing makes the main hand alone
			-- (enumerated first) the best setup at the worn value, next to a junk two-hander
			local tie = { [S.MAINHAND] = item("INVTYPE_WEAPON", { AGI = 2, DPS = 26 }, "oldMH"), [S.OFFHAND] = item("INVTYPE_HOLDABLE", {}, "frill") }
			local junk2H = item("INVTYPE_2HWEAPON", { DPS = 1 }, "junk2H")
			local rt = Sc.Evaluate(junk2H, W, ctx(tie, { junk2H }))
			T.truthy(rt.delta < 0, "the junk two-hander is a loss: " .. rt.delta)
			T.eq(rt.betterOther, nil, "a tie is no better setup")
		end },
		{ "a melee weapon proc fires only on its own hand's melee hits", function()
			local eq = { [S.MAINHAND] = weaponOf("INVTYPE_WEAPON", 1, 2.6, { DPS = 22.1 }) }
			local cand = weaponOf("INVTYPE_WEAPON", 2, 2.6, { DPS = 22.1 }); cand.procs = { onHit(28, "weapon") }
			local r = Sc.Evaluate(cand, W, ctx(eq, nil, { dualWield = false, landedHitsFor = madeUpHits }))
			T.near(r.delta, 28 * 1.5 * 2.6 * (0.02 + 0.003) / 60 * 6.5, 1e-9, "the main hand's swings and specials, no shot, no sting")
		end },
		{ "a unique-equipped second copy only replaces the worn copy", function()
			local ring = item("INVTYPE_FINGER", { AGI = 10 }); ring.id = 7; ring.uniqueEquipped = true
			local other = item("INVTYPE_FINGER", { AGI = 2 }); other.id = 8
			local eq = { [S.FINGER1] = ring, [S.FINGER2] = other }
			local copy = item("INVTYPE_FINGER", { AGI = 10 }); copy.id = 7; copy.uniqueEquipped = true
			local r = Sc.Evaluate(copy, W, ctx(eq))
			T.eq(r.slot, S.FINGER1); T.near(r.delta, 0, 1e-9)
		end },
		{ "scope adds per-shot damage in the ranged slot", function()
			local bow = item("INVTYPE_RANGED", { DPS = 20 }); bow.speed = 2.5
			local scoped = item("INVTYPE_RANGED", { DPS = 20, RANGED_FLAT = 5 }); scoped.speed = 2.5
			local r = Sc.Evaluate(scoped, W, ctx({ [S.RANGED] = bow }))
			T.near(r.delta, 10.4 * 5 / 2.5, 1e-6)
		end },
		{ "user rule: equal damage -> 400 mana beats 100 health", function()
			local Wd = fullW({ AGI = 2.5, RAP = 1 }) -- damage-only weights, like Model.Weights returns
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 44 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local eq = { [S.NECK] = item("INVTYPE_NECK", { AGI = 7, STA = 10 }) }       -- +100 HP
			local cand = item("INVTYPE_NECK", { AGI = 7, INT = 27 })                       -- +405 mana
			local r = Sc.Evaluate(cand, Wd, ctx(eq, nil, { pools = pools, secondaryRates = rates }))
			T.near(r.delta, 0, 1e-9, "same damage")
			T.truthy(r.sec > 0, "mana side wins: " .. r.sec)
			T.eq(Sc.Verdict(r.delta, r.sec), "better2")
		end },
		{ "user rule: damage always first, +1 Agility beats +400 mana", function()
			local Wd = fullW({ AGI = 2.5, RAP = 1 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 44 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local eq = { [S.NECK] = item("INVTYPE_NECK", { AGI = 7, INT = 27 }) }
			local cand = item("INVTYPE_NECK", { AGI = 8 })
			local r = Sc.Evaluate(cand, Wd, ctx(eq, nil, { pools = pools, secondaryRates = rates }))
			T.truthy(r.sec < 0, "loses mana")
			T.eq(Sc.Verdict(r.delta, r.sec), "better")
		end },
		-- Raid mode's tie-break (raid-mode design 7.9): no mana part, the mana stats priced in the damage (Model.Weights' raid
		-- W.INT, W.MP5, W.SPI, W.MANA), and the armor against the raid boss's hits, level 63: 1500 armor reduces 1500 / (1500
		-- + 400 + 85 x 63) = 0.2049 there against 0.2643 at the hunter's 44 (my arithmetic); levelling as before. Score.Secondary
		-- without a mode is an error
		{ "raid secondary: no mana part, the armor against the boss's 63; levelling unchanged; no mode an error", function()
			local Wd = fullW({ AGI = 2.5 })
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local eq = { [S.NECK] = item("INVTYPE_NECK", { STA = 10, ARMOR = 100 }) }
			local cand = { [S.NECK] = item("INVTYPE_NECK", { INT = 27, ARMOR = 160 }) }
			local function sec(mode, level)
				local c = ctx(eq, nil, { mode = mode, pools = { hp = 2000, mana = 1725, armor = 1500, level = level }, secondaryRates = rates })
				return Sc.Secondary(cand, c)
			end
			local function hpPct(attacker)
				local function dr(a) return a / (a + 400 + 85 * attacker) end
				return ((2000 - 100) / (1 - dr(1560))) / (2000 / (1 - dr(1500))) * 100 - 100
			end
			local tot, hp, mana = sec("raid", 60)
			T.eq(mana, 0, "raid: no mana part")
			T.near(hp, hpPct(63), 1e-9, "raid: the armor against level 63")
			T.near(tot, hp, 1e-12)
			local ltot, lhp, lmana = sec("level", 44)
			T.near(lhp, hpPct(44), 1e-9, "levelling: the armor against the hunter's level")
			T.near(lmana, (15 * 27) / 1725 * 100, 1e-9, "levelling: Intellect's 15 mana a point of the pool")
			T.near(ltot, lhp + lmana, 1e-12)
			local noMode = ctx(eq, nil, { pools = { hp = 2000, mana = 1725, armor = 1500, level = 44 }, secondaryRates = rates })
			noMode.mode = nil
			local ok, err = pcall(Sc.Secondary, cand, noMode)
			T.eq(ok, false); T.truthy(tostring(err):find("Score.Secondary without ctx.mode", 1, true), tostring(err))
			T.eq(Wd.AGI, 2.5)
		end },
		{ "armor counts as effective health", function()
			local Wd = fullW({ AGI = 2.5 })
			local pools = { hp = 2000, mana = 1500, armor = 1500, level = 44 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local eq = { [S.WRIST] = item("INVTYPE_WRIST", { ARMOR = 100 }) }
			local cand = item("INVTYPE_WRIST", { ARMOR = 124 })
			local r = Sc.Evaluate(cand, Wd, ctx(eq, nil, { pools = pools, secondaryRates = rates }))
			T.truthy(r.sec > 0 and r.sec < 1, "24 armor is a small effective-health gain: " .. r.sec)
		end },
		{ "shield is never evaluated", function()
			T.eq(Sc.Evaluate(item("INVTYPE_SHIELD", { AGI = 50 }), W, ctx({})), nil)
		end },

		-- swap plan (the banner): what to put on from the bags, all together
		{ "plan: the best bag item per slot, worse ones stay in the bags", function()
			local head = item("INVTYPE_HEAD", { AGI = 10 }, "head")
			local r1, r2 = item("INVTYPE_FINGER", { AGI = 10 }, "r1"), item("INVTYPE_FINGER", { AGI = 2 }, "r2")
			local eq = { [S.HEAD] = head, [S.FINGER1] = r1, [S.FINGER2] = r2 }
			local headA, headB = item("INVTYPE_HEAD", { AGI = 14 }, "headA"), item("INVTYPE_HEAD", { AGI = 12 }, "headB")
			local ring, junk = item("INVTYPE_FINGER", { AGI = 6 }, "ring"), item("INVTYPE_FINGER", { AGI = 1 }, "junk")
			local target = Sc.Plan(eq, { headB, junk, headA, ring }, W, ctx(eq))
			T.eq(target[S.HEAD], headA); T.eq(target[S.FINGER1], r1); T.eq(target[S.FINGER2], ring)
			local rows = Sc.PlanRows(eq, target)
			T.eq(#rows, 2)
			T.eq(rows[1].slot, S.HEAD); T.eq(rows[1].new, headA); T.eq(rows[1].old, head)
			T.eq(rows[2].slot, S.FINGER2); T.eq(rows[2].new, ring); T.eq(rows[2].old, r2)
		end },
		{ "plan: two bag rings replace both worn rings", function()
			local eq = { [S.FINGER1] = item("INVTYPE_FINGER", { AGI = 2 }), [S.FINGER2] = item("INVTYPE_FINGER", { AGI = 3 }) }
			local a, b = item("INVTYPE_FINGER", { AGI = 10 }, "a"), item("INVTYPE_FINGER", { AGI = 8 }, "b")
			local target = Sc.Plan(eq, { a, b }, W, ctx(eq))
			T.truthy((target[S.FINGER1] == a and target[S.FINGER2] == b) or (target[S.FINGER1] == b and target[S.FINGER2] == a))
		end },
		{ "plan: hit over the cap is not stacked", function()
			local eq = { [S.HEAD] = item("INVTYPE_HEAD", {}), [S.HANDS] = item("INVTYPE_HAND", { AGI = 10 }, "hands") }
			local hitHead = item("INVTYPE_HEAD", { HIT = 4 }, "hitHead")
			local hitHands = item("INVTYPE_HAND", { HIT = 4 }, "hitHands") -- alone +47, after the helm -7
			local target = Sc.Plan(eq, { hitHands, hitHead }, W, ctx(eq))
			T.eq(target[S.HEAD], hitHead); T.eq(target[S.HANDS].name, "hands")
		end },
		{ "plan: a 2H worn, two bag one-handers make the pair; the 2H leaves", function()
			local th = item("INVTYPE_2HWEAPON", { AGI = 15, DPS = 34 }, "2H")
			local eq = { [S.MAINHAND] = th }
			local a = item("INVTYPE_WEAPON", { AGI = 9, DPS = 26 }, "a")
			local b = item("INVTYPE_WEAPON", { AGI = 8, DPS = 27 }, "b")
			local target = Sc.Plan(eq, { a, b }, W, ctx(eq, { a, b }))
			T.truthy((target[S.MAINHAND] == a and target[S.OFFHAND] == b) or (target[S.MAINHAND] == b and target[S.OFFHAND] == a))
			local rows = Sc.PlanRows(eq, target)
			T.eq(#rows, 2); T.eq(rows[1].slot, S.MAINHAND); T.eq(rows[1].old, th)
			T.eq(rows[2].slot, S.OFFHAND); T.eq(rows[2].old, nil)
		end },
		{ "plan: a 2H from the bags empties the off hand (row without an item to put on)", function()
			local mh, oh = item("INVTYPE_WEAPON", { AGI = 1, DPS = 20 }, "mh"), item("INVTYPE_WEAPON", { AGI = 1, DPS = 20 }, "oh")
			local eq = { [S.MAINHAND] = mh, [S.OFFHAND] = oh }
			local th = item("INVTYPE_2HWEAPON", { AGI = 30, DPS = 40 }, "2H")
			local target = Sc.Plan(eq, { th }, W, ctx(eq, { th }))
			T.eq(target[S.MAINHAND], th); T.eq(target[S.OFFHAND], nil)
			local rows = Sc.PlanRows(eq, target)
			T.eq(#rows, 2); T.eq(rows[1].new, th); T.eq(rows[2].slot, S.OFFHAND); T.eq(rows[2].new, nil); T.eq(rows[2].old, oh)
		end },
		{ "plan: nothing better in the bags -> no rows", function()
			local eq = { [S.HEAD] = item("INVTYPE_HEAD", { AGI = 10 }) }
			local target = Sc.Plan(eq, { item("INVTYPE_HEAD", { AGI = 3 }) }, W, ctx(eq))
			T.eq(#Sc.PlanRows(eq, target), 0)
		end },
		{ "equal-damage survival vs mana items do not make the plan loop", function()
			local Wd = fullW({ AGI = 2.5 }) -- BM without Careful Aim: no damage weight on INT/SPI/STA/armor
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 40 }
			local tal = {}
			for k, v in pairs(ns.Model.DEFAULT_TALENTS) do tal[k] = v end
			local cases = {
				-- a survival chest (b) against a mana chest (c) at equal damage, with Bestial Discipline 0 and at the default
				-- build's 2
				{ bd = 0, b = { AGI = 10, STA = 15, ARMOR = 300 }, c = { AGI = 10, INT = 12, SPI = 6, ARMOR = 100 } },
				{ bd = 2, b = { AGI = 10, STA = 2, ARMOR = 340 }, c = { AGI = 10, INT = 8, ARMOR = 100 } },
			}
			for i, case in ipairs(cases) do
				tal.bestialDiscipline = case.bd
				local rates = ns.Model.SecondaryRates(tal)
				local worn = item("INVTYPE_CHEST", { AGI = 10, ARMOR = 100 }, "worn")
				local eq = { [S.CHEST] = worn }
				local B, C = item("INVTYPE_CHEST", case.b, "B"), item("INVTYPE_CHEST", case.c, "C")
				local c = ctx(eq, nil, { pools = pools, secondaryRates = rates })
				local ok, target = pcall(Sc.Plan, eq, { B, C }, Wd, c)
				T.truthy(ok, "case " .. i .. ": " .. tostring(target))
				-- the pick is the better of the two against the worn chest
				local sB = Sc.Secondary({ [S.CHEST] = B }, c)
				local sC = Sc.Secondary({ [S.CHEST] = C }, c)
				T.eq(target[S.CHEST], sB > sC and B or C, "case " .. i)
			end
		end },
		{ "two copies of a unique-equipped one-hander are never paired", function()
			local sword = item("INVTYPE_WEAPON", { AGI = 10, DPS = 30 }, "unique"); sword.id = 777; sword.uniqueEquipped = true
			local weak = item("INVTYPE_WEAPON", { DPS = 10 }, "weak")
			local eq = { [S.MAINHAND] = sword, [S.OFFHAND] = weak }
			local copy = item("INVTYPE_WEAPON", { AGI = 10, DPS = 30 }, "copy"); copy.id = 777; copy.uniqueEquipped = true
			local target = Sc.Plan(eq, { copy }, W, ctx(eq, { copy }))
			T.eq(#Sc.PlanRows(eq, target), 0, "no off-hand copy suggested")
			local r = Sc.Evaluate(copy, W, ctx(eq, { copy }))
			T.truthy(not (r.mh == sword and r.oh == copy) and not (r.mh == copy and r.oh == sword), "Evaluate does not pair them")
		end },
		-- every item record has its item id (Items.Get: C_Item.GetItemInfoInstant's itemID), which the unique-equipped check
		-- compares: a unique item without one is an error there, not a clash of two nil ids
		{ "a unique-equipped item without an item id is an error where uniqueness is checked: the hands, a ring pair", function()
			local sword = item("INVTYPE_WEAPON", { AGI = 10, DPS = 30 }, "unique"); sword.id = 777; sword.uniqueEquipped = true
			local copy = item("INVTYPE_WEAPON", { AGI = 10, DPS = 30 }, "copy"); copy.id = nil; copy.uniqueEquipped = true
			local eq = { [S.MAINHAND] = sword }
			local ok, err = pcall(Sc.Evaluate, copy, W, ctx(eq, { copy }))
			T.eq(ok, false, "a unique copy without an id")
			T.truthy(tostring(err):find("a unique-equipped item without an item id", 1, true), tostring(err))
			sword.id = nil
			ok, err = pcall(Sc.Evaluate, copy, W, ctx(eq, { copy }))
			T.eq(ok, false, "two unique items without ids")
			T.truthy(tostring(err):find("a unique-equipped item without an item id", 1, true), tostring(err))
			-- a unique ring against a worn unique ring without an id (the ring and trinket slot choice)
			local worn = item("INVTYPE_FINGER", { AGI = 2 }, "worn ring"); worn.id = nil; worn.uniqueEquipped = true
			local other = item("INVTYPE_FINGER", { AGI = 1 }, "other ring")
			local ring = item("INVTYPE_FINGER", { AGI = 5 }, "bag ring"); ring.uniqueEquipped = true
			local eqr = { [S.FINGER1] = worn, [S.FINGER2] = other }
			ok, err = pcall(Sc.Evaluate, ring, W, ctx(eqr, { ring }))
			T.eq(ok, false, "a worn unique ring without an id")
			T.truthy(tostring(err):find("a unique-equipped item without an item id", 1, true), tostring(err))
		end },
		{ "row gains — a pair counts once, a moved weapon is part of it, no row shows a loss", function()
			local mh = item("INVTYPE_WEAPON", { AGI = 6, DPS = 26 }, "mh")
			local oh = item("INVTYPE_WEAPON", { AGI = 1, DPS = 20 }, "oh")
			local eq = { [S.MAINHAND] = mh, [S.OFFHAND] = oh, [S.HEAD] = item("INVTYPE_HEAD", { AGI = 1 }, "head") }
			local big = item("INVTYPE_WEAPON", { AGI = 12, DPS = 28 }, "big")
			local helm = item("INVTYPE_HEAD", { AGI = 5 }, "helm")
			local c = ctx(eq, { big })
			local target = Sc.Plan(eq, { big, helm }, W, c)
			local rows = Sc.PlanRows(eq, target)
			Sc.RowGains(eq, target, rows, W, c)
			T.eq(#rows, 3)
			T.eq(rows[2].slot, S.MAINHAND); T.eq(rows[2].new, big)
			T.eq(rows[3].slot, S.OFFHAND); T.eq(rows[3].new, mh, "the old main hand goes to the off hand")
			T.truthy(rows[2].gain and rows[2].gain.delta > 0, "hands gain on the main-hand row")
			T.eq(rows[3].pairPart, true); T.eq(rows[3].gain, nil, "no second number for the same swap")
			local total = Sc.SetValue(target, W, c) - Sc.SetValue(eq, W, c)
			T.near(rows[1].gain.delta + rows[2].gain.delta, total, 1e-6, "independent parts add up to the total")
		end },
		-- Score.Plan: a step passes when it gains, any damage gain (the user's rule, no threshold): an off hand of +0.45
		-- damage is taken over one of equal damage and more health
		{ "plan: a step that gains less than 0.5 is taken", function()
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local m = item("INVTYPE_WEAPON", { DPS = 20 }, "m")
			local h0 = item("INVTYPE_HOLDABLE", {}, "h0")
			local eq = { [S.MAINHAND] = m, [S.OFFHAND] = h0 }
			local o2 = item("INVTYPE_WEAPON", { DPS = 5 }, "o2")      -- +0.45 damage
			local h1 = item("INVTYPE_HOLDABLE", { STA = 20 }, "h1") -- same damage, more health
			local Wd = fullW({ MH_DPS = 0.27, OH_DPS = 0.09 }) -- damage only, like Model.Weights (no STA weight)
			local c = ctx(eq, { o2 }, { pools = pools, secondaryRates = rates })
			local target = Sc.Plan(eq, { o2, h1 }, Wd, c)
			T.eq(target[S.OFFHAND], o2)
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 0.45, 1e-9, "+0.45 damage")
		end },
		{ "a worn ring is not moved to the other finger when it can stay", function()
			local R1, R2 = item("INVTYPE_FINGER", { AGI = 10 }, "R1"), item("INVTYPE_FINGER", { HIT = 2 }, "R2")
			local eq = { [S.FINGER1] = R1, [S.FINGER2] = R2, [S.HEAD] = item("INVTYPE_HEAD", {}, "H0") }
			local A, H1 = item("INVTYPE_FINGER", { AGI = 20 }, "A"), item("INVTYPE_HEAD", { HIT = 2 }, "H1")
			local target = Sc.Plan(eq, { A, H1 }, W, ctx(eq, nil, { hitCap = 3 }))
			T.eq(target[S.FINGER1], R1, "R1 stays in finger 1"); T.eq(target[S.FINGER2], A); T.eq(target[S.HEAD], H1)
			T.eq(#Sc.PlanRows(eq, target), 2)
		end },
		{ "a worn 2H replaced by an off-hand item only: the gain sits on the off-hand row", function()
			local staff = item("INVTYPE_2HWEAPON", { DPS = 30, STA = 8 }, "staff")
			local eq = { [S.MAINHAND] = staff }
			local frill = item("INVTYPE_HOLDABLE", { AGI = 5, INT = 4 }, "frill")
			local Wr = fullW({ AGI = 2.506, TH_DPS = 0.346, MH_DPS = 0.27, OH_DPS = 0.09 })
			local c = ctx(eq, { frill })
			local target = Sc.Plan(eq, { frill }, Wr, c)
			local rows = Sc.PlanRows(eq, target)
			Sc.RowGains(eq, target, rows, Wr, c)
			T.eq(#rows, 2); T.eq(rows[1].slot, S.MAINHAND); T.eq(rows[1].new, nil); T.eq(rows[1].pairPart, true)
			T.eq(rows[2].new, frill); T.truthy(rows[2].gain and rows[2].gain.verdict == "better", "gain on the frill row")
		end },
		{ "equal-damage options are ranked by the plan's own measure (vs the worn set)", function()
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local m = item("INVTYPE_WEAPON", { DPS = 20 }, "m")
			local hI = item("INVTYPE_HOLDABLE", { INT = 11 }, "hI")
			local eq = { [S.CHEST] = item("INVTYPE_CHEST", { AGI = 5, ARMOR = 200 }, "chest0"), [S.MAINHAND] = m, [S.OFFHAND] = hI }
			local chest1 = item("INVTYPE_CHEST", { AGI = 8, ARMOR = 700 }, "chest1")
			local hS = item("INVTYPE_HOLDABLE", { STA = 20 }, "hS")
			local c = ctx(eq, { hS }, { pools = pools, secondaryRates = rates })
			local Wd = fullW({ AGI = 2.5, MH_DPS = 0.27, OH_DPS = 0.09 }) -- damage only: the off hands tie on damage
			local target = Sc.Plan(eq, { chest1, hS }, Wd, c)
			T.eq(target[S.CHEST], chest1)
			local withS, withI = Sc.CopySet(target), Sc.CopySet(target)
			withS[S.OFFHAND], withI[S.OFFHAND] = hS, hI
			local best = Sc.Secondary(withS, c) > Sc.Secondary(withI, c) and hS or hI
			T.eq(target[S.OFFHAND], best, "the off hand the plan's measure prefers")
		end },
		{ "final check: the three cleanup repros keep every plan property", function()
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local Wh = fullW({ AGI = 2.5, HIT = 18 })
			local function u(it, id) it.id = id; it.uniqueEquipped = true; return it end
			local cases = {
				{ name = "not a fixed point after a revert", cap = 4,
					eq = { [S.HANDS] = item("INVTYPE_HAND", { HIT = 2 }, "gloves"), [S.TRINKET1] = item("INVTYPE_TRINKET", { HIT = 1 }, "T1"),
						[S.TRINKET2] = item("INVTYPE_TRINKET", { AGI = 3 }, "T2") },
					cands = { item("INVTYPE_TRINKET", { AGI = 2, HIT = 3 }, "TA"), item("INVTYPE_TRINKET", { AGI = 3, STA = 1 }, "TB"),
						item("INVTYPE_FINGER", { HIT = 1, STA = 1 }, "R1"), item("INVTYPE_FINGER", { HIT = 1, STA = 1 }, "R2") } },
				{ name = "unique copies", cap = 3,
					eq = { [S.NECK] = item("INVTYPE_NECK", { AGI = 3, HIT = 1 }, "neck0"), [S.HANDS] = item("INVTYPE_HAND", { AGI = 8, STA = 2 }, "gloves0"),
						[S.FINGER1] = item("INVTYPE_FINGER", { AGI = 5, STA = 1 }, "ring0"),
						[S.FINGER2] = u(item("INVTYPE_FINGER", { AGI = 1, HIT = 1, STA = 1 }, "uniqueWorn"), 100) },
					cands = { u(item("INVTYPE_FINGER", { AGI = 7, HIT = 1, STA = 1 }, "uniqueBag"), 100),
						item("INVTYPE_HAND", { AGI = 5, HIT = 2, STA = 2 }, "gloves1"), item("INVTYPE_FINGER", { AGI = 1, STA = 1 }, "ringA"),
						item("INVTYPE_NECK", { AGI = 2, HIT = 1, STA = 1 }, "neck1"), item("INVTYPE_FINGER", { HIT = 2, STA = 2 }, "ringB") } },
				{ name = "a step of hit over the cap", cap = 6,
					eq = { [S.HANDS] = item("INVTYPE_HAND", { HIT = 1 }, "gloves0"), [S.FINGER1] = item("INVTYPE_FINGER", { HIT = 4 }, "ring0"),
						[S.TRINKET1] = item("INVTYPE_TRINKET", {}, "trinket0") },
					cands = { item("INVTYPE_TRINKET", { AGI = 4, HIT = 1 }, "trinketA"), item("INVTYPE_NECK", { HIT = 2, STA = 4 }, "neckN"),
						item("INVTYPE_HAND", { STA = 4 }, "glovesB") } },
			}
			for _, cs in ipairs(cases) do
				local c = ctx(cs.eq, nil, { pools = pools, secondaryRates = rates, hitCap = cs.cap })
				local bad = planProblems(cs.eq, cs.cands, Wh, c)
				T.eq(#bad, 0, cs.name .. ": " .. table.concat(bad, "; "))
			end
		end },
		{ "plans over many generated sets keep every plan property", function()
			local seed = 12345
			local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
			local locs = { { "INVTYPE_HEAD", S.HEAD }, { "INVTYPE_HAND", S.HANDS }, { "INVTYPE_FINGER", S.FINGER1 },
				{ "INVTYPE_FINGER", S.FINGER2 }, { "INVTYPE_CHEST", S.CHEST }, { "INVTYPE_TRINKET", S.TRINKET1 },
				{ "INVTYPE_TRINKET", S.TRINKET2 } }
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local function gen(loc, name)
				local it = item(loc, { AGI = rnd(4) * 3, HIT = rnd(3), STA = rnd(12), INT = rnd(10), ARMOR = rnd(4) * 40 }, name)
				-- now and then a unique-equipped ring/trinket with a twin of other stats (enchant / suffix)
				if (loc == "INVTYPE_FINGER" or loc == "INVTYPE_TRINKET") and rnd(5) == 0 then
					it.id = (loc == "INVTYPE_FINGER" and 900 or 910) + rnd(2); it.uniqueEquipped = true -- a ring is never a trinket
				end
				return it
			end
			local bad = {}
			for n = 1, 800 do
				local eq = {}
				for _, l in ipairs(locs) do eq[l[2]] = gen(l[1], "worn") end
				-- two worn copies of one unique item cannot happen: the second becomes an item of its own id
				if eq[S.FINGER1].id == eq[S.FINGER2].id then eq[S.FINGER2].id, eq[S.FINGER2].uniqueEquipped = 990, nil end
				if eq[S.TRINKET1].id == eq[S.TRINKET2].id then eq[S.TRINKET2].id, eq[S.TRINKET2].uniqueEquipped = 991, nil end
				local cands = {}
				for k = 1, 7 do local l = locs[1 + rnd(#locs)]; cands[k] = gen(l[1], "bag" .. k) end
				local c = ctx(eq, nil, { pools = pools, secondaryRates = rates, hitCap = 1 + rnd(5) })
				for _, p in ipairs(planProblems(eq, cands, fullW({ AGI = 2.5, HIT = 18 }), c)) do bad[#bad + 1] = "set " .. n .. ": " .. p end
			end
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		-- weapons at their own speed: ctx.weaponGain (Advisor: the damage model) prices the set's weapons
		{ "weapon speed: with ctx.weaponGain the weapon-DPS terms come from it, once per set; ammo stays linear", function()
			local bow = item("INVTYPE_RANGED", { DPS = 20, AGI = 2 }, "bow"); bow.speed = 2.6
			local mh = item("INVTYPE_WEAPON", { DPS = 26, AGI = 1 }, "mh")
			local ammo = item("INVTYPE_AMMO", { AMMO_DPS = 10 }, "ammo")
			local eq = { [S.RANGED] = bow, [S.MAINHAND] = mh, [S.AMMO] = ammo }
			local cand = item("INVTYPE_RANGED", { DPS = 24.6, RANGED_FLAT = 5, AGI = 3 }, "cand"); cand.speed = 1.8
			local calls = 0
			local c = ctx(eq, nil, { weaponGain = function(set)
				calls = calls + 1
				return set[S.RANGED] == cand and 7 or 0
			end })
			calls = 0
			T.near(Sc.SetValue(eq, W, c), 2 * 2.5 + 1 * 2.5 + 10 * 10.4, 1e-9, "worn set: no weapon DPS, ammo linear")
			T.eq(calls, 1, "weaponGain once per set")
			local r = Sc.Evaluate(cand, W, c)
			T.near(r.delta, 7 + (3 - 2) * 2.5, 1e-9, "the gain + Agility; no RANGED_DPS x DPS, no scope term")
			local better = item("INVTYPE_AMMO", { AMMO_DPS = 12 }, "better")
			T.near(Sc.Evaluate(better, W, c).delta, 2 * 10.4, 1e-9, "ammo: W.AMMO_DPS")
			-- without weaponGain the linear terms stay
			T.near(Sc.Evaluate(cand, W, ctx(eq)).delta, 4.6 * 10.4 + 10.4 * 5 / 1.8 + 2.5, 1e-9, "plain W as before")
		end },
		{ "weapon speed: BestHands and Plan follow a speed-dependent weaponGain and keep every plan property", function()
			local old = item("INVTYPE_WEAPON", { DPS = 20 }, "old"); old.speed = 2.6
			local fast = item("INVTYPE_WEAPON", { DPS = 30, AGI = 1 }, "fast"); fast.speed = 1.8
			local slow = item("INVTYPE_WEAPON", { DPS = 30 }, "slow"); slow.speed = 3.6
			local eq = { [S.MAINHAND] = old, [S.HEAD] = item("INVTYPE_HEAD", { AGI = 1 }, "head") }
			-- not linear in DPS: the main hand's speed decides (a stand-in for Raptor's swing count)
			local function gain(set)
				local m = set[S.MAINHAND]
				if not m then return -20 end
				return (m.speed >= 3 and 6 or 0) + (m.stats.DPS - 20) * 0.01
			end
			local c = ctx(eq, { fast, slow }, { weaponGain = gain, dualWield = false })
			local best = Sc.BestHands(nil, eq, { fast, slow }, W, c)
			T.eq(best.mh, slow, "the slow weapon by the gain (linear MH_DPS would take the fast one)")
			local helm = item("INVTYPE_HEAD", { AGI = 3 }, "helm")
			local target = Sc.Plan(eq, { fast, slow, helm }, W, c)
			T.eq(target[S.MAINHAND], slow); T.eq(target[S.HEAD], helm)
			local bad = planProblems(eq, { fast, slow, helm }, W, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		-- Score.Verdict: any damage gain above Score.EPS is "better", whatever the survival side (the user's rule: any damage
		-- gain gets the checkmark); there is no "minor"; a change within EPS is no damage change
		{ 'verdict: any damage gain above EPS is "better"; there is no "minor"', function()
			T.eq(Sc.Verdict(0.01, 0), "better", "+0.01")
			T.eq(Sc.Verdict(0.4, -5), "better", "+0.4 with less survival")
			T.eq(Sc.Verdict(Sc.EPS / 2, 1), "better2", "within EPS: survival decides")
			T.eq(Sc.Verdict(Sc.EPS / 2, 0), "same")
			T.eq(Sc.Verdict(-0.01, 5), "worse")
			local eq = { [S.HEAD] = item("INVTYPE_HEAD", { AGI = 10 }) }
			local cand = item("INVTYPE_HEAD", { AGI = 10.04 }) -- +0.1
			T.eq(#Sc.PlanRows(eq, Sc.Plan(eq, { cand }, W, ctx(eq))), 1, "a +0.1 step")
		end },

		-- item sets: Devilsaur Armor is set 143 (Devilsaur Leggings 15062, Devilsaur Gauntlets 15063; 2 pieces:
		-- spell 460230, +2% hit) in Game/SetData.lua; the other sets here are made up for one rule each
		{ "SetData: bonuses read from the DB2 rows (tools/gen_set_data.py)", function()
			-- the bonus of set `set` at n pieces given by `spell` (ItemSetSpell row), nil when the data has none
			local function bonus(set, n, spell)
				for _, b in ipairs(ns.SetData[set]) do if b.n == n and b.spell == spell then return b end end
			end
			-- the stats of that bonus, as "KEY=v KEY=v" in key order ("unknown" for a bonus not counted)
			local function show(set, n, spell)
				local b = bonus(set, n, spell)
				if not b then return "missing" end
				if not b.stats then return "unknown" end
				local keys = {}
				for k in pairs(b.stats) do keys[#keys + 1] = k end
				table.sort(keys)
				local parts = {}
				for i, k in ipairs(keys) do parts[i] = k .. "=" .. b.stats[k] end
				return table.concat(parts, " ")
			end
			-- Embrace of the Viper 162: 9106 A_MOD_STAT misc 3 bp 10; 9140 A_MOD_ATTACK_POWER bp 10 + A_MOD_RANGED_ATTACK_POWER
			-- bp 10 (melee + ranged attack power = AP); 4 pieces 1291796, a proc
			T.eq(show(162, 2, 9106), "INT=10"); T.eq(show(162, 3, 9140), "AP=10"); T.eq(show(162, 4, 1291796), "unknown")
			-- Devilsaur Armor 143: 460230 A_MOD_HIT_CHANCE bp 2 + A_MOD_SPELL_HIT_CHANCE bp 2
			T.eq(show(143, 2, 460230), "HIT=2 SPELL_HIT=2")
			-- Black Dragon Mail 489: 15464 A_MOD_HIT_CHANCE bp 1 (+ spell hit); 7598 A_MOD_WEAPON_CRIT_PERCENT bp 2
			T.eq(show(489, 2, 15464), "HIT=1 SPELL_HIT=1"); T.eq(show(489, 3, 7598), "CRIT=2")
			-- generator rules, each on a DB2 row:
			-- A_MOD_RATING 189 hit rating / 10: Necropile Raiment 122, 2 pieces 1299734 bp 5, mask 224 (melee, ranged, spell hit)
			T.eq(show(122, 2, 1299734), "HIT=0.5 SPELL_HIT=0.5")
			-- crit rating / 14: Bloodmail Regalia 123, 5 pieces 1299738 bp 21, mask 1792 (melee, ranged, spell crit)
			T.eq(show(123, 5, 1299738), "CRIT=1.5 SPELL_CRIT=1.5")
			-- expertise rating / 10: Grovekeeper Rage 2113, 4 pieces 1301076 bp 12, mask 8388608
			T.eq(show(2113, 4, 1301076), "EXPERTISE=1.2")
			-- A_MOD_MELEE_ATTACK_POWER_VERSUS 102 + A_MOD_RANGED_ATTACK_POWER_VERSUS 131 of one amount and creature mask = the
			-- AP_VS_<TYPE> key of each type the mask names: Defias Leather 161, 3 pieces 1292025 (bp 15, misc 64 both: Humanoid,
			-- bit 1 << (7 - 1), wowsims sim/core/spelldata/mob_types.go:32-55)
			T.eq(show(161, 3, 1292025), "AP_VS_HUMANOID=15")
			-- A_MOD_CRIT_PCT 290 = physical and spell crit: The Gladiator 1, 5 pieces 1314795 bp 1
			T.eq(show(1, 5, 1314795), "CRIT=1 SPELL_CRIT=1")
			-- a set bonus's aura 342 = ATTACK_SPEED, the owner's and the pet's speed, not the hawks' (wowsims attackSpeedRow,
			-- raid-mode W1 design 7.3; aura 65 casting speed beside it): Wildstalker Armor 2101, 2 pieces 1300945 bp 1, and the
			-- other four Tier-1 two-piece bonuses, the only aura-342 set bonuses of build 70888
			T.eq(show(2101, 2, 1300945), "ATTACK_SPEED=1 CAST_SPEED=1")
			for _, b in ipairs({ { 1300934 }, { 1300951 }, { 1300957 }, { 1300968 } }) do
				local found
				for sid, def in pairs(ns.SetData) do
					for _, bonus in ipairs(def) do
						if bonus.spell == b[1] then found = bonus.stats; T.eq(bonus.n, 2, "set " .. sid) end
					end
				end
				T.truthy(found and found.ATTACK_SPEED == 1 and found.HASTE == nil, "Tier-1 two-piece " .. b[1])
			end
			-- every ItemSetSpell bonus, those wowsims' hand-written sets leave out included (aura 42 procs, aura 232, aura 161)
			T.eq(show(186, 3, 9336), "AP=30"); T.eq(show(186, 4, 1302712), "unknown") -- Beaststalker Armor
			T.eq(show(1669, 5, 1302712), "unknown"); T.eq(show(1669, 6, 14049), "AP=40") -- Beastmaster Armor
			T.eq(show(121, 3, 9140), "AP=10"); T.eq(show(121, 3, 1292546), "unknown") -- Cadaverous Garb: two bonuses at 3
			T.eq(show(184, 4, 1302698), "unknown"); T.eq(show(184, 5, 27787), "unknown"); T.eq(show(184, 6, 21347), "unknown") -- Shadowcraft
			T.eq(show(1676, 3, 21347), "unknown"); T.eq(show(1676, 4, 27787), "unknown"); T.eq(show(1676, 5, 1302698), "unknown") -- Darkmantle
			T.eq(#ns.SetData[186], 5, "Beaststalker Armor: the five ItemSetSpell rows")
			-- the profession and rank of the ItemSet row (RequiredSkill / RequiredSkillRank)
			local prof = { [421] = { 197, 300 }, [441] = { 165, 300 }, [442] = { 165, 300 }, [444] = { 164, 300 } }
			for sid, want in pairs(prof) do
				T.eq(ns.SetData[sid].skill, want[1], "set " .. sid .. " skill"); T.eq(ns.SetData[sid].skillRank, want[2], "set " .. sid .. " rank")
			end
			T.eq(ns.SetData[143].skill, nil); T.eq(ns.SetData[143].skillRank, nil)
			-- a set without ItemSetSpell rows: known, with no bonuses
			T.eq(ns.SetData[1969].name, "Goliaths' Adaptive Garments"); T.eq(#ns.SetData[1969], 0)
		end },
		{ "set bonus: completing Devilsaur Armor gains its 2% hit, under the hit cap", function()
			T.eq(ns.SetData[143][1].n, 2); T.eq(ns.SetData[143][1].stats.HIT, 2, "SetData: Devilsaur 2 pieces = 2% hit")
			local Wh = fullW({ HIT = 10 })
			local eq = { [S.LEGS] = piece("INVTYPE_LEGS", 15062, 143), [S.HANDS] = piece("INVTYPE_HAND", 1) }
			local cand = piece("INVTYPE_HAND", 15063, 143)
			local r = Sc.Evaluate(cand, Wh, ctx(eq, nil, { baseHit = 2, sets = ns.SetData }))
			T.near(r.delta, 20, 1e-9, "2% more hit below the cap")
			local r2 = Sc.Evaluate(cand, Wh, ctx(eq, nil, { baseHit = 4, sets = ns.SetData }))
			T.near(r2.delta, 10, 1e-9, "4% + 2% stops at the 5% cap: 1% counts")
		end },
		{ "set bonus: breaking Devilsaur Armor loses its 2% hit", function()
			local Wh = fullW({ HIT = 10, AGI = 1 })
			local eq = { [S.LEGS] = piece("INVTYPE_LEGS", 15062, 143), [S.HANDS] = piece("INVTYPE_HAND", 15063, 143) }
			local r = Sc.Evaluate(piece("INVTYPE_HAND", 2, nil, { AGI = 5 }), Wh, ctx(eq, nil, { sets = ns.SetData }))
			T.near(r.delta, 5 - 20, 1e-9, "+5 Agility, -2% hit")
		end },
		{ "set bonus: pieces are distinct item ids (two copies of one ring are one piece)", function()
			local data = { [9001] = { name = "two rings", { n = 2, stats = { AP = 10 } } } }
			local same = { [S.FINGER1] = piece("INVTYPE_FINGER", 77, 9001), [S.FINGER2] = piece("INVTYPE_FINGER", 77, 9001) }
			local st, by = Sc.SetBonuses(same, data)
			T.eq(by[9001].count, 1); T.eq(st.AP, nil, "one piece: no bonus")
			T.near(Sc.SetValue(same, fullW({ AP = 1 }), ctx(same, nil, { sets = data })), 0, 1e-9)
			local two = { [S.FINGER1] = piece("INVTYPE_FINGER", 77, 9001), [S.FINGER2] = piece("INVTYPE_FINGER", 78, 9001) }
			T.near(Sc.SetValue(two, fullW({ AP = 1 }), ctx(two, nil, { sets = data })), 10, 1e-9, "two pieces: +10 AP")
		end },
		{ "set bonus: an unknown bonus is reported, not valued", function()
			local data = { [9002] = { name = "half known", { n = 2, stats = { AGI = 4 } }, { n = 2, unknown = "Some Proc" },
				{ n = 3, stats = { AGI = 100 } } } }
			local set = { [S.HEAD] = piece("INVTYPE_HEAD", 1, 9002), [S.CHEST] = piece("INVTYPE_CHEST", 2, 9002) }
			local st, by = Sc.SetBonuses(set, data)
			T.eq(st.AGI, 4, "only the known 2-piece bonus; the 3-piece one is not reached")
			T.eq(#by[9002].counted, 1); T.eq(by[9002].counted[1], 2)
			T.eq(#by[9002].notCounted, 1, "the unknown bonus is reported"); T.eq(by[9002].notCounted[1], 2)
			T.near(Sc.SetValue(set, fullW({ AGI = 1 }), ctx(set, nil, { sets = data })), 4, 1e-9, "and adds nothing")
			local _, unknownSet = Sc.SetBonuses(set, {})
			T.eq(unknownSet[9002].known, false, "a set missing from the data is marked unknown")
		end },
		{ "set bonus: a set piece scored without set data is an error", function()
			local set = { [S.HEAD] = piece("INVTYPE_HEAD", 1, 143) }
			local ok, err = pcall(Sc.SetValue, set, W, ctx(set))
			T.eq(ok, false); T.truthy(tostring(err):find("without set data"), tostring(err))
		end },
		{ "set bonus: set hit past the cap still lowers dual-wield misses (HIT_DW)", function()
			local data = { [9003] = { name = "pair", { n = 2, stats = { HIT = 3 } } } }
			local set = { [S.MAINHAND] = piece("INVTYPE_WEAPON", 1, 9003, { DPS = 20 }), [S.OFFHAND] = piece("INVTYPE_WEAPON", 2, 9003, { DPS = 20 }) }
			local v = Sc.SetValue(set, fullW({ HIT = 10, HIT_DW = 3 }), ctx(set, nil, { baseHit = 4, sets = data }))
			T.near(v, 10 * 5 + 3 * 2, 1e-9, "4% + 3% = 7%: 5% under the cap, 2% dual-wield hit")
		end },
		{ "set bonus: a set whose ItemSet row needs a profession counts only at the required rank", function()
			-- Blood Tiger Harness 442: Leatherworking (SkillLine 165) at rank 300, 2 pieces: 7597 +1% crit
			local set = { [S.SHOULDER] = piece("INVTYPE_SHOULDER", 19689, 442), [S.CHEST] = piece("INVTYPE_CHEST", 19688, 442) }
			local Wc = fullW({ CRIT = 10 })
			-- the player's Leatherworking skill is `rank`; the check gets the set's skill line and rank
			local asked = {}
			local function skill(rank)
				return function(line, need)
					asked[#asked + 1] = line .. "/" .. tostring(need)
					return line == 165 and rank >= need
				end
			end
			T.near(Sc.SetValue(set, Wc, ctx(set, nil, { sets = ns.SetData, hasSkill = skill(300) })), 10, 1e-9, "rank 300: +1% crit")
			T.eq(asked[1], "165/300", "the check gets the skill line and the ItemSet rank")
			T.near(Sc.SetValue(set, Wc, ctx(set, nil, { sets = ns.SetData, hasSkill = skill(299) })), 0, 1e-9, "rank 299: nothing")
			local _, by = Sc.SetBonuses(set, ns.SetData, skill(299))
			T.eq(by[442].needsSkill, 165); T.eq(by[442].needsRank, 300)
			local _, byOk = Sc.SetBonuses(set, ns.SetData, skill(300))
			T.eq(byOk[442].needsSkill, nil); T.eq(#byOk[442].counted, 2, "7597 and 18384")
			local ok, err = pcall(Sc.SetValue, set, Wc, ctx(set, nil, { sets = ns.SetData }))
			T.eq(ok, false); T.truthy(tostring(err):find("needs a profession"), tostring(err))
			-- a set with a skill line and no rank is bad data, an error
			local bad = { [9005] = { name = "no rank", skill = 165, { n = 2, stats = { AP = 10 } } } }
			local two = { [S.HEAD] = piece("INVTYPE_HEAD", 1, 9005), [S.CHEST] = piece("INVTYPE_CHEST", 2, 9005) }
			local ok2, err2 = pcall(Sc.SetBonuses, two, bad, skill(300))
			T.eq(ok2, false); T.truthy(tostring(err2):find("without a rank"), tostring(err2))
		end },
		-- swap plan with item sets: a set step puts on the off-body pieces of one set together
		{ "plan: a set that needs two bag pieces at once is put on together (each piece alone is a loss)", function()
			-- worn legs AGI 20, gloves AGI 18; bags: Devilsaur Leggings 15062 (AGI 19) and Devilsaur
			-- Gauntlets 15063 (AGI 17), set 143 (2 pieces: 2% hit); W = { AGI = 1, HIT = 10 }: each alone -1, the pair +18
			local Wh = fullW({ AGI = 1, HIT = 10 })
			local eq = { [S.LEGS] = piece("INVTYPE_LEGS", 1, nil, { AGI = 20 }), [S.HANDS] = piece("INVTYPE_HAND", 2, nil, { AGI = 18 }) }
			local legs, gloves = piece("INVTYPE_LEGS", 15062, 143, { AGI = 19 }), piece("INVTYPE_HAND", 15063, 143, { AGI = 17 })
			local c = ctx(eq, nil, { sets = ns.SetData })
			T.near(Sc.Evaluate(legs, Wh, c).delta, -1, 1e-9, "legs alone"); T.near(Sc.Evaluate(gloves, Wh, c).delta, -1, 1e-9, "gloves alone")
			local target = Sc.Plan(eq, { legs, gloves }, Wh, c)
			T.eq(target[S.LEGS], legs); T.eq(target[S.HANDS], gloves)
			T.near(Sc.SetValue(target, Wh, c) - Sc.SetValue(eq, Wh, c), 18, 1e-9, "the pair")
			T.eq(#Sc.PlanRows(eq, target), 2)
			local bad = planProblems(eq, { legs, gloves }, Wh, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set step wears the set's weapon with its armor pieces", function()
			-- made-up set 9202 (2 pieces: +30 Agility): a neck and a one-hander, each alone -2
			local data = { [9202] = { name = "neck and sword", { n = 2, stats = { AGI = 30 } } } }
			local Wd = fullW({ AGI = 1, MH_DPS = 1 })
			local old = piece("INVTYPE_WEAPON", 1, nil, { DPS = 20, AGI = 5 })
			local eq = { [S.NECK] = piece("INVTYPE_NECK", 2, nil, { AGI = 5 }), [S.MAINHAND] = old }
			local neck = piece("INVTYPE_NECK", 6001, 9202, { AGI = 3 })
			local sword = piece("INVTYPE_WEAPON", 6002, 9202, { DPS = 20, AGI = 3 })
			local c = ctx(eq, { sword }, { sets = data, dualWield = false })
			local target = Sc.Plan(eq, { neck, sword }, Wd, c)
			T.eq(target[S.NECK], neck); T.eq(target[S.MAINHAND], sword)
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 26, 1e-9, "-2 -2 +30")
			local bad = planProblems(eq, { neck, sword }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set step wears the set's off-hand item with its armor pieces", function()
			-- made-up set 9216 (2 pieces: +30 Agility): a neck and a held-in-off-hand item, each alone -2 (AGI 3 over 5);
			-- the set piece goes into the off hand next to the worn main hand
			local data = { [9216] = { name = "neck and orb", { n = 2, stats = { AGI = 30 } } } }
			local Wd = fullW({ AGI = 1 })
			local mh = piece("INVTYPE_WEAPON", 1, nil, { DPS = 20, AGI = 5 })
			local eq = { [S.NECK] = piece("INVTYPE_NECK", 2, nil, { AGI = 5 }), [S.MAINHAND] = mh, [S.OFFHAND] = piece("INVTYPE_HOLDABLE", 3, nil, { AGI = 5 }) }
			local neck, orb = piece("INVTYPE_NECK", 6201, 9216, { AGI = 3 }), piece("INVTYPE_HOLDABLE", 6202, 9216, { AGI = 3 })
			local c = ctx(eq, { orb }, { sets = data, dualWield = false })
			local target, kinds = Sc.Plan(eq, { neck, orb }, Wd, c)
			T.eq(target[S.NECK], neck); T.eq(target[S.MAINHAND], mh); T.eq(target[S.OFFHAND], orb)
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 26, 1e-9, "-2 -2 +30")
			T.truthy(took(kinds, "set"), "a set step")
			local bad = planProblems(eq, { neck, orb }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set step wears one copy of a unique set ring", function()
			-- made-up set 9201 (2 pieces: +30 Agility): two copies of a unique ring (id 5001, AGI 8 and 7) and a one-hander;
			-- the better copy goes on, the other never joins it, though it beats the worn ring it would replace
			local data = { [9201] = { name = "ring and sword", { n = 2, stats = { AGI = 30 } } } }
			local Wd = fullW({ AGI = 1, MH_DPS = 1 })
			local r1, r2 = piece("INVTYPE_FINGER", 1, nil, { AGI = 5 }), piece("INVTYPE_FINGER", 2, nil, { AGI = 1 })
			local eq = { [S.FINGER1] = r1, [S.FINGER2] = r2, [S.MAINHAND] = piece("INVTYPE_WEAPON", 3, nil, { DPS = 20, AGI = 5 }) }
			local a1 = piece("INVTYPE_FINGER", 5001, 9201, { AGI = 7 }); a1.uniqueEquipped = true
			local a2 = piece("INVTYPE_FINGER", 5001, 9201, { AGI = 8 }); a2.uniqueEquipped = true
			local sword = piece("INVTYPE_WEAPON", 5003, 9201, { DPS = 20, AGI = 3 })
			local c = ctx(eq, { sword }, { sets = data, dualWield = false })
			local target = Sc.Plan(eq, { a1, a2, sword }, Wd, c)
			T.eq(target[S.FINGER1], r1); T.eq(target[S.FINGER2], a2); T.eq(target[S.MAINHAND], sword)
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 35, 1e-9, "+7 -2 +30")
			local bad = planProblems(eq, { a1, a2, sword }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set step leaves a worn piece of the set in its slot", function()
			-- made-up set 9203 (3 pieces: +30 Agility): helm A (worn, AGI 10), helm B (bag, AGI 0), gloves C and chest D
			-- (bag, AGI 3 each, the worn ones AGI 5): C + D reach 3 pieces with A, +26; B over A would cost 10 more and
			-- add no piece (+16)
			local data = { [9203] = { name = "three", { n = 3, stats = { AGI = 30 } } } }
			local Wd = fullW({ AGI = 1 })
			local a = piece("INVTYPE_HEAD", 7001, 9203, { AGI = 10 })
			local eq = { [S.HEAD] = a, [S.HANDS] = piece("INVTYPE_HAND", 1, nil, { AGI = 5 }), [S.CHEST] = piece("INVTYPE_CHEST", 2, nil, { AGI = 5 }) }
			local b = piece("INVTYPE_HEAD", 7002, 9203, { AGI = 0 })
			local gloves, chest = piece("INVTYPE_HAND", 7003, 9203, { AGI = 3 }), piece("INVTYPE_CHEST", 7004, 9203, { AGI = 3 })
			local c = ctx(eq, nil, { sets = data })
			local target = Sc.Plan(eq, { b, gloves, chest }, Wd, c)
			T.eq(target[S.HEAD], a); T.eq(target[S.HANDS], gloves); T.eq(target[S.CHEST], chest)
			local bad = planProblems(eq, { b, gloves, chest }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set step leaves out a copy of a worn piece (it adds no piece)", function()
			-- made-up set 9204 (3 pieces: +30 Agility): ring R (id 8001) worn in finger 1; bags: a second R (AGI 4), helm H
			-- and gloves G (AGI 3 each, the worn ones AGI 5): H + G reach 3 pieces, +26; the second R in finger 2 (over a
			-- ring of AGI 10) adds no piece and costs 6 (+20)
			local data = { [9204] = { name = "ring set", { n = 3, stats = { AGI = 30 } } } }
			local Wd = fullW({ AGI = 1 })
			local r = piece("INVTYPE_FINGER", 8001, 9204, { AGI = 5 })
			local eq = { [S.FINGER1] = r, [S.FINGER2] = piece("INVTYPE_FINGER", 1, nil, { AGI = 10 }),
				[S.HEAD] = piece("INVTYPE_HEAD", 2, nil, { AGI = 5 }), [S.HANDS] = piece("INVTYPE_HAND", 3, nil, { AGI = 5 }) }
			local copy = piece("INVTYPE_FINGER", 8001, 9204, { AGI = 4 })
			local helm, gloves = piece("INVTYPE_HEAD", 8002, 9204, { AGI = 3 }), piece("INVTYPE_HAND", 8003, 9204, { AGI = 3 })
			local c = ctx(eq, nil, { sets = data })
			local target = Sc.Plan(eq, { copy, helm, gloves }, Wd, c)
			T.eq(target[S.FINGER1], r); T.eq(target[S.FINGER2], eq[S.FINGER2]); T.eq(target[S.HEAD], helm); T.eq(target[S.HANDS], gloves)
			local bad = planProblems(eq, { copy, helm, gloves }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a weak third piece of a set does not hide the gainful pair (Embrace of the Viper)", function()
			-- set 162 Embrace of the Viper in Game/SetData.lua (2 pieces: +10 Intellect, 3: +10 attack
			-- power); worn chest / gloves / belt AGI 20 / 20 / 70; bags: 6473 (AGI 19), 10413 (AGI 19), 10412 (AGI 0);
			-- W = { AGI = 1, AP = 1, INT = 0.5 }: alone -1, -1, -70; chest + gloves +3; all three -57
			local Wv = fullW({ AGI = 1, AP = 1, INT = 0.5 })
			local eq = { [S.CHEST] = piece("INVTYPE_CHEST", 1, nil, { AGI = 20 }), [S.HANDS] = piece("INVTYPE_HAND", 2, nil, { AGI = 20 }),
				[S.WAIST] = piece("INVTYPE_WAIST", 3, nil, { AGI = 70 }) }
			local chest, gloves = piece("INVTYPE_CHEST", 6473, 162, { AGI = 19 }), piece("INVTYPE_HAND", 10413, 162, { AGI = 19 })
			local belt = piece("INVTYPE_WAIST", 10412, 162, { AGI = 0 })
			local c = ctx(eq, nil, { sets = ns.SetData })
			local all = Sc.CopySet(eq); all[S.CHEST], all[S.HANDS], all[S.WAIST] = chest, gloves, belt
			T.near(Sc.SetValue(all, Wv, c) - Sc.SetValue(eq, Wv, c), -57, 1e-9, "all three")
			local target, kinds = Sc.Plan(eq, { chest, gloves, belt }, Wv, c)
			T.eq(target[S.CHEST], chest); T.eq(target[S.HANDS], gloves); T.eq(target[S.WAIST], eq[S.WAIST], "the belt stays in the bags")
			T.near(Sc.SetValue(target, Wv, c) - Sc.SetValue(eq, Wv, c), 3, 1e-9, "the pair")
			T.truthy(took(kinds, "set"), "a set step")
			local bad = planProblems(eq, { chest, gloves, belt }, Wv, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set step wears the set's weapon with the first armor pieces in best-alone order", function()
			-- made-up set 9205 (2 pieces: +30 Agility): a neck (AGI 3 over 5), a chest (AGI 0 over 50) and a one-hander
			-- (AGI 3 over 5): the neck and the sword +26; the neck, the chest and the sword -24
			local data = { [9205] = { name = "neck, chest and sword", { n = 2, stats = { AGI = 30 } } } }
			local Wd = fullW({ AGI = 1, MH_DPS = 1 })
			local eq = { [S.NECK] = piece("INVTYPE_NECK", 1, nil, { AGI = 5 }), [S.CHEST] = piece("INVTYPE_CHEST", 2, nil, { AGI = 50 }),
				[S.MAINHAND] = piece("INVTYPE_WEAPON", 3, nil, { DPS = 20, AGI = 5 }) }
			local neck, chest = piece("INVTYPE_NECK", 6101, 9205, { AGI = 3 }), piece("INVTYPE_CHEST", 6102, 9205, { AGI = 0 })
			local sword = piece("INVTYPE_WEAPON", 6103, 9205, { DPS = 20, AGI = 3 })
			local c = ctx(eq, { sword }, { sets = data, dualWield = false })
			local target, kinds = Sc.Plan(eq, { chest, neck, sword }, Wd, c)
			T.eq(target[S.NECK], neck); T.eq(target[S.MAINHAND], sword); T.eq(target[S.CHEST], eq[S.CHEST], "the chest stays in the bags")
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 26, 1e-9, "-2 -2 +30")
			T.truthy(took(kinds, "set"), "a set step")
			local bad = planProblems(eq, { chest, neck, sword }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set ring goes over the weaker worn ring (each piece in its best slot alone)", function()
			-- made-up set 9208 (2 pieces: +15 Agility); worn rings AGI 20 and 1, worn gloves AGI 10;
			-- bags: a set ring AGI 0 and set gloves AGI 9: the ring over the AGI 1 ring with the gloves, +13 (over the
			-- AGI 20 ring: -6)
			local data = { [9208] = { name = "ring and gloves", { n = 2, stats = { AGI = 15 } } } }
			local Wd = fullW({ AGI = 1 })
			local r1 = piece("INVTYPE_FINGER", 1, nil, { AGI = 20 })
			local eq = { [S.FINGER1] = r1, [S.FINGER2] = piece("INVTYPE_FINGER", 2, nil, { AGI = 1 }), [S.HANDS] = piece("INVTYPE_HAND", 3, nil, { AGI = 10 }) }
			local ring, gloves = piece("INVTYPE_FINGER", 21, 9208, { AGI = 0 }), piece("INVTYPE_HAND", 22, 9208, { AGI = 9 })
			local c = ctx(eq, nil, { sets = data })
			local target = Sc.Plan(eq, { ring, gloves }, Wd, c)
			T.eq(target[S.FINGER1], r1); T.eq(target[S.FINGER2], ring); T.eq(target[S.HANDS], gloves)
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 13, 1e-9, "-1 -1 +15")
			local bad = planProblems(eq, { ring, gloves }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: set pieces go on best alone first (three set rings, the worst offered first)", function()
			-- made-up set 9209 (2 pieces: +5 Agility); worn rings AGI 20 / 20; set rings A 19, B 19 and
			-- C 0, C offered first: A and B, +3 (C with B: -16)
			local data = { [9209] = { name = "rings", { n = 2, stats = { AGI = 5 } } } }
			local Wd = fullW({ AGI = 1 })
			local eq = { [S.FINGER1] = piece("INVTYPE_FINGER", 1, nil, { AGI = 20 }), [S.FINGER2] = piece("INVTYPE_FINGER", 2, nil, { AGI = 20 }) }
			local a, b = piece("INVTYPE_FINGER", 11, 9209, { AGI = 19 }), piece("INVTYPE_FINGER", 12, 9209, { AGI = 19 })
			local cRing = piece("INVTYPE_FINGER", 13, 9209, { AGI = 0 })
			local c = ctx(eq, nil, { sets = data })
			local target = Sc.Plan(eq, { cRing, b, a }, Wd, c)
			T.truthy((target[S.FINGER1] == a and target[S.FINGER2] == b) or (target[S.FINGER1] == b and target[S.FINGER2] == a), "rings A and B")
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 3, 1e-9, "-1 -1 +5")
			local bad = planProblems(eq, { cRing, b, a }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a set whose bonus adds only survival is put on at equal damage, like one item with that gain", function()
			-- made-up set 9206 (2 pieces: +40 Stamina); worn head and hands AGI 10, STA 5; set pieces
			-- AGI 10, STA 4 each (equal damage, -1 Stamina alone): the pair is +38 Stamina at equal damage, the gain of
			-- a helm with 38 more Stamina
			local data = { [9206] = { name = "stamina", { n = 2, stats = { STA = 40 } } } }
			local Wd = fullW({ AGI = 1 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local eq = { [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { AGI = 10, STA = 5 }), [S.HANDS] = piece("INVTYPE_HAND", 2, nil, { AGI = 10, STA = 5 }) }
			local h, g = piece("INVTYPE_HEAD", 31, 9206, { AGI = 10, STA = 4 }), piece("INVTYPE_HAND", 32, 9206, { AGI = 10, STA = 4 })
			local c = ctx(eq, nil, { sets = data, pools = pools, secondaryRates = rates })
			local target, kinds = Sc.Plan(eq, { h, g }, Wd, c)
			T.eq(target[S.HEAD], h); T.eq(target[S.HANDS], g); T.truthy(took(kinds, "set"), "a set step")
			T.near(Sc.SetValue(target, Wd, c) - Sc.SetValue(eq, Wd, c), 0, 1e-9, "equal damage")
			local helm = piece("INVTYPE_HEAD", 33, nil, { AGI = 10, STA = 43 })
			local one = Sc.Plan(eq, { helm }, Wd, c)
			T.eq(one[S.HEAD], helm, "the helm")
			T.truthy(Sc.Secondary(target, c) > 0, "more survival")
			T.near(Sc.Secondary(target, c), Sc.Secondary(one, c), 1e-9, "the pair's survival is the helm's")
			local bad = planProblems(eq, { h, g }, Wd, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a hands configuration whose part loses is no step: its part that gains is", function()
			-- worn m0 (AGI 0) / o0 (AGI 3, off hand only); bags m1 (AGI 3) and o1 (AGI 0, STA 20, off hand only): m1 with
			-- o0 is +3; m1 with o1 is equal damage with more health, but its off hand loses 3 against o0
			local function w(name, loc, agi, sta) return item(loc, { AGI = agi, STA = sta, DPS = 20 }, name) end
			local m0, o0 = w("m0", "INVTYPE_WEAPON", 0, 0), w("o0", "INVTYPE_WEAPONOFFHAND", 3, 0)
			local m1, o1 = w("m1", "INVTYPE_WEAPON", 3, 0), w("o1", "INVTYPE_WEAPONOFFHAND", 0, 20)
			local eq = { [S.MAINHAND] = m0, [S.OFFHAND] = o0 }
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local Wa = fullW({ AGI = 1 })
			local c0 = ctx(eq, { m1, o1 }, { pools = pools, secondaryRates = rates })
			local t0 = Sc.Plan(eq, { m1, o1 }, Wa, c0)
			T.eq(t0[S.MAINHAND], m1); T.eq(t0[S.OFFHAND], o0)
			local bad0 = planProblems(eq, { m1, o1 }, Wa, c0)
			T.eq(#bad0, 0, table.concat(bad0, "; "))
		end },
		{ "plan: a set step whose piece loses is no step: the head alone, which gains, is", function()
			-- made-up set 9210 (2 pieces: +40 Stamina); worn head and hands AGI 10; set head AGI 13 (+3) and set hands AGI 7
			-- (-3): the pair is equal damage with more health, but its hands lose 3 against the worn ones
			local data = { [9210] = { name = "stamina", { n = 2, stats = { STA = 40 } } } }
			local Wd = fullW({ AGI = 1 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local eq = { [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { AGI = 10 }), [S.HANDS] = piece("INVTYPE_HAND", 2, nil, { AGI = 10 }) }
			local h, g = piece("INVTYPE_HEAD", 41, 9210, { AGI = 13 }), piece("INVTYPE_HAND", 42, 9210, { AGI = 7 })
			-- the head alone is a step; the set hands then lose 3 for the Stamina
			local c0 = ctx(eq, nil, { sets = data, pools = pools, secondaryRates = rates })
			local t0 = Sc.Plan(eq, { h, g }, Wd, c0)
			T.eq(t0[S.HEAD], h); T.eq(t0[S.HANDS], eq[S.HANDS])
			local bad0 = planProblems(eq, { h, g }, Wd, c0)
			T.eq(#bad0, 0, table.concat(bad0, "; "))
		end },
		{ "plan: the best part of a set step takes its place (a set step without its middle placement)", function()
			-- made-up set 9211 (2 pieces: +10 Agility, 3 pieces: +11 Agility); W = { AGI = 1, HIT = 10 }, hit cap 1%; worn
			-- head AGI 11, gloves AGI 12, chest AGI 3; bags: set head HIT 1 (-1 alone), set gloves HIT 1 (-2), set chest
			-- AGI 0 (-3). Best-alone order head, gloves, chest: head + gloves -3 (one hit over the cap), all three +5; their
			-- part without the gloves, head + chest, is +6 and no set step of its own (the gloves are the middle placement)
			local data = { [9211] = { name = "middle", { n = 2, stats = { AGI = 10 } }, { n = 3, stats = { AGI = 11 } } } }
			local Wh = fullW({ AGI = 1, HIT = 10 })
			local eq = { [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { AGI = 11 }), [S.HANDS] = piece("INVTYPE_HAND", 2, nil, { AGI = 12 }),
				[S.CHEST] = piece("INVTYPE_CHEST", 3, nil, { AGI = 3 }) }
			local head, gloves = piece("INVTYPE_HEAD", 11, 9211, { HIT = 1 }), piece("INVTYPE_HAND", 12, 9211, { HIT = 1 })
			local chest = piece("INVTYPE_CHEST", 13, 9211, { AGI = 0 })
			local c = ctx(eq, nil, { sets = data, hitCap = 1 })
			local all = Sc.CopySet(eq); all[S.HEAD], all[S.HANDS], all[S.CHEST] = head, gloves, chest
			T.near(Sc.SetValue(all, Wh, c) - Sc.SetValue(eq, Wh, c), 5, 1e-9, "all three")
			for _, order in ipairs({ { head, gloves, chest }, { chest, gloves, head } }) do
				local target, kinds = Sc.Plan(eq, order, Wh, c)
				T.eq(target[S.HEAD], head); T.eq(target[S.CHEST], chest); T.eq(target[S.HANDS], eq[S.HANDS], "the gloves stay in the bags")
				T.near(Sc.SetValue(target, Wh, c) - Sc.SetValue(eq, Wh, c), 6, 1e-9, "head and chest")
				-- one step: the part takes the set step's place (no step of all three, then the gloves' undo)
				T.eq(table.concat(kinds, ","), "set", "one set step")
				local bad = planProblems(eq, order, Wh, c)
				T.eq(#bad, 0, table.concat(bad, "; "))
			end
		end },
		{ "plan: the best of the parts that beat a set step takes its place, not the first in slot order", function()
			-- made-up set 9214 (2 pieces: +10 Agility, 3 pieces: +11 Agility); W = { AGI = 1, HIT = 10 }, hit cap 1%; worn
			-- head AGI 12, chest AGI 4, gloves AGI 13; bags: set head HIT 1 (-2 alone), set gloves HIT 1 (-3), set chest
			-- AGI 0 (-4). All three +2; its parts in slot order: without the head +3, without the chest -5, without the
			-- gloves +4 (head + chest, the best)
			local data = { [9214] = { name = "best part", { n = 2, stats = { AGI = 10 } }, { n = 3, stats = { AGI = 11 } } } }
			local Wh = fullW({ AGI = 1, HIT = 10 })
			local eq = { [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { AGI = 12 }), [S.HANDS] = piece("INVTYPE_HAND", 2, nil, { AGI = 13 }),
				[S.CHEST] = piece("INVTYPE_CHEST", 3, nil, { AGI = 4 }) }
			local head, gloves = piece("INVTYPE_HEAD", 11, 9214, { HIT = 1 }), piece("INVTYPE_HAND", 12, 9214, { HIT = 1 })
			local chest = piece("INVTYPE_CHEST", 13, 9214, { AGI = 0 })
			local c = ctx(eq, nil, { sets = data, hitCap = 1 })
			local all = Sc.CopySet(eq); all[S.HEAD], all[S.HANDS], all[S.CHEST] = head, gloves, chest
			T.near(Sc.SetValue(all, Wh, c) - Sc.SetValue(eq, Wh, c), 2, 1e-9, "all three")
			local target, kinds = Sc.Plan(eq, { head, gloves, chest }, Wh, c)
			T.eq(target[S.HEAD], head); T.eq(target[S.CHEST], chest); T.eq(target[S.HANDS], eq[S.HANDS], "the gloves stay in the bags")
			T.near(Sc.SetValue(target, Wh, c) - Sc.SetValue(eq, Wh, c), 4, 1e-9, "head and chest")
			T.eq(table.concat(kinds, ","), "set", "one set step: its best part")
			local bad = planProblems(eq, { head, gloves, chest }, Wh, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a part that takes a set step's place is checked part by part again", function()
			-- made-up set 9215 (2 pieces: +40 Stamina, 3 pieces: +4 Agility); worn head AGI 0, gloves AGI 3, chest AGI 4
			-- STA 10; bags: set head AGI 3 (+3 alone), set gloves AGI 0 (-3), set chest AGI 0 STA 0 (-4). All three: equal
			-- damage, +30 Stamina; its best part, head + gloves: equal damage, +40 Stamina; that part's own best part, the
			-- head alone: +3, the plan.
			local data = { [9215] = { name = "two levels", { n = 2, stats = { STA = 40 } }, { n = 3, stats = { AGI = 4 } } } }
			local Wa = fullW({ AGI = 1 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local eq = { [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { AGI = 0 }), [S.HANDS] = piece("INVTYPE_HAND", 2, nil, { AGI = 3 }),
				[S.CHEST] = piece("INVTYPE_CHEST", 3, nil, { AGI = 4, STA = 10 }) }
			local head, gloves = piece("INVTYPE_HEAD", 31, 9215, { AGI = 3 }), piece("INVTYPE_HAND", 32, 9215, { AGI = 0 })
			local chest = piece("INVTYPE_CHEST", 33, 9215, { AGI = 0, STA = 0 })
			local c = ctx(eq, nil, { sets = data, pools = pools, secondaryRates = rates })
			local all = Sc.CopySet(eq); all[S.HEAD], all[S.HANDS], all[S.CHEST] = head, gloves, chest
			local two = Sc.CopySet(eq); two[S.HEAD], two[S.HANDS] = head, gloves
			T.near(Sc.SetValue(all, Wa, c), Sc.SetValue(eq, Wa, c), 1e-9, "all three: equal damage")
			T.near(Sc.SetValue(two, Wa, c), Sc.SetValue(eq, Wa, c), 1e-9, "head + gloves: equal damage")
			T.truthy(Sc.Secondary(two, c) > Sc.Secondary(all, c), "head + gloves: more health than all three")
			local target = Sc.Plan(eq, { head, gloves, chest }, Wa, c)
			T.eq(target[S.HEAD], head); T.eq(target[S.HANDS], eq[S.HANDS]); T.eq(target[S.CHEST], eq[S.CHEST])
			T.near(Sc.SetValue(target, Wa, c) - Sc.SetValue(eq, Wa, c), 3, 1e-9, "the head alone")
			local bad = planProblems(eq, { head, gloves, chest }, Wa, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a part of a set step puts both hands back together (a set one-hander and an off-hand item over a two-hander)", function()
			-- made-up set 9212 (2 pieces: +40 Stamina); worn head AGI 0 and a two-hander AGI 5; bags: set helm AGI 3, set
			-- main-hand weapon AGI 0 and an off-hand item AGI 2: helm, one-hander and off-hand item are equal damage with
			-- more health; with both hands back (the two-hander) the helm alone is +3, the plan. Putting back the main hand
			-- alone (the two-hander with the off-hand item) is no wearable set.
			local data = { [9212] = { name = "stamina", { n = 2, stats = { STA = 40 } } } }
			local Wa = fullW({ AGI = 1 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local twoH = piece("INVTYPE_2HWEAPON", 2, nil, { AGI = 5, DPS = 30 })
			local eq = { [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { AGI = 0 }), [S.MAINHAND] = twoH }
			local helm = piece("INVTYPE_HEAD", 11, 9212, { AGI = 3 })
			local sword = piece("INVTYPE_WEAPONMAINHAND", 12, 9212, { AGI = 0, DPS = 30 })
			local orb = piece("INVTYPE_HOLDABLE", 13, nil, { AGI = 2 })
			local all = Sc.CopySet(eq); all[S.HEAD], all[S.MAINHAND], all[S.OFFHAND] = helm, sword, orb
			local c0 = ctx(eq, { sword, orb }, { sets = data, dualWield = false, pools = pools, secondaryRates = rates })
			T.eq(Sc.Verdict(Sc.SetValue(all, Wa, c0) - Sc.SetValue(eq, Wa, c0), Sc.Secondary(all, c0)), "better2", "the set step alone")
			local t0 = Sc.Plan(eq, { helm, sword, orb }, Wa, c0)
			T.eq(t0[S.HEAD], helm); T.eq(t0[S.MAINHAND], twoH); T.eq(t0[S.OFFHAND], nil)
			local bad0 = planProblems(eq, { helm, sword, orb }, Wa, c0)
			T.eq(#bad0, 0, table.concat(bad0, "; "))
		end },
		{ "plan: a generated set step next to a worn two-hander whose hands part beats it is no step", function()
			-- a plan from random sets (made-up sets 9401 2: +1% hit, 3: +3 Agility; 9402 2: +15 Stamina; 9403 2: +2 Agility,
			-- 3: +10 Stamina, 4: +4 Agility), hit cap 2%, no dual wield: the set ring 900 (set 9401) with a main-hand weapon
			-- of set 9403 and a held-in-off-hand item of set 9401 over the worn two-hander is equal damage with more health;
			-- with both hands back the ring alone is +1. The plan: the helm bag6 and the ring bag1, +4
			local data = {
				[9401] = { name = "hit", { n = 2, stats = { HIT = 1 } }, { n = 3, stats = { AGI = 3 } } },
				[9402] = { name = "sta", { n = 2, stats = { STA = 15 } } },
				[9403] = { name = "agi", { n = 2, stats = { AGI = 2 } }, { n = 3, stats = { STA = 10 } }, { n = 4, stats = { AGI = 4 } } },
			}
			local Wx = fullW({ AGI = 1, HIT = 2, MH_DPS = 0.25, OH_DPS = 0.125, TH_DPS = 0.5, HIT_DW = 0.5 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local function it(name, loc, a, h, s, dps, set, id, u)
				return { name = name, equipLoc = loc, stats = { AGI = a, HIT = h, STA = s, DPS = dps }, procs = {}, setID = set, id = id, uniqueEquipped = u }
			end
			local eq = {
				[S.HEAD] = it("head", "INVTYPE_HEAD", 1, 1, 4, nil, nil, 25413),
				[S.MAINHAND] = it("2h", "INVTYPE_2HWEAPON", 1, 1, 8, 20, 9403, 25418),
				[S.HANDS] = it("gloves", "INVTYPE_HAND", 1, 1, 0, nil, 9401, 25414),
				[S.FINGER1] = it("ring1", "INVTYPE_FINGER", 1, 0, 4, nil, nil, 25415),
				[S.FINGER2] = it("ring2", "INVTYPE_FINGER", 2, 0, 8, nil, nil, 25416),
				[S.CHEST] = it("chest", "INVTYPE_CHEST", 3, 0, 8, nil, nil, 25417),
			}
			local w3 = it("bagW3", "INVTYPE_WEAPONMAINHAND", 3, 0, 4, 20, 9402, 25421)
			local w5 = it("bagW5", "INVTYPE_HOLDABLE", 1, 0, 4, nil, 9401, 25423)
			local w7 = it("bagW7", "INVTYPE_WEAPONMAINHAND", 1, 0, 4, 20, 9403, 25425)
			local cands = { it("bag1", "INVTYPE_FINGER", 1, 0, 8, nil, 9403, 25419), it("bag2", "INVTYPE_FINGER", 0, 1, 8, nil, nil, 25420), w3,
				it("bag4", "INVTYPE_FINGER", 2, 1, 8, nil, 9401, 900, true), w5, it("bag6", "INVTYPE_HEAD", 3, 0, 4, nil, nil, 25424), w7 }
			local c = ctx(eq, { w3, w5, w7 }, { sets = data, dualWield = false, hitCap = 2, pools = pools, secondaryRates = rates })
			local step = Sc.CopySet(eq); step[S.FINGER1], step[S.MAINHAND], step[S.OFFHAND] = cands[4], w7, w5
			T.eq(Sc.Verdict(Sc.SetValue(step, Wx, c) - Sc.SetValue(eq, Wx, c), Sc.Secondary(step, c)), "better2", "the set step alone")
			local target = Sc.Plan(eq, cands, Wx, c)
			local rows = Sc.PlanRows(eq, target)
			T.eq(#rows, 2); T.eq(target[S.HEAD], cands[6]); T.eq(target[S.FINGER1], cands[1])
			T.eq(target[S.MAINHAND], eq[S.MAINHAND], "the two-hander stays"); T.eq(target[S.OFFHAND], nil)
			T.near(Sc.SetValue(target, Wx, c) - Sc.SetValue(eq, Wx, c), 4, 1e-9, "+4")
			local bad = planProblems(eq, cands, Wx, c)
			T.eq(#bad, 0, table.concat(bad, "; "))
		end },
		{ "plan: a dual-wield set step whose one-hand parts are wearable and lose is no step when its both-hands part beats it", function()
			-- a plan from random sets (made-up sets 9401 2: +1% hit, 3: +3 Agility; 9402 2: +15 Stamina; 9403 2: +2 Agility,
			-- 3: +10 Stamina, 4: +4 Agility), dual wield, hit cap 0% (all hit past it, at W.HIT_DW), two worn one-handers of
			-- set 9403. The set step: the set ring of 9401 in the first ring slot, the set one-hander of 9401 in the main hand
			-- and a one-hander of 9402 in the off hand, equal damage (26) with more health. Each one-hand part is a wearable
			-- pair and loses (25.5 each); the step with both hands put back, the ring alone, is +1 (27), the plan
			local data = {
				[9401] = { name = "hit", { n = 2, stats = { HIT = 1 } }, { n = 3, stats = { AGI = 3 } } },
				[9402] = { name = "sta", { n = 2, stats = { STA = 15 } } },
				[9403] = { name = "agi", { n = 2, stats = { AGI = 2 } }, { n = 3, stats = { STA = 10 } }, { n = 4, stats = { AGI = 4 } } },
			}
			local Wx = fullW({ AGI = 1, HIT = 2, MH_DPS = 0.25, OH_DPS = 0.125, TH_DPS = 0.5, HIT_DW = 0.5 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local function it(name, loc, a, h, s, dps, set, id)
				return { name = name, equipLoc = loc, stats = { AGI = a, HIT = h, STA = s, DPS = dps }, procs = {}, setID = set, id = id }
			end
			local eq = {
				[S.HEAD] = it("head", "INVTYPE_HEAD", 2, 0, 4, nil, 9402, 36366),
				[S.MAINHAND] = it("mh", "INVTYPE_WEAPON", 2, 0, 0, 24, 9403, 36371),
				[S.HANDS] = it("hands", "INVTYPE_HAND", 2, 1, 0, nil, 9402, 36367),
				[S.FINGER1] = it("ring1", "INVTYPE_FINGER", 2, 1, 0, nil, nil, 36368),
				[S.FINGER2] = it("ring2", "INVTYPE_FINGER", 3, 1, 8, nil, 9402, 36369),
				[S.OFFHAND] = it("oh", "INVTYPE_WEAPON", 2, 1, 4, 24, 9403, 36372),
				[S.CHEST] = it("chest", "INVTYPE_CHEST", 0, 0, 0, nil, nil, 36370),
			}
			local w1 = it("bagW1", "INVTYPE_WEAPON", 3, 1, 8, 20, 9402, 36373)
			local ring = it("bag2", "INVTYPE_FINGER", 3, 1, 0, nil, 9401, 36374)
			local w3 = it("bagW3", "INVTYPE_WEAPON", 2, 0, 0, 24, 9401, 36375)
			local cands = { w1, ring, w3 }
			local c = ctx(eq, { w1, w3 }, { sets = data, hitCap = 0, pools = pools, secondaryRates = rates })
			local v0 = Sc.SetValue(eq, Wx, c)
			T.near(v0, 26, 1e-9, "the worn set")
			local step = Sc.CopySet(eq); step[S.FINGER1], step[S.MAINHAND], step[S.OFFHAND] = ring, w3, w1
			T.near(Sc.SetValue(step, Wx, c), v0, 1e-9, "the set step: equal damage")
			T.eq(Sc.Verdict(Sc.SetValue(step, Wx, c) - v0, Sc.Secondary(step, c)), "better2", "the set step alone")
			-- both one-hand parts are wearable pairs (two one-handers, dual wield) and lose to the step
			local mhBack = Sc.CopySet(step); mhBack[S.MAINHAND] = eq[S.MAINHAND]
			local ohBack = Sc.CopySet(step); ohBack[S.OFFHAND] = eq[S.OFFHAND]
			T.near(Sc.SetValue(mhBack, Wx, c), 25.5, 1e-9, "main hand back: below the step")
			T.near(Sc.SetValue(ohBack, Wx, c), 25.5, 1e-9, "off hand back: below the step")
			local ringOnly = Sc.CopySet(eq); ringOnly[S.FINGER1] = ring
			T.near(Sc.SetValue(ringOnly, Wx, c) - v0, 1, 1e-9, "both hands back: the ring alone, +1")
			local t0 = Sc.Plan(eq, cands, Wx, c)
			local rows0 = Sc.PlanRows(eq, t0)
			T.eq(#rows0, 1, "one row"); T.eq(rows0[1].slot, S.FINGER1); T.eq(rows0[1].new, ring)
			local bad0 = planProblems(eq, cands, Wx, c)
			T.eq(#bad0, 0, table.concat(bad0, "; "))
		end },
		{ "plan: a part of a set step puts back a hand the step empties", function()
			-- made-up set 9213 (2 pieces: +5 Agility, +40 Stamina); no dual wield; worn head AGI 2, a one-hander AGI 0 and an
			-- off-hand item AGI 3; bags: set helm AGI 0 and set one-hander AGI 0. The set step helm + set one-hander with the
			-- off hand empty is equal damage with more health; its part with the off-hand item back is +3, the plan; its other
			-- parts lose (head back: 2, main hand back: 0, both hands back: 3, against 5)
			local data = { [9213] = { name = "empty hand", { n = 2, stats = { AGI = 5, STA = 40 } } } }
			local Wa = fullW({ AGI = 1 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local mh, oh = piece("INVTYPE_WEAPON", 2, nil, { AGI = 0, DPS = 20 }), piece("INVTYPE_HOLDABLE", 3, nil, { AGI = 3 })
			local eq = { [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { AGI = 2 }), [S.MAINHAND] = mh, [S.OFFHAND] = oh }
			local helm, sword = piece("INVTYPE_HEAD", 21, 9213, { AGI = 0 }), piece("INVTYPE_WEAPON", 22, 9213, { AGI = 0, DPS = 20 })
			local c0 = ctx(eq, { sword }, { sets = data, dualWield = false, pools = pools, secondaryRates = rates })
			local step = Sc.CopySet(eq); step[S.HEAD], step[S.MAINHAND], step[S.OFFHAND] = helm, sword, nil
			T.eq(Sc.Verdict(Sc.SetValue(step, Wa, c0) - Sc.SetValue(eq, Wa, c0), Sc.Secondary(step, c0)), "better2", "the set step alone")
			local t0 = Sc.Plan(eq, { helm, sword }, Wa, c0)
			T.eq(t0[S.HEAD], helm); T.eq(t0[S.MAINHAND], sword); T.eq(t0[S.OFFHAND], oh)
			local bad0 = planProblems(eq, { helm, sword }, Wa, c0)
			T.eq(#bad0, 0, table.concat(bad0, "; "))
		end },
		{ "plan: plans over many generated sets with item set pieces keep every plan property", function()
			local seed = 4242
			local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
			-- made-up sets: 9301 (2: +8 Agility, 3: +2% hit), 9302 (2: +20 Stamina, 4: +15 Agility)
			local data = {
				[9301] = { name = "a", { n = 2, stats = { AGI = 8 } }, { n = 3, stats = { HIT = 2 } } },
				[9302] = { name = "b", { n = 2, stats = { STA = 20 } }, { n = 4, stats = { AGI = 15 } } },
			}
			local locs = { { "INVTYPE_HEAD", S.HEAD }, { "INVTYPE_HAND", S.HANDS }, { "INVTYPE_FINGER", S.FINGER1 },
				{ "INVTYPE_FINGER", S.FINGER2 }, { "INVTYPE_CHEST", S.CHEST }, { "INVTYPE_TRINKET", S.TRINKET1 },
				{ "INVTYPE_TRINKET", S.TRINKET2 } }
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local nextID = 1000
			-- the set of a unique twin's id (one item id has one set)
			local twinSet = { [900] = 9301, [901] = nil, [910] = 9302, [911] = 9301 }
			local function gen(loc, name)
				local it = item(loc, { AGI = rnd(4) * 3, HIT = rnd(3), STA = rnd(12), INT = rnd(10), ARMOR = rnd(4) * 40 }, name)
				nextID = nextID + 1
				it.id = nextID
				it.setID = ({ false, false, 9301, 9302 })[1 + rnd(4)] or nil
				if (loc == "INVTYPE_FINGER" or loc == "INVTYPE_TRINKET") and rnd(5) == 0 then
					it.id = (loc == "INVTYPE_FINGER" and 900 or 910) + rnd(2); it.uniqueEquipped = true
					it.setID = twinSet[it.id]
				end
				return it
			end
			local bad, setSteps = {}, 0
			for n = 1, 500 do
				local eq = {}
				for _, l in ipairs(locs) do eq[l[2]] = gen(l[1], "worn") end
				for _, p in ipairs({ { S.FINGER1, S.FINGER2 }, { S.TRINKET1, S.TRINKET2 } }) do
					local a, b = eq[p[1]], eq[p[2]]
					if a.uniqueEquipped and b.uniqueEquipped and a.id == b.id then b.id, b.uniqueEquipped, b.setID = nextID + 5000, nil, nil end
				end
				local cands = {}
				for k = 1, 7 do local l = locs[1 + rnd(#locs)]; cands[k] = gen(l[1], "bag" .. k) end
				local c = ctx(eq, nil, { pools = pools, secondaryRates = rates, hitCap = 1 + rnd(5), sets = data })
				local probs, kinds = planProblems(eq, cands, fullW({ AGI = 2.5, HIT = 18 }), c)
				for _, p in ipairs(probs) do bad[#bad + 1] = "set " .. n .. ": " .. p end
				-- count the plans that took a set step (Score.Plan's step kinds)
				if took(kinds, "set") then setSteps = setSteps + 1 end
			end
			T.eq(#bad, 0, table.concat(bad, "; "))
			T.truthy(setSteps > 0, "some plans take a set step")
		end },
		{ "plan: plans over many generated sets with weapons and survival-only sets keep every plan property", function()
			local seed = 777
			local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
			-- made-up sets: 9301 (2: +8 Agility, 3: +2% hit), 9302 (2: +20 Stamina, 4: +15 Agility), 9303 (2: +30
			-- Stamina, survival only), 9304 (2: +6 Agility, 3: +200 armor); any piece, weapons included, can be in one
			local data = {
				[9301] = { name = "a", { n = 2, stats = { AGI = 8 } }, { n = 3, stats = { HIT = 2 } } },
				[9302] = { name = "b", { n = 2, stats = { STA = 20 } }, { n = 4, stats = { AGI = 15 } } },
				[9303] = { name = "survival", { n = 2, stats = { STA = 30 } } },
				[9304] = { name = "weapons", { n = 2, stats = { AGI = 6 } }, { n = 3, stats = { ARMOR = 200 } } },
			}
			local armorLocs = { { "INVTYPE_HEAD", S.HEAD }, { "INVTYPE_HAND", S.HANDS }, { "INVTYPE_FINGER", S.FINGER1 },
				{ "INVTYPE_FINGER", S.FINGER2 }, { "INVTYPE_CHEST", S.CHEST }, { "INVTYPE_TRINKET", S.TRINKET1 },
				{ "INVTYPE_TRINKET", S.TRINKET2 } }
			local weaponLocs = { "INVTYPE_WEAPON", "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON",
				"INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE" }
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local nextID = 1000
			-- unique twins (one item id has one set): rings 900 / 901, trinkets 910 / 911, one-handers 920 / 921
			local twinSet = { [900] = 9301, [910] = 9302, [911] = 9303, [920] = 9304 }
			local function gen(loc, name)
				local it = item(loc, { AGI = rnd(4) * 3, HIT = rnd(3), STA = rnd(12), INT = rnd(10), ARMOR = rnd(4) * 40 }, name)
				if Sc.WEAPON_LOCS[loc] and loc ~= "INVTYPE_HOLDABLE" then it.stats.DPS = 20 + rnd(3) * 5 end
				nextID = nextID + 1
				it.id = nextID
				it.setID = ({ false, false, 9301, 9302, 9303, 9304 })[1 + rnd(6)] or nil
				local twin = (loc == "INVTYPE_FINGER" and 900) or (loc == "INVTYPE_TRINKET" and 910) or (loc == "INVTYPE_WEAPON" and 920)
				if twin and rnd(5) == 0 then
					it.id = twin + rnd(2); it.uniqueEquipped = true
					it.setID = twinSet[it.id]
				end
				return it
			end
			local Wx = fullW({ AGI = 2.5, HIT = 18, MH_DPS = 0.27, OH_DPS = 0.09, TH_DPS = 0.35, HIT_DW = 4 })
			local bad, setPlans, handsPlans = {}, 0, 0
			for n = 1, 400 do
				local eq = {}
				for _, l in ipairs(armorLocs) do eq[l[2]] = gen(l[1], "worn") end
				local dw = rnd(2) == 0
				eq[S.MAINHAND] = gen(({ "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON" })[1 + rnd(3)], "wornMH")
				if not Sc.IsTwoHand(eq[S.MAINHAND]) then
					local oh = gen(dw and ({ "INVTYPE_WEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE" })[1 + rnd(3)] or "INVTYPE_HOLDABLE", "wornOH")
					if rnd(4) > 0 then eq[S.OFFHAND] = oh end
				end
				for _, p in ipairs({ { S.FINGER1, S.FINGER2 }, { S.TRINKET1, S.TRINKET2 }, { S.MAINHAND, S.OFFHAND } }) do
					local a, b = eq[p[1]], eq[p[2]]
					if a and b and a.uniqueEquipped and b.uniqueEquipped and a.id == b.id then b.id, b.uniqueEquipped, b.setID = nextID + 5000, nil, nil end
				end
				local cands, pool = {}, {}
				for k = 1, 9 do
					if rnd(3) == 0 then
						cands[k] = gen(weaponLocs[1 + rnd(#weaponLocs)], "bagW" .. k); pool[#pool + 1] = cands[k]
					else
						local l = armorLocs[1 + rnd(#armorLocs)]; cands[k] = gen(l[1], "bag" .. k)
					end
				end
				local c = ctx(eq, pool, { pools = pools, secondaryRates = rates, hitCap = 1 + rnd(5), sets = data, dualWield = dw })
				local probs, kinds = planProblems(eq, cands, Wx, c)
				for _, p in ipairs(probs) do bad[#bad + 1] = "set " .. n .. ": " .. p end
				if took(kinds, "set") then setPlans = setPlans + 1 end
				if took(kinds, "hands") then handsPlans = handsPlans + 1 end
			end
			T.eq(#bad, 0, table.concat(bad, "; "))
			T.truthy(setPlans > 0, "some plans take a set step")
			T.truthy(handsPlans > 0, "some plans take a hands step")
		end },
		{ "set bonus: a set piece without an item id is an error", function()
			local set = { [S.HEAD] = piece("INVTYPE_HEAD", 1, 143), [S.CHEST] = { equipLoc = "INVTYPE_CHEST", setID = 143, stats = {}, procs = {}, name = "no id" } }
			local ok, err = pcall(Sc.SetBonuses, set, ns.SetData)
			T.eq(ok, false); T.truthy(tostring(err):find("set piece without an item id: no id"), tostring(err))
		end },
		{ "set bonus: survival counts a set bonus' stamina", function()
			local data = { [9004] = { name = "stamina", { n = 2, stats = { STA = 20 } } } }
			local a, b = piece("INVTYPE_HEAD", 1, 9004), piece("INVTYPE_CHEST", 2, 9004)
			local eq = { [S.HEAD] = a, [S.CHEST] = piece("INVTYPE_CHEST", 3) }
			local c = ctx(eq, nil, { sets = data, pools = { hp = 1000, mana = 0, armor = 0, level = 60 },
				secondaryRates = { hpPerSta = 10, hpMult = 1, manaPerInt = 15, manaPerMp5 = 12, manaPerSpi = 1 } })
			local _, hp = Sc.Secondary({ [S.HEAD] = a, [S.CHEST] = b }, c)
			T.near(hp, 20, 1e-9, "+20 Stamina = +200 health = +20%")
		end },

		-- stats-gear-10: Beastslaying (SpellItemEnchantment 249 / 853, aura 59 on Beasts): flat damage per hit of the hunter's
		-- weapon strikes and shots (Model.Parts flat), its aura the player's whichever hand carries it. Without ctx.weaponGain
		-- Score.ItemValue prices it at W.BEAST_SLAYING on a weapon in either hand; with ctx.weaponGain the set's weapon run
		-- holds it (Player.WeaponInputs beastSlaying) and ItemValue leaves it out
		{ "stats-gear-10: Beastslaying at W.BEAST_SLAYING on a weapon in either hand; inside ctx.weaponGain when it runs", function()
			local function weapon(id, speed, stats) local w = piece("INVTYPE_WEAPON", id, nil, stats or { DPS = 20 }); w.speed = speed; return w end
			local Wb = fullW({ MH_DPS = 0.27, OH_DPS = 0.09, TH_DPS = 0.35, BEAST_SLAYING = 0.8 })
			local eq = { [S.MAINHAND] = weapon(1, 2.4) }
			local cand = weapon(2, 2.4, { DPS = 20, BEAST_SLAYING = 6 })
			T.near(Sc.Evaluate(cand, Wb, ctx(eq, nil, { dualWield = false })).delta, 6 * 0.8, 1e-12, "+6 a hit at W.BEAST_SLAYING")
			-- the aura is the player's: an enchanted off hand gives the same, whatever the hands' speeds
			local mh, plainOH, beastOH = weapon(3, 2.0), weapon(4, 2.6), weapon(5, 2.6, { DPS = 20, BEAST_SLAYING = 6 })
			local c = ctx({}, nil, {})
			local function gain(a, b) return Sc.SetValue(a, Wb, c) - Sc.SetValue(b, Wb, c) end
			T.near(gain({ [S.MAINHAND] = mh, [S.OFFHAND] = beastOH }, { [S.MAINHAND] = mh, [S.OFFHAND] = plainOH }), 6 * 0.8, 1e-12,
				"the off hand's")
			local beastMH = weapon(6, 2.0, { DPS = 20, BEAST_SLAYING = 2 })
			T.near(gain({ [S.MAINHAND] = beastMH, [S.OFFHAND] = beastOH }, { [S.MAINHAND] = mh, [S.OFFHAND] = plainOH }), (2 + 6) * 0.8,
				1e-12, "both hands: summed")
			T.near(gain({ [S.OFFHAND] = beastOH }, { [S.OFFHAND] = plainOH }), 6 * 0.8, 1e-12, "empty main hand")
			local staff = piece("INVTYPE_2HWEAPON", 7, nil, { DPS = 30, BEAST_SLAYING = 6 }); staff.speed = 3.4
			local plainStaff = piece("INVTYPE_2HWEAPON", 8, nil, { DPS = 30 }); plainStaff.speed = 3.4
			T.near(gain({ [S.MAINHAND] = staff }, { [S.MAINHAND] = plainStaff }), 6 * 0.8, 1e-12, "a two-hander")
			-- ctx.weaponGain runs the set's weapons, Beastslaying in them: the item's stat terms leave it out
			T.near(Sc.ItemValue(cand, "mh", Wb, true), 0, 1e-12, "noWeaponDPS: no Beastslaying term")
			local cw = ctx(eq, nil, { dualWield = false, wornHit = 0,
				weaponGain = function(set) return set[S.MAINHAND] == cand and 3 or 0 end })
			T.near(Sc.Evaluate(cand, Wb, cw).delta, 3, 1e-12, "the weapon run's gain alone")
		end },
		-- the model's own weight: with no melee (Player.Snapshot outside the Survival branch) Beastslaying still reaches the
		-- shots, so a two-hander's Beastslaying is worth W.BEAST_SLAYING > 0 a point, the derivative of Model.Total by
		-- p.beastSlaying in the weights' unit (the model is linear in it)
		{ "Beastslaying on a two-hander with no melee: W.BEAST_SLAYING of the model, from the shots", function()
			local M = ns.Model
			local p = refPoint({ survival = false, twoH = true, ohDPS = 0, mhSpeed = 3.3, mhNorm = 3.3 })
			local Wm, unitDps, t0 = M.Weights(p)
			local q = {}
			for k, v in pairs(p) do q[k] = v end
			q.beastSlaying = 10
			T.truthy(Wm.BEAST_SLAYING > 0, "the shots take it: " .. Wm.BEAST_SLAYING)
			T.near(Wm.BEAST_SLAYING, (M.Total(q) - t0) / 10 / unitDps, 1e-9, "the model's derivative, linear")
			T.eq(M.Parts(q).melee, 0, "no melee part")
			local staff = piece("INVTYPE_2HWEAPON", 7, nil, { DPS = 30, BEAST_SLAYING = 6 }); staff.speed = 3.3
			local plainStaff = piece("INVTYPE_2HWEAPON", 8, nil, { DPS = 30 }); plainStaff.speed = 3.3
			T.near(Sc.ItemValue(staff, "2h", Wm) - Sc.ItemValue(plainStaff, "2h", Wm), 6 * Wm.BEAST_SLAYING, 1e-12, "+6 on the staff")
		end },
		-- attack speed by scope (Parse's attack speed enchants: Minor Haste HASTE, Iron Counterweight MELEE_HASTE, Arcanum
		-- of Rapidity MELEE_HASTE + RANGED_HASTE): each at its own weight in ItemValue's stat loop, a weapon's enchant too
		-- when ctx.weaponGain prices the weapon's DPS and speed (its other stats stay in the loop)
		{ "attack speed stats: HASTE / MELEE_HASTE / RANGED_HASTE at their weights; a weapon's counterweight with weaponGain too", function()
			local Wh = fullW({ HASTE = 10.9, MELEE_HASTE = 4.6, RANGED_HASTE = 8.5, AGI = 2.5, TH_DPS = 0.35 })
			local gloves = piece("INVTYPE_HAND", 1, nil, { HASTE = 1 })
			local helm = piece("INVTYPE_HEAD", 2, nil, { MELEE_HASTE = 1, RANGED_HASTE = 1 })
			T.near(Sc.ItemValue(gloves, "armor", Wh), 10.9, 1e-12, "Minor Haste")
			T.near(Sc.ItemValue(helm, "armor", Wh), 4.6 + 8.5, 1e-12, "Arcanum of Rapidity: both scopes")
			local axe = piece("INVTYPE_2HWEAPON", 3, nil, { DPS = 40, AGI = 10, MELEE_HASTE = 3 }); axe.speed = 3.6
			local plainAxe = piece("INVTYPE_2HWEAPON", 4, nil, { DPS = 40, AGI = 10 }); plainAxe.speed = 3.6
			T.near(Sc.ItemValue(axe, "2h", Wh) - Sc.ItemValue(plainAxe, "2h", Wh), 3 * 4.6, 1e-12, "no weaponGain")
			T.near(Sc.ItemValue(axe, "2h", Wh, true), 10 * 2.5 + 3 * 4.6, 1e-12, "weaponGain prices the DPS, the stats stay")
			-- through Score.Evaluate with a weaponGain that prices both axes alike: the counterweight is the difference,
			-- and a bag copy of the worn counterweight axe gives 0
			local function weaponGain(set) return set[S.MAINHAND] and 7 or 0 end
			local c = ctx({ [S.MAINHAND] = plainAxe }, nil, { weaponGain = weaponGain, wornHit = 0, dualWield = false })
			T.near(Sc.Evaluate(axe, Wh, c).delta, 3 * 4.6, 1e-12, "the bag axe's counterweight")
			local cw = ctx({ [S.MAINHAND] = axe }, nil, { weaponGain = weaponGain, wornHit = 0, dualWield = false })
			local copy = setmetatable({}, { __index = axe })
			T.near(Sc.Evaluate(copy, Wh, cw).delta, 0, 1e-12, "the worn counterweight axe's copy: 0")
			T.near(Sc.Evaluate(plainAxe, Wh, cw).delta, -3 * 4.6, 1e-12, "the axe without it loses the 3%")
			-- a set bonus of each scope counts at its weight too
			local data = { [9100] = { name = "speed", { n = 2, stats = { MELEE_HASTE = 2, RANGED_HASTE = 1 } } } }
			local a, b = piece("INVTYPE_HEAD", 5, 9100), piece("INVTYPE_CHEST", 6, 9100)
			T.near(Sc.SetValue({ [S.HEAD] = a, [S.CHEST] = b }, Wh, ctx({}, nil, { sets = data })), 2 * 4.6 + 8.5, 1e-12, "set bonus")
		end },
		-- Beastslaying is a melee weapon's enchant (spells 7786 / 13653: item class 2, melee subclass mask 189939), which
		-- Player.WeaponInputs reads from the hands: on the ranged slot, a held-in-off-hand item or armor nothing reads it, an
		-- error with or without ctx.weaponGain. An off-hand weapon gives its aura to the player whether or not it swings
		{ "stats-gear-10: Beastslaying on an item that does not swing in melee is an error; an off-hand weapon's counts", function()
			local Wb = fullW({ MH_DPS = 0.27, OH_DPS = 0.09, BEAST_SLAYING = 0.8 })
			local mh = piece("INVTYPE_WEAPON", 2, nil, { DPS = 20 }); mh.speed = 2.0
			local bow = piece("INVTYPE_RANGED", 3, nil, { DPS = 20, BEAST_SLAYING = 6 }); bow.speed = 2.6
			local held = piece("INVTYPE_HOLDABLE", 4, nil, { BEAST_SLAYING = 6 })
			local ring = piece("INVTYPE_FINGER", 5, nil, { BEAST_SLAYING = 6 })
			for _, case in ipairs({ { { [S.RANGED] = bow }, "the ranged slot" }, { { [S.MAINHAND] = mh, [S.OFFHAND] = held }, "held in the off hand" },
				{ { [S.FINGER1] = ring }, "a ring" } }) do
				for _, wg in ipairs({ false, true }) do
					local c = ctx({}, nil, wg and { wornHit = 0, weaponGain = function() return 0 end } or {})
					local ok, err = pcall(Sc.SetValue, case[1], Wb, c)
					T.eq(ok, false, case[2] .. (wg and ", weaponGain" or ""))
					T.truthy(tostring(err):find("Beastslaying on an item that does not swing in melee", 1, true), tostring(err))
				end
			end
			local noDPS = piece("INVTYPE_WEAPON", 6, nil, { BEAST_SLAYING = 6 }); noDPS.speed = 2.6
			T.near(Sc.SetValue({ [S.MAINHAND] = mh, [S.OFFHAND] = noDPS }, Wb, ctx({}, nil, {})), 20 * 0.27 + 6 * 0.8, 1e-12,
				"an off-hand weapon's Beastslaying")
		end },
		-- Score.SetValue prices a set's procs on that set's landed hits (ctx.landedHitsFor, Advisor A.State; Score.LandedHitsOf):
		-- without them every proc, of every hits value and on every item, is an error, and Score.ProcRate / Score.ProcValue
		-- without hits are one; an item without a proc does not ask, and Score.ItemValue prices no proc
		{ "a proc scored without ctx.landedHitsFor is an error, whatever its hits; an item without a proc does not need them", function()
			local c = ctx({}, nil, {})
			for _, case in ipairs({ { "INVTYPE_HAND", S.HANDS, "any" }, { "INVTYPE_HAND", S.HANDS, "weapon" },
				{ "INVTYPE_HAND", S.HANDS, "melee" }, { "INVTYPE_HAND", S.HANDS, "ranged" }, { "INVTYPE_RANGED", S.RANGED, "weapon" },
				{ "INVTYPE_WEAPON", S.MAINHAND, "weapon" } }) do
				local it = case[1] == "INVTYPE_HAND" and piece(case[1], 7284) or weaponOf(case[1], 7285, 2.6, { DPS = 20 })
				it.procs = { proc(250, case[3]) }
				local kind = Sc.SlotKind(case[2], it)
				local ok, err = pcall(Sc.SetValue, { [case[2]] = it }, W, c)
				T.eq(ok, false, case[1] .. " " .. case[3])
				T.truthy(tostring(err):find("a proc scored without ctx.landedHitsFor", 1, true), tostring(err))
				ok, err = pcall(Sc.ProcRate, it, kind, it.procs[1], nil, c)
				T.eq(ok, false, "ProcRate " .. case[3])
				T.truthy(tostring(err):find("a proc scored without the landed hits of its set", 1, true), tostring(err))
				T.eq((pcall(Sc.ProcValue, it, kind, W, nil, c)), false, "ProcValue " .. case[3])
				local bare = {}
				for k, v in pairs(it) do bare[k] = v end
				bare.procs = nil
				T.eq(Sc.ItemValue(it, kind, W), Sc.ItemValue(bare, kind, W), "ItemValue prices no proc: " .. case[3])
			end
			local plain = weaponOf("INVTYPE_WEAPON", 7286, 2.6, { DPS = 20 })
			T.near(Sc.SetValue({ [S.MAINHAND] = plain }, W, c), 20 * W.MH_DPS, 1e-12, "no proc: not asked")
			T.truthy(Sc.SetValue({ [S.MAINHAND] = plain }, W, ctx({}, nil, { landedHitsFor = madeUpHits })), "with them")
		end },
		-- Score.LandedHitsOf: the set's own model point swings each weapon at its own speed (Player.WeaponInputs), so hits whose
		-- hand runs at another speed are the hits of another set: an error, not a price
		{ "LandedHitsOf: the hits of another set, a weapon's hand at another speed, are an error", function()
			local sword = weaponOf("INVTYPE_WEAPON", 7287, 2.4, { DPS = 20 }); sword.procs = { proc(100, "weapon") }
			local function fixedHits() return hitsOf({ 0.02, 0.003, 2.6 }, { 0.03, 1.8 }, { 0.5, 0.17, 2.5, 0.04 }) end
			for _, case in ipairs({ { S.MAINHAND, "mh" }, { S.OFFHAND, "oh" }, { S.RANGED, "ranged" } }) do
				local it = weaponOf(case[1] == S.RANGED and "INVTYPE_RANGED" or "INVTYPE_WEAPON", 7288, 2.4, { DPS = 20 })
				local set = { [S.HANDS] = piece("INVTYPE_HAND", 7284), [case[1]] = it }
				set[S.HANDS].procs = { proc(100, "any", true) }
				local ok, err = pcall(Sc.SetValue, set, W, ctx({}, nil, { landedHitsFor = fixedHits }))
				T.eq(ok, false, case[2])
				T.truthy(tostring(err):find("landed hits that swing the " .. case[2] .. " at", 1, true), tostring(err))
				T.truthy(tostring(err):find("the hits of another set", 1, true), tostring(err))
				T.truthy(Sc.SetValue(set, W, ctx({}, nil, { landedHitsFor = madeUpHits })), case[2] .. ": its own hits")
			end
			T.truthy(Sc.SetValue({ [S.MAINHAND] = sword }, W, ctx({}, nil, { landedHitsFor = madeUpHits })), "the sword")
		end },
		-- a weapon without a speed in any hand is a parse failure (Player.weaponSpeedDPS), named as such whatever the hits'
		-- speed there, never the hits of another set
		{ "LandedHitsOf: a weapon without a parsed speed in any hand is an error of its own, never the hits of another set", function()
			local function fixedHits() return hitsOf({ 0.02, 0.003, 2.6 }, { 0.03, 1.8 }, { 0.5, 0.17, 2.5, 0.04 }) end
			for _, case in ipairs({ { S.MAINHAND, "mh" }, { S.OFFHAND, "oh" }, { S.RANGED, "ranged" } }) do
				local bare = weaponOf(case[1] == S.RANGED and "INVTYPE_RANGED" or "INVTYPE_WEAPON", 7289, nil, { DPS = 20 })
				bare.procs = { proc(100, "weapon") }
				for _, hitsFor in ipairs({ fixedHits, madeUpHits }) do
					local ok, err = pcall(Sc.SetValue, { [case[1]] = bare }, W, ctx({}, nil, { landedHitsFor = hitsFor }))
					T.eq(ok, false, case[2])
					T.truthy(tostring(err):find("a weapon without a parsed speed in the " .. case[2] .. ": ", 1, true), tostring(err))
					T.eq(tostring(err):find("the hits of another set", 1, true), nil, tostring(err))
				end
			end
		end },
		-- Score reads directly what every item record and A.State's ctx always hold: an item's stats and procs tables
		-- (Items.Get from Parse:Lines: a stat the item lacks is absent from stats, procs empty without a damage proc) and its
		-- item id, ctx.baseHit and ctx.hitCap (A.State): one missing is an error, never a default; a proc with no rate from a
		-- source HGA reads is not priced (U4 = (a): no rate is made up), no setting stands in for it
		{ "errors: an item record without stats or procs, a ctx without baseHit or hitCap, a worn item without an id in a plan; an unmeasured rate prices nothing", function()
			local ring = piece("INVTYPE_FINGER", 99401, nil, { AGI = 3 })
			T.near(Sc.SetValue({ [S.FINGER1] = ring }, W, ctx({})), 3 * 2.5, 1e-12, "a full record")
			local noProcs = piece("INVTYPE_FINGER", 99402, nil, { AGI = 3 }); noProcs.procs = nil
			T.eq(pcall(Sc.SetValue, { [S.FINGER1] = noProcs }, W, ctx({})), false, "a record without procs")
			T.eq(pcall(Sc.ProcValue, noProcs, "armor", W, madeUpHits({}), {}), false, "ProcValue without procs")
			local noStats = piece("INVTYPE_FINGER", 99403); noStats.stats = nil
			T.eq(pcall(Sc.ItemValue, noStats, "armor", W), false, "ItemValue without stats")
			T.eq(pcall(Sc.SetValue, { [S.FINGER1] = noStats }, W, ctx({})), false, "SetValue without stats")
			T.eq(pcall(Sc.Secondary, { [S.FINGER1] = noStats }, ctx({}, nil, { pools = { hp = 2000, mana = 1000, armor = 100, level = 43 },
				secondaryRates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS) })), false, "Secondary without stats")
			for _, key in ipairs({ "baseHit", "hitCap" }) do
				local c = ctx({}); c[key] = nil
				local ok, err = pcall(Sc.SetValue, { [S.FINGER1] = ring }, W, c)
				T.eq(ok, false, "a ctx without " .. key)
				T.truthy(tostring(err):find("without ctx." .. key, 1, true), tostring(err))
			end
			local unmeasured = weaponOf("INVTYPE_RANGED", 99404, 2.5, { DPS = 20 }); unmeasured.procs = { proc(20, "weapon") }
			local none, noneKind = Sc.ProcRateSource(unmeasured, unmeasured.procs[1])
			T.eq(none, nil, "no rate"); T.eq(noneKind, nil)
			T.eq(Sc.ProcRate(unmeasured, "ranged", unmeasured.procs[1], madeUpHits({})), 0, "an unmeasured proc: no procs")
			local plainBow = weaponOf("INVTYPE_RANGED", 99405, 2.5, { DPS = 20 })
			T.eq(Sc.SetValue({ [S.RANGED] = unmeasured }, W, ctx({}, nil, { landedHitsFor = madeUpHits })),
				Sc.SetValue({ [S.RANGED] = plainBow }, W, ctx({}, nil, { landedHitsFor = madeUpHits })), "priced as the same bow without it")
			local measured = weaponOf("INVTYPE_RANGED", 17753, 2.8, { DPS = 20 }); measured.procs = { proc(28, "weapon") }
			local rate, kind = Sc.ProcRateSource(measured, measured.procs[1])
			T.eq(rate, 3.5, "a measured rate"); T.eq(kind, "measured")
			T.eq(Sc.ProcsPerMinute, nil, "no setting-backed rate function")
			-- every worn item has its item id (Items.Get: C_Item.GetItemInfoInstant's itemID), which the plan's set steps read
			local helm = item("INVTYPE_HEAD", { AGI = 1 }, "helm")
			local better = item("INVTYPE_HEAD", { AGI = 2 }, "better helm")
			T.truthy(Sc.Plan({ [S.HEAD] = helm }, { better }, W, ctx({ [S.HEAD] = helm })), "worn items with ids")
			helm.id = nil
			ok, err = pcall(Sc.Plan, { [S.HEAD] = helm }, { better }, W, ctx({ [S.HEAD] = helm }))
			T.eq(ok, false); T.truthy(tostring(err):find("a worn item without an item id", 1, true), tostring(err))
		end },
		-- dual-wield hit past the cap (W.HIT_DW): Score.SetValue against Model.Parts' dual wield (ohDPS > 0, no two-hander)
		{ "dual-wield hit past the cap with plain W: a dual-wield set gains it, a two-hander does not; an off hand alone dual wields", function()
			local Wd = fullW({ HIT = 10, HIT_DW = 3 })
			local function w(loc, id) return piece(loc, id, nil, { DPS = 20 }) end
			-- wornHit is given and must not matter without ctx.weaponGain
			local c = ctx({}, nil, { baseHit = 9, wornHit = 9 })
			T.near(Sc.SetValue({ [S.MAINHAND] = w("INVTYPE_WEAPON", 1), [S.OFFHAND] = w("INVTYPE_WEAPON", 2) }, Wd, c), 10 * 5 + 3 * 4, 1e-9,
				"dual wield: 4% past the 5% cap")
			T.near(Sc.SetValue({ [S.MAINHAND] = w("INVTYPE_2HWEAPON", 3) }, Wd, c), 10 * 5, 1e-9, "a two-hander: nothing past the cap")
			T.near(Sc.SetValue({ [S.OFFHAND] = w("INVTYPE_WEAPON", 2) }, Wd, c), 10 * 5 + 3 * 4, 1e-9,
				"an off-hand weapon with the main hand empty dual wields, as the model counts it")
			T.near(Sc.SetValue({ [S.MAINHAND] = w("INVTYPE_WEAPON", 1), [S.OFFHAND] = item("INVTYPE_HOLDABLE", {}) }, Wd, c), 10 * 5, 1e-9,
				"a held-in-off-hand item is no weapon")
			T.near(Sc.SetValue({ [S.MAINHAND] = w("INVTYPE_WEAPON", 1), [S.OFFHAND] = piece("INVTYPE_WEAPON", 4) }, Wd, c), 10 * 5, 1e-9,
				"an off-hand weapon without DPS (Model: ohDPS 0) does not dual wield")
		end },
		{ "dual-wield hit past the cap with ctx.weaponGain: only the hit past the cap beyond the worn hit's; no other set gets any", function()
			local Wd = fullW({ HIT = 10, HIT_DW = 3 })
			local function w(loc, id, hit) return piece(loc, id, nil, { DPS = 20, HIT = hit }) end
			-- the model ran every set's weapons at the worn 9% hit: a dual-wield set's gain holds those white misses
			local c = ctx({}, nil, { baseHit = 9, wornHit = 9, weaponGain = function() return 0 end })
			local function dw(hit) return { [S.MAINHAND] = w("INVTYPE_WEAPON", 1, hit), [S.OFFHAND] = w("INVTYPE_WEAPON", 2) } end
			local function th(hit) return { [S.MAINHAND] = w("INVTYPE_2HWEAPON", 3, hit) } end
			T.near(Sc.SetValue(dw(0), Wd, c), 10 * 5, 1e-9, "dual wield at the worn hit: nothing on top of the model")
			T.near(Sc.SetValue(dw(2), Wd, c), 10 * 5 + 3 * 2, 1e-9, "2% more hit than the worn set's")
			T.near(Sc.SetValue(dw(-3), Wd, c), 10 * 5 + 3 * (1 - 4), 1e-9, "3% less: 1% past the cap instead of 4%")
			T.near(Sc.SetValue(th(0), Wd, c), 10 * 5, 1e-9, "a two-hander at the worn hit")
			T.near(Sc.SetValue(th(2), Wd, c), 10 * 5, 1e-9, "a two-hander's hit past the cap: nothing")
			local noWorn = ctx({}, nil, { baseHit = 9, weaponGain = function() return 0 end })
			local ok, err = pcall(Sc.SetValue, dw(0), Wd, noWorn)
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.wornHit"), tostring(err))
		end },
		-- ranged weapon skill: SKILL_BOWS / SKILL_GUNS / SKILL_CROSSBOWS for the line of the set's ranged weapon, by
		-- wowsims' attack table (Model.SkillMiss, raid-mode W1 design 3.3): its hit ns.Model.SkillHit(ctx.mobDiff, b) meets
		-- the shots' cap at W.HIT_RANGED, its crit below the level's maximum costs W.SKILL_CRIT a point; never W.HIT / W.CRIT.
		-- The test ctx: an equal-level mob (mobDiff 0, the 5% cap), the worn line's trained skill at the level's (skillBase 0)
		{ "ranged weapon skill: the set's own ranged line's bonuses go through the shots' capped hit and the skill crit, once", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, CRIT = 7, CRIT_RANGED = 3, SKILL_CRIT = 5 })
			local function ranged(id, subclass, stats)
				local r = piece("INVTYPE_RANGED", id, nil, stats); r.classID, r.subclassID = 2, subclass; return r
			end
			local ring = piece("INVTYPE_FINGER", 9, nil, { SKILL_BOWS = 5 })
			local function value(set, baseHit, extra, Wx)
				local c = ctx({}, nil, { baseHit = baseHit })
				for k, v in pairs(extra or {}) do c[k] = v end
				return Sc.SetValue(set, Wx or Wk, c)
			end
			-- +5 over the maximum at +0: the gap -5, 4.5% miss, 0.5% of the shots' hit; no crit above the maximum
			T.near(value({ [S.RANGED] = ranged(1, 2, { SKILL_BOWS = 5 }) }, 2), 10 * 2 + 4 * 0.5, 1e-9,
				"+5 Bows on a bow: 0.5% of the shots' hit")
			T.near(value({ [S.RANGED] = ranged(1, 2, {}), [S.FINGER1] = ring }, 2), 10 * 2 + 4 * 0.5, 1e-9, "a ring's +5 Bows with a bow")
			T.near(value({ [S.RANGED] = ranged(2, 3, {}), [S.FINGER1] = ring }, 2), 10 * 2, 1e-9, "the ring's +5 Bows with a gun: nothing")
			T.near(value({ [S.RANGED] = ranged(1, 2, { SKILL_BOWS = 5 }) }, 6), 10 * 5, 1e-9, "past the cap: nothing")
			-- the worn line 10 points below the maximum (skillBase -10): the bow's +5 is 5 below, the shots' -0.5%, and 5
			-- points of skill crit over a set at the trained skill
			T.near(value({ [S.RANGED] = ranged(1, 2, { SKILL_BOWS = 5 }) }, 2, { skillBase = -10 }), 10 * 2 + 4 * -0.5 + 5 * (10 - 5), 1e-9,
				"+5 Bows 10 below the maximum: the hit and the crit of 5 points")
			-- a W with a weight under the skill stat's own key (Model.Weights never sets one)
			local Wskill = fullW({ HIT = 10, HIT_RANGED = 4, CRIT = 7, CRIT_RANGED = 3, SKILL_CRIT = 5 }); Wskill.SKILL_BOWS = 100
			T.near(value({ [S.RANGED] = ranged(1, 2, { SKILL_BOWS = 5 }) }, 2, nil, Wskill),
				10 * 2 + 4 * 0.5, 1e-9, "never a linear skill weight")
			-- a reached set bonus' skill for the set's line counts too: +10 Guns, the gap -10, 1% of the shots' hit
			local data = { [9005] = { name = "gunner", { n = 2, stats = { SKILL_GUNS = 10 } } } }
			local set = { [S.RANGED] = ranged(2, 3, {}), [S.HEAD] = piece("INVTYPE_HEAD", 11, 9005), [S.CHEST] = piece("INVTYPE_CHEST", 12, 9005) }
			T.near(value(set, 2, { sets = data }), 10 * 2 + 4 * 1.0, 1e-9, "a 2-piece +10 Guns with a gun")
			T.near(Sc.SkillBonus(set, "SKILL_GUNS", data), 10, 1e-9)
		end },
		{ "ranged weapon skill: measured against the worn set; a piece's skillOffset counts; it never lowers dual-wield misses", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, CRIT = 7, CRIT_RANGED = 3, SKILL_CRIT = 5, HIT_DW = 3 })
			local function ranged(id, subclass, stats)
				local r = piece("INVTYPE_RANGED", id, nil, stats); r.classID, r.subclassID = 2, subclass; return r
			end
			local bow5, plainBow = ranged(1, 2, { SKILL_BOWS = 5 }), ranged(2, 2, {})
			local worn = { [S.RANGED] = bow5 }
			-- the worn bows line trained 10 points below the maximum (skillBase -10), the worn bow's +5 Bows: 5 below
			local c = ctx(worn, nil, { baseHit = 2, skillBase = -10 })
			T.near(Sc.SetValue(worn, Wk, c), 10 * 2 + 4 * -0.5, 1e-9, "the worn set: the shots at its skill's -0.5%, its crit the model's")
			T.near(Sc.SetValue({ [S.RANGED] = plainBow }, Wk, c), 10 * 2 + 4 * -1.0 + 5 * (5 - 10), 1e-9,
				"without the +5 Bows: 10 below, 0.5% less of the shots' hit and 5 points of skill crit")
			-- a gun whose line's trained skill is 3 points over the worn line's (Advisor rangedSkillPiece): 7 below
			local gun = ranged(3, 3, {}); gun.skillOffset = 3
			T.near(Sc.SetValue({ [S.RANGED] = gun }, Wk, c), 10 * 2 + 4 * -0.7 + 5 * (5 - 7), 1e-9, "3 points over the trained bows, 2 under the worn")
			-- dual wield past the cap: the ranged skill's hit adds nothing to the white misses
			local function dwSet(r)
				return { [S.RANGED] = r, [S.MAINHAND] = piece("INVTYPE_WEAPON", 4, nil, { DPS = 20 }),
					[S.OFFHAND] = piece("INVTYPE_WEAPON", 5, nil, { DPS = 20 }) }
			end
			local c9 = ctx(dwSet(plainBow), nil, { baseHit = 9, skillBase = -10 })
			T.near(Sc.SetValue(dwSet(bow5), Wk, c9) - Sc.SetValue(dwSet(plainBow), Wk, c9), 5 * 5, 1e-9,
				"9% hit: +5 Bows is the skill crit only, for a dual-wield set too")
			local ok, err = pcall(Sc.SetValue, worn, Wk, { baseHit = 2 })
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.equipped"), tostring(err))
		end },
		-- SPELL_HIT and SPELL_CRIT (raid-mode design 18.8): spell hit is priced on the whole set at W.SPELL_HIT up to
		-- ctx.spellHitCap (Model.TrapHitCap) on the base spell hit (ctx.baseSpellHit), never in ItemValue's stat loop; a set
		-- bonus's counts with the items'; spell crit at W.SPELL_CRIT a point, linearly; a Use buff's spell hit over its uptime
		-- through the same cap (Nat Pagle's Broken Reel 231271: SPELL_HIT 10 for 15 s every 90 s, Game/UseData.lua)
		{ "spell hit up to the trap's cap on the whole set; spell crit at its weight", function()
			local Ws = fullW({ SPELL_HIT = 3, SPELL_CRIT = 2 })
			local c = ctx({}, nil, { baseSpellHit = 3, spellHitCap = 4 })
			local function value(stats) return Sc.SetValue({ [S.FINGER1] = piece("INVTYPE_FINGER", 99801, nil, stats) }, Ws, c) end
			T.eq(Sc.ItemValue(piece("INVTYPE_FINGER", 99801, nil, { SPELL_HIT = 2 }), "armor", Ws), 0, "not in the stat loop")
			T.near(value({}), 3 * 3, 1e-12, "the base spell hit, under the cap")
			T.near(value({ SPELL_HIT = 2 }) - value({}), 3 * 1, 1e-12, "2% more spell hit: 1% of it under the cap")
			T.near(value({ SPELL_CRIT = 1.5 }) - value({}), 2 * 1.5, 1e-12, "spell crit at its weight")
			local reel = piece("INVTYPE_TRINKET", 99803, nil, {})
			reel.use = { spell = 99804, stats = { SPELL_HIT = 10 }, duration = 15, cooldown = 90 }
			T.near(Sc.SetValue({ [S.TRINKET1] = reel }, Ws, c) - value({}), 15 / 90 * 3 * (4 - 3), 1e-12,
				"a Use buff of 10% spell hit: its uptime of the 1% under the cap")
			local cb = ctx({}, nil, { baseSpellHit = 3, spellHitCap = 4,
				sets = { [99901] = { name = "made-up", { n = 1, spell = 1, stats = { SPELL_HIT = 2 } } } } })
			local setPiece = piece("INVTYPE_FINGER", 99802, 99901)
			T.near(Sc.SetValue({ [S.FINGER1] = setPiece }, Ws, cb), 3 * 4, 1e-12, "a set bonus's spell hit with the base, to the cap")
			local bad = ctx({}, nil, { baseSpellHit = 0 }); bad.spellHitCap = nil
			T.eq(pcall(Sc.SetValue, {}, Ws, bad), false, "no cap: an error")
			local bad2 = ctx({}); bad2.baseSpellHit = nil
			T.eq(pcall(Sc.SetValue, {}, Ws, bad2), false, "no base spell hit: an error")
		end },
		{ "score: one ctx scored again with another worn set, set data or skill check scores as a new ctx does", function()
			-- Score keeps the worn set's skill points and survival / mana totals on the ctx (ctx.wornTerms) for the
			-- ctx.equipped, ctx.sets and ctx.hasSkill they come from. Made-up set 9218 (2 pieces: +5 Bows, +20 Stamina;
			-- other data: +10 Bows, +40 Stamina; a profession version needs rank 300 of skill line 165); the scored set
			-- breaks it.
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, CRIT = 7, SKILL_CRIT = 5, AGI = 1 })
			local pools = { hp = 2133, mana = 1725, armor = 1500, level = 43 }
			local rates = ns.Model.SecondaryRates(ns.Model.DEFAULT_TALENTS)
			local bow = piece("INVTYPE_RANGED", 1, nil, {}); bow.classID, bow.subclassID = 2, 2
			local function worn(sid)
				return { [S.RANGED] = bow, [S.HEAD] = piece("INVTYPE_HEAD", 11, sid), [S.CHEST] = piece("INVTYPE_CHEST", 12, sid) }
			end
			local dataA = { [9218] = { name = "a", { n = 2, stats = { SKILL_BOWS = 5, STA = 20 } } } }
			local dataB = { [9218] = { name = "b", { n = 2, stats = { SKILL_BOWS = 10, STA = 40 } } } }
			local dataS = { [9218] = { name = "profession", skill = 165, skillRank = 300, { n = 2, stats = { SKILL_BOWS = 5, STA = 20 } } } }
			local set = { [S.RANGED] = bow, [S.HEAD] = piece("INVTYPE_HEAD", 21, nil, { AGI = 3 }) }
			-- the worn bows line trained 10 points below the maximum (skillBase -10)
			local function fresh(c)
				return ctx(c.equipped, nil, { baseHit = 2, skillBase = -10, pools = pools, secondaryRates = rates, sets = c.sets,
					hasSkill = c.hasSkill })
			end
			local function same(c, label)
				local f = fresh(c)
				T.near(Sc.SetValue(set, Wk, c), Sc.SetValue(set, Wk, f), 1e-9, label .. ": value")
				T.near(Sc.Secondary(set, c), Sc.Secondary(set, f), 1e-9, label .. ": survival")
			end
			local c = fresh({ equipped = worn(9218), sets = dataA })
			same(c, "set data A")
			T.near(Sc.SetValue(set, Wk, c), 10 * 2 + 4 * -1.0 + 5 * (5 - 10) + 3, 1e-9,
				"set data A: 5 Bows less (10 below the maximum: the shots' -1%, 5 points of skill crit), +3 Agility")
			local v0, s0 = Sc.SetValue(set, Wk, c), Sc.Secondary(set, c)
			c.sets = dataB
			same(c, "set data B")
			T.truthy(Sc.SetValue(set, Wk, c) < v0 and Sc.Secondary(set, c) < s0, "set data B: breaking the set costs more")
			c.equipped = worn(9219)
			same(c, "another worn set (no data: no bonus)")
			c.equipped, c.sets, c.hasSkill = worn(9218), dataS, function() return false end
			same(c, "the profession set below its rank")
			c.hasSkill = function(line, rank) return line == 165 and rank <= 300 end
			same(c, "the profession set at its rank")
		end },
		{ "ranged weapon skill: a skill loss past the cap costs the skill crit only", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, CRIT = 7, CRIT_RANGED = 3, SKILL_CRIT = 5 })
			local function ranged(id, stats)
				local r = piece("INVTYPE_RANGED", id, nil, stats); r.classID, r.subclassID = 2, 2; return r
			end
			local bow5, plainBow = ranged(1, { SKILL_BOWS = 5 }), ranged(2, {})
			-- the bows line trained 10 below the maximum: the worn +5 Bows at 5 below (the shots at 9 - 0.5%), without it 10
			-- below (9 - 1%): both past the 5% cap
			local c = ctx({ [S.RANGED] = bow5 }, nil, { baseHit = 9, skillBase = -10 })
			T.near(Sc.SetValue({ [S.RANGED] = plainBow }, Wk, c) - Sc.SetValue({ [S.RANGED] = bow5 }, Wk, c), -5 * 5, 1e-9,
				"9% hit: without the worn +5 Bows 8% stays past the 5% cap, 5 points of skill crit lost")
		end },
		-- the worn skill's own hit against the level's skill (wowsims' table, ns.Model.SkillHit): level 43 (5 x 43 = 215)
		{ "ranged weapon skill: the shots' cap counts the worn skill's hit against the level's skill (ctx.skillBase)", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, CRIT = 7, CRIT_RANGED = 3, SKILL_CRIT = 5 })
			local function ranged(id, stats)
				local r = piece("INVTYPE_RANGED", id, nil, stats); r.classID, r.subclassID = 2, 2; return r
			end
			local bow5, plainBow = ranged(1, { SKILL_BOWS = 5 }), ranged(2, {})
			-- a worn plain bow at 195 of 215: the gap 20 past 10, 9% miss, the shots 4% short at a sheet hit of the 5% cap,
			-- every other attack at the cap
			local below = ctx({ [S.RANGED] = plainBow }, nil, { baseHit = 5, skillBase = 195 - 215 })
			T.near(Sc.SetValue({ [S.RANGED] = plainBow }, Wk, below), 10 * 5 - 4 * 4, 1e-9, "the worn set: every attack at 5%, the shots at 1%")
			-- +5 Bows: 200, the gap 15, 8% miss: 1% more of the shots' hit and 5 points of skill crit
			T.near(Sc.SetValue({ [S.RANGED] = bow5 }, Wk, below) - Sc.SetValue({ [S.RANGED] = plainBow }, Wk, below),
				4 * 1 + 5 * 5, 1e-9, "+5 Bows below the shots' cap: 1% of their hit and 5 points of skill crit")
			-- a worn bow with +5 Bows at 220 (215 trained): its 0.5% hit is past the cap, a plain bow at 215 is at the cap,
			-- and no crit above the maximum
			local above = ctx({ [S.RANGED] = bow5 }, nil, { baseHit = 5, skillBase = 0 })
			T.near(Sc.SetValue({ [S.RANGED] = plainBow }, Wk, above) - Sc.SetValue({ [S.RANGED] = bow5 }, Wk, above),
				0, 1e-12, "without the +5 Bows: 215, still at the cap")
			-- an on-use hit buff meets the same cap: Nat Pagle's Broken Reel 231271 (+10% hit, 15 s every 90 s)
			local reel = piece("INVTYPE_TRINKET", 231271); reel.use = ns.UseData[231271]
			local wornReel = { [S.RANGED] = plainBow, [S.TRINKET1] = reel }
			T.near(Sc.SetValue(wornReel, Wk, below) - Sc.SetValue({ [S.RANGED] = plainBow }, Wk, below), 15 / 90 * 4 * 4, 1e-9,
				"the reel fills the shots' 4% the worn skill leaves")
			for _, key in ipairs({ "skillBase", "mobDiff" }) do
				local without = ctx({ [S.RANGED] = plainBow }, nil, { baseHit = 5 }); without[key] = nil
				local ok, err = pcall(Sc.SetValue, { [S.RANGED] = plainBow }, Wk, without)
				T.eq(ok, false); T.truthy(tostring(err):find("without ctx." .. key, 1, true), tostring(err))
			end
		end },
		{ "ranged weapon skill: the worn skill's hit never lowers dual-wield white misses", function()
			local Wd = fullW({ HIT = 10, HIT_RANGED = 4, HIT_DW = 3 })
			local bow = piece("INVTYPE_RANGED", 1); bow.classID, bow.subclassID = 2, 2
			local set = { [S.RANGED] = bow, [S.MAINHAND] = piece("INVTYPE_WEAPON", 2, nil, { DPS = 20 }),
				[S.OFFHAND] = piece("INVTYPE_WEAPON", 3, nil, { DPS = 20 }) }
			-- 7% hit at the 5% cap: every attack capped, 2% past it for the dual-wield white misses; the bow 8 below the
			-- maximum puts the shots at 6.2% (ns.Model.SkillHit(0, -8) = -0.8)
			local below = Sc.SetValue(set, Wd, ctx(set, nil, { baseHit = 7, skillBase = -8 }))
			local level = Sc.SetValue(set, Wd, ctx(set, nil, { baseHit = 7, skillBase = 0 }))
			T.near(below, 10 * 5 + 3 * 2, 1e-9, "every attack capped and 2% past the cap")
			T.near(below, level, 1e-12, "the worn skill leaves the white misses alone")
		end },
		{ "a Use hit buff counts its hit parts and, in a dual-wield set, its dual-wield part (Nat Pagle's Broken Reel 231271)", function()
			local Wd = fullW({ HIT = 10, HIT_RANGED = 4, HIT_DW = 3 })
			local reel = piece("INVTYPE_TRINKET", 231271); reel.use = ns.UseData[231271]
			T.eq(reel.use.stats.HIT, 10); T.eq(reel.use.duration, 15); T.eq(reel.use.cooldown, 90)
			local function w(loc, id) return piece(loc, id, nil, { DPS = 20 }) end
			local function dw(withReel)
				return { [S.MAINHAND] = w("INVTYPE_WEAPON", 1), [S.OFFHAND] = w("INVTYPE_WEAPON", 2), [S.TRINKET1] = withReel and reel or nil }
			end
			local function th(withReel) return { [S.MAINHAND] = w("INVTYPE_2HWEAPON", 3), [S.TRINKET1] = withReel and reel or nil } end
			local function reelPart(set, noReel, hit)
				-- the model runs the weapons at the worn hit: the dual-wield part counts past the cap beyond it; the worn ranged
				-- skill 8 below the maximum (ns.Model.SkillHit(0, -8) = -0.8), which the sets without a bow keep
				local c = ctx(noReel, nil, { baseHit = hit, wornHit = hit, skillBase = -8, weaponGain = function() return 0 end })
				return Sc.SetValue(set, Wd, c) - Sc.SetValue(noReel, Wd, c)
			end
			local function pastCap(h) return math.min(math.max(h - 5, 0), 19) end
			-- 4% hit: every attack 1% short of the 5% cap, the shots 1.8% short (the worn skill's -0.8%); the reel's
			-- 10% fills both and goes 9% past the cap
			T.near(reelPart(dw(true), dw(false), 4), 15 / 90 * (10 * 1 + 4 * 0.8 + 3 * (pastCap(14) - pastCap(4))), 1e-9,
				"dual wield: the hit parts and the dual-wield part")
			T.near(reelPart(th(true), th(false), 4), 15 / 90 * (10 * 1 + 4 * 0.8), 1e-9, "a two-hander: the hit parts only")
			-- 6% hit: every attack past the cap already, the shots at 5.2%: only the dual-wield part is left
			T.near(reelPart(dw(true), dw(false), 6), 15 / 90 * 3 * (pastCap(16) - pastCap(6)), 1e-9, "dual wield past the cap")
			T.near(reelPart(th(true), th(false), 6), 0, 1e-9, "a two-hander past the cap: nothing")
		end },
		-- Model.Parts missChance: base miss - hit, floored at 0 only, so each point of hit below 0% still lowers the miss
		-- chance a point; the worn ranged skill 8 below the maximum (ns.Model.SkillHit(0, -8) = -0.8)
		{ "hit below 0% (a hit debuff): no floor, every attack and the shots priced linearly", function()
			local Wd = fullW({ HIT = 10, HIT_RANGED = 4 })
			local ring = piece("INVTYPE_FINGER", 1, nil, { HIT = 2 })
			local c = ctx({}, nil, { baseHit = -3, skillBase = -8 })
			T.near(Sc.SetValue({}, Wd, c), 10 * -3 + 4 * -0.8, 1e-9, "every attack at -3%, the shots at -3.8%")
			T.near(Sc.SetValue({ [S.FINGER1] = ring }, Wd, c) - Sc.SetValue({}, Wd, c), 10 * 2, 1e-9, "-3% to -1%: 2% of every attack's hit")
			local c2 = ctx({}, nil, { baseHit = 0.5, skillBase = -8 })
			T.near(Sc.SetValue({}, Wd, c2), 10 * 0.5 + 4 * -0.8, 1e-9, "the shots alone below 0%: -0.3%")
		end },
		-- the crit scope (SpellItemEnchantment 8720: bows, guns and crossbows only) is ranged crit (Parse CRIT_RANGED)
		{ "a crit scope's crit (CRIT_RANGED) is priced at W.CRIT_RANGED, an item's own crit at W.CRIT", function()
			local Wc = fullW({ CRIT = 7, CRIT_RANGED = 5 })
			local scoped = piece("INVTYPE_RANGED", 1, nil, { CRIT_RANGED = 2 })
			T.near(Sc.ItemValue(scoped, "ranged", Wc), 5 * 2, 1e-9, "2% ranged crit")
			local ring = piece("INVTYPE_FINGER", 2, nil, { CRIT = 2 })
			T.near(Sc.ItemValue(ring, "armor", Wc), 7 * 2, 1e-9, "an item's own crit: every attack")
			T.near(Sc.SetValue({ [S.RANGED] = scoped }, Wc, ctx({})), 5 * 2, 1e-9, "the same through SetValue")
		end },
		{ "a scope on a ranged item without a speed is an error with plain W", function()
			local scoped = piece("INVTYPE_RANGED", 1, nil, { DPS = 20, RANGED_FLAT = 7 })
			local ok, err = pcall(Sc.ItemValue, scoped, "ranged", W)
			T.eq(ok, false); T.truthy(tostring(err):find("a scope's damage on a ranged item without a speed", 1, true), tostring(err))
			ok, err = pcall(Sc.SetValue, { [S.RANGED] = scoped }, W, ctx({}))
			T.eq(ok, false); T.truthy(tostring(err):find("without a speed", 1, true), tostring(err))
			scoped.speed = 2.5
			T.near(Sc.ItemValue(scoped, "ranged", W), 10.4 * (20 + 7 / 2.5), 1e-9, "7 damage a shot every 2.5 s")
		end },
		-- stats-gear-4: measured rates (wowsims docs/evidence EV-0119: Heartseeking Crossbow 13040 2.7, Stinging Viper 6472 1.75)
		{ "stats-gear-4: a measured proc rate; an unmeasured one prices nothing; Heartseeking's equip proc rolls on its shots alone", function()
			T.eq(Sc.MEASURED_PPM[13040], 2.7); T.eq(Sc.MEASURED_PPM[6472], 1.75); T.eq(Sc.MEASURED_PPM[12974], 0.6)
			local eq = { [S.RANGED] = weaponOf("INVTYPE_RANGEDRIGHT", 1, 2.5, { DPS = 20 }) }
			-- Heartseeking Crossbow at 3.1 s (Era ItemSparse ItemDelay 3100): its equip trigger (Parse proc.equip, the "Equip:"
			-- line of ItemEffect 99815, TriggerType 1) rolls on its own hand's damaging hits in its own set at its own 3.1 s, the
			-- Auto Shots and the special shots; no Serpent Sting application (an equip aura takes no hit without damage)
			local heart = weaponOf("INVTYPE_RANGEDRIGHT", 13040, 3.1, { DPS = 20 }); heart.procs = { proc(16, "ranged", true) }
			local c = ctx(eq, nil, { landedHitsFor = madeUpHits })
			local r = Sc.Evaluate(heart, W, c)
			T.near(r.delta, 16 * 2.7 * 3.1 * (0.5 + 0.17) / 60 * 6.5, 1e-9, "Heartseeking at its measured 2.7 a minute, its shots alone")
			local ppm, kind = Sc.ProcRateSource(heart, heart.procs[1])
			T.eq(ppm, 2.7); T.eq(kind, "measured")
			local other = weaponOf("INVTYPE_RANGEDRIGHT", 99999, 3.1, { DPS = 20 }); other.procs = { proc(16, "ranged", true) }
			T.near(Sc.Evaluate(other, W, c).delta, 0, 1e-9, "unmeasured: not priced (no rate is made up)")
			T.eq(select(2, Sc.ProcRateSource(other, other.procs[1])), nil)
		end },
		-- U4 = (a), as wowsims: a weapon that shares a measured weapon's proc spell takes no rate of its own unless wowsims'
		-- override data gives one (wowsims has no WeaponProcs row for Skullforge Reaver 228542, Venomspitter 228573,
		-- Gravestone War Axe 228029 or Chipped Bite of Serra'kis 209436: its tools/database/overrides/weapon_procs.go), so the
		-- twins are not priced; the measured weapon keeps its rate. Each twin's proc is a damage over time, which
		-- Game/ProcData.lua writes (raid-mode design 17.4) with no rate of its own
		{ "U4: a twin of a measured weapon takes no carried rate (wowsims has no row for it); the measured weapon keeps its own", function()
			T.eq(Sc.SAME_PROC, nil); T.eq(Sc.CARRIED_PPM, nil); T.eq(Sc.CarryRates, nil)
			for _, id in ipairs({ 228542, 228573, 228029, 209436 }) do
				local w = weaponOf("INVTYPE_WEAPON", id, 2.5, { DPS = 30 }); w.procs = { proc(100, "weapon") }
				T.eq(Sc.MEASURED_PPM[id], nil, id .. " is not measured"); T.eq(#ns.ProcData[id], 1, id .. ": its one entry")
				local e = ns.ProcData[id][1]
				T.truthy(e.dot ~= nil, id .. ": a damage over time"); T.eq(e.source, nil, id .. ": no override row"); T.eq(e.ppm, nil, id .. ": no rate")
				T.eq(Sc.ProcRateSource(w, w.procs[1]), nil, id .. ": no rate")
			end
			local reaver = weaponOf("INVTYPE_WEAPON", 13361, 2.5, { DPS = 30 }); reaver.procs = { proc(100, "weapon") }
			T.eq(Sc.ProcRateSource(reaver, reaver.procs[1]), 1.95, "13361 keeps its measured rate (EV-0121)")
		end },
		-- a non-weapon item's proc: each hand's landed hits at the speed of the weapon in that hand at the model point
		-- (wowsims sim/core/attack.go PPMProc), the hands its hits name
		{ "stats-gear-4: an equip proc on armor rolls on the hits its text names, each hand at its own speed, no sting", function()
			local undo = measuredFor(1.5, { id = 7284 })
			-- the made-up hits carry Serpent Sting applications (0.04 a second), which no non-weapon item's proc takes
			local c = ctx({}, nil, { landedHitsFor = madeUpHits })
			local function gloves(hits) local g = piece("INVTYPE_HAND", 7284); g.procs = { proc(250, hits, true) }; return g end
			local function value(it) return Sc.SetValue({ [S.HANDS] = it }, W, c) end
			local mh, oh, ranged = 2.6 * (0.02 + 0.003), 1.8 * 0.03, 2.5 * (0.5 + 0.17)
			T.near(value(gloves("melee")), 250 * 1.5 * (mh + oh) / 60 * 6.5, 1e-9, "melee hits: the main hand and the off hand")
			T.near(value(gloves("ranged")), 250 * 1.5 * ranged / 60 * 6.5, 1e-9, "ranged hits: the shots")
			T.near(value(gloves("any")), 250 * 1.5 * (mh + oh + ranged) / 60 * 6.5, 1e-9, "melee and ranged hits")
			T.near(value(gloves("weapon")), 250 * 1.5 * (mh + oh + ranged) / 60 * 6.5, 1e-9, "a non-weapon item's own hits: every hand")
			local bad = piece("INVTYPE_HAND", 1); bad.procs = { proc(1, "sometimes") }
			local ok, err = pcall(value, bad)
			T.eq(ok, false, "an unknown hit type is an error"); T.truthy(tostring(err):find("unknown hits sometimes", 1, true), tostring(err))
			undo()
		end },
		-- Score.ProcRate on Model.LandedHits: procs per second = rate / 60 x the sum over the hands that roll the proc of the
		-- speed of the weapon in that hand x its landed hits (wowsims docs/evidence EV-0119 lines 25-27, EV-0022 line 20,
		-- EV-0003 lines 11-12; wowsims sim/core/attack.go:1255-1268 PPMProc), on the hits of the model point with the set's own
		-- weapons. The model point: test_model's reference state with a 1.8 s off hand.
		{ "procs: a worn ranged weapon's proc follows the model's landed shots as the quiver, ranged haste and haste change", function()
			local M = ns.Model
			-- Verdant Keeper's Aim 17753 (Forever Item.csv class 2 subclass 2, a bow; Era ItemSparse ItemDelay 2800; Keeper's
			-- Sting 29655 SpellEffect EffectBasePointsF 28), worn: the model's bow at its 2.8 s
			local bow = weaponOf("INVTYPE_RANGED", 17753, 2.8, { DPS = 21 }); bow.procs = { proc(28, "weapon") }
			local function at(extra)
				local p = refPoint({ bowSpeed = 2.8 })
				for k, v in pairs(extra) do p[k] = v end
				local lh = M.LandedHits(p)
				return Sc.ProcRate(bow, "ranged", bow.procs[1], lh, {}), lh.ranged, M.Parts(p), p
			end
			local rate0, h0, parts0 = at({})
			local perShot0 = parts0.auto / h0.swings -- the damage of one landed Auto Shot, whatever the speed
			local cases = { { quiver = 0.15 }, { rangedHaste = 5 }, { haste = 3 }, { quiver = 0.15, rangedHaste = 5, haste = 3 } }
			for i, extra in ipairs(cases) do
				local rate, h, parts = at(extra)
				T.near(rate, 3.5 * 2.8 * (h.swings + h.specials + h.casts), 1e-12,
					"case " .. i .. ": 3.5 a minute at the bow's own 2.8 s on its shots and Serpent Sting's applications")
				T.near(rate / rate0, (h.swings + h.specials + h.casts) / (h0.swings + h0.specials + h0.casts), 1e-12, "case " .. i .. ": as the landed hits")
				T.truthy(h.swings > h0.swings * 1.01, "case " .. i .. ": faster Auto Shots")
				T.eq(h.casts, h0.casts, "case " .. i .. ": Serpent Sting's applications keep their rate")
				-- the hits are the model's own: Model.Parts' Auto Shot damage is the landed Auto Shots x one shot's damage
				T.near(parts.auto / h.swings, perShot0, 1e-9 * perShot0, "case " .. i .. ": Model.Parts' Auto Shots")
				-- the special shots at level 43 with the hawks: Aimed Shot 0.92 / (6 + 2 s / the shots' speed) and Arcane Shot
				-- once per 18 s, landing with the shots' hit (shotHitf: 5% base miss - 1% hit), whole (the BM build: no melee); and
				-- the dives, two a 18 s, always landing (Model.LandedHits: the dive is a ranged ability)
				local shotHitf = 1 - 0.04
				local hRanged = h.swings / shotHitf * 2.8
				T.near(h.specials, shotHitf * (0.92 / (6 + 2 / hRanged) + 1 / 18) + 2 / 18, 1e-12,
					"case " .. i .. ": Aimed, Arcane and the dives")
			end
			T.near(rate0, 3.5 * 2.8 * (h0.swings + h0.specials + h0.casts), 1e-12, "the reference")
		end },
		-- Serpent Sting's applications deal no damage: they roll a weapon's "Chance on hit" proc (Parse: no proc.equip) whose
		-- hits include the ranged hand, and never a proc from an "Equip:" line (proc.equip, an equip aura), on the same weapon
		-- (EV-0021 lines 18-19 and 41-47: only a damaging hit rolls an equip aura; lines 32-33 and 49-50: non-damaging
		-- applications roll a chance on hit; wowsims sim/core/spelldata/resolve_proc.go:95-110 WeaponProc,
		-- sim/common/forever/items_weapons.go:207-223 Heartseeking Crossbow's 29626 without it)
		{ "procs: Serpent Sting's applications roll a weapon's chance-on-hit proc at the ranged hand's speed, never the same weapon's equip proc", function()
			local undo = measuredFor(1.5, { id = 99105 }, { id = 99106 }, { id = 99107 })
			local o = { procOutcome = WHOLE_OUTCOME }
			-- made-up hits: the ranged hand at 2.5 s, 0.5 Auto Shots, 0.17 special shots and 0.04 applications a second; a
			-- 3.0 s bow on them, as A.ModelProcRates prices a ranged weapon it places in no set on the worn set's hits: each
			-- hand at the speed of the weapon in that hand at the hits' point, the applications too, never the bow's own 3.0 s
			local h = madeUpHits({})
			local bow = weaponOf("INVTYPE_RANGED", 99105, 3.0, { DPS = 21 })
			bow.procs = { proc(28, "weapon"), proc(16, "ranged", true), proc(16, "any", true),
				proc(16, "weapon", true) }
			T.near(Sc.ProcRate(bow, "ranged", bow.procs[1], h, o), 1.5 * 2.5 * (0.5 + 0.17 + 0.04), 1e-12,
				"the chance on hit: the shots and Serpent Sting's applications at the ranged hand's 2.5 s")
			T.near(Sc.ProcRate(bow, "ranged", bow.procs[2], h, o), 1.5 * 2.5 * (0.5 + 0.17), 1e-12, "the equip proc of ranged hits: the shots alone")
			T.near(Sc.ProcRate(bow, "ranged", bow.procs[3], h, o), 1.5 * (2.6 * (0.02 + 0.003) + 1.8 * 0.03 + 2.5 * (0.5 + 0.17)), 1e-12,
				"the equip proc of melee and ranged hits: every hand's landed hits, no application")
			-- an equip proc of the weapon's own hits (Parse: "Chance on hit to", "Атаки с некоторой вероятностью наносят"), as on
			-- the ranged-slot wand Firebelcher 5243 (Item.csv class 2 / 19, InventoryType 26; ItemXItemEffect -> ItemEffect 232775
			-- TriggerType 1, spell 1291686): its own hand's shots, still no application
			T.near(Sc.ProcRate(bow, "ranged", bow.procs[4], h, o), 1.5 * 2.5 * (0.5 + 0.17), 1e-12,
				"the equip proc of the weapon's own hits: the ranged hand's shots alone")
			-- in a set: the bow's two procs priced on its set's hits, the applications for the chance on hit alone
			local c = ctx({}, nil, { landedHitsFor = madeUpHits })
			-- each bow in its own set: madeUpHits swings the ranged hand at the bow's own 2.5 s there
			local onHitOnly = weaponOf("INVTYPE_RANGED", 99106, 2.5, { DPS = 21 }); onHitOnly.procs = { bow.procs[1] }
			local equipOnly = weaponOf("INVTYPE_RANGED", 99107, 2.5, { DPS = 21 }); equipOnly.procs = { bow.procs[2] }
			local bare = weaponOf("INVTYPE_RANGED", 99108, 2.5, { DPS = 21 })
			local function value(it) return Sc.SetValue({ [S.RANGED] = it }, W, c) - Sc.SetValue({ [S.RANGED] = bare }, W, c) end
			T.near(value(onHitOnly), 28 * 1.5 * 2.5 * (0.5 + 0.17 + 0.04) / 60 * 6.5, 1e-9, "the chance on hit in its set")
			T.near(value(equipOnly), 16 * 1.5 * 2.5 * (0.5 + 0.17) / 60 * 6.5, 1e-9, "the equip proc in its set: no application")
			undo()
		end },
		-- Serpent Sting's applications (Model.LandedHits ranged.casts): a cast that lands without a damage event rolls a
		-- weapon's chance-on-hit proc (EV-0119 line 25; EV-0021 lines 32-33), in the share Model.Parts counts the sting's damage in: whole, one
		-- sting per 15 s (SpellMisc DurationIndex 8 -> SpellDuration 8, 15000 ms, every rank) for CONST.serpentUptime of the
		-- time, landing with the shots' hit, wherever Model.Parts counts its damage (a bow, gun or crossbow, level 4 on)
		{ "Serpent Sting's applications: 0.8 / 15 s landing with the shots' hit, wherever and as Model.Parts counts its damage", function()
			local M = ns.Model
			T.eq(M.CONST.serpentDuration, 15); T.eq(M.CONST.serpentUptime, 0.8)
			local perApp -- one application's damage, out.serpent / the applications: the same at any hit
			for _, case in ipairs({ { level = 3 }, { level = 4 }, { level = 26 }, { level = 60 }, { noShots = true },
				{ hit = 3, rangedHit = 1 }, { hit = -2 }, { mobDiff = 3 }, { quiver = 0.15, haste = 4 } }) do
				local p = refPoint(case)
				local h, parts = M.LandedHits(p).ranged, M.Parts(p)
				local name = ""
				for k, v in pairs(case) do name = name .. k .. "=" .. tostring(v) .. " " end
				local shotHitf = 1 - math.max(0, M.HitCap(p.mobDiff) - p.hit - (p.rangedHit or 0)) / 100
				T.eq(parts.serpent > 0, p.level >= 4 and not p.noShots, name .. ": Model.Parts' sting")
				if parts.serpent > 0 then
					T.near(h.casts, 0.8 / 15 * shotHitf, 1e-15, name .. ": the applications")
					if p.level == 43 and p.mobDiff == 0 then
						local per = parts.serpent / h.casts
						if perApp then T.near(per, perApp, 1e-9 * perApp, name .. ": the damage of one application") end
						perApp = per
					end
				else
					T.eq(h.casts, 0, name .. ": no sting, no application")
				end
			end
		end },
		{ "procs: a bow's proc rolls on the shots, Serpent Sting's applications and the dives; a melee proc on the Survival weave's melee alone, none without a bow", function()
			local undo = measuredFor(1.5, { id = 99101 }, { id = 99102 }, { id = 99103 }, { id = 99104 })
			local M = ns.Model
			local o = { procOutcome = WHOLE_OUTCOME }
			local bow = weaponOf("INVTYPE_RANGED", 99101, 2.6, { DPS = 21 }); bow.procs = { proc(28, "weapon") }
			local sword = weaponOf("INVTYPE_WEAPON", 99102, 2.6, { DPS = 26 }); sword.procs = { proc(28, "weapon") }
			local rangedRing = piece("INVTYPE_FINGER", 99103); rangedRing.procs = { proc(28, "ranged", true) }
			local meleeRing = piece("INVTYPE_FINGER", 99104); meleeRing.procs = { proc(28, "melee", true) }
			local function rates(p)
				local lh = M.LandedHits(p)
				return { bow = Sc.ProcRate(bow, "ranged", bow.procs[1], lh, o), sword = Sc.ProcRate(sword, "mh", sword.procs[1], lh, o),
					rangedRing = Sc.ProcRate(rangedRing, "armor", rangedRing.procs[1], lh, o),
					meleeRing = Sc.ProcRate(meleeRing, "armor", meleeRing.procs[1], lh, o) }, lh
			end
			-- from range (the BM build): no melee hit; the shots, the applications (0.8 / 15 a second landing with the shots'
			-- hit, 5% base miss - 1% hit) and the dives (two a 18 s with the hawks at 43: a ranged ability that always lands)
			local none, hNone = rates(refPoint({}))
			T.eq(none.sword, 0, "a melee weapon's proc from range: no shot or sting rolls it (EV-0119 lines 5-7)")
			T.eq(none.meleeRing, 0, "melee hits from range")
			T.near(hNone.ranged.casts, 0.8 / 15 * 0.96, 1e-15, "the applications")
			T.truthy(hNone.ranged.swings > 0, "the shots")
			T.near(none.bow, 1.5 * 2.6 * (hNone.ranged.swings + hNone.ranged.specials + hNone.ranged.casts), 1e-12,
				"a bow's proc: the shots, the dives and Serpent Sting's applications")
			T.near(none.rangedRing, 1.5 * 2.6 * (hNone.ranged.swings + hNone.ranged.specials), 1e-12,
				"a ring's ranged proc: the shots and the dives, no application (EV-0021 lines 18-19)")
			-- the Survival weave (Model weaveParts, its counts averaged over Rapid Fire): no dive (no Summon Hawk), the landed
			-- applications 0.8 / 15 a second (the sting's uptime that of the landed sting), the melee hits of both hands
			local sv = refPoint({ survival = true })
			local all, hAll = rates(sv)
			local r = M.Weave(sv).average.rates
			T.near(hAll.ranged.casts, 0.8 / 15, 1e-15, "the weave's applications")
			T.near(hAll.ranged.specials, (r.arcane + r.multi) * 0.96, 1e-12, "the weave's ranged specials: Arcane Shot and Multi-Shot, no dive")
			T.near(all.bow, 1.5 * 2.6 * (hAll.ranged.swings + hAll.ranged.specials + hAll.ranged.casts), 1e-12, "the weave: a bow's proc")
			T.truthy(all.sword > 0, "the weave's melee rolls the sword's proc")
			T.near(all.sword, 1.5 * 2.6 * (hAll.mh.swings + hAll.mh.specials), 1e-12, "the sword on the main hand's hits")
			T.near(all.meleeRing, 1.5 * (2.6 * (hAll.mh.swings + hAll.mh.specials) + 1.8 * hAll.oh.swings), 1e-12, "melee: both hands")
			-- the Survival branch without a bow, gun or crossbow: no Auto Shot, so no weave: no shot, no sting, no melee hit; with
			-- no ranged weapon at all (bowDPS 0, Player.WeaponInputs) the ranged hand's speed is 0 (wowsims
			-- sim/core/procs.go:183-227 skips the ranged entry of speed 0)
			local noBow = M.LandedHits(refPoint({ survival = true, noShots = true, bowDPS = 0 }))
			T.eq(noBow.ranged.casts, 0); T.eq(noBow.ranged.speed, 0); T.eq(noBow.ranged.specials, 0); T.eq(noBow.ranged.swings, 0)
			T.eq(noBow.mh.swings + noBow.mh.specials + noBow.oh.swings, 0, "no melee hit")
			T.eq(Sc.ProcRate(bow, "ranged", bow.procs[1], noBow, o), 0, "no ranged weapon in the set: 0")
			T.eq(Sc.ProcRate(sword, "mh", sword.procs[1], noBow, o), 0, "no weave: the sword's proc 0")
			-- Expose Prey (rank 3: 15% a landed hit opens Mongoose Bite): the weave's bites land with the special-attack hit
			-- chance (5% base miss - 1% hit, 5% dodge: 0.91) in the main hand's specials, with Raptor Strike and Wing Clip
			local tal = {}
			for k, v in pairs(ns.Model.DEFAULT_TALENTS) do tal[k] = v end
			tal.exposePrey = 3
			local ep = refPoint({ survival = true, tal = tal })
			local re = M.Weave(ep).average.rates
			local rb, hb = rates(ep)
			T.truthy(re.bite > 0, "bites")
			T.near(hb.mh.specials, (re.raptor + re.wingClip + re.bite) * 0.91, 1e-12, "the bites in the specials")
			T.near(rb.sword, 1.5 * 2.6 * (hb.mh.swings + hb.mh.specials), 1e-12, "the sword with the bites")
			undo()
		end },
		{ "procs: a weapon's own proc rolls on its own set's hits at its own speed; Raptor Strike and Quick Shots follow that speed", function()
			local undo = measuredFor(1.5, { id = 99201 }, { id = 99202 }, { id = 99203 }, { id = 99205 })
			local M = ns.Model
			local o = { procOutcome = WHOLE_OUTCOME }
			-- In the Survival weave (Model weaveParts, its counts averaged over Rapid Fire): one main-hand swing a cycle, Raptor
			-- Strike in its place every nCycles(6) cycles and Wing Clip in the melee looks, main-hand specials landing with the
			-- special-attack hit chance (1 - 4% miss - 5% dodge), the other swings white, landing with the dual-wield white one
			-- (1 - 23% - 5%); where the swing timer sets the cycle (a 5.0 s or 6.0 s main hand) Raptor Strike's count follows the
			-- weapon's own speed (every ceil(6 / M) swings)
			local function sv(over) local t = { survival = true }; for k, v in pairs(over) do t[k] = v end; return refPoint(t) end
			local ref = M.LandedHits(sv({})).mh
			local r = M.Weave(sv({})).average.rates
			T.eq(ref.speed, 2.6)
			T.near(ref.specials, 0.91 * (r.raptor + r.wingClip), 1e-12, "Raptor Strike and Wing Clip at the special-attack hit chance")
			T.near(ref.swings, r.mhWhite * 0.72, 1e-12, "the white swings: the swings Raptor Strike leaves")
			local bySpeed = {}
			for _, speed in ipairs({ 1.8, 2.6, 2.9, 3.0, 3.6, 5.0, 6.0 }) do
				local cand = weaponOf("INVTYPE_WEAPON", 99201, speed, { DPS = 26 }); cand.procs = { proc(28, "weapon") }
				local q = M.LandedHits(sv({ mhSpeed = speed }))
				T.eq(q.mh.speed, speed)
				T.near(Sc.ProcRate(cand, "mh", cand.procs[1], q, o), 1.5 * speed * (q.mh.swings + q.mh.specials), 1e-12,
					"a " .. speed .. " s one-hander on its own set's hits")
				bySpeed[speed] = M.Weave(sv({ mhSpeed = speed })).base.rates.raptor
				local th = weaponOf("INVTYPE_2HWEAPON", 99202, speed, { DPS = 34 }); th.procs = { proc(28, "weapon") }
				local t = M.LandedHits(sv({ mhSpeed = speed, twoH = true, ohDPS = 0 }))
				T.near(Sc.ProcRate(th, "2h", th.procs[1], t, o), 1.5 * speed * (t.mh.swings + t.mh.specials), 1e-12, "a " .. speed .. " s two-hander")
			end
			-- where the swing timer sets the cycle, Raptor Strike every ceil(6 / M) swings: each 6.0 s swing, every 2 of 5.0 s
			T.near(bySpeed[6.0], 1 / 6.0, 1e-12, "6.0 s: Raptor Strike each swing"); T.near(bySpeed[5.0], 1 / 10, 1e-12, "5.0 s: every 2 swings")
			-- the off hand's own proc: its swings at its own 2.2 s, no special, where the swing timer holds the hunter in melee
			-- (a 5.0 s main hand: Model weaveParts' off-hand share)
			local oc = weaponOf("INVTYPE_WEAPON", 99203, 2.2, { DPS = 26 }); oc.procs = { proc(28, "weapon") }
			local oq = M.LandedHits(sv({ mhSpeed = 5.0, ohSpeed = 2.2 }))
			T.eq(oq.oh.speed, 2.2); T.eq(oq.oh.specials, 0); T.truthy(oq.oh.swings > 0, "the off hand swings")
			T.near(Sc.ProcRate(oc, "oh", oc.procs[1], oq, o), 1.5 * 2.2 * oq.oh.swings, 1e-12, "an off-hand weapon")
			-- a bow's: Quick Shots' uptime follows the Auto Shots at the bow's own speed (Model.Parts shots12; Deadly Aspects 5/5),
			-- so a 3.4 s bow's Auto Shots x 3.4 are not the 2.6 s bow's x 2.6
			local b26, b34 = M.LandedHits(refPoint({})).ranged, M.LandedHits(refPoint({ bowSpeed = 3.4 })).ranged
			T.truthy(math.abs(3.4 * b34.swings - 2.6 * b26.swings) > 1e-4, "Quick Shots: the Auto Shots x the speed move with the bow's speed")
			local slow = weaponOf("INVTYPE_RANGED", 99205, 3.4, { DPS = 21 }); slow.procs = { proc(28, "weapon") }
			T.near(Sc.ProcRate(slow, "ranged", slow.procs[1], M.LandedHits(refPoint({ bowSpeed = 3.4 })), o),
				1.5 * 3.4 * (b34.swings + b34.specials + b34.casts), 1e-12, "a 3.4 s bow on its own shots and stings")
			undo()
		end },
		-- Equip spell 1214125 ("Chance on direct spell damage or melee attack to deal $1213941s1 Fire damage", Parse hits
		-- "melee"; 1213941 SpellEffect EffectBasePointsF 412) is on seven melee weapons (Forever build 70888 ItemXItemEffect ->
		-- ItemEffect TriggerType 1, SpellID 1214125): 233491, 233490, 233796, 233797, 233798, 233801 and 234428. Obsidian
		-- Sageblade 233798: Item.csv class 2 subclass 7 InventoryType 21, a main-hand sword, Era ItemSparse ItemDelay 1500;
		-- Obsidian Heartseeker 234428: subclass 15 InventoryType 13, a one-hand dagger, Era ItemDelay 1700 (Era rows: the
		-- build 70888 ItemSparse export has none). A weapon's "melee" proc rolls on both hands and an "any" proc on the shots
		-- too, each hand at the speed of the weapon in that hand (wowsims sim/core/attack.go:1255-1268 PPMProc), never at the
		-- speed of the weapon carrying it
		{ "procs: a weapon's melee or any equip proc rolls on the other hands at their own weapons' speeds, no Serpent Sting application", function()
			local undo = measuredFor(1.5, { id = 233798 }, { id = 234428 }, { id = 99601 })
			local M = ns.Model
			local o = { procOutcome = WHOLE_OUTCOME }
			local function obsidian(id, loc, speed) local w = weaponOf(loc, id, speed, { DPS = 30 }); w.procs = { proc(412, "melee", true) }; return w end
			local sageblade = obsidian(233798, "INVTYPE_WEAPONMAINHAND", 1.5)
			local heartseeker = obsidian(234428, "INVTYPE_WEAPON", 1.7)
			local other = weaponOf("INVTYPE_WEAPON", 99602, 2.6, { DPS = 26 })
			-- made-up landed hits of a set in Model.LandedHits' form, each hand at the speed of the set's weapon there (Score's
			-- rule; the Survival weave lets the off hand swing only while the swing timer holds the hunter in melee, so made-up
			-- counts give both hands hits): the main hand 0.2 white swings and 0.05 specials a second, the off hand 0.15
			local function made(mhSpeed, ohSpeed) return hitsOf({ 0.2, 0.05, mhSpeed }, { 0.15, ohSpeed }, { 0.3, 0.1, 2.9, 0.05 }) end
			-- the Sageblade in the main hand, a 2.6 s sword in the off hand: the main hand's hits at 1.5 s, the off hand's at 2.6 s
			local h = made(1.5, 2.6)
			local mhRate = 1.5 * (1.5 * (h.mh.swings + h.mh.specials) + 2.6 * h.oh.swings)
			T.near(Sc.ProcRate(sageblade, "mh", sageblade.procs[1], h, o), mhRate, 1e-12, "the off hand at its own 2.6 s")
			-- the Heartseeker in the off hand behind a 2.6 s main hand: the main hand's hits at 2.6 s, its own at 1.7 s
			local g = made(2.6, 1.7)
			local ohRate = 1.5 * (2.6 * (g.mh.swings + g.mh.specials) + 1.7 * g.oh.swings)
			T.near(Sc.ProcRate(heartseeker, "oh", heartseeker.procs[1], g, o), ohRate, 1e-12, "the main hand at its own 2.6 s")
			-- through Score.SetValue on each set's own hits (ctx.landedHitsFor: the made-up hits at the set's weapons' speeds)
			local function ownHits(set)
				local mh, oh = set[S.MAINHAND], set[S.OFFHAND]
				return made(mh.speed, oh.speed)
			end
			local c = ctx({}, nil, { landedHitsFor = ownHits })
			local function procPart(set) local bare = {}; for k, v in pairs(set) do bare[k] = v end
				for slot, it in pairs(set) do local b = {}; for k, v in pairs(it) do b[k] = v end; b.procs = {}; bare[slot] = b end
				return Sc.SetValue(set, W, c) - Sc.SetValue(bare, W, c)
			end
			T.near(procPart({ [S.MAINHAND] = sageblade, [S.OFFHAND] = other }), 412 * mhRate / 60 * W.EXTRA_DPS, 1e-9, "the Sageblade's set")
			T.near(procPart({ [S.MAINHAND] = other, [S.OFFHAND] = heartseeker }), 412 * ohRate / 60 * W.EXTRA_DPS, 1e-9, "the Heartseeker's set")
			-- an "any" equip proc (27656's "Melee and Ranged attacks have a chance to", Parse proc.equip) on a 2.0 s melee weapon
			-- with a 2.9 s bow: the shots at the bow's 2.9 s, no Serpent Sting application (an equip aura takes no hit without
			-- damage, EV-0021 lines 18-19), the off hand at its 1.8 s
			local anyAxe = weaponOf("INVTYPE_WEAPON", 99601, 2.0, { DPS = 26 }); anyAxe.procs = { proc(100, "any", true) }
			local k = made(2.0, 1.8)
			T.truthy(k.ranged.swings > 0 and k.ranged.casts > 0, "shots and stings")
			T.near(Sc.ProcRate(anyAxe, "mh", anyAxe.procs[1], k, o),
				1.5 * (2.0 * (k.mh.swings + k.mh.specials) + 1.8 * k.oh.swings + 2.9 * (k.ranged.swings + k.ranged.specials)),
				1e-12, "the shots at the bow's 2.9 s, no sting")
			undo()
		end },
		-- Multi-Shot (levels 18-19: its cooldown category is Aimed Shot's, learned at 20) and Sniper Shot (the Marksmanship
		-- talent, level 40 on) are special shots: their landed hits are in the ranged hand's specials at Model.Parts' rates,
		-- Multi-Shot CONST.aimedUse / (6 + 0.5 s / the shots' speed), Sniper Shot CONST.sniperUse / (15 + 4 s / the shots'
		-- speed) next to Aimed Shot at CONST.aimedUseSniper, landing with the shots' hit (the BM build: no melee, the shots whole)
		{ "procs: Multi-Shot at levels 18-19 and Sniper Shot from 40 are in the ranged specials, as Model.Parts counts them", function()
			local M = ns.Model
			local C = M.CONST
			-- the BM build: no melee, the shots whole
			local shotHitf, f = 1 - 0.04, 0
			local function shotsSpeed(h, s) return h.swings / ((1 - f) * shotHitf) * s end -- hRanged, from the Auto Shots
			-- level 18 and 19, no hawks yet: Arcane Shot on its own cooldown (CONST.arcaneUse / 6 s) and Multi-Shot
			local perMulti
			for _, level in ipairs({ 18, 19 }) do
				for _, quiver in ipairs({ 0.13, 0.15 }) do
					local p = refPoint({ level = level, quiver = quiver })
					local h, parts = M.LandedHits(p).ranged, M.Parts(p)
					local hR = shotsSpeed(h, 2.6)
					local multiRate = C.aimedUse / (6 + 0.5 / hR)
					T.truthy(parts.multi > 0 and parts.aimed == 0 and parts.sniper == 0, level .. ": Multi-Shot, no Aimed Shot")
					T.near(h.specials, (1 - f) * shotHitf * (multiRate + C.arcaneUse / 6), 1e-12, level .. " quiver " .. quiver .. ": Multi and Arcane")
					local multiHits = (1 - f) * shotHitf * multiRate
					local per = parts.multi / multiHits -- one landed Multi-Shot's damage: the same at any shots' speed
					if level == 18 and perMulti then T.near(per, perMulti, 1e-9 * perMulti, "Model.Parts' Multi-Shots") end
					if level == 18 then perMulti = per end
				end
			end
			T.eq(M.Parts(refPoint({ level = 20 })).multi, 0, "Aimed Shot replaces it at 20")
			-- level 43 with Sniper Shot: Aimed Shot at CONST.aimedUseSniper, Arcane Shot once per 18 s with the hawks, Sniper Shot
			local tal = {}
			for k, v in pairs(M.DEFAULT_TALENTS) do tal[k] = v end
			tal.sniperShot = 1
			local perSniper
			for _, quiver in ipairs({ 0.13, 0.15 }) do
				local p = refPoint({ tal = tal, quiver = quiver })
				local h, parts = M.LandedHits(p).ranged, M.Parts(p)
				local hR = shotsSpeed(h, 2.6)
				local sniperRate = C.sniperUse / (15 + 4 / hR)
				T.truthy(parts.sniper > 0, "Sniper Shot")
				-- and the dives, two a 18 s, whole
				T.near(h.specials, (1 - f) * shotHitf * (C.aimedUseSniper / (6 + 2 / hR) + 1 / 18 + sniperRate) + 2 / 18, 1e-12,
					"quiver " .. quiver .. ": Aimed, Arcane, Sniper and the dives")
				local per = parts.sniper / ((1 - f) * shotHitf * sniperRate)
				if perSniper then T.near(per, perSniper, 1e-9 * perSniper, "Model.Parts' Sniper Shots") end
				perSniper = per
			end
			T.eq(M.Parts(refPoint({ level = 39, tal = tal })).sniper, 0, "no Sniper Shot below 40")
		end },
		-- Raptor Strike goes off in place of a main-hand swing (Model.LandedHits), a melee ability (wowsims
		-- sim/hunter/raptor_strike.go:13, 60-71): in the Survival weave that swing's landed hit moves from the white swings to
		-- the specials and lands with the special-attack hit chance instead of the white one. With one hand the two chances
		-- are one (whiteMiss is miss itself), so the main hand's swings and specials sum to the unarmed hand's swings (no
		-- Raptor Strike: it needs a melee weapon; the cycle is the same) and Wing Clip's landed hits (a melee weapon's too),
		-- neither below 0; with two hands Raptor Strike's swing lands whiteMiss - miss more
		{ "procs: Raptor Strike moves its swing from the white swings to the specials; one hand: the unarmed hand's total, two: the miss difference more", function()
			local M = ns.Model
			math.randomseed(3)
			local bad = 0
			for _ = 1, 4000 do
				-- one hand (a two-hander, or no off-hand weapon), no Strider Kick, no Expose Prey (DEFAULT_TALENTS): Raptor Strike
				-- is the only special
				local d, hit, expertise = math.random(0, 3), math.random(-3, 9) + math.random(), math.random(0, 5)
				local p = fullP({ level = math.random(20, 60), rap = 600, map = 500, crit = 10, hit = hit,
					expertise = expertise, haste = math.random(0, 6), bowDPS = 21, bowSpeed = 2.6, ammoDPS = 13, quiver = 0.13,
					mobDiff = d, survival = true, mhDPS = 30, mhSpeed = 1.5 + 2 * math.random(), ohDPS = 0,
					twoH = math.random() < 0.5, tal = M.DEFAULT_TALENTS })
				local h = M.LandedHits(p).mh
				local wc = M.Weave(p).average.rates.wingClip
				local hitSpecial = 1 - math.max(0, M.HitCap(d) - hit) / 100 - math.max(0, M.MobAvoid(d) - expertise) / 100
				local q = {}
				for k, v in pairs(p) do q[k] = v end
				q.unarmed = true
				local u = M.LandedHits(q).mh
				if h.swings < 0 or h.specials < 0 or u.specials ~= 0 or wc <= 0
					or math.abs(h.swings + h.specials - u.swings - wc * hitSpecial) > 1e-12 then
					bad = bad + 1
				end
			end
			T.eq(bad, 0, "one hand: the white swings, Raptor Strike and Wing Clip sum to the unarmed hand's swings and Wing Clip's, neither below 0")
			-- two hands at 1% hit in the weave: the white swings, the cycle's main-hand swings less Raptor Strike's, land with 1
			-- - 23% - 5%, Raptor Strike and Wing Clip with 1 - 4% - 5%
			local sv = refPoint({ survival = true })
			local h = M.LandedHits(sv).mh
			local r = M.Weave(sv).average.rates
			T.near(h.specials, 0.91 * (r.raptor + r.wingClip), 1e-12, "two hands: Raptor Strike and Wing Clip at the special-attack hit chance")
			T.near(h.swings, r.mhWhite * 0.72, 1e-12, "two hands: the white swings Raptor Strike leaves")
			T.near(r.mhWhite + r.raptor, r.auto, 1e-12, "one main-hand swing a cycle")
			local u = M.LandedHits(refPoint({ survival = true, unarmed = true })).mh
			T.near(h.swings + h.specials - u.swings, (0.23 - 0.04) * r.raptor + 0.91 * r.wingClip, 1e-12,
				"two hands: the miss difference over the unarmed hand, and Wing Clip")
		end },
		{ "procs: a melee equip proc on armor while dual wielding sums both hands, each at its own speed", function()
			local undo = measuredFor(1.5, { id = 99301 })
			local M = ns.Model
			-- the Survival weave with a 5.0 s main hand, whose swing timer holds the hunter in melee long enough for the 1.8 s
			-- off hand (Model weaveParts' off-hand share), the counts averaged over Rapid Fire (Model.Weave): the white swings land
			-- with the dual-wield white miss (5% + 19% - 1% hit) and the 5% dodge, Raptor Strike and Wing Clip with 1 - 4% - 5%
			local p = refPoint({ survival = true, mhSpeed = 5.0 })
			local lh = M.LandedHits(p)
			local r = M.Weave(p).average.rates
			T.truthy(r.oh > 0, "the off hand swings")
			T.near(lh.mh.swings, r.mhWhite * (1 - 0.23 - 0.05), 1e-12, "the main hand's white swings")
			T.near(lh.mh.specials, (r.raptor + r.wingClip) * 0.91, 1e-12, "the main hand's specials")
			T.near(lh.oh.swings, r.oh * (1 - 0.23 - 0.05), 1e-12, "the off hand's swings")
			T.eq(lh.oh.speed, 1.8); T.eq(lh.oh.specials, 0)
			local ring = piece("INVTYPE_FINGER", 99301); ring.procs = { proc(250, "melee", true) }
			local o = { procOutcome = WHOLE_OUTCOME }
			local rate = Sc.ProcRate(ring, "armor", ring.procs[1], lh, o)
			T.near(rate, 1.5 * (5.0 * (lh.mh.swings + lh.mh.specials) + 1.8 * lh.oh.swings), 1e-12, "both hands at their own speeds")
			T.near(Sc.ProcValue(ring, "armor", W, lh, o), 250 * rate / 60 * W.EXTRA_DPS, 1e-12, "priced as extra damage")
			-- a two-hander: no off hand
			local th = M.LandedHits(refPoint({ survival = true, twoH = true, ohDPS = 0, mhSpeed = 3.3 }))
			T.eq(th.oh.swings, 0)
			T.near(Sc.ProcRate(ring, "armor", ring.procs[1], th, o), 1.5 * 3.3 * (th.mh.swings + th.mh.specials), 1e-12, "a two-hander: the main hand alone")
			-- empty hands: the main hand swings unarmed at the no-weapon speed it is given, once a cycle, with no Raptor Strike
			-- or Wing Clip (they need a melee weapon)
			local bp = refPoint({ survival = true, mhDPS = 0, mhSpeed = 2.6, ohDPS = 0, ohSpeed = 2.6, unarmed = true })
			local bare = M.LandedHits(bp)
			T.eq(bare.mh.speed, 2.6); T.eq(bare.mh.specials, 0); T.eq(bare.oh.swings, 0)
			T.near(bare.mh.swings, M.Weave(bp).average.rates.auto * (1 - 0.04 - 0.05), 1e-12, "unarmed swings, once a cycle, the one-hand white miss")
			T.near(Sc.ProcRate(ring, "armor", ring.procs[1], bare, o), 1.5 * 2.6 * bare.mh.swings, 1e-12, "unarmed: the main hand at 2.6 s")
			undo()
		end },
		-- Highborne Research Tablet 260205: "Chance on hit to deal $1265634s1 Arcane damage" (spell 1318159, aura 42 with
		-- trigger 1265634); 1265634's SpellEffect EffectBasePointsF 75 with Variance 0.16, so 69 to 81, 75 on average (wowsims
		-- sim/common/forever/items_trinkets.go:256 "69 to 81"). Game/ProcData.lua's entry: an equip aura of mask 65876 =
		-- 0x10154 (melee swings and abilities, Auto Shot, ranged abilities, the harmful spell) and chance 100, no stated rate,
		-- so the measured 2.6 a minute (MEASURED_PPM, EV-0021) at the speed of the hand that hits, wowsims'
		-- NewLegacyPPMManagerWithSpells (items_trinkets.go:275-277); RequireDamageDealt kept over the harmful-spell bit
		-- (items_trinkets.go:279-281: no Serpent Sting application rolls it). With no ranged weapon (the ranged hand's speed
		-- 0) the dives roll it at the main hand's speed (Score.PROC_OVERRIDES spellsAtMainHand). Linked (Items.LinkProcs) or
		-- not (Parse's "weapon": every hand of a non-weapon item), the same hits
		{ "procs: the Highborne Research Tablet at each hand's own speed, the dives at the main hand's with no ranged weapon, no sting", function()
			local undo = measuredFor(1.5, { id = 99401 })
			local M = ns.Model
			T.eq(Sc.MEASURED_PPM[260205], 2.6)
			local e = ns.ProcData[260205][1]
			T.eq(e.kind, "equip"); T.eq(e.mask, 65876); T.eq(e.chance, 100); T.eq(e.icd, 0); T.eq(e.avg, 75)
			T.eq(e.ppm, 2.6); T.eq(e.source, "EV-0021", "wowsims' override row of 1318159, the same measurement")
			local tablet = piece("INVTYPE_TRINKET", 260205); tablet.classID = 4
			local linked = { avg = 75, hits = "weapon", equip = true, school = "magic", linked = true, defense = e.defense,
				crit = e.crit, mask = e.mask, chance = e.chance, ppm = e.ppm, icd = e.icd }
			tablet.procs = { linked, proc(75, "weapon", true) }
			local o = { procOutcome = WHOLE_OUTCOME }
			-- a 2.6 s main hand, a 1.8 s off hand and a 2.8 s bow: each hand at its own speed, the dives (2 a 18 s) at the bow's
			local lh = M.LandedHits(refPoint({ bowSpeed = 2.8 }))
			T.truthy(lh.ranged.casts > 0 and lh.ranged.specials > 2 / 18, "Serpent Sting's applications, the shots and the dives")
			local atHands = 2.6 * (2.6 * (lh.mh.swings + lh.mh.specials) + 1.8 * lh.oh.swings + 2.8 * (lh.ranged.swings + lh.ranged.specials))
			for i = 1, 2 do
				T.near(Sc.ProcRate(tablet, "armor", tablet.procs[i], lh, o), atHands, 1e-12, (i == 1 and "linked" or "unlinked") .. ": each hand's speed")
			end
			T.near(Sc.ProcValue({ procs = { linked }, id = 260205, name = "tablet" }, "armor", W, lh, o), 75 * atHands / 60 * W.EXTRA_DPS, 1e-12)
			-- no ranged weapon (bowDPS 0: the ranged hand's speed 0): no shot, no sting; the dives at the main hand's 2.6 s
			local bare = M.LandedHits(refPoint({ noShots = true, bowDPS = 0 }))
			T.eq(bare.ranged.speed, 0); T.eq(bare.ranged.swings, 0); T.near(bare.ranged.specials, 2 / 18, 1e-15)
			local atMain = 2.6 * (2.6 * (bare.mh.swings + bare.mh.specials + 2 / 18) + 1.8 * bare.oh.swings)
			for i = 1, 2 do
				T.near(Sc.ProcRate(tablet, "armor", tablet.procs[i], bare, o), atMain, 1e-12, (i == 1 and "linked" or "unlinked") .. ": the dives at the main hand's speed")
			end
			-- an unmeasured trinket of the same proc: the setting at each hand's speed; without a ranged weapon its dives roll
			-- no rate at a hand's speed (no spellsAtMainHand: the ranged entry of speed 0 is skipped)
			local other = piece("INVTYPE_TRINKET", 99401); other.classID = 4; other.procs = { proc(75, "weapon", true) }
			T.near(Sc.ProcRate(other, "armor", other.procs[1], lh, o), 1.5 * atHands / 2.6, 1e-12, "a measured rate at each hand's speed")
			T.near(Sc.ProcRate(other, "armor", other.procs[1], bare, o), 1.5 * (2.6 * (bare.mh.swings + bare.mh.specials) + 1.8 * bare.oh.swings),
				1e-12, "no dive without a ranged weapon")
			undo()
		end },
		-- A held-in-off-hand item (INVTYPE_HOLDABLE: no weapon, Score.IsWeapon, whatever its item class) scored in the off-hand
		-- kind keeps a non-weapon item's rule (Score.ProcRate): its "weapon" proc rolls every hand's swings and specials, each
		-- at the speed of the weapon in that hand, and no Serpent Sting application; a measured rate on it rolls at the speed
		-- of each hand too. The held items are of item class 2, as Frying Pan 280317 (Forever Item.csv build 70888: class 2,
		-- subclass 14, InventoryType 23, the one class-2 row held in the off hand), so only the equipLoc keeps them from being
		-- weapons. Made up: the procs on them, the hits, and the ids put on them (260205 measured at 2.6, 9478 at 2).
		{ "procs: a held-in-off-hand item of the weapon class in the off-hand kind rolls every hand, no sting; a measured rate at each hand's speed", function()
			local undo = measuredFor(1.5, { id = 280317 })
			-- three hand speeds and Serpent Sting applications
			local hits = hitsOf({ 0.02, 0.003, 2.6 }, { 0.03, 1.8 }, { 0.5, 0.17, 2.8, 0.04 })
			local o = { procOutcome = WHOLE_OUTCOME }
			local function held(id)
				local h = piece("INVTYPE_HOLDABLE", id); h.classID, h.subclassID = 2, 14; h.procs = { proc(50, "weapon") }
				return h
			end
			local orb = held(280317)
			T.eq(Sc.IsWeapon(orb), false, "class 2 held in the off hand: no weapon"); T.eq(Sc.SlotKind(S.OFFHAND, orb), "oh")
			local atHands = 2.6 * (0.02 + 0.003) + 1.8 * 0.03 + 2.8 * (0.5 + 0.17)
			local rate = Sc.ProcRate(orb, "oh", orb.procs[1], hits, o)
			T.near(rate, 1.5 * atHands, 1e-12, "the setting on every hand's swings and specials at their speeds, no sting")
			T.near(Sc.ProcValue(orb, "oh", W, hits, o), 50 * rate / 60 * W.EXTRA_DPS, 1e-12)
			local measured = held(260205)
			T.near(Sc.ProcRate(measured, "oh", measured.procs[1], hits, o), 2.6 * atHands, 1e-12,
				"a measured rate at each hand's speed, no sting")
			local stray = held(9478)
			T.near(Sc.ProcRate(stray, "oh", stray.procs[1], hits, o), 2 * atHands, 1e-12, "Ripsaw's measured 2 at each hand's speed")
			undo()
		end },
		-- Score.UsePriced: raid mode prices every Use buff through the fight; levelling one with a stat besides the mana stats,
		-- the survival stats and spell power (levelling weighs them at 0): Serenity Field 272439's Spirit alone is not, Golden
		-- Banana 270226's Agility, Strength and Intellect are (its Spirit and Stamina beside them); another mode is an error
		{ "Score.UsePriced: raid every Use buff; levelling one with a stat it weighs; another mode an error", function()
			local sf, gb = ns.UseData[272439], ns.UseData[270226]
			T.eq(Sc.UsePriced(sf, "raid"), true); T.eq(Sc.UsePriced(sf, "level"), false, "Spirit alone")
			T.eq(Sc.UsePriced(gb, "level"), true, "Agility among its stats")
			T.eq(Sc.UsePriced({ stats = { MP5 = 10, MANA = 100, STA = 20, ARMOR = 50, SPELL_POWER = 30 } }, "level"), false)
			T.eq(Sc.UsePriced({ stats = { STA = 20, HIT = 1 } }, "level"), true, "hit priced at its cap")
			T.eq((pcall(Sc.UsePriced, sf, "solo")), false, "another mode")
		end },
		-- stats-gear-4: on-use stat buffs (Game/UseData.lua from tools/gen_use_data.py)
		{ "stats-gear-4: UseData read from the DB2 rows (tools/gen_use_data.py)", function()
			-- Earthstrike 21180: ItemEffect TriggerType 0, cooldown 120000 ms, category 1141 for 20000 ms; spell 25891
			-- A_MOD_ATTACK_POWER + A_MOD_RANGED_ATTACK_POWER bp 280, 20 s (SpellMisc DurationIndex -> SpellDuration)
			local e = ns.UseData[21180]
			T.eq(e.spell, 25891); T.eq(e.stats.AP, 280); T.eq(e.duration, 20); T.eq(e.cooldown, 120); T.eq(e.category, 1141)
			-- Kiss of the Spider 22954: spell 28866 melee haste 319 + ranged haste 140, 20% for 15 s, every 2 min: each
			-- aura its own scope (melee speed: melee and the pet; ranged speed: the shots and the hawks)
			local kiss = ns.UseData[22954].stats
			T.eq(kiss.MELEE_HASTE, 20); T.eq(kiss.RANGED_HASTE, 20); T.eq(kiss.HASTE, nil); T.eq(ns.UseData[22954].duration, 15)
			T.eq(ns.UseData[236268].stats.MELEE_HASTE, 20); T.eq(ns.UseData[236268].stats.RANGED_HASTE, 20)
			local kissPiece = piece("INVTYPE_TRINKET", 22954); kissPiece.use = ns.UseData[22954]
			local Wk = fullW({ MELEE_HASTE = 4.6, RANGED_HASTE = 8.5, HASTE = 10.9 })
			T.near(Sc.SetValue({ [S.TRINKET1] = kissPiece }, Wk, ctx({})), 15 / 120 * 20 * (4.6 + 8.5), 1e-9,
				"priced at W.MELEE_HASTE and W.RANGED_HASTE for its uptime")
			T.eq(ns.UseData[19991], nil, "Devilsaur Eye's Use (spell 24352) roots: not a stat buff")
		end },
		{ "UseData leaves out a buff that a crit uses up and an effect that needs an elemental nearby", function()
			-- Weakness Analyzer 272438: spell 1291101 "... by $s1% for $d or until you deal a non-periodic critical
			-- effect", SpellAuraOptions row 245743 ProcCharges 1 (tools/gen_use_data.py skips aura charges)
			T.eq(ns.UseData[272438], nil, "Weakness Analyzer: used up by the first crit, not priced")
			-- Flamebreak Talisman 280071: spell 1315878 effects 0 and 1 are Agility 33 each; "If there is an elemental
			-- nearby, gain an additional $s2" (gen_use_data.py CONDITIONAL_EFFECTS leaves effect 1 out)
			local f = ns.UseData[280071]
			T.eq(f.spell, 1315878); T.eq(f.stats.AGI, 33); T.eq(f.duration, 30); T.eq(f.cooldown, 300)
			local talisman = piece("INVTYPE_TRINKET", 280071); talisman.use = f
			-- a Use buff's Agility at its Use weight (W.AGI_USE: the pet keeps its summon's attack power, Model.Weights)
			local Wu = fullW({ AGI = 2.5, AGI_USE = 2.2 })
			T.near(Sc.SetValue({ [S.TRINKET1] = talisman }, Wu, ctx({})), 33 * 30 / 300 * 2.2, 1e-9, "33 Agility a tenth of the time")
		end },
		{ "stats-gear-4: an on-use buff counts over its uptime; a hit buff only up to the cap", function()
			local earthstrike = piece("INVTYPE_TRINKET", 21180); earthstrike.use = ns.UseData[21180]
			local stamina = piece("INVTYPE_TRINKET", 2, nil, { STA = 20 })
			local eq = { [S.TRINKET1] = piece("INVTYPE_TRINKET", 3), [S.TRINKET2] = piece("INVTYPE_TRINKET", 4) }
			-- a Use buff's attack power at its Use weight (W.AP_USE, Model.Weights: the pet keeps its summon's attack power, the
			-- user's answer O6), not at W.AP
			local Wu = fullW({ RAP = 1, AP = 1, AP_USE = 0.9, STA = 0.4, HIT = 18 })
			local r = Sc.Evaluate(earthstrike, Wu, ctx(eq))
			T.near(r.delta, 280 * 20 / 120 * 0.9, 1e-9, "280 attack power a sixth of the time")
			local rs = Sc.Evaluate(stamina, Wu, ctx(eq))
			T.truthy(r.delta > rs.delta + 1, "the Use trinket beats the Stamina trinket on damage")
			-- Nat Pagle's Broken Reel 231271: +10% hit for 15 s every 90 s; the set's hit 4% of a 5% cap
			local reel = piece("INVTYPE_TRINKET", 231271); reel.use = ns.UseData[231271]
			local Wh = fullW({ HIT = 18 })
			local v4 = Sc.SetValue({ [S.TRINKET1] = reel }, Wh, ctx({}, nil, { baseHit = 4 }))
			T.near(v4, 18 * 4 + 15 / 90 * 18 * 1, 1e-9, "only the 1% under the cap, for its uptime")
			local v0 = Sc.SetValue({ [S.TRINKET1] = reel }, Wh, ctx({}, nil, { baseHit = 0 }))
			T.near(v0, 15 / 90 * 18 * 5, 1e-9, "from 0% hit: 5% for its uptime")
			-- two burst trinkets never overlap (category 1141 locks for the buff's duration), each keeps its uptime
			local crest = piece("INVTYPE_TRINKET", 23041); crest.use = ns.UseData[23041]
			local both = Sc.SetValue({ [S.TRINKET1] = earthstrike, [S.TRINKET2] = crest }, Wu, ctx({}))
			T.near(both, (280 + 260) * 20 / 120 * 0.9, 1e-9)
			-- the Use weights are read, never skipped: a W without W.AP_USE is an error
			local Wn = fullW({ AP = 1 }); Wn.AP_USE = nil
			local ok, err = pcall(Sc.SetValue, { [S.TRINKET1] = earthstrike }, Wn, ctx({}))
			T.eq(ok, false); T.truthy(tostring(err):find("a Use buff's AP without W.AP_USE", 1, true), tostring(err))
		end },
		-- One buff per Use spell a set: two copies of one item share one cooldown and one aura. Accursed Chalice 228078:
		-- ItemXItemEffect 124552 -> ItemEffect 189379 (TriggerType 0, CoolDownMSec 120000, SpellID 461224), the client keys
		-- the item's cooldown on its item id (C_Container.GetItemCooldown(itemID), Forever ContainerDocumentation.lua), and
		-- both copies cast spell 461224, one aura on the player
		-- The raid mode's Use buffs (raid-mode design 6.8; Score.SetValue): the set's buffs through the raid fight, their gain
		-- ctx.useGain(set) (Advisor: Model.Total with the set's buffs at the model point), their hit, spell hit and expertise
		-- through their caps at ctx.useUptime(set)[spell], the buff's share of the fight (Model.UseUptimes), not duration /
		-- cooldown and not at W. Nat Pagle's Broken Reel 231271 (+10% hit and spell hit, 15 s every 90 s) at a made-up share
		-- 0.2 and a gain of 12.5 with the set's hit at 4% of the 5% cap and its spell hit at 3% of a 4% cap: 12.5 + 0.2 x 18 x 1
		-- + 0.2 x 7 x 1 (my arithmetic); Earthstrike's attack power only through the gain. Score.SetUses: the order the fight
		-- fires them at one instant, wowsims' ItemSlot order (the legs, then trinket 13, then 14), one buff a spell
		{ "raid use: the gain through the fight (ctx.useGain), a hit buff with its cap at the fight's share (ctx.useUptime); Score.SetUses' order", function()
			local reel = piece("INVTYPE_TRINKET", 231271); reel.use = ns.UseData[231271]
			local es = piece("INVTYPE_TRINKET", 21180); es.use = ns.UseData[21180]
			local Wr = fullW({ HIT = 18, SPELL_HIT = 7, AP = 1, AP_USE = 0.9 })
			local seen = {}
			local function raidCtx(extra)
				local c = ctx({}, nil, { mode = "raid", baseHit = 4, baseSpellHit = 3, spellHitCap = 4,
					useGain = function(set) seen[#seen + 1] = set; return 12.5 end, eventGain = function() return 0 end,
					useUptime = function() return { [ns.UseData[231271].spell] = 0.2, [ns.UseData[21180].spell] = 0.25 } end })
				for k, v in pairs(extra or {}) do c[k] = v end
				return c
			end
			local base = Sc.SetValue({}, Wr, raidCtx())
			T.eq(#seen, 0, "a set without a Use buff runs no fight")
			T.near(Sc.SetValue({ [S.TRINKET1] = reel }, Wr, raidCtx()) - base, 12.5 + 0.2 * 18 * 1 + 0.2 * 7 * 1, 1e-9,
				"the gain and the hit and spell hit at the fight's share, under their caps")
			T.near(Sc.SetValue({ [S.TRINKET1] = es }, Wr, raidCtx()) - base, 12.5, 1e-9, "Earthstrike's attack power through the gain alone")
			for _, key in ipairs({ "useGain", "useUptime", "eventGain" }) do
				local bad = raidCtx(); bad[key] = nil
				local ok, err = pcall(Sc.SetValue, { [S.TRINKET1] = reel }, Wr, bad)
				T.eq(ok, false); T.truthy(tostring(err):find("in raid mode without ctx." .. key, 1, true), tostring(err))
			end
			local noMode = raidCtx(); noMode.mode = nil
			local ok, err = pcall(Sc.SetValue, {}, Wr, noMode)
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.mode 'raid' or 'level'", 1, true), tostring(err))
			local noShare = raidCtx({ useUptime = function() return {} end })
			T.eq(pcall(Sc.SetValue, { [S.TRINKET1] = reel }, Wr, noShare), false, "a buff without its share is an error")
			-- the order: the legs (wowsims' ItemSlot 8), trinket 13 (12), trinket 14 (13); two copies of a spell give one buff
			local legs = piece("INVTYPE_LEGS", 14554); legs.use = ns.UseData[14554]
			local es2 = piece("INVTYPE_TRINKET", 21180); es2.use = ns.UseData[21180]
			local uses = Sc.SetUses({ [S.LEGS] = legs, [S.TRINKET2] = reel, [S.TRINKET1] = es })
			T.eq(#uses, 3); T.eq(uses[1].spell, ns.UseData[14554].spell, "the legs before the trinkets")
			T.eq(uses[2].spell, ns.UseData[21180].spell, "trinket 13"); T.eq(uses[3].spell, ns.UseData[231271].spell, "trinket 14")
			local back = piece("INVTYPE_CLOAK", 990003); back.use = ns.UseData[23041]
			local order = Sc.SetUses({ [S.TRINKET1] = es, [S.BACK] = back, [S.LEGS] = legs })
			T.eq(order[1].spell, ns.UseData[23041].spell, "the back (3) before the legs (8)"); T.eq(order[2].spell, ns.UseData[14554].spell)
			local ammo = piece("INVTYPE_AMMO", 990004); ammo.use = ns.UseData[23041]
			local okA, errA = pcall(Sc.SetUses, { [S.AMMO] = ammo })
			T.eq(okA, false); T.truthy(tostring(errA):find("a Use item in slot 0", 1, true), tostring(errA))
			local two = Sc.SetUses({ [S.TRINKET1] = es, [S.TRINKET2] = es2 })
			T.eq(#two, 1, "two copies of Earthstrike: one buff")
			T.eq(#Sc.SetUses({ [S.HEAD] = piece("INVTYPE_HEAD", 5) }), 0, "no Use buff")
		end },
		-- A levelling Use buff's attack power keys at their Use weights (Score.SetValue USE_WEIGHT; Model.Weights W.*_USE: the
		-- pet keeps its summon's attack power, the user's answer O6): RAP at W.RAP_USE, MAP at W.MAP_USE, INT at W.INT_USE, not
		-- at W.RAP, W.MAP or W.INT; its expertise through the cap (expertiseValue) at its uptime in both modes. A made-up buff
		-- of 10 RAP, 20 MAP, 30 Intellect and 2% expertise, 20 s every 120 s, next to a helm of 4% expertise (the cap 5%: 1% of
		-- the buff's counts): levelling 1/6 x (10 x 0.7 + 20 x 0.3 + 30 x 0.2 + 12 x 1); raid mode its attack power keys through
		-- ctx.useGain (12.5 here) and its expertise at the fight's share 0.2: 12.5 + 0.2 x 12 x 1 (my arithmetic)
		{ "a Use buff's RAP, MAP and Intellect at their Use weights; its expertise up to the cap at its uptime, levelling and raid", function()
			local use = { spell = 990001, stats = { RAP = 10, MAP = 20, INT = 30, EXPERTISE = 2 }, duration = 20, cooldown = 120 }
			local it = piece("INVTYPE_TRINKET", 990001); it.use = use
			local helm = piece("INVTYPE_HEAD", 990002, nil, { EXPERTISE = 4 })
			local Wu = fullW({ RAP = 1, RAP_USE = 0.7, AP = 1, AP_USE = 0.9, MAP = 0.5, MAP_USE = 0.3, INT = 0.4, INT_USE = 0.2,
				EXPERTISE = 12 })
			local with, without = { [S.HEAD] = helm, [S.TRINKET1] = it }, { [S.HEAD] = helm }
			T.near(Sc.SetValue(with, Wu, ctx({})) - Sc.SetValue(without, Wu, ctx({})),
				20 / 120 * (10 * 0.7 + 20 * 0.3 + 30 * 0.2 + 12 * 1), 1e-9, "levelling: the Use weights, the expertise to the cap")
			local rc = ctx({}, nil, { mode = "raid", useGain = function() return 12.5 end, eventGain = function() return 0 end,
				useUptime = function() return { [990001] = 0.2 } end })
			T.near(Sc.SetValue(with, Wu, rc) - Sc.SetValue(without, Wu, rc), 12.5 + 0.2 * 12 * 1, 1e-9,
				"raid: the gain and the expertise to the cap at the fight's share")
		end },
		-- The change of the raid fight's consumables' events (raid-mode design 25.1; Score.SetValue): the weights hold the model
		-- point's events, so a set's value adds ctx.eventGain(stats), stats the set's amounts of the stats the fight reads
		-- (Model.FIGHT_KEYS) less the worn set's, its items' and set bonuses' alike, each key whose difference is not 0. A worn
		-- helm of 10 Intellect, 5 Spirit, 1% hit and 7 Stamina with two pieces of a made-up set (4 Agility each, its two-piece
		-- bonus 10 Agility and 1% hit): the worn set passes none; a helm of 14 Intellect, 1 MP5, 5 Spirit, 2% hit and 9 Stamina
		-- and a belt of 50 mana and 1% expertise off the set pass Intellect +4, MP5 +1, mana +50 and Agility -14 (the belt's 4 and
		-- the bonus's 10), no Spirit (the same), no hit, Stamina or expertise; a made-up gain of 3 an Intellect and 100 an MP5
		-- adds 112 at zero weights
		{ "raid events: ctx.eventGain takes the set's stats the fight reads less the worn set's, set bonuses in, hit, stamina and expertise out; none for the worn set; its gain is added", function()
			local seen = {}
			local function eg(stats) seen[#seen + 1] = stats; return 3 * (stats.INT or 0) + 100 * (stats.MP5 or 0) end
			local sets = { [777] = { { n = 2, stats = { AGI = 10, HIT = 1 } } } }
			local helm = piece("INVTYPE_HEAD", 910001, nil, { INT = 10, SPI = 5, HIT = 1, STA = 7 })
			local gloves = piece("INVTYPE_HAND", 910002, 777, { AGI = 4 })
			local belt = piece("INVTYPE_WAIST", 910003, 777, { AGI = 4 })
			local worn = { [S.HEAD] = helm, [S.HANDS] = gloves, [S.WAIST] = belt }
			local rc = ctx(worn, nil, { mode = "raid", useGain = function() return 0 end, useUptime = function() return {} end,
				eventGain = eg, sets = sets })
			local Wz = fullW({})
			local base = Sc.SetValue(worn, Wz, rc)
			T.eq(#seen, 1); T.eq(next(seen[1]), nil, "the worn set: no stats"); T.eq(base, 0)
			local helm2 = piece("INVTYPE_HEAD", 910004, nil, { INT = 14, MP5 = 1, SPI = 5, HIT = 2, STA = 9 })
			local belt2 = piece("INVTYPE_WAIST", 910005, nil, { MANA = 50, EXPERTISE = 1 })
			local v = Sc.SetValue({ [S.HEAD] = helm2, [S.HANDS] = gloves, [S.WAIST] = belt2 }, Wz, rc)
			local d = seen[#seen]
			T.eq(d.INT, 4); T.eq(d.MP5, 1); T.eq(d.MANA, 50); T.eq(d.AGI, -14, "the belt's 4 and the set bonus's 10")
			T.eq(d.SPI, nil, "the same Spirit: no key")
			T.eq(d.HIT, nil); T.eq(d.STA, nil); T.eq(d.EXPERTISE, nil, "priced by their caps or by no fight input")
			local n = 0
			for _ in pairs(d) do n = n + 1 end
			T.eq(n, 4, "four keys")
			T.near(v - base, 3 * 4 + 100 * 1, 1e-12, "the gain added")
		end },
		{ "a set counts one buff per Use spell: two copies in two trinket slots give one; a copy into an empty slot adds only its stats", function()
			local use = ns.UseData[228078]
			T.eq(use.spell, 461224); T.eq(use.stats.STR, 80); T.eq(use.duration, 20); T.eq(use.cooldown, 120)
			local function chalice(stats) local it = piece("INVTYPE_TRINKET", 228078, nil, stats); it.use = use; return it end
			local Ws = fullW({ STR = 1.5, AGI = 2.5, AP = 1, STR_USE = 1.2, AP_USE = 0.9 })
			local one = Sc.SetValue({ [S.TRINKET1] = chalice() }, Ws, ctx({}))
			T.near(one, 80 * 20 / 120 * 1.2, 1e-9, "80 Strength a sixth of the time at its Use weight")
			T.near(Sc.SetValue({ [S.TRINKET1] = chalice(), [S.TRINKET2] = chalice() }, Ws, ctx({})), one, 1e-9, "two copies: one buff")
			local worn = { [S.TRINKET1] = chalice() }
			local withCopy = { [S.TRINKET1] = worn[S.TRINKET1], [S.TRINKET2] = chalice({ AGI = 3 }) }
			T.near(Sc.SetValue(withCopy, Ws, ctx(worn)) - Sc.SetValue(worn, Ws, ctx(worn)), 3 * 2.5, 1e-9, "the copy's own Agility alone")
			-- Use items of two spells each keep their buff (Earthstrike 21180: spell 25891)
			local earthstrike = piece("INVTYPE_TRINKET", 21180); earthstrike.use = ns.UseData[21180]
			T.near(Sc.SetValue({ [S.TRINKET1] = chalice(), [S.TRINKET2] = earthstrike }, Ws, ctx({})), one + 280 * 20 / 120 * 0.9, 1e-9,
				"another spell: its own buff")
			-- each UseData spell belongs to one item, so the buff a spell counts is the same whichever copy gives it
			local items = {}
			for id, u in pairs(ns.UseData) do
				T.eq(items[u.spell], nil, "spell " .. u.spell .. " of items " .. tostring(items[u.spell]) .. " and " .. id)
				items[u.spell] = id
			end
		end },
		-- a set without a bow, gun or crossbow casts no shot and its ranged hand is at bonus 0 (wowsims
		-- sim/core/weapon_skill.go:17-19): against the worn skill only the crit of the pet, the dive and the hawks moves, by
		-- the worn deficit at W.SKILL_CRIT_NO_SHOTS; never the shots' hit (its cap term keeps the worn skill's) or W.SKILL_CRIT
		{ "ranged weapon skill: a set without shots has bonus 0; only what still attacks takes its crit change", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, CRIT = 7, CRIT_RANGED = 1, SKILL_CRIT = 5, SKILL_CRIT_NO_SHOTS = 3 })
			local bow = piece("INVTYPE_RANGED", 1); bow.classID, bow.subclassID = 2, 2
			-- Egan's Blaster 13289: Forever Item.csv build 70888 class 12, InventoryType 26: no weapon
			local blaster = piece("INVTYPE_RANGEDRIGHT", 13289); blaster.classID, blaster.subclassID = 12, 0
			local worn = { [S.RANGED] = bow, [S.FINGER1] = piece("INVTYPE_FINGER", 9, nil, { SKILL_BOWS = 5 }) }
			-- the worn bow and ring 5 over the level's skill (skillBase 0), 15 under it (skillBase -20), under and past the
			-- shots' cap: the set without shots gains 3 x the worn deficit, 0 above the maximum
			for _, case in ipairs({ { base = 0, hit = 1, deficit = 0 }, { base = -20, hit = 1, deficit = 15 }, { base = 0, hit = 6, deficit = 0 },
				{ base = -20, hit = 6, deficit = 15 } }) do
				for _, gain in ipairs({ false, true }) do
					local c = ctx(worn, nil, { baseHit = case.hit, skillBase = case.base, weaponGain = gain and function() return 0 end or nil })
					local v0 = Sc.SetValue(worn, Wk, c)
					for _, r in ipairs({ blaster, false }) do
						local set = Sc.CopySet(worn); set[S.RANGED] = r or nil
						T.near(Sc.SetValue(set, Wk, c) - v0, 3 * case.deficit, 1e-9, string.format("%s, skillBase %d, hit %d, weaponGain %s",
							r and "the Blaster" or "an empty ranged slot", case.base, case.hit, tostring(gain)))
					end
				end
			end
			-- no bow worn (skillBase 0): another set without one changes nothing; a bow's own skill counts: the ring's +5
			-- Bows, 0.5% of the shots' hit (the gap -5 at +0), no crit above the maximum
			local bare = { [S.FINGER1] = worn[S.FINGER1] }
			local c0 = ctx(bare, nil, { baseHit = 1 })
			T.near(Sc.SetValue({ [S.RANGED] = blaster, [S.FINGER1] = worn[S.FINGER1] }, Wk, c0) - Sc.SetValue(bare, Wk, c0), 0, 1e-12, "the Blaster")
			T.near(Sc.SetValue(worn, Wk, c0) - Sc.SetValue(bare, Wk, c0), 4 * 0.5, 1e-9, "the bow with the ring's +5 Bows")
		end },
		-- The shots' skill hit by wowsims' table (ns.Model.SkillHit, raid-mode W1 design 3.3): +5 over the maximum is the gap
		-- 15 - 5 = 10 at +3, 6% miss against the 8% cap, 2% of hit; at +0 the gap -5, 4.5% against 5%, 0.5% (my arithmetic).
		-- Mutant: 0.04 a point (0.2%)
		{ "score: +5 Bows reach the shots' cap as 2% hit at +3 and 0.5% at +0", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, SKILL_CRIT = 5 })
			local bow = piece("INVTYPE_RANGED", 1, nil, { SKILL_BOWS = 5 }); bow.classID, bow.subclassID = 2, 2
			local function value(mobDiff, baseHit)
				return Sc.SetValue({ [S.RANGED] = bow }, Wk, ctx({}, nil, { mobDiff = mobDiff, hitCap = ns.Model.HitCap(mobDiff), baseHit = baseHit }))
			end
			T.near(value(3, 2), 10 * 2 + 4 * 2.0, 1e-9, "+3: 2% of the shots' hit")
			T.near(value(0, 2), 10 * 2 + 4 * 0.5, 1e-9, "+0: 0.5%")
			T.near(value(3, 7), 10 * 7 + 4 * 1, 1e-9, "+3 at 7%: 1% left under the 8% cap")
		end },
		-- The skill's crit (Model critSuppressor, petCritBase): nothing above the level's maximum, W.SKILL_CRIT a point below
		-- it, against the worn set's deficit; past the cap (9% hit at +0) the hit adds nothing. Mutant: the crit priced for
		-- skill above the maximum too
		{ "score: skill above the maximum adds no crit; each point below costs W.SKILL_CRIT", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, SKILL_CRIT = 5 })
			local function ranged(id, subclass, stats)
				local r = piece("INVTYPE_RANGED", id, nil, stats); r.classID, r.subclassID = 2, subclass; return r
			end
			local plain, bow5, bow15 = ranged(1, 2), ranged(2, 2, { SKILL_BOWS = 5 }), ranged(3, 2, { SKILL_BOWS = 15 })
			local function gain(skillBase, set)
				local c = ctx({ [S.RANGED] = plain }, nil, { baseHit = 9, skillBase = skillBase })
				return Sc.SetValue(set, Wk, c) - Sc.SetValue({ [S.RANGED] = plain }, Wk, c)
			end
			T.near(gain(0, { [S.RANGED] = bow5 }), 0, 1e-12, "at the maximum: +5 adds no crit")
			T.near(gain(-10, { [S.RANGED] = bow5 }), 5 * 5, 1e-9, "10 below: +5 lifts 5 points of deficit")
			T.near(gain(-10, { [S.RANGED] = bow15 }), 5 * 10, 1e-9, "10 below: +15 lifts the 10 up to the maximum alone")
			-- a gun of a line trained 15 below the worn bows' (Advisor rangedSkillPiece skillOffset), the bows at +5: the gun
			-- at -10, 10 points of deficit more
			local gun = ranged(4, 3); gun.skillOffset = -15
			T.near(gain(5, { [S.RANGED] = gun }), -5 * 10, 1e-9, "from +5 to -10: 10 points below the maximum")
		end },
		-- A set without shots: its ranged hand at bonus 0 (wowsims sim/core/weapon_skill.go:17-19), so against a worn skill 20
		-- below the maximum (195 of 215) its pet, dive and hawks gain the 20 points at W.SKILL_CRIT_NO_SHOTS; its shots' cap
		-- term keeps the worn skill's -4% (the gap 20: 9% miss). At 2% hit: the worn set 10 x 2 + 4 x (min(2 - 4, 5) - 2) (my
		-- arithmetic). Mutants: W.SKILL_CRIT for it; the set's skill hit 0
		{ "score: a set without shots gains W.SKILL_CRIT_NO_SHOTS x the worn deficit; its shots' cap term keeps the worn skill's hit", function()
			local Wk = fullW({ HIT = 10, HIT_RANGED = 4, SKILL_CRIT = 5, SKILL_CRIT_NO_SHOTS = 3 })
			local bow = piece("INVTYPE_RANGED", 1); bow.classID, bow.subclassID = 2, 2
			local worn = { [S.RANGED] = bow }
			local c = ctx(worn, nil, { baseHit = 2, skillBase = -20 })
			T.near(Sc.SetValue(worn, Wk, c), 10 * 2 + 4 * -4, 1e-9, "the worn set: the shots at -2%")
			T.near(Sc.SetValue({}, Wk, c), 10 * 2 + 4 * -4 + 3 * 20, 1e-9, "no ranged weapon: the worn shots' term and 20 points of crit")
		end },
		-- ctx.weaponGain runs the weapons at ctx.wornHit, the worn hit of every attack: the dual-wield part counts past the
		-- cap beyond it, and the worn ranged skill's hit (the shots' own hit) stays out of it
		{ "dual-wield hit past the cap with ctx.weaponGain: beyond ctx.wornHit itself, whatever the worn ranged skill", function()
			local Wd = fullW({ HIT = 10, HIT_RANGED = 4, HIT_DW = 3 })
			local dw = { [S.MAINHAND] = piece("INVTYPE_WEAPON", 1, nil, { DPS = 20, HIT = 1 }), [S.OFFHAND] = piece("INVTYPE_WEAPON", 2, nil, { DPS = 20, HIT = 1 }) }
			local th = { [S.MAINHAND] = piece("INVTYPE_2HWEAPON", 3, nil, { DPS = 30 }) }
			for _, base in ipairs({ 0, -8 }) do
				local c = ctx(th, nil, { baseHit = 9, wornHit = 9, skillBase = base, weaponGain = function() return 0 end })
				T.near(Sc.SetValue(dw, Wd, c) - Sc.SetValue(th, Wd, c), 3 * 2, 1e-9, "the pair's 2% past the worn 9%, skillBase " .. base)
			end
		end },
		-- The main hand's skill hit meets the melee consumers' cap on top of h (raid-mode W1 design 3.4): at W.HIT_MELEE x
		-- (min(h + skM, cap) - min(h, cap)), skM = ns.Model.SkillHit(ctx.mobDiff, the set's main-hand skill). A sword line
		-- trained 10 below the maximum (ctx.meleeTrained): skM -1%, with +5 Swords -0.5% (the gap 10 and 5 at +0); ctx.weaponGain
		-- prices the rest of the skill. Mutant: the melee part at h alone
		{ "melee hit: the melee part meets the cap with h + Model.SkillHit(d, MH skill)", function()
			local Wm = fullW({ HIT = 10, HIT_MELEE = 4 })
			local sword = piece("INVTYPE_WEAPON", 1, nil, { DPS = 20 }); sword.classID, sword.subclassID = 2, 7
			local ring = piece("INVTYPE_FINGER", 2, nil, { SKILL_SWORDS = 5 })
			local function value(set, baseHit)
				local c = ctx({ [S.MAINHAND] = sword }, nil, { baseHit = baseHit, weaponGain = function() return 0 end,
					meleeTrained = function(w) return w.subclassID == 7 and -10 or 0 end })
				return Sc.SetValue(set, Wm, c)
			end
			T.near(value({ [S.MAINHAND] = sword }, 3), 10 * 3 + 4 * -1, 1e-9, "3% hit: the main hand at 2%")
			T.near(value({ [S.MAINHAND] = sword, [S.FINGER1] = ring }, 3), 10 * 3 + 4 * -0.5, 1e-9, "with +5 Swords: at 2.5%")
			T.near(value({ [S.MAINHAND] = sword }, 5.5), 10 * 5 + 4 * -0.5, 1e-9, "5.5%: the main hand 0.5% under the 5% cap")
			T.near(value({ [S.MAINHAND] = sword }, 7), 10 * 5, 1e-9, "past the cap with the skill's -1%: nothing")
			T.near(value({}, 3), 10 * 3, 1e-9, "no main hand: bonus 0")
			-- a W with a weight under the melee skill stat's own key (Model.Weights never sets one): never read
			local Wskill = fullW({ HIT = 10, HIT_MELEE = 4 }); Wskill.SKILL_SWORDS = 100
			local c = ctx({ [S.MAINHAND] = sword }, nil, { baseHit = 3, weaponGain = function() return 0 end,
				meleeTrained = function(w) return w.subclassID == 7 and -10 or 0 end })
			T.near(Sc.SetValue({ [S.MAINHAND] = sword, [S.FINGER1] = ring }, Wskill, c), 10 * 3 + 4 * -0.5, 1e-9, "never a linear skill weight")
			T.near(Sc.ItemValue(ring, "armor", Wskill), 0, 1e-12, "the ring alone: nothing")
			local sets = { [99911] = { name = "made-up", { n = 1, spell = 1, stats = { SKILL_SWORDS = 5 } } } }
			c.sets = sets
			T.near(Sc.SetValue({ [S.MAINHAND] = sword, [S.FINGER1] = piece("INVTYPE_FINGER", 99912, 99911) }, Wskill, c), 10 * 3 + 4 * -0.5,
				1e-9, "a set bonus's +5 Swords: in the skill, no weight")
			-- a set with a weapon of a melee line needs ctx.meleeTrained
			c.meleeTrained = nil
			local ok, err = pcall(Sc.SetValue, { [S.MAINHAND] = sword }, Wm, c)
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.meleeTrained", 1, true), tostring(err))
		end },
		-- Dual wield past the cap per hand (raid-mode W1 design 3.4): the main hand's white swings meet it with h + skM in
		-- room(h + skM, 19) at W.HIT_DW_MH, the off hand's with h alone in its own room 19 - skO at W.HIT_DW - W.HIT_DW_MH
		-- (its miss Model.SkillMiss(d, its skill) + 19 - h). A sword main hand 10 below the maximum (skM -1%), a dagger off
		-- hand 10 above (skO +1%, room 18), the 5% cap. With ctx.weaponGain from the worn 9% and the worn main hand's -1%: the
		-- main hand from room(8, 19) = 3, the off hand from room(9, 18) = 4 (my arithmetic). A ring of 2% hit and +5 Swords
		-- moves the set's main hand to 5 below (skM -0.5%): its part meets the cap at 11% - 0.5% from the worn main hand's
		-- room(9% - 1%, 19), the hit the weapon run holds (ctx.wornMeleeHit), 2 x (5.5 - 3) (my arithmetic). Mutants: W.HIT_DW x
		-- room(h + skM, 19) for both hands; the off hand's room 19; the main hand's part from the set's own skill hit
		{ "dual-wield hit past the cap: the main hand's part meets it with h + its skill hit, the off hand's with h in its own room 19 - its skill hit", function()
			local Wd = fullW({ HIT = 10, HIT_DW = 3, HIT_DW_MH = 2 })
			local sword = piece("INVTYPE_WEAPON", 1, nil, { DPS = 20 }); sword.classID, sword.subclassID = 2, 7
			local dagger = piece("INVTYPE_WEAPON", 2, nil, { DPS = 20 }); dagger.classID, dagger.subclassID = 2, 15
			local function trained(w) return w.subclassID == 7 and -10 or 10 end
			local function set(hit) return { [S.MAINHAND] = sword, [S.OFFHAND] = dagger, [S.FINGER1] = piece("INVTYPE_FINGER", 3, nil, { HIT = hit }) } end
			local c = ctx(set(0), nil, { baseHit = 9, wornHit = 9, wornMeleeHit = -1, meleeTrained = trained, weaponGain = function() return 0 end })
			T.near(Sc.SetValue(set(0), Wd, c), 10 * 5, 1e-9, "at the worn hit: nothing on top of the model")
			T.near(Sc.SetValue(set(2), Wd, c), 10 * 5 + 2 * (5 - 3) + 1 * (6 - 4), 1e-9, "2% more: each hand 2% in its room")
			T.near(Sc.SetValue(set(21), Wd, c), 10 * 5 + 2 * (19 - 3) + 1 * (18 - 4), 1e-9, "both rooms full: 19 and 18")
			local skillRing = { [S.MAINHAND] = sword, [S.OFFHAND] = dagger, [S.FINGER1] = piece("INVTYPE_FINGER", 4, nil, { HIT = 2, SKILL_SWORDS = 5 }) }
			T.eq((Sc.MeleeSkills(skillRing, c)), -5, "the ring's main hand at 5 below")
			T.near(Sc.SetValue(skillRing, Wd, c), 10 * 5 + 2 * (5.5 - 3) + 1 * (6 - 4), 1e-9, "the main hand's part from the worn skill hit")
			-- a worn hit of 25%: the worn main hand at 24% and the off hand at 25% fill their rooms (19 and 18); the set at the
			-- worn hit adds nothing
			local c25 = ctx(set(16), nil, { baseHit = 9, wornHit = 25, wornMeleeHit = -1, meleeTrained = trained, weaponGain = function() return 0 end })
			T.near(Sc.SetValue(set(16), Wd, c25), 10 * 5, 1e-9, "the worn 25%: both rooms full, nothing on top")
			-- without ctx.weaponGain (the worn set's skills): each hand's whole room past the cap
			local plain = ctx(set(0), nil, { baseHit = 9, meleeTrained = trained })
			T.near(Sc.SetValue(set(2), Wd, plain), 10 * 5 + 2 * 5 + 1 * 6, 1e-9, "11% hit: the main hand at 10%, the off hand at 11%")
			-- at skill 0 on both hands the two parts are W.HIT_DW x the hit past the cap
			local level = ctx(set(0), nil, { baseHit = 9 })
			T.near(Sc.SetValue(set(2), Wd, level), 10 * 5 + 3 * 6, 1e-9, "skill 0: W.HIT_DW x 6")
			local noWorn = ctx(set(0), nil, { baseHit = 9, wornHit = 9, meleeTrained = trained, weaponGain = function() return 0 end })
			noWorn.wornMeleeHit = nil
			local ok, err = pcall(Sc.SetValue, set(2), Wd, noWorn)
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.wornMeleeHit", 1, true), tostring(err))
		end },
		-- melee weapon skill is priced only by the weapon run (ctx.weaponGain) and the main hand's skill hit: without
		-- ctx.weaponGain a set whose melee skills differ from the worn set's is an error, the off hand's alone too (a dagger
		-- off hand and a ring of +5 Daggers). Mutants: the check removed; the main hand's skill checked alone
		{ "score: a set's melee skill without ctx.weaponGain is an error", function()
			local sword = piece("INVTYPE_WEAPON", 1, nil, { DPS = 20 }); sword.classID, sword.subclassID = 2, 7
			local ring = piece("INVTYPE_FINGER", 2, nil, { SKILL_SWORDS = 5 })
			local worn = { [S.MAINHAND] = sword }
			local c = ctx(worn, nil, { baseHit = 3 })
			local ok, err = pcall(Sc.SetValue, { [S.MAINHAND] = sword, [S.FINGER1] = ring }, W, c)
			T.eq(ok, false); T.truthy(tostring(err):find("melee weapon skill differs from the worn set's without ctx.weaponGain", 1, true), tostring(err))
			T.truthy(pcall(Sc.SetValue, { [S.MAINHAND] = sword, [S.FINGER1] = piece("INVTYPE_FINGER", 3, nil, { SKILL_DAGGERS = 5 }) }, W, c),
				"+5 Daggers with a sword: the same skills")
			c.weaponGain = function() return 0 end
			T.truthy(pcall(Sc.SetValue, { [S.MAINHAND] = sword, [S.FINGER1] = ring }, W, c), "with ctx.weaponGain")
			local dagger = piece("INVTYPE_WEAPON", 4, nil, { DPS = 20 }); dagger.classID, dagger.subclassID = 2, 15
			local dw = ctx({ [S.MAINHAND] = sword, [S.OFFHAND] = dagger }, nil, { baseHit = 3 })
			ok, err = pcall(Sc.SetValue, { [S.MAINHAND] = sword, [S.OFFHAND] = dagger, [S.FINGER1] = piece("INVTYPE_FINGER", 5, nil, { SKILL_DAGGERS = 5 }) }, W, dw)
			T.eq(ok, false, "the off hand's skill alone"); T.truthy(tostring(err):find("melee weapon skill differs from the worn set's without ctx.weaponGain", 1, true), tostring(err))
		end },
		-- Score.MeleeSkills reads each hand alone (raid-mode W1 design 3.4): an off-hand dagger beside an empty main hand, or
		-- beside a main-hand weapon of no melee line (subclass 14, miscellaneous), is at its line's trained skill and the set's
		-- points for it; that main hand at 0 (an empty hand: wowsims sim/core/weapon_skill.go:17-19; a weapon of no line: its
		-- WeaponSkillUnknown entry, as Score.MeleeSkills reads it). Mutant: both hands 0 when the main hand has no line
		{ "score: MeleeSkills: an off-hand weapon beside an empty main hand or one of no melee line", function()
			local dagger = piece("INVTYPE_WEAPON", 1, nil, { DPS = 20 }); dagger.classID, dagger.subclassID = 2, 15
			local misc = piece("INVTYPE_WEAPON", 2, nil, { DPS = 5 }); misc.classID, misc.subclassID = 2, 14
			local ring = piece("INVTYPE_FINGER", 3, nil, { SKILL_DAGGERS = 4 })
			local c = ctx({}, nil, { meleeTrained = function(w)
				if w.subclassID ~= 15 then error("a weapon of no melee line asked for its trained skill") end
				return -7
			end })
			local mh, oh = Sc.MeleeSkills({ [S.OFFHAND] = dagger, [S.FINGER1] = ring }, c)
			T.eq(mh, 0); T.eq(oh, -3)
			mh, oh = Sc.MeleeSkills({ [S.MAINHAND] = misc, [S.OFFHAND] = dagger }, c)
			T.eq(mh, 0); T.eq(oh, -7)
		end },
		-- The melee skill stat of each melee weapon subclass (DB2 ItemSubClass class 2; Game/Player.lua's skill lines): 0 Axes,
		-- 1 Two-Handed Axes, 4 Maces, 5 Two-Handed Maces, 6 Polearms, 7 Swords, 8 Two-Handed Swords, 10 Staves, 13 Fist
		-- Weapons, 15 Daggers; no other subclass (the ranged ones, thrown, wands, fishing poles, miscellaneous). Mutants: two
		-- subclasses swapped (7 as SKILL_2H_SWORDS); a subclass missing
		{ "score: MELEE_SKILL maps each melee weapon subclass to its line's key (0, 1, 4, 5, 6, 7, 8, 10, 13, 15)", function()
			local want = { [0] = "SKILL_AXES", [1] = "SKILL_2H_AXES", [4] = "SKILL_MACES", [5] = "SKILL_2H_MACES", [6] = "SKILL_POLEARMS",
				[7] = "SKILL_SWORDS", [8] = "SKILL_2H_SWORDS", [10] = "SKILL_STAVES", [13] = "SKILL_FIST", [15] = "SKILL_DAGGERS" }
			for sub = 0, 20 do
				T.eq(Sc.MELEE_SKILL[sub], want[sub], "subclass " .. sub)
				T.eq(Sc.MeleeSkillStat({ classID = 2, subclassID = sub }), want[sub], "a weapon of subclass " .. sub)
			end
			T.eq(Sc.MeleeSkillStat({ classID = 4, subclassID = 0 }), nil, "an item held in the off hand: no weapon")
			T.eq(Sc.MeleeSkillStat(nil), nil, "an empty hand")
		end },
		-- the weights the scorer names are read as they are: Model.Weights always sets them, so a W without one is an error
		{ "a W without a weight the scorer names is an error where it is read", function()
			local function without(key) local w = fullW({ AGI = 1 }); w[key] = nil; return w end
			local bow = piece("INVTYPE_RANGED", 1, nil, { DPS = 20, RANGED_FLAT = 5 }); bow.classID, bow.subclassID, bow.speed = 2, 2, 2.5
			local ammo = piece("INVTYPE_AMMO", 2, nil, { AMMO_DPS = 10 })
			local gloves = piece("INVTYPE_HAND", 7284); gloves.procs = { proc(250, "any", true) }
			local beast = piece("INVTYPE_WEAPON", 4, nil, { DPS = 20, BEAST_SLAYING = 6 }); beast.speed = 2.4
			local beastStaff = piece("INVTYPE_2HWEAPON", 8, nil, { DPS = 30, BEAST_SLAYING = 6 }); beastStaff.speed = 3.2
			local plainBow = piece("INVTYPE_RANGED", 5, nil, { DPS = 20 }); plainBow.classID, plainBow.subclassID, plainBow.speed = 2, 2, 2.5
			local sword = piece("INVTYPE_WEAPON", 6, nil, { DPS = 20 }); sword.speed = 2.6
			local staff = piece("INVTYPE_2HWEAPON", 7, nil, { DPS = 30 }); staff.speed = 3.2
			local c = ctx({}, nil, { landedHitsFor = madeUpHits })
			local reads = {
				{ "AMMO_DPS", function(w) return Sc.ItemValue(ammo, "ammo", w) end },
				{ "RANGED_DPS", function(w) return Sc.ItemValue(bow, "ranged", w) end },
				{ "RANGED_DPS", function(w) return Sc.ItemValue(plainBow, "ranged", w) end },
				{ "MH_DPS", function(w) return Sc.ItemValue(sword, "mh", w) end },
				{ "OH_DPS", function(w) return Sc.ItemValue(sword, "oh", w) end },
				{ "TH_DPS", function(w) return Sc.ItemValue(staff, "2h", w) end },
				{ "EXTRA_DPS", function(w) return Sc.ProcValue(gloves, "armor", w, madeUpHits({}), c) end },
				{ "EXTRA_DPS", function(w) return Sc.SetValue({ [S.HANDS] = gloves }, w, c) end },
				{ "BEAST_SLAYING", function(w) return Sc.ItemValue(beast, "mh", w) end },
				{ "BEAST_SLAYING", function(w) return Sc.ItemValue(beast, "oh", w) end },
				{ "BEAST_SLAYING", function(w) return Sc.ItemValue(beastStaff, "2h", w) end },
				{ "HIT", function(w) return Sc.SetValue({}, w, c) end },
				{ "HIT_RANGED", function(w) return Sc.SetValue({}, w, c) end },
				{ "HIT_DW", function(w) return Sc.SetValue({}, w, c) end },
				{ "SKILL_CRIT", function(w) return Sc.SetValue({ [S.RANGED] = bow }, w, c) end },
				{ "SKILL_CRIT_NO_SHOTS", function(w) return Sc.SetValue({}, w, c) end },
				{ "EXPERTISE", function(w) return Sc.SetValue({}, w, c) end },
			}
			for _, r in ipairs(reads) do
				T.truthy(pcall(r[2], fullW({ AGI = 1 })), r[1] .. ": a full W scores")
				local ok, err = pcall(r[2], without(r[1]))
				T.eq(ok, false, r[1] .. " missing")
				-- an arithmetic error names the field; a comparison (HIT_DW > 0) does not
				if r[1] ~= "HIT_DW" then T.truthy(tostring(err):find("'" .. r[1] .. "'", 1, true), tostring(err)) end
			end
		end },
		-- A linked equip aura (Items.LinkProcs: the Game/ProcData.lua entry's mask, chance, ppm, icd) rolls on the hits of its
		-- ProcTypeMask (wowsims sim/core/proc_types.go:86-175): 0x4 the white melee swings of both hands, 0x10 the main hand's
		-- specials, 0x40 Auto Shot, 0x100 the ranged abilities (the shots and the dives) and, with the harmful-spell bit
		-- 0x10000 (no RequireDamageDealt), Serpent Sting's applications, unless the item keeps RequireDamageDealt (the Tablet,
		-- Score.PROC_OVERRIDES). Made-up hits: a 2.6 s main hand (0.02 swings, 0.003 specials), a 1.8 s off hand (0.03), a
		-- 2.8 s bow (0.5 Auto Shots, 0.17 specials, 0.04 applications); chance 100, no stated rate: the test gives the ring a
		-- measured 1.5 at each hand's speed (measuredFor; U4 = (a))
		{ "equip procs by mask: 0x4 swings, 0x10 melee specials, 0x40 Auto Shots, 0x100 the ranged specials, 0x10000 the applications", function()
			local undo = measuredFor(1.5, { id = 99701 })
			local hits = hitsOf({ 0.02, 0.003, 2.6 }, { 0.03, 1.8 }, { 0.5, 0.17, 2.8, 0.04 })
			local o = { procOutcome = WHOLE_OUTCOME }
			local ring = piece("INVTYPE_FINGER", 99701)
			local function rate(mask, item)
				local p = { avg = 100, hits = "any", equip = true, school = "magic", linked = true, defense = 1, crit = true,
					mask = mask, chance = 100, ppm = 0, icd = 0 }
				return Sc.ProcRate(item or ring, "armor", p, hits, o)
			end
			T.near(rate(0x4), 1.5 * (2.6 * 0.02 + 1.8 * 0.03), 1e-12, "0x4: both hands' white swings")
			T.near(rate(0x10), 1.5 * 2.6 * 0.003, 1e-12, "0x10: the main hand's specials")
			T.near(rate(0x40), 1.5 * 2.8 * 0.5, 1e-12, "0x40 alone: Auto Shots only")
			T.near(rate(0x140), 1.5 * 2.8 * (0.5 + 0.17), 1e-12, "0x140: the shots and the dives, no application")
			T.near(rate(0x10100), 1.5 * 2.8 * (0.17 + 0.04), 1e-12, "0x10100: the ranged specials and Serpent Sting's applications")
			T.eq(rate(0x10000), 0, "0x10000 alone: a spell cast, no hunter hit")
			local tablet = piece("INVTYPE_TRINKET", 260205); tablet.classID = 4
			T.near(rate(65876, tablet), 2.6 * (2.6 * (0.02 + 0.003) + 1.8 * 0.03 + 2.8 * (0.5 + 0.17)), 1e-12,
				"the Tablet's 0x10154 keeps RequireDamageDealt: no application")
			undo()
		end },
		-- At a Survival point with Raptor Strike (the model's landed hits, Model.LandedHits): an equip aura of mask 0x4 rolls
		-- the white swings of both hands, which leave out the swings Raptor Strike takes, and one of mask 0x10 the main hand's
		-- specials, Raptor Strike and Wing Clip among them (wowsims casts Raptor Strike in the swing's place with
		-- ProcMaskMeleeMHSpecial, sim/hunter/raptor_strike.go:13, 60-71, a melee special: sim/core/flags.go:75, 79; Wing Clip
		-- likewise, wing_clip.go:15). Level 43, +3, 1% hit, the Survival weave (its counts averaged over Rapid Fire,
		-- Model.Weave), a 2.6 s main hand and a 1.8 s off hand: the white swings land with 1 - 26% - 6.5%, the specials with
		-- 1 - 7% - 6.5%; an 8% chance a hit (my arithmetic)
		{ "equip procs by mask at a Survival point: 0x4 the white swings without Raptor Strike, 0x10 Raptor Strike", function()
			local sv = refPoint({ mobDiff = 3, survival = true })
			local hits = ns.Model.LandedHits(sv)
			local r = ns.Model.Weave(sv).average.rates
			local o = { procOutcome = WHOLE_OUTCOME }
			local function rate(mask)
				local p = { avg = 100, hits = "melee", equip = true, school = "magic", linked = true, defense = 1, crit = true,
					mask = mask, chance = 8, ppm = 0, icd = 0 }
				return Sc.ProcRate(piece("INVTYPE_FINGER", 99705), "armor", p, hits, o)
			end
			T.truthy(r.raptor > 0 and r.mhWhite > 0, "Raptor Strike and white swings")
			T.near(rate(0x4), 60 * 0.08 * (r.mhWhite + r.oh) * 0.675, 1e-12, "0x4: the white swings")
			T.near(rate(0x10), 60 * 0.08 * (r.raptor + r.wingClip) * 0.865, 1e-12, "0x10: Raptor Strike and Wing Clip")
			T.near(rate(0x14), rate(0x4) + rate(0x10), 1e-12, "0x14: both")
		end },
		-- The rate of a linked equip aura (Score.ProcRateSource, U4 = (a)): the item's MEASURED_PPM first, per minute at the
		-- hand's speed; else a procs per minute (wowsims' override row, the entry's source, or the DB2's SpellProcsPerMinute)
		-- at the speed of the hand that hits; else a chance of 1 to 99 a hit (an override row's or the DB2's), whatever the
		-- speed; else (100, 101, 0: no stated rate, no row) no proc. The internal cooldown (ProcCategoryRecovery, ms) caps a
		-- trigger of r a second at r / (1 + r x icd / 1000) (the mean gap icd + 1 / r; my arithmetic)
		{ "equip proc rate: MEASURED_PPM, else PPM or chance 1-99 (an override row's or the DB2's), else none; the ICD caps it", function()
			local hits = hitsOf({ 0.02, 0.003, 2.6 }, { 0.03, 1.8 }, { 0.5, 0.17, 2.8, 0.04 })
			local o = { procOutcome = WHOLE_OUTCOME }
			local function rate(chance, ppm, icd, id, source)
				local p = { avg = 100, hits = "ranged", equip = true, school = "magic", linked = true, defense = 1, crit = true,
					mask = 0x140, chance = chance, ppm = ppm, icd = icd, source = source }
				return Sc.ProcRate(piece("INVTYPE_FINGER", id or 99702), "armor", p, hits, o)
			end
			local n = 0.5 + 0.17
			T.near(rate(100, 2, 0), 2 * 2.8 * n, 1e-12, "a stated 2 a minute at the bow's speed")
			T.near(rate(8, 0, 0), 60 * 0.08 * n, 1e-12, "8% a hit, whatever the speed")
			T.near(rate(99, 0, 0), 60 * 0.99 * n, 1e-12, "99% a hit")
			for _, c in ipairs({ 100, 101, 0 }) do
				T.eq(rate(c, 0, 0), 0, "chance " .. c .. ": no stated rate, no row: no proc (no rate is made up)")
			end
			T.near(rate(100, 0, 0, 13040), 2.7 * 2.8 * n, 1e-12, "no stated rate on a measured item: its MEASURED_PPM")
			T.near(rate(100, 2, 0, 13040), 2.7 * 2.8 * n, 1e-12, "the measured rate before a stated one")
			T.near(rate(100, 1.5, 0, nil, "vanilla-carryover"), 1.5 * 2.8 * n, 1e-12, "wowsims' carried-over rate at the bow's speed")
			T.near(rate(8, 0, 0, nil, "EV-0115"), 60 * 0.08 * n, 1e-12, "wowsims' chance row: 8% a hit")
			T.eq(pcall(rate, 100, 0, 0, nil, "vanilla-carryover"), false, "an override source without a rate is an error")
			local r = 0.08 * n
			T.near(rate(8, 0, 200), 60 * r / (1 + r * 0.2), 1e-12, "8% capped by a 0.2 s internal cooldown")
			local q = 2 * 2.8 * n / 60
			T.near(rate(100, 2, 10000), 60 * q / (1 + q * 10), 1e-12, "a stated rate capped by a 10 s internal cooldown")
		end },
		-- With no ranged weapon the ranged hand's speed is 0 (Model.LandedHits): a rate at the hand's speed (a stated or a
		-- hand-supplied procs per minute) finds the dives none to roll at, as wowsims' managers skip the ranged entry of speed
		-- 0 (sim/core/procs.go:183-227); a fixed chance hears them; the Tablet's spellsAtMainHand rolls them at the main hand's
		{ "PPM equip proc without a ranged weapon: the dive does not roll it; a chance does; the Tablet at the main hand's speed", function()
			local hits = hitsOf({ 0.02, 0.003, 2.6 }, { 0.03, 1.8 }, { 0, 2 / 18, 0, 0 })
			local o = { procOutcome = WHOLE_OUTCOME }
			local function rate(chance, ppm, item)
				local p = { avg = 100, hits = "ranged", equip = true, school = "magic", linked = true, defense = 1, crit = true,
					mask = 0x100, chance = chance, ppm = ppm, icd = 0 }
				return Sc.ProcRate(item or piece("INVTYPE_FINGER", 99703), "armor", p, hits, o)
			end
			T.eq(rate(100, 2), 0, "a stated rate: no ranged speed")
			T.eq(rate(100, 0), 0, "no stated rate: no proc")
			T.near(rate(8, 0), 60 * 0.08 * 2 / 18, 1e-12, "8% a dive")
			local tablet = piece("INVTYPE_TRINKET", 260205); tablet.classID = 4
			T.near(rate(100, 0, tablet), 2.6 * 2.6 * 2 / 18, 1e-12, "the Tablet: the dives at the main hand's 2.6 s")
		end },
		-- A proc's value (Score.ProcValue): its average x the hunter's damage multiplier (own) x the armor for the physical
		-- school (phys) or Curse of the Elements for a magic one (coe), plus Gift of Arthas on a physical one (gift, after the
		-- armor, before the outcome: raid-mode design 5.3), x its table's outcome (its DefenseType; 0 by the school), the crit
		-- factor left out when the spell cannot crit, x its procs per second, at W.EXTRA_DPS. Made-up outcomes, each number
		-- its own; first without the raid boss's debuffs (coe 1, gift 0)
		{ "proc value: the table by DefenseType, 0 by the school; armor on the physical school alone; no crit factor when it cannot crit; x own", function()
			local hits = hitsOf({ 0.02, 0.003, 2.6 }, { 0.03, 1.8 }, { 0.5, 0.17, 2.8, 0.04 })
			local A, B, C = { hit = 0.9, critMult = 1.2 }, { hit = 0.8, critMult = 1.1 }, { hit = 0.95, critMult = 1.3 }
			local outcome = { [0] = { physical = A, magic = B }, [1] = B, [2] = A, [3] = C, phys = 0.6, own = 1.1, coe = 1, gift = 0 }
			local o = { procOutcome = outcome }
			local ring = piece("INVTYPE_FINGER", 99704)
			local function value(school, defense, crit)
				ring.procs = { { avg = 100, hits = "melee", equip = true, school = school, linked = false, defense = defense, crit = crit } }
				local rate = Sc.ProcRate(ring, "armor", ring.procs[1], hits, o)
				return Sc.ProcValue(ring, "armor", W, hits, o) / (100 * rate / 60 * W.EXTRA_DPS)
			end
			T.near(value("magic", 1, true), 1.1 * 0.8 * 1.1, 1e-12, "magic table, magic school")
			T.near(value("physical", 2, true), 1.1 * 0.6 * 0.9 * 1.2, 1e-12, "melee table, physical school: the armor")
			T.near(value("magic", 3, true), 1.1 * 0.95 * 1.3, 1e-12, "ranged table, magic school: no armor")
			T.near(value("physical", 3, false), 1.1 * 0.6 * 0.95, 1e-12, "a spell that cannot crit: no crit factor")
			T.near(value("physical", 0, true), 1.1 * 0.6 * 0.9 * 1.2, 1e-12, "no DefenseType, physical: the melee table")
			T.near(value("magic", 0, true), 1.1 * 0.8 * 1.1, 1e-12, "no DefenseType, magic: the spell table")
			-- the raid boss's debuffs (raid mode): Curse of the Elements x1.10 on a magic proc, not on a physical one; Gift of
			-- Arthas +8 on a physical proc after the armor and own, before the outcome (100 average: +8 / 100 a point here)
			outcome.coe, outcome.gift = 1.10, 8
			T.near(value("magic", 1, true), 1.1 * 1.10 * 0.8 * 1.1, 1e-12, "raid: magic x coe")
			T.near(value("magic", 3, false), 1.1 * 1.10 * 0.95, 1e-12, "raid: a magic proc on the ranged table, x coe, no gift")
			T.near(value("physical", 2, true), (1.1 * 0.6 + 8 / 100) * 0.9 * 1.2, 1e-12, "raid: physical, the gift after the armor")
			T.near(value("physical", 0, false), (1.1 * 0.6 + 8 / 100) * 0.9, 1e-12, "raid: physical, no DefenseType, cannot crit")
			outcome.coe, outcome.gift = 1, 0
			-- a proc without its school or crit, a DefenseType outside 0..3, or no ctx.procOutcome: errors
			ring.procs = { { avg = 100, hits = "melee", equip = true, linked = false, defense = 0, crit = true } }
			local ok, err = pcall(Sc.ProcValue, ring, "armor", W, hits, o)
			T.eq(ok, false); T.truthy(tostring(err):find("without its school or crit", 1, true), tostring(err))
			ring.procs = { { avg = 100, hits = "melee", equip = true, school = "magic", linked = false, defense = 0 } }
			T.eq(pcall(Sc.ProcValue, ring, "armor", W, hits, o), false, "no crit flag")
			ring.procs = { { avg = 100, hits = "melee", equip = true, school = "magic", linked = false, defense = 4, crit = true } }
			ok, err = pcall(Sc.ProcValue, ring, "armor", W, hits, o)
			T.eq(ok, false); T.truthy(tostring(err):find("a proc of DefenseType 4", 1, true), tostring(err))
			ring.procs = { proc(100, "melee", true) }
			ok, err = pcall(Sc.ProcValue, ring, "armor", W, hits, {})
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.procOutcome", 1, true), tostring(err))
		end },
		-- A proc's damage over time (raid-mode design 17.3; U2 = (a), as wowsims prices it): per landed application it deals the
		-- ticks before the next landed application ends it, E[n] = sum over k = 1..N of e^(-lambda k T) (Score.DotTicks; the
		-- landed applications a Poisson stream, approximation DA1), lambda its procs a second x its application's chance; so a
		-- faster rate loses ticks. A made-up Rot-like dot: 24 a tick every 1 s, 7 ticks, magic (the env-free outcome tables
		-- below: the application lands 0.8, the magic tick crit factor 1.05)
		{ "dot proc: E[n] = sum e^(-lambda k T); a faster rate loses ticks", function()
			local dot = { tick = 24, period = 1000, ticks = 7, canCrit = true }
			local function oracle(perMinute, land)
				local l = perMinute / 60 * land
				local n = 0
				for k = 1, 7 do n = n + math.exp(-l * k) end
				return n
			end
			T.near(Sc.DotTicks(dot, 1.45, 1, 0), oracle(1.45, 1), 1e-12, "1.45 a minute, every application lands")
			T.near(Sc.DotTicks(dot, 0, 1, 0), 7, 1e-12, "no other application: every tick")
			T.near(Sc.DotTicks(dot, 6, 0.8, 0), oracle(6, 0.8), 1e-12, "6 a minute at 0.8")
			T.truthy(Sc.DotTicks(dot, 30, 1, 0) < Sc.DotTicks(dot, 6, 1, 0) - 0.5, "a faster rate loses ticks")
			T.near(Sc.DotTicks({ tick = 30, period = 2000, ticks = 5 }, 12, 0.5, 0), (function()
				local n = 0
				for k = 1, 5 do n = n + math.exp(-0.1 * k * 2) end
				return n
			end)(), 1e-12, "the period: k x 2 s")
			-- the value: (rate / 60) x land x E[n] x the tick's damage x its crit factor, at W.EXTRA_DPS
			local A = { hit = 0.8, critMult = 1.05, land = 0.8, tickCrit = 1.05 }
			local outcome = { [0] = { physical = A, magic = A }, [1] = A, [2] = A, [3] = A, phys = 0.6, own = 1, coe = 1, gift = 0 }
			local hits = hitsOf({ 0.4, 0.05, 2.5 }, { 0, 1.8 }, { 0, 0, 0, 0 })
			local harpoon = weaponOf("INVTYPE_2HWEAPON", 274963, 2.5, { DPS = 30 })
			harpoon.procs = { { hits = "weapon", school = "magic", linked = true, defense = 1, crit = true, ppm = 1.45, source = "EV-0122", dot = dot } }
			local perMinute = Sc.ProcRate(harpoon, "2h", harpoon.procs[1], hits)
			T.near(perMinute, 1.45 * 2.5 * 0.45, 1e-12, "1.45 a minute at its 2.5 s on its hand's landed hits")
			T.near(Sc.ProcValue(harpoon, "2h", W, hits, { procOutcome = outcome }),
				perMinute / 60 * 0.8 * oracle(perMinute, 0.8) * 24 * 1.05 * W.EXTRA_DPS, 1e-12, "the dot's value")
		end },
		-- The application rolls the proc's table once, without crit (shared_utils.go:730, 771-776): land; a magic tick crits at
		-- the spell crit x1.5, a physical tick at the suppressed physical crit (Model.ProcOutcomes tickCrit; only with
		-- PERIODIC_CAN_CRIT, canCrit), a physical tick takes no armor (spell_resistances.go:25-28) and Gift of Arthas' +8 in
		-- raid (after own, before the crit), a magic tick Curse of the Elements; made-up outcomes, each number its own
		{ "dot proc: the application rolls the table once, no crit; magic ticks x1.5 spell crit; physical ticks at the suppressed physical crit, no armor, +8 Gift in raid", function()
			local hits = hitsOf({ 0.4, 0.05, 2.5 }, { 0, 1.8 }, { 0, 0, 0, 0 })
			-- (tickCrit apart from critMult, so the ticks are seen to read their own: Model.ProcOutcomes gives the two alike)
			local MAG = { hit = 0.83, critMult = 1.07, land = 0.83, tickCrit = 1.06 }
			local MEL = { hit = 0.9, critMult = 1.25, land = 0.9, tickCrit = 1.2 }
			local RNG = { hit = 0.95, critMult = 1.25, land = 0.95, tickCrit = 1.2 }
			local outcome = { [0] = { physical = MEL, magic = MAG }, [1] = MAG, [2] = MEL, [3] = RNG, phys = 0.6, own = 1.1, coe = 1, gift = 0 }
			local o = { procOutcome = outcome }
			local axe = weaponOf("INVTYPE_WEAPON", 17730, 2.5, { DPS = 30 })
			local function value(school, defense, canCrit)
				local dot = { tick = 30, period = 1000, ticks = 7, canCrit = canCrit }
				axe.procs = { { hits = "weapon", school = school, linked = true, defense = defense, crit = true, ppm = 1.2, source = "EV-0003", dot = dot } }
				local perMinute = Sc.ProcRate(axe, "mh", axe.procs[1], hits)
				local land = (defense == 1 or (defense == 0 and school == "magic")) and 0.83 or defense == 3 and 0.95 or 0.9
				return Sc.ProcValue(axe, "mh", W, hits, o) / (perMinute / 60 * land * Sc.DotTicks(dot, perMinute, land, 0) * W.EXTRA_DPS)
			end
			T.near(value("physical", 2, true), 30 * 1.1 * 1.2, 1e-12, "a bleed: no armor, the physical crit")
			T.near(value("physical", 2, false), 30 * 1.1, 1e-12, "no PERIODIC_CAN_CRIT: no crit factor")
			T.near(value("magic", 1, true), 30 * 1.1 * 1.06, 1e-12, "a poison: the spell crit x1.5")
			T.near(value("magic", 3, true), 30 * 1.1 * 1.2, 1e-12, "a magic school on the ranged table: the physical crit (levelling: coe 1)")
			T.near(value("physical", 0, true), 30 * 1.1 * 1.2, 1e-12, "no DefenseType, physical: the melee table")
			T.near(value("magic", 0, true), 30 * 1.1 * 1.06, 1e-12, "no DefenseType, magic: the spell table")
			-- the application's chance is land, no crit factor on it: a table whose crit factor moves leaves E[n] and land alone
			local before = value("physical", 2, false)
			MEL.critMult = 1.5
			T.near(value("physical", 2, false), before, 1e-12, "the application takes no crit")
			MEL.critMult = 1.25
			-- raid: Gift of Arthas +8 a physical tick after own and before the crit; Curse of the Elements x1.10 a magic tick;
			-- each by the tick's school, whatever its table (raid-mode design 22.1: Xorothian Fire 18755, Fire on the ranged
			-- table, takes the curse)
			outcome.coe, outcome.gift = 1.10, 8
			T.near(value("physical", 2, true), (30 * 1.1 + 8) * 1.2, 1e-12, "raid: a bleed's tick + 8 Gift, no armor")
			T.near(value("magic", 1, true), 30 * 1.1 * 1.10 * 1.06, 1e-12, "raid: a poison's tick x coe, no gift")
			T.near(value("magic", 3, true), 30 * 1.1 * 1.10 * 1.2, 1e-12, "raid: a magic school on the ranged table: x coe by its school, no gift")
			T.near(value("magic", 2, true), 30 * 1.1 * 1.10 * 1.2, 1e-12, "raid: a magic school on the melee table: x coe, no gift")
			T.near(value("physical", 3, true), (30 * 1.1 + 8) * 1.2, 1e-12, "raid: a physical school on the ranged table: + 8 Gift by its school, no coe")
			T.near(value("physical", 1, true), (30 * 1.1 + 8) * 1.06, 1e-12, "raid: a physical school on the magic table: + 8 Gift, no coe")
			outcome.coe, outcome.gift = 1, 0
		end },
		-- A spell with a direct damage and a damage over time (Demonshear 13348's Shadow Bolt 17483: 150 Shadow and 34 every 2 s
		-- for 6 s, Game/ProcData.lua): its direct part rolls hit and crit, the dot lands with its hit (shared_utils.go:810-816):
		-- the two priced together at one rate; a proc with neither is an error
		{ "dot proc: a direct part and a dot priced together", function()
			local hits = hitsOf({ 0.4, 0.05, 2.5 }, { 0, 1.8 }, { 0, 0, 0, 0 })
			local MAG = { hit = 0.83, critMult = 1.06, land = 0.83, tickCrit = 1.06 }
			local outcome = { [0] = { physical = MAG, magic = MAG }, [1] = MAG, [2] = MAG, [3] = MAG, phys = 0.6, own = 1, coe = 1, gift = 0 }
			local o = { procOutcome = outcome }
			local shear = weaponOf("INVTYPE_2HWEAPON", 13348, 3.8, { DPS = 40 })
			local dot = { tick = 34, period = 2000, ticks = 3, canCrit = true }
			shear.procs = { { avg = 150, hits = "weapon", school = "magic", linked = true, defense = 1, crit = true, ppm = 1.1, source = "EV-0003", dot = dot } }
			local perMinute = Sc.ProcRate(shear, "2h", shear.procs[1], hits)
			local direct = 150 * 0.83 * 1.06
			local over = 0.83 * Sc.DotTicks(dot, perMinute, 0.83, 0) * 34 * 1.06
			T.near(Sc.ProcValue(shear, "2h", W, hits, o), (direct + over) * perMinute / 60 * W.EXTRA_DPS, 1e-12, "direct and dot")
			shear.procs[1].dot = nil
			T.near(Sc.ProcValue(shear, "2h", W, hits, o), direct * perMinute / 60 * W.EXTRA_DPS, 1e-12, "the direct part alone")
			shear.procs[1].avg, shear.procs[1].dot = nil, nil
			local ok, err = pcall(Sc.ProcValue, shear, "2h", W, hits, o)
			T.eq(ok, false); T.truthy(tostring(err):find("neither a direct damage nor a damage over time", 1, true), tostring(err))
		end },
		-- Versus bonuses of a creature type (raid-mode design 25.2; wowsims sim/core/spell_result.go:442-445 CalcDamage, 464-467
		-- CalcPeriodicDamage: the base damage x the factor against a target of its types, before the attacker's multipliers):
		-- over the mode's targets 1 + share x (factor - 1), share the targets of the bonus's types (Model.TargetShare: raid 1
		-- for the boss's dragonkin, 0 for the others; levelling 0.3 a type, the shares of several types summed, more than
		-- every target an error), on the direct part and each tick, before own and Gift of Arthas. Game/ProcData.lua's three
		-- rows (tools/gen_proc_data.py from wowsims' VersusBonuses): Drakefang Butcher 12463's Rend 14118 (23 a 1 s tick for 7
		-- s, a bleed, x2 against Dragonkin), Lightcrest Hammer 276419's Smite 1299631 (105 Holy, x2 against Undead), Gloves of
		-- Holy Might 867's 1325229 (x3 against Undead); made-up outcomes, each number its own
		{ "versus: a proc's base damage, direct and periodic, x 1 + share x (factor - 1) before own and Gift of Arthas; the three rows of Game/ProcData.lua", function()
			local P = ns.ProcData
			local rendV, smiteV, holyV = P[12463][1].versus, P[276419][1].versus, P[867][1].versus
			T.eq(rendV.factor, 2); T.eq(#rendV.types, 1); T.eq(rendV.types[1], "DRAGONKIN")
			T.eq(smiteV.factor, 2); T.eq(#smiteV.types, 1); T.eq(smiteV.types[1], "UNDEAD")
			T.eq(holyV.factor, 3); T.eq(#holyV.types, 1); T.eq(holyV.types[1], "UNDEAD")
			local n = 0
			for _, list in pairs(P) do for _, e in ipairs(list) do if e.versus then n = n + 1 end end end
			T.eq(n, 3, "three entries")
			T.eq(Sc.VersusFactor({ versus = rendV }, "raid"), 2, "raid: the boss a dragonkin")
			T.near(Sc.VersusFactor({ versus = rendV }, "level"), 1.3, 1e-12, "levelling: 30% of the targets")
			T.eq(Sc.VersusFactor({ versus = smiteV }, "raid"), 1, "raid: no undead")
			T.near(Sc.VersusFactor({ versus = holyV }, "level"), 1.6, 1e-12, "x3 at 30%: 1 + 0.3 x 2")
			T.eq(Sc.VersusFactor({}, "raid"), 1, "no bonus")
			T.near(Sc.VersusFactor({ versus = { factor = 2, types = { "BEAST", "UNDEAD", "DEMON" } } }, "level"), 1.9, 1e-12, "three types: the shares summed")
			local ok, err = pcall(Sc.VersusFactor, { versus = { factor = 2, types = { "BEAST", "UNDEAD", "DEMON", "GIANT" } } }, "level")
			T.eq(ok, false); T.truthy(tostring(err):find("more than every target", 1, true), tostring(err))
			T.eq(pcall(Sc.VersusFactor, { versus = rendV }, nil), false, "no mode")
			local hits = hitsOf({ 0.4, 0.05, 3.4 }, { 0, 1.8 }, { 0, 0, 0, 0 })
			local MEL = { hit = 0.9, critMult = 1.25, land = 0.9, tickCrit = 1.2 }
			local MAG = { hit = 0.83, critMult = 1.06, land = 0.83, tickCrit = 1.06 }
			local outcome = { [0] = { physical = MEL, magic = MAG }, [1] = MAG, [2] = MEL, [3] = MEL, phys = 0.6, own = 1.1, coe = 1.10, gift = 8, mode = "raid" }
			local o = { procOutcome = outcome }
			local axe = weaponOf("INVTYPE_2HWEAPON", 12463, 3.4, { DPS = 40 })
			local dot = P[12463][1].dot
			T.eq(dot.tick, 23); T.eq(dot.ticks, 7)
			axe.procs = { { hits = "weapon", school = "physical", linked = true, defense = 2, crit = true, ppm = 1.5, source = "EV-0003", dot = dot, versus = rendV } }
			local perMinute = Sc.ProcRate(axe, "2h", axe.procs[1], hits)
			local per = perMinute / 60 * 0.9 * Sc.DotTicks(dot, perMinute, 0.9, 0) * W.EXTRA_DPS
			T.near(Sc.ProcValue(axe, "2h", W, hits, o) / per, (23 * 2 * 1.1 + 8) * 1.2, 1e-12, "raid: the tick x2 before own, the gift after")
			outcome.mode, outcome.coe, outcome.gift = "level", 1, 0
			T.near(Sc.ProcValue(axe, "2h", W, hits, o) / per, 23 * 1.3 * 1.1 * 1.2, 1e-12, "levelling: x1.3")
			local hammer = weaponOf("INVTYPE_WEAPON", 276419, 3.4, { DPS = 40 })
			hammer.procs = { { avg = 105, hits = "weapon", school = "magic", linked = true, defense = 1, crit = true, ppm = 3.6, source = "EV-0003", versus = smiteV } }
			local pm = Sc.ProcRate(hammer, "mh", hammer.procs[1], hits)
			local direct = pm / 60 * W.EXTRA_DPS * 0.83 * 1.06
			T.near(Sc.ProcValue(hammer, "mh", W, hits, o) / direct, 105 * 1.3 * 1.1, 1e-12, "levelling: the direct part x1.3")
			outcome.mode, outcome.coe, outcome.gift = "raid", 1.10, 8
			T.near(Sc.ProcValue(hammer, "mh", W, hits, o) / direct, 105 * 1.1 * 1.10, 1e-12, "raid: no undead, x1")
			-- a physical direct part in raid (made up: 100, x2 against Dragonkin): x2 before own and the armor, the gift after
			local cleaver = weaponOf("INVTYPE_WEAPON", 990700, 3.4, { DPS = 40 })
			cleaver.procs = { { avg = 100, hits = "weapon", school = "physical", linked = true, defense = 2, crit = true, ppm = 2, source = "EV-0003", versus = rendV } }
			local pc = Sc.ProcRate(cleaver, "mh", cleaver.procs[1], hits)
			T.near(Sc.ProcValue(cleaver, "mh", W, hits, o) / (pc / 60 * W.EXTRA_DPS * 0.9 * 1.25), 100 * 2 * 1.1 * 0.6 + 8, 1e-12,
				"raid: a physical direct part x2 before own and the armor, the gift after")
		end },
		-- A proc on every hit of its mask (raid-mode design 25.3; wowsims ProcChanceAlways, StatedChance 1,
		-- sim/core/spelldata/resolve_proc.go:187-199): Game/ProcData.lua's always on a linked equip aura is a chance of 100 a
		-- hit (Score.ProcRateSource "always", after MEASURED_PPM and an override row), so its procs a minute are 60 x its
		-- mask's landed hits a second: mask 64 the Auto Shots (Hurricane 2824), 20 the melee swings and abilities (Fiery Plate
		-- Gauntlets 12631, Blazefury Medallion 17111); its internal cooldown a dead time, r / (1 + r x icd); without always a
		-- column of 100 is no rate (Frostburn 276631, which no wowsims registration names). Score.DotTicks past a cooldown d:
		-- no landed application within it, E[n] = the sum of 1 for T k <= d, else e^(-r land (T k - d)), r = r_eff / (1 - r_eff
		-- d) the rate without the cooldown; a cooldown as long as the dot deals every tick (228666's 45 s against 5 ticks of 2
		-- s); Score.ProcValue passes an equip aura's cooldown and 0 for a chance on hit. Made-up hits, each number its own
		{ "always: an equip aura wowsims rolls on every hit of its mask, chance 100 a hit, the cooldown its dead time; the dot's ticks past the cooldown", function()
			local P = ns.ProcData
			T.eq(P[2824][1].always, true); T.eq(P[12631][1].always, true); T.eq(P[17111][1].always, true)
			T.eq(P[276631][1].always, nil, "no wowsims registration: no rate")
			local hits = hitsOf({ 0.4, 0.05, 2.5 }, { 0.3, 1.8 }, { 0.35, 0.2, 2.8, 0.06 })
			local function aura(mask, icd, extra)
				local p = { avg = 8, equip = true, linked = true, school = "magic", defense = 3, crit = true, mask = mask, chance = 100,
					ppm = 0, icd = icd, always = true }
				for k, v in pairs(extra or {}) do p[k] = v end
				return p
			end
			local bow = weaponOf("INVTYPE_RANGED", 990800, 2.8, { DPS = 40 })
			local rate, kind = Sc.ProcRateSource(bow, aura(64, 0))
			T.eq(rate, 100); T.eq(kind, "always")
			T.near(Sc.ProcRate(bow, "ranged", aura(64, 0), hits), 60 * 0.35, 1e-12, "mask 64: every Auto Shot")
			local gloves = item("INVTYPE_HAND")
			local raw = 0.4 + 0.3 + 0.05
			T.near(Sc.ProcRate(gloves, "armor", aura(20, 0), hits), 60 * raw, 1e-12, "mask 20: the melee swings and abilities")
			T.near(Sc.ProcRate(gloves, "armor", aura(20, 1000), hits), 60 * raw / (1 + raw * 1), 1e-12, "a 1 s cooldown: r / (1 + r x icd)")
			-- an aura of the main hand alone (Game/ProcData.lua mainHand, ProcTypeMask_1 0x20; raid-mode design 26.2): the off
			-- hand's white swings out; Iceblade Hacker 13952, Warblade of Caer Darrow 13982 and Dreadfrost Saber 274603 so
			local blade = weaponOf("INVTYPE_WEAPONMAINHAND", 990801, 2.5, { DPS = 30 })
			T.near(Sc.ProcRate(blade, "mh", aura(20, 0, { mainHand = true }), hits), 60 * (0.4 + 0.05), 1e-12,
				"mask 20 of the main hand: its swings and abilities")
			for _, id in ipairs({ 13952, 13982, 274603 }) do
				local e
				for _, x in ipairs(P[id]) do if x.kind == "equip" then e = x end end
				T.eq(e.mainHand, true, id .. " mainHand"); T.eq(e.always, true, id .. " always"); T.eq(e.mask, 20, id .. " mask")
			end
			T.eq(P[17111][1].mainHand, nil, "Blazefury Medallion: both hands")
			T.eq(Sc.ProcRate(gloves, "armor", aura(20, 0, { always = false }), hits), 0, "a column of 100 without always: no rate")
			T.eq(select(2, Sc.ProcRateSource(gloves, aura(20, 0, { always = false }))), nil)
			local undo = measuredFor(1.5, gloves)
			T.eq(select(2, Sc.ProcRateSource(gloves, aura(20, 0))), "measured", "a measured rate first")
			undo()
			-- the dot past the cooldown
			local dot = { tick = 51, period = 2000, ticks = 5, canCrit = true }
			T.eq(Sc.DotTicks(dot, 1.2, 1, 45000), 5, "a 45 s cooldown against a 10 s dot: every tick")
			local pm, land = 6, 0.8
			local rEff = pm / 60
			local r = rEff / (1 - rEff * 3)
			local want = 1
			for k = 2, 5 do want = want + math.exp(-r * land * (2 * k - 3)) end
			T.near(Sc.DotTicks(dot, pm, land, 3000), want, 1e-12, "a 3 s cooldown: the first tick whole, the rest at the rate without it")
			local plain = 0
			for k = 1, 5 do plain = plain + math.exp(-rEff * land * 2 * k) end
			T.near(Sc.DotTicks(dot, pm, land, 0), plain, 1e-12, "no cooldown: e^(-lambda k T)")
			T.eq(pcall(Sc.DotTicks, dot, pm, land, nil), false, "no cooldown given")
			T.eq(pcall(Sc.DotTicks, dot, pm, land, -1), false, "a cooldown below 0")
			T.eq(pcall(Sc.DotTicks, dot, 20, land, 3000), false, "a rate past the cooldown's: 20 a minute, 3 s")
			local ring = item("INVTYPE_FINGER")
			ring.procs = { aura(20, 3000, { dot = dot, defense = 1 }) }
			ring.procs[1].avg = nil -- a damage over time alone
			local per = Sc.ProcRate(ring, "armor", ring.procs[1], hits)
			T.near(Sc.ProcValue(ring, "armor", W, hits, { procOutcome = WHOLE_OUTCOME }),
				per / 60 * Sc.DotTicks(dot, per, 1, 3000) * 51 * W.EXTRA_DPS, 1e-12, "the equip aura's cooldown in the ticks")
			T.truthy(math.abs(Sc.DotTicks(dot, per, 1, 3000) - Sc.DotTicks(dot, per, 1, 0)) > 0.01, "the cooldown moves the ticks")
		end },
		-- Game/ProcData.lua as tools/gen_proc_data.py writes it from build 70888: Heartseeking Crossbow 13040 (equip 29626 ->
		-- 29640: mask 320, chance 100, 13 to 19 Shadow, the ranged table), the Highborne Research Tablet 260205 (1318159 ->
		-- 1265634: mask 65876, 69 to 81 Arcane, the magic table), Sul'thraze 223526 (a chance on hit, 11658, no SpellCategories
		-- row: DefenseType 0), 273003 (Sear 1291570, Attributes_2 0x20000000: it cannot crit), Keeper's Sting 29655 of
		-- Verdant Keeper's Aim 17753 (a chance on hit: no rate columns)
		{ "Game/ProcData.lua: Heartseeking, the Tablet, a DefenseType 0 spell, a spell that cannot crit, a chance on hit", function()
			local P = ns.ProcData
			local function one(id) T.eq(#P[id], 1, "one entry of " .. id); return P[id][1] end
			local h = one(13040)
			for k, v in pairs({ trigger = 29626, kind = "equip", mask = 320, chance = 100, ppm = 2.7, icd = 0, spell = 29640, avg = 16,
				min = 13, max = 19, school = 32, defense = 3, crit = true, source = "EV-0119" }) do T.eq(h[k], v, "13040 " .. k) end
			local t = one(260205)
			for k, v in pairs({ trigger = 1318159, kind = "equip", mask = 65876, chance = 100, ppm = 2.6, spell = 1265634, avg = 75,
				min = 69, max = 81, school = 64, defense = 1, crit = true, source = "EV-0021" }) do T.eq(t[k], v, "260205 " .. k) end
			T.eq(one(223526).defense, 0, "no SpellCategories row"); T.eq(one(223526).kind, "hit")
			T.eq(one(273003).crit, false, "cannot crit")
			local k = one(17753)
			T.eq(k.kind, "hit"); T.eq(k.spell, 29655); T.eq(k.avg, 28); T.eq(k.school, 8); T.eq(k.defense, 3)
			T.eq(k.mask, nil); T.eq(k.chance, nil); T.eq(k.icd, nil)
			T.eq(k.ppm, 3.5); T.eq(k.source, "EV-0003", "wowsims' WeaponProcs row (17753, 29655)")
			-- a carried-over rate of wowsims' WeaponProcs (Hammer of the Northern Wind 810, 13439: 3.5, vanilla-carryover)
			local hammer = one(810)
			T.eq(hammer.kind, "hit"); T.eq(hammer.ppm, 3.5); T.eq(hammer.source, "vanilla-carryover")
			-- wowsims' measured rows (EV-<n>) agree with Score.MEASURED_PPM, the same measurements
			local evRows = 0
			for id, entries in pairs(P) do
				for _, e in ipairs(entries) do
					if e.source and e.source:match("^EV%-") and Sc.MEASURED_PPM[id] then
						evRows = evRows + 1
						T.eq(e.ppm, Sc.MEASURED_PPM[id], id .. ": wowsims' " .. e.source .. " row and MEASURED_PPM")
					end
				end
			end
			-- 17 direct procs and the 13 damage over time procs a measured item has (6472, 6904, 9453, 12463, 12582, 12969, 13183,
			-- 13361, 13983, 17730, 274963, 279480, 279852; raid-mode design 17.2)
			T.eq(evRows, 30, "the measured rows with a ProcData entry")
			-- Rot-Covered Harpoon 274963: Rot 1295744, 24 Nature every 1 s for 7 s, the magic table, its ticks crit, no direct
			-- damage (Forever DB2 build 70888; raid-mode design 17.2)
			local rot = one(274963)
			for k, v in pairs({ kind = "hit", spell = 1295744, avg = 0, min = 0, max = 0, school = 8, defense = 1, ppm = 1.45, source = "EV-0122" }) do
				T.eq(rot[k], v, "274963 " .. k)
			end
			for k, v in pairs({ tick = 24, period = 1000, ticks = 7, canCrit = true }) do T.eq(rot.dot[k], v, "274963 dot " .. k) end
			-- Demonshear 13348: Shadow Bolt 17483, a direct 150 and 34 every 2 s for 6 s
			local shear = one(13348)
			T.eq(shear.avg, 150); T.eq(shear.dot.tick, 34); T.eq(shear.dot.period, 2000); T.eq(shear.dot.ticks, 3)
			-- Rot 1231261 of 240842's equip aura: its ticks cannot crit
			T.eq(one(240842).dot.canCrit, false)
			-- a direct proc has no dot
			T.eq(one(13040).dot, nil)
		end },
		-- Expertise in two slopes (Score.SetValue): W.EXPERTISE up to the mob's dodge (ctx.expertiseCap), W.EXPERTISE_PARRY
		-- from there up to the tanking pet's parry (ctx.parryCap, Model.PetParry: 14% at +3), nothing past it; with the parry
		-- cap at the dodge (the pet behind, or +0..+2) one slope
		{ "expertise: a tanking pet at +3 gains past the dodge cap up to 14%, at W.EXPERTISE_PARRY", function()
			local We = fullW({ EXPERTISE = 10, EXPERTISE_PARRY = 4 })
			local function value(e, parryCap)
				local c = ctx({}, nil, { expertiseCap = 6.5, parryCap = parryCap })
				return Sc.SetValue({ [S.HEAD] = piece("INVTYPE_HEAD", 1, nil, { EXPERTISE = e }) }, We, c)
			end
			T.near(value(5, 14), 50, 1e-12, "below the dodge")
			T.near(value(8, 14), 65 + 1.5 * 4, 1e-12, "1.5% past the dodge at the parry's slope")
			T.near(value(20, 14), 65 + 7.5 * 4, 1e-12, "nothing past the parry")
			T.near(value(8, 6.5), 65, 1e-12, "the parry cap at the dodge: one slope")
			local c = ctx({}, nil, {}); c.parryCap = nil
			local ok, err = pcall(Sc.SetValue, {}, We, c)
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.parryCap", 1, true), tostring(err))
		end },
		-- Expertise lowers the mob's dodge up to the dodge itself (Model.MobAvoid), where every model consumer clamps it:
		-- Score.SetValue prices the set's expertise, items' and set bonuses' (a Use buff's on top), as W.EXPERTISE x
		-- min(e, ctx.expertiseCap), never an item's alone
		{ "expertise: priced on the whole set up to ctx.expertiseCap; an item crossing it gets the part below, a worn one past it is priced when it comes off", function()
			local We = fullW({ EXPERTISE = 10, AGI = 2 })
			local function gear(loc, id, e, extra)
				local st = { EXPERTISE = e }
				for k, v in pairs(extra or {}) do st[k] = v end
				return piece(loc, id, nil, st)
			end
			local helm3, helm7, plainHelm = gear("INVTYPE_HEAD", 1, 3), gear("INVTYPE_HEAD", 2, 7), gear("INVTYPE_HEAD", 3, nil, { AGI = 1 })
			T.eq(Sc.ItemValue(helm7, "armor", We), 0, "an item's expertise is no item value of its own")
			-- below the cap 3% -> 7%: only the 2% up to the 5% cap
			local worn = { [S.HEAD] = helm3 }
			local c = ctx(worn)
			T.near(Sc.SetValue(worn, We, c), 10 * 3, 1e-12)
			local r = Sc.Evaluate(helm7, We, c)
			T.near(r.delta, 10 * 2, 1e-12, "3 -> 7 at a 5% cap: 2% of it")
			T.near(Sc.Evaluate(helm3, We, c).delta, 0, 1e-12, "the worn item: delta 0")
			-- past the cap: 9% worn (a 7% helm, a 2% belt); a plain helm (1 Agility) or the 3% helm for the 7% one
			local wornPast = { [S.HEAD] = helm7, [S.WAIST] = gear("INVTYPE_WAIST", 4, 2) }
			local cp = ctx(wornPast)
			T.near(Sc.SetValue(wornPast, We, cp), 10 * 5, 1e-12, "9% at a 5% cap")
			T.near(Sc.Evaluate(plainHelm, We, cp).delta, 2 * 1 + 10 * (2 - 5), 1e-12, "9 -> 2: 3% below the cap lost")
			T.near(Sc.Evaluate(helm3, We, cp).delta, 10 * (5 - 5), 1e-12, "9 -> 5: still at the cap, nothing lost")
			T.near(Sc.Evaluate(helm7, We, cp).delta, 0, 1e-12, "the worn item: delta 0")
			-- another cap (a mob 3 levels up: Model.MobAvoid(3) = 6.5)
			T.near(Sc.Evaluate(plainHelm, We, ctx(wornPast, nil, { expertiseCap = ns.Model.MobAvoid(3) })).delta, 2 + 10 * (2 - 6.5), 1e-12,
				"9 -> 2 at a 6.5% cap")
			-- below 0 (a negative expertise stat): no floor, the model's dodge grows a point for every point
			T.near(Sc.SetValue({ [S.HEAD] = gear("INVTYPE_HEAD", 5, -2) }, We, ctx({})), 10 * -2, 1e-12, "-2%")
			-- a set bonus' expertise joins the items' under the cap: Grovekeeper Rage 2113, 4 pieces 1301076 EXPERTISE 1.2
			local function gk(loc, id, e) return piece(loc, id, 2113, { EXPERTISE = e }) end
			local three = { [S.HEAD] = gk("INVTYPE_HEAD", 280986, 4), [S.CHEST] = gk("INVTYPE_CHEST", 280988), [S.FEET] = gk("INVTYPE_FEET", 280990) }
			local cg = ctx(three, nil, { sets = ns.SetData })
			T.eq(ns.SetData[2113][3].stats.EXPERTISE, 1.2)
			T.near(Sc.Evaluate(gk("INVTYPE_HAND", 280991), We, cg).delta, 10 * (5 - 4), 1e-12, "4% + the bonus' 1.2%: 1% up to the cap")
			-- a Use buff's expertise on top of the set's, through the cap, over its uptime
			local trinket = piece("INVTYPE_TRINKET", 6); trinket.use = { spell = 6, stats = { EXPERTISE = 4 }, duration = 20, cooldown = 120 }
			T.near(Sc.SetValue({ [S.HEAD] = helm3, [S.TRINKET1] = trinket }, We, c), 10 * 3 + 20 / 120 * 10 * 2, 1e-12,
				"3% + 4% for a sixth of the time: 2% of it")
			T.near(Sc.SetValue({ [S.HEAD] = helm7, [S.TRINKET1] = trinket }, We, c), 10 * 5, 1e-12, "past the cap: nothing")
			-- the cap is the model point's: a ctx without it is an error
			local bare = ctx({}); bare.expertiseCap = nil
			local ok, err = pcall(Sc.SetValue, {}, We, bare)
			T.eq(ok, false); T.truthy(tostring(err):find("without ctx.expertiseCap", 1, true), tostring(err))
		end },
		-- Dread Hunter's Chain, ItemSet 1647: Chainmail 220666, Chausses 220667, Greaves 220668 (Forever Item.csv build
		-- 70888: class 4 subclass 3, mail; the Era ItemSparse rows: AllowableClass 4, hunters; the build 70888 ItemSparse
		-- export has no row for them). Its 3-piece bonus 450403 "Lethal Shots" is aura 52 A_MOD_WEAPON_CRIT_PERCENT +2 on
		-- SpellEquippedItems 252803 (item class 2, subclass mask 327692: bows, guns, thrown, crossbows): the ranged
		-- weapon's crit, CRIT_RANGED (tools/gen_set_data.py), priced at W.CRIT_RANGED
		{ "SetData: Dread Hunter's Chain's 3-piece crit with ranged weapons is CRIT_RANGED, priced at W.CRIT_RANGED", function()
			local def = ns.SetData[1647]
			T.eq(def.name, "Dread Hunter's Chain")
			local three = {}
			for _, b in ipairs(def) do if b.n == 3 and b.stats then three[#three + 1] = b end end
			T.eq(#three, 1); T.eq(three[1].spell, 450403)
			local keys = 0
			for k, v in pairs(three[1].stats) do keys = keys + 1; T.eq(k, "CRIT_RANGED"); T.eq(v, 2) end
			T.eq(keys, 1)
			local Wc = fullW({ AP = 1, CRIT = 7, CRIT_RANGED = 5 })
			local bow = piece("INVTYPE_RANGED", 1); bow.classID, bow.subclassID = 2, 2
			local two = { [S.RANGED] = bow, [S.CHEST] = piece("INVTYPE_CHEST", 220666, 1647), [S.LEGS] = piece("INVTYPE_LEGS", 220667, 1647) }
			local all = Sc.CopySet(two); all[S.FEET] = piece("INVTYPE_FEET", 220668, 1647)
			local c = ctx(two, nil, { sets = ns.SetData })
			T.near(Sc.SetValue(two, Wc, c), 20, 1e-9, "2 pieces: 20 attack power")
			T.near(Sc.SetValue(all, Wc, c) - Sc.SetValue(two, Wc, c), 2 * 5, 1e-9, "3 pieces: 2% ranged crit")
			-- a melee weapon's own crit stays not counted: Madcap's Outfit 1829, 3-piece 468436, aura 52 +5 on SpellEquippedItems
			-- 253342 (item class 2, subclass mask 32768: daggers)
			local dagger
			for _, b in ipairs(ns.SetData[1829]) do if b.spell == 468436 then dagger = b end end
			T.eq(dagger.n, 3); T.eq(dagger.stats, nil); T.truthy(dagger.unknown, "the dagger crit: not counted")
		end },
		-- A set's ranged-only hit (RANGED_HIT: items and set bonuses) is the shots', the pet's and the hawks' hit
		-- (Model.Parts rangedGearHit): on top of the hit of every attack it meets their cap at W.RANGED_HIT, the shots' own
		-- skill hit on top of both at W.HIT_RANGED, and it never lowers the dual-wield white misses (the hunter's melee)
		{ "score: a set's RANGED_HIT meets the shots' and the pet's cap at W.RANGED_HIT, never melee's", function()
			local Wr = fullW({ HIT = 20, RANGED_HIT = 12, HIT_RANGED = 8, HIT_DW = 1, MH_DPS = 0.3, OH_DPS = 0.1 })
			local function value(set, extra) return Sc.SetValue(set, Wr, ctx({}, {}, extra)) end
			local plain = { [S.FINGER1] = item("INVTYPE_FINGER", {}) }
			local bands = { [S.FINGER1] = item("INVTYPE_FINGER", { RANGED_HIT = 2 }) }
			-- under the cap (base 0): 2% at W.RANGED_HIT
			T.near(value(bands) - value(plain), 2 * 12, 1e-9, "2% under the 5% cap")
			-- base 4%: 1% left under the cap, the other 1% adds nothing
			T.near(value(bands, { baseHit = 4 }) - value(plain, { baseHit = 4 }), 12, 1e-9, "1% left under the cap")
			T.near(value(bands, { baseHit = 6 }) - value(plain, { baseHit = 6 }), 0, 1e-12, "past the cap: nothing")
			-- the shots' skill hit on top: base 2%, the worn skill 10 over the maximum, +1% (ns.Model.SkillHit(0, 10)), which a
			-- set without a bow keeps: the bands' 1% fills 2 to 3 at W.RANGED_HIT and moves the shots' skill hit from 2-3 to
			-- 3-4, which stays under the cap at W.HIT_RANGED
			local one = { [S.FINGER1] = item("INVTYPE_FINGER", { RANGED_HIT = 1 }) }
			local ex = { baseHit = 2, skillBase = 10 }
			T.near(value(plain, ex), 20 * 2 + 8 * 1, 1e-9, "the base: every attack's 2%, the shots' 1%")
			T.near(value(one, ex), 20 * 2 + 12 * 1 + 8 * 1, 1e-9, "the bands: + W.RANGED_HIT x 1, the skill's 1% still under the cap")
			-- base 3%, the skill +1%, the bands' 1.5%: every attack 3%, the ranged-only 3 to 4.5% at W.RANGED_HIT, the skill's
			-- 4.5 to 5.5% meets the cap at 5%, so 0.5% of it at W.HIT_RANGED
			local half = { [S.FINGER1] = item("INVTYPE_FINGER", { RANGED_HIT = 1.5 }) }
			T.near(value(half, { baseHit = 3, skillBase = 10 }), 20 * 3 + 12 * 1.5 + 8 * 0.5, 1e-9, "the skill's hit on top of the ranged-only hit")
			-- a set bonus's RANGED_HIT counts as the items' (Score.SetBonuses): two pieces of a made-up set
			local sets = { [99901] = { name = "made-up", { n = 2, spell = 1, stats = { RANGED_HIT = 1 } } } }
			local two = { [S.FINGER1] = piece("INVTYPE_FINGER", 99902, 99901), [S.FINGER2] = piece("INVTYPE_FINGER", 99903, 99901) }
			T.near(value(two, { sets = sets }) - value(plain), 12, 1e-9, "the set bonus's 1%")
			T.near(value(two, { sets = sets, baseHit = 4.5 }) - value(plain, { baseHit = 4.5 }), 6, 1e-9, "the set bonus's 1% at the cap: 0.5% counts")
			-- dual wield past the cap (base 7%): the bands add nothing to the dual-wield part, which takes the hit of every
			-- attack alone
			local mh = weaponOf("INVTYPE_WEAPON", 99904, 2.6, { DPS = 26 })
			local oh = weaponOf("INVTYPE_WEAPON", 99905, 1.8, { DPS = 20 })
			local dwPlain = { [S.MAINHAND] = mh, [S.OFFHAND] = oh, [S.FINGER1] = plain[S.FINGER1] }
			local dwBands = { [S.MAINHAND] = mh, [S.OFFHAND] = oh, [S.FINGER1] = bands[S.FINGER1] }
			T.near(value(dwPlain, { baseHit = 7 }) - value(dwPlain, { baseHit = 6 }), 1, 1e-9, "the dual-wield part counts the hit of every attack")
			T.near(value(dwBands, { baseHit = 7 }) - value(dwPlain, { baseHit = 7 }), 0, 1e-12, "no dual-wield value from the bands")
			-- the stat loop leaves RANGED_HIT out (no W.RANGED_HIT x amount past the cap)
			T.eq(Sc.ItemValue(bands[S.FINGER1], "armor", Wr), 0)
		end },
	}
end
