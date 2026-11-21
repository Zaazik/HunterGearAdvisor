# W1 — HGA checked against wowsims/forever (2026-11-16)

Two-way comparison of HunterGearAdvisor's damage model and gear scoring with the wowsims/forever hunter sim
(github.com/wowsims/forever, master as of 2026-11-16; web UI www.wowsims.com/forever/hunter/dps/). wowsims code was
read, never run. Every finding was checked by a second, independent verifier against the primary data: Forever DB2
build 1.60.1.70888 (wago.tools), the Forever UI source and API docs, and wowsims' own in-game log evidence
(`docs/evidence/EV-*.md`). Each fix then went through adversarial review rounds (a reviewer per commit and one for the
whole branch, mutation-checked tests).

Columns: **direction** = what the finder claimed (ours_missing / ours_wrong / theirs_wrong / unclear_who / by_design);
**verdict** = the verifier's result; **right** = which side the primary data supports.

## Findings

| id | finding | direction | verdict | right | HGA action |
|---|---|---|---|---|---|
| stats-gear-1 | Set bonuses ignored; a worn set's hit stayed in the base hit after the set was broken | ours_missing | confirmed | theirs | Fixed: bonuses of every set from DB2 ItemSet / ItemSetSpell, profession rank, set steps in the plan (dd1ef52, c7ad4d2, 31bb76e) |
| stats-gear-2 | A weapon type not yet levelled is scored as if its skill were at the level maximum | ours_missing | confirmed | theirs | Fixed for ranged weapons: skill per line, skillOffset, the 5 x level zero point, ranged-only weights, a no-shots set at the level's skill (4de9e20, dfe84d5, 1cb7712, 7d80acf, 10f2f32); the melee skill lines by wowsims' attack table too (raid-mode W1 design 3; 427b65f, 60ea133, 4cb32fb) |
| stats-gear-3 | Item scoring ignores the candidate weapon's speed | ours_missing | confirmed | theirs | Fixed: weapons run through the model at their own speed (ef7ed04) |
| stats-gear-4 | On-use effects and stat procs get no value; damage procs use a flat 1.5 PPM where measured rates run 0.6-3.75 | ours_missing | confirmed | theirs | Fixed: Use buffs (UseData, one per Use spell), measured PPM from the EV files, Equip procs, proc rates on the landed hits of the scored set's own weapons, each hand at its weapon's speed (4de9e20, 59220b0, b2c6ede, 5f1ddaf, ab07913); procs from the DB2 by trigger mask and DefenseType (raid-mode design 4.6, 7c3cb1b); no rate made up: measured, else wowsims' override row, else the DB2's, else not priced, re-issued twins included (U4 = (a), f155584); DoT procs priced as wowsims prices them (U2 = (a), raid-mode design 17, 4d30a5b) |
| stats-gear-5 | Armor multiplier a constant 0.70; Forever data gives about 0.71 up to level 35 and 0.61 from 45 | ours_wrong | confirmed | theirs | Fixed: creature armor by level from ExpectedStat (b63f422) |
| stats-gear-6 | Ranged weapon DPS worth about 12% more RAP in ours than in wowsims' turret weights | unclear_who | uncertain | unknown | Closed (raid-mode W1 design 9): wowsims' figures are EP presets of a simulation and it states no rule for a weight; the weights stay HGA's analytic derivatives |
| stats-gear-7 | Weapon skill on gear: 0.04% hit + 0.04% crit a point (Forever UI) vs wowsims' Classic slope; melee skill lines get no value | unclear_who | uncertain | unknown | Closed with wowsims' attack table (raid-mode W1 design 3, the user's rule for W1's open questions): each hand's miss, dodge, glance and crit suppression by its own skill, the ranged hand (b874063) and the melee hands with their skill lines and set bonuses (427b65f, 60ea133, 4cb32fb) |
| stats-gear-8 | No crit suppression against higher-level targets | unclear_who | uncertain | unknown | Closed the wowsims way (raid-mode design 4.2, 560856e): 1% a level of the difference, and at +3 the aura crit up to 1.8% (EV-0090, Classic Era logs; no Forever log); the target is +3 at 60, the hunter's own level below |
| stats-gear-9 | Melee table: 0.95 glancing on every white swing, dodge fixed at 5%, no parry | ours_wrong | confirmed | theirs | Fixed: glancing and dodge by mob level, parry on the tanking pet (b63f422); the white swings of the hunter, the pet and the hawks as one roll, the crit capped by the room left (wowsims OutcomeExpectedMeleeWhite; raid-mode design 4.3, 1db4d89) |
| stats-gear-10 | SAF-T scope "+2% Crit" and the Beastslaying enchants not parsed | ours_missing | confirmed | theirs | Fixed (4de9e20, dfe84d5) |
| stats-gear-11 | Haste weight 6.0 Agi per 1% vs their 8.0; hunter haste passed to the pet | unclear_who | refuted | unknown | Haste priced by scope (all / melee / ranged) from the worn enchants, set bonuses and Wind Blessed (f249083), weights as the value of one more source (dcc5173); the pet takes the owner's permanent and melee haste over its own measured swing (b07454b) |
| stats-gear-12 | Int, MP5, Spirit have no damage value | by_design | refuted | not_applicable | At 60 (raid mode) the mana as wowsims: it limits the casts, and Int, MP5, Spirit and mana get a damage value through the raid fight (the user's answer 4 = (b); raid-mode design 7, 29e870c-0935dfe); below 60 mana stays a tie-break |
| stats-gear-13 | Their weave values the two-hander far higher (raid setup, weave timing) | by_design | refuted | not_applicable | The Survival branch weaves as wowsims' SV Weave preset (raid-mode design 15, 05b810d); buffs stay the live sheet (the user's answer 2 = (a)) |
| ranged-1 | Our haste weight is 25-35% under wowsims' Turret EP; other ranged weights agree within ~10% | unclear_who | uncertain | unknown | Haste priced by scope (f249083, dcc5173); closed (raid-mode W1 design 9): wowsims' EP presets are simulation output, no rule for a weight; the haste sources take wowsims' paths (raid-mode W1 design 7, a597962): an item's or enchant's aura 342, a set bonus's and Wind Blessed's attack speed, haste rating |
| ranged-2 | Aimed Shot has no GCD / cast competition factor, Arcane has one (0.9) | ours_wrong | confirmed | theirs | Fixed: Aimed / Sniper share of their cooldown (b63f422) |
| ranged-3 | Multi-Shot missing: at 18-19 (Multi known, Aimed not yet) a 6 s cooldown shot is left out | ours_missing | confirmed | theirs | Fixed (b63f422) |
| ranged-4 | Serpent Sting uptime 0.8 vs ~95-98% in their turret | by_design | confirmed | not_applicable | At 60 the raid fight re-casts Serpent Sting when it falls, its uptime from the fight's cast tempo (raid-mode design 6.4, 1d24ae4); below 60 the solo 0.8 stays |
| ranged-5 | At 60 the model assumes the book ranks Serpent Sting IX (135/tick) and Aspect of the Hawk VII (120) for everyone | ours_wrong | confirmed | theirs | Fixed: book ranks only when learned (b63f422) |
| ranged-6 | Rapid Killing's after-kill bonus (+10/20% to the next shot) missing; solo it fires on every mob | ours_missing | confirmed | theirs | Fixed (b63f422) |
| ranged-7 | Improved Arcane Shot with Summon Hawk: wowsims shortens the shared Arcane/Hawk timer after Arcane, ours keeps 1/18 | unclear_who | uncertain | unknown | Closed with wowsims' rule (raid-mode W1 design 6): the HHA cycle 18 - 0.3 x rank s, Arcane 1 / C0, the dive 2 / C0 (c8fb4c4); zero for the user's build (IAS 0) |
| ranged-8 | wowsims' weave rotations take Multi-Shot over Aimed; ours keeps Aimed at any meleeFrac | by_design | confirmed | not_applicable | The Survival weave casts Multi-Shot in its range looks, as wowsims' SV Weave (U3 = (a), fda9136); the build that shoots from range keeps Aimed Shot in the shared cooldown (wowsims' BM preset) |
| ranged-9 | wowsims lets haste rating speed the GCD of Serpent Sting and Hunter's Mark but not Arcane Shot | unclear_who | refuted | not_applicable | None (theirs; irrelevant for gear) |
| pet-hawk-bm-1 | Pet white swings crit at the owner's full crit in both models; the only swing count we hold says about 0.35% | unclear_who | uncertain | unknown | Closed (raid-mode W1 design 4): the 0.35% count is trueshot's override (V1-verify-forever-pet.md:56), not a wowsims rule; wowsims gives the pet the owner's crit, now as its max(melee, ranged) branches (b874063, 427b65f) |
| pet-hawk-bm-2 | Hawk attack power counts ammo DPS in both models; EV-0073's numbers show bow DPS only | ours_wrong | confirmed | neither | Fixed: bow DPS without ammo (b63f422) |
| pet-hawk-bm-3 | Pet base white DPS linear 34 x level/43; DB2 creature DPS runs 12-22% higher from 41 | ours_wrong | confirmed | theirs | Fixed: ExpectedStat creature DPS (b63f422) |
| pet-hawk-bm-4 | A tanking pet can be parried; ours counted dodge only | ours_missing | confirmed | theirs | Fixed (b63f422) |
| pet-hawk-bm-5 | Hawk expertise: wowsims gives hawks the owner's expertise without a measurement | unclear_who | uncertain | unknown | Adopted: the hawks take the owner's expertise against dodge, as the pet (dcc5173); unmeasured (EV-0074 measures the hawks' hit only); closed: the same rule on both sides (raid-mode W1 design 8) |
| pet-hawk-bm-6 | Pet Claw/Bite DPS a fixed 12 x level/43; DB2 ranks give more from 43; Bestial Discipline should add Claws only | ours_wrong | confirmed | theirs | Fixed: Claw / Bite from DB2 ranks by the family's abilities (b63f422) |
| pet-hawk-bm-7 | The pet family's damage passive ignored (Cat/Raptor +10% ... Boar/Turtle -10%) | ours_missing | confirmed | theirs | Fixed: read with UnitCreatureFamily (b63f422) |
| pet-hawk-bm-8 | Read literally, DB2 gives the hawk dive +3 a rank of Unleashed Fury and +2 a rank of Ferocity as flat damage | unclear_who | uncertain | unknown | Closed with wowsims' rule (raid-mode W1 design 5): the flats in the dive's base before crit, armor and the multipliers, at every rank (3319f14) |
| pet-hawk-bm-9 | Hawk base swing 7.5 x level/43 instead of EV-0073's 0.185 x creature DPS | ours_wrong | refuted | theirs | Adopted EV-0073's rule anyway (b63f422) |
| pet-hawk-bm-10 | Orc Command multiplied with Unleashed Fury and given to the hawks in wowsims | theirs_wrong | confirmed | ours | None |
| pet-hawk-bm-11 | Rapid Fire speeds the hawks in wowsims, not in ours | unclear_who | refuted | unknown | Adopted: Rapid Fire's average reaches the hawks (f249083); unmeasured, and Rapid Fire 3045 carries the auras (140, 319) of Berserking, whose speed wowsims states does not reach a hawk |
| pet-hawk-bm-12 | Intimidation not modelled | ours_missing | refuted | theirs | None (irrelevant to gear ranking) |
| pet-hawk-bm-13 | No glancing on pet and hawk white swings in ours; the logs show hawk glances | ours_missing | confirmed | theirs | Fixed (b63f422) |
| pet-hawk-bm-14 | Pet share of the owner's AP: 10% (tooltip, sheets) vs 7.6% in EV-0071 | unclear_who | refuted | neither | None |
| pet-hawk-bm-15 | wowsims takes 0.04% pet crit off per missing weapon-skill point | theirs_wrong | refuted (raid-mode W1 design 4) | theirs | Corrected record: wowsims' max(melee, ranged) returns the ranged crit whole where the melee sheet crit is at least the ranged less 0.04%, and EV-0070 records no melee crit, so EV-0070 does not contradict it; HGA takes wowsims' rule (b874063, 427b65f) |
| melee-sv-1 | Weave as a fixed time share and no candidate weapon speed: a weaver's bow and 2H pairing ranked wrong | ours_missing | confirmed | theirs | Fixed the weapon speed (ef7ed04); the time share replaced: the Survival branch weaves as wowsims' SV Weave, no other build melees (raid-mode design 3, 15; a533624, 05b810d) |
| melee-sv-2 | Hit past the special cap worth nothing in ours; it keeps lowering dual-wield white misses | ours_wrong | confirmed | theirs | Fixed: W.HIT_DW, relative to the worn hit (b63f422, dfe84d5) |
| melee-sv-3 | Expose Prey also procs from ranged attacks; ours counted melee only | ours_missing | confirmed | theirs | Fixed for the weave (b63f422) |
| melee-sv-4 | Raptor Strike every 6.0 s instead of on the first swing after its cooldown | ours_wrong | confirmed | theirs | Fixed (b63f422, 401ad04) |
| melee-sv-5 | Lacerating Strikes: ours rolled the unticked bleed over; wowsims now has a new bite replace it | unclear_who | uncertain | unknown | Adopted wowsims' current rule, unverified in game (b63f422); closed: the same rule on both sides (raid-mode W1 design 8) |
| melee-sv-6 | Glancing 0.95 on every white swing; the formula gives 0.995 at equal level, 1.0 below | ours_wrong | confirmed | theirs | Fixed (b63f422) |
| melee-sv-7 | Mob dodge does not change with mobDiff or melee weapon skill | ours_wrong | confirmed | theirs | Fixed the level part, 0.5% a level (Forever UI BASE_ENEMY_DODGE_CHANCE, b63f422); the melee weapon skill per hand by wowsims' attack table (raid-mode W1 design 3, 427b65f) |
| melee-sv-8 | Wing Clip as a melee filler missing | ours_missing | confirmed | theirs | In the Survival weave where wowsims' SV Weave casts it (raid-mode design 15, 05b810d) |
| melee-sv-9 | Traps (and Clever Traps) ignored | by_design | confirmed | not_applicable | Immolation Trap in the Survival weave where wowsims' SV Weave casts it, Clever Traps included (raid-mode design 15, 05b810d) |
| melee-sv-10 | Bites after the hunter's dodge and Counterattack after its parry not modelled | by_design | confirmed | not_applicable | None |
| melee-sv-11 | Improved Tracking applied to all damage; game files limit it to tracked creature types | ours_wrong | refuted | theirs | None (gear-irrelevant) |
| melee-sv-12 | Resourcefulness mana uptime under what the game files suggest | ours_wrong | refuted | unknown | The comments name the DB2 chain (440529: the rank sets the trigger chance, 1242688 gives 50% regen for 30 s) (2e0bf3a); at 60 its uptime comes from the raid fight's ability crits (raid-mode design 7.3, df9eebc); below 60 the tie-break's 0.4 stays |
| melee-sv-13 | wowsims gives Strider Kick and Mongoose Bite the non-weapon special outcome, against its own rule | theirs_wrong | confirmed | not_applicable | None |

## Fixed in HGA

Commits on branch `wowsims-fixes`, oldest first:

- `b63f422` The damage model against wowsims and the DB2: creature armor and DPS by level (ExpectedStat), glancing and
  dodge by mob level, parry on a tanking pet, the Aimed / Sniper share of their cooldown, Multi-Shot at 18-19, book ranks
  only when learned, Rapid Killing, pet Claw / Bite from the DB2 ranks of the family's abilities, the family damage
  passive, hawk AP from the bow's own DPS, the hawk base swing from EV-0073, glancing on pet and hawk swings, Raptor
  Strike on the first swing after its cooldown, Expose Prey from ranged hits in the weave, Lacerating Strikes replaced by
  the next bite, the dual-wield hit weight W.HIT_DW.
- `ef7ed04` Weapons scored through the model at their own speed.
- `dd1ef52` Item set bonuses from DB2 ItemSet / ItemSetSpell.
- `4de9e20` Crit scopes, ranged weapon skill, measured proc rates from the EV files, Use buffs (UseData), Beastslaying.
- `401ad04` The pet's own swing time for Frenzy.
- `dfe84d5` Weapon pricing, Beastslaying and ranged skill corrections.
- `c7ad4d2` Set steps in the plan, the profession rank of a set, every DB2 set bonus.
- `59220b0` Use buff and measured proc rate corrections.
- `8a7d8ba` Pet swing corrections; secret Aspect of the Hawk / Trueshot Aura states.
- `1cb7712` The ranged slot, the worn skill's zero point, sets with no shots.
- `31bb76e` Plan set steps: subsets and losing parts.
- `a852359` A measured proc rate carried to a re-issued twin only at the measured weapon's speed.
- `b07454b` Pet swing keys and heartbeat; the owner's permanent haste divided out of the pet's measured swing.
- `eae4413` Worn Use buffs kept out of the live reading; a stale reading only for the same gear.
- `7d80acf` Ranged-only hit and crit weights, no hit clamps, no Ranged Weapon Specialization on the dive without a bow.
- `1907877` Plan part reduction, the both-hands part, one SetBonuses call per set (plan time about a third).
- `f249083` Attack speed by scope (all / melee / ranged), haste enchants parsed, Beastslaying at the model's swing rate,
  Rapid Fire's average on the hawks.
- `a8b956f` Stale readings keyed on talents, re-read when a Use buff falls, every UseData buff out of the live reading.
- `10f2f32` Sets with no shots at the level's skill, named weights required, ranged-only set crit.
- `3a551b0` Tests: the dual-wield both-hands plan part, one worn set with every mechanism.
- `dcc5173` Aura 342 reaches the hawks, haste weights as the value of one more source, the hawks take the owner's
  expertise.
- `a9a1f5d` The Use-buff timer reads the aura state only; `/hga weights` names why a reading is stale.
- `b2c6ede` The weights' unit where RAP adds no damage (melee AP, else DPS), one Use buff per Use spell, named weights read
  directly.
- `5f1ddaf` Damage procs at the hunter's landed hits by hand (white swings and specials), each hand at its weapon's base
  speed; the Highborne Research Tablet at its measured 2.5 s on every hand; the tooltip and `/hga dump` give the rate at the
  model point.
- `2e0bf3a` Expertise capped on the whole set (W.EXPERTISE the slope below the cap, a set's expertise priced up to the mob's
  dodge); `/hga weights` texts for Lone Wolf and a thrown weapon; the two attack-speed sums that add instead of multiplying
  documented; Resourcefulness comments follow the DB2 chain.
- `6a0a054` Tests: the Use-buff check with nothing rebuilding the state, the plan's and each row's DPS, a negative RAP
  derivative.
- `3213e50` The W.EXPERTISE comment, no nil guards in `/hga weights`, the expertise cap in `/hga dump`.
- `ab07913` Procs on the landed hits of the set being scored (each set's own weapons, one model run per weapon triple), Serpent
  Sting's applications rolling a weapon's proc with ranged hits, Raptor Strike's hits exactly 0 with one hand, the hand speed
  each measured rate is taken at, the Highborne Research Tablet's damage 69-81 (DB2 1265634).
- `b0ab6e2` The proc tooltip names the set its rate is in (now / if worn), no masking defaults on talent ranks, the EV-0122
  lines, test gaps.
- `f963167` Equip procs take no Serpent Sting application; the model inputs every producer sets are required; no masking
  defaults in the branch's code; tests split by what they assert.
- `fe7c21d` petOut a required model input, input type tests, the dump's ammo fields in two client states, a unique item
  without an id an error.
- `cb0924d` The same id rule for unique rings and trinkets, the dump's ammo fields apart, the quiver tooltip line under test.

Commits on branch `raid-mode` that close W1's open questions the wowsims way (`docs/superpowers/specs/raid-mode-w1-open-design.md`,
the user's rule of 2026-11-17 for them), oldest first:

- `3319f14` The dive's base holds Unleashed Fury's 3 and Ferocity's 2 a rank (pet-hawk-bm-8).
- `c8fb4c4` Improved Arcane Shot shortens the hawks' HHA cycle to 18 - 0.3 x rank s (ranged-7).
- `b874063` The ranged weapon skill by wowsims' attack table, the pet's ranged crit branch (stats-gear-7, pet-hawk-bm-1,
  pet-hawk-bm-15, pet crit from weapon skill).
- `427b65f`, `60ea133`, `4cb32fb` The melee weapon skill per hand, the pet's melee crit branch (stats-gear-7).
- `a597962` The hawk speed by wowsims' paths: attack speed and haste rating apart from an item's aura 342 (hawk speed,
  ranged-1).

Commits on branch `raid-mode` of the two modes and wowsims' mechanics (`docs/superpowers/specs/raid-mode-design.md`, the
user's decisions of 2026-11-17) that settle W1 entries, oldest first:

- `df2cdd9` The level difference of every attack table capped at +3.
- `a533624`, `05b810d` Melee for the Survival branch alone, as wowsims' SV Weave (melee-sv-1, melee-sv-8, melee-sv-9,
  stats-gear-13); `fda9136` Multi-Shot in the weave (ranged-8).
- `4d78c40` Beastslaying as flat damage on every weapon strike and shot (Beastslaying's flat damage).
- `560856e` Crit suppression against a higher-level target (stats-gear-8).
- `1db4d89` The white swings as one roll (stats-gear-9).
- `7c3cb1b` Procs from the DB2: the Highborne Research Tablet at each hand's speed, equip procs by their trigger mask,
  Serpent Sting's applications by the harmful-spell bit, damage by DefenseType (the Tablet, the equip mask, the
  application rule).
- `f155584` No proc rate made up (U4 = (a); stats-gear-4).
- `1d24ae4` Serpent Sting re-cast in the raid fight (ranged-4).
- `29e870c`-`0935dfe` The mana in the raid fight, Resourcefulness from the fight's crits (stats-gear-12, melee-sv-12).
- `4d30a5b` DoT procs as wowsims prices them (U2 = (a); stats-gear-4).

## Where wowsims is wrong (by its own evidence or the game data)

- **pet-hawk-bm-10 — orc Command.** wowsims multiplies it with Unleashed Fury and gives it to the hawks
  (`racials.go:282-289`, `summon_hawk.go:106`). DB2 20576 adds a flat 5 to the Tamed Pet Passive (8875) effect only —
  additive with UF, tamed pet only. Their own comment (`racials.go:277-279`) says the same.
- **pet-hawk-bm-2 — hawk AP.** wowsims adds ammo DPS to the hawks' 14 AP per weapon DPS; EV-0073's numbers fit the bow's
  own DPS (390 AP for a 27.32 DPS bow; with ammo it would be about 570). HGA had the same error; fixed.
- **melee-sv-13 — Strider Kick / Mongoose Bite outcome.** Their code gives these the non-weapon special outcome against
  their own rule for weapon-damage effects (`spell_outcome.go:300-302`). No effect from behind the target.
- **ranged-9 — GCD haste.** Haste rating speeds the GCD of Serpent Sting and Hunter's Mark but not Arcane Shot
  (school-based `IgnoreHaste`). Internal inconsistency; irrelevant for gear, since haste rating sits on four test items
  only (`Game/Player.lua` wornHaste notes).
- **Berserking against Quick Shots and Rapid Fire.** `sim/hunter/summon_hawk.go:63-65` states that Berserking's speed
  does not reach a hawk while Quick Shots' does. In the DB2, Berserking (20554, the Forever Troll racial) carries auras 319,
  140 and 65, Quick Shots 6150 aura 140 and Rapid Fire 3045 auras 140 and 319: by the auras the statement cannot hold for
  all three. No log settles it; HGA follows the statement for Quick Shots and Rapid Fire and does not model Berserking.

## Corrected records (raid-mode W1 design, 2026-11-17)

Two records once listed under "Where wowsims is wrong", corrected when W1's open questions went the wowsims way
(`docs/superpowers/specs/raid-mode-w1-open-design.md`):

- **pet-hawk-bm-15 — pet crit from weapon skill.** wowsims' pet crit is `max(0, melee, ranged)`, each branch the sheet's
  crit less 0.04% a point of its own hand's skill below the level's maximum (`sim/hunter/pets.go:142-153`). It returns the
  ranged crit whole wherever the owner's melee sheet crit is at least the ranged crit less 0.04%, and EV-0070 (a level 17
  pet sheet read the owner's ranged crit whole at 84 of 85 bow skill) records no melee crit, so EV-0070 does not
  contradict it (a reading of the code, not run). HGA takes wowsims' rule (design section 4; b874063, 427b65f).
- **Aura 342 takes two paths.** wowsims gives an item's or enchant's aura 342 the melee and the ranged speed
  (`sim/core/enchant_speed.go:13-41, 65-79`, `sim/core/spelldata/speed.go:14-20`), which reach the tamed pet and the
  hawks, and a set bonus's aura 9 or 342 and Wind Blessed the attack speed multiplier (`parse_effects_table.go:367-368`,
  `sim/core/racials.go:225-229`, MultiplyAttackSpeed `sim/core/unit.go:729-742`), which reaches the tamed pet and not the
  hawks; haste rating sits on the owner's totals alone (`sim/core/unit.go:564-566`). In the DB2 Wind Blessed 1259710, the
  Tier-1 two-piece bonuses and Minor Haste 13928 carry the same auras (342 and 65); HGA takes wowsims' paths (design
  section 7; a597962).

