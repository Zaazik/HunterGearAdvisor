"""Tests of tools/gen_proc_data.py's rules on DB2 rows: the chains of Heartseeking Crossbow 13040 and the Highborne Research
Tablet 260205 as build 70888 has them (ItemEffect 99815 -> 29626 -> 29640; 226835 -> 1318159 -> 1265634), and synthetic
rows for the rules those two do not exercise.

Run from the addon root: python -I tests/test_gen_proc_data.py (the generator is loaded from its path: -I keeps the
script's directory off sys.path). Exits 1 on a failure.

Rows of build 70888 (Forever DB2 exports): SpellEffect 704986 (29626: Effect 6 aura 42, EffectTriggerSpell 29640),
SpellAuraOptions 137308 (29626: ProcTypeMask_0 320, ProcChance 100, SpellProcsPerMinuteID 0, ProcCategoryRecovery 0),
SpellEffect 705032 (29640: Effect 2, ImplicitTarget 6, EffectBasePointsF 16, Variance 0.375), SpellMisc of 29640
(SchoolMask 32, Attributes_2 0), SpellCategories of 29640 (DefenseType 3); SpellEffect 1351486 (1318159: aura 42 ->
1265634), SpellAuraOptions 248218 (1318159: ProcTypeMask_0 65876, ProcChance 100), SpellEffect 1277542 (1265634: Effect 2,
EffectBasePointsF 75, Variance 0.15999999642), SpellMisc of 1265634 (SchoolMask 64), SpellCategories of 1265634
(DefenseType 1); SpellProcsPerMinute 455 (BaseProcRate 2). The damage over time of Rot-Covered Harpoon 274963's Rot
1295744 (SpellEffect 1317984: Effect 6 aura 3, ImplicitTarget 6, EffectBasePointsF 24, EffectAuraPeriod 1000; SpellEffect
1317985: aura 4, a dummy; SpellMisc 843139: SchoolMask 8, DurationIndex 165, Attributes_8 512; SpellDuration 165: 7000 ms;
SpellCategories 184305: DefenseType 1; SpellAuraOptions 246140: CumulativeAura 0) and of Demonshear 13348's Shadow Bolt
17483 (SpellEffect 696593: Effect 2, 150; SpellEffect 696594: aura 3, 34 every 2000 ms; SpellMisc 328994: SchoolMask 32,
DurationIndex 32, Attributes_8 512; SpellDuration 32: 6000 ms; SpellCategories 75867: DefenseType 1).
"""
import collections
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("gen_proc_data", os.path.join(ROOT, "tools", "gen_proc_data.py"))
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def se(effect, aura=0, trigger=0, bp=0, variance=0, target=6, ppl=0, period=0, index=0):
    return {"Effect": str(effect), "EffectAura": str(aura), "EffectTriggerSpell": str(trigger), "EffectBasePointsF": str(bp),
            "Variance": str(variance), "ImplicitTarget_0": str(target), "EffectRealPointsPerLevel": str(ppl),
            "EffectAuraPeriod": str(period), "EffectIndex": str(index)}


def sao(mask, chance, ppm_id=0, icd=0, mask1=0, cumulative=0):
    return {"ProcTypeMask_0": str(mask), "ProcTypeMask_1": str(mask1), "ProcChance": str(chance),
            "SpellProcsPerMinuteID": str(ppm_id), "ProcCategoryRecovery": str(icd), "CumulativeAura": str(cumulative)}


def misc(school, attr2=0, attr8=0, duration=0):
    return {"SchoolMask": str(school), "Attributes_2": str(attr2), "Attributes_8": str(attr8), "DurationIndex": str(duration)}


def dur(ms, per_level=0, max_ms=None):
    return {"Duration": str(ms), "DurationPerLevel": str(per_level), "MaxDuration": str(ms if max_ms is None else max_ms)}


def tables(**over):
    t = dict(
        spell_effects={
            29626: [se(6, 42, 29640, target=1)], 29640: [se(2, bp=16, variance=0.375)],
            1318159: [se(6, 42, 1265634, bp=2, target=1)], 1265634: [se(2, bp=75, variance=0.15999999642)],
        },
        aura_options={29626: [sao(320, 100)], 1318159: [sao(65876, 100)]},
        ppm={455: 2.0},
        misc={29640: [misc(32)], 1265634: [misc(64)]},
        categories={29640: [{"DefenseType": "3"}], 1265634: [{"DefenseType": "1"}]},
        durations={165: dur(7000), 32: dur(6000)},
        en={29626: "Chance to strike your ranged target with a Shadow Bolt for $29640s1 Shadow damage.",
            1318159: "Chance on hit to deal $1265634s1 Arcane damage. Deals $s2 times as much damage to Naga and Satyrs."},
        ru={29626: "Шанс поразить отдаленную цель стрелой Тьмы и нанести ей $29640s1 ед. урона от темной магии.",
            1318159: "С некоторой вероятностью при попадании наносит $1265634s1 ед. урона от тайной магии."},
    )
    for k, v in over.items():
        merged = dict(t[k])
        merged.update(v)
        t[k] = merged
    return gen.Tables(**t)


def entry(trigger_type, spell, t, item=900001):
    e = gen.entry_for(trigger_type, spell, t, item, set())
    if isinstance(e, dict):
        e = {k: v for k, v in e.items() if k not in ("en", "ru")}
    return e


