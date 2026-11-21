# Хант WoW Forever (Orc, BM): таланты и пререйд гир, итоговая сводка

Все данные взяты из отчётов верификаторов этого прогона. Источник каждого утверждения указан в их файлах (папки scratchpad перечислены в конце). Новых фактов в сводке нет, только сведение и арифметика. Всё, что я посчитал сам, помечено «(мой расчёт)».

---

## 1. Таланты

### Рекомендация: BM 31/20/0 (пет, дальний бой)
Билд совпадает с пресетом BM из wowsims/forever. Его проверил валидатор по DB2 клиента 1.60.1.70888: 51 очко, все гейты рядов и пререквизиты в порядке.

**Почему этот билд:**
- В симе Brokenmeta (1.60.1.70753) BM занимает 1-е место с 1370 DPS. MM Lone Wolf на 2-м месте с 1313 DPS.
- Тот же каркас 31/20 у ConquestCapped (raid) и у Icy Veins PvE.
- Орочий Command даёт +5% к урону пета.

| Ветка | Талант (ru / en) | Ранг |
|---|---|---|
| ЗМ | Смертоносные духи / Deadly Aspects | 5 |
| ЗМ | Тренировка стойкости / Endurance Training | 3 |
| ЗМ | Направленный огонь / Focused Fire | 2 |
| ЗМ | Звериная стремительность / Bestial Swiftness | 1 |
| ЗМ | Неудержимое неистовство / Unleashed Fury | 5 |
| ЗМ | Свирепость / Ferocity | 5 |
| ЗМ | Призыв ястреба / Summon Hawk | 1 |
| ЗМ | Устрашение / Intimidation | 1 |
| ЗМ | Беспрекословное послушание / Bestial Discipline | 2 |
| ЗМ | Бешенство / Frenzy | 5 |
| ЗМ | Звериный гнев / Bestial Wrath | 1 |
| Стрельба | Смертоносные атаки / Lethal Attacks | 5 |
| Стрельба | Смертельные укусы / Improved Stings | 3 |
| Стрельба | Верная цель / Careful Aim | 5 |
| Стрельба | Улучшенный чародейский выстрел / Improved Arcane Shot | 2 |
| Стрельба | Аура меткого выстрела / Trueshot Aura | 1 |
| Стрельба | Смертоносные выстрелы / Mortal Shots | 4 |

**Порядок вложения от текущего билда без респека.** Текущие ранги взяты со скриншота 2026-11-12 (43 ур.): DA5, ET1, FF2, Improved Revive Pet 2, Pathfinding 2, BS1, UF5, Fer5, SH1, Int1, BD2, Frenzy4, BW1 / LA2 = 34 очка. В Forever даётся 1 очко за уровень с 10 по 60, поэтому на 54 уровне очков 45, а на 60 — 51. Значит, на 54 у тебя ~11 очков сверх скриншота. Я не проверял, свободны они или уже вложены.
- 35: Frenzy 5/5
- 36–38: Lethal Attacks 3→5
- 39–43: Careful Aim 1→5
- 44–45: Improved Stings 1→2 (всё до этого места доступно на 54)
- 55: Improved Stings 3
- 56–57: Improved Arcane Shot 1→2 (в MM набирается 15 очков, открывается ряд 4)
- 58: Trueshot Aura
- 59–60: Mortal Shots 1→2. После этого получается 33/18/0.

**Респек на 60.** Снять Pathfinding 2 и Improved Revive Pet 2, вложить Endurance Training +2 (до 3/5) и Mortal Shots +2 (до 4/5). Итог 31/20/0. До 60 эти 4 очка можно оставить ради скорости в аспекте гепарда.

**Флекс-варианты:**
- Improved Arcane Shot 2 можно заменить на Rapid Killing 2, как у ConquestCapped. CC утверждает, что IAS не сокращает общий КД с Summon Hawk. Я это не проверял, а wowsims всё равно берёт IAS 2.
- Для данжей, где пет часто умирает: ET 5 вместо части Mortal Shots (вариант CC).

