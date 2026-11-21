-- Gear scoring: whole equipped set with capped hit and expertise, slot choice, MH/OH/2H pairing.
-- Pure Lua 5.1: no WoW API here.
--
-- An item is { name, id, equipLoc, classID, subclassID, setID, stats = {...}, speed, procs, use,
-- uniqueEquipped }. stats.DPS is the tooltip weapon DPS, stats.AMMO_DPS the ammo DPS,
-- stats.RANGED_FLAT a scope's flat damage per shot, stats.CRIT_RANGED a crit scope's crit of the ranged attacks
-- alone (Parse; priced at W.CRIT_RANGED by ItemValue's stat loop, as every stat by its own weight key),
-- stats.BEAST_SLAYING Beastslaying's flat damage per hit against beasts (Model.Parts p.beastSlaying: ctx.weaponGain runs it
-- with the set's weapons, else Score.ItemValue prices it at W.BEAST_SLAYING), stats.HASTE / ATTACK_SPEED / HASTE_RATING /
-- MELEE_HASTE / RANGED_HASTE the attack speed by source in % (Model.Parts p.haste / attackSpeed / hasteRating /
-- meleeHaste / rangedHaste; priced at W.HASTE / W.ATTACK_SPEED / W.HASTE_RATING / W.MELEE_HASTE / W.RANGED_HASTE, each
-- the value of one more 1% source of its input at the worn point (Model.Weights), by ItemValue's
-- stat loop, a weapon's attack speed enchant too, like the weapon's other stats; the
-- worn state's are in the model point, Player wornHaste); setID is the item set it belongs to
-- (nil: none); procs = { { avg, hits, equip, school, linked, defense, crit [, mask, chance, ppm, icd] } ... } its damage
-- procs (Parse:Lines, linked to Game/ProcData.lua by Items.Get; priced by Score.ProcRate and Score.ProcValue); use = its
-- on-use stat buff { spell, stats = {...}, duration, cooldown } (Game/UseData.lua);
-- skillOffset = for a ranged weapon of another type than the worn one, the skill points its line's trained
-- skill differs from the worn line's (Advisor rangedSkillPiece; nil: 0).

local _, ns = ...
local Score = {}
ns.Score = Score

Score.SLOT = {
	HEAD = 1, NECK = 2, SHOULDER = 3, CHEST = 5, WAIST = 6, LEGS = 7, FEET = 8, WRIST = 9, HANDS = 10,
	FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17,
	RANGED = 18, AMMO = 0,
}
local S = Score.SLOT

-- equipLoc -> candidate slots (weapons are handled separately)
Score.ARMOR_SLOTS = {
	INVTYPE_HEAD = { S.HEAD }, INVTYPE_NECK = { S.NECK }, INVTYPE_SHOULDER = { S.SHOULDER },
	INVTYPE_CHEST = { S.CHEST }, INVTYPE_ROBE = { S.CHEST }, INVTYPE_WAIST = { S.WAIST },
	INVTYPE_LEGS = { S.LEGS }, INVTYPE_FEET = { S.FEET }, INVTYPE_WRIST = { S.WRIST },
	INVTYPE_HAND = { S.HANDS }, INVTYPE_FINGER = { S.FINGER1, S.FINGER2 },
	INVTYPE_TRINKET = { S.TRINKET1, S.TRINKET2 }, INVTYPE_CLOAK = { S.BACK },
}

local WEAPON_LOCS = {
	INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
	INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true,
}
Score.WEAPON_LOCS = WEAPON_LOCS


local function canMH(item) return item.equipLoc == "INVTYPE_WEAPON" or item.equipLoc == "INVTYPE_WEAPONMAINHAND" or item.equipLoc == "INVTYPE_2HWEAPON" end
local function canOH(item, dualWield)
	if item.equipLoc == "INVTYPE_HOLDABLE" then return true end
	if not dualWield then return false end
	return item.equipLoc == "INVTYPE_WEAPON" or item.equipLoc == "INVTYPE_WEAPONOFFHAND"
end
local function isTwoHand(item) return item ~= nil and item.equipLoc == "INVTYPE_2HWEAPON" end
Score.CanMH, Score.CanOH, Score.IsTwoHand = canMH, canOH, isTwoHand

-- Procs per minute of chance-on-hit items with a rate measured in Forever combat logs, by item id: the claims of
-- wowsims/forever docs/evidence EV-0003 (end-game dungeon weapons), EV-0021 (Highborne Research Tablet), EV-0022
-- (levelling logs), EV-0024 (Sword of Dismemberment), EV-0050 (Rock on Stick), EV-0119 (isolated hits; it replaces
-- EV-0003's Stoneslayer and EV-0022's Bigger Rock on Bigger Stick), EV-0120, EV-0121 and EV-0122. Item ids as the EV
-- files state them; EV-0119 names its items only, their ids are the ItemSparse rows of those names (the Era export: the
-- build 70888 ItemSparse export lacks these classic rows), checked against the Forever Item.csv row and the
-- ItemXItemEffect -> ItemEffect proc spell. A rate is procs per minute at the base speed of the weapon in the hand
-- that hits: each landed hit of a hand rolls rate x the base speed of the weapon in that hand / 60 (a weapon's proc on
-- its own hand's hits at its own speed, a weapon's "melee" or "any" proc on another hand's hits at that hand's weapon's
-- speed), and haste leaves that chance alone (EV-0119 lines 26-27: "PPM = chance x 60 / the weapon's speed", the rate
-- priced on the weapon's base speed; EV-0022 lines 33-35: Bigger Rock on Bigger Stick's chance a swing follows the
-- speed of what swings, a procs-per-minute fit, not a flat chance; wowsims sim/core/attack.go:1255-1268 PPMProc: ppm x
-- the SwingSpeed of the hand that hits / 60, and weapon_speed_ppm_test.go). A non-weapon item's measured rate rolls at the
-- speed of the hand that hits as well (wowsims sim/core/procs.go:183-227 mergeOrAppend: the main hand's hits at its
-- speed, the off hand's at its, the ranged ones at the ranged weapon's). Each rate counts the procs over the landed
-- hits of the weapon carrying it, white swings and specials alike (EV-0022 line 20, EV-0003 lines 11-12); a cast that
-- lands without damage rolls a weapon's "Chance on hit" proc too (EV-0119 line 25; wowsims
-- sim/core/spelldata/resolve_proc.go:95-110 WeaponProc: RequireDamageDealt = false, a landed hit is enough, so a special
-- that deals no damage, such as Sunder Armor, rolls it; EV-0021 lines 49-50), and never an equip aura's (EV-0021 lines
-- 18-19 and 41-47; Score.ProcRate); a ranged-type hit never rolls a melee weapon's proc (EV-0119 lines 5-7).
-- Score.ProcRate turns a rate into procs on the landed hits of the set the item is scored in. An open point:
-- Heartseeking Crossbow 13040's rate is an equip aura's (ItemEffect 99815, TriggerType 1), priced on its damaging
-- hits alone, the Auto Shots and the special shots, no Serpent Sting application; EV-0119 line 25 counts "casts that
-- land without a damage event" as hits in its method, and its Heartseeking row (line 86, "Hunter | rng | 105 / 747")
-- does not say whether Serpent Sting's applications are in that denominator. Left out: White Obsidian Wand 274425
-- (3.75, a wand: no hunter skill line) and Dragon's Call 10847 (4.5 behind a 45 s cooldown, so the rate alone overstates
-- it).
-- The hand speed each rate is measured at: the weapon's own speed (EV-0003 lines 11-12, EV-0022 lines 20-21, EV-0024
-- line 9, EV-0050 lines 38-39, EV-0119 lines 21-27, EV-0120 line 28, EV-0121 line 24), but for three rows measured on
-- another hand's hits. Seeping Willow 12969: a druid's 1.0 s Cat Form paw (EV-0003 line 23; line 12: a druid's rate is
-- at the paw's speed). Rot-Covered Harpoon 274963: the 1.0 s paw (EV-0122 line 3: 1.45 a minute on Cat Form white
-- swings, priced on the 1.0 s paw; lines 12-15: 11 of the 12 procs logged, over landed Cat Form white swings on creatures
-- with the harpoon worn; lines 15-16: PPM = chance x 60 / 1.0, the paw's speed, and the same chance read on the
-- harpoon's own 2.5 s as 0.57 a minute [0.32, 1.01]; line 17: rounded to the nearest 0.05; line 21: 11 procs in 463
-- landed swings, 2.38% a swing [1.33, 4.20], 1.43 a minute on the paw [0.80, 2.52]; lines 28-29: 2 a minute, 3.33% a
-- swing, not ruled out). Princess Theradras' Scepter 17766: a shaman's hits and a cat druid's mixed (EV-0003 line
-- 29). HGA applies every rate per minute at the speed of the weapon that hits, the hunter's own: the chance a swing
-- follows the speed of the hand that hits, a cat's 1.0 s paw included (EV-0022 lines 33-35: Bigger Rock on Bigger
-- Stick 11.7% a swing at its own 3.4 s, 8.6% at a bear's 2.5 s, 2.5% at a cat's 1.0 s, a procs-per-minute fit), as
-- wowsims prices a rate (sim/core/attack.go:1255-1268 PPMProc: ppm x the SwingSpeed of the hand that hits / 60). So
-- the harpoon swung at its 2.5 s rolls 1.45 x 2.5 / 60 a hit.
Score.MEASURED_PPM = {
	[10750] = 1.5,   -- Lifeforce Dirk (EV-0003)
	[11744] = 3.2,   -- Bloodfist (EV-0003)
	[11803] = 2,     -- Force of Magma (EV-0003)
	[12463] = 1.5,   -- Drakefang Butcher (EV-0003)
	[12582] = 1.7,   -- Keris of Zul'Serak (EV-0003)
	[12969] = 0.9,   -- Seeping Willow (EV-0003), on a 1.0 s cat paw
	[13183] = 1.7,   -- Venomspitter (EV-0003)
	[13348] = 1.1,   -- Demonshear (EV-0003)
	[13983] = 1.9,   -- Gravestone War Axe (EV-0003)
	[17730] = 1.2,   -- Gatorbite Axe (EV-0003)
	[17753] = 3.5,   -- Verdant Keeper's Aim, ranged hits only (EV-0003)
	[17766] = 1.8,   -- Princess Theradras' Scepter (EV-0003), on a shaman's and a cat druid's hits
	[17943] = 3.2,   -- Fist of Stone (EV-0003)
	[18388] = 1.7,   -- Stoneshatter (EV-0003)
	[274270] = 1.1,  -- Weed Whacker (EV-0003)
	[275441] = 2.3,  -- Cremation Longbow (EV-0003)
	[276419] = 3.6,  -- Lightcrest Hammer (EV-0003)
	[260205] = 2.6,  -- Highborne Research Tablet, at a 2.5 s main hand; Auto Shot rolls it too (EV-0021)
	[9478] = 2,      -- Ripsaw (EV-0022)
	[9639] = 2,      -- The Hand of Antu'sul (EV-0022)
	[11086] = 2.9,   -- Jang'thraze the Protector (EV-0022)
	[17705] = 1,     -- Thrash Blade (EV-0022)
	[287005] = 0.6,  -- Sword of Dismemberment (EV-0024)
	[279852] = 1.85, -- Rock on Stick (EV-0050)
	[6472] = 1.75,   -- Stinging Viper (EV-0119)
	[9453] = 1.8,    -- Toxic Revenger (EV-0119)
	[6220] = 1.55,   -- Meteor Shard (EV-0119)
	[6904] = 1.45,   -- Bite of Serra'kis (EV-0119)
	[9418] = 1.95,   -- Stoneslayer (EV-0119)
	[279480] = 1.5,  -- Bigger Rock on Bigger Stick (EV-0119)
	[7717] = 1,      -- Ravager (EV-0119)
	[12974] = 0.6,   -- The Black Knight (EV-0119)
	[13040] = 2.7,   -- Heartseeking Crossbow, an equip trigger (EV-0119)
	[871] = 1.65,    -- Flurry Axe (EV-0120)
	[13361] = 1.95,  -- Skullforge Reaver (EV-0121)
	[274963] = 1.45, -- Rot-Covered Harpoon (EV-0122), on a 1.0 s cat paw
}

-- The overrides wowsims sets by hand on an equip aura's trigger, by item id (Score.ProcRate). The Highborne Research
-- Tablet 260205 (wowsims sim/common/forever/items_trinkets.go:253-286; EV-0021 lines 4, 13-20: 70 procs from 647 landed
-- damaging melee hits at a 2.5 s main hand, an Auto Shot rolls it too, only a hit that deals damage does):
-- - spellsAtMainHand: its rate (MEASURED_PPM, 2.6) is NewLegacyPPMManagerWithSpells' (items_trinkets.go:275-277;
--   sim/core/procs.go:62-82): the hits of each hand at that hand's weapon's speed, and every other hit of its mask but a
--   ranged auto attack at the main hand's speed, so with no ranged weapon (the ranged hand's speed 0, Model.LandedHits)
--   the dives roll it at the main hand's;
-- - requireDamage: RequireDamageDealt stays true over its row's harmful-spell bit (items_trinkets.go:279-281), so
--   Serpent Sting's applications, which deal no damage, never roll it.
Score.PROC_OVERRIDES = {
	[260205] = { spellsAtMainHand = true, requireDamage = true },
}
local NO_OVERRIDES = {}