def raises(f):
    try:
        f()
    except SystemExit:
        return True
    return False


def two_entries(kind, spell):
    """The (kind, damage spell) pairs written for an item after an equip entry of spell 29640 and a second one."""
    out = collections.defaultdict(list)
    gen.add_entry(out, 13040, {"kind": "equip", "spell": 29640})
    gen.add_entry(out, 13040, {"kind": kind, "spell": spell})
    return [(e["kind"], e["spell"]) for e in out[13040]]


HEART = {"kind": "equip", "mask": 320, "chance": 100, "ppm": 0.0, "icd": 0, "trigger": 29626, "spell": 29640, "avg": 16,
         "min": 13, "max": 19, "school": 32, "defense": 3, "crit": True}
TABLET = {"kind": "equip", "mask": 65876, "chance": 100, "ppm": 0.0, "icd": 0, "trigger": 1318159, "spell": 1265634,
          "avg": 75, "min": 69, "max": 81, "school": 64, "defense": 1, "crit": True}

# a chance-on-hit spell (TriggerType 2) of made-up rows: 50.4 base points, Variance 0.3 (+-7.56: 43 to 58)
HIT = 900100
# Rot 1295744 and Shadow Bolt 17483 as build 70888 has them (module docstring)
ROT, BOLT = 1295744, 17483


def rot_tables(**over):
    base = dict(
        spell_effects={ROT: [se(6, 3, bp=24, period=1000), se(6, 4, bp=2)],
                       BOLT: [se(2, bp=150), se(6, 3, bp=34, period=2000)]},
        misc={ROT: [misc(8, attr8=512, duration=165)], BOLT: [misc(32, attr8=512, duration=32)]},
        categories={ROT: [{"DefenseType": "1"}], BOLT: [{"DefenseType": "1"}]},
        aura_options={ROT: [sao(0, 101)], BOLT: [sao(0, 101)]},
        en={ROT: "Rots the target, causing $s1 Nature damage every $t1 sec. for $d.",
            BOLT: "Sends a shadowy bolt at the enemy causing $s1 Shadow damage and an additional $o2 Shadow damage over $d."},
        ru={ROT: "Гниль наносит $s1 ед. урона от сил природы раз в $t1 сек. в течение $d.",
            BOLT: "Посылает в противника стрелу Тьмы, наносящую $s1 ед. урона от темной магии и $o2 ед. урона от темной магии за $d."},
    )
    for k, v in over.items():
        merged = dict(base.get(k, {}))
        merged.update(v)
        base[k] = merged
    return tables(**base)
