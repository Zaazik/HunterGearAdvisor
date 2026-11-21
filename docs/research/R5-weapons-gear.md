# R5 — Hunter weapons & gear rules in WoW Forever (ranged slot, MH, OH, 2H vs DW, armor, Zygor scoring)

Scope tags: forever_client_data = Forever DB2 build 1.60.1.70888 (wago.tools) or the Forever client/addon files on disk;
forever_web = a web source explicitly about WoW Forever; classic_era = Era 1.15.9.70576 DB2 or Classic/vanilla sources.
Own downloads: C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/db2_R5-weapons-gear/ (Era copies in .../era/).
Helper scripts: C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/r5scripts/spells.py, items.py
(run: `python -I ../r5scripts/spells.py <base_db2_dir> <own_dir> <spellIDs | name:X | like:X>` from db2_R5-weapons-gear).
Wowhead fetches used: 2 of 10 (BM overview, BM stat priority). No captcha.

Housekeeping: one of my early commands wrote a stray file to C:\Program Files\Git\tmp_r5_q.txt (Git-Bash "/" path). I moved it into db2_R5-weapons-gear/q11.txt right away; nothing else outside the scratchpad was touched.

---------------------------------------------------------------------------------------------------
## 1. Proficiencies (what a hunter can equip)

### 1.1 SkillRaceClassInfo (hunter = ClassMask bit 4), Forever vs Era — identical apart from race-mask encoding
| Skill (ID) | Row | MinLevel | Note |
|---|---|---|---|
| Axes (44), Two-Handed Axes (172) | 117/628, 122 | 0 | |
| Swords (43), Two-Handed Swords (55) | 328/2535, 125/2526 | 0 | rows 2526/2535 are Forever-only extra rows |
| Daggers (173) | 129/631/632 | 0 | |
| Fist Weapons (473) | 330 | 0 | |
| Staves (136) | 139 | 0 | |
| Polearms (229) | 136 | **20** | same in Era |
| Bows (45), Crossbows (226), Guns (46) | 126/127, 128, 133/635 | 0 | |
| Thrown (176) | 143 | 0 | |
| Dual Wield (118) | 132 | **20** | same in Era |
| Cloth (415), Leather (414) | 148, 147 | 0 | |
| Mail (413) | 145 | **40** | same in Era |
No rows for hunter: Maces (54), Two-Handed Maces (160), Wands (228), Shield (433), Plate (293). (Forever + Era DB2, my filter included those IDs, nothing returned.)

### 1.2 Where/when learned (forever_client_data — Zygor Forever trainer table)
`D:/wow/World of Warcraft/_forever_/Interface/AddOns/ZygorGuidesViewerForever/Data-Forever/Skill_Training.lua`
- line 57, block [20]: `{674,2100}, -- Dual Wield (Passive)` → Dual Wield at **level 20 from the hunter class trainer**, 21 silver.
- line 136, block [40]: `{8737,16000}, -- Mail` → Mail at **level 40 from the class trainer**, 1g60s.
- line 98 [30] Aspect of the Beast R1 (7600), line 144 [40] R2, line 176 [50] R3, line 210 [60] R4.
- Polearms is not in this class-trainer table (weapon master skill, MinLevel 20 per SkillRaceClassInfo). Weapon-master training for Polearms/Crossbows/Fist etc. = Classic behaviour; theforeverera.com: "it learns dual wield at level 20, and the types it does not start with from a weapon master … Blizzard has not announced any change to this for Forever".
- warcraft.wiki.gg/wiki/Dual_wield patch history: "Patch 4.0.1: Hunters … now gain the ability to Dual Wield at level 10 … (was learned from trainers at level 20)" → confirms the pre-Cata level-20 trainer rule.
- SkillLineAbility (Forever): Throw 2764 classmask 13 (warrior/hunter/rogue), acquired with the Thrown skill; Shoot Bow/Gun/Crossbow (2480/7918/7919) classmask 9 = warrior+rogue only (hunters use Auto Shot).