-- The rate of an item's damage proc (U4 = (a), the orchestrator's settlement under the user's rule «берем как в вов
-- симс»; raid-mode design 14.4, 18.6): wowsims makes no rate up (docs/rulings/R-0046: a rate the game files do not state
-- takes a per-item carry-over value; R-0047: a proc whose entry states no rate registers nothing). So a proc's rate is,
-- in order: the item's measured rate in Forever logs (MEASURED_PPM); else the rate wowsims' override data gives its
-- entry (Game/ProcData.lua source: tools/database/overrides weapon_procs.go and spell_overrides.go, read by
-- tools/gen_proc_data.py; a measurement "EV-<n>" or a carry-over "vanilla-carryover" / "tbc-carryover", unchecked in
-- Forever); else the DB2's own rate or chance (a linked equip aura's SpellProcsPerMinute or ProcChance 1-99). A proc with
-- none of them is not priced (Score.ProcRate gives 0) and its tooltip line says its rate is unknown. A linked equip aura
-- wowsims rolls on every hit of its mask (Game/ProcData.lua always: ProcChanceAlways, StatedChance 1, wowsims
-- sim/core/spelldata/resolve_proc.go:187-199; raid-mode design 25.3) has the chance 100 a hit after the measured rate and
-- an override row (its row states no other). Returns the rate per minute and its kind: "measured" (MEASURED_PPM, per
-- minute at the speed of the hand that hits), "wowsims" (an override row, its source in proc.source), "db2ppm" (the DB2's
-- procs per minute), "db2chance" (the DB2's chance a hit, the second value then the chance in %), "always" (every hit:
-- the chance 100 in %), or nil, nil (unknown).
function Score.ProcRateSource(item, proc)
	local measured = Score.MEASURED_PPM[item.id]
	if measured then return measured, "measured" end
	if proc.linked and proc.source ~= nil then
		if proc.ppm ~= nil and proc.ppm > 0 then return proc.ppm, "wowsims" end
		if proc.chance ~= nil and proc.chance >= 1 and proc.chance <= 99 then return proc.chance, "wowsims" end
		error("HunterGearAdvisor: a proc with an override source and no rate: " .. tostring(item.name), 2)
	end
	if proc.equip and proc.linked then
		if proc.always then return 100, "always" end
		if proc.ppm > 0 then return proc.ppm, "db2ppm" end
		if proc.chance >= 1 and proc.chance <= 99 then return proc.chance, "db2chance" end
	end
	return nil, nil
end

-- A weapon for the damage model and the procs: an item of class 2 (Weapon) that is not held in the off hand (Player
-- isWeapon and Player.WeaponInputs read this rule).
function Score.IsWeapon(item)
	return item ~= nil and item.classID == 2 and item.equipLoc ~= "INVTYPE_HOLDABLE"
end

-- The hands of Model.LandedHits, in a fixed order; the hand of a weapon scored in a slot of each kind (Score.SlotKind);
-- the hands each proc's hits (Parse) roll on, "weapon" aside; the hand of each weapon slot.
local HANDS = { "mh", "oh", "ranged" }
local OWN_HAND = { mh = "mh", ["2h"] = "mh", oh = "oh", ranged = "ranged" }
local ROLLS = {
	melee = { mh = true, oh = true },
	ranged = { ranged = true },
	any = { mh = true, oh = true, ranged = true },
}
local ONE_HAND = { mh = { mh = true }, oh = { oh = true }, ranged = { ranged = true } }
local SLOT_HAND = { { S.MAINHAND, "mh" }, { S.OFFHAND, "oh" }, { S.RANGED, "ranged" } }

-- n hits per second at a base speed of `speed` seconds; a hand that lands no hit adds nothing, whatever its speed
-- (Model.LandedHits gives p's speed, which the model leaves unread for a hand it does not swing).
local function atSpeed(n, speed)
	if n == 0 then return 0 end
	return n * speed
end

-- The ProcTypeMask bits of an equip aura that a hunter's hits roll (wowsims sim/core/dbcenums/proc_flags.go:10-31,
-- decoded sim/core/proc_types.go:86-175): the white melee swings, the melee abilities, the ranged auto attacks (Auto
-- Shot), the ranged abilities (the shots, the dive, Serpent Sting's application) and the harmful spell, which clears
-- RequireDamageDealt (proc_types.go:166-175) so a landed hit that deals no damage rolls it too.
local MASK_MELEE_AUTO, MASK_MELEE_ABILITY, MASK_RANGED_AUTO, MASK_RANGED_ABILITY, MASK_HARMFUL_SPELL =
	0x4, 0x10, 0x40, 0x100, 0x10000
local function hasBit(mask, bit) return mask % (2 * bit) >= bit end

-- Procs per minute of one damage proc (Parse, linked by Items.Get: { avg, hits, equip, linked, ... }) of an item scored in
-- a slot of kind `kind` (Score.SlotKind), on `hits`, the landed hits of a model point by hand (Model.LandedHits' form): in
-- Score.SetValue the hits of the set the item is scored in (Score.LandedHitsOf: the model point with that set's weapons,
-- Advisor ctx.landedHitsFor); A.ModelProcRates passes the worn set's for an item it places in no set. Its rate comes from
-- Score.ProcRateSource (the measured rate, wowsims' override row, the DB2's), 0 procs for a proc with none (not priced,
-- U4 = (a)). L_h: a hand's landed hits per wall-clock second (Model.LandedHits:
-- the Survival weave's melee and shots, or the shots from range and the dives); S_h: the speed of the weapon in that hand at the hits' model
-- point, h.speed, 0 for the ranged hand with no ranged weapon (wowsims sim/core/attack.go:1255-1268 PPMProc and
-- sim/core/procs.go:183-227: the chance is ppm x the SwingSpeed of the hand that hits / 60, and the ranged entry of speed
-- 0 is skipped). In the set's own model point the hand a weapon sits in swings at the weapon's own speed
-- (Player.WeaponInputs takes item.speed).
-- A linked equip aura (proc.equip, proc.linked; wowsims spelldata.ProcTrigger, sim/core/spelldata/resolve_proc.go:32-68):
-- - its hits by its mask: 0x4 the main hand's and the off hand's white swings (the main hand's alone for an aura of the
--   main hand only, proc.mainHand: ProcTypeMask_1 0x20, whose off-hand melee bits wowsims drops whatever slot the item
--   sits in, sim/core/proc_types.go:222-224; raid-mode design 26.2), 0x10 the main hand's specials (Raptor
--   Strike, which goes off in a main-hand swing's place, Strider Kick, Mongoose Bite: Model.LandedHits), 0x40 the ranged
--   hand's swings (Auto Shots), 0x100 the ranged hand's specials (the shots and the dives) and, with 0x10000 (no
--   RequireDamageDealt), Serpent Sting's landed applications (the ranged hand's casts) unless the item keeps
--   RequireDamageDealt (PROC_OVERRIDES requireDamage);
-- - its rate (Score.ProcRateSource): MEASURED_PPM, per minute at S_h, the ranged specials at the main hand's speed for an
--   item with spellsAtMainHand when no ranged weapon is worn (PROC_OVERRIDES); else a procs-per-minute rate (wowsims'
--   override row, else the DB2's SpellProcsPerMinute), ppm x S_h / 60 a hit of each hand; else a chance of 1 to 99 (an
--   override row's, else the aura's ProcChance), that chance a hit, whatever the hand's speed (a fixed chance needs no
--   speed, so the dives roll it with no ranged weapon); else an aura wowsims rolls on every hit of its mask (proc.always,
--   ProcChanceAlways: raid-mode design 25.3), a chance of 100 a hit; else (the ProcChance column at 0, 100 or 101 and no
--   row: no stated rate, wowsims resolve_proc.go:222-266 settleProcRate) no proc;
-- - its internal cooldown icd (ProcCategoryRecovery, ms): a trigger of r procs a second with a dead time of icd after each
--   proc gives r / (1 + r x icd / 1000) (the mean gap is icd + 1 / r; my arithmetic). wowsims' override rows of a rate,
--   weapon_procs.go and spell_overrides.go's PPM and ProcChancePct, come in through Game/ProcData.lua's source
--   (Score.ProcRateSource), its ProcChanceAlways auras through Game/ProcData.lua's always; its other override fields (an
--   ICD, a hint) and its chances stated on an effect rather than the column (resolve_proc.go:182-207) are not reproduced
--   (raid-mode design A11).
-- Any other proc, a weapon's "Chance on hit" (ItemEffect TriggerType 2: no rate in the DB2, the Score.MEASURED_PPM
-- comment) and an equip proc that is not linked: the rate Score.ProcRateSource gives (MEASURED_PPM, else the linked
-- entry's wowsims override row; none: no proc), per minute at S_h, on the hits Parse reads from its text (proc.hits): "melee" the main and the off hand, "ranged" the
-- ranged slot, "any" all three, "weapon" the hand of the weapon carrying it and all three for a non-weapon item; each hand's
-- swings and specials, the ranged specials (the dives among them) at the main hand's speed for an item with
-- spellsAtMainHand when no ranged weapon is worn. So a melee weapon's "weapon" proc takes no ranged-type hit (EV-0119
-- lines 5-7), and a ranged weapon's takes the dives (the dive is the hunter's spell with ProcMaskRangedSpecial, wowsims
-- sim/hunter/summon_hawk.go:130-139; a weapon proc hears every landed hit of its hands, resolve_proc.go:95-111).
-- Serpent Sting's landed applications (the ranged hand's casts, Model.LandedHits) deal no damage. They roll a weapon's
-- "Chance on hit" proc (a proc without proc.equip: Parse's "Chance on hit:" lines, ItemEffect TriggerType 2) whose hits
-- include the ranged hand, at the ranged hand's speed: the game casts a chance-on-hit effect and a combat enchant off
-- every eligible weapon hit, a landed one without damage too (wowsims sim/core/spelldata/resolve_proc.go:95-110
-- WeaponProc: RequireDamageDealt = false; EV-0021 lines 32-33 and 49-50: non-damaging Rend, Concussion Blow and Sunder
-- Armor applications proc Dragon's Call 10847, a chance on hit, and Fiery Blaze, a combat enchant). An unlinked equip
-- proc keeps RequireDamageDealt (its mask is not known: wowsims' default, proc_types.go:87): no application rolls it.
-- Hits not given or an unknown hits value is an error.
function Score.ProcRate(item, kind, proc, hits)
	if hits == nil then error("HunterGearAdvisor: a proc scored without the landed hits of its set: " .. tostring(item.name), 2) end
	-- the hands a proc of Parse's hits rolls on (every proc but a linked equip aura, which its mask rules): an unknown hits
	-- value is an error whether or not the proc has a rate
	local rolls
	if not (proc.equip and proc.linked) then
		local own = Score.IsWeapon(item) and OWN_HAND[kind] or nil
		if proc.hits == "weapon" then
			rolls = own and ONE_HAND[own] or ROLLS.any
		else
			rolls = ROLLS[proc.hits]
			if not rolls then error("HunterGearAdvisor: a proc with unknown hits " .. tostring(proc.hits), 2) end
		end
	end
	local rate, rateKind = Score.ProcRateSource(item, proc)
	if rate == nil then return 0 end
	local over = Score.PROC_OVERRIDES[item.id] or NO_OVERRIDES
	local ranged = hits.ranged
	local rangedSpecialSpeed = ranged.speed
	if rangedSpecialSpeed == 0 and over.spellsAtMainHand then rangedSpecialSpeed = hits.mh.speed end
	if proc.equip and proc.linked then
		local mask = proc.mask
		local n, seconds = 0, 0 -- hits a second, and hits x their hand's speed
		local function add(count, speed)
			n = n + count
			seconds = seconds + atSpeed(count, speed)
		end
		if hasBit(mask, MASK_MELEE_AUTO) then
			add(hits.mh.swings, hits.mh.speed)
			if not proc.mainHand then add(hits.oh.swings, hits.oh.speed) end
		end
		if hasBit(mask, MASK_MELEE_ABILITY) then add(hits.mh.specials, hits.mh.speed) end
		if hasBit(mask, MASK_RANGED_AUTO) then add(ranged.swings, ranged.speed) end
		if hasBit(mask, MASK_RANGED_ABILITY) then
			add(ranged.specials, rangedSpecialSpeed)
			if hasBit(mask, MASK_HARMFUL_SPELL) and not over.requireDamage then add(ranged.casts, ranged.speed) end
		end
		local perMinute
		if (rateKind == "wowsims" and proc.ppm ~= nil and proc.ppm > 0) or rateKind == "measured" or rateKind == "db2ppm" then
			perMinute = rate * seconds
		else
			perMinute = 60 * rate / 100 * n
		end
		if proc.icd > 0 then
			local r = perMinute / 60
			perMinute = 60 * r / (1 + r * proc.icd / 1000)
		end
		return perMinute
	end
	local weapon = Score.IsWeapon(item)
	if rateKind ~= "measured" and rateKind ~= "wowsims" then
		error("HunterGearAdvisor: a chance-on-hit proc rated by the DB2 equip row: " .. tostring(item.name), 2)
	end
	local ppm = rate
	local seconds = 0
	for _, hand in ipairs(HANDS) do
		if rolls[hand] then
			local h = hits[hand]
			if hand == "ranged" then
				seconds = seconds + atSpeed(h.swings, h.speed) + atSpeed(h.specials, rangedSpecialSpeed)
			else
				seconds = seconds + atSpeed(h.swings + h.specials, h.speed)
			end
		end
	end
	if weapon and not proc.equip and rolls.ranged then
		seconds = seconds + atSpeed(ranged.casts, ranged.speed)
	end
	return ppm * seconds
end

-- The landed hits a set's procs roll on: ctx.landedHitsFor(set), the hits of the model point with the set's weapons
-- (Advisor). There every weapon in a hand swings at its own speed (Player.WeaponInputs), so a hand whose speed is not
-- the weapon's (hits of another set) is an error, as is a proc scored without ctx.landedHitsFor. A weapon in a hand
-- without a speed is a parse failure (every weapon's tooltip shows its speed, Player.weaponSpeedDPS): an error of its
-- own, raised before the speeds are compared. mhSkill, ohSkill: the set's hands' melee weapon skills (Score.MeleeSkills
-- of the set) when the caller has them, passed on to ctx.landedHitsFor; nil, nil: ctx.landedHitsFor takes them itself.
function Score.LandedHitsOf(set, ctx, mhSkill, ohSkill)
	local hitsFor = ctx.landedHitsFor
	if hitsFor == nil then error("HunterGearAdvisor: a proc scored without ctx.landedHitsFor (the landed hits of its set)", 2) end
	local hits = hitsFor(set, mhSkill, ohSkill)
	for i = 1, 3 do
		local slot, hand = SLOT_HAND[i][1], SLOT_HAND[i][2]
		local it = set[slot]
		if it and Score.IsWeapon(it) then
			if it.speed == nil then
				error(string.format("HunterGearAdvisor: a weapon without a parsed speed in the %s: %s", hand, tostring(it.name)), 2)
			end
			if hits[hand].speed ~= it.speed then
				error(string.format("HunterGearAdvisor: landed hits that swing the %s at %s s, its weapon %s at %s s: the hits of another set",
					hand, tostring(hits[hand].speed), tostring(it.name), tostring(it.speed)), 2)
			end
		end
	end
	return hits
end

-- The value of an item's damage procs in a slot of kind `kind`, on the landed hits `hits` (Score.ProcRate), as extra damage
-- (W.EXTRA_DPS): each proc's average damage x the hunter's damage multiplier (own) x the armor for a physical-school damage
-- (phys) or Curse of the Elements' multiplier for a magic one (coe), plus Gift of Arthas' flat damage on a physical one
-- (gift, after the armor and before the outcome: wowsims sim/core/spell_result.go:391-401, 928-936; raid-mode design 5.3),
-- x its outcome x its procs per second. Its outcome is the table of its DefenseType (proc.defense, Game/ProcData.lua;
-- 0, no DefenseType, by the school: the melee table for "physical", the spell table for "magic"; wowsims
-- sim/common/shared/shared_utils.go:76-119), hit x crit factor, without the crit factor when the spell cannot crit
-- (proc.crit false). opts.procOutcome: Model.ProcOutcomes at the model point with the main hand's skill of the set the
-- item is scored in (Score.SetValue: ctx.procOutcomeFor of the set's Score.MeleeSkills; raid-mode design 18.7), with its
-- phys, own, coe and gift (raid mode coe 1.10 and gift 8, levelling 1 and 0): the set's own hit and crit left out (as procs
-- leave out the set's other stats, raid-mode design A6).
-- A proc's damage over time (proc.dot, Game/ProcData.lua through Items.LinkProcs: tick, period, ticks, canCrit; raid-mode
-- design 17.3, U2 = (a), as wowsims prices it, sim/common/shared/shared_utils.go:724-819) adds, beside its direct damage
-- where the spell has one (proc.avg; a proc of a damage over time alone has none): its landed applications a second
-- (procs a second x the application's chance, land) x the ticks each deals before the next landed application ends it (a
-- landed application while the dot runs starts a full set of ticks, the unticked rest lost: sim/core/dot.go:93-105
-- Apply, Deactivate then Activate; Score.DotTicks) x the tick's damage: the tick x own x Curse of the Elements on a
-- magic school, plus Gift of Arthas on a physical one (spell_result.go:929-951, no periodic exception), no armor on a
-- physical tick (spell_resistances.go:25-28: "All physical dots (Bleeds) ignore armor"), x the tick's crit factor
-- (tickCrit) where the row states PERIODIC_CAN_CRIT (canCrit). The damage over time's table is the proc's (land, tickCrit:
-- Model.ProcOutcomes). A versus bonus of a creature type (proc.versus) multiplies the base damage, the direct and the tick,
-- by its mean over the mode's targets (Score.VersusFactor, opts.procOutcome's mode), before the multipliers and Gift of
-- Arthas; one of a creature family alone (Rot x2 against Aquatic) is left out (approximation DA3).
-- item.procs is every item record's (Parse:Lines gives it, empty for an item without a damage proc; Items.Get links each,
-- giving every proc its school, defense and crit). A proc without them, a proc with neither a direct damage nor a damage
-- over time, or one scored without opts.procOutcome, is an error.
local SCHOOLS = { physical = true, magic = true }

-- The ticks a proc's damage over time deals between two landed applications (raid-mode design 17.3, 25.3; approximation
-- DA1, where wowsims runs the applications as they come; my arithmetic): the k-th tick, T x k seconds after an
-- application, is dealt when no landed application comes before it. Past the proc's internal cooldown d (icd, ms: no proc
-- comes within it, wowsims' ProcTrigger ICD) the trigger fires as a Poisson stream of its rate without the dead time, r =
-- r_eff / (1 - r_eff x d) for the rate r_eff = r / (1 + r x d) Score.ProcRate gives (perMinute / 60), and lands at land:
-- E[n] = the sum over k = 1..N of 1 where T k <= d, else e^(-r x land x (T k - d)); with no cooldown the sum of
-- e^(-lambda k T), lambda = r_eff x land. So a cooldown as long as the dot or longer (228666: 45 s against 10 s) deals
-- every tick. dot: { period (ms), ticks }; perMinute: the proc's procs a minute (Score.ProcRate); land: its application's
-- chance (Model.ProcOutcomes land); icd: its internal cooldown in ms (0 for none). An icd that is not a number of 0 or
-- more, or a rate past the one the cooldown allows, is an error.
function Score.DotTicks(dot, perMinute, land, icd)
	if type(icd) ~= "number" or icd < 0 then error("HunterGearAdvisor: Score.DotTicks without an internal cooldown of 0 ms or more: " .. tostring(icd), 2) end
	local rEff, d = perMinute / 60, icd / 1000
	if rEff * d >= 1 then error("HunterGearAdvisor: Score.DotTicks: a rate of " .. perMinute .. " a minute past its cooldown's " .. icd .. " ms", 2) end
	local lambda = rEff / (1 - rEff * d) * land
	local T = dot.period / 1000
	local n = 0
	for k = 1, dot.ticks do
		local t = k * T
		if t <= d then n = n + 1 else n = n + math.exp(-lambda * (t - d)) end
	end
	return n
end

-- The mean factor of a proc's versus bonus over the mode's targets (raid-mode design 25.2): wowsims multiplies the proc's
-- base damage, direct and periodic, by its trigger's factor against a target of the bonus's mob types, before the
-- attacker's multipliers (sim/core/spell_result.go:442-445 CalcDamage, 464-467 CalcPeriodicDamage; versus_effects.go:18-24
-- Against), so over the mode's targets it is 1 + share x (factor - 1), share the targets of those types:
-- Model.TargetShare of each type summed (raid mode 1 for the boss's dragonkin, 0 for any other type; levelling
-- Model.AP_CREATURE_SHARE a type). proc.versus: { factor, types } (Game/ProcData.lua through Items.LinkProcs, wowsims'
-- VersusBonuses rows of a creature type); none, 1. A share of more than every target is an error.
function Score.VersusFactor(p, mode)
	local v = p.versus
	if v == nil then return 1 end
	local share = 0
	for _, ty in ipairs(v.types) do share = share + ns.Model.TargetShare(ty, mode) end
	if share > 1 then error("HunterGearAdvisor: a versus bonus whose types cover more than every target: " .. share, 2) end
	return 1 + share * (v.factor - 1)