CASES = [
    ("13040: 29626 -> 29640, mask 320, chance 100, Shadow, the ranged table", lambda: entry(1, 29626, tables(), 13040), HEART),
    ("260205: 1318159 -> 1265634, mask 65876, Arcane, the magic table", lambda: entry(1, 1318159, tables(), 260205), TABLET),
    ("a stated procs-per-minute rate: SpellProcsPerMinute 455's 2, a chance 8 and an internal cooldown kept",
     lambda: {k: entry(1, 29626, tables(aura_options={29626: [sao(320, 8, 455, 200)]}))[k] for k in ("ppm", "chance", "icd")},
     {"ppm": 2.0, "chance": 8, "icd": 200}),
    ("a damage spell with no SpellCategories row: DefenseType 0",
     lambda: entry(1, 29626, tables(categories={29640: []}))["defense"], 0),
    ("Attributes_2 0x20000000: the spell cannot crit",
     lambda: entry(1, 29626, tables(misc={29640: [misc(32, 0x20000000)]}))["crit"], False),
    ("Attributes_2 as a signed number with 0x20000000 set: the spell cannot crit",
     lambda: entry(1, 29626, tables(misc={29640: [misc(32, -1610612736)]}))["crit"], False),
    ("Attributes_2 without 0x20000000: the spell can crit",
     lambda: entry(1, 29626, tables(misc={29640: [misc(32, 0x10000000)]}))["crit"], True),
    ("a chance on hit (TriggerType 2): the item effect's spell is the damage, no mask or rate",
     lambda: entry(2, HIT, tables(spell_effects={HIT: [se(2, bp=50.4, variance=0.3)]}, misc={HIT: [misc(4)]}, categories={HIT: [{"DefenseType": "1"}]})),
     {"kind": "hit", "trigger": HIT, "spell": HIT, "avg": 50.400001525878906, "min": 43, "max": 58, "school": 4, "defense": 1, "crit": True}),
    ("the physical school's mean: the midpoint of the rounded bounds",
     lambda: entry(2, HIT, tables(spell_effects={HIT: [se(2, bp=50.4, variance=0.3)]}, misc={HIT: [misc(1)]}))["avg"], 50.5),
    ("the rounded ends half to even: 12 +- 1.5 (Variance 0.25) is 10 to 14",
     lambda: {k: entry(2, HIT, tables(spell_effects={HIT: [se(2, bp=12, variance=0.25)]}, misc={HIT: [misc(1)]}))[k] for k in ("min", "max", "avg")},
     {"min": 10, "max": 14, "avg": 12}),
    ("Variance 0: the floored base points at both ends, the base points the mean",
     lambda: {k: entry(2, HIT, tables(spell_effects={HIT: [se(2, bp=30.5)]}, misc={HIT: [misc(2)]}))[k] for k in ("min", "max", "avg")},
     {"min": 30, "max": 30, "avg": 30.5}),
    ("a SchoolMask with the physical bit and another (3): physical, as its school words read",
     lambda: entry(1, 29626, tables(misc={29640: [misc(3)]}, en={29626: "Strikes your target for $29640s1 damage."},
                                    ru={29626: "Наносит цели $29640s1 ед. урона."}))["school"], 3),
    ("an equip spell with no proc trigger aura: left out",
     lambda: entry(1, 29626, tables(spell_effects={29626: [se(6, 29, target=1)]})), None),
    ("a damage spell with neither school damage nor a periodic damage aura (a slow, aura 33): left out",
     lambda: entry(1, 29626, tables(spell_effects={29640: [se(6, 33, bp=10)]})), None),
    ("a periodic damage aura on the caster alone: left out",
     lambda: entry(2, ROT, rot_tables(spell_effects={ROT: [se(6, 3, bp=24, period=1000, target=1)]})), None),
    ("Rot 1295744 from the DB2: 24 every 1 s for 7 s, Nature, magic, can crit, no direct damage (avg 0)",
     lambda: entry(2, ROT, rot_tables(), 274963),
     {"kind": "hit", "trigger": ROT, "spell": ROT, "avg": 0, "min": 0, "max": 0, "school": 8, "defense": 1, "crit": True,
      "dot": {"tick": 24.0, "period": 1000, "ticks": 7, "canCrit": True}}),
    ("Shadow Bolt 17483: a direct 150 and 34 every 2 s for 6 s: 3 ticks, the duration over the period",
     lambda: {k: v for k, v in entry(2, BOLT, rot_tables(), 13348).items() if k in ("avg", "min", "max", "dot")},
     {"avg": 150.0, "min": 150, "max": 150, "dot": {"tick": 34.0, "period": 2000, "ticks": 3, "canCrit": True}}),
    ("Attributes_8 without 0x200: its ticks cannot crit",
     lambda: entry(2, ROT, rot_tables(misc={ROT: [misc(8, attr8=0x100, duration=165)]}))["dot"]["canCrit"], False),
    ("a damage over time behind an equip aura's trigger: an equip entry with its dot",
     lambda: {k: v for k, v in entry(1, 29626, rot_tables(spell_effects={29626: [se(6, 42, ROT, target=1)]})).items()
              if k in ("kind", "mask", "spell", "avg", "dot")},
     {"kind": "equip", "mask": 320, "spell": ROT, "avg": 0, "dot": {"tick": 24.0, "period": 1000, "ticks": 7, "canCrit": True}}),
    ("a damage over time alone: its words are not checked (Corruption's \"causing $o1 damage\" for a Shadow school)",
     lambda: entry(2, ROT, rot_tables(misc={ROT: [misc(32, attr8=512, duration=165)]},
                                      en={ROT: "Corrupts the target, causing $o1 damage over $d."},
                                      ru={ROT: "Ранит цель, нанося $o1 ед. урона от кровотечения за $d."}))["school"], 32),
    ("a periodic damage that gains points a level: the skip \"level\"",
     lambda: entry(2, ROT, rot_tables(spell_effects={ROT: [se(6, 3, bp=24, period=1000, ppl=1)]})), "level"),
    ("a damage over time of one stack (CumulativeAura 1): written",
     lambda: entry(2, ROT, rot_tables(aura_options={ROT: [sao(0, 101, cumulative=1)]}))["dot"]["ticks"], 7),
    ("school damage on the caster alone: left out",
     lambda: entry(1, 29626, tables(spell_effects={29640: [se(2, bp=16, target=1)]})), None),
    ("a damage that gains points a level: the skip \"level\"",
     lambda: entry(1, 29626, tables(spell_effects={29640: [se(2, bp=16, ppl=1)]})), "level"),
    ("ProcTypeMask_1's main-hand-only bit: an entry of the main hand alone (mainHand), its mask 20 as it stands",
     lambda: {k: v for k, v in entry(1, 29626, tables(aura_options={29626: [sao(20, 100, mask1=32)]})).items()
              if k in ("kind", "mask", "mainHand", "chance", "spell")},
     {"kind": "equip", "mask": 20, "mainHand": True, "chance": 100, "spell": 29640}),
    ("no bit of ProcTypeMask_1: no mainHand",
     lambda: "mainHand" in entry(1, 29626, tables(aura_options={29626: [sao(20, 100)]})), False),
    ("ProcTypeMask_0's main-hand weapon swing bit: the skip \"hands\"",
     lambda: entry(1, 29626, tables(aura_options={29626: [sao(0x400014, 100)]})), "hands"),
    ("an item's second entry of another kind or another damage spell: both written",
     lambda: (two_entries("hit", 29640), two_entries("equip", 29641)),
     ([("equip", 29640), ("hit", 29640)], [("equip", 29640), ("equip", 29641)])),
    ("every TEXT_SCHOOL_MISMATCHES description met by a written entry: no stop",
     lambda: gen.check_mismatches_seen(set(gen.TEXT_SCHOOL_MISMATCHES)), None),
]

