# HunterGearAdvisor — raid mode and wowsims mechanics (design)

Design of the two modes (levelling below 60, raid boss at 60) and of the mechanics HGA takes from wowsims/forever in
both modes. No code is changed by this document; section 12 is the implementation order, section 13 the user's answers
and the points still open. The user's later decisions of 2026-11-17 add section 14 (the tuning commands and settings
removed), section 15 (the Survival branch's melee as wowsims' SV Weave, in place of the `/hga melee` time share and the
weave flag), section 16 (the unarmed main hand at 1.0 s) and section 17 (DoT procs as wowsims prices them); where an
earlier section names a removed command or setting, sections 14-17 hold. W1's other open questions, the wowsims way, are
designed in `docs/superpowers/specs/raid-mode-w1-open-design.md` (below "W1D").

## 0. Conventions and sources

- Roots. `wowsims/` = the read-only wowsims/forever clone `C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/wowsims/src`
  (never run). `DB2/` = the Forever DB2 exports of build 1.60.1.70888 under
  `C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/` (`db2/`, `db2_ru/`, `db2_R3-core-formulas/`,
  `db2_R4-ability-formulas/f/`, `db2_R5-weapons-gear/`, `db2_V3-verify-gear-weights/`).
  `UI/` = the Forever UI repo (git, HEAD `1.60.1 (70888)`), read with `git show HEAD:<path>`. HGA paths are relative to
  this worktree (branch `raid-mode`, from `fddaf12`); HGA line numbers are those of that commit in sections 1-13 and
  those of HEAD `dfa7300` (steps 1-9 and their reviews committed) in sections 14-17.
- A DB2 citation names the table and the row ID (the first column), which identifies the row. Where it also gives a line
  number (`file.csv:N`), N is the physical line of the file as `grep -n` prints it. It differs from the record number
  wherever an earlier record holds a line break inside a quoted field (`db2/Spell.csv`, `db2_ru/Spell.csv`,
  `GlobalStrings.csv`).
- Every source below was re-read for this design. Numbers marked **(my arithmetic)** are computed by me from the cited
  values and are not output of wowsims (which was not run). "My reading" marks a conclusion I draw from code I read
  without running it.
- EV-0090, the basis of wowsims' 1.8% aura crit suppression, is Classic Era logs, not Forever
  (`wowsims/docs/evidence/EV-0090-era-no-aura-crit-suppression-plus-one-two.md:1-15`). No Forever log against a +3
  target exists (Forever raids are not open: `docs/research/R1-forever-ruleset.md:22`).
- wowsims' combat model is defined for a level-60 character against targets of level 58 to 63
  (`wowsims/docs/rulings/R-0032-combat-model-level-60-targets.md:1-9`; its creature constants are the maximum level's,
  `wowsims/sim/core/base_stats_auto_gen.go:21-24`). Below 60, levelling mode applies the same formulas to the lower level
  through the level difference and the skill gap: an extrapolation (approximation A9).
- Rules of the project hold for the implementation: an invalid state raises (no masking defaults, no nil guards for
  states that cannot happen); comments in English, with sources, present tense, no history; UI text in Russian; Lua 5.1;
  every rule gets a test that fails on a mutant (each new test below names its mutant).

## 1. The user's decisions (2026-11-17, fixed)

| # | Decision | Effect here |
|---|---|---|
| modes | «если не 60 то на прокачку, если 60 значит на рейд» | level < 60: levelling mode (today's solo assumptions); level 60: raid mode (wowsims' raid-boss setup) |
| mechanics | «берем как в вов симс» | wowsims' side on every mechanic listed in section 4, in both modes |
| melee | «мили атака вообще ни в учет хант ее избегает кроме сурв ветки»; answer 1 = (a) | melee only when Survival has strictly the most talent points (O1); else none; both modes (section 3); its melee is wowsims' SV Weave (section 15) |
| 2 = (a) | buffs: the live character sheet as it is | no preset raid buffs, no buff removal |
| 3 = (b) | boss armor with wowsims' preset debuffs | 3731 − 2250 − 505 = 976 (section 5.1) |
| 4 = (b) | mana as in wowsims in the raid fight | mana limits casts; Int / MP5 / Spirit / mana get a damage value in raid mode (section 7) |
| 5 = (a) | creature type as wowsims' raid target (dragonkin) | +AP vs beasts and Beastslaying give 0 in raid mode (section 4.5) |
| 6 = (a) | at 60 the target is always +3 | the target follows the mode, no setting (section 14.2) |
| agreed defaults | live talents; Aimed Shot in the shared cooldown; pet alive all fight; fight 180 s, cooldowns from 5 s, aligned; wowsims crit suppression; pet behind; Serpent Sting re-cast on expiry; one target, no movement | sections 5-7 (the Survival weave's shared-category shot: U3, section 15.11) |
| O2 = (a) | in-fight consumables as wowsims' preset, always on, no setting, no command | section 7.4 |
| O7 = (a) | the boss carries Judgement of Wisdom, Curse of the Elements and Gift of Arthas as well | section 5.3 |
| settings | «нахуй ты спамишь командами… у адона 2 функции: показать что одеть и вкладка с бис шмоткой», «убирай нахуй», «просто блять на прокачке на мой уровень на 60 на рейды» | `/hga target`, `/hga melee`, `/hga weave`, `/hga cap`, `/hga ppm`, `/hga min`, `/hga banner` and their saved keys removed; below 60 the target is the hunter's own level, at 60 +3; the hit cap follows the target; threshold 0; the banner always on (section 14) |
| Survival melee | the Survival branch's melee and weave follow wowsims' Survival preset (SV Weave) | section 15 |
| unarmed | the unarmed main hand is 1.0 s everywhere, as wowsims | section 16 |
| U2 = (a) | DoT procs priced as wowsims prices them | section 17 |
| O1, O3, O5, O6, O8 | strictly most points; W1's other questions the wowsims way (W1D); armor penetration against the boss armor; a Use buff's AP never reaches the pet (both modes); the live sheet's stat multipliers count | sections 3, 4.8, 5.1, 6.8, 13 |

Answer 3 covers the boss's armor debuffs and answer 2 the buffs; the preset's other debuffs on the boss (Judgement of
Wisdom, Curse of the Elements, Gift of Arthas: section 5.3), the preset's in-fight consumables (section 7.4) and the
live sheet's stat multipliers (Kings and the like: section 4.8) were covered by neither; the user answered them with
O7 = (a), O2 = (a) and O8 = (a) (section 13).

## 2. Overview

| Change | Section | Files |
|---|---|---|
| Mode switch by level, `p.mode`, per-mode constants | 2.1-2.5 | Core/Model.lua, Game/Player.lua, Game/Advisor.lua, Game/Commands.lua, Game/Init.lua |
| Melee for the Survival branch only | 3 | Game/Player.lua, Game/Commands.lua, Game/Init.lua |
| Level difference capped at +3 | 4.1 | Core/Model.lua, Game/Commands.lua, Game/Init.lua |
| Crit suppression | 4.2 | Core/Model.lua, Game/Player.lua |
| Single-roll white table (hunter melee, pet, hawks), parry from the front | 4.3 | Core/Model.lua, Core/Score.lua, Game/Advisor.lua |
| Pet and hawk hit = physical + ranged gear hit | 4.4 | Core/Model.lua |
| Beastslaying as flat damage per weapon strike; AP vs creature type on the hunter's own attacks | 4.5 | Core/Model.lua, Core/Parse.lua, Core/Score.lua, Game/Player.lua, Game/Items.lua, tools/gen_set_data.py, tools/gen_use_data.py |
| Procs: Tablet per hand, equip procs by their DB2 trigger, damage by DefenseType, the dive as a ranged ability | 4.6 | tools/gen_proc_data.py (new), Game/ProcData.lua (new), Game/Items.lua, Core/Parse.lua, Core/Score.lua, Core/Model.lua, Game/Advisor.lua |
| Parse gaps: ranged-weapon hit (items, the ranged-hit rating line, the two +3% scopes), Counterattack Lodestone | 4.7 | Core/Parse.lua, Game/Templates.lua, Core/Model.lua, Core/Score.lua, Game/Player.lua, Game/Commands.lua, tools/gen_set_data.py |
| Live stat multipliers (O8 = (a)) | 4.8 | Game/Player.lua, Core/Model.lua |
| Raid target: +3, armor 976, dragonkin, pet behind | 5.1-5.2 | Core/Model.lua |
| The preset's other debuffs: Judgement of Wisdom, Curse of the Elements, Gift of Arthas (O7 = (a)) | 5.3 | Core/Model.lua, Core/Score.lua |
| Raid fight of 180 s (cooldown windows, cast tempo, Serpent Sting, hawks, Use buffs) | 6 | Core/Model.lua, Core/Score.lua, Game/Advisor.lua |
| Mana in raid mode, in-fight consumables (O2 = (a), always on) | 7 | Core/Model.lua, Core/Score.lua, Game/Player.lua, Game/Advisor.lua, Game/Commands.lua, tools/gen_use_data.py |
| UI: /hga weights, dump, help; tooltip lines | 8, 14.5 | Game/Commands.lua, Game/Advisor.lua |
| Tuning commands and settings removed; the target by the mode, the cap by the target | 14 | Game/Commands.lua, Game/Init.lua, Game/Player.lua, Game/Advisor.lua, Game/Swap.lua, Game/Quest.lua, Game/Tooltip.lua, Core/Score.lua, tools/preraid/rescore/rescore.lua |
| The Survival branch's melee as wowsims' SV Weave | 15 | Core/Model.lua, Core/Score.lua, Game/Player.lua, Game/Advisor.lua, Game/Commands.lua, Game/Init.lua |
| The unarmed main hand at 1.0 s | 16 | Game/Player.lua |
| DoT procs | 17 | tools/gen_proc_data.py, Game/ProcData.lua, Game/Items.lua, Core/Model.lua, Core/Score.lua, Game/Advisor.lua |

### 2.1 The mode switch

- Rule: level 60 = raid mode, below 60 = levelling mode (the user's decision). 60 is Forever's level cap (the task's
  premise; `RAID_BOSS_LEVEL = 63` = 60 + `WEAPON_SKILL_BOSS_LEVEL_OFFSET` 3, `UI/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua:57-58`).
- Source of the level: `Player.Snapshot` already reads `UnitLevel("player")` (`Game/Player.lua:692`; Forever
  `UnitDocumentation.lua:2474` `UnitLevel` returns a number, not nilable).
- New constant `Model.RAID_LEVEL = 60`. New required model input `p.mode`, the string `"raid"` or `"level"`;
  `checkInputs` (`Core/Model.lua:165-177`) raises for anything else ("Model input p.mode must be 'raid' or 'level'").
  `Player.Snapshot` sets `model.mode = level >= Model.RAID_LEVEL and "raid" or "level"`. The model never derives the
  mode from `p.level` itself: a test can run levelling mechanics at 60 and the reverse is an error
  (`p.mode == "raid"` with `p.level ~= 60` raises: raid mode is defined for the level-60 boss only).
- `Model.Total`, `Model.Parts`, `Model.LandedHits`, `Model.TotalAndHits` branch on `p.mode`: `"level"` runs today's
  single averaged pass (`partsAndHits(p)`, with the both-mode mechanics of section 4); `"raid"` runs the fight
  (`fight(p)`, section 6), which calls `partsAndHits(p, seg)` once per time segment.
- A mode change needs no extra event: `PLAYER_LEVEL_UP` already clears the item cache and invalidates the state
  (`Game/Commands.lua:295-300`), and the last stat reading is reused only at the same level, gear and talents
  (`Game/Player.lua:358-366`), so a reading taken at 59 never serves a level-60 snapshot.

### 2.2 What each mode fixes (every solo assumption of C.md)

| Item (today) | Levelling mode | Raid mode | Source of the raid value |
|---|---|---|---|
| `mobDiff` (`/hga target`, `Game/Init.lua:8`) | 0: the hunter's own level (14.2) | 3 | the user (14.2); user 6 = (a); wowsims `defaults.siml:64` level=63 |
| `hitCapOverride` (`/hga cap`) | removed: `Model.HitCap(mobDiff)`, 5% (14.2) | removed: 8% | the user (14) |
| the cap shown by `/hga help`, `/hga target`, `/hga cap` (`Game/Commands.lua:195-197`) | removed with the commands; `/hga weights` shows `ctx.hitCap` (14.5) | the same | the user (14) |
| `meleeFrac` 0.05 (`Game/Init.lua:6`) | removed: the Survival branch weaves (section 15), every other build has no melee (section 3) | the same | the user (15) |
| `weave` false | removed: the Survival weave is wowsims' SV Weave (section 15) | the same | the user (15) |
| `procsPerMinute` 1.5 | removed as a setting; the unmeasured rate per U4 (14.4) | the same | U4 |
| `threshold`, `swapBanner` | removed: threshold 0, the banner always on (14.3, 14.5) | the same | the user (14) |
| `CONST.serpentUptime` 0.8 (`Core/Model.lua:187`) | 0.8 | derived per fight (section 6.4) | `turret_hawk.apl.siml:14`, `serpent_sting.go:39-51`, `apl.go:594-613` |
| fight length (none; averages per cooldown) | none (averages) | 180 ± 5 s, time weight w(t) (section 6.2) | `defaults.siml:58-59`, `sim.go:410-414` |
| Rapid Fire 15 / (300 − 60·RK) (`Core/Model.lua:331-334`) | average as now | windows from 5 s (section 6.3) | `turret_hawk.apl.siml:12`, `apl_actions_casting.go:596-619` |
| Bestial Wrath ×1.075 (`Core/Model.lua:581`) | ×1.075 as now | ×1.5 in its windows, 5-23 s and from 125 s if mana allows (6.3, 7.6) | DB2 SpellEffect 697223 (19574 effect index 1, +50); SpellCooldowns 55448 (`db2/SpellCooldowns.csv:2120`, 120000 ms) |
| Use buffs duration / cooldown (`Core/Score.lua:728`) | as now | windows from 5 s, through the model (6.3, 6.8) | autocast of MCDs, same sources |
| `CONST.killInterval` 25 (Rapid Killing) | 25 | no kill inside the fight: the Aimed bonus is 0 | `talents_marksmanship.go:85-93` (the buff on a killing blow or a stung death) |
| `CONST.petTanks` 1.0 | 1.0 (parry by wowsims' formula, 4.3; no block: A8) | 0 (pet behind, no parry, no block) | `pet.go:145`, `spell_outcome.go:886-893`, `defaults.siml` / `bm.siml` set no `in_front_of_target` |
| `CONST.hawkUptime` 0.9 | 0.9 | `min(1, 18 / C)`, `C = C0 + 3·δ_H` at the fight's tempo (6.5; `C0 = 18 − 0.3 × Improved Arcane Shot`, W1D 6) | `summon_hawk.go:14-15, 140-147`; `apl.go:594-613`, `gcd.go:93-107` |
| `CONST.happy` 1.25, pet always out | as now | as now | `pets.go:110`, `defaults.siml:15` pet_uptime 1 |
| `aimedUse` / `aimedUseSniper` / `sniperUse` | as now | as now in the rich regime, mana-limited in the starved one (7.5; A12) | `Core/Model.lua:197-205` |
| Arcane with hawks `1/18` (`Core/Model.lua:480`) | `1 / C0`, the dive `2 / C0` (W1D 6, step W2) | one cycle of three HHA elements per `C` (6.5) | as `hawkUptime` |
| `CONST.resourcefulnessUptime` 0.4 (`Core/Model.lua:214-219`) | 0.4 (mana is a tie-break there) | derived from the fight's ability crits (7.3) | DB2 SpellAuraOptions 242512 (0x110), buff 1242688 30 s |
| `Model.AP_CREATURE_SHARE` 0.3 | 0.3 for every creature type | 1 for dragonkin, 0 for every other type (4.5) | `defaults.siml:65` mob_type=dragonkin |
| Beastslaying (melee swings × 0.3 × meleeFrac) | flat per weapon strike × 0.3 (4.5) | 0 (the target is no beast) | `spell_result.go:445-466`, `defaults.siml:65` |
| `CONST.trackUptime` 1.0 | 1.0 | 1.0: Track Dragonkin names dragonkin | `talents_survival.go:43-66` |
| armor (`CREATURE_ARMOR[level + mobDiff]`, no debuffs) | as now (`Core/Model.lua:248-253`) | 976 (5.1) | section 5.1 |
| the preset's other debuffs on the boss | none | Judgement of Wisdom, Curse of the Elements, Gift of Arthas (O7 = (a), 5.3) | `defaults.siml:46-48` |
| crit suppression (none) | by mobDiff (4.2) | +3: 3% + min(aura crit, 1.8%) (4.2) | `target.go:504-512, 591-595`; `spell_result.go:211-231` |
| raid buffs | live sheet | live sheet | user 2 = (a) |
| the sheet's stat multipliers (Kings, Zandalar) on an item's stats | applied (O8 = (a), 4.8) | applied (O8 = (a), 4.8) | the user (O8) |
| in-fight consumables | none | as wowsims' preset, always on (O2 = (a), 7.4) | `defaults.siml:21, 30-31` |
| mana: tie-break only (`Core/Model.lua:939-960`) | tie-break as now | damage (section 7); the tie-break keeps survival only (7.9) | user 4 = (b) |
| the survival tie-break's armor against the attacker's level | `pools.level` = the player's | 63, the boss's | `spell_resistances.go:147` (400 + 85 × attacker level), `defaults.siml:64` |
| test fixtures at the solo point (`tests/test_model.lua:9-17`, `tests/test_score.lua:72-79`) | stay (level 43 is levelling) | new raid fixtures at 60 | — |
| `tools/preraid/rescore` (`rescore.lua:681-687` MOB_DIFFS 3/2/0) | — (its point is level 60) | the raid pass alone: `mode = "raid"`, +3 and the mana inputs (14.6) | steps 1, 4, 12; 14.6 |

### 2.3 Commands and settings for the mode

- No command and no setting picks the mode or the target (the user, section 14): the mode follows the level (2.1), the
  target follows the mode (14.2: the hunter's own level below 60, +3 at 60), the hit cap follows the target. Step 1's
  `/hga target 0-3` and its v3 migration (HEAD `dfa7300` `Game/Init.lua:52`) are removed by step A1 (section 14); there is no
  `/hga potions` and no `raidConsumables` (the consumables are always on, O2 = (a), 7.4).
- `/hga weights`, `/hga dump` and the help: sections 8 and 14.5.

### 2.4 Inputs: where Snapshot and A.State set them

| Input | Mode | Set by | Value |
|---|---|---|---|
| `p.mode` | both | Player.Snapshot | 2.1 |
| `p.mobDiff` | both | Player.Snapshot | raid: 3; levelling: 0 (14.2) |
| `p.survival` (replaces `p.meleeFrac` and `p.weave`) | both | Player.Snapshot | `Player.SurvivalBranch(points)` (sections 3, 15.6) |
| `p.agi` | both | Player.ReadStats → Snapshot | `select(2, UnitStat("player", 2))`, effective Agility (`UnitDocumentation.lua:3198` UnitStat, SecretWhenUnitStatsRestricted) |
| `p.rangedGearHit` | both | Player.Snapshot | worn items' and set bonuses' `RANGED_HIT` (4.7); `p.hit` = live hit − that |
| `p.beastSlaying` | both | Player.WeaponInputs | sum of `BEAST_SLAYING` of the set's main hand and off hand (4.5) |
| `p.apVsTarget` | both | Player.Snapshot | worn items' and set bonuses' `AP_VS_<TYPE>` × the mode's share of the type (4.5) |
| `p.spellHit`, `p.spellCrit` | both | Player.ReadStats → Snapshot | `GetSpellHitModifier()`, `GetSpellCritChance()` (`PlayerScriptDocumentation.lua:1113, 1086`; both SecretWhenUnitStatsRestricted) |
| `p.manaMax` | raid | ReadStats (already reads it, `Game/Player.lua:349`) | `UnitPowerMax("player", Enum.PowerType.Mana)` |
| `p.regenRest`, `p.regenCast` | raid | ReadStats → Snapshot | `GetManaRegen()` baseManaRegen, castingManaRegen in mana/s (`PlayerScriptDocumentation.lua:571-580`; the paper doll prints them ×5 as mana/5 s, `Camelot/PaperDollFrame.lua:1245-1255`) |
| `p.spirit` | raid | ReadStats → Snapshot | `select(2, UnitStat("player", 5))` |
| `p.statMult` | both (O8 = (a)) | Player.Snapshot | 4.8 |
| `p.armorPen` | raid (step 10) | Player.Snapshot | the worn items' and set bonuses' `ARMOR_PEN` (5.1, O5) |
| `p.uses` | raid, optional | Advisor (ctx.useGain) | the Use buffs of a set (6.8); absent = none |

Every new live value joins the `isSecret` list of `Player.ReadStats` (`Game/Player.lua:354-355`) and the last reading
(`lastStats`, `Game/Player.lua:368-372`). `checkInputs` gets two lists: the both-mode list (today's plus `mode`, `agi`,
`rangedGearHit`, `beastSlaying`, `apVsTarget`, `spellHit`, `spellCrit`) and `RAID_REQUIRED` (`manaMax`, `regenRest`,
`regenCast`, `spirit`), checked when `p.mode == "raid"`. Section 15.6 replaces `meleeFrac` (a required number) and
`weave` (a required flag) by the required flag `survival`.

### 2.5 Tests for the mode switch

- Moves: none by itself (every test_game environment is below 60, `tests/test_game.lua:271, 4551, 4610, 4628`, and
  test_model / test_score pass `p.mode` explicitly, `"level"` also in `weights stay sane at level 60 and level 20`); the
  input test `test_model / a model input every producer sets is required...` (`tests/test_model.lua:324`) gets the new
  inputs; the fixtures `ref` (`tests/test_model.lua:9-17`) and `refPoint` (`tests/test_score.lua:72-79`) add
  `mode = "level"`, `agi = 167`, `rangedGearHit = 0`, `beastSlaying = 0`, `apVsTarget = 0`, `spellHit = 0`,
  `spellCrit = 3.6` (the hunter's base spell crit, `wowsims/sim/core/base_stats_auto_gen.go:62-66`).
  test_game's environment (`tests/test_game.lua:271-280`) adds the stubs `UnitStat`, `GetManaRegen`,
  `GetManaRegenFromSpirit`, `GetSpellHitModifier`, `GetSpellCritChance` and `GetHitModifier` (the last two of `/hga dump`,
  section 8); without them every test_game case errors.
- New (each with its mutant): `mode: level 60 is raid, 59 is levelling (Snapshot)` (mutant: `> 60`);
  `mode: p.mode other than raid/level is an error` (mutant: the check removed);
  `mode: raid at a level other than 60 is an error` (mutant: the check removed);
  `mode: raid ignores /hga target (mobDiff 3 at a setting of 0)` (mutant: mobDiff from the setting in raid);
  `settings v3: a saved mobDiff 5 becomes 3` (mutant: no migration); `/hga target 4 is stored as 3` (mutant: clamp at 5)
  — these three, built in step 1, are replaced in step A1 by section 14.7's tests (the target by the mode, the v4
  migration);
  `raid inputs required only in raid mode` (mutants: required in levelling; not required in raid);
  `mode switch: a level-up 59 → 60 while the stats are secret uses no level-59 reading; after combat the mode is raid`
  (mutant: the level test dropped from the last-reading condition, `Game/Player.lua:358`);
  `mode switch: applying a Survival tree (TRAIT_CONFIG_UPDATED, Game/Commands.lua:268-273) turns the melee share on`
  (mutant: the Survival rule read once at load).

## 3. Melee only for the Survival branch (both modes)

### 3.1 Rule and source

- The user: «мили атака вообще ни в учет хант ее избегает кроме сурв ветки»; answer 1 = (a): the Survival branch is
  "most talent points in Survival" (`Player.BRANCHES` points); every other build has no melee.
- Tie rule (O1, the user's answer: strictly most): Survival counts only with strictly more points than each other branch:
  `points.SV > points.BM and points.SV > points.MM`. A tie (SV 20 / MM 20 / BM 11) and the all-zero tree below level 10
  give no melee. `Player.ReadTalents` gives the points (`Game/Player.lua:424-452`, `points[branch.key]`).
- How the Survival branch melees: wowsims' SV Weave, section 15 (the user's later decision; it replaces the `/hga melee`
  time share that step 3 built).

### 3.2 Formula in HGA terms

- `Player.Snapshot`: `survival = points.SV > points.BM and points.SV > points.MM` (`Player.SurvivalBranch`, step 3);
  `snap.survival = survival` for the UI. Step 3 passes `model.meleeFrac = survival and s.meleeFrac or 0`; step A2
  (section 15.6) passes `model.survival = survival` instead and removes the setting.
- What no melee does (the code paths with `p.survival` false, as step 3's meleeFrac 0): no melee part, the shots in
  full; `W.MH_DPS`, `W.OH_DPS`, `W.TH_DPS` = 0 (the derivative of a part that is absent); `W.HIT_DW`, `W.HIT_DW_MH` and
  `W.HIT_MELEE` = 0 (W1D 3.4);
  `ctx.weaponGain` of a melee weapon = 0 except through Beastslaying on the shots (4.5) and its stats; a melee weapon's
  chance-on-hit proc rolls on no hit (its hand lands none, `Score.ProcRate`); expertise goes to the pet and the hawks
  only; Raptor Strike, Strider Kick, Mongoose Bite, Wing Clip, Immolation Trap, Expose Prey, Lacerating Strikes vanish.

### 3.3 UI

- The melee line of `/hga weights` and the absence of `/hga melee`: section 15.6 (UI) and section 14.

### 3.4 Tests

The lists below are step 3's (built, commit `a533624`); section 15.9 lists what step A2 moves.

- Moves: 15 test_game cases. Measured on a copy of this worktree's HEAD with the rule in `Game/Player.lua:825`:
  `314 passed, 15 failed`. The rule is wider than C.md's mutation `DEFAULTS_meleeFrac_0` (11 failed), which leaves the
  tests that set the share themselves (`ns.settings.meleeFrac = 0.3`, `/hga melee 5`). test_game's environment tree is
  `tests/test_game.lua:34-37` `G.talentRanks`: BM 26 / MM 2 by `Player.BRANCHES` (`Game/Player.lua:380-392`), so its
  effective meleeFrac becomes 0.
  - Switched to a Survival tree (an environment whose SV nodes hold the most points; valid from level 10), since each
    tests a melee mechanism:
    `/hga weights: Lone Wolf with no pet says the pet's stats are not counted and where expertise still goes` (its
    `melee 5` cases); `weapon speed: a 2H and a 1H pair are priced at each weapon's own speed`;
    `weapon speed: taking both weapons off is a loss (the melee share stays, unarmed)`;
    `dual-wield hit past the cap: hands of the other kind than the worn ones score as the model at the worn 9% hit`;
    `procs: a proc weapon in the off hand of a pair, a two-hander worn: the pair's own off-hand hits at that weapon's speed`;
    `procs: a two-hander's melee proc, a pair worn: the two-hander's own set, no off-hand swings and no dual-wield miss`;
    `procs: a worn set with procs on both hands, the bow and armor gives 0, each worn proc at its own set's hits`;
    `/hga weights prints the attack speed inputs and weights and W.HIT_DW; a stale reading for a Use buff says so; dump has statsStale`;
    `dual wield past the cap at a worn bow skill off the level's: ctx.wornHit is the sheet hit; a two-hander has no dual-wield part`;
    `one worn set with every mechanism: it and its copies give 0, …`;
    `weights' unit: Lone Wolf without Summon Hawk, no pet out and no bow at 40: finite weights in melee AP`.
  - New expectation re-derived by hand from meleeFrac 0, with a comment naming this rule:
    `procs: the Tablet's tooltip names its 2.5 s weapon and the rate at the model point; /hga dump lists the hits`
    (it moves again in step 9); `a live hit under the worn gear's hit: the base goes negative and +2% hit is priced under the cap`;
    `two copies of a Use trinket: the bag copy into the empty trinket slot adds no second buff and is no plan row`;
    `weights' unit: level 8 with an empty ranged slot is 1 melee AP; …`: at level 8 no talent point exists, so the test
    sets an empty tree; with meleeFrac 0, no shot and no pet below level 10 the unit is 1 DPS (`Core/Model.lua:786-790`),
    and the bag bow stays an upgrade; the test's name follows the new expectation.
  `test_model` and `test_score` fixtures set `meleeFrac` explicitly and do not move.
- New (each with its mutant): `melee: SV most → the setting; BM most → 0; MM most → 0` (mutant: the rule removed);
  `melee: a tie SV = MM is 0` (mutant: `>=`); `melee: below level 10 (no points) is 0` (mutant: `>=`, which takes
  0 = 0 = 0 as Survival); `melee: the rule holds in raid mode too` (mutant: the rule in levelling only);
  `/hga melee says whether it counts` (mutant: the branch clause dropped); `/hga weights names the melee state` (mutant:
  the line dropped).

## 4. Mechanics taken from wowsims (both modes)

### 4.1 Level difference capped at +3

- Rule: every attack table uses `min(target − attacker, 3)`. Source: `wowsims/sim/core/target.go:536-538`
  (`combatLevelDiff`), `wowsims/docs/rulings/R-0032-combat-model-level-60-targets.md:1-9`.
- HGA: a local `capDiff(mobDiff) = math.min(mobDiff, 3)` used by `baseMiss` / `Model.HitCap` (`Core/Model.lua:233-245`),
  `Model.GlanceMult` (259-267), `Model.MobAvoid` (272-275), the parry (4.3), the crit suppression (4.2), the spell
  miss (4.6). `Model.PhysMult` keeps `level + mobDiff` clamped to the armor table (250), the creature's own armor.
  Step 1 made `/hga target` accept 0..3 and migrated saved values; section 14 removes the command: the target is 0
  below 60 and 3 at 60, so the cap matters for a model point a test builds (any `p.mobDiff`).
- Both modes: the same rule.
- Tests: moves none (no test uses +4 or +5; C.md and `tests/test_model.lua:26`). New: `level cap: HitCap, MobAvoid,
  GlanceMult and the suppression at +4 and +5 equal +3` (mutant: no cap); `/hga target 5 stores 3` (mutant: clamp at 5).

### 4.2 Crit suppression

- Rule (wowsims): a physical attack's crit is reduced by the hand's `MeleeCritSuppression` plus the aura crit clamped to
  `AuraCritSuppression`:
  - `MeleeCritSuppression = 0.002 × baseSkillDiff` when `baseSkillDiff > 0`, with `baseSkillDiff = 5 × levelDiff −
    min(skillBonus, 0)` (`wowsims/sim/core/target.go:562-597`);
  - `AuraCritSuppression = 0.018` only at `levelDiff >= 3` (`target.go:504-512`, EV-0090 — Classic Era logs);
  - aura crit = the attack's whole crit less the base crit and the crit from Agility
    (`wowsims/sim/core/spell_result.go:221-231`); the hunter's base physical crit is 0
    (`wowsims/sim/core/base_stats_auto_gen.go:62-66`);
  - it applies in `PhysicalCritChance` (`spell_result.go:208-219`): shots (`ProcMaskRanged` adds ranged crit, then the
    suppression), melee white and specials, the dive (`OutcomeRangedCritOnly`, `spell_outcome.go:506-517` → physical
    crit), Serpent Sting's ticks (`serpent_sting.go:34-37`, physical tick crit), the pet and the hawks (their own attack
    tables at level 60, skill 300); spell crit (magic procs) is not suppressed (`spell_result.go:306-317`).
- Per level (my arithmetic from the rule): +0: 0; +1: 1%; +2: 2%; +3: 3% + min(aura, 1.8%).
- Pet and hawks: all their crit is aura crit (the pet's base stats hold no crit, `wowsims/sim/hunter/pets.go:38-42`; the
  hawks' base stats hold health only, `summon_hawk.go:39-41`), so at +3 they lose 3% + min(their crit, 1.8%).
- HGA formula (Core/Model.lua, `partsAndHits`), with `d = capDiff(p.mobDiff)`, `cpa = Model.CritPerAgility(p.level)/100`
  per Agility:
  - `skillSupp(bonus) = 0.002 × (5 × d + max(0, −bonus))`, `bonus` the attacking hand's weapon skill over 5 × level
    (W1D 3.3, stats-gear-7 by O3: wowsims' rule wherever `d ≥ 0`); the ranged hand's `bonus` is `p.rangedSkill`, the pet's
    and the hawks' 0 (their own tables), the hunter's melee and a proc's table the main hand's (W1D W4);
  - `function supp(critFrac, agiCritFrac, bonus) return skillSupp(bonus) + (d >= 3 and clamp(critFrac − agiCritFrac, 0,
    0.018) or 0) end`;
  - shots, dive, Serpent ticks: `critR = max(0, crit − supp(crit, cpa × p.agi, p.rangedSkill))`, used in `rcrit` (382),
    the dive (519);
  - melee, per hand (W1D 3.4): `critM_hand = max(0, meleeCrit − supp(meleeCrit, cpa × p.agi, bonus_hand))`, the main
    hand at `p.mhSkill` (its white roll and `critAbil`), the off hand at `p.ohSkill` (its white roll);
  - pet: `critP = max(0, petCrit − supp(petCrit, 0, 0))` with `petCrit = petCritBase + fer` (543); hawks: `critH =
    max(0, hawkCrit − supp(hawkCrit, 0, 0))` with `hawkCrit = 0.5 × petCritBase + fer` (528); `petCritBase = max(0,
    meleeCrit + 0.0004 × min(p.mhSkill, 0), crit + 0.0004 × min(p.rangedSkill, 0))`, wowsims' `inheritedCrit` (W1D
    section 4, `pets.go:142-153`): the melee branch with the main hand's skill and the ranged branch with the ranged skill,
    each 0.04% a point below the level's maximum, nothing above it.
- Weights. Every mutation of `Model.Weights` goes through `Model.ApplyStats` (6.8), so the stat keys mean one thing
  everywhere. `W.AGI = deriv(p, t0, function(q, d) Model.ApplyStats(q, { AGI = d }, T) end, 10) / unitDps`, where
  `ApplyStats` turns `d` item Agility into `e = d × agiMult` effective Agility (Lightning Reflexes,
  `Core/Model.lua:813`; × `p.statMult.AGI`, O8 = (a)) and adds `2e` to `rap`, `e` to `map`, `cpa × e` to `crit` and
  `meleeCrit`, and `e` to `agi`. No `× agiMult` follows the derivative (today's `Core/Model.lua:819` multiplies outside,
  with the mutation in effective units; with the mutation through `ApplyStats` an outer factor would count Lightning
  Reflexes twice). Since `agi` moves with the Agility crit, that crit stays out of the aura part. `W.CRIT`,
  `W.CRIT_RANGED` mutate crit only (aura crit grows with them); `W.SKILL_CRIT` and `W.SKILL_CRIT_NO_SHOTS` (W1D 3.3) take
  one ranged skill point below `min(p.rangedSkill, 0)`, with and without shots. Consequence (my reading of the
  formula, as critic.md checks): with aura crit above 1.8% (Lethal Attacks 2 gives 2%, `Core/Model.lua:127`) the clamp
  is saturated, so the suppression is a constant 4.8% at +3 and the crit weight is not cut; below 1.8% aura crit an
  item's crit is suppressed point for point.
- Both modes: by `d`; raid is always +3.
- Tests: moves — not measured (a new mechanism); the tests that run at +3 are the candidates (C.md):
  `tests/test_model.lua:50-64, 597-640`; `tests/test_score.lua:1857, 2081, 2351-2352`;
  `tests/test_game.lua:2779-2789, 4102-4103`; the implementing step measures them and re-derives each moved number by hand.
  New: `suppression: 0 / 1 / 2 / 3% skill part at +0..+3` (mutant: 0.001 a point); `suppression: the aura part only at
  +3, clamped at 1.8%` (mutants: at +2; no clamp); `suppression: Agility crit is not aura crit (W.AGI vs W.CRIT at aura
  below 1.8%)` (mutant: `agi` left out of the AGI mapping); `W.AGI with Lightning Reflexes 5/5 at aura crit below 1.8% is
  1.15 × W.AGI without` (mutants: `agi + d` with the crit at `cpa × d × agiMult`; an outer `× agiMult` on top of
  `ApplyStats`); `suppression: pet and hawks lose all their crit as aura` (mutant: their crit taken as Agility crit);
  `suppression: magic procs keep spell crit whole` (mutant: suppression on spell crit).

### 4.3 White swings as one roll; pet specials; parry

- Rule (wowsims): a white melee swing is one roll; its expected multiplier is
  `1 − miss − dodge − parry + (critMult − 1) × min(crit, critRoom) − glance × (1 − (glanceMin + glanceMax)/2) − block × blockedFraction`,
  `critRoom = 1 − miss − dodge − parry − glance − block`; parry and block only from the front
  (`wowsims/sim/core/spell_outcome.go:852-875`, `886-893`). A melee special (Raptor, Mongoose, Strider Kick, the pet's
  Claw / Bite) rolls hit then crit: `(1 − miss − dodge − parry) × (1 + crit)` from behind (`spell_outcome.go:303-333`,
  `875-882`). Parry `= 0.05 + 0.001 × baseSkillDiff` up to a 10-point gap, `0.05 + 0.006 × baseSkillDiff` past it
  (`target.go:585-590`): 5 / 5.5 / 6 / 14% at +0..+3 (my arithmetic). Glance chance `clamp(0.1 + 0.02 × baseSkillDiff)`,
  damage `[clamp(1.3 − 0.05 × skillDiff, 0.01, 0.91), clamp(1.2 − 0.03 × skillDiff, 0.2, 0.99)]` (`target.go:576-578`).
- HGA today multiplies `(1 − miss)(1 + crit) × GlanceMult` (`Core/Model.lua:536, 577, 583, 611, 614`).
- HGA formula: `Model.GlanceMult(d)` splits into `Model.Glance(d, bonus)` returning `chance, avg` by the attacking
  hand's skill bonus (W1D 3.4: chance from `5d + max(0, −bonus)`, the bounds from `5d − bonus`, at `capDiff`; the pet and
  the hawks at bonus 0); `GlanceMult` stays `1 − chance × (1 − avg)` at bonus 0 for callers.
  A local `white(miss, dodge, parry, crit, gChance, gAvg)` with the attacker's glance:
  `room = 1 − miss − dodge − parry − gChance`; `return 1 − miss − dodge − parry + math.min(crit, room) − gChance × (1 −
  gAvg)` (crit multiplier 2, so `critMult − 1 = 1`; `spell.go:959-975`).
  - Hunter melee (Survival only), per hand (W1D 3.4): the main hand's white roll `white(whiteMissMH, dodgeMH, 0,
    critM_MH, Model.Glance(d, p.mhSkill))`, the off hand's `white(whiteMissOH, dodgeOH, 0, critM_OH, Model.Glance(d,
    p.ohSkill))` × 0.5 × Predator's Edge, each miss and dodge by its hand's skill (the main hand's miss less
    `p.meleeHit`); specials keep `hitSpecial × critAbil` (two rolls) on the main hand's entry.
  - Pet: `parryP = CONST.petTanks > 0 and max(0, parry(d) − p.expertise/100) or 0` (expertise lowers dodge and parry,
    each floored at 0, `wowsims/sim/core/unit.go:1175-1196`);
    `petWhiteDmg = (creatureDPS + 0.10 × max(rap, map)/14) × petHaste × white(missP, dodgeP, parryP, critP, Model.Glance(d, 0))`;
    `petSpecialDmg = petSpecial × (1 − missP − dodgeP − parryP) × (1 + critP)`;
    `out.pet = (petWhiteDmg + petSpecialDmg) × petMult × phys`.
  - Hawks: `× white(missH, dodgeH, 0, critH)` in place of `glance × max(0, hitf − hawkDodge) × (1 + hawkCrit)` (536-537).
- Block. From the front wowsims also rolls a 5% block (`BaseBlockChance = min(0.05, 0.05 + skillDiff × 0.001)`,
  `target.go:575`; `unit.go:1207-1215`) that takes the target's block value off the hit (`blockedFraction`,
  `spell_outcome.go:895-900`). It matters for the tanking pet of levelling mode only (raid: the pet is behind). No source
  here gives a creature's block value by level (ExpectedStat holds no block column; D.md found no creature data), so
  levelling leaves the block out (approximation A8): its loss is 5% × min(1, blockValue / hit) of the pet's hits.
- Parry and expertise. Levelling keeps the tanking pet (`CONST.petTanks = 1`), now with wowsims' parry: at +0..+2 it
  equals today's dodge base, at +3 it is 14% against 6.5%. Expertise lowers dodge and parry; past the dodge (6.5%) it
  still lowers a tanking pet's parry up to 14%. So Score's expertise term becomes two-sloped:
  `expertiseValue(e) = W.EXPERTISE × min(e, ctx.expertiseCap) + W.EXPERTISE_PARRY × clamp(e − ctx.expertiseCap, 0, ctx.parryCap − ctx.expertiseCap)`
  (`Core/Score.lua:705-708`), `W.EXPERTISE_PARRY` = the slope taken at `expertise = Model.MobAvoid(d)` (only the
  tanking pet's parry left), `ctx.parryCap = Model.PetParry(d)` when the pet tanks, else `= ctx.expertiseCap`
  (Advisor A.State, `Game/Advisor.lua:162`). In raid mode (pet behind) `ctx.parryCap = ctx.expertiseCap` and the second
  term is 0.
- Both modes: the single roll and the parry formula; raid has no parry and no block.
- Tests: moves — every test that pins a pet or hawk DPS number at any mobDiff (the factor changes at +0 too: glance 10%
  at 0.95). Candidates: `test_model / reference BM 32/2 build: weights of the current model` (C.md: it moves under every
  pet/hawk mutation), `test_model / hawks: …` (553, 597), `test_model / pet swing: …` (454, 483, 508),
  `test_model / W.EXPERTISE: …` (616). `test_model / wowsims check: pet family passive and abilities, parry when the pet
  tanks` keeps `e1/e0 = 2` at +0 (dodge and parry both linear in expertise). Measured in the step.
  New: `white table: one roll, crit capped by the room left` (mutant: no `min`); `white table: glance takes chance ×
  (1 − avg) off, not a factor` (mutant: the factor); `pet specials: two rolls` (mutant: the white table on specials);
  `parry: 5 / 5.5 / 6 / 14% at +0..+3` (mutant: 0.001 past 10); `parry: none from behind (raid)` (mutant: parry with
  petTanks 0); `expertise: a tanking pet at +3 gains past the dodge cap up to 14%` (Score, mutant: one slope).

### 4.4 Pet and hawk hit

- Rule (wowsims): the pet and the hawks take the owner's physical hit plus the owner's ranged-only hit
  (`wowsims/sim/hunter/pets.go:155-158` `inheritedHit`; pet `pets.go:122-145`; hawks `summon_hawk.go:79-86`). The
  ranged-only hit is the `RangedHitPercent` pseudo-stat, which wowsims' item and enchant fold fills from an aura 54 bound
  to ranged weapons (`tools/database/dbc/util.go:356-373`; `tools/database/equip_pseudo_stats_test.go:88-105` pins the
  +3% scope 2523 to ranged hit alone). Weapon skill is no stat there: their tables are their own at level 60, skill 300.
- HGA today: the pet's miss is `missChance(mobDiff, p.hit)` (`Core/Model.lua:363, 545`), the hawks' `hitf` (537).
- HGA formula: `missPH = missChance(d, p.hit + p.rangedGearHit)` for the pet and the hawks; the shots
  `missChance(d, p.hit + p.rangedGearHit + p.rangedHit)` (366, `p.rangedHit` = the worn ranged skill's hit, shots only,
  unchanged); the hunter's melee `missChance(d, p.hit)` (and the dual-wield white miss, 607). Comment at
  `Core/Model.lua:396-403` is rewritten to state the wowsims rule.
- Both modes.
- Tests: moves none while `rangedGearHit` is 0 in every fixture. New: `ranged gear hit reaches the shots, the pet and the
  hawks, not the hunter's melee` (mutants: drop it from the pet; add it to melee).

### 4.5 Beastslaying and AP versus a creature type

**Beastslaying.**
- Rule (wowsims): Beastslayer's aura is `A_MOD_DAMAGE_DONE_CREATURE` on the player (`spelldata/mob_types.go:9-16`:
  PhysicalDamage and SpellDamage against the masked types); `CalcDamage` adds the flat bonus to the base damage before
  the attacker's multipliers, armor and the outcome when the spell has `BonusCoefficient > 0` or is physical school
  without `SpellFlagPhysicalSchoolDamage` (`spell_result.go:445-466`, `391-443`); a physical row that deals school
  damage gets that flag and its coefficient (`spelldata/resolve_spell.go:135-139`); periodic damage only with a dot
  coefficient (`spell_result.go:467-481`). Auto attacks of a physical weapon have coefficient 1 (`attack.go:130-136`);
  the off hand's 0.5 is on the weapon damage alone (`attack.go:174-176`), the flat bonus is added whole.
- Which hunter hits get it (DB2 SpellEffect effect types): weapon-damage rows — Aimed Shot 20904 (row 697764, Effect 121),
  Multi-Shot 2643 (680907, 121), Sniper Shot 1310786 (1340619, 121), Raptor Strike 14266 (691552, 58), Mongoose Bite
  14271 (690394, 121), Strider Kick 1317257 (1350273 / 1350274, 121 / 31) — plus white main hand, off hand and Auto
  Shot: yes. School-damage rows — Arcane Shot 14287 (691069, Effect 2, arcane school) and the dive 1293527 (1314239,
  Effect 2): no. Serpent Sting's ticks: no (no dot coefficient). The pet and the hawks: no (other units: the bonus sits
  on the hunter's own attack tables, `attack_table_helpers.go:46-61`). The task's list names neither Sniper Shot nor
  Strider Kick; the DB2 rows put them with the weapon strikes.
- HGA formula: model input `p.beastSlaying` (flat per hit, Player.WeaponInputs: `BEAST_SLAYING` of the main hand plus
  the off hand of the set, `Game/Player.lua:175-194`); `flat = p.beastSlaying × targetShare("BEAST", p.mode)` with
  `targetShare(type, mode) = mode == "raid" and (type == CONST.raid.targetType and 1 or 0) or Model.AP_CREATURE_SHARE`.
  Added inside each strike's base damage (`Core/Model.lua`):
  Auto Shot `(w + rapShot/14 + flat/s)` (446); Aimed `(w×s + … + 9 + flat)` (454); Multi (470); Sniper (503);
  white MH `(p.mhDPS + p.map/14 + flat/p.mhSpeed)` (611); white OH `(0.5 × (p.ohDPS + p.map/14) + flat/ohSpeed)` (614);
  Raptor `swing + raptorBonus + flat` (634, both its own and the white swing it replaces); Strider `normHit + flat` (641);
  Mongoose `normHit + bonus + flat` (681). Everything after the base (crit, armor, multipliers) applies as for the rest.
- Score: `beastSlayingValue` (`Core/Score.lua:576-594`), `ctx.meleeSwingMult`, `ctx.meleeFrac` and
  `Model.MeleeSwingMult` (`Core/Model.lua:336-347`) are removed. With `ctx.weaponGain` the flat damage is inside the
  set's weapon run (WeaponInputs carries it); without it `ItemValue` prices `BEAST_SLAYING × W.BEAST_SLAYING` for a weapon
  in the main hand or a dual-wield off hand, `W.BEAST_SLAYING` = the derivative of `Model.Total` by `p.beastSlaying`.
- Both modes: levelling × 0.3 (beasts' share, as today's share), raid 0 (dragonkin, `defaults.siml:65`).
- Tooltip (`Game/Advisor.lua:671-674`): levelling `HGA: «+%d к убийству животных» учтено по зверям (доля 30%%) на всех ударах оружием и выстрелах (оценка)`;
  raid `HGA: «+%d к убийству животных» — в рейд-режиме цель дракон: не учитывается`.
- Tests: moves (C.md mutation `RapidFire_15of180` lists the Beastslaying swing-rate tests): `test_score / Beastslaying:
  the swings at the model's melee swing rate (ctx.meleeSwingMult) at the same W.EXTRA_DPS` (1317-1337) and the
  Beastslaying cases at `tests/test_score.lua:1269-1361, 2295-2309`; `test_game / stats-gear-10: the worn bow's crit
  scope counts; Beastslaying is noted as a melee estimate` (2577-2580); `tests/test_game.lua:3245, 4458-4471`
  (`meleeSwingMult` in dump and ctx); `test_model / MeleeSwingMult: …` (710) is removed with the function, and
  `test_model / talent ranks without a talent the model reads are an error in Parts, Weights, MeleeSwingMult and
  SecondaryRates` (306) drops MeleeSwingMult. New: `beastslaying: flat on Auto, Aimed, Multi, Sniper, Raptor, Mongoose,
  Strider, white MH, OH whole` (one mutant per strike: the flat dropped there); `beastslaying: none on Arcane, Serpent,
  dive, pet, hawks` (mutant: flat on Arcane); `beastslaying: before armor and crit` (mutant: added after);
  `beastslaying: 0.3 levelling, 0 raid` (mutant: 0.3 in raid); `beastslaying on a 2H with meleeFrac 0 still raises the
  shots` (mutant: flat only with meleeFrac > 0; from step A2 the case reads "outside the Survival branch", section 15).

**AP versus a creature type.**
- Rule (wowsims): `AddMobTypeBonusStats` adds the stats to the unit's own attack tables, against a defender of the masked
  type only (`attack_table_helpers.go:46-54`); the hunter's attacks read them: `RangedAttackPower(target)`
  (`spell_result.go:185-187`) and the melee attack power (`unit.go:265-267`) add `MobTypeBonusStats[target.MobType]`.
  The pet and the hawks take their attack power from the owner's stats, which hold no versus-type part: the pet
  `max(AP, RAP) × 0.1` (`wowsims/sim/hunter/pets.go:122-128`), a hawk `(RAP + hawkWeaponAP) × 0.8`
  (`summon_hawk.go:79-81`). So versus-type AP reaches the hunter's own attacks alone: the shots (Auto, Aimed, Multi,
  Arcane, Sniper), Serpent Sting's RAP part, the dive's RAP part (the hunter's spell, `summon_hawk.go:130-139`) and the
  hunter's melee. The misc value is a creature-type mask, bit `1 << (type − 1)`: 1 Beast, 2 Dragonkin, 4 Demon,
  8 Elemental, 16 Giant, 32 Undead, 64 Humanoid, 256 Mechanical (`spelldata/mob_types.go:32-55`).
- DB2 (my query of `db2/SpellEffect.csv` for aura 102 / 131 with Effect 6, and `db2/Spell.csv`, `db2_ru/Spell.csv`): the
  equip texts that Parse must read, by mask (spell ID, then the physical lines of `db2/Spell.csv` / `db2_ru/Spell.csv`):
  | Mask | enUS (`db2/Spell.csv`) | ruRU (`db2_ru/Spell.csv`) | e.g. spell (lines en / ru) |
  |---|---|---|---|
  | 1 Beast | `+$s1 Attack Power against Beasts.` | `+$s1 к силе атаки против животных.` | 13492 (4174 / 4187) |
  | 2 Dragonkin | `+$s1 Attack Power against Dragonkin.` | `+$s1 к силе атаки против драконов.` | 24291 (25936 / 26558) |
  | 4 Demon | `+$s1 Attack Power against Demons.` | `+$s1 к силе атаки против демонов.` | 12822 (4029 / 4045) |
  | 8 Elemental | `+$s1 Attack Power against Elementals.` | `+$s1 к силе атаки против элементалей.` | 22836 (6632 / 6678) |
  | 16 Giant | `+$s1 Attack Power against Giants.` | `Увеличение силы атаки против великанов на $s1 ед.` | 21937 (6445 / 6489) |
  | 32 Undead | `+$s1 Attack Power against Undead.` | `+$s1 к силе атаки против нежити.` | 12981 (4076 / 4092) |
  | 64 Humanoid | `+$s1 Attack Power against Humanoids.` | `+$s1 к силе атаки против гуманоидов.` | 1292025 (16719 / 17401) |
  | 256 Mechanical | `+$s1 Attack Power against Mechanical units.` | `Увеличивает силу атаки против механизмов на $s1.` | 435360 (11693 / 11895) |
  | 36 Undead + Demon | `+$s1 Attack Power against Undead and Demons.  Allows the acquisition …` / `+$s1 Attack Power when fighting Undead and Demons.  It also allows …` | `Повышает силу атаки против нежити и демонов на $s1. Также позволяет …` / `Повышает силу атаки в бою против нежити и демонов на $s1. Также позволяет …` | 29112 (8174 / 8230), 1219521 (13775 / 14383) |
  | 32 Undead (scourgestones) | `+$s1 Attack Power against Undead.  Allows the acquisition of Scourgestones …` | `Повышает силу атаки против нежити на $s1. Также позволяет собирать камни Плети …` | 23930 (6961 / 7005) |
- Parse (`Core/Parse.lua:71-75, 552-559`): `CREATURE_AP_PATTERNS` becomes a list of `{ pat, types = { … } }` built from
  the table above (a capture for the amount, the types it names); each match adds `AP_VS_<TYPE>` for each type
  (`AP_VS_BEAST`, `AP_VS_DRAGONKIN`, `AP_VS_DEMON`, `AP_VS_ELEMENTAL`, `AP_VS_GIANT`, `AP_VS_UNDEAD`,
  `AP_VS_HUMANOID`, `AP_VS_MECHANICAL`). A line with "against"/"против" and an unknown type word matches no pattern and
  stays an equip effect "not counted" (today's path, `Core/Parse.lua:579-582`). The key `AP_CREATURE` is removed.
  `Game/Items.lua:28` maps `ATTACK_POWER_VS_BEAST` to `AP_VS_BEAST`.
- Generators: `tools/gen_set_data.py:177-212` turns the 102 + 131 pair into `AP_VS_<TYPE>` per bit of the misc mask
  (one key per type; a mask with a bit outside the eight types makes the spell unknown, as today); `tools/gen_use_data.py:61-62`
  `DAMAGE_KEYS` lists the eight keys in place of `AP_CREATURE`; `Game/SetData.lua` (three `AP_CREATURE` bonuses:
  lines 73, 85, 253) and `Game/UseData.lua` are regenerated.
- Model: new input `p.apVsTarget`, the versus-type attack power against the mode's target (2.4: the worn items' and set
  bonuses' `AP_VS_<TYPE>` × `targetShare(TYPE, p.mode)`; it is on no live sheet, as today's `AP_CREATURE`). In
  `partsAndHits` it is added to the hunter's own attack power only: `rapOwn = p.rap + p.apVsTarget` for Auto, Aimed,
  Multi, Arcane, Sniper, Serpent Sting's `0.25 × rapShot` and the dive's `0.05 × rapShot` (`rapShot = rapOwn +` Hunter's
  Mark), `mapOwn = p.map + p.apVsTarget` for the hunter's white swings and melee abilities; the pet keeps
  `0.10 × max(p.rap, p.map)` and the hawks `0.8 × (p.rap + 7 + 14 × p.bowDPS)`.
- Model.Weights (`Core/Model.lua:928`): `W.AP_VS = deriv by p.apVsTarget / unitDps` (the model is linear in it, so the
  point's own value does not move the weight) and `W.AP_VS_<TYPE> = W.AP_VS × targetShare(TYPE, p.mode)`: levelling 0.3
  for each type, raid `W.AP_VS_DRAGONKIN = W.AP_VS` and the other seven 0. `W.AP_VS < W.AP` whenever a pet or hawks are
  out (a reviewer's rough arithmetic at the BM point, not recomputed here: pet and hawks take about 20% of `W.RAP`).
  `Model.ApplyStats` (6.8) maps `AP_VS_<TYPE>` of a Use buff to `p.apVsTarget` × the share.
- Two-type lines in levelling: a line that names two types (Undead and Demons) gives both keys, so levelling prices it
  at 2 × 0.3 where today's single `AP_CREATURE` priced it at 0.3. The 0.3 share is an estimate either way (C.md: no
  test pins it, mutations `AP_CREATURE_SHARE_0/1`: 0 failed); the doubling is stated here and in the tooltip.
- Tooltip (raid, new line for a non-dragonkin key): `HGA: «+%d к силе атаки против %s» — в рейд-режиме цель дракон: не учитывается`
  (the ruRU type words of the table); the dragonkin key's: `HGA: «+%d к силе атаки против драконов» учтено полностью: в
  рейд-режиме цель дракон` (built in step 10, kept by group 0, 18.9); every versus-type line adds `(только твои атаки: пету и
  ястребам не идёт)`.
- Tests: moves — `AP_CREATURE` users: `tests/test_parse.lua:23`, `tests/test_score.lua:599-601`,
  `tests/test_game.lua:1583, 3097` (C.md: the share itself is pinned by no test, mutations `AP_CREATURE_SHARE_0/1`: 0
  failed). New: one Parse case per row of the table in ruRU and enUS (mutant: drop a row); `AP vs Undead and Demons adds
  both keys` (mutant: the first type only); `weights: levelling 0.3 for every type; raid dragonkin 1, beast 0` (mutants:
  raid 0.3; dragonkin 0); `AP vs type reaches the shots, Serpent, the dive and melee, not the pet or the hawks` (mutants:
  `apVsTarget` in the pet's `max(rap, map)`; in `hawkAP`); `gen_set_data: the mask gives the type key` (test_score's
  SetData case at 599-601 re-pinned to `AP_VS_HUMANOID=15`).

### 4.6 Procs

**4.6.1 The Highborne Research Tablet at each hitting hand's speed.**
- Rule (wowsims): the trigger 1318159 rolls 2.6 a minute (`triggerRow.RPPM`, override per EV-0021) through
  `NewLegacyPPMManagerWithSpells` (`wowsims/sim/common/forever/items_trinkets.go:253-286`, the manager at 275-277):
  main-hand hits at the main hand's speed, off-hand hits at the off hand's, ranged hits at the ranged weapon's
  (`wowsims/sim/core/procs.go:183-227` `mergeOrAppend`), and every other hit of the mask except a ranged auto attack at
  the main hand's own weapon speed (the fallback entry, `procs.go:62-82`; `WeaponFromMainHand`, the unarmed weapon of
  speed 1 when the main hand is empty, `attack.go:35-45, 96-102`). RequireDamageDealt forced true
  (`items_trinkets.go:279-281`, EV-0021 lines 9-20).
- HGA: `Score.MEASURED_SPEED` (`Core/Score.lua:135-139`) is removed; `Score.ProcRate` (288-320) loses the `fixed` branch:
  every rate is taken at `h.speed` of the hand that hits. The Tablet's entry of `Score.MEASURED_PPM` gets
  `spellsAtMainHand = true` (the `WithSpells` manager): with no ranged weapon worn, the dive's hits (4.6.3) roll it at the
  main hand's speed (1 unarmed; HGA's unarmed main hand swings at 1.0 s everywhere from step A3, section 16).
  The tooltip line (`Game/Advisor.lua:656-662`) becomes `(%.2f/мин на скорости бьющей руки — замер по логам; …)`.
- Both modes.

**4.6.2 Equip procs by their DB2 trigger.**
- Rule (wowsims): an equip proc's trigger decodes its ProcTypeMask: 0x4 melee white, 0x10 melee abilities, 0x40 ranged
  auto, 0x100 ranged abilities, 0x10000 / 0x40000 spell damage (`wowsims/sim/core/proc_types.go:86-110`, flags
  `dbcenums/proc_flags.go:10-31`; trigger `spelldata/resolve_proc.go:32-68`). RequireDamageDealt starts true and the
  harmful-spell bit 0x10000 among the dealt bits clears it (`proc_types.go:166-175`): such a proc hears a landed hit that
  deals no damage, Serpent Sting's application included (it has `ProcMaskRangedSpecial`, `serpent_sting.go:25-28`).
  wowsims overrides that for the Tablet alone (`items_trinkets.go:279-281`, from EV-0021). The rate comes from the
  trigger's row: a stated procs-per-minute rate, else the stated chance, and the internal cooldown is
  `ProcCategoryRecovery` in ms (`resolve_proc.go:32-68, 182-200, 222-266`; `spelldata/spell.go:50-53`); a row that states
  neither needs a hand-supplied rate (`settleProcRate` panics otherwise, `resolve_proc.go:240-244`; Heartseeking's 29626
  takes its item entry's rate, `items_weapons.go:200-223`). A weapon's chance on hit hears every landed hit of the
  hand(s) holding the weapon, damage or not (`resolve_proc.go:95-111` WeaponProc; hands `character.go:734-751`).
- DB2 examples: Heartseeking Crossbow 13040 → ItemEffect 99815 (TriggerType 1, spell 29626; ItemXItemEffect 93694) →
  SpellAuraOptions 137308 (ProcTypeMask 320 = ranged auto + ranged abilities, ProcChance 100, SpellProcsPerMinuteID 0,
  ProcCategoryRecovery 0) → SpellEffect 704986 aura 42 → 29640 (SchoolMask 32 Shadow, SpellCategories 78298
  DefenseType 3 ranged; 16, Variance 0.375: 13-19, SpellEffect 705032). Highborne Research Tablet 260205 → ItemEffect
  226835 (TriggerType 1, spell 1318159) → SpellAuraOptions 248218 (ProcTypeMask 65876 = 0x10154, ProcChance 100, no PPM
  row) → SpellEffect 1351486 → 1265634 (SchoolMask 64 Arcane, SpellCategories 188733 DefenseType 1 magic; 75, Variance
  0.16: 69-81, SpellEffect 1277542). Firebelcher's 1291686: SpellAuraOptions 245787 (ProcTypeMask 64, ProcChance 100,
  ProcCategoryRecovery 10 ms).
- Generated data: new `tools/gen_proc_data.py` (Python run with `-I`) → `Game/ProcData.lua`:
  `ns.ProcData[itemID] = { { trigger = <spell>, kind = "equip" | "hit", mask = <ProcTypeMask_0, equip only>,
  chance = <ProcChance>, ppm = <SpellProcsPerMinute BaseProcRate or 0>, icd = <ProcCategoryRecovery ms>, spell =
  <damage spell>, avg = <mean>, min, max, school = <SchoolMask>, defense = <DefenseType 0 none, 1 magic, 2 melee,
  3 ranged>, crit = <false when SpellMisc Attributes_2 has 0x20000000> }, … }` from `ItemXItemEffect`, `ItemEffect`
  (TriggerType 1 = equip, 2 = chance on hit), `SpellAuraOptions` (of the equip spell), `SpellProcsPerMinute`
  (`db2_R4-ability-formulas/f/SpellProcsPerMinute.csv`), `SpellEffect` (Effect 6 aura 42 PROC_TRIGGER_SPELL →
  EffectTriggerSpell; the damage effect 2 SCHOOL_DAMAGE base points and Variance; the mean and the bounds as wowsims'
  `spread`, `spelldata/effect.go:125-140`), `SpellMisc` (SchoolMask, Attributes_2), `SpellCategories` (DefenseType; a
  spell with no SpellCategories row has DefenseType 0). Items whose proc is no direct school damage (a DoT, a stat buff)
  are left out here (W1 stats-gear-4); section 17 adds the DoT procs, priced as wowsims (U2 = (a)). The generator checks every row it writes and stops on a chain
  it cannot follow (as `gen_use_data.py` does).
- DefenseType 0 and CannotCrit (wowsims): a damage spell with no stated DefenseType rolls the melee table if its school is
  physical, else the spell table (`wowsims/sim/common/shared/shared_utils.go:76-88` `damageDefenseType`; `spell.go:959-963`
  panics on a crit multiplier for DefenseType none, so the type is settled first); a spell that cannot crit rolls the
  no-crit variant of its table (`shared_utils.go:58-61, 92-119`; the attribute `ATTR_EX_2_CANT_CRIT 0x20000000`,
  `wowsims/tools/database/dbc/spell.go:90-96`, `sim/core/dbcenums/attributes.go:28`). Two items have such a damage
  spell (the reviewer's walk of ItemXItemEffect → ItemEffect → SpellEffect: 223526 → spell 11658, 278219 → 1306765);
  neither spell has a row in any SpellCategories export of build 70888 here (my grep).
- Link (Game/Items.lua `Items.Get`, `Game/Items.lua:74-138`): each parsed proc `{ avg, hits, equip, school }`
  (`Core/Parse.lua:534-578`) is linked to the one `ProcData[itemID]` entry of the same kind (`equip` ↔ `"equip"`,
  else `"hit"`) whose mean equals the parsed average within 0.5. The linked proc gets `mask`, `chance`, `ppm`, `icd`,
  `school`, `defense`, `crit`.
- An unlinked proc (no entry, or more than one: an item newer than build 70888) keeps today's coverage: it is priced
  with wowsims' rule for a damage spell of no stated DefenseType, by its school as the tooltip names it. Parse adds
  `school = "magic" | "physical"` from the damage words (`PROC_DAMAGE_PATTERNS`, `Core/Parse.lua:143-149`): ruRU
  `ед. урона от <word>` (the school after "урона от") and enUS `<Arcane|Fire|Frost|Holy|Nature|Shadow> damage` are
  magic; `ед. урона`, `ед. физического урона`, `damage` with no school word are physical (the forms of the DB2 Spell
  descriptions, `db2/Spell.csv`, `db2_ru/Spell.csv`). `gen_proc_data.py` checks this rule on the ruRU and enUS
  descriptions of every trigger spell it writes against the row's SchoolMask and stops on a disagreement. The unlinked
  proc takes `defense = 0` (so its table follows the school), `crit = true`, the hits of its text (`hits`, as today) and
  the rate `Score.ProcRateSource` gives it (18.6: `MEASURED_PPM`, else none, since an unlinked proc has no override row
  and no DB2 rate); a priced one's tooltip line says
  `HGA: эффект при попадании не найден в данных DB2 (Game/ProcData.lua): исход по школе урона из текста (оценка)`
  (approximation A14), an unpriced one's says only that its rate is unknown (18.6).
- Score (`Score.ProcRate`, `Core/Score.lua:288-320`), linked equip proc (`proc.equip`):
  - Hits by mask: 0x4 → `mh.swings` at `mh.speed` and `oh.swings` at `oh.speed`; 0x10 → `mh.specials` at `mh.speed`;
    0x40 → `ranged.swings` at `ranged.speed`; 0x100 → `ranged.specials` at `ranged.speed` (the dive included, 4.6.3) and,
    when the mask holds 0x10000 (RequireDamageDealt false), Serpent Sting's landed applications (`ranged.casts`); the
    Tablet keeps RequireDamageDealt (no application). Parse's text-based `hits` for equip lines
    (`Core/Parse.lua:160-188`) stays as the parse result but is no longer read for a linked equip proc.
  - Rate (`Score.ProcRateSource`, 18.6): `MEASURED_PPM[itemID]` first; else the entry's wowsims override row (`ppm` or
    `chance` with its `source`); else the DB2's: `ppm > 0` → `ppm × speed / 60` a hit of each hand (wowsims' legacy PPM
    manager, `procs.go:183-227`; with no ranged weapon the ranged hand's entry is skipped, `procs.go:199-202`); else
    `chance` from 1 to 99 → `chance/100` a hit; else (100, 101 or 0 and no row: no stated rate) no proc, as wowsims makes
    no rate up. Then the internal cooldown: `rate_eff = r / (1 + r × icd/1000)` for a proc rate `r` per second (the mean
    gap of a Poisson trigger with a dead time is `icd + 1/r`, my arithmetic). wowsims' other override fields (an ICD, a
    hint) and its rule for a chance stated on an effect rather than the column (`resolve_proc.go:182-207`) are not
    reproduced (approximation A11); its ProcChanceAlways auras (`spelldata.go:182-186`: the column at 100 or 101 with a
    trigger clause that states no chance, firing on every hit it hears) are, at a chance of 100 a hit (25.3).
  - A chance-on-hit proc keeps today's `hits` rule (`"weapon"`: the carrying weapon's hand, swings, specials and, for the
    ranged hand, Serpent Sting's applications); its rate is `MEASURED_PPM`, else its item's WeaponProcs row, else none
    (18.6).
- Both modes.

**4.6.3 The dive is a ranged ability for procs.**
- Rule (wowsims): Summon Hawk's dive is the hunter's spell with `ProcMaskRangedSpecial` (`summon_hawk.go:130-139`), so it
  rolls ranged-ability equip procs and a ranged weapon's chance on hit; it always lands (`OutcomeRangedCritOnly`,
  `spell_outcome.go:506-517`). Summon Hawk needs no ranged weapon (it has no SpellEquippedItems row,
  `Core/Model.lua:390-392`), so the dive happens without one.
- HGA: `Model.LandedHits` adds the dive casts to `hits.ranged.specials` (`Core/Model.lua:697-701`) whenever hawks are
  out: `1/9` per second in levelling (two dives per 18 s, 519), the fight's dive rate `rH` in raid (6.5). Which managers
  take them without a ranged weapon follows wowsims' managers: a fixed chance hears them (no speed needed); a plain PPM
  rate (`NewLegacyPPMManager`) does not (the ranged entry of speed 0 is skipped, `procs.go:199-202`); the Tablet's
  `WithSpells` manager rolls them at the main hand's speed (4.6.1).
- Tests (4.6.1-4.6.3): moves — the Tablet cases `tests/test_score.lua:2121-2172`
  (`MEASURED_SPEED` pinned: `procs: a held-in-off-hand item of the weapon class in the off-hand kind rolls every hand,
  no sting; a measured rate at MEASURED_SPEED`), `tests/test_game.lua:2089-2092, 2426-2444` and the env item at 399-404;
  every proc test with Summon Hawk taken and a ranged-hand proc gains the dive (candidates: `test_score / procs: a worn
  ranged weapon's proc follows the model's landed shots as the quiver, ranged haste and haste change`, `test_score / procs:
  a weapon's own proc rolls on its own set's hits at its own speed; …`, the C.md `DEFAULTS_ppm_1.0` list of 8 test_game
  proc cases); measured in the step.
- Fixtures (the procs of the tests are invented items with no DB2 row): test_game's environment gets a test table
  `ns.ProcData` with entries for its invented ids (`tests/test_game.lua:409-418` 99502, 2174 99501, 2313-2356, 99504) and
  for the real ones it wears (260205, 17753); test_score's procs (`tests/test_score.lua:171, 226, 1366, 1387, 1407,
  1437, 1687`: `procs = { { avg = …, hits = … } }`) get explicit `mask`, `chance`, `ppm`, `icd`, `school`, `defense`,
  `crit` (or stay unlinked on purpose), and test_score's `ctx` gets `procOutcome` (4.6.4).
- New (each with its mutant): `Tablet: each hand at its own weapon's speed` (mutant: one speed); `Tablet: the dive with
  no ranged weapon rolls at the main hand's speed` (mutant: the dive skipped); `equip proc mask 0x40 alone: Auto Shots
  only` (mutant: specials too); `equip proc mask 0x140: shots and the dive, no Serpent application` (mutant: applications
  counted); `equip proc with 0x10000 and 0x100: Serpent's applications roll it; the Tablet's do not` (mutants: the
  harmful-spell rule ignored; the Tablet's override ignored); `equip proc rate: MEASURED_PPM, else PPM or chance 1-99 (an
  override row's or the DB2's), else none; …` (18.6; mutants: chance 100 taken as a rate; no ICD); `PPM equip proc without a ranged weapon: the
  dive does not roll it` (mutant: the dive at speed 0); `chance on hit on a bow: the dive rolls it` (mutant: no dive);
  `ProcData link: one match by kind and mean; none or two → unlinked` (mutant: the first of two taken);
  `unlinked proc: priced by its tooltip school at its measured rate and noted` (mutant: unpriced); `parse: the proc's school words,
  ruRU and enUS, magic vs physical` (mutant: every proc physical); `gen_proc_data: 13040 → 29640, mask 320, chance 100,
  shadow, ranged; 260205 → 1265634, 65876, arcane, magic; a damage spell with no SpellCategories row → defense 0;
  Attributes_2 0x20000000 → crit false` (one mutant per field).

**4.6.4 Proc damage by the damage spell's DefenseType.**
- Rule (wowsims): a proc's damage rolls the table of its DefenseType: melee, ranged, else the spell table
  (`wowsims/sim/common/shared/shared_utils.go:92-119`; DefenseType 0 by the school, 4.6.2); the Tablet's
  `OutcomeMagicHitAndCrit` (`items_trinkets.go:263-269`); Heartseeking's `OutcomeRangedHitAndCrit`
  (`items_weapons.go:207-215`). The proc spell is built with `ProcMaskEmpty` (`procSpellConfig`,
  `sim/common/forever/items_armor.go:311-317`; the generic builder, `shared_utils.go:121-125`), so a melee or ranged table
  rolls with the main hand's entry (`AttackTable.Hand`, `target.go:606-615`: only a ranged proc mask selects the ranged
  hand), the physical hit alone (`RangedHitPercent` only under `ProcMaskRanged`, `spell_result.go:196-204`) and the
  physical crit alone (`RangedCritPercent` likewise, `spell_result.go:215-219`), suppressed by the main hand's entry
  (`spell_result.go:225-231`). Spell miss `0.04 + 0.01 × levelDiff`, 0.17 at +3 (`target.go:542-547`), less spell hit,
  no 1% floor (`spell_result.go:287-304`); spell crit from SpellCritPercent, not suppressed (`spell_result.go:306-317`);
  crit damage ×1.5 for magic, ×2 otherwise (`spell.go:959-975`); armor for physical school only
  (`spell_resistances.go:18-31`), and no level-based magic resistance (`spell_resistances.go:64-76`: the boss of the
  preset has none). The proc spell takes the hunter's damage multipliers: no `SpellFlagIgnoreAttackerModifiers` (the
  `Proc()` option, `resolve_spell.go:221-233`), so `attackerDamageMultiplierInternal` applies the unit's
  `DamageDealtMultiplier`, `SchoolDamageDealtMultiplier` and the attack table's versus multiplier
  (`spell_result.go:916-927`): Focused Fire (`talents_beast_mastery.go:39-56`, the hunter's `DamageDealtMultiplier`),
  Lone Wolf without a pet (`talents_marksmanship.go:157-173`) and Improved Tracking (`talents_survival.go:49-65`,
  `MultiplyDamageVersus`). Ranged Weapon Specialization does not reach a proc: its aura 79 is bound to ranged weapons and
  becomes a spell mod on the ranged proc mask (`spelldata/weapon_scope.go:40-58` per-weapon rule;
  `parse_effects_table.go:162-170`), which an empty proc mask does not match (my reading).
- HGA formula: new `Model.ProcOutcomes(p)` returns, at the model point, `{ [0] = { phys = …, magic = … }, [1] = magic,
  [2] = melee, [3] = ranged, phys, own, coe, gift }`:
  - magic: `(1 − max(0, spellMiss(d) − p.spellHit/100)) × (1 + 0.5 × p.spellCrit/100)`;
  - melee: the main hand's entry (W1D 3.4): `(1 − max(0, Model.SkillMiss(d, p.mhSkill) − p.hit)/100 − max(0,
    Model.SkillDodge(d, p.mhSkill) − p.expertise)/100) × (1 + critM_MH)` (from behind: no parry, no block);
  - ranged: `(1 − max(0, Model.SkillMiss(d, p.mhSkill) − p.hit)/100) × (1 + critM_MH)`: the main hand's miss with the
    physical hit alone (no `p.rangedGearHit`, no `p.rangedHit`) and the melee sheet's crit as the physical crit without
    the ranged-only part, suppressed as the main hand's (`critM_MH`, 4.2); no dodge (the ranged table has none);
  - DefenseType 0: `[0].phys` = melee, `[0].magic` = magic;
  - the no-crit variants (`crit == false`) drop the `(1 + …)` factor;
  - `phys` = the physical multiplier of the mode (levelling `Model.PhysMult`, raid 5.1); `own = ff × lone × track`
    (`Core/Model.lua:375-380`); `coe`, `gift` of 5.3 (O7 = (a): raid 1.10 and 8, levelling 1 and 0).
  `Score.ProcValue` (`Core/Score.lua:350-356`): `(p.avg × own × (p.school == 1 and phys or coe) + (p.school == 1 and
  gift or 0)) × outcome × rate / 60 × W.EXTRA_DPS`, `outcome = ctx.procOutcome[p.defense]` (for 0, by the school) with
  the crit factor dropped when `crit == false`. `ctx.procOutcome = Model.ProcOutcomes(model)` (A.State). The outcome is
  the worn point's (the set's own hit differs: a cross term left out, as procs leave out the set's other stats today,
  A6).
- Left out (stated): Int's spell crit on magic procs (DB2 PlayerExpectedStat row 306, SpellCritPerIntellect 0.000165;
  wowsims `CritPerIntMaxLevel` hunter 0.0165%, `base_stats_auto_gen.go:38-42`: 10 Int add 0.165% spell crit, about
  0.08% of a magic proc's value, my arithmetic); the Tablet's ×2 against Naga and Satyrs (`items_trinkets.go:256-266`,
  `VersusBonus`: creature families, which HGA does not model; a versus bonus of a creature type counts, 25.2).
- Both modes; at +0 a magic proc misses 4%, at +3 17% (my arithmetic: an 8% hit hunter with no spell hit keeps
  0.83 × (1 + 0.5 × spellCrit) of the Tablet's damage at +3).
- Tests: moves — every test that pins a proc's value with `W.EXTRA_DPS` alone (today no miss / crit: the C.md
  `DEFAULTS_ppm_1.0` cases and `tests/test_score.lua:2295-2309`); measured in the step. New: `proc outcome: magic 17%
  at +3, 4% at +0, less spell hit, ×1.5 crit` (mutants: 0.16; ×2); `proc outcome: a ranged-defense proc rolls the main
  hand with physical hit and crit, no ranged gear hit, no ranged crit` (mutants: `p.rangedGearHit` in its miss; `critR`
  for its crit); `proc outcome: DefenseType 0 by the school` (mutant: always magic); `proc outcome: no crit when the
  spell cannot crit` (mutant: crit always); `proc value: × Focused Fire, Lone Wolf, Improved Tracking` (mutant: `own`
  dropped); `proc outcome: armor on physical school only` (mutant: armor on magic).

### 4.7 The two Parse gaps

**4.7.1 The ranged-weapon hit: items, the rating line and the two scopes.**
- Data: spell 1294769 (SpellEffect 1316376: aura 54 A_MOD_HIT_CHANCE, bp 1, on the caster; SpellEquippedItems row
  256232, `db2_R5-weapons-gear/SpellEquippedItems.csv:1833`: item class 2, subclass mask 262156 = bows, guns, crossbows),
  texts `db2/Spell.csv:36392` enUS `Improves your chance to hit with ranged weapons by ${$s1}.1%.`, `db2_ru/Spell.csv:36349`
  ruRU `Повышает вероятность попадания в дальнем бою на ${$s1}.1%.` (the same text on 22780 bp 3, `db2/Spell.csv:6593`,
  `db2_ru/Spell.csv:6634`; 1301125, 1301127). Items: Marksman Bands 18296, Sash of the Grand Hunt 22207, Stoneshatter 18388,
  Infernal Trickster Leggings 17754 (C.md: ItemXItemEffect 167268/167594/167606/168894). The client also has
  `ITEM_MOD_HIT_RANGED_RATING` (GlobalStrings 16385: enUS `Improves ranged hit by %s.`, ruRU `Меткость (оруж. дальн. боя) +%s.`;
  `db2_R3-core-formulas/GlobalStrings.csv:4964`, `db2_ru/GlobalStrings.csv:5023`).
- The scopes: SpellItemEnchantment 2523 (ruRU `+3% к рейтингу меткости`, enUS `+3% Hit`) and 8057 (ruRU `Птичий прицел
  (+3% к вероятности попадания)`, enUS `Poultry Precision Scope (+3% Hit)`) apply 22780 (`db2_ru/SpellItemEnchantment.csv`
  rows 2523, 8057; enUS `db2_V3-verify-gear-weights/SpellItemEnchantment.csv`; 8057's second effect 1236217 is aura 4, a
  dummy, SpellEffect 1231980). 22780 is aura 54 bp 3 on the caster (SpellEffect 698524) bound to ranged weapons
  (`db2_V3-verify-gear-weights/SpellEquippedItems.csv` row 181192: class 2, subclass 262156): ranged hit alone, as
  wowsims' fold makes it (4.4). Today Parse reads 2523 as `HIT` (`Core/Parse.lua:87-88`, which also gives it to melee and
  the dual-wield part) and 8057 not at all. No other SpellItemEnchantment name is exactly `+N% к рейтингу меткости` or
  `+N% Hit` (my grep of both exports; 2586's `…/+1% к рейтингу меткости` is a combined line that Parse does not split, and
  its 24154 is unbound hit).
- Parse (`Core/Parse.lua:80-131`):
  - two `EXTRA_STAT_PATTERNS` for the item line, stat `RANGED_HIT`:
    `^Повышает вероятность попадания в дальнем бою на ([%d%.,]+)%%$` and
    `^Improves your chance to hit with ranged weapons by ([%d%.,]+)%%$` (`${$s1}.1` prints one decimal; the number goes
    through `Parse.ToNumber` with the client's decimal separator, so `1,0` and `1.0` both read; the in-game rendering is
    checked with `/hga dump`; `Parse:MatchOne` reads this capture with `Parse.ToNumber(n, self.decimal)`, where today it
    calls `tonumber`, `Core/Parse.lua:440`, which fits the integer captures only);
  - the scope patterns of lines 87-88 give `RANGED_HIT` in place of `HIT`, and two more read 8057:
    `^Птичий прицел %(%+(%d+)%% к вероятности попадания%)$`, `^Poultry Precision Scope %(%+(%d+)%% Hit%)$`;
  - `{ key = "ITEM_MOD_HIT_RANGED_RATING", stat = "RANGED_HIT", rating = 10 }` in `STAT_TEMPLATES` (10 rating a 1%,
    `Core/Parse.lua:11-12`). `Parse.New` builds a template pattern only for a key the template table holds
    (`Core/Parse.lua:338-345`), and `Game/Templates.lua:4-31` collects only the keys of its `KEYS` list, so
    `ITEM_MOD_HIT_RANGED_RATING` joins `KEYS` and both locales of `tests/fixtures_templates.lua` (ruRU at line 24's
    block, enUS at 87's, with the texts above).
  The item match runs on the equip body (after `ITEM_SPELL_TRIGGER_ONEQUIP`), as other equip stats do
  (`Core/Parse.lua:549-570`).
- `tools/gen_set_data.py:104-112`: a weapon-bound aura 54 on ranged weapons alone (`ranged_only`) becomes `RANGED_HIT`
  (today: unknown); SetData regenerated.
- Model: input `p.rangedGearHit` (4.4): shots, pet, hawks; not the hunter's melee, not a proc's table (4.6.4).
- Snapshot (`Game/Player.lua:792-805`): `wornRangedHit` = the worn items' `RANGED_HIT` (scope included) + the set
  bonuses'; `model.hit = liveHit − wornRangedHit`, `model.rangedGearHit = wornRangedHit`. Today's live hit is the ranged
  reading (`GetCombatRatingBonus(CR_HIT_RANGED) + GetRangedHitModifier()`, `Game/Player.lua:344`); that it holds the
  ranged-only aura and that `GetHitModifier()` does not is checked in game (`/hga dump` writes both, section 8).
- Score (`Core/Score.lua:692-697`): the set's `r` = its items' and set bonuses' `RANGED_HIT` (excluded from the stat
  loop like `HIT`, `Core/Score.lua:388`); `hitValue(h, r)` =
  `W.HIT × min(h, cap) + W.RANGED_HIT × (min(h + r, cap) − min(h, cap)) + W.HIT_RANGED × (min(h + r + sk, cap) − min(h + r, cap)) + W.HIT_MELEE × (min(h + skM, cap) − min(h, cap)) + DW part`,
  `sk = Model.SkillHit(ctx.mobDiff, b)` the set's ranged skill hit against the level's skill (W1D 3.3: `b` the set's bonus
  with shots, the worn `bWorn` without), `skM`, `skO = Model.SkillHit(ctx.mobDiff, the set's mhSkill / ohSkill)` its hands'
  melee skill hits (`Score.MeleeSkills`, W1D 3.4). The DW part, for a set that dual wields, per hand in its own room
  (`room(x, n) = min(max(x − cap, 0), n)`, W1D 3.4): `W.HIT_DW_MH × (room(h + skM, 19) − dwFromMH) + (W.HIT_DW −
  W.HIT_DW_MH) × (room(h, 19 − skO) − dwFromOH)`, with `ctx.weaponGain` `dwFromMH = room(ctx.wornHit + ctx.wornMeleeHit,
  19)` and `dwFromOH = room(ctx.wornHit, 19 − skO)` (the weapon run holds `p.hit` and `p.meleeHit` at the worn set's),
  without it both 0 (and a set's melee skills differ from the worn set's only with `ctx.weaponGain`, else an error).
  `r` never reaches the hunter's melee.
  The consumers nest (every attack ⊇ shots + pet + hawks ⊇ shots; every attack ⊇ the main hand's melee), so `W.HIT ≥
  W.RANGED_HIT ≥ W.HIT_RANGED`, `W.HIT ≥ W.HIT_MELEE`, and the telescoping is exact. `ctx.baseHit` (`Game/Advisor.lua:148`)
  = live hit − worn ranged gear hit − worn items' and set bonuses' `HIT`; the base ranged gear hit of a set is 0 outside
  its items.
- `Model.Weights`: `W.RANGED_HIT` = derivative by `p.rangedGearHit` at `q0` (`hit = rangedHit = rangedGearHit = meleeHit =
  0`, beside `W.HIT`, `W.HIT_RANGED` and `W.HIT_MELEE`, `Core/Model.lua:883-886`).
- `/hga weights`' cap line (`Game/Commands.lua:65-70`): `capHit = ctx.baseHit + snap.gearHit + snap.setHit +
  snap.rangedGearHit + Model.SkillHit(ctx.mobDiff, bWorn)`, the shots' hit of the worn set (section 8; W1D 3.3).

**4.7.2 Counterattack Lodestone 18537.**
- Data: spell 1318938 (ItemEffect 237974 → item 18537, C.md), SpellEffect `db2/SpellEffect.csv:42125-42128` rows
  1352636 aura 99 bp 30 (melee AP), 1352637 aura 124 bp 30 (RAP), 1352638 aura 102 misc 256 bp 30, 1352639 aura 131 misc
  256 bp 30 (vs Mechanical). Texts: enUS `+$s1 Attack Power, doubled against Mechanical units.` (`db2/Spell.csv:18354`),
  ruRU `+$s1 к силе атаки. Бонус удваивается против механизмов.` (`db2_ru/Spell.csv:19079`).
- Parse: one pattern per locale in the creature-AP list giving `AP = n` and `AP_VS_MECHANICAL = n`:
  `^%+(%d+) к силе атаки%. Бонус удваивается против механизмов%.?$` and
  `^%+(%d+) Attack Power, doubled against Mechanical units%.?$` (the creature-AP loop matches the equip body as the
  tooltip gives it, the trailing period included, `Core/Parse.lua:552-559`). If `C_Item.GetItemStats` also reports AP 30,
  `Items.Get` sees equal values and notes nothing (`Game/Items.lua:105-116`).
- Value: `AP` in both modes (HGA's `AP` = melee and ranged, `Core/Model.lua:820`; owner stats, so it reaches the pet and
  the hawks as today); `AP_VS_MECHANICAL` through `p.apVsTarget` (the hunter's own attacks, 4.5): 0.3 × `W.AP_VS` in
  levelling, 0 in raid.
- Tests (4.7, each with its mutant): `parse: «Повышает вероятность попадания в дальнем бою на 1,0%» and enUS → RANGED_HIT 1`
  (mutant: HIT); `parse: ITEM_MOD_HIT_RANGED_RATING → RANGED_HIT / 10` (mutant: the template missing from
  STAT_TEMPLATES); `templates: BuildTemplates returns ITEM_MOD_HIT_RANGED_RATING` (mutant: the key missing from KEYS);
  `parse: scopes 2523 and 8057, ruRU and enUS → RANGED_HIT 3` (mutants: 2523 as HIT; the 8057 patterns dropped);
  `parse: Lodestone → AP 30 and AP_VS_MECHANICAL 30` (mutant: the `%.?$` tail dropped);
  `score: a set's RANGED_HIT meets the shots' and the pet's cap, never melee's` (mutants: count past the cap; add to the
  dual-wield part); `snapshot: worn Marksman Bands and a worn +3% scope leave p.hit and go to p.rangedGearHit` (mutant:
  the scope kept in p.hit); `/hga weights: the cap line holds the worn ranged gear hit` (mutant: without it); moves none
  (no fixture has either line; C.md ran them as unparsed).

### 4.8 The live sheet's stat multipliers (O8 = (a), the user's answer: they count)

- Gap (critic.md, "gap: рейд-баффы на живом листе против пресета"): with answer 2 the point is the live sheet, which can
  hold all-stat multipliers (Greater Blessing of Kings 25898: aura 137 A_MOD_TOTAL_STAT_PERCENTAGE +10, misc −1, DB2
  SpellEffect 702574; Blessing of Kings 20217 and 1213408; Spirit of Zandalar 24425 and 355365 +15; others by my query
  of `db2/SpellEffect.csv` for aura 137). On such a sheet an item's +10 Agility gives 11; today `Model.Weights` holds
  Lightning Reflexes alone (`Core/Model.lua:812-819`), and the Intellect of a Use buff and of `W.INT` (Careful Aim, the
  mana pool) likewise.
- O8 = (a): new `tools/gen_stat_mult_data.py` → `Game/StatMultData.lua`: every DB2 spell with an Effect 6 aura 137
  effect of positive base points, as `{ [spellID] = { [statIndex] = pct } }` (misc −1 → all five, 0..4 → one), minus
  the talents the model reads itself (Lightning Reflexes, read as a rank); `Player.Snapshot` multiplies the factors of
  the player's live auras among them (`C_UnitAuras.GetPlayerAuraBySpellID`, as `Game/Player.lua:272-284` reads Aspect of
  the Hawk) into `p.statMult = { AGI, STR, INT, SPI }`; `Model.ApplyStats` (6.8) multiplies an item's AGI, STR, INT, SPI
  by them (and the mana of INT through it). (O8 = (b), not chosen, would have left them out: approximation A13.)
- Tests: `stat multipliers: Kings on the sheet makes 10 item Agility 11 in W.AGI` (mutant: statMult
  ignored); `gen_stat_mult_data: 25898 → all stats 10, Lightning Reflexes left out` (mutant: talents kept).
- Built in step 13 (section 21); the stats an effect names are read as wowsims reads them, the second misc value's mask
  first (21.1). The positive effects of aura 80 A_MOD_PERCENT_STAT count as well (Sayge's Dark Fortune of Agility, Elune's
  Blessing: wowsims multiplies a stat by either aura, 24.3).

## 5. The raid target (raid mode)

### 5.1 Armor 976

- Rule: wowsims' boss armor 3731 (`defaults.siml:66`; DB2 ExpectedStat ID 63 CreatureArmor 3731,
  `db2_R3-core-formulas/ExpectedStat.csv:64`) with the preset's debuffs (`defaults.siml:46-48`): one
  MajorArmorReduction (Sunder Armor 11597, SpellEffect 688831 −450 a stack, SpellAuraOptions 124201 CumulativeAura 5;
  Expose Armor 11198, SpellEffect 688758 PointsPerResource −450, the five-point finisher, `tools/database/buffmanifest/buffs.go:531-539`,
  `buffs/debuffs_auto_gen.go:126-133`) and one MinorArmorReduction (Faerie Fire 9907, SpellEffect 687337 −505; Curse of
  Recklessness 11717, SpellEffect 690026 −505); one debuff per category (`buffs/debuffs_auto_gen.go:85-147`; the Minor
  category carries `TODO: verify in game`, `tools/database/buffmanifest/buffs.go:517-527`). The Sunder ramp over five GCDs
  (`buffs/drivers.go:490-509`) does not matter while Expose Armor holds the category (my reading of the same lines).
- Value: 3731 − 5 × 450 − 505 = 976; physical multiplier `max(0.25, 1 − 976 / (976 + 400 + 85 × 60)) = 0.8493`
  (my arithmetic; formula `spell_resistances.go:140-153`; without debuffs 0.5958).
- HGA: `CONST.raid = { bossArmor = 3731, majorArmorReduction = 2250, minorArmorReduction = 505, targetType = "DRAGONKIN", … }`;
  `Model.ArmorMult(armor, level)` = the formula above (today's body of `Model.PhysMult`, `Core/Model.lua:248-253`, which
  keeps the table path for levelling). `partsAndHits` takes `phys` from the mode.
- Armor penetration (O5, the user's answer: as wowsims): flat armor penetration comes off the boss armor, floored at 0
  (`wowsims/sim/core/spell_resistances.go:147-150`): `armor = max(0, 976 − ArPen)`. Parse already reads the item line
  as `ARMOR_PEN` (HEAD `dfa7300` `Core/Parse.lua:37`), and `Model.Weights` sets `W.ARMOR_PEN = 0` today (`Core/Model.lua:1211`). In raid
  mode `W.ARMOR_PEN` becomes the derivative of `Model.Total` by a new model input `p.armorPen` (the worn items' and set
  bonuses' `ARMOR_PEN`, Player.Snapshot; 0 in every fixture), `Model.ApplyStats` maps `ARMOR_PEN` to it, and Score
  prices it by key as today; levelling keeps 0 (the user's answer names the boss armor).
- Whose armor penetration: wowsims takes the attacking unit's own `ArmorPenetration` off the defender's armor
  (`spell_resistances.go:150`, `at.Attacker.stats`), and neither the pet's stat inheritance (`sim/hunter/pets.go:122-140`
  makeStatInheritance) nor the hawks' (`sim/hunter/summon_hawk.go:79-87`) passes it on. So the hunter's own attacks (the
  shots; the dive, the hunter's own spell, `summon_hawk.go:135`; the weave's melee; the procs) face `976 − ArPen`, and the
  pet and the hawks the whole 976 (`Core/Model.lua` physOf).
- Tests: new `raid armor: 976 and 0.8493` (mutants: no Minor; both Minor debuffs; the pet or the hawks with the hunter's
  ArPen); `raid armor penetration: 100 ArPen makes 876, floored at 0` (mutants: no floor; ArPen ignored).

### 5.2 Level, type, position

- +3 always (2.2); dragonkin (`defaults.siml:65`); the pet behind: `petTanks = 0` in raid (no parry, no block); the
  hunter at 12 yd (`bm.siml:9`), which only sets Serpent Sting's travel (6.4).
- The BM build file is loaded over the hunter defaults (`bm.siml:1-14` sets talents, gear, APL and its settings;
  `wowsims/sim/siml/SPEC.md:1740`: "each committed ui/specs build loaded over its defaults"), so the preset's
  consumables, buffs, debuffs and encounter are `defaults.siml`'s.

### 5.3 The preset's other debuffs on the boss (O7 = (a))

The user's answer to O7 (2026-11-17): (a), the boss carries Judgement of Wisdom, Curse of the Elements and Gift of Arthas
as wowsims' preset has them, beside the armor debuffs of answer 3. The preset's nine debuffs (`defaults.siml:46-48`) and
what each does to the hunter in wowsims:

| Debuff | wowsims | On the hunter's damage or mana | Here |
|---|---|---|---|
| Sunder Armor, Expose Armor, Faerie Fire, Curse of Recklessness | armor (5.1) | physical multiplier | answer 3 = (b): counted |
| Judgement of Wisdom 20355 | a permanent aura on the target (`buffs/drivers.go:483-488`); each hit the target takes that its ProcFlags 0x222a8 name (melee swing and ability, ranged auto and ability, harmful spell; decoded `proc_types.go:110-132`) rolls 50% (override ProcChancePct 50, `spells_auto_gen.go:17776-17779`) to give the striker 59 mana (20353, SpellEffect 698050), a landed hit that deals no damage included (`buffs/paladin.go:204-234`), and only a unit with a mana bar gains (`paladin.go:224-227`; in `sim/hunter` only the hunter enables one, `hunter.go:85`) | 29.5 mana per landed hunter hit: Auto Shot, Aimed, Multi, Arcane, Sniper, Serpent Sting's application, the dive, the hunter's melee swings and abilities; none from the pet and the hawks | O7 = (a): counted |
| Curse of the Elements 1311680 (rank 4) | A_MOD_DAMAGE_PERCENT_TAKEN +10 on schools 126, all magic (`spells_auto_gen.go:38326-38331`), the target's school damage taken multiplier (`spelldata/parse_effects_table.go:196-199`); its −75 resistance adds nothing (a resistance below 0 adds nothing, `spell_resistances.go:64-76`) | ×1.10 on Arcane Shot, Serpent Sting's ticks (nature) and magic procs | O7 = (a): counted |
| Gift of Arthas 11374 | A_MOD_DAMAGE_TAKEN +8 physical (`spells_auto_gen.go:8438-8441`) → `BonusPhysicalDamageTaken` (`parse_effects_table.go:223-224`), added to every physical-school hit on the target from any attacker after the attacker's multipliers and armor, before the target multipliers and the outcome (`spell_result.go:391-401, 928-936`) | +8 per physical hit (Auto, Aimed, Multi, Sniper, white melee, Raptor, Mongoose, Strider, Wing Clip, the dive, the pet, the hawks, a physical DoT proc's ticks: section 17), × its outcome | O7 = (a): counted |
| Judgement of Light | heals the attacker (`buffs/paladin.go`) | none | not modelled |
| Insect Swarm 24977 | the target's hit −2% (SpellEffect 703381) | none | not modelled |

- Model (O7 = (a)): the debuffs' values in `CONST.raid`, each from its DB2 row (`coe = 1.10`, `giftOfArthas = 8`; JoW's
  29.5 with step 12), not on/off flags: the user's answer turns every one on, and a flag no setting can change adds
  nothing (built in step 10, kept by group 0, 18.9). `coe = 1.10` multiplies
  `out.arcane`, `out.serpent`, the magic procs (4.6.4), Immolation Trap's ticks (15.4) and the magic DoT procs (17);
  `gift = 8` adds `8 × attempts/s × outcome` to every physical part (the attempts of the part, its outcome factor
  without armor and without the attacker's multipliers); JoW is a mana income (7.5): `J = 29.5 × Σ landed hunter hits/s`
  of the segment (`partsAndHits` returns the landed counts in `hits`, the dive's always landing).
- Tests (O7 = (a)): `raid JoW: 29.5 mana per landed hunter hit, Serpent's application included; none for the pet
  and the hawks` (mutants: misses counted; pet hits counted); `raid CoE: ×1.10 on Arcane, Serpent and magic procs,
  not on physical` (mutant: on Auto Shot); `raid Gift of Arthas: +8 per physical hit after armor, before the outcome`
  (mutants: before armor; on Arcane).

## 6. The raid fight (raid mode)

### 6.1 Structure

- `fight(p)` (Core/Model.lua) builds an ordered list of time segments `{ t0, t1, weight, seg }`; each `seg` holds the
  state that is constant inside it: `rf` (Rapid Fire up), `bw` (Bestial Wrath up), `uses` (the Use buffs and the Frenzy
  Potion up, O2 = (a), 6.3), `manaMax` (the ceiling, moved by an Intellect buff, 7.6), `regime` (`"rich"` /
  `"starved"`, section 7) and the cast shares `serpent`, `aimed`, `hha` (1 = the rich regime's rate). It calls
  `partsAndHits(p, seg)` per segment and returns the weighted sums. The structure is the "time-segmented model"
  the task asks for; it is exact for the fluid model below and gives the overlaps of windows that act on the same part
  (Rapid Fire × Bestial Wrath on the pet) by construction, since inside a segment both factors multiply in
  `partsAndHits`.
- `partsAndHits(p, seg)`: with `seg == nil` (levelling) every line is today's average. With a `seg`:
  - Rapid Fire: `rf = seg.rf and 0.40 or 0`, `rfUp = seg.rf and 1 or 0` in place of `rapidFire(level, T)`
    (`Core/Model.lua:331-334, 384`); the speeds by source of W1D 7.3 (step W5), each `× (1 + rf)` in a Rapid Fire
    window: the owner's shots `ranged × haste_o × (1 + rf)` and melee swings `haste_o × (1 + meleeHaste/100) × (1 + rf)`
    with `haste_o = (1 + haste/100)(1 + attackSpeed/100)(1 + hasteRating/100)`; the pet `petInherit = (1 + haste/100)(1
    + attackSpeed/100)(1 + meleeHaste/100)(1 + rf)` (no haste rating); the hawks `ranged × (1 + haste/100) × (1 + rf)`
    (no attack speed, no haste rating); Raptor's count at `meleeSpeed × (seg.rf and 1.4 or 1)` (633).
  - Bestial Wrath: `× (seg.bw and 1.5 or 1)` in `petMult` (581) in place of 1.075.
  - Use buffs: `Model.ApplyStats(q, use.stats, T)` on a copy of `p` for each use in `seg.uses` (6.8), except the pet's
    attack power (6.8).
  - Cast tempo (6.4, 6.5): `aimedRate × seg.aimed` (453); the HHA elements at three per `C` × `seg.hha` (Arcane
    480, the dive 519, the hawks 536 with the uptime of 6.5); Serpent Sting from 6.4 × `seg.serpent`.
  - Rapid Killing: the Aimed bonus line (458-460) is skipped with a `seg` (no kill inside the fight).
  - `armor` 976, `petTanks` 0 (5.1, 5.2); the debuffs of 5.3 (O7 = (a)).
  It also returns, beside `out` and `hits`, `casts = { serpent, aimed, hawk, arcane, raptor, mongoose, strider, sniper }`
  per second at the segment's shares, which sections 6.4 and 7 read for the tempo and the mana spend.

### 6.2 The time axis and the weight

- Rule: wowsims draws the fight length uniformly in 180 ± 5 s (`defaults.siml:58-59`; `wowsims/sim/core/sim.go:410-414`).
- HGA: each instant `t` counts with `w(t) = 1` for `t < 175`, `(185 − t)/10` for `175 ≤ t < 185`, 0 after: the share of
  fights still running at `t`. The fight's DPS = `Σ_seg DPS_seg × ∫_seg w(t) dt / 180` (∫w over [0, 185] = 180, my
  arithmetic). This is the ratio of expectations E[damage] / E[length] (close to wowsims' mean of per-fight DPS) and makes
  every event that starts near the end fade out continuously, which keeps `Model.Weights`' finite differences smooth
  (6.9). Constants `CONST.raid.fight = 180`, `fightVariation = 5`.

### 6.3 Cooldown windows

- Rule: wowsims' BM APL casts every ready major cooldown from 5 s (`turret_hawk.apl.siml:12`
  `autocast_other_cooldowns if current_time >= 5s`; `apl_actions_casting.go:596-619`); a cooldown fires only when it can
  be cast, mana included (`major_cooldown.go:110-133` `shouldActivateHelper` → `Spell.CanCast`; `369-402`
  `getFirstReadyMCD`, which takes the ready cooldowns by ready time, then priority, then their registration order: a stable
  sort, `major_cooldown.go:404-420`). Rapid Fire (`rapid_fire.go:25-28`) and Bestial Wrath
  (`talents_beast_mastery.go:114-125`, pet out) are MCDs; a Use trinket of stats is one through
  `NewSimpleStatActive` → `RegisterTemporaryStatsOnUseCD` (`sim/common/shared/shared_utils.go:1236-1257`,
  `sim/core/major_cooldown.go:423-447`); the potions and the rune are MCDs too (7.4).
- Rapid Fire 3045: 15 s (SpellMisc 314846, `db2/SpellMisc.csv:487`, DurationIndex 8 = 15000 ms), category cooldown 300 s
  (SpellCooldowns 53197, `db2/SpellCooldowns.csv:217`), cost 100 (SpellPower 169901,
  `db2_R4-ability-formulas/f/SpellPower.csv:204`), −60 s a rank of Rapid Killing (`Core/Model.lua:332`). Windows
  `[5 + k·cd, 5 + k·cd + 15)` while the start is below 185; with RK ≤ 2 (cd ≥ 180) one window `[5, 20)` that counts (a
  second would start at 185 with weight 0; my arithmetic).
- Bestial Wrath 19574 (talent and pet out): 18 s (SpellMisc 329513, `db2/SpellMisc.csv:10563`, DurationIndex 85 = 18000
  ms), cooldown 120 s (SpellCooldowns 55448, `db2/SpellCooldowns.csv:2120`), +50% pet damage (SpellEffect 697223), cost
  12% of base mana (SpellPower 184568) = 206.4 at 60 (base mana 1720: DB2 PlayerExpectedStat row 306,
  `db2_R3-core-formulas/PlayerExpectedStat.csv:307`). Windows: `[5, 23)`; the second from 125 s if mana allows at that
  moment, else when the income can buy it (7.5, 7.6), else none.
- Use buffs (6.8): each item's buff fires at 5 s and then every cooldown; a burst-category buff (SpellCategory 1141,
  `Game/UseData.lua` `category`) locks the other burst buffs for its own duration (today's rule, `Core/Score.lua:714-716`),
  so a second burst trinket starts when the first ends. At a tie the buffs fire in wowsims' registration order: it walks
  the equipment array in its ItemSlot order (`item_effects.go:107-120` `applyItemEffects` over `Equipment
  [NumItemSlots]Item`, `database.go:305`; `proto/common.proto:466-484`: head 0, neck 1, shoulder 2, back 3, chest 4, wrist
  5, hands 6, waist 7, legs 8, feet 9, the fingers 10-11, the trinkets 12-13, main hand 14, off hand 15, ranged 16),
  appending each Use cooldown to its list (`major_cooldown.go:236-268`), and fires the ready ones by ready time, then
  priority (0 for an item's), then the list's order, which a stable sort keeps (`major_cooldown.go:369-421`). So the legs
  (Cloudkeeper Legplates 14554) fire before trinket 13 and 13 before 14 (`Score.SetUses`). At a later tie wowsims' list
  holds the order its re-sorts by ready time left; two burst buffs tie again only where one's cooldown is the other's
  duration and cooldown, which no pair of `Game/UseData.lua` has (my arithmetic; approximation A5). Windows are cut by
  the weight at 185 s.
- The Frenzy Potion window (O2 = (a), 7.4): `[5, 35)`, and `[125, 155)` when the mana potion does not fit at 125 s.
- Mana for Rapid Fire and Bestial Wrath: paid at their start (7.6).

### 6.4 The cast tempo and Serpent Sting's re-cast

- Rule (wowsims scheduling): after an action on the GCD the rotation looks again exactly when the GCD ends
  (`SetGCDTimer` → `SetRotationTimer(gcdReadyAt)`, `wowsims/sim/core/gcd.go:93-107`), after a hardcast that outlasts the
  GCD at the cast's end (`hardcastHoldsRotation`, `gcd.go:109-115`; `apl.go:604-607`); a look that takes no action
  schedules the next one a reaction time later (`nextEvaluation = max(now + ReactionTime, NextGCDAt)`,
  `apl.go:594-613`), the reaction drawn uniformly in 150-350 ms per instant (`bm.siml:8`; `gcd.go:133-143`). A swing can
  bring a look earlier (`attack.go:469-471`, `ReactToEvent`, `gcd.go:145-173`); a dot's expiry triggers none (no
  `ReactToEvent` caller in the dot or aura code: the callers are `attack.go`, `health.go`, `rage.go`, `target.go`). Each
  look takes the first action of the priority list that is ready and affordable (`apl.go:617-631`;
  `apl_actions_casting.go:31-33` `CanCastOrQueue` → `spell.go:748-776` with the mana cost).
- So an action that becomes ready (Serpent Sting's dot gone, the HHA category over) waits for the hold in progress, if
  any, to end, else for the next poll. HGA's tempo model (approximation A1) takes the mean of that wait, for an action X:
  `δ_X = b_X × R_X + (1 − b_X) × r_poll` with
  - `b_X = Σ_i f_i h_i` over the GCD actions `i` other than X: their rich-regime frequencies `f_i` at full rate (HHA
    `3 / C0`, Aimed `aimedUse / (6 + 2/hRanged)`, Serpent Sting `1/15`, Sniper `sniperUse / (15 + 4/hRanged)`, Mongoose
    Bite and Strider Kick at their model rates) and their holds `h_i = max(1.5, cast)`: GCD 1500 ms for Summon Hawk,
    Arcane, Serpent Sting, Aimed, Sniper, Mongoose and Strider Kick (`spells_auto_gen.go` rows 1293527, 14287, 13555,
    25295, 20904, 1310786, 14271, 1317257: GCDMs 1500), Aimed's cast `2/hRanged` and Sniper's `4/hRanged`
    (`Core/Model.lua:452-453, 502`); Raptor Strike has no GCD (row 14266) and holds nothing;
  - `R_X = Σ_i f_i h_i² / (2 b_X)`: the mean rest of the hold in progress at an instant that falls inside one (my
    arithmetic, length-biased);
  - `r_poll = E[R²] / (2 E[R]) = ((0.15² + 0.15 × 0.35 + 0.35²) / 3) / 0.5 = 0.1317 s`: the mean rest of a polling
    interval, R uniform in 0.15-0.35 s (my arithmetic). Swings that bring a look earlier are left out (the wait is a
    little too long).
- Serpent Sting (rich regime): `cast serpent_sting if not dot(serpent_sting).is_active` (`turret_hawk.apl.siml:14`); the
  cast rolls the ranged table at the cast (`serpent_sting.go:40` `OutcomeRangedHit`), the dot lands after the travel time
  (`serpent_sting.go:43-49`); travel = distance / missile speed (`wowsims/sim/core/spell.go:1005-1010`) = 12 yd
  (`bm.siml:9`) / 40 yd/s (Serpent Sting `Speed: 40`, `spells_auto_gen.go:10012, 21609`) = 0.3 s; 15 s duration
  (`Core/Model.lua:188-190`); a miss is known at the cast and the next attempt comes at the end of its GCD (1.5 s).
  - `q = missChance(3, p.hit + p.rangedGearHit + p.rangedHit)` (the application rolls the ranged table: 4.4);
  - gap from expiry to the next landed dot `g = δ_S + travel + q / (1 − q) × gcd`, `travel = 0.3`, `gcd = 1.5`;
  - landed applications per second `aL = 1 / (15 + g)`; uptime `U = 15 × aL`; casts per second `aL / (1 − q)`.
  - Example (my arithmetic: hRanged 1.15, aimedUse 0.92, no Sniper, no melee): Aimed `f = 0.1189`, `h = 1.739`; for
    Serpent `b_S = 0.25 + 0.2068 = 0.4567`, `R_S = 0.804`, `δ_S = 0.4567 × 0.804 + 0.5433 × 0.1317 = 0.439 s`;
    `q = 0.08` (no hit at +3): `g = 0.869`, `U = 0.945`, casts `0.0685`/s; `q = 0`: `g = 0.739`, `U = 0.953`.
  - `out.serpent = (5·tick + 0.25·rapShot) / 15 × U × seg.serpent × rcrit × own × rws × stings × coe` (no `shotHitf`: the
    miss is inside `U` through `q`); `hits.ranged.casts = aL × seg.serpent`.
- Starved regime: the share `seg.serpent` from section 7.5 (0 in the deep-starved case); the ticks of a dot still running
  when mana runs out are not counted (fluid approximation A2).
- Rapid Recuperation's mana share uses this `U` (7.3).
- Levelling keeps `CONST.serpentUptime = 0.8`.
- Tests: moves none (levelling 0.8: C.md `serpentUptime_0.97` moves 3, but the value stays in levelling). New:
  `raid tempo: δ = b·R + (1 − b)·0.1317 from the other GCD actions` (mutants: R as half the GCD; the reaction added
  after a GCD); `raid serpent: U = 15 / (15 + δ_S + 0.3 + q/(1 − q) × 1.5)` (mutants: no travel; no miss term);
  `raid serpent: more hit raises U and lowers the casts` (mutant: casts without `1/(1 − q)`); `raid serpent: starved
  share scales damage and applications` (mutant: the share on damage only).

### 6.5 Hawks and the dive

- Rule (wowsims): each Summon Hawk cast dives and (re)summons a hawk for 18 s (1293248: SpellMisc 840689,
  `db2/SpellMisc.csv:29672`, DurationIndex 85 = 18000 ms; `summon_hawk.go:14-15, 140-147`), two hawks
  (`summon_hawk.go:73`, effect 3), round robin replacing the one with the least time left; the APL casts Summon Hawk,
  Summon Hawk, Arcane Shot in sequence (`turret_hawk.apl.siml:15-16`), each on the shared 6 s category 1173
  (SpellCooldowns 54834 / 99423, `db2/SpellCooldowns.csv:1598, 4032`, CategoryRecoveryTime 6000; SpellCategories 74283 /
  183670, `db2_R4-ability-formulas/f/SpellCategories.csv:3046, 9855`, Category 1173). Each element becomes ready 6 s after
  the previous one and then waits as 6.4 says.
- HGA formula (rich regime): each element ready 6 s after the previous one (Arcane's own 6 − 0.3 × Improved Arcane Shot,
  W1D 6) and cast `δ_H` later, `δ_H` from 6.4 with Serpent Sting, Aimed and the other GCD actions as the holds; a cycle of
  three elements lasts `C = C0 + 3·δ_H`, `C0 = 18 − 0.3 × Improved Arcane Shot`; hawk casts per second `rH = (2 / C) × seg.hha`,
  Arcane `(1 / C) × seg.hha`, the dive at `rH`; each hawk is re-summoned once a cycle and lives 18 s, so
  `hawkUp = min(1, 18 / C)` at the full share and `min(1, 9 × rH)` at a share below it (my arithmetic);
  `out.hawks = 2 × hawkUp × …` (536); `out.dive = (diveBase + 0.05 rapShot) × rH × …` (519), `diveBase` the rank's base
  with Unleashed Fury's 3 and Ferocity's 2 a rank (W1D section 5, step W1).
- Example (my arithmetic, the point of 6.4): `b_H = 0.1 + 0.2068 = 0.3067`, `R_H = 0.831`, `δ_H = 0.346 s`,
  `C = 19.04 s`, `hawkUp = 0.945`, `rH = 0.1051`/s (full rate 0.1111), Arcane 0.0525/s.
- Levelling keeps `CONST.hawkUptime = 0.9` (no source in the repo for 0.9, C.md; out of scope), Arcane `1 / C0` and the
  dive `2 / C0` (W1D 6, step W2).
- Tests: new `raid hawks: uptime 18 / C at the full share, 9 × rH below it` (mutants: 0.9; uptime 1 at the
  full share); `raid dive and Arcane rates follow the tempo and the share` (mutant: `2/18` fixed); `raid HHA: C = 18 − 0.3
  × rank + 3 × δ_H` (mutant: the talent left out of `C`, W1D 6).

### 6.6 Rapid Killing

- Rule: the buff comes on a killing blow or when the enemy dies with the hunter's Serpent Sting on it
  (`talents_marksmanship.go:85-93`): once, at the fight's end, on a single target. Raid: no Aimed bonus; its cooldown
  reduction of Rapid Fire stays (6.3). Levelling: `killInterval` as now.
- Tests: new `raid: Rapid Killing adds nothing to Aimed` (mutant: killInterval used).

### 6.7 What the fight returns

- `Model.Total(p)` (raid) = `Σ_seg w_seg × sum(out_seg) / 180`, `w_seg = ∫_seg w(t) dt`.
- `Model.Parts(p)` (raid) = the weighted mean of each part (for `/hga weights`' shares).
- `Model.LandedHits(p)` (raid) = the weighted mean of each hand's `swings`, `specials`, `casts` (speeds are the point's).
- `Model.Fight(p)` (new, for `/hga weights` and `/hga dump`): the segments, the regime times, the consumable times, the
  Bestial Wrath, Rapid Fire and Frenzy Potion windows, `δ_S`, `δ_H`, `U`, the mean hawk uptime, the JoW income.

### 6.8 Use buffs in the fight

- `Model.ApplyStats(q, stats, T)`: the one map from item stat keys to model inputs, used by the Use buffs, the Frenzy
  Potion and every `Model.Weights` mutation (so they agree): `AP` → rap, map; `RAP` → rap; `MAP`/`STR` → map; `AGI`:
  `e = amount × agiMult` (× `p.statMult.AGI` with O8) → rap `2e`, map `e`, crit and meleeCrit `cpa × e`, agi `e`;
  `CRIT` → crit, meleeCrit; `HASTE` / `ATTACK_SPEED` / `HASTE_RATING` / `MELEE_HASTE` / `RANGED_HASTE` → one more
  source of the input (`Core/Model.lua:868-870`; `ATTACK_SPEED`, `HASTE_RATING`: W1D 7.3, step W5); `INT` → Careful Aim `0.20 × rank` to rap and map (both modes) and, in raid, the ceiling
  `manaMax` 15 a point (7.6); `SPI` (raid) → spirit, regenRest `1/8`, regenCast `share/8` (7.3); `MP5` (raid) → both
  regens `1/5`; `MANA` (raid) → manaMax; `AP_VS_<TYPE>` → `apVsTarget` × the type's share (4.5); `HIT`, `SPELL_HIT`,
  `EXPERTISE` are not applied here (priced with their caps in Score, below).
- The pet's attack power does not take a Use buff: the pet keeps the attack power it had at the summon
  (`wowsims/sim/hunter/pets.go:160-171` `keepSummonStats`, EV-0072). `partsAndHits` reads the pet's AP from the point's
  `rap` / `map` before the segment's Use stats (an input `petRap`, `petMap` copied from `p` before `ApplyStats`). The
  hawks follow the owner (`summon_hawk.go:79-89`, `IsDynamic`). Levelling (O6, the user's answer: the wowsims rule in
  both modes) keeps today's linear pricing `W × amount × uptime`, with the attack power keys at weights taken with the
  pet's attack power held: `W.AP_USE`, `W.RAP_USE`, `W.MAP_USE` = the derivatives of `Model.Total` by `rap` / `map`
  with `petRap` / `petMap` fixed at the point's (`Model.Weights`, levelling); a Use buff's `AGI` and `STR` take
  `Model.ApplyStats` with the pet's attack power held in the same way. Test: `levelling use: a Use buff's AP is priced
  without the pet's share, W.AP_USE < W.AP with a pet out` (mutant: `W.AP`).
- Score (`Core/Score.lua:709-740`): in raid mode (`ctx.mode == "raid"`)
  `v = v + ctx.useGain(set)` where `ctx.useGain(set) = (Model.Total(model ⊕ { uses = the set's Use buffs }) − total) / unitDps`
  (Advisor, cached by the spell ids of the set's uses in their firing order, `Score.SetUses`: step 11, 19.1); `HIT` and
  `EXPERTISE` of a Use buff go through `hitValue` /
  `expertiseValue` as today with `uptime = ctx.useUptime(set)[spell]`, the buff's weighted share of the fight (the same
  windows). Raid mode without `ctx.useGain` is an error. Levelling: today's loop.
- `tools/gen_use_data.py:61-62` `DAMAGE_KEYS` gains `SPI`, `MP5`, `MANA` (raid gives them a damage weight; levelling's
  weight 0 prices such a buff at 0 there) and the eight `AP_VS_<TYPE>` in place of `AP_CREATURE`; `Game/UseData.lua` is
  regenerated (Golden Banana 270226's `SPI 16` then counts in raid). A Use spell that restores mana (an ENERGIZE effect)
  is no stat aura and stays unpriced, as today (approximation A10).
- Tooltip (`Game/Advisor.lua:679-688`), raid: `HGA: «Использование» учтено как оценка: %g сек. раз в %s — в бою 180 с %d раз(а), %.0f%% времени, с 5-й секунды вместе с Rapid Fire и Bestial Wrath`.
- Tests: moves none in levelling (C.md `UseUptime_180s`: 6 tests pin duration / cooldown, and that stays in levelling).
  New: `raid use: Earthstrike 20 s / 120 s fires at 5 and 125` (mutant: duration / cooldown); `raid use: two burst
  trinkets do not overlap, the second starts when the first ends` (mutant: no lock); `raid use: an AP buff inside Rapid
  Fire is worth more than outside (faster shots)` (mutant: windows averaged); `raid fight: the pet inside Rapid Fire and
  Bestial Wrath deals the product of both` (mutant: the sum); `raid use: the pet's AP ignores the buff, the hawks' takes
  it` (mutant: the pet takes it); `raid use: a hit buff priced with the cap at the fight's uptime` (mutant: duration /
  cooldown); `gen_use_data: a buff of SPI alone is written` (mutant: SPI missing from DAMAGE_KEYS).

### 6.9 Weights through the fight

- `Model.Weights` (`Core/Model.lua:791-937`) keeps its finite differences of `Model.Total`; in raid mode each derivative
  re-runs the whole fight (segments, regimes, consumable times move with the stat). The time weight w(t) (6.2) makes the
  events near the end continuous. The fluid timeline (7.6) is piecewise linear and continuous in the inputs except two
  discrete switches, both real wowsims behaviour: a consumable that fits or not (pool vs its maximum, 7.4) and the second
  Bestial Wrath at 125 s or later (7.6); a step that crosses one moves the derivative. The steps stay as today (10 RAP,
  0.5% crit, …); the mana stats take step 10 (Int, MP5, Spirit) and 100 (mana). Every mutation goes through
  `Model.ApplyStats` (4.2, 6.8). Built otherwise for the two consumables (25.1): each derivative holds the consumables'
  events of the point it is taken at, and a set's own change of an event is priced at the set level (`ctx.eventGain`).
- New raid weights: `W.INT` = derivative of `ApplyStats(q, { INT = d })` (mana pool and Careful Aim: 20% of Intellect a
  rank as attack power and ranged attack power, `wowsims/sim/hunter/talents_marksmanship.go:73-83`, DB2 auras 580 + 598,
  `docs/research/R3-core-formulas.md` §4) — in levelling it stays `0.20 × carefulAim × W.AP` (`Core/Model.lua:876-877`);
  `W.MP5`, `W.SPI`, `W.MANA` likewise (levelling 0, `Core/Model.lua:932-935`). With JoW (O7) the shots' hit and ranged
  haste raise the mana income too, which the fight's derivatives hold.

## 7. Mana in raid mode

### 7.1 The pool

- `p.manaMax` = the live `UnitPowerMax` (answer 2: the live sheet). Its Intellect slope: 15 mana a point
  (`wowsims/sim/core/mana.go:59-71` `AddStatDependency(Intellect, Mana, 15)` after `AddStat(Mana, 20 − 15 × 20)`; Forever UI
  `UI/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrameConstants.lua:25-26` `INTELLECT_BREAK = 20`,
  `MANA_PER_INTELLECT = 15`, used by the Intellect tooltip, `Camelot/PaperDollFrameStats.lua:282-283`). The fight starts at full mana
  (prepull spends are refilled before the pull: Hunter's Mark at −22 s costs 60, `pull.apl.siml:8`).

### 7.2 Spell costs (DB2 `db2_R4-ability-formulas/f/SpellPower.csv`, build 70888, and the server hotfix)

| Spell | Cost | Source |
|---|---|---|
| Serpent Sting VIII 13555 / IX 25295 | 230 / 250 | SpellPower 179175 (line 1334) / 188672 (2366); IX when `p.serpentTick == 135` (book known) |
| Aimed Shot 20904 | 310 | SpellPower 184990 (2014) |
| Arcane Shot 14287, Summon Hawk 1293527 | 11% of base mana = 189.2 | server hotfix of 10-11 Nov (`docs/research/R4-ability-formulas.md:105, 273`); wowsims `spells_auto_gen.go:10733-10737, 35894-35901` CostPct 11; DB2 70888 still has 190 flat (SpellPower 179523, line 1385; 313592, line 3328) |
| Hunter's Mark 14325 | 60 | SpellPower 179455 (1375); recast at 98 s (prepull −22 s + 120 s, SpellMisc 324400, `db2/SpellMisc.csv:6727`, DurationIndex 4 = 120000 ms; `turret_hawk.apl.siml:13`) |
| Rapid Fire 3045 | 100 | SpellPower 169901 (204) |
| Bestial Wrath 19574 | 12% of base mana = 206.4 | SpellPower 184568 (1958) |
| Sniper Shot 1310786 | 365 | SpellPower 314529 (3389) |
| Raptor Strike 14266 / Mongoose Bite 14271 / Strider Kick 1317257 | 100 / 65 / 5.81% base = 99.9 | SpellPower 179931 (1443) / 178962 (1312) / 314743 (3415) |

Base mana at 60 = 1720 (PlayerExpectedStat row 306; wowsims `base_stats_auto_gen.go:62-66`). Percent costs are of base
mana (`CONST.raid.baseMana = 1720`).

### 7.3 Regeneration in combat

- Rule (wowsims): the five-second rule starts at every mana spend (`mana.go:403-411`:
  `FiveSecondRuleRefreshTime = max(now + 5 s, hardcast end)`); inside it the regen is MP5 + Spirit regen × the casting
  share (capped at 1), outside it MP5 + the whole Spirit regen (`mana.go:167-196`); the hunter's Spirit regen is
  `6.25 + Spirit/8` mana/s (`mana.go:77-78`, no EV file behind the constants; Classic emulators give `7.5 + Spirit/10`,
  R3 §5 — approximation A3). Bestial Discipline adds its effect 2 (A_MOD_MANA_REGEN_INTERRUPT) to the casting share
  (`talents_beast_mastery.go:174-182`): DB2 19590 SpellEffect 1230289 (EffectIndex 1) aura 134 bp 50 at the top rank, 25% a rank
  (R3 §5, curve 82816). Rapid Recuperation's buff adds its share while up (`talents_marksmanship.go:183-231`).
  Resourcefulness: a melee or ranged ability crit (SpellAuraOptions 242512 ProcTypeMask 0x110) triggers 1242688 with 50%
  a rank, 30 s (SpellMisc DurationIndex 9), whose aura 134 bp 50 adds 50% to the casting share
  (`Core/Model.lua:214-219, 939-946`).
- HGA inputs: `p.regenRest`, `p.regenCast` = `GetManaRegen()` (the live sheet: MP5 from gear and buffs, Spirit, Bestial
  Discipline). The model adds what the reading cannot hold, the shares of buffs that come in combat:
  `regenCast' = p.regenCast + min(1 − 0.25·BD, 0.25·RR·U + 0.5·resUp) × (6.25 + p.spirit/8)`
  (the shares of `Model.SecondaryRates`, `Core/Model.lua:950-952`, with the raid `U` of 6.4). `resUp` is derived from the
  segment's ability crits in raid, where it carries damage: `resUp = 1 − Π_i (1 − 0.5·Res·c_i)^(30·f_i)` over the
  ability hits that can crit (Aimed, Multi, Arcane, Sniper, the dive, Raptor, Mongoose, Strider Kick), `f_i` landed per
  second, `c_i` their crit (`critR`, `critM`): the chance that one of the last 30 s of ability hits triggered the buff
  (my arithmetic, crits as independent events; the same form as Frenzy's uptime, `Core/Model.lua:574-575`). Levelling
  keeps `CONST.resourcefulnessUptime` 0.4 in the tie-break (W1 melee-sv-12, by design there). Slopes for the weights:
  `d regenRest / d Spirit = 1/8`, `d regenCast / d Spirit = share/8` with `share = min(1, 0.25·BD + …)`;
  `d / d MP5 = 1/5` for both.
- `/hga dump` writes `GetManaRegen()` and `GetManaRegenFromSpirit()` (`PlayerScriptDocumentation.lua:582`) with Spirit so
  the 1/8 slope can be checked in game.

### 7.4 In-fight consumables (O2 = (a), always on)

- wowsims' preset (`defaults.siml:21, 30-31`): a Demonic Rune (conjured), a Major Mana Potion (resource pot) and a Major
  Frenzy Potion (offensive pot). Each is a major cooldown (`sim/common/shared/consumable_potion.go:255-281`; the potions
  while the consumes pick them, `consumes.go:89-94` `IsPickedPotion`, the rune as the spec's conjured item). A mana gain
  alone fires only when its whole maximum fits under the maximum after 5 s of casting regen (`consumable_potion.go:257-266`
  ShouldActivate, `382-388` fits: `max − current − 5 × ManaRegenPerSecondWhileCasting ≥ the effect's maximum`); the Frenzy
  Potion has no such condition and fires when ready.
- DB2: Major Mana Potion 13444 → ItemEffect 99861 (`db2_R5-weapons-gear/ItemEffect.csv:1057`; ItemXItemEffect 115591):
  spell 17531, SpellCategoryID 4, CategoryCoolDownMSec 120000; SpellEffect 695996 (`db2/SpellEffect.csv:12132`)
  ENERGIZE 1800, Variance 0.5 → 1350-2250, mean 1800. Demonic Rune 12662 → ItemEffect 99229 (line 861; ItemXItemEffect
  124919): spell 16666, category 1153, CategoryCoolDownMSec 120000; SpellEffect 694074 (line 10665) ENERGIZE 1200,
  Variance 0.5 → 900-1500, mean 1200 (bounds: wowsims `effect.go:125-140`, ±Variance/2). Major Frenzy Potion: ItemEffect
  214812 (line 4224) states no cooldown and no category (−1, 0), so the spell row's apply (`consumable_potion.go:283-300`
  `consumableCooldownsOf`): 1251940 Category 4, CategoryCooldownMs 120000 (`spells_auto_gen.go:34318`; DB2 SpellCategories
  176135, SpellCooldowns 95731), 30 s, +80 AP and +80 RAP (auras 99 and 124, DB2 SpellEffect 1256847, 1356023). So the
  mana potion and the Frenzy Potion share potion category 4 (120 s); the rune's 1153 is apart.
- The fight in wowsims (my reading): at 5 s the Frenzy Potion is ready and fires with the other cooldowns; the mana
  potion does not fit then (the pool is down by the first 5 s of casts only, far less than 2250 + 5 × regen), so the shared
  category locks both until 125 s. At 125 s both are ready at once; the stable sort keeps the resource pot ahead of the
  offensive pot (registered in `SelectedConsumableIDs` order, resource pot first, `consumes.go:105-107`; default priority
  for both, `major_cooldown.go:12-13, 415-420`), so the mana potion fires if it fits at that look and the Frenzy Potion
  otherwise (its second window `[125, 155)`); whichever fires locks the other past 185 s. The rune fires whenever it fits,
  then every 120 s.
- O2 = (a), the user's answer (2026-11-17), always on, with no setting and no command: as wowsims' preset, the Frenzy
  Potion at 5 s, the mana potion only at 125 s and only if it fits then, else a second Frenzy Potion; the rune by its fit.
  The model holds one consumables table of these three; no input switches it off (no `p.raidConsumables`, no
  `/hga potions`).
- The Frenzy Potion's +80 AP / RAP goes through `Model.ApplyStats` as a Use buff (6.8): the hawks take it, the pet does
  not (EV-0072). Explosives of the preset (Goblin Sapper Charge, EZ-Thro Dynamite II, `defaults.siml:22-24`) deal damage
  that no gear stat changes and go off inside the GCD (`major_cooldown.go:385-397`): left out, they move no item's value.

### 7.5 Regimes and what drops when mana runs out

- wowsims' APL `turret_hawk` has no mana condition (`turret_hawk.apl.siml:11-20`); a look takes the first action of the
  priority list that is ready and affordable (`apl.go:617-631`; `apl_actions_casting.go:31-33` → `spell.go:748-776`,
  the mana cost last; cooldowns `major_cooldown.go:110-133`). The priority is: cooldowns, Hunter's Mark (60) if missing,
  Serpent Sting (230/250) if its dot is down, the HHA sequence (189.2 each), Aimed Shot (310).
- Consequence (my reading of that mechanism): with mana rising slowly from empty, the first action that is ready when the
  mana reaches its cost goes, so the cheapest ready action goes first whatever its place in the list; the order of the
  list decides only between two actions both ready and both affordable at one look, which the starved regime does not
  produce. HGA's casts beyond turret_hawk follow the same rule by cost: Sniper Shot (365, in wowsims' `turret.apl.siml:16,
  29`, the MM APL) and the Survival melee abilities (Mongoose 65, Wing Clip 80, Strider Kick 99.9, Raptor 100, Immolation Trap 245: 15.5; in wowsims' weave APLs,
  `default.apl.siml:20-22`, `clean_weave.apl.siml:8-10`, before Serpent Sting): HGA models no APL for those builds, so
  the rule by cost is its approximation (A2) of "first ready and affordable".
- Fluid model (HGA): two regimes.
  - Rich: every cast at its rich rate (`seg.serpent = seg.aimed = seg.hha = 1`, the tempo of 6.4-6.5); spend
    `S = Σ casts × cost` from `partsAndHits`' `casts` (6.1); the hunter casts more often than every 5 s, so the regen is
    `regenCast'` (approximation A4); net drain `D = S − regenCast' − J`, `J` the JoW income of the segment (O7; 0 without
    it).
  - Starved (mana at 0): Auto Shots keep landing, so the JoW part `J_a = 29.5 × autoLanded` flows all the time (O7);
    a cast also returns its own JoW, so an HHA element costs `c_eff = c − 29.5 × (2 + land)/3` with JoW (the two dives
    always land, Arcane with `land = 1 − q`), `c = 0.11 × 1720` without. The income of a cycle in which the hunter casts
    one HHA element as soon as it can pay it: rates `g1 = regenCast' + J_a` for 5 s after the cast and
    `g2 = regenRest + J_a` after; if `c_eff ≤ 5·g1`, `T = c_eff / g1`, else `T = 5 + (c_eff − 5·g1) / g2`; income
    `I = c_eff / T` (the element itself bought). The income buys casts cheapest ready first: the Survival melee abilities
    by cost, the HHA elements to their rich rate (`S_hha = (3 / C) × c_eff`, 6.5; without Summon Hawk, Arcane Shot alone
    at the same cost and today's `arcRate`), the second Bestial Wrath once (206.4) when its turn comes (7.6), then Serpent
    Sting to its rich rate, then Aimed Shot, then Sniper Shot; each share is `min(1, what is left / its full spend)`. If
    the income buys every cast at its rich rate, the rest raises `m`: the regime is rich (`D < 0`).
  - Example without JoW (my arithmetic, rounded; the point of 6.4, `regenCast' = 7.5`, `regenRest = 15` mana/s):
    `T = 5 + (189.2 − 37.5)/15 = 15.1 s`, `I = 12.5` mana/s, `seg.hha = 12.5 / 29.8 = 0.42`, Serpent and Aimed 0.
    Rich spend: HHA `3/19.04 × 189.2 = 29.8` + Serpent `0.0685 × 230 = 15.8` + Aimed `0.1189 × 310 = 36.9` = 82.4 mana/s,
    so `D = 74.9`.
  - Example with JoW (my arithmetic, same point, bow speed 3.0, `q = 0.08`): landed hunter hits 0.678/s (Auto 0.353,
    Aimed 0.109, Arcane 0.048, Serpent's applications 0.063, dives 0.105) → `J = 20.0` mana/s, `D = 54.9`. Starved:
    `J_a = 10.4`, `c_eff = 160.5`, `g1 = 17.9`, `g2 = 25.4`, `T = 7.79 s`, 0.128 elements/s against 0.158 at the rich
    rate: `seg.hha = 0.81`.

### 7.6 The timeline

`fight(p)` walks the time from 0 to 185 s with the mana `m` (start `p.manaMax`), the ceiling `manaMax(t)` (`p.manaMax`
plus 15 × the Intellect of the Use buffs up, plus their `MANA`), the regime, and the next times of: the fixed boundaries
(5, the ends of the Rapid Fire / Bestial Wrath / Use / Frenzy Potion windows, 98 Hunter's Mark, 125 the second Bestial
Wrath and the potion category ready, 175, 185), the out-of-mana time (rich with `D > 0`: `t + m / D`), the rune's fit
time (rich: when `manaMax(t) − m(t) = 1500 + 5·regenCast'`; starved: at once if `manaMax(t) ≥ 1500 + 5·regenCast'`; never
otherwise) and the consumables' cooldowns (120 s each). Events at one instant apply in this order: consumables, then the
cooldowns (an MCD that cannot be paid is skipped, `major_cooldown.go:110-112`, so a potion at 125 s pays the Bestial Wrath
of that instant: my reading).
1. At 5 s: Rapid Fire (−100) and, with the talent and a pet out, Bestial Wrath (−206.4) start; the Use buffs start (no
   cost); the Frenzy Potion starts (O2 = (a)).
2. A one-off cost in the starved regime (Hunter's Mark 60 at 98 s) is a debt: the income repays it before any cast
   (the cheapest ready action, 7.5).
3. Out of mana (`m = 0` in rich): the regime becomes starved; `m` stays 0.
4. The consumables (O2 = (a), always): the rune at its fit time, `m = m + 1200`, next 120 s later; the mana potion at
   125 s if `manaMax(125) − m(125) ≥ 2250 + 5·regenCast'`, `m = m + 1800`, else the second Frenzy Potion. An income event
   makes the regime rich.
5. At 125 s the second Bestial Wrath fires if the regime is rich and `m ≥ 206.4`; in the starved regime it is bought from
   the income after the HHA elements at their rich rate (7.5); if neither happens before 185 s, there is none.
6. A rich segment with `D ≤ 0` keeps `m` at `manaMax(t)` (casts fully paid).
7. A Use buff's Intellect raises the ceiling for its window and leaves `m` as it is (the current mana moves only by gains
   and spends, a gain capped at the maximum: `mana.go:100-125`); at the window's end `m = min(m, manaMax(t))`, since the
   next regen gain is capped at the lower maximum (`mana.go:116`; my reading).
Each stretch with one state becomes a segment (6.1). The ticks of a dot or a hawk still up when the regime changes are not
carried over (fluid: A2).

### 7.7 The value of mana stats

- With the fluid timeline (my arithmetic, for verification): one more point of mana in the pool moves the out-of-mana
  time by `1/D`, the fight's damage by `(DPS_rich − DPS_starved) / D` and `Model.Total` (damage / 180, 6.7) by
  `(DPS_rich − DPS_starved) / (180 · D)`; so `W.MANA × unitDps = (DPS_rich − DPS_starved) / (180 · D)` while that time
  lies in the weight-1 part and no other event moves. MP5 lowers `D` by 1/5 and raises the starved income; Spirit acts
  mostly on the starved income (`regenRest`, out of the five-second rule) and on `D` by `share/8`; Int = 15 mana +
  Careful Aim.
- `Model.Weights` gets these by finite differences (6.9); the closed forms above are test oracles, not code.

### 7.8 What drops vs what continues

Auto Shot, the pet, the hawks already summoned and Rapid Fire / Bestial Wrath / Use / Frenzy Potion windows already
running cost no mana and continue; Serpent Sting, Aimed Shot and the second Bestial Wrath drop when the income cannot buy
them (7.5).

### 7.9 Score and the tie-break in raid mode

- `Score.Better` (`Core/Score.lua:758-762`) is unchanged: damage decides.
- `Score.Secondary` (`Core/Score.lua:808-827`): in raid mode `manaPct = 0` (mana is in the damage, an item's Int / MP5 /
  Spirit / mana go through `W` in `ItemValue`'s stat loop, `Core/Score.lua:387-393`), the health part stays, and the armor
  reduction is against the boss's level 63 (`armorReduction(armor, 63)`: `spell_resistances.go:147`,
  `defaults.siml:64`). `ctx.raid = true` (A.State) selects it. Levelling: today's tie-break unchanged (MP5 = 12 mana,
  Spirit = 1 + 6 × min(1, s), `Core/Model.lua:939-960`).
- Tooltip and banner (`Game/Advisor.lua:446-474`): raid `secText` shows health only.

### 7.10 Tests (section 7)

- Moves: none in levelling. New (raid, at 60; each with its mutant): `raid mana: never out of mana when regen ≥ spend`
  (mutant: OOM anyway); `raid mana: OOM time = pool / D in a rich fight without events` (mutant: pool / S, regen left
  out); `raid mana: starved income by the FSR cycle, both branches (c ≤ 5·g1 and above)` (mutant: income = regenCast);
  `raid mana: cheapest ready first — HHA, the second BW, Serpent, Aimed` (mutant: Serpent first); `raid mana: the
  second Bestial Wrath waits for the income when starved at 125 s` (mutant: casts at 125); `raid mana: JoW lowers D by
  29.5 a landed hit and enters the starved cycle` (O7 = (a); mutants: J left out of the starved cycle; the cast's own
  JoW left out); `raid Resourcefulness: uptime from the fight's ability crits` (mutant: 0.4 in raid); `raid consumables
  (O2 = (a)): Frenzy Potion at 5 s; the mana potion only at 125 s and only if it fits, else a second Frenzy Potion`
  (mutants: the mana potion at its fit time; no shared category); `raid consumables: the rune at room = 1500 +
  5·regenCast', adds 1200, next 120 s later` (mutant: the fit without `5·regenCast'`); `raid consumables: always on, no
  input switches them` (mutant: a `raidConsumables` flag read from the point); `raid use: an Int buff raises the ceiling
  in its window, m is clamped at its end` (mutants: m raised
  with the ceiling; no clamp); `raid weights: W.MANA × unitDps = (DPS_rich − DPS_starved) / (180 · D)` (oracle of 7.7;
  mutant: the fight's damage not divided by 180); `raid weights: W.INT = 15 W.MANA + Careful Aim's AP` (mutant: no
  Careful Aim); `raid weights: W.SPI and W.MP5 > 0, levelling 0` (mutant: 0 in raid); `raid secondary: no mana part,
  armor vs 63` (mutant: the player's level); `levelling secondary unchanged` (mutant: the raid branch in levelling).

## 8. UI

- `/hga weights` (`Game/Commands.lua:19-126`) adds, first: raid, from step 11 (the fight) `режим: рейд (ур. 60) — босс +3 (дракон), броня 976, кап меткости %.1f%%, бой 180 ± 5 с, кулдауны с 5-й секунды, пет сзади`
  (the cap of 14.5 kept); until step 11 (step 10, the averaged raid target) `режим: рейд (ур. 60) — босс +3 (дракон), броня 976%s, кап меткости %.1f%%, кулдауны в среднем, пет сзади`,
  `%s` the armor the hunter's own attacks face with worn armor penetration (5.1) (group 0, 18.9);
  levelling `режим: прокачка (ур. %d) — цель твоего уровня, кап меткости %.1f%%, кулдауны в среднем, Serpent Sting 80%%, пет держит цель`
  (14.5).
  Raid then: `мана: запас %d, реген %.1f/с при кастах, %.1f/с без кастов 5 с%s; мана кончается на %.0f с%s; без маны — только ястребы и Arcane (%.0f%% темпа), без Serpent Sting и Aimed Shot`
  (the first `%s` = `, Judgement of Wisdom +%.1f/с` (O7 = (a)); the second = `; зелье маны на %s с, руна на %s с,
  Frenzy Potion %s` (O2 = (a)); `мана не кончается` when it does not);
  `Serpent Sting висит %.0f%% боя, ястребы %.0f%%, Rapid Fire %s, Bestial Wrath %s` (window lists, e.g. `5–23 с, 140–158 с`
  or `5–23 с; второго не будет — нет маны`). The melee line of 15.6. The weights line adds `Инт %s, MP5 %s, Дух %s, мана %s`
  in raid; the tie-break line (`Game/Commands.lua:120-121`) in raid reads
  `здоровье и броня — только при равном уроне; мана считается в уроне`. The cap line's hit (`Game/Commands.lua:65-70`)
  adds the worn ranged gear hit (4.7.1).
- The cap: `Game/Commands.lua`'s `effectiveCap` and the help's cap and target lines go with `/hga cap` and `/hga target`
  (14.1); `/hga weights` prints `ctx.hitCap` = `Model.HitCap(model.mobDiff)` (14.2: 5% below 60, 8% at 60).
- `/hga dump` (`Game/Commands.lua:161-193`) adds `mode`, `survival`, `fight` (`Model.Fight`: segments with times, regime,
  shares, windows, out-of-mana time, consumable times, `δ_S`, `δ_H`, `U`, hawk uptime, JoW income),
  `manaRegen = { GetManaRegen() }`, `manaRegenFromSpirit = { GetManaRegenFromSpirit() }`,
  `hitModifiers = { melee = GetHitModifier(), ranged = GetRangedHitModifier(), spell = GetSpellHitModifier() }`,
  `spellCrit`, `apVsTarget`, `rangedGearHit` and `procOutcome`.
- Tooltip lines: 4.5 (Beastslaying, AP vs type), 4.6 (Tablet, unlinked proc), 6.8 (Use), 7.9 (secondary).
- Tests: moves `test_game / /hga weights prints the hit Score meets the cap with, …` and the other `/hga weights` /
  dump cases only by the added lines (their asserted lines stay; C.md lists them under `DEFAULTS_mobDiff_3` and
  `DEFAULTS_meleeFrac_0`). New (each with its mutant): `/hga weights in raid names the mode, the mana and the windows`
  (mutant: the mode line dropped); `/hga weights in levelling names the mode` (mutant: the raid text);
  `/hga dump has mode, fight, manaRegen, hitModifiers` (mutant: a field dropped); `/hga weights at level 60 shows the 8%
  cap, at 59 the 5%` (14.7; mutant: the cap from a stored setting).

## 9. Score / Advisor context summary

`A.State` (`Game/Advisor.lua:82-172`) builds:
- `ctx.mode = model.mode`; `ctx.raid = model.mode == "raid"`;
- `ctx.hitCap = Model.HitCap(model.mobDiff)` (14.2; today `s.hitCapOverride or Model.HitCap(s.mobDiff)`, HEAD
  `dfa7300` `Game/Advisor.lua:144`);
- `ctx.expertiseCap = Model.MobAvoid(model.mobDiff)`; `ctx.parryCap` (4.3);
- `ctx.procOutcome = Model.ProcOutcomes(model)` (4.6.4);
- raid: `ctx.useGain`, `ctx.useUptime` (6.8);
- `pools.level` = 63 in raid (7.9);
- removed: `ctx.meleeFrac`, `ctx.meleeSwingMult` (4.5); `ctx.threshold`, `ctx.procsPerMinute` (14.3, 14.4).
`weaponModelFor` (lines 34-54) is unchanged in shape: in raid mode its `Model.TotalAndHits` runs the fight; for the
Survival branch every set's run holds the weave of that set's weapons (section 15).
`Game/Commands.lua`'s `effectiveCap` is removed (section 14).

## 10. Tests that move, by change

| Change | Tests that move | Count source |
|---|---|---|
| melee for Survival only | the 15 test_game cases of 3.4 | measured on a copy with the rule: 314 passed, 15 failed |
| raid mobDiff 3 | none (fixtures are levelling); a level-60 test_game env would move the 5 of `DEFAULTS_mobDiff_3` | C.md: 5 |
| Rapid Fire / Bestial Wrath / Use / Serpent / Rapid Killing / hawks in raid | none (levelling keeps the averages) | C.md: 13 / 1 / 6 / 3 / 1 / 1 would move only if levelling changed |
| petTanks 0 | none in levelling; the 2 of `petTanks_0` stay | C.md: 2 |
| AP_CREATURE → AP_VS_* and `p.apVsTarget` | `tests/test_parse.lua:23`, `tests/test_score.lua:599-601`, `tests/test_game.lua:1583, 3097` | key rename (C.md: the share pins none) |
| Beastslaying per wowsims, MeleeSwingMult removed | 4.5 list | key and function removal |
| Tablet per hand, equip triggers, dive, DefenseType, own multipliers | 4.6 lists; the proc fixtures of 4.6.3 | measured in the step |
| crit suppression, single-roll table, parry, W.AGI through ApplyStats | 4.2, 4.3 candidates | measured in the step |
| scopes 2523 / 8057 as RANGED_HIT | none (no fixture parses a scope line as HIT: checked in the step) | — |
| settings removed (A1) | 14.7 | measured on a copy of HEAD `dfa7300` (the runs of 14.7) |
| Survival weave (A2) | 15.9 | measured likewise (15.9) |
| unarmed main hand 1.0 s (A3) | 16.3 | measured likewise |
| W1 dive flats (A4), W2 Improved Arcane Shot with hawks (A5) | W1D 5, 6: 1 and 0 | measured likewise |
| DoT procs | 17: none measured, two predicted | by reading |

A pinned number that moves is re-derived by hand from the formula of this document, and the test comment names the rule
that moved it; it is never copied from the new code's output.

## 11. Approximations (stated, not the user's call)

- A1 The cast tempo (6.4-6.5): the mean wait `δ = b·R + (1 − b)·r_poll`, with the other actions' holds taken at their
  rich-regime frequencies and independent phases, and the looks that a swing brings earlier left out: an estimate of
  wowsims' scheduling, not its output. It sets Serpent Sting's uptime and the HHA tempo (hawk uptime, dive and Arcane).
- A2 Fluid regimes: casts as rates; the ticks and hawks running at a regime change are not carried over; the starved
  regime buys casts by cost (wowsims' "first ready and affordable" with mana rising from 0), also for the Sniper Shot and
  melee abilities of builds turret_hawk does not cover.
- A3 Spirit regen `6.25 + Spirit/8` mana/s from wowsims `mana.go:77-78` without an EV file; the model point uses the live
  `GetManaRegen()`, the constant sets only the Spirit slope.
- A4 Rich regime always inside the five-second rule; starved income from a cycle of one HHA element's cost.
- A5 Use buffs that become ready together fire in wowsims' registration order (6.3), at a later tie too, where wowsims'
  list holds the order of its re-sorts by ready time (no pair of `Game/UseData.lua` ties again).
- A6 Proc outcome, Use gain, weapon gain and the change of the fight's events (25.1) each at the worn point (cross terms
  with the set's other stats left out).
- A7 The fight weight w(t) gives E[damage] / E[length], not the mean of per-fight DPS.
- A8 Levelling: no block on the tanking pet's hits from the front (no creature block value in the sources; wowsims
  `target.go:575`, `spell_outcome.go:895-900`).
- A9 Below 60 the wowsims formulas run at the lower level by the level difference and skill gap (R-0032 defines the
  model for level 60 against 58-63).
- A10 Use spells that restore mana are not modelled (no stat aura for `tools/gen_use_data.py`).
- A11 Proc rates in the order of 18.6 (`MEASURED_PPM`, wowsims' PPM and ProcChancePct override rows, the DB2's PPM or a
  column chance from 1 to 99, wowsims' ProcChanceAlways auras at 100 a hit (25.3), else none; ICD as a dead time) without
  wowsims' other override fields and its effect-stated chances.
- A12 Aimed Shot and Sniper Shot keep HGA's use shares (`Core/Model.lua:197-205`) in the rich regime.
- A13 (dropped: O8 = (a) applies the live sheet's stat multipliers, 4.8.)
- A14 An unlinked proc: its table by the school its tooltip names, crit allowed, its rate by 18.6 (`MEASURED_PPM`, else
  none).
- A15 Resourcefulness' raid uptime treats the ability crits as independent events.
- A16 The starved regime (step 12, section 20): each cast group at its share of its rich rate; the Survival weave's cycle,
  Expose Prey's windows and range looks stay the rich regime's (a Raptor Strike not bought is a white swing); the starved
  income's free Judgement of Wisdom from the rich pass's free hits.
- A17 The mana potion's fit at 125 s by the ceiling and the casting regen of the state up to that instant.
- The Survival weave's approximations are WA1-WA10 of section 15.10; the DoT procs' are DA1-DA4 of section 17.6.

## 12. Implementation order (each step leaves `lua tests/run.lua` green)

Steps 1-9 are done on `raid-mode`: 1 `4e1a574`, 2 `df2cdd9`, 3 `a533624`, 4 `7fe7f5d`, 5 `8fd5b34` (review `98fe4db`,
`3308816`), 6 `4d78c40`, 7 `560856e`, 8 `1db4d89`, 9 `7c3cb1b` (review `452bea5`, `054a572`, `a1bd4a7`, `dfa7300`). Their
text below is the record of what they built; groups A, B and C and the later steps follow, one commit a step, each
naming the tests it moves (measured with mutations on a scratch copy of HEAD `dfa7300` where a mutation can stand for the
step: 14.7, 15.9, 16.3, W1D 5 and 6).

1. **Inputs and the mode, no behaviour change.** `p.mode` (raid treated as levelling for now), `p.agi`,
   `p.rangedGearHit = 0`, `p.beastSlaying` (unused), `p.apVsTarget` (unused), `p.spellHit`, `p.spellCrit`, raid mana
   inputs read and required in raid; `checkInputs` lists; Snapshot sets them; ReadStats reads them (secret checks); Init
   v3 migration; `/hga target` 0-3; test_game env stubs (`UnitStat`, `GetManaRegen`, `GetManaRegenFromSpirit`,
   `GetSpellHitModifier`, `GetSpellCritChance`, `GetHitModifier`); fixtures; the mode-switch tests of 2.5;
   `tools/preraid/rescore/rescore.lua` `pointFor` gets the new inputs so the tool keeps running (`mode` by its mobDiff,
   `agi = BASE.AGI + t.AGI`, `rangedGearHit = 0`, `beastSlaying = 0`, `apVsTarget = 0`, `spellHit = 0`,
   `spellCrit = 3.6 + 0.0165 × Int` from `wowsims/sim/core/base_stats_auto_gen.go:38-42, 62-66`; run by hand, it is not in
   `tests/run.lua:34`). Files: Core/Model.lua, Game/Player.lua, Game/Init.lua, Game/Commands.lua, tests/test_model.lua,
   tests/test_score.lua, tests/test_game.lua, tools/preraid/rescore/rescore.lua.
2. **Level cap +3** (4.1). Core/Model.lua, tests.
3. **Melee for Survival only** (3). Game/Player.lua, Game/Commands.lua, Game/Init.lua (the `meleeFrac` comment),
   tests/test_game.lua (the 15 cases of 3.4).
4. **Ranged gear hit, scopes and pet / hawk hit** (4.4, 4.7.1). Core/Parse.lua, Game/Templates.lua,
   tests/fixtures_templates.lua, Core/Model.lua, Core/Score.lua, Game/Player.lua, Game/Advisor.lua, Game/Commands.lua (the
   cap line), tools/gen_set_data.py, Game/SetData.lua (regenerated), tools/preraid/rescore/rescore.lua (its RHIT into
   `rangedGearHit`), tests.
5. **AP versus creature type, Lodestone** (4.5 second part, 4.7.2). Core/Parse.lua, Game/Items.lua, Core/Model.lua
   (`p.apVsTarget` on the hunter's own attacks, `W.AP_VS`), Game/Player.lua (the input), tools/gen_set_data.py,
   tools/gen_use_data.py, Game/SetData.lua, Game/UseData.lua (regenerated), Game/Advisor.lua, tests.
6. **Beastslaying per wowsims** (4.5 first part). Core/Model.lua, Core/Score.lua, Game/Player.lua, Game/Advisor.lua,
   Game/Commands.lua (dump field), tests.
7. **Crit suppression and `Model.ApplyStats` for the weights** (4.2, 6.8's map without the raid keys). Core/Model.lua,
   tests.
8. **Single-roll white table, pet specials, parry, two-slope expertise** (4.3). Core/Model.lua, Core/Score.lua,
   Game/Advisor.lua, tests.
9. **Procs** (4.6): tools/gen_proc_data.py, Game/ProcData.lua, the TOC entry for it, Game/Items.lua (link), Core/Parse.lua
   (the proc's school), Core/Score.lua (masks, rates, ICD, RequireDamageDealt, DefenseType 0, CannotCrit, `own`),
   Core/Model.lua (`ProcOutcomes`, dive in `LandedHits`), Game/Advisor.lua (ctx.procOutcome, tooltips), the test
   fixtures of 4.6.3 (test_game's `ns.ProcData`, test_score's proc fields and `ctx.procOutcome`), tests (run.lua and
   test_game's `loadAll` load ProcData).
Group A (the user's later decisions, then W1D's first two steps):

- **A1 Settings removed** (section 14): `/hga target`, `/hga cap`, `/hga ppm`, `/hga min`, `/hga banner` and their saved
  keys (migration v4); the target by the mode, the hit cap by the target, threshold 0 (`Score.Verdict`, `Score.Plan`),
  the banner always on, the help; the unmeasured proc rate per U4 (13: this part waits for the user's answer).
  Game/Commands.lua, Game/Init.lua, Game/Player.lua, Game/Advisor.lua, Game/Swap.lua, Core/Score.lua,
  tools/preraid/rescore/rescore.lua (its ctx and its passes, 14.6), tests (14.7).
- **A2 The Survival weave** (section 15): `p.survival` in place of `p.meleeFrac` and `p.weave`; the cycle, the range and
  melee looks, Raptor Strike, Strider Kick, Mongoose Bite, Wing Clip, Immolation Trap, Serpent Sting from the shooting
  spot, Expose Prey and Lacerating Strikes in the weave; `/hga melee`, `/hga weave` and their keys removed (migration v5,
  `ns.settings` gone); the `/hga weights` melee line. The range look's shared-category shot waits for U3 (13).
  Core/Model.lua, Core/Score.lua, Game/Player.lua, Game/Advisor.lua, Game/Commands.lua, Game/Init.lua, Game/Quest.lua,
  Game/Tooltip.lua, tests (15.9).
- **A3 The unarmed main hand at 1.0 s** (section 16). Game/Player.lua, tests (16.3).
- **A4 = W1D W1** (the dive's flats) and **A5 = W1D W2** (Improved Arcane Shot with hawks, levelling).

Group B: **W1D W3** (ranged weapon skill, the pet's ranged branch) and **W1D W4** (melee weapon skill, the pet's melee
branch; its melee rolls are the weave's, RMD 15).

Group C: **W1D W5** (hawk speed), **W1D W6** (docs) and:

10. **Raid target, averaged** (5): raid mode switches armor 976 (with armor penetration, O5), petTanks 0, dragonkin
    shares, Rapid Killing 0, Curse of the Elements and Gift of Arthas (O7 = (a)), still with averaged cooldowns; the mode
    line of `/hga weights`; the comments of `Core/Model.lua:206` (`killInterval` "while levelling" → the levelling mode's
    value; raid has no kill) and `Core/Model.lua:210` (`petTanks` "solo levelling: the pet tanks" → the levelling mode's
    value; raid 0, the pet behind); first raid fixtures at 60. (The target 3 at 60 and the cap from `model.mobDiff` come
    with A1.) Core/Model.lua, Core/Score.lua, Game/Player.lua (`p.armorPen`), Game/Advisor.lua, Game/Commands.lua, tests.

Group 0 (after group C, before step 11; section 18): the probe battery's failing lines classified and the test env's
weapon lines by the level (18.1), the swap banner's take-off rows (18.2), the weave's open points (18.3, 18.4), U3 (18.5),
U4 (18.6), a set's proc table (18.7), spell hit and spell crit (18.8), the texts and data of the open points (18.9);
its review's fixes and the one point it leaves open, wowsims' ProcChanceAlways auras (18.10).

Later groups:

11. **The fight without mana** (6): segments, w(t), windows, the cast tempo (`δ_S`, `δ_H`), Serpent `U`, hawks, Use buffs
    through the model (`Model.ApplyStats` with the raid keys, `ctx.useGain`, `ctx.useUptime`, the pet's AP snapshot; the
    levelling Use weights without the pet's share, O6), `Model.Fight`, tooltip Use line, the Survival weave per segment
    (15.5). Every segment rich. Core/Model.lua, Core/Score.lua, Game/Advisor.lua, Game/Commands.lua, tests. Done:
    11.1 `15c56d1`, 11.2 `1d24ae4`, 11.3 `cec875f`, 11.4 `fc40e9c` (review `bde3ff6`, `ba10ecc`, `aa8b83b`); what it
    settles and leaves: section 19.
12. **Mana** (7): costs (the weave's casts included, 15.5), regen (Resourcefulness from the fight), regimes, timeline (the
    ceiling, the debt, the cheapest ready rule), JoW (O7 = (a)), consumables always on (O2 = (a): category 4 shared, the
    Frenzy Potion window), raid weights for Int / MP5 / Spirit / mana, raid secondary, `/hga weights` and dump lines;
    `tools/gen_use_data.py` `DAMAGE_KEYS` + `SPI`, `MP5`, `MANA` and `Game/UseData.lua` regenerated; `rescore.lua` gets
    the mana inputs for its raid pass (`manaMax = 1720 + 20 + 15 × (Int − 20)`, `mana.go:59-71` with base mana 1720;
    Spirit = the orc hunter's 70 + 3, `wowsims/sim/core/base_stats.go:52-56, 138-147`, plus gear; `regenCast = MP5/5 +
    share × (6.25 + Spirit/8)`, `regenRest = MP5/5 + 6.25 + Spirit/8`, `mana.go:77-78, 167-196`). Core/Model.lua,
    Core/Score.lua, Game/Player.lua, Game/Advisor.lua, Game/Commands.lua, tools/gen_use_data.py, Game/UseData.lua,
    tools/preraid/rescore/rescore.lua, tests. Done: 12.1 `29e870c`, 12.2 `df9eebc`, 12.3 `c438322`, 12.4 `cfadb55`, 12.5
    `0935dfe`, 12.6 `3007a5f`; what it settles and leaves: section 20.
13. **Stat multipliers** (4.8, O8 = (a)): tools/gen_stat_mult_data.py, Game/StatMultData.lua, the TOC entry,
    Game/Player.lua, Core/Model.lua, tests. Done: `f57ed7b`; what it settles: section 21.
D. **DoT procs** (section 17, U2 = (a)): tools/gen_proc_data.py, Game/ProcData.lua (regenerated), Game/Items.lua (the
    link of a DoT entry), Core/Model.lua (`ProcOutcomes`' application and tick factors), Core/Score.lua (`ProcValue`'s DoT
    part), Game/Advisor.lua (tooltip), tests (17.5). Done: `4d30a5b`; what it settles: section 22.
14. **Docs and tools**: `docs/superpowers/specs/hunter-gear-advisor-design.md` (modes, mechanics, the user's lines 14-17
    on melee and mana by mode, the removed commands and settings of section 14, the Survival weave of section 15, the
    unarmed speed of section 16, the DoT procs of section 17), `docs/research/W1-wowsims-check-2026-11-16.md` by-design and
    open entries that this design settles (ranged-4, stats-gear-12, stats-gear-8, melee-sv-12, the Tablet, Beastslaying,
    the equip mask, the application rule, the white table, stats-gear-4's DoT procs), and
    `tools/preraid/rescore/README.md` (mode, the new inputs, the raid pass alone, 14.6). Done in one commit; what it
    settles: section 23.

Group G (after steps 13, D and 14 and their review; section 25): the points the design left open (18.10, 19.4, 20.5, 24.6),
built the wowsims way, one commit a point, each with its tests and this design.

## 13. The user's answers and the points still open

Answered by the user (2026-11-17):
- **O1 Survival tie: strictly most.** Survival counts only with strictly more points than BM and than MM; a tie gives no
  melee, and so does a hunter below level 10 (section 3; built in step 3).
- **O2 In-fight consumables: (a), always on, no setting, no command** (7.4).
- **O3 W1's other open questions: the wowsims way**, each where wowsims states a rule: W1D. Aspect of the Viper (415423)
  stays unmodelled: wowsims has it in its generated data only (`sim/hunter/spell_data_auto_gen.go:33, 253`) and registers
  no use of it.
- **O4 Manual hit cap in raid mode: gone** with `/hga cap` (section 14); the hit cap follows the target.
- **O5 Armor penetration: against the boss armor, as wowsims** (5.1).
- **O6 A Use buff's attack power never reaches the pet, both modes** (6.8).
- **O7 The preset's other debuffs on the boss: (a)** (5.3): Judgement of Wisdom, Curse of the Elements and Gift of
  Arthas. The caveat stays on record: Judgement of Wisdom needs a paladin in the raid, the character is Horde
  (`docs/research/preraid-bis-60.md:64`), and whether Forever's Horde has paladins is not in the local sources
  (critic.md); the user's answer counts it as wowsims' preset does.
- **O8 The live sheet's stat multipliers: (a), they count** (4.8).
- **U2 DoT procs: (a), as wowsims prices them** (section 17).

Settled by the orchestrator under the user's rule «берем как в вов симс» (group 0, section 18):
- **U3 The Survival weave's shared-category shot: (a), Multi-Shot** (15.11; 18.5): the SV Weave preset's rotation casts
  Multi-Shot and never Aimed Shot (`default.apl.siml:6-7, 30-33`).
- **U4 The unmeasured proc rate: (a), as wowsims, no rate made up** (14.4; 18.6): `MEASURED_PPM`, else wowsims' per-item
  carry-over / override data, else the DB2 rate or chance; a proc with none of them is not priced.

Settled by the orchestrator (group G, section 25): **wowsims' ProcChanceAlways auras** (18.10): Parse reads their lines,
the generator marks the auras wowsims registers "every time", Score prices them at 100 a hit with the cooldown as a dead
time (25.3).

Settled by the orchestrator (group G, section 25): **Quick Shots inside Rapid Fire** (19.4: each state of the fight at its
own Auto Shot rate, 25.4) and **the HHA sequence with no bow at 60** (19.4: it stops at Arcane Shot after its two hawks,
25.5).

Open (step 12, 20.4): **the Survival weave in a starved fight scores a set without a melee weapon higher** (Raptor Strike
and Wing Clip, which take the starved income first, need one), so the swap plan can name taking the main hand off.

Settled by the orchestrator (group G, section 25): **the mana stats' weights across a discrete event of the fight** (the
mana potion's or the rune's fit, 20.5): the weights hold the point's events, a set's change of an event is priced on the
set (25.1).

Open (step 11's review, 19.6): **the major cooldowns on a free GCD**, **the BM preset's walk in from 25 yd**, **a worn
trinket moved between the two trinket slots** and **the Use line's count of the casts after 180 s**.

## 14. Settings removed

The user (2026-11-17): «нахуй ты спамишь командами… у адона 2 функции: показать что одеть и вкладка с бис шмоткой»,
«убирай нахуй», «просто блять на прокачке на мой уровень на 60 на рейды». No new slash command or setting, and the tuning
commands and their saved settings go.

### 14.1 Commands removed and kept

| Command | Today (`Game/Commands.lua`) | Saved key (`Game/Init.lua` `ns.DEFAULTS`) | Step |
|---|---|---|---|
| `/hga target` | 264-273, help 237 | `mobDiff` (8) | A1 |
| `/hga cap` | 261-263, help 235-236, `effectiveCap` 226-228 | `hitCapOverride` (9) | A1 |
| `/hga ppm` | 291-293, help 241 | `procsPerMinute` (10-11) | A1, with U4 |
| `/hga min` | 294-296, help 242 | `threshold` (12-13) | A1 |
| `/hga banner` | 301-305, help 245-246 | `swapBanner` (14) | A1 |
| `/hga melee` | 274-286, help 238; `topBranches` 19-29 (its only caller is 284) | `meleeFrac` (6) | A2 (its model input goes with the weave, section 15) |
| `/hga weave` | 287-290, help 239-240 | `weave` (7) | A2 |

Kept: `/hga weights` (`/hga w`), `/hga dump`, `/hga swap` (the list of what to put on), `/hga preraid` (`/hga pr`, the
BiS window). The first two set nothing (read-only diagnostics). Any other text prints the help, as today
(`Game/Commands.lua:306-307`), so a removed command prints the help and changes nothing.

### 14.2 The target and the hit cap follow the mode

- `Player.Snapshot` (`Game/Player.lua:873`, today `mobDiff = s.mobDiff`): `mobDiff = model.mode == "raid" and 3 or 0`.
  Below 60 the target is the hunter's own level (the user's «на прокачке на мой уровень»); at 60 it is the raid boss +3
  (user 6 = (a); wowsims' target level 63, `defaults.siml:64`; the Forever client's `RAID_BOSS_LEVEL = 63`,
  `UI/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua:57-58`). `p.mobDiff` stays a required model input,
  so a test builds any point 0..3 (and 4.1's cap at +3 holds for it).
- `A.State` (`Game/Advisor.lua:143-144`, today `s.hitCapOverride or ns.Model.HitCap(s.mobDiff)`):
  `ctx.hitCap = ns.Model.HitCap(model.mobDiff)`: 5% below 60, 8% at 60 (`Model.HitCap`; the client's
  `CR_HUNTER_HIT_CAP_TOOLTIP`, GlobalStrings 60052: 8% against raid bosses, 5% against the own level). `ctx.expertiseCap`
  and `ctx.parryCap` already read `model.mobDiff` (`Game/Advisor.lua:173-174`). The local `s = ns.settings` of A.State
  goes.

### 14.3 Threshold 0

- The user's earlier rule (the v2 comment, `Game/Init.lua:16-17`): any damage gain gets the checkmark. `Score.Verdict`
  (`Core/Score.lua:1405-1415`) loses the threshold argument: a gain above `Score.EPS` is "better"; the verdict "minor"
  goes, with its tooltip line (`Game/Advisor.lua:475-476`, «урон +%s — меньше порога галочки (/hga min)») and its case at
  484. `Score.Plan` loses `ctx.threshold` (`Core/Score.lua:1026, 1270-1290`: a step passes when it gains; the comments of
  1175-1200 shrink to that rule); the three `Score.Verdict` calls (`Game/Advisor.lua:334, 400, 435`) and the ctx field
  (162) lose the argument. The Plan's invariants are those of threshold 0, today's default (the mutation that fixes it at 0
  kills no test, 14.7).

### 14.4 The unmeasured proc rate (U4: settled (a), section 18.6)

- What it is today: the rate of a damage proc with no measured rate (`Score.ProcsPerMinute`, `Core/Score.lua:211-234`:
  `MEASURED_PPM`, a twin's carried rate, else `opts.procsPerMinute`, the `/hga ppm` setting, default 1.5,
  `Game/Init.lua:10`), also the rate of an equip proc whose DB2 row states none (4.6.2).
- The decision: it becomes a constant with its source. The sources read give no constant:
  - wowsims makes no rate up. A rate the game files do not state takes a per-item carry-over value
    (`wowsims/tools/database/overrides/weapon_procs.go:1-19`: 117 rows, 79 of them `vanilla-carryover`, each with
    "TODO: Vanilla value - verify in-game"; `wowsims/docs/rulings/R-0046-unstated-rate-carryover-todo.md`), and a proc
    whose item entry states no rate registers nothing: "no rate is made up for it"
    (`wowsims/docs/rulings/R-0047-hand-proc-needs-entry-rate.md`).
  - HGA's 1.5 has no source in the repository (W1 stats-gear-4: "a flat 1.5 PPM").
- Options for the user:
  - (a) as wowsims: `Score.MEASURED_PPM` takes wowsims' carry-over rows as well (their tooltip line says the rate is a
    carry-over, unchecked in Forever), and an item in neither table is not priced (its tooltip line says so). Moves 23
    tests (measured: the unmeasured rate set to 0, 14.7).
  - (b) keep 1.5 as a constant, stated in the code as HGA's estimate with no source. Moves no test.
  - (c) another constant the user names, with its source.
- Settled (a) by the orchestrator under the user's rule; group 0 builds it (18.6). Step A1 removed the other settings;
  `/hga ppm` and `procsPerMinute` go with 18.6. The tooltip
  line of an unmeasured rate (`Game/Advisor.lua:677`, «%.1f/мин на базовой скорости оружия — /hga ppm») becomes, under
  (a), `HGA: частота эффекта не замерена — не учитывается (как в wowsims)` (or, for a carry-over row,
  `… %.2f/мин — перенос из классики, в Forever не проверено`), under (b) `%.1f/мин — оценка без замера`.

### 14.5 What the UI prints instead

- Help (`helpLines`, `Game/Commands.lua:230-248`), four lines:
  `/hga weights — веса статов и входные цифры`;
  `/hga dump — записать разбор всех вещей в файл (потом /reload)`;
  `/hga swap — показать список замен (что из сумок надеть вместо чего)`;
  `/hga preraid (/hga pr) — окно пререйд-набора: чего не хватает и где брать`.
- `/hga weights`: its first line names the mode and the target in place of the settings: levelling
  `режим: прокачка (ур. %d) — цель твоего уровня, кап меткости %.1f%%`, raid
  `режим: рейд (ур. 60) — босс +3, кап меткости %.1f%%` (step 10 extends the raid line as section 8 gives it); the melee
  line of 15.6 in place of the `/hga melee` lines (`Game/Commands.lua:75-82`); the cap field of the stat line prints
  `ctx.hitCap` as today.
- `/hga dump`: adds `target = st.model.mobDiff`; keeps `hitCap`; `settings = ns.settings` (`Game/Commands.lua:194`) goes
  in A2 with `ns.settings` (A1 keeps it while `meleeFrac` and `weave` are still saved); A2 adds the weave's breakdown
  (15.6).
- The swap banner is always on: `Game/Swap.lua:351` builds the plan whenever out of combat (today
  `(ns.settings.swapBanner or forced)`); the × keeps hiding it until the plan changes (`Game/Swap.lua:45, 286-291,
  341-343`, unchanged); `Swap.ResetDismissed` (`Game/Swap.lua:389-392`), whose only caller is `/hga banner`
  (`Game/Commands.lua:303`), goes; the `forced` flag keeps its role for `/hga swap` after a × (`Game/Swap.lua:46,
  371-375`), its comment loses "although the automatic banner is off".
- Tooltip lines naming a removed command: `Game/Advisor.lua:476` (/hga min) goes with "minor" (14.3); 677 (/hga ppm) per
  U4 (14.4).

### 14.6 Saved settings, the migration and the tool

- A1: `SETTINGS_VERSION = 4`. Under a saved `settingsVersion` below 4, ADDON_LOADED deletes `mobDiff`, `hitCapOverride`,
  `procsPerMinute` (with U4), `threshold` and `swapBanner` from `db.settings`; the v2 rule (a threshold of 0.5 → 0) and the
  v3 rule (a mobDiff above 3 → 3) (`Game/Init.lua:51-52`) go, since their keys go. `ns.DEFAULTS` loses the five keys
  (`Game/Init.lua:8-14`).
- A2: `SETTINGS_VERSION = 5`. Under a saved version below 5, `meleeFrac` and `weave` are deleted; `ns.DEFAULTS` is then
  empty and goes with its fill loop (`Game/Init.lua:5-14, 54-56`), and `db.settings` itself is removed
  (`HunterGearAdvisorDB.settings = nil`): HGA keeps no setting. `ns.settings` goes; the three loaded checks that read it
  (`Game/Quest.lua:73, 226`, `Game/Tooltip.lua:28`) read `ns.db` (set at ADDON_LOADED, `Game/Init.lua:57`), and
  `Player.Snapshot`'s `local s = ns.settings` (`Game/Player.lua:848`) goes.
- The migration deletes silently: the removed settings tuned nothing the model keeps.
- `tools/preraid/rescore/rescore.lua`: its passes `MOB_DIFFS = {3, 2, 0}` (`rescore.lua:707-714`) were `/hga target`
  values; its point is a level-60 hunter, so it keeps the raid pass alone (`mode = "raid"`, +3, the user's «на 60 на
  рейды»); its ctx loses `threshold` and takes U4's rate rule; its README result table (`README.md:42-49`, whose +2 and
  +0 lines go) is re-run in step 14.

### 14.7 Tests

Measured on a copy of HEAD `dfa7300` (`git archive`), one mutation at a time, the whole suite (395 tests) each time.
Runner, mutants and results: `C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/rmdoc/tools/mut.py`, `tools/mutants_a.py`,
`tools/mutants_c.py`, `out/a.json`, `out/c.json` (same folder).

| Mutation (standing for a part of A1) | Result | Tests that fail |
|---|---|---|
| `/hga target` unreachable | 391 / 4 | test_game `/hga target 4 and 5 are stored as 3; /hga target 2 as 2`; `slash commands run`; `/hga dump: the expertise cap 6 at /hga target 2; at /hga target 3 the two caps differ, expertise 6.5 and hit 8`; `expertise: an item crossing the mob's dodge gets the part below it; a worn one past it is priced when it comes off` |
| `/hga cap`, `/hga ppm`, `/hga min` unreachable | 395 / 0 each | — |
| `/hga banner` unreachable | 392 / 3 | test_game `swap banner: x hides it until the plan changes, combat hides it, /hga swap and /hga banner`; `the banner's × survives a bag sort and a manual equip, a new suggestion brings it back, /hga banner on clears it`; `/hga swap works with the banner off; the list stays open after a refresh; closing it hides the banner` |
| Snapshot `mobDiff` by the mode | 393 / 2 | the `/hga dump: the expertise cap 6 …` and `expertise: an item crossing …` cases above |
| `ctx.hitCap` from `model.mobDiff`, no override | 395 / 0 | — |
| threshold fixed at 0 | 395 / 0 | — |
| the unmeasured rate a constant 1.5 (U4 (b)) | 395 / 0 | — |
| the unmeasured rate 0 (U4 (a), no rate made up) | 372 / 23 | test_score: `proc adds extra dps value: …`, `a melee weapon proc fires only on its own hand's melee hits`, `errors: … an unmeasured rate without the setting …`, `stats-gear-4: a measured proc rate comes before the setting; …`, `SAME_PROC: a twin takes the measured rate only at the measured weapon's tooltip speed`, `stats-gear-4: an equip proc on armor rolls on the hits its text names, …`, `procs: Serpent Sting's applications roll a weapon's chance-on-hit proc …`, `procs: a bow's proc at meleeFrac 1 …`, `procs: a weapon's own proc rolls on its own set's hits …`, `procs: a weapon's melee or any equip proc rolls on the other hands …`, `procs: a melee equip proc on armor while dual wielding …`, `procs: the Highborne Research Tablet at each hand's own speed, …`, `procs: a held-in-off-hand item of the weapon class …`, `equip procs by mask: …`, `equip proc rate: PPM, chance 1-99, else MEASURED_PPM or /hga ppm; the ICD caps it`; test_game: `SAME_PROC: a twin's carried rate names the item it is measured on; …`, `procs: a proc weapon in the off hand of a pair, …`, `procs: a bag bow's proc with no bow worn …`, `procs: a two-hander's melee proc, a pair worn: …`, `procs: a two-hander's melee proc is valued on its own set's hits: …`, `ModelProcRates: a worn off-hand weapon at the off hand's rate; …`, `procs: the tooltip's rate says 'сейчас' …`, `procs: a worn set with procs on both hands, …` |
| the banner always on | 392 / 3 | `swap banner: x hides it …`; `/hga swap works with the banner off; …`; test_game `use buff: the aura state is checked every second while A.State waits on a Use buff, one re-read when it falls` |
| all of A1 but U4 together | 387 / 8 | the union of the rows above |

- Moves by reading (no mutation stands for them): test_game `settings v1 threshold 0.5 is reset to 0 (damage always
  decides)`, `settings: a threshold of 0.5 saved under settingsVersion 1 is reset to 0`, `settings: a threshold of 0.5
  saved under settingsVersion 2 stays`, `settings v3: a saved mobDiff 5 or 4 becomes 3; a saved 3 or 2 stays` (replaced
  by the v4 test below); test_score's ctx builder and the Score cases that pass `procsPerMinute` (per U4).
- New (each with its mutant):
  - `settings v4: a saved mobDiff, hitCapOverride, procsPerMinute, threshold and swapBanner are deleted under version 3; a
    key HGA does not know stays` (mutants: one key kept; the check `<= 4`).
  - `settings v5 (A2): meleeFrac and weave deleted; db.settings removed; the loaded checks read ns.db` (mutants: weave
    kept; db.settings kept).
  - `target: Snapshot's mobDiff is 0 at 59 and 3 at 60, and a saved mobDiff is not read` (mutants: 3 at 59; the saved key
    read).
  - `hit cap: ctx.hitCap 5% at 59 and 8% at 60` (mutant: a saved override wins).
  - `verdict: any damage gain above EPS is "better"; there is no "minor"` (mutant: a threshold of 0.5).
  - `plan: a step that gains less than 0.5 is taken` (mutant: `thr = 0.5`).
  - `slash commands: target, melee, weave, cap, ppm, min and banner print the help and change nothing` (mutant: one
    command kept).
  - `help: the four lines of weights, dump, swap and preraid` (mutant: a removed line kept).
  - `banner: the plan is built whenever out of combat; the × hides it until the plan changes` (mutant: a flag read).
  - `rescore`: no test (the tool is run by hand, step 1); A1 runs it once and states its one raid pass in the commit.

## 15. Survival melee as wowsims' weave

### 15.1 Rule and sources

- The user: the Survival branch (strictly most points, section 3) melees, in both modes; «its melee and weave follow
  wowsims' Survival preset». The preset: the build `SV Weave` (`wowsims/ui/specs/hunter/dps/builds/sv_weave.siml:1-14`,
  the first of `Builds`, `presets.ts:133-141`: "Only Survival has a weave build") with the rotation
  `apls/default.apl.siml` ("Melee Weave (Max)", `presets.ts:116-118`; `DefaultRotation`, `presets.ts:125`), its variables
  `Melee weave = true`, `Use Aimed Shot = false`, `Use Multi-Shot = true`, `Use Arcane Shot = true`, `Use Summon Hawk =
  false` (`default.apl.siml:5-9`), over `weave_common.apl.siml`, `walk_in.apl.siml`, `common.apl.siml` and
  `pull.apl.siml`; reaction 150-350 ms and distance 12 yd (`sv_weave.siml:8-10`). `presets.ts:32-34`: "the melee swing
  resets Auto Shot, so each weave lasts as long as the slower of the two swings".
- The weave as the APL plays it (`weave_common.apl.siml:6-7`): "once Auto Shot has gone off, walk in and swing; once I've
  swung, hit or not, walk back out to the spot and shoot". Its rows (`weave_common.apl.siml:24-33`): start the attack in
  melee; in melee wait for the GCD if it comes up within 400 ms, and for Strider Kick likewise (`kick_soon`, 13-19); walk
  out to the shooting spot if no Auto Shot came since the last swing (`shot_since_swing`, 20); walk in to the melee spot
  if one did. The shooting spot is `max($ranged_range 13.19, 11.67)` = 13.19 yd (`weave_common.apl.siml:3, 8`); the melee
  spot 4.99 yd (9-10).
- The priority (`default.apl.siml:15-39`), each look taking the first ready row: Rapid Fire at range after 5 s (17);
  the other major cooldowns at range after 5 s (18); Hunter's Mark if missing (19); Raptor Strike (20); Strider Kick (21);
  Mongoose Bite (22); Immolation Trap in melee (23); Wing Clip unless Strider Kick is known and ready within 1.5 s (24);
  Serpent Sting if its dot is down (25); the HHA sequence and Summon Hawk only with `Use Summon Hawk` (26-28: off);
  Arcane Shot (29); Multi-Shot (30); Aimed Shot only with `Use Aimed Shot` and when its cast and the walk in fit before
  the next main-hand swing (31-33: off); the walk in at the pull (35-38); the Weave group (39).
- The engine rules it runs on (wowsims `sim/core`, read, not run):
  - a player walks 7 yd/s (`movement.go:263-266`); a walk that crosses melee range (5 yd, `constants.go:24`) wakes the
    unit there (`movement.go:216-224`) and the melee swing starts in range (`movement.go:123-132`; `attack.go:850-867`:
    at its timer or at once if due);
  - the melee swing timer keeps running out of range (`attack.go:900-914` stops the swing event only;
    `attack.go:863` resumes it at `max(swingAt, now)`);
  - a melee swing restarts the ranged auto: the next Auto Shot comes a full ranged swing after it, the windup included
    (`attack.go:461-465`, `StopRangedUntil` `attack.go:1132-1140`); the windup is 500 ms over the ranged speed
    (`constants.go:22`; `attack.go:353-362`); a bow fires from 11.67 yd (`constants.go:30`; `attack.go:61-69`);
  - moving holds the ranged auto (`attack.go:364-377`, `movement.go:32-36`); a shot that came due while moving waits a
    reaction time after the walk ends, one not yet due goes at its time (`attack.go:946-958`);
  - after every swing, melee or ranged, the rotation looks a reaction time later (`attack.go:469-471`,
    `gcd.go:145-173`); each look draws its own reaction, uniform in the range (`gcd.go:133-143`); a rotation with a walk
    looks every reaction time, through the GCD too (`apl.go:594-614`); one look casts rows until none is ready, so a GCD
    spell and then a walk go in one look (`apl.go:553-572`);
  - instants are cast while walking, a cast with a cast time is not (`spell.go:783`, `cast.go:188`);
  - Raptor Strike is queued by the APL whenever its 6 s cooldown is up and its mana is there, with no range, and goes off
    in place of the next main-hand swing (`sim/hunter/raptor_strike.go:24-71`);
  - starting the melee attack puts the off hand's next swing at least half its swing time out
    (`attack.go:806-819`), and starting an Auto Shot turns the melee attack off (`attack.go:415`).

### 15.2 The cycle

One cycle runs from a main-hand swing to the next. Symbols (seconds; `ρ` a reaction, uniform in `[0.15, 0.35]`,
mean `ρ̄ = 0.25`; `meleeSpeed`, `ranged`, `haste`, `rf` as `partsAndHits` has them, `haste` the owner's speed of W1D 7.3,
`(1 + p.haste/100)(1 + p.attackSpeed/100)(1 + p.hasteRating/100)`, step W5):
- `M = p.mhSpeed / (haste × (1 + meleeHaste/100) × (1 + rf))`, the main hand's swing time (1.0 s unarmed, section 16);
- `R = p.bowSpeed / hRanged` and `wu = 0.5 / hRanged`, the ranged swing time and its windup, `hRanged` the shots' speed
  with Quick Shots and Rapid Fire (`Core/Model.lua` `hRanged`);
- the walks at 7 yd/s: out `W_out = (13.19 − 4.99) / 7 = 1.1714`, in to melee range `W_in = (13.19 − 5) / 7 = 1.1700`;
  inside Strider Kick's 3 s the hunter walks 30% faster (DB2 SpellEffect 1357611: aura 31, base points 30; SpellMisc
  863136 DurationIndex 27 = 3000 ms; wowsims `sim/hunter/talents_survival.go:155-163`).

The path (my reading of the rules of 15.1):
1. The swing at `T_m`; the look at `T_m + ρ₁` casts the melee look's GCD action (15.3) and starts the walk out.
2. The walk ends at `T_m + ρ₁ + W_out`. The Auto Shot's windup is due at `T_m + R − wu`: if it is not yet due, the shot
   goes at `T_m + R`; if it is, it starts a reaction `ρ₂` after the walk: the shot at `T_m + ρ₁ + W_out + ρ₂ + wu`.
   With `u = R − wu − W_out`, the shot path `S = T_s − T_m` has the mean (exact over the uniform `ρ₁`, `ρ₂`; my arithmetic)
   `E[S] = R + h(u)`, `h(u) = 0` for `u ≥ 0.35`, `0.5 − u` for `u ≤ 0.15`, and
   `((0.35 − u)(0.25 − u) + (0.35² − u²)/2) / 0.2` between (continuous at both ends).
3. The look at `T_s + ρ₃` casts the range look's GCD action if the GCD is free (15.3) and starts the walk in; the swing
   comes at `T_m' = max(T_m + M, T_s + ρ₃ + W_in)`.
4. The cycle `C = K + e(M − K)` with `K = E[S] + W_in` and `e(c) = E[max(c, ρ₃)]` = `0.25` for `c ≤ 0.15`, `c` for
   `c ≥ 0.35`, `(c(c − 0.15) + (0.35² − c²)/2) / 0.2` between (exact over `ρ₃` at the mean `S`, WA1).
5. Strider Kick's speed: with `k` the share of cycles whose melee look kicks (15.3), the walk out after a kick takes
   `8.2 / 9.1 = 0.9011`, and the walk in after it runs at 9.1 yd/s for what is left of the 3 s, `t = max(0, 3 − E[S])`:
   `W_in^K = t + (8.19 − 9.1 t)/7` while `9.1 t < 8.19`, else `8.19 / 9.1`. The cycle takes `W_out = (1 − k) × 1.1714 +
   k × 0.9011` in `u` and `W_in = (1 − k) × 1.17 + k × W_in^K` in `K` (WA6).
6. The spread of a cycle, for 15.3's counts: `σ² = (0.2²/12) × P_arr × (1 + 2 P_held)`, `P_arr = clamp((K + 0.35 −
   M)/0.2, 0, 1)` (the walk sets the swing, not the timer), `P_held = clamp((0.35 − u)/0.2, 0, 1)` (the shot waits on the
   walk) (my arithmetic, WA2); `σ = 0` when the swing timer binds.
7. `C`, Quick Shots' uptime (its proc on each Auto Shot: `12 / C` shots in its 12 s window) and `k` depend on each other:
   they are solved together by fixed-point iteration from `k = 0`, Quick Shots 0, to `|ΔC| < 1e-9` s; no convergence in 100
   iterations is an error (WA10).

### 15.3 What a cycle holds

- **The Auto Shot**: one a cycle (`1/C` a second), landing with `shotHitf`.
- **The main-hand swing**: one a cycle; Raptor Strike takes it every `nCycles(6, C, σ)` cycles (its cooldown from the
  swing it went off on; armed only, as today), the white swing the others. `nCycles(d, C, σ)`, the mean number of
  cycles from an event to the first look at least `d` later, cycle lengths of mean `C` and spread `σ` (normal
  approximation of their sum, my arithmetic, WA2):
  `nCycles(d, C, σ) = 1 + Σ_{n≥1} Φ((d − n·C) / (σ·√n))`, the sum until `n·C` passes `d` by 8 σ√n; at `σ = 0` the terms
  are `1` for `d > n·C`, else `0` (`ceil(d / C)`). The interval of such an action is `nCycles × C` (Wald).
- **The off hand**: it swings in a visit only when half its swing time fits before the walk out (15.1): share
  `clamp((0.35 + max(0, M − K) − ohSwing/2) / 0.2, 0, 1)` a cycle, `ohSwing = p.ohSpeed / (meleeSpeed × (1 + rf))`, Rapid
  Fire's melee speed in it (WA7; group 0, 18.3): half of any
  off hand's swing (1.3 s or slower) is above the reaction's 0.35 s, so the off hand swings only where the swing timer
  holds the hunter in melee.
- **The melee look** (one GCD action a cycle, WA4), in the APL's order:
  - Strider Kick (talent, from 30): at the first melee look whose cooldown is within 0.4 s (`kick_soon`):
    `r_K = 1 / (nCycles(8 − 0.4, C, σ) × C)` (cooldown 8000 ms, GCD 1500: DB2 SpellCooldowns 101528); its wait is left out
    (WA3); `k = r_K × C`;
  - Mongoose Bite: Expose Prey's windows (10 s) opened by every landed hunter hit of its mask (0x154: melee white and
    abilities, Auto Shot and the ranged abilities; 1310532, `spells_auto_gen.go:38066`), so today's weave branch holds:
    `x = (landed hits a second) × 0.05 × rank`, `bites = 1 / (5 + e^(−5x) / x)` (`Core/Model.lua` Expose Prey, the
    `p.weave` branch), a window spent at the next melee look; `r_B = min(bites, 1/C − r_K)`;
  - Immolation Trap (from 16): placed in melee (`in_melee`), springs on the boss (`sim/hunter/traps.go:35-53`):
    `r_T = min(1 / (nCycles(30 × (1 − 0.2 × SD), C, σ) × C), 1/C − r_K − r_B)` (category cooldown 30000 ms, Category 411,
    `spells_auto_gen.go:10789`; Survivalist's Discipline 1310496 −20% a rank on the trap placements' cooldown: SpellEffect
    1340058 aura 108 misc 11 mask 0:128, curve −20 / −40, `spells_auto_gen.go:38062-38064, 40027`);
  - Wing Clip (from 12; a melee weapon: EquipClass 2, subclass mask 173555, `spells_auto_gen.go:10647`): every melee look
    left, but the look before a kick when the kick is ready within 1.5 s (`default.apl.siml:24`), taken as `min(1, 1.1 /
    C)` of a look a kick (the look before the kick sees the cooldown uniformly in `(0.4, 0.4 + C]`, my arithmetic):
    `r_WC = max(0, 1/C − r_K − r_B − r_T − r_K × min(1, 1.1/C))`; with no Strider Kick, `1/C − r_B − r_T`.
- **The range looks**: instants go at the looks of the walk out once past 11.67 yd, of the standing time at the
  shooting spot and of the post-shot look (instants while walking, 15.1), each when the GCD is free; the melee look's GCD
  action holds the first 1.5 s after it. Range GCD slots a cycle `n_R = 1 + P₂`, `P₂` the chance that the window from the
  first free range look to the post-shot look reaches a GCD:
  `P₂ = f_M × T(3 − E[S]) + (1 − f_M) × T(1.5 + 6.68/7 + 0.1317 − E[S])`, with `f_M = min(1, (r_K + r_B + r_T + r_WC) × C)`
  the share of cycles whose melee look casts, `6.68 / 7` the walk out to 11.67 yd (4.99 to 11.67), 0.1317 s the mean wait
  for the next look (RMD 6.4's `r_poll`), and `T(x) = P(ρ₃ − ρ₁ ≥ x)`, triangular on `[−0.2, 0.2]`: `1` for `x ≤ −0.2`,
  `1 − (x + 0.2)²/0.08` for `−0.2 ≤ x ≤ 0`, `(0.2 − x)²/0.08` for `0 ≤ x ≤ 0.2`, `0` for `x ≥ 0.2` (my arithmetic, WA5).
  The range actions see a look every `C_R = C / n_R`, in the APL's order:
  - Serpent Sting (from 4) when its dot is down. Levelling: `CONST.serpentUptime` 0.8 as today (its applications
    `0.8 / 15` a second, its casts that over `shotHitf`); raid: the dot lands 13.19 / 40 = 0.33 s after the cast
    (Serpent Sting `Speed: 40`, `spells_auto_gen.go:10012, 21609`; RMD 6.4's travel) and lasts 15 s, so the landed
    applications come every `I_S = (nCycles(15.33, C_R, σ) + q/(1 − q)) × C_R` (a miss, `q`, known at the cast, retried
    at the next look), uptime `U = 15 / I_S`, casts `1 / ((1 − q) I_S)`; `r_S` its casts a second;
  - Arcane Shot (from 6): `r_A = min(1 / (nCycles(6 − 0.3 × IAS, C_R, σ) × C_R), 1/C_R − r_S)` (category 1173, Improved
    Arcane Shot −0.3 s a rank on Arcane's own cooldown, W1D 6);
  - the shared category 2 shot (from 18), per U3 = (a) (15.11, 18.5): Multi-Shot `r_M = max(0, min(1 / (nCycles(6 +
    0.5 / h_R, C_R, σ) × C_R), 1/C_R − r_S − r_A))`, its 6 s cooldown counted from the end of its 0.5 s cast at the cycle's
    ranged speed h_R (`sim/hunter/multi_shot.go:15-17`, `hunter.go:141-148`; the hardcast's `OnComplete` triggers the
    cooldown, `sim/core/cast.go:224-258`), the cast taken in the shooting spot's standing time (WA5); no Aimed Shot (`Use
    Aimed Shot = false`, `default.apl.siml:6, 31-33`).
  - No Summon Hawk, no dive, no hawks (`Use Summon Hawk = false`), with the talent taken or not; no Sniper Shot (no row
    for it in `default.apl.siml`).
- **No bow, gun or crossbow** (`p.noShots`): no Auto Shot comes, so `shot_since_swing` (`weave_common.apl.siml:20`) stays
  false after the first swing and the Weave group never walks back in (31-33): the Survival hunter then deals no melee
  and no shot (my reading, not run). The pet and the hawks (none in the weave) are as today.

### 15.4 Damage and landed hits in `partsAndHits`

With `p.survival` (15.6) and shots, the melee block and the shots' rates of `Core/Model.lua` `partsAndHits` become the
cycle's (levelling: averaged over Rapid Fire, 15.5); `phys`, `own`, `flat`, `rcrit`, `critAbil`, `hitSpecial`,
`shotHitf`, `rws` as today, and each hand's white roll by its own skill (W1D 3.4: `whiteRollMH` at `p.mhSkill` with the
main hand's miss less `p.meleeHit`, `whiteRollOH` at `p.ohSkill`; Raptor Strike, Strider Kick, Mongoose Bite, Wing Clip
and Lacerating Strikes' bleed on the main hand's entry, `hitSpecial = 1 − missMH − dodgeMH`):
- `out.auto = ((w + rapShot/14) × s + flat) / C × shotHitf × rcrit × phys × own × rws`;
- white main hand `((p.mhDPS + mapOwn/14) × p.mhSpeed + flat) × whiteRollMH × (1/C − r_R)`; off hand
  `(0.5 × (p.ohDPS + mapOwn/14) × p.ohSpeed + flat) × whiteRollOH × share_OH / C × (1 + 0.10 × PE)`;
- Raptor Strike `(swing + raptorBonus) × hitSpecial × critAbil × r_R`; Strider Kick `normHit × hitSpecial × critAbil ×
  r_K`; Mongoose Bite `perBite × r_B` (Lacerating Strikes as today);
- Wing Clip `(wingClip(lvl) + flat) × hitSpecial × critAbil × r_WC` (DB2 SpellEffect 680817 / 690318 / 690647, base points
  5 / 25 / 50 at levels 12 / 38 / 60, SpellLevels 98126 / 101362 / 101488; Effect 2 physical school with
  EffectBonusCoefficient 1, so Beastslaying's flat comes whole, `spell_result.go:449-452`, `resolve_spell.go:135-139`; the
  melee special table, `sim/hunter/wing_clip.go:18`; Savage Strikes and Predator's Edge reach it, their masks 0:66 hold
  its 0:64, `spells_auto_gen.go:16342, 38088`); armor, `own` and (raid, O7) Gift of Arthas as the other melee hits;
- Immolation Trap `5 × (trapTick(lvl) + 0.02 × rapShot) × (1 + 0.15 × CT) × (1 − trapMiss) × (1 + 0.5 × spellCrit) × own ×
  coe × r_T` (ticks: DB2 SpellEffect 691012 / 691189 / 690934 / 690935 / 691047, 21 / 43 / 68 / 102 / 138 every 3000 ms
  for 15 s at levels 16 / 26 / 36 / 46 / 56, SpellLevels 101691 / 101800 / 101722 / 101758 / 101793; 10% of the ranged
  attack power over its five ticks, read at each tick, `sim/hunter/traps.go:10-14, 65-68`, a Forever-notes value wowsims
  marks for in-game testing; the application rolls the spell table, `traps.go:71-76`: `trapMiss = max(0, spellMiss(d) −
  p.spellHit/100 − 0.05 × ST)`, Survival Tactics 19376 SPELLMOD_RESIST_MISS_CHANCE 5 / 10 by rank, SpellEffect 695689
  (whose own base points read 17), the rank curve wowsims takes `spells_auto_gen.go:39912`; the ticks crit as magic
  ticks, Attributes_8 0x200 on 14301, spell crit ×1.5, `spelldata/spell.go:368-377`, `spell_outcome.go:183-199`; Clever Traps 19239 effect 2, SpellEffect 695954 mask 0:4,
  +15% a rank, curve `spells_auto_gen.go:39908`, `talents_survival.go:228-236`; fire, no armor; `coe` 1.10 in raid, O7);
- Arcane `(arcaneBase + 0.15 rapShot) × shotHitf × rcrit × own × rws × r_A` (× `coe` in raid); Multi-Shot `(w × s +
  rapShot × 2.8/14 + 9 + flat) × shotHitf × rcrit × phys × own × rws × barrage × r_M`; Serpent Sting as 15.3;
- no Aimed (U3 = (a): Multi-Shot, its part `(w × s + rapShot × 2.8/14 + 9 + flat) × shotHitf × rcrit × phys × own × rws × barrage
  × r_M` with Gift of Arthas on its hit in raid, 18.5), no Sniper, no dive, no hawks; the pet as today. The shots are no longer cut by a time share: every
  `(1 − frac)` factor goes.
- `Model.LandedHits`: `mh.swings = (1/C − r_R) × (1 − wmiss_MH)`; `mh.specials = (r_R + r_K + r_B + r_WC) × hitSpecial`
  (all main-hand specials: `ProcMaskMeleeMHSpecial`, `raptor_strike.go:13`, `mongoose_bite.go:31`,
  `talents_survival.go:153`, `wing_clip.go:15`); `oh.swings = share_OH / C × (1 − wmiss_OH)`; `ranged.swings = shotHitf /
  C`; `ranged.specials = (r_A + r_M) × shotHitf`; `ranged.casts` = Serpent's landed applications. Immolation Trap's
  application and ticks roll no equip proc (WA9).

### 15.5 Both modes

- Levelling: the cycle and the counts at the point's speeds, every per-second quantity averaged over Rapid Fire as
  Raptor Strike is today: `(1 − rfUp) × q(rf = 0) + rfUp × q(rf = 0.40)`; Serpent Sting at `CONST.serpentUptime`; no mana.
- Raid (step 11 on): the cycle per segment with the segment's `rf`, Use buffs and shares (6.1); Serpent Sting by 15.3's
  re-cast; mana (step 12): the weave's casts join the spend with their costs (DB2 SpellPower: Raptor Strike 100, Strider
  Kick 5.81% of base mana = 99.9, Mongoose Bite 65, Wing Clip 80 (179168), Immolation Trap 245 (179926; ranks 50 / 90 /
  135 / 190), Arcane Shot 11% = 189.2, Multi-Shot 13.9% = 239.1, Serpent Sting 230 / 250); the starved regime buys them
  cheapest first (7.5), the walk, the swings and the Auto Shot cost nothing and go on; the starved income's element cost
  is the cheapest cast the weave still makes (Wing Clip 80 with a melee weapon, else Mongoose Bite 65 while Expose Prey
  opens windows, else Strider Kick 99.9) (RMD A2, A4); Judgement of Wisdom (O7) pays for every landed hunter hit, the
  weave's melee hits and Wing Clip included (5.3).
- The cooldowns' `at_range` condition (`default.apl.siml:17-18`) holds them to the next range look after 5 s; left out
  (WA8).

### 15.6 Inputs, code and UI

- Model input: the required flag `p.survival` (the Survival branch weaves) replaces the required number `p.meleeFrac`
  and the required flag `p.weave` (`Core/Model.lua` `REQUIRED_NUMBERS`, `REQUIRED_FLAGS`, the p-fields comment).
  `Player.Snapshot`: `survival = P.SurvivalBranch(points)` (step 3) as `model.survival`; no setting is read.
- `Core/Model.lua`: a local `weaveCycle(p, T, speeds)` returning `C`, `σ`, `k`, the counts of 15.3 and the parts' rates;
  `partsAndHits` uses it when `p.survival and not p.noShots`; `p.survival and p.noShots` gives no melee and no shot; not
  `p.survival` gives no melee (section 3). New `Model.Weave(p)` returns the breakdown for `/hga weights` and `/hga dump`.
  `CONST.weave = { shootSpot = 13.19, meleeSpot = 4.99, meleeRange = 5, minRanged = 5 + 8 − 4/3, runSpeed = 7,
  striderSpeed = 0.30, striderDuration = 3, windup = 0.5, reactionMin = 0.15, reactionMax = 0.35, gcd = 1.5, kickSoon =
  0.4, kickWingClip = 1.5 }`, each with its source line. `Model.Rank` tables `wingClip` and `immolationTick` from the DB2
  rows of 15.4.
- `Game/Commands.lua`: `/hga melee`, `/hga weave` and `topBranches` go (14.1); the melee line of `/hga weights`:
  Survival `ближний бой: плетение как в wowsims (SV Weave) — цикл %.2f с: выстрел и удар правой рукой, Raptor Strike раз
  в %.1f цикла, Strider Kick %.1f, Mongoose Bite %.1f, Wing Clip %.1f, Immolation Trap %.1f в минуту`; not Survival
  `ближний бой: не в счёт — больше всего очков не в Выживании`. `/hga dump` adds `weave = Model.Weave(st.model)` for
  Survival.
- `Game/Advisor.lua`: the tooltip of a melee weapon in a Survival build adds `HGA: плетение — цикл %.2f с с этим оружием
  (было %.2f с)` when the weapon changes `C` (the set's weapon run, `weaponModelFor`); Beastslaying's line (4.5) and the
  melee skill line (W1D W4) unchanged otherwise.
- `Game/Init.lua`: migration v5 (14.6). `Core/Score.lua`: the comments that name `meleeFrac` shares (`Core/Score.lua:274`
  and the `LandedHits` text) follow the weave.

### 15.7 Weights

- `Model.Weights` keeps its finite differences of `Model.Total`; the weave enters every weight through `C` and the counts.
  Consequences (my reading of 15.2-15.4): where the ranged path sets `C` (`K + ρ` above `M`), melee haste moves nothing
  but Raptor Strike's count (no white swing a second more), ranged haste shortens `R`, the windup and so `C` (more Auto
  Shots and more melee swings), and a slower two-hander of equal DPS deals more per swing at the same swing rate; where
  the swing timer sets `C` (`M` above `K + 0.35`), melee haste shortens `C`. `ctx.weaponGain` runs each set's weave with
  that set's weapons, so a two-hander and a bow are priced as the pair they make (`presets.ts:32-34`).
- `W.MH_DPS`, `W.OH_DPS`, `W.TH_DPS` (`Model.Weights`' melee setup, read only without `ctx.weaponGain`) are taken in the
  weave when `p.survival`, 0 otherwise; `W.HIT_DW` is the white swings past the specials' cap, `W.HIT_DW_MH` the main
  hand's part of it and `W.HIT_MELEE` the main hand's skill hit under the cap (W1D 3.4), all three 0 outside the Survival
  branch; expertise reaches the weave's melee hits and the pet.
- The weave has kinks (the `max` of 15.2, `min` of the slots) and, where `σ = 0`, steps of `nCycles`; a finite
  difference across one moves the weight (the steps are real wowsims behaviour where the swing timer sets the cycle).

### 15.8 Worked example (my arithmetic, for the tests)

Computed by the formulas of 15.2-15.3 with
`C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/rmdoc/tools/weave_example.py`.
Level 60, a two-hander of 3.8 s, a bow of 3.0 s, quiver 15%, no other speed, no Rapid Fire, no Quick Shots, Strider
Kick taken, Expose Prey 0, Survivalist's Discipline 0, Improved Arcane Shot 0, +3 with no hit (`q = 0.08`):
`M = 3.8`, `R = 2.6087`, `wu = 0.4348`; the fixed point gives `k = 0.5000` (2 iterations), `W_out = 1.0363`,
`u = 1.1376` (no held shot), `E[S] = 2.6087`, `W_in = 1.1113`, `K = 3.7200`, `C = 3.9700` s, `σ = 0.0577`. Counts a second:
Raptor Strike 0.1259 (every 2 cycles), white main hand 0.1259, Strider Kick 0.1259, Immolation Trap 0.0315 (every 8
cycles), Wing Clip 0.0596; the melee look casts in `f_M = 0.8615` of the cycles, so a second range slot comes with `P₂ =
(1 − f_M) × T(1.5 + 6.68/7 + 0.1317 − E[S]) = 0.1385 × 0.6067 = 0.0844` (`3 − E[S] = 0.391 ≥ 0.2`: none after a melee
cast), `n_R = 1.0844`; in them (levelling mode, `CONST.serpentUptime` 0.8) Serpent Sting 0.0580 casts (`0.8 / 15 / 0.92`),
Arcane Shot 0.1366, Multi-Shot 0.0786 (U3 = (a)); an off hand would swing in no visit (`M − K = 0.08` s). Auto Shots 0.2519
a second against 0.3833 shooting from range with the same bow. (Group 0, 18.5: the code's numbers; this example's first
version had `P₂ = 0`, `f_M` taken as 1, and Serpent Sting by the raid re-cast of step 11.)

### 15.9 Tests

- Mechanical: every test point drops `meleeFrac` and `weave` for `survival` (test_model 45 and 24 mentions, test_score
  29 and 14, test_game 24 and 4: `grep -c` at HEAD `dfa7300`; `tests/test_model.lua` `ref`, test_score's `fullP`, the
  rescore point `rescore.lua:86-87, 199`).
- Moves, measured on a copy of HEAD `dfa7300` (runner and mutants as 14.7, `tools/mutants_a.py`, `tools/mutants_b.py`,
  results `out/a.json`, `out/b.json`) by four mutations that stand for the step: the melee share set to 0 everywhere
  (354 passed / 41 failed: every test that needs melee), the share × 1.01 (381 / 14: every test that pins a number of
  the share), the weave flag's branches off (390 / 5) and `/hga melee` / `/hga weave` unreachable (392 / 3, 394 / 1); the
  union, 45 tests, each re-derived by hand from 15.2-15.4 with its name following the weave:
  - test_model: `reference BM 32/2 build: weights of the current model`; `level cap: HitCap, MobAvoid and GlanceMult at
    +4 and +5 equal +3; …`; `ranged gear hit reaches the shots, the pet and the hawks, not the hunter's melee; …`; `AP vs
    type reaches the shots, Serpent, the dive and melee, …`; `beastslaying: flat on Auto, Aimed, Multi, Sniper, Raptor,
    Mongoose, Strider, white MH and OH whole, at 0.3`; `crit suppression: the aura part at +3 alone, …`; `crit
    suppression: Savage Strikes is aura crit of the melee abilities' whole crit`; `white table: Raptor Strike takes the
    white swing it replaces at the white table's factor`; `white table: the hunter's off hand; Strider Kick and Mongoose
    Bite roll hit, then crit, uncapped`; `landed hits: the dives in the ranged specials with hawks; …`; `wowsims check:
    Raptor waits for a swing; dual-wield hit past the cap; Expose Prey in a weave`; `spec: survival melee: Strider Kick,
    Expose Prey + Lacerating Strikes, Improved Tracking`; `weapon speed: an empty main hand keeps the melee share
    (unarmed), no Raptor Strike there`; `attack speed scopes: …`; `the hunter's white swings at p.haste x p.meleeHaste x
    Rapid Fire's average`; `Raptor Strike: a 3.0 s swing gets it every 2 swings (6 s), a 2.9 s swing every 3 (8.7 s)`;
    `Expose Prey in a weave: shots open Mongoose Bite too, …`; `no bow, gun or crossbow (noShots): …`; `ranged-only
    hit: Expose Prey's shot hits in a weave land with it; …`; `ranged crit: W.CRIT_RANGED is the derivative of p.crit
    alone, …`; `weights' unit: 1 RAP where RAP adds damage, …`; `a model input every producer sets is required: …`.
  - test_score: `procs: a worn ranged weapon's proc follows the model's landed shots …`; `procs: a bow's proc at
    meleeFrac 1 is Serpent Sting's applications alone, …`; `procs: a weapon's own proc rolls on its own set's hits …`;
    `procs: a weapon's melee or any equip proc rolls on the other hands …`; `procs: Multi-Shot at levels 18-19 and Sniper
    Shot from 40 are in the ranged specials, …`; `procs: Raptor Strike moves its swing from the white swings to the
    specials; …`; `procs: a melee equip proc on armor while dual wielding …`; `equip procs by mask at a Survival point:
    …`.
  - test_game: `/hga melee says whether it counts`; `melee: SV most -> the setting; BM most -> 0; MM most -> 0`;
    `wowsims check: pet family read live and kept, weave setting, …`; `/hga weights: Lone Wolf with no pet …`; `/hga
    weights prints the attack speed inputs and weights and W.HIT_DW; …`; `dual wield past the cap at a worn bow skill off
    the level's: …`; `dual-wield hit past the cap: hands of the other kind than the worn ones …`; `one worn set with every
    mechanism: …`; `procs: a proc weapon in the off hand of a pair, …`; `procs: a two-hander's melee proc, a pair worn:
    …`; `procs: a worn set with procs on both hands, …`; `two copies of a Use trinket: …`; `weapon speed: a 2H and a 1H
    pair are priced at each weapon's own speed`; `weapon speed: taking both weapons off is a loss (the melee share stays,
    unarmed)`; `weights' unit: Lone Wolf without Summon Hawk, no pet out and no bow at 40: …`.
- Moves by reading (Survival environments whose expectations the mutations do not reach: a text, or a value taken from
  the model itself): test_game `/hga weights names the melee state; /hga dump has survival`; `mode switch: applying a
  Survival tree (TRAIT_CONFIG_UPDATED) turns the melee share on`; `procs: a two-hander's melee proc is valued on its own
  set's hits: …`; `ModelProcRates: a worn off-hand weapon at the off hand's rate; …` (the weave's off hand swings by its
  share); `Beastslaying on a bag sword raises the shots outside the Survival branch, …`; `Beastslaying's tooltip line:
  …`.
- New (each with its mutant):
  - `weave cycle: the ranged path sets it: C = E[S] + W_in + 0.25 when M ≤ K + 0.15 (15.8's numbers)` (mutants: no windup;
    no reaction after the swing; the walk at 8 yd/s; the shooting spot at 12 yd; `W_in` to 4.99 yd);
  - `weave cycle: the held shot's mean h(u) at u = 0.10, 0.25, 0.40` (mutants: no held reaction; the reaction always added);
  - `weave cycle: the swing timer sets it: C = M when M ≥ K + 0.35, σ = 0` (mutant: `C = K + 0.25` always);
  - `nCycles: ceil at σ = 0; at σ > 0 the normal smoothing just above and below an integer d/C` (mutant: `d/C + 0.5`);
  - `weave: one Auto Shot and one main-hand swing a cycle; Raptor Strike every nCycles(6)` (mutants: Auto Shots at
    `hRanged / s`; Raptor at `ceil(6 / swing)` swings);
  - `weave melee look: Strider Kick at nCycles(7.6); the bite in the slots left; the trap at nCycles(30 × (1 − 0.2 SD));
    Wing Clip the rest but before a kick due within 1.5 s` (mutants: Wing Clip before the kick too; two melee actions a
    cycle; Survivalist's Discipline left out);
  - `weave range looks: Serpent Sting first, then Arcane Shot, then the category 2 shot; a second slot by P₂` (mutants:
    Arcane before Serpent; `n_R = 1` always);
  - `weave: Strider Kick's 30% for 3 s shortens the walk out and the next walk in` (mutant: no speed);
  - `weave: no hawks, no dive and no Sniper Shot with the talents taken` (mutant: hawks counted);
  - `weave: no bow, no melee and no shot` (mutant: melee kept);
  - `weave: the off hand swings only while the swing timer holds the hunter in melee, by its share` (mutant: every
    cycle);
  - `weave: Wing Clip deals 50 + Beastslaying's flat on the special table with Savage Strikes and Predator's Edge,
    through armor; none unarmed` (mutants: no flat; unarmed Wing Clip; no armor);
  - `weave: Immolation Trap's five ticks of 138 + 2% RAP, its spell miss less Survival Tactics, ×1.5 spell crit, Clever
    Traps, no armor` (mutants: armor; ×2 crit; Survival Tactics left out);
  - `weave landed hits: white swings 1/C less Raptor Strike; Raptor, Strider, Mongoose and Wing Clip in the specials; one
    Auto Shot a cycle` (mutant: Wing Clip in the swings);
  - `weave weights: at equal DPS a slower two-hander gains while the ranged path sets the cycle` (mutant: the swings at
    the weapon's speed);
  - `weave levelling: Rapid Fire averaged over the two cycles; Serpent Sting at 0.8` (mutant: the cycle at the average
    speed);
  - `weave fixed point: Quick Shots and the kick share converge; no convergence is an error` (mutant: one pass);
  - `Snapshot: model.survival from strictly most SV points; no meleeFrac, no weave` (mutant: meleeFrac kept);
  - `/hga weights: the weave line with the cycle for Survival; "не в счёт" otherwise` (mutant: the old "% времени" line).

### 15.10 Approximations (stated, not the user's call)

- WA1 Stationary cycles at the mean reactions, with the exact expectation over the uniform reaction in the held shot
  (15.2 step 2) and in the swing's `max` (step 4); the shot path's spread inside that `max` is left out.
- WA2 `nCycles`: the sum of cycle lengths as a normal variable with `σ` from the reaction terms of 15.2 step 6.
- WA3 The in-melee waits of `weave_common.apl.siml:27, 29` (for a GCD or Strider Kick within 400 ms) are left out of
  the cycle's length; the kick counts from 7.6 s.
- WA4 One melee GCD action a visit: a visit longer than a GCD (the swing timer binding by more than 1.25 s) casts more.
- WA5 Range slots by the triangular window; the actions' cooldown restarts after a slot taken by a higher row are left
  out (the slots shared by priority, as RMD 7.5's fluid rule); Multi-Shot's cast taken in the standing time.
- WA6 Strider Kick's speed by the mean shot path.
- WA7 The off hand's share by one reaction and the mean wait for the swing timer.
- WA8 The `at_range` condition of Rapid Fire and the other cooldowns left out.
- WA9 Immolation Trap's hits roll no equip proc; its 0.5 s arming (`traps.go:20`) left out.
- WA10 Quick Shots' uptime at the cycle's Auto Shot rate, solved with the cycle.

### 15.11 U3: the weave's shared-category shot (settled: (a), section 18.5)

The agreed default "Aimed Shot in the shared cooldown (not Multi-Shot)" was taken from wowsims' BM preset (its
`turret_hawk` rotation); the later decision has the Survival branch's melee and weave follow wowsims' SV Weave preset,
whose `default.apl.siml` sets `Use Aimed Shot = false` and `Use Multi-Shot = true` (5-7) and so casts Multi-Shot at the
range look after Serpent Sting and Arcane Shot (25-30) and Aimed Shot never (31-33). Options:
- (a) Multi-Shot, as the SV Weave preset: 15.3's `r_M`; its 0.5 s cast in the standing time (WA5); 239.1 mana (13.9% of
  base mana) in raid.
- (b) Aimed Shot, as the agreed default: cast at the range look when category 2 is ready and `cast time + time to melee
  ≤ time to the next main-hand swing` (`default.apl.siml:31-33`, `${Time to melee}` = distance less 4.99 over the run
  speed, 13): at 15.8's point `2/1.15 + 1.17 = 2.91 s` against `M − E[S] − ρ̄ = 0.94 s` (my arithmetic), so Aimed Shot is
  cast only where the swing timer leaves that much room (a slow main hand against a fast bow), and its 2 s cast (hasted)
  holds the walk in.
- (c) Neither.
Settled (a) by the orchestrator under the user's rule «берем как в вов симс»; group 0 builds it (18.5).

## 16. The unarmed main hand at 1.0 s

### 16.1 Rule

The user (2026-11-17): as wowsims, the unarmed main hand is 1.0 s everywhere. wowsims' unarmed weapon: `SwingSpeed: 1`,
`NormalizedSwingSpeed: 1`, no damage (`wowsims/sim/core/attack.go:35-45`), taken by `WeaponFromMainHand` when the main
hand is empty (`attack.go:95-102`); its own comment reads "These numbers are probably wrong but nobody cares". An empty
off hand or ranged slot is no weapon there (`attack.go:104-120`: `Weapon{}`), so neither swings.

### 16.2 HGA

- `Game/Player.lua` `WeaponInputs` (`Game/Player.lua:175-200`): an empty main hand (or one with no class 2 weapon,
  `isWeapon`) takes `mhSpeed = 1.0` and `mhNorm = 1.0` (today `NO_WEAPON_SPEED` 2.6, `Game/Player.lua:158-161`, and
  `normSpeed(nil)` 2.4, `Game/Player.lua:125-132`, from vmangos' unarmed normalized speed,
  `docs/research/R3-core-formulas.md:114`). "Everywhere": the swing time of the white swings and of the weave (15.2's
  `M`), Raptor Strike's count (none unarmed), the normalized hit of Strider Kick and Mongoose Bite rank 4 (they hit
  unarmed), the main hand's proc speed (the Highborne Research Tablet's dives with no ranged weapon, 4.6.1). The
  normalized 1.0 replaces vmangos' 2.4 as wowsims' rule (the user's "as wowsims"; it lowers an unarmed Strider Kick's
  and Mongoose Bite's attack power part by 1.0 / 2.4).
- The empty off hand and ranged slot keep `NO_WEAPON_SPEED` with 0 DPS: no swing reads them (dual wield needs `ohDPS > 0`,
  the shots a bow, `Core/Model.lua` `dw`, `shoots`), so their value reaches no damage; the comment says so in place of
  "an assumption".
- An unarmed white swing deals `mapOwn / 14 × 1.0 + flat` once a second (once a cycle in the weave), the same damage a
  second from attack power as at 2.6 s outside the weave, with 2.6 times the landed hits for procs and Expose Prey.

### 16.3 Tests

- Moves, measured on a copy of HEAD `dfa7300` (`tools/mutants_a.py`, `out/a.json`): the main hand's empty speed 1.0:
  394 / 1, test_game `weapon inputs: a weapon without a parsed speed or DPS is an error; a slot with no weapon is 0 DPS at
  2.6 s`; the empty normalized speed 1.0: 394 / 1, the same test; both: 394 / 1.
- New: `unarmed: an empty main hand swings at 1.0 s with normalized 1.0; the empty off hand and ranged slot keep 0 DPS`
  (mutants: 2.6; normalized 2.4); `unarmed: the Tablet's dives with no weapons roll at 1.0 s` (mutant: 2.6).

## 17. DoT procs as wowsims prices them (U2 = (a))

### 17.1 Rule (wowsims)

- A gear proc whose spell applies a periodic damage aura is built by `NewSpellDataDamageProc` → `spellDataProcDamageSpell`
  (`wowsims/sim/common/shared/shared_utils.go:428-430, 678-693, 724-819`), e.g. Rot-Covered Harpoon 274963's Rot 1295744
  (`sim/common/forever/stat_bonus_procs_auto_gen.go:4693-4699`: a weapon proc at 1.45 a minute, EV-0122).
- The application rolls once, on the hit table of the spell's DefenseType, without crit (the damage over time "lands only
  with the hit that applies it", `shared_utils.go:771-776`; `application := damageOutcome(defenseType, true, …)`,
  730); a direct part of the same spell rolls its own hit and crit and the dot lands with it (`shared_utils.go:810-816`).
- The ticks roll no hit (`spelldata/resolve_aura.go:68-70`); they crit only where the row states PERIODIC_CAN_CRIT
  (Attributes_8 0x200), a magic tick at spell crit ×1.5, a physical tick at physical crit
  (`spelldata/spell.go:368-377`; `spell_outcome.go:171-199`); their amount is the effect's base points each period, for
  the duration over the period ticks (`resolve_aura.go:78-99`).
- A landed application while the dot runs ends it and starts a full set of ticks: the unticked rest is lost
  (`sim/core/dot.go:93-105`: `Deactivate`, then `Activate`).
- Multipliers: the attacker's (`spell_result.go:901-927`: Focused Fire, Lone Wolf, Improved Tracking, as the direct
  procs of 4.6.4), the target's: Curse of the Elements on magic schools, Gift of Arthas +8 on a physical tick
  (`spell_result.go:929-951`, no periodic exception), no armor on a physical tick ("All physical dots (Bleeds) ignore
  armor", `spell_resistances.go:25-28`). A versus bonus (Rot ×2 against Aquatic) needs a creature family HGA does not
  model (DA3); one of a creature type counts (Rend ×2 against Dragonkin: 25.2).

### 17.2 Which procs (DB2, build 70888)

My script over ItemXItemEffect → ItemEffect (TriggerType 1 equip, 2 chance on hit) → the proc spell (TriggerType 2) or
its aura 42 trigger (TriggerType 1) → SpellEffect Effect 6 aura 3 A_PERIODIC_DAMAGE on an enemy, with SpellMisc
DurationIndex → SpellDuration, SchoolMask, Attributes_8, SpellCategories DefenseType and SpellAuraOptions
(`C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/rmdoc/tools/dot_procs.py`, output `dot_procs.txt`): 98 item-proc rows, 93 chance on hit and 5 equip
auras; physical bleeds (Rend, DefenseType 2, e.g. 17730 Gatorbite Axe, 21949: 30 every 1 s for 7 s), magic poisons and
diseases (DefenseType 1, e.g. 274963 → 1295744: Nature 24 every 1 s for 7 s, can crit; 13183 Venomspitter → 18203: Nature
7 every 1 s for 15 s), drains (17484 Skullforge Brand: Shadow 21 every 1 s for 10 s) and spells with a direct part and
a dot (Fireball procs, e.g. 13348 Demonshear → 17483: Shadow, direct and 34 every 2 s for 6 s); no damage spell of them
stacks (no SpellAuraOptions CumulativeAura above 1 of DifficultyID 0). Twelve of them have a rate measured in Forever
logs in `Score.MEASURED_PPM` (6472, 6904, 9453, 12463, 12582, 12969, 13183, 13348, 13361, 13983, 17730, 274963).

### 17.3 HGA formula

- Per landed application of a dot with tick `a`, period `T`, `N` ticks, at `λ` landed applications a second of that proc
  (its rate on the set's hits, as Score.ProcRate gives it, times the application's land chance): ticks dealt before the
  next landed application `E[n] = Σ_{k=1..N} e^(−λ·k·T)` (applications as a Poisson stream, my arithmetic; today's rule
  for Lacerating Strikes, `Core/Model.lua`), damage `E[n] × a × tickCrit × mult`, `tickCrit = 1 + 0.5 × spellCrit`
  (magic, PERIODIC_CAN_CRIT), `1 + critM` (physical, the main hand's suppressed physical crit, 4.2), `1` otherwise;
  `mult = own × (magic and coe or 1)` (raid, O7), `+ gift` per physical tick (raid, O7; after the multipliers, as
  4.6.4's direct procs), no armor on a physical tick.
- The application's land chance: magic `1 − max(0, spellMiss(d) − p.spellHit/100)`; melee `1 − missChance(d, p.hit) −
  dodge` (from behind); ranged `1 − missChance(d, p.hit)` (4.6.4's tables without their crit factor); DefenseType 0 by
  the school.
- `Score.ProcValue` (`Core/Score.lua:347-356`, 4.6.4) adds the dot part: `(rate/60) × land × E[n] × a × tickCrit × mult ×
  W.EXTRA_DPS`, beside the direct part where the spell has one. `Model.ProcOutcomes` returns the application chances and
  the tick crit factors beside today's outcomes.

### 17.4 Data and the link

- `tools/gen_proc_data.py` writes a dot entry instead of leaving it out (4.6.2's "Left out" line):
  `dot = { tick = <EffectBasePointsF>, period = <EffectAuraPeriod ms>, ticks = <duration / period>, canCrit =
  <Attributes_8 0x200> }`, `avg / min / max` of the direct part or 0 when the spell has none; the checks stop on a
  duration that is no multiple of the period, an aura 3 with EffectRealPointsPerLevel (as the direct part's skip), more
  than one aura 3 on the spell, or a CumulativeAura above 1. `Game/ProcData.lua` regenerated.
- The link (`Items.LinkProcs`, `Game/Items.lua`): the tooltip texts of dots take many forms (DB2 Spell descriptions:
  "$s1 Nature damage every $t1 sec for $d", "bleed for $o1 damage over $d", "causing $s1 Shadow damage and dealing $s2
  damage every $t2 sec"; ruRU likewise), so Parse does not read them. A dot entry with no direct part links by item and
  kind: to the one effect line of the item with that kind's prefix (`ITEM_SPELL_TRIGGER_ONPROC` for "hit",
  `ITEM_SPELL_TRIGGER_ONEQUIP` for "equip") that Parse left as an effect "not counted"; none, or more than one such line,
  leaves it unlinked and unpriced, as an item newer than build 70888 (DA2). A dot entry with a direct part links by the
  direct part's mean as today (4.6.2) and brings its dot; a direct part of Variance 0 (min = max, Demonshear 13348's 150)
  shows one number and no range on the tooltip, and links by the amount its line states (24.2, DA4).
- The rate: by 18.6 (U4 = (a)): `MEASURED_PPM`, else wowsims' override row, else the DB2's rate or chance, else no proc.
- Tooltip (`Game/Advisor.lua`): `HGA: урон со временем учтён: %d ед. × %d %s за %g с (%.1f тика между срабатываниями),
  %s` with the ticks' noun in the form of their count (`A.RuPlural`: 1, 21 … «тик»; 2–4, 22–24 … «тика»; 0, 5–20, 25–30 …
  «тиков»; 24.1) and the rate text of 4.6.

### 17.5 Tests

- Moves: none measured (no mutation stands for the new part); by reading: test_game `SAME_PROC: a twin's carried rate
  names the item it is measured on; …` (Skullforge Reaver 228542) and `ModelProcRates: a worn off-hand weapon at the off
  hand's rate; …` (Stinging Viper 6472) wear real ids with dot procs and made-up direct lines: their direct lines stay
  unlinked (no direct part in their entries) and no "not counted" line is left for the dot, so by 17.4 they move none;
  the step checks it.
- New (each with its mutant): `dot proc: Rot 1295744 from the DB2: 24 every 1 s for 7 s, Nature, magic, can crit`
  (gen_proc_data; mutant: ticks from the duration only); `dot proc: E[n] = Σ e^(−λkT); a faster rate loses ticks`
  (mutant: N ticks always); `dot proc: the application rolls the table once, no crit; magic ticks ×1.5 spell crit;
  physical ticks at the suppressed physical crit, no armor, +8 Gift in raid` (mutants: crit on the application; armor on a
  bleed; Gift left out); `dot proc: a direct part and a dot priced together` (mutant: the dot dropped); `dot link: one
  unparsed "Chance on hit" line links the item's dot entry; two lines leave it unlinked` (mutant: the first of two).

### 17.6 Approximations

- DA1 Applications as a Poisson stream for the lost ticks (wowsims runs them as they come), past the proc's internal
  cooldown at its rate without the cooldown (25.3).
- DA2 A dot entry with no direct part links by the item's one unparsed proc line of its kind.
- DA3 Versus bonuses of a creature family are left out (those of a creature type count, 25.2).
- DA4 An entry of a fixed direct damage (min = max), with a dot or without, links by the item's one unparsed proc line of
  its kind that states its amount as damage, a line no other such entry claims (24.2).

Built in step D (section 22).

## 18. Group 0: what groups A-C left open, settled

Group 0 runs after group C (HEAD `74fb0d2`) and before steps 11-14 and D. The orchestrator settles the open points by the
user's rule «берем как в вов симс»: as wowsims; where wowsims states nothing, HGA's behaviour stays and the section says
so. U3 = (a) and U4 = (a) (section 13); R2-F1 part 2 (a gain credited to a bag weapon) stays as it is (Score.Evaluate).
Each point names its tests and their mutants; "my arithmetic" and "my reading" as in section 0.

### 18.1 The probe battery at HEAD: every failing line by kind

The batteries of group C (`w56/battery.sh` for a Survival tree, `battery_bm.sh` for the BM build; copies with the
probes' expectations by kind in `C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/g0`,
`g0lib.lua`, the classification `classify.py`, `classify_sv.txt`, `classify_bm.txt`) gave 901 failing lines for the
Survival tree and 142 for BM at HEAD. Each is one of these kinds (the run of the same configuration on the fixed env with
the probes' expectations by kind says which):

| Kind | What | Verdict | SV lines | BM lines |
|---|---|---|---|---|
| A | the Survival weave with a bow takes the off hand off: behind a main hand whose swing the walk sets, the off hand swings in few visits (its swing at least half its swing time after the attack starts on arrival, `attack.go:806-819, 869-871`; `start_attack if in_melee`, `weave_common.apl.siml:25`) while its presence gives every main-hand white swing 19% more miss (`spell_outcome.go:852-871` takes `GetPhysicalMissChance`, `:546-554`, with `IsDualWielding` = an off hand of a swing speed, `attack.go:560`; the specials take none, `:569-571`) | a genuine result of wowsims' rules | 544 (sweep 162, scen 324, cross2 12, cross3 12, edge 2, agree 30 with the plan over one candidate holding the removal, procs_agree 2 whose HEAD gain 152.2 holds B2 too: 2.78 on the fixed env) | 0 |
| B1 | the probes' env gave 27 Survival points at levels 3 and 8, where a hunter has none (its first point comes at 10; test_game's `melee: below level 10 (no points) weaves not` empties the ranks): an impossible weave | an artifact of the probes' env | 252 (sweep 36, scen 72, cross5 144) | 0 |
| B2 | the test env kept every weapon line at 215 at any level: at 60 a worn main hand and bow 85 points below the level's 300 lower the pet's melee and ranged crit branches 3.4% each (`sim/hunter/pets.go:147-153`), and an empty main hand has no bonus (`weapon_skill.go:17-19`, `character.go:612-618`), so it gave the pet its whole melee branch (the "+49.3" of group B) | the rule is wowsims' (a); its size here an artifact of the env (b) | 54 (sweep 18, scen 36) | 56 (sweep 18, scen 36, procs_agree 2) |
| C1 | a tie between the worn hands and a removal (hit past the cap, no melee), the probe comparing the hands' identity | the probe's expectation | 1 (edge) | 2 (edge) |
| C2 | a bag copy of a worn one-hander that is not unique pairs with its original (two copies worn: a new set, worth its own gain) | the probe's expectation | 36 (cross5) | 84 (cross5 72, cross2 6, cross3 6) |
| C3 | a bag copy of the worn main hand credited with the worn hands' own removal of kind A (Score.Evaluate's attribution, R2-F1 part 2 kept) | A, credited by the kept rule | 12 (cross2 6, cross3 6) | 0 |
| C4 | the edge variant with an empty main hand and an off-hand weapon: the weave swings the weapon in the main hand (unarmed: 1.0 s at 0 DPS, section 16) | the probe's expectation | 2 (edge) | 0 |

No line is a bug of the addon. The fixes: the test env's weapon lines follow the level (`tests/test_game.lua` env: 5 x the
level read at the call, the most a trained line reaches and its maxRank, the Forever client's
`SKILL_RANKS_PER_SKILL_LEVEL = 5` and `GetExpectedSkillForLevelOffset`, `Camelot/SkillsFrame.lua:1, 40-42`; the skill
wowsims leaves a line it is not given, `weapon_skill.go:56`; Polearms only from 20, DB2 SkillRaceClassInfo 136 MinLevel 20
for the hunter). No local Forever source states the rank of a line below its maximum (a line trained late), so the env
takes the maximum; Dual Wield (SkillRaceClassInfo 132, MinLevel 20) and Mail (145, MinLevel 40) are proficiencies the env
keeps at any level, as before. The probes' copies (scratchpad, not the repository): no talent point below 10, the
weapon skills at 5 x level (a polearm a staff below 20), the removed settings gone, and the expectations by kind:
BestHands of the worn hands is the worn hands or a gain of kind A or C4, verified (the weapon run's gain in the melee
part alone for A), the plan without candidates holds exactly those rows; a bag copy's delta is 0, the worn hands' own
gain, or a pair of copies; `casts_share` takes the inputs the model requires now. On the fixed env with these
expectations every battery line passes (SV and BM: sweep 252, cross5 252, procs_agree 24, scen 768, agree, edge, cross2,
cross3 all OK; on the final tree of group 0, after U3 and U4, the probes verify 424 gains of kind A, one of kind C4 and
the copies' attribution and pairs, with no failing line). Tests (each with its mutant, all killed): test_game `env: the weapon lines follow the level; at 60 the worn
main hand at the level's skill stays, one 85 points below comes off for the pet's melee crit (wowsims)` (mutants: the
lines at 215; no Polearms gate; the pet's melee branch without the main hand's skill; maxRank alone following the level);
test_model `weave: an off hand that swings in no visit still gives the main hand's white swings the dual-wield 19% more
miss; taking it off gains` (mutants: no dual-wield miss on the main hand; 20% in place of 19%).

### 18.2 The swap banner and `/hga swap` with a plan that takes an item off

Group A's open point: a plan whose rows only take items off (kind A of 18.1, the off hand in the weave; an empty main
hand for the pet's melee crit) hid the banner, and `/hga swap` said there was nothing to put on, though the plan gains.
Taking an item off is part of what to wear (the user's "показать что одеть"):
- `A.Plan` marks a row that takes its item off by itself, `row.takeOff`: a slot the plan empties that the game does not
  empty on its own when another row goes on. The game takes the off hand off when a two-hander goes into the main hand,
  and a worn two-hander off when an item goes into the off hand (the rows Swap already says so of: «снимется само: эту
  руку займёт двуручное», «… правая останется пустой»), and a slot whose worn item another row moves to another slot
  (`row.movesTo`: a weapon to the other hand, 18.1's C4) loses it by that row, which picks it up there (`Swap.EquipRow`,
  as `EquipmentManager_EquipInventoryItem`, `Mainline/EquipmentManager.lua:118-131`); every other emptied slot is a
  take-off row. `plan.takeOffs` counts them; a take-off row's key is `slot=-<link of the item taken off>`, so another item
  to take off is a new suggestion for the ×. The moved item's old slot has no button: «освободится само: вещь перейдёт в
  слот «<slot>»» when the slot it goes to is empty now, else «перейдёт в слот «<slot>»; что окажется здесь, покажет
  обновлённый список» (the item that slot holds now lands somewhere the game decides, and the next plan shows it).
- `Swap`: a take-off row counts as a row to act on (the banner shows, the × and `/hga swap` treat it as any row); the
  banner's title is «Можно снять вещь с выгодой» («Можно снять вещи с выгодой: N») when the plan only takes items off;
  the row names the item, says «снять в сумку — рука останется пустой» (a slot outside the hands: «… слот останется
  пустым»), shows its gain (or, as part of a hands unit whose gain is in the other row, «одна замена вместе с другой рукой
  — прирост в её строке») and has a «Снять» button: `Swap.UnequipRow` takes the item off into the first free slot of a bag
  of family 0, the backpack first (Blizzard's EquipmentManager, `Mainline/EquipmentManager.lua:18-43, 147-190`:
  `PutItemInBackpack`, else `PutItemInBag` with the bag's inventory slot, `C_Container.ContainerIDToInventoryID`; a quiver
  or an ammo pouch, a family other than 0, takes none). Combat, an item on the cursor, a worn item changed since the plan,
  a locked slot and no free bag slot are said in chat and nothing is picked up; an item the game does not give to the
  cursor is said in chat and nothing is put away. A take-off row without its item (or an equip row without its item) is
  no row the panel makes: an error. `/hga swap` with nothing to do says «нечего надеть или снять с выгодой».
- Test: test_game `swap banner: a plan that only takes the off hand off shows; its row says «снять в сумку» with a «Снять»
  button that puts the item in a bag` (the env's Survival tree with nothing in the bags; the backpack, a bag past a
  quiver, no room, a changed worn item, combat, an item on the cursor, a locked slot, an item not picked up, a row without
  its item, the × and `/hga swap`; and a bag two-hander whose off-hand row has no button); test_game `swap banner: a worn
  weapon the plan moves to the other hand leaves its slot by that row: no take-off row, no «Снять»` (C4's empty main hand;
  a weak sword in the main hand). Mutants (23, all killed): no take-off in the off hand; only rows with an item to put on
  count; no take-off title; a quiver taken; no room check; the key without the item; the two-hander's off hand a take-off
  row; no check of the worn item; the button equips; a worn two-hander's main hand a take-off row; the row's text; the move
  not seen; takesOff without `movesTo`; `moveDisplaces` always false; one text for both moves; the move row's hint
  dropped; a «Снять» button on the move row; no combat check; no cursor check; no lock check; no check of the pick-up; the
  take-off row's and the equip row's missing item a quiet return.

### 18.3 The weave: the negative weight of haste rating, the off hand at Rapid Fire's speed, Serpent Sting's uptime

- **The negative `W.HASTE_RATING` at group C's level-60 Survival point** (−3.90; `W.RANGED_HASTE` the same, `W.HASTE` and
  `W.ATTACK_SPEED` +8.56 with the pet's part) is a property of wowsims' weave, not of the smoothing. The point's cycle
  outside Rapid Fire is C = 3.8006 s (M = 3.6 s, K = 3.5506 s, E[S] = 2.4471 s), and Strider Kick waits for the melee look
  whose cooldown is within 0.4 s (`kick_soon`, `weave_common.apl.siml:13-19`): 8 − 0.4 = 7.6 s, so a cycle of 3.8 s or more
  kicks every second cycle and a shorter one every third. 2 × 3.8006 = 7.6012 s sits on that edge: with the cycles' spread
  (σ = 0.0577 s, WA2) the kick share k is 0.4010 there. 0.5% more haste rating shortens the shots and the cycle to
  3.7893 s, k falls to 0.3841 (Strider Kick −3.9% a second), its looks go to Wing Clip (+24%, a weaker hit), and the melee
  part loses 0.638 DPS while the Auto Shots, Arcane Shot and the trap gain 0.414 (my arithmetic from `Model.Weave` and
  `Model.Parts`, `C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/g0/haste60.lua`). Over haste rating 0-10% the total falls
  from 627.57 to 627.04 at 2% and rises from 3% on, the kick at every third cycle (k = 1/3) from about 5%. These are group
  C's numbers, before U3 (18.5): with Multi-Shot in the range looks the point's total is 663.72, falls to 663.48 at 1% and
  rises from 2% on (663.59 at 2%, 664.54 at 3%), C and k as above, Multi-Shot +0.048 DPS at +0.5%, and `W.HASTE_RATING`
  is −2.70 (`W.RANGED_HASTE` the same; my runs of `rm/rev-g0/scripts/haste_scan.lua` and `g0/refpoints.lua` on the
  final tree of group 0's review). The smoothing
  (WA2) sets only how wide the step is (about ±2% haste); the step itself is wowsims' rule, so the weight stays: a
  finite difference across a real step (15.7). Test: test_model `weave: at the edge of Strider Kick's 7.6 s (2C near
  7.6 s) more haste rating moves kicks to every third cycle and lowers the total` (15.8's point with a 2.85 s bow and a
  3.7 s two-hander, C 3.83 s; mutants: the kick at 8 s, without `kick_soon`; the kick's count at σ 0).
- **The off hand's half swing inside Rapid Fire** (group A's open point): starting the melee attack puts the off hand's
  swing half its swing time out at the unit's whole melee speed (`attack.go:814-816`, `TotalMeleeHasteMultiplier`,
  `unit.go:610-612`), which holds Rapid Fire's aura 319 (`parse_effects_table.go:364-366`, MeleeSpeedMultiplier). So
  `weaveParts` takes `ohSwing = p.ohSpeed / (meleeSpeed × (1 + rf))` per cycle (15.3 above). Test: test_model `weave: the
  off hand's half swing at Rapid Fire's melee speed: inside Rapid Fire it swings in part of the visits` (level 60, a 5.0 s
  main hand and a 1.8 s off hand: no swing outside Rapid Fire, a share strictly between inside it; mutant: the off hand at
  the permanent speed).
- **Serpent Sting in the levelling weave without the shots' hit** (group A's open point): kept, as wowsims. The SV Weave
  rotation casts Serpent Sting while its dot is down (`default.apl.siml:25`), so a sting that misses is cast again at the
  next range look: a miss costs a cast (its range look), not uptime. The levelling weave's `CONST.serpentUptime` is the
  landed sting's uptime (its damage without `shotHitf`, its casts that over `shotHitf`), pinned by test_model `weave
  levelling: …; Serpent Sting at 0.8` ("no hit factor") and `weave range looks: …` (the casts over 0.92). The turret
  build's levelling Serpent (0.8 × `shotHitf`) is HGA's levelling estimate and stays; the raid fight derives both from
  the re-cast (6.4, step 11).

### 18.4 The strikes' weapon: a fishing pole or a miscellaneous weapon takes none

Group A's open point: the weave's `armed` flag (`not p.unarmed`) let a fishing pole or a miscellaneous weapon in the main
hand take Raptor Strike, Wing Clip and Mongoose Bite. Their SpellEquippedItems rows (Forever DB2 build 70888,
`db2_R5-weapons-gear/SpellEquippedItems.csv`: 166357 / 175525 Raptor Strike 2973 / 14266, 166400 / 174762 Wing Clip 2974 /
14268, 254988 / 254990 Mongoose Bite 1495 / 14270) need EquippedItemClass 2 with EquippedItemSubclass 173555: bits 0, 1, 4,
5, 6, 7, 8, 10, 13, 15, 17 (axes, two-handed axes, maces, two-handed maces, polearms, swords, two-handed swords, staves,
fist weapons, daggers, spears), not 14 (miscellaneous) and not 20 (fishing poles); wowsims checks a spell's weapon
requirement before the cast (`sim/core/spelldata/resolve_spell.go:281-283`, `sim/core/equip_requirement.go:26-31`). So
`Player.WeaponInputs` gives `unarmed` for a main hand without a weapon of that mask (`STRIKE_WEAPON`); such a weapon still
swings at its own speed and DPS (`mhSpeed`, `mhDPS`), and Strider Kick (no row) and Mongoose Bite rank 4 (no row) need
none. `/hga weights` says «без Raptor Strike (в правой руке нет оружия для него)». Test: test_game `weapon inputs: a
fishing pole or a miscellaneous weapon swings at its speed and DPS but takes no Raptor Strike, Wing Clip or Mongoose Bite`
(mutants: `unarmed = not armed`; the fishing pole in the mask; the miscellaneous weapon in the mask; swords left out); the
test also checks every weapon subclass 0-20 against the bits of 173555 (group 0's review; mutants, all killed: daggers,
fist weapons, two-handed axes, polearms, two-handed swords or spears left out; miscellaneous or guns put in).

### 18.5 U3 = (a): Multi-Shot in the weave's range looks

- Rule (wowsims' SV Weave preset): `default.apl.siml` sets `Use Aimed Shot = false`, `Use Multi-Shot = true` (5-7) and casts
  Multi-Shot at the range look after Serpent Sting and Arcane Shot (25-30), Aimed Shot never (31-33). Forever has one rank
  of Multi-Shot, 2643, learned at 18 (wowsims `sim/hunter/spell_data_auto_gen.go:379` `Ranked(2643)`, SpellLevel 18,
  `spells_auto_gen.go:1796`): the normalized ranged weapon hit + 9 (`multi_shot.go:20`, `hunter.go:20`
  `normalizedShotBonus`), the shared 6 s category 2 cooldown, a 0.5 s cast (`multi_shot.go:15-17`, EV-0069) that
  `ProcMaskRangedSpecial` makes a ranged ability (`:14`).
- HGA (`Core/Model.lua` `weaveParts`, `CONST.weave.multiCooldown`, `multiCast`): the range looks' third action, `r_M =
  max(0, min(1 / (nCycles(6 + 0.5 / h_R, C_R, σ) × C_R), 1/C_R − r_S − r_A))` from 18 (the cooldown starts when the cast
  completes, `sim/core/cast.go:224-258` `Hardcast.OnComplete` → `triggerCooldown`, as the turret's `6 + 0.5 / hRanged`;
  `h_R` the cycle's ranged speed, the quiver, Quick Shots, haste and Rapid Fire in it, `hunter.go:141-148`
  `hasteRangedCast`, `unit.go:599-601`); its part `(w × s + rapShot × 2.8/14 + 9 + flat) ×
  shotHitf × rcrit × phys × own × rws × (1 + 0.05 × Barrage) × r_M`, the turret's Multi-Shot formula, with Gift of Arthas on
  its hit in raid mode (`gift × shotHitf × rcrit × r_M`: the open point that Gift of Arthas on Multi-Shot was unreachable
  is closed, the weave casts it at 60); its landed hits in the ranged specials (a ranged ability's equip proc, a ranged
  weapon's chance on hit) and in Expose Prey's x (mask 0x154 holds the ranged abilities). `out.multi` carries it; its cast
  stays in the standing time (WA5), so the cycle does not move. Raid mode's mana (step 12) adds its 239.1 a cast.
- The worked example 15.8 is the code's again (P₂ 0.0844 with `f_M` 0.8615; Serpent Sting by the levelling 0.8; Arcane
  Shot 0.1366, Multi-Shot 0.0786 a second), pinned by test_model `weave cycle: …` and `weave range looks: …`.
- Tests moved (6, each re-derived): test_model `Expose Prey in a weave: …` (Multi-Shot's landed hits in x), `weave range
  looks: Serpent Sting first, then Arcane Shot, then Multi-Shot; a second slot by P2` (the rate in the looks left and its
  hit against Auto Shot's: `(53 × 3 + RAP × 2.8/14 + 9) / ((53 + RAP/14) × 3)` a hit, my arithmetic; none before 18),
  `weave: no hawks, no dive and no Sniper Shot with the talents taken` (Multi-Shot is cast), `weave landed hits: …; Arcane
  and Multi-Shot`; test_score `procs: a bow's proc rolls on the shots, …` (the ranged specials hold Multi-Shot); test_game
  `tooltip placement: …` (the Survival case wears a pair without stats: with Multi-Shot the env's sword's +22 attack power
  and the off-hand sword's +4 Agility now outweigh the off hand's dual-wield miss, so the weave keeps them).
  New assertions: test_model `raid Gift of Arthas in the weave: …` (Multi-Shot's gift at the shots' outcome), `weave range
  looks: …` (Multi-Shot from 18, none at 17). Mutants (7, all killed): no Multi-Shot; Multi-Shot before Arcane Shot;
  Multi-Shot without its +9; Multi-Shot out of Expose Prey's x; Multi-Shot out of the ranged specials; no Gift of Arthas on
  it (raid); Multi-Shot from 20. Group 0's review: test_model `weave range looks: …` (a 3.42 s bow at 15.8's point,
  C_R 3.02 s: two range looks pass 6 s but not 6.43 s, so the cooldown takes three looks) and `weave Multi-Shot's hit:
  Barrage, Focused Fire, Ranged Weapon Specialization and Beastslaying's flat reach it` (a cast's damage ×1.15, ×1.02,
  ×1.05; the flat adds to a Multi-Shot what it adds to an Auto Shot, Barrage on it too). Mutants (7, all killed): the
  cooldown from the cast's start; the cast unhasted; a 1.0 s cast; no Barrage; no flat; no Ranged Weapon Specialization;
  no own damage. The reference points do not move (my runs of `g0/refpoints.lua`: at L44 SV and L60 SV the looks left
  bind Multi-Shot, not its cooldown); at the reviewer's L60 SV point with a 3.0 s bow and quiver 13%
  (`rm/rev-g0whole/scripts/multicd.lua`) Multi-Shot falls from 33.752 to 33.584 DPS (Rapid Fire 7.058 → 6.581 a minute).

### 18.6 U4 = (a): no proc rate is made up

- Rule (wowsims): a rate the game files do not state takes a per-item carry-over value
  (`docs/rulings/R-0046-unstated-rate-carryover-todo.md`), and a proc whose entry states no rate registers nothing: "no
  rate is made up for it" (`R-0047-hand-proc-needs-entry-rate.md`). wowsims' rates outside the game files are its
  override data, `tools/database/overrides/weapon_procs.go` (`WeaponProcs`: 95 rows a rate, 22 more commented out "waiting
  for PPM data", by ItemID and the item effect's SpellID, each with its Source: "EV-<n>" a measurement on Forever,
  "vanilla-carryover" / "tbc-carryover" a carried-over rate unchecked in Forever) and `spell_overrides.go` (`Spells`: the
  PPM and ProcChancePct rows of a spell, an equip aura's rate where the game files state none); `enchant_procs.go` holds
  permanent enchants' rates (HGA prices no enchant proc), `hand_triggers.go` and `extra_spells.go` no rate.
- HGA (`Score.ProcRateSource`, `Score.ProcRate`): a proc's rate is the item's `MEASURED_PPM` (per minute at the speed of
  the hand that hits; first, as before for a chance on hit, and now before a stated rate of an equip aura too: no item
  has both, the EV rows and `MEASURED_PPM` agree, test below); else wowsims' override row of its linked entry
  (`Game/ProcData.lua` `ppm` / `chance` with `source`, written by `tools/gen_proc_data.py --overrides`: a chance-on-hit
  entry takes its item's WeaponProcs row, an equip aura of no stated rate its item's WeaponProcs row or its spell's PPM /
  ProcChancePct row; an override on an entry that states a rate stops the generator, as wowsims' own does); else the
  DB2's own SpellProcsPerMinute or ProcChance 1-99 of a linked equip aura. A proc with none of them is not priced (0
  procs) and its tooltip line says «HGA: частота эффекта при попадании не замерена — не учитывается (как в wowsims)» (and
  nothing of an outcome by the school its text names, which only a priced unlinked proc says); a carried-over row's says
  «… — перенос из классики (данные wowsims), в Forever не проверено» for a "vanilla-carryover" row and «… — перенос из TBC
  …» for a "tbc-carryover" one (wowsims `weapon_procs.go:13`: the Source names the version the rate comes from; Darkmoon
  Card: Maelstrom 19289 and 20147 carry The Burning Crusade's), a measured row's «… — замер по логам (данные wowsims,
  EV-<n>)»; any other source is an error (the rate rows of build 70888's overrides name only these). The regenerated `Game/ProcData.lua` (DB2 build 70888 with wowsims' overrides) gives 53
  of its 309 entries a rate with a source; 67 override rows name no written entry (a proc of no direct damage, a skip).
- Twins: `Score.SAME_PROC` / `CARRIED_PPM` (a twin of a measured weapon taking its rate at the same speed) go: wowsims
  has no row for them (228542, 228573, 228029, 209436), so a twin's proc is not priced.
- The setting goes: `/hga ppm` (any other text prints the four-line help), `ns.DEFAULTS`, `ns.settings`, the
  `procsPerMinute` of ctx and of `tools/preraid/rescore/rescore.lua`; `Game/Init.lua` removes the saved settings table
  whole at load, whatever version saved it (v5: HGA keeps no setting; the banner's position and the other saved data
  stay). `/hga dump` loses `settings`.
- Tests moved (33): test_score `proc adds extra dps value: …`, `a melee weapon proc fires only on its own hand's melee
  hits` (a chance on hit with a carried-over rate, `onHit`), `errors: …; an unmeasured rate prices nothing`, `stats-gear-4:
  a measured proc rate; an unmeasured one prices nothing; …`, `stats-gear-4: an equip proc on armor rolls on the hits its
  text names, …`, `procs: Serpent Sting's applications …`, `procs: a bow's proc rolls on …`, `procs: a weapon's own proc
  rolls on its own set's hits …`, `procs: a weapon's melee or any equip proc …`, `procs: a melee equip proc on armor while
  dual wielding …`, `procs: the Highborne Research Tablet …`, `procs: a held-in-off-hand item …`, `equip procs by mask: …`
  (each made-up item a measured 1.5 for its test, `measuredFor`: the numbers stay), `equip proc rate: MEASURED_PPM, else
  PPM or chance 1-99 (an override row's or the DB2's), else none; …`, `Game/ProcData.lua: …` (13040, 260205 and 17753 take
  their rows; the carried-over 810; every EV row with a measured item agrees with `MEASURED_PPM`: 17), `SAME_PROC: …`
  replaced by `U4: a twin of a measured weapon takes no carried rate …`, `CarryRates: …` removed; test_game `settings v4:
  …` and `settings v5: …` merged into `settings: the saved settings table goes whole, …`, `target: …`, `hit cap: …`,
  `banner: …` (an old saved key in the saved data), `slash commands: target, melee, weave, cap, ppm, min and banner print
  the help and change nothing`, `help: the four lines …`, `slash commands run`, `procs: a proc weapon in the off hand of a
  pair, …`, `procs: a bag bow's proc …`, `procs: a two-hander's melee proc, a pair worn: …`, `procs: a two-hander's melee
  proc is valued on its own set's hits: …`, `procs: the tooltip's rate says …`, `procs: a worn set with procs on both
  hands, …` (the env's made-up proc items a measured 1.5, `G.measuredPPM`), `one worn set with every mechanism: …`,
  `SAME_PROC: …` replaced by `U4: a twin of a measured weapon takes no carried rate: not priced, its tooltip says the rate
  is unknown; a wowsims carry-over row prices a proc and says so` (the Bow of Searing Arrows 2825, 3.35 a minute). Python:
  `tests/test_gen_proc_data.py` 43 → 54 (the override files read as data, a commented row left out, the rows attached, the
  stops). Mutants (all killed): Lua 10 (an unknown rate at 1.5; the DB2's rate before the measured one; no override rate;
  the link without its source; the carry-over text; the hits checked after the rate; the saved settings kept; the unknown
  text; an override chance read as none; a chance on hit's rate left unlinked), Python 5 (commented rows read; no stated-rate
  check; no double-row check; unused rows unreported; a chance row read as a rate).

### 18.7 A set's procs at its own main hand's table

Group B's open point: `ctx.procOutcome` was computed once at the worn main hand's skill, so a set with another main hand
priced its procs on the worn hand's table, an approximation W1D and this design did not name. wowsims rolls a proc
spell's melee and ranged tables on the main hand's entry of the weapons the hunter holds (`sim/core/target.go:606-615`
`Hand`; the attack tables are rebuilt on every weapon change, `sim/core/weapon_skill.go:85-94`
`UpdateAttackTableWeapons`), so each set's procs take its own main hand's skill. `Advisor A.State` gives
`ctx.procOutcomeFor(mhSkill)`, `Model.ProcOutcomes` at the model point with that skill (one run a skill, the worn skill
giving `ctx.procOutcome` itself, which `/hga dump` keeps), and `Score.SetValue` prices a set's procs at
`ctx.procOutcomeFor` of the set's `Score.MeleeSkills` main hand; the set's other stats stay out of its procs (A6). Test:
test_game `procs: a set's procs roll at its own main hand's skill (the dagger at 195 of 215), not the worn one's`
(mutants, all killed: the worn outcome; the outcome run without the set's skill; the off hand's skill).

### 18.8 Spell hit and spell crit get their weights

Group A's open point: since the weave's Immolation Trap reads `p.spellHit` and `p.spellCrit`, an item's or a set bonus's
SPELL_HIT and SPELL_CRIT (Game/SetData.lua gives them to several sets, often next to HIT and CRIT) had no weight. wowsims
rolls the trap's application on the spell table and crits its ticks at spell crit ×1.5 (`traps.go:71-76`,
`spelldata/spell.go:368-377`), so both count:
- `Model.Weights`: `W.SPELL_CRIT` the value of 1% more spell crit (`Model.ApplyStats` SPELL_CRIT → `p.spellCrit`; the model
  is linear in it); `W.SPELL_HIT` the value of 1% below the trap's cap, taken at `p.spellHit = 0` as `W.HIT` is;
  `Model.TrapHitCap(mobDiff, Survival Tactics)` = the spell miss (17% at +3, 4% + 1% a level below) less 5% a rank, floored
  at 0. Both are 0 outside the Survival weave.
- `Score.SetValue` prices a set's spell hit (its items' and set bonuses' SPELL_HIT on `ctx.baseSpellHit`, the live spell hit
  less the worn set's: `Player.Snapshot` `gearSpellHit`, `Advisor A.State`) as `W.SPELL_HIT × min(spell hit,
  ctx.spellHitCap)`, never in `ItemValue`'s stat loop; a Use buff's SPELL_HIT over its uptime the same way; SPELL_CRIT at its
  weight through the stat loops. `rescore.lua`'s ctx takes both. The magic procs keep the worn point's spell table (A6).
- Tests: test_model `weights: spell hit below the trap's cap and spell crit price Immolation Trap in the weave; none outside
  it`; test_score `spell hit up to the trap's cap on the whole set; spell crit at its weight`; test_game `spell hit:
  ctx.baseSpellHit is the live spell hit less the worn set bonus's; the trap's cap 17% at 60`. Mutants (9, all killed): no
  cap; SPELL_HIT in the stat loop; a set bonus's spell hit left out; the weight taken at the model point; the cap without
  Survival Tactics; the worn set bonus's spell hit left in the base; the base the live spell hit; no SPELL_CRIT weight; the
  items' spell hit left out. Group 0's review: the test_score test prices a Use buff of SPELL_HIT 10 for 15 s of 90 (Nat
  Pagle's Broken Reel 231271's, `Game/UseData.lua`) at its uptime of the 1% left under the cap (mutant, killed: the Use
  buff's spell hit priced linearly).

### 18.9 The texts and data of the open points: the tooltip outside the Survival branch, API_MAP, the raid mode line, the dragonkin line, CONST.raid

- **The melee skill line outside the Survival branch** (group B's open point): «ближний бой не в счёт» said the hand's
  skill reached nothing, while the main hand's skill still moves the pet's melee crit branch (0.04% a point below the
  level's maximum, `sim/hunter/pets.go:147-153`; the pet takes the higher branch) and the main hand's entry of a proc's
  tables (18.7). The line now says what it reaches: the main hand «навык %s %d/%d — своего ближнего боя нет (не ветка
  Выживания); правой рукой он двигает ветку ближнего боя крита пета (%+.2f%%, в счёт, пока она выше ветки дальнего боя) и
  таблицу эффектов при попадании», the off hand «… в левой руке он ни на что не влияет», a line no hand holds «навык %s — ни
  одна рука набора не держит оружие этой линии: не в счёт». Tests moved: test_game `melee skill: each hand at its own line,
  …` (the texts of the gloves and the ring) and `tooltip: a melee weapon in a Survival build names its miss, glance and
  crit; out of Survival what its hand's skill reaches` (the bag sword goes into the off hand). Mutants (3, all killed): the
  main-hand text dropped; the pet's 0.2% a point; the off hand's text dropped. Group 0's review adds to test_game `tooltip:
  a melee skill item of several lines …` a ring of +7 Axes (no hand holds the line: «… — ни одна рука набора не держит
  оружие этой линии: не в счёт») and a ring of +12 Swords that takes the main hand to 217 of 215 (the pet's branch moves
  only up to the maximum: +0.40%, not +0.48%); mutants, killed: the text of a line no hand holds dropped; the pet's branch
  past the maximum.
- **`Items.API_MAP` melee keys** (group B's open point): the Forever client names a stat key for every weapon line,
  `ITEM_MOD_<LINE>_SHORT` (GlobalStrings 58882-58908: TWOHANDED_AXES, TWOHANDED_MACES, TWOHANDED_SWORDS, AXES, BOWS,
  CROSSBOWS, DAGGERS, DUAL_WIELD, FIST_WEAPONS, GUNS, MACES, POLEARMS, STAVES, SWORDS, and 58910 THROWN); the Forever API
  docs give `C_Item.GetItemStats`' table as a LuaValueVariant with no key list (`ItemDocumentation.lua:1004-1017`), and the
  in-game dumps of 2026-11-12 show its keys are these `ITEM_MOD_*_SHORT` names (no item with a weapon skill was dumped).
  The ranged lines were mapped from the start; W1D 3.4's "no source names the keys" is answered by GlobalStrings, so the
  ten melee lines map to `Score.MELEE_SKILL`'s stats as well (an API value with no tooltip line is taken and noted, one the
  tooltip states is checked). Test: test_game `GetItemStats: the melee weapon skill keys map to Score.MELEE_SKILL's stats`
  (mutants: SWORDS unmapped; FIST_WEAPONS to another stat).
- **The raid mode line against section 8**: section 8 named the step-11 line (the fight); step 10 built the averaged raid
  target's line with the cap 14.5 asks for. wowsims states no UI: HGA's line stays, and section 8 now names both (above).
- **The dragonkin line «учтено полностью»** (made up in step 10): wowsims states no UI; it stays as HGA's text, now
  written in 4.5 (above).
- **`CONST.raid` holds numbers, not the flags 5.3 named**: the user's answer O7 = (a) turns every preset debuff on, so a
  flag nothing can switch off adds nothing; `CONST.raid` keeps each debuff's value with its DB2 row (wowsims' preset names
  the debuffs, `defaults.siml:46-48`, and its spell data gives their values). Kept; 5.3 now says so.
- **Gift of Arthas on Multi-Shot**: reachable with U3 (18.5), built there.

### 18.10 Group 0's review: what changed, and the one point left open

- **A worn weapon the plan moves to the other hand** (18.2): its old slot is no take-off row (`row.movesTo`), no button;
  `Swap.UnequipRow` and `Swap.EquipRow` raise on a row without its item.
- **Multi-Shot's cooldown in the weave counts from the end of its cast** (18.5, `sim/core/cast.go:224-258`).
- **The tooltip's proc lines**: a "tbc-carryover" row says «перенос из TBC» (18.6); an unpriced unlinked proc says only that
  its rate is unknown (4.6.2, 18.6).
- **Tests pinned**: Multi-Shot's hit factors (18.5), the strikes' weapon mask (18.4), a Use buff's spell hit (18.8), the
  skill line texts (18.9), the take-off row's refusals (18.2), the tooltip's source texts (18.6), and in
  `tests/test_gen_proc_data.py` a Spells row on equip auras alone, an ICDMs row not read, a WeaponProcs row on an equip
  aura that states a chance stopping the generator.
- **Open, not built: wowsims' ProcChanceAlways auras** (built by group G, 25.3). wowsims' spell data marks an aura whose ProcChance column reads
  100 or 101 and whose trigger clause states no chance as firing on every hit it hears (`sim/core/spelldata/spelldata.go:
  182-186`, `resolve_proc.go:187-199` StatedChance 1), and `sim/common/forever/stat_bonus_procs_auto_gen.go` registers
  such procs (Hurricane 2824 «Автоатаки в дальнем бою призывают ледяные стрелы, наносящие цели $29502s1 ед. урона от магии
  льда», Blazefury Medallion 17111 and 19968 (7711), Fiery Plate Gauntlets 12631 (7721), Storm Gauntlets 12632 (16615),
  Force Imbued Gauntlets 18383 (1302248), the explosions of 285275-285278's thrown attacks (1318034, 1318062, 1318069,
  1318123), and more: 23 of Game/ProcData.lua's equip entries at chance 100 or 101 with no source have a ProcChanceAlways
  trigger in wowsims' `spells_auto_gen.go`, my lookup). HGA prices
  none of them, today or before group 0: Parse reads no such line as a proc (`Core/Parse.lua` EQUIP_PROC_PATTERNS starts
  with a chance phrase and needs a damage range; these lines state a single amount and no chance: my run of the ruRU
  descriptions through `Parse`, `g0r/always_parse.lua`), so no proc of theirs reaches `Score.ProcRateSource` or the
  tooltip; every trigger a Parse pattern reads that wowsims' spell data holds is ProcChancePPM or a column chance. Pricing
  them as wowsims does needs a new Parse gap (the lines above, their single amount, their hits by the aura's mask) and the
  generator to carry each trigger's ProcChanceSource: a new mechanism beyond sections 4.6-4.7, for the orchestrator and the
  user to decide.

## 19. Step 11: the raid fight as built

Step 11 builds section 6 without mana (every segment rich) in four commits on `raid-mode`: 11.1 `15c56d1` (`fight`,
`fightPlan`: the segments of 0-185 s, the time weight w(t), Rapid Fire's and Bestial Wrath's windows from 5 s, the Use
buffs' windows with the burst lock, a pass of `partsAndHits` a state with the state's Use buffs applied and the pet's
attack power held, the Survival weave per state at its Rapid Fire; `Model.Total`, `Parts`, `LandedHits`, `TotalAndHits`,
`Weave` and `Fight` in raid mode), 11.2 `1d24ae4` (the tempo of 6.4-6.5: `δ_S`, `δ_H`, Serpent Sting's re-cast, the HHA
cycle `C = C0 + 3·δ_H`, the dives and Arcane Shot at `2 / C` and `1 / C`, the hawks at `min(1, 18 / C)`; the weave's
Serpent Sting by 15.3's `I_S`), 11.3 `cec875f` (the Use buffs through the fight: `Score.SetUses`, `ctx.mode`,
`ctx.useGain`, `ctx.useUptime`, Score's raid branch, levelling's Use weights, `Model.ApplyStats`' raid keys, the tooltip
line), 11.4 `fc40e9c` (`Model.Fight`'s means, the `/hga weights` fight line, `/hga dump`'s fight). The design's own
numbers come out of the code: 6.4-6.5's example (the shots' speed 1.15, Aimed Shot's 0.92) gives `δ_S` 0.439 s, `δ_H`
0.346 s, `C` 19.04 s and the hawks' 0.945 (test_model `raid tempo: …`).

### 19.1 Points the design leaves open, settled here

- **The cache of `ctx.useGain`**: keyed by the set's Use spells in their firing order (`Score.SetUses`: wowsims' ItemSlot
  order, 6.3), not by the sorted spell ids 6.8 named: two sets of the same burst buffs in the other slots fire
  them in the other order (the second waits for the first's lock, 6.3), so their gains differ and a sorted key would give
  the second set the first one's (test_game `raid use: …`, mutant killed).
- **Spirit in `Model.ApplyStats`** (6.8 "regenCast `share/8`"): `regenCast` takes the live sheet's casting share alone,
  Bestial Discipline's 25% a rank (the reading holds it, 7.3), so 7.3's `regenCast'`, which adds the shares that come in
  combat from `p.spirit` (step 12), makes the slope while casting 7.3's `share/8` with no part counted twice. Intellect adds
  15 mana of the pool a point in raid mode, MP5 a fifth a second to both regens, MANA the pool; levelling applies none of
  the three (mana is the tie-break there). No input reads them in step 11 (their weights stay 0 until step 12).
- **Stats no damage input reads**: `Model.ApplyStats` applies no STA, ARMOR, HEALTH, HP5, DEFENSE, DODGE, PARRY, BLOCK or
  SPELL_POWER (and in levelling no SPI, MP5, MANA), which `Model.Weights` prices at 0: Golden Banana 270226's Use buff
  carries Stamina (`Game/UseData.lua`), and the fight applies it. Any other unknown key stays an error.
- **O6 in levelling covers Intellect**: `W.INT_USE = 0.20 × Careful Aim × W.AP_USE` beside 6.8's `W.AP_USE`, `W.RAP_USE`,
  `W.MAP_USE`, `W.STR_USE`, `W.AGI_USE` (Careful Aim's attack power from a Use buff's Intellect is a Use buff's attack
  power, which never reaches the pet).
- **The raid Use line's set** (6.8): the set the evaluation puts the item in (`res.newSet`, the worn set for a worn item)
  holds the item's Use spell, so a set without it is an error; the buff fires alone only where the item goes into no set
  (one the character cannot wear).
- **The fight of `/hga dump`**: the worn set's, the model point with the worn set's Use buffs (`Score.SetUses`, the fight
  `ctx.useGain` prices them in), so its segments name the buffs up; the `/hga weights` fight line stays the model point's,
  as its parts and weights.
- **`tools/preraid/rescore`'s `D(set)`** prices a Use buff with the pet's attack powers held (`withBuff`: `p.petRap`,
  `p.petMap`; O6), as the Score pass's `W.AP_USE`.
- **Texts** (wowsims states no UI): the raid Use line of 6.8 says «вместе с Rapid Fire и Bestial Wrath» where the fight
  has Bestial Wrath and «вместе с Rapid Fire» where it has none, and for a burst buff that waits for another «с N-й секунды,
  после «Использования» другой вещи (общий откат)»; the `/hga weights` line of section 8 says «ястребов нет» and «Bestial
  Wrath нет (нет таланта или пета)» where the fight has none; the mode line keeps step 10's armor penetration part.

### 19.2 Left to step 12 (mana)

The shares `seg.serpent`, `seg.aimed`, `seg.hha` (step 11's segments run the rich rates), the hawks' `9 × rH` below the
full share (6.5), the per-segment `casts` table of 6.1 (its reader is the mana spend; Serpent Sting's casts are in each
state's `tempo.serpentCasts`), the Frenzy Potion's window (a consumable of 7.4, which step 12's list names with category
4), and the tests that need a starved regime (6.4 `raid serpent: starved share …`, 6.5 `… 9 × rH below it`). Built in step
12 (section 20).

### 19.3 Tests

New, each with its mutants (killed): test_model `raid fight: the time weight …` (no fade; windows from 0; one Bestial
Wrath; Bestial Wrath without the talent or without a pet; the fight over 185 s), `raid fight: the pet inside Rapid Fire and
Bestial Wrath deals the product of both` (Bestial Wrath not inside Rapid Fire; the levelling 1.075; the pet at rf 0),
`raid weave: the cycle per state …` (the levelling average in a state), `raid use: Earthstrike …` (no lock; the lock for
the cooldown; the cooldown after the duration; the order reversed; the uptime without the weight; the bound at 180 s; no
error on a cooldown below the duration; uses in levelling), `raid use: the pet keeps its summon's attack power …` (the pet
takes the buff; every buff in every state; the pair check), `raid tempo: …` (R as half the GCD; the reaction after a GCD;
Aimed's hold without the GCD; Serpent Sting not an action; the HHA elements at 3 / 18; the talent out of C; the hawks at
0.9 or 1; the dive at 2 / 18; Arcane at 1 / 18; Arcane Shot alone not an action), `raid serpent: …` (no travel; no miss
term; the casts without 1 / (1 - q)), `raid weave: Serpent Sting re-cast …` (the travel from 12 yd; the levelling rate in
raid; no miss term; the casts without the hit), `raid fight: Model.Fight's means …`, `levelling use: …` (W.AP; no pet
held; W.INT; W.AGI); test_score `raid use: the gain through the fight …` (the uptime duration / cooldown; no gain; the
other stats at W; no error without ctx.useGain or ctx.mode; the order; no dedup); test_game `raid use: ctx.useGain …` (a
sorted cache key; ctx.mode "level"; the tooltip's start, Bestial Wrath, share and set), `/hga weights in raid names the
fight's uptimes and windows …` (the line dropped; the hawks' text; one Bestial Wrath window; the dump's fight nil, in
levelling, without Rapid Fire). Moved (each re-derived by hand in the test, the rule named): test_model `raid Gift of
Arthas: +8 …` and `… attempts at Quick Shots, Frenzy …` (the fight's means, `fightMean`, and the tempo's C, `hhaCycle`),
`Model.ApplyStats: …` (SPI moves nothing in levelling; the raid mana keys); test_score `UseData leaves out …`,
`stats-gear-4: an on-use buff …`, `a set counts one buff per Use spell …` and test_game `stats-gear-4: a Use trinket …`
(the levelling Use weights, O6); test_game `raid fixture at 60: …` and `hit cap: …` (the mode line). One equivalent
mutant: `cooldownWindows`' last start at 180 s in place of 185 s (no start of Rapid Fire's or Bestial Wrath's falls in
180-185 s); `useWindows`' bound is pinned by a cast at 182.5 s.

### 19.4 Points found, not built (for the orchestrator)

- **Quick Shots inside Rapid Fire** (built by group G, 25.4; the build that shoots from range): 6.1 keeps the shots' speed `ranged × haste × (1 +
  rf)` with `ranged = (1 + quiver)(1 + rangedHaste)(1 + 0.3 × qsUp)` and `qsUp` from the Auto Shots at the speed without
  Rapid Fire (`Core/Model.lua` `shots12`), so a Rapid Fire segment holds the Quick Shots uptime of the time outside it;
  wowsims rolls Quick Shots on each Auto Shot (`sim/hunter/aspects.go`), more of them inside Rapid Fire, and the Survival
  weave takes its Quick Shots at the cycle of the segment's speed (`weaveParts`). Kept as 6.1 writes it.
- **The HHA sequence with no bow at 60** (built by group G, 25.5): HGA keeps the hawks at `C = C0 + 3·δ_H` with Arcane Shot's element in it (as
  levelling's `2 / C0`), while wowsims' sequence waits at an element that is not ready (`sim/core/apl_actions_sequences.go:
  63-68`; `turret_hawk.apl.siml:15-16`), so without a bow, gun or crossbow its HHA sequence would stop at Arcane Shot after
  the first two hawks (my reading, not run).

### 19.5 Numbers (my runs of `refpoints.lua` on each commit)

| Point | before step 11 | 11.1 | 11.2-11.4 |
|---|---|---|---|
| L44 Cat (levelling, pet swing 1.2 s) | 270.6990 | 270.6990 | 270.6990 |
| L60 raid BM | 661.6998 | 672.9073 | 690.3033 |
| L44 SV (levelling) | 265.0675 | 265.0675 | 265.0675 |
| L60 raid SV | 663.7242 | 674.4447 | 674.4954 |
| test_game env at 60 (BM) | 432.7138 | 440.9981 | 451.8495 |

11.1: Bestial Wrath's +50% for 36 of the 180 weighted seconds (the pet's mean ×1.10 in place of ×1.075) and Rapid Fire 15
of 180 s in place of 15 of 300 s; 11.2: Serpent Sting's uptime about 0.95 by the re-cast in place of 0.8 × the shots' hit,
the hawks 18 / C. At L60 raid BM `W.HIT` goes 36.04 → 32.47 (a missed Serpent Sting costs a cast, no uptime), `W.CRIT`
39.04 → 38.94, `W.HASTE` 24.31 → 24.55; at L60 SV `W.HASTE_RATING` −2.70 → −3.06 (18.3's edge of Strider Kick's 7.6 s).
The review's commits leave every number of the table as it is (a point without a Use item).

### 19.6 Step 11's review: what changed, and the points left open

- **Pinned** (each with its mutants, killed): Serpent Sting's raid damage, the whole sting at the turret's landed
  applications `aL` and at the weave's `serpentLanded` (test_model `raid serpent damage: …`), its cast's miss with the
  ranged weapon skill's hit `p.rangedHit`; Bestial Wrath on the pet alone; the pet's held melee attack power under a
  Strength buff (`p.petMap`); a Use buff without its spell; the levelling `W.MAP_USE` and `W.STR_USE` where the pet reads
  the melee attack power, `W.RAP_USE` beside `W.AP_USE` in the Survival weave; Score's Use weights of RAP, MAP and
  Intellect and a Use buff's expertise through its cap in both modes; the raid Use line without Bestial Wrath and with
  one cast; the dump's segment spells and weights.
- **Changed**: a turret without hawks has no `hawkWait` and no `hhaCycle` (`Model.Fight`'s means leave them nil); the
  raid Use line's set without the item's spell is an error, `/hga dump`'s fight is the worn set's and `rescore`'s
  `withBuff` holds the pet's attack powers (19.1); the Use buffs fire at one instant in wowsims' registration order, the
  legs before the trinkets (6.3, A5), which moves a set of Cloudkeeper Legplates 14554 and Kiss of the Spider 22954 from
  +22.51 to +17.71 DPS at a reviewer's level-60 BM point (with Earthstrike 21180 +15.01 → +14.30, with Slayer's Crest
  23041 +14.15 → +13.52; my runs of `s11fix/order_hga.lua` on `f44947e` and `aa8b83b`); the DB2 citations of 2.2, 6.3, 6.5
  and 7.2 name the row IDs.
- **Open, not built** (wowsims read, not run):
  - **The major cooldowns on a free GCD**: wowsims' `getFirstReadyMCD` passes over a cooldown that is not reactive while
    the GCD runs (`sim/core/major_cooldown.go:369-402`, `case gcdLeft > 0: continue` at 393), so Rapid Fire, Bestial
    Wrath and the Use buffs fire at the first free GCD from 5 s or from their ready time; HGA fires them at 5 s and at
    the ready time exactly. Not in A1-A15.
  - **The BM preset's walk in**: the preset's defaults name `pull_range 25` (`ui/specs/hunter/dps/defaults.siml:52-53`)
    and `apls/turret_hawk.apl.siml:3-4` uses `walk_in.apl.siml` (the walk to the shooting spot at 12 yd) and
    `pull.apl.siml`; HGA's fight starts at 0 s in place.
  - **A worn trinket moved between the slots**: two burst trinkets fire in their slots' order (6.3), so moving a worn
    trinket from slot 14 to 13 changes `ctx.useGain` (Slayer's Crest 23041 in 13 and Earthstrike 21180 in 14: 143.126 →
    143.213 of the weights' unit, my run of the reviewer's `rev-s11/probes/swap13.lua` on `aa8b83b`), and `Score.Plan`
    offers bag items alone; whether the plan names such a move is the user's call.
  - **The Use line's casts** («в бою 180 с N раз(а)») count every window that starts before 185 s, a cast at 182.5 s
    among them, which the fight's weight counts at 0.3125 s.

## 20. Step 12: mana in the raid fight as built

Step 12 builds section 7 in six commits on `raid-mode`: 12.1 `29e870c` (`CONST.mana` costs, `Model.ManaCosts`, each raid
state's casts by action from `partsAndHits`), 12.2 `df9eebc` (`manaFlow`: the spend, Judgement of Wisdom's income, the
casting regen with Rapid Recuperation and Resourcefulness from the state, the net drain), 12.3 `c438322` (the fight walks
0-185 s with the mana: the rich and the starved regime, the income of the five-second rule's cycle, cheapest ready first
by the shares of `STARVED_ITEMS`, the debt, the second Bestial Wrath by its mana, the ceiling of an Intellect buff), 12.4
`cfadb55` (the consumables of 7.4, always on), 12.5 `0935dfe` (the raid weights of Intellect, MP5, Spirit and mana; the
raid tie-break; `tools/gen_use_data.py`'s `SPI`, `MP5`, `MANA` and `Game/UseData.lua` regenerated), 12.6 `3007a5f` (the
`/hga weights` mana line and its texts, `/hga dump`'s fight, `Model.Fight`'s mana means, `rescore.lua`'s raid pass).

### 20.1 Points the design leaves open or states otherwise, settled by the wowsims rule

- **Costs a percent of base mana are rounded to the whole mana** (wowsims `sim/core/mana.go:372` `newManaCost`,
  `math.Round(BaseCostPercent × BaseMana / 100)`): Arcane Shot and Summon Hawk 189, Bestial Wrath 206, Strider Kick 100,
  Multi-Shot 239, in place of 7.2's 189.2, 206.4, 99.9 and 239.1.
- **Efficiency 19416 and Resourcefulness' first effect cut the costs**, which 7.2 leaves out and wowsims parses
  (`sim/hunter/talents_marksmanship.go:65-71`, `talents_survival.go:110-116`): Efficiency −3% a rank on the shots, the
  stings, the melee abilities and Summon Hawk, Resourcefulness −30% a rank on the melee abilities and the trap
  placements, each by its class mask (DB2 SpellEffect 696992, 1134467; SpellClassOptions of each spell; the rank curves
  82809, 82781), the two multiplied and the cost not rounded after them (`spell_mod.go:504-509`, `spell.go:1055-1063`).
  `Model.DEFAULT_TALENTS` names `efficiency` (Player.BRANCHES reads it).
- **Judgement of Wisdom pays for Immolation Trap's landed application too**: 5.3's rule hears every landed hit its
  ProcFlags 0x222a8 name, the harmful spell among them (`dbcenums/proc_flags.go`, `PROC_FLAG_TAKE_HARMFUL_SPELL`), a hit
  that deals no damage included; 5.3's list did not name the trap. **Wing Clip's crits trigger Resourcefulness** (a melee
  ability, ProcTypeMask 0x110), which 7.3's list did not name.
- **A cast group's whole spend in the starved regime is net of its own Judgement of Wisdom** (the rich D holds every
  landed hit's income alike), a group that returns more than it costs bought whole; **the starved casting regen follows the
  shares it buys** (Rapid Recuperation at the bought Serpent Sting's uptime, Resourcefulness at the bought ability crits),
  the shares and the income solved together (`fight` starvedOf).
- **A starved stretch whose income buys every cast stays starved with every share whole while its state's rich D is above
  0**, and the regime turns rich at a state whose D is 0 or less, the mana rising from 0 (7.5's "the rest raises m" read as
  the fluid limit: a casting that runs whole cannot pause for the regen out of the five-second rule).
- **A one-off cost the pool cannot pay is a debt in both regimes** (7.6 item 2 names the starved one): Rapid Fire's 100
  and Bestial Wrath's 206 at 5 s, Hunter's Mark's 60 at 98 s for both rotations (both use `pull.apl.siml`, its mark at −22
  s). test_model's raid point (a pool of 4000, regen 15 / 7.5) holds 51.3 at 98 s and owes 8.7.
- **The second Bestial Wrath rich at 125 s without its 206** fires when the mana rising at −D reaches it, and waits for
  the starved income where D > 0 (7.6 item 5 names the rich and the starved case alone).
- **A mana gain repays a debt first and takes the saving for the second Bestial Wrath** into the pool.
- **The weave's income element after Wing Clip, Mongoose Bite and Strider Kick is Arcane Shot** (15.5 names the three).
- **The mana potion's fit at 125 s reads the ceiling and the casting regen of the state up to the instant** (A17).
- **A drink or food that lasts while the user sits is no Use buff** (SpellInterrupts AuraInterruptFlags_0 0x40000, as
  wowsims' `WhileSeated`, `sim/core/spelldata/consumable.go:21-25`): with `MP5` priced, `tools/gen_use_data.py` would have
  priced Lapidis Tankard of Tidesippe 4696, Skum's Bucket 273137 and item 286541 at 5 s of the fight; it leaves them out and
  names them (a new argument `--interrupts`). Serenity Field 272439 (Spirit 72) is the one new priced buff.
- **`ctx.raid` is not added**: `Score.Secondary` reads `ctx.mode` (step 11's field, raid or level, anything else an
  error), the raid branch's attacker `Model.RAID_BOSS_LEVEL` 63 in place of 7.9's `pools.level = 63`.
- **`rescore.lua`'s untyped `AP_CREATURE`** (convert.py names no type) counts at 0 in the raid pass (the boss is
  dragonkin); its D runs the fight with the set's Use buffs and their hit at their share, and its ctx has `useGain` and
  `useUptime`; `withBuff` goes (the fight holds the pet's attack power itself). Run by hand on made-up sets only: the
  worktree holds no `out/items.lua`.
- **Texts** (wowsims states no UI): the mana line's consumables (`зелье маны на N с` or `не помещается на 125-й секунде —
  вместо него второй Frenzy Potion`, `руна на N и M с` or `не помещается`, the Frenzy Potion's windows) and its starved part
  built from the first starved stretch's shares (`только X и Y (N% темпа), без Z`); the windows in whole seconds.

### 20.2 Tests

New (each with its mutants, killed): test_model `raid mana costs: …`, `raid casts: …`, `raid JoW and spend: …` (the
design's example of 7.5: 0.678 landed hits, J 20.0, S 82.4, D 54.9), `raid regen: …`, `raid mana: never out of mana …`,
`raid mana: the starved income …` (both branches, Rapid Recuperation and Resourcefulness, the debt with and without a
shortfall), `raid mana: cheapest ready first …` (the saving carried over a change of state), `raid starved: a share scales
…` (the hawks at min(1, 9 rH)), `raid weave starved: …`, `raid mana: an Intellect buff raises the ceiling …`, `raid
consumables (O2 = (a)): …` (the fit at 2287.5), `raid consumables: the rune …` (the debt repaid first), `raid weights:
W.MANA x unitDps = …` (the oracle of 7.7); test_score `raid secondary: …`; test_game `/hga weights in raid names the mana
…`; `tests/test_gen_use_data.py` three keys and four seated cases. Moved (each re-derived in the test, the rule named):
the step-11 tests of the fight's other mechanics run at `richPoint` (regen 200: the mana never runs out), the bleed's and
Arcane Shot's checks with the Frenzy Potion's attack power off (`noPotionAP`), Serpent Sting's damage with the potion's +80
in its windows, the time weight's states with the potion's windows; test_game's dump segments with the 98 s cut and the
potion's windows. Mutants: 86 on the Lua suite, 2 on the Python one, 4 on a probe of `rescore.lua`; all killed, four of
them after a test was strengthened. The probe battery (group 0's, on a copy of each tree): SV and BM all OK on 12.6, its
library taking two cases the mana brings (`s12/g0c/g0lib.lua`): a configuration of the worn hands that wins through the
mana (20.4), and a bag copy of a worn weapon standing for it in such a configuration.

### 20.3 Numbers (my runs of `refpoints.lua` on each commit)

| Point | step 11 | 12.3 | 12.4-12.6 |
|---|---|---|---|
| L44 Cat (levelling, pet swing 1.2 s) | 270.6990 | 270.6990 | 270.6990 |
| L60 raid BM (a pool of 3500, regen 15 / 7.5) | 690.3033 | 553.9517 | 643.5405 |
| L60 raid SV | 674.4954 | 512.1935 | 604.9675 |
| test_game env at 60 (BM; a pool of 1725, regen 12.6 / 3.15) | 451.8495 | 337.1787 | 374.7043 |

At L60 raid BM (12.6) the weights in RAP: Intellect 2.67 (Careful Aim 5/5 and 15 mana), MP5 3.72, Spirit 1.29, mana
0.111; at the env's point MP5 3.42, Spirit 1.32, mana 0.088, Intellect 1.32 (no Careful Aim).

### 20.4 Points found, not built

- **The Survival weave in a starved fight**: its cheapest casts, Raptor Strike and Wing Clip (with Resourcefulness the
  trap too), take the starved income first (wowsims' first-ready-affordable, which the SV Weave rotation runs with no mana
  condition, `default.apl.siml:20-24`), while Arcane Shot buys far more damage a mana point. Without a melee weapon neither
  is cast, so the income goes to the shots: on the probe battery's dual-wield SV set at 60 (a pool of 1725, regen 12.6 /
  3.15) taking the main hand off gains 22.9 DPS on 12.6 (the melee part −33.8, Arcane Shot +41.0, Serpent Sting +8.2, my
  run of `s12/probes/dbg_best.lua`),
  and the swap plan names it. It follows the rules of 7.5 and wowsims' rotation; whether the advice should stand is the
  user's call.

### 20.5 Step 12's review: what changed, and the points left open

Two reviews of `29e870c..aeb7275`; four commits on `raid-mode` settle their findings:

- `57b09dd`, the starved income. **J_a takes the starved state's own free hits**: a Raptor Strike the starved weave does
  not buy leaves its main-hand swing white, a free landed hit at the white table's landing (`casts.acts.raptor.white`,
  weaveParts), so J_a counts the free landed hits at the state's shares (7.5: the white swings go on) and a starved state
  spends what comes in (its own D is 0 where I = g1). J_a took the rich pass's free hits before: on an SV point with regen
  7 / 0 the buying state's own D was −0.85 and Hunter's Mark's debt was repaid at 11.16 a second in place of 14.71 (the
  review's probe). **The income is the largest root of I = F(I)**, F(I) the income at the shares I buys. Where a bought
  share raises the casting regen (Rapid Recuperation's U, Resourcefulness' crits) F rises with I: with Rapid
  Recuperation 2/2 and Spirit 152 by 0.86 a mana a second of income, so 12.3's iteration from the rich rc did not reach
  1e-12 in its 100 steps and threw (Model.Weights → the fight: the addon stopped for such a character; the review found 39
  of 492 game points); where F rises faster than I (Spirit above about 200 with Rapid Recuperation 2/2) I = F(I) has three
  roots, the high one keeping the casts whose regen pays them. `fight` now checks F at the incomes where a share turns and
  where the in-combat share bought reaches its cap (between two such points one share moves linearly with I); the topmost
  point with F(I) ≥ I and the next above it bracket the root, and the Illinois method finds it to 1e-12 of I a second (100
  steps without it are an error). My method; my probes: on 10,500 random raid points (Spirit 40-650, Rapid
  Recuperation, Resourcefulness, Bestial Discipline and Efficiency from 0 to the top rank, both rotations,
  `s12r/fuzz.lua`, `fuzz6.lua`) it matches 12.3's iteration run to its end with no step limit within 7.1e-10 DPS; on 4,500
  random raid points scanned at 6,001 incomes a state (`s12r/roots.lua`) 62 states have three roots and it takes the
  largest in each; the reviews' failing points run (`repro.lua`, `envfp.lua` 0 of 492, their fuzz 0 errors on 4,500). Two
  more roots between two checked points (a share's own curve) would be missed; none was found. Model.Total at the probe's
  raid points costs what it cost (0.21-0.28 ms BM, 1.15-1.57 ms SV, my run of `s12r/perf.lua`).
- `3592324`, tests of rules the reviews found untested (each with its mutant): the second Bestial Wrath when the mana
  rising at −D reaches 206, the debt repaid before the regime turns rich, the mana potion's fit at the ceiling of the state
  up to 125 s (an Intellect buff up before 125 s makes room, one from 125 s does not), Rapid Recuperation's U by the landed
  applications below the hit cap, the melee abilities' and Arcane Shot's crits, the off hand's white swings among the free
  hits (a 3.8 s main hand and a 1.8 s off hand), Serpent Sting's starved share in the weave, the out-of-mana time at
  Hunter's Mark's cost, and Wing Clip as the weave's income element where the element decides the income (the cycle's
  branch: no Strider Kick, a 5.0 s main hand, a 3.0 s bow).
- `36f077b`, the `/hga weights` mana line: the mana runs out at the first starved stretch's start (a time the mana reached
  0 and came straight back no longer stands for it); where no stretch is starved, `мана доходит до 0 на N с и сразу
  возвращается (руна, зелье маны или реген баффа)` (the command threw there: a rune that fits at 0 mana at the instant the
  mana runs out); a part of the rate under 1% `<1%`, over 99% `>99%`; `без ястребов и Arcane` in the genitive. Pinned:
  the mana potion's time, Arcane Shot alone without Summon Hawk, no second Bestial Wrath without the talent, the debt-only
  stretch's `ничего, только автоатаки и пет` (reached with a made-up pool of 200 that the model takes).
- `63e5a5e`, a levelling Use buff of the mana stats alone (Serenity Field 272439) stays not counted in the tooltip:
  levelling weighs Spirit, MP5 and mana at 0 and its tie-break reads no Use buff (`Score.UsePriced`); the raid fight prices
  it.

Numbers (`refpoints.lua`): L44 Cat 270.6990, L60 raid BM 643.5405 and the test_game env at 60 374.7043 unchanged; L60 raid
SV 604.9675 → 605.1628 (the weave's J_a). Tests 517 → 520. The probe battery (s12's `g0c`) on a copy of the tree: SV and BM
as on 12.6, all OK, scen 768 all OK.

Points left open (not built; the architect's or the user's call):
- **The mana stats' weights across a discrete event** (built by group G, 25.1). 6.9 names the two switches (a consumable that fits or not, the
  second Bestial Wrath) and that a step across one moves the derivative; the step of 10 Intellect (150 mana) or 100 mana
  crosses the mana potion's fit at 125 s (2250 + 5 rc): at L60 raid BM W.INT is 23.7 for pools 2150-2250 against about
  2.85 around them and W.MANA 2.20 against 0.12, the rune's fit at pools 1500-1550 likewise (W.INT 39.1, W.MANA 3.73), and
  just past the potion's threshold W.MP5 and W.SPI fall below 0 (W.MP5 −15.1 at pools 2288-2296, W.SPI −17.9 at
  2288-2290; the review's probes, rerun on this review's tree). The fight follows wowsims' fit rule; how an item's stat
  that moves such an event is priced (the
  events held at the base point and the switch priced on the whole set, as `ctx.useGain`, or the fit smoothed) changes
  6.9 / 7.7.
- **Rapid Fire and Bestial Wrath at 5 s with no mana for them**: 20.1 makes them a debt, 7.6 skips such a cooldown until
  it can be paid (`major_cooldown.go:110-112`). Only a pool under 306 + 5 D at 5 s reaches it, below any level-60 pool
  (1440 + 15 Intellect, my arithmetic from 7.1's base mana 1720 and `mana.go:59-71`).
- **A starved state with no cast to buy** (no bow, gun or crossbow and no Summon Hawk, Model.Weights' no-shot point; with
  25.5 any build with no bow, gun or crossbow) is an error, but for a debt, which repays at the regen out of the
  five-second rule (25.5): with no cast spending, only the one-off costs on a pool under 306 + 5 D at 5 s starve it, again below any
  level-60 pool.
- **`/hga weights` and `/hga dump`**: the weights' fight (its mana line and Bestial Wrath text) runs without the worn
  set's Use buffs, as W at the model point and step 11's uptime line; the dump's fight has them. Kept.
- **The mutants left alive**, each equivalent on every reachable state: the cap point's `>=` and its other bisection end
  (one ulp apart), the Illinois halving (the plain false position converges within the 100 steps on every tested state),
  and the turn points' `left` (it moves a turn only when a cast whose net spend is 0 or less follows one whose is above 0
  in cost order; the net spend falls to 0 only for the cheapest casts, which come first).

## 21. Step 13: the live sheet's stat multipliers as built

Step 13 builds section 4.8 (O8 = (a)) in one commit on `raid-mode`: `tools/gen_stat_mult_data.py` (new) writes
`Game/StatMultData.lua` (new, in the TOC before `Game/Items.lua`), 36 spells of build 70888; `Player.ReadStats` reads the
auras of it up on the player into the reading's `statMult`, `Player.Snapshot` passes it as `model.statMult`; `checkMode`
requires it in both modes; `Model.ApplyStats` multiplies an item's and a Use buff's Agility, Strength, Intellect and Spirit
by it; `Model.Weights` takes the levelling Intellect weights at it.

### 21.1 Points the design leaves open or states otherwise, settled by the wowsims rule

- **The stats an aura 137 effect names** (4.8 wrote "misc −1 → all five, 0..4 → one"): wowsims reads the mask of the
  second misc value first, one bit per client stat index, and the first misc value only where the mask is 0
  (`sim/core/spelldata/parse_effects_table.go:1446-1454` `TotalStatPercentStats`, `statMaskList` :1435-1444,
  `clientStatList` :1425-1433; its test `parse_effects_test.go:742-781`). Every positive aura 137 row of build 70888 has a
  mask, and the first misc value often says otherwise: Lightning Reflexes 19168 states 0 and 2 (Agility, where 4.8's rule
  reads Strength), Heart of the Wild 17003, Arcane Mind 11232, Divine Intellect 20257 0 and 8 (Intellect), Toughness 16252
  0 and 4 (Stamina), Insight 1299796 0 and 16 (Spirit), Anointed By Elune 430420 3 and 16 and Anointed By The Loa 430421
  2 and 16 (Spirit, where the first misc value names Intellect and Stamina), Vitality 29140 2 and 5 (Strength and
  Stamina). The generator takes wowsims' rule; 4.8's rule would have written other stats for 15 of the 36 spells (my count
  over `db2/SpellEffect.csv`).
- **The factors multiply**: several auras up multiply their factors of one stat, and with Lightning Reflexes' rank too
  (`sim/core/stats/deps.go:232-237` combines the static factors of one stat by product, :279-283 applies each to the
  stat's whole); Lightning Reflexes is left out of the data as 4.8 says (its two trait nodes 110859 and 104982 both name
  spell 19168: TraitNodeXTraitNodeEntry → TraitNodeEntry 137851 / 129646 → TraitDefinition 142605 / 134447).
- **An aura's state the client keeps secret hides the reading**, as an unknown Aspect of the Hawk does (`Player.ReadStats`:
  the multipliers price an item's stats on the sheet the reading is taken on; the last reading of the same gear and talents
  serves with its own multipliers); the `/hga weights` stale line names them («игра скрывает статы, состояние Aspect of the
  Hawk или баффов, умножающих статы (Kings и т. п.)»).
- **`W.MAP` is the melee attack power's own derivative** (it was `W.STR`, which now carries the Strength multiplier), and
  the levelling `W.STR_USE` the derivative by a Use buff's Strength (it was `W.MAP_USE`); the levelling `W.INT` and
  `W.INT_USE` take the Intellect multiplier.
- **Stamina is not multiplied**: 4.8 names `p.statMult = { AGI, STR, INT, SPI }`; no damage input reads Stamina, and the
  survival tie-break (`Score.Secondary`) keeps its rates (`Model.SecondaryRates`: 10 health a Stamina point, 15 mana an
  Intellect point) without the sheet's multipliers: wowsims has no tie-break, HGA's stays as it was.
- **`tools/preraid/rescore`** builds its point with `statMult` 1 each: its point is the gear on the base character, with
  no stat multiplier aura (the game reads the live sheet's).

### 21.2 Tests

New (each with its mutants, killed): test_model `stat multipliers: Kings on the sheet makes 10 item Agility 11 in W.AGI;
Strength, Intellect and Spirit at theirs; W.MAP at none; statMult required` (Model.ApplyStats under Kings as 11 of each
attribute at none, the raid pool and regens included; Lightning Reflexes 5/5 and Kings multiplied; W.AGI in levelling and in
raid as the value of 11 Agility over 10; the levelling W.INT and W.INT_USE; W.STR, W.MAP and W.STR_USE in the Survival weave;
a Use buff's Agility in the raid fight; statMult missing, short of a key or below 1 is an error, ProcOutcomes too), test_game
`stat multipliers: Snapshot multiplies the live auras of Game/StatMultData.lua; an unknown aura state hides the reading; the
data` (Greater Blessing of Kings, Kings with Spirit of Zandalar and Insight multiplied, Divine Strength and Heart of the Wild
each on its own stat, a secret aura's stale reading and its line, the dump's statMult, the generated rows of 25898, 19168,
24425, 1299796), `tests/test_gen_stat_mult_data.py` (8 rules, 7 stops). Moved: test_game `/hga weights: a stale reading for
hidden stats names the stats and Aspect of the Hawk, Trueshot Aura with its talent` (the line names the stat multipliers);
the fixtures `ref` (test_model) and `fullP` (test_score) and `tools/preraid/rescore/rescore.lua`'s point take `statMult` 1
each. Mutants (31, all killed, one after a stop case was added: a mask of Strength and an unknown bit): the four
attributes, Intellect's attack power and pool, Spirit's regens unmultiplied; the Agility factor added; Strength at the
Agility factor; the levelling W.INT, W.INT_USE unmultiplied; W.MAP = W.STR; W.STR_USE = W.MAP_USE; no statMult check, a check
of > 0, a check of three keys; Player's factors added, a secret aura taken as off, Agility and Intellect at the wrong stat
index, statMult not passed, the hidden reading not hidden, only the first aura counted; the generator keeping Lightning
Reflexes, reading the first misc value first, keeping negative points, without the duplicate, the stale-exclusion, the
Effect check or the unknown-bit check. The probe battery (group 0's, `s13/g0c` with `Game/StatMultData.lua` in its file lists
and `statMult` in `casts_share`'s point) on a copy of the tree: SV and BM all OK, scen 768 all OK, as on step 12.

### 21.3 Numbers (my runs of `refpoints.lua`)

Every point of section 20.3 is unchanged (no stat multiplier aura: `statMult` 1 each): L44 Cat 270.6990, L60 raid BM
643.5405, L44 SV 265.0675, L60 raid SV 605.1628, the test_game env at 44 263.9600 and at 60 374.7043. Under Greater Blessing
of Kings (`statMult` 1.1 each) the totals stay (a reading of the same sheet) and the attributes' weights rise by the factor:
at L60 raid BM W.AGI 2.7441 → 3.0189, W.INT 2.6713 → 2.9389, W.SPI 1.2860 → 1.4122 (W.MP5, W.MANA, W.AP unchanged); at L44
Cat W.AGI 2.5282 → 2.7815.

## 22. Step D: DoT procs as built (U2 = (a))

Step D builds section 17 in one commit on `raid-mode`: `tools/gen_proc_data.py` writes a damage spell's periodic damage
aura as the entry's `dot = { tick, period, ticks, canCrit }` (SpellEffect aura 3 on an enemy, SpellMisc DurationIndex →
SpellDuration, Attributes_8 0x200, the damage spell's SpellAuraOptions), `avg / min / max` 0 where the spell deals no
direct damage; `Game/ProcData.lua` regenerated: 381 entries of 366 items (309 of 295 before), 98 with a damage over time,
72 of them without a direct damage; 75 entries take a wowsims override rate (53 before), 45 override rows name no written
entry (67 before). `Items.LinkProcs` brings a linked entry's dot and links a dot-only entry by item and kind (17.4);
`Model.ProcOutcomes` gives each table `land` and `tickCrit`; `Score.ProcValue` adds the damage over time (17.3, new
`Score.DotTicks`, `Score.ProcTable`); `Game/Advisor.lua`'s tooltip line of 17.4.

### 22.1 Points the design leaves open or states otherwise, settled by the wowsims rule

- **Which DoT entries have a rate** (17.2 named 12 measured items): 14 of the 98 have a measured rate in
  `Score.MEASURED_PPM` (17.2's twelve and Bigger Rock on Bigger Stick 279480 and Rock on Stick 279852, whose "Rock to the
  Face" 1306816 / 1309967 deals 14 and 7 physical a 2 s tick for 20 s and cannot crit), 14 more a wowsims override row
  (`weapon_procs.go`: carry-overs and EV rows), and 70 none: by U4 = (a) they are written and not priced, their tooltip
  line says the rate is unknown (the twins 228542, 228573, 228029, 209436 among them; test_score's U4 test now checks
  their entry has no rate in place of no entry).
- **`land` and `tickCrit`** (17.3: "`Model.ProcOutcomes` returns the application chances and the tick crit factors"):
  wowsims' application rolls the proc's own table without crit (`shared_utils.go:730`) and its ticks crit by the dot
  spell's DefenseType (`spelldata/spell.go:368-377`: the magic table's spell crit ×1.5, else the physical crit ×2 of the
  main hand's entry), so each table's `land` is its `hit` and its `tickCrit` its `critMult`; the fields carry the two names
  so `Score.ProcValue` reads what each means. A magic school on the melee or ranged table (Xorothian Fire 18755: Fire,
  DefenseType 3) crits its ticks at the physical crit and takes Curse of the Elements by its school.
- **The direct part's school words are checked, a dot-only entry's are not**: 4.6.2's check guards the rule Parse prices an
  unlinked direct proc by; a damage over time alone has no damage Parse reads (Parse needs a damage range), and 12 of the
  dot-only entries' descriptions read otherwise than their SchoolMask by that rule ("Corrupts the target, causing $o1 damage"
  for Shadow, "ед. урона от кровотечения" for a physical bleed, "Burns the enemy for $o1 damage" for Fire; my run of the
  generator's checks, `sD/mism.py`), so the generator checks them for an entry with a direct damage alone.
- **avg 0 means no direct damage only beside a dot**: build 70888 already has direct entries of mean 0 (the extra-attack
  and weapon-damage shots of 227990, 230253, 232607, 242310 and the Timeworn Shot 1213393 items), written as before; a dot
  entry with avg 0 is dot-only (`Items.LinkProcs` leaves it out of the mean match: a parsed average of 0.5 matches none),
  and a direct damage of mean 0 beside a dot stops the generator.
- **A periodic damage of EffectRealPointsPerLevel** (17.4 lists it among the stops and says "as the direct part's skip"):
  a skip ("level"), as the direct part's; no aura 3 of an item proc gains points a level in build 70888 (`sD/dots.py`: 0 of
  98 rows), so the output is the same either way.
- **More checks of the rows** (4.6.2: the generator stops on a chain it cannot follow): a period above 0, no Variance on
  the periodic effect, one SpellDuration row whose duration is fixed (DurationPerLevel 0, MaxDuration the Duration, above
  0: a permanent aura's −1 stops, wowsims `DotConfig` panics on it, `resolve_aura.go:78-87`), at most one SpellAuraOptions
  row of the damage spell. None stops at build 70888.
- **The link of a dot-only entry** (17.4) takes exactly one such entry of the kind and exactly one line (two dot-only
  entries of one kind and one line stay unlinked, as two lines do); a "hit" line becomes a proc of the weapon's hits
  (`hits = "weapon"`, a chance on hit's rule of 4.6.2), an "equip" one an equip proc of its mask; the line is marked
  counted (`effect.dot`), so «эффекты не учтены» no longer counts it. `Items.LinkProcs` requires the parse's effects.
- **The tooltip** (17.4): a dot-only proc shows the dot line alone; a direct part with a dot shows the direct line and the
  dot line, each with the rate text; the ticks between procs at the rate there and the application's chance of the set
  the item goes in (`A.ModelProcRates`' third value: `ctx.procOutcomeFor` of the set's main hand skill, as
  `Score.SetValue` prices the set's procs, 18.7).

### 22.2 Tests

New (each with its mutants, killed): test_model `proc outcome: …` (each table's `land` and `tickCrit`); test_score `dot
proc: E[n] = sum e^(-lambda k T); a faster rate loses ticks`, `dot proc: the application rolls the table once, no crit;
magic ticks x1.5 spell crit; physical ticks at the suppressed physical crit, no armor, +8 Gift in raid`, `dot proc: a
direct part and a dot priced together`, `Game/ProcData.lua: …` (Rot 274963: 24 every 1 s for 7 s, Nature, magic, its
ticks crit, no direct damage; Demonshear 13348's direct 150 and 34 every 2 s for 6 s; 240842's Rot without
PERIODIC_CAN_CRIT; 30 measured EV rows); test_game `dot link: one unparsed "Chance on hit" line links the item's dot entry;
two lines leave it unlinked`, `dot tooltip: the ticks, the duration and the ticks between procs at the proc's rate; a direct
part with a dot shows both`, `dot tooltip: a main-hand weapon's dot lands at its own main hand's skill`;
`tests/test_gen_proc_data.py` 57 → 75 (Rot and Shadow Bolt from their build 70888 rows, the canCrit bit, an equip
trigger's dot, the unchecked words of a dot alone, the skip, the twelve stops). Moved: test_score `U4: a twin …` (each
twin's entry has no rate), `Game/ProcData.lua: …` (17 → 30 measured rows), test_game `ProcData link: …` (the effects
argument), test_gen_proc_data's "a damage spell with no school damage: left out" (an aura 33 slow now; aura 3 is a dot).
17.5's two tests of real ids with made-up direct lines (228542, 6472) move none, as 17.5 reads: their parsed range matches
no dot-only entry and no line is left not counted. Mutants: 48, all killed, five after a test was strengthened (a parsed
average of 0.5; the effects check on an item without a dot entry; `tickCrit` apart from `critMult` in a made-up table; a
main-hand dagger at 195 of 215 for the tooltip's application chance, against the worn outcome and against 1). The probe
battery (`s13/g0c`) on a copy of the tree: SV and BM all OK, scen 768 all OK, as on step 13 (its `tipnew` line prints
`A.ModelProcRates`' new third value).

### 22.3 Numbers (my runs of `refpoints.lua` and `sD/dotprobe.lua`)

Every model point of 21.3 is unchanged (procs are priced in Score, not in `Model.Total`). A DoT proc's value at the SV
points of `refpoints.lua` (the weapon in the main hand, `sD/dotprobe.lua`): Rot-Covered Harpoon 274963 (1.45 a minute at
2.5 s) L44 SV 4.300 DPS (1.717 procs a minute, land 0.96, 6.28 of 7 ticks), L60 raid SV 3.754 (land 0.83: the spell miss
17% at +3, Curse of the Elements ×1.10); Gatorbite Axe 17730 (a bleed, 2.8 s) 4.834 and 5.814 (Gift of Arthas' +8 a tick
in raid, no armor); Demonshear 13348 (3.6 s) 7.207 (direct 4.486, dot 2.721) and 6.450 (3.980, 2.470). Before step D the
two DoT-only weapons priced 0 (their damage over time left out of `Game/ProcData.lua`). The probe builds each proc from its
entry, past `Items.Get`: in the addon Demonshear priced 0 before step D and after it (its tooltip's one number, 150, is no
range Parse reads, so its entry linked to nothing), until 24.2 links it; through `Items.LinkProcs` and its real line it
prices the same 7.207 and 6.450 (24.2).

## 23. Step 14: documents and tools as built

Step 14 updates the documents and the tool in one commit on `raid-mode`:

- `docs/superpowers/specs/hunter-gear-advisor-design.md`: a pointer to this design; the user's lines on melee and mana
  (14-17) by the mode; a section of the user's decisions of 2026-11-17 (the modes and the raid target, wowsims'
  mechanics, the live sheet and its stat multipliers, the raid fight, the mana and the consumables, the commands and
  settings removed, the Survival weave, the unarmed 1.0 s, the DoT procs, no proc rate made up); the decisions' bullets
  that named a removed command or setting or an old rule (the weights' unit, the model inputs, the secondary comparison
  by mode, the threshold 0, the hit cap by the target, the procs by U4 with their DB2 link, mask, table and DoT part, the
  Use buffs in the raid fight and O6, Beastslaying as wowsims, the shot-less set and the unarmed main hand, the stale
  reading's stat multipliers, the swap banner always on, `/hga dump`'s fight) and two new bullets (crit suppression and
  the attack tables; the raid fight's mana); the layout's generated data and the generator tests.
- `docs/research/W1-wowsims-check-2026-11-16.md`: the table's actions of stats-gear-2, -4, -8, -9, -12, -13, ranged-4,
  ranged-8, melee-sv-1, -7, -8, -9, -12; the commits of `raid-mode` that settle them; the five open questions (stats-gear-8,
  the Tablet, the application rule, the equip mask, Beastslaying) moved under "Closed the wowsims way" with the raid fight,
  the weave and the white table; Rot's line; the by-design list.
- `tools/preraid/rescore/README.md` (and `run.sh`'s comment, `tools/preraid/README.md`'s line): the raid mode, the new
  inputs of `pointFor`, the one pass against the +3 boss (14.6), the stand's procs, the parse readings, and the result of
  a new run (below).

### 23.1 Points found and settled

- **`rescore.lua` stopped at load after step 13**: `Game/Player.lua` lists `ns.StatMultData`'s spells at load (21), and the
  tool loaded no `Game/StatMultData.lua` (a run on a copy of the tree after step D: "bad argument #1 to 'for iterator'" at
  `Player.lua:349`). The tool loads it now, before `Game/Player.lua`; the test suite does not run the tool (step 1), so no
  test saw it.
- **The two runs of `run.sh` give the same result in raid mode**: `convert.py`'s untyped `AP_CREATURE` counts 0 against the
  dragonkin boss in both (`UNTYPED_SHARE`), and `Model.AP_CREATURE_SHARE`, which the `nocreature` run sets to 0, is the
  levelling mode's share alone; the outputs differ only in that run's header line (my diff). Kept, as the README says.
- **The SetValue fixed point cycles** in both variants («SetValue iteration cycles; stopping»), and in variant B it stops at
  721.11 against the best set's 721.22 by D: the mana stats' weights across a discrete event of the fight (20.5's open
  point) move between the iterations. Not built (20.5).
- **The tool's `out/items.lua`**: the worktree has no `../data` to rebuild it (`tools/preraid/data/` is not in git); the run
  takes the copy the groups A–C runs used (998420 bytes; 3922 candidates in variant A, 3914 on 2026-11-16).

### 23.2 Numbers (my run of `tools/preraid/rescore/rescore.lua` on a copy of the tree after step D, `sR/rs/out/out.txt`)

Variant A: current 732.06 DPS, best by D 739.74 (+7.69; Star of Mystaria 12103, Gordok's Gloves 18368, Ranger's Belt
272397, Ironbark Staff 20220), the addon's SetValue fixed point the same set. Variant B: current 715.32, best 721.22
(+5.91; Bone Golem Shoulders 18686, Beastmaster's Bindings 226885, Ranger's Belt 272397, Ring of Demonic Guile 18314,
Flameslash Crescent 280056), the fixed point 721.11 (+5.79; Shroud of the Nathrezim 18720, Staff of Jordan 873 in place of
the shoulders and the main hand). The run took about 30 minutes for both outputs side by side. The 2026-11-16 run (the
levelling model's +3 pass: A 508.8) is not comparable: the raid fight, the consumables and the boss's debuffs changed the
model since.

## 24. Steps 13, D and 14's review: what changed, and the points left open

Two reviews of the three steps' commits; each finding re-checked against the code, this design and the sources, one
commit a fix on `raid-mode`.

### 24.1 The ticks' noun in the form of their count

The dot line of 17.4 wrote «× %d тиков» whatever the count: «× 3 тиков», «× 4 тиков» for 33 of the 98 dot entries (24 of
3 ticks, 9 of 4; my count over `Game/ProcData.lua`). `A.RuPlural(n, one, few, many)` picks the form by Russian's rule for
a whole count (one: n mod 10 = 1, n mod 100 not 11; few: n mod 10 of 2 to 4, n mod 100 not 12 to 14; many: the rest),
the three forms the ruRU client strings' plural markers name (`|4ячейка:ячейки:ячеек;`, which `Core/Parse.lua`
`resolvePlurals` saw unresolved in game, so the addon picks the form itself); «(%.1f тика между срабатываниями)» keeps
«тика», the form of a fractional count. Test: test_game `dot tooltip: …` (the fireball's «6 ед. × 3 тика» and the forms of
0 to 25, 101, 111, 112, 114, 121, 122); mutants (6, killed): «тиков» always, 11 as one, 12 to 14 as few, few up to 5,
the count not taken mod 10, 12 alone kept from few.

### 24.2 An entry of a fixed direct damage links by the amount its line states (DA4)

- **Found**: an entry whose direct damage has Variance 0 (`Game/ProcData.lua` min = max above 0) never linked in game.
  Its tooltip shows one number ("наносящей 150 ед. урона от темной магии"), and Parse reads a proc's damage only as a range
  (`PROC_DAMAGE_PATTERNS`: "X - Y", "от X до Y", "X to Y"), so the line stayed an effect "not counted", no proc came of it,
  and 17.4's link by the direct part's mean had nothing to match: Demonshear 13348 (measured 1.1 a minute, EV-0003; 17.2
  names it) and 12992 (80 and a dot, a carry-over row) priced 0, the direct part and the dot, and so did the direct
  entries of one number with a rate since step 9 (4.6.2). 122 entries are of a fixed direct damage, 31 of them with a rate
  (my count over `Game/ProcData.lua`, `revfix/fixed.lua`): 13348 and 12992 with a dot, and 29 direct ones, 10 of them
  measured (6220, 9418, 9478, 9639, 11744, 11803, 17766, 18388, 275441, 276419) and 19 with a wowsims override row or the
  DB2's equip rate (754, 942, 1481, 2256, 2912, 2942, 5028, 5182, 8190, 13051, 13054, 13060, 17704, 17780, 19019, 19099,
  19100, 223964, 227683). wowsims prices them: Demonshear's proc is registered with its spell's damage at 1.1 a minute
  (`sim/common/forever/stat_bonus_procs_auto_gen.go:4407-4413`, the row `tools/database/overrides/weapon_procs.go:70-76`),
  Meteor Shard 6220's at 1.55 (`weapon_procs.go:190-196`, EV-0119; its Firebolt 1292152 deals 42 of no Variance,
  `sim/core/spelldata/spells_auto_gen.go:35638-35640`). 22.3's numbers for Demonshear came from a probe that built the proc
  from its entry, past `Items.Get`.
- **Built** (DA4): `Items.LinkProcs` links an entry of a fixed direct damage that no parsed proc links to the one line of its
  kind Parse leaves not counted (a "Chance on hit:" line with no damage range for "hit", an "Equip:" line Parse reads
  nothing of for "equip") that states its amount as damage, `Parse.StatesDamage` (ruRU "N ед. урона", "N ед. <word>
  урона"; enUS "N damage", "N <word> damage": the words `PROC_DAMAGE_PATTERNS` reads after a range), a line no other such
  entry of the kind claims; its proc takes the entry's mean as its direct damage and its dot. Then the dot-only link of
  17.4 takes the lines left. A linked line is marked `effect.linked` (17.4's `effect.dot`), which «эффекты не учтены» skips.
  My check of the rule on the DB2 (`revfix/fixeddesc.py`: each fixed entry's shown spell's ruRU and enUS descriptions,
  `db2_ru/Spell.csv` and `db2/Spell.csv`, their `$s` tokens at the effects' base points): 117 of the 122 state the amount
  so in both locales, every one of the 31 with a rate among them; the other five (10760, 17111, 19353, 19968, 276631)
  have no rate and stay "not counted".
- **Not built**: Parse reading a single amount as a proc's damage. A damage over time states its tick the same way ("24
  ед. урона от сил природы раз в 1 сек."), and Parse prices an unlinked proc by its text (A14), so a dot-only line would
  become a direct proc of its tick. The amount is read only against the entry that names it.
- **Tests**: test_game `fixed link: one not-counted line that states the entry's amount links it; another amount, two lines,
  two entries leave it unlinked` (made-up entries: the ruRU and enUS forms, a word between «ед.» and «урона», 43, 142 and
  «броню на 42 ед.» against 42, two lines, two entries on one line, a range entry against a line of its min, an equip entry
  on its «Если на персонаже:» line and not on a chance-on-hit line, a fixed entry with a dot beside a dot-only entry on two
  lines and on one, a parsed match kept); test_game `fixed link: Demonshear's 150 with its dot and Meteor Shard's 42, from
  their real lines, are priced` (the Survival tree: both linked, the direct line «1.10/мин …», the dot line «34 ед. × 3
  тика за 6 с», «1.55/мин …», no effect left not counted; both fail before the change: no proc). Moved: test_game `dot
  link: …` (`effect.linked` for `effect.dot`). Mutants (17, killed): no fixed link; a line two entries claim links; the
  first of two lines; a linked line still open; an entry a parsed proc links linked again; any number taken as the amount;
  the proc without its avg; a range entry by its min; an equip entry on a chance-on-hit line; no kind check; the line not
  marked; Advisor reading `effect.dot`; no enUS form; no word between; a plain find of the amount («142» for 42); the
  dot-only link over every line; the first entry of a shared line linked.
- **Numbers** (`revfix/linkprobe.lua`: `sD/dotprobe.lua`'s points, the proc from `Items.LinkProcs` and the real ruRU line):
  Demonshear 7.207 DPS at L44 SV (direct 4.486, dot 2.721) and 6.450 at L60 raid SV (3.980, 2.470), 22.3's numbers, 0 in
  the addon before; Meteor Shard 0.723 and 0.654 (1.037 and 0.976 procs a minute), 0 before. Rot-Covered Harpoon 4.300 /
  3.754 and Gatorbite Axe 4.834 / 5.814 through the dot-only link, as 22.3.

### 24.3 The stat multipliers of aura 80 A_MOD_PERCENT_STAT

- **Found**: 4.8 and step 13 read the multipliers of aura 137 A_MOD_TOTAL_STAT_PERCENTAGE alone. wowsims multiplies a stat
  by aura 80 A_MOD_PERCENT_STAT the same way (`sim/core/spelldata/parse_effects_table.go:311-312`: A_MOD_PERCENT_STAT →
  `percentStatRow`, A_MOD_TOTAL_STAT_PERCENTAGE → `totalStatPercentRow`; :807-813: both `p.statMultiplier(…,
  core.MultiplierFromPercent(v))`), and buffs a hunter's sheet can hold carry it: Sayge's Dark Fortune of Agility 23736 and
  its Forever spell 1304780 (+10% Agility, misc 1), of Strength 23735 / 1304782, Intelligence 23766 / 1304772, Spirit 23738
  / 1304775, Elune's Blessing 26393, Celebrate Good Times! 26035 and Festival Fortune! 26462 (+10% to all five, misc −1;
  `db2/SpellEffect.csv`, my query `revfix/a80.py`). Under Sayge's Agility the sheet counts an item's 10 Agility as 11 and
  HGA counted 10: O8 (the live sheet's stat multipliers count) held for aura 137 alone.
- **Built**: `tools/gen_stat_mult_data.py` reads the positive Effect 6 effects of aura 80 too, their stats by the first misc
  value alone (−1 all five, 0..4 one: `percentStatRow`'s `clientStatList(e.Misc)`, :807-809, which reads no mask), with
  the same checks (Effect 6 of DifficultyID 0, a first misc value of −1..4, a stat once a spell across both auras).
  `Game/StatMultData.lua`: 58 spells (36 before; the 22 new: 16734-16738, 23735-23738, 23766, 24705, 26035, 26393, 26462,
  460906, 466312, 1304772, 1304775, 1304778, 1304780, 1304782, 1327754). Negative effects stay out, as 4.8 says
  (Resurrection Sickness 15007 −75%, a debuff the reading meets on the sheet: a point for the user, below).
- **Tests**: `tests/test_gen_stat_mult_data.py` 15 → 24: aura 80's Sayge's Agility 23736 and Elune's Blessing 26393 from
  their build 70888 rows, aura 80 reading the first misc value alone (1 and 8: Agility), its negative points left out,
  aura 80 and aura 137 of two stats on one spell, and an aura 137 effect of −1 with a mask of 2 (Agility alone: the review's
  case, a mutant that reads −1 before the mask survived before); stops: aura 80 on another Effect, its first misc value
  outside −1..4, aura 80 and aura 137 of one stat on one spell. test_game `stat multipliers: Snapshot …`: the rows of
  1304780 and 26393, Sayge's Agility up (AGI 1.1 alone), with Elune's Blessing (AGI 1.21, the others 1.1). Mutants (8,
  killed): aura 80 not read; aura 80 reading the mask; −1 read before the mask; aura 80's negative points kept; aura 80's
  Effect unchecked; the duplicate check off; the data rows of 1304780 and 26393 removed.

### 24.4 Tests the review found missing

- **Curse of the Elements and Gift of Arthas by the tick's school** (22.1: a magic school on the melee or ranged table takes
  the curse by its school): test_score `dot proc: the application rolls the table once, …` pinned the raid factors on a
  bleed of the melee table and a poison of the magic table alone, so a curse by the DefenseType (1, or 0 with a magic
  school) and a gift by DefenseType 2 survived. It now prices in raid a magic school on the ranged and on the melee table
  (×1.10, no gift) and a physical school on the ranged and on the magic table (+8, no curse); the levelling case's label
  says coe 1 there. Mutants (4, killed): the curse by the DefenseType, the gift by DefenseType 2, the gift on every tick,
  the curse on every tick.
- **The stacking stop's boundary** (17.4: a CumulativeAura above 1 stops): `tests/test_gen_proc_data.py` stopped on 3
  alone, so `> 2` survived; 75 → 77: CumulativeAura 2 stops, CumulativeAura 1 writes the dot. Mutants (2, killed): `> 2`,
  `> 0`.
- **Aura 137's mask over a first misc value of −1**: 24.3.

### 24.5 Comments

The dot tooltip test's comment spoke of a change («no longer counts»): it says what holds (24.1's commit). The header of
`tools/preraid/rescore/rescore.lua` named the branch it was written on, and its `nocreature` and AP_CREATURE comments named
`Model.AP_CREATURE_SHARE` (0.3) as the raid pass's share: they say what the tool does in raid mode (the boss a dragonkin by
`Model.TargetShare`, convert.py's untyped AP_CREATURE at `UNTYPED_SHARE` 0, the two outputs alike, 23.1).

### 24.6 Points found, not built (for the orchestrator and the user)

- **Versus bonuses of a creature type** (built by group G, 25.2; one review: «design-deviation»): wowsims multiplies a proc spell's damage, the
  periodic one included, by its versus bonus against the target (`tools/database/overrides/spell_overrides.go:172-180`
  `VersusBonus`, rows :184-292; `sim/common/shared/shared_utils.go:689` `damageConfig.VersusBonus = ItemVersusBonus(…)`;
  `sim/core/spell_result.go:464-467` `CalcPeriodicDamage`: `baseDamage *= spell.VersusBonus.Against(target)`). Four rows
  name a creature type, which HGA models (`Model.TargetShare`), not a family: Rend 14118 (Drakefang Butcher 12463,
  measured 1.5 a minute, EV-0003) ×2 against Dragonkin, the raid boss's type (answer 5 = (a)); Smite 1299631 (Lightcrest
  Hammer 276419, measured) ×2 and Gloves of Holy Might 1325229 ×3 against Undead; Serpentbane 1295039 ×2 against Beasts
  (and the Serpentine family; no `Game/ProcData.lua` entry names it). 17.1 / DA3 left versus bonuses out as needing "a creature family HGA does not model", and 4.6.4 the
  Tablet's (a family: Naga, Satyrs); the type rows do not need one. Building them changes DA3 and 4.6.4's "Left out" (the
  generator reading `VersusBonuses` as data, `Score.ProcValue` taking `1 + Model.TargetShare(type, mode) × (factor − 1)`
  on the base damage, Gift of Arthas after it), so it is not built here. Size (`revfix/drakeprobe.lua`, my arithmetic for
  the doubled tick, the +8 not doubled): Drakefang Butcher at L60 raid SV, a 3.4 s two-hander, 6.887 DPS today, 12.022 with
  the tick doubled.
- **Negative stat multipliers on the sheet** (settled by the orchestrator and built by group G, 25.6; a review's note): 4.8 takes positive effects alone; Resurrection Sickness
  15007 (aura 80, −75% all stats) and «Coward!» 422978 (aura 137, −20%) are debuffs a sheet can show. wowsims multiplies by
  any row; whether HGA should price gear under such a debuff is the user's call (O8 names buffs).
- **An aura always kept secret** (the step 13 report, confirmed by a review): if the client keeps the state of one of
  `Game/StatMultData.lua`'s 58 auras secret always (`C_Secrets.ShouldSpellAuraBeSecret`), the reading is always hidden;
  only the game shows it (the API documentation gives no list), as for the Use spells.
- **DA1 and a proc of an internal cooldown longer than its dot, or of a 100% chance** (built by group G, 25.3; a review's note: 228666, 45 s and a
  10 s dot; 9483, every Auto Shot): none of them is priced (a chance of 100 is no rate, `Score.ProcRateSource`); E[n]'s
  Poisson stream would need a dead time once one has a rate.
- **Bisecting** (a review's note): `tools/preraid/rescore` stopped at load from `f57ed7b` (step 13) to `f59aea6` (step 14,
  23.1); the test suite does not run the tool.

## 25. Group G: the points left open, built the wowsims way

Group G runs after the review of steps 13, D and 14 (HEAD `38f02d0`) and builds the points left open in 18.10, 19.4,
20.5 and 24.6, by the user's rule «берем как в вов симс»: each as wowsims does it; where wowsims states nothing, HGA's
behaviour stays and the subsection says so. One commit a point on `raid-mode`, this design in the same commit. Numbers
marked (my run) come from probes under `C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/gG`
(`pts.lua` holds the points: the L60 BM and SV raid points of `refpoints.lua`).

### 25.1 The weights across the consumables' fits (20.5)

- **The rule** (wowsims, 7.4): the mana potion and the rune fire only when their maximum fits under the maximum mana after
  5 s of the casting regen (`sim/common/shared/consumable_potion.go:257-266` ShouldActivate, `382-388` fits). So the fight's
  damage jumps where a stat moves the pool, the regen or the spend across a fit: at the L60 BM point (regen 15 / 7.5) the
  total goes 585.81 → 619.55 between the pools 2280 and 2290 (the potion) and 518.77 → 571.34 between 1525 and 1550 (the
  rune, both uses). A finite difference across such a jump divided by its step was 20.5's W.INT 23.7, W.MANA 2.20, W.MP5
  −15.1 and W.SPI −17.9. wowsims states no item weight of its own (it runs the fight); HGA's weights are derivatives
  (6.9), so the design takes 20.5's first option.
- **Built**:
  - `Model.FightEvents(p)` gives the fight's consumables' events, `{ manaPotion = whether it fired at 125 s, runes = the
    rune's times }`; `Model.Fight` returns them as `events`.
  - A raid input `p.events` (optional, that form; levelling or another form is an error) holds them: the mana potion at
    125 s fires as held; the rune is used as many times as held, the k-th at its fit, or else, from the k-th held time on,
    at an instant of 0 mana, where its room is the whole ceiling, the largest it reaches (the limit of its fit time as the
    fit closes on the ceiling: in a falling stretch the fit time tends to the instant the mana runs out); a use past the
    held count never comes. The fight marks `deviated` where a held decision differs from the one its fit takes; with a
    point's own events held no branch differs, the same fight to the bit.
  - `Model.Weights` takes every derivative at a point holding that point's own events: the point, and the points of the
    expertise, hit, spell hit, ranged skill and melee weapon weights (each its own events); a held fight that deviates at
    its own point is an error.
  - `Model.EventGain(q, events)` = `Model.Total(q)` less the fight at q with `events` held, 0 (one run) where nothing
    deviates.
  - Advisor `ctx.eventGain(stats)` = `Model.EventGain` at the model point with `stats` applied (`Model.ApplyStats`) against
    the model point's events, over unitDps, one run a distinct stats table (26.3: none for stats with no key of
    `Model.EventKeys`, none for stats whose projection on those keys a run found to change no event); `Score.SetValue` (raid) adds
    `ctx.eventGain(the set's amounts of Model.FIGHT_KEYS less the worn set's, items and set bonuses, each key whose
    difference is not 0)`, so the worn set adds 0. `tools/preraid/rescore/rescore.lua`'s ctx gives the same values (one run
    a distinct stats table, without 26.3's projection: an offline tool).
- **Which stats**: the keys `Model.ApplyStats` moves an input by in raid mode (`Model.FIGHT_KEYS`). Hit, spell hit and
  expertise, priced by their caps, stay out; the weapons and the Use buffs run the fight whole (`ctx.weaponGain`,
  `ctx.useGain`, their own events in it); the set's cross terms are left out (A6).
- **The second Bestial Wrath** (6.9's other switch) is not held: no jump of the held fight was found along the pool 1300-4000
  by 2, the casting regen 2-30 by 0.05 at the pools 1600, 2000 and 2600, Intellect 0-300, Agility 0-300 and haste 0-20% at
  the BM point, and the pool and the regen at the SV point: every step of the held total within 4 times the median step,
  while the free total jumps at each consumable's fit (my runs of `gG/jumps.lua`).
- **Numbers** (my runs of `gG/scan1.lua`, `gG/scan2.lua` at the BM point, before → after): at the pool 2140 W.INT 23.72 →
  2.850; 2190 W.MANA 2.200 → 0.1228; 2290 W.MP5 −15.14 → 3.921, W.SPI −17.92 → 1.405; 1400 W.INT 39.24 → 3.110; 1450
  W.MANA 3.737 → 0.1400. Over the pools 1400-3600 by 5: W.INT [2.67, 39.24] → [2.67, 3.11], W.MANA [0.111, 3.74] → [0.111,
  0.140], W.MP5 [−28.0, 5.44] → [3.71, 5.44], W.SPI [−31.0, 2.13] → [1.28, 2.13]; the largest step between neighbours now
  6.8% (INT), 10.0% (MANA), 15.8% (MP5), 17.3% (SPI), each where the point's own events change (1535 → 1540 the rune, 2285
  → 2290 the potion); at the SV point W.INT [4.59, 79.09] → [4.59, 6.34]. The set level (my run of `gG/cross1.lua`): at the
  pool 2200 the exact gain of 10 Intellect, 236.75 in RAP, is W.INT × 10 (28.47) + the event's change 208.29; of 10 MP5 at
  2290, −151.35 = 39.21 − 190.57 (the casting regen lifts the potion's fit past the pool, wowsims' rule); of 10 Intellect at
  1500, 390.63 = 31.02 + 359.61 (the rune). For one stat the two parts make the exact gain to 1e-3; with 20 Agility beside
  10 Intellect a cross term of 0.39 of 295 is left out (A6). The reference points do not move (none sits by a fit).
- **Cost** (my runs of `gG/perf.lua`: the fake env at 60, 16 worn and 40 bag pieces, State, Plan and 50 tooltips): BM State
  15.3 → 21.7 ms, Plan 26.7 → 97.3 ms, tooltips 9.3 → 13.3 ms; SV 32.7 → 42.0, 71.0 → 201.7, 21.7 → 24.3 ms (26.3 takes
  the Plan back to 28 and 73 ms).
- **Tests**: test_model `raid events: Model.FightEvents; …` (the events, a point's own held, the potion held both ways, the
  rune held at the instant of 0 mana past its time, at its held time, not before its fit with mana left, a use past the
  count, the input's checks) and `raid weights hold the point's events: …` (each mana weight near its neighbours across
  both fits; W.INT × 10 + `Model.EventGain` the exact gain); test_score `raid events: ctx.eventGain takes the set's stats …`;
  test_game `raid events: a bag neck whose Intellect makes the mana potion fit …` (the env at a pool of 2250). Moved:
  test_score's two raid ctx tables take `eventGain`. Mutants (20, all killed): the weights not held; the potion's held
  decision ignored; a rune past the held count; the forced rune without the 0 mana, without its held time, without the
  starved stretch's stop at it; the falling fit past the count; `Model.EventGain` 0 or reversed; no deviation from the
  potion; no check of the input in either mode; the worn set not subtracted; the set bonuses left out; every stat key
  taken; a key of 0 kept; the gain not added; Advisor without the stats applied, without unitDps, a gain for no stats.
  `Model.EventGain` without its no-deviation return gives the same value (the two fights are one): a mutant of speed alone.

### 25.2 Versus bonuses of a creature type (24.6)

- **The rule** (wowsims): a gear proc's damage spell takes the versus bonus of its trigger's row
  (`sim/common/shared/shared_utils.go:678-690` applySpellDataDamageProc: `damageConfig.VersusBonus = ItemVersusBonus(…,
  trigger)`; a weapon's chance on hit is its own trigger, `stat_bonus_procs_auto_gen.go:4247-4252` for Drakefang Butcher),
  whose factor is the row's Multiplier, else the base points of the row's EffectIndex (`sim/core/spelldata/versus.go:18-33`),
  against a target of the row's mob types or families, 1 against any other (`sim/core/versus_effects.go:18-24` Against);
  the base damage takes it before the attacker's multipliers, the direct one (`sim/core/spell_result.go:442-445`
  CalcDamage) and each tick (`464-467` CalcPeriodicDamage); Gift of Arthas comes after the multipliers (5.3). Gloves of
  Holy Might 867 is wowsims' own code (`sim/common/forever/items_armor.go:97-125`), its factor on the damage spell 1325229.
  The rows: `tools/database/overrides/spell_overrides.go:182-292` `VersusBonuses`.
- **Built**: `tools/gen_proc_data.py` reads the `VersusBonuses` rows as data (`read_versus_bonuses`; the mob types by
  wowsims' proto names, `proto/common.proto:544-554`, onto HGA's `Model.CREATURE_TYPES`, any other an error) and puts each
  row's mob types onto the entries whose trigger is the row's spell (`attach_versus`: `versus = { factor, types }`; the
  factor above 1, one row an entry, the EffectIndex's effect unique, else a stop). `Game/ProcData.lua` regenerated: Drakefang
  Butcher 12463 (Rend 14118, ×2 against Dragonkin, DB2 SpellEffect 1324263), Lightcrest Hammer 276419 (Smite 1299631, ×2
  against Undead, SpellEffect 1323966), Gloves of Holy Might 867 (1325229, the Multiplier 3 against Undead); Serpentbane
  1295039 (×2 against Beasts) names no entry: it is Serpentbane Crown 274609's Use (`stat_bonus_cds_auto_gen.go:265-266`
  NewSpellDataDamageOnUse), an on-use damage HGA does not price. `Items.LinkProcs` carries `versus`;
  `Score.VersusFactor(proc, mode)` = 1 + share × (factor − 1), share the sum of `Model.TargetShare(type, mode)` over the
  row's types (raid 1 for the boss's dragonkin, 0 for any other; levelling 0.3 a type; more than 1 an error), the mean of
  wowsims' factor over the mode's targets; `Score.ProcValue` takes it on the direct base and on the tick before own, the
  armor or Curse of the Elements and Gift of Arthas; `Model.ProcOutcomes` returns the mode it reads. The tooltip adds «HGA:
  урон эффекта ×N против драконов — в рейд-режиме цель дракон: учтено ×2» (or «не учитывается»), levelling «… — при
  прокачке доля таких целей 30%: учтено ×1.30» (wowsims states no UI).
- **Families stay out**: 11 rows name creature families alone (the Tablet's Naga and Satyrs, Rot's Aquatic, the Plants of
  Grass Killer and the like) and Serpentbane's Serpentine beside its Beasts. HGA models creature types alone
  (`Model.CREATURE_TYPES`, `Model.TargetShare`), and its targets name no family: the preset's raid target sets a mob type
  and no family (`ui/specs/hunter/dps/defaults.siml:61-71`), and the levelling targets are a share of each type (4.5). DA3
  and 4.6.4 now say so.
- **Numbers** (my runs of `revfix/drakeprobe.lua` on group G's commit 1 and on this one; the proc built through
  `Items.LinkProcs` from its real ruRU line): Drakefang Butcher at L60 raid SV 6.887 → 12.022 DPS (the tick ×2 before own,
  the +8 after it: 24.6's arithmetic), at L44 SV 5.649 → 7.343 (×1.3); Lightcrest Hammer ×1.3 below 60 and as before at 60.
  Gloves of Holy Might stays unpriced: its DB2 item effect is a chance on hit with no rate (U4), while wowsims' own code
  rolls 1330855's 15% with a 20 s internal cooldown (`items_armor.go:119`), a trigger this generator does not read (found,
  not built: the rate of one item outside the versus rows).
- **Tests**: test_score `versus: a proc's base damage, direct and periodic, x 1 + share x (factor - 1) …` (the three rows,
  the factor by the mode, three types summed, more than every target an error, the bleed's tick ×2 before own and the gift
  in raid and ×1.3 in levelling, Smite's direct part, a physical direct part before the armor); test_game `versus: Drakefang
  Butcher's Rend x2 against dragonkin and Lightcrest Hammer's Smite x2 against undead …` (their real lines link with the
  bonus; the value against the same proc without it; the tooltip at 60 and 44); `tests/test_gen_proc_data.py` 77 → 90 (the
  rows read, the factor of an effect and a Multiplier, families left out, the trigger's alone, the result lists; stops: an
  unknown mob type, no Source, no type or family, no or two effects of the index, a factor of 1, two rows on one entry).
  Mutants (20, all killed): Python 8 (no types read, the index ignored, the Multiplier ignored, matched by the damage spell,
  families taken, no stop on an unknown type, a factor of 1 taken, two rows taken); Lua 12 (no factor, the factor after the
  gift on the direct part or on the tick, none on the direct part, none on the tick, the levelling share in raid, the first
  type alone, no check of the share, no versus linked, no mode in the outcomes, no tooltip line, the raid text).

### 25.3 Procs on every matching hit, a 100% chance, a cooldown longer than the dot (18.10, 24.6)

- **The rule** (wowsims): an equip aura whose ProcChance column reads 100 or 101 and whose tooltip states no chance in its
  trigger clause has the store's ProcChanceSource ProcChanceAlways (wowsims' generator, `tools/database/spelldata_hints.go:
  87-127`; a tooltip that says the effect only sometimes happens makes it ProcChancePPM, a rate owed), StatedChance 1
  (`sim/core/spelldata/resolve_proc.go:187-199`): its trigger fires on every hit of its mask, an internal cooldown aside; a
  stated procs per minute is the manager instead (`fillProcChance`, `resolve_proc.go:203-209`). Its generated registration
  is labelled "every time" (`sim/common/forever/stat_bonus_procs_auto_gen.go:4077-4081`, Hurricane 2824).
- **Built**:
  - Parse (`ALWAYS_PROC_PATTERNS`): the "Equip:" lines of the auras wowsims registers so, as their DB2 descriptions read
    in both locales (Hurricane 1316319, the bombs 1318069 / 1318123, Fiery Plate Gauntlets 7721, Blazefury Medallion 7711,
    Storm Gauntlets 16615, Force Imbued Gauntlets 1302248), become equip procs: their damage a range (`procDamage`) or a
    single amount (`procAmount`: "N ед. урона", "N <word> damage", and 7711's ruRU "уронаот огня на 2 ед.", the number
    after the words), their hits the mask's among Parse's ("ranged" for the ranged auto attacks, "melee" for the melee swings
    and abilities). Crest of Retribution 17495 (on a block) stays an equip effect.
  - `tools/gen_proc_data.py --registrations --store`: `read_every_time` reads the "every time" damage registrations
    (active or commented out, their ItemVariant rows), `store_sources` the triggers' ProcChanceSource, `attach_always`
    marks `always = true` on the equip entry of each active registration's item and trigger (the store's ProcChanceAlways,
    a ProcChance of 100 or 101 and no override rate, else a stop); a trigger with a stated procs per minute keeps it
    (Lord Sakrasis' Scepter 5028: ppm 2). `Game/ProcData.lua`: always on 11 entries, Hurricane 2824 (the Auto Shots), Fiery
    Plate Gauntlets 12631, Storm Gauntlets 12632, Blazefury Medallion 17111, Force Imbued Gauntlets 18383 (the melee swings
    and abilities), Iceblade Hacker 13952, Warblade of Caer Darrow 13982 and Dreadfrost Saber 274603 (the main hand's melee
    swings and abilities: 26.2), Crest of Retribution 13375 (a block: no hunter hit rolls it), the Satchels of Iron and Dark
    Iron Bombs 285277 / 285278 (thrown weapons: HGA counts no thrown attack); 2 registrations name items with no equip entry
    here (two block procs, 7726's 1293539 and 276742's 1308777).
  - `Items.LinkProcs` carries `always`; `Score.ProcRateSource` gives such a linked equip aura `100, "always"` after
    `MEASURED_PPM` and an override row; `Score.ProcRate` prices it as a chance of 100 a hit of its mask, the internal
    cooldown a dead time, `r / (1 + r × icd)`; the tooltip says «на каждом попадании — как в wowsims».
  - `Score.DotTicks(dot, perMinute, land, icd)`: no landed application comes within the cooldown, and past it the trigger
    fires at its rate without the dead time, `r = r_eff / (1 − r_eff × d)`: `E[n] = Σ_k (T k ≤ d ? 1 : e^(−r × land × (T k −
    d)))` (my arithmetic; DA1 extended), so a cooldown as long as the dot or longer deals every tick; `Score.ProcValue`
    passes an equip aura's cooldown, 0 for a chance on hit.
- **Unpriced, as wowsims**:
  - Flaming Incinerator 9483: its trigger 1294530's tooltip reads «Chance on hit to light the target ablaze» (db2
    Spell.csv), so wowsims' store makes it ProcChancePPM and its registration is commented out «unsupported: states no rate»
    (`stat_bonus_procs_auto_gen.go:657-664`): no rate. 24.6's "every Auto Shot" is its mask (64), not its chance.
  - 228666: its trigger 462628 has no row in wowsims' spell store and no registration names the item. Its 45 s cooldown
    against its 10 s dot gives every tick once a rate exists; there is none.
  - The items whose trigger the store marks ProcChanceAlways but which no wowsims registration names (Frostburn 276631
    «against Frozen targets», Cursed Murloc Eye 273840, Thorncurse 274159, Sear 273003, 19968, 227865, 227870, 284703, the
    Copper and Bronze Bombs 285275 / 285276) and Swine Fists 10760, wowsims' own code, which fires against a Swine alone
    (`sim/common/forever/items_armor.go:67-95`, a creature family, 25.2).
  - A weapon's chance-on-hit spell the store marks ProcChanceAlways (Bloodrazor 809's Rend and the like) is a weapon
    proc: wowsims rolls it at its WeaponProcs rate and registers none without one (the commented "every time"
    registrations with `IsWeaponProc`): unchanged (U4).
- **Numbers** (my runs of `gG/alwaysprobe.lua`: the test env, the real ruRU lines, commit 2 → this one): Hurricane in the BM
  env at 60 0 → 26.65 procs a minute, 3.852 DPS, the bow's delta 63.94 → 91.64 in RAP; at 44 0 → 27.16 a minute, 3.853 DPS,
  82.62 → 110.84; Blazefury Medallion in the Survival env at 60 0 → 25.07 a minute, 0.800 DPS, delta 0 → 11.00; at 44 0 →
  27.66, 0.928 DPS, 0 → 9.55. No priced dot proc of build 70888 has a cooldown (9483 and 228666 alone have one, both
  unpriced: my grep of `Game/ProcData.lua`), so the dead time moves no number today.
- **Tests**: test_parse `parse: the lines of a proc on every hit are equip procs of their amount and their mask's hits, …`;
  test_score `always: an equip aura wowsims rolls on every hit of its mask, …` (the data, masks 64 and 20, a 1 s cooldown,
  no rate without it, the measured rate first, the dot's ticks past a 45 s and a 3 s cooldown and with none, the checks,
  the equip aura's cooldown in its value); test_game `always: Hurricane's icy bolt on every Auto Shot and Blazefury
  Medallion's fire on every melee hit, …`; `tests/test_gen_proc_data.py` 90 → 102 (the registrations read, the store's
  source, the marks, the stated rate, the commented one; stops: the column under an every-time registration, no store row,
  a ProcChance of 5, an override rate, no item, no end). Moved: every `Score.DotTicks` call of the tests takes the cooldown
  (0). Mutants (25, all killed): Python 7 (a commented registration active, any constructor, the store's default, no store
  check, a stated rate marked, no chance check, no item stop); Lua 18 (no always rate, always before the measured rate,
  always as a procs-per-minute rate, no dead time in the ticks, the effective rate past it, the ticks within it lost, the
  ticks from the application, the cooldown 0 in the value, no check of the cooldown or of the rate, no always linked, no
  always line read, no single amount, no number after the words, every single amount physical, Hurricane's ruRU line
  dropped, a melee line as "any", no tooltip text).

### 25.4 Quick Shots inside Rapid Fire (19.4)

- **The rule** (wowsims): Quick Shots 6150 is Deadly Aspects' proc on each Auto Shot (`sim/hunter/aspects.go`), 2% a rank,
  for 12 s (`CONST.quickShotsDuration`), so its uptime at an instant is the chance that one of the Auto Shots of the last 12 s
  rolled it; inside Rapid Fire's window the Auto Shots come 40% faster and more of them roll it.
- **Built** (`Core/Model.lua` partsAndHits): the turret's `shots12`, the Auto Shots in Quick Shots' 12 s, takes the state's
  own Rapid Fire in a state of the raid fight, `12 × rangedSpeed × 1.3 × haste × (1 + rf) / bowSpeed` (rf 0.40 inside the
  window, 0 outside), so a Rapid Fire state holds its own uptime, not the time outside it (19.4). The shots' speed, the
  hawks' (which take Quick Shots, W1D 7) and the casts that follow them move with it. The Survival weave already takes
  Quick Shots from its cycle at the state's speed (`weaveParts` cycleAt: `1 − (1 − c)^(12 / C)`, C the cycle at the state's
  Rapid Fire): unchanged, now pinned. Levelling's averaged pass keeps the Auto Shots at the speed without Rapid Fire (HGA's
  levelling estimate; wowsims has no levelling mode): unchanged.
- **Numbers** (my runs of `s13/refpoints.lua`, commit 3 → this one): L44 Cat 270.6990 and L44 SV 265.0675 unchanged; L60
  raid BM 643.5405 → 644.6749 (auto 196.544 → 197.255, hawks 72.822 → 73.103, aimed 70.254 → 70.347; W.HASTE 27.4506 →
  27.4632, W.HASTE_RATING 14.9524 → 14.9805, W.AGI 2.7441 → 2.7434, W.CRIT 39.1196 → 39.0838); L60 raid SV 605.1628
  unchanged (the weave); the test_game env at 60 374.7043 → 375.3434. At the test point of Deadly Aspects 5 (10% an Auto
  Shot, a 2.6 s bow, quiver 13%) the uptime is 0.6322 inside Rapid Fire against 0.5105 outside, the Auto Shots 1.4443
  times as many (my arithmetic).
- **Approximation** (named by group G's review, 26.1): each state takes the steady uptime of its own Auto Shot rate, while
  the uptime at an instant follows the Auto Shots of the last 12 s, which at the window's edges hold shots of the other
  rate. At the test point (my arithmetic, the shots before the window at the rate without Rapid Fire): inside the window
  0.586 against the state's 0.632, in the 12 s after it 0.574 against 0.510; the uptime's integral over 5-32 s 15.68
  against 15.61 s: part of the window's uptime lands in the 12 s after it.
- **Tests**: test_model `raid Quick Shots: each state's uptime from its own Auto Shot rate, …` (the turret's Auto Shots
  inside Rapid Fire at the state's own uptime, the weave's at each cycle, levelling's hawks with Rapid Killing's average in
  their speed alone). Moved: test_model `raid Gift of Arthas: attempts at Quick Shots, …` (Quick Shots' uptime by the
  state's rf, re-derived) and `raid events: …` (25.1's rune times at the raid point, 25.77 → 25.92 s, re-derived from
  the fight). Mutants (4, all killed): the uptime without Rapid Fire (the old rule), the levelling average in it, Rapid
  Fire counted twice, the weave's cycle with Rapid Fire counted again.

### 25.5 The HHA sequence with no bow, gun or crossbow at 60 (19.4)

- **The rule, re-read** (wowsims): a sequence is ready only while its current step is, and advances only past a step it
  casts (`sim/core/apl_actions_sequences.go:63-87`: IsReady reads `subactions[curIdx]`, Execute moves `curIdx` on a cast);
  the BM rotation resets the HHA sequence only once it is complete (`apls/turret_hawk.apl.siml:15-16`), and its other Summon
  Hawk line wants Use Arcane Shot false (`:17`; the preset sets it true, `:8`). Arcane Shot is cast through its spell data
  (`sim/hunter/arcane_shot.go:14-15` `spelldata.SpellConfig`), whose cast requirement holds its SpellEquippedItems row
  (`sim/core/spelldata/resolve_spell.go:270-283`; `sim/core/equip_requirement.go:26-45`: the ranged slot's weapon of the
  subclass mask 262156, bows, guns, crossbows). So with no bow, gun or crossbow the sequence casts its two Summon Hawks and
  waits at Arcane Shot for good: two hawks, two dives, then none for the rest of the fight (my reading, not run).
- **Built** (raid mode; `Core/Model.lua` fight, partsAndHits): a build that shoots from range (not the Survival branch, which
  casts no Summon Hawk) with `p.noShots` and Summon Hawk casts its first hawk at 0 s and its second when the category's 6 s
  are over (`CONST.raid.hawkCategory`, SpellCooldowns 54834 / 99423) and the rotation looks, the tempo's wait with no other
  GCD action, the poll's 0.1317 s (6.4, A1): 6.1317 s; each lives 18 s. The fight cuts at the casts and the hawks' ends, and
  each state holds `seg.hawks` hawks up (0, 1 or 2: the uptime `hawks / 2`, no dive of its own, no HHA cycle); the two dives
  are the fight's own damage (each its state's `tempo.diveHit` over 180, both before 175 s where the weight is 1) and two
  landed ranged specials (procs, Judgement of Wisdom); each Summon Hawk a one-off cost, 189 less its dive's 29.5 of
  Judgement of Wisdom. Such a fight has no cast of its own, so its rich D is 0 or less and it starves only in a debt of
  one-off costs (a made-up pool), which repays at the regen out of the five-second rule (`regenRest` and the free hits'
  Judgement of Wisdom: the one-off's own 5 s of casting regen left out, my approximation; it is reached by no level-60 pool,
  1440 + 15 Intellect against the 465.5 of one-off costs in the first 6.2 s, my arithmetic). Levelling's averaged pass keeps
  its HHA cycle with Arcane Shot's element in it (HGA's levelling estimate; wowsims has no levelling mode).
- **Numbers** (my runs of `gG/hhaprobe.lua`, commit 4 → this one): test_model's rich raid point with no bow 216.72 → 166.20
  (the hawks 39.87 → 5.25, the dive 17.71 → 1.82, the mean hawk uptime 0.9785 → 0.1); refpoints' L60 BM point with no bow
  271.24 → 202.71 (hawks 55.57 → 7.11, dive 22.28 → 2.21). With a bow every number stays: L60 raid BM 644.6749, SV 605.1628,
  L44 270.6990 and 265.0675, the env at 60 375.3434; W.SKILL_CRIT_NO_SHOTS (the crit of what attacks with no shot) falls at
  L60 raid BM 0.2288 → 0.0227 and at the env at 60 0.2281 → 0.0242.
- **Tests**: test_model `raid HHA with no bow, gun or crossbow: the sequence stops at Arcane Shot after its two hawks; …` (the
  hawks up by the segment, the second hawk at 6.1317 s and its end, the mean uptime 0.1, no HHA cycle, the two dives in
  their states, two landed specials, both costs less their Judgement of Wisdom, the cycle with a bow, none without Summon
  Hawk, levelling's dives at 2 / C0, a debt repaid at the regen out of the five-second rule). Mutants (13, all killed): the
  cycle kept (the old rule), one hawk, no wait, no cut at a hawk's end, no cost, the cost without the dive's Judgement of
  Wisdom, no dives, no landed specials, a hawk's uptime whole, the cycle's dives kept, the cycle's means kept, the debt at
  the casting regen, the debt an error. The guard of a state's hawks outside this case (partsAndHits) is an invariant no
  input reaches.

### 25.6 A stat-lowering aura on the live sheet (24.6)

- **The rule** (the orchestrator's, as HGA treats a Use buff): wowsims multiplies a stat by an aura 80 or aura 137 row of
  negative points as by any (`sim/core/spelldata/parse_effects_table.go:807-813`), but HGA prices gear on the character's
  own sheet (answer 2: the live sheet; O8 names the buffs), and a sheet under Resurrection Sickness 15007 (aura 80, −75%
  every stat) or «Coward!» 422978 (aura 137, −20%) is not it. So while such an aura is up the new reading is stale and
  the last reading of the same gear and talents without it serves; with none the state is not ready and says why.
- **Built**: `tools/gen_stat_mult_data.py` writes `ns.StatDebuffData` beside `ns.StatMultData` in `Game/StatMultData.lua`:
  every spell with an Effect 6 effect of aura 137 or aura 80 of negative points (`stat_debuffs`; one on another Effect or
  DifficultyID stops), 22 spells of build 70888 (Resurrection Sickness, «Coward!», Cripple, Dredge Sickness, Curse of
  Vengeance and the like; `StatMultData` unchanged). `Player.StatDebuffState()` is whether one of them is up on the
  player (`auraState`: nil when the client says its aura would be secret). `Player.ReadStats` takes no new reading while
  one is up or unknown: the last reading of the same level, gear and talents with `staleBy = "debuff"`, or nil and the
  reason "debuff" (the order "hidden", "debuff", "useBuff"). Advisor waits on it as on a Use buff (`WAIT_STATE`: its
  aura state every second, one re-read once it is known off); the tooltip and `/hga` say «на персонаже аура, снижающая
  статы (Resurrection Sickness и т. п., или игра её скрывает) — оценка появится, когда она спадёт», `/hga weights` with a
  stale reading «статы — последнее чтение с этой же экипировкой и талантами: на персонаже аура, снижающая статы …»
  (wowsims states no UI).
- **Tests**: test_game `debuff: a reading under Resurrection Sickness keeps the previous weights; …` (the data, the last
  reading's crit, attack power and weights under the aura, the weights line, an aura kept secret, the live reading once
  it falls, at login with no earlier reading none and the tooltip's text, no re-read while it is up, the re-read once it
  falls); `tests/test_gen_stat_mult_data.py` 24 → 28 (the debuffs once, sorted, the positive ones none, another aura none;
  stops: another Effect, another difficulty). Mutants (10, all killed): the aura not read, an unknown state taken as off,
  the reason "hidden", no wait, the wait on the Use buffs' state, no tooltip text, no weights line; the generator writing
  none, the positive ones, no check.
- No model number moves (a reading without such an aura is as before).

### 25.7 `/hga weights` names the spell hit and the spell crit (group 0's open point)

- **Built** (wowsims states no UI): the weights line prints `меткость заклинаний 1% <W.SPELL_HIT> (до капа ловушки
  <ctx.spellHitCap>%), крит заклинаний 1% <W.SPELL_CRIT>` after the expertise: the value of a point of spell hit below
  Immolation Trap's cap (`Model.TrapHitCap`, 17% at +3) and of a point of spell crit (18.8), both 0 outside the Survival
  weave.
- **Tests**: test_game `spell hit: ctx.baseSpellHit is the live spell hit less the worn set bonus's; …` (the line with both
  weights and the cap 17.0% at 60). Mutants (3, all killed): the two swapped, the hit cap in place of the trap's, no spell
  crit.

### 25.8 Left as they are

- **The negative `W.HASTE_RATING` at the Strider Kick step**: a property of wowsims' weave (18.3), a finite difference across
  a real step; the weight stays and prints as it is.
- **Multi-Shot's 0.5 s cast hidden in the stand at the shooting spot** (WA5): kept.
- **The twins 228542, 228573, 228029, 209436**: unpriced under U4, wowsims having no rate for them (18.6, 22.1).
- **An aura always kept secret** (24.6): only the game shows it; a stat multiplier's or a stat-lowering aura's state the
  client always keeps secret keeps the reading the last one (or none) for good.
- **Gloves of Holy Might 867** (25.2; listed here by group G's review): wowsims prices it by its own code
  (`sim/common/forever/items_armor.go:97-125`: trigger 1330855, 15% with a 20 s internal cooldown, ×3 against Undead), a
  trigger `tools/gen_proc_data.py` does not read; HGA's entry has no rate (U4 names the override files as the rate's
  source), so it stays unpriced: for the orchestrator and the user.

## 26. Group G's review: what changed, and the points left open

Two reviews of group G's seven commits (`327e634` … `5838579`); each finding re-checked against the code, this design and
the sources. Probes under `C:/Users/Admin/AppData/Local/Temp/claude/5d742c03ef588fd5/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/gGfix`.

### 26.1 Tests the review found missing, and the comments

- **Each weight's own point holds its own events** (25.1): no test pinned it; every side point's `hold` could go. test_model
  `raid weights: each weight's own point holds its own events, …` bisects the casting regen for a point that sits just
  inside the potion's fit while its step lies outside it and takes the weight there against the derivative with the point's
  events held: the BM raid point's W.HIT (my run: the fit at a casting regen of 33.78, held 23.86 against free 46.51) and at
  a Survival raid point with expertise 2, spell hit 3, a ranged skill 4 over the maximum and Resourcefulness 3 W.HIT,
  W.EXPERTISE, W.SPELL_HIT, W.SKILL_CRIT (Resourcefulness reads the shots' crit, so the skill's crit moves the casting regen)
  and W.HIT_DW (fits at 5.38, 3.04, 2.74, 2.71 and 2.69; the free derivatives 19 to 39 units off). Two holds are equivalent,
  their step moving no input of the mana (my runs of `gGfix/parry.lua`: the segments' mana bit for bit, at the BM and two
  Survival raid points): the parry's point (past the dodge only the tanking pet's parry, and the raid pet stands behind the
  boss: W.EXPERTISE_PARRY 0) and the melee weapons' (a weapon's DPS). Mutants (7): 5 killed, the parry's and the melee
  weapons' equivalent.
- **`Model.FIGHT_KEYS` against `Model.ApplyStats`**: test_model `raid events: Model.FIGHT_KEYS holds every item stat key that
  moves an input of the raid fight, and no other` applies each of 38 item stat keys at the BM raid point with Careful Aim and
  at a Survival raid point and asks that a key is listed exactly when it moves an input, but every AP_VS_<TYPE> (listed;
  it moves `p.apVsTarget` at its raid share alone, the dragonkin's). And the Spirit across the potion's fit at the pool 2290
  (test_model `raid weights hold the point's events: …`): `Model.EventGain` below 0, W.SPI × 10 + it the exact gain to 1e-9
  (my run: −116.604 = 8.860 − 125.464). Mutants (4, killed): no SPI, no HASTE, no ARMOR_PEN, no AP_VS keys.
- **The cache key of `ctx.eventGain` holds the amounts** (test_game `raid events: a bag neck …`): 1 Intellect at the pool
  2250 leaves the potion out, its gain 0 after the 20's. Mutant (killed): the key of the names alone.
- **The checks of 25.1** (test_model `raid events: …`): `p.events` with a time that is not a number, a key past the list, a
  key 0, a key 1.5 inside the list, a key that is no number; `Model.FightEvents` and `Model.EventGain` of a levelling point,
  `Model.EventGain` of a point with held events; the fight's own checks where it starts (a missing pool or haste, a missing
  level with no bow, which the stuck HHA sequence reads first, and `p.uses` of 5, whose windows it builds first), each
  through `Model.FightEvents`, `Model.EventGain` and `Model.Weights` with the input's own message. Mutants (10, killed): the
  number check, the key check down to its type, without `k < 1`, without `k > #runes`, without the whole-number check,
  `Model.EventGain`'s two checks, `Model.FightEvents`' mode check, the fight's `checkInputs`, its `checkMode`.
- **The reasons' order "hidden", "debuff", "useBuff"** (25.6; test_game `debuff: …`): Resurrection Sickness and Nat Pagle's
  Broken Reel's buff up together give "debuff" (the check waits on the stat-lowering auras), then "useBuff" once it falls,
  then the live reading; both up at login, none with the reason "debuff". Mutant (killed): "useBuff" before "debuff".
- **The enUS amount's school** (25.3, Parse procAmount; test_parse `parse: the lines of a proc on every hit …`): "N <word>
  damage" magic for the school words alone, a made-up Physical line and 16615's "Lightning" physical. Mutant (killed): the
  enUS amount always magic.
- **Comments**: `Model.Weights`' comment spoke of the old weights («priced Intellect at 23.7»), and the fight's comment of
  the point «the events were taken at»: both say what holds.
- **Named by the review**: 25.4's approximation of the window's edges; Gloves of Holy Might in 25.8.

### 26.2 Procs of the main hand alone (25.3)

- **Found** (both reviews, «design-deviation»): wowsims registers three "every time" damage procs of the main hand alone,
  Iceblade Hacker 13952 (1298413 → 1298414, 40.7 Frost), Warblade of Caer Darrow 13982 (1298500 → 1298499, 27.72 Frost of
  Variance 0.4) and Dreadfrost Saber 274603 (1294939 → 1294940, 1 Frost), each `ProcMaskMeleeMHAuto |
  ProcMaskMeleeMHSpecial` (`sim/common/forever/stat_bonus_procs_auto_gen.go:4423-4437, 4677-4683`; DB2 SpellAuraOptions
  246321, 246336, 248286: ProcChance 100, ProcTypeMask_0 20, ProcTypeMask_1 32). `tools/gen_proc_data.py` skipped them
  ("hand bits"), so 25.3's rule, as wowsims, missed them, and Dreadfrost Saber's line, which 25.3's pattern for 1302248
  reads, stayed an unlinked proc whose tooltip said wowsims prices no rate for it.
- **The rule** (wowsims): ProcTypeMask_1's 0x20 (PROC_FLAG_2_MAIN_HAND_ONLY) drops the off hand's melee bits from the mask
  (`sim/core/proc_types.go:222-224`), whatever slot the item sits in (the listener takes the row's decoded
  mask, `sim/core/spelldata/resolve_proc.go:32-51`); the three are main-hand weapons (Item.csv InventoryType 21, 17, 21), so it hears
  their own hand's hits.
- **Built**: the generator writes such an equip aura with `mainHand = true` (word 0's hand bits, which no equip aura of
  build 70888 holds, stay a skip; another bit of word 1 beside 0x20 stops); `Game/ProcData.lua` regenerated: the three
  entries, each with `always` (their registrations), the two Frost spells of 1298413 / 1298500 on the melee table
  (SpellCategories DefenseType 2), 1294940 on the magic table; no other entry moves. `Items.LinkProcs` carries `mainHand`;
  `Score.ProcRate` drops the off hand's white swings from mask 0x4 for it; Parse reads 1298413 / 1298500's lines («Атаки
  этим оружием в ближнем бою наносят …», "Melee attacks with this weapon deal …": ALWAYS_PROC_PATTERNS, a range or one
  number), 1294939's by 1302248's pattern; the tooltip says «на каждом попадании правой руки — как в wowsims». Every active
  "every time" registration's item that Parse reads now has its entry; the two left without one are block procs (25.3).
- **Numbers** (my runs of `gGfix/mhprocs.lua` at `gG/pts.lua`'s points, the entries as linked; the reference points carry
  none of these items and do not move): at the L60 raid SV point (a 3.6 s two-hander) the Warblade 117.37 RAP (13.01 DPS of
  605.16), the Hacker 172.32 RAP (19.10 DPS), the Saber 3.63 RAP (0.40 DPS); at the L60 raid BM point 0 (no melee). The
  reviewer's `rev-G/probes/dreadfrost.lua` (the Survival env at 60): the Saber and the Warblade linked, 11.51 and 27.54
  procs a minute in their sets.
- **Tests**: test_parse `parse: the lines of a proc on every hit …` (the three lines, ruRU and enUS, a range and one
  number); test_score `always: …` (mask 20 of the main hand: the off hand's swings out; the three entries' mainHand,
  always and mask, Blazefury Medallion's none); test_game `main hand: Iceblade Hacker's, Warblade of Caer Darrow's and
  Dreadfrost Saber's frost on every main-hand hit, …` (their real lines linked with always and mainHand, the rate 60 × the
  set's main-hand swings and abilities beside an off hand that swings, the tooltip); `tests/test_gen_proc_data.py` 102 →
  104 (the main-hand bit written as mainHand, none without it; a stop on another bit of word 1 beside it).

### 26.3 The cost of `ctx.eventGain` (25.1)

- **Found** (a review, «minor»): `ctx.eventGain` ran the raid fight once a distinct stats table, so a Plan at 60 ran it
  150 times in the BM env and 165 in the Survival env (`Model.EventGain` 49 of the Plan's 82 ms and 113 of 188), after each
  fight and each loot (`BAG_UPDATE_DELAYED`, `PLAYER_REGEN_ENABLED`: `ns.Invalidate` → `Swap.Refresh` → `A.Plan`), while
  every one of them returned 0. wowsims states nothing on this (it runs the fight); the values stay HGA's 25.1.
- **The rule** (my reading of `Core/Model.lua`): the fight's events are the mana's decisions (the fits of 7.4, `fight`),
  and the mana reads the pool (`manaMax`), the regens (`regenRest`, `regenCast`, `spirit`), each cast's rate and landed hits
  (`manaFlow`: the casts' costs and Judgement of Wisdom's landed hits) and, through Resourcefulness' buff, the casts' crit
  (`castingRegen`: `(1 − 0.5 × rank × crit)^…`, 1 with the talent at 0). So a set's stats move an event only by the keys
  that move those inputs, `Model.EventKeys(p)`: the attack speeds (HASTE, ATTACK_SPEED, HASTE_RATING, MELEE_HASTE,
  RANGED_HASTE), INT, SPI, MP5, MANA and, with Resourcefulness, AGI, CRIT, CRIT_RANGED; the attack powers (AP, RAP, MAP,
  STR, AP_VS_<TYPE>), ARMOR_PEN and SPELL_CRIT (Immolation Trap's ticks, a cast that rolls no Resourcefulness) move the
  damage alone. Whether the held fight deviates is then a function of the stats' projection on those keys.
- **Built**: `Model.EventKeys(p)` (raid mode alone); `Model.EventGain` returns the fight's deviated beside the gain;
  `ctx.eventGain` gives 0 with no run to stats with no key of `Model.EventKeys`, and 0 with no run to stats whose
  projection (their amounts of those keys) a run found to change no event; else it runs the whole stats as before (two
  runs where an event changes, the cross term of the other keys in the gain), one run a distinct stats table. No value
  moves: a stats table it skips is one whose held fight runs as the model point's, where `Model.EventGain` gives 0.
- **Numbers** (my runs of `gG/perf.lua` and `gGfix/perf_eg.lua`, the reviewer's probe passing the second value on, on a
  copy of the tree at the commit before this one → this one, 5 and 3 runs): BM Plan 82.4 → 28.2 ms, `Model.EventGain` calls
  in a Plan 150 → 1; SV Plan 187.4 → 72.8 ms, 165 → 1; State and the 50 tooltips unchanged (18.8 / 11.0 and 39.6 / 22.4
  ms). Every tooltip's delta and every plan row of both envs (`gGfix/dumpplan.lua`) the same to 1.2e-11, the noise of one
  tree run twice (Lua 5.4's hash order sums the stats in another order: 52 differing lines of 59 between two runs of one
  tree).
- **Tests**: test_model `raid events: Model.EventKeys are the keys whose inputs the fight's mana reads, …` (at the BM raid
  point at 2140 and three Survival raid points at 2000, without and with Resourcefulness and with a 3.8 s two-hander: the
  keys listed exactly; each key of `Model.FIGHT_KEYS` outside them leaves the fight's mana bit for bit, each key in them
  moves it at one of the points; levelling an error; `Model.EventGain`'s second value false at 1 Intellect, true at 10);
  test_game `raid events: a bag neck …` (the runs counted from a fresh state: none for no stats, for Agility, attack
  power, Strength and armor penetration in the BM tree, for 1 Intellect and 50 attack power after 1 Intellect's run; a run
  of its own for 20 Intellect and 50 attack power, its gain the whole stats', the attack power's cross term in it).
  Mutants (15): the skip of no key, the projection's cache, the cache on a deviating projection, the projection as the
  whole key, every fight key as an event key, the key without its amounts, the crit always and never, no INT, no
  MELEE_HASTE, AP and SPELL_CRIT as event keys, the second value true and missing, `Model.EventKeys`' mode check: all
  killed.

### 26.4 Left open (for the orchestrator and the user)

- **Quick Shots and the HHA sequence while levelling** (a review's note): levelling keeps Quick Shots without Rapid Fire's
  average speed and the HHA cycle with Arcane Shot's element when no bow is worn (25.4, 25.5: HGA's levelling estimate,
  wowsims having no levelling mode); the user's «mechanics as wowsims in both modes» may ask otherwise: the user's call.
- **The tooltip of an event's change** (a review's note): a set whose stats make the mana potion fit (a neck of 20 Intellect
  at a pool of 2250: +169.6, ~+24.0 DPS, the review's run) gains the potion's change with no word of it on the tooltip; wowsims states no UI.
- **`C_UnitAuras.GetPlayerAuraBySpellID` and the stat-lowering auras** (a review's note): its API documentation (Forever
  UnitAuraDocumentation.lua:397-411) does not say whether it returns a harmful aura (Resurrection Sickness is one), and if one of the 22 spells is always secret the state is never known
  (25.8); only the game shows either.
- **`tools/preraid/rescore`** is not run here: the worktree has no `tools/preraid/data` (as the review found).