## Open questions (no primary data decides them)

None is left: the five once listed here went the wowsims way with the user's rule «берем как в вов симс» (2026-11-17;
`docs/superpowers/specs/raid-mode-design.md` section 4), below under "Closed the wowsims way". No Forever log decides any of
them still (see "Not checked").

## Closed the wowsims way (raid-mode W1 design, 2026-11-17)

The user settled W1's open questions: each goes wowsims' way where wowsims states a rule («берем как в вов симс»;
`docs/superpowers/specs/raid-mode-w1-open-design.md`, below "W1D", and `docs/superpowers/specs/raid-mode-design.md`):

- **stats-gear-6, ranged-1** No wowsims rule: its figures are EP presets, simulation output on a Marksmanship turret
  without a pet at the 8% cap (W1D 9). The weights stay HGA's analytic derivatives; the haste sources take wowsims'
  paths (W1D 7, a597962).
- **stats-gear-7** wowsims' attack table: each hand's miss, dodge, glance and crit suppression by its own skill
  (`sim/core/target.go:549-615`; W1D 3), the ranged hand (b874063) and each melee hand (427b65f, 60ea133, 4cb32fb).
- **ranged-7** wowsims' rule: the HHA cycle `18 - 0.3 x rank` s (W1D 6, c8fb4c4).
- **pet-hawk-bm-1** The 0.35% count is trueshot's override (`docs/research/V1-verify-forever-pet.md:56`), no wowsims rule;
  both models give the pet the owner's crit (W1D 4).