### Альтернатива: MM Lone Wolf 5/41/5 (пресет wowsims MM, без пета)
- ЗМ: Смертоносные духи / Deadly Aspects 5.
- Стрельба: Lethal Attacks 5, Improved Stings 3, Efficiency 4, Careful Aim 5, Rapid Killing 2, Improved Arcane Shot 5, Lone Wolf 1, Trueshot Aura 1, Mortal Shots 5, Rapid Recuperation 2, Barrage 2, Ranged Weapon Specialization 5, Sniper Shot 1. По-русски: Смертоносные атаки, Смертельные укусы, Эффективность, Верная цель, Быстрые убийства, Улучшенный чародейский выстрел, Одинокий волк, Аура меткого выстрела, Смертоносные выстрелы, Быстрая концентрация, Заградительный огонь, Специализация на оружии дальнего боя, Снайперский выстрел.
- Выживание: Мастерское выслеживание / Improved Tracking 5.
- Минусы: нужен полный респек, нет пета (хуже для соло на PvP-сервере), пропадает бонус Command. По Brokenmeta билд примерно на 4% ниже BM.
- Brokenmeta считает Sniper Shot на 4.5% хуже, чем Barrage 3/3. Это расходится с пресетом wowsims.

SV-билды с вивингом и мили (SV Weave, SV Melee, Brokenmeta SV) валидны, но тебе не подходят: они рассчитаны на мили.

---

## 2. Пререйд гир (Horde, только то, что можно добыть сейчас) — пересборка 2026-11-16

