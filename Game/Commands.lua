-- Slash commands: /hga
local _, ns = ...

local function fmt(v) return string.format("%.2f", v) end

-- The casts the starved regime buys (Model fight's items; raid-mode design 7.5, 8), by name: the build that shoots from
-- range, the Survival weave. hha: the HHA elements, the hawks with Arcane Shot (Arcane Shot alone without Summon Hawk)
local STARVED_NAMES = {
	turret = { { "hha" }, { "serpent", "Serpent Sting" }, { "aimed", "Aimed Shot" }, { "sniper", "Sniper Shot" } },
	weave = { { "raptor", "Raptor Strike" }, { "strider", "Strider Kick" }, { "bite", "Mongoose Bite" }, { "wingClip", "Wing Clip" },
		{ "trap", "Immolation Trap" }, { "serpent", "Serpent Sting" }, { "arcane", "Arcane Shot" }, { "multi", "Multi-Shot" } },
}
-- Names in a Russian list: "A", "A и B", "A, B и C" (a comma before each name after the first, «и» before the last
-- instead). Every caller passes at least one name.
local function andList(list)
	local s = list[1]
	for i = 2, #list do
		s = s .. (i < #list and ", " or " и ") .. list[i]
	end
	return s
end
local function windowsText(list)
	local t = {}
	for _, w in ipairs(list) do t[#t + 1] = string.format("%.0f–%.0f с", w[1], w[2]) end
	return table.concat(t, ", ")
end
-- a share of a cast's rate bought in part (0 < share < 1) in whole percent: below 1% "<1", above 99% ">99", so a part
-- reads neither as none nor as whole
local function partText(share)
	local pct = share * 100
	if pct < 1 then return "<1" end
	if pct > 99 then return ">99" end
	return string.format("%.0f", pct)
end

-- The mana line of /hga weights in raid mode (raid-mode design 8): the pool, the casting regen (the fight's mean with the
-- shares that come in combat) and the regen out of the five-second rule, Judgement of Wisdom's mean income (O7 = (a)); when
-- the mana runs out, the first starved stretch's start, or that it never does (Model.Fight's oom empty), or that it reaches
-- 0 and comes back at that instant with no starved stretch (a rune that fits at 0 mana, Model fight); the consumables
-- (O2 = (a)): the mana potion's time or that it does not fit at 125 s, the runes, the Frenzy Potion's windows; and what the
-- first starved stretch buys (its shares: whole, in part with its share of the rate, none)
local function manaLine(m, f)
	local cons = string.format("зелье маны %s, руна %s, Frenzy Potion %s",
		f.manaPotion and string.format("на %g с", f.manaPotion) or "не помещается на 125-й секунде — вместо него второй Frenzy Potion",
		#f.runes > 0 and ("на " .. andList((function()
			local t = {}
			for _, x in ipairs(f.runes) do t[#t + 1] = string.format("%.0f", x) end
			return t
		end)()) .. " с") or "не помещается", windowsText(f.frenzyPotion))
	local head = string.format("мана: запас %.0f, реген %.1f/с при кастах, %.1f/с без кастов 5 с, Judgement of Wisdom +%.1f/с",
		m.manaMax, f.means.regenCast, m.regenRest, f.means.jow)
	if #f.oom == 0 then return head .. "; мана не кончается; " .. cons end
	-- the first starved stretch, and the first that buys casts (a debt's buys none; a debt alone: the fight ends in it or a
	-- gain or a regen that pays the casts ends it)
	local first, starved, debtOnly
	for _, s in ipairs(f.segments) do
		if s.state.regime == "starved" then
			first = first or s
			if s.state.phase ~= "debt" then starved = starved or s.state else debtOnly = debtOnly or s.state end
		end
	end
	if not first then
		return string.format("%s; мана доходит до 0 на %.0f с и сразу возвращается (руна, зелье маны или реген баффа); %s",
			head, f.oom[1], cons)
	end
	starved = starved or debtOnly
	local kind = m.survival and "weave" or "turret"
	-- a cast group's name, after "без" (without) in the genitive: the HHA elements the hawks with Arcane Shot, Arcane Shot
	-- alone without hawks
	local hawks = f.means.hawkUptime > 0
	local function nameOf(it, without)
		if it[1] == "hha" and hawks then return without and "ястребов и Arcane" or "ястребы и Arcane" end
		return it[2] or "Arcane"
	end
	local whole, part, none = {}, {}, {}
	for _, it in ipairs(STARVED_NAMES[kind]) do
		local key = it[1]
		local casts = 0
		for _, a in ipairs(key == "hha" and { "hawk", "arcane" } or { key }) do
			local x = starved.rich.casts.acts[a]
			if x then casts = casts + x.casts end
		end
		if casts > 0 then
			local sh = starved.shares[key]
			if sh >= 1 then whole[#whole + 1] = nameOf(it)
			elseif sh > 0 then part[#part + 1] = string.format("%s (%s%% темпа)", nameOf(it), partText(sh))
			else none[#none + 1] = nameOf(it, true) end
		end
	end
	local bought = {}
	for _, x in ipairs(whole) do bought[#bought + 1] = x end
	for _, x in ipairs(part) do bought[#bought + 1] = x end
	local starvedText = #bought > 0 and ("только " .. andList(bought)) or "ничего, только автоатаки и пет"
	if #none > 0 then starvedText = starvedText .. ", без " .. andList(none) end
	return string.format("%s; мана кончается на %.0f с; %s; без маны — %s", head, first.t0, cons, starvedText)
end

local PART_NAMES = {
	{ "auto", "Auto Shot" }, { "aimed", "Aimed" }, { "multi", "Multi" }, { "arcane", "Arcane" }, { "serpent", "Serpent" },
	{ "sniper", "Sniper" }, { "dive", "пике" }, { "hawks", "ястребы" }, { "pet", "пет" }, { "melee", "мили" },
	{ "trap", "Immolation Trap" },
}

-- The weights' unit for /hga weights, by Model.Weights' name of it: 1 RAP; 1 melee attack power where RAP adds no
-- damage; 1 DPS where neither does. dps: the DPS one unit adds.
local UNIT_TEXT = {
	RAP = function(dps) return string.format("1 = 1 RAP, 1 RAP ~ %.3f DPS", dps) end,
	MAP = function(dps) return string.format("1 = 1 AP ближнего боя, 1 AP ближнего боя ~ %.3f DPS; RAP сейчас урона не даёт", dps) end,
	DPS = function() return "1 = 1 DPS; ни RAP, ни AP ближнего боя сейчас урона не дают" end,
}

local function printWeights()
	local st = ns.Advisor.State()
	if not st then ns.Print(ns.Advisor.NotReadyText()); return end
	-- the model point the weights are computed at (A.State: the live reading with the worn ranged skill's effect)
	local m = st.model
	local pts = st.snap.points
	-- the mode and the target, which follow the level (Player.Snapshot: below 60 a mob of the hunter's own level, at 60 the
	-- raid boss +3), and the hit cap, which follows the target (Advisor A.State ctx.hitCap, Model.HitCap); raid-mode design 8
	-- and 14.5. Raid: the boss's type (Model.TargetShare), its armor with the preset's debuffs (Model.BossArmor) and, with
	-- worn armor penetration, the armor the hunter's own attacks face (the pet and the hawks have none of it: Model physOf),
	-- the fight of 180 +- 5 s with the cooldowns from 5 s (Model.Fight: CONST.raid fight, fightVariation, cooldownsFrom), the
	-- pet behind the boss (Model.PetTanks); levelling: the cooldowns at their averages, Serpent Sting's 80%
	-- (CONST.serpentUptime), the pet tanking
	if m.mode == "raid" then
		local penText = m.armorPen > 0
			and string.format(" (твоим атакам с пробиванием брони %d — %d)", m.armorPen, ns.Model.BossArmor(m.armorPen)) or ""
		local r = ns.Model.CONST.raid
		ns.Print(string.format("режим: рейд (ур. 60) — босс +3 (дракон), броня %d%s, кап меткости %.1f%%, бой %d ± %d с, кулдауны с %d-й секунды, пет сзади",
			ns.Model.BossArmor(0), penText, st.ctx.hitCap, r.fight, r.fightVariation, r.cooldownsFrom))
		-- the fight (Model.Fight, raid-mode design 8): Serpent Sting's uptime and the hawks' (its weighted means), Rapid
		-- Fire's and Bestial Wrath's windows
		local f = ns.Model.Fight(m)
		local hawkText = f.means.hawkUptime > 0 and string.format("ястребы %.0f%%", f.means.hawkUptime * 100) or "ястребов нет"
		-- Bestial Wrath's windows; one alone with the talent and the pet out: the second, ready at 125 s, waited for mana
		-- that never came before 185 s (Model fight)
		local wrathText = f.bestialWrath[1] and windowsText(f.bestialWrath) or "нет (нет таланта или пета)"
		if #f.bestialWrath == 1 then wrathText = wrathText .. "; второго не будет — нет маны" end
		ns.Print(string.format("Serpent Sting висит %.0f%% боя, %s, Rapid Fire %s, Bestial Wrath %s",
			f.means.serpentUptime * 100, hawkText, windowsText(f.rapidFire), wrathText))
		-- the mana (raid-mode design 7, 8)
		ns.Print(manaLine(m, f))
	else
		ns.Print(string.format("режим: прокачка (ур. %d) — цель твоего уровня, кап меткости %.1f%%, кулдауны в среднем, Serpent Sting %d%%, пет держит цель",
			m.level, st.ctx.hitCap, math.floor(ns.Model.CONST.serpentUptime * 100 + 0.5)))
	end
	-- which build the weights are for and who gets the damage (the stats that feed them); Model.Parts gives every part of
	-- PART_NAMES, 0 for one that deals none, and m.tal is Player.ReadTalents' ranks, every talent a key
	local parts, total = ns.Model.Parts(m), st.total
	local shares = {}
	for _, pn in ipairs(PART_NAMES) do
		local v = parts[pn[1]]
		if v > 0 then shares[#shares + 1] = string.format("%s %.0f%%", pn[2], v / total * 100) end
	end
	local lw = m.tal.loneWolf > 0
	-- the pet's swing time Frenzy's uptime is counted with (Player.PetSwing, Model petSwing)
	local swingText = m.petSwing and string.format("удар %.2f с", m.petSwing)
		or string.format("удар ещё не виден — считается %.1f с", ns.Model.PET_BASE_SWING)
	local petText
	if not st.snap.petOut then
		-- Lone Wolf with no pet out (Player.PetOut): the pet's share of crit, hit and expertise is gone; expertise still
		-- lowers the mob's dodge against the hawks (Model.Parts hawkDodge, while they are counted: outside the Survival branch)
		-- or the melee swings (the Survival weave, which needs a bow, gun or crossbow: Model weaveParts)
		local hawks, melee = parts.hawks > 0, st.snap.survival and not m.noShots
		local expText = hawks and "мастерство идёт ястребам" or melee and "мастерство идёт ближнему бою" or "мастерство урона не даёт"
		petText = "пета нет — Lone Wolf +20%; доля пета в крите, меткости и мастерстве не в счёт, " .. expText
	elseif parts.pet <= 0 then
		petText = "пета до 10 ур. нет — статы для пета не в счёт"
	elseif lw then
		petText = "пет призван — Lone Wolf не действует, урон пета −17%, " .. swingText
	else
		local fam = m.petFamily and ns.Model.PET_FAMILY[m.petFamily]
		if fam then
			petText = string.format("пет считается (семейство %+d%% урона, %s)", fam.pct,
				fam.claw and fam.bite and "Claw + Bite" or fam.claw and "Claw" or "Bite")
		elseif m.petFamily then
			petText = "пет считается (семейство " .. m.petFamily .. " не в таблице: без бонуса, Claw + Bite)"
		else
			petText = "пет считается (семейство не видно — призови пета: пока без бонуса, Claw + Bite)"
		end
		petText = petText .. ", " .. swingText
	end
	ns.Print(string.format("билд BM %d / MM %d / SV %d; %s", pts.BM, pts.MM, pts.SV, petText))
	-- the melee the model counts: the Survival branch weaves as wowsims' SV Weave preset (Player.SurvivalBranch, Model.Weave:
	-- the cycle outside Rapid Fire, Raptor Strike every nCycles(6) of its cycles, the melee look's casts a minute averaged
	-- over Rapid Fire while levelling, over the raid fight's states in raid mode), and without a bow, gun or crossbow it
	-- neither shoots nor melees; every other build has no melee
	local wv = st.snap.survival and ns.Model.Weave(m)
	if wv then
		local base, rate = wv.base, wv.average.rates
		local raptorText = base.rates.raptor > 0
			and string.format("Raptor Strike раз в %.1f цикла", 1 / (base.rates.raptor * base.C))
			or "без Raptor Strike (в правой руке нет оружия для него)"
		ns.Print(string.format("ближний бой: плетение как в wowsims (SV Weave) — цикл %.2f с: выстрел и удар правой рукой, %s, Strider Kick %.1f, Mongoose Bite %.1f, Wing Clip %.1f, Immolation Trap %.1f в минуту",
			base.C, raptorText, rate.strider * 60, rate.bite * 60, rate.wingClip * 60, rate.trap * 60))
	elseif st.snap.survival then
		ns.Print("ближний бой: плетение как в wowsims (SV Weave) — без лука, ружья или арбалета нет ни выстрелов, ни ближнего боя")
	else
		ns.Print("ближний бой: не в счёт — больше всего очков не в Выживании")
	end
	-- no part attacks with no shot, no hawks and no pet (Model.Weights: the unit is then 1 DPS)
	ns.Print("кому идёт урон: " .. (#shares > 0 and table.concat(shares, ", ") or "никому — нет ни выстрелов, ни ястребов, ни пета, ни ближнего боя"))
	-- the hit the worn set's shots meet the cap with in Score.SetValue: the base hit, the worn items' and set
	-- bonuses' hit and the worn gear's ranged-only hit (ctx.baseHit + snap.gearHit + snap.setHit + snap.rangedGearHit:
	-- the live hit) and the worn ranged skill's hit against the level's skill by wowsims' attack table
	-- (Model.SkillHit at the model point's bonus m.rangedSkill, the worn skill shown less 5 x level); the sheet's hit
	-- (snap.liveHit); the crit: the model's, the sheet's ranged crit (the skill's crit effect is on the skill line: the
	-- shots' crit suppression, 0.2% a point below the level's maximum, Model critSuppressor: -0.2 x max(0, -bonus) =
	-- min(0, 0.2 x bonus))
	local ctx, rs = st.ctx, st.rangedSkill
	local skillHit = ns.Model.SkillHit(ctx.mobDiff, m.rangedSkill)
	local capHit = ctx.baseHit + st.snap.gearHit + st.snap.setHit + st.snap.rangedGearHit + skillHit
	local skillText
	if rs.line then
		-- rs.line: a bow's, gun's or crossbow's line (A.State: 45, 46, 226), each in Player.SKILL_NAME; the skill shown
		-- with the worn gear and the trained skill (A.State rangedSkill) against the level's 5 x level
		skillText = string.format("навык %s %d/%d против %d по уровню: меткость выстрелов %+.1f%%, крит выстрелов %+.1f%%",
			ns.Player.SKILL_NAME[rs.line], rs.shown, rs.skill, 5 * m.level, skillHit, math.min(0, 0.2 * m.rangedSkill))
	else
		skillText = "нет лука, ружья или арбалета — навык как у уровня"
	end
	-- a stale reading (Player.ReadStats: the last reading of the same gear and talents) with the reason the new one is
	-- not used (snap.statsStaleBy): "useBuff", a Use buff of Game/UseData.lua up or unknown; "debuff", an aura that lowers
	-- the stats up or unknown (Game/StatMultData.lua StatDebuffData: Resurrection Sickness and the like); "hidden", the
	-- stats secret or an aura state unknown, Aspect of the Hawk's, with the Trueshot Aura talent (ranks.trueshotAura, the
	-- only case ReadStats reads that aura) Trueshot Aura's, or a stat multiplier's (Game/StatMultData.lua)
	local staleBy = st.snap.statsStaleBy
	if staleBy == "useBuff" then
		ns.Print("статы — последнее чтение с этой же экипировкой и талантами: сейчас действует бафф «Использования» вещи (или игра его скрывает)")
	elseif staleBy == "debuff" then
		ns.Print("статы — последнее чтение с этой же экипировкой и талантами: на персонаже аура, снижающая статы (Resurrection Sickness и т. п., или игра её скрывает)")
	elseif staleBy == "hidden" then
		ns.Print("статы — последнее чтение с этой же экипировкой и талантами: игра скрывает "
			.. (m.tal.trueshotAura > 0 and "статы, состояние Aspect of the Hawk, Trueshot Aura или баффов, умножающих статы (Kings и т. п.)"
				or "статы, состояние Aspect of the Hawk или баффов, умножающих статы (Kings и т. п.)"))
	end
	-- the ranged weapon the shots fire with; with no bow, gun or crossbow (Model.Parts noShots) no shot is cast, and the
	-- model's bowSpeed is Player.WeaponInputs' speed of a slot without a weapon (or a thrown weapon's), no bow's. A thrown
	-- weapon is a weapon without shots: Player.WeaponInputs puts its DPS in bowDPS with noShots, and Model.Parts reads
	-- bowDPS in the hawks' AP with no shot condition (hawkAP), so with the hawks counted its DPS goes there and nowhere
	-- else, and without them into no damage
	local bowText
	if not m.noShots then
		bowText = string.format("лук %.1f DPS / %.2f с", m.bowDPS, m.bowSpeed)
	elseif m.bowDPS > 0 then
		bowText = string.format("не лук, ружьё или арбалет — выстрелов нет, DPS оружия %.1f %s", m.bowDPS,
			parts.hawks > 0 and "идёт только в AP ястребов" or "урона не даёт (ястребов нет)")
	else
		bowText = "нет лука, ружья или арбалета"
	end
	-- the worn set's expertise (the model's: the worn items' and set bonuses', Player.Snapshot reads no live expertise)
	-- and the cap Score.SetValue prices every set's expertise up to (ctx.expertiseCap: the mob's dodge, Model.MobAvoid)
	ns.Print(string.format("ур. %d, RAP %d, крит %.2f%%, меткость %.2f%% (кап %.1f%%; в листе %.2f%%, %s), мастерство %.2f%% (кап %.1f%%; с вещей и комплектов), %s, патроны %.1f, колчан %d%%",
		m.level, m.rap, m.crit, capHit, ctx.hitCap, st.snap.liveHit, skillText, m.expertise, ctx.expertiseCap,
		bowText, m.ammoDPS, math.floor(m.quiver * 100 + 0.5)))
	-- the worn state's permanent attack speed by source (Player wornHaste; Model.Parts p.haste / attackSpeed / hasteRating /
	-- meleeHaste / rangedHaste) and who takes each (wowsims' paths, raid-mode W1 design section 7)
	ns.Print(string.format("скорость атаки (надетое): общая %.2f%% (выстрелы, ближний бой, пет, ястребы), скорость атаки (комплект, раса) %.2f%% (выстрелы, ближний бой, пет), рейтинг скорости %.2f%% (выстрелы, ближний бой), только ближний бой %.2f%% (ближний бой, пет), только дальний бой %.2f%% (выстрелы, ястребы)",
		m.haste, m.attackSpeed, m.hasteRating, m.meleeHaste, m.rangedHaste))
	local W = st.W
	-- W.HIT_DW: both hands' white swings past the cap; W.HIT_DW_MH: the main hand's part of it (Model.Weights); in raid mode
	-- the mana stats' weights beside Intellect's (raid-mode design 8: the fight's derivatives); W.SPELL_HIT a point below the
	-- trap's spell hit cap (ctx.spellHitCap, Model.TrapHitCap) and W.SPELL_CRIT a point of spell crit, Immolation Trap's in
	-- the Survival weave, 0 outside it (raid-mode design 18.8, 25.7)
	local intText = fmt(W.INT)
	if m.mode == "raid" then intText = string.format("%s, MP5 %s, Дух %s, мана %s", fmt(W.INT), fmt(W.MP5), fmt(W.SPI), fmt(W.MANA)) end
	ns.Print(string.format("урон (%s): Ловк %s, AP %s, Сила %s, Инт %s, меткость 1%% %s (только выстрелы %s; сверх капа с двумя оружиями %s, из них правая рука %s), крит 1%% %s (только дальний бой %s), мастерство 1%% %s, меткость заклинаний 1%% %s (до капа ловушки %.1f%%), крит заклинаний 1%% %s, скорость атаки 1%% %s (скорость атаки (комплект, раса) %s, рейтинг скорости %s, только ближний бой %s, только дальний бой %s), DPS лука %s, DPS патронов %s, ПР %s, ЛР %s, 2H %s",
		UNIT_TEXT[st.unit](st.unitDps), fmt(W.AGI), fmt(W.AP), fmt(W.STR), intText, fmt(W.HIT), fmt(W.HIT_RANGED), fmt(W.HIT_DW), fmt(W.HIT_DW_MH), fmt(W.CRIT),
		fmt(W.CRIT_RANGED), fmt(W.EXPERTISE), fmt(W.SPELL_HIT), ctx.spellHitCap, fmt(W.SPELL_CRIT), fmt(W.HASTE), fmt(W.ATTACK_SPEED),
		fmt(W.HASTE_RATING), fmt(W.MELEE_HASTE), fmt(W.RANGED_HASTE), fmt(W.RANGED_DPS), fmt(W.AMMO_DPS), fmt(W.MH_DPS), fmt(W.OH_DPS),
		fmt(W.TH_DPS)))
	-- the tie-break (Score.Secondary): ctx.pools, Player.Snapshot's pools (UnitHealthMax, UnitPowerMax, UnitArmor); raid
	-- mode has no mana part, the mana is in the damage (raid-mode design 7.9, 8)
	local p = st.ctx.pools
	if m.mode == "raid" then
		ns.Print("здоровье и броня — только при равном уроне; мана считается в уроне")
	else
		ns.Print(string.format("здоровье, броня, мана — только при равном уроне, в %% от запаса: здоровье %s, мана %s, броня %s",
			tostring(p.hp), tostring(p.mana), tostring(p.armor)))
	end
	local names = {}
	for k, v in pairs(m.tal) do if v > 0 then names[#names + 1] = k .. " " .. v end end
	table.sort(names)
	ns.Print("таланты из игры (применённые): " .. table.concat(names, ", "))
end

local function linesCopy(lines)
	local out = {}
	for i, l in ipairs(lines or {}) do
		out[i] = (l.left or "") .. (l.right and ("  ||  " .. l.right) or "")
			.. ((l.leftRed or l.rightRed) and "  [RED]" or "")
	end
	return out
end

local function dumpItem(piece)
	local res = ns.Advisor.Evaluate(piece.link, piece.where and piece.where.bag and piece.where or nil)
	return {
		link = piece.link, name = piece.name, equipLoc = piece.equipLoc,
		classID = piece.classID, subclassID = piece.subclassID, setID = piece.setID,
		stats = piece.stats, apiStats = piece.apiStats, apiRaw = piece.apiRaw, mismatch = piece.mismatch,
		speed = piece.speed, reqLevel = piece.reqLevel, restrictText = piece.restrictText,
		procs = piece.procs, use = piece.use, effects = piece.effects, unparsed = piece.unparsed,
		tooltip = linesCopy(piece.lines),
		result = res and {
			usable = res.usable, reason = res.reason, delta = res.delta, dps = res.dps,
			isUpgrade = res.isUpgrade, hand = res.hand,
			mh = res.mh and res.mh.name, oh = res.oh and res.oh.name,
			-- each damage proc's procs per minute on the landed hits of the set the result scores the item in
			-- (Advisor.ModelProcRates): for a worn item and an item placed in no set the worn set's hits ("worn"), for an
			-- item the evaluation places the hits of res.newSet, the set it goes into ("newSet"), as procsPerMinuteHits
			-- names them; each proc's rate by its source (Score.ProcRateSource: measured, wowsims' override row, the DB2's;
			-- 0 for a proc with none)
			procsPerMinuteAtModel = ns.Advisor.ModelProcRates(res),
			procsPerMinuteHits = select(2, ns.Advisor.ModelProcRates(res)),
		} or "not ready",
	}
end

-- The raid fight of Model.Fight for /hga dump: its segments { t0, t1, weight, rf, bw, uses = { the spells up, the Frenzy
-- Potion's among them }, regime, phase, shares, income, m0, m1, D (the state's net drain), rc (its casting regen), J (its
-- Judgement of Wisdom income) }, the windows of Rapid Fire, Bestial Wrath, the Use buffs and the Frenzy Potion, the times
-- the mana runs out, the runes and the mana potion, the costs, and its means; the states' parts and hits stay out
-- (Model.Parts and the landed hits are dumped as such). The fight is the worn set's: the model point with the worn set's Use
-- buffs in their firing order (Score.SetUses; the fight Advisor ctx.useGain prices the worn set's buffs in)
local function fightDump(st)
	local p = {}
	for k, v in pairs(st.model) do p[k] = v end
	p.uses = ns.Score.SetUses(st.snap.equipped)
	local f = ns.Model.Fight(p)
	local segments = {}
	for i, s in ipairs(f.segments) do
		local spells = {}
		for _, k in ipairs(s.state.uses) do spells[#spells + 1] = f.useSpells[k] end
		local ss = s.state
		segments[i] = { t0 = s.t0, t1 = s.t1, weight = s.weight, rf = ss.rf, bw = ss.bw, uses = spells, regime = ss.regime,
			phase = ss.phase, shares = ss.shares, income = ss.income, m0 = s.m0, m1 = s.m1, D = ss.mana.D, rc = ss.mana.rc,
			J = ss.mana.J }
	end
	return { segments = segments, rapidFire = f.rapidFire, bestialWrath = f.bestialWrath, uses = f.uses,
		frenzyPotion = f.frenzyPotion, oom = f.oom, runes = f.runes, manaPotion = f.manaPotion, costs = f.costs, means = f.means }
end

local function dump()
	local st = ns.Advisor.State()
	if not st then ns.Print(ns.Advisor.NotReadyText()); return end
	local out = {
		when = date("%Y-%m-%d %H:%M:%S"), locale = GetLocale(), build = (GetBuildInfo()),
		model = st.model, weights = st.W, weightUnit = st.unit, dpsPerUnit = st.unitDps, modelTotal = st.total,
		-- target: the mob level difference the mode gives (Player.Snapshot), which the caps follow
		target = st.model.mobDiff,
		hitCap = st.ctx.hitCap, expertiseCap = st.ctx.expertiseCap, baseHit = st.ctx.baseHit, liveHit = st.snap.liveHit, gearHit = st.snap.gearHit,
		setHit = st.snap.setHit, wornHit = st.ctx.wornHit, rangedSkill = st.rangedSkill,
		-- the worn hands' melee weapon skill lines, live skills and trained skills (Advisor A.State); the model point's
		-- mhSkill, ohSkill and meleeHit come with model
		meleeSkill = st.meleeSkill,
		-- the worn ranged line's trained skill over 5 x level and the target Score prices each set's ranged skill against
		-- (Advisor A.State); the model point's rangedSkill and rangedHit come with model
		skillBase = st.ctx.skillBase, mobDiff = st.ctx.mobDiff,
		-- landedHits: the worn set's (Advisor A.State ctx.landedHits)
		landedHits = st.ctx.landedHits, statsStale = st.snap.statsStale == true,
		-- the outcome of a proc's damage by its table at the model point (Model.ProcOutcomes)
		procOutcome = st.ctx.procOutcome,
		dualWield = st.snap.dualWield,
		-- the Survival branch, the one build that melees (Player.SurvivalBranch), and its weave (Model.Weave: the cycles and
		-- their rates; nil without a bow, gun or crossbow)
		survival = st.snap.survival, weave = st.snap.survival and ns.Model.Weave(st.model) or nil,
		-- the raid fight of the worn set (Model.Fight with its Use buffs; nil while levelling): its segments with their times,
		-- weight and state (Rapid Fire, Bestial Wrath, the buffs' spells up, the mana's regime, shares and pool), the windows,
		-- the mana's events, and the weighted means of Serpent Sting's and the hawks' uptime, delta_S, delta_H, the HHA cycle,
		-- Judgement of Wisdom's income, the casting regen and the starved share (fightDump)
		fight = st.model.mode == "raid" and fightDump(st) or nil,
		-- the mana regen and the hit modifiers as the client gives them, to check in game the model's readings against them:
		-- GetManaRegen (the model's regenRest and regenCast) and GetManaRegenFromSpirit (PlayerScriptDocumentation.lua:571-590:
		-- each two numbers, mana a second) with the sheet's Spirit (the model's spirit), and the melee, ranged and spell hit
		-- modifiers (GetHitModifier :533, GetRangedHitModifier :946, GetSpellHitModifier :1113)
		manaRegen = { GetManaRegen() }, manaRegenFromSpirit = { GetManaRegenFromSpirit() },
		hitModifiers = { melee = GetHitModifier(), ranged = GetRangedHitModifier(), spell = GetSpellHitModifier() },
		-- the ammo slot as the client answers (Forever UI: GetInventoryItemID and GetInventoryItemCount as
		-- Camelot/PaperDollFrame.lua:2221 and :2185 call them, C_PaperDollInfo.AmmoNeeded in
		-- PaperDollInfoDocumentation.lua, UnitUsesAmmo in UnitDocumentation.lua)
		ammo = {
			fromBag = st.snap.ammoFromBag,
			slotLink = GetInventoryItemLink("player", 0),
			slotID = GetInventoryItemID("player", 0),
			slotCount = GetInventoryItemCount("player", 0),
			ammoNeeded = C_PaperDollInfo.AmmoNeeded(),
			unitUsesAmmo = UnitUsesAmmo("player"),
			rangedHaste = { GetRangedHaste() },
			quiver = st.snap.quiverPiece and st.snap.quiverPiece.name,
		},
		equipped = {}, bags = {},
	}
	for slot, piece in pairs(st.snap.equipped) do out.equipped[tostring(slot)] = dumpItem(piece) end
	for _, piece in ipairs(st.snap.bagPieces) do
		if piece.equipLoc ~= "" then out.bags[#out.bags + 1] = dumpItem(piece) end
	end
	ns.db.dump = out
	ns.Print("записал. Сделай /reload, потом скажи Claude: файл WTF\\Account\\<аккаунт>\\SavedVariables\\HunterGearAdvisor.lua")
end

-- The help: the commands HGA keeps (raid-mode design 14.5). The target, the hit cap, the checkmark's threshold, the swap
-- banner and the melee follow the mode and the talents, and a proc's rate its sources (Score.ProcRateSource): no command
-- sets anything (the user, 2026-11-17).
local HELP_LINES = {
	"/hga weights — веса статов и входные цифры",
	"/hga dump — записать разбор всех вещей в файл (потом /reload)",
	"/hga swap — показать список замен (что из сумок надеть вместо чего)",
	"/hga preraid (/hga pr) — окно пререйд-набора: чего не хватает и где брать",
}

SLASH_HUNTERGEARADVISOR1 = "/hga"
SlashCmdList.HUNTERGEARADVISOR = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "weights" or cmd == "w" then
		printWeights()
	elseif cmd == "dump" then
		dump()
	elseif cmd == "swap" then
		ns.Swap.Show()
	elseif cmd == "preraid" or cmd == "pr" then
		ns.PreRaidUI.Toggle()
	else
		-- any other text, a removed command among them, prints the help and changes nothing
		for _, line in ipairs(HELP_LINES) do ns.Print(line) end
	end
end

-- Things that change the answer. Talents: TRAIT_CONFIG_UPDATED after "Apply" (clicks before
-- it only stage changes, see Player.ReadTalents), TRAIT_CONFIG_LIST_UPDATED when the configs
-- arrive after login.
for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
	"TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "PLAYER_TALENT_UPDATE", "TRAIT_NODE_CHANGED" }) do
	ns.On(ev, function() ns.Invalidate() end)
end
-- Dual spec switch: another talent config becomes the active one (the Camelot talent frame
-- waits for ACTIVE_COMBAT_CONFIG_CHANGED; ACTIVE_TALENT_GROUP_CHANGED as a second signal).
for _, ev in ipairs({ "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
	ns.On(ev, function()
		ns.Player.ForgetAppliedTalents()
		ns.Invalidate()
	end)
end
-- Pet out or not, its family and its swing time (Player.PetCheck): summoned / dismissed (UNIT_PET for the
-- player), died (UNIT_HEALTH of the pet), the attack speed of the pet or the hunter changes
-- (UNIT_ATTACK_SPEED: Frenzy coming and going; a melee haste of the hunter coming and going, which
-- Player.PetSwing follows, and reaching the pet at its heartbeat), and an addon restriction ended
-- (ADDON_RESTRICTION_STATE_CHANGED fires after a restriction is deactivated, Forever
-- RestrictedActionsDocumentation.lua): PetSwing reads nothing while Frenzy's aura or a swing is secret.
ns.On("UNIT_PET", function(_, unit) if unit == "player" then ns.Player.PetCheck() end end)
ns.On("UNIT_HEALTH", function(_, unit) if unit == "pet" then ns.Player.PetCheck() end end)
ns.On("UNIT_ATTACK_SPEED", function(_, unit) if unit == "pet" or unit == "player" then ns.Player.PetCheck() end end)
ns.On("ADDON_RESTRICTION_STATE_CHANGED", function() ns.Player.PetCheck() end)
-- These can turn red tooltip lines white (skill, profession, reputation, level): the item
-- records keep the parsed red lines, so they are read again.
for _, ev in ipairs({ "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP", "UPDATE_FACTION" }) do
	ns.On(ev, function()
		ns.Items.ClearCache()
		ns.Invalidate()
	end)
end
