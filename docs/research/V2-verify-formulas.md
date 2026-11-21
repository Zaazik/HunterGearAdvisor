# V2-verify-formulas: adversarial check of R3 (core formulas) and R4 (ability formulas)

Date 2026-11-12. Forever client 1.60.1.70888. Downloads: `scratchpad/db2_V2-verify-formulas/ws/` (wowsims/forever master `sim/core/target.go`, `spell_outcome.go`, `unit.go`, `character.go`).

## What I re-checked myself (local data)

| Item | Where | Result |
|---|---|---|
| PlayerExpectedStat hunter L40/43/45/50/55/60 CritPerAgility, BaseMana, SpellCritPerIntellect | db2_R3-core-formulas/PlayerExpectedStat.csv | L43 0.000279 (35.84 AGI/1%), L60 0.000189 (52.91). Base mana 1105/1210/1270/1420/1570/1720. Matches R3 |
| vmangos crit-per-agility sql class 3 | src/vm_crit_per_agi.sql lines 150/153/155/168 | 33.0033 / 35.8423 / 37.7358 / 52.9101. Same values |
| ChrClasses | db2/ChrClasses.csv; era/ChrClasses.csv | Hunter RAP/AGI 2, AP/AGI 1, AP/STR 1 (Era 0/0/0). **Caveat:** Warrior RAP/AGI = 2, AP/STR = 2; Rogue RAP/AGI = 2. vmangos Classic gives warrior and rogue ranged AP = level + AGI − 10 (1 per AGI). So the column either changed for those classes in Forever or means something else. The hunter values agree with Classic either way |
| GlobalStrings 13882, 14243, 14269, 60046, 60051-60054, 60062, 60188, 60217, 60229, 59054, 59069, 17416, 23446 | db2_R3-core-formulas/GlobalStrings.csv | Text matches what R3 quoted. CR_HUNTER_HIT_CAP_TOOLTIP is word-for-word the same as the ROGUE and WARRIOR versions (8 / 17 / 27%, 5 / 4 / 24%). Era GlobalStrings has no hit-cap tooltip at all (new in Forever) |
| Forever UI Lua | db2_R3-core-formulas/ui/gh/Camelot_*.lua | ATTACK_POWER_MAGIC_NUMBER = 14 (Stats:11), ARMOR_PER_AGILITY = 2, the unused `meleeMissChances = {5.0, 5.2, 5.4, 9.0}` (Stats:460), SkillsFrame 0.04 per point (lines 50/54), PET_BONUS_AP_CONVERSION = 0.3 (PaperDollFrame:52; feeds a format number that the hunter tooltip string never prints, because "10%%" is hard-coded in it). Pet hit = owner MELEE hit (GetHitModifier) + pet modifier (Stats:529-532) |
| combatratings.txt | gt/1391669.txt | Every level 1-60: dodge 12, parry 15, block 5, hit 10/10/10, crit 14/14/14, haste 10, expertise 10. Confirmed |
| basehp.txt | gt/6859293.txt | Hunter L40 667, L43 775, L45 842, L60 1467. Confirmed |
| ItemSparse rating counts | db2_R3-core-formulas/ItemSparse.csv | 32:523, 38:285, 43:230 (R3 said 226), 31:184, 39:20, 37:8, 36:4 |
| Spell data (bp, cast, CD, category, duration) | db2_R4-ability-formulas/f vs era, scripts_R4/dump.py | Every R4 rank table matches DB2: AotH 20/35/50/70/90/110/120; AotB 50/70/90/110; HM 26/59/98/143; Arcane 25…280; Serpent 3…135; Aimed 40/70/115/185/260/350; Hawk 32/47/85/108 (+ e3 = 5); Raptor 5/11/21/30/35/40/55/70; Mongoose 15/22/37/57; TSA 20/35/50/75/100; Sniper 320/450/590. Aimed cast 2000 ms (Era 3000). Aimed and Multi share category 2 (6 s); Era Multi is in category 85 (10 s). Arcane and Hawk share category 1173. Multi-Shot ranks 14288/14289/14290/25294 are missing from Forever SpellName. Quick Shots 6150 and Quick Strikes 1299448: 30%, 12000 ms. Rapid Fire: aura 140 bp 40 + aura 319 bp 40, and also aura 110 and aura 134 at bp 0 (a talent fills them, per the $?$w2 text) |
| SpellEquippedItems | f/ vs era/ | Auto Shot subclass mask 262156 = bow, gun, crossbow (no thrown). Raptor, Wing Clip, Mongoose (Forever only) and Counterattack (Forever only): mask 173555, which includes 1H and 2H maces, but hunters have no mace skill. Quivers 29413: bow + crossbow; ammo pouch 14824: gun |
| Talent curves | hunter_talents_forever.txt lines 108-156 | UF curve 3/6/9/12/15 (bp 20); Ferocity 2…10 (bp 16); Lethal Attacks 1…5; Focused Fire 1/2; Bestial Discipline e1 25/50; Deadly Aspects 2…10. A spell's bp is sometimes the rank-1 value (Frenzy 20, Lethal 1) and sometimes the max-rank value (FF 2, BD 50, ET 15). UF 20 and Ferocity 16 fit neither, so those bp are stale Classic-like numbers |
| Mortal Shots 19485 | f/SpellEffect | aura 108 misc 15 bp 30. Mask word 0 = 424449 includes bit 0 = Auto Shot (mask 1), so it applies to Auto Shot |
| vmangos AP / regen | src/vmangos_StatSystem.cpp:203, vmangos_Unit.cpp:6255-6320 | Hunter RAP = 2L + 2AGI − 10. HP regen 0.43·SPI − 5.5. MP 15 + SPI/5. Matches R3 |

