# HunterGearAdvisor — W1's remaining open questions, the wowsims way (design)

Design for the open questions of `docs/research/W1-wowsims-check-2026-11-16.md` ("Open questions", lines 148-195) that
the raid-mode design (`docs/superpowers/specs/raid-mode-design.md`, below "RMD") does not settle. The user settled RMD
open point O3: W1's other open questions go wowsims' way, each where wowsims states a rule (the user's «берем как в вов
симс»). No code is changed by this document; section 11 is the implementation order, section 12 the user's answer on
the one call it raised (U2, DoT procs: designed in RMD 17); the hawk speed and the pet's crit below the maximum skill are
settled by O3 (sections 7 and 4).

The user's later decisions of 2026-11-17 hold here as in RMD: no tuning command or setting (RMD 14: the target follows
the mode, 0 below 60 and +3 at 60, and the hit cap follows the target), the Survival branch's melee is wowsims' SV Weave
(RMD 15, in place of the `/hga melee` time share and the weave flag), the unarmed main hand swings at 1.0 s (RMD 16) and
DoT procs are priced as wowsims prices them (RMD 17).

## 0. Conventions and sources

- Roots as RMD section 0. `wowsims/` = the read-only wowsims/forever clone
  `C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/wowsims/src` (never run). `DB2/` = the Forever DB2
  exports of build 1.60.1.70888 under `C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/`. `UI/` = the Forever UI repo
  (`git show HEAD:<path>`, HEAD `1.60.1 (70888)`).
- HGA paths are relative to the `raid-mode` worktree. HGA code line numbers are those of commit `fddaf12` (the commit
  RMD cites), read with `git show fddaf12:<path>`, except where a line says "HEAD `1db4d89`" (RMD step 8, committed).
  Tests are cited by name only (their line numbers move with every step), by their names at HEAD `dfa7300`. Steps 1-9
  of RMD are committed on the branch (`4e1a574` .. `dfa7300`, with their review commits), so the functions named here
  are RMD's where RMD changes them. RMD 14-16 (group A of RMD 12) come before W3 and rename the melee-share tests that
  W4 names (RMD 15.9): the step that implements W4 maps each name to its RMD 15 successor.
- A DB2 citation names the table and the row ID. Numbers marked **(my arithmetic)** are computed by me from the cited
  values, not output of wowsims (which was not run). "My reading" marks a conclusion drawn from code read, not run.
- The project's rules hold: an invalid state raises; comments in English with sources, present tense, no history; UI
  text in Russian; Lua 5.1; every rule gets a test that fails on a mutant (each new test names its mutant).
- Both modes as RMD 2.1: levelling (`p.mode == "level"`, below 60) and raid (`p.mode == "raid"`, level 60, +3). Every
  rule below is a mechanic and holds in both modes unless a line says otherwise; below 60 wowsims' formulas run at the
  lower level through the level difference and the 5 × level skill (RMD approximation A9).

## 1. The questions and what is settled elsewhere

W1's open list and where each is decided:

| W1 open question | Where |
|---|---|
| stats-gear-8 crit suppression | RMD 4.2 |
| The Highborne Research Tablet's chance per hit | RMD 4.6.1 |
| Serpent Sting's applications and a bow's proc; an equip proc's own mask | RMD 4.6.2 |
| Beastslaying's flat damage | RMD 4.5 |
| (by design) ranged-4, stats-gear-12, melee-sv-12 in raid | RMD 6.4, 7, 7.3 |
| stats-gear-7 weapon skill (ranged and melee) | section 3 (change) |
| pet-hawk-bm-1 pet white crit; pet crit from weapon skill above 5 × level (and W1's pet-hawk-bm-15, the same mechanic below the maximum) | section 4 (change; W1's record corrected in W6) |
| pet-hawk-bm-8 the dive's flat damage per rank of Unleashed Fury and Ferocity | section 5 (change) |
| ranged-7 Improved Arcane Shot with Summon Hawk | section 6 (change) |
| Hawk speed (which owner speeds reach the hawks) | section 7 (change; W1's record corrected in W6) |
| pet-hawk-bm-5 hawk expertise; melee-sv-5 Lacerating Strikes; Ranged Weapon Specialization on the dive with a bow; Rot-Covered Harpoon's rate; hit cap at +1 / +2 | section 8 (same rule on both sides: no change) |
| Serpent Sting at a high melee share | RMD 15 (the Survival weave casts it from the shooting spot); section 8 |
| stats-gear-6 ranged weapon DPS weight; ranged-1 haste weight | section 9 (no wowsims rule: nothing proposed) |

## 2. Summary

| Item | wowsims rule | HGA (`fddaf12`) | Differ | Change | Step |
|---|---|---|---|---|---|
| stats-gear-7 ranged | the ranged hand's miss and crit suppression by its skill (`target.go:562-597`) | 0.04% hit and 0.04% crit a point (`Score.lua:358-360`, `Advisor.lua:119, 132-133`) | yes | `Model.SkillMiss` / `Model.SkillHit`, `p.rangedSkill`, suppression by the deficit, `W.SKILL_CRIT` | W3 |
| stats-gear-7 melee | each melee hand's miss, dodge, glance and crit suppression by its skill | melee skill not valued (`Advisor.lua:185-188`), not parsed, set bonuses not generated | yes | melee skill keys, per-hand table, priced through the weapon run, a melee hit term, a per-hand dual-wield term | W4 |
| pet / hawk crit | `max(0, melee, ranged)` sheet crit, each branch less 0.04% a point of its hand's skill below the maximum (`pets.go:147-153`); hawks half (`summon_hawk.go:83`) | the ranged crit with the skill's ±0.04% a point, always (`Model.lua:543, 528`; `Advisor.lua:133`) | yes | ranged branch with the penalty below the maximum only (W3); the melee branch and `max` (W4) | W3, W4 |
| pet-hawk-bm-8 | the dive's base + 3 a rank of Unleashed Fury + 2 a rank of Ferocity, flat | none (`Model.lua:519`) | yes | the flats in the dive's base | W1 |
| ranged-7 | the shared category ready 6 − 0.3 × rank s after Arcane Shot, 6 s after Summon Hawk | 1 Arcane per 18 s with hawks (`Model.lua:480`) | yes (rank > 0) | HHA cycle `18 − 0.3 × rank` | W2 |
| hawk speed | the owner's ranged speed multiplier only (`pet.go:415-431`) | the owner's ranged speed and every aura-342 source and haste rating (`Model.lua:438`) | yes | split of `p.haste` | W5 |
| pet-hawk-bm-5, melee-sv-5, RWS on the dive, Serpent at a high melee share, harpoon rate, +1/+2 cap | — | — | no | none | — |
| stats-gear-6, ranged-1 | EP numbers of a simulation | analytic derivatives | model difference | none | — |

## 3. stats-gear-7 — weapon skill

### 3.1 Rule (wowsims)

- Each hand has its own attack-table entry built from the skill of the weapon it holds (`wowsims/sim/core/target.go:549-604`
  `AttackTableHand`, `newAttackTableHand`, `setWeapons`; `weapon_skill.go:10-39` `GetWeaponSkill`: the bonus of the
  weapon's skill over the level-based maximum 5 × level, the main hand's or off hand's own bonus on top, 0 for an empty
  hand; `weapon_skill.go:85-94` rebuilds the entries on a weapon change). With `levelDiff = min(target − attacker, 3)`
  (`target.go:536-538`), `bonus` = the hand's skill − 5 × level:
  - `skillDiff = 5 × levelDiff − bonus`; `baseSkillDiff = 5 × levelDiff − min(bonus, 0)` (`target.go:563-567`);
  - miss `0.05 + 0.001 × skillDiff` while `skillDiff ≤ 10`, else `0.05 + 0.002 × skillDiff` (`target.go:581-585`);
  - dodge `0.05 + 0.001 × skillDiff` (`target.go:574`; read for the attack's hand, `unit.go:1179-1180`); parry `0.05 +
    0.001 × baseSkillDiff` up to 10, `0.05 + 0.006 × baseSkillDiff` past it (`target.go:586-590`, from the front only);
  - glance chance `clamp(0.1 + 0.02 × baseSkillDiff, 0, 1)`; glance damage `[clamp(1.3 − 0.05 × skillDiff, 0.01, 0.91),
    clamp(1.2 − 0.03 × skillDiff, 0.2, 0.99)]` (`target.go:576-578`);
  - `MeleeCritSuppression = 0.002 × baseSkillDiff` when `baseSkillDiff > 0`, else `0.0004 × baseSkillDiff`
    (`target.go:591-595`), the hand's part of `physicalCritSuppression` (`spell_result.go:224-231`).
  So skill above the maximum lowers miss and dodge and raises glancing damage but leaves parry, glance chance and crit
  suppression alone; skill below it raises all of them (`attack_table_test.go:87-157`, the sword hand at +3: 285 skill
  miss 11%, dodge 8%, parry 23%, glance 70% at 0.01-0.30, crit suppression 6%; 300: 8 / 6.5 / 14 / 40% at 0.55-0.75 /
  3%; 305: 6 / 6 / 14 / 40% at 0.80-0.90 / 3%; 315: 5 / 5 / 14 / 40% at 0.91-0.99 / 3%).
- Which hand an attack uses: a ranged proc mask the ranged entry, an off-hand-only mask the off hand's, everything else
  the main hand's (`target.go:606-615`). Shots and Serpent Sting's application roll `BaseMissChance − hit` of the ranged
  entry (`spell_outcome.go:566-571`, no dual-wield penalty); the dive (`summon_hawk.go:135`, `ProcMaskRangedSpecial`)
  and Serpent Sting's ticks (`serpent_sting.go:28`) take the ranged entry's crit suppression; a proc spell
  (`ProcMaskEmpty`) and Lacerating Strikes' bleed (`talents_survival.go:189`) the main hand's. A magic proc's spell miss
  is the table's level-based one, no hand's (`spell_result.go:287-288` reads `attackTable.BaseSpellMissChance`).
- The pet and the hawks: their own tables at skill bonus 0 (level-60 units, `pet.go:107`; no weapon:
  `weapon_skill.go:17-19`), so the owner's skill reaches them only through their inherited crit (section 4).
- Supporting data (Forever): the client's hit cap text gives 8% against raid bosses (GlobalStrings 60052
  `CR_HUNTER_HIT_CAP_TOOLTIP`), stated for the level's skill only: wowsims' table at 300 (`5 + 0.2 × 15`, my arithmetic)
  and HGA's `baseMiss(3)` (`Core/Model.lua:233-237`) both give it, so it checks the level part and not the slope a skill
  point. The Forever UI's Skills frame computes `(5 × (level + offset) − skill) × −0.04` for hit and crit
  (`UI/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua:44-55`): at 300 against a raid boss −0.6% hit
  (my arithmetic), so a 5% base with that hit gives 5.6%, not the client's own 8% (B.md "Подавление крита", "Навык
  оружия"): the frame is no rule of the game's miss. No Forever source states the slope a skill point; it comes from
  wowsims' table by O3. HGA's `Score.SKILL_STEP` is the Skills-frame slope.

### 3.2 HGA today

- Ranged: `Score.SKILL_STEP = 0.04` (`Core/Score.lua:358-360`); `A.State` puts the worn skill's effect into the model
  point as `p.rangedHit = skillShift` and `p.crit + skillShift`, `skillShift = 0.04 × (shown − 5 × level)`
  (`Game/Advisor.lua:117-133`); `Score.setValue` prices a set's skill against the worn at `W.CRIT_RANGED × skillHit` and
  through the shots' cap in `hitValue` (`Core/Score.lua:639-671, 692-697`), a set without shots at
  `−W.CRIT_NO_SHOTS × shift` (`Score.lua:669-670`; `W.CRIT_NO_SHOTS`, `Core/Model.lua:830-838`).
- Melee: not valued (`Game/Advisor.lua:185-188`); the melee skill item lines are not in `STAT_TEMPLATES`
  (`Core/Parse.lua:41-47` holds the ranged lines only); the set generator maps skill auras of Defense, Bows, Guns and
  Crossbows only (`tools/gen_set_data.py` HEAD `1db4d89`:77 `SKILL_KEYS`), so the five melee skill set bonuses of build 70888 are
  `unknown` in `Game/SetData.lua` (section 3.4); the melee table uses `baseMiss(mobDiff)`, `Model.MobAvoid`,
  `Model.GlanceMult` at the level's skill (`Core/Model.lua:233-275, 602-686`).
- W1 records this as "Kept the Forever UI slope" (W1 line 23); by O3 it goes wowsims' way (3.1's last point: no Forever
  source states the slope, and the Skills frame is no rule of the game's miss).
- A worn thrown weapon and no ranged weapon: the level's skill (`Game/Advisor.lua:97-117`; test_game `a worn thrown
  weapon: no shots, the level's skill (skillShift 0) whatever the thrown line's skill`, which moves in W3: it reads
  `ctx.skillShift`).

### 3.3 Change — ranged hand (step W3)

Model (`Core/Model.lua`):
- `Model.SkillMiss(mobDiff, bonus)` (%): `sd = 5 × capDiff(mobDiff) − bonus`; `sd ≤ 10 → 5 + 0.1 × sd`, else
  `5 + 0.2 × sd` (`target.go:581-585`). `baseMiss(d)` becomes `Model.SkillMiss(d, 0)` (the same values at bonus 0).
- `Model.SkillHit(mobDiff, bonus) = Model.SkillMiss(mobDiff, 0) − Model.SkillMiss(mobDiff, bonus)`: the hit a hand's
  skill gives against the level's skill (negative below the maximum). It jumps at the 10-point gap (my arithmetic:
  +3, bonus 4 → 0.8, bonus 5 → 2.0; +0, bonus −10 → −1.0, bonus −11 → −2.2), as wowsims' table does.
- New required number `p.rangedSkill` (`REQUIRED_NUMBERS`, `Core/Model.lua` HEAD `1db4d89`:178): the ranged hand's skill
  bonus over 5 × level (signed). It is read for the crit only; the shots' hit keeps coming from `p.rangedHit`
  (unchanged in the model: `shotHitf`, RMD 6.4's `q`). A.State sets it (as it sets `p.rangedHit`; `Player.Snapshot`
  does not).
- Crit suppression (extends RMD 4.2): the skill part per hand is
  `skillSupp(bonus) = 0.002 × (5 × d + max(0, −bonus))`. For `d ≥ 0` this is wowsims' rule exactly: `baseSkillDiff =
  5d + max(0, −bonus) ≥ 0`, and it is 0 only at `d = 0, bonus ≥ 0`, where both branches of `target.go:591-595` give 0
  (my reading; HGA has no target below the player's level, RMD 4.1). Shots, the dive and Serpent Sting's ticks take
  `skillSupp(p.rangedSkill)` in `supp(...)` (RMD 4.2 `critR`); the pet and the hawks keep bonus 0.
- `p.crit` is the live ranged crit, read as the sheet's crit without the weapon skill: A.State no longer adds a skill
  crit. Source: wowsims models the sheet that way, the hit and crit percents as physical + ranged + scoped mods and the
  crit suppression, which holds the hand's skill part, as a field apart (`wowsims/sim/core/character_sheet.go:13-44`
  `sheetAttackStats`, `sheetCritSuppressionPercent`). wowsims' model, not checked in game: the Forever UI source shows
  the sheet values as they come (HGA's own note, `Core/Score.lua:650-654`). The same reading holds for the live hit,
  so the skill's hit enters apart as `p.rangedHit`.
- The pet's and hawks' crit, ranged branch (section 4): `petCritBase = max(0, crit + 0.0004 × min(p.rangedSkill, 0))`
  (W3); W4 adds the melee branch.

Advisor (`Game/Advisor.lua` A.State, lines 97-170):
- `rangedBonus = rangedSkill.shown − 5 × snap.level` (0 with no bow, gun or crossbow, as today);
  `model.rangedSkill = rangedBonus`; `model.rangedHit = ns.Model.SkillHit(model.mobDiff, rangedBonus)`;
  `model.crit = snap.model.crit`. `model.mobDiff` is the mode's target: 0 below 60, 3 at 60 (RMD 14.2).
- ctx: `skillShift` is replaced by `skillBase = rangedSkill.skill − 5 × snap.level` (the worn line's trained skill
  against the level's) and `mobDiff = model.mobDiff`.

Score (`Core/Score.lua` setValue, lines 639-697):
- `Score.SKILL_STEP` is removed. A set with shots has the bonus `b = ctx.skillBase + skillPoints(set, ctx, bonusStats)`
  (`skillPoints`, lines 511-519, unchanged: the set's items' and reached set bonuses' points for its line plus the
  piece's `skillOffset`); the worn set's is `bWorn = ctx.skillBase + wornSkillPoints(ctx)` (= shown − 5 × level).
- Hit: the shots' term of `hitValue` (RMD 4.7.1's three-term form) takes `sk = ns.Model.SkillHit(ctx.mobDiff, b)` in
  place of `shift + skillHit`: `W.HIT_RANGED × (min(h + r + sk, cap) − min(h + r, cap))`. A set without shots keeps the
  worn skill's hit there, `sk = Model.SkillHit(ctx.mobDiff, bWorn)` (today's rule, `Score.lua:659-661`).
- Crit, with `deficit(x) = max(0, −x)`: a set with shots `v = v + W.SKILL_CRIT × (deficit(bWorn) − deficit(b))`; a set
  without shots (bonus 0, `weapon_skill.go:17-19`) `v = v + W.SKILL_CRIT_NO_SHOTS × deficit(bWorn)`.
- ctx checks: `ctx.skillBase` and `ctx.mobDiff` missing are errors (as `ctx.skillShift` today, `Score.lua:663-664`).

Model.Weights:
- `W.SKILL_CRIT = (Total(p with rangedSkill = b0) − Total(p with rangedSkill = b0 − 1)) / unitDps`,
  `b0 = min(p.rangedSkill, 0)`: one point further below the maximum, one-sided because the crit parts start at 0
  (wowsims' suppression and the pet's penalty both count `min(bonus, 0)`). It holds the ranged hand's suppression
  (shots, Serpent ticks, the dive) and, while the pet's ranged branch wins at that point, the pet's 0.04% and the hawks'
  0.02% a point (section 4: from W4 none at equal sheet crits).
- `W.SKILL_CRIT_NO_SHOTS`: the same at `qn` (`noShots = true`, `bowDPS = 0`, today's `W.CRIT_NO_SHOTS` point,
  `Model.lua:837`), the crit of what still attacks without shots: the pet, the hawks and the dive.
- `W.CRIT_NO_SHOTS` is removed (its only reader is the skill line, `Score.lua:670`). `W.CRIT_RANGED` stays (the crit
  scope, `Parse.lua` `CRIT_RANGED`).

UI (Russian):
- Tooltip of a ranged weapon of another line (`Game/Advisor.lua:630-637`):
  `HGA: навык %s %d/%d (%s) — меткость выстрелов %+.1f%%, крит выстрелов %+.1f%% (по правилу wowsims)` with
  `Model.SkillHit(d, have − 5L) − Model.SkillHit(d, shown − 5L)` and `−0.2 × (deficit(have − 5L) − deficit(shown − 5L))`.
- `/hga weights` skill line (`Game/Commands.lua:63-78`): `capHit = ctx.baseHit + snap.gearHit + snap.setHit +
  snap.rangedGearHit + Model.SkillHit(ctx.mobDiff, bWorn)`; text `навык %s %d/%d против %d по уровню: меткость выстрелов
  %+.1f%%, крит выстрелов %+.1f%%`. The crit field `крит %.2f%% (в листе %.2f%%)` (`Commands.lua:107-108`: the model's
  crit against the sheet's) prints two equal numbers once the model's crit is the sheet's: it becomes `крит %.2f%%`
  (the skill's crit effect is on the skill line).
- `/hga dump`: the field `skillShift = st.ctx.skillShift` (`Game/Commands.lua` HEAD `1db4d89`:189) becomes
  `skillBase = st.ctx.skillBase, mobDiff = st.ctx.mobDiff`; the model's `rangedSkill` comes through `model = st.model`
  (the dump writes the whole model point).
- `tools/preraid/rescore/rescore.lua` (`stateAt`, HEAD `1db4d89`:280-325): `rangedSkill = 0`, `rangedHit = 0`,
  `skillBase = 0`, `mobDiff` in ctx (a bow at 300 skill); its weapon-run cache key stays (the ranged skill is priced in
  Score).

### 3.4 Change — melee hands (step W4)

The melee part counts only in the Survival branch's weave (RMD 3, RMD 15: one main-hand swing slot a cycle, the off
hand's swings by RMD 15.3's share, Raptor Strike, Strider Kick, Mongoose Bite and Wing Clip at the melee look); the
main hand's skill also reaches the pet's crit (section 4) and the physical proc tables (below) in every build.

Parse (`Core/Parse.lua:41-47`), templates (`Game/Templates.lua:4-31`, `tests/fixtures_templates.lua`):
- Ten `STAT_TEMPLATES` pairs, `INCREASE` and `DECREASE` (negated): `TOOLTIP_ITEM_STAT_SKILL_SWORDS` → `SKILL_SWORDS`,
  `_MACES` → `SKILL_MACES`, `_AXES` → `SKILL_AXES`, `_FIST_WEAPONS` → `SKILL_FIST`, `_DAGGERS` → `SKILL_DAGGERS`,
  `_STAVES` → `SKILL_STAVES`, `_TWO-HANDED_SWORDS` → `SKILL_2H_SWORDS`, `_TWO-HANDED_MACES` → `SKILL_2H_MACES`,
  `_TWO-HANDED_AXES` → `SKILL_2H_AXES`, `_POLEARMS` → `SKILL_POLEARMS` (GlobalStrings 59290-59309: enUS
  `DB2/db2_R3-core-formulas/GlobalStrings.csv:26515-26534`, e.g. `Equip: Increased Axes +%1$d.`; ruRU
  `DB2/db2_ru/GlobalStrings.csv:26584-26603`, e.g. `Если на персонаже: повышение навыка использования топоров на %1$d.`).
  The twenty keys join `KEYS` and both locales of the fixtures. The six `TWO-HANDED` names hold a hyphen, so the fixture
  tables write them as `["TOOLTIP_ITEM_STAT_SKILL_TWO-HANDED_SWORDS_INCREASE"] = …` (the fixtures use identifier keys
  today); `KEYS` holds them as strings already. `Game/Items.lua` `API_MAP` gets no melee key: no source read here names
  the `GetItemStats` keys for them (the tooltip templates carry the stat). (Group 0, RMD 18.9: GlobalStrings 58882-58908
  name them; the ten melee keys are mapped.)
- `Score.MELEE_SKILL` by weapon subclass (DB2 ItemSubClass class 2, as `Game/Player.lua:10-13` maps subclasses to skill
  lines): 0 → `SKILL_AXES`, 1 → `SKILL_2H_AXES`, 4 → `SKILL_MACES`, 5 → `SKILL_2H_MACES`, 6 → `SKILL_POLEARMS`, 7 →
  `SKILL_SWORDS`, 8 → `SKILL_2H_SWORDS`, 10 → `SKILL_STAVES`, 13 → `SKILL_FIST`, 15 → `SKILL_DAGGERS`. These keys stay out
  of `ItemValue`'s stat loop (as the ranged skill keys, `Score.lua:389`) and out of setValue's set-bonus loop (the
  `RANGED_SKILL_STAT` exclusion, HEAD `1db4d89` `Score.lua:617`, becomes one set of every skill key), so no weight
  lookup meets them.

Set bonuses (`tools/gen_set_data.py` HEAD `1db4d89`:77 `SKILL_KEYS`, `Game/SetData.lua` regenerated):
- `SKILL_KEYS` gets the ten melee lines by their SkillLine ids (`Game/Player.lua:10-13` `WEAPON_SKILL`): 43
  `SKILL_SWORDS`, 44 `SKILL_AXES`, 54 `SKILL_MACES`, 55 `SKILL_2H_SWORDS`, 136 `SKILL_STAVES`, 160 `SKILL_2H_MACES`,
  172 `SKILL_2H_AXES`, 173 `SKILL_DAGGERS`, 229 `SKILL_POLEARMS`, 473 `SKILL_FIST`.
- Five set bonuses of build 70888 carry `A_MOD_SKILL` (aura 30) on a melee line and are `unknown` in `Game/SetData.lua`
  today (HEAD `1db4d89`): 7534 Daggers +1 (161 Defias Leather, 5 pieces), 7574 Daggers +3 (1585 Insulated Leathers, 3),
  7523 Swords +3 (1800 The Twin Blades of Hakkari, 2), 15763 Swords +6 (461 The Twin Blades of Hakkari, 2), 1324675
  Swords +1 (2136 Defias Enforcer's Garb, 4) (`DB2/db2/SpellEffect.csv` rows of these spells: aura 30, misc 173 / 43,
  base points as listed; the sets from `ItemSetSpell.csv` of the `db2dl` export; read with a script of mine, and the
  same five spells are the `unknown` "Increased Dagger" / "Increased 1H Sword" entries of `Game/SetData.lua`). They
  become `stats = { SKILL_DAGGERS = n }` / `{ SKILL_SWORDS = n }`.

Model:
- New required numbers `p.mhSkill`, `p.ohSkill` (the hands' skill bonuses over 5 × level; 0 for an empty hand,
  `weapon_skill.go:17-19`) and `p.meleeHit` (the main hand's skill hit, `Model.SkillHit(d, mhSkill)` at the model point;
  the melee counterpart of `p.rangedHit`), set by A.State.
- The hunter's melee (RMD 4.3's single roll), per hand, as fractions: main-hand special miss `missMH = max(0,
  Model.SkillMiss(d, 0) − p.hit − p.meleeHit) / 100`; main-hand white miss the same with `+ 19` inside with dual wield;
  off-hand white miss `max(0, Model.SkillMiss(d, p.ohSkill) + 19 − p.hit) / 100`; dodge per hand `max(0,
  Model.SkillDodge(d, bonus) − p.expertise) / 100` with `Model.SkillDodge(d, b) = 5 + 0.1 × (5d − b)` (= `Model.MobAvoid(d)`
  at b = 0); glance per hand `Model.Glance(d, bonus)` (RMD 4.3's `Model.Glance(d)` with the skill: chance from `5d +
  max(0, −b)`, damage bounds from `5d − b`); crit per hand `critM_hand = max(0, meleeCrit − supp_hand)` with
  `skillSupp(bonus)` of 3.3. Raptor Strike, Mongoose Bite, Strider Kick, Wing Clip (RMD 15: `ProcMaskMeleeMHSpecial`,
  `wowsims/sim/hunter/wing_clip.go:15`) and Lacerating Strikes' bleed take the main hand's entry (3.1). The pet and the
  hawks call `Model.Glance(d, 0)` and keep `Model.MobAvoid(d)`. In the weave (RMD 15) these are the rolls of the main
  hand's one swing slot a cycle and of the melee look's abilities; the off hand's white roll prices only its share of
  RMD 15.3.
- Where the code changes (HEAD `1db4d89`, RMD step 8): `Core/Model.lua:418` computes one `Model.Glance(mobDiff)` for
  every white swing and `white(miss, dodge, parry, crit)` (427-430) reads it from the closure; the melee block shares
  one `dodge`, `whiteMiss`, `wmiss` and `whiteRoll = white(whiteMiss, dodge, 0, critM)` between the main hand and the off
  hand (736-747), one `hitSpecial = 1 − miss − dodge` (754), and `mhLanded` / `ohLanded` from the one `wmiss` (785-786).
  W4 gives `white` the glance of its attacker (`white(miss, dodge, parry, crit, gChance, gAvg)`; the pet and the hawks
  pass the level's) and splits each of those per hand: `whiteRollMH = white(whiteMissMH, dodgeMH, 0, critM_MH, glance
  of mhSkill)`, `whiteRollOH` likewise with the off hand's, `hitSpecial = 1 − missMH − dodgeMH`, `mhLanded` with
  `whiteMissMH + dodgeMH`, `ohLanded` with the off hand's.
- `Model.ProcOutcomes` (RMD 4.6.4): a melee- or ranged-defense proc spell has `ProcMaskEmpty` and rolls the main hand's
  entry (`target.go:606-615`), in every build (a hunter of any branch may hold a melee weapon below its skill):
  - melee: miss `max(0, Model.SkillMiss(d, p.mhSkill) − p.hit) / 100`, dodge `max(0, Model.SkillDodge(d, p.mhSkill) −
    p.expertise) / 100` (the hand's `BaseDodgeChance`, `target.go:574`, read for the attack's hand at
    `unit.go:1179-1180`), crit `critM` of the main hand (`skillSupp(p.mhSkill)`);
  - ranged: the same miss and crit, no dodge (the ranged table has none, RMD 4.6.4);
  - magic: the level's spell miss (`spell_result.go:287-288`, no hand).
- `Model.Weights`:
  - `W.HIT_MELEE = d(Total) / d(p.meleeHit)` at `q0` (hit, rangedHit, rangedGearHit and meleeHit at 0) over `unitDps`: the
    main hand's specials and white swings under the specials' cap; 0 outside the Survival branch (no weave, RMD 15).
  - The dual-wield point `qd` (HEAD `1db4d89` `Core/Model.lua:1123-1129`: `qd.hit = Model.HitCap(p.mobDiff) + 0.5`,
    `qd.rangedHit = 0`) also sets `qd.meleeHit = 0`: with a worn main hand below the maximum (`p.meleeHit < −0.5`) its
    specials would still miss there and their slope would enter the weight.
  - `W.HIT_DW` keeps its meaning, the derivative by `p.hit` at `qd`: both hands' white swings past the specials' cap.
    New `W.HIT_DW_MH`: the derivative by `p.meleeHit` at `qd`, the main hand's white swings alone. The off hand's part is
    `W.HIT_DW − W.HIT_DW_MH`. Both 0 outside the Survival branch; in the weave the off hand's part is its share of
    RMD 15.3 (0 for an off hand slower than the visit allows), so `W.HIT_DW − W.HIT_DW_MH` is mostly 0 there.

Advisor:
- `A.State`: `model.mhSkill`, `model.ohSkill` from the worn weapons' lines (`Player.WeaponSkill(line) − 5 × level`,
  `Game/Player.lua:78-82`; 0 for an empty hand); `model.meleeHit = Model.SkillHit(model.mobDiff, model.mhSkill)`;
  `ctx.meleeTrained(line)` = the line's live skill less the worn set's bonuses to it (the rule `rangedSkill.skill` uses,
  `Advisor.lua:113-114`), less 5 × level: a bonus over the level's maximum; `ctx.wornMeleeHit = model.meleeHit`.
- `weaponModelFor` (`Advisor.lua:34-54`): each set's `mhSkill` / `ohSkill` = `ctx.meleeTrained(line of the hand's
  weapon) + the set's items' and reached set bonuses' points for that line` (a new `Score.MeleeSkills(set,
  ctx)`); the run sets `p.mhSkill`, `p.ohSkill` to them and holds `p.meleeHit` at the model point's; the cache is keyed
  by (ranged, main hand, off hand, mhSkill, ohSkill). The worn set gives exactly 0 (its skills are the model point's).
- Score without `ctx.weaponGain` for a set whose melee skills differ from the worn set's is an error (melee skill is
  priced only by the run; Advisor always passes `weaponGain`, `Advisor.lua:154`).

Score `hitValue` (each set's `skM = Model.SkillHit(ctx.mobDiff, set's mhSkill)`, `skO = Model.SkillHit(ctx.mobDiff,
set's ohSkill)` from `Score.MeleeSkills`; `room(x, n) = min(max(x − cap, 0), n)`):
- The main hand's skill hit enters the melee consumers' cap: `x = x + W.HIT_MELEE × (min(h + skM, cap) − min(h, cap))`.
- Dual wield, per hand: `x = x + W.HIT_DW_MH × (room(h + skM, 19) − dwFromMH) + (W.HIT_DW − W.HIT_DW_MH) × (room(h, 19 −
  skO) − dwFromOH)`. The main hand's white misses reach 0 at `h + skM = cap + 19`; the off hand's at `h = cap + 19 −
  skO` (its miss `SkillMiss(d, ohSkill) + 19 − h`, my arithmetic with `cap = SkillMiss(d, 0)`), so its room past the
  cap is `19 − skO` and its own skill hit never reaches the main hand. With `ctx.weaponGain`: `dwFromMH = room(ctx.wornHit
  + ctx.wornMeleeHit, 19)` (the run holds `p.meleeHit` at the worn's) and `dwFromOH = room(ctx.wornHit, 19 − skO)` at
  the set's `skO` (the run already prices the off hand's skill at the worn hit, so the set adds only its hit beyond the
  worn hit in its own room); without it both are 0 (and the skills are the worn's, by the error above). At skill 0 on
  both hands this is today's `W.HIT_DW × (pastCap(h) − dwFrom)` exactly.
- `ctx.wornMeleeHit` missing with `ctx.weaponGain` is an error (as `ctx.wornHit`, HEAD `1db4d89` `Score.lua:666`).

UI (Russian): the tooltip of a melee weapon or a melee skill item in a Survival build:
`HGA: навык %s %d/%d — в ближнем бою (ветка Выживания): промах %+.1f%%, скользящие %d%% по %.0f%%, крит %+.1f%%`; out of
Survival: `HGA: навык %s — ближний бой не в счёт (не ветка Выживания)`. `/hga weights` prints `W.HIT_DW_MH` beside
`W.HIT_DW` (`сверх капа с двумя оружиями %s, из них правая рука %s`). `/hga dump`: the model's `mhSkill`, `ohSkill`,
`meleeHit` come through `model = st.model`; it adds `meleeSkill = { mh = { line, shown, trained }, oh = { … } }` for the
worn hands (as `rangedSkill`).

`tools/preraid/rescore/rescore.lua` (`stateAt`): `ctx.meleeTrained(line) = 0` for every line (every melee line at 300
= 5 × 60, as the bow's `skillBase` 0; wowsims' racials hold no weapon skill, `sim/core/racials.go` has no skill term, so
the orc it models has none); `ctx.wornMeleeHit`; its weapon run sets `p.mhSkill`, `p.ohSkill` from
`Score.MeleeSkills(set, ctx)` and its cache key adds them (`rescore.lua` HEAD `1db4d89`:294); the model point's
`mhSkill = ohSkill = meleeHit = 0`.

### 3.5 Both modes

The same formulas at `d = capDiff(p.mobDiff)` and the level's 5 × level (RMD A9 below 60). Effect (my arithmetic):
raid, a bow at 305 skill: the shots' base miss 6% (wowsims) against 7.8% today; levelling at 43, a crossbow at 200 of
215 (bonus −15) against a same-level mob: miss 8%, crit suppression 3% (wowsims) against 5.6% and −0.6% today.

### 3.6 Tests

Fixtures and required inputs (each step that adds a required input):
- W3 `rangedSkill`, W4 `mhSkill`, `ohSkill`, `meleeHit`, W5 `attackSpeed`, `hasteRating` join `REQUIRED_NUMBERS`
  (`Core/Model.lua`), test_model's `ref` (0), test_score's `fullP` (`fill(…, 0)`), the list of test_model `a model input
  every producer sets is required: one missing or of the wrong type is an error naming it; the optional ones may be nil`
  (its mutant: the key left out of `REQUIRED_NUMBERS`), and `rescore.lua`'s point. test_game builds the model through
  `A.State` and `Player.Snapshot`, which set them; no new client API is read. Its skill stub (`G.C_SkillInfo
  .GetSkillLineInfoByID`, "the weapon lines at 215") answers lines 43, 44, 45, 46, 136, 173 and 226 only, and from W4
  `A.State` reads the worn melee hands' lines through `Player.WeaponSkill`, which raises on a line without info: the
  stub gains the hunter's other melee lines 55, 172, 229 and 473 at 215 (`Game/Player.lua:24-27` `HUNTER_SKILLS`), so a
  test that wears such a weapon keeps the level's skill. (Group 0, RMD 18.1: the stub's lines follow the level, 5 x the
  level, Polearms from 20.)
- W3 replaces `skillShift` by `skillBase` and `mobDiff` in test_score's ctx builder (the `ctx` function at the top of
  test_score, `skillShift = 0`), which every Score test goes through; W4 adds `wornMeleeHit = 0` there.

Moves, W3. Rule: every test whose expected value reads `ctx.skillShift`, `Score.SKILL_STEP`, a 0.04-a-point skill hit or
crit, or `W.CRIT_NO_SHOTS` moves; each is re-derived by hand from 3.3, its name follows the new rule, and the step
measures the moves. By name (HEAD `1db4d89`):
- test_score: `ranged weapon skill: the set's own ranged line's bonuses go through the shots' capped hit and the ranged
  crit, once`; `ranged weapon skill: measured against the worn set; a piece's skillOffset counts; it never lowers
  dual-wield misses`; `ranged weapon skill: a skill loss past the cap costs the ranged crit only`; `ranged weapon skill:
  the shots' cap counts the worn skill's hit against 5 points a level (ctx.skillShift)`; `ranged weapon skill: the worn
  skill's shift never lowers dual-wield white misses`; `a Use hit buff counts its hit parts and, in a dual-wield set, its
  dual-wield part (Nat Pagle's Broken Reel 231271)`; `hit below 0% (a hit debuff): no floor, every attack and the shots
  priced linearly`; `ranged weapon skill: a set without shots has the level's skill; only what still attacks takes its
  crit change`; `dual-wield hit past the cap with ctx.weaponGain: beyond ctx.wornHit itself, whatever the worn ranged
  skill's shift`; `a W without a weight the scorer names is an error where it is read` (`CRIT_NO_SHOTS` →
  `SKILL_CRIT`, `SKILL_CRIT_NO_SHOTS`); `score: a set's RANGED_HIT meets the shots' and the pet's cap at W.RANGED_HIT,
  never melee's`; `a set counts one buff per Use spell: …` (through the ctx builder).
- test_game: `snapshot: worn Marksman Bands and a worn +3% scope leave p.hit and go to p.rangedGearHit; /hga weights' cap
  line holds them`; the five `stats-gear-2: …` cases; `a ranged-slot item that is no weapon: in the bags the plan settles
  and the tooltip works; worn, A.State builds`; `worn bow skill below or above 5 points a level moves the room under the
  hit cap`; `procs: the Tablet's tooltip names its 2.5 s weapon and the rate at the model point; /hga dump lists the
  hits`; `/hga weights prints the hit Score meets the cap with, the sheet hit and the ranged skill against the level's`;
  `the model point holds the worn skill's effect; the worn set and its copies give exactly 0 with skill, scope and a Use
  hit buff`; `a live hit under the worn gear's hit: the base goes negative and +2% hit is priced under the cap`; `dual
  wield past the cap at a worn bow skill off the level's: …`; `Egan's Blaster against a worn bow off the level's skill:
  …`; `a worn thrown weapon: no shots, the level's skill (skillShift 0) whatever the thrown line's skill` (it checks
  `ctx.skillShift == 0`: it checks `ctx.skillBase == 0` and `model.rangedSkill == 0`); `one worn set with every
  mechanism: …` (its `ctx.skillShift` checks); `set: a worn profession set's hit and ranged skill count only at the
  required rank (Snapshot, A.State)` if its numbers hold the slope (measured).
- test_model: `W.CRIT_NO_SHOTS: …` (becomes `W.SKILL_CRIT_NO_SHOTS`).
- Not moving: test_model `ranged-only hit: Expose Prey's shot hits in a weave land with it; …` and `ranged gear hit
  reaches the shots, the pet and the hawks, …` (`p.rangedHit` keeps its meaning).

New, W3 (each with its mutant):
- `skill: Model.SkillMiss is wowsims' hand miss: +3 at 285 / 300 / 305 / 315 → 11 / 8 / 6 / 5%; +0 at −5 / +5 → 5.5 /
  4.5%` (wowsims `attack_table_test.go:107-137`; +0 my arithmetic) — mutants: 0.1 a point past the 10-point gap; the
  kink at `sd ≥ 10`; `bonus` taken as 0.
- `skill: Model.SkillHit is 0 at bonus 0 and jumps at the 10-point gap (+3: bonus 4 → 0.8, 5 → 2.0)` — mutant:
  `SkillHit = 0.04 × bonus`.
- `skill suppression: the shots, Serpent Sting's ticks and the dive lose 0.2% crit a point below the maximum on top of
  the level part (+3 at 295: 4%); none above it` — mutants: the dive at bonus 0; a crit gain above the maximum
  (`0.0004 × baseSkillDiff` branch for `bonus > 0`); 0.04 a point.
- `model point: p.crit is the live crit, p.rangedHit = Model.SkillHit(model.mobDiff, worn bonus), p.rangedSkill the
  worn bonus` (test_game) — mutants: `+ skillShift` on `p.crit`; the 0.04 slope. (RMD step 10's raid fixtures check
  that `model.mobDiff` is 3 at 60; below 60 it is 0, RMD 14.2.)
- `score: +5 Bows reach the shots' cap as 2% hit at +3 and 0.5% at +0` — mutant: `SKILL_STEP × 5`.
- `score: skill above the maximum adds no crit; each point below costs W.SKILL_CRIT` — mutant: crit priced for skill
  above the maximum.
- `score: a set without shots gains W.SKILL_CRIT_NO_SHOTS × the worn deficit; its shots' cap term keeps the worn
  skill's hit` — mutants: `W.SKILL_CRIT`; `sk = 0`.
- `W.SKILL_CRIT: one point below min(worn, 0), one-sided at 0` (a fixture with `crit` above `meleeCrit` by more than the
  penalty, so the result holds after W4) — mutant: the two-sided difference at 0 (half the value).
- `tooltip: a gun against the worn bow says the shots' hit and crit by wowsims' table` (test_game, the 3.3 text) —
  mutants: the 0.04 slope in the hit; the crit above the maximum.
- `/hga weights: the skill line names the shots' hit and crit by wowsims' table; the crit field is printed once`
  (test_game) — mutants: the old `(против навыка уровня) %+.2f%%` text; the old `(в листе …)` field.
- `/hga dump: skillBase and mobDiff, no skillShift; the model holds rangedSkill` (test_game) — mutant: the dump keeps
  `skillShift`.

Moves, W4. Rule: every test that pins `W.HIT_DW`'s point with a worn main hand off the maximum, the melee white roll or
the shared glance, the proc outcome tables, or the weapon-run cache key moves (measured). By name: test_model `wowsims
check: Raptor waits for a swing; dual-wield hit past the cap; Expose Prey in a weave` (its dual-wield part); test_score
`dual-wield hit past the cap with plain W: …`, `dual-wield hit past the cap with ctx.weaponGain: only the hit past the
cap beyond the worn hit's; …` (unchanged values at skill 0: they are the check that the per-hand form reduces to today's);
test_game `/hga weights prints the attack speed inputs and weights and W.HIT_DW; …` (the new `W.HIT_DW_MH` field);
the step 9 proc-outcome tests (RMD 4.6.4's tables at the main hand's entry).

New, W4:
- `parse: the ten melee skill lines, ruRU and enUS, INCREASE and DECREASE → SKILL_<LINE> (negative for DECREASE)` —
  mutants: a line dropped; DECREASE not negated.
- `templates: BuildTemplates returns the twenty melee skill keys` — mutant: a key missing from `KEYS`.
- `score: MELEE_SKILL maps each melee weapon subclass to its line's key (0, 1, 4, 5, 6, 7, 8, 10, 13, 15)` — mutants:
  two subclasses swapped (7 → `SKILL_2H_SWORDS`); a subclass missing.
- `gen_set_data: an A_MOD_SKILL bonus on a melee line gives SKILL_<LINE>; The Twin Blades of Hakkari 461 gives
  SKILL_SWORDS = 6` (the generator's test harness, as RMD step 4's ranged-only hit) — mutant: the line missing from
  `SKILL_KEYS` (`unknown`).
- `melee skill: each hand's miss, dodge, glance and crit by its own skill (the sword hand at +3: 285 / 300 / 305 / 315
  as wowsims)` — mutants: glance chance from `skillDiff`; the off hand at the main hand's skill (one `whiteRoll`);
  dodge without skill.
- `melee skill: the weapon run takes each set's melee skills; one run per (ranged, MH, OH, mhSkill, ohSkill); the worn
  set gives exactly 0` — mutant: skill not in the cache key.
- `melee skill: a set's +Swords set bonus reaches the run's mhSkill` (test_game, the Twin Blades) — mutant: set bonuses
  left out of `Score.MeleeSkills`.
- `melee hit: the melee part meets the cap with h + Model.SkillHit(d, MH skill)` — mutant: `h` alone.
- `dual-wield hit past the cap: the main hand's part meets it with h + its skill hit, the off hand's with h in its own
  room 19 − its skill hit` — mutants: `W.HIT_DW × room(h + skM, 19)` (the main hand's skill hit on the off hand's part);
  the off hand's room 19.
- `W.HIT_DW at qd with meleeHit 0; W.HIT_DW_MH the main hand's white part of it` (a fixture with `meleeHit = −2`) —
  mutants: `qd.meleeHit = p.meleeHit` (the specials' slope enters `W.HIT_DW`); `W.HIT_DW_MH = W.HIT_DW`.
- `melee skill: zero outside the Survival branch while the pet's ranged crit branch wins` — mutant: priced outside the
  run.
- `score: a set's melee skill without ctx.weaponGain is an error` — mutant: the check removed.
- `proc outcome: a melee-defense proc rolls the main hand's skill table (miss, dodge and crit suppression), a
  ranged-defense one its miss and crit, a magic one the level's spell miss` — mutants: the level's skill for the
  physical tables; dodge at `Model.MobAvoid(d)`; the hand's skill on the spell miss.
- `tooltip: a melee weapon in a Survival build names its miss, glance and crit; out of Survival "ближний бой не в
  счёт"` (test_game) — mutants: the Survival line out of Survival; the line missing in Survival.
- `/hga dump: meleeSkill for the worn hands; the model holds mhSkill, ohSkill, meleeHit` (test_game) — mutant:
  `meleeSkill` missing.
- `rescore: a set's melee skill reaches its weapon run` is no test (the tool is run by hand, RMD step 1); the step runs
  it once and states the result in the commit.

### 3.7 RMD texts W3 and W4 amend

RMD steps 10-12 are implemented from RMD's text, so each W step amends the RMD sections it changes in its own commit
(section 11):
- W3: RMD 4.2 `skillSupp = d > 0 and 0.002 * 5 * d or 0` ("skill bonus taken as 0") → `skillSupp(bonus)` of 3.3, its
  pet line `critP` from `petCritBase` (section 4), and the `W.CRIT_NO_SHOTS` mention → `W.SKILL_CRIT_NO_SHOTS`;
  RMD 4.7.1's `hitValue(h, r)` with `shift + skillHit` → `sk` of 3.3, and its `/hga weights` cap line `+ ctx.skillShift`
  → `+ Model.SkillHit(ctx.mobDiff, bWorn)`.
- W4: RMD 4.3's hunter melee line (one `white(whiteMiss, dodge, 0, critM)` for `mh` and "`oh` likewise") → the per-hand
  rolls of 3.4, and its `white` with the attacker's glance; RMD 4.2's `critM` → per hand; RMD 4.6.4's melee and ranged
  outcomes (`missChance(d, p.hit)`, `dodge`) → the main hand's entry of 3.4; RMD 15.4's melee lines (the swing slot's
  white roll, Raptor Strike, the melee look's Strider Kick, Mongoose Bite and Wing Clip, the off hand's share) → the
  per-hand entries of 3.4; RMD 15.7's zero weights outside the Survival branch add `W.HIT_MELEE` and `W.HIT_DW_MH`.
W3 needs RMD step 4 (`hitValue`'s three terms, `p.rangedGearHit`) and step 7 (`supp`, `Model.ApplyStats`); W4 needs
step 8 (`Model.Glance`, `white`, the single roll), step 9 (`Model.ProcOutcomes`), step 3 (the Survival rule) and RMD 15
(the weave, group A). Both come before step 10 (group B of RMD 12), so the first raid fixtures at 60 are built on them.

## 4. Pet and hawk crit — pet-hawk-bm-1, pet crit from weapon skill (above and below 5 × level)

- Rule (wowsims): the pet's crit is `inheritedCrit = max(0, melee, ranged)` with `melee = PhysicalCrit +
  min(mhSkillBonus, 0) × 0.04` and `ranged = PhysicalCrit + RangedCrit + min(rangedSkillBonus, 0) × 0.04`, in percent
  (`wowsims/sim/hunter/pets.go:142-153`, `makeStatInheritance` `pets.go:122-140`). `RangedCrit` is the ranged crit stat,
  which an item's or enchant's ranged crit fills: the crit scope SpellItemEnchantment 8720 carries
  `PseudoStatRangedCritPercent` 2 (`wowsims/assets/database/db.json:7903`, pseudo stat 25 = `PseudoStatRangedCritPercent`,
  `proto/common.proto:337`), added to the equip stats (`sim/core/database.go:704`). Ferocity adds its 2% a rank to the pet
  and the hawks whole (`talents_beast_mastery.go:71-84`); a hawk takes half of `inheritedCrit` (`summon_hawk.go:63-67,
  83`; EV-0074 lines 18-21: "10 plus half the owner's crit" at Ferocity 5/5 over 4340 swings). White swings crit at that
  crit through the single roll (RMD 4.3) and the pet's own suppression (RMD 4.2). Skill above the maximum gives the pet
  nothing. Below it a branch loses 0.04% a point of its own hand's skill, and the pet loses it only while that branch
  is the higher one: with equal sheet crits (no ranged-only crit) and the main hand at or above its maximum, the ranged
  branch is below the melee branch at any bow deficit, and the pet keeps the whole crit (my reading of `pets.go:147-153`).
- HGA today: `petCrit = crit + fer`, `hawkCrit = 0.5 × crit + fer` (`Core/Model.lua:543, 528`), `crit` = the live ranged
  crit + `skillShift` (`Game/Advisor.lua:133`), so the pet takes ±0.04% a skill point both ways, always, and never the
  melee crit.
- Differ: (a) skill above the maximum (HGA +0.04% a point, wowsims nothing); (b) below it HGA always takes the penalty,
  wowsims only while the penalized ranged branch stays above the melee branch, which needs a ranged-only crit lead over
  the melee sheet crit; (c) the melee branch: a main hand below its maximum lowers it (wowsims) and it wins over a ranged
  branch below it. The test fixtures today sit at equal crits (test_model's `ref` has `crit == meleeCrit`; test_score's
  `fullP` fills `meleeCrit = crit`), where wowsims gives the pet no part of a bow deficit.
- W1's pet-hawk-bm-15 ("Where wowsims is wrong", W1 lines 53 and 128-129) reads EV-0070 (a level 17 pet sheet read the
  owner's ranged crit whole at 84 of 85 bow skill, `wowsims/docs/evidence/EV-0070-hunter-pet-sheet-readings.md`,
  "Ranged crit") as against wowsims' penalty. EV-0070 records no melee crit. wowsims' formula returns the ranged crit
  whole there whenever the owner's melee sheet crit is at least the ranged crit less 0.04% (my reading), so EV-0070 does
  not contradict it. The rule is wowsims' by O3 (W1's open "pet crit from weapon skill", RMD O3); W6 corrects W1's
  record (section 11).
- The pet's white-swing crit count of about 0.35% (W1 line 39) is trueshot's override, not a wowsims rule
  (`docs/research/V1-verify-forever-pet.md:56`: 21 crits in 6109 swings); wowsims gives the pet the owner's crit, as HGA
  does: nothing is proposed for it.
- HGA formula (`partsAndHits`, where `crit = p.crit / 100` and `meleeCrit = p.meleeCrit / 100` are fractions, so 0.04%
  a point is 0.0004):
  - W3: `petCritBase = max(0, crit + 0.0004 × min(p.rangedSkill, 0))` (the ranged branch: (a) closed);
  - W4: `petCritBase = max(0, meleeCrit + 0.0004 × min(p.mhSkill, 0), crit + 0.0004 × min(p.rangedSkill, 0))` ((b) and
    (c) closed; `p.mhSkill` is a live input from W4 on, and the weapon run varies it per set);
  - `petCrit = petCritBase + fer`; `hawkCrit = 0.5 × petCritBase + fer`; RMD 4.2's `critP`, `critH` take these.
- Weights (forward steps, `deriv`, HEAD `1db4d89` `Core/Model.lua:908-912`): `W.CRIT` raises both branches, so it reaches
  the pet whichever wins; `W.CRIT_RANGED` (p.crit alone) reaches the pet where the ranged branch wins or ties at the model
  point (a tie goes to the ranged branch after the step), not where the melee branch leads; `W.SKILL_CRIT` (one point
  further below `min(worn, 0)`) holds the pet's 0.04% and the hawks' 0.02% where the ranged branch leads the melee
  branch by at least that point's 0.04% at `b0`, a part of it where it leads by less, and none at equal sheet crits with
  the main hand at or above its maximum (from W4; in W3 there is no melee branch yet).
- Both modes.
- Tests:
  - W3, moves: test_model `ranged crit: W.CRIT_RANGED is the derivative of p.crit alone, melee crit held; the pet, the
    dive and the hawks take it` only if a fixture's melee crit is above its ranged crit (measured). New: `pet crit: 0.04%
    a point below the maximum of the ranged skill, nothing above` with `crit` above `meleeCrit` by more than the
    penalty — mutants: `+0.04 × bonus` above the maximum; 0.2% a point.
  - W4, new: `pet crit: the higher of melee and ranged sheet crit; hawks half; Ferocity whole on both` — mutants: ranged
    branch only; Ferocity halved on the hawks. `pet crit: at equal sheet crits a bow deficit does not reach the pet or
    the hawks; with a ranged-only lead it does, up to the lead` (crit = meleeCrit, then crit = meleeCrit + 0.1 at a
    5-point deficit: the pet loses 0.1%, my arithmetic) — mutants: no `max` (ranged branch only); the penalty on both
    branches. `pet crit: a main hand below its maximum lowers the melee branch` — mutant: the melee branch without its
    skill term. `W.SKILL_CRIT at equal sheet crits holds the shots' suppression alone` — mutant: no `max`.

## 5. pet-hawk-bm-8 — the dive's flat damage per rank of Unleashed Fury and Ferocity

- Rule (wowsims): Unleashed Fury and Ferocity are parsed onto the hunter (`talents_beast_mastery.go:57-84`,
  `spelldata.ParseStatic`); each row is `A_ADD_FLAT_MODIFIER` misc 3 (`SPELLMOD_EFFECT1`), which the parse table turns
  into `SpellMod_BaseDamage_Flat` (`spelldata/parse_effects_table.go:660-662, 721-728`; `spell_mod.go:1300-1302` adds it
  to `spell.BonusBaseDamage`), on the spells of its class mask. The dive's class mask matches, and the comment states it
  ("Its class flags match the Summon Hawk dive too", `talents_beast_mastery.go:57-58, 71-73`; the parse table's note on
  19616: "the flat value is what the sim applies and the tooltip's number is flagged, not adopted",
  `parse_effects_table.go:665-669`). The dive is a physical row with a school-damage effect, so it carries
  `SpellFlagPhysicalSchoolDamage` and coefficient 0 (`spelldata/resolve_spell.go:135-139`), and `CalcDamage` adds
  `spell.BonusBaseDamage` to its base before the attacker's multipliers, armor and the outcome
  (`spell_result.go:445-463`). The pet's and hawks' Unleashed Fury multiplier and Ferocity crit are separate
  (`talents_beast_mastery.go:66-68, 80-83`) and do not reach the dive (the hunter's spell).
- DB2 (build 70888): Unleashed Fury 19616 SpellEffect 697146 (aura 107, misc 3, class mask 0x2000000 / 0 / 8192 / 0);
  Ferocity 19598 SpellEffect 697447 (aura 107, misc 3, class mask 0x40000000 / 0 / 8192 / 0); the dive 1293527
  SpellClassOptions 83475 (class set 9, mask 0 / 0 / 8192 / 0), its damage SpellEffect 1314239 (Effect 2, 108);
  per-rank values 3 / 6 / 9 / 12 / 15 and 2 / 4 / 6 / 8 / 10 (the wowsims store's curves of the game files,
  `spelldata/spells_auto_gen.go:39928-39929`; HGA already reads 3% and 2% a rank of these talents from the DB2 curves,
  `Core/Model.lua:509-510`). Ranks 1-3 of the dive (1293241, 1293525, 1293526) carry the same class
  mask (`spells_auto_gen.go`, their rows), so the flats reach every rank (my reading; wowsims registers the top rank
  only, `summon_hawk.go:11`).
- HGA today: `out.dive = (Model.Rank("hawkDive", lvl) + 0.05 × rapShot) / 9 × (1 + crit) × phys × own × diveRws`
  (`Core/Model.lua:519`): no flats.
- HGA formula: `diveBase = Model.Rank("hawkDive", lvl) + 3 × T("unleashedFury") + 2 × T("ferocity")`;
  `out.dive = (diveBase + 0.05 × rapShot) × rate × …` (rate: `2 / C0` levelling, section 6 — `1/9` while Improved Arcane
  Shot is 0; `rH` raid, RMD 6.5). At 60 with 5/5 and 5/5 the base is 133 instead of 108 (my arithmetic). The flats sit
  before crit, armor and the multipliers, as the rest of the base; Gift of Arthas (RMD O7) stays after armor.
- RMD text W1 amends: RMD 6.5's `out.dive = (Rank + 0.05 rapShot) × rH × …` → `(diveBase + 0.05 rapShot) × rH × …`, so
  RMD step 11 keeps the flats.
- Both modes.
- Tests (step W1): moves — every test pinning `out.dive` or a total with Unleashed Fury or Ferocity taken
  (`Model.DEFAULT_TALENTS` has both at 5, `Core/Model.lua:125-133`). Measured on a copy of HEAD `dfa7300` with the
  flats added to the dive's base (`(Model.Rank("hawkDive", lvl) + 3 × T("unleashedFury") + 2 × T("ferocity") + 0.05 ×
  rapShot)`): 394 passed, 1 failed, test_model `reference BM 32/2 build: weights of the current model`. New: `dive: base
  + 3 a rank of Unleashed Fury + 2 a rank of Ferocity, before crit and armor` — mutants: the Unleashed Fury flat
  dropped; the Ferocity flat dropped; the flats added after `(1 + crit) × phys`; `dive: the flats at every rank (level
  43: 47 + 15 + 10)` — mutant: the flats at the top rank only.

## 6. ranged-7 — Improved Arcane Shot with Summon Hawk

- Rule (wowsims): Arcane Shot (14287) and Summon Hawk (1293527) each have a 6 s category cooldown in category 1173 and no
  cooldown of their own (`spelldata/spells_auto_gen.go:10733` and `:35894`), so each runs as the spell's `CD` on the
  unit's category timer (`spelldata/resolve_spell.go:383-407`). Improved Arcane Shot 19454 is `A_ADD_FLAT_MODIFIER` misc 11
  (`SPELLMOD_COOLDOWN`) on class mask 2048 (`spells_auto_gen.go:16711-16714`; DB2 SpellEffect 696223; Arcane Shot's
  SpellClassOptions 44954 mask 2048), −300 ms a rank (`spells_auto_gen.go:39916`), parsed as `SpellMod_Cooldown_Flat`
  (`parse_effects_table.go:627-629`) onto Arcane Shot's `CD.Duration` (`spell_mod.go:949-961`). A cast sets the shared
  timer to now + its own duration (`cast.go:321-333`). So the category is ready 6 − 0.3 × rank s after an Arcane Shot and
  6 s after a Summon Hawk, and the HHA sequence (`turret_hawk.apl.siml:15-16`) cycles in `18 − 0.3 × rank` s plus the
  waits.
- HGA today: with hawks `arcRate = 1/18`, the dive `/ 9` (`Core/Model.lua:475-481, 519`); without hawks
  `arcaneUse / (6 − 0.3 × rank)` (480), as wowsims.
- HGA formula: `C0 = 18 − 0.3 × T("improvedArcaneShot")`. Levelling: Arcane `1 / C0`, the dive `2 / C0` (its damage and
  `Model.LandedHits`' dive count, RMD 4.6.3), the hawks' uptime stays `CONST.hawkUptime` 0.9 (RMD 6.5 keeps it in
  levelling). Raid (RMD 6.5): `C = C0 + 3 × δ_H`, `rH = (2 / C) × seg.hha`, Arcane `(1 / C) × seg.hha`, `hawkUp = min(1,
  18 / C)` at the full share; RMD 6.4's HHA frequency in `b_X` is `3 / C0`; RMD 7.5's `S_hha = (3 / C) × c_eff`. Example
  (my arithmetic): rank 2 (wowsims' BM build) gives `C0 = 17.4 s`; 5/5 gives 16.5 s.
- Both modes. The user's build has the talent at 0 (`Model.DEFAULT_TALENTS`), so its numbers do not move. The Survival
  weave casts no Summon Hawk (RMD 15.3: the SV Weave preset's `Use Summon Hawk = false`), so W2 reaches the builds that
  shoot from range. The pre-raid tool's BM 31/20/0 has rank 2 (`tools/preraid/rescore/rescore.lua:39-43`); its level-60
  point keeps the raid pass alone (RMD 14.6: the +2 and +0 passes went with `/hga target`), which runs in raid mode from
  RMD step 12 on (RMD 12 step 12: the mana inputs for +3), where the cycle is `C = 17.4 + 3 × δ_H` (my arithmetic).
- RMD texts W2 amends (so RMD step 11 builds `C` with the talent): RMD 2.2's rows `CONST.hawkUptime` (raid `min(1, 18 /
  (18 + 3·δ_H))` → `min(1, 18 / C)`) and "Arcane with hawks `1/18`" (levelling `1 / C0`; raid one cycle of three
  elements per `C`); RMD 6.1's cast-tempo line ("the HHA elements at one per `6 + δ_H` s") → three elements per `C`;
  RMD 6.4's `b_X` frequency "HHA `3/18`" → `3 / C0`; RMD 6.5's `C = 18 + 3·δ_H` → `C0 + 3·δ_H`, its line "Levelling keeps
  `CONST.hawkUptime = 0.9` and Arcane `1/18`" → Arcane `1 / C0`, the dive `2 / C0`, and its tests (`uptime 18 / C`);
  RMD 7.5's `S_hha = (3 / C) × c_eff` keeps its text with this `C`.
- Tests (step W2): moves none (test_model `spec: Arcane Shot every 6 s (Improved Arcane Shot) without hawks, 1 per 18 s
  with them` sets the talent after taking Summon Hawk away). Measured on a copy of HEAD `dfa7300` with `C0` in the
  Arcane and dive rates: 395 passed, 0 failed. New: `ranged-7: with Summon Hawk, Improved Arcane Shot
  shortens the HHA cycle to 18 − 0.3 × rank s: Arcane 1 / C0, the dive 2 / C0` — mutants: `C0 = 18`; the reduction on
  every element (`18 − 0.9 × rank`). In RMD step 11: `raid HHA: C = 18 − 0.3 × rank + 3 × δ_H` — mutant: the talent
  left out of `C`.

## 7. Hawk speed — which owner speeds reach the hawks

The hawk speed is in RMD O3's list of W1's open questions (RMD 13 O3), which the user answered «берем как в вов симс»:
the change is wowsims' rule, and W1's entry "Aura 342 takes two paths" (W1 lines 137-142, "Where wowsims is wrong") is
corrected in W6.

### 7.1 Rule (wowsims)

- A hawk inherits the owner's ranged speed multiplier: at its summon `PseudoStats.RangedSpeedMultiplier` and every
  later `MultiplyRangedSpeed` (`wowsims/sim/core/pet.go:415-431`; `unit.go:681-692`; the hawks set
  `HasDynamicRangedSpeedInheritance`, `summon_hawk.go:88-91`). It does not read `AttackSpeedMultiplier`, the melee speed
  or haste rating. The tamed pet inherits the owner's `MeleeSpeedMultiplier` and `AttackSpeedMultiplier`
  (`pet.go:381-398`; `unit.go:650-661, 729-742`; `pets.go:96-98`), not haste rating (`hasteRatingMultiplier`,
  `unit.go:564-566, 610-638`, sits on the owner's totals alone).
- By source (my reading of the paths):

| Source | Path | Shots, melee | Pet | Hawks |
|---|---|---|---|---|
| quiver | `RangedSpeedMultiplier` (`hunter.go:90`) | shots | no | yes |
| aura 140: Quick Shots 6150, Rapid Fire 3045, the ranged half of Arcanum of Rapidity and Kiss of the Spider | `MultiplyRangedSpeed` (`parse_effects_table.go:369-371`; enchants `enchant_speed.go:65-79`) | shots | no | yes |
| aura 319: Rapid Fire, Iron Counterweight, the melee halves | `MultiplyMeleeSpeed` (`parse_effects_table.go:364-366`) | melee | yes | no |
| aura 342 of an item or enchant: Minor Haste 931 | `registerEquipSpeedAuras` → `AttachHastePseudoStats` → melee and ranged speed (`enchant_speed.go:13-41, 65-79`; `spelldata/speed.go:14-20`) | both | yes | yes |
| aura 9 or 342 of a set bonus or a parsed buff: the Tier-1 two-pieces 1300934 … 1300968 (342) | `ParsedSetBonus` → `ParseEffects` (`common/shared/item_sets.go:16-28`; `hunter/item_sets.go:41`) → `attackSpeedRow` → `MultiplyAttackSpeed` (`parse_effects_table.go:367-368, 1048-1050`) | both | yes | no |
| aura 192 | no row in the parse table and no handler in `sim/` (my grep for `A_MOD_MELEE_RANGED_HASTE`) | — | — | — |
| Wind Blessed (Skyborne racial) | `AttackSpeedMultiplier × 1.02` (`racials.go:225-229`) | both | yes | no |
| haste rating | `hasteRatingMultiplier` | both | no | no |
| Berserking (Troll racial) | `AttachMultiplyAttackSpeed(1.1)` (`racials.go:165-171`) | both | yes | no (stated, `summon_hawk.go:63-65`) |

- The statement `summon_hawk.go:63-65` ("a quiver's and Quick Shots' included; Berserking's attack speed does not reach
  it in game") agrees with the paths.

### 7.2 HGA today

`hawkSpeed = ranged × haste × (1 + rf)` (`Core/Model.lua:416-438`) with `haste = 1 + p.haste/100`, and `p.haste` holds
the worn items' `HASTE` (haste rating lines and Minor Haste), the set bonuses' `HASTE` and Wind Blessed
(`Game/Player.lua:630-686` `wornHaste`); the pet takes `p.haste` too (`ownerMelee`, `Model.lua:339-342, 576`). W1 lines
137-142 recorded wowsims' split as inconsistent with the DB2 (Wind Blessed, the Tier-1 two-pieces and Minor Haste carry
the same auras 342 and 65) and gave HGA one rule. `tools/gen_set_data.py` (HEAD `1db4d89`:189-190, `effect_stats`) maps auras 9, 192 and 342 to `HASTE`.
Berserking is not modelled (a racial Use; no gear changes it).

### 7.3 Change (step W5)

- Parse (`Core/Parse.lua:25-26, 51`): `TOOLTIP_ITEM_STAT_HASTE_PCT_INCREASE` / `_DECREASE` and `ITEM_MOD_HASTE_RATING`
  give `HASTE_RATING` (haste rating, stat type 36: the Player.lua note, `Game/Player.lua:644-650`); the attack speed
  enchant lines `Haste +N%` / `+N% к скорости` (`Parse.lua:120-121`, Minor Haste) keep `HASTE`.
- `tools/gen_set_data.py` `effect_stats` (HEAD `1db4d89`:189-190; reached through `spell_stats`, which `tools/gen_use_data.py` reuses, HEAD `1db4d89`:115, 118): an aura 9 or 342 effect gives
  `ATTACK_SPEED` (wowsims' `attackSpeedRow` for both, `parse_effects_table.go:367-368`); an aura 192 effect stops the
  generator with an error naming the spell (wowsims reads no aura 192, 7.1; no set bonus or item effect of build 70888
  carries it: the three spells with aura 192 in `DB2/db2/SpellEffect.csv`, 367987, 469261 and 1221578, have no
  `ItemSetSpell` row and no `ItemEffect` row in the exports read, my script); an `A_MOD_RATING` haste bonus
  `HASTE_RATING` (`rating_stats`, HEAD `1db4d89` `gen_set_data.py:91-112`). `Game/SetData.lua` regenerated: the five Tier-1 two-pieces
  (the only aura-342 bonuses, `Game/SetData.lua:2440-2524`; no set bonus carries aura 9 or 192, the same script) become
  `ATTACK_SPEED = 1`. `tools/gen_use_data.py` HEAD `1db4d89`:62 `DAMAGE_KEYS` gets `ATTACK_SPEED` and `HASTE_RATING` (no Use buff of
  build 70888 has aura 9, 342 or a haste rating: `Game/UseData.lua` does not change; the step checks it by
  regenerating).
- `Player.wornHaste` returns `haste` (the items' `HASTE`), `attackSpeed` (the set bonuses' `ATTACK_SPEED` and Wind
  Blessed, one product), `hasteRating` (the items' `HASTE_RATING`, summed as ratings do), `meleeHaste`, `rangedHaste`.
- Model: new required numbers `p.attackSpeed`, `p.hasteRating` (set by `Player.Snapshot`). The owner: `haste = (1 +
  p.haste/100)(1 + p.attackSpeed/100)(1 + p.hasteRating/100)` for the shots (`hBase`), their casts and the melee swings;
  the pet: `(1 + p.haste/100)(1 + p.attackSpeed/100)(1 + p.meleeHaste/100)(1 + rf)` (no rating); the hawks: `ranged × (1
  + p.haste/100) × (1 + rf)` (no attack speed, no rating). `Player.PetSwing` divides out the pet's inherited speeds only
  (haste, attack speed, melee haste: not the rating).
- Weights: `W.ATTACK_SPEED`, `W.HASTE_RATING` beside `W.HASTE`, each the value of one more source of its scope
  (`Core/Model.lua:851-873`; the rating sums as the items' `HASTE` does today). `Model.ApplyStats` (RMD 6.8) maps the two
  new keys; Score prices them by key in `ItemValue`'s loop.
- RMD text W5 amends (so RMD step 11 keeps the split): RMD 6.1's segment lines `ownerMelee = haste × (1 + meleeHaste/100)
  × (1 + rf)` and "the hawks' speed `× (1 + rf)`" → the owner's, the pet's and the hawks' speeds above, each `× (1 + rf)`
  in a Rapid Fire window; RMD 15.2's weave cycle takes the owner's speeds above for its melee swing time `M` and its
  ranged swing time `R` and windup.
- UI: `/hga weights` attack speed line adds `скорость атаки (комплект, раса) %s, рейтинг скорости %s`.
- Both modes.
- Effect (my reading): Wind Blessed is the Skyborne racial (the pre-raid tool models an orc,
  `tools/preraid/rescore/rescore.lua:2, 158`); the Tier-1 two-piece's 1% stops speeding the hawks; haste rating sits on
  four test items only (`Game/Player.lua:646-647`).
- Tests: moves — test_game `haste: the worn items' haste, a worn Tier-1 two-piece bonus and Wind Blessed reach the model's
  haste`, `attack speed enchants: …`, `/hga weights prints the attack speed inputs and weights and W.HIT_DW; …`, `one worn
  set with every mechanism: …`; test_model `hawks: the owner's ranged speed (p.haste, ranged-only haste, quiver, Quick
  Shots, Rapid Fire), not melee-only`, `attack speed scopes: …`, `attack speed weights: …`, `the hunter's white swings at
  p.haste x p.meleeHaste x Rapid Fire's average`; test_parse `attack speed enchants: 342 is HASTE, …`; test_score `attack
  speed stats: HASTE / MELEE_HASTE / RANGED_HASTE at their weights; …` (measured in the step). New: `hawk speed: an item's
  or enchant's aura 342 reaches the hawks; a set bonus's and Wind Blessed's do not; haste rating reaches neither the pet
  nor the hawks` — mutants: `p.attackSpeed` in `hawkSpeed`; `p.hasteRating` in the pet's speed; `parse: haste rating
  lines → HASTE_RATING, Minor Haste → HASTE` — mutant: the rating as `HASTE`; `gen_set_data: a Tier-1 two-piece's aura
  342 → ATTACK_SPEED; aura 9 → ATTACK_SPEED; aura 192 is an error` — mutants: `HASTE`; 192 mapped to `ATTACK_SPEED`;
  `weights: W.ATTACK_SPEED and W.HASTE_RATING as one more source of their scope` — mutant: `W.HASTE` for both.

## 8. Same rule on both sides (no change)

- **pet-hawk-bm-5, hawk expertise.** wowsims: `stats.ExpertisePercent: ownerStats[stats.ExpertisePercent]`
  (`summon_hawk.go:85`), lowering dodge (`unit.go:1174-1185`). HGA: `hawkDodge = max(0, avoid − p.expertise/100)`
  (`Core/Model.lua:529-535`); RMD 4.3 keeps it with the single roll (no parry from behind). Same.
- **melee-sv-5, Lacerating Strikes.** wowsims: a landed bite starts a bleed of 40% of the bite's dealt damage over its
  ticks; a bite while it is up replaces it and the unticked damage is lost (`talents_survival.go:177-226`); the bleed
  1310536 ticks every 3 s for 21 s (`spells_auto_gen.go:38074-38077`), its ticks can crit (Attr 8 0x200), and Savage
  Strikes and Predator's Edge reach them (their class masks hold its 1:4096, `spells_auto_gen.go` rows 19159 and
  1310627). HGA: `perBite × (1 + 0.40 × rank × critAbil × ticks / 7)` with ticks lost to the next bite and `critAbil`
  of Savage Strikes and Predator's Edge, armor and `own` once on bite and bleed (`Core/Model.lua:675-683, 690`). Since
  the bite's dealt damage already holds its armor and multipliers, wowsims' `0.4 × dealt` and HGA's single `phys × own`
  over both are the same amount (my reading). Same.
- **Ranged Weapon Specialization on the dive with a bow.** wowsims: its aura 79 row names ranged weapons alone
  (EquippedItemSubclass 262156), so it is a per-weapon mod on the ranged proc mask (`spelldata/weapon_scope.go:40-58,
  117-134`; `parse_effects_table.go:155-195`) that applies when the ranged slot holds a matching weapon
  (`equip_requirement.go:26-50`); the dive has `ProcMaskRangedSpecial` (`summon_hawk.go:135`). HGA: `diveRws = shoots and
  rws or 1` (`Core/Model.lua:392-395, 518`). Same.
- **Serpent Sting at a high melee share (Survival).** wowsims' APLs keep the sting up in melee play: the weave casts it
  at range, where it returns after each swing (`default.apl.siml:25`; `weave_common.apl.siml:3, 31-33`), and the melee
  APL runs out to 13.19 yd for it while Strider Kick's speed is up, the dot is down and mana is above 30%, or casts it on
  the walk in (`melee.apl.siml:19-23, 35-37`). The uptime is the simulation's, no rule. The melee share it was asked
  against is gone: the Survival branch weaves as wowsims' SV Weave (RMD 15), whose range look casts the sting first when
  its dot is down (RMD 15.3, levelling at `CONST.serpentUptime`, raid by the re-cast at the range looks). Nothing more
  proposed here.
- **Rot-Covered Harpoon 274963's rate.** wowsims: 1.45 a minute (`tools/database/overrides/weapon_procs.go:276-283`,
  EV-0122) as a weapon proc at the speed of the hand that hits (`procs.go:183-227`, B.md "Открытый вопрос 3"). HGA: the
  same 1.45 at the hitting hand's speed (`Core/Score.lua:129, 288-320`). Same. (Its Rot is a DoT: U2 = (a), RMD 17.)
- **Hit cap at +1 / +2.** wowsims: 5.5% and 6% (`target.go:581-585`; `attack_table_test.go:46-47`). HGA: `baseMiss`
  5.5 / 6 (`Core/Model.lua:233-237`), capped at +3 (RMD 4.1). Same; with W3 the cap of a hand moves with its skill
  (`Model.SkillMiss`), as wowsims'.

## 9. No wowsims rule (nothing proposed)

- **stats-gear-6, ranged weapon DPS weight; ranged-1, haste weight.** The figures W1 compares against are wowsims' EP
  presets (`ui/specs/hunter/dps/presets.ts:42-102`), simulation output on a Marksmanship turret without a pet at the 8%
  cap with the preset's raid buffs (A.md A17-A18); wowsims states no rule for a weight. The mechanics behind them match
  (W1 "Matching rules": the shots' weapon damage formulas) or are changed here and in RMD (haste scopes: section 7;
  armor, crit suppression, the fight: RMD). The weights stay HGA's analytic derivatives of its own model.

## 10. Approximations (stated, not the user's call)

- B1 The ranged skill's crit is priced by one-sided linear weights (`W.SKILL_CRIT`, `W.SKILL_CRIT_NO_SHOTS`), taken one
  point below `min(worn, 0)`: exact while every crit stays above 0 and the pet's `max(melee, ranged)` keeps over the
  priced skill range the branch it has at that point (a ranged-only lead over the melee branch larger than 0.04% times
  the deficit change keeps the ranged branch; equal sheet crits with the main hand at or above its maximum keep the
  melee branch); a set whose deficit crosses the point where the two branches meet is priced at the slope of the
  model point's side.
- B2 A thrown weapon keeps the level's skill (HGA's no-shot rule, `Game/Advisor.lua:97-117`), where wowsims takes the
  thrown line's skill for the ranged entry (`weapon_skill.go:35-37`): it moves only the dive's suppression, the pet's
  ranged branch and the half of it the hawks take (`summon_hawk.go:83`), and only for a worn thrown weapon
  (`Player.CanUse` keeps thrown weapons out of every candidate, `Core/Model.lua:831-833`).
- B3 Melee: the expertise cap stays `Model.MobAvoid(d)` (the pet's and hawks' dodge, a hand's at skill 0), while a
  melee hand with skill has its own dodge `Model.SkillDodge(d, bonus)`, 0.1% a skill point off `Model.MobAvoid(d)` (my
  arithmetic): a Survival hunter's expertise between the two is priced as if that hand's dodge were `Model.MobAvoid(d)`
  (its part over-priced up to the cap for a hand above the maximum, under-priced past the cap for one below it). The hit
  of both hands is exact within the linear pieces (3.4: the main hand's skill hit through Score, the off hand's in the
  run with its own room past the cap).
- B4 The dive flats reach every rank by the shared class mask (wowsims registers the top rank only).

## 11. Implementation order (each step leaves `lua tests/run.lua` green)

All after RMD step 9 (committed) and in the groups of RMD 12: W1 and W2 in group A (after RMD 14 settings removal, RMD
15 the Survival weave and RMD 16 the unarmed main hand), W3 and W4 in group B, W5 and W6 in group C with RMD step 10.
Each W step amends, in its own commit, the RMD sections it changes (named in 3.7, 5, 6, 7.3), so RMD steps 10-12 are
built from the amended text: step 10's raid fixtures on the ranged and melee skill of W3 / W4; step 11 with the dive's
flats (W1), `C = C0 + 3·δ_H` (W2), the hawks' and the pet's speeds of W5 in its segment lines, and the per-hand melee
rolls (W4) in the weave's lines (RMD 15); step 12's `rescore.lua` raid pass with the inputs of W3-W5.

- **W1 The dive's flats** (section 5). Core/Model.lua, RMD 6.5, tests.
- **W2 Improved Arcane Shot with hawks, levelling** (section 6). Core/Model.lua (Arcane, the dive, `LandedHits`' dive
  count), RMD 2.2 / 6.1 / 6.4 / 6.5 (section 6's list), tests.
- **W3 Ranged weapon skill and the pet's ranged branch** (sections 3.3, 4). Core/Model.lua (`Model.SkillMiss`,
  `Model.SkillHit`, `p.rangedSkill`, `skillSupp`, `petCritBase` ranged branch, `W.SKILL_CRIT`, `W.SKILL_CRIT_NO_SHOTS`,
  `W.CRIT_NO_SHOTS` removed), Game/Advisor.lua (model point, ctx, tooltip), Core/Score.lua (`SKILL_STEP` removed,
  `hitValue`, crit terms), Game/Commands.lua (`/hga weights` skill line and crit field, dump `skillBase` / `mobDiff`),
  tools/preraid/rescore/rescore.lua, RMD 4.2 / 4.7.1, tests and fixtures (3.6).
- **W4 Melee weapon skill and the pet's melee branch** (sections 3.4, 4). Core/Parse.lua, Game/Templates.lua,
  tests/fixtures_templates.lua, tools/gen_set_data.py (`SKILL_KEYS`), Game/SetData.lua (regenerated), Core/Model.lua
  (per-hand table and `white` with its glance, `p.mhSkill`, `p.ohSkill`, `p.meleeHit`, `petCritBase` with `max`,
  `ProcOutcomes` at the main hand's entry, `W.HIT_MELEE`, `qd.meleeHit = 0`, `W.HIT_DW_MH`), Core/Score.lua
  (`MELEE_SKILL`, `MeleeSkills`, the skill keys out of both loops, `hitValue`'s melee and per-hand dual-wield terms, the
  errors), Game/Advisor.lua (`meleeTrained`, `wornMeleeHit`, `weaponModelFor` key, tooltip), Game/Commands.lua
  (`W.HIT_DW_MH`, dump `meleeSkill`), rescore.lua, RMD 3.2 / 4.2 / 4.3 / 4.6.4, tests and fixtures (3.6).
- **W5 Hawk speed** (section 7). Core/Parse.lua, tools/gen_set_data.py, Game/SetData.lua (regenerated),
  tools/gen_use_data.py, Game/Player.lua (`wornHaste`, `PetSwing`), Core/Model.lua, Core/Score.lua, Game/Commands.lua,
  rescore.lua (`wornHaste`), RMD 6.1, tests and fixtures.
- **W6 Docs**: `docs/research/W1-wowsims-check-2026-11-16.md` closes stats-gear-6, stats-gear-7, ranged-1, ranged-7,
  pet-hawk-bm-1, -5, -8, melee-sv-5, hawk speed, Ranged Weapon Specialization on the dive, pet crit from weapon skill,
  Serpent Sting at a high melee share, Rot-Covered Harpoon, hit cap at +1 / +2 with the rule taken, and corrects two
  records under "Where wowsims is wrong": pet-hawk-bm-15 (wowsims' `max(melee, ranged)` returns the ranged crit whole
  where the melee sheet crit is at least the ranged less 0.04%, and EV-0070 records no melee crit, so EV-0070 does not
  contradict it; HGA takes wowsims' rule, section 4) and "Aura 342 takes two paths" (HGA takes wowsims' paths by O3,
  section 7); the design doc `docs/superpowers/specs/hunter-gear-advisor-design.md` (weapon skill by wowsims' table, the
  pet's crit, the dive's base, the hawk speed).

## 12. User's call, answered

- **U2 DoT procs (outside W1's open list): (a), the user's answer of 2026-11-17.** wowsims prices a damage-over-time
  proc (the harpoon's Rot 1295744, 24 Nature a second for 7 s, a magic-table dot:
  `common/forever/stat_bonus_procs_auto_gen.go:4693-4699`, `spells_auto_gen.go:36330-36334`); HGA leaves DoT procs
  unpriced today (W1 stats-gear-4; RMD 4.6.2), and the harpoon's tooltip has no damage range for Parse's proc patterns
  (`Core/Parse.lua:141-149`). They are priced as wowsims prices them: the design is RMD 17 (a later group of RMD 12).
- Settled by O3, no call: the hawk speed (section 7, in RMD O3's list) and the pet's crit below the maximum skill
  (section 4: wowsims' rule, which EV-0070 does not contradict); W6 records both.