- **pet-hawk-bm-5, melee-sv-5, Ranged Weapon Specialization on the dive with a bow** The same rule on both sides (W1D 8).
- **pet-hawk-bm-8** wowsims' rule: the dive's base with 3 a rank of Unleashed Fury and 2 a rank of Ferocity (W1D 5,
  3319f14).
- **Hawk speed** wowsims' paths: a hawk inherits the owner's ranged speed multiplier alone (`sim/core/pet.go:415-431`):
  the quiver, aura 140 (Quick Shots, Rapid Fire, the ranged-only speed) and an item's or enchant's aura 342, not a set
  bonus's or Wind Blessed's attack speed and not haste rating (W1D 7, a597962). wowsims' statement on Berserking
  (`sim/hunter/summon_hawk.go:63-65`) agrees with these paths; HGA does not model Berserking.
- **Pet crit from weapon skill above and below 5 x level** wowsims' `max(0, melee, ranged)`: skill above the maximum gives
  the pet nothing, below it each branch loses 0.04% a point of its hand's skill (W1D 4; b874063, 427b65f). See the
  corrected record pet-hawk-bm-15.
- **Serpent Sting at a high melee share** The Survival branch weaves as wowsims' SV Weave, which casts the sting from the
  shooting spot (raid-mode design 15; W1D 8).