### 1.3 Racial weapon specializations are gone in Forever (forever_client_data)
Forever SpellName has no "Gun Specialization" (20595), "Bow Specialization" (26290), "Mace Specialization" (20864), "Throwing Specialization" (20558).
20597 (Era "Sword Specialization") is now "Ruthless": +1% crit with all spells and attacks (aura 290 bp 1). 20574 (Era "Axe Specialization") is now "Savage": +1% crit (aura 290 bp 1).
→ No race gets a bonus for a specific bow/gun/axe/sword in Forever; weapon type is chosen only by DPS/speed/stats/ammo-bag. (forever-hunter wiki "Forever Hunter Patch Notes" agrees: Gun Spec, Bow Spec, Throwing Spec removed; Ruthless/Savage replace Sword/Axe Spec.)
Note: the wiki says Ruthless is +2% crit, client bp = 1 → trust client (+1%); Wowhead Forever BM overview also says "1% crit buff with Ruthless".

---------------------------------------------------------------------------------------------------
## 2. Ranged slot

### 2.1 Which weapons actually work (forever_client_data, SpellEquippedItems)
EquippedItemClass 2 (weapon), EquippedItemSubclass mask 262156 = bit2 Bow + bit3 Gun + bit18 Crossbow for:
Auto Shot 75, Aimed Shot 19434, Multi-Shot 2643, Arcane Shot 3044, Serpent Sting 1978, Scorpid Sting 3043, Viper Sting 3034, Concussive Shot 5116, Scatter Shot 19503, Volley 1510, Distracting Shot 20736, Sniper Shot 1310687, Tranquilizing Shot 19801. (Same mask in Era for Auto Shot/Aimed/Multi/Arcane.)
Throw 2764 needs subclass mask 65536 = Thrown only.
→ **A thrown weapon in the ranged slot disables Auto Shot and every hunter shot/sting**; the hunter only gets "Throw" (8-30 yd). Thrown = stat stick / emergency only, never a real hunter ranged weapon.
No weapon requirement: Summon Hawk 1293241, Rapid Fire 3045, Aspect of the Hawk, Hunter's Mark, Strider Kick 1317257.

### 2.2 Range (forever_client_data, SpellMisc.RangeIndex → SpellRange; ItemSparse.ItemRange)
- Auto Shot / Aimed / Multi / Arcane: "Hunter Range" 8–35 yd. Sniper Shot: "Longer Range (Hunter)" 8–45 yd. Summon Hawk "Hunter Range (no min)" 0–35. Throw: "Ranged Weapon" 8–30.
- ItemSparse.ItemRange = 100 for every bow (94/95), gun (81/81), crossbow (16/16) and thrown (34/34) row present in the Forever client → **range does not depend on bow vs gun vs crossbow**; only the spell (and talents: Hawk Eye +2 yd/rank, Sniper Shot +10 yd to next 3 shots) changes it.

