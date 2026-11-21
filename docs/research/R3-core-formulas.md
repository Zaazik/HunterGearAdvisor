# R3 — Core stat formulas for a Hunter (Classic 1.12 / Era 1.15 vs WoW Forever 1.60.1.70888)

Scope tags: **[F-client]** = proven from Forever client data (DB2 / gametables / Forever UI Lua / GlobalStrings of build 1.60.1.70888);
**[F-web]** = a web source explicitly about Forever; **[Classic]** = 1.12 / Classic Era (emulator source, Blizzard blue posts, Magey);
**[memory]** = unverified.

Working folder with every downloaded artefact: `C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/db2_R3-core-formulas/`
(gt/ = Forever gametables, gt_era/ = Era gametables, ui/gh/ = Forever ("Camelot") FrameXML from wow-ui-source branch `forever` @ commit "1.60.1 (70888)", src/ = vmangos/cmangos sources, web/ = forever-hunter wiki + Magey wiki copies).

---------------------------------------------------------------------------------------------------

## 0. Key discoveries about the Forever client (why many things are now provable)

1. Forever's game type is **"camelot"**. `Blizzard_UIPanels_Game.toc` (forever branch) loads, in order:
   `Camelot\PaperDollFrame.lua` → `Vanilla\PaperDollFrameStats.lua` → `Cata\PaperDollFrameStats.lua` → `Camelot\PaperDollFrameStats.lua` (toc lines 53-58).
   The last file wins for globals, so `ATTACK_POWER_MAGIC_NUMBER = 14` (Camelot/PaperDollFrameStats.lua:11) overrides the 3.5 in Camelot/PaperDollFrame.lua:35.
2. Forever DB2 **PlayerExpectedStat** (does NOT exist in Era 1.15.9 — wago returns "Table not found") has per class+level:
   `BaseMana, HPPerStamina, CritPerAgility, SpellCritPerIntellect` (+ an unnamed field that equals itemlevelbylevel.txt).