STOPS = [
    ("two proc trigger auras", lambda: entry(1, 29626, tables(spell_effects={29626: [se(6, 42, 29640, target=1), se(6, 42, 29640, target=1)]}))),
    ("no SpellAuraOptions row", lambda: entry(1, 29626, tables(aura_options={29626: []}))),
    ("two SpellAuraOptions rows", lambda: entry(1, 29626, tables(aura_options={29626: [sao(320, 100), sao(320, 100)]}))),
    ("a SpellProcsPerMinuteID without a row", lambda: entry(1, 29626, tables(aura_options={29626: [sao(320, 100, 999)]}))),
    ("another bit of ProcTypeMask_1", lambda: entry(1, 29626, tables(aura_options={29626: [sao(320, 100, mask1=1)]}))),
    ("another bit of ProcTypeMask_1 beside the main hand's", lambda: entry(1, 29626, tables(aura_options={29626: [sao(20, 100, mask1=0x21)]}))),
    ("two school damage effects", lambda: entry(1, 29626, tables(spell_effects={29640: [se(2, bp=16), se(2, bp=16)]}))),
    ("no SpellMisc row", lambda: entry(1, 29626, tables(misc={29640: []}))),
    ("two SpellCategories rows", lambda: entry(1, 29626, tables(categories={29640: [{"DefenseType": "3"}, {"DefenseType": "3"}]}))),
    ("a DefenseType of 4", lambda: entry(1, 29626, tables(categories={29640: [{"DefenseType": "4"}]}))),
    ("an enUS description that names no school for a magic damage",
     lambda: entry(1, 29626, tables(en={29626: "Chance to strike your ranged target for $29640s1 damage."}))),
    ("a ruRU description that names no school for a magic damage",
     lambda: entry(1, 29626, tables(ru={29626: "Наносит цели $29640s1 ед. урона."}))),
    ("a description that names a school for a physical damage",
     lambda: entry(1, 29626, tables(misc={29640: [misc(1)]}))),
    ("a listed mismatch whose description reads otherwise now",
     lambda: entry(2, 1290950, tables(spell_effects={1290950: [se(2, bp=250, variance=0.4)]}, misc={1290950: [misc(32)]},
                                      en={1290950: "Wounds the target for $s1 Shadow damage."}), 19324)),
    ("an item's second entry of one kind and damage spell", lambda: two_entries("equip", 29640)),
    ("two periodic damage auras", lambda: entry(2, ROT, rot_tables(spell_effects={ROT: [se(6, 3, bp=24, period=1000), se(6, 3, bp=5, period=1000)]}))),
    ("a duration no whole number of periods (7 s over 2 s)",
     lambda: entry(2, ROT, rot_tables(spell_effects={ROT: [se(6, 3, bp=24, period=2000)]}))),
    ("a period of 0", lambda: entry(2, ROT, rot_tables(spell_effects={ROT: [se(6, 3, bp=24, period=0)]}))),
    ("a periodic damage with a Variance", lambda: entry(2, ROT, rot_tables(spell_effects={ROT: [se(6, 3, bp=24, period=1000, variance=0.2)]}))),
    ("a DurationIndex without a SpellDuration row", lambda: entry(2, ROT, rot_tables(misc={ROT: [misc(8, attr8=512, duration=999)]}))),
    ("a duration that gains a level", lambda: entry(2, ROT, rot_tables(durations={165: dur(7000, per_level=100)}))),
    ("a duration with another maximum", lambda: entry(2, ROT, rot_tables(durations={165: dur(7000, max_ms=14000)}))),
    ("no duration (a permanent aura's -1)", lambda: entry(2, ROT, rot_tables(durations={165: dur(-1)}))),
    ("a damage over time that stacks (CumulativeAura 3)", lambda: entry(2, ROT, rot_tables(aura_options={ROT: [sao(0, 101, cumulative=3)]}))),
    ("a damage over time of two stacks (CumulativeAura 2)", lambda: entry(2, ROT, rot_tables(aura_options={ROT: [sao(0, 101, cumulative=2)]}))),
    ("two SpellAuraOptions rows of a damage spell with a damage over time",
     lambda: entry(2, ROT, rot_tables(aura_options={ROT: [sao(0, 101), sao(0, 101)]}))),
    ("a direct damage of mean 0 beside a damage over time",
     lambda: entry(2, BOLT, rot_tables(spell_effects={BOLT: [se(2, bp=0), se(6, 3, bp=34, period=2000)]}))),
    ("a TEXT_SCHOOL_MISMATCHES description no written entry met",
     lambda: gen.check_mismatches_seen(set(gen.TEXT_SCHOOL_MISMATCHES) - {(19324, 1290950, "en")})),
]