## Independent web checks

- Blizzard dev notes 3 Nov (forum post #9). Confirmed: Aimed bonus ~+110%. Arcane base +30% and AP coefficient 0.1 → 0.15. Serpent AP per tick 3% → 5% and base +20%. AotH 20/35/50/70/90/110. TSA 20/35/50/75/100. Sniper +100%. Barrage 5/10/15. Traps share one 30 s CD. HM ranks no longer stack.
- Wowhead hotfixes 10 Nov (383837). Confirmed: Arcane Shot and Summon Hawk cost 11% of base mana. "Melee damage dealt by the Hawk pet increased by about 80%." Pets' 150% HP corrected to 115%.
- Blizzard Class Deep Dive. Confirmed: Aimed Shot baseline at 20. Arcane no longer shares a CD with Aimed. Multi-Shot shares with Aimed. AotB gives melee AP. UF "decreased slightly", Ferocity "decreased", both now reach hawks. Improved Hunter's Mark is baseline. BD = Spirit regen while casting. Lethal Attacks covers all attacks. "Pets now get increased stats based on their Hunter's gear." "**Pets can no longer receive player buffs that increase their stats.**" Surefooted hit now applies to all attacks.
- sixtysim BM (28 Oct, wowsims engine): hit cap 8%, "beta logs … show no extra hit penalty". "A tenth of that attack power and all of that crit reach the cat." "A boss three levels above you takes 4.8% off [crit]." Weights in AGI: weapon DPS 2.33, RAP 0.27 (so **1 ranged weapon DPS ≈ 8.6 RAP**), hit 14.6 per 1%, crit 12.4 per 1%, haste 11.7 per 1%. This is a 33/13/5 build with Careful Aim; the user is 32/2/0.
- sixtysim SV: weapon DPS 1.69 and RAP 0.20 (1 DPS ≈ 8.5 RAP).
- foreverdb.net/stats/hunter uses the same client data as R3. It is not an independent source, but it agrees.
- wowsims/forever `sim/core/target.go` (`newAttackTableHand`, `NewAttackTable`):
  - miss = 5% + 0.1%·skillDiff (gap ≤ 10) or 5% + 0.2%·skillDiff (gap > 10). `GetPhysicalMissChance` = BaseMiss − hit, with **no hit suppression**, plus 19% for white attacks while dual wielding.
  - mob dodge 5 + 0.1%·gap; parry 5 + 0.6%·gap when gap > 10 (14% at +3); block min(5%, …); glance 10% + 2%·gap, multipliers clamp(1.3 − 0.05·gap, .01, .91) / clamp(1.2 − 0.03·gap, .2, .99).
  - MeleeCritSuppression 0.2%·gap. AuraCritSuppression 1.8% vs +3 ("Era logs show no aura crit suppression against targets 1 or 2 levels above"). Spell miss 4% + 1%/level, 17% at +3.
  - So the Forever sim drops only the hit suppression and keeps Classic's 0.1/0.2 miss slope. It does **not** use the UI's 0.04 per point.
- wowsims pets.go: pet AP = 0.1 · max(MAP, RAP), "read on a level 17 pet sheet at two gear states". Pet crit = max(melee, ranged) owner crit. Pet hit = owner ranged hit. summon_hawk.go: hawk AP = 0.8·(RAP + 7 + 14·Ranged().DPS()). In wowsims, `Ranged().DPS()` includes ammo, because core_attack.go:84 adds bonusDps·SwingSpeed to BaseDamage. The swing coefficient 0.0417 per AP was measured *with* UF 5/5 and FF 2/2. Its log point "1180 at 747 RAP with a 27.3 dps bow" gives 747 + 7 + 14·27.3 = 1136, not 1180, so the formula is an approximate fit.

## Verdict notes (arguments)

- **R3-weapon-dps-vs-rap is wrong as stated.** One normalized shot gains S damage per +1 weapon DPS and 2.8 damage per +14 RAP, so weapon DPS ≥ 14 RAP only when S ≥ 2.8. RAP also feeds Arcane (0.15), Serpent (0.25), hawk dive (0.05), traps and Volley, and weapon DPS feeds none of those. Both feed Auto Shot and hawk AP equally. The Forever sim measures 1 DPS ≈ 8.6 RAP (BM 60). Zygor's 5.6 is low, but not by the 2.5× that R3 implied.
- **R3-hitcap-forever.** The 8% cap has two independent supports: the Blizzard tooltip, and wowsims' log-fitted table with no suppression. The tooltip alone is weak, because it is shared by three classes and lists "17% spells to never miss", which is a raw base-miss table. Use 0.1/0.2 per skill point for mobs, not the UI's 0.04: +1 5.5%, +2 6.0%, +3 8.0%.
- **R3-pet-inherit conflict resolved: 10%.** Supported by the tooltip, wowsims (pet sheet readings) and sixtysim. The 0.3 constant is never printed in the hunter tooltip.
- **R3-agi-crit-forever.** "Base crit = 0" is proven only for Classic; Forever base crit is server-side (R3 itself and foreverdb say so).
- **R4-hawk-pet / R4-rap-derivatives.** Hawk "weapon DPS" includes ammo DPS (wowsims). 0.0133 DPS per RAP is the value *with* UF 5/5 and FF 2/2 (correct for this user), not "before modifiers". Before talents it is ≈ 0.0114.
- **R4-melee-norm-oh.** Missing: an equipped off-hand adds +19% miss to the *main-hand* white swings as well. Raptor Strike replaces a white MH swing (attr0 0x4, next swing), so its net gain over that swing is the flat bonus plus no glance and no DW penalty. For a BM 32/2/0 hunter, melee weapons matter mostly for their stats.
- **R4-volley.** 0.03 sits in EffectBonusCoefficient (the spell-power column) on dummy effect 0, not on the damage spell 1279721 (coef 0). Reading it as RAP is wowsims' assumption.
- **R3-crit-suppression.** The Forever sim keeps it (sixtysim "takes 4.8% off"), but its own source is Era logs. Unverified in Forever.
