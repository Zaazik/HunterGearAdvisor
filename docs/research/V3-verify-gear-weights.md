# V3-verify-gear-weights — adversarial check of R5 (weapons/gear) and R6 (stat weights)

Own downloads (independent re-download, build 1.60.1.70888 unless noted):
C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/db2_V3-verify-gear-weights/
(SpellEquippedItems, ItemDamage{OneHand,TwoHand,Ranged,Thrown} + era/, RandPropPoints, ItemXItemEffect, ItemEffect, ItemArmorTotal,
SpellCastTimes, SpellCategories, SpellCategory, SpellItemEnchantment (+era), combatratings_forever.txt = gametable fdid 1391669).
Web pages saved in .../scratchpad/dl_V3/ (theforeverera tfe.txt, wowfdb, Pawn page, wowsims sim.ts/pet.go, Sixx gist).
Wowhead fetches used: 0 (one Wowhead spell page appeared as an exa search hit only).

## 1. Verdict table (short)
| ID | Verdict | Key evidence |
|---|---|---|
| R5-prof-list | confirmed | SkillRaceClassInfo rows with ClassMask&4: 117,122,125,126,127,128,129,132,133,136,139,143,145,147,148,328,330,628,631,632,635,2526,2535; mace/2H mace/wand/shield/plate rows (21,123,124,135,144,246,325,624,625,636,637,643,644,702,2533,2536) never include bit 4 |
| R5-prof-levels | confirmed | Row 132 Dual Wield MinLevel 20 (cm 5 = warrior+hunter), row 145 Mail MinLevel 40 (cm 68); Zygor Skill_Training.lua:57 {674,2100}, :136 {8737,16000} |
| R5-no-racial-wspec | corrected | Gun/Bow/Mace/Throwing spec gone (confirmed). BUT Orc no longer has Savage: SkillLineAbility race line 125 = Blood Fury, Hardiness, Shatter Curse, Command 20576 (hunter mask 4, aura 107 +5% pet dmg). 20574 "Savage" exists only in SpellName/SpellEffect, not granted. wowfdb: "26 October 2026: Orc Savage was removed; Command (+5% pet damage) is back". Human Ruthless 20597 +1% crit (aura 290 bp1), no SpellEquippedItems row = no weapon requirement. Dwarf: Artisan's Precision 1259719 +1% hit (aura 54+55). theforeverera still prints old "Sword Specialization 2% with a sword / Axe Specialization 1% with an axe" text → stale |
| R5-ranged-req | confirmed | SpellEquippedItems: all listed shots mask 262156 (bits 2,3,18), Throw 2764 mask 65536 (bit 16); Summon Hawk/Rapid Fire/AotH/Hunter's Mark/Strider Kick have no row |
| R5-range | confirmed (spot) | Rhok'delar ItemSparse.ItemRange 100 |
| R5-ammo | confirmed | items 2512/11284/11285/274387/274388 ClassID 6 in client; Jagged Arrow & Accurate Slugs ilvl45 q1 req40; ItemDamageAmmo[45].Q1 = 13.03. Formula = classic rule + forever wiki; Icy Veins Forever Aimed formula mentions ammo as an extra factor |
| R5-quiver | confirmed | ItemXItemEffect→ItemEffect(TriggerType 1)→spell aura 557: 2101/3573→29418 10, 3605→29417 11, 7371→29416 12, 8217/274926→29413 13, 19319/18714→29414 15; 2102→14824 10, 3604→14825 11, 7372→14826 12, 8218→14827 13, 19320→14829 15; 29413/29414/29418 mask 262148 (bow+xbow), 14824/14829 mask 8 (gun); Matriarch Quiver ilvl40 q2 req35 14 slots. Haste-on-cast part = wiki only |
| R5-tooltip-dps | confirmed | ItemDamageRanged[75].Q4 = 44.0486 × 2.9 = 127.74 → ×0.7 = 89.4, ×1.3 = 166.06 → 89–166, (89+166)/2/2.9 = 43.97 |
| R5-dps-type-ratio | confirmed | ratios 1.30 / 0.78 / 0.90 at every ilvl/quality checked (25..75, q2..q4); Forever tables row-identical to Era 1.15.9. Caveat: generic client tables; hand-tuned vanilla items are server-side |
| R5-ranged-formulas | corrected | Arcane Shot RAP coefficient is 0.15 since the Nov 3 2026 notes (was 0.10). Rest confirmed: Auto Shot effect 58, Aimed/Multi/Sniper effect 121, Arcane effect 2 with EffectBonusCoefficient 0; Icy Veins Forever independently gives Aimed = RAP/14×2.8 + avg weapon dmg + bonus |
| R5-dps-rap-equiv | corrected | Arithmetic OK (AutoShot 1 DPS = 14 RAP; Aimed/Multi 5×Speed RAP); theforeverera BM table verified (Hit 14/1%, Crit 12/1%, Ranged DPS 7, Agi 1, RAP 0.5, AP 0.5, 2H DPS 0.5, Int 0.3, Sta 0.3, MH 0.3, OH 0.2, Spirit 0.1, Str 0.1, MP5 0.6). "~3× Zygor" holds only vs the RAP part of Agility; counting Agility's crit, community values are 3.4 (distillnote) – 5.05 (wowhandbook) – 7 (theforeverera) Agi per ranged DPS = 1.4–2.9× Zygor's 2.4. Hawk = 32 + RAP×5/100 confirmed by client description "${$s1+($rap*($s4/100))}" |
| R5-forever-shots | confirmed | Aimed 19434/20900-20904: cast 2000 (Era 3000), bp 40/70/115/185/260/350 (Era 70/125/200/330/460/600 = bp+1), BaseLevel 20/28/36/44/52/60 → lvl 43 = R3 115; SpellCategory 2 6000 ms shared with Multi 2643 (Era Multi cd 10000, rank 25294 exists); Arcane 3044..14287 bp 25..280 coef 0 (Era coef 0.204/0.429), Category 1173 shared with Summon Hawk 1293241. These client values already include the Nov 3 "+110% Aimed" and "+30% Arcane" buffs (wowforever.news datamined 166→350, 217→280). Baseline at 20: theforeverera (Blizzard Sep 30) + Wowhead Forever spell page "Requires level 20" |
| R5-autoshot-forever | confirmed (with caveat) | forever-bugs #387 maintainer: "auto shot will behave like classic has, with the only exception being autos while casting aimed/sniper shot"; melee resetting ranged "mentioned as a bug on issue #14". Caveat: Blizzard forum 16 Oct (build 70450) reports clipping partly re-introduced past a point of the swing timer |
| R5-speed-tradeoff | confirmed (derivation) | Re-ran Monte-Carlo: 58.9/54.8/46.9/42.8/40.3/37.5% → identical. Caveats: assumes only Auto Shot procs, ignores 0.5 s stand-still cast; Icy Veins Forever also says prefer slower weapon (avg damage per hit) |
| R5-hawk-procflag | confirmed | SpellAuraOptions 13165/14321 ProcTypeMask_0 320, 13161/1299447 = 4; Era 13165 87376; tooltip 19552 says "Auto Shot" |
| R5-melee-mh | confirmed | Forever SpellEffect Raptor 58 bp 5/11/21/30/35/40/55/70; Era EffectBasePoints+DieSides 34 (R4) / 140 (R8); Mongoose 121 bp 15/22/37/57 (Era effect 2, 115 R4); Counterattack 121 26 + 31 50%; Strider Kick 121 0 + 31 100%; Wing Clip effect 2 bp 5 |
| R5-slow-mh | confirmed | follows from effect 58 non-normalized (avg roll = DPS×Speed); Mongoose is normalized (121) so speed matters only for its weapon roll, not AP part |
| R5-oh-dw | confirmed (scope upgraded) | +19% DW miss is in Forever client: CR_HUNTER_HIT_CAP_TOOLTIP "8.00% Melee/Ranged … 27.00% Dual Wielding", equal level 5.00% / 24.00%. OH 50% damage = wiki/classic only |
| R5-preds-edge | confirmed (client), conflict | Spell 1310627 description "…melee ability critical strike damage by $s1% and your Off Hand weapon damage by $s2%", e1 aura 122 bp 50. wowfdb: 16 Oct build 70450 tooltip "reworded to say it boosts only the crit damage of your abilities" — not what 70888 client text says |
| R5-aotb | confirmed | 13161/1299445/1299446/1299447 aura 99 bp 50/70/90/110; trainer 7600@30, 16000@40, 30000@50, 39000@60 (Skill_Training.lua:98,144,176,210); Quick Strikes 1299448 aura 319 30; Rapid Fire 3045 aura 140 40 + aura 319 40, cd 300000 |
| R5-statstick | confirmed (method), budget ratio plausible | theforeverera: "the best two-hander is compared with the best one-hand pair". Forever RandPropPoints groups ilvl 45 Superior 26/19/14/11/8 → ratios 1/0.73/0.54/0.42/0.31 match allakhazam 2H 1.00 / OH 0.55 / 1H 0.42 / ranged 0.30; ranged = group 4 confirmed on Cliffrunner's Aim (6666×Good_4(29)=2.0 → +2 Agi +2 Int, as wowhandbook shows) |
| R5-zygor-dps | confirmed | Item-ItemScore.lua:544-557, weights verbatim at Item-Statweights.lua:34; 26.73×2.4=64.2, 34.75×2.4=83.4, 20.85×2.4=50.0 |
| R5-zygor-dw | confirmed | Code-Forever/Item-ItemScore.lua:27-56 (no HUNTER), :77-105 |
| R5-zygor-2h | confirmed | Item-Upgrades.lua:354-356, Item-GearFinder.lua:167-171,226,315 |
| R5-zygor-thrown | confirmed | itemtypes THROWN=1; get_slots_by_type INVTYPE_THROWN→INVSLOT_RANGED; skill gate :741-753 |
| R5-zygor-hitcap | confirmed | Item-ItemScore.lua:548-553 (C_Item.IsEquippedItem check) |
| R5-zygor-ammo | confirmed | TypeToSlot has no INVTYPE_AMMO/QUIVER/BAG; IsValidItem "not equipment" :680-686 |
| R5-zygor-armor | confirmed | IsValidItem limit<0 → invalid at level ≥ 40; Item-Upgrades.lua:286-288 old invalid → 100; GetItemScore ×0.9 (40-49) / ×0.5 (≥50) |
| R5-zygor-sv-typo | confirmed | get_ruleset_for copies keys verbatim (Item-ItemScore.lua:159-161), lookup statweights[statname] exact → "RaNGED_ATTACK_POWER" never used |
| R5-armor-mail | confirmed | ItemArmorTotal 40: 1441.5/689.26=2.09; 45: 2.045; 50: 2.064; 60: 2.094 |
| R6-forever-rating-units | confirmed (+ resolved open question) | QSR 5000×Epic_2(67)=28→14.0; Kiss 3256×43=14.0, 2326×43=10.0; Devilsaur Leggings crit 4118×34=14 (+46 AP, +12 Sta = classic). combatratings.txt (Forever) has hit 10 / crit 14 / haste 10 / expertise 10 identical at every level 1..123 → conversion is NOT level-scaled |
| R6-forever-tooltip-percent | confirmed | GlobalStrings rows 59247/59249/59280/59282 (enUS) and ruRU 59247/59249; Era GlobalStrings: 0 PERCENT_INCREASE strings |
| R6-zygor-is-tbc-pawn | confirmed | Pawn "Hunt BM" line identical to Zygor BM except Spirit (0.05 vs 1), Health (0.05 vs 0.02), MeleeDps dropped; MM identical too |
| R6-zygor-units-per-percent | corrected (range) | Code confirmed (L.HIT2/CRIT2 capture %). Community per-1% in Agi: hit 8.3 (wowhandbook 22.94/2.77) – 14.1 (mythicsim); crit 9.5 (wowhandbook) – 13.8 (distillnote) → Zygor is ~8–14× low, not 10–15× |
| R6-zygor-regex-breaks | confirmed (code-level; in-game not checked) | Keywords regexes = ITEM_MOD_HIT_RATING "Increases your hit by %s." (+ _SHORT "Hit") and L.HIT/HIT2 "Improves your chance to hit by ([0-9]+)%%."; line has "Equip: " stripped then :lower(); Forever text "improves your chance to hit by 1.0%." cannot match ([0-9]+)%; ruRU strings differ in wording. Tooltip rendering is client C code — cannot be checked offline |
| R6-zygor-no-dualwield-hunter | corrected (range) | Code confirmed. Community ranged DPS weight = 3.4–7 Agi (theforeverera 7), and melee DPS weight is small but not 0 in theforeverera (2H 0.5, MH 0.3, OH 0.2) |
| R6-forever-sim-mythicsim | confirmed | page values re-read: Hit 1.41, Agi 1.00, Crit 0.91, Exp 0.73, Int 0.59, Haste 0.40, RAP 0.29, MP5 0.26, ArP 0.13, Str 0.10, AP 0.09, Weapon damage 1.20; engine pinned Nov 11, client 70707. Whether 31/20/0 includes Careful Aim is not stated on the page (R6 assumption) |
| R6-forever-sim-distillnote | confirmed | crit 6.33, hit 5.53, haste 3.63, exp 1.78, rDPS 1.57, Agi 0.46, Int 0.164, RAP 0.149, ArP 0.0549; derived ratios recomputed OK |
| R6-forever-sim-brokenmeta | confirmed | Item.csv 22384 class 2 sub 4 (1H mace), 12776 class 2 sub 5 (2H mace); no hunter mace skill |
| R6-forever-wowhandbook | confirmed | values re-read |
| R6-forever-icyveins | corrected | Pet hit: client STAT_PET_HIT_TOOLTIP (GlobalStrings 60479) "Increased by 100% of Master's Hit Chance" → Icy Veins BM ("does not directly benefit from your hit chance at all", re-read) is wrong; pet crit 100% confirmed by STAT_HUNTER_PET_CRIT_BONUS (60229). 8% cap confirmed |
| R6-forever-hitcap | confirmed (client) | CR_HUNTER_HIT_CAP_TOOLTIP (60052); 5.5/6% for +1/+2 from wowhandbook only. Conflict: unused local {5.0,5.2,5.4,9.0} in PaperDollFrameStats.lua (R3) |
| R6-forever-pet-scaling-client | corrected | aura 54/55 meaning is now proven from Forever data: Artisan's Precision 1259719 ("+$s1% hit with all spells and attacks") = aura 54 + 55. Pet hit inheritance = 100% (client tooltip), not "unknown" |
| R6-classic-sixx-ep | confirmed (spot) | gist lines 301-308: Brutality Blade 58, Core Hound Tooth 54, "1% crit weapon" 34 |
| R6-classic-icyveins-legacy | unverifiable | not re-fetched; consistent with Sixx ranges |
| R6-lowgear-crit-hit-scale | corrected | wowcalc values confirmed (hit 12.3, haste 11.6, crit 10.3, Agi 2.2, SP 1.6, Int 0.09) but the model is level-60 20/31/0, RAP 554, "Arcane Shot (rank 8) plus auto attacks", no pet, not a BM low-gear char; the "×0.5 at 43" is an unverified derivation |
| R6-ranged-dps-value | corrected | 10.5 RAP (distillnote) – 14 (wowhandbook, theforeverera); in Agi 3.4–7, not 3.4–5 |
| R6-sod-wowsims-ep | confirmed | sim.ts lines 79-101 and pet.go 283-291 re-read |
| R6-sod-pet-scaling-shift | unverifiable | commit history not re-checked; current pet.go shows MeleeCrit = owner crit |
| R6-melee-statstick-dw | confirmed (Forever-scoped now) | Forever SpellItemEnchantment 2564 "Agility +15", 2646 "Agility +25" (also 883 "+15 Agility", 1102 "+25 Agility"), identical to Era |
| R6-classic-hitcap | confirmed | R3 vmangos + Blizzard blue (first 1% ignored) |
| R6-int-spirit-zygor | corrected | Careful Aim curve r1..r5 = 20..100 confirmed. But not all Forever sources set Int≈0 without Careful Aim: theforeverera BM Int 0.3 Agi (mana for Arcane Shot/aspects), wowhandbook BM Int 1.12 AP (talents not stated) |