# wowsims' override files as data (tools/database/overrides): WeaponProcs rows (one commented out, waiting for a rate: no
# row; a Reason across two string literals) and Spells rows (PPM and ProcChancePct read; another field skipped, an ICDMs
# row too: an internal cooldown is no rate, spell_overrides.go's ICDMs row of 350026; a PPM row whose spell is only a
# chance on hit's trigger: the Spells rows go onto equip auras alone)
WEAPON_PROCS_GO = """package overrides

var WeaponProcs = []WeaponProc{
	// Measured in end-game dungeon logs (EV-0003).
	{
		ItemID:  17753,
		SpellID: 29655,
		PPM:     3.5,
		Reason:  "Verdant Keeper's Aim: no proc row; " +
			"melee hits do not roll it",
		Source:  "EV-0003",
	},
	// {
	// 	ItemID:  869,
	// 	SpellID: 13752,
	// 	PPM:     0, // TODO: waiting for PPM data
	// 	Reason:  "Dazzling Longsword: column reads 101",
	// 	Source:  "vanilla-carryover",
	// },
	{
		ItemID:  2825,
		SpellID: 29638,
		PPM:     3.35,
		Reason:  "Bow of Searing Arrows: no proc row {braces}",
		Source:  "vanilla-carryover",
	},
}
"""
SPELL_OVERRIDES_GO = """package overrides

var Spells = []Override{
	{
		SpellID: 1318159,
		Field:   PPM,
		Value:   2.6,
		Reason:  "Highborne Research Tablet: 2.6 procs per minute",
		Source:  "EV-0021",
	},
	{
		SpellID: 1294668,
		Field:   ProcChancePct,
		Value:   5,
		Reason:  "5% a hit",
		Source:  "EV-0115",
	},
	{
		SpellID: 20230,
		Field:   FlatThreat,
		Value:   7,
		Reason:  "not a rate",
		Source:  "game-files-rows",
	},
	{
		SpellID: 350026,
		Field:   ICDMs,
		Value:   1000,
		Reason:  "an internal cooldown, not a rate",
		Source:  "EV-0001",
	},
	{
		SpellID: 29655,
		Field:   PPM,
		Value:   9,
		Reason:  "the chance on hit's trigger: no equip aura takes it",
		Source:  "EV-0002",
	},
}
"""


# wowsims' VersusBonuses rows as data (tools/database/overrides/spell_overrides.go, raid-mode design 25.2), the forms of
# its rows: Rend 14118 (a mob type, its factor the base points of effect 1), Gloves of Holy Might 1325229 (a Multiplier no
# effect states), Ancient Power 1318159 (families alone), Serpentbane 1295039 (a mob type and a family; no entry here)
VERSUS_GO = """package overrides

var VersusBonuses = []VersusBonus{
	{
		SpellID:     14118,
		EffectIndex: 1,
		MobTypes:    []proto.MobType{proto.MobType_MobTypeDragonkin},
		Reason:      "Rend: 'Deals $s2 times as much damage to Dragonkin'",
		Source:      "tooltip",
	},
	{
		SpellID:    1325229,
		Multiplier: 3,
		MobTypes:   []proto.MobType{proto.MobType_MobTypeUndead},
		Reason:     "Gloves of Holy Might: 'Damage is tripled against Undead'",
		Source:     "tooltip",
	},
	{
		SpellID:     1318159,
		EffectIndex: 0,
		Families:    []proto.CreatureFamily{proto.CreatureFamily_CreatureFamilyNaga, proto.CreatureFamily_CreatureFamilySatyr},
		Reason:      "Ancient Power: 'Deals $s1 times as much damage to Naga and Satyrs'",
		Source:      "tooltip",
	},
	{
		SpellID:     1295039,
		EffectIndex: 2,
		MobTypes:    []proto.MobType{proto.MobType_MobTypeBeast},
		Families:    []proto.CreatureFamily{proto.CreatureFamily_CreatureFamilySerpentine},
		Reason:      "Serpentbane: 'Inflicts $s3 times as much damage to Beast and Serpentine targets'",
		Source:      "tooltip",
	},
}
"""


def versus_case(rows=None, effects=None):
    """(entries after attach_versus, its result) of the VersusBonuses rows on made-up entries: a chance on hit of 14118, one
    of 1325229, the Tablet's equip aura 1318159, and an equip aura 900200 whose damage spell is 14118 (the bonus is the
    trigger's: it takes none)"""
    out = collections.defaultdict(list)
    out[12463].append({"kind": "hit", "trigger": 14118, "spell": 14118})
    out[867].append({"kind": "hit", "trigger": 1325229, "spell": 1325229})
    out[260205].append({"kind": "equip", "trigger": 1318159, "spell": 1265634})
    out[900200].append({"kind": "equip", "trigger": 900201, "spell": 14118})
    t = tables(spell_effects=effects if effects is not None else {14118: [se(6, 3, bp=23, period=1000), se(6, 4, bp=2, index=1)],
                                                                1295039: [se(2, bp=100), se(6, 3, bp=45, period=2000, index=1),
                                                                          se(0, bp=2, index=2)]})
    result = gen.attach_versus(out, rows if rows is not None else gen.read_versus_bonuses(VERSUS_GO), t)
    return out, result


