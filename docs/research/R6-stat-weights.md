# R6-stat-weights — existing hunter stat weights / EP sets and gear-comparison methods

Scope tags: forever_client_data (Forever DB2/client files read this session), forever_web (pages explicitly about WoW Forever), classic_era, sod, tbc_or_later, unknown.
All numbers below were read from the cited source this session unless marked "derived" (my arithmetic on cited numbers) or "unverified (memory)".

---------------------------------------------------------------------------------------------------
## 0. TL;DR for calibration

1. Units in Forever: items store hit/crit/haste/expertise as RATINGS in DB2 but the tooltip shows a PERCENT with one decimal.
   - 14 crit rating = 1% crit, 10 hit rating = 1% hit (level-60 items; derived from Forever ItemSparse + RandPropPoints, matches chaosboost/mythicsim claims). Haste 10 = 1%, expertise 10 = 1% (mythicsim, chaosboost; not re-derived).
   - Tooltip strings exist ONLY in the Forever build (not in Era 1.15.9): `TOOLTIP_ITEM_STAT_HIT_PERCENT_INCREASE = "Equip: Improves your chance to hit by %1$.1f%%."`, crit/haste/expertise analogues.
2. Community / sim EP for Forever BM at level 60 (RAP = 1): Agility ~2.4–3.5; 1% crit ~26–44; 1% hit (below 8% cap) ~23–49; 1% haste ~14–24; Intellect ~1.1–2.0 ONLY with Careful Aim (user does not have it -> ~0 for damage); 1 ranged weapon DPS ~10.5–14 RAP; Strength ~0; melee AP ~0.1–0.3 (melee-weave builds only).
3. Classic Era (MM 20/31/0, lvl 60 raid, no pet scaling): 1% crit 27–35 AP, 1% hit 32–40.5 AP, 1 Agi 2.4–3.3 AP (buff dependent).
4. At level ~43 with leveling gear, crit/hit are worth far fewer RAP than at 60 (they scale with total damage; RAP's value per point does not shrink the same way) — wowcalc's low-gear Classic example gives crit 10.3 / hit 12.3 RAP per 1%. Use the formula in section 7, not the level-60 constants.
5. Zygor Forever hunter weights are a copy of a TBC 2.4.3 Pawn scale (per RATING POINT in TBC) applied to Forever's per-PERCENT tooltips -> hit/crit undervalued ~10–15x; plus Zygor's regexes probably cannot parse Forever's "1.0%" hit/crit lines at all; plus Zygor treats hunters as non-dual-wielders.
6. Hit cap: Forever 8% vs raid boss (lvl+3), 5% vs same level, 5.5%/6% vs +1/+2; no hit suppression (Classic Era was 9%). Hit beyond cap = 0 for ranged. Dual-wield white melee ~27% (irrelevant to ranged BM).

---------------------------------------------------------------------------------------------------
## 1. Zygor Forever weights — what the code actually does

Files (read-only, game client):
- Weights: `D:/wow/World of Warcraft/_forever_/Interface/AddOns/ZygorGuidesViewerForever/Data-Forever/Item-Statweights.lua` lines 30-48
  - BM (line 34): STRENGTH 0.05, AGILITY 1, DAMAGE_PER_SECOND 2.4, ATTACK_POWER 0.43, RANGED_ATTACK_POWER 0.43, HIT 1, EXPERTISE 0.05, CRIT 0.8, HASTE 0.5, ARMOR_PENETRATION 0.17, INTELLECT 0.8, MANA 0.075, SPIRIT 1, MANA_REGENERATION 2.4, STAMINA 0.5, HEALTH 0.02, HEALTH_REGENERATION 1, ARMOR 0.005, ... caps {HIT=5}
  - MM (line 40): DPS 2.6, AP/RAP 0.55, CRIT 0.6, HASTE 0.4, ARP 0.37, INT 0.9 ...
  - SV (line 46): contains typo `RaNGED_ATTACK_POWER=0.55` -> key never matches "RANGED_ATTACK_POWER" -> SV has no RAP weight (bug).
  - itemtypes (line 33): CLOTH/LEATHER until 40, MAIL from 40; BOW, CROSSBOW, GUN, TH_SWORD, TH_AXE, SWORD, AXE, FIST, TH_POLE, DAGGER, TH_STAFF, THROWN (no maces — consistent with SkillRaceClassInfo).
- Origin: these numbers are IDENTICAL to a TBC 2.4.3 Pawn scale "Hunt BM" published at http://tbcwowaddons.weebly.com/pawn.html ("derived primarily from Elitist Jerks and Maxdps.com at the time of TBC 2.4.3", normalized so Agility = 1): `Strength=0.05, Agility=1, MeleeDps=0.75, RangedDps=2.4, Ap=0.43, Rap=0.43, HitRating=1, ExpertiseRating=0.05, CritRating=0.8, HasteRating=0.5, ArmorPenetration=0.17, Intellect=0.8, Mana=0.075, Spirit=0.05, Mp5=2.4, Stamina=0.5, Health=0.05, Hp5=1, Armor=0.005 ...`. Differences: Zygor SPIRIT=1 (Pawn 0.05), HEALTH 0.02 (0.05), MeleeDps dropped. MM/SV also match ("Hunt Mark" RangedDps 2.6, Ap/Rap 0.55, Crit 0.6, Haste 0.4, ArP 0.37, Int 0.9).
  - In TBC "HitRating=1" meant per RATING POINT (~15.8 hit rating = 1% at 70 — unverified (memory)). So 1% hit ≈ 15.8 Agi in TBC context, which is reasonable there.
- Units in Zygor: stats are scraped from tooltip TEXT with regexes (Item-ItemScore.lua:436-468). Regexes come from (a) GlobalStrings ITEM_MOD_* templates and (b) localization L.HIT2/L.CRIT2:
  - `Localization/Core_enUS.lua:407` `CRIT2 = "Improves your chance to get a critical strike by ([0-9]+)%%."`, `:414` `HIT2 = "Improves your chance to hit by ([0-9]+)%%."` -> captured number is the PERCENT => Zygor HIT/CRIT weights are per 1%.
  - Consequence: in Forever, Zygor scores 1% hit = 1 Agi and 1% crit = 0.8 Agi (should be ~10–15 Agi each, see section 4). Massive undervaluation.
- Forever tooltip format breaks the regex (high-confidence inference, NOT verified in game):
  - Forever GlobalStrings (wago.tools GlobalStrings build 1.60.1.70888, row 59247/59249): `"Equip: Improves your chance to hit by %1$.1f%%."` -> renders "1.0%". Lua pattern `by ([0-9]+)%%.` requires '%' right after the digits; "1.0%" has '.' -> no match. ITEM_MOD_HIT_RATING regex ("Increases your hit by %s.") does not match that line either.
  - ruRU (wago GlobalStrings locale=ruRU): `"Если на персонаже: повышает вероятность попадания на %1$.1f%%."`, crit `"...повышает вероятность критического удара на %1$.1f%%."`; Zygor ruRU `HIT2 = "Вероятность нанесения удара увеличена на ([0-9]+)%%."`, `CRIT2 = "Увеличение вероятности нанесения критического урона на ([0-9]+)%%."` (Localization/Core_ruRU.lua:24,31) — different wording -> never matches on the user's Russian client.
  - Era 1.15.9 GlobalStrings has NO TOOLTIP_ITEM_STAT_*_PERCENT strings -> these are Forever-new.
  - => On Forever, Zygor most likely scores hit/crit/haste/expertise items as 0 for those stats. Verify in game via Zygor's verbose item-score tooltip.
- Cap logic (Item-ItemScore.lua:548-553): for capped stats (HIT, cap 5) on non-equipped items, weight is halved if current equipped hit > 5 OR `playerlevel < GetMaxPlayerLevel()` -> while leveling, HIT weight always 0.5.
- Weapon DPS: DAMAGE_PER_SECOND parsed from DPS_TEMPLATE "(%s damage per second)" for both melee and ranged weapons (Code-Forever/Item-DataTables.lua:28); single weight 2.4 Agi per DPS used for both. Slots are compared separately, so ranking within the ranged slot is only off by the DPS-vs-stats ratio, but melee weapons get 2.4 Agi per melee DPS, which is far too high for a ranged BM.
- Dual wield: `Code-Forever/Item-ItemScore.lua:28-56` CanPlayerDualWield returns true only for DK/Rogue/DH/Fury Warrior/WW Monk/Enh Shaman/Feral — NOT hunters. So for hunters 1H weapons go to main hand only and INVTYPE_WEAPONOFFHAND is rejected (lines 89-101). Also `Item-Upgrades.lua:356` returns "2hnd mismatch" when a 2H and 1H are compared against each other -> Zygor never evaluates 2H vs 1H+1H for a hunter. (Core Item-ItemScore.lua:111 records `IsSpellKnown(674)` dual wield but the Forever slot logic ignores it.)
- Armor/DPS fallback: whiteScoreWeight = 0.1 x lowest positive weight (Item-ItemScore.lua:181-195).
- Pawn import in Forever is broken: `ItemScore.Gear_PawnToZygor` / `KeywordsPawnToRules` are referenced (Item-ItemScore.lua:1386,1409) but not defined anywhere in the addon (grep found no definition).

Verdict: Zygor Forever hunter weights = heuristic TBC rating-era weights; wrong units for Forever; treat as one weak data point.

---------------------------------------------------------------------------------------------------
## 2. Forever stat units (forever_client_data)

Local download: `C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/db2_R6-stat-weights/` (ItemSparse.csv, Item.csv, RandPropPoints.csv, GlobalStrings*.csv; build 1.60.1.70888 unless noted).

- ItemSparse stat types used (count of item-stat slots): 7 STA 3451, 5 INT 1895, 4 STR 1317, 3 AGI 1152, 6 SPI 1063, 45 SPELL_POWER 1027, 32 CRIT_RATING 523, 41 / 42 healing/spell dmg, 38 AP 285, 31 HIT_RATING 184, 36 HASTE_RATING 4, 37 EXPERTISE 8, 39 RAP 20 ... (stat-ID names from modern ItemModType enum — unverified (memory) for IDs >56: 84-89, 117, 124, 127, 128, 131, 132 are unknown/new).
- Amount formula (modern): amount = StatPercentEditor/10000 x RandPropPoints[ilvl][quality][slotGroup]. Checks:
  - Quick Strike Ring 18821 (ilvl 67 epic, finger -> group 2 = 28): STA 2857 -> 8.0, STR 1786 -> 5.0, AP 10714 -> 30.0, CRIT 5000 -> 14.0 (Classic QSR = 1% crit) => 14 crit rating = 1%.
  - Kiss of the Spider 22954 (ilvl 85 epic trinket -> group 1 = 43): CRIT 3256 -> 14.0, HIT 2326 -> 10.0 (Classic: 1% crit, 1% hit) => 10 hit rating = 1%.
  - Fletcher's Gloves 7348 (ilvl 25 green hands -> Good group 1 = 6): CRIT 23333 -> 14.0 -> shown as "+1% Critical Strike" by wowhandbook (Forever data) — suggests the 14:1 conversion is NOT level-scaled for display (unverified in game).
- Tooltip strings (Forever-only): hit/crit `%1$.1f%%`, haste "Increases your attack speed and casting speed by %1$.1f%%.", expertise "Reduces chance to be Dodged or Parried by %1$.1f%%.", AP "+%1$d Attack Power.", RAP "+%1$d Ranged Attack Power.", weapon damage "+%1$d Weapon Damage.". CR_HASTE_RATING_RANGED_TOOLTIP: "Increases the speed of Melee attacks, Ranged attacks, and Spell casts" (haste affects ranged).
- Weapon subclass check (Item.csv): Persuader 22384 = 1H Mace (2/4), Enchanted Battlehammer 12776 = 2H Mace (2/5) — both recommended by brokenmeta's BM optimizer although hunters have no mace skill in Forever SkillRaceClassInfo -> brokenmeta optimizer ignores proficiencies (reliability flag).

---------------------------------------------------------------------------------------------------
## 3. Forever-specific community EP / weights (forever_web)

| Source | Assumptions | RAP=1 equivalents (derived where noted) |
|---|---|---|
| Icy Veins Forever BM stat priority (Impakt, 2026-10-26) https://www.icy-veins.com/wow-forever/beast-mastery-hunter-ranged-dps-pve-stat-priority | lvl 60, beta info | "1 point of Agility is roughly equivalent to 2.4 ranged attack power"; priority Weapon Damage > Hit (8%) > Crit > Agility > (Int w/ Careful Aim) > AP; pet inherits 10% of higher of RAP/MAP and 100% crit; says "Your pet also does not directly benefit from your hit chance at all". |
| Icy Veins Forever SV page (2026-10-26) https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-stat-priority | lvl 60 | hit cap 9%->8% because hit suppression removed; Surefooted 3%; says pet "will inherit 8% of your hit" (contradicts BM page); pets 10% AP, 100% crit; pet scaling "only affects auto attack damage and does not affect pet abilities". |
| Wowhead Forever BM (Docoda) https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/stat-priority-pve-dps (search highlight only) | speculative, beta locked lvl 30 | Hit to 9% > Crit > Agi > Int > RAP > Spirit > Sta; "Forever seems to have 0.x% values on gear". |
| mythicsim https://mythicsim.com/wow-forever/stat-priority/hunter | lvl 60, BM 31/20/0 weave, client 1.60.1.70707, raid buffs/consumes, 2-min patchwerk, 10k it; ratings hit10/crit14/haste10/exp10 per 1%; below hit cap | EP (Agi=1) per rating point: Hit 1.41, Crit 0.91, Exp 0.73, Int 0.59, Haste 0.40, RAP 0.29, MP5 0.26, ArP 0.13, Str 0.10, AP 0.09, "Weapon damage" 1.20. Derived per 1%: hit 14.1 Agi, crit 12.7 Agi, haste 4.0 Agi; RAP=1: Agi 3.45, hit 48.6, crit 43.9, haste 13.8, Int 2.0 (Careful Aim assumed in 31/20). |
| distillnote https://distillnote.com/classes/hunter/beast-mastery/stats | lvl 60 engine preset gear, 2-min, 5000 it (run 6 Nov) | DPS per: crit 1% 6.33, hit 1% 5.53, haste 1% 3.63, exp 1% 1.78, ranged weapon DPS 1.57, phys dmg 1.04, Agi 0.46, Int 0.164, RAP 0.149, ArP 0.055; Str/MP5/AP 0. Derived RAP=1: crit 42.5, hit 37.1, haste 24.4, exp 11.9, rDPS 10.5, Agi 3.09, Int 1.10. |
| brokenmeta https://brokenmeta.gg/en/wow-forever/guides/hunter/beast-mastery/ | lvl 60 BM 33/18 (incl. Careful Aim 5/5, Lethal Attacks 5/5), 180 s, 6000 runs, raid buffs, best known gear, sim build 69913 | Relative to AP=1: Agi 2.96, crit per rating 2.67 (x14 = 37.4 per 1%), Int 2.01, haste per rating 1.72 (x10 = 17.2 per 1%), hit ~0 (capped), Str 0, Spirit -0.09. Optimizer picks maces (see §2) -> low reliability. |
| wowhandbook https://wowhandbook.com/bis/hunter/ | "Data from WoW Forever client 1.60.1.70862"; leveling 20-60 BiS; crit/hit per 1% | BM leveling: Crit 26.35, Hit 22.94, Agi 2.77, Int 1.12, AP 1, Sta 0.4, Weapon DPS 14 (AP per DPS, fixed). MM: 31.5/23.75/2.83/1.08. SV: 31.33/21.91/3.1/1.09. Hit needed 5/5.5/6/8% vs +0/+1/+2/+3. |
| wowfdb https://wowfdb.com/classes/hunter/beast-mastery/ | build 70205 list | Int = Agi point for point with Careful Aim 5/5; "attack power on gear is worth half as much"; Sta/Str 0; 9% cap "unverified". |
| method.gg MM https://www.method.gg/wow-forever/class-guides/marksmanship-hunter/bis-gear-and-stats | MM | Careful Aim converts 100% Int to AP; pets inherit 100% crit, 10% of highest AP, 30% armor, 2 HP per Stamina. |
| warcrafttavern https://www.warcrafttavern.com/forever/guides/hunter/ | general | Hit & crit unified across all attack types; weapon skill bonuses replaced by Expertise; Haste added; pets scale with 10% AP and 100% crit; Unleashed Fury & Ferocity values reduced vs Classic. |

Hit caps (forever_web): conquestcapped (Oct 15 beta character panel) https://conquestcapped.com/guides/wow-forever/wow-forever-hit-cap/ : melee/ranged 5% same level, 8% raid boss; spells 4% / 17%; dual-wield white ~24% / ~27-29%. Grimoire https://wowgrimoire.app/guides/stats-and-combat same; "Hit Chance ... is a flat percentage, not a rating" (player-facing). chaosboost https://www.chaosboost.com/articles/wow-forever-stats-explained : 1% hit = 10 rating, 1% crit = 14 rating, 1% expertise = 10 rating; "+1 weapon DPS still equals 14 attack power"; Kiss of the Spider now "+14 Critical Strike Rating and +10 Hit Rating" in client data (consistent with my §2 derivation). outputlag: Blizzard has not published a hit cap.

Pet scaling (forever_web vs sod):
- Forever community: pet gets 10% of hunter's higher AP (RAP or MAP), 100% crit, ~30% armor (method.gg, warcrafttavern, Icy Veins). Pet hit inheritance disputed (Icy Veins BM: none; Icy Veins SV: "8%").
- Client: "Hunter Pet Scaling" 415429 has all base points 0 (server-side values) and includes aura 54 and 55 (shared context). By TrinityCore AuraType enum 54 = MOD_HIT_CHANCE, 55 = MOD_SPELL_HIT_CHANCE (unverified (memory)) -> suggests pets DO inherit hit; contradicts Icy Veins BM.

---------------------------------------------------------------------------------------------------
## 4. Classic Era EP sets (classic_era)

| Source | Assumptions | Values (AP/RAP = 1) |
|---|---|---|
| Skinnay's Classic Hunter Gear lists (Sixx's DPS sheet) https://gist.github.com/skinnay-dev/39f71f3cce1c64b95142f7e0e0d97bca | lvl 60, MM 20/31/0 (13/31/7 for weave P3-4), full raid buffs + consumes + boss debuffs, no pet scaling | Early phases: 1% crit 32, 1% hit 35, Agi 2.6 (Kings 2.85, ZG 3.0, both 3.3). Later: crit 33-35, hit 37.5-40.5, Agi 2.43-2.61. Melee-weave: melee hit 1% 5.5-7, melee AP 0.14-0.16. Stat-stick eAP table: Hakkari MH/Fang of the Faceless/R14 62, Brutality Blade 58, Core Hound Tooth 54, Doom's Edge/Dragonfang 42, Dal'rend's (avg) 42, Ribsplitter 39, Bone Slicing Hatchet 34, "1% crit weapon" 34. |
| Icy Veins Classic hunter stats (Impakt, 2019) https://www.icy-veins.com/wow-classic/hunter-dps-pve-stat-priority | lvl 60 raid | 1% hit ~32 AP; 1% crit ~32 AP; 1 Agi ~2.5 AP solo/unbuffed, ~3 AP full raid + world buffs; boss miss 8.6% -> 9% cap. |
| legacy-wow Classic Hunter Guide https://legacy-wow.com/classic-hunter-guide/ | 20/31/0, full buffs except world/shaman/paladin, lvl 63 dragonkin with 5 sunders | 1% crit = 26.95 AP (T1), 31.80 (T2), 32.43 (R13), 35.03 (T3). 10 AP = 1.37-1.44 DPS. |
| Elysium forum https://forum.elysium-project.org/topic/23285-hunter-stat-weights/ | private-server 1.12 | "30 rap is safe average" for 1% crit; ~30 AP ~= 10 agi ~= 1% crit. |
| Wowhead Classic stats (Sh3rro) https://www.wowhead.com/classic/guide/classes/hunter/dps-stat-priority-attributes-pve | lvl 60 | 53 Agi = 106 RAP + 1% crit + 2% dodge; 5% hit PvP cap, 9% PvE (blue post: first 1% of hit ignored vs +10 def skill); crit "soft cap" ~24-25% (19-20% with Lethal Shots) — mechanism not explained, low trust. |
| wowcalc Classic theorycrafting https://wowcalc.net/en/classic/theorycrafting/hunter | unknown default char (RAP 554 -> low gear) | BM: hit 1% 12.3, haste 1% 11.6, crit 1% 10.3, Agi 2.2, SP 1.6 (Arcane Shot), Int 0.09. Illustrates that hit/crit EP collapse at low gear. |
| Dhralla Elysium guide https://forum.elysium-project.org/topic/47244-dhrallas-hunter-guide/ | 1.12 | 1 Agi = 2 RAP; 53 Agi (46 SV) = 1% crit; 14 RAP ≈ 1 DPS; ranged attacks: miss/hit/crit/block only (no dodge/parry/glance). |