- **Rot-Covered Harpoon 274963's rate** The same rule on both sides: 1.45 a minute (EV-0122) at the speed of the hand that
  hits (`sim/core/procs.go:183-227`; W1D 8). Its Rot, a DoT, is priced as wowsims prices it since step D (the user's
  answer U2 = (a); RMD 17, 22; 4d30a5b): 24 Nature a 1 s tick for 7 s, its application rolling the spell table once, its
  ticks dealt until the next landed application (stats-gear-4).
- **Hit cap at +1 and +2 levels** The same rule on both sides: 5.5% and 6% (`sim/core/target.go:581-585`,
  `attack_table_test.go:46-47`; W1D 8); with W1D 3 a hand's cap moves with its skill.

The user's decisions of 2026-11-17 (two modes by the level; wowsims' side on every mechanic) close the rest, by
`docs/superpowers/specs/raid-mode-design.md` (below "RMD"):

- **stats-gear-8 — crit suppression.** wowsims' rule (`sim/core/target.go:504-512, 591-595`, `spell_result.go:211-231`):
  a physical crit roll loses 0.2% a point of the skill gap, 1% a level of the difference, and at +3 the aura crit up to
  1.8% more, from EV-0090 (Classic Era logs: no Forever log against a +3 target exists); in both modes (RMD 4.2,
  560856e).