### 2.3 Ammo (forever_client_data + forever_web)
- Ammo still exists in Forever: Item ClassID 6, subclass 2 = Arrow (BagFamily 1), subclass 3 = Bullet (BagFamily 2), InventoryType 24. New Forever ammo: Swiftfeather Arrow 274387 and Swiftstrike Shot 274388 (ilvl 65, epic, req 60). forever-hunter wiki calls them "WoW Forever's 22 DPS epic ammunition".
- Wowhead Forever BM overview: "Currently, there seem to be no notable changes to the ammo system. You will still use a quiver for arrows or an ammo pouch for bullets."
- Arrows → bows AND crossbows; bullets → guns (forever-hunter wiki "Ammo and Quivers"; classic rule).
- Per-shot contribution: `ammo_damage_per_shot = AmmoDPS × weapon_base_speed` (forever-hunter wiki Attack Formulas: verified for Auto Shot; also used for Aimed/Multi/Scatter, only the RAP part is normalized).
- Ammo DPS is NOT part of the weapon tooltip DPS (wiki Melee Weaving example: Rhok'delar 43.97 DPS + 22 ammo = 65.97 effective ranged DPS).
- Ammo DPS values (wiki, classic numbers): Rough Arrow 1.5, Sharp 3.5, Razor 7.5, Feathered 9.5, Precision 11.5, Jagged 13.0, Ice Threaded 16.5, Thorium Headed 17.5, Doomshot 20.0; bullets: Exploding Shot 9.5, Hi-Impact Mithril Slugs 12.5, Mithril Gyro-Shot 15.0, Ice Threaded 16.5, Thorium Shells 17.5, Rockshard Pellets 18.0, Miniature Cannon Balls 20.5.
  The client ItemDamageAmmo table (generic ilvl/quality curve) gives close but not identical numbers (Rough 1.82, Sharp 3.62, Razor 7.64, Jagged 13.03, Thorium Headed 17.71, Ice Threaded 16.79) → the in-game tooltip value is authoritative; level-40 vendor ammo (Jagged Arrow / Accurate Slugs, req 40) = 13 DPS either way.

### 2.4 Quiver / ammo pouch haste — kept in Forever (forever_client_data)
Bag item → ItemXItemEffect → ItemEffect(TriggerType 1 = on equip) → spell with aura 557 (ranged haste %):
Quiver spells 29413-29418 need SpellEquippedItems subclass mask 262148 (Bow + Crossbow). Ammo-pouch spells 14824-14829 need mask 8 (Gun).
| Bag | ID | Slots | Haste | Spell |
|---|---|---|---|---|
| Light Quiver | 2101 | 6 | 10% | 29418 |
| Small Quiver / Light Leather Quiver | 5439 / 7278 | 8 | 10% | 29418 |
| Medium Quiver / Hunting Quiver | 11362 / 3573 | 10 | 10% | 29418 |
| Quiver of the Night Watch | 3605 | 12 | 11% | 29417 |
| Heavy Quiver | 7371 | 14 | 12% | 29416 |
| **Matriarch Quiver (Forever-new, ilvl 40, req 35)** | 274926 | 14 | 13% | 29413 |
| Quickdraw Quiver (req 40) | 8217 | 16 | 13% | 29413 |
| Harpy Hide Quiver | 19319 | 16 | 15% | 29414 |
| Ancient Sinew Wrapped Lamina | 18714 | 18 | 15% | 29414 |
| Small Ammo Pouch / Small Shot Pouch / Small Leather Ammo Pouch / Medium Shot Pouch / Hunting Ammo Sack | 2102/5441/7279/11363/3574 | 6-10 | 10% | 14824 |
| Bandolier of the Night Watch | 3604 | 12 | 11% | 14825 |
| Heavy Leather Ammo Pouch | 7372 | 14 | 12% | 14826 |
| Thick Leather Ammo Pouch (req 40) | 8218 | 16 | 13% | 14827 |
| Gnoll Skin Bandolier | 19320 | 16 | 15% | 14829 |
→ Switching bow↔gun also switches which bag gives haste: a quiver's haste does nothing while a gun is equipped and vice versa. When comparing a gun with a bow, include the haste of the bag you actually own.
Haste stacking (forever-hunter wiki): multiplicative, `attack_time = base_speed / (1+quiver) / (1+other)`; quiver haste also shortens the 0.5 s Auto Shot cast and Aimed/Multi cast times. Bonus from two quivers does not stack.

### 2.5 Tooltip "damage per second" (forever_client_data, verified on an item)
- `tooltip_DPS = ((min_dmg + max_dmg) / 2) / weapon_speed`. Ammo, RAP, scope, quiver haste are NOT included.
- Client item damage: `DPS = ItemDamage<Type>[ItemLevel].Quality_q`; `min = DPS × speed × (1 − DmgVariance/2)`, `max = DPS × speed × (1 + DmgVariance/2)`. <Type> = Ranged (InvType 15/26 bow/gun/crossbow), Thrown (25), OneHand (13/21/22), TwoHand (17).
  Check: Rhok'delar 18713 (ilvl 75, epic, 2.9, var 0.6): ItemDamageRanged[75].Q4 = 44.05 → 89–166, matching the known 89–166 / 43.97 DPS.
  Note: the Forever ItemSparse holds only ~19k rows (vanilla items mostly come from the server), so this check works only for items present in the client.
- Weapon DPS by type at equal ilvl & quality (ItemDamage tables; Forever tables byte-identical to Era 1.15.9):
  `DPS_2H = 1.30 × DPS_1H`, `DPS_ranged(bow/gun/xbow) = 0.78 × DPS_1H`, `DPS_thrown = 0.90 × DPS_1H` (= 1.154 × ranged).
  e.g. ilvl 45 green: 1H 26.73, 2H 34.75, bow/gun 20.85, thrown 24.06; ilvl 45 blue: 30.51 / 39.66 / 23.79 / 27.45.
  → ranged weapon DPS numbers are always lower than melee DPS numbers at the same item level; an addon that weights "DPS" identically for both slots overvalues melee weapons.

### 2.6 Damage formulas for ranged attacks (forever_web — classic-hunter/forever-hunter wiki "Attack Formulas", marked "Verified" there)
- `AutoShot = WeaponRoll + AmmoDPS×Speed + RAP/14×Speed + Scope`
- `AimedShot = WeaponRoll + AmmoDPS×Speed + Scope + RAP/14×2.8 + AimedBonus` (normalized RAP only)
- `MultiShot = WeaponRoll + AmmoDPS×Speed + Scope + RAP/14×2.8 + MultiBonus` (per target)
- `ScatterShot = 0.5 × [WeaponRoll + AmmoDPS×Speed + RAP/14×Speed + Scope]`
- `ArcaneShot = Base + 0.10×RAP` (no weapon involvement) — note: client DB2 shows no AP or SP coefficient (server-side scaling); Era had SP coef 0.204–0.429.
- Client confirmation: Auto Shot = SpellEffect 58 (WEAPON_DAMAGE, non-normalized); Aimed Shot, Multi-Shot, Sniper Shot = effect 121 (NORMALIZED_WEAPON_DMG); Arcane Shot = effect 2 (flat school damage). Normalization constant 2.8 for ranged: warcraft.wiki.gg/wiki/Normalization ("2.8 for ranged weapons"; "Hunter ranged instant attacks were also normalized in patch 1.10").
- Derived equivalence (my derivation from the formulas above):
  - Auto Shot: +1 weapon DPS adds `Speed` dmg/shot; +1 RAP adds `Speed/14` → **1 ranged weapon DPS ≡ 14 RAP ≡ 7 Agility (RAP part only)**.
  - Aimed/Multi: +1 weapon DPS adds `Speed`; +1 RAP adds `0.2` → 1 weapon DPS ≡ `5×Speed` RAP on those shots (3.0 bow → 15 RAP).
  - Arcane Shot, Summon Hawk (`32 + 5%×RAP`, client e3 bp 5), pet (10% of highest AP, forever_web) scale with RAP/Agility but not with weapon DPS → for BM a point of weapon DPS is worth a bit less than 14 RAP overall; still far above the 2.4 Agility Zygor assigns.
  - theforeverera.com (forever_web) BM weights: ranged weapon DPS 7, two-hand DPS 0.5, main-hand DPS 0.3, off-hand DPS 0.2, Agility 1 — consistent with this derivation.

### 2.7 Spell data that matters for weapon choice (forever_client_data vs classic_era DB2)
| Spell | Forever 1.60.1 | Era 1.15.9 |
|---|---|---|
| Aimed Shot 19434… | cast 2000 ms; flat 40/70/115/185/260/350 (R1-R6, R4 = lvl 44); SpellCategory 2 "Direct Damage – Spell" 6 s, **shared with Multi-Shot** | cast 3000 ms; 70/125/200/330/460/600; 6 s cd |
| Multi-Shot 2643 | 1 rank, flat 0, 3 targets, Category 2 (6 s, shared with Aimed) | 5 ranks (0…120), 10 s cd |
| Arcane Shot 3044… | flat 25/35/50/85/120/175/220/280, SP coef 0; Category 1173 "Arcane Shot" 6 s **shared with Summon Hawk** | 13/21/33/59/83/115/145/183, SP coef 0.204–0.429 |
| Sniper Shot 1310687 | 4000 ms cast, 15 s cd, normalized weapon dmg + 320/450(/R3), 8–45 yd | — |
| Rapid Fire 3045 | +40% ranged (aura 140) AND +40% melee (aura 319) haste, 15 s, 5 min | ranged only |
Conflict: Wowhead Forever BM overview shows Aimed Shot "increases ranged damage by 350" (= client R6). forever-hunter wiki Patch Notes lists 20/34/55/89/125/166 and Arcane 20/26/39/…/217 — older beta numbers, do not use.
Multi-Shot cast: client CastingTimeIndex 1 = instant; wiki says "Instant → 0.5 sec cast" (unresolved; tooltip in game decides).

### 2.8 Auto Shot timing & speed (Classic vs Forever)
- classic_era: Auto Shot = 0.5 s cast (must stand still) + (speed − 0.5) cooldown; Aimed Shot cast blocks Auto Shot; hidden 500 ms retry timer (Blizzard "Not a bug" list) — forever-hunter wiki "Shot Mechanics"; legacy-gaming Classic hunter guide (Aimed Shot 3 s cast, free Auto 0.5 s after Aimed).
- Forever (forever_web): Wowhead BM overview: Auto Shot "has a 0.5s cast time again, but can continue during the cast of other abilities"; forever-hunter wiki 🔵 Blizzard-confirmed "Auto Shot can fire while casting abilities such as Aimed Shot and Sniper Shot" → the Classic slow-weapon/clipping logic around Aimed Shot mostly disappears.
- Forever bug (wiki): a melee swing resets the ranged swing timer (ranged does not reset melee) → melee weaving costs more than in Classic.
- Client: Auto Shot CastingTimeIndex 1 (0 ms) in both Forever and Era — the 0.5 s is server-side.

### 2.9 Slow vs fast ranged weapon (derived)
- Auto Shot DPS ≈ `(WeaponDPS + AmmoDPS + RAP/14) × haste_mult` — independent of speed (except Deadly Aspects procs and the 0.5 s stand-still cast).
- Aimed/Multi per hit carry `(WeaponDPS + AmmoDPS) × Speed` → slower is better: at equal DPS, `ΔAimed = (WeaponDPS+AmmoDPS) × ΔSpeed` per cast (one Aimed or Multi per 6 s shared cd).
- Deadly Aspects (Hawk) procs 10%/Auto Shot → faster weapon = more procs. My Monte-Carlo (15% quiver, 10% per Auto Shot, +30% for 12 s, refresh on proc): speed 1.8 → 58.9% uptime (avg ×1.177 haste); 2.0 → 54.8% (×1.164); 2.5 → 46.9% (×1.141); 2.8 → 42.8% (×1.128); 3.0 → 40.3% (×1.121); 3.3 → 37.5% (×1.113).
  So fast vs slow ≈ 4-6% Auto Shot DPS for fast, against slow's per-hit gain on Aimed/Multi → roughly a wash at lvl 40s; **weapon DPS dominates, speed is a tiebreaker (slight edge to slow while you use Aimed/Multi)**.
- Unresolved: Aspect of the Hawk aura ProcTypeMask_0 = 320 (0x40 ranged auto attack + 0x100 ranged ability) in Forever, while the talent text says "Auto Shot". If abilities can also proc it, uptime is higher and less speed-dependent. (Era Aspect of the Hawk mask = 87376.)

---------------------------------------------------------------------------------------------------
## 3. Melee: main hand, off hand, 2H

### 3.1 Which hand each ability uses (forever_client_data unless stated)
All need a melee weapon (SpellEquippedItems subclass mask 173555 = Axe, 2H Axe, Mace, 2H Mace, Polearm, Sword, 2H Sword, Staff, Fist, Dagger, Spear) except Strider Kick (no requirement; 🔵 "can be used while disarmed or without a Main Hand weapon equipped" — wiki Patch Notes).
| Ability | Effect in Forever | Hand | Era |
|---|---|---|---|
| Raptor Strike 2973/14260-14266 | effect 58 WEAPON_DAMAGE (non-normalized) + 5/11/21/30/35/40/55/70; next-melee-swing ability (gcd 0, attr0 has ON_NEXT_SWING), Category 40, 6 s | Main hand | same effect; flat 5/11/21/34/50/80/110/140 |
| Mongoose Bite 1495/14269-14271 | effect 121 NORMALIZED weapon dmg + 15/22/37/57; Category 65, 5 s | Main hand | flat 25/45/75/115 school damage |
| Counterattack 19306/1242634/20909/20910 (talent, not taken) | effect 31 50% weapon + effect 121 flat 26/40/70/110 | Main hand | flat 40/70/110 |
| Strider Kick 1317257 (SV 21-pt, not taken) | 121 + 31 100% weapon dmg, 8 s cd | Main hand | — |
| Wing Clip 2974/14267/14268 | effect 2 flat 5/25/50 (not weapon based) | — | same |
- "Instant attacks are always assumed to be made with the weapon in the main hand only" — warcraft.wiki.gg/wiki/Dual_wield (classic+). Off-hand variants of Raptor Strike exist in the Forever client (409691…, attr3 0x01000000 = off-hand; SoD Dual Wield Specialization rune 409687 "Raptor Strike strikes with both weapons") but **no Forever spell triggers them** (no SpellEffect.EffectTriggerSpell = 409691/415335) and the rune is not in the Forever talent tree → treat Raptor Strike as MH-only in Forever.
- forever-hunter wiki formulas (verified there): `RaptorStrike = WeaponRoll + MAP/14×Speed + Bonus`; `MongooseBite = WeaponRoll + MAP/14×Speed + Bonus` (client says normalized effect 121 → AP part may be 2.4/3.3/1.7 instead of speed — conflict, unverified); `StriderKick = WeaponRoll + MAP/14×Speed`.
- Raptor Strike, Mongoose Bite, Strider Kick, Wing Clip trigger melee on-hit effects (Windfury, Crusader-type) — wiki Ability Mechanics.
- → **A slow main hand matters for Raptor Strike**: `avg weapon roll = DPS × Speed`, so at equal DPS a 3.8 weapon hits 3.8/2.6 = 1.46× harder per Raptor Strike than a 2.6 weapon; white-swing DPS is speed-independent. Put the slower 1H in the main hand (classicwowforever.com, mobalytics Forever SV guide say the same).

### 3.2 Off hand & dual wield (classic_era mechanics; no evidence of change in Forever)
- `OH_white_damage = 0.5 × (WeaponRoll + MAP/14×Speed)` — warcraft.wiki.gg Dual_wield: "an off-hand weapon will deal 50% of its damage"; forever-hunter wiki Attack Formulas uses the same ×0.50 for Forever.
- Dual wield miss: `+19%` miss on **white** (auto) swings for both hands, not on special attacks — warcraft.wiki.gg Dual_wield. Wowhead Forever stat page: 9% hit removes misses for "ranged auto attacks and two-handed auto attacks. Only one-handed weapons require a higher Hit Chance" (forever_web, consistent).
- Predator's Edge (SV, not taken) 1310627: e1 aura 122 (MOD_OFFHAND_DAMAGE_PCT) +10%/rank → `OH = 0.5 × (1 + 0.10×rank)` = 0.75 at 5/5 (wiki: "Predator's Edge ×1.50 Off Hand weapon damage"); e0 aura 108 op 15 = +6%/rank crit damage of melee abilities (not white swings). classicwowforever.com notes Blizzard's 15 Oct notes only mention the crit part; client tooltip lists both.
- OH requires Dual Wield (lvl 20). Shields: no proficiency. "Off Hand" weapons (INVTYPE_WEAPONOFFHAND) only fit the OH; "Main Hand" only MH; "One-Hand" either.

### 3.3 Aspect of the Beast & Deadly Aspects (forever_client_data vs Era)
- Era 13161: one rank, untrackable only (aura 120).
- Forever 13161 / 1299445 / 1299446 / 1299447: untrackable + melee AP (aura 99) **+50 / +70 / +90 / +110** (SpellLevel 30/40/50/60; trainer levels 30/40/50/60 per Zygor), and e2 aura 42 proc-trigger → Quick Strikes 1299448 (+30% melee speed aura 319, 12 s), base ProcChance 0, ProcTypeMask 4 (melee auto attack).
- Aspect of the Hawk 13165…: RAP +20/35/50/70/90… (aura 124) + aura 42 → Quick Shots 6150 (+30% ranged speed aura 140, 12 s), base ProcChance 0.
- Deadly Aspects 19552: two aura-107 spellmods op 18 (proc chance) +2%/rank on the Hawk family flag (mask0 1048576) and Beast flag (mask2 16) → 10% at 5/5. Aspects are exclusive → you get ranged haste (Hawk) OR melee haste (Beast), never both.
- Aspect of the Beast's AP is melee-only (aura 99), it does not raise RAP.

### 3.4 2H vs MH+OH for a ranged BM (how to evaluate)
- For a BM who stays at range, melee weapons are stat sticks: Agility/Hit/Crit/Stamina/Int on them count fully for ranged (Agility → 2 RAP; ChrClasses RangedAttackPowerPerAgility=2); melee DPS only feeds Raptor Strike/white swings/Mongoose Bite.
- Compare the 2H against the PAIR, never against one 1H:
  `S_2H = Σ w_stat×stat(2H) + w_2Hdps×DPS_2H`
  `S_DW = Σ w_stat×stat(MH) + Σ w_stat×stat(OH) + w_MHdps×DPS_MH + w_OHdps×DPS_OH`
  with w_dps ≈ 0 for a non-weaving BM, small if you weave (theforeverera: 0.5 / 0.3 / 0.2 Agility per DPS point for 2H / MH / OH).
- Stat budget (classic itemization, community-mined, "accuracy doubtful"): slot modifier 2H = 1.00, 1H = 0.42, off-hand/shield 0.55, ranged 0.30 (allakhazam "Itemization Formulas") → two 1H of the same ilvl/quality ≈ 0.84 of one 2H's budget. Treat as a rule of thumb only.
- If you do weave: 2H gives one big MH roll for Raptor Strike (2H DPS = 1.3×1H and usually slow); DW adds an OH white swing at 50% with +19% white miss and more chances for Quick Strikes / on-hit procs. With Forever's melee-resets-ranged-timer bug, BM weaving is costly → stats first.

---------------------------------------------------------------------------------------------------
## 4. Zygor Guide Viewer Forever — exactly how it scores weapons (forever_client_data, addon code on disk)
Paths relative to D:/wow/World of Warcraft/_forever_/Interface/AddOns/ZygorGuidesViewerForever/

1. **Weights** (Data-Forever/Item-Statweights.lua:30-49): HUNTER BM line 34 `DAMAGE_PER_SECOND=2.4, AGILITY=1, ATTACK_POWER=0.43, RANGED_ATTACK_POWER=0.43, HIT=1, CRIT=0.8, …, ARMOR=0.005`; MM line 40 DPS 2.6; SV line 46 DPS 2.4 and a typo `RaNGED_ATTACK_POWER=0.55` → key never matches, SV gets 0 for RAP. caps `{HIT=5}`.
   itemtypes (line 33): `CLOTH=-40, LEATHER=-40, MAIL=40, BOW, CROSSBOW, GUN, TH_SWORD, TH_AXE, SWORD, AXE, FIST, TH_POLE, DAGGER, TH_STAFF, THROWN` (no MACE/TH_MACE/WAND/SHIELD/MISCARM/OFFHAND).
2. **DPS parsing**: Code-Forever/Item-DataTables.lua:28 `{blizz="DAMAGE_PER_SECOND", pattern="DPS_TEMPLATE"}` → the tooltip "(X damage per second)" line, same keyword for ranged and melee weapons. Weapon speeds are parsed (lines 59-60, MEELE_/RANGED_WEAPON_SPEED; Item-ItemScore.lua:446-453 keeps only the matching one) but have no weight → speed ignored.
3. **Score** (Item-ItemScore.lua:544-557): `score = Σ statvalue × weight` over all parsed stats; DPS is just another stat: `score += tooltipDPS × 2.4` for BM, for ranged and melee alike. Lines 567-574 (min-weight armor/DPS fallback) are unused for hunters because ARMOR and DAMAGE_PER_SECOND have weights. No ammo, quiver haste, weapon speed, normalization, hand, or 2H/1H factor anywhere.
   Example (client DPS tables, ilvl 45 green, stats ignored): 1H 26.73×2.4 = 64 pts, 2H 34.75×2.4 = 83 pts, bow 20.85×2.4 = 50 pts → a melee weapon's DPS counts like 64-83 Agility for a ranged BM.
4. **Cap rule** (Item-ItemScore.lua:548-553): for HIT (cap 5) on items not equipped, weight is halved if equipped hit > 5 OR `playerlevel < GetMaxPlayerLevel()` → while levelling, candidate items get HIT weight 0.5 while equipped items keep 1.0 (biased toward keeping current hit gear).
5. **Dual wield**: Code-Forever/Item-ItemScore.lua:28-56 `CanPlayerDualWield` has no HUNTER branch → returns false for hunters (even though Item-ItemScore.lua:111 records `character.dualwield=IsSpellKnown(674)`, unused here).
   `GetValidSlots` (Code-Forever/Item-ItemScore.lua:77-105): INVTYPE_WEAPON & !DW → main hand only (95-97); INVTYPE_2HWEAPON → main hand, twohander=true (92-94); INVTYPE_WEAPONOFFHAND & !DW → no slot → invalid (99-101); ranged/rangedright/thrown → INVSLOT_RANGED (get_slots_by_type 71-73).
   → **Zygor never recommends anything for a hunter's off hand** and never treats a one-hander as an off-hand candidate.
6. **2H vs 1H never compared**: Item-Upgrades.lua:354-356 — if the equipped main hand's twohander flag differs from the candidate's → `return false, "", 0, 0, "2hnd mismatch"`. Gear Finder: Item-GearFinder.lua:167-171 `is_replacement` (comment line 161: "don't switch between 2h and 1h when looking in dungeons"), used at 226 and 315. A hunter wearing a 2H is only shown 2H upgrades; wearing a 1H, only 1H main-hand upgrades.
7. **Thrown**: THROWN=1 in itemtypes + INVTYPE_THROWN → ranged slot, and thrown DPS at equal ilvl is 15% higher than bow/gun → if the Thrown skill is trained (skill check Item-ItemScore.lua:741-753), Zygor can rank a thrown weapon above a bow although it disables Auto Shot and all shots.
8. **Ammo & quivers not scored**: Code-Forever/Item-DataTables.lua:170-194 TypeToSlot has no INVTYPE_AMMO / bag entries → no slot → IsValidItem "not equipment" (Item-ItemScore.lua:680-686).
9. **Armor type**: GetItemScore 577-596 — for limit<0 types (LEATHER=-40): score ×0.9 at 40-49, ×0.5 at ≥50. IsValidItem 717-729: at playerlevel ≥ 40 leather/cloth become invalid ("valid until level 40"). get_upgrade Item-Upgrades.lua:286-288: if the equipped item is invalid → any valid candidate = 100% upgrade → **after 40 Zygor flags every mail piece as an upgrade over any leather piece, regardless of stats.**
10. Skill gate (Item-ItemScore.lua:741-753): untrained weapon types (e.g. Polearms before visiting a weapon master) are "no skill" → invalid.

---------------------------------------------------------------------------------------------------
## 5. Armor: leather → mail at 40
- Mail usable from 40 (SkillRaceClassInfo MinLevel 40; trainer level 40, 1g60s).
- ItemArmorTotal (forever_client_data): mail ≈ 2.05–2.12 × leather armor at the same ilvl (ilvl 40: 689 vs 1442; ilvl 45: 759 vs 1553; ilvl 50: 827 vs 1706).
- No armor-specialization bonus in Forever client data (searched SpellName "armor specialization", "mail specialization", "leather specialization": none).
- Classic itemization: stat budget per slot does not depend on armor type (allakhazam/wowwiki budget table has no armor-type factor) → a mail piece of equal ilvl/quality has about the same stats plus ~2× armor.
- Conclusion for the guide: prefer mail only when its stat score is equal or close; a leather piece with clearly more Agility/Hit/Crit stays better for DPS (armor has a tiny weight: Zygor 0.005/pt). Zygor itself forces mail after 40 (see §4.9) — ignore that when the leather piece has better stats.

---------------------------------------------------------------------------------------------------
## 6. Sources
- Forever DB2 (wago.tools, build 1.60.1.70888): SpellEffect, SpellMisc, SpellEquippedItems, SpellCategories/SpellCategory, SpellCastTimes, SpellRange, SpellDuration, SpellAuraOptions, SpellLevels, SkillRaceClassInfo, SkillLineAbility, SpellName, Spell, Item, ItemSparse, ItemEffect, ItemXItemEffect, ItemDamage{OneHand,TwoHand,Ranged,Thrown,Ammo}, ItemArmorTotal, SpellClassOptions.
- Era DB2 (build 1.15.9.70576) same spell tables + ItemDamage*.
- Zygor Forever addon files listed in §4.
- https://github-wiki-see.page/m/classic-hunter/forever-hunter/wiki/Attack-Formulas , /Ammo-and-Quivers , /Shot-Mechanics , /Melee-Weaving , /Ability-Mechanics , /Forever-Hunter-Patch-Notes , /Forever-Beta-Changes (forever_web; community wiki mirror; some numbers outdated beta values).
- https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/overview-pve-dps ; https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/stat-priority-pve-dps
- https://theforeverera.com/en/guides/classes/hunter/ ; https://classicwowforever.com/class-guides/hunter/survival/ ; https://mobalytics.gg/wow-forever/classes/survival-hunter-guide-1-60-ludideo ; https://hearthproof.com/classes/hunter/leveling/ ; https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-stat-priority
- https://warcraft.wiki.gg/wiki/Dual_wield ; https://warcraft.wiki.gg/wiki/Normalization ; https://wow.allakhazam.com/wiki/Itemization_Formulas_(wow) ; http://www.legacy-gaming.com/wow/classic-guides/classic-hunter-guide/