# wowsims' generated proc registrations (sim/common/forever/stat_bonus_procs_auto_gen.go) and spell store rows
# (sim/core/spelldata/spells_auto_gen.go) as data, in their forms (raid-mode design 25.3): Hurricane's active "every time"
# damage registration (stat_bonus_procs_auto_gen.go:4077-4081), a commented-out one (a weapon proc with no rate), a heal
# registration (another constructor), Blazefury Medallion's with an item no entry has, Lord Sakrasis' Scepter 5028's of a
# trigger that states a procs per minute, and a registration of another rate
REGISTRATIONS_GO = """package forever

func RegisterAllProcs() {
	// All ranged auto-attacks conjure an icy bolt to blast your current target, inflicting 8 Frost damage.
	// trigger 1316319 (every time, core.CallbackOnSpellHitDealt, core.ProcMaskRangedAuto) -> buff 29502
	shared.NewSpellDataDamageProc(shared.SpellDataProc{TriggerSpellID: 1316319, BuffSpellID: 29502},
		[]shared.ItemVariant{
			{ItemID: 2824, ItemName: "Hurricane"},
		})

	// unsupported: states no rate
	// trigger 17504 (every time, core.CallbackEmpty, core.ProcMaskUnknown)
	// shared.NewSpellDataDamageProc(shared.SpellDataProc{TriggerSpellID: 17504, BuffSpellID: 17504, IsWeaponProc: true},
	//	[]shared.ItemVariant{
	//	{ItemID: 809, ItemName: "Bloodrazor"},
	// })

	// trigger 28847 (every time, core.CallbackOnCastComplete, core.ProcMaskSpellHealing)
	shared.NewSpellDataHealProc(shared.SpellDataProc{TriggerSpellID: 28847},
		[]shared.ItemVariant{
			{ItemID: 23004, ItemName: "Idol of Longevity"},
		})

	// trigger 7711 (every time, core.CallbackOnSpellHitDealt, core.ProcMaskMeleeMHAuto | core.ProcMaskMeleeOHAuto) -> buff 7712
	shared.NewSpellDataDamageProc(shared.SpellDataProc{TriggerSpellID: 7711, BuffSpellID: 7712},
		[]shared.ItemVariant{
			{ItemID: 17111, ItemName: "Blazefury Medallion"},
			{ItemID: 999901, ItemName: "No entry here"},
		})

	// trigger 1326019 (every time, core.CallbackOnCastComplete, core.ProcMaskSpellDamage) -> buff 1312330
	shared.NewSpellDataDamageProc(shared.SpellDataProc{TriggerSpellID: 1326019, BuffSpellID: 1312330},
		[]shared.ItemVariant{
			{ItemID: 5028, ItemName: "Lord Sakrasis' Scepter"},
		})

	// trigger 29626 (5%, core.CallbackOnSpellHitDealt, core.ProcMaskRanged) -> buff 29640
	shared.NewSpellDataDamageProc(shared.SpellDataProc{TriggerSpellID: 29626, BuffSpellID: 29640},
		[]shared.ItemVariant{
			{ItemID: 13040, ItemName: "Heartseeking Crossbow"},
		})
}
"""
STORE_GO = """package spelldata

var spellData = []Spell{
	{ID: 7711, Name: "Add Fire Dam - Weap 02", School: 1, ProcChance: 100, ProcFlags: [2]uint32{0: 0x14}, ProcChanceSource: ProcChanceAlways, ProcHint: core.ProcHintDamage,
	{ID: 29626, Name: "Heartseeking", School: 1, ProcChance: 100,
	{ID: 1316319, Name: "Hurricane", School: 1, ProcChance: 100, ProcFlags: [2]uint32{0: 0x40}, RefIDs: []int32{29502}, ProcChanceSource: ProcChanceAlways,
	{ID: 1326019, Name: "Sakrasis", School: 1, ProcChance: 101, ProcChanceSource: ProcChanceAlways,
}
"""


def always_case(regs=None, sources=None, extra=None):
    """(entries after attach_always, its result) on made-up equip entries of Hurricane 2824, Blazefury Medallion 17111 and
    Lord Sakrasis' Scepter 5028 (a stated procs per minute) and a chance on hit of 809"""
    out = collections.defaultdict(list)
    out[2824].append({"kind": "equip", "trigger": 1316319, "chance": 100, "ppm": 0.0})
    out[17111].append({"kind": "equip", "trigger": 7711, "chance": 100, "ppm": 0.0})
    out[5028].append({"kind": "equip", "trigger": 1326019, "chance": 101, "ppm": 2.0})
    out[809].append({"kind": "hit", "trigger": 17504})
    for item_id, e in (extra or {}).items():
        out[item_id].append(e)
    regs = regs if regs is not None else gen.read_every_time(REGISTRATIONS_GO)
    sources = sources if sources is not None else gen.store_sources(STORE_GO, sorted({r["trigger"] for r in regs}))
    return out, gen.attach_always(out, regs, sources)


def overrides_case():
    """(read rows, entries after attach_overrides, unused rows) of the synthetic override files"""
    weapon = gen.read_weapon_procs(WEAPON_PROCS_GO)
    spells = gen.read_spell_overrides(SPELL_OVERRIDES_GO)
    out = collections.defaultdict(list)
    out[17753].append({"kind": "hit", "trigger": 29655, "spell": 29655})
    out[260205].append({"kind": "equip", "trigger": 1318159, "spell": 1265634, "ppm": 0.0, "chance": 100})
    out[99001].append({"kind": "equip", "trigger": 1294668, "spell": 1, "ppm": 0.0, "chance": 101})
    out[99002].append({"kind": "equip", "trigger": 350026, "spell": 2, "ppm": 0.0, "chance": 100})
    unused = gen.attach_overrides(out, weapon, spells)
    return weapon, spells, out, unused


def attach_stop(entry, weapon=(), spells=()):
    out = collections.defaultdict(list)
    out[1].append(entry)
    gen.attach_overrides(out, list(weapon), list(spells))