Ranged weapon DPS value (classic_era theory): auto shot / Multi-Shot / Aimed Shot add weapon damage and RAP/14 x weapon speed -> 1 ranged DPS = 14 RAP for those shots (Wowhead Classic stats overview "1 DPS per 14 AP"; chaosboost says unchanged in Forever). Overall EP_rangedDPS = 14 x S where S = share of RAP-scaling damage that also scales with weapon (excludes Arcane Shot, stings, pet, hawk). Sims: distillnote 10.5 RAP; wowhandbook 14 (fixed); wowsims SoD P2-6 6.32 RAP (sod).

---------------------------------------------------------------------------------------------------
## 5. SoD (sod) — wowsims presets and pet scaling

Files downloaded to `C:/Users/Admin/AppData/Local/Temp/claude/2a905840fcccbf59/16fa10c0-d056-41cc-b0ee-6fc1125ecde7/scratchpad/dl_R6/wowsims/` from github.com/wowsims/sod.
- `ui/hunter/presets.ts` (master): `DefaultWeights = PresetBuildPhase7NaxxRanged.epWeights!` but the build JSONs contain no epWeights -> undefined; actual defaults live in `ui/hunter/sim.ts`.
- `ui/hunter/sim.ts` defaults (master, = commit 03b580affb 2025-02-14 "added p7 presets according to 60s p7 sim spreadsheet"), epReferenceStat = Agility: Str 0.12, Agi 1.0, Sta 0, Int 0.02, AP 1, RAP 1.0, MeleeHit 15.0, MeleeCrit 10.22, Expertise 4.13, SP 0.11, Nature 0.01, Arcane 0.10, SpellCrit 0.02, MP5 0.05, FireRes 0.5; MH DPS 3.00, OH DPS 1.66, Ranged DPS 2.61, MeleeSpeedMult 3.92, RangedSpeedMult 1.43, Timeworn 11.06. (AP = RAP = Agi = 1 is internally inconsistent for a ranged build -> these are gear-picker placeholders mixing melee/ranged.)
- Older defaults (commits c13f043954 2024-02-24 P2 "update Hunter Eps" through a8de0c7140 P5), epReferenceStat = RangedAttackPower: Str 0.30, Agi 0.64, AP 1, RAP 1.0, MeleeHit 3.29, MeleeCrit 4.45, MeleeHaste 1.08, ArP 1.32, SP 0.03, MP5 0.05; MH DPS 2.11, OH DPS 1.39, Ranged DPS 6.32. (Agi 0.64 RAP is impossible for ranged since 1 Agi = 2 RAP -> these were melee-hunter-derived; do not use for ranged.)
- Units: `sim/core/base_stats_auto_gen.go:11-15` CritRatingPerCritChance = 1, MeleeHitRatingPerHitChance = 1, ExpertiseRatingPerExpertiseChance = 1 -> 1 stat point = 1%.
- Pet stat inheritance `sim/hunter/pet.go:278-295`: Stamina 0.3 x owner, Armor 0.35 x owner, AttackPower = 0.22 x owner RAP, MeleeCrit = owner MeleeCrit, SpellCrit = owner MeleeCrit, MeleeHit = owner hit, SpellHit = 2 x owner hit, Expertise = owner expertise.
- `sim/core/constants.go`: DefaultAttackPowerPerDPS = 14.0.
- Early SoD Icy Veins BM/MM pages (https://www.icy-veins.com/wow-classic/beast-mastery-hunter-dps-season-of-discovery-pve-stat-priority): crit "does NOT scale your pet's critical strike chance, making this a weak stat now that pets have AP scaling"; priority Hit 9% > Agi > AP > Crit. wowsims commit c13f043954 (2024-02-24) "Update ... Hunter Pets Crit formulas" -> later SoD pets inherit 100% crit. So: SoD BM weights moved AP/Agi up when pets gained AP scaling, crit up again once pets inherited crit.

---------------------------------------------------------------------------------------------------
## 6. Melee weapon for a ranged hunter, 2H vs DW, hit cap

- Classic consensus: melee weapon = stat stick (Agi/AP/crit/hit), melee DPS irrelevant unless melee weaving (Skinnay stat-stick table in eAP; wowhead classic forum "Hunters want Agility... two Dawn's Edges or two Bone Slicing Hatchets... 2 +15 agility enchants" https://www.wowhead.com/classic/spell=674/dual-wield).
- Enchants (classic_era/tbc data): Enchant Weapon - Agility +15 (1H), Enchant 2H Weapon - Agility +25 -> DW = +30 Agi vs 2H +25 Agi (psynister https://psynister.wordpress.com/2010/03/30/hunter-weapons-20-40/ ; lurkerlounge 2006 "Still won't beat twin +15's on one-handers for Hunters"). Forever enchant values: brokenmeta lists "Enchant 2H Weapon - Agility +25 Agility" in Forever data (forever_web, unverified in DB2 here).
- Off hand in classic: weapon damage halved for OH and DW white attacks get +19% miss, but OH weapon STATS count 100% (stat stick) -> for a ranged hunter OH damage is irrelevant. Forever DW white miss +19% (~27% vs boss) per conquestcapped/grimoire.
- Melee hunter Forever: Icy Veins SV notes melee hunter viable in Forever and hit past 8% helps DW; mobalytics Forever leveling: "Prioritize Two-Handed Weapons over One-Handed ones ... melee attacks and Raptor Strike hit harder" (leveling melee-weave advice).
- Zygor cannot model DW for hunters (see §1).
- Hit cap: Classic Era 9% vs boss, 5% vs same level, hit = crit in damage terms but capping prioritized (Icy Veins); Forever 8% / 5% / 5.5 / 6%, dungeons lvl 62 -> 6% (chaosboost). Above cap: 0 value for ranged hunter. Crit has no hard cap for ranged; classic two-roll for ranged (AMR forum https://forums.askmrrobot.com/t/hunter-bis-and-item-weights/8725 "Roll 1 - Hit/Miss/Block ... Roll 2 - Normal/Crit").

---------------------------------------------------------------------------------------------------
## 7. Calibration method (derived — my framework, not a cited source)

Let D = total damage per second of hunter + pet + hawks, and split it into:
- W = hunter weapon-based damage (Auto Shot, Multi-Shot, Aimed Shot): scales with (weaponDPS + ammoDPS + RAP/14)
- A = other hunter damage scaling with RAP (Arcane Shot, Serpent Sting, hawk dive 5% RAP)
- P = pet + hawk damage, scaling with 10% of hunter AP (Forever community) and with hunter crit (100% inheritance)
Then (all in DPS):
- dD/dRAP ≈ W/(14*(wDPS+aDPS) + RAP) + a_coef terms + 0.10 * dP/dPetAP
- EP_rangedDPS (in RAP) = 14 * [dW/dRAP] / [dD/dRAP]  (≈ 10–14; lower the larger the pet share)
- EP_crit(1%) = 0.01 * [W*(cm_hunter-1)/(1+c_h*(cm_hunter-1)) + A*(...) + P*(cm_pet-1)/(1+c_p*(cm_pet-1)) + Frenzy uptime gain] / [dD/dRAP]   (cm = crit multiplier 2.0; Mortal Shots not taken by user)
- EP_hit(1%) (below cap) = 0.01 * (W + A + specials) / (1 - miss) / [dD/dRAP] (+ pet part only if pet inherits hit)
- EP_agi = 2 + EP_crit(1%)/AgiPerCrit(level)   (AgiPerCrit = 53 at 60 in Classic; lower at level 43 — needs the level table from another agent)
- EP_int = Careful Aim ranks * 0.2 (user: 0) + mana value (fight-length dependent, not DPS)
- EP_meleeDPS for ranged BM ≈ 0; melee weapon valued by its stats only.
- At level 43 the denominators (total AP-equivalent damage) are ~half of level-60 values, so crit/hit EP in RAP are roughly half of the level-60 numbers (consistent with wowcalc low-gear 10–12 RAP vs 32–44 at 60).