## 2. New / important facts found
- Forever combatratings.txt (fdid 1391669): flat 10 hit / 14 crit / 10 haste / 10 expertise / 12 dodge / 15 parry / 5 block at all levels.
- Client hit-cap tooltip: 8% melee/ranged vs raid boss, 5% vs equal level, DW 27% / 24% → DW white penalty +19%.
- Pets: 100% of master's hit (60479) and 100% of master's crit (60229).
- Zygor Forever never scores trinkets: Code-Forever/Item-ItemScore.lua:70 INVTYPE_TRINKET → false,false; Item-ItemScore.lua:1249-1251 "Trinkets are not part of the Zygor scoring system."
- Zygor per-character weight overrides (SavedVariables altDB[name].statweights[spec.."_"..STAT]) replace defaults in get_ruleset_for (Item-ItemScore.lua:173-179).
- Nov 3 2026 notes (wowforever.ninja / kickegg / wowfdb / wowforever.be / theforeverera): Arcane Shot AP coef 0.10 → 0.15 (+30% base), Serpent Sting 5% AP per tick (was 3%), Aspect of the Hawk 20/35/50/70/90/110 RAP, Aimed Shot +110% bonus (client 350 at R6), Sniper Shot bonus doubled. Nov 11: Arcane Shot & Summon Hawk cost 11% base mana; hawk melee damage ~80% higher.
- Racials (client SkillLineAbility): Human Ruthless +1% crit, Orc Command +5% pet damage (Savage not granted), Dwarf Artisan's Precision +1% hit, Troll Beast Slaying; no weapon-type racial remains.
- Aimed Shot baseline at 20 (Blizzard Sep 30 per theforeverera; Wowhead Forever spell 19434 "Requires level 20"); Zygor's Skill_Training.lua still tags ranks 2-6 with talent=19434 (stale classic table).