end

-- The table of a proc's damage spell (Model.ProcOutcomes): its DefenseType's, by the school for DefenseType 0
local function procTable(item, p, outcomes)
	local t
	if p.defense == 0 then t = outcomes[0][p.school] else t = outcomes[p.defense] end
	if t == nil then error("HunterGearAdvisor: a proc of DefenseType " .. tostring(p.defense) .. ": " .. tostring(item.name), 3) end
	return t
end
Score.ProcTable = procTable

function Score.ProcValue(item, kind, W, hits, opts)
	local outcomes = opts.procOutcome
	if outcomes == nil then error("HunterGearAdvisor: a proc scored without ctx.procOutcome (Model.ProcOutcomes): " .. tostring(item.name), 2) end
	local v = 0
	for _, p in ipairs(item.procs) do
		if not SCHOOLS[p.school] or type(p.crit) ~= "boolean" then
			error("HunterGearAdvisor: a proc without its school or crit (Items.Get links every proc): " .. tostring(item.name), 2)
		end
		if p.avg == nil and p.dot == nil then
			error("HunterGearAdvisor: a proc with neither a direct damage nor a damage over time: " .. tostring(item.name), 2)
		end
		local t = procTable(item, p, outcomes)
		local physical = p.school == "physical"
		local perMinute = Score.ProcRate(item, kind, p, hits)
		local vs = Score.VersusFactor(p, outcomes.mode)
		-- the internal cooldown a linked equip aura states (Game/ProcData.lua icd; a chance on hit states none)
		local icd = (p.equip and p.linked) and p.icd or 0
		local each = 0 -- the damage of one proc
		if p.avg ~= nil then
			local outcome = t.hit * (p.crit and t.critMult or 1)
			each = (p.avg * vs * outcomes.own * (physical and outcomes.phys or outcomes.coe) + (physical and outcomes.gift or 0)) * outcome
		end
		if p.dot ~= nil then
			local tick = (p.dot.tick * vs * outcomes.own * (physical and 1 or outcomes.coe) + (physical and outcomes.gift or 0))
				* (p.dot.canCrit and t.tickCrit or 1)
			each = each + t.land * Score.DotTicks(p.dot, perMinute, t.land, icd) * tick
		end
		v = v + each * perMinute / 60 * W.EXTRA_DPS
	end
	return v
end

-- The skill stat of a ranged weapon's line, by weapon subclass (DB2 ItemSubClass, class 2: 2 Bows, 3 Guns,
-- 18 Crossbows); item stats SKILL_BOWS / SKILL_GUNS / SKILL_CROSSBOWS (Parse, Items.API_MAP).
Score.RANGED_SKILL = { [2] = "SKILL_BOWS", [3] = "SKILL_GUNS", [18] = "SKILL_CROSSBOWS" }
-- The skill stat of a melee weapon's line, by weapon subclass (DB2 ItemSubClass, class 2, as Game/Player.lua maps the
-- subclasses to skill lines: 0 Axes 44, 1 Two-Handed Axes 172, 4 Maces 54, 5 Two-Handed Maces 160, 6 Polearms 229, 7
-- Swords 43, 8 Two-Handed Swords 55, 10 Staves 136, 13 Fist Weapons 473, 15 Daggers 173); item stats SKILL_<LINE> (Parse,
-- GlobalStrings 59290-59309 TOOLTIP_ITEM_STAT_SKILL_*; Game/SetData.lua). Raid-mode W1 design 3.4.
Score.MELEE_SKILL = { [0] = "SKILL_AXES", [1] = "SKILL_2H_AXES", [4] = "SKILL_MACES", [5] = "SKILL_2H_MACES",
	[6] = "SKILL_POLEARMS", [7] = "SKILL_SWORDS", [8] = "SKILL_2H_SWORDS", [10] = "SKILL_STAVES", [13] = "SKILL_FIST",
	[15] = "SKILL_DAGGERS" }
-- every weapon skill stat, ranged and melee: priced on the whole set (Score.SetValue's ranged skill, the weapon run's melee
-- skills), never by a weight in ItemValue's stat loop or the set bonuses' loop
local SKILL_STAT = {}
for _, k in pairs(Score.RANGED_SKILL) do SKILL_STAT[k] = true end
for _, k in pairs(Score.MELEE_SKILL) do SKILL_STAT[k] = true end

-- The skill stat of a ranged weapon's line (nil: no item, or not a bow, gun or crossbow).
function Score.RangedSkillStat(item)
	return item ~= nil and item.classID == 2 and Score.RANGED_SKILL[item.subclassID] or nil
end
-- The skill stat of a melee weapon's line (nil: no item, no weapon, or a weapon of no melee line).
function Score.MeleeSkillStat(item)
	return item ~= nil and item.classID == 2 and Score.MELEE_SKILL[item.subclassID] or nil
end
-- The skill stat of the line of the set's ranged weapon.
local function rangedSkillKey(set) return Score.RangedSkillStat(set[S.RANGED]) end
-- The skill points of a bonus below the level's maximum (0 at or above it): what the crit suppression and the pet's crit
-- count (Model critSuppressor, petCritBase)
local function deficit(bonus) return math.max(0, -bonus) end

-- Value of an item in a slot, without hit (HIT and the ranged-only RANGED_HIT) and expertise (each is capped on the
-- whole set, Score.SetValue) and without its damage procs (priced on the landed hits of the set it is in,
-- Score.ProcValue in Score.SetValue).
-- kind: "armor", "ranged", "mh", "oh", "2h", "ammo".
-- noWeaponDPS: leave out the weapon-DPS terms (ranged / hand weapon DPS, a scope's flat damage and Beastslaying's);
-- SetValue passes it when ctx.weaponGain prices the set's weapons. Ammo stays linear either way.
-- Ranged weapon skill and the on-use buff are priced on the whole set (SetValue).
-- W: Model.Weights' table. A stat key it has no weight for has no damage value (the stat loops skip it); the
-- weights the scorer reads by name (AMMO_DPS, RANGED_DPS, MH_DPS, OH_DPS, TH_DPS, BEAST_SLAYING here; EXTRA_DPS in
-- ProcValue; HIT, RANGED_HIT, HIT_RANGED, HIT_MELEE, HIT_DW, HIT_DW_MH, SKILL_CRIT, SKILL_CRIT_NO_SHOTS, EXPERTISE,
-- EXPERTISE_PARRY in SetValue)
-- Model.Weights always
-- sets, so a missing one is an error where it is read.
function Score.ItemValue(item, kind, W, noWeaponDPS)
	local v = 0
	local st = item.stats
	for k, amount in pairs(st) do
		if k ~= "HIT" and k ~= "RANGED_HIT" and k ~= "SPELL_HIT" and k ~= "EXPERTISE" and k ~= "DPS" and k ~= "AMMO_DPS" and k ~= "RANGED_FLAT"
			and k ~= "BEAST_SLAYING" and not SKILL_STAT[k] then
			local w = W[k]
			if w then v = v + w * amount end
		end
	end
	local dps = st.DPS or 0
	-- Beastslaying (BEAST_SLAYING): flat damage per hit of the hunter's weapon strikes and shots (Model.Parts flat), the
	-- enchant of a melee weapon (spells 7786 / 13653: SpellEquippedItems rows 170492 / 175987, item class 2, melee
	-- subclass mask 189939), which Player.WeaponInputs reads from the main hand and the off hand. On an item of another
	-- kind, or a held-in-off-hand item, it is an error: nothing would read it
	local beast = st.BEAST_SLAYING or 0
	if beast ~= 0 and not (kind == "mh" or kind == "2h" or (kind == "oh" and item.equipLoc ~= "INVTYPE_HOLDABLE")) then
		error("HunterGearAdvisor: Beastslaying on an item that does not swing in melee: " .. tostring(item.name), 2)
	end
	if kind == "ammo" then
		v = v + W.AMMO_DPS * (st.AMMO_DPS or 0)
	elseif noWeaponDPS then
		-- the weapon's DPS and speed and its Beastslaying are in ctx.weaponGain
	elseif kind == "ranged" then
		v = v + W.RANGED_DPS * dps
		-- a scope adds flat damage per shot: per second that is N / weapon speed; a scope on an item without a
		-- parsed speed is an error (Player.weaponSpeedDPS: every weapon has one)
		if st.RANGED_FLAT then
			if not item.speed then error("HunterGearAdvisor: a scope's damage on a ranged item without a speed: " .. tostring(item.name), 2) end
			v = v + W.RANGED_DPS * st.RANGED_FLAT / item.speed
		end
	elseif kind == "mh" then
		v = v + W.MH_DPS * dps + W.BEAST_SLAYING * beast
	elseif kind == "oh" and item.equipLoc ~= "INVTYPE_HOLDABLE" then
		v = v + W.OH_DPS * dps + W.BEAST_SLAYING * beast
	elseif kind == "2h" then
		v = v + W.TH_DPS * dps + W.BEAST_SLAYING * beast
	end
	return v