- **The Highborne Research Tablet's chance per hit.** wowsims' legacy PPM manager with spells: each hand's hits at that
  hand's weapon's speed, every other hit of its mask but an Auto Shot at the main hand's (`sim/core/procs.go:62-82,
  183-227`, `items_trinkets.go:253-286`); `Score.MEASURED_SPEED` is gone (RMD 4.6.1, 7c3cb1b).
- **Serpent Sting's applications and a bow's proc.** wowsims' rules: a weapon's chance on hit hears every landed hit of its
  hand, the applications that deal no damage among them (WeaponProc, `resolve_proc.go:95-111`); an equip aura hears an
  application only where its mask's harmful-spell bit clears RequireDamageDealt (`proc_types.go:166-175`), never the
  Highborne Research Tablet, whose RequireDamageDealt wowsims forces (`items_trinkets.go:279-281`, EV-0021) (RMD 4.6.2,
  7c3cb1b).
- **An equip proc's own mask.** wowsims' rule: an equip proc rolls on the hits its DB2 ProcTypeMask names (white melee 0x4,
  melee abilities 0x10, Auto Shot 0x40, ranged abilities 0x100: `proc_types.go:86-110`); `Game/ProcData.lua` carries each
  equip aura's mask (`tools/gen_proc_data.py`), and its rate is its measured one, wowsims' override row or the DB2's (RMD
  4.6.2, 18.6; 7c3cb1b, f155584).
- **Beastslaying's flat damage.** wowsims' rule: the flat added to each physical weapon strike's and shot's base damage
  before the attacker's multipliers, armor and the outcome (`spell_result.go:236-246, 391-397, 445-466`), the set's main
  hand's and off hand's summed, at the mode's share of beasts: 0.3 while levelling, 0 against the dragonkin boss (RMD 4.5,
  4d78c40).
- **ranged-4, stats-gear-12, melee-sv-12 — the raid fight.** At 60 the 180 s fight of wowsims' preset: Serpent Sting re-cast
  when it falls (RMD 6.4), the mana limiting the casts with Intellect, MP5, Spirit and mana valued through it and
  Resourcefulness' uptime from the fight's crits (RMD 7; the user's answer 4 = (b)); below 60 the solo levelling values
  stay (the 0.8 uptime, mana as a tie-break).
- **stats-gear-13, ranged-8, melee-sv-1, melee-sv-8, melee-sv-9 — the weave.** The Survival branch weaves as wowsims' SV
  Weave preset (its cycle of an Auto Shot and a melee swing, Raptor Strike, Strider Kick, Mongoose Bite, Wing Clip and
  Immolation Trap where it casts them, Multi-Shot in its range looks); no other build melees (RMD 3, 15; the user's
  «мили атака вообще ни в учет хант ее избегает кроме сурв ветки»).
- **The white table** (stats-gear-9, melee-sv-6). wowsims' OutcomeExpectedMeleeWhite: a white swing of the hunter, the
  pet or the hawks is one roll, its crit capped by the room the miss, dodge, parry and glance leave
  (`spell_outcome.go:852-875`; RMD 4.3, 1db4d89).

## By design / refuted

- **stats-gear-12, stats-gear-13, ranged-8, ranged-4, melee-sv-9, melee-sv-12** Once by design for solo levelling; closed by
  the two modes and the Survival weave (above, "Closed the wowsims way"): below 60 mana stays a tie-break and Serpent
  Sting's uptime 0.8; at 60 the raid fight of wowsims' preset.
- **melee-sv-10** Dodge / parry-triggered attacks: HGA assumes neither in combat.
- **pet-hawk-bm-9** Hawk swing base: refuted as gear-irrelevant, EV-0073's 0.185 x creature DPS adopted anyway because it
  fits the only measured level.
- **pet-hawk-bm-12** Intimidation: no gear stat changes it.
- **pet-hawk-bm-14** The pet's share of the owner's AP: the tooltip and the sheets give 10%, which both models use.
- **melee-sv-11** Improved Tracking on all damage: a constant multiplier, gear-irrelevant.
- **stats-gear-11, pet-hawk-bm-11** Refuted as stated (no difference in the gear ranking at the time); both are adopted
  in HGA since (see the table).

## Matching rules (both sides agree with the data)

Agility 2 RAP + 1 AP, crit per Agility per level, rating conversion 10 / 14 / 10 / 10, hit cap 5 / 5.5 / 6 / 8%, DW +19%,
two-roll ranged outcome, crit x2 (+Mortal Shots), Auto Shot / Aimed / Arcane / Serpent / Multi / Sniper formulas and ranks,
Raptor / Mongoose / Strider Kick formulas, normalized speeds 1.7 / 2.4 / 3.3, off-hand 0.5 with Predator's Edge, talent
per-rank values, pet AP 10% of max(AP, RAP), pet hit / crit inheritance, happiness x1.25, pet attack-speed passives
normalized, a chance-on-hit proc's per-hit chance from its rate at the weapon's base speed (EV-0119:26-27, wowsims
`sim/core/attack.go` PPMProc).

## Not checked

- wowsims was not run (rule), so their per-spell breakdown and EP at levelling inputs were not reproduced.
- No Forever combat log was available for: pet white-swing crit rate, Lacerating Strikes refresh, the melee Auto Shot reset,
  the server side of the hawk talent flats / Command / expertise / Rapid Fire / attack speed, crit suppression vs
  higher-level targets.
- Nothing on this branch has been checked in game.