3. Forever **ChrClasses** Hunter: RangedAttackPowerPerAgility=2, AttackPowerPerAgility=1, AttackPowerPerStrength=1. In Era 1.15.9 the same columns are **0** (server-side there).
4. Forever ships **gametables/combatratings.txt** with flat, level-independent rating conversions (Era's file is a leftover retail curve), and Forever items carry rating stats (ItemSparse stat types 31 HIT_RATING ×184 items, 32 CRIT_RATING ×523, 36 HASTE_RATING ×4 (test/legendary only), 37 EXPERTISE ×8, 38 AP ×285, 39 RAP ×20, 43 MP5 ×226).
5. Forever removed `gametables/regenmpperspt.txt` and `octregenmp.txt` (present in Era 1.15.9) → Spirit regen is server-side in Forever (not provable from client).
6. Forever's `gametables/armormitigationbylvl.txt` is byte-for-byte the retail 12.1.5 table (L60 "Constant" = 1059); it is a mainline-engine leftover and NOT the vanilla armor constant (vanilla K at L60 = 5500). Armor formula therefore unproven for Forever.

---------------------------------------------------------------------------------------------------

## 1. Agility

| Effect | Formula | Scope / source |
|---|---|---|
| Ranged AP | +2 RAP per AGI | [F-client] ChrClasses.RangedAttackPowerPerAgility=2; GlobalStrings HUNTER_AGILITY_TOOLTIP lists "Ranged Attack Power by %d"; [Classic] vmangos `GetAttackPowerFromStrengthAndAgility` (src/game/StatSystem.cpp) `level*2 + agility*2 - 10` |
| Melee AP | +1 MAP per AGI | [F-client] ChrClasses.AttackPowerPerAgility=1; HUNTER_MELEE_ATTACK_POWER_TOOLTIP "Increased by Strength and Agility"; [Classic] vmangos `level*2 + strength + agility - 20` |
| Crit (melee AND ranged, same value) | crit% = AGI × CritPerAgility(level) ; hunter base crit = 0 | [F-client] PlayerExpectedStat.CritPerAgility; UI: `increasedRangedCritChance = increasedMeleeCritChance` (Camelot/PaperDollFrameStats.lua ~line 318); [Classic] vmangos table `player_crit_per_agility` (migration 20260703210621_world.sql, sniffed) |
| Armor | +2 armor per AGI | [F-client] `ARMOR_PER_AGILITY = 2` (Camelot/PaperDollFrameStats.lua:6); [Classic] vmangos `Player::UpdateArmor` `GetStat(STAT_AGILITY) * 2.0f` |
| Dodge | dodge% = AGI / DodgePerAgi(level); hunter base dodge 0 | [Classic] vmangos `player_dodge_per_agility` (20260711022757_world.sql). [Forever] value comes from API `GetDodgeChanceFromAttribute()`; not in client data → unproven |

### 1a. Hunter Agility per 1% crit — FOREVER client = CLASSIC sniffed table (identical)

Forever PlayerExpectedStat (ClassID 3) value is crit-fraction per point; Agility per 1% = 0.01 / CritPerAgility.
Compared row by row with vmangos sniffed Classic table — identical to 3-4 significant digits at every level vmangos has (vmangos lacks 46 and 55, which it interpolates).

| Level | Forever CritPerAgility | AGI per 1% crit (Forever) | vmangos Classic | Spell crit: INT per 1% (Forever) | Base mana (Forever) |
|---|---|---|---|---|---|
| 1 | 0.002174 | 4.60 | 4.59982 | 14.29 | 65 |
| 10 | 0.001471 | 6.80 | 6.7981 | 17.86 | 206 |
| 20 | 0.000658 | 15.20 | 15.1976 | 25.00 | 451 |
| 30 | 0.000417 | 23.98 | 23.9808 | 32.90 | 775 |
| 40 | 0.000303 | **33.00** | 33.0033 | 41.49 | 1105 |
| 41 | 0.000296 | 33.78 | 33.7838 | 42.19 | 1135 |
| 42 | 0.000287 | 34.84 | 34.8432 | 42.19 | 1180 |
| 43 | 0.000279 | **35.84** | 35.8423 | 43.48 | 1210 |
| 44 | 0.000272 | 36.76 | 36.7647 | 44.25 | 1240 |
| 45 | 0.000265 | **37.74** | 37.7358 | 45.66 | 1270 |
| 46 | 0.000259 | 38.61 | (interp.) | 46.51 | 1300 |
| 47 | 0.000253 | 39.53 | 39.5257 | 47.17 | 1330 |
| 48 | 0.000245 | 40.82 | 40.8163 | 48.54 | 1360 |
| 49 | 0.000239 | 41.84 | 41.841 | 49.26 | 1390 |
| 50 | 0.000234 | **42.74** | 42.735 | 50.76 | 1420 |
| 52 | 0.000224 | 44.64 | 44.6429 | 52.08 | 1480 |
| 55 | 0.000209 | **47.85** | (interp. ≈47.64) | 55.87 | 1570 |
| 58 | 0.000197 | 50.76 | 50.7614 | 58.48 | 1660 |
| 60 | 0.000189 | **52.91** | 52.9101 | 60.61 | 1720 |

Full 1-60 table: run the python snippet in this research session or read `db2_R3-core-formulas/PlayerExpectedStat.csv` (ClassID=3).
Other Classic confirmations of the 60 value: Blizzard blue (2005) "Hunters require 53 Agility for an additional 1% critical hit chance" (quoted in Wowhead classic hunter stat guide); bluetracker Eyonix post: "Prior to the Burning Crusade, Hunters had an intercept of 0 … 53 points of agility per critical strike percent" → base crit 0.
cmangos-classic uses a LINEAR approximation (3.5 at L1 → 53 at L60) — wrong at intermediate levels; do not use.

### 1b. Hunter Agility per 1% dodge (Classic only, vmangos sniff)
L40 16.50 · L43 17.89 · L45 18.90 · L50 21.41 · L55 ≈23.85 (interp 23.42/24.27) · L60 26.53. Blizzard blue: "Hunters require 26.5 AGI for an additional 1% dodge". Forever: unproven (client has no table).

---------------------------------------------------------------------------------------------------

## 2. Strength
- Hunter: +1 melee AP per STR, **no ranged AP**. [F-client] ChrClasses AttackPowerPerStrength=1, HasStrengthAttackBonus=1; RANGED_ATTACK_POWER_TOOLTIP says RAP is "Increased by Agility" only. [Classic] vmangos melee formula.
- Block value from STR: Classic `STR/20 - 1` block value (vmangos `GetShieldBlockValue`), Forever UI `BLOCK_VALUE_PER_STRENGTH = 20`. Hunters cannot use shields → irrelevant.

## 3. Stamina
- HP = baseHP + min(STA,20)×1 + max(STA-20,0)×10. [Classic] vmangos `GetHealthBonusFromStamina`. [F-client] PlayerExpectedStat.HPPerStamina = 10 at every level; gametables/hppersta.txt = 10 at all levels (Era's leftover file has 14…36); UI `STAMINA_BREAK = 20` and tooltip formula `min(20,sta) + (max(20,sta)-20)*UnitHPPerStamina` (Camelot/PaperDollFrameStats.lua ~line 287).
- Forever base HP hunter (gametables/basehp.txt, new in Forever): L40 667, L43 775, L45 842, L50 1032, L55 1237, L60 1467 (Classic L60 1467 per wow-guides.com 1.12 DB read).

## 4. Intellect
- Mana = baseMana + min(INT,20) + max(INT-20,0)×15. [Classic] vmangos `GetManaBonusFromIntellect`. [F-client] UI `INTELLECT_BREAK = 20; MANA_PER_INTELLECT = 15` (Camelot/PaperDollFrameConstants.lua:24-26) and the INT tooltip uses them.
- Spell crit from INT (Forever): INT × SpellCritPerIntellect (L43 43.48 INT per 1%, L60 60.61). Hunters gain little from spell crit (Forever community: hunter DoTs crit with ranged crit, not spell crit — forever-hunter wiki Stat-Mechanics).
- INT also raises weapon-skill gain rate (Forever GlobalStrings DEFAULT_INTELLECT_TOOLTIP "Increases Weapon Skill improvement rate").
- NOT taken by this character but relevant: Forever Careful Aim 5/5 = AP and RAP += 100% of INT (auras 580 + 598, bp 100, curve 20/rank) → with Careful Aim INT ≈ 0.5 AGI for ranged AP.

## 5. Spirit, MP5, five-second rule
### Classic (vmangos `Unit::GetRegenMPPerSpirit`, `Player::UpdateManaRegen`, `Player::Regenerate`)
- Hunter mana per 2-s tick (outside FSR) = **15 + SPI/5** → per second 7.5 + 0.1×SPI → per 5 s 37.5 + 0.5×SPI.
  Era client table gametables/regenmpperspt.txt Hunter = 0.100000 mana/sec per Spirit at every level (consistent with SPI/5 per 2 s).
- Inside the 5-second rule (5 s after any mana spend) spirit regen = 0 × (15+SPI/5) unless an aura 134 (MOD_MANA_REGEN_INTERRUPT) exists: in-FSR regen = mp5/5 + (15+SPI/5)/2 × (aura134%/100) per second… exactly: `m_modManaRegenInterrupt = mp5/5 + spiritRegenPerSec × min(aura134,100)/100`.
- **MP5 (aura 85 / ItemSparse stat 43) ticks always**, in and out of FSR: per 2-s tick = MP5 × 0.4.
- HP regen out of combat (hunter) per 2-s tick = max(0, 0.43×SPI − 5.5); ×1.5 while sitting; zero in combat (vmangos `GetRegenHPPerSpirit`, `RegenerateHealth`). Medium confidence (emulator constant).
### Forever
- FSR confirmed: GlobalStrings DEFAULT_SPIRIT_TOOLTIP: "Increases Mana Regeneration by %d per 5 sec while not casting … Mana Regeneration from Spirit is halted for 5 sec after spending Mana". HP regen "while not in combat".
- Sitting HP regen multiplier in Forever = ×1.333 (SPIRIT_STANDING_WARNING "+33% while sitting"; Lua `spiritStandingPenalty = 0.75`, Camelot/PaperDollFrameStats.lua:296) vs Classic emulator ×1.5.
- Spirit→regen coefficients: removed from the client (regenmpperspt.txt absent) → **unproven for Forever**; assume Classic 15+SPI/5 per 2 s.
### Bestial Discipline 2/2 (taken)
- Forever DB2 spell 19590 effect 1 = aura 134 (MOD_MANA_REGEN_INTERRUPT), bp 50; curve 82816 r1=25, r2=50.
- Meaning (Classic aura semantics): while inside the FSR, 50% of Spirit-based regen (the whole "15 + SPI/5" term) continues. Per 5 s at level 43 with e.g. 60 SPI: outside FSR 37.5+30 = 67.5 mana/5s; inside FSR 33.75 + MP5. MP5 is unaffected (always 100%).
- Practical: with BD 2/2, 1 Spirit = 0.5 mp5 out of FSR and 0.25 mp5 inside FSR; 1 MP5 = 1 mp5 always → 1 MP5 ≈ 2-4 Spirit for in-combat mana.

---------------------------------------------------------------------------------------------------

## 6. Attack power formulas and AP→DPS

| | Classic 1.12 (vmangos + cmangos, identical) | Forever |
|---|---|---|
| Ranged AP | `RAP = 2×Level + 2×AGI − 10` + gear/buff RAP + AP | per-stat coefficients proven (ChrClasses); level term/constant NOT in client → unproven (assume Classic) |
| Melee AP | `MAP = 2×Level + STR + AGI − 20` + gear AP | same caveat |
| note | warcraft.wiki.gg Attack_power table lists hunter ranged as `Level×2 + (AGI×2 − 20)` (post-TBC wiki); the two emulators both use −10. Only the constant differs; weights unaffected. | |

- **14 AP = 1 DPS**: [F-client] GlobalStrings RANGED_ATTACK_POWER_TOOLTIP "Every 14 Ranged Attack Power adds 1 damage per second", MELEE_ATTACK_POWER_TOOLTIP same for melee, `ATTACK_POWER_MAGIC_NUMBER = 14` (Camelot/PaperDollFrameStats.lua:11). [Classic] vmangos `CalculateMinMaxDamage`: `GetTotalAttackPowerValue(attType) / 14.0f * att_speed`.
- Damage per auto attack = weaponDamage + AP/14 × **base** weapon speed (haste does not shrink it) → DPS gain from AP is AP/14 regardless of weapon speed.
- Normalized abilities (vmangos `GetAPMultiplier(normalized)`): ranged 2.8, 2H 3.3, 1H 2.4, dagger 1.7, unarmed 2.4. Forever community testing: Aimed Shot / Multi-Shot use RAP/14×2.8 + full weapon damage roll + ammo; Auto Shot and Scatter Shot use real speed (forever-hunter wiki Attack-Formulas, [F-web], medium).
- Ammo: adds ammoDPS × weapon speed per ranged shot (forever-hunter wiki; Classic same).
- Consequence for weights: +1 ranged weapon DPS ≥ +14 RAP (equal on Auto Shot; better on normalized shots for speed>2.8 weapons since the full weapon roll is added). Zygor's built-in BM weights (DPS 2.4 vs RAP 0.43 → 1 DPS ≈ 5.6 RAP) undervalue weapon DPS relative to this formula.

---------------------------------------------------------------------------------------------------

## 7. Combat ratings in Forever (new vs Classic)
[F-client] gametables/combatratings.txt (Forever build) — same value at every level 1-123:
- Hit (melee/ranged/spell) **10 rating = 1%**; Crit (melee/ranged/spell) **14 rating = 1%**; Haste **10 = 1%**; Expertise 10 = 1%; Armor penetration column 10; Dodge 12; Parry 15; Block 5; Defense skill 1 rating = 1 skill.
- Era's file has a leftover retail curve (L60: hit 8, crit 14, haste 12.5 …) but Classic Era items don't use ratings ("+1% hit" are equip auras).
- ForeverDB (foreverdb.net/stats/hunter) and stillsixty.com (Forever) state the same 10/14/12/15/5 values [F-web].
- One Hit rating / one Crit rating applies to melee, ranged and spells (ITEM_MOD_HIT_RATING / ITEM_MOD_CRIT_RATING are the common stat types 31/32 in ItemSparse) — stillsixty [F-web].

---------------------------------------------------------------------------------------------------

## 8. Hit / attack table

### Classic (Blizzard blue posts via Magey's wiki; Beaza formulas; vmangos `SpellCaster::GetMeleeMissChance`)
- vs mob, defense − skill ≤ 10: miss = 5% + (Def − Skill)×0.1%.
- vs mob, defense − skill ≥ 11: miss = 5% + (Def − Skill)×0.2%, and the first (Def−Skill−10)×0.2% of +hit is ignored ("hit suppression"; Blizzard: first 1% ignored at 300 vs 315).
- vs player: 5% + (Def − Skill)×0.04%. Mob below level 10: miss × level/10.
- Mob defense = 5×mobLevel. With maxed skill (5×yourLevel): equal 5.0%, +1 5.5%, +2 6.0%, +3 **8.0% base + 1% suppression = 9% hit cap**. With +5 skill vs +3: 6.0%, no suppression.
- Table by skill gap (Magey): 15→8.0% (cap 9.0), 14→7.8 (8.6), 13→7.6 (8.2), 12→7.4 (7.8), 11→7.2 (7.4), 10→6.0 (6.0) … 0→5.0.
- Ranged attacks: no dodge, no parry, no glancing; can be blocked from the front (Blizzard forum hunters, Icy Veins classic hunter, forever-hunter wiki). vmangos disables block as well ("Intentional: ranged attacks only roll for miss and crit in our implementation").
- Crit vs higher mobs: −0.2% crit per point (Def − min(Skill, 5×yourLevel)) → −1% per level (Blizzard: "reduced by 1% per each additional level"); +skill above 5×level does NOT restore crit vs mobs. Extra **−1.8%** applied to crit from auras (talents like Lethal Shots/Lethal Attacks, "+1% crit" gear, buffs) vs +3 mobs; Agility crit not affected (Magey crit-aura-suppression research). Total vs boss typically −4.8%.
- Weapon skill vs crit (own sheet): vmangos `UpdateCritPercentage` adds (skill − 5×level)×0.04% to displayed crit.

### Forever client evidence (conflicts with Classic on suppression)
- GlobalStrings CR_HUNTER_HIT_CAP_TOOLTIP: "To never miss Raid Bosses: **8.00% Melee/Ranged**, 17.00% Spells, **27.00% Dual Wielding**; To never miss Lvl N targets/players: **5.00% Melee/Ranged**, 4.00% Spells, **24.00% Dual Wielding**".
- Camelot/SkillsFrame.lua (Forever weapon-skill detail panel): hit/dodge/parry AND crit change by **0.04% per point** of (5×targetLevel − skill), linear, boss = level 63 (lines 44-58). This is a different model from Classic's 0.1/0.2%.
- Camelot/PaperDollFrameStats.lua:460 has an unused local `meleeMissChances = {5.0, 5.2, 5.4, 9.0}` (contradicts the 8% string).
- [F-web] SixtySim (Forever sim site): "beta logs against level +3 targets show none of Classic's extra hit penalty" → cap 8%. wowhandbook.com (Forever data): miss 5 / 5.5 / 6 / 8%. Other Forever sites (stillsixty, Warcraft Tavern, wowcalc, wowfdb) still say 9% but explicitly "carried over from Classic / unverified".
- **Conclusion**: Forever ranged hit cap vs +3 = 8% per Blizzard's own tooltip (medium confidence); Classic = 9%. Leveling vs equal/+1/+2 mobs: 5 / 5.5 / 6% (Classic-proven, consistent with Forever tooltip for equal level).
- Hunter hit sources in tree: Surefooted 3/3 (+3% melee and ranged hit, auras 54+55) — not taken.

---------------------------------------------------------------------------------------------------

## 9. Crit damage
- Ranged and melee crit = **200%** damage (+100%). [F-client] GlobalStrings STAT_HUNTER_CRIT_BONUS: "Melee and Ranged critical strikes deal 100% increased damage". [Classic] same (Wowhead classic hunter stat guide: physical crit 200%, Mortal Shots → 230%).
- Mortal Shots 5/5 (not taken): Forever spell 19485 aura 108 misc 15 (SPELLMOD_CRIT_DAMAGE_BONUS) bp 30 → ranged ability crit = 230%.
- Predator's Edge 5/5 (not taken): melee ability crit damage +30% (230%) and Off-Hand weapon damage +50% (aura 122) — Forever DB2 spell 1310627.
- Value of 1% crit = +1% × (critMult − 1) of the crit-eligible damage (0.01 for 200%, 0.013 with Mortal Shots).

---------------------------------------------------------------------------------------------------

## 10. Armor
- Classic: `DR = Armor / (Armor + 400 + 85 × AttackerLevel)`, cap 75% (vmangos `CalcArmorReducedDamage`: `0.1*armor/(8.5*L+40)` then x/(1+x); warcraft.wiki.gg Armor page for levels 1-59).
- Forever: cap 75% confirmed (GlobalStrings ARMOR_MAX_EFFECTIVENESS_TOOLTIP). Formula itself unproven (UI calls C_PaperDollInfo.GetArmorEffectiveness; the shipped armormitigationbylvl.txt is the retail 12.1.5 table, not vanilla).

## 11. Level difference (non-attack-table)
- Physical damage has no level-based damage multiplier in Classic; higher-level mobs only bring higher miss/crit suppression (above), higher dodge/parry/glancing for melee, and more armor. (vmangos damage pipeline has none; Classic sources above.) Forever: no contrary evidence found.

## 12. Melee-only mechanics (matter only for weaving / Raptor Strike / Mongoose Bite)
- **Dual wield miss**: white swings +19% miss while an off-hand weapon is equipped (Classic: Magey PTR data "DualWieldMissChance = NormalMissChance + 19%"; vmangos). Specials/yellow attacks unaffected. Forever tooltip: 24% vs equal level, 27% vs boss (= 5+19, 8+19).
- **Off-hand damage** = 50% of [weapon dmg + MAP/14 × OH speed] (warcraft.wiki.gg Attack_power; forever-hunter wiki). Predator's Edge +10%/rank OH damage in Forever.
- **Glancing** (white melee vs higher-level mobs, players' melee only, never ranged): chance = 10% + (5×TargetLevel − min(5×AttackerLevel, Skill))×2% → 10/20/30/40% for Δlevel 0/1/2/3. Damage of a glance: low = 1.3 − 0.05×(Def−Skill) (cap 0.91), high = 1.2 − 0.03×(Def−Skill) (min 0.2, cap 0.99), avg penalty ≈ 5% (Δ0-1), 15% (Δ2), 35% (Δ3 at 300 skill). Hunters are NOT in vmangos CLASSMASK_WAND_USERS so they use the melee-class formula. (Magey Attack-table; vmangos `GetGlancingBlowDamageMultiplier`). Forever UI computes these via C APIs GetGlancingBlowChance/Penalty (values not visible).
- Mob dodge vs your melee: 5% + 0.5%/level (Classic Blizzard; Forever UI constant BASE_ENEMY_DODGE_CHANCE = {5.0, 5.5, 6.0, 6.5}). Mob parry +3 = 14% (Classic; Forever CR_RANGED_EXPERTISE_TOOLTIP also says 14.00%, CR_EXPERTISE_TOOLTIP says 16.50%). Mobs parry only from the front.
- Dual Wield skill for hunters at level 20 (Forever SkillRaceClassInfo MinLevel 20, from shared context).

## 13. Haste
- Forever: 10 haste rating = 1% (combatratings.txt); haste on items is essentially absent (only test/legendary items). Ranged haste = base + ammo/quiver haste (UI `GetRangedHaste()` returns `baseRangedHaste, ammoHaste`).
- Deadly Aspects (taken 5/5): Quick Shots spell 6150 = aura 140 (MOD_RANGED_HASTE) +30% for **12 s** (SpellMisc DurationIndex 29 = 12000 ms); Quick Strikes 1299448 = aura 319 +30% melee haste, 12 s. Proc 10% per Auto Shot (curve 2/rank).

## 14. Pet inheritance (Forever-specific; for the pet researcher)
- GlobalStrings MELEE_ATTACK_POWER_PET_HUNTER_TOOLTIP: pet AP "Increased by 10% of Master's Attack Power from whichever is higher: Melee or Ranged" (UI constant HUNTER_PET_BONUS["PET_BONUS_AP_CONVERSION"] = 0.3 in Camelot/PaperDollFrame.lua:52 — conflicts with the 10% string).
- STAT_HUNTER_PET_CRIT_BONUS: pet crit "Increased by 100% of Master's Critical Strike Chance". Pet hit: "Pets inherit 100% of the owner's hit chance" (Camelot/PaperDollFrameStats.lua, PaperDollFrame_SetHitChance).
- ⇒ In Forever, hunter Agility/crit/hit also raise BM pet damage (not true in Classic).

---------------------------------------------------------------------------------------------------

## 15. Quick numbers for a level-43 hunter (Forever, everything Classic-proven unless noted)
- 1 AGI = 2 RAP + 1 MAP + 0.0279% crit (35.84 AGI = 1%) + 2 armor + ~0.056% dodge (Classic table 17.89).
- 14 RAP = +1 ranged DPS on Auto Shot; 1 ranged weapon DPS = 14 RAP on Auto Shot, more on Aimed/Multi.
- 14 crit rating = 1% crit; 10 hit rating = 1% hit (flat across levels).
- Hit caps: equal-level 5%, +1 5.5%, +2 6%, boss 8% (Forever tooltip) / 9% (Classic).
- 1 STA = 10 HP (after the first 20); 1 INT = 15 mana (after the first 20).

## Sources
- Forever DB2 (wago.tools build 1.60.1.70888): PlayerExpectedStat, ChrClasses, GlobalStrings, ItemSparse, SpellDuration; existing shared DB2 (SpellEffect, SpellMisc, SpellName).
- Forever gametables via `https://wago.tools/api/casc/<fdid>?download&build=1.60.1.70888`: combatratings.txt (1391669), hppersta.txt (1391642), basemp.txt (1391664), basehp.txt (6859293), armormitigationbylvl.txt (1385707); absent in Forever: regenmpperspt.txt (2238240), octregenmp.txt (2238239), chancetomeleecrit.txt (3999262). Era 1.15.9.70576 comparison in gt_era/.
- Forever UI: https://github.com/Gethe/wow-ui-source/tree/forever (commit message "1.60.1 (70888)"): Interface/AddOns/Blizzard_UIPanels_Game/{Blizzard_UIPanels_Game.toc, Camelot/PaperDollFrame.lua, Camelot/PaperDollFrameConstants.lua, Camelot/PaperDollFrameStats.lua, Camelot/SkillsFrame.lua}.
- vmangos: https://github.com/vmangos/core (src/game/StatSystem.cpp, src/game/Objects/Player.cpp, Unit.cpp, SpellCaster.cpp, ObjectMgr.cpp; sql/migrations/20260703210621_world.sql crit/agi, 20260711022757_world.sql dodge/agi; commits 2c8df6bb44, d8a1636210).
- cmangos-classic: https://github.com/cmangos/mangos-classic (src/game/Entities/StatSystem.cpp, Player.cpp).
- Magey: https://github.com/magey/classic-warrior/wiki/Attack-table (Blizzard blue quotes + Beaza formulas + PTR DW data).
- https://www.bluetracker.gg/wow/topic/eu-en/285038681-25-04-eyonix-on-hunters/ (hunter crit intercept 0, 53 agi/1% pre-TBC).
- https://www.wowhead.com/classic/guide/classes/hunter/dps-stat-priority-attributes-pve (2005 blue post: 53 agi/crit, 26.5 agi/dodge; 200% crit, Mortal Shots 230%).
- https://wow-guides.com/knowledge/attributes (1.12 DB read: hunter 52.91 agi/crit at 60, 26.53 dodge, base HP 1467 / mana 1720).
- https://warcraft.wiki.gg/wiki/Armor , https://warcraft.wiki.gg/wiki/Attack_power , https://warcraft.wiki.gg/wiki/Attack_table
- https://us.forums.blizzard.com/en/wow/t/hunter-wow-classic-question-crossbow-skills/1182265 (ranged can't dodge/parry/glance, can be blocked)
- https://www.icy-veins.com/wow-classic/hunter-dps-pve-stat-priority
- Forever web: https://foreverdb.net/stats/hunter ; https://sixtysim.com/guides/hunter/survival/stats/ ; https://www.stillsixty.com/guides/stats-and-attributes ; https://wowhandbook.com/bis/hunter/ ; https://github.com/classic-hunter/forever-hunter/wiki (Ranged-Attack-Table, Attack-Formulas, Stat-Mechanics, Forever-Hunter-Patch-Notes).
