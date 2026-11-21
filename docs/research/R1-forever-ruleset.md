# R1 — WoW Forever ruleset vs Classic Era: what matters for a HUNTER's stats and gear

Scope tags used below: **[FV-client]** = proven from Forever client data (DB2 build 1.60.1.70888, product `wowf`, created 2026-11-10 per wago builds.json) or Forever GlobalStrings; **[FV-web]** = a source explicitly about WoW Forever (Blizzard posts first); **[FV-sim]** = wowsims/forever (third-party simulator for Forever, values fitted to in-game combat logs; MIT, github.com/wowsims/forever, master as of 2026-11-12); **[Era]** = Classic Era DB2 build 1.15.9.70576; **[memory]** = unverified.

Local evidence files (all under scratchpad):
- `research/_r1_hunter_spell_diff.txt` — full diff of every spell in hunter skill lines 50/163/51, Forever vs Era (script `r1_scripts/diff_hunter.py`, helper `r1_scripts/db.py`, viewer `r1_scripts/show.py`).
- `research/_r1_forum.txt` — all Blizzard (Kaivax) posts of "WoW Forever Beta Development Notes" thread (us.forums.blizzard.com/en/wow/t/2360696, JSON pulled 2026-11-12).
- `research/_r1_hotfixes.txt` — "WoW: Forever Hotfixes" thread (us.forums.blizzard.com/en/wow/t/2403040), posts Nov 6 – Nov 12 2026.
- `research/_r1_fetch1.txt` — Icy Veins copy of Nov 2 dev notes.
- `db2_R1-forever-ruleset/{fv,era}/` — extra DB2 tables (Era Spell*, ItemSparse, ItemEffect, GlobalStrings, ItemDamage*, SkillRaceClassInfo; Forever ItemSparse, ItemEffect, ItemXItemEffect, GlobalStrings, ItemDamage*).
- `dl_r1_wowsims/x/forever-master/` — extracted wowsims/forever sources (sim/hunter/*.go, sim/core/*, assets/db_inputs/basestats-forever/CombatRatings.txt).
- `dl_r1_wh/*.json` — Wowhead Forever tooltip JSON (Lionheart Helm, Moonsight Rifle).

Note on DB2 base points: Era SpellEffect value = EffectBasePoints + EffectDieSides (vanilla style); Forever SpellEffect only has EffectBasePointsF (+Variance). All Era numbers below are already corrected (+1).

---

## 1. What WoW Forever is (brief) [FV-web]
- Official Blizzard "Classic Plus" product, launched **2026-11-04** (Blizzard news "World of Warcraft: Forever Now Live!", https://news.blizzard.com/en-us/article/24315820/world-of-warcraft-forever-now-live). Included in the WoW subscription.
- Base: original WoW (patch 1.12 foundation), "set after the events of Warcraft III Reforged: Forsaken Kingdom and before Molten Core". **Level cap 60, permanently** ("sticks to a level cap of 60 without going beyond", https://news.blizzard.com/article/24315821/wow-foreverwhats-new-and-what-feels-familiar).
- New: 1000+ quests, new zones (Mount Hyjal, Shen'dralas, Riverglades, Zephras Isle), 9 new 5-player dungeons (13–60), Skyborne race, new race/class combos (Human Hunter etc.), Legacy System (account perks, 16 spendable points), Camping, rulesets Normal/PvP/RP/RP-PvP (Hardcore later).
- Phases: Blizzard Nov 2 notes: "we don't plan on making big tuning changes between now and the opening of the raids next month" → raids open ~December 2026; a large tuning pass is planned after data from 30+ players (research/_r1_forum.txt post 30732723).
- Talents: from level 10, 1 point/level, 51 at 60; new 16-point milestone row (Blizzard Hunter/Druid deep dive). Legacy perk **Talented** (5 ranks) moves the start down to level 5 but never more than 51 total (Wowhead legacy guide https://www.wowhead.com/forever/guide/legacy-system-overview-rewards, fextralife talent calc). → 34 points spent = level 43 without Talented, level 38–42 with 1–5 ranks of Talented.
- Client: 1.60.1.x (builds.json; `wowf` 1.60.1.70888 created 2026-11-10 15:10).

## 2. Hunter-relevant Forever mechanics

### 2.1 Stat system / items (the most important difference for gear comparison)
- **Hit and crit are each ONE stat for melee, ranged and spells** (BlizzCon deep-dive transcript, Blizzplanet: "with unified hit, hit is for all types of attacks at once ... hunters landing their traps"; same for crit). [FV-web]
- **Item stats are stored as ratings but shown in tooltips as percentages.** Evidence:
  - Forever GlobalStrings has NEW templates (not in Era): `TOOLTIP_ITEM_STAT_HIT_PERCENT` "Equip: Improves your chance to hit by %1$.1f%%.", `..._CRIT_PERCENT` "...critical strike by %1$.1f%%.", `..._HASTE_PCT` "Equip: Increases your attack speed and casting speed by %1$.1f%%.", `..._EXPERTISE_PCT` "Equip: Reduces chance to be Dodged or Parried by %1$.1f%%.", `..._ARMOR_PENETRATION` "Equip: Your attacks pierce up to %1$d Armor.", `..._ATTACK_POWER` "Equip: +%1$d Attack Power.", `..._RANGED_ATTACK_POWER`, `..._WEAPON_DAMAGE` "Equip: +%1$d Weapon Damage.", `..._SKILL_BOWS/GUNS/CROSSBOWS/...` "Equip: Increased Bows +%1$d.", `..._AP_VS_BEAST` etc. [FV-client: db2_R1-forever-ruleset/fv/GlobalStrings.csv]
  - Wowhead Forever tooltip (dataEnv 16) for Lionheart Helm 12640: "Equip: Improves your chance to hit by 2.0%." / "Equip: Improves your chance to get a critical strike by 2.0%."; Moonsight Rifle 4383 (ilvl 29): "Equip: Improves your chance to hit by 0.3%." (dl_r1_wh/*.json, nether.wowhead.com/forever/tooltip/item/...). [FV-web]
  - Forever CombatRatings GameTable (wowsims/forever assets/db_inputs/basestats-forever/CombatRatings.txt, from build 1.60.1.70790) is **flat at every level 1–70**: Hit (melee/ranged/spell) 10 = 1%, Crit 14 = 1%, Haste 10 = 1%, Expertise 10 = 1%, Armor Penetration 10, Dodge 12, Parry 15, Block 5, Defense 1. Same constants in sim/core/base_stats_auto_gen.go. Corroborated by kickegg article (https://wowforever.kickegg.net/articles/forever-combat-ratings-conversion) and senseos/aggroly item comparisons (1% crit item → 14, 1% hit → 10, 1% dodge → 12). [FV-sim/FV-web]
  - Some third-party sites (senseos.gg, aggroly, chaosboost) say items "show points" — they read raw DB2; the in-game/Wowhead tooltip shows %. Since the table is flat, both views are equivalent: % = rating/10 (hit, haste, expertise) or rating/14 (crit).
- Forever ItemSparse has **no flat stat amounts** (Era has StatModifier_bonusAmount_*); it has StatModifier_bonusStat_* + StatPercentEditor_* = budget allocation → stats computed from item level (modern budget system). Kovarel notes "WoW Forever recomputes values from its stat budget, so some stats ... are one point off Classic" (https://kovarel.com/wow-forever/items/changes). [FV-client + FV-web]
- Stat type ids seen on Forever items (my mapping via Era equip spells, db2_R1-forever-ruleset): 3 Agi, 4 Str, 5 Int, 6 Spi, 7 Sta, 12 Defense, 13 Dodge, 14 Parry, 15 Block, 31 Hit, 32 Crit, 36 Haste, 37 Expertise, 38 AP, 39 RAP, 41 healing, 42 spell dmg, 43 mp5, 45 spell power, 46 hp5, 47 spell pen, 48 block value, 50 bonus armor, 51–56 resistances, 83 weapon damage, 85–89 school spell damage, 90 2H-axe skill, 91 2H-mace skill, 96 dagger skill, 103 sword skill, 124 all resist, 127/128/131 AP vs demons/undead/beasts, 135/136 spell dmg vs undead/demons.
- Counts in Forever ItemSparse (19,325 rows on wago): Hit 184 items, Crit 523, AP 285, RAP 20, Expertise 8, **Haste 4 (test items)**, **Armor penetration 0**. mmonster.co & conquestcapped confirm: no gear with armor penetration; haste essentially absent from gear (sources: Skyborne Wind Blessed 2%, Troll Berserking, Enchant Gloves Minor Haste 1%, Arcanum of Rapidity 1%, some consumables; quivers for ranged). [FV-client + FV-web]
- **Weapon skill still exists** (GlobalStrings STAT_CATEGORY_WEAPON_SKILLS "Weapon Skills", WEAPON_SKILL_DETAIL_BOSS "...Glancing Blows occur %s of the time and deal %s less damage", WEAPON_SKILL_DETAIL_BOSS_RANGED "Chance to Hit / Chance to Critically Hit" — no glancing line for ranged) [FV-client]; items give much less (Edgemaster's +7 → +1; Huge Thorium Battleaxe +10 → +2) and **racial weapon/gun/bow specializations are removed** (Blizzard Oct 26 notes; tierlist: Gun Specialization (Dwarf) and Bow Specialization (Troll) removed). Per point below/above defense: ±0.04% miss, dodge, parry, crit (Wowhead Forever rogue guide; Grimoire). [FV-web]
- **Expertise** exists (new): removes dodge/parry, % flat. Client tooltip CR_EXPERTISE_TOOLTIP: "Raid Boss chance to: 6.50% Dodge, 16.50% Parry; Equal-Level Creature: 5.00% Dodge, 5.00% Parry"; CR_RANGED_EXPERTISE_TOOLTIP lists 6.50% Dodge / 14.00% Parry. [FV-client]
- **Armor penetration** renamed "Armor Piercing", flat: ARMOR_PENETRATION_TOOLTIP "Your Attacks ignore %d of your enemies' Armor ... Reducing an enemy's armor below 0 will increase your damage against them." [FV-client] (no item carries it).
- Primary-stat tooltips (Forever GlobalStrings): HUNTER_AGILITY_TOOLTIP "Increases Critical Strike chance by %.1f%% / Attack Power by %d / Ranged Attack Power by %d / Armor by %d / Dodge chance by %.1f%%"; RANGED_ATTACK_POWER_TOOLTIP "...Every 14 Ranged Attack Power adds 1 damage per second"; HUNTER_MELEE_ATTACK_POWER_TOOLTIP "Increased by Strength and Agility ... Every 14 Attack Power adds 1 damage per second"; DEFAULT_INTELLECT_TOOLTIP "Mana / Spell Critical Strike / Weapon Skill improvement rate"; STAT_HUNTER_CRIT_BONUS "Melee and Ranged critical strikes deal 100% increased damage". [FV-client]
- ChrClasses Hunter: RAP/Agi 2, AP/Agi 1, AP/Str 1 (shared context, Forever DB2). wowsims: base AP 100, base RAP 110 (= level×2 − 10) at 60; crit per Agi at 60 = 0.0189%/Agi (≈ 52.9 Agi per 1%), dodge per Agi = 2× that, base physical crit 0 (sim/core/base_stats*.go). [FV-sim]
- **Hit caps (client strings)**: CR_HUNTER_HIT_CAP_TOOLTIP: "To never miss Raid Bosses: 8.00% Melee/Ranged, 17.00% Spells, 27.00% Dual Wielding. To never miss Lvl %d Targets/Players: 5.00% Melee/Ranged, 4.00% Spells, 24.00% Dual Wielding" (assumes max weapon skill). [FV-client]. Players note Classic was 9%/16% (chaosboost attributes the change to removal of hit suppression); some guides still say 9% (method.gg leveling, warcrafttavern) — client string says 8%.
- Weapon DPS on Forever items has no explicit min/max in ItemSparse; it equals ItemDamageRanged/OneHand/TwoHand[ilvl][quality] (tables identical to Era's) × weapon speed, ± DmgVariance/2. Median Forever/Era ranged DPS ratio 1.008 over 182 bows/guns/crossbows; e.g. Laminated Recurve Bow 5.77 vs 5.77, Hunter's Boomstick 5.08 vs 5.00. Weapon speeds unchanged. [FV-client inference; medium]
- Crit on everything: periodic effects can crit (Serpent Sting ticks crit at ranged crit in wowsims; STAT_HUNTER_CRIT_BONUS "Most periodic effects can critically strike"). [FV-client]
- PvP crits full damage since Oct 8; no resilience (BlizzCon). [FV-web]

### 2.2 Ammo, quivers, ranged haste [FV-client]
- Ammo exists and is consumed: SPELL_FAILED_NEED_AMMO "Must have ammo equipped in the ammo slot."; Nov 4 UI note "Added remaining bag space and ammo count indicators"; Sep 24 beta fix "guns and bows use and consume ammo correctly" (tierlist). 36 ammo items in Forever ItemSparse.
- Ammo DPS = ItemDamageAmmo[ilvl][quality] (rounded down to 0.5 in tooltip, per wowsims ammo_auto_gen.go): Rough Arrow 1.5, Sharp 3.5, Razor 7.5, Feathered 9.5, Precision 11.5, Jagged 13, Explosive 14.5, Ice Threaded 16.5, Thorium Headed 17.5, Doomshot 20, NEW Swiftfeather Arrow / Swiftstrike Shot (ilvl 65 epic, req 60) 24.5. Same values as Era ammo. Added to ranged weapon damage as ammoDPS × weapon speed per shot (wowsims hunter.go `BonusRangedDps`).
- Quivers/ammo pouches still give ranged haste via equip spell "Haste" (aura 557, desc "Increases ranged attack speed by $s1%"): Light/Small/Hunting Quiver 10%, Quiver of the Night Watch 11%, Heavy Quiver 12%, Quickdraw Quiver 13%, Ribbly's 14%, Ancient Sinew Wrapped Lamina 15% — identical to Era. Must be equipped in a bag slot (bags now must be manually equipped, Nov 2 notes).
- Quick Shots 6150: +30% ranged attack speed (A140) for 12 s — unchanged vs Era. Quick Strikes 1299448 (new): +30% melee attack speed (A319) 12 s.
- Rapid Fire 3045: now "Increases ranged and melee attack speed by 40% for 15 s" (A140 40 + A319 40), cd 5 min (Era: ranged 40%, melee only with SoD rune). wowsims: Rapid Fire's melee haste reaches the pet; ranged haste does not.
- Auto Shot 75: DB2 identical to Era; server rule since Oct 15: must stand still 0.5 s before firing; still fires while casting Aimed/Sniper Shot (Blizzard Oct 15 notes).

### 2.3 Pet scaling (biggest BM-relevant change)
- Blizzard: "Pets now get increased stats based on their Hunter's gear. Pets can no longer receive player buffs that increase their stats." (deep dive 2026-09-30). [FV-web]
- Client tooltips [FV-client, GlobalStrings]:
  - MELEE_ATTACK_POWER_PET_HUNTER_TOOLTIP: pet AP "Increased by 10% of Master's Attack Power from whichever is higher: Melee or Ranged ... Every 14 Attack Power adds 1 damage per second".
  - STAT_HUNTER_PET_CRIT_BONUS: "Increased by 100% of Master's Critical Strike Chance".
  - STAT_PET_HIT_TOOLTIP: "Increased by 100% of Master's Hit Chance. To never miss Raid Bosses: 8.00% Melee, 17.00% Spells; Equal-Level: 5.00% Melee, 4.00% Spells".
  - CR_PET_EXPERTISE_TOOLTIP: "Increased by 100% of Master's Expertise".
  - STAT_HEALTH_PET_TOOLTIP: "Increased by Master's Stamina. Every 1 Stamina adds 2 Health".
  - STAT_ARMOR_PET_TOOLTIP: "Increased by %d%% of Master's Armor" (value server-side; 30% per beta testing: conquestcapped, wowfdb, mobalytics).
- Blizzard Oct 15: "Pets now correctly benefit from Expertise." and "pets were only ever inheriting the player's Melee Critical Strike chance instead of whichever is higher, melee or ranged" (fixed). Nov 10 hotfix: "Pets erroneously had 150% of their normal health. This is now corrected to 115%." Oct 26: Orc Command re-added (+5% Hunter/Warlock pet damage).
- wowsims (in-game logs): health = 2×owner Sta; armor 30%; AP = 0.10 × max(AP, RAP); crit = owner's higher melee/ranged crit (minus 0.04%/point of weapon-skill deficit); hit = owner's ranged hit (spell hit = 17/8 × that); expertise = owner's; **AP and health are snapshotted at summon** (kept until dismissed; armor follows); re-inheritance on pet action at most once per 2 s; pet's own AP = 0.3×14×creature dps; happiness ×1.25 damage. Forum bug report #48 (ClassicWoWCommunity/forever-bugs): pet stats only update on resummon/stable (snapshot). [FV-sim]
- Hunter Pet Scaling aura 415429 Forever effects: A230 health, A99 AP, A13 spell dmg, A22 resist ×5, A674 (armor), A54/A55 hit, **A319 melee haste**, A65 cast speed, A52/A57 crit, A418 max focus (bp 50, misc 2), A593 ×2 (combat-result chance = expertise), A49 dodge. Era (SoD) version had A29 Stamina and A138 instead of A230/A319. Amounts server-side (bp 0). [FV-client]
- Conflict: wowsims says Faster/Slower Attack pet passives are normalized (damage per second unchanged); wowfdb says "damage isn't normalized, so a faster beast hits harder" (beta: level-20 cat 26.8 DPS at 2.0 s vs 38 at 1.2 s). Unresolved.

### 2.4 Summon Hawk (BM 16-pt talent) [FV-client + FV-sim + FV-web]
- Ranks (DB2): R1 L25 32, R2 L36 47, R3 L48 85, R4 L60 108 physical dive damage + 5% RAP (effect 4 bp 5); max 2 hawks (effect 3 bp 2); hawk guardian 1293248 lasts 18 s; shares cd category 1173 (6 s) with Arcane Shot. Nov 10 hotfix: mana cost 11% base mana; "Melee damage dealt by the Hawk pet increased by about 80%".
- Hawk scaling aura 1293586 "Hunter Guardian Hawk Pet Scaling 01": A342 (haste), A79 (dmg % all schools), A290 (crit) — values server-side.
- wowsims (logs at L30/L48, before the Nov 10 +80% hotfix): hawk AP = 0.8 × (owner RAP + 7 + 14 × ranged weapon DPS); 60 hawk AP = 1 hawk DPS; swing 2.5 s, follows owner's **ranged** attack speed (quiver, Quick Shots; not Berserking); crit = 50% of owner's higher crit + Ferocity (full: "a hawk with Ferocity 5/5 read 10 plus half its owner's crit"); hit & expertise = owner's; damage multiplier = owner's at summon (Focused Fire etc.) × Unleashed Fury.

### 2.5 Aspects, marks, auras [FV-client]
- **Aspect of the Hawk** RAP: R1 L10 20, R2 L18 35, R3 L28 50, R4 L38 70, R5 L48 90, R6 L58 110, R7 L60 120 (book). Identical to Era DB2. Nov 2 notes "increased on all ranks. New values: 20, 35, 50, 70, 90, 110" = restoring Classic values after beta reductions. (TDGN article calls it a nerf — contradicted by Blizzard text and DB2.) Proc trigger 6150 (Quick Shots) with base chance 0; Deadly Aspects 2%/rank → 10% at 5/5, Auto Shot only (Era Improved AotH: 1%/rank on all normal ranged attacks).
- **Aspect of the Beast** (now ranked): +melee AP R1 L30 50, R2 L40 70, R3 L50 90, R4 L60 110; untrackable; procs Quick Strikes with Deadly Aspects (melee autos). Melee AP only.
- **Hunter's Mark** (A127 RANGED_ATTACK_POWER_ATTACKER_BONUS, ranged attackers only): R1 L6 26, R2 L22 59, R3 L40 98, R4 L58 143 RAP (Era 20/45/75/110 → ×1.3, Improved Hunter's Mark baseline). Nov 2: no longer stacks across ranks; rank-4 bug fixed.
- **Trueshot Aura** (MM 21-pt talent, not taken): RAP only (Era also gave melee AP), raid-wide (Oct 15): R1 L25 20, R2 L32 35, R3 L40 50, R4 L50 75, R5 L60 100.
- Aspect of the Wild now raid-wide (E65).

### 2.6 Shots and melee abilities: Forever vs Era DB2 [FV-client vs Era]
| Spell | Forever | Era |
|---|---|---|
| Auto Shot 75 | weapon damage (E58 bp0), same row | same |
| Aimed Shot (baseline L20) | cast 2.0 s; +40/70/115/185/260/350 (R1–R6, L20/28/36/44/52/60); shares 6 s cd with Multi-Shot | talent; cast 3.0 s; +70/125/200/330/460/600 |
| Multi-Shot | **only rank 2643 exists (bonus +0)**; ranks 14288/14289/14290/25294 absent from Forever Spell/SpellName/SpellEffect; cd category 2 6 s shared with Aimed Shot | 5 ranks +0/40/80/120/150, 10 s cd |
| Arcane Shot | 25/35/50/85/120/175/220/280 (R1–R8); AP coeff 0.15 RAP server-side (Nov 2); own cd 6 s (cat 1173, shared with Summon Hawk); mana 11% base mana (Nov 10) | 13/21/33/59/83/115/145/183 |
| Serpent Sting (per tick ×5 over 15 s) | 3/7/14/26/40/58/75/100/135; + 5% RAP per tick server-side (Nov 2) | 4/8/16/28/42/58/77/98/111 |
| Scorpid Sting | single rank, −2% target hit (A54 −2) | −Str/−Agi |
| Volley | waves 1279721 (R1 70) … 1279715 (R3 112); 3% RAP per wave (wowsims) | 50/65/80 per s |
| Sniper Shot (MM 31) | 4 s cast, 15 s cd, 45 yd; +320/450/590 (L40/48/58) | n/a |
| Raptor Strike | still next-swing; +5/11/21/30/35/40/55/70 | +5/11/21/34/50/80/110/140 |
| Mongoose Bite | normalized melee weapon dmg + 15/22/37/57 | flat 25/45/75/115 |
| Counterattack | 50% weapon dmg + 26/40/70/110 | flat 40/70/110 |
| Strider Kick (SV 21) | 100% normalized melee weapon dmg, +30% speed 3 s, 8 s cd | n/a |
| Wing Clip | unchanged (5…50 flat) | same |
| Rapid Fire | +40% ranged & melee speed, 15 s, 5 min | ranged 40% |
| Bestial Wrath | +50% pet dmg 18 s / 2 min, + many immunities | same dmg |
| Intimidation | stun + next attack +100% crit | stun only |
| Frenzy buff 19615 | +30% pet attack speed (A319) 8 s | A138 30% |
- wowsims treats Aimed/Multi/Sniper as **normalized ranged weapon damage (2.8 s)** + 9 hidden bonus for Aimed/Multi ("In game Multi-Shot and Aimed Shot hit 9 harder than the rows' normalised weapon damage"), Multi-Shot has a 0.5 s cast in game. [FV-sim]
- Removed: Wyvern Sting, Improved Scorpid Sting, Killer Instinct, Improved Feign Death, Monster/Humanoid Slaying (→ Improved Tracking), Thick Hide (→ Endurance Training); Improved Hunter's Mark & Improved Eyes of the Beast baseline. [FV-web deep dive + DB2 absence]

### 2.7 Talent value conflicts — RESOLVED
- Mechanism: Forever talents are a single spell per talent with TraitDefinitionEffectPoints curves (OperationType 0 = set) that override spell base points; old per-rank spells (e.g. Unleashed Fury 19617–19620, Ferocity 19599–19602) are deleted from Forever DB2. Spell bp/tooltip numbers (20, 16) are stale.
- **Unleashed Fury 5/5 = +15% pet (and hawk) damage** (3/rank). Evidence: curve 82822 r1..r5 = 3/6/9/12/15 [FV-client]; Blizzard deep dive "Unleashed Fury: Benefit to pet damage decreased slightly, but now also benefits new Hawk summons" (Classic = 4%/rank = 20%; Era DB2 19616 bp 3+1 = 4) [FV-web]; wowforeverbuilder rank 1 = 3% [FV-web]; wowsims uses MultiplierAt(5) = 1.15 and its hawk/pet fits were done with UF 5/5 [FV-sim]. Oct 8 fix: "Unleashed Fury now correctly increases your pet's damage" (it did nothing before).
- **Ferocity 5/5 = +10% pet (and hawk) crit** (2/rank). Evidence: curve 82820 = 2/4/6/8/10 [FV-client]; Wowhead Forever spell=19598 page: "Trait #134429 Rank 1 Mode 0 Value: 2 ... Rank 5 Mode 0 Value: 10" (tooltip text still shows 16) [FV-web]; Blizzard deep dive "Ferocity: Critical strike bonuses to pets decreased" (Classic 3%/rank = 15%; Era 19598 bp 2+1 = 3) [FV-web]; wowsims log: "a hawk with Ferocity 5/5 read 10 plus half its owner's crit" [FV-sim]. Known issue (Oct 8): Ferocity's pet crit does not show on the pet character sheet (visual only).
- Same mechanism → Bestial Discipline 2/2 = pet focus regen +20% (curve 10/20; spell bp 100 stale) and 50% mana regen while casting; Frenzy 4/5 = 80% proc; Focused Fire 2/2 = +2%; Endurance Training 1/5 = +3%; Lethal Attacks 2/5 = +2% crit all attacks (A290; Era A52 ranged only); Deadly Aspects 5/5 = 10%.

### 2.8 Racials that touch hunter stats [FV-web: Blizzard Oct 15 / Oct 26 notes in _r1_forum.txt, tierlist]
- Human: Ruthless +1% crit (was Sword Spec). Dwarf: Artisan's Precision +1% hit (spells+attacks); Gun Specialization removed; Big Game Hunter +5% dmg vs Beasts (tierlist). Night Elf: Elune's Light +10% crit 15 s (tierlist). Orc: Command +5% pet damage; Blood Fury (2 min). Troll: Berserking flat +10% attack/cast speed 15 s, Bow Specialization removed. Tauren: Endurance +5% HP only. Skyborne: Wind Blessed +2% haste. Undead: Touch of the Grave.

### 2.9 Weapons a hunter can use (Forever = Era, SkillRaceClassInfo diff) [FV-client]
- Axes, 2H Axes, Swords, 2H Swords, Daggers, Fist Weapons, Polearms (L20), Staves, Bows, Crossbows, Guns, Thrown, Dual Wield (L20); Leather, Cloth, Mail (L40). No Maces/2H Maces/Wands. Identical set in Era DB2.
- Off-hand: Dual Wield 674 unchanged; base OH = 50% damage (wowsims OHWeaponDamage 0.5×), DW auto-attack miss +19% (24% equal level / 27% boss caps, client string). Predator's Edge (SV) +10%/rank OH damage (A122).
- 2H/MH melee only matters for melee abilities (Raptor Strike, Mongoose Bite, Counterattack, Strider Kick, Wing Clip) and as a stat stick; pet AP takes max(AP, RAP) so melee AP rarely matters for the pet.

## 3. Patch notes timeline for hunters (Blizzard)
- Sep 24: Lone Wolf −4% bug, Furious Howl −40%, Tame Beast ≤ own level, ammo consumption fixed.
- Sep 30: Class deep dive (baseline Aimed Shot, traps in combat 30 s cd, Arcane free of Aimed, Multi shares Aimed cd, Aspect of the Beast melee AP, pets scale with gear, no player buffs on pets, Fox family, every family Bite/Claw + Dive/Dash + signature).
- Oct 1: Sniper Shot 45 yd + next 3 shots +10 yd; Deflection halved.
- Oct 8: Disengage threat doubling implemented; Unleashed Fury fixed; pet health bug; Improved Concussive Shot chance fixed.
- Oct 15 (build 70425): Auto Shot 0.5 s stand-still; pets benefit from Expertise; pets inherit higher of melee/ranged crit; Fire traps scale with AP; 1 Fire + 1 Ice trap; Dismember/Sonic Blast/Mine! nerfed; Summon Hawk spawn/stick fixes; Improved Mend Pet fixed; Trueshot Aura raid-wide; Sniper Shot gets MM talents; racial overhaul.
- Oct 26–27: racial pass (Human Ruthless 1%, Dwarf Artisan's Precision, Orc Command back, Troll Berserking 15 s, Skyborne haste 2%).
- Nov 2 (launch notes): classes buffed + creature HP raised; Hunter's Mark no rank stacking + R4 fix; all traps share one 30 s cd; Aimed Shot bonus ~+110%; Arcane Shot base ~+30% & AP coeff 0.10→0.15; Serpent Sting AP coeff/tick 3%→5% & base ~+20%; Aspect of the Hawk 20/35/50/70/90/110; pets keep innate attack-speed passives; Pathfinding back to row 3; Barrage 5/10/15%; Sniper Shot bonus +100%; Trueshot Aura 20/35/50/75/100; Lightning Reflexes 3–15%; Throw uses 0.5 s windup.
- Nov 6–11 hotfixes: Nov 10 pets 150%→115% normal health; Arcane Shot & Summon Hawk mana = 11% base mana; hawk melee damage +~80%; Nov 11 Volley no longer activates procs / stops channel on move; Swiftfeather Arrow / Swiftstrike Shot no longer BoP.

## 4. Third-party heuristics noted (not truth)
- Zygor Forever BM weights (shared context) — heuristic.
- Grimoire (https://wowgrimoire.app/guides/stats-and-combat): hunter 53 Agi per 1% crit at 60, 2 RAP/Agi, 1 AP/Agi, 1 AP/Str; 14 AP = 1 DPS; raid boss glancing 40% / −35% at max skill (Classic numbers, Blizzard flagged glancing sheet values as inaccurate in beta).

## 5. Open questions
1. Agility→crit ratio below level 60 in Forever (wowsims only has the level-60 value 0.0189%/Agi). Need gtChanceToMeleeCrit-style table or in-game sheet at the user's level.
2. Whether Hunter's Mark's target RAP bonus feeds pet AP (10%) / hawk AP (80%) — probably not (it is an attacker bonus, not RAP stat); untested.
3. Pet attack speed normalization (wowsims: normalized; wowfdb: not).
4. Exact hawk melee numbers after the Nov 10 "+~80%" hotfix (wowsims fit predates it).
5. Multi-Shot: client data has a single rank with +0 bonus; wowsims logs see +9 over normalized damage at L34/36. Whether there is server-side level scaling is unknown.
6. Whether ranged attacks can be dodged/blocked by bosses in Forever (CR_RANGED_EXPERTISE_TOOLTIP lists dodge/parry, but its text is a copy of the melee one).
7. Pet armor % (30%) is from testing; client string leaves %d server-side.
