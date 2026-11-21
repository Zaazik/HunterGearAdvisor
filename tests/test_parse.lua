return function(ns, T)
	local F = require("fixtures_templates")
	local ru = ns.Parse.New(F.ruRU)
	local en = ns.Parse.New(F.enUS)
	local function L(left, right, leftRed, rightRed) return { left = left, right = right, leftRed = leftRed, rightRed = rightRed } end

	return {
		-- A proc's school as its damage words name it (Core/Parse.lua PROC_DAMAGE_PATTERNS; the forms of the Forever DB2 Spell
		-- descriptions): ruRU "ед. урона от <the school>" magic, "ед. урона" and "ед. физического урона" physical, "от" right
		-- after "урона" alone ("ед. урона противнику" of Spell 16790, SchoolMask 1, holds "от" inside a word); enUS
		-- "<Arcane|Fire|Frost|Holy|Nature|Shadow> damage" magic (Spell 16067 Arcane, 14105 Frost, 13519 Holy, 13527 Nature:
		-- "Blasts a target for $s1 Arcane damage." and the like), "damage" with no such word physical; an "Equip:" proc's too
		{ "parse: the proc's school words, ruRU and enUS, magic vs physical", function()
			local function school(p, line) return p:Lines({ L("Item"), L(line) }).procs[1].school end
			T.eq(school(ru, "Возможный эффект при попадании: наносит 22 - 34 ед. урона от огня."), "magic")
			T.eq(school(ru, "Возможный эффект при попадании: наносит от 22 до 34 ед. урона от тайной магии."), "magic")
			T.eq(school(ru, "Возможный эффект при попадании: наносит 30 - 50 ед. урона."), "physical")
			T.eq(school(ru, "Возможный эффект при попадании: Смертельно ранит противника, нанося 92 - 118 ед. физического урона."), "physical")
			T.eq(school(ru, "Если на персонаже: Шанс поразить отдаленную цель стрелой Тьмы и нанести ей 13 - 19 ед. урона от темной магии."), "magic")
			T.eq(school(ru, "Если на персонаже: Атаки ближнего боя с некоторой вероятностью наносят 200 - 300 ед. урона."), "physical")
			T.eq(school(ru, "Возможный эффект при попадании: нанесение 30 - 50 ед. урона противнику и его ближайшим союзникам."), "physical")
			T.eq(school(en, "Chance on hit: Blasts a target for 22 - 34 Fire damage."), "magic")
			for _, word in ipairs({ "Arcane", "Frost", "Holy", "Nature" }) do
				T.eq(school(en, "Chance on hit: Blasts a target for 22 - 34 " .. word .. " damage."), "magic", word)
			end
			T.eq(school(en, "Chance on hit: Wounds the target for 30 to 50 Shadow damage."), "magic")
			T.eq(school(en, "Chance on hit: Wounds the target for 30 to 50 damage."), "physical")
			T.eq(school(en, "Chance on hit: Delivers a fatal wound for 92 to 118 Physical damage."), "physical")
			T.eq(school(en, "Equip: Chance to strike your ranged target with a Shadow Bolt for 13 to 19 Shadow damage."), "magic")
			T.eq(school(en, "Equip: Chance on melee attack to deal 200 - 300 damage."), "physical")
		end },
		{ "ruRU primary stats with sign", function()
			local r = ru:Lines({ L("Item"), L("+5 к ловкости"), L("+7 к выносливости"), L("-2 к духу") })
			T.eq(r.stats.AGI, 5); T.eq(r.stats.STA, 7); T.eq(r.stats.SPI, -2)
			T.eq(#r.unparsed, 0)
		end },
		{ "ruRU percent hit/crit with comma and with dot", function()
			local r = ru:Lines({ L("Item"),
				L("Если на персонаже: повышает вероятность попадания на 1,0%."),
				L("Если на персонаже: повышает вероятность критического удара на 0.7%.") })
			T.near(r.stats.HIT, 1.0, 1e-9, "hit"); T.near(r.stats.CRIT, 0.7, 1e-9, "crit")
		end },
		{ "ruRU attack power lines seen in game", function()
			local r = ru:Lines({ L("Перчатки дрессировщика собак"),
				L("Если на персонаже: +24 к силе атаки."),
				L("Если на персонаже: +21 к силе атаки против животных.") })
			T.eq(r.stats.AP, 24, "ap"); T.eq(r.stats.AP_VS_BEAST, 21, "ap vs beasts")
			T.eq(#r.effects, 0); T.eq(#r.unparsed, 0)
		end },
		{ "ruRU ranged attack power without trailing period", function()
			local r = ru:Lines({ L("Item"), L("Если на персонаже: +12 к силе атаки дальнего боя") })
			T.eq(r.stats.RAP, 12); T.eq(r.stats.AP, nil)
		end },
		{ "ruRU weapon dps with comma, speed on the right", function()
			local r = ru:Lines({ L("Bow"), L("Дальний бой", "Лук"), L("Урон: 50-80", "Скорость 2,60"), L("(24,6 ед. урона в секунду)") })
			T.near(r.stats.DPS, 24.6, 1e-9, "dps"); T.near(r.speed, 2.6, 1e-9, "speed")
		end },
		{ "ruRU proc average", function()
			local r = ru:Lines({ L("Bow"), L("Возможный эффект при попадании: Поражает цель в дальнем бою \"Огненным взрывом\", наносит 22 - 34 ед. урона от огня.") })
			T.eq(r.procs[1].avg, 28); T.eq(r.procs[1].hits, "weapon"); T.eq(r.effects[1].kind, "proc")
		end },
		{ "ruRU enchant line, armor, ammo", function()
			local r = ru:Lines({ L("Item"), L("Броня: 120"), L("Чары: +5 к ловкости"), L("Добавляет 13 ед. урона в секунду") })
			T.eq(r.stats.ARMOR, 120); T.eq(r.stats.AGI, 5); T.eq(r.stats.AMMO_DPS, 13)
		end },
		{ "ruRU red level line is not a restriction, red weapon type is", function()
			local r = ru:Lines({ L("Item"), L("Требуется 45-й уровень", nil, true) })
			T.eq(r.reqLevel, 45); T.eq(r.restricted, nil)
			local r2 = ru:Lines({ L("Mace"), L("Одноручное", "Булава", false, true) })
			T.eq(r2.restricted, true); T.eq(r2.restrictText, "Булава")
		end },
		{ "ruRU set bonus and use lines are effects, unknown equip line is an effect", function()
			local r = ru:Lines({ L("Item"), L("Комплект: +10 к силе атаки."), L("Комплект (2 предмета): что-то"),
				L("Использование: Восстанавливает 100 ед. здоровья."), L("Если на персонаже: Вы невидимы.") })
			T.eq(r.stats.AP, nil, "set bonus AP must not count")
			T.eq(#r.effects, 4)
		end },
		{ "ruRU old rating wording converts to percent", function()
			local r = ru:Lines({ L("Item"), L("Повышает рейтинг меткости на 10."), L("Повышает рейтинг критического удара на 14.") })
			T.near(r.stats.HIT, 1.0, 1e-9); T.near(r.stats.CRIT, 1.0, 1e-9)
		end },
		{ "enUS lines", function()
			local r = en:Lines({ L("Item"), L("+12 Agility"), L("Equip: Improves your chance to hit by 1.0%."),
				L("Equip: +24 Attack Power."), L("Equip: +20 Ranged Attack Power."), L("Requires Level 45"),
				L("(1,024.5 damage per second)"), L("Chance on hit: Blasts a target for 22 - 34 Fire damage.") })
			T.eq(r.stats.AGI, 12); T.near(r.stats.HIT, 1, 1e-9); T.eq(r.stats.AP, 24); T.eq(r.stats.RAP, 20)
			T.eq(r.reqLevel, 45); T.near(r.stats.DPS, 1024.5, 1e-9); T.eq(r.procs[1].avg, 28)
		end },
		{ "ruRU item seen in game: enchant with two stats, Feral Combat, durability", function()
			local r = ru:Lines({ L("Item"), L("+18 к ловкости"), L("+11 к духу"),
				L("Если на персонаже: Повышает силу зверя на 1."),
				L("Чары: +3 к выносливости и +24 к броне"), L("Прочность: 75 / 75") })
			T.eq(r.stats.AGI, 18); T.eq(r.stats.SPI, 11); T.eq(r.stats.STA, 3); T.eq(r.stats.ARMOR, 24)
			T.eq(#r.unparsed, 0, "nothing unparsed")
			T.eq(r.effects[1].kind, "useless", "Feral Combat is useless for a hunter")
		end },
		{ "half-understood multi-stat line is not counted", function()
			local r = ru:Lines({ L("Item"), L("Чары: +3 к выносливости и что-то ещё") })
			T.eq(r.stats.STA, nil); T.eq(#r.unparsed, 1)
		end },
		{ "ordinary lines from the in-game dump are not unparsed", function()
			local r = ru:Lines({ L("Меч Покорителя"), L("Становится персональным при поднятии"), L("Одноручное", "Меч"),
				L("Урон: 46-86", "Скорость 2,20"), L("(30,0 ед. урона в секунду)"), L("Если на персонаже: +22 к силе атаки."),
				L("|cff00ff00<Изготовитель: Заазик Величайший>|r"), L("Уникальный"), L("Сумка (10 |4ячейка:ячейки:ячеек;)"),
				L("Этот предмет позволяет получить задание."), L("\"Ремесленный заказ, перехваченный и все еще актуальный.\""),
				L("Сотворенный предмет"), L("22 - 35 ед. урона от огня"), L("Вероятность блока: 19") })
			T.eq(r.stats.AP, 22); T.near(r.stats.DPS, 30, 1e-9); T.near(r.speed, 2.2, 1e-9)
			T.eq(#r.unparsed, 0, "unparsed: " .. table.concat(r.unparsed, " | "))
		end },
		{ "line without a number is never reported as unparsed", function()
			local r = ru:Lines({ L("Item"), L("Какое-то описание без чисел") })
			T.eq(#r.unparsed, 0)
		end },
		{ "ranged weapon skill, scope, hit scope and quiver lines are read as stats", function()
			local r = ru:Lines({ L("Ружьё"), L("Если на персонаже: повышение навыка владения огнестрельным оружием на 3."),
				L("Чары: Прицел (+5 к урону)") })
			T.eq(r.stats.SKILL_GUNS, 3); T.eq(r.stats.RANGED_FLAT, 5); T.eq(#r.effects, 0)
			-- the hit scope 2523 is ranged-only hit (spell 22780 bound to ranged weapons): RANGED_HIT, not HIT
			local r2 = ru:Lines({ L("Ружьё"), L("Чары: +3% к рейтингу меткости") })
			T.eq(r2.stats.RANGED_HIT, 3); T.eq(r2.stats.HIT, nil)
			local q = ru:Lines({ L("Колчан"), L("Если на персонаже: Увеличение скорости дальней атаки на 13%.") })
			T.eq(q.stats.QUIVER_HASTE, 13); T.eq(#q.effects, 0)
			local en1 = en:Lines({ L("Gun"), L("Equip: Increased Bows +2."), L("Enchanted: Scope (+7 Damage)") })
			T.eq(en1.stats.SKILL_BOWS, 2); T.eq(en1.stats.RANGED_FLAT, 7)
		end },
		-- The melee weapon skill lines (GlobalStrings 59290-59309, the fixtures' texts of build 70888): each INCREASE gives
		-- SKILL_<LINE> the amount, each DECREASE the amount negated (raid-mode W1 design 3.4). Mutants: a line's template
		-- dropped; DECREASE not negated
		{ "parse: the ten melee skill lines, ruRU and enUS, INCREASE and DECREASE -> SKILL_<LINE> (negative for DECREASE)", function()
			local LINES = { SWORDS = "SKILL_SWORDS", MACES = "SKILL_MACES", AXES = "SKILL_AXES", FIST_WEAPONS = "SKILL_FIST",
				DAGGERS = "SKILL_DAGGERS", STAVES = "SKILL_STAVES", ["TWO-HANDED_SWORDS"] = "SKILL_2H_SWORDS",
				["TWO-HANDED_MACES"] = "SKILL_2H_MACES", ["TWO-HANDED_AXES"] = "SKILL_2H_AXES", POLEARMS = "SKILL_POLEARMS" }
			local n = 0
			for line, key in pairs(LINES) do
				for locale, p in pairs({ ruRU = ru, enUS = en }) do
					for _, dir in ipairs({ { "INCREASE", 4 }, { "DECREASE", -4 } }) do
						local text = F[locale]["TOOLTIP_ITEM_STAT_SKILL_" .. line .. "_" .. dir[1]]:gsub("%%1%$d", "4")
						local r = p:Lines({ L("Item"), L(text) })
						T.eq(r.stats[key], dir[2], locale .. " " .. text)
						T.eq(#r.unparsed, 0, locale .. " " .. text .. ": unparsed")
						T.eq(#r.effects, 0, locale .. " " .. text .. ": an effect")
						n = n + 1
					end
				end
			end
			T.eq(n, 40)
		end },
		{ "a stat-debuff proc is not counted as damage", function()
			local r = ru:Lines({ L("Меч"), L("Возможный эффект при попадании: Уменьшает силу атаки цели на 40 на 1 мин.") })
			T.eq(#r.procs, 0); T.eq(r.effects[1].avg, nil)
			local r2 = ru:Lines({ L("Лук"), L("Возможный эффект при попадании: наносит от 22 до 34 ед. урона от огня.") })
			T.eq(r2.procs[1].avg, 28)
			-- Forever ruRU physical procs: "N - M ед. физического урона" (spells 18107, 13486)
			local r3 = ru:Lines({ L("Меч"), L("Возможный эффект при попадании: Смертельно ранит противника, нанося 92 - 118 ед. физического урона.") })
			T.eq(r3.procs[1].avg, 105)
			local r4 = ru:Lines({ L("Меч"), L("Возможный эффект при попадании: Похищает 10 - 20 ед. здоровья у цели.") })
			T.eq(#r4.procs, 0, "health drain is not damage")
		end },
		{ "the charges template does not hide stat lines", function()
			local r = ru:Lines({ L("Item"), L("3 заряда"), L("+5 к странному стату") })
			T.eq(#r.unparsed, 1, "unknown stat line must be reported")
			local e = en:Lines({ L("Item"), L("+5 Fire Damage") })
			T.eq(#e.unparsed, 1, "'%s Damage' only counts on the weapon damage line")
		end },
		{ "a set name line is no unparsed line; the unique-equipped line marks the item", function()
			local r = ru:Lines({ L("Item"), L("Облачение повелителя зверей (0/8)"), L("Уникальный использующийся") })
			T.eq(#r.unparsed, 0); T.eq(r.uniqueEquipped, true)
		end },
		{ "enUS enchant lines with the name before the amount are read", function()
			local r = en:Lines({ L("Item"), L("Enchanted: Stamina +3 and Armor +24"), L("Enchanted: Agility +5") })
			T.eq(r.stats.STA, 3); T.eq(r.stats.ARMOR, 24); T.eq(r.stats.AGI, 5)
		end },
		-- stats-gear-10: SpellItemEnchantment 8720 (enUS "+2% Crit", ruRU db2_ru row; spell 1310308 with SpellEquippedItems
		-- 256731, bows, guns and crossbows: ranged crit alone) and 249 / 853 Beastslaying
		{ "stats-gear-10: crit scope and Beastslaying enchant lines are read, not unparsed; the scope's crit is ranged only", function()
			local r = ru:Lines({ L("Лук"), L("Чары: +2% к вероятности критического удара") })
			T.eq(r.stats.CRIT_RANGED, 2); T.eq(r.stats.CRIT, nil); T.eq(#r.unparsed, 0)
			local e = en:Lines({ L("Bow"), L("Enchanted: +2% Crit") })
			T.eq(e.stats.CRIT_RANGED, 2); T.eq(e.stats.CRIT, nil); T.eq(#e.unparsed, 0)
			local b = ru:Lines({ L("Меч"), L("Чары: +6 к убийству животных") })
			T.eq(b.stats.BEAST_SLAYING, 6); T.eq(#b.unparsed, 0); T.eq(#b.effects, 0)
			local be = en:Lines({ L("Sword"), L("Enchanted: Beastslaying +2") })
			T.eq(be.stats.BEAST_SLAYING, 2); T.eq(#be.unparsed, 0)
		end },
		-- stats-gear-4: Heartseeking Crossbow 13040 (ItemEffect 99815 TriggerType 1, spell 29626) and the other
		-- equip chance-on-hit wordings of the Forever Spell descriptions
		{ "stats-gear-4: equip chance-on-hit damage lines are procs with the hits that roll them", function()
			local r = ru:Lines({ L("Арбалет"), L("Если на персонаже: Шанс поразить отдаленную цель стрелой Тьмы и нанести ей 13 - 19 ед. урона от темной магии.") })
			T.eq(#r.procs, 1); T.eq(r.procs[1].avg, 16); T.eq(r.procs[1].hits, "ranged")
			T.eq(r.effects[1].kind, "proc"); T.eq(r.effects[1].equip, true)
			local e = en:Lines({ L("Crossbow"), L("Equip: Chance to strike your ranged target with a Shadowbolt for 13 to 19 Shadow damage.") })
			T.eq(e.procs[1].avg, 16); T.eq(e.procs[1].hits, "ranged")
			-- Darkmoon Card: Maelstrom (spell 23686): melee hits only, on a trinket too
			local m = ru:Lines({ L("Карта"), L("Если на персонаже: Вероятность поражения вашей цели в ближнем бою молнией с нанесением 200 - 300 ед. урона от сил природы.") })
			T.eq(m.procs[1].avg, 250); T.eq(m.procs[1].hits, "melee")
			-- Highborne Research Tablet (spell 1318159: "Chance on hit to deal $1265634s1 Arcane damage", 1265634 SpellEffect
			-- EffectBasePointsF 75 with Variance 0.16, 69 to 81): the hits of what carries it
			local t = en:Lines({ L("Tablet"), L("Equip: Chance on hit to deal 69 to 81 Arcane damage. Deals 2 times as much damage to Naga and Satyrs.") })
			T.eq(t.procs[1].avg, 75); T.eq(t.procs[1].hits, "weapon")
			-- not procs: damage when struck (spell 1292880), a chance on hit without damage (Fist of Stone 1294794)
			local s = ru:Lines({ L("Пояс"), L("Если на персонаже: Атакующие противники с вероятностью 5% получают 10 - 20 ед. урона от сил природы.") })
			T.eq(#s.procs, 0); T.eq(s.effects[1].kind, "equip")
			local f = en:Lines({ L("Mace"), L("Equip: Chance on hit to restore 100 mana.") })
			T.eq(#f.procs, 0); T.eq(f.effects[1].kind, "equip")
		end },
		-- The origin of a proc: an "Equip:" line is an equip aura (ItemEffect TriggerType 1: Heartseeking Crossbow 13040's
		-- ItemEffect 99815, spell 29626), a "Chance on hit:" line a chance on hit (TriggerType 2). Score.ProcRate rolls a
		-- landed hit without damage (Serpent Sting's applications) on the second only (EV-0021 lines 18-19, 32-33, 41-50).
		{ "a proc's record says whether it comes from an \"Equip:\" line: equip = true there, absent on a chance-on-hit line", function()
			local both = ru:Lines({ L("Арбалет"),
				L("Если на персонаже: Шанс поразить отдаленную цель стрелой Тьмы и нанести ей 13 - 19 ед. урона от темной магии."),
				L("Возможный эффект при попадании: Поражает цель в дальнем бою \"Огненным взрывом\", наносит 22 - 34 ед. урона от огня.") })
			T.eq(#both.procs, 2)
			T.eq(both.procs[1].avg, 16); T.eq(both.procs[1].hits, "ranged"); T.eq(both.procs[1].equip, true, "ruRU \"Если на персонаже:\"")
			T.eq(both.procs[2].avg, 28); T.eq(both.procs[2].hits, "weapon"); T.eq(both.procs[2].equip, nil, "ruRU \"Возможный эффект при попадании:\"")
			local en2 = en:Lines({ L("Crossbow"), L("Equip: Chance to strike your ranged target with a Shadowbolt for 13 to 19 Shadow damage."),
				L("Chance on hit: Blasts a target for 22 - 34 Fire damage.") })
			T.eq(en2.procs[1].equip, true, "enUS \"Equip:\""); T.eq(en2.procs[2].equip, nil, "enUS \"Chance on hit:\"")
			-- an equip proc on any item (a trinket's "weapon" hits: the Highborne Research Tablet's 1318159) is one too
			local t = en:Lines({ L("Tablet"), L("Equip: Chance on hit to deal 69 to 81 Arcane damage. Deals 2 times as much damage to Naga and Satyrs.") })
			T.eq(t.procs[1].hits, "weapon"); T.eq(t.procs[1].equip, true, "the Tablet's equip line")
		end },
		-- attack speed enchants by the scope of their aura: SpellItemEnchantment 931 (spell 13928, aura 342), 34 (7217,
		-- aura 319), 2543 (22841, auras 319 + 140), 7123 (432137, aura 319 bp 50); enUS / ruRU Name_lang of build 70888. Haste
		-- rating (stat type 36) is HASTE_RATING, the hunter's own attacks alone (wowsims hasteRatingMultiplier, raid-mode W1
		-- design 7.3): its equip lines (GlobalStrings 59282 / 59283 TOOLTIP_ITEM_STAT_HASTE_PCT_INCREASE / _DECREASE) and its
		-- rating line (16404 ITEM_MOD_HASTE_RATING, 10 rating a 1%), ruRU and enUS; Minor Haste's aura 342 stays HASTE
		{ "attack speed enchants: 342 is HASTE, 319 MELEE_HASTE, 319 + 140 both scopes; ruRU and enUS, bare or after Чары; haste rating lines are HASTE_RATING", function()
			local function stats(p, text)
				local r = p:Lines({ L("Item"), L(text) })
				T.eq(#r.unparsed, 0, "unparsed: " .. text); T.eq(#r.effects, 0, "effects: " .. text)
				return r.stats
			end
			local function keys(st)
				local out = {}
				for k, v in pairs(st) do out[#out + 1] = k .. "=" .. v end
				table.sort(out)
				return table.concat(out, " ")
			end
			for _, prefix in ipairs({ "", "Чары: " }) do
				T.eq(keys(stats(ru, prefix .. "+1% к скорости")), "HASTE=1", "Minor Haste " .. prefix)
				T.eq(keys(stats(ru, prefix .. "Противовес (+3% к скорости атаки)")), "MELEE_HASTE=3", "Counterweight " .. prefix)
				T.eq(keys(stats(ru, prefix .. "+1% к скорости атаки")), "MELEE_HASTE=1 RANGED_HASTE=1", "Arcanum " .. prefix)
				T.eq(keys(stats(ru, prefix .. "Автоматический пробойник толпы")), "MELEE_HASTE=50", "Pummeler " .. prefix)
			end
			for _, prefix in ipairs({ "", "Enchanted: " }) do
				T.eq(keys(stats(en, prefix .. "Haste +1%")), "HASTE=1", "Minor Haste " .. prefix)
				T.eq(keys(stats(en, prefix .. "Counterweight +3% Attack Speed")), "MELEE_HASTE=3", "Counterweight " .. prefix)
				T.eq(keys(stats(en, prefix .. "Attack Speed +1%")), "MELEE_HASTE=1 RANGED_HASTE=1", "Arcanum " .. prefix)
				T.eq(keys(stats(en, prefix .. "Automatic Crowd Pummeler")), "MELEE_HASTE=50", "Pummeler " .. prefix)
			end
			-- other speed enchants of the table are no attack speed: 911 "Minor Speed Increase" (run speed)
			local r = ru:Lines({ L("Item"), L("Чары: Небольшое увеличение скорости") })
			T.eq(next(r.stats), nil, "run speed is no attack speed")
			-- haste rating: HASTE_RATING in %, negative for DECREASE, the rating line / 10, and no other key
			local function rating(p, text, want)
				local st = stats(p, text)
				T.near(st.HASTE_RATING, want, 1e-12, text)
				for k in pairs(st) do T.eq(k, "HASTE_RATING", text) end
			end
			rating(ru, "Если на персонаже: повышает скорость атаки и применения заклинаний на 1,0%.", 1)
			rating(ru, "Если на персонаже: понижает скорость атаки и применения заклинаний на 2,0%.", -2)
			rating(en, "Equip: Increases your attack speed and casting speed by 1.0%.", 1)
			rating(en, "Equip: Decreases your attack speed and casting speed by 2.0%.", -2)
			rating(ru, "Повышает рейтинг скорости боя на 20.", 2)
			rating(en, "Increases your haste by 20.", 2)
		end },
		{ "unknown line goes to unparsed", function()
			local r = ru:Lines({ L("Item"), L("Нечто странное 5") })
			T.eq(r.unparsed[1], "Нечто странное 5")
		end },
		-- the ranged-only hit of an item's equip spell (1294769 and 22780: aura 54 bound to ranged weapons; Marksman Bands
		-- 18296): ruRU "Повышает вероятность попадания в дальнем бою на ${$s1}.1%.", enUS "Improves your chance to hit with
		-- ranged weapons by ${$s1}.1%." (db2_ru / db2 Spell.csv); one decimal, read with the client's decimal separator
		{ "parse: the ranged-only hit line, ruRU and enUS, is RANGED_HIT", function()
			for _, case in ipairs({ { "1,0", 1 }, { "1", 1 }, { "3,0", 3 } }) do
				local r = ru:Lines({ L("Item"), L("Если на персонаже: Повышает вероятность попадания в дальнем бою на " .. case[1] .. "%.") })
				T.near(r.stats.RANGED_HIT, case[2], 1e-12, case[1]); T.eq(r.stats.HIT, nil, case[1])
				T.eq(#r.effects, 0, case[1]); T.eq(#r.unparsed, 0, case[1])
			end
			for _, case in ipairs({ { "1.0", 1 }, { "2", 2 } }) do
				local r = en:Lines({ L("Item"), L("Equip: Improves your chance to hit with ranged weapons by " .. case[1] .. "%.") })
				T.near(r.stats.RANGED_HIT, case[2], 1e-12, case[1]); T.eq(r.stats.HIT, nil, case[1]); T.eq(#r.effects, 0, case[1])
			end
		end },
		-- the ranged hit rating line (GlobalStrings 16385 ITEM_MOD_HIT_RANGED_RATING), 10 rating a 1% (Forever's flat table)
		{ "parse: ITEM_MOD_HIT_RANGED_RATING is RANGED_HIT, 10 rating a 1%", function()
			local r = ru:Lines({ L("Item"), L("Меткость (оруж. дальн. боя) +10.") })
			T.near(r.stats.RANGED_HIT, 1, 1e-12, "ruRU"); T.eq(r.stats.HIT, nil); T.eq(#r.unparsed, 0)
			local e = en:Lines({ L("Item"), L("Improves ranged hit by 20.") })
			T.near(e.stats.RANGED_HIT, 2, 1e-12, "enUS"); T.eq(e.stats.HIT, nil); T.eq(#e.unparsed, 0)
		end },
		-- the hit scopes SpellItemEnchantment 2523 and 8057 apply 22780, ranged-only hit
		{ "parse: the hit scopes 2523 and 8057, ruRU and enUS, are RANGED_HIT 3", function()
			for _, case in ipairs({ { ru, "Чары: +3% к рейтингу меткости" }, { ru, "Чары: Птичий прицел (+3% к вероятности попадания)" },
				{ en, "Enchanted: +3% Hit" }, { en, "Enchanted: Poultry Precision Scope (+3% Hit)" } }) do
				local r = case[1]:Lines({ L("Bow"), L(case[2]) })
				T.eq(r.stats.RANGED_HIT, 3, case[2]); T.eq(r.stats.HIT, nil, case[2]); T.eq(#r.unparsed, 0, case[2])
			end
		end },
		-- attack power against a creature type: the equip texts of aura 102 + 131 by mask (Forever DB2 build 70888, db2 /
		-- db2_ru Spell.csv: 13492, 24291, 12822, 22836, 21937, 12981, 1292025, 435360, 23930), one key each
		{ "parse: attack power against each creature type, ruRU and enUS, is AP_VS_<TYPE>", function()
			local rows = {
				{ "+15 к силе атаки против животных.", "+15 Attack Power against Beasts.", "BEAST" },
				{ "+15 к силе атаки против драконов.", "+15 Attack Power against Dragonkin.", "DRAGONKIN" },
				{ "+15 к силе атаки против демонов.", "+15 Attack Power against Demons.", "DEMON" },
				{ "+15 к силе атаки против элементалей.", "+15 Attack Power against Elementals.", "ELEMENTAL" },
				{ "Увеличение силы атаки против великанов на 15 ед.", "+15 Attack Power against Giants.", "GIANT" },
				{ "+15 к силе атаки против нежити.", "+15 Attack Power against Undead.", "UNDEAD" },
				{ "+15 к силе атаки против гуманоидов.", "+15 Attack Power against Humanoids.", "HUMANOID" },
				{ "Увеличивает силу атаки против механизмов на 15.", "+15 Attack Power against Mechanical units.", "MECHANICAL" },
				{ "Повышает силу атаки против нежити на 15. Также позволяет собирать камни Плети по поручению Серебряного Рассвета.",
					"+15 Attack Power against Undead.  Allows the acquisition of Scourgestones on behalf of the Argent Dawn.", "UNDEAD" },
			}
			for _, row in ipairs(rows) do
				for _, case in ipairs({ { ru, "Если на персонаже: " .. row[1] }, { en, "Equip: " .. row[2] } }) do
					local r = case[1]:Lines({ L("Item"), L(case[2]) })
					local keys = 0
					for k in pairs(r.stats) do keys = keys + 1 end
					T.eq(r.stats["AP_VS_" .. row[3]], 15, case[2]); T.eq(keys, 1, case[2] .. ": one key")
					T.eq(#r.effects, 0, case[2]); T.eq(#r.unparsed, 0, case[2])
				end
			end
		end },
		-- mask 36 (Undead + Demon): 29112 and 1219521 name both types, each gets the amount
		{ "parse: AP vs Undead and Demons adds both keys", function()
			for _, case in ipairs({
				{ ru, "Если на персонаже: Повышает силу атаки против нежити и демонов на 81. Также позволяет собирать камни Плети по поручению Серебряного Рассвета." },
				{ ru, "Если на персонаже: Повышает силу атаки в бою против нежити и демонов на 81. Также позволяет собирать камни Плети по поручению Серебряного Рассвета." },
				{ en, "Equip: +81 Attack Power against Undead and Demons.  Allows the acquisition of Scourgestones on behalf of the Argent Dawn." },
				{ en, "Equip: +81 Attack Power when fighting Undead and Demons.  It also allows the acquisition of Scourgestones on behalf of the Argent Dawn." },
			}) do
				local r = case[1]:Lines({ L("Item"), L(case[2]) })
				T.eq(r.stats.AP_VS_UNDEAD, 81, case[2]); T.eq(r.stats.AP_VS_DEMON, 81, case[2])
				T.eq(#r.effects, 0, case[2]); T.eq(#r.unparsed, 0, case[2])
			end
		end },
		-- the "doubled against" texts: Counterattack Lodestone 18537 (spell 1318938: auras 99 + 124 bp 30 and 102 + 131 misc
		-- 256 bp 30) and item 273817 (1319047: 99 + 124 bp 12, 102 + 131 misc 32 bp 12): plain AP and AP against the type
		{ "parse: the 'doubled against' lines are AP and AP_VS of their type (Counterattack Lodestone 18537, item 273817)", function()
			for _, case in ipairs({
				{ ru, "Если на персонаже: +30 к силе атаки. Бонус удваивается против механизмов.", "MECHANICAL", 30 },
				{ en, "Equip: +30 Attack Power, doubled against Mechanical units.", "MECHANICAL", 30 },
				{ ru, "Если на персонаже: +12 к силе атаки. Бонус удваивается против нежити.", "UNDEAD", 12 },
				{ en, "Equip: +12 Attack Power, doubled against Undead targets.", "UNDEAD", 12 },
			}) do
				local r = case[1]:Lines({ L("Item"), L(case[2]) })
				T.eq(r.stats.AP, case[4], case[2]); T.eq(r.stats["AP_VS_" .. case[3]], case[4], case[2])
				T.eq(#r.effects, 0, case[2]); T.eq(#r.unparsed, 0, case[2])
			end
		end },
		-- a type word none of the texts has stays an equip effect "not counted"
		{ "parse: attack power against an unknown type word is no stat, an equip effect", function()
			local r = ru:Lines({ L("Item"), L("Если на персонаже: +10 к силе атаки против тварей.") })
			T.eq(next(r.stats), nil); T.eq(r.effects[1].kind, "equip")
			local e = en:Lines({ L("Item"), L("Equip: +10 Attack Power against Critters.") })
			T.eq(next(e.stats), nil); T.eq(e.effects[1].kind, "equip")
		end },
		-- The "Equip:" lines of a proc on every hit (raid-mode design 25.3; Core/Parse.lua ALWAYS_PROC_PATTERNS): the Forever
		-- DB2 descriptions (build 70888, db2 Spell.csv / db2_ru Spell.csv at their values) of Hurricane 1316319 (a range:
		-- "6 - 10", "от 6 до 10", "6 to 10", or one number), the bombs 1318069, Fiery Plate Gauntlets 7721, Blazefury Medallion
		-- 7711 ("уронаот огня на 2 ед.": the number after the words), Storm Gauntlets 16615, Force Imbued Gauntlets 1302248:
		-- each an equip proc of its damage and its mask's hits ("ranged" for the ranged auto attacks, "melee" for the melee
		-- swings and abilities); a line of no amount, and Crest of Retribution's block, stay equip effects
		{ "parse: the lines of a proc on every hit are equip procs of their amount and their mask's hits, ruRU and enUS", function()
			local function proc(p, line)
				local r = p:Lines({ L("Item"), L(line) })
				local x = r.procs[1]
				return x and x.avg, x and x.hits, x and x.equip, x and x.school, #r.procs, r.effects[1].kind
			end
			local function is(p, line, avg, hits, school)
				local a, h, eq, sc, n, kind = proc(p, line)
				T.eq(a, avg, line); T.eq(h, hits, line); T.eq(eq, true, line); T.eq(n, 1, line); T.eq(kind, "proc", line)
				if school then T.eq(sc, school, line) end
			end
			is(ru, "Если на персонаже: Автоатаки в дальнем бою призывают ледяные стрелы, наносящие цели 6 - 10 ед. урона от магии льда.", 8, "ranged", "magic")
			is(ru, "Если на персонаже: Автоатаки в дальнем бою призывают ледяные стрелы, наносящие цели от 6 до 10 ед. урона от магии льда.", 8, "ranged")
			is(ru, "Если на персонаже: Автоатаки в дальнем бою призывают ледяные стрелы, наносящие цели 8 ед. урона от магии льда.", 8, "ranged", "magic")
			is(en, "Equip: All ranged auto-attacks conjure an icy bolt to blast your current target, inflicting 6 to 10 Frost damage.", 8, "ranged", "magic")
			is(ru, "Если на персонаже: Атаки метательным оружием вызывают взрывы, наносящие ближайшим противникам 3 - 30 ед. урона от огня.", 16.5, "ranged")
			is(en, "Equip: Thrown attacks explode on impact, causing 4 - 37 Fire damage to nearby enemies.", 20.5, "ranged")
			is(ru, "Если на персонаже: Атаки оружием наносят еще 4 ед. урона от огня.", 4, "melee", "magic")
			is(en, "Equip: Adds 4 Fire damage to your weapon attack.", 4, "melee", "magic")
			is(ru, "Если на персонаже: Повышение наносимого в ближнем бою уронаот огня на 2 ед.", 2, "melee", "magic")
			is(en, "Equip: Adds 2 fire damage to your melee attacks.", 2, "melee")
			is(ru, "Если на персонаже: Наделение оружия способностью наносить в атаках дополнительно 3 ед. урона от эффетка \"Молния\".", 3, "melee", "magic")
			is(en, "Equip: Adds 3 Lightning damage to your melee attacks.", 3, "melee")
			is(ru, "Если на персонаже: Атаки ближнего боя также наносят 2 ед. урона от тайной магии.", 2, "melee", "magic")
			is(en, "Equip: Adds 2 Arcane damage to your melee attacks.", 2, "melee", "magic")
			-- the auras of the main hand alone (raid-mode design 26.2): Iceblade Hacker's 1298413 (one number), Warblade of Caer
			-- Darrow's 1298500 (a range or one number), Dreadfrost Saber's 1294939
			is(ru, "Если на персонаже: Атаки этим оружием в ближнем бою наносят 41 ед. урона от магии льда.", 41, "melee", "magic")
			is(ru, "Если на персонаже: Атаки этим оружием в ближнем бою наносят 22 - 33 ед. урона от магии льда.", 27.5, "melee", "magic")
			is(en, "Equip: Melee attacks with this weapon deal 28 Frost damage.", 28, "melee", "magic")
			is(en, "Equip: Melee attacks with this weapon deal 22 to 33 Frost damage.", 27.5, "melee", "magic")
			is(ru, "Если на персонаже: Атаки ближнего боя также наносят 1 ед. урона от магии льда.", 1, "melee", "magic")
			is(en, "Equip: Adds 1 Frost damage to your melee attacks.", 1, "melee", "magic")
			-- an unlinked one's school by Parse's enUS rule (procDamage's): "N <word> damage" magic for the school words alone,
			-- any other word physical; a made-up physical line, and 16615's "Lightning" read so (its entry links it with the
			-- school of its spell)
			is(en, "Equip: Adds 5 Physical damage to your melee attacks.", 5, "melee", "physical")
			is(en, "Equip: Adds 3 Lightning damage to your melee attacks.", 3, "melee", "physical")
			local a, _, _, _, n, kind = proc(ru, "Если на персонаже: Атаки ближнего боя также наносят урон.")
			T.eq(a, nil); T.eq(n, 0); T.eq(kind, "equip", "no amount: an equip effect")
			local a2, _, _, _, n2, kind2 = proc(en, "Equip: Deals 22 Physical damage every time you block.")
			T.eq(a2, nil); T.eq(n2, 0); T.eq(kind2, "equip", "on a block: no hunter hit")
		end },
	}
end
