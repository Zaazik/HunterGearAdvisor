# Pre-raid re-score (стенд)

Проверяет пререйд-набор из `docs/research/preraid-bis-60.md` (варианты А и Б; А — это `Game/PreRaidData.lua`)
расчётом плюсов самого аддона (Core/Model.lua + Core/Score.lua) в рейд-режиме: персонаж 60-го уровня против рейдового
босса +3, как аддон считает на 60-м уровне (`docs/superpowers/specs/raid-mode-design.md`, раздел 14.6). Гонять после
любой правки модели / весов / SetData / UseData / StatMultData, и после обновления данных (новый скан аукциона, новая
база wowsims).

## Запуск — одна команда

```bash
cd /c/Users/Admin/WowProjects/HunterGearAdvisor && bash tools/preraid/rescore/run.sh
```

- Модель берётся из этого репозитория (`../../..`). Другой checkout: `HGA_ADDON=<путь> bash tools/preraid/rescore/run.sh`
  (пока новый расчёт не влит в main — `HGA_ADDON=/c/Users/Admin/WowProjects/HunterGearAdvisor-wowsims`).
- `out/cands_all.json` и `out/items.lua` пересобираются только если что-то в `../data` или `avail.py`/`convert.py` новее.
- Две оценки параллельно, ~30 мин (прогон 2026-11-18): `out/out.txt` и `out/out_nocreature.txt` (+AP против типа
  существ = 0). В рейд-режиме они совпадают: цель — дракон, а `convert.py` не называет тип у «+AP против типа существ»
  (`AP_CREATURE`), поэтому такая сила атаки и так считается 0 (`UNTYPED_SHARE` в `rescore.lua`). Результат прогона
  2026-11-16 (ещё модель прокачки, цели +3 / +2 / +0) сохранён в `out/out_*2026-11-16.txt`.

## Что внутри

| Файл | Что делает |
|---|---|
| `avail.py` | Кандидаты: те же правила доступности, что `../opt.py` (Horde, без рейдов/ПвП/Watchers/квеста Ониксии, BoP-крафт только своих профессий; выкройка крафта — из DB2 клиента, её источник — из db.json, если он там есть, иначе со страницы выкройки на foreverdb.net; крафт, у выкроек которого источник неизвестен, выкинут, если ни выкройку, ни вещь не видели на АХ), но без фильтра по старым EP. → `out/cands_all.json` (~3400 вещей, 106 тринкетов) |
| `convert.py` | Вещи wowsims db.json → формат вещи аддона (заголовок Core/Score.lua): HIT/CRIT в %, AP/RAP, AP_CREATURE, RHIT (хит только дальнего боя), скорость/DPS оружия. → `out/items.lua` |
| `rescore.lua` | D(set) = Model.Total модели в рейд-режиме, собранной из всего набора: бой 180 с с окнами Rapid Fire, Bestial Wrath, Use-баффов набора (`p.uses`, порядок `Score.SetUses`) и расходников, с маной; хит Use-баффа — по его доле боя (`Model.UseUptimes`). Это решает. Параллельно Score.SetValue при W = Model.Weights(p) и ctx как в Advisor A.State (`ctx.useGain`, `ctx.useUptime`, правило частоты проков U4), итерация до неподвижной точки (то, что покажет аддон). Поиск: покоординатный подъём по всем кандидатам всех слотов, рестарты (текущие А/Б, неподвижные точки, все сеты с бонусом урона), затем парные замены топ-40. Цель одна — босс +3 (кап 8%): прогоны +2 и +0 были значениями `/hga target`, которой больше нет. |

Персонаж (точка модели, `pointFor`): Орк 60, BM 31/20/0 из дока (ключи Player.BRANCHES), `mode = "raid"`, цель +3;
база wowsims base_stats.go (Agi 122, Str 58, Int 62, MAP 100, RAP 110), пет Raptor 1.6 с, Command, Aspect of the Hawk +
Trueshot Aura, Thorium Headed Arrow 17.5 DPS, Quickdraw Quiver 13%, лук 300 скилла, ближнего боя нет (не ветка
Выживания). Новые входы модели: мана — пул 1720 + 20 + 15 × (Int − 20) + MANA гира (wowsims mana.go:59-71), Дух 73
(охотник 70 + орк 3) + гир, реген 6.25 + Дух / 8 в секунду вне правила 5 секунд и 25% за ранг Bestial Discipline внутри,
плюс MP5 / 5 (mana.go:77-78, 166-169); спелл-крит 3.6% + 0.0165% за Инт, спелл-хит 0; пробивание брони гира против брони
босса 976; хит только дальнего боя (RHIT) отдельно от общего; множители статов листа 1 (баффов на точке нет). Баффов,
зачарок нет; расходники боя — как в аддоне, всегда (Major Frenzy Potion, Major Mana Potion или второй Frenzy, Demonic
Rune).