end

local function slotKind(slot, item)
	if slot == S.RANGED then return "ranged" end
	if slot == S.AMMO then return "ammo" end
	if slot == S.MAINHAND then return isTwoHand(item) and "2h" or "mh" end
	if slot == S.OFFHAND then return "oh" end
	return "armor"
end
Score.SlotKind = slotKind

-- Dual wield as the damage model counts it (Model.Parts: dw = ohDPS > 0 and not twoH): a weapon with
-- DPS in the off hand (a held-in-off-hand item is not a weapon) and no two-hander in the main hand,
-- an empty main hand included.
local function dualWields(set)
	local mh, oh = set[S.MAINHAND], set[S.OFFHAND]
	return oh ~= nil and not isTwoHand(mh)
		and (oh.equipLoc == "INVTYPE_WEAPON" or oh.equipLoc == "INVTYPE_WEAPONOFFHAND")
		and (oh.stats.DPS or 0) > 0
end

-- Item set bonuses of a set ({ [slot] = item }). item.setID is the item's set (C_Item.GetItemInfo
-- return 16); data = setID -> { name, skill, skillRank, { n = pieces, stats = {...} } | { n, unknown = name } ... }
-- (Game/SetData.lua). A set counts its distinct item ids (two copies of one ring are one piece) and
-- gives every bonus with n <= that count. A set with a skill gives nothing unless hasSkill(skill, skillRank)
-- says the player's skill in that line reaches skillRank (the ItemSet row's RequiredSkill / RequiredSkillRank:
-- 421 Bloodvine Garb Tailoring 300, 441 Primal Batskin and 442 Blood Tiger Harness Leatherworking 300,
-- 444 The Darksoul Blacksmithing 300). Returns stats (the sum of the active bonuses that HGA counts) and
-- bySet: setID -> { count, known = data has the set, needsSkill / needsRank = the skill line and rank the
-- player lacks, counted = { n ... }, notCounted = { n ... } } (active bonuses, by piece count). A set missing
-- from data gives nothing; the tooltip says its bonuses are not counted.
-- setBonuses(set, data, hasSkill, withInfo): the same; without withInfo it returns stats alone (the scorer's
-- use), with the same sums in the same order.
local NO_BONUSES = {}
local function setBonuses(set, data, hasSkill, withInfo)
	local ids = {}
	for _, item in pairs(set) do
		local sid = item.setID
		if sid then
			if item.id == nil then error("HunterGearAdvisor: set piece without an item id: " .. tostring(item.name), 2) end
			ids[sid] = ids[sid] or {}
			ids[sid][item.id] = true
		end
	end
	local stats, bySet = {}, withInfo and {} or nil
	if next(ids) == nil then return stats, bySet end
	if not data then error("HunterGearAdvisor: a set piece is scored without set data (ctx.sets)", 2) end
	for sid, pieces in pairs(ids) do
		local count = 0
		for _ in pairs(pieces) do count = count + 1 end
		local def = data[sid]
		local info = withInfo and { count = count, known = def ~= nil, counted = {}, notCounted = {} } or nil
		local bonuses = def or NO_BONUSES
		if def and def.skill then
			if not def.skillRank then error("HunterGearAdvisor: set " .. sid .. " needs a profession without a rank (SetData)", 2) end
			if not hasSkill then error("HunterGearAdvisor: set " .. sid .. " needs a profession, scored without ctx.hasSkill", 2) end
			if not hasSkill(def.skill, def.skillRank) then
				if info then info.needsSkill, info.needsRank = def.skill, def.skillRank end
				bonuses = NO_BONUSES
			end
		end
		for _, b in ipairs(bonuses) do
			if b.n <= count then
				if b.stats then
					for k, amount in pairs(b.stats) do stats[k] = (stats[k] or 0) + amount end
					if info then info.counted[#info.counted + 1] = b.n end
				elseif info then
					info.notCounted[#info.notCounted + 1] = b.n
				end
			end
		end
		if info then bySet[sid] = info end
	end
	return stats, bySet
end
function Score.SetBonuses(set, data, hasSkill) return setBonuses(set, data, hasSkill, true) end

-- Skill points of one skill stat (key) that a set's items give plus those of bonusStats (the set's SetBonuses
-- stats).
local function skillBonusWith(set, key, bonusStats)
	local points = 0
	for _, item in pairs(set) do points = points + (item.stats[key] or 0) end
	return points + (bonusStats[key] or 0)
end

-- Skill points of one skill stat (key, e.g. "SKILL_GUNS") that a set's items and reached set bonuses give
-- (ctx.sets, ctx.hasSkill as in SetBonuses).
function Score.SkillBonus(set, key, sets, hasSkill)
	return skillBonusWith(set, key, (setBonuses(set, sets, hasSkill)))
end

-- Ranged weapon skill of a set, in points over the trained skill of the worn ranged weapon's line: the skill
-- bonuses of its items and reached set bonuses for the line of its own ranged weapon (a ring's +Bows counts
-- with a bow, not with a gun), plus its ranged weapon's skillOffset (the trained-skill difference of a ranged
-- weapon of another type than the worn one, Advisor rangedSkillPiece). bonusStats: the set's SetBonuses stats
-- when the caller has them (nil: SetBonuses runs here when the set's ranged weapon has a skill line).
local function skillPoints(set, ctx, bonusStats)
	local r = set[S.RANGED]
	local key = rangedSkillKey(set)
	local points = (r and r.skillOffset) or 0
	if key then
		points = points + skillBonusWith(set, key, bonusStats or (setBonuses(set, ctx.sets, ctx.hasSkill)))
	end
	return points
end

-- Each hand's melee weapon skill bonus over the level's maximum 5 x level for a set (raid-mode W1 design 3.4): the trained
-- skill of its weapon's line (ctx.meleeTrained(weapon): the line's live skill less the worn set's bonuses to it, less 5 x
-- level; Advisor A.State reads the line, Player.WeaponSkillLine) plus the set's items' and reached set bonuses' points for
-- that line (bonusStats: the set's SetBonuses stats when the caller has them); 0 for a hand without a weapon of a melee
-- line (an empty hand, an item held in the off hand: wowsims sim/core/weapon_skill.go:17-19; a weapon of no line HGA
-- knows, a fishing pole or a miscellaneous weapon, which wowsims looks up as WeaponSkillUnknown, an entry no skill is
-- ever set on, so 0 too: weapon_skill.go:21, 31-39, 81-84, character_constants.go:195-210). Returns the main hand's and
-- the off hand's. Both hands' points come from one pass over the set's items (skillBonusWith's sum, per hand).
function Score.MeleeSkills(set, ctx, bonusStats)
	local mhWeapon, ohWeapon = set[S.MAINHAND], set[S.OFFHAND]
	local mhKey, ohKey = Score.MeleeSkillStat(mhWeapon), Score.MeleeSkillStat(ohWeapon)
	if not mhKey and not ohKey then return 0, 0 end
	local trained = ctx.meleeTrained
	if trained == nil then error("HunterGearAdvisor: Score.MeleeSkills without ctx.meleeTrained (a line's trained skill)", 2) end
	bonusStats = bonusStats or (setBonuses(set, ctx.sets, ctx.hasSkill))
	local mhPoints, ohPoints = 0, 0
	for _, item in pairs(set) do
		local stats = item.stats
		if mhKey then mhPoints = mhPoints + (stats[mhKey] or 0) end
		if ohKey then ohPoints = ohPoints + (stats[ohKey] or 0) end
	end
	local mh = mhKey and trained(mhWeapon) + (mhPoints + (bonusStats[mhKey] or 0)) or 0
	local oh = ohKey and trained(ohWeapon) + (ohPoints + (bonusStats[ohKey] or 0)) or 0
	return mh, oh
end

-- The worn set's terms every set is measured against (its skill points, its survival / mana totals), kept on
-- ctx.wornTerms for the ctx.equipped, ctx.sets and ctx.hasSkill they were computed from, each filled on first
-- use. ctx.equipped is never changed in place: Player.Snapshot builds it whole, and every scorer copies a set
-- before it changes a slot (copySet); a ctx copy with another worn set (Score.Plan, Score.RowGains) keeps its
-- own terms.
local function wornTerms(ctx)
	local t = ctx.wornTerms
	if t and t.equipped == ctx.equipped and t.sets == ctx.sets and t.hasSkill == ctx.hasSkill then return t end
	t = { equipped = ctx.equipped, sets = ctx.sets, hasSkill = ctx.hasSkill }
	ctx.wornTerms = t
	return t
end
local function wornSkillPoints(ctx)
	local t = wornTerms(ctx)
	if t.skill == nil then t.skill = skillPoints(ctx.equipped, ctx) end
	return t.skill
end

-- The amounts of the stats the raid fight reads (ns.Model.FIGHT_KEYS) that a set's items and set bonuses (bonusStats) give
local function fightStats(set, bonusStats)
	local keys, out = ns.Model.FIGHT_KEYS, {}
	for _, item in pairs(set) do
		for k, a in pairs(item.stats) do
			if keys[k] then out[k] = (out[k] or 0) + a end
		end
	end
	for k, a in pairs(bonusStats) do
		if keys[k] then out[k] = (out[k] or 0) + a end
	end
	return out
end
-- A set's amounts of those stats less the worn set's (each key whose difference is not 0): the stats ctx.eventGain applies
-- at the model point (Score.SetValue, raid mode)
local function fightDelta(set, bonusStats, ctx)
	local t = wornTerms(ctx)
	if t.fight == nil then t.fight = fightStats(ctx.equipped, (setBonuses(ctx.equipped, ctx.sets, ctx.hasSkill))) end
	local d = fightStats(set, bonusStats)
	for k, a in pairs(t.fight) do d[k] = (d[k] or 0) - a end
	local out = {}
	for k, a in pairs(d) do
		if a ~= 0 then out[k] = a end
	end
	return out
end

