# R2-pet-scaling — what the hunter pet and Summon Hawk inherit (WoW Forever, BM 32/2/0, ~lvl 43)

Scope tags: forever_client_data = Forever DB2/GlobalStrings/UI source of build 1.60.1.70888;
forever_web = source explicitly about Forever (Blizzard notes, community bug tracker, combat-log sims);
sod = Season of Discovery; classic_era = 1.12 / 1.15 Era; tbc_or_later.

Local working files (downloaded, untrusted data, read-only use):
- C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/db2_R2-pet-scaling/ (SpellEffect_era.csv, SpellName_era.csv = build 1.15.9.70576; SpellDuration.csv, SpellClassOptions.csv, GlobalStrings.csv = Forever 1.60.1.70888; GlobalStrings_era.csv)
- C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/dl_R2-pet-scaling/ (tc_SpellAuraDefines.h, simc_data_enums.hh, sod_*.go = wowsims/sod, wsf/*.go = wowsims/forever, ui/*.lua = Gethe/wow-ui-source branch `forever`, trueshot/overrides.toml + PLAN.md = dj0le/trueshot, issues_dump.txt = forever-bugs issues, c_*.patch = wowsims/forever commit patches)

---------------------------------------------------------------------------------------------------
## 1. Client data: aura decode (modern AuraType enum: TrinityCore master SpellAuraDefines.h + SimulationCraft data_enums.hh)

### 1a. 415429 "Hunter Pet Scaling" (Forever) — all base points 0 = amounts set server-side
| eff | aura | modern name | misc | meaning for pet |
|---|---|---|---|---|
| 0 | 230 | MOD_MAX_HEALTH (flat) | – | pet max health from owner (Forever: "2 Health per owner Stamina") |
| 1 | 99 | MOD_ATTACK_POWER | – | pet melee AP from owner AP |
| 2 | 13 | MOD_DAMAGE_DONE | 126 (Holy..Arcane) | pet spell damage from owner |
| 3-7 | 22 | MOD_RESISTANCE | 4,16,8,32,64 (Fire,Frost,Nature,Shadow,Arcane) | resistances from owner (share unknown) |
| 8 | 674 | (unnamed in TC/simc) armor | 1 (Physical) | pet armor from owner. 674 misc 1 is Forever's armor aura client-wide (Devotion Aura 465, Mark of the Wild 1126, Sunder Armor 7386 all use 674 misc 1 in Forever; same spells use 22 misc 1 in 1.15.9) |
| 9 | 54 | MOD_HIT_CHANCE | – | pet melee hit |
| 10 | 55 | MOD_SPELL_HIT_CHANCE | – | pet spell hit |
| 11 | 319 | MOD_MELEE_HASTE_NO_REGEN (simc: MOD_MELEE_AUTO_ATTACK_SPEED) | – | pet auto-attack speed from owner melee speed |
| 12 | 65 | MOD_CASTING_SPEED | – | pet cast speed |
| 13 | 52 | MOD_WEAPON_CRIT_PERCENT | – | pet melee crit |
| 14 | 57 | MOD_SPELL_CRIT_CHANCE | – | pet spell crit |
| 15 | 418 | MOD_MAX_POWER | 2 (Focus) bp 50 | +50 max focus as written; combat logs show pets cap at 100 focus (wowsims/forever commit 82230204) |
| 16-17 | 593 | (unnamed; wowsims calls it A_MOD_COMBAT_RESULT_CHANCE2) | 4 / 2 | target dodge / parry chance vs pet = expertise inheritance (same aura with bp -1/-2 on "Increased Expertise 1/2" 1213288/1213289) |
| 18 | 49 | MOD_DODGE_PERCENT | – | pet dodge (Forever-only effect) |

1328676 "[DNT] Hunter Pet Scaling (Old Testing Backup)" = identical effects.
Source: db2/SpellEffect.csv rows SpellID 415429/1328676; enum: dl_R2-pet-scaling/tc_SpellAuraDefines.h lines 100-761, simc_data_enums.hh lines 1053-1631.

### 1b. Diff vs the SoD/Era client (1.15.9.70576 SpellEffect, SpellID 415429)
- eff0: SoD = aura 29 MOD_STAT misc 2 (Stamina)  -> Forever = aura 230 MOD_MAX_HEALTH. Pet gets health directly, not stamina.
- eff8: SoD = aura 22 misc 1 -> Forever = 674 misc 1 (client-wide armor renumbering, not a pet change).
- eff11: SoD = aura 138 MOD_MELEE_HASTE -> Forever = 319 MOD_MELEE_HASTE_NO_REGEN (auto-attack speed only).
- Forever adds eff18 aura 49 MOD_DODGE_PERCENT.
- 418 bp 50 misc 2 and 593 x2 identical in both.
Same renumbering seen on Frenzy proc 19615 (Era aura 138 bp30 -> Forever aura 319 bp30) and Tamed Pet Passive 19591 (Era 52+57 -> Forever 290 MOD_CRIT_PCT).

### 1c. 1293586 "Hunter Guardian Hawk Pet Scaling 01" (Forever-only)
- eff0 aura 342 MOD_MELEE_RANGED_HASTE_NO_REGEN (simc: MOD_RANGED_AND_MELEE_AUTO_ATTACK_SPEED) -> hawk swing speed from owner speed.
- eff1 aura 79 MOD_DAMAGE_PERCENT_DONE misc 127 (all schools) -> hawk damage % (logs: owner's damage multiplier at summon).
- eff2 aura 290 MOD_CRIT_PCT, EffectBonusCoefficient=1 -> hawk crit. NOTE: EffectBonusCoefficient=1 on aura 290/52 also appears on ordinary talents (Lethal Attacks 19426, Malice 14138, Killer Instinct 19370, Tamed Pet Passive 19591...), so it is a generic field value, NOT evidence of 100% crit inheritance. Logs say 50% (see §4).
- No aura 99 (AP) in the client row, yet logs show hawks have AP (server-side).
Duration 1293248 (summon) = DurationIndex 85 = 18000 ms (db2_R2-pet-scaling/SpellDuration.csv). Max hawks = effect 2 bp 2; dive RAP share = effect 3 bp 5 (5%).
Summon Hawk ranks: 1293241 bp32 (lvl 25), 1293525 bp47 (lvl 36), 1293526 bp85 (lvl 48), 1293527 bp108 (lvl 60) — level per Wowhead/fextralife/talentsforever. A level-43 hunter has rank 2: dive = 47 + 0.05*RAP.

### 1d. Talent spell-mods (SpellClassOptions, Forever) — what UF/Ferocity actually modify
- Unleashed Fury 19616: aura 107 ADD_FLAT_MODIFIER, SpellModOp 3 (PointsIndex0), class mask [0x2000000,0,0x2000,0] -> targets Tamed Pet Passive 8875 (aura 79 MOD_DAMAGE_PERCENT_DONE, bp 0: "Damage increased by $s1%") and all 4 Summon Hawk ranks (SpellClassMask_2 = 8192).
- Ferocity 19598: same, mask [0x40000000,0,0x2000,0] -> Tamed Pet Passive 19591 (aura 290 crit, bp 0) and Summon Hawk.
- Frenzy 19621: aura 107 op 18 (ProcChance) -> Tamed Pet Passive 20784 (proc trigger of 19615).
- Bestial Discipline 19590 -> 19589 (focus regen); Endurance Training 19583 -> 19580 (armor %) and 19581 (health %).
- Values per rank come from TraitDefinitionEffectPoints curves (UF 3/6/9/12/15, Ferocity 2/4/6/8/10, Frenzy 20..100, BD 10/20); the spell's own bp (20, 16) is stale. Era (1.15.9) for comparison: UF rank-1 spell bp 4 (=20% at 5/5), Ferocity bp 3 (=15%).

### 1e. Family passives (Forever DB2 SpellEffect, aura 79 misc 1 = physical damage %, 142 = base armor %, 133 = max health %)
Cat 17210 +10 / 0 / -2; Raptor 17217 +10 / +3 / -5; Bat 17206, Bird of Prey 17216, Spider 17219, Wind Serpent 17222: +7 / 0 / 0; Gorilla 17214 +2 / 0 / +4; Carrion Bird 17209 0/+5/0; Croc 17212 0/+10/-5; Hyena 17215 0/+5/0; Tallstrider 17220 0/0/+5; Wolf (and Fox) 17223 0/+5/0; Crab 17211 -5/+13/-4; Scorpid 17218 -6/+10/0; Bear 17208 -9/+5/+8; Boar 7000 -10/+9/+4; Turtle 17221 -10/+13/0.

### 1f. Faster/Slower Attack passives (Forever-new): aura 9 MOD_ATTACKSPEED on pet: I 17, II 25, III 33, IV 43, V 54, VI 67, VII 100; Slower I -17, II -20, III -26 (spells 1263099..1263114). Base pet swing 2.0 s.

### 1g. Haste auras (who gets what)
- Quick Shots 6150 (Deadly Aspects, Hawk): aura 140 MOD_RANGED_HASTE bp30, 12 s -> ranged only.
- Quick Strikes 1299448 (Beast): aura 319 bp30.
- Rapid Fire 3045: aura 140 bp40 + aura 319 bp40, 15 s (ranged + melee auto-attack speed).
- Quiver "Haste" 14824/14829/29413: aura 557 (ranged ammo haste) 10/15/13%.
- Wind Blessed 1259710 (Skyborne) and Tier-1 hunter 2P 1300945: aura 342 (melee+ranged) + 65.

### 1h. Forever client strings (GlobalStrings DB2, build 1.60.1.70888; none of these exist in 1.15.9 GlobalStrings)
- 60217 MELEE_ATTACK_POWER_PET_HUNTER_TOOLTIP: "Increased by 10% of Master's Attack Power from whichever is higher: Melee or Ranged ... Every 14 Attack Power adds 1 damage per second"
- 60229 STAT_HUNTER_PET_CRIT_BONUS: "Increased by 100% of Master's Critical Strike Chance ... Melee critical strikes deal 100% increased damage"
- 60479 STAT_PET_HIT_TOOLTIP: "Increased by 100% of Master's Hit Chance. To never miss Raid Bosses: 8.00% Melee 17.00% Spells; Equal-Level Targets: 5.00% Melee 4.00% Spells"
- 60480 CR_PET_EXPERTISE_TOOLTIP: "Increased by 100% of Master's Expertise. Raid Boss chance to: 6.50% Dodge 16.50% Parry; Equal-Level Creature: 5.00% Dodge 5.00% Parry"
- 21755 STAT_HEALTH_PET_TOOLTIP: "Increased by Master's Stamina ... Every 1 Stamina adds 2 Health" (1.15.9 text was "Maximum health...")
- 60215 STAT_ARMOR_PET_TOOLTIP: "Increased by %d%% of Master's Armor" — UI fills %d with ComputePetBonus("PET_BONUS_ARMOR",100) = 30 (HUNTER_PET_BONUS["PET_BONUS_ARMOR"]=0.3 in Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua, wow-ui-source branch forever, lines 43-52; PaperDollFrameStats.lua line 498)
- 60228 STAT_SPELLPOWER_PET_TOOLTIP: "Increased by 10% of Master's Spell Damage" (generic pet tooltip, shown for any pet with SP>0)
- The rest of the legacy HUNTER_PET_BONUS table (RAP_TO_AP 0.22, RAP_TO_SPELLDMG 0.1287, STAM 0.3, RES 0.4) is Wrath-era leftover; only ARMOR is used in the Forever pet panel code.
- Pet panel stats (Camelot/PaperDollFrameConstants.lua lines 92-116): Health, Move speed, Armor, Damage, AP, Spell Power, Hit, Crit, Haste (GetPetMeleeHaste), Expertise, Dodge — no primary attributes.
- Pet hit display code (PaperDollFrameStats.lua ~line 528): "Pets inherit 100% of the owner's hit chance" using owner MELEE hit (CR_HIT_MELEE + GetHitModifier) + GetPetHitChanceModifier; pet expertise display = owner GetExpertise().

---------------------------------------------------------------------------------------------------
## 2. SoD baseline (for scope contrast only)
- 415429 was introduced by SoD (present in 1.15.9 client). Blizzard SoD class tuning Dec 12 2023 (bluetracker.gg/wow/topic/us-en/1739014; quoted in us.forums.blizzard.com/en/wow/t/its-time-to-take-a-serious-look-at-hunter-pets/1765304): "Pets now gain 30% of the hunter's armor (was 45%) and 20% of the hunter's stamina (was 45%)"; "All damaging Hunter pet abilities now gain damage from Attack Power based on their Focus costs. Hunter pets no longer gain any spell damage."
- wowsims/sod sim/hunter/pet.go makeStatInheritance: Stamina*0.3, Armor*0.35, AP = RAP*0.22, MeleeCrit = owner crit, SpellCrit = owner crit, MeleeHit = owner hit, SpellHit = 2*owner hit, Expertise = owner; happiness x1.25; EnableDynamicMeleeSpeedInheritance (Phase 8, owner melee speed). sim/hunter/talents.go: Ferocity 3%/rank, Unleashed Fury 4%/rank, Frenzy 20%/rank chance +30% speed 8 s, BW x1.5 18 s / 2 min, Endurance Training 3%/rank.
- TBC/Wrath (petopia classic_lk/stats_scaling.php; wowhead forum topic 81660): 45% stamina, 35% armor, 22% RAP->AP, 12.5% RAP->spell dmg, 40% resist, hit and crit inherited; "Starting with Patch 2.0, hunter pets now benefit from pet scaling" => Classic Era 1.12 pets inherit nothing.

---------------------------------------------------------------------------------------------------
## 3. Forever tamed pet — inheritance (best current values)
| owner stat | pet gets | evidence | confidence |
|---|---|---|---|
| Attack Power | 10% of max(melee AP, RAP), floored; added to pet's own AP (4.2 x creature DPS of its level, nothing from Str) | client string 60217; Wowhead SV overview; wowsims/forever pets.go (pet sheets lvl 11/17/30 read 36/61/103 own AP + owner 10%) | high |
| Stamina | +2 pet max Health per owner Stamina | client string 21755; aura 230; Wowhead; community | high (2/pt); total health also x1.15 "normal health" since Nov 10 hotfix (Blizzard) |
| Armor | 30% (dynamic, follows gear) | UI code 0.3; community; wowsims logs | high |
| Crit | 100% of the HIGHER of owner melee/ranged crit (+Ferocity, +Intimidation) | client string 60229; Blizzard beta notes Oct 15 (fix: was melee only); wowsims | high for specials; see caveat |
| Hit | melee hit = owner RANGED hit (physical + ranged-only hit) 1:1; spell hit = 17/8 x that | forever-bugs #394 (log: 2% Surefooted -> pet white miss 2.81% vs equal level); fix comment by AidanZMoon Oct 20; wowsims inheritedHit() | high (melee), medium (spell 17/8) |
| Expertise | 100% | client string 60480; Blizzard Oct 15 notes "Pets now correctly benefit from Expertise" | high (100% per tooltip; wowsims says share unmeasured) |
| Melee haste (incl. generic "Haste" aura 342, Rapid Fire's melee 40%) | multiplies pet swing speed | wowsims commit d729b139 (Nov 8 log: pet 1.965 s with owner 2% Wind Blessed, 1.40 s under Rapid Fire, 1.08 s with Frenzy too) | high |
| Ranged-only haste (quiver 557, Quick Shots 140, ammo) | NOTHING | same log: "The owner's Quick Shots left it at 1.965 s" | high |
| Spell damage | 10% to pet spell damage (generic tooltip) | client string 60228 | low (not tested for hunter pets) |
| Intellect / Spirit / Strength | nothing (Str only if melee AP > RAP, practically never for a hunter) | no aura; tooltip "whichever is higher" | high |
| Resistances | some share (5 auras) | aura 22 x5; share unknown | low |
| Player stat buffs (Kings, MotW, scrolls) | do NOT apply to pet | Blizzard Sep 30 notes via classicwowforever.com; Wowhead; forever-bugs #41 | high |

Snapshot rule (forever_web, combat logs): the pet's inherited AP and Health are taken at summon and kept while out; armor follows the owner; other stats refresh on any pet action, at most every 2 s (wowsims/forever pets.go keepSummonStats + registerStatInheritance; commit 82230204 "pet's attack power holds through 20 Aspect of the Hawk toggles and a gear swap in one summon"; forever-bugs #48 Blood Fury +34 RAP only counted after re-summon). => after a weapon/gear upgrade or switching to Aspect of the Hawk, re-call the pet to refresh its AP.

### Pet base mechanics (Forever)
- Swing 2.0 s base; Faster/Slower Attack passives speed the swing but damage per swing is normalized (DPS unchanged): trueshot task 53 (The Rake 1.20 s, damage per hit 0.6 of a 2.0 s cat), overrides pet.attackSpeedSec (1.31 s pet hits 0.65x), forever-bugs #31 comment "The damage has been normalized" (Oct 25); wowsims applyAttackSpeed divides damage. Early beta tests (conquestcapped: 1.3 cat 35.1 vs 23.5 DPS) predate normalization.
- Pet swing per hit = (creatureDPS(level) - ownAP/14)*2 +-20% + AP/14*2.0 (wowsims pets.go; fits level-30 cat logs).
- Pet focus: 10/s continuous (100 cap), 11-13/s with Bestial Discipline 2/2 (wowsims commit 82230204, Nov logs). Level-30 cat spending all on Claw: one Claw per 2.43 s.
- Pet Claw/Bite: flat damage, NO attack power scaling (Forever DB2 BonusCoefficientFromAP 0 on Bite 17253-17261 / Claw; trueshot task 64: ~2000 rank-3 Claws flat from pet AP 44 to 90). So owner AP reaches the pet only through white swings.
- Pet white-swing crit on live is far below the sheet: trueshot (launch logs to Nov 10, levels 7-26, no Ferocity): 21 crits / 6109 white swings (0.34%) vs 8.1% sheet; Claw/Bite crit ~sheet (Claw 8.5% vs 9.6% sheet). White crit by level gap: ~0.1% at +0, 0.4% at -1, 1.2% at -4, 3.6% at -8, none at +2 and up. => Inherited crit currently works on pet specials; white swings barely crit (unresolved whether intended; wowsims assumes they do).
- Pet glancing vs higher mobs: 10 + 2.5 x (defense - skill) % (trueshot task 66: +0 9.7%, +1 22.7%, +2 34%, +3 51%).
- Pet miss vs equal level 5% melee (client tooltip) -> 5% hit cap for pet white/specials vs equal level; 8% vs +3 boss.
- Happiness: happy 125%, content 100%, unhappy 75% (conquestcapped Forever guide; wowsims/trueshot use 1.25). Dismiss Pet costs 50 happiness (conquestcapped, unverified).
- Pet health: Blizzard Nov 10: "Pets erroneously had 150% of their normal health. This is now corrected to 115%". Pet's own Stamina gives 0 HP now (forever-bugs #432: since 11/09 pets gain health from training instead).

---------------------------------------------------------------------------------------------------
## 4. Summon Hawk guardians (Forever-new)
- Dive (hunter's ranged special, cannot miss, crits with owner ranged crit): rank2 47 + 0.05*RAP (rank1 32, rank3 85, rank4 108). 6 s cd shared with Arcane Shot, 11% base mana (Blizzard Nov 10). Missile speed 35 yd/s.
- Hawk: 18 s, max 2 (third replaces oldest), spawns at and sticks to the target (Oct 15 fix). Health 5% of creature health; no own AP/armor.
- Hawk AP = 0.8 x (owner RAP + 7 + 14 x ranged weapon DPS) — wowsims/forever summon_hawk.go from level 48 logs ("352 at 345 RAP with no weapons, and 1180 at 747 with a 27.3 dps bow"; 747+7+14*27.3 = 1136, the remaining 44 is consistent with ammo DPS ~3.1, i.e. ammo may count too).
- Hawk swing: base 2.5 s; per swing (before armor, before UF/FF) = 0.185 x creatureDPS(level) x 2.5 +-22% + hawkAP/60 x 2.5 (i.e. 1 dps per 60 hawk AP) — post-Nov-10 fit (commit 77a901ae: pre-hotfix 112 AP per dps; Blizzard: "Melee damage dealt by the Hawk pet increased by about 80%").
- Hawk speed follows owner RANGED speed incl. quiver and Quick Shots (Berserking does not reach it).
- Hawk crit = 0.5 x owner's higher crit + Ferocity (10 at 5/5): "4340 swings with Ferocity 5/5 read 10 plus half the owner's crit".
- Hawk hit and expertise = owner's ranged hit / expertise ("1% hit took a hawk from 1 miss in 32 swings to none in 515").
- Hawk damage multiplier = owner's damage-done multiplier at summon (Focused Fire reaches hawks) x Unleashed Fury. Bestial Wrath does NOT reach hawks (BW targets pet only, ImplicitTarget 5; trueshot audit "hawks share only the 'pets and hawks' passives (no Bestial Wrath)"). Frenzy is the tamed pet's passive only.
- Share of damage: mobalytics BM leveling guide (pre-Nov-10): hawks ~10% of the author's damage (5% dive + 5% melee). Cargos via mmogah (beta): Summon Hawk = 8-12% DPS for one point; Unleashed Fury = 1.2% total DPS per point. After the +80% melee hotfix the melee part should be ~1.8x -> hawks roughly 12-15% (estimate, unverified).
- Older (pre-hotfix, level 30) observation: trueshot overrides pet.hawk.hitPctOfPetMelee 16 ("hawk hits 14 (crits 29) against wolf hits 41-61"), interval ~2.0-2.25 s.

---------------------------------------------------------------------------------------------------
## 5. Talent values that touch pet/hawk (Forever)
- Unleashed Fury 5/5 = +15% pet AND hawk damage (3/rank). Evidence: DB2 curve 82822; forever-bugs #227 ("should increase pet and hawk damage by 3%/6%/9%/12%/15%", dev reply "Fixed in next build"); in-game tooltips quoted by wowcalc/talentsforever/wowseer ("by 15%"/"by 3%"); conquestcapped "slightly less than in Classic". Spell bp 20 = stale/placeholder. => CONFLICT RESOLVED: 15%.
- Ferocity 5/5 = +10% pet AND hawk crit (2/rank). Evidence: curve 82820; forever-bugs #228 (2/4/6/8/10; dev: "just a visual bug. The pet is getting the correct amount"); wowsims hawk log "10 plus half the owner's crit". Spell bp 16 stale. => CONFLICT RESOLVED: 10%. Pet panel does not show Ferocity (visual bug).
- Focused Fire 2/2 = +2% hunter and pet damage while pet active; hawks get it via owner multiplier (wowsims log fit used FF 2/2). trueshot task 64: no visible effect on Claw (unresolved).
- Frenzy 4/5 = 80% chance per pet crit -> +30% pet auto-attack speed (aura 319) for 8 s; multiplies with owner melee haste (log: 1.40 s RF -> 1.08 s RF+Frenzy). Only on the pet; procs off crits (practically special crits given the white-crit issue).
- Bestial Wrath: +50% pet damage (aura 79 bp 50), 18 s, 2 min cd (SpellCooldowns 120000, SpellDuration 18000) -> average x1.075 on pet only.
- Intimidation: next pet attack +100% crit, 3 s stun, 1 min cd (aura 290 bp100).
- Endurance Training 1/5: +3% pet health and armor. Bestial Discipline 2/2: +20% pet focus regen (curve 10/20).
- Lethal Attacks 2/5: +2% crit all attacks (aura 290) -> pet specials +2%, hawks +1%.
- Orc racial Command (20575): +5 to the pet damage passive (trueshot: as UF raises it, so hawks get it too). Night Elf Elune's Light crit buffs pet too (Cargos).

---------------------------------------------------------------------------------------------------
## 6. Marginal value formulas for a BM hunter (pet + hawks part only; add to the hunter's own value)
Notation: c = owner crit (fraction, higher of melee/ranged), h = owner ranged hit, Mpet = 1.25 happy x 1.15 UF x family (Cat 1.10) x 1.02 FF x 1.075 BW avg (= 1.73 for a happy cat), Mhawk = 1.15 UF x 1.02 FF (= 1.173), u = average number-of-hawks-up / 2 (0..1), L = landed fraction (miss/dodge/parry/glance).

- d(PetWhiteDPS)/d(RAP) = 0.10/14 x Mpet x Hmelee x Frenzy_speed x L x (1 + c_white)  ~= 0.0125 x L x speed  -> about 0.011-0.014 pet DPS per 1 RAP (per 1 AGI = 2 RAP: ~0.025). Only if RAP > melee AP; snapshot at summon.
- d(HawksDPS)/d(RAP) = 2u x 0.8/60 x Mhawk x Hranged x L x (1 + 0.5c + 0.10)  ~= 0.031 x u x Hranged x L  -> ~0.03 hawk DPS per 1 RAP at u=0.9, Hranged 1.15, L 0.9. Plus dive: 0.05/9 s x (1+c) ~= 0.006 per RAP when hawks are kept up (one cast per 9 s).
- d(HawksDPS)/d(ranged weapon DPS) = 2u x 0.8 x 14/60 x Mhawk x Hranged x L x (1 + 0.5c + 0.10) ~= 0.43 per +1 weapon DPS (u=0.9, Hranged 1.15, L 0.9, c 0.15). Pet: 0 (weapon DPS is not in RAP).
- Hit: +1% owner hit -> +1% landed attacks for pet (white + Claw/Bite) and hawks until 5% vs equal-level (pet tooltip; 8% vs +3 boss).
- Crit: +1% owner crit -> +1% crit on pet specials (Claw/Bite; ~flat damage) and +0.5% hawk crit; white pet swings: near zero on live (trueshot) — if fixed it would be +1% on white too. Also raises Frenzy uptime (proc 80% per crit, 8 s).
- Haste: generic Haste / melee haste -> pet swing faster (x(1+haste)) and hawks (via ranged speed if the haste is aura 342 type); ranged-only haste (quiver, Quick Shots) -> hawks only.
- Stamina -> 2 pet HP each (survival only); Armor -> 30% to pet and to hawks; Intellect -> 0; Spell power -> negligible (10% to pet spell damage, only magic pet abilities).
Relative per-RAP comparison (pre-armor, illustrative): hunter Auto Shot ~1/14 = 0.071 x hunter multipliers; hawks ~0.03-0.036; pet ~0.012. One hawk takes ~1.9x as much from a point of RAP as the tamed pet; two hawks ~3.7x.

---------------------------------------------------------------------------------------------------
## 7. Pet / hawk share of a BM hunter's damage
- trueshot PLAN.md (combat-log-calibrated sim): level 60 BM boss fights pet 30% of BM damage ("beta boss fights showed 30-36%"); level-30 beta stream Troll BM: pet melee ~26-27% of damage; task 54 note "pet is about 40% of BM damage" (leveling recheck at 35/40/45).
- Cargos (beta): UF 1.2% total DPS per 3% point -> pet+hawks ~40% of damage.
- Mobalytics (pre-Nov-10): hawks ~10% (5% dive + 5% melee).
- Qualitative: "Your pet is half of your damage while leveling" (stillsixty; conquestcapped).
=> For a level-43 BM leveling: pet ~30-40%, hawks ~10-15%, hunter ~50-55% (estimate from the above, not a direct measurement at 43).

---------------------------------------------------------------------------------------------------
## Sources (URLs)
- Blizzard hotfixes Nov 10 2026: https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-10-2026 ; forum https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-10-2026/2403040/6
- Blizzard Oct 15 beta notes (as relayed): https://patchmymain.com/classes/hunter/ ; https://wowforeverpets.com/blog/october-15-hunter-pet-nerfs-wow-forever ; https://crogin.com/wow/pages/beta-changes.html ; https://www.wowhead.com/blue-tracker/topic/us/wow-forever-beta-development-notes-updated-october-15-2360696
- Wowhead SV overview (pet scaling list): https://www.wowhead.com/forever/guide/classes/hunter/survival/overview-pve-dps
- conquestcapped pets guide: https://conquestcapped.com/guides/wow-forever/wow-forever-hunter-pets/
- forever-bugs: https://github.com/ClassicWoWCommunity/forever-bugs/issues/394 , /31 , /48 , /227 , /228 , /432
- wowsims/forever: https://github.com/wowsims/forever/blob/master/sim/hunter/pets.go , summon_hawk.go , talents_beast_mastery.go ; commits 77a901ae, 82230204, d729b139, 71d4f460
- trueshot: https://github.com/dj0le/trueshot (packages/data/overrides.toml, PLAN.md)
- wowsims/sod: https://github.com/wowsims/sod/blob/master/sim/hunter/pet.go , talents.go
- SoD blue post Dec 12 2023: https://www.bluetracker.gg/wow/topic/us-en/1739014-season-of-discovery-class-tuning-incoming-december-12/ ; https://us.forums.blizzard.com/en/wow/t/its-time-to-take-a-serious-look-at-hunter-pets/1765304
- Petopia Wrath scaling: https://www.wow-petopia.com/classic_lk/stats_scaling.php ; Wowhead forum https://www.wowhead.com/forums/topic/pet-scaling-coefficients-81660
- Cargos summary: https://www.mmogah.com/news/wow-forever/wow-forever-beast-mastery-hunter-leveling-guide-pet-scaling-reworked-hunters-get-their-strongest-version-yet
- Mobalytics BM leveling: https://mobalytics.gg/wow-forever/classes/beast-mastery-leveling-guide
- Summon Hawk ranks: https://wowforever.wiki.fextralife.com/Summon_Hawk ; https://talentsforever.com/hunter/talents/summon-hawk ; https://www.wowhead.com/forever/spell=1293525/summon-hawk
- UI source: https://github.com/Gethe/wow-ui-source/tree/forever (Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua, PaperDollFrameStats.lua, PaperDollFrameConstants.lua)
- Enums: https://github.com/TrinityCore/TrinityCore/blob/master/src/server/game/Spells/Auras/SpellAuraDefines.h ; https://github.com/simulationcraft/simc/blob/midnight/engine/dbc/data_enums.hh