Данные: `../data/` (не в git; откуда — `../data/SOURCES.txt`): `db.json` (wowsims/forever 6084403), `db2/*.csv`
(клиент 1.60.1.70888 с wago.tools), `ah.tsv` (цены аукциона, `../ah.lua` из сохранённой базы Auctionator), `cands.json` (старый пул: вывод `../opt.py`), `exalted.txt`
(Exalted-вещи — вариант Б их исключает), `pattern_sources.tsv` (источники выкроек по foreverdb.net, `../gen_pattern_sources.py` из сохранённых страниц `fdb/<id>.html`). Выкройки: `db2/ItemEffect.csv` (строки с TriggerType 6 — заклинание, которому учит предмет) и `db2/ItemXItemEffect.csv` (предмет этой строки), клиент 1.60.1.70888 с wago.tools. Где выкройка падает или продаётся — её источники в `db.json`, а db.json (wowsims 6084403) выкроек не содержит, поэтому источник берётся из списка «Where to get it» её страницы на foreverdb.net. Крафт, у выкроек которого источник неизвестен (foreverdb.net пишет «isn't known yet» / «Not known yet» или страницы нет), выкинут с пометкой `craft: recipe N source unknown (db.json, foreverdb.net), neither recipe nor item ever seen on AH`, если ни выкройку, ни вещь не видели на АХ. Выкройка, которой нет в `pattern_sources.tsv`, — ошибка со списком id: сохрани их страницы и перезапусти генератор. С данными 2026-11-21 так выкинуты Hyper Deluxe Sniper Rifle Mk XVII 279273, Outlaw's Collar 279253 и Mourning Handguards 279257; кандидатов 3408 (в прогоне 2026-11-16 было 3456; ни одна из 48 вещей разницы не входит в варианты А и Б). Также читает с диска игры ForeverGuide NewDungeonData.lua.

## Не моделируется

Урон от проков (191 вещь в пуле: стенд берёт вещи из базы wowsims и не разбирает их тексты, `item.procs` пустые; аддон
проки считает, с DoT-проками), Use без записи в UseData (Blackhand's Breadth +5% крита ~1.5 DPS, Behemoth Bones,
Counterattack Lodestone), зональные статы (Rune of the Guard Captain в лесах), зачарки, баффы.
Строки «Повышает вероятность попадания в дальнем бою на X%» (Marksman Bands) и Counterattack Lodestone аддон читает
(RANGED_HIT; AP 30 и AP_VS_MECHANICAL 30); стенд даёт вещам те же ключи. Чтения `parse` и `api_ap` (отдаёт ли
GetItemStats силу атаки Lodestone) дают одно и то же: Items.Get берёт значение из текста.

## Итог 2026-11-18 (ветка raid-mode после шагов 13 и D, рейд-режим)

Прогон на копии дерева после шага D с `out/items.lua` тех же данных, что у прогонов групп A–C (3922 кандидата в
варианте А против 3914 в прогоне 2026-11-16; пересобрать его в рабочем дереве нечем: `../data` в git нет).

- А: текущий 732.06 DPS, лучший 739.74 (+7.69): Star of Mystaria 12103 вместо Mark of Fordring, Gordok's Gloves 18368
  вместо Raider Gloves, Ranger's Belt 272397 вместо Marksman's Girdle, Ironbark Staff 20220 вместо Peacemaker.
  Неподвижная точка аддона (Score.SetValue, оба чтения) — тот же набор.
- Б: текущий 715.32 DPS, лучший 721.22 (+5.91): Bone Golem Shoulders 18686, Beastmaster's Bindings 226885 вместо Marksman
  Bands, Ranger's Belt 272397, Ring of Demonic Guile 18314 вместо Tarnished Elven Ring, Flameslash Crescent 280056 вместо
  Peacemaker. Неподвижная точка аддона — 721.11 (+5.79): Shroud of the Nathrezim 18720 на плечах и Staff of Jordan 873 в
  руке, на 0.11 DPS ниже лучшего по D.
- В обоих вариантах итерация неподвижной точки зацикливается («SetValue iteration cycles; stopping»): веса мана-статов
  скачут на пороге зелья маны и руны (открытый пункт раздела 20.5 дизайна).
- Цифры выше прогона 2026-11-16 (508.8 у варианта А): бой 180 с с окнами кулдаунов, расходники, дебаффы босса (броня
  976, Curse of the Elements, Gift of Arthas) — модель другая, сравнивать с прошлыми цифрами нельзя.

## Итог 2026-11-16 (ветка wowsims-fixes ab07913 + незакоммиченные правки, модель прокачки)

- Рейд-босс (+3, кап 8%): А 508.8 DPS, лучший 511.5 (+0.5%) — разница только от условности «AP против типа» или < 1 DPS;
  Blackhand's on-use (не в UseData) её перекрывает. **Набор А и Б не меняется.**
- 5-ман (+2, кап 6%) и цель аддона по умолчанию (+0, кап 5%): хит сверх капа пропадает, реальные приросты ~3 DPS
  каждый: Marksman Bands → Bracers of the Eclipse 18375, Rune of the Guard Captain → Behemoth Bones 280065,
  (+0) Marksman's Girdle → Ranger's Belt 272397. Аддон с целью +0 покажет эти вещи как плюсы поверх набора А.