### Откуда данные
- **Статы:** wowsims/forever `assets/database/db.json`, коммит `6084403` (16.11.2026): обычные статы + массив `pseudoStats` (проценты хита/крита). Ограничения по классу — `classAllowlist`, фракция — `factionRestriction`.
- **Вторая сверка каждой вещи** (независимо от wowsims): foreverdb.net, legacyofwarcraft.com (Blizzard Game Data API), foreverchanges.pro, conquestcapped, icy-veins db. Статы всех вещей ниже совпали.
- **Веса:** EP-пресет Turret из wowsims (`ui/specs/hunter/dps/presets.ts`), измерен симом на пререйд-наборе в хит-капе: Agi 1, хит 1.14 за рейтинг, крит 0.84, Int 0.42 (Careful Aim), RAP 0.34, DPS лука 2.87.
- **Хит-кап:** 8% (рейд-босс +3). Хит сверх 8% считается за 0. Набор собран перебором целиком, а не по слотам.
- **Бонусы сетов:** клиентские DB2 ItemSet / ItemSetSpell / SpellEffect, билд 1.60.1.70888 (Devilsaur 2 шт. = +2% хита).
- **Доступность сейчас (до рейдов 9 декабря):**
  - выкинуты рейды (MC, Ony, BWL, ZG, AQ, Naxx), квест с головой Ониксии, репутация The Watchers, PvP-ранги, Alliance-only;
  - выкинуты вещи не для ханта (Assassin's Waistguard и Darkmantle — только Rogue, Gloves of Spell Mastery — кастеры);
  - выкинут BoP-крафт чужих профессий: Legionite Glaive — только кузнец (у тебя кожевничество);
  - крафт берётся, если выкройка или вещь были на твоём аукционе (скан CAMWOW EU4 PvP-Horde 15.11 в `tools/preraid/data/ah.tsv`; новый `ah.tsv` пишет `tools/preraid/ah.lua` из базы цен Auctionator) или известен источник выкройки; выкройка крафта и чему она учит — DB2 клиента (ItemEffect, ItemXItemEffect, билд 1.60.1.70888), её источник — db.json, где он есть, и foreverdb.net;
  - выкинут крафт, у выкройки которого источник неизвестен, если ни выкройку, ни вещь не видели на аукционе. Источник выкройки стенд берёт со страницы foreverdb.net (страницы сохранены 2026-11-21, `tools/preraid/gen_pattern_sources.py` → `tools/preraid/data/pattern_sources.tsv`). Так выкинуты три крафта с реагентом Malleable Essence of Nature (DB2 SpellReagents): Hyper Deluxe Sniper Rifle Mk XVII, Outlaw's Collar и Mourning Handguards. Про их выкройки 279322, 279302 и 279306 foreverdb.net пишет «where it comes from isn't known yet»;
  - вещи с неизвестным источником, которых не было на аукционе, выкинуты.
- Готовый пререйд-набор wowsims для стрелка (`prebis_turret.gear.siml`) почти совпадает с вариантом Б; расходится там, где у них ханту недоступные вещи (их Legionite Glaive — BoP кузнеца).

### Вариант А — с Exalted на полях боя (Darkspear Islands, Warsong, Frostwolf)
Хит 7.7%. Названия фракций и полей боя — из клиента ruRU (Faction, AreaTable). Четыре вещи за репутацию, все на «Превознесение» (42 000 от «Равнодушия»); как её набрать — таблица ниже (проверено 2026-11-17).

| Вещь | Фракция, поле боя | DPS вещи* | Как качается | Оценка |
|---|---|---|---|---|
| Darkspear Pauldrons / Epaulets (плечи) | Налетчики Черного Копья, Острова Черного Копья (15×15, 30–60) | +5.6 | Квест за победу +200; сдача 3 марок +150 (по conquestcapped повторно +100); марки: победа 3, поражение 1; в клиенте есть +10 за действие в матче, триггер неизвестен | ~120–420 побед |
| Raider Gloves (перчатки) | Налетчики Черного Копья | вместе с поножами +5.4 | та же репутация, что плечи | — |
| Outrider's Chain Leggings (поножи) | Всадники Песни Войны, Ущелье Песни Войны (10×10, с 10 ур.) | вместе с перчатками +5.4 | Рейты Forever не опубликованы; Classic: +35 за флаг всей команде, сдача 3 марок +50 (или +100); в клиенте спелл «+42 за победу», триггер неизвестен | ~170–400 побед 3:0 (≈270) |
| Don Julio's Band (кольцо) | Клан Северного Волка, Альтеракская долина (40×40, 51–60) | +2.8 | Classic: генерал ~300–389, лейтенанты по 125, бункеры/башни/кладбища по 12–24, сдача 3 марок +100; разовые квесты ~2 500 | ~40–100 побед (~100–120 игр при 50%) |

\* DPS — насколько набор А хуже, если вещь заменить вариантом без репутации (новая модель аддона, рейд-босс): плечи → Stratholme Militia; перчатки + поножи → пара Devilsaur (только парой: одни поножи без перчаток Devilsaur дают −11.7, теряется бонус сета); кольцо → Tarnished Elven Ring.

- Ранг «Превознесение»: Налетчики Черного Копья — данные клиента Forever (wowreputations). Всадники Песни Войны — подсказка Wowhead Forever, но в клиенте у вещи требования нет. Клан Северного Волка — только Classic; в клиенте Forever требования нет. Если окажется «Почтение» — нужно 21 000, вдвое меньше.
- Перк Diplomat: +2% репутации за ранг, до +10%. Квест на марки всех полей боя (For Great Honor, у боевого вестника в Оргриммаре) даёт репутацию сразу Всадникам Песни Войны и Клану Северного Волка.
- «Clear the Forest!» (+1 000 Всадникам Песни Войны, ежедневный) есть в данных клиента, но по Warcraft Wiki — только Season of Discovery; не рассчитывать.
- Источники: wowhead.com/forever (faction=2798, tooltip 22673 dataEnv=16), wowreputations.com/forever (darkspear-raiders, warsong-outriders, frostwolf-clan), conquestcapped (Darkspear Islands, Warsong Gulch), forever-codex.com/reputations/frostwolf-clan, foreverdb.net/reputation/warsong-outriders, worstguidesever (Classic-значения), форум Blizzard EU 14.11 (очереди AV).

| Слот | Предмет | Статы (Forever) | Где брать |
|---|---|---|---|
| Голова | Black Dragonscale Helm 252605 (кольчуга, BoE) | +21 Agi, +38 Int, +1% крита | Кожевничество 300. На твоём АХ: шлем 290.50g, выкройка 252939 53g |
| Шея | Mark of Fordring 15411 | +26 AP, +1% крита | Квест 5944 «In Dreams» (цепочка Тирион/Таэлан, WPL→EPL, шаг в Стратхольме) |
| Плечи | Darkspear Pauldrons 272105 (кожа) / Darkspear Epaulets 272106 (кольчуга) | +27 Agi, +12 Sta, +1% крита | Creeg Bothunk, Барренс 65.0,34.6, Darkspear Raiders Exalted, ~16g |
| Плащ | Cape of the Black Baron 13340 | +15 Agi, +20 AP | Барон Ривендер, Стратхольм |
| Грудь | Dawn Armor 252483 (кожа, BoE) | +37 Agi, +1% хита, +1% крита | Кожевничество 300. На твоём АХ: 300g, выкройка 252892 1176g |
| Запястья | Marksman Bands 18296 (кольчуга, BoE) | +12 Agi, +8 Sta, +1% хита | Трэш Dire Maul; на твоём АХ 49g |
| Руки | Raider Gloves 272099 (кожа) | +27 Agi, +11 Str, +15 Sta | Creeg Bothunk, Darkspear Raiders Exalted |
| Пояс | Marksman's Girdle 22232 | +21 Agi, +1% хита | Urok Doomhowl, LBRS |
| Ноги | Outrider's Chain Leggings 22673 | +35 Agi, +15 Sta, +1% хита, +1% крита | Kelm Hargunth, Mor'shan (Барренс 46.6,8.4), Warsong Outriders, ~25g |
| Ступни | Windreaver Greaves 13967 | +20 Agi, +4 Int, +1% хита | Kirtonos the Herald, Scholomance |
| Кольцо 1 | Don Julio's Band 19325 | +14 AP, +10 Sta, +1% хита, +1% крита | Frostwolf Supply Officer (Jekyll Flandring, Альтерак 62.8,59.3 / Grunnda Wolfheart в AV), ~75g |
| Кольцо 2 | Cutthroat's Signet 272408 | +14 Agi, +8 Sta, +1% хита | Pix Xizzix, Booty Bay 28.4,75.8, 75 Tarnished Undermine Real (раз в день с боссов данжей 55+) |
| Тринкет 1 | Blackhand's Breadth 13965 | +1% крита; on-use +5% крита по цели 20 с / 5 мин (x2 против орков и огров) | Квест 4974 «For The Horde!» (голова Ренда, UBRS) |
| Тринкет 2 | Rune of the Guard Captain 19120 | +14 AP (x3 в лесах и лугах), +7 рейтинга хита = 0.7% | Квест 7862, доска в Revantusk Village (Хинтерленд 79.1,79.0) |
| Оружие | Peacemaker 18725 (древковое, носитель статов) | +56 AP, +1% крита | Мировой судья Бартилас, Стратхольм. Заменил Bear Poking Stick 274419 (2026-11-17): тот требует Barkskin Burrow Revered, ~1030 Deadwood Tribal Beads (~2000 убийств), а по модели аддона лучше всего на 0.35 DPS |
| Дальний бой | Eaglehorn Long Bow 13023 (BoE) | 32.2 DPS @1.8, +10 Agi, +4 Sta | Мировой дроп; на твоём АХ 85.41g |

### Вариант Б — без репутации полей боя и без Норы Древокожих
Хит 8.0%. Таблица ниже — набор до модели рейдового режима; **окно `/hga preraid` с 2026-11-18 показывает вариант Б по новой модели** (раздел «Пересчёт по модели рейдового режима» ниже). Перепроверен стендом с фильтром «без репутации полей боя и Норы Древокожих»: лучший, выигрыш стенда только от условности «сила атаки против типа существ» и неучтённого использования Blackhand's Breadth.

| Слот | Предмет | Статы (Forever) | Где брать |
|---|---|---|---|
| Голова | Black Dragonscale Helm 252605 | как в А | как в А |
| Шея | Mark of Fordring 15411 | как в А | как в А |
| Плечи | Stratholme Militia Shoulderguard 18742 (кольчуга, BoE) | +22 Agi, +6 Int, +9 Sta | Трэш Стратхольма (очень редко); на твоём АХ не видели, на других Horde-серверах 38–50g |
| Плащ | Cape of the Black Baron 13340 | как в А | как в А |
| Грудь | Dawn Armor 252483 | как в А | как в А |
| Запястья | Marksman Bands 18296 | как в А | как в А |
| Руки | Devilsaur Gauntlets 15063 (кожа, BoE) | +28 AP, +9 Sta, +1% крита; сет 2 шт. +2% хита | Кожевничество 265 и специализация «Кожевничество: традиции предков» (DB2 клиента: ItemSparse выкройки 15758, RequiredAbility 10660); выкройка у торговца Nergal, Кратер Ун'Горо, 2з 20с (foreverdb.net). На твоём АХ 13.77g |
| Пояс | Marksman's Girdle 22232 | как в А | как в А |
| Ноги | Devilsaur Leggings 15062 (кожа, BoE) | +46 AP, +12 Sta, +1% крита; сет | Кожевничество 290 и специализация «Кожевничество: традиции предков» (DB2 клиента: ItemSparse выкройки 15772, RequiredAbility 10660); выкройка падает со слизней Glutinous, Primal, Cloned и Muculent Ooze, 0.9–1.1% (foreverdb.net, данные Classic). На твоём АХ 54g |
| Ступни | Windreaver Greaves 13967 | как в А | как в А |
| Кольцо 1 | Cutthroat's Signet 272408 | как в А | как в А |
| Кольцо 2 | Tarnished Elven Ring 18500 | +10 Agi, +1% хита, +10 к сопр. тайной магии | DM North, Gordok Tribute |
| Тринкет 1 | Blackhand's Breadth 13965 | как в А | как в А |
| Тринкет 2 | Behemoth Bones 280065 | +34 AP; on-use хил себя и союзника, 5 мин | Blackmaw Behemoth, Blackmaw Hold (новый данж 55–60, Азшара) |
| Оружие | Peacemaker 18725 | как в А | как в А |
| Дальний бой | Eaglehorn Long Bow 13023 | как в А | как в А |

Перебор для обоих вариантов: `tools/preraid/opt.py` (кандидаты и фильтры) и `tools/preraid/solve.py` (DP по слотам с хитом как состоянием, бонусы сетов перебором слотов).

### Пересчёт по модели рейдового режима (2026-11-18)
Стенд `tools/preraid/rescore` на модели рейдового режима (босс +3, бой 180 с с откатами, маной, зельями, дебаффами босса;
`docs/superpowers/specs/raid-mode-design.md`), критерий D = модельный DPS всего набора. Старые A и Б с данными окна сохранены в
`docs/research/preraid-bis-60-before-raid-mode.md`.

- **Вариант Б (показывает окно):** 716.6 → 722.5 DPS (+5.9), хит 7.5%. Плечи Bone Golem Shoulders 18686 (Некроситет, Громоклин)
  вместо 18742; запястья Beastmaster's Bindings 226885 (Моквар, Оргриммар, 25з по Wowhead Forever) вместо Marksman Bands 18296;
  пояс Ranger's Belt 272397 (Пикс, 100 реалов) вместо Marksman's Girdle 22232; палец Ring of Demonic Guile 18314 (Забытый
  Город, Алззин) вместо Tarnished Elven Ring 18500; двуручное Flameslash Crescent 280056 (Крепость Черночревов, Бесаан
  Бесноватый) вместо Peacemaker 18725. Выигрыш только у набора целиком: по одной вещи Flameslash Crescent даёт −7.5 DPS, Beastmaster's
  Bindings −1.0.
- **Вариант А:** 733.4 → 741.1 DPS (+7.7). Шея Star of Mystaria 12103 (Стратхольм, Балназар) вместо Mark of Fordring 15411; кисти
  Gordok's Gloves 18368 (квест «Unfinished Gordok Business») вместо Raider Gloves 272099; пояс Ranger's Belt 272397 вместо
  Marksman's Girdle 22232; двуручное Ironbark Staff 20220 (Осквернители, Превознесение) вместо Peacemaker 18725.
- Не проверено в игре; цена Beastmaster's Bindings и нужен ли для покупки квест 84156 — только по Wowhead Forever.

---

## 3. Хит-кап, приоритет статов, зачарки, расходники

**Хит-кап:**
- 6% против мобов на +2 уровня (5-ман), 8% против рейдового босса. Wowhead для запаса берёт 9%.
- Хит дальнего боя нельзя увернуть или спарировать. Expertise полезна только пету.
- Практичный набор выше даёт примерно 10–12% хита (мой расчёт: Mask 2, Truestrike 1.5, Dawn 1, Slashclaw 1, Devilsaur 2, Marksman 1, Windreaver 1, Don Julio 1, Cutthroat 1, Rune 0.7, винтовка 0.5). Это выше капа.
- Когда кап закрыт, меняй хит-вещи на варианты без хита: Mark вместо Beads, Cape вместо Howler's, Eclipse вместо Slashclaw, Ranger's Belt вместо Marksman's, Darkspear вместо Truestrike.
- ConquestCapped набирает 9.1% хита одной экипировкой.

**Приоритет статов** (EP-пресет wowsims для турели, в единицах Agi): DPS оружия дальнего боя 2.87 > хит (до капа) 1.14 > Agi 1.00 > крит 0.84 > скорость 0.80 > Int 0.42 > RAP 0.34. ConquestCapped даёт тот же порядок: DPS оружия > хит до 8% > Agi > крит > Int > AP.

**Зачарки:**
- Голова и ноги: Lesser Arcanum of Voracity 11647, +8 Agi (квест 4484, Libram of Voracity).
- Шея: Enchant Necklace — Agility 249504, +5 Agi. Новинка Forever, вендор Beneris в Barrens.
- Плащ: Enchant Cloak — Agility 273604, +5 Agi, у того же Beneris.
- Грудь: Greater Stats, +4 ко всем статам.
- Запястья: Superior Agility +9, эффект 7656. Формула падает с Thuzadin Acolyte в Strat (5.9%).
- Руки: Greater Agility +10. Формула 16219 стоит 6.20g на AH. Superior Agility +15 отклонена: формула только из AQ, ZG и мировых боссов.
- Ступни: Greater Agility +7. Формула 16245 стоит 4.50g на AH.
- Прицел: SAF-T Ultra Precision Scope (+2% крита, 279272) у sim. Источник схемы не подтверждён. ConquestCapped советует Sniper Scope (+7 урона), запасной вариант — Deadly Scope. Biznicks (+3% хита) требует MC, это рейд.

**Расходники** (сим wowsims и гайды):
- Elixir of the Mongoose 13452. По Brokenmeta Elixir of the Honey Badger сильнее Mongoose.
- Major Frenzy Potion 250943: +80 AP, пить под Bestial Wrath.
- Major Mana Potion 13444 и Demonic Rune 12662 или Dark Rune. Мана — главное ограничение BM, а Aspect of the Viper нет.
- Greater Mageblood Elixir 250341.
- Еда: Swiftstrike Steak 250072 (сим) или Grilled Squid (+1% крита в Forever, по ConquestCapped).
- Juju Might 12460, Ground Scorpok Assay 8412.
- Flask of Natural Aggression 274274 есть в симе. Доступна ли она до рейда, не проверено.


---

## 4. Что не проверено

1. Требование Exalted у Warsong Outriders (Outrider's Chain Leggings) и Frostwolf (Don Julio's Band) в клиенте Forever не записано (Warsong — только подсказка Wowhead Forever, Frostwolf — Classic); в игре не подтверждено. Рейты репутации полей боя Forever не опубликованы.
2. Источник выкройки Dawn Armor не известен ни одному сайту (foreverdb.net 2026-11-21: «New in Forever: where it comes from isn't known yet»); доступность — только по твоему скану аукциона 15.11 (броня 300g, выкройка 1176g).
3. Источник выкройки Black Dragonscale Helm не найден (foreverdb.net 2026-11-21: «New in Forever: where it comes from isn't known yet»); выкройка есть на твоём АХ (53g).
4. Шансы дропа (Kirtonos, Rivendare, трэш Strat/DM) — данные Classic.
5. Rune of the Guard Captain: «+7 Hit» = 0.7% по конверсии 10 рейтинга = 1%; страницы сами в проценты не переводят.
6. EP-веса wowsims намерены для MM-билда (Turret), не для BM 31/20; порядок статов тот же, абсолютные числа для BM могут отличаться.
7. Ничего из этого не проверено в игре.