## 3. Conflicts still open
1. Arcane Shot coef: R5 0.10 vs Nov 3 notes 0.15 (server-side; client coef 0).
2. Orc racial: R5 "Savage +1% crit" vs client (Command) / wowfdb (Savage removed Oct 26); theforeverera still shows pre-Oct-15 sword/axe specs.
3. Predator's Edge OH part: client 70888 tooltip includes "Off Hand weapon damage +50%"; wowfdb says it was reworded (build 70450) to crit only.
4. Auto Shot during Aimed Shot: maintainers say yes; one Blizzard forum report (build 70450) says clipping partly returned.
5. Quick Shots proc: ProcTypeMask 320 (auto + abilities) vs tooltip "Auto Shot".
6. Ranged DPS EP: 10.5 RAP (distillnote) vs 14 (wowhandbook, theforeverera); per-1% hit/crit: wowhandbook 23/26 RAP vs sims 37-49 RAP.
7. Intellect value without Careful Aim: R6 ≈0 vs theforeverera 0.3 Agi vs wowhandbook 1.12 AP.
8. Hit cap 8% (client tooltip) vs unused {5.0,5.2,5.4,9.0} in PaperDollFrameStats.lua.
9. Epic ammo DPS: wiki 22 vs ItemDamageAmmo[65].Q4 24.6.
10. Icy Veins BM (pet gets no hit) vs client tooltip (100% of master's hit) vs Icy Veins SV ("8%").
