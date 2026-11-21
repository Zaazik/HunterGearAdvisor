# R4-ability-formulas — формулы урона способностей охотника в WoW Forever

Агент: R4-ability-formulas. Дата: 2026-11-12. Клиент Forever 1.60.1.70888, сравнение с Classic Era 1.15.9.70576.

## 0. Источники и как читать

- **Forever DB2** (wago.tools, build 1.60.1.70888): общая папка `scratchpad/db2/` + мои загрузки в
  `scratchpad/db2_R4-ability-formulas/f/` (SpellCastTimes, SpellDuration, SpellCategories, SpellClassOptions,
  SpellRange, SpellPower, SpellEquippedItems и др.).
- **Classic Era DB2** (build 1.15.9.70576): `scratchpad/db2_R4-ability-formulas/era/`.
  ВАЖНО: в клиенте Era серверные числа вырезаны — `EffectBasePoints = 0` у всех способностей охотника
  (например, Aimed Shot e0 bp=0 die=1). Поэтому числа Era я беру с wowcalc.net (Classic 1.12/1.15.9) и
  wowhead classic, а из Era DB2 сравниваю только структуру: типы эффектов, время каста, КД, длительности, требования к оружию.
- Полный автоматический дифф Era→Forever по всем спеллам навыков 50/51/163:
  `scratchpad/db2_R4-ability-formulas/diff_hunter_era_vs_forever.txt` (скрипт `scratchpad/scripts_R4/diff.py`).
- Скрипты: `scratchpad/scripts_R4/dump.py <dir> <spellIDs…>` (печатает описание, misc, КД, категорию, стоимость, уровни, эффекты),
  `scratchpad/scripts_R4/masks.py` (какие таланты задевают какие способности по SpellClassMask), `scratchpad/scripts_R4/grepdesc.py`.