def main():
    passed = failed = 0
    weapon, spells, out, unused = overrides_case()
    checks = [
        ("WeaponProcs rows, the commented one left out", [(r["item"], r["spell"], r["ppm"], r["source"]) for r in weapon],
         [(17753, 29655, 3.5, "EV-0003"), (2825, 29638, 3.35, "vanilla-carryover")]),
        ("Spells rows: PPM and ProcChancePct", [(r["spell"], r["field"], r["value"], r["source"]) for r in spells],
         [(1318159, "PPM", 2.6, "EV-0021"), (1294668, "ProcChancePct", 5.0, "EV-0115"), (29655, "PPM", 9.0, "EV-0002")]),
        ("a chance on hit takes its WeaponProcs row", (out[17753][0]["ppm"], out[17753][0]["source"]), (3.5, "EV-0003")),
        ("an equip aura of no stated rate takes its PPM row", (out[260205][0]["ppm"], out[260205][0]["source"]), (2.6, "EV-0021")),
        ("an equip aura of no stated rate takes its ProcChancePct row", (out[99001][0]["chance"], out[99001][0]["source"]),
         (5.0, "EV-0115")),
        ("a Spells PPM row leaves a chance on hit's entry of its trigger alone (its WeaponProcs row stays)",
         (out[17753][0]["ppm"], out[17753][0]["source"]), (3.5, "EV-0003")),
        ("an ICDMs row is no rate: the equip aura of its spell keeps no rate", (out[99002][0]["ppm"], out[99002][0]["chance"],
         "source" in out[99002][0]), (0.0, 100, False)),
        ("the rows no entry takes", unused, [("weapon", 2825, 29638), ("spell", 29655, "PPM")]),
    ]
    for name, got, want in checks:
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    override_stops = [
        ("an override on an equip aura that states a chance", lambda: attach_stop(
            {"kind": "equip", "trigger": 7, "ppm": 0.0, "chance": 5}, spells=[{"spell": 7, "field": "PPM", "value": 2, "source": "x"}])),
        ("a WeaponProcs row on an equip aura that states a chance", lambda: attach_stop(
            {"kind": "equip", "trigger": 7, "ppm": 0.0, "chance": 5}, weapon=[{"item": 1, "spell": 7, "ppm": 1, "source": "x"}])),
        ("an override on an equip aura that states a procs per minute", lambda: attach_stop(
            {"kind": "equip", "trigger": 7, "ppm": 2.0, "chance": 100}, weapon=[{"item": 1, "spell": 7, "ppm": 1, "source": "x"}])),
        ("a WeaponProcs row named twice", lambda: attach_stop(
            {"kind": "hit", "trigger": 7}, weapon=[{"item": 1, "spell": 7, "ppm": 1, "source": "x"}] * 2)),
        ("a WeaponProcs row without its Source", lambda: gen.read_weapon_procs(
            WEAPON_PROCS_GO.replace('Source:  "EV-0003",', ""))),
        ("an override file without its slice", lambda: gen.read_spell_overrides("package overrides\n")),
    ]
    for name, f in override_stops:
        if raises(f):
            passed += 1
        else:
            failed += 1
            print("FAIL %s: the generator does not stop" % name)
    # the versus bonuses: the rows read, their mob types on the entries whose trigger is the row's spell
    vrows = gen.read_versus_bonuses(VERSUS_GO)
    vout, (v_took, v_families, v_unused) = versus_case()
    versus_checks = [
        ("VersusBonuses rows: spell, index, multiplier, types, families",
         [(r["spell"], r["index"], r["multiplier"], r["types"], r["families"], r["source"]) for r in vrows],
         [(14118, 1, 0.0, ["DRAGONKIN"], [], "tooltip"), (1325229, 0, 3.0, ["UNDEAD"], [], "tooltip"),
          (1318159, 0, 0.0, [], ["Naga", "Satyr"], "tooltip"), (1295039, 2, 0.0, ["BEAST"], ["Serpentine"], "tooltip")]),
        ("Rend: the base points of its effect 1, x2 against Dragonkin", vout[12463][0].get("versus"), {"factor": 2.0, "types": ["DRAGONKIN"]}),
        ("Gloves of Holy Might: the Multiplier 3 against Undead", vout[867][0].get("versus"), {"factor": 3.0, "types": ["UNDEAD"]}),
        ("a row of families alone: no entry takes it", "versus" in vout[260205][0], False),
        ("the bonus is the trigger's: an equip aura whose damage spell is the row's takes none", "versus" in vout[900200][0], False),
        ("the rows taken, of families alone, of types with no entry", (v_took, v_families, v_unused), ([14118, 1325229], [1318159], [1295039])),
    ]
    for name, got, want in versus_checks:
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    rend = [r for r in vrows if r["spell"] == 14118]
    versus_stops = [
        ("a mob type HGA has no creature type for", lambda: gen.read_versus_bonuses(VERSUS_GO.replace("MobTypeDragonkin", "MobTypeCritter"))),
        ("a row without its Source", lambda: gen.read_versus_bonuses(VERSUS_GO.replace('Source:      "tooltip",\n\t},\n\t{\n\t\tSpellID:    1325229', '},\n\t{\n\t\tSpellID:    1325229', 1))),
        ("a row with neither a mob type nor a family", lambda: gen.read_versus_bonuses(VERSUS_GO.replace(
            "\t\tMobTypes:    []proto.MobType{proto.MobType_MobTypeDragonkin},\n", "", 1))),
        ("no effect of the row's index", lambda: versus_case(rend, {14118: [se(6, 3, bp=23, period=1000)]})),
        ("two effects of the row's index", lambda: versus_case(rend, {14118: [se(6, 4, bp=2, index=1), se(6, 4, bp=2, index=1)]})),
        ("a factor of 1", lambda: versus_case(rend, {14118: [se(6, 4, bp=1, index=1)]})),
        ("two rows on one entry", lambda: versus_case(rend + rend)),
    ]
    for name, f in versus_stops:
        if raises(f):
            passed += 1
        else:
            failed += 1
            print("FAIL %s: the generator does not stop" % name)
    # the procs on every hit: wowsims' active "every time" damage registrations mark their items' equip entries always
    regs = gen.read_every_time(REGISTRATIONS_GO)
    aout, (a_marked, a_missing, a_stated) = always_case()
    always_checks = [
        ("every-time damage registrations: trigger, items, active (the heal and the other rate left out)",
         [(r["trigger"], r["items"], r["active"]) for r in regs],
         [(1316319, [2824], True), (17504, [809], False), (7711, [17111, 999901], True), (1326019, [5028], True)]),
        ("the store's ProcChanceSource: Always where it says so, the column where it names none",
         gen.store_sources(STORE_GO, [7711, 29626, 1316319, 4242]),
         {7711: "ProcChanceAlways", 29626: "ProcChanceColumn", 1316319: "ProcChanceAlways"}),
        ("Hurricane and Blazefury Medallion always", (aout[2824][0].get("always"), aout[17111][0].get("always")), (True, True)),
        ("a stated procs per minute: its entry keeps its ppm, no always", ("always" in aout[5028][0], aout[5028][0]["ppm"]), (False, 2.0)),
        ("a commented-out registration marks nothing", "always" in aout[809][0], False),
        ("the pairs marked, with no entry, with a stated rate", (a_marked, a_missing, a_stated),
         ([(2824, 1316319), (17111, 7711)], [(999901, 7711)], [(5028, 1326019)])),
    ]
    for name, got, want in always_checks:
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    hurricane = [r for r in regs if r["trigger"] == 1316319]
    always_stops = [
        ("a store row of the column under an every-time registration",
         lambda: always_case(hurricane, {1316319: "ProcChanceColumn"})),
        ("an every-time trigger with no store row", lambda: always_case(hurricane, {})),
        ("an every-time entry with a ProcChance of 5",
         lambda: always_case([{"trigger": 7, "items": [7], "active": True}], {7: "ProcChanceAlways"},
                             {7: {"kind": "equip", "trigger": 7, "chance": 5, "ppm": 0.0}})),
        ("an every-time entry with an override rate",
         lambda: always_case([{"trigger": 7, "items": [7], "active": True}], {7: "ProcChanceAlways"},
                             {7: {"kind": "equip", "trigger": 7, "chance": 100, "ppm": 0.0, "source": "EV-0001"}})),
        ("an every-time registration naming no item", lambda: gen.read_every_time(REGISTRATIONS_GO.replace(
            '\t\t\t{ItemID: 2824, ItemName: "Hurricane"},\n', ""))),
        ("an every-time registration without its end", lambda: gen.read_every_time(
            "\t// trigger 7711 (every time, x)\n\tshared.NewSpellDataDamageProc(shared.SpellDataProc{TriggerSpellID: 7711},\n")),
    ]
    for name, f in always_stops:
        if raises(f):
            passed += 1
        else:
            failed += 1
            print("FAIL %s: the generator does not stop" % name)
    for name, f, want in CASES:
        got = f()
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    for name, f in STOPS:
        if raises(f):
            passed += 1
        else:
            failed += 1
            print("FAIL %s: the generator does not stop" % name)
    # the school words: enUS "<school> damage" magic, "damage" with another word or none physical; ruRU "ед. урона от" magic
    words = [
        (gen.school_en("for $s1 Shadow damage."), "magic"), (gen.school_en("for $s1 damage."), "physical"),
        (gen.school_en("for $s1 Physical damage."), "physical"), (gen.school_en("no damage phrase"), None),
        (gen.school_ru("наносит $s1 ед. урона от огня."), "magic"), (gen.school_ru("наносит $s1 ед. урона."), "physical"),
        (gen.school_ru("наносит $s1 ед. физического урона."), "physical"),
    ]
    for got, want in words:
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL school words: expected %r, got %r" % (want, got))
    # a listed mismatch (TEXT_SCHOOL_MISMATCHES): The Lobotomizer's 1290950, read as cited, is written and recorded
    seen = set()
    t = tables(spell_effects={1290950: [se(2, bp=250, variance=0.4)]}, misc={1290950: [misc(32)]},
               en={1290950: gen.TEXT_SCHOOL_MISMATCHES[(19324, 1290950, "en")]},
               ru={1290950: gen.TEXT_SCHOOL_MISMATCHES[(19324, 1290950, "ru")]})
    e = gen.entry_for(2, 1290950, t, 19324, seen)
    if isinstance(e, dict) and e["school"] == 32 and seen == {(19324, 1290950, "en"), (19324, 1290950, "ru")}:
        passed += 1
    else:
        failed += 1
        print("FAIL a listed mismatch: %r, %r" % (e, seen))
    print("%d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