-- set: { [slot] = item }. ctx: { equipped = the worn set, hitCap = %, baseHit = % from talents/racials,
-- dualWield, weaponGain, wornHit, wornMeleeHit, sets, hasSkill, skillBase, mobDiff, meleeTrained,
-- landedHitsFor, expertiseCap, parryCap }
-- ctx.expertiseCap = Model.MobAvoid of the model point's mobDiff (Advisor A.State), in %: the mob's dodge, past which
-- expertise lowers the tanking pet's parry alone; ctx.parryCap (Advisor A.State) = Model.PetParry of that mobDiff while
-- the pet tanks (Model.PetTanks of the mode), else ctx.expertiseCap: the expertise past which the model adds nothing (Model.Weights
-- EXPERTISE, EXPERTISE_PARRY); see the expertise below.
-- ctx.landedHitsFor(set, mhSkill, ohSkill) = the landed hits of the set's own model point, Model.LandedHits at the model
-- point with the set's weapon inputs (Advisor A.State: the model run ctx.weaponGain takes for that set): the hits the
-- set's procs roll on (Score.LandedHitsOf, Score.ProcRate). Each set's procs roll on its own hands' hits, as
-- ctx.weaponGain prices its own hands and HIT_DW counts its own dual wield (dualWields); the other inputs are the model
-- point's, the worn hit, haste and crit, as in ctx.weaponGain. mhSkill, ohSkill: as ctx.weaponGain's.
-- ctx.skillBase = the worn ranged weapon's line's trained skill (its live skill less the worn set's bonuses to it) less
-- 5 x level, 0 with no bow, gun or crossbow worn; ctx.mobDiff = the model point's mob level difference (Advisor A.State):
-- see the ranged weapon skill below. ctx.meleeTrained(weapon) = the trained skill of a melee weapon's line over 5 x level
-- (Score.MeleeSkills); ctx.wornMeleeHit = the worn main hand's skill hit, the model point's p.meleeHit (Advisor A.State):
-- see the melee weapon skill below.
-- ctx.weaponGain(set, mhSkill, ohSkill), when given, is the gain in the weights' unit (Model.Weights) of the set's ranged
-- weapon and hands (DPS at each weapon's own speed, a scope's flat damage, each hand at its melee weapon skill) over the
-- worn ones (Advisor builds it from the damage model, at the model point's attack speed); mhSkill, ohSkill are the set's
-- hands' skills, Score.MeleeSkills of the set, which setValue computes once a set and passes on (nil, nil: the function
-- takes them itself); the items then carry no weapon-DPS terms, and their other
-- stats, a weapon's attack speed enchant among them (Iron Counterweight's MELEE_HASTE), count in ItemValue's stat
-- loop as every item's do. Without it each weapon's DPS counts
-- linearly with W.RANGED_DPS / MH_DPS / OH_DPS / TH_DPS. ctx.wornHit is the hit (%) the model runs
-- every set's weapons at: the worn set's hit (Advisor passes the model's live hit).
-- ctx.sets = Game/SetData.lua's table, ctx.hasSkill(skillLine, rank) = whether the player's skill in that line
-- reaches rank (a set's profession requirement, SetBonuses): the set bonuses the set reaches count through W,
-- their hit with the items' hit before the cap.
-- Score.SetValue with the set's SetBonuses stats given (bonusStats). itemCache (nil: none) is a per-call item
-- cache: item -> { [slot] = its ItemValue in that slot, sec = its survival / mana stats as a list { key, amount,
-- ... } (secondaryTotals) }, for one W and ctx. A scorer that values many sets of the same items within one
-- call (Score.Plan, Score.BestHands, Score.RowGains) passes one table for that call; items do not change
-- during a call. An item's damage procs are no part of it: they roll on the landed hits of the set they are in
-- (Score.LandedHitsOf), which another set's hands change, so each set prices them on its own hits (Score.ProcValue).
-- USE_WEIGHT: the levelling mode's weight of a Use buff's attack power key, taken with the pet's attack power held
-- (Model.Weights W.AP_USE ...: a Use buff's attack power never reaches the pet, the user's answer O6)
local USE_WEIGHT = { AP = "AP_USE", RAP = "RAP_USE", MAP = "MAP_USE", STR = "STR_USE", AGI = "AGI_USE", INT = "INT_USE" }
local function setValue(set, W, ctx, bonusStats, itemCache)
	local weaponGain = ctx.weaponGain
	local noWeaponDPS = weaponGain ~= nil
	-- exp: the set's expertise, its items' and its set bonuses' (with a Use buff's on top, below); the model's expertise
	-- is the worn items' and set bonuses' alone (Player.Snapshot reads no live expertise), so a set's starts at 0
	local baseHit = ctx.baseHit
	if baseHit == nil then error("HunterGearAdvisor: Score.SetValue without ctx.baseHit (the hit of every set outside its items)", 2) end
	local v, hit, exp = 0, baseHit, 0
	-- the set's hands' melee weapon skills (Score.MeleeSkills; the melee weapon skill below), once a set: its procs' landed
	-- hits (Score.LandedHitsOf) and ctx.weaponGain take them
	local mhSkill, ohSkill = Score.MeleeSkills(set, ctx, bonusStats)
	-- rhit: the set's ranged-only hit (RANGED_HIT), its items' and its set bonuses'; outside its items a set has none (the
	-- worn set's is out of ctx.baseHit, Advisor A.State)
	local rhit = 0
	-- sh: the set's spell hit (SPELL_HIT), its items' and its set bonuses' (the base spell hit added below), priced below the
	-- trap's cap (spellHitValue)
	local sh = 0
	local hits, procOpts -- the set's landed hits and its procs' outcome, read for its first item with a damage proc
	for slot, item in pairs(set) do
		local iv
		if itemCache then
			local rec = itemCache[item]
			if not rec then rec = {}; itemCache[item] = rec end
			iv = rec[slot]
			if iv == nil then iv = Score.ItemValue(item, slotKind(slot, item), W, noWeaponDPS); rec[slot] = iv end
		else
			iv = Score.ItemValue(item, slotKind(slot, item), W, noWeaponDPS)
		end
		v = v + iv
		if item.procs[1] then
			if hits == nil then
				hits = Score.LandedHitsOf(set, ctx, mhSkill, ohSkill)
				-- the set's procs at its own main hand's entry of the tables (ctx.procOutcomeFor, Advisor A.State)
				local outcomeFor = ctx.procOutcomeFor
				if outcomeFor == nil then error("HunterGearAdvisor: a proc scored without ctx.procOutcomeFor (a set's proc outcome)", 2) end
				procOpts = { procOutcome = outcomeFor(mhSkill) }
			end
			v = v + Score.ProcValue(item, slotKind(slot, item), W, hits, procOpts)
		end
		hit = hit + (item.stats.HIT or 0)
		rhit = rhit + (item.stats.RANGED_HIT or 0)
		sh = sh + (item.stats.SPELL_HIT or 0)
		exp = exp + (item.stats.EXPERTISE or 0)
	end
	for k, amount in pairs(bonusStats) do
		if k == "HIT" then
			hit = hit + amount
		elseif k == "RANGED_HIT" then
			rhit = rhit + amount
		elseif k == "SPELL_HIT" then
			sh = sh + amount
		elseif k == "EXPERTISE" then
			exp = exp + amount
		elseif not SKILL_STAT[k] then
			local w = W[k]
			if w then v = v + w * amount end
		end
	end
	-- Ranged weapon skill by wowsims' attack table (raid-mode W1 design 3.3; ns.Model.SkillMiss, wowsims
	-- sim/core/target.go:561-597): a set with a bow, gun or crossbow has the skill bonus b = ctx.skillBase + skillPoints
	-- (its items' and reached set bonuses' points for its own ranged weapon's line, a piece's skillOffset among them) over
	-- the level's maximum 5 x level; the worn set's is bWorn = ctx.skillBase + its own points, the worn skill shown less
	-- 5 x level (ctx.equipped: the live sheet and the model price the worn set as it fights). Its hit is
	-- ns.Model.SkillHit(ctx.mobDiff, b), the
	-- shots' own hit against the level's skill, which meets the shots' cap on top of their other hit (hitValue, at
	-- W.HIT_RANGED): past it the hit adds nothing, and it never lowers dual-wield white misses. Its crit is the ranged
	-- hand's crit suppression, 0.2% a point below the maximum and nothing above it (Model critSuppressor), and the pet's
	-- ranged crit branch below the maximum (Model petCritBase): priced at W.SKILL_CRIT a point of deficit(b) =
	-- max(0, -b) against the worn set's (Model.Weights). The live hit and the live ranged crit are taken to leave the skill
	-- out, as wowsims models the sheet (the hit and crit percents apart from the hand's crit suppression,
	-- sim/core/character_sheet.go:13-44); the Forever UI source shows the sheet values as they come
	-- (Camelot/PaperDollFrameStats.lua PaperDollFrame_SetHitChance and PaperDollFrame_SetCritChance), so this is wowsims'
	-- model, not checked in game. The model runs at the worn skill (Advisor A.State: p.rangedSkill = bWorn, p.rangedHit =
	-- ns.Model.SkillHit(mobDiff, bWorn)).
	-- A set without a bow, gun or crossbow in the ranged slot (rangedSkillKey nil, the same rule as Player.WeaponInputs
	-- noShots: an empty slot, an item that is no weapon, a thrown weapon) casts no shot and its ranged hand is at bonus 0
	-- (wowsims sim/core/weapon_skill.go:17-19). Against the worn skill its crit gains deficit(bWorn), which reaches only
	-- what attacks without shots, the pet, the dive and the hawks: it counts at W.SKILL_CRIT_NO_SHOTS (Model.Weights),
	-- never at the shots' hit. Its shots' cap term (hitValue) keeps the worn skill's hit, so the skill change adds no
	-- shot's hit there: ctx.weaponGain takes every worn shot away at the model point (the worn skill's effect in it), and
	-- without ctx.weaponGain the set's lost shots count at W.RANGED_DPS alone.
	if ctx.equipped == nil then error("HunterGearAdvisor: Score.SetValue without ctx.equipped (the worn set)", 2) end
	local skillBase = ctx.skillBase
	if skillBase == nil then error("HunterGearAdvisor: Score.SetValue without ctx.skillBase (the worn ranged line's trained skill over 5 x level)", 2) end
	local mobDiff = ctx.mobDiff
	if mobDiff == nil then error("HunterGearAdvisor: Score.SetValue without ctx.mobDiff (the model point's mob level difference)", 2) end
	local bWorn = skillBase + wornSkillPoints(ctx)
	local sk -- the shots' skill hit against the level's skill: the set's own with shots, the worn set's without
	if rangedSkillKey(set) then
		local b = skillBase + skillPoints(set, ctx, bonusStats)
		sk = ns.Model.SkillHit(mobDiff, b)
		v = v + W.SKILL_CRIT * (deficit(bWorn) - deficit(b))
	else
		sk = ns.Model.SkillHit(mobDiff, bWorn)
		v = v + W.SKILL_CRIT_NO_SHOTS * deficit(bWorn)
	end
	-- Melee weapon skill by wowsims' attack table (raid-mode W1 design 3.4): each hand's skill bonus (mhSkill, ohSkill:
	-- Score.MeleeSkills, above). Its dodge, glance and crit suppression and the off hand's miss are priced by
	-- ctx.weaponGain, which runs the set's weapons at the set's skills (Advisor weaponModelFor); the main hand's skill hit
	-- skM = ns.Model.SkillHit(ctx.mobDiff, its bonus) through the melee consumers' cap (hitValue, at W.HIT_MELEE; the weapon
	-- run holds p.meleeHit at the worn set's). So without ctx.weaponGain a set whose melee skills differ from the worn
	-- set's is an error: nothing else prices them.
	if not weaponGain then
		local wornMH, wornOH = Score.MeleeSkills(ctx.equipped, ctx)
		if mhSkill ~= wornMH or ohSkill ~= wornOH then
			error("HunterGearAdvisor: Score.SetValue of a set whose melee weapon skill differs from the worn set's without ctx.weaponGain", 2)
		end
	end
	local skM, skO = ns.Model.SkillHit(mobDiff, mhSkill), ns.Model.SkillHit(mobDiff, ohSkill)
	if weaponGain then v = v + weaponGain(set, mhSkill, ohSkill) end
	local cap = ctx.hitCap
	if cap == nil then error("HunterGearAdvisor: Score.SetValue without ctx.hitCap", 2) end
	local dw = W.HIT_DW > 0 and ctx.dualWield and dualWields(set)
	-- room(x, n): hit x past the cap, up to n
	local function room(x, n) return math.min(math.max(x - cap, 0), n) end
	-- Dual wield: hit past the cap keeps lowering white misses, up to 19% more (Model.Weights HIT_DW), each hand's in its
	-- own room: the main hand's white misses reach 0 at h + skM = cap + 19 (its miss baseMiss + 19 - h - its skill hit,
	-- Model weaveParts), at W.HIT_DW_MH; the off hand's at h = cap + 19 - skO (its miss Model.SkillMiss(d, its bonus) + 19 -
	-- h, so its room past the cap is 19 - skO, my arithmetic with cap = Model.SkillMiss(d, 0)), at W.HIT_DW - W.HIT_DW_MH;
	-- its own skill hit never reaches the main hand. ctx.weaponGain runs the set's weapons through the model at
	-- ctx.wornHit and the worn main hand's ctx.wornMeleeHit, the off hand at the set's skill, so a dual-wield set's gain
	-- already holds the white misses there: the set adds only its hit past the cap beyond those, and a set that does not
	-- dual wield adds nothing. Without ctx.weaponGain a dual-wield set adds all of it (its skills are the worn set's, the
	-- error above). At skill 0 on both hands this is W.HIT_DW x (room(h, 19) - room(ctx.wornHit, 19)).
	local dwFromMH, dwFromOH = 0, 0
	if dw and weaponGain then
		if ctx.wornHit == nil then error("HunterGearAdvisor: ctx.weaponGain without ctx.wornHit prices dual-wield hit", 2) end
		if ctx.wornMeleeHit == nil then error("HunterGearAdvisor: ctx.weaponGain without ctx.wornMeleeHit prices dual-wield hit", 2) end
		dwFromMH = room(ctx.wornHit + ctx.wornMeleeHit, 19)
		dwFromOH = room(ctx.wornHit, 19 - skO)
	end
	-- h: the hit of every attack (items, set bonuses, the base, a Use buff). Every attack meets the cap with h, at
	-- W.HIT; the shots, the pet and the hawks meet it with the set's ranged-only hit rhit on top, the difference at
	-- W.RANGED_HIT (Model.Parts rangedGearHit); the shots meet it with the ranged weapon skill's hit sk on top of that (the
	-- set's skill against the level's, the worn skill's for a set without shots), the difference at W.HIT_RANGED. The
	-- consumers nest (Model.Weights: W.HIT >= W.RANGED_HIT >= W.HIT_RANGED), so the three terms add up to each attack's
	-- hit under its cap; the main hand's melee meets it with its skill hit skM on top of h, the difference at W.HIT_MELEE
	-- (W.HIT >= W.HIT_MELEE). No floor at 0% hit: the model's miss chance (Model.Parts missChance: base miss -
	-- hit, floored at 0 only) grows a point for every point of hit below 0 too. The melee and dual-wield parts take h and
	-- the hands' skill hits (rhit never reaches the hunter's melee).
	local function hitValue(h)
		local all = math.min(h, cap)
		local ranged = math.min(h + rhit, cap)
		local x = W.HIT * all + W.RANGED_HIT * (ranged - all) + W.HIT_RANGED * (math.min(h + rhit + sk, cap) - ranged)
			+ W.HIT_MELEE * (math.min(h + skM, cap) - all)
		if dw then
			x = x + W.HIT_DW_MH * (room(h + skM, 19) - dwFromMH) + (W.HIT_DW - W.HIT_DW_MH) * (room(h, 19 - skO) - dwFromOH)
		end
		return x
	end
	v = v + hitValue(hit)
	-- Spell hit lowers Immolation Trap's spell miss (Model weaveParts), floored at 0 at ctx.spellHitCap (Model.TrapHitCap):
	-- W.SPELL_HIT a point below it (Model.Weights), nothing past it; no floor below 0 spell hit (the miss grows there)
	local spellHitCap = ctx.spellHitCap
	if spellHitCap == nil then error("HunterGearAdvisor: Score.SetValue without ctx.spellHitCap (Model.TrapHitCap)", 2) end
	-- the base spell hit: the live spell hit less the worn set's SPELL_HIT (Advisor A.State)
	local baseSpellHit = ctx.baseSpellHit
	if baseSpellHit == nil then error("HunterGearAdvisor: Score.SetValue without ctx.baseSpellHit (the spell hit of every set outside its items)", 2) end
	sh = sh + baseSpellHit
	local function spellHitValue(x) return W.SPELL_HIT * math.min(x, spellHitCap) end
	v = v + spellHitValue(sh)
	-- Expertise lowers the mob's dodge and, while the pet tanks, its parry against the pet, each floored at 0 (Model.Parts:
	-- the hawks, the pet and the melee swings clamp the dodge at it, the pet its parry): the set's expertise e counts as
	-- W.EXPERTISE x min(e, ctx.expertiseCap), W.EXPERTISE the slope below the dodge, plus W.EXPERTISE_PARRY x the part of
	-- e between the dodge and ctx.parryCap, the slope of the tanking pet's parry alone (Model.Weights; ctx.parryCap is the
	-- dodge itself when the pet does not tank or the parry is no higher, so that part is 0). Past ctx.parryCap the model
	-- adds nothing. No floor at 0: below 0 the model's dodge grows a point for every point (max(0, avoid - e / 100)
	-- floors at 0 dodge only). The worn set's expertise is the model's (Player.Snapshot), so the worn set prices as the
	-- model point does.
	local expCap = ctx.expertiseCap
	if expCap == nil then error("HunterGearAdvisor: Score.SetValue without ctx.expertiseCap (the mob's dodge, Model.MobAvoid)", 2) end
	local parryCap = ctx.parryCap
	if parryCap == nil then error("HunterGearAdvisor: Score.SetValue without ctx.parryCap (the tanking pet's parry, Model.PetParry)", 2) end
	local function expertiseValue(e)
		return W.EXPERTISE * math.min(e, expCap) + W.EXPERTISE_PARRY * math.max(0, math.min(e - expCap, parryCap - expCap))
	end
	v = v + expertiseValue(exp)
	-- On-use stat buffs (item.use, Game/UseData.lua). A set counts one buff per Use spell (use.spell; Score.SetUses): two
	-- copies of one item, worn in both trinket slots, share one cooldown and one aura. The cooldown is the item's: Accursed
	-- Chalice 228078's Use is ItemXItemEffect 124552 -> ItemEffect 189379 (TriggerType 0, CoolDownMSec 120000,
	-- SpellCategoryID 1141, SpellID 461224; SpellCooldowns has no row for 461224), and the client keys an item's cooldown
	-- on its item id (C_Container.GetItemCooldown takes an itemID, Forever ContainerDocumentation.lua). The aura is the
	-- spell's own on the player (every effect of each UseData spell is APPLY_AURA on TARGET_UNIT_CASTER, Game/UseData.lua),
	-- the same spell 461224 from either copy. The burst trinket category (SpellCategory 1141) locks the others only for the
	-- buff's own duration, so two such buffs never overlap but each still runs its full uptime when used one after the
	-- other; tools/gen_use_data.py checks that the uptimes a set can wear add up to less than the whole time.
	-- Each buff's hit adds what it adds on top of the set's hit through hitValue (every attack's cap, the shots' cap with the
	-- skill's hit, the dual-wield part), its spell hit through spellHitValue and its expertise through expertiseValue (its
	-- caps; no UseData buff carries expertise in build 70888, tools/gen_use_data.py counts EXPERTISE as a damage key), for
	-- its uptime. The other stats, by the mode (ctx.mode, Advisor A.State: the model point's):
	-- - levelling: over the buff's average uptime, duration / cooldown (an estimate: it assumes every use goes into a
	--   fight), at W, the attack power keys (AP, RAP, MAP, STR, AGI, INT) at their Use weights (W.AP_USE ..., Model.Weights:
	--   the pet keeps its summon's attack power, the user's answer O6);
	-- - raid: through the raid fight (raid-mode design 6.8): ctx.useGain(set), the gain in the weights' unit of the set's Use
	--   buffs in their windows from 5 s at the model point (Model.Total with p.uses = Score.SetUses(set): each buff in the
	--   states it is up in, Model.ApplyStats, the pet's attack power held; approximation A6, the set's other stats left out),
	--   and the uptime of each buff for its hit, spell hit and expertise, ctx.useUptime(set)[spell], its share of the
	--   fight's weighted time (Model.UseUptimes).
	-- Any other mode is an error.
	-- Raid mode also prices the change of the fight's consumables' events the set's stats make (raid-mode design 25.1): the
	-- weights hold the model point's events (Model.Weights), so W x the stats leaves out a mana potion or a rune that fits or
	-- not with the set's pool, regen or spend; ctx.eventGain(stats) (Advisor: Model.EventGain at the model point with stats
	-- applied, against its events, in the weights' unit) takes the set's amounts of the stats the fight reads less the worn
	-- set's (fightDelta: none for the worn set), the jump of the fight's damage across such a threshold. The Use buffs and the
	-- weapons run the fight whole (ctx.useGain, ctx.weaponGain), their events with them; hit, spell hit and expertise, priced
	-- by their caps, stay out of it (approximation A6, as the set's other cross terms).
	local mode = ctx.mode
	if mode == "raid" then
		local useGain, useUptime, eventGain = ctx.useGain, ctx.useUptime, ctx.eventGain
		if useGain == nil then error("HunterGearAdvisor: Score.SetValue in raid mode without ctx.useGain (the Use buffs in the raid fight)", 2) end
		if useUptime == nil then error("HunterGearAdvisor: Score.SetValue in raid mode without ctx.useUptime (the Use buffs' share of the raid fight)", 2) end
		if eventGain == nil then error("HunterGearAdvisor: Score.SetValue in raid mode without ctx.eventGain (the change of the fight's events)", 2) end
		v = v + eventGain(fightDelta(set, bonusStats, ctx))
		local uses = Score.SetUses(set)
		if uses[1] then
			v = v + useGain(set)
			local shares = useUptime(set)
			for _, use in ipairs(uses) do
				local uptime = shares[use.spell]
				if uptime == nil then error("HunterGearAdvisor: ctx.useUptime without the Use spell " .. tostring(use.spell), 2) end
				for k, amount in pairs(use.stats) do
					if k == "HIT" then
						v = v + uptime * (hitValue(hit + amount) - hitValue(hit))
					elseif k == "SPELL_HIT" then
						v = v + uptime * (spellHitValue(sh + amount) - spellHitValue(sh))
					elseif k == "EXPERTISE" then
						v = v + uptime * (expertiseValue(exp + amount) - expertiseValue(exp))
					end
				end
			end
		end
	elseif mode == "level" then
		local usedSpells = {}
		for _, item in pairs(set) do
			local use = item.use
			if use and not usedSpells[use.spell] then
				usedSpells[use.spell] = true
				local uptime = use.duration / use.cooldown
				for k, amount in pairs(use.stats) do
					if k == "HIT" then
						v = v + uptime * (hitValue(hit + amount) - hitValue(hit))
					elseif k == "SPELL_HIT" then
						v = v + uptime * (spellHitValue(sh + amount) - spellHitValue(sh))
					elseif k == "EXPERTISE" then
						v = v + uptime * (expertiseValue(exp + amount) - expertiseValue(exp))
					elseif USE_WEIGHT[k] then
						local w = W[USE_WEIGHT[k]]
						if w == nil then error("HunterGearAdvisor: Score.SetValue of a Use buff's " .. k .. " without W." .. USE_WEIGHT[k], 2) end
						v = v + uptime * w * amount
					else
						local w = W[k]
						if w then v = v + uptime * w * amount end
					end
				end
			end
		end
	else
		error("HunterGearAdvisor: Score.SetValue without ctx.mode 'raid' or 'level': " .. tostring(mode), 2)
	end
	return v
end

function Score.SetValue(set, W, ctx)
	return setValue(set, W, ctx, (setBonuses(set, ctx.sets, ctx.hasSkill)))
end

-- The keys of a Use buff that levelling prices at 0 (setValue): the mana stats, which levelling weighs at 0 (Model.Weights;
-- its tie-break, Score.Secondary, reads the mana of the items' own stats, not of a Use buff), and the survival stats and
-- spell power, which no damage input reads (Model.ApplyStats)
local LEVEL_UNPRICED = { SPI = true, MP5 = true, MANA = true, STA = true, ARMOR = true, HEALTH = true, HP5 = true, DEFENSE = true,
	DODGE = true, PARRY = true, BLOCK = true, SPELL_POWER = true }
-- Whether the valuation of the mode (ctx.mode) prices a Use buff (item.use, Game/UseData.lua): raid mode every one (the
-- raid fight prices the mana stats too, raid-mode design 6.8, 7.7), levelling one with a stat besides LEVEL_UNPRICED's
-- (Serenity Field 272439's Spirit alone is priced at 0 there). Any other mode is an error.
function Score.UsePriced(use, mode)
	if mode == "raid" then return true end
	if mode ~= "level" then error("HunterGearAdvisor: Score.UsePriced without the mode 'raid' or 'level': " .. tostring(mode), 2) end
	for k in pairs(use.stats) do
		if not LEVEL_UNPRICED[k] then return true end
	end
	return false
end

-- The Use buffs of a set ({ [slot] = item }) in the order they fire at one instant in the raid fight (Model.UseUptimes,
-- Model.Fight; raid-mode design 6.3), one per Use spell (two copies of one item share one cooldown and one aura,
-- Score.SetValue): a list of item.use entries (Game/UseData.lua). The order is wowsims': it registers an item's Use
-- cooldown as it walks the equipment array (sim/core/item_effects.go:107-120 applyItemEffects over Equipment, an array
-- [NumItemSlots]Item by ItemSlot, sim/core/database.go:305; sim/common/shared/shared_utils.go:1236-1257
-- NewSimpleStatActive -> RegisterTemporaryStatsOnUseCD), each appended to its major cooldowns
-- (sim/core/major_cooldown.go:236-268 AddMajorCooldown), and fires the ready ones by ready time, then priority (0 for an
-- item's), then that order (a stable sort, major_cooldown.go:414-421). USE_ORDER: the client's inventory slot (Score.SLOT)
-- to wowsims' ItemSlot (proto/common.proto:466-484: head 0, neck 1, shoulder 2, back 3, chest 4, wrist 5, hands 6, waist
-- 7, legs 8, feet 9, the fingers 10 and 11, the trinkets 12 and 13, main hand 14, off hand 15, ranged 16), so the legs
-- (Cloudkeeper Legplates 14554) fire before trinket 13 and trinket 13 before 14. A Use item in another slot is an error.
local USE_ORDER = {
	[S.HEAD] = 0, [S.NECK] = 1, [S.SHOULDER] = 2, [S.BACK] = 3, [S.CHEST] = 4, [S.WRIST] = 5, [S.HANDS] = 6, [S.WAIST] = 7,
	[S.LEGS] = 8, [S.FEET] = 9, [S.FINGER1] = 10, [S.FINGER2] = 11, [S.TRINKET1] = 12, [S.TRINKET2] = 13, [S.MAINHAND] = 14,
	[S.OFFHAND] = 15, [S.RANGED] = 16,
}
function Score.SetUses(set)
	local slots = {}
	for slot, item in pairs(set) do
		if item.use then
			if USE_ORDER[slot] == nil then
				error("HunterGearAdvisor: Score.SetUses: a Use item in slot " .. tostring(slot) .. ", no slot of wowsims' equipment", 2)
			end
			slots[#slots + 1] = slot
		end
	end
	table.sort(slots, function(a, b) return USE_ORDER[a] < USE_ORDER[b] end)
	local uses, seen = {}, {}
	for _, slot in ipairs(slots) do
		local use = set[slot].use
		if not seen[use.spell] then
			seen[use.spell] = true
			uses[#uses + 1] = use
		end
	end
	return uses
end

local function copySet(set)
	local c = {}
	for k, v in pairs(set) do c[k] = v end
	return c
end
Score.CopySet = copySet

-- Damage always decides; survival and mana only when damage is equal (user, 2026-11-12:
-- "урон всегда приоритет"). EPS absorbs float noise between equal stat sums.
Score.EPS = 1e-6
function Score.Better(dmgA, secA, dmgB, secB)
	if dmgA > dmgB + Score.EPS then return true end
	if dmgA < dmgB - Score.EPS then return false end
	return (secA or 0) > (secB or 0) + Score.EPS
end

local SECONDARY_KEYS = { "STA", "HEALTH", "ARMOR", "INT", "MANA", "MP5", "SPI" }
-- The items' survival / mana stats plus those of the set bonuses the set reaches (ctx.sets,
-- ctx.hasSkill as in SetValue; bonusStats: the set's SetBonuses stats when the caller has them; itemCache: as
-- in setValue, or nil). t holds exactly SECONDARY_KEYS, so an item's stat counts when t has its key.
local function secondaryTotals(set, ctx, bonusStats, itemCache)
	local t = { STA = 0, HEALTH = 0, ARMOR = 0, INT = 0, MANA = 0, MP5 = 0, SPI = 0 } -- SECONDARY_KEYS
	for _, item in pairs(set) do
		local st = item.stats
		if itemCache then
			local rec = itemCache[item]
			if not rec then rec = {}; itemCache[item] = rec end
			local list = rec.sec
			if not list then
				list = {}
				for k, amount in pairs(st) do
					if t[k] then list[#list + 1] = k; list[#list + 1] = amount end
				end
				rec.sec = list
			end
			for i = 1, #list, 2 do
				local k = list[i]
				t[k] = t[k] + list[i + 1]
			end
		else
			for k, amount in pairs(st) do
				if t[k] then t[k] = t[k] + amount end
			end
		end
	end
	local bonus = bonusStats or setBonuses(set, ctx.sets, ctx.hasSkill)
	for _, k in ipairs(SECONDARY_KEYS) do t[k] = t[k] + (bonus[k] or 0) end
	return t
end

local function armorReduction(armor, level)
	local dr = armor / (armor + 400 + 85 * level) -- Classic formula (Forever's own is not published)
	return math.max(0, math.min(0.75, dr))
end

-- Survival and mana of a set compared with the worn set, as % of the character's pools
-- (user: the balance between survival and mana; 400 mana beats 100 HP at 2133 HP / 1725 mana).
-- Returns total %, health % (armor counted as effective health), mana %.
-- ctx.pools = { hp, mana, armor, level }, ctx.secondaryRates = Model.SecondaryRates(...)
-- bonusStats: the set's SetBonuses stats when the caller has them; itemCache: as in setValue, or nil.
-- By the mode (ctx.mode, Advisor A.State): levelling as above, the armor against a mob of the hunter's level
-- (pools.level); raid mode (raid-mode design 7.9) without the mana part, its stats priced in the damage (Model.Weights'
-- raid W.INT, W.MP5, W.SPI, W.MANA through Score.ItemValue), and the armor against the raid boss's hits, level 63
-- (Model.RAID_BOSS_LEVEL; wowsims sim/core/spell_resistances.go:147, 400 + 85 x the attacker's level). Any other mode is
-- an error.
local function secondary(set, ctx, bonusStats, itemCache)
	local pools, rates = ctx.pools, ctx.secondaryRates
	if not pools or not rates or not pools.hp or pools.hp <= 0 then return 0, 0, 0 end
	local raid
	if ctx.mode == "raid" then
		raid = true
	elseif ctx.mode == "level" then
		raid = false
	else
		error("HunterGearAdvisor: Score.Secondary without ctx.mode 'raid' or 'level': " .. tostring(ctx.mode), 2)
	end
	local a = secondaryTotals(set, ctx, bonusStats, itemCache)
	local worn = wornTerms(ctx)
	if worn.secondary == nil then worn.secondary = secondaryTotals(ctx.equipped, ctx) end
	local b = worn.secondary
	local dHP = rates.hpPerSta * (a.STA - b.STA) + rates.hpMult * (a.HEALTH - b.HEALTH)
	local arm0 = pools.armor or 0
	local attacker = raid and ns.Model.RAID_BOSS_LEVEL or pools.level or 1
	local dr0 = armorReduction(arm0, attacker)
	local dr1 = armorReduction(math.max(0, arm0 + a.ARMOR - b.ARMOR), attacker)
	local hpPct = ((pools.hp + dHP) / (1 - dr1)) / (pools.hp / (1 - dr0)) * 100 - 100
	local manaPct = 0
	if not raid and pools.mana and pools.mana > 0 then
		local dMana = rates.manaPerInt * (a.INT - b.INT) + (a.MANA - b.MANA)
			+ rates.manaPerMp5 * (a.MP5 - b.MP5) + rates.manaPerSpi * (a.SPI - b.SPI)
		manaPct = dMana / pools.mana * 100
	end
	return hpPct + manaPct, hpPct, manaPct
end
function Score.Secondary(set, ctx) return secondary(set, ctx) end

-- Score.SetValue and Score.Secondary of one set on one SetBonuses call: the value under ctx, survival / mana
-- against the worn set of secCtx (ctx itself, or a copy of it with another worn set: Score.Plan, Score.RowGains);
-- itemCache as in setValue. Returns value, then Secondary's total %, health %, mana %.
local function valueAndSecondary(set, W, ctx, secCtx, itemCache)
	local bonusStats = setBonuses(set, ctx.sets, ctx.hasSkill)
	return setValue(set, W, ctx, bonusStats, itemCache), secondary(set, secCtx, bonusStats, itemCache)
end

-- Two items that cannot be worn together: one of them unique-equipped and both the same item id. Every item record has
-- its id (Items.Get: C_Item.GetItemInfoInstant's itemID), so a unique item without one is an error.
local function uniqueClash(a, b)
	if a == nil or b == nil or not (a.uniqueEquipped or b.uniqueEquipped) then return false end
	if a.id == nil or b.id == nil then
		error("HunterGearAdvisor: a unique-equipped item without an item id: " .. tostring((a.id == nil and a or b).name), 2)
	end
	return a.id == b.id
end

-- Whether a main hand / off hand pair can be worn: a main hand alone, a main hand that is no two-hander with
-- another item that fits the off hand, or an off-hand item alone (both hands empty is no configuration). Two
-- copies of a unique-equipped weapon cannot be worn (13 such one-handers in Forever's ItemSparse); the same
-- rule as for rings and trinkets. eachHands enumerates exactly these pairs.
local function handsLegal(mh, oh, dualWield)
	if mh == nil then return oh ~= nil and canOH(oh, dualWield) end
	if not canMH(mh) then return false end
	if oh == nil then return true end
	return not isTwoHand(mh) and oh ~= mh and canOH(oh, dualWield) and not uniqueClash(mh, oh)
end

-- Best main hand / off hand configuration that includes `cand` (or any configuration
-- when cand is nil). Pool = extra weapons (bags) besides the currently equipped hands.
-- Returns { mh = item|nil, oh = item|nil, value = setValue, set = full set } or nil.
-- Calls fn(set) for every legal main hand / off hand configuration (handsLegal) over the hands of
-- `equipped` plus `pool` (and `cand` first, when given; then only configurations that include it).
local function eachHands(cand, equipped, pool, dualWield, fn)
	local base = copySet(equipped)
	base[S.MAINHAND], base[S.OFFHAND] = nil, nil
	local items = {}
	local seen = {}
	local function add(it)
		if it and not seen[it] then seen[it] = true; items[#items + 1] = it end
	end
	add(cand)
	add(equipped[S.MAINHAND])
	add(equipped[S.OFFHAND])
	for _, it in ipairs(pool or {}) do add(it) end

	local function try(mh, oh)
		if cand and mh ~= cand and oh ~= cand then return end
		if not handsLegal(mh, oh, dualWield) then return end
		local set = copySet(base)
		set[S.MAINHAND], set[S.OFFHAND] = mh, oh
		fn(set, mh, oh)
	end
	for _, mh in ipairs(items) do
		if canMH(mh) then
			try(mh, nil)
			for _, oh in ipairs(items) do try(mh, oh) end
		end
	end
	for _, oh in ipairs(items) do try(nil, oh) end
end

function Score.BestHands(cand, equipped, pool, W, ctx)
	local best
	local itemCache = {}
	eachHands(cand, equipped, pool, ctx.dualWield, function(set, mh, oh)
		local v, sec = valueAndSecondary(set, W, ctx, ctx, itemCache)
		if not best or Score.Better(v, sec, best.value, best.sec) then
			best = { mh = mh, oh = oh, value = v, sec = sec, set = set }
		end
	end)
	return best
end

-- Slots a non-weapon candidate can go into, given the set it joins (nil: no slot). A
-- unique-equipped item can only replace its own worn copy.
local function candidateSlots(cand, set)
	local loc = cand.equipLoc
	local slots
	if loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT" then
		slots = { S.RANGED }
	elseif loc == "INVTYPE_AMMO" then
		slots = { S.AMMO }
	else
		slots = Score.ARMOR_SLOTS[loc]
	end
	if not slots then return nil end
	if cand.uniqueEquipped and #slots > 1 then
		for _, slot in ipairs(slots) do
			local e = set[slot]
			if uniqueClash(e, cand) then return { slot } end
		end
	end
	return slots
end

local function weaponResult(pick, cand, eq, current)
	local hand
	if pick.mh == cand then hand = isTwoHand(cand) and "2h" or "mh" else hand = "oh" end
	return {
		delta = pick.value - current, sec = pick.sec, current = current, hand = hand,
		mh = pick.mh, oh = pick.oh, slot = hand == "oh" and S.OFFHAND or S.MAINHAND,
		swapFrom2H = isTwoHand(eq[S.MAINHAND]) and not isTwoHand(cand),
		swapTo2H = isTwoHand(cand) and not isTwoHand(eq[S.MAINHAND]),
		newSet = pick.set,
	}
end

-- Evaluates a candidate item against the equipped set.
-- ctx: { equipped = set, pool = {bag weapons}, dualWield, hitCap, baseHit, landedHitsFor, ... }
-- (Score.SetValue)
-- Returns { delta, slot, hand = "mh"|"oh"|"2h"|nil, mh, oh, swapFrom2H, newSet, betterOther }
function Score.Evaluate(cand, W, ctx)
	local eq = ctx.equipped
	local current = Score.SetValue(eq, W, ctx)
	local loc = cand.equipLoc

	if WEAPON_LOCS[loc] then
		if loc == "INVTYPE_SHIELD" then return nil end
		-- Best hands over everything available (bags + this item). The item is credited with
		-- that gain only when it is part of that best setup; otherwise it is judged on its own,
		-- next to the hands worn now (so junk does not borrow a good bag weapon's gain).
		local poolAll = { cand }
		for _, it in ipairs(ctx.pool or {}) do poolAll[#poolAll + 1] = it end
		local bestAll = Score.BestHands(nil, eq, poolAll, W, ctx)
		local pick, other
		if bestAll and (bestAll.mh == cand or bestAll.oh == cand) then
			pick = bestAll
		else
			-- with a 2H worn, a one-hander only makes sense as half of a pair (user: "which two
			-- one-handers instead of my two-hander"), so its own setup takes the best bag partner;
			-- otherwise it is judged next to the hands worn now
			local ownPool = {}
			if isTwoHand(eq[S.MAINHAND]) and not isTwoHand(cand) then ownPool = ctx.pool or {} end
			pick = Score.BestHands(cand, eq, ownPool, W, ctx)
			-- name a better setup only when it is not just the hands worn now and it beats them: any damage gain, or equal
			-- damage with more survival/mana (Score.Better; the user's rule, any damage gain gets the checkmark, no threshold)
			if pick and bestAll and (bestAll.mh ~= eq[S.MAINHAND] or bestAll.oh ~= eq[S.OFFHAND])
				and Score.Better(bestAll.value, bestAll.sec, current, 0) then
				other = bestAll
			end
		end
		if not pick then return nil end
		local res = weaponResult(pick, cand, eq, current)
		if other then res.betterOther = { mh = other.mh, oh = other.oh, delta = other.value - current, sec = other.sec } end
		return res
	end

	local slots = candidateSlots(cand, eq)
	if not slots then return nil end

	local best
	for _, slot in ipairs(slots) do
		local set = copySet(eq)
		set[slot] = cand
		local v, sec = valueAndSecondary(set, W, ctx, ctx)
		if not best or Score.Better(v, sec, best.value, best.sec) then best = { slot = slot, value = v, sec = sec, set = set } end
	end
	return { delta = best.value - current, sec = best.sec, current = current, slot = best.slot, newSet = best.set }
end

-- Rows of a plan, in slot order: { slot, new = item|nil, old = item|nil }. new == nil means the
-- slot gets emptied (the off hand when a two-hander goes into the main hand, or the main hand
-- when only an off-hand item beats the worn two-hander).
local PLAN_SLOT_ORDER = { S.HEAD, S.NECK, S.SHOULDER, S.BACK, S.CHEST, S.WRIST, S.HANDS, S.WAIST, S.LEGS,
	S.FEET, S.FINGER1, S.FINGER2, S.TRINKET1, S.TRINKET2, S.MAINHAND, S.OFFHAND, S.RANGED, S.AMMO }
function Score.PlanRows(equipped, target)
	local rows = {}
	for _, slot in ipairs(PLAN_SLOT_ORDER) do
		if target[slot] ~= equipped[slot] then
			rows[#rows + 1] = { slot = slot, new = target[slot], old = equipped[slot] }
		end
	end
	return rows
end

local function isHands(slot) return slot == S.MAINHAND or slot == S.OFFHAND end
local PAIRS = { { S.FINGER1, S.FINGER2 }, { S.TRINKET1, S.TRINKET2 } }

-- What each row adds inside the plan: the plan versus the plan with that row put back as worn
-- (leave one out). Rows that only make sense together form one unit and are put back together:
-- both hands always (a two-hander, a pair, a weapon moved to the other hand), and a ring or
-- trinket pair when putting one slot back would wear two copies of a unique item. The gain goes
-- on the unit's first row that puts an item on; the unit's other row is marked pairPart.
-- row.unit = "hands" / "pair" for rows of such units. Sets row.gain = { delta, sec, secHp,
-- secMana, verdict }. Survival/mana is measured the way Score.Plan measures it (each set
-- against the worn set, then the difference), so a row's sign agrees with the plan's choice.
function Score.RowGains(equipped, target, rows, W, ctx)
	local base = copySet(ctx)
	base.equipped = equipped
	local itemCache = {}
	local full, fullSec, fullHp, fullMana = valueAndSecondary(target, W, ctx, base, itemCache)
	local pairOf = {}
	for _, p in ipairs(PAIRS) do
		local a, b = p[1], p[2]
		if (target[a] ~= equipped[a] and uniqueClash(equipped[a], target[b]))
			or (target[b] ~= equipped[b] and uniqueClash(equipped[b], target[a])) then
			pairOf[a], pairOf[b] = p, p
		end
	end
	local function unitOf(slot)
		if isHands(slot) then return "hands", { S.MAINHAND, S.OFFHAND }, "hands" end
		local p = pairOf[slot]
		if p then return "pair" .. p[1], p, "pair" end
		return slot, { slot }, nil
	end
	local carrier = {}
	for _, row in ipairs(rows) do
		local key = unitOf(row.slot)
		local c = carrier[key]
		if not c or (c.new == nil and row.new ~= nil) then carrier[key] = row end
	end
	for _, row in ipairs(rows) do
		local key, slots, kind = unitOf(row.slot)
		row.unit = kind
		if carrier[key] ~= row then
			row.pairPart = true
		else
			local reverted = copySet(target)
			for _, s in ipairs(slots) do reverted[s] = equipped[s] end
			local rVal, rSec, rHp, rMana = valueAndSecondary(reverted, W, ctx, base, itemCache)
			local delta = full - rVal
			local sec = fullSec - rSec
			row.gain = { delta = delta, sec = sec, secHp = fullHp - rHp, secMana = fullMana - rMana,
				verdict = Score.Verdict(delta, sec) }
		end
	end
end

-- Rings and trinkets have two equal slots: a worn one that ended up in the other slot of its
-- pair goes back to its own slot (the same set, without a pointless move: the greedy can put a worn ring
-- it took off into the other slot of its pair, and a single-slot leave-one-out of such a plan would wear
-- one ring twice).
local function normalizePairs(equipped, set)
	for _, p in ipairs(PAIRS) do
		local a, b = p[1], p[2]
		if (set[b] ~= nil and set[b] == equipped[a]) or (set[a] ~= nil and set[a] == equipped[b]) then
			set[a], set[b] = set[b], set[a]
		end
	end
	return set
end

-- Items in best-first order by (value, sec) (Score.Better), the first of equal ones first. A selection by
-- scanning, not table.sort: Better's EPS tolerance is not a strict weak order.
local function bestFirst(list)
	local left, out = {}, {}
	for i, x in ipairs(list) do left[i] = x end
	while #left > 0 do
		local bi = 1
		for k = 2, #left do
			if Score.Better(left[k].value, left[k].sec, left[bi].value, left[bi].sec) then bi = k end
		end
		out[#out + 1] = table.remove(left, bi)
	end
	return out
end

-- Swap plan for the banner: the set reached by putting on bag items. Greedy: the biggest single
-- gain first (damage, then survival/mana at equal damage), then again from the new set, until
-- nothing is a gain. Re-evaluating after every step keeps the hit cap, the two ring / trinket
-- slots and the hand pairing right. cands = bag pieces that can be worn now (the caller filters
-- level, proficiency, ammo and quivers). Returns the target set { [slot] = item } and the kinds of the
-- steps the plan took, in order ("item", "hands" or "set").
--
-- A step puts on one item (each slot it fits), one hands configuration, or pieces of one item set
-- together: a set bonus adds value only at its piece count (SetBonuses), so two bag pieces of a set can
-- each be a loss alone and a gain together, and single swaps never reach the pair. The pieces of a set are
-- its pieces off the body (bag pieces and worn ones the plan took off) whose item ids the current set does
-- not wear. Its armor pieces are placed in best-alone order: each in the slot where it is best alone, by the
-- same (value, sec) measure, the piece best alone first when two want one slot (a ring or trinket pair takes
-- two); a slot that holds a piece of this set already is skipped, and so is a second piece of one item id.
-- Slots come from candidateSlots, as for single swaps; no two copies of a unique item end up worn, since a
-- piece whose id the current set wears is never offered and each id goes on once. The set steps are the
-- first j placements for every j from 2 up, and the first j placements for every j from 1 up with each hands
-- configuration (eachHands) that wears at least one of the set's weapons (j = 0 is that hands configuration
-- alone, a hands step): every piece count the set reaches this way is tried, so a weak further piece of the
-- set does not hide a gainful pair. The trials grow linearly with the set's pieces off the body.
--
-- A step that changes two or more slots (a hands configuration, a set step) is checked part by part. A part
-- is the step with one of its changed slots put back as in the current set, when that is a wearable set
-- (handsLegal), and, when the step changes both hands and another slot, the step with both hands put back
-- together: RowGains puts the hands back as one unit; next to a worn two-hander putting back one hand alone is
-- no wearable set; and next to a worn dual-wield pair of one-handers whose bonus only the two give together (two
-- pieces of one item set) each hand put back alone is a wearable set that can lose to the step while the pair
-- put back beats it. When a part beats the step, the best part becomes the step and its own parts are
-- checked the same way, until no part beats it; that step is then judged against the current set again. A losing
-- part would be a loss as a swap of its own. A part that beats the step need not be a step the plan offers itself (a
-- set step without a middle placement, or with both hands put back), so it takes the step's place instead of the step
-- falling away.
-- Each round probes one part per changed slot and the hands pair: a step with n changed slots takes at most
-- n - 1 rounds.
--
-- Every set is scored as (damage value, survival/mana vs the ORIGINAL worn set): a function of
-- the set alone, and each step must raise it. Measuring survival/mana from the moving current
-- set is not transitive (the health x armor cross term makes A-over-B and B-over-A both
-- positive), and the greedy then swaps two items forever. Every option (each
-- slot of a ring, each hands configuration, each set step) is judged by that same measure.
-- Worn items the plan took off stay available: a step may put worn items back where they were (undoing one made
-- redundant by a later step, e.g. hit over the cap).
-- A step passes when it gains: any damage gain above Score.EPS, or equal damage with more survival/mana (Score.Verdict
-- "better" or "better2"; the user's rule, any damage gain gets the checkmark, no threshold). The result is a fixed
-- point of these steps, so no row is a loss (putting any unit back as worn would itself have been a step, or a part
-- of it would), and every step raises the set it starts from, so the total gains too.
local PLAN_MAX_STEPS = 64
function Score.Plan(equipped, cands, W, ctx)
	local base = copySet(ctx)
	base.equipped = equipped
	-- (value, survival/mana) of each set content scored in this call, so a set the steps offer again (a set
	-- piece alone is its single swap too; a part of a step is often a shorter set step) is scored once. A set is
	-- known by the slots of PLAN_SLOT_ORDER whose item differs from `equipped`, in that order, each with its item
	-- (NONE: emptied): every set here is `equipped` with changes in those slots only (candidateSlots, the hands,
	-- bestPart). memo is a tree over those (slot, item) pairs; a node's `value` field holds { value, sec }.
	local NONE = {}
	local memo, itemCache = {}, {}
	local function eval(set)
		local node = memo
		for _, slot in ipairs(PLAN_SLOT_ORDER) do
			local it = set[slot]
			if it ~= equipped[slot] then
				local bySlot = node[slot]
				if not bySlot then bySlot = {}; node[slot] = bySlot end
				local key = it == nil and NONE or it
				local nxt = bySlot[key]
				if not nxt then nxt = {}; bySlot[key] = nxt end
				node = nxt
			end
		end
		local known = node.value
		if known then return known[1], known[2] end
		local v, s = valueAndSecondary(set, W, ctx, base, itemCache)
		node.value = { v, s }
		return v, s
	end
	local cur = copySet(equipped)
	local curVal, curSec = eval(cur)
	local originals = {}
	for _, it in pairs(equipped) do originals[#originals + 1] = it end
	local kinds = {}
	local settled = false
	for _ = 1, PLAN_MAX_STEPS do
		local inSet = {}
		for _, it in pairs(cur) do inSet[it] = true end
		local best
		-- the best part of a step (set, worth v, s) that beats the step, or nil. The parts: the step with one of its
		-- changed slots (filled or emptied, in slot order) put back as in cur, when that set can be worn, and the
		-- step with both hands put back as in cur, when it changes both hands and another slot, whether or not a hand
		-- put back alone can be worn (a worn two-hander, a worn dual-wield pair).
		local function bestPart(set, v, s)
			local changed = {}
			for _, slot in ipairs(PLAN_SLOT_ORDER) do
				if set[slot] ~= cur[slot] then changed[#changed + 1] = slot end
			end
			if #changed < 2 then return nil end
			local top
			local function probe(part)
				local pv, ps = eval(part)
				if Score.Better(pv, ps, v, s) and (not top or Score.Better(pv, ps, top.value, top.sec)) then
					top = { set = part, value = pv, sec = ps }
				end
			end
			for _, slot in ipairs(changed) do
				local part = copySet(set)
				part[slot] = cur[slot]
				if not isHands(slot) or handsLegal(part[S.MAINHAND], part[S.OFFHAND], ctx.dualWield) then probe(part) end
			end
			if #changed > 2 and set[S.MAINHAND] ~= cur[S.MAINHAND] and set[S.OFFHAND] ~= cur[S.OFFHAND] then
				local part = copySet(set)
				part[S.MAINHAND], part[S.OFFHAND] = cur[S.MAINHAND], cur[S.OFFHAND]
				probe(part)
			end
			return top
		end
		-- whether a step worth (v, s) gains against cur and beats the best step so far
		local function passes(v, s)
			local verdict = Score.Verdict(v - curVal, s - curSec)
			return (verdict == "better" or verdict == "better2") and (not best or Score.Better(v, s, best.value, best.sec))
		end
		local function consider(set, kind)
			local v, s = eval(set)
			if not passes(v, s) then return end
			local part = bestPart(set, v, s)
			if part then
				-- the best part takes the step's place until no part beats it; that step must gain against cur too
				repeat
					set, v, s = part.set, part.value, part.sec
					part = bestPart(set, v, s)
				until not part
				if not passes(v, s) then return end
			end
			best = { set = set, value = v, sec = s, kind = kind }
		end
		local weapons = {}
		local function offer(c)
			if inSet[c] then return end
			if WEAPON_LOCS[c.equipLoc] then
				weapons[#weapons + 1] = c
			else
				for _, slot in ipairs(candidateSlots(c, cur) or {}) do
					local set = copySet(cur)
					set[slot] = c
					consider(set, "item")
				end
			end
		end
		for _, c in ipairs(cands) do offer(c) end
		for _, o in ipairs(originals) do offer(o) end
		-- every hands configuration over the worn hands, bag weapons and worn ones taken off
		eachHands(nil, cur, weapons, ctx.dualWield, function(set, mh, oh)
			if mh ~= cur[S.MAINHAND] or oh ~= cur[S.OFFHAND] then consider(set, "hands") end
		end)
		-- set steps: the off-body pieces of each item set, by set id, in offer order
		local wornIds = {}
		for _, it in pairs(cur) do
			if it.id == nil then error("HunterGearAdvisor: a worn item without an item id: " .. tostring(it.name), 2) end
			wornIds[it.id] = true
		end
		local bySet, setOrder = {}, {}
		local function collect(c)
			local sid = c.setID
			if sid == nil or inSet[c] or wornIds[c.id] then return end
			if not bySet[sid] then bySet[sid] = {}; setOrder[#setOrder + 1] = sid end
			local list = bySet[sid]
			list[#list + 1] = c
		end
		for _, c in ipairs(cands) do collect(c) end
		for _, o in ipairs(originals) do collect(o) end
		for _, sid in ipairs(setOrder) do
			local armor, setWeapons = {}, {}
			-- (a set piece without an item id that fits a slot or a hand has already raised in SetBonuses
			-- through the single swaps above; one that fits nothing is never placed here)
			for _, p in ipairs(bySet[sid]) do
				if WEAPON_LOCS[p.equipLoc] then
					setWeapons[#setWeapons + 1] = p
				else
					-- each slot the piece fits that holds no piece of this set, best alone first
					local opts = {}
					for _, slot in ipairs(candidateSlots(p, cur) or {}) do
						local held = cur[slot]
						if not (held and held.setID == sid) then
							local alone = copySet(cur)
							alone[slot] = p
							local value, sec = eval(alone)
							opts[#opts + 1] = { slot = slot, value = value, sec = sec }
						end
					end
					if #opts > 0 then
						opts = bestFirst(opts)
						armor[#armor + 1] = { item = p, opts = opts, value = opts[1].value, sec = opts[1].sec }
					end
				end
			end
			-- placed[j] = cur with the first j armor placements in best-alone order
			local placed, filled, placedIds = { [0] = cur }, {}, {}
			for _, a in ipairs(bestFirst(armor)) do
				if not placedIds[a.item.id] then
					for _, o in ipairs(a.opts) do
						if not filled[o.slot] then
							local set = copySet(placed[#placed])
							set[o.slot] = a.item
							placed[#placed + 1] = set
							filled[o.slot], placedIds[a.item.id] = true, true
							break
						end
					end
				end
			end
			-- the first j armor pieces alone (j = 1 is a single swap, tried above), and the first j armor pieces for
			-- every j from 1 with every hands configuration that wears one of the set's weapons (j = 0 is that hands
			-- configuration alone, tried above)
			for j = 2, #placed do consider(placed[j], "set") end
			if #setWeapons > 0 then
				local isSetWeapon = {}
				for _, w in ipairs(setWeapons) do isSetWeapon[w] = true end
				eachHands(nil, cur, weapons, ctx.dualWield, function(_, mh, oh)
					local wearsSetWeapon = (mh ~= nil and isSetWeapon[mh]) or (oh ~= nil and isSetWeapon[oh])
					if wearsSetWeapon then
						for j = 1, #placed do
							local set = copySet(placed[j])
							set[S.MAINHAND], set[S.OFFHAND] = mh, oh
							consider(set, "set")
						end
					end
				end)
			end
		end
		if not best then settled = true; break end
		cur, curVal, curSec = best.set, best.value, best.sec
		kinds[#kinds + 1] = best.kind
	end
	-- every step strictly raises (damage, survival/mana vs the worn set), so reaching this is a
	-- bug in the scorer, not a game state
	if not settled then error("HunterGearAdvisor: Score.Plan did not settle in " .. PLAN_MAX_STEPS .. " steps") end

	normalizePairs(equipped, cur)
	return cur, kinds
end

-- Verdict for a candidate: damage first, survival/mana only at equal damage.
-- "better" / "worse" (by damage), "better2" / "worse2" (equal damage, by survival/mana), "same". Any damage gain above
-- Score.EPS is "better" (the user's rule: any damage gain gets the checkmark; no threshold). delta is in the weights'
-- unit (Model.Weights).
function Score.Verdict(delta, sec)
	if delta > Score.EPS then return "better" end
	if delta < -Score.EPS then return "worse" end
	if (sec or 0) > Score.EPS then return "better2" end
	if (sec or 0) < -Score.EPS then return "worse2" end
	return "same"
end