- **Официально Blizzard**: Kaivax, «WoW Forever Beta Development Notes – Updated November 2», пост #9 от 3 ноября 2026:
  https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696/9
  (копия: https://www.wowhead.com/forever/news/wow-forever-official-development-notes-and-class-tuning-383704);
  Class Deep Dive Hunter: https://news.blizzard.com/en-us/article/24301515/world-of-warcraft-forever-class-deep-dives-hunter-and-druid
- **wowsims/forever** (симулятор, читает файлы игры + подгоняет по логам; master на 2026-11-12, коммит b2047bfe):
  https://github.com/wowsims/forever/tree/master/sim/hunter — копии исходников у меня в
  `scratchpad/db2_R4-ability-formulas/wowsims_hunter/*.go.txt`.
- **Комьюнити-вики Forever** (classic-hunter/forever-hunter): https://github-wiki-see.page/m/classic-hunter/forever-hunter/wiki/Attack-Formulas и
  https://github-wiki-see.page/m/classic-hunter/forever-hunter/wiki/Forever-Hunter-Patch-Notes (часть данных до хотфикса 3 ноября — устарела по числам).
- **wowfdb.com** журнал изменений: https://wowfdb.com/classes/hunter/changes/
- Нормализация (история): https://warcraft.wiki.gg/wiki/Normalization ; патч 1.10 Multi-Shot: https://vanilla-wow-archive.fandom.com/wiki/Multi-Shot ;
  лог классик-беты (Multi-Shot = 2.8×RAP/14, патроны × реальная скорость): https://github.com/watchyoursixx/classic-hunter/issues/4 ;
  старый EJ-пост с формулами: https://legacy-wow.com/hunter-damage-cycles-breakdown/

Обозначения ниже: `W` — средний урон оружия (min+max)/2 (+ прицел/scope, он плоско добавляется к урону оружия),
`S` — родная скорость оружия, `AmmoDPS` — ДПС патронов, `RAP` — сила атаки дальнего боя (с учётом Hunter's Mark против цели),
`MAP` — сила атаки ближнего боя.

---

## 1. Главная поправка к заданию: нормализация в Classic Era

В задании сказано «в Classic Era ranged weapon-damage shots используют реальную скорость оружия». **Это неверно для Aimed Shot и Multi-Shot.**
- Патч 1.10.0 (28.03.2006): Multi-Shot (и Aimed Shot) нормализованы — AP считается как у оружия скоростью 2.8
  (vanilla-wow-archive Multi-Shot, warcraft.wiki.gg Normalization: «Hunter ranged instant attacks were also normalized in patch 1.10»).
- Classic Era 1.12-логика (лог беты 1.13, watchyoursixx #4): `MS = (13*2.7 + (2.8*402/14 + 40 + 20)) * 1.15 * 1.05` — RAP×2.8, патроны × реальная скорость 2.7.
- В DB2 обеих версий Aimed/Multi = эффект 121 (`NORMALIZED_WEAPON_DMG`), Auto Shot = эффект 58 (`WEAPON_DAMAGE`, реальная скорость).
- Реальная скорость для RAP остаётся у: Auto Shot, Scatter Shot (эффект 31), белых ударов, Raptor Strike (эффект 58).

---

## 2. Формулы дальнего боя (Forever)

### 2.1 Auto Shot (75)
- DB2 Forever: e0 effect 58 (weapon damage), bp 0; дальность 35 ярдов (RangeIndex 114), мин. 8 ярдов; требует лук/огнестрел/арбалет
  (SpellEquippedItems subclass bits 2,3,18 — **метательное оружие (16) Auto Shot не стреляет**).
- Формула: `AutoShot = W_ranged + AmmoDPS*S_ranged + RAP/14*S_ranged` (scope входит в W).
  Источники: forever-hunter вики Attack-Formulas («Verified»); wowsims `core/attack.go` (`BaseDamage + bonusDps*SwingSpeed`, `CalculateWeaponDamage = base + SwingSpeed*AP/14`).
- Скорость: делится на ускорение (колчан/подсумок 10–15%, Quick Shots 30%, Rapid Fire 40%); в wowsims множители ускорения перемножаются.
- Forever-специфика: с 15 окт. Auto Shot требует 0.5 с стоять на месте перед выстрелом (wowfdb). Auto Shot продолжает стрелять во время каста Aimed Shot / Sniper Shot
  (forever-hunter вики, помечено как подтверждённое Blizzard; endgametools) — в Classic каст Aimed Shot «съедал» автовыстрелы.
- Scope: та же формула в Era (EJ, dkpminus).

### 2.2 Aimed Shot (19434/20900/20901/20902/20903/20904) — **базовая способность в Forever**
| Ранг | ID | Ур. | Бонус Forever (DB2 e0 bp) | Бонус Classic (wowcalc) | Мана (DB2) |
|---|---|---|---|---|---|
| 1 | 19434 | 20 | 40 | 70 | 75 |
| 2 | 20900 | 28 | 70 | 125 | 115 |
| 3 | 20901 | 36 | 115 | 200 | 160 |
| 4 | 20902 | 44 | 185 | 330 | 210 |
| 5 | 20903 | 52 | 260 | 460 | 260 |
| 6 | 20904 | 60 | 350 | 600 | 310 |
- e0 effect 121 (normalized weapon dmg + bp). Каст **2.0 с** (Era 3.0 с), КД категории 2 = **6 с, общий с Multi-Shot**, ГКД 1.5 с.
- Формула: `AimedShot = W_ranged + AmmoDPS*S_ranged + RAP/14*2.8 + Bonus(rank)` (+ возможно +9, см. ниже).
- В Forever — базовая способность с 20 уровня у тренера, не талант (Blizzard Deep Dive; в дереве талантов Forever её нет; SkillLineAbility AcquireMethod 0).
- Бонус поднят ~110% хотфиксом 3 ноября (было 20/34/55/89/125/166) — числа в DB2 совпадают с постом Blizzard/форумом.
- Каст укорачивается ранжевым ускорением (wowsims `hasteRangedCast`).
- wowsims (hunter.go): «In game Multi-Shot and Aimed Shot hit 9 harder than the rows' normalised weapon damage… the game files state no such bonus» — константа `normalizedShotBonus = 9`, TODO, наблюдалась на 34/36 ур.; не подтверждено.

### 2.3 Multi-Shot (2643) — один ранг
- Forever: только ранг 1 (2643); ранги 2–5 (14288/14289/14290/25294) **удалены** (нет в SpellName/SpellEffect Forever).
- e0 effect 121 bp 0, `ChainTargets = 3`. КД 6 с (Era 10 с), общий с Aimed Shot (категория 2). Стоимость 13.9% базовой маны (Era 100…230 маны).
- Формула (на каждую из 3 целей): `MultiShot = W_ranged + AmmoDPS*S_ranged + RAP/14*2.8` (+9?, wowsims).
- Каст 0.5 с, ускоряется хастом — не в файлах игры, по wowsims multi_shot.go и forever-hunter вики.
- Classic: +0/40/80/120/150 по рангам (wowcalc), 10 с КД, мгновенный (на деле короткий каст).

### 2.4 Sniper Shot (1310687/1310785/1310786) — талант MM 31 (Forever-новый)
- e0 effect 121 bp 320/450/590 (ур. 40/48/58); e1 aura 107 misc 5 (SPELLMOD_RANGE) +10 ярдов следующим 3 выстрелам на 10 с (charges=3).
  Каст 4.0 с, КД 15 с, дальность 45 ярдов, 365 маны (DB2).
- Формула (DB2 + wowsims sniper_shot.go): `SniperShot = W_ranged + AmmoDPS*S_ranged + RAP/14*2.8 + Bonus(rank)`; wowsims +9 не даёт; forever-hunter вики: «Unverified».
- Бонус удвоен 3 ноября (было 160/225/295).

### 2.5 Arcane Shot (3044, 14281–14287)
| Ранг | Ур. | Forever bp | Classic |
|---|---|---|---|
| 1 | 6 | 25 | 13 |
| 2 | 12 | 35 | 21 |
| 3 | 20 | 50 | 33 |
| 4 | 28 | 85 | 59 |
| 5 | 36 | 120 | 83 |
| 6 | 44 | 175 | 115 |
| 7 | 52 | 220 | 145 |
| 8 | 60 | 280 | 183 |
- e0 effect 2 (school damage), школа Arcane (64), Variance 0 (фиксированный урон), КД 6 с (категория 1173, общая с Summon Hawk).
- В клиенте Forever `EffectBonusCoefficient = 0` и `BonusCoefficientFromAP = 0` (в Era SP-коэф. 0.204…0.429 — **SP-скейлинг убран**).
- **AP-скейлинг серверный**: Blizzard 3.11: «Attack Power coefficient raised from 0.1 to 0.15». wowsims arcane_shot.go: `const arcaneShotAPShare = 0.15`, `base + 0.15*RangedAttackPower(target)`.
- Формула: `ArcaneShot = Base(rank) + 0.15*RAP`. Арканный урон — броня не режет. Не зависит от оружия и патронов.
- Стоимость: с хотфикса 10–11 ноября 11% базовой маны на всех рангах (wowfdb, wowhead news 383837); в DB2 70888 ещё старые 25…190.

### 2.6 Serpent Sting (1978, 13549–13555, 25295)
- e0 aura 3 (periodic damage), период 3 с, длительность 15 с → 5 тиков. Тик Forever: 3/7/14/26/40/58/75/100/135 → итого 15/35/70/130/200/290/375/500/675.
  Classic итого: 20/40/80/140/210/290/385/490/555 (wowcalc). Ур.: 4/10/18/26/34/42/50/58/60 (ранг 9 из книги — wowsims).
- Клиент: коэффициенты 0. Blizzard 3.11: «Attack Power coefficient per tick increased to 5% from 3%». wowsims: `serpentStingTickAPShare = 0.05`, читается на каждом тике.
- Формула: `SerpentTick = Tick(rank) + 0.05*RAP`; `SerpentTotal = 5*Tick(rank) + 0.25*RAP`.
- Тики критуют с ранжевым критом и пересчитываются по текущему RAP (forever-hunter вики; wowsims «ticks crit at the ranged crit»).

### 2.7 Volley (1510/14294/14295) — без КД
- Forever: канал 6 с, тик каждые 1 с (e2 aura 226 periodic dummy) → каждый тик кастует «волну» 1279721/1279719/1279715: effect 2 Arcane, bp 70/91/112 (Classic 50/65/80 в секунду, wowcalc).
  КД убран (Era catRecovery 60000 → Forever 0). Мана 350/420/490.
- e0 Volley несёт `EffectBonusCoefficient = 0.03`; wowsims трактует как долю RAP: `wave = base + 0.03*RAP` на цель. forever-hunter вики: «AP scaling needs verified».
- Формула: `VolleyWave = Base(rank) + 0.03*RAP` (за цель), 6 волн; канал ускоряется скоростью каста (wowsims). С 12 ноября не вызывает проки и прерывается движением (wowfdb).

### 2.8 Scatter Shot (19503) — талант MM
- e0 effect 31 bp 50 (50% урона оружия), дезориентация 4 с, КД 30 с, 8% базовой маны.
- Формула: `ScatterShot = 0.5*(W_ranged + AmmoDPS*S_ranged + RAP/14*S_ranged)` (реальная скорость; forever-hunter вики «Verified»).

### 2.9 Summon Hawk (1293241 / 1293525 / 1293526 / 1293527) — талант BM 16
- 4 ранга (а не 1): ур. 25 (талант) / 36 / 48 / 60 (тренер), bp e0 = 32/47/85/108, e3 = 5 (доля RAP %), e2 = 2 (макс. ястребов).
  Описание: `${$s1+($rap*($s4/100))}` → **Пике: `Dive = Base(rank) + 0.05*RAP`**, физический урон, мгновенно, дальность 35, КД 6 с общий с Arcane Shot (категория 1173).
- Ястреб (1293248, существо 264850) живёт 18 с, максимум 2. Масштабирование 1293586 «Hunter Guardian Hawk Pet Scaling 01» (auras 342, 79 school 127, 290).
- wowsims summon_hawk.go (по логам 30/48 ур., обновлён после хотфикса 10 ноября «+80% урона ястреба»):
  - `HawkAP = 0.8 * (RAP_owner + 7 + 14*RangedWeaponDPS)` — **ястреб получает силу атаки и от ДПС дальнобойного оружия**;
  - удар ястреба (ур. 48): `17…26.5 + 0.0417*HawkAP` за удар, скорость 2.5 с, ускоряется ранжевым хастом владельца (колчан, Quick Shots; Berserking — нет);
  - крит ястреба = 0.5 × (больший из мили/ренж крита хозяина) + Ferocity (10% на 5/5);
  - урон × Unleashed Fury × Focused Fire × множитель урона хозяина на момент призыва.
  Это подгонка по логам, не данные клиента.
- Стоимость: в DB2 80/105/135/190 маны; с 10–11 ноября 11% базовой маны (Blizzard хотфикс через wowhead news 383837 / wowfdb).

### 2.10 Ловушки
- Immolation Trap (13795…14305 → эффект 13797…14301): тик 21/43/68/102/138 каждые 3 с, 15 с → 105/215/340/510/690 — **как в Classic** (wowcalc).
  Новое: AP-скейлинг (Blizzard 15 окт.: «Fire traps now scale with attack power»). wowsims: 10% RAP на всю длительность (`0.10/5 = 0.02*RAP` за тик), TODO; forever-hunter вики: «2% RAP per tick — Verified».
  Формула: `ImmoTick = Tick(rank) + 0.02*RAP`.
- Explosive Trap (13813/14316/14317 → 13812/14314/14315): мгновенно bp 115/163/229, Variance 0.26/0.29/0.24, +0.8/1.0/1.2 за уровень (= Classic 104–134 / 145–193 / 208–264 на макс. уровне ранга) + 15/24/33 каждые 2 с 20 с (= 150/240/330, как Classic).
  wowsims: `ExplosiveHit = Roll + 0.10*RAP`, тики без AP. forever-hunter вики: коэффициент не проверен.
- Все ловушки: можно ставить в бою, КД 30 с (Era 15 с, только вне боя); с 3 ноября один общий КД (Blizzard), одна огненная + одна ледяная одновременно.
- Clever Traps (SV) +15/30% к урону огненных ловушек.

---

## 3. Ближний бой (Forever)

Нормализованные скорости для эффекта 121 (warcraft.wiki.gg Normalization; wowsims `newWeaponFromItem`): кинжал 1.7, прочее одноручное 2.4, двуручное 3.3, дальнобойное 2.8.
Требования к оружию (SpellEquippedItems Forever): Raptor Strike, Mongoose Bite, Counterattack, Wing Clip — нужен мили-оружие
(subclass 0,1,4,5,6,7,8,10,13,15,17); в Era Mongoose Bite и Counterattack требований не имели. Strider Kick — без требования (можно без оружия/в дизарме).
Все спецудары охотника бьют **только основной рукой (MH)**; офф-хенд даёт только белые удары.

### 3.1 Raptor Strike (2973, 14260–14266)
| Ранг | Ур. | Forever bp | Classic |
|---|---|---|---|
| 1 | 1 | 5 | 5 |
| 2 | 8 | 11 | 11 |
| 3 | 16 | 21 | 21 |
| 4 | 24 | 30 | 34 |
| 5 | 32 | 35 | 50 |
| 6 | 40 | 40 | 80 |
| 7 | 48 | 55 | 110 |
| 8 | 56 | 70 | 140 |
- e0 effect 58 (weapon damage, НЕ нормализован), «на следующий удар» (gcd 0, атрибут 0x4), КД 6 с. Мана R1 10 (Era 15).
- Формула: `RaptorStrike = W_MH + MAP/14*S_MH + Bonus(rank)` — заменяет белый удар MH (wowsims raptor_strike.go `MHWeaponDamage`; forever-hunter вики).
- Медленное MH-оружие выгоднее (AP-часть × реальная скорость).

### 3.2 Mongoose Bite (1495, 14269, 14270, 14271)
- Forever: e0 **effect 121** + bp 15/22/37/57 (ур. 16/30/44/58). Era: effect 2, плоский урон 25/45/75/115 (wowcalc). КД 5 с.
- Формула: `MongooseBite = W_MH + MAP/14*Norm(MH) + Bonus(rank)`, Norm = 1.7/2.4/3.3 (wowsims `MHNormalizedWeaponDamage`).
  forever-hunter вики пишет `MAP/14 × Weapon Speed` — противоречит типу эффекта 121 и wowsims; считаю нормализованной (средняя уверенность).
- Доступ: после уклонения или через Expose Prey (SV).

### 3.3 Counterattack (19306, 1242634, 20909, 20910) — талант SV 16
- Forever: 4 ранга (новый 1242634), e0 effect 121 bp 26/40/70/110, e1 effect 31 = 50%, корни 5 с; ур. 30/30/42/54; КД 5 с.
  Era: 3 ранга, плоские 40/70/110.
- Формула wowsims (`WeaponStrike`: процент масштабирует и плоскую часть): `Counterattack = 0.5*(W_MH + MAP/14*Norm(MH) + Bonus)`.
  Тултип «$s2% weapon damage plus $m1» можно прочитать и как `0.5*Weapon + Bonus` — не проверено в игре.

### 3.4 Strider Kick (1317257) — талант SV 21
- e0 effect 121 bp 0 + e1 effect 31 = 100%, +30% скорости бега 3 с, КД 8 с, 5.81% базовой маны.
- Формула: `StriderKick = W_MH + MAP/14*Norm(MH)` (wowsims talents_survival: «Effect 1 is normalised weapon damage with no bonus; effect 2 is the share of it, 100%»).

### 3.5 Wing Clip (2974/14267/14268)
- e1 effect 2 плоско 5/25/50, замедление 50/55/60% 10 с — **как в Classic** (wowcalc). Не зависит от оружия/AP.

### 3.6 Белые удары и офф-хенд
- `MH_swing = W_MH + MAP/14*S_MH`; `OH_swing = 0.5*(W_OH + MAP/14*S_OH)` (wowsims `OHWeaponDamage`; forever-hunter вики). Predator's Edge (SV, не взят) +10%/ранг урона OH (aura 122 bp 50 на 5/5).
- Lacerate (24118/24119/24120/1299332) есть в клиенте (кровотечение 7 тиков/21 с, bp 17/28/40/58 + за уровень), но у тренеров не найден (wowfdb «Still open»).

---

## 4. Баффы и ауры

| Способность | Forever (DB2) | Classic | Примечание |
|---|---|---|---|
| Aspect of the Hawk 13165/14318–14322/25296 | +20/35/50/70/90/110/120 RAP (aura 124), ур. 10/18/28/38/48/58/60 | те же | только RAP; e1 aura 42 → Quick Shots 6150 (шанс задаёт Deadly Aspects). Хотфикс 27.10 урезал до 15/22/30/38/47/55, 3.11 вернули. |
| Aspect of the Beast 13161/1299445/1299446/1299447 | +50/70/90/110 **мили AP** (aura 99), ур. 30/40/50/60, непрослеживаемость | только непрослеживаемость, 1 ранг | e2 aura 42 → Quick Strikes 1299448 |
| Aspect of the Monkey 13163 | +8% уклонения | 8% | |
| Aspect of the Wild 20043/20190 | +45/60 сопр. природе, рейд/пати (effect 65) | 45/60 | |
| Hunter's Mark 1130/14323/14324/14325 | +26/59/98/143 RAP **атакующим дальним боем** (aura 127), 2 мин, ур. 6/22/40/58 | 20/45/75/110 | = Classic × 1.3: Improved Hunter's Mark встроен (Blizzard Deep Dive «Improved Hunter's Mark… now baseline»). aura 127 — только дальние атаки, питомцу (мили) и ястребу не помогает. Ранги больше не стакаются (3.11). |
| Trueshot Aura 1299346/1299348/19506/20905/20906 | +20/35/50/75/100 **только RAP** (aura 124), вся рейд-группа, ур. 25/32/40/50/60 | 50/75/100 (ур. 40/50/60), AP мили+ренж, пати | Талант MM 21 — не у пользователя |
| Rapid Fire 3045 | +40% скорости **дальних и ближних** атак (aura 140 + aura 319), 15 с, КД 5 мин | только дальние 40% | Rapid Killing (MM) −1/−2 мин |
| Quick Shots 6150 | +30% ренж-скорость, **12 с** | 30%, 12 с | прок от Auto Shot при Aspect of the Hawk |
| Quick Strikes 1299448 | +30% мили-скорость, 12 с | — | прок от белых мили при Aspect of the Beast |
| Deadly Aspects 19552 | шанс 2%/ранг (кривая 82832/104809), 10% на 5/5 | Improved Aspect of the Hawk: «all normal ranged attacks» | aura 107 misc 18 (CHANCE_OF_SUCCESS) по маскам AotH/AotB |
| Колчаны 29413–29418 | +10…15% ренж-скорость (aura 557), только лук/арбалет | так же | |
| Подсумки 14824–14829 | +10…15% (aura 557), только огнестрел | так же | |
| Bestial Wrath 19574 | питомец +50% урона, 18 с, КД 2 мин, 12% баз. маны | так же | |
| Aspect of the Viper 415423, Aspect of the Falcon 469145, Kill Command 409379 | есть в DB2 и SkillLineAbility | строки идентичны Era/SoD | доступность в Forever **не подтверждена** (наследие SoD-данных); Steady Shot в Forever отсутствует как обучаемый спелл |

---

## 5. Таланты пользователя (BM 32 / MM 2), влияющие на формулы

- **Lethal Attacks 2/5**: +2% крита со всеми атаками (aura 290, кривая 1/ранг).
- **Focused Fire 2/2**: ×1.02 урон охотника и питомца при активном питомце (wowsims — мультипликативно; ястребы наследуют через множитель хозяина).
- **Deadly Aspects 5/5**: 10% шанс с Auto Shot (Aspect of the Hawk) → Quick Shots +30% на 12 с; с белых мили при AotB → +30% мили на 12 с.
- **Unleashed Fury 5/5**: **15%** урона питомцу и ястребам. Конфликт «кривая 15 / bp 20» решается в пользу кривой: Blizzard «Benefit to pet damage decreased slightly» (Classic 20% → 15%), forever-hunter вики «Rank 1 reduced from 4% to 3%»; wowsims берёт кривую.
- **Ferocity 5/5**: **10%** крита питомцу и ястребам. Кривая подтверждена логами wowsims: «a hawk with Ferocity 5/5 read 10 plus half its owner's crit»; Blizzard «critical strike bonuses to pets decreased».
- Маски: Unleashed Fury/Ferocity (aura 107 misc 3) бьют по Tamed Pet Passive 8875/19591 и по Summon Hawk (mask2 0x2000).
- Не взяты, но меняют формулы: Barrage (+5/10/15% Aimed/Multi/Volley), Ranged Weapon Specialization (+1%/ранг ренж-урон), Mortal Shots (+6%/ранг к крит-бонусу ренж-способностей, в т.ч. Auto Shot), Careful Aim (AP/RAP += 20%/ранг Интеллекта), Lone Wolf (+20% без питомца), Improved Stings (+20% Serpent Sting), Improved Arcane Shot (−0.3 с/ранг КД), Savage Strikes (+2/4% крит мили-способностей), Predator's Edge, Clever Traps.

---

## 6. Что каждый стат даёт каждой способности (производная по стату)

| Способность | +1 RAP даёт урона | ДПС дальнобойного оружия | Патроны | Скорость оружия | Мили-оружие / MAP |
|---|---|---|---|---|---|
| Auto Shot | S/14 за выстрел (= 1/14 ДПС до хаста) | полностью | AmmoDPS×S | реальная | — |
| Aimed / Multi / Sniper | 2.8/14 = 0.2 | +W = ДПС×S за выстрел (медленный лук → больше) | AmmoDPS×S | только для W и патронов | — |
| Scatter Shot | 0.5×S/14 | 50% | 50% | реальная | — |
| Arcane Shot | 0.15 | нет | нет | нет | — |
| Serpent Sting | 0.25 за 15 с (0.05/тик) | нет | нет | нет | — |
| Volley | 0.03 за волну на цель (×6) | нет | нет | нет | — |
| Summon Hawk (пике) | 0.05 | нет | нет | нет | — |
| Ястреб (каждый) | 0.8×0.0417 = 0.0334 за удар (≈0.0133 ДПС до модификаторов) | +14×0.8 = 11.2 AP ястреба за 1 ДПС лука (wowsims) | нет | нет | — |
| Immolation / Explosive Trap | 0.10 итого / 0.10 в первый удар | нет | нет | нет | — |
| Raptor Strike | — | — | — | — | W_MH + MAP×S_MH/14 + бонус |
| Mongoose / Counterattack / Strider | — | — | — | — | W_MH + MAP×Norm/14 (1.7/2.4/3.3) |

Пример (только арифметика): W=56, S=2.8, AmmoDPS=13, RAP 600 + Hunter's Mark 98 = 698:
Auto Shot 232; Aimed Shot R3 347 (+9?); Multi-Shot 232 на цель; Arcane Shot R5 224.7; Serpent Sting R6 464.5 за 15 с; пике ястреба R2 81.9; волна Volley R1 90.9.

---

## 7. Итоговый список изменений Forever vs Classic Era (подтверждено диффом DB2 + источниками)

1. Aimed Shot — базовый с 20 ур., каст 3.0→2.0 с, бонусы 40/70/115/185/260/350 (Classic 70…600), КД 6 с общий с Multi-Shot.
2. Multi-Shot — 1 ранг без бонуса, КД 10→6 с (общий с Aimed), 13.9% баз. маны, 0.5 с каст.
3. Arcane Shot — база ×~1.5 к Classic, SP-коэффициент убран, +0.15 RAP (серверно), КД больше не общий с Aimed (общий с Summon Hawk).
   Проверено по SpellCategories: Era — Arcane Shot и Aimed Shot в категории 2 (6 с), Multi-Shot в категории 85 (10 с);
   Forever — Aimed Shot + Multi-Shot в категории 2 (6 с), Arcane Shot + Summon Hawk в категории 1173 (6 с).
4. Serpent Sting — база выше на высоких рангах (R9 675 vs 555), SP убран, +5% RAP за тик, тики критуют.
5. Volley — КД 60 с убран, урон 70/91/112 (Classic 50/65/80), +3% RAP за волну (wowsims), канал-реализация через areatrigger.
6. Raptor Strike — бонусы с R4 сильно урезаны (R8 70 vs 140), механика та же (next swing, реальная скорость).
7. Mongoose Bite — теперь урон оружия (нормализованный) + 15/22/37/57 вместо плоских 25…115; требует мили-оружие.
8. Counterattack — 50% урона оружия + 26/40/70/110, 4 ранга, талант 16-го ряда.
9. Новые: Summon Hawk (4 ранга), Sniper Shot (3 ранга), Strider Kick, Lacerate (в клиенте), Trueshot Aura ранги 1–2.
10. Aspect of the Beast — +50…110 мили AP, 4 ранга; Rapid Fire ускоряет и мили; Hunter's Mark ×1.3 (встроенный Improved HM); Trueshot Aura — только RAP, рейд.
11. Ловушки: те же базовые числа, но в бою, КД 30 с, огненные скейлятся от AP.
12. Wing Clip, Aspect of the Hawk (после 3.11), Aspect of the Monkey/Wild, Quick Shots (30%/12 с), колчаны — как в Classic.

## 8. Открытые вопросы
- +9 к нормализованным Aimed/Multi (wowsims TODO) — плоская константа или от RAP?
- Mongoose Bite: нормализованная скорость (эффект 121, wowsims) vs реальная (forever-hunter вики).
- Counterattack: 50% масштабирует плоский бонус или нет.
- Volley 3% RAP и Explosive Trap 10% RAP — не подтверждены независимым источником, только wowsims.
- Ловушки: RAP или мили AP? wowsims использует RAP; Blizzard пишет просто «attack power».
- Hunter's Mark (aura 127) в коэффициентах Arcane/Serpent/Hawk dive: wowsims считает RAP против цели (включая метку) — в игре не проверено мной.
- Доступность Aspect of the Viper / Aspect of the Falcon / Kill Command / Lacerate в Forever.
- Стоимость Arcane Shot/Summon Hawk (11% базовой маны) — серверный хотфикс, в DB2 70888 не отражён.
