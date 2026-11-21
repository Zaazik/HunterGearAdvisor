"""Generates Game/ProcData.lua: the damage procs of gear, as the Forever DB2 states them, which Items.Get links to the
procs Parse reads from an item's tooltip (Core/Parse.lua Lines: "Chance on hit:" lines and the "Equip:" lines of
EQUIP_PROC_PATTERNS) and Score prices (Score.ProcRate, Score.ProcValue).

Sources (all read-only, Forever DB2 build 70888 exports):
  * ItemXItemEffect / ItemEffect: an item's effects; TriggerType 1 is "Equip:" (an equip aura whose proc casts the
    damage), 2 "Chance on hit:" (the damage spell itself).
  * SpellEffect (DifficultyID 0): an equip spell's Effect 6 APPLY_AURA with aura 42 A_PROC_TRIGGER_SPELL names the spell
    its proc casts (EffectTriggerSpell); a damage spell's Effect 2 SCHOOL_DAMAGE on an enemy (ImplicitTarget other than
    1, the caster) gives the direct damage: EffectBasePointsF and Variance; its Effect 6 APPLY_AURA with aura 3
    A_PERIODIC_DAMAGE on an enemy the damage over time: EffectBasePointsF a tick, EffectAuraPeriod (ms) between ticks.
  * SpellMisc DurationIndex / SpellDuration (Duration, ms) of a damage spell with a damage over time: the aura's duration,
    its ticks the duration over the period (wowsims sim/core/spelldata/resolve_aura.go:78-99 DotConfig: NumberOfTicks =
    the duration over the period); SpellMisc Attributes_8 0x200 (PERIODIC_CAN_CRIT, wowsims sim/core/spelldata/
    spell.go:368-377 TickOutcome): whether its ticks crit; SpellAuraOptions (DifficultyID 0) of the damage spell:
    CumulativeAura, its stacks.
  * SpellAuraOptions (DifficultyID 0) of the equip spell: ProcTypeMask_0 (the hits that roll it), ProcChance,
    SpellProcsPerMinuteID, ProcCategoryRecovery (the internal cooldown in ms); SpellProcsPerMinute: BaseProcRate.
  * SpellMisc (DifficultyID 0) of the damage spell: SchoolMask, Attributes_2 (0x20000000 ATTR_EX_2_CANT_CRIT, wowsims
    sim/core/dbcenums/attributes.go:28, tools/database/dbc/spell.go:90-96).
  * SpellCategories (DifficultyID 0) of the damage spell: DefenseType (0 none, 1 magic, 2 melee, 3 ranged); a spell
    with no row has DefenseType 0 (wowsims sim/common/shared/shared_utils.go:76-90 damageDefenseType then rolls the
    melee table for the physical school and the spell table for any other).
  * Spell (Description_lang, enUS and ruRU) of the spell the tooltip shows (the ItemEffect's SpellID): the school
    words, checked against the SchoolMask (below).
  * ItemSparse (Display_lang) and SpellName: names for the comments only.
  * wowsims/forever's override data, read as data (never run): tools/database/overrides/weapon_procs.go `WeaponProcs`, a
    chance-on-hit item's procs per minute by (ItemID, SpellID: the item effect's spell), each with its Source
    ("EV-<n>", a measurement on Forever, or "vanilla-carryover" / "tbc-carryover"); tools/database/overrides/
    spell_overrides.go, the PPM and ProcChancePct rows of a spell (an equip aura's proc rate the game files do not state:
    SpellProcsPerMinuteID 0, the ProcChance column at its 100 or 101 sentinel), each with its Source. wowsims makes no
    rate up past them (docs/rulings/R-0046, R-0047: a proc whose entry states no rate registers nothing). The other
    override files hold no rate of a gear proc HGA prices: enchant_procs.go (a permanent enchant's proc; HGA prices no
    enchant proc), hand_triggers.go and extra_spells.go (trigger edges and extra spells). spell_overrides.go's
    `VersusBonuses`: the factor a proc spell deals against some creature types or families, which only its tooltip
    names (below).
  * wowsims/forever's generated proc registrations and spell store, read as data (never run):
    sim/common/forever/stat_bonus_procs_auto_gen.go, each `// trigger <id> (<its rate>, ...)` line above a
    shared.NewSpellDataDamageProc registration and its ItemVariant rows (a registration commented out registers nothing);
    sim/core/spelldata/spells_auto_gen.go, the ProcChanceSource of a trigger's row (below).

The damage of an entry is wowsims' spread of the effect (sim/core/spelldata/effect.go:125-140, 159-165, 178-186):
with Variance 0 the bounds are the floored base points and the mean the base points; with a Variance the bounds are
the base points less and plus half the Variance of their absolute value, in float32, each rounded half to even, the
low end floored and the high end ceiled; the mean is the base points for a spell school other than physical (its whole
amount rolls once, DirectVariance) and the bounds' midpoint for the physical school. With Variance 0 (min == max) the
tooltip shows one number, no range Parse reads: Items.LinkProcs links such an entry by the item's one effect line of its
kind that Parse leaves not counted and that states the amount as damage (raid-mode design 24.2).

The damage over time of an entry (raid-mode design 17.4; U2 = (a), DoT procs as wowsims prices them,
sim/common/shared/shared_utils.go:724-819 spellDataProcDamageSpell): dot = { tick, period (ms), ticks, canCrit }; an entry
with a damage over time and no direct damage has avg, min and max 0 (Items.LinkProcs links it by the item's one effect
line of its kind that Parse leaves not counted, the tooltip forms of a damage over time being many: "$s1 Nature damage
every $t1 sec for $d", "bleed for $o1 damage over $d").

A proc on every matching hit (raid-mode design 25.3): wowsims rolls an equip aura whose ProcChance column reads 100 or 101
and whose tooltip states no chance (its store's ProcChanceSource ProcChanceAlways, sim/core/spelldata/spelldata.go:
182-186, decided by wowsims' generator from the tooltip, tools/database/spelldata_hints.go:87-127) at StatedChance 1
(sim/core/spelldata/resolve_proc.go:187-199): on every hit of its mask, an internal cooldown aside. Its generated file
labels such a registration "every time" (stat_bonus_procs_auto_gen.go:4077-4081 Hurricane 2824). An equip entry of an
item an active "every time" damage registration names, with its trigger, gets always = true; its row's ProcChance is
100 or 101 and it states no procs per minute (a stated rate is the manager wowsims takes instead, resolve_proc.go:203-209
fillProcChance: a registration of a trigger with one is listed, and its entry keeps its ppm).

A versus bonus (raid-mode design 25.2): wowsims multiplies a proc's damage, direct and periodic, by the factor of its
trigger's VersusBonuses row against a target of the row's mob types or families (sim/common/shared/shared_utils.go:678-690
applySpellDataDamageProc: damageConfig.VersusBonus = ItemVersusBonus(..., trigger); sim/core/spell_result.go:442-445
CalcDamage and 464-467 CalcPeriodicDamage: baseDamage *= spell.VersusBonus.Against(target); sim/core/versus_effects.go:
18-24 Against). The factor is the row's Multiplier, else the base points of the trigger's effect of the row's EffectIndex
(sim/core/spelldata/versus.go:18-33). An entry whose trigger is a row's spell gets versus = { factor, types } with the
row's mob types as HGA's creature types (MOB_TYPES; Score.ProcValue prices them by the mode's share of each type,
Model.TargetShare). A row's creature families stay out: HGA models the creature types alone (Model.CREATURE_TYPES), and
its targets name no family (the raid boss a dragonkin, wowsims ui/specs/hunter/dps/defaults.siml:65; levelling a share of
each type). Gloves of Holy Might 867 is wowsims' own code (sim/common/forever/items_armor.go:97-125), its factor on the
damage spell 1325229, which is the trigger of 867's chance-on-hit entry here.

Left out (no entry; an item's proc that Parse reads then stays unlinked, Items.Get): an equip spell with no aura 42, a
proc or chance-on-hit spell with neither direct school damage nor a periodic damage aura on an enemy (a stat buff, a
heal: W1 stats-gear-4).

Skips (printed, and listed in the generated file's header; an item's proc that Parse reads stays unlinked): a damage
effect, direct or periodic, whose amount gains points a level (EffectRealPointsPerLevel): the amount the tooltip shows is
the one at the caster's level within the spell's SpellLevels range, which an entry of one mean cannot hold; an equip aura
with ProcTypeMask_0's hand bits (0x400000 the main-hand weapon swing, 0x800000 the off hand's: wowsims
sim/core/proc_types.go:211-221 keeps the melee hits of the one hand a mask names), which Score.ProcRate does not read (it
reads the hit bits of ProcTypeMask_0: 0x4, 0x10, 0x40, 0x100, 0x10000) and which no equip aura of build 70888 holds.

The main hand only (raid-mode design 26.2): an equip aura whose ProcTypeMask_1 holds 0x20 (PROC_FLAG_2_MAIN_HAND_ONLY)
hears the main hand's melee hits alone, wowsims dropping the off hand's melee bits from its mask whatever slot the item
sits in (sim/core/proc_types.go:222-224; the listener takes the row's decoded mask, sim/core/spelldata/resolve_proc.go:
32-51): its entry has mainHand = true, which Score.ProcRate reads (the off hand's white swings out). Build 70888:
Iceblade Hacker 13952 (1298413), Warblade of Caer Darrow 13982 (1298500), Dreadfrost Saber 274603 (1294939), each
wowsims' "every time" registration of ProcMaskMeleeMHAuto | ProcMaskMeleeMHSpecial
(stat_bonus_procs_auto_gen.go:4423-4437, 4677-4683).

A rate from wowsims' override data goes onto the entry with its source: a chance-on-hit entry takes its item's
WeaponProcs row of its spell (ppm, source); an equip aura whose row states no rate (ppm 0 and the ProcChance column 0,
100 or 101) takes its item's WeaponProcs row of its spell (an equip trigger: Heartseeking Crossbow 13040) or its spell's
PPM row (ppm, source) or ProcChancePct row (chance, source). The rows no entry takes (an
item or spell with no written entry: a proc of no direct damage, a skip) are counted in the generated file's header.

Checks (the script stops instead of writing doubtful data):
  * an equip spell has at most one aura 42 effect, exactly one SpellAuraOptions row of DifficultyID 0 and a
    SpellProcsPerMinuteID of 0 or a SpellProcsPerMinute row; a written equip entry has no bit of ProcTypeMask_1 but 0x20
    (the main hand only, above);
  * a damage spell has at most one Effect 2 on an enemy, at most one aura 3 effect on an enemy, exactly one SpellMisc row
    and at most one SpellCategories row of DifficultyID 0, and a DefenseType of 0 to 3; beside a damage over time, a direct
    damage of a mean above 0 (an entry with a damage over time and avg 0 has no direct damage);
  * a damage over time has a period above 0 and no Variance; its spell a duration of one SpellDuration row that gains
    nothing a level (DurationPerLevel 0, MaxDuration the Duration) and is a whole number of periods, and at most one
    SpellAuraOptions row of DifficultyID 0 with a CumulativeAura of at most 1 (no damage spell of an item proc stacks in
    build 70888);
  * the school words of the shown spell's enUS and ruRU descriptions (Parse's rule for an unlinked proc, Core/Parse.lua
    procDamage: enUS "<Arcane|Fire|Frost|Holy|Nature|Shadow> damage" magic, "damage" with another word or none physical;
    ruRU "ед. урона от <word>" magic, "ед. урона" and "ед. <word> урона" physical) of an entry with a direct damage (the
    damage Parse reads, a range; a damage over time alone has none Parse reads, so its words, such as "Corrupts the target,
    causing $o1 damage" or "ед. урона от кровотечения", are not checked) agree with the SchoolMask (physical
    when it holds the physical bit 1, as wowsims' SpellSchool.Matches reads it), but for the descriptions
    TEXT_SCHOOL_MISMATCHES lists, which the rule misreads (each must still disagree, and every listed one occur); a
    description with no such phrase is not checked and is counted in the output;
  * one entry per item, kind and damage spell;
  * an override row is read whole (ItemID / SpellID, PPM or Field and Value, Source), a WeaponProcs row names one
    (item, spell) once, and no override row lands on an equip aura whose row states a rate itself (wowsims' generator
    refuses that too, spell_overrides.go: "fails when ...");
  * a VersusBonuses row has its SpellID, its Source and a mob type or a family, each mob type one of MOB_TYPES; a row of
    mob types finds its factor (the Multiplier, else exactly one SpellEffect of its EffectIndex) above 1, and no entry gets
    two rows;
  * an active "every time" registration's trigger has a spell store row whose ProcChanceSource is ProcChanceAlways, and
    the equip entry it marks has a ProcChance of 100 or 101 and no override rate.

Usage:
  python -I tools/gen_proc_data.py --db2 <dir with SpellEffect.csv, SpellMisc.csv, SpellAuraOptions.csv, Spell.csv,
      SpellName.csv, ItemSparse.csv> --ru <db2_ru Spell.csv> --gear <dir with ItemEffect.csv, ItemXItemEffect.csv,
      SpellCategories.csv, SpellDuration.csv> --ppm <SpellProcsPerMinute.csv> --overrides <wowsims tools/database/overrides>
      --registrations <wowsims sim/common/forever/stat_bonus_procs_auto_gen.go>
      --store <wowsims sim/core/spelldata/spells_auto_gen.go> --out Game/ProcData.lua
"""
import argparse
import collections
import csv
import math
import os
import re
import struct

TRIGGER_EQUIP, TRIGGER_ON_HIT = 1, 2
E_SCHOOL_DAMAGE, E_APPLY_AURA = 2, 6
A_PERIODIC_DAMAGE, A_PROC_TRIGGER_SPELL = 3, 42
# SpellMisc Attributes_8: SPELL_ATTR8_PERIODIC_CAN_CRIT (wowsims sim/core/spelldata/spell.go PeriodicCanCrit)
ATTR8_PERIODIC_CAN_CRIT = 0x200
TARGET_UNIT_CASTER = 1
ATTR_EX_2_CANT_CRIT = 0x20000000
# ProcTypeMask word 0: PROC_FLAG_MAIN_HAND_WEAPON_SWING 0x400000, PROC_FLAG_OFF_HAND_WEAPON_SWING 0x800000 (wowsims
# sim/core/dbcenums/proc_flags.go)
HAND_BITS = 0x400000 | 0x800000
MAIN_HAND_ONLY = 0x20  # ProcTypeMask word 1: PROC_FLAG_2_MAIN_HAND_ONLY (an entry's mainHand)
SCHOOL_PHYSICAL = 1
MAGIC_WORDS_EN = {"Arcane", "Fire", "Frost", "Holy", "Nature", "Shadow"}
# The descriptions the school-word rule misreads against their damage spell's SchoolMask (build 70888), each checked to
# still read so: (item, shown spell, locale) -> the description. The entries stand (the SchoolMask is the DB2's); the
# rule is what an unlinked proc is priced by (Items.Get), an approximation (raid-mode design A14).
TEXT_SCHOOL_MISMATCHES = {
    # The Lobotomizer: damage spell 1290950, SchoolMask 32 (Shadow), no school word
    (19324, 1290950, "en"): "Wounds the target for $s1 damage and increases the casting time of all spells by $s2% for $d.",
    (19324, 1290950, "ru"): "Наносит цели $s1 ед. урона и увеличивает время применения ею заклинаний на $s2%. Время действия – $d.",
    # 461151, SchoolMask 4 (Fire): a ring of fire, no school word on the damage
    (227934, 461151, "en"): "Envelops the caster with a Fire shield for 15 sec and shoots a ring of fire dealing $s1 damage to all nearby enemies.",
    (227934, 461151, "ru"): "Окружает себя огненным щитом на 15 сек. и выпускает кольцо огня, наносящее $s1 ед. урона ближайшим противникам.",
    # 465412 -> 465411, SchoolMask 2 (Holy): "holy" in lower case
    (229749, 465412, "en"): "Adds $465411s1 holy damage to your melee attacks.",
    (229966, 465412, "en"): "Adds $465411s1 holy damage to your melee attacks.",
    (230003, 465412, "en"): "Adds $465411s1 holy damage to your melee attacks.",
    # 468671 -> 468670, SchoolMask 8 (Nature): ruRU names no school
    (231387, 468671, "ru"): "Заклинания, наносящие непериодический урон, с некоторой вероятностью могут поразить до $s2 целей, нанося им $s1 ед. урона.",
    # 1231550 -> 1231549, SchoolMask 2 (Holy): "holy" in lower case
    (240920, 1231550, "en"): "Adds $1231549s1 holy damage to your melee attacks.",
    # 1282503, SchoolMask 10 (Holy and Fire): "Holystorm"
    (267369, 1282503, "en"): "Sear the target with a vortex of blazing wind, dealing $s1 Holystorm damage. Deals $s2 times as much damage to Wolves and Worgen.",
    # 278990: shown 1309320, damage spell 1309321, SchoolMask 36 (Shadow and Fire): "Shadowflame"
    (278990, 1309320, "en"): "Harmful spell casts against Demons have a chance to deal $1309321s1 Shadowflame damage.",
    # 280573: shown 1309322, damage spell 1309323, SchoolMask 36 (Shadow and Fire): "Shadowflame"
    (280573, 1309322, "en"): "Melee and ranged attacks against Demons have a chance to deal $1309321s1 Shadowflame damage.",
    # 282700: 1314274, SchoolMask 32 (Shadow): a shadow bolt volley, no school word on the damage
    (282700, 1314274, "en"): "Unleash a shadow bolt volley at all nearby targets, inflicting $s1 damage to each enemy struck.",
    (282700, 1314274, "ru"): "Выпускает залп стрел Тьмы в ближайшие цели, нанося каждому пораженному противнику $s1 ед. урона.",
    # 8708: 1317432, SchoolMask 1 (Physical) while the texts name Fire
    (8708, 1317432, "en"): "Deal $s1 Fire damage. Deals $s2 times as much damage to Earth Elementals, Fire Elementals, and Mountain Giants.",
    (8708, 1317432, "ru"): "Наносит $s1 ед. урона от огня. Против элементалей земли, элементалей огня и горных великанов урон увеличивается в $s2 $lраз:раза:раз;.",
    # 6953: 1322218, SchoolMask 6 (Holy and Fire): "Holyfire"
    (6953, 1322218, "en"): "Ignite the target in the flames of the Great Forge, dealing $s1 Holyfire damage. Deals $s2 times as much damage to Fire Elementals and Earth Elementals.",
}
# a spell value token of a description: $s1, $29640s1, $m1, $o2 ...
TOKEN = r"\$\d*[A-Za-z]\d+"
DAMAGE_EN = re.compile(TOKEN + r"\s+(?:([A-Za-z]+)\s+)?[Dd]amage")
DAMAGE_RU = re.compile(TOKEN + r"\s+ед\.\s+(?:[^\s\d]+\s+)?урона(\s+от\s)?")


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def f32(x):
    return struct.unpack("f", struct.pack("f", x))[0]


def round_half_even(x):
    return float(round(x))  # Python's round is half to even, as Go's math.RoundToEven


def spread(base_points, variance, physical):
    """(min, max, mean) of an effect's amount as wowsims' spread and MeanAt (module docstring)."""
    exact = f32(base_points)
    if variance == 0:
        whole = math.floor(exact)
        return whole, whole, exact
    base = f32(base_points)
    side = f32(f32(abs(base_points)) * f32(variance) / 2)
    # wowsims adds the per-level gain to each rounded end and floors the low end, ceils the high one; every written entry
    # has no gain (a level-scaled damage is a skip), so the rounded ends are the bounds
    low = round_half_even(f32(base - side))
    high = round_half_even(f32(base + side))
    mean = (low + high) / 2 if physical else exact
    return low, high, mean


def text_school(text, pattern, magic):
    """'magic' / 'physical' by the first damage phrase of a description, None when it has none."""
    if not text:
        return None
    m = pattern.search(text)
    if not m:
        return None
    return "magic" if magic(m) else "physical"


def school_en(text):
    return text_school(text, DAMAGE_EN, lambda m: m.group(1) in MAGIC_WORDS_EN)


def school_ru(text):
    return text_school(text, DAMAGE_RU, lambda m: m.group(1) is not None)


class Tables:
    """The DB2 rows the entries read, by spell id (DifficultyID 0)."""

    def __init__(self, spell_effects, aura_options, ppm, misc, categories, durations, en, ru):
        self.spell_effects = spell_effects  # spell -> [SpellEffect rows]
        self.aura_options = aura_options    # spell -> [SpellAuraOptions rows]
        self.ppm = ppm                      # SpellProcsPerMinute ID -> BaseProcRate
        self.misc = misc                    # spell -> [SpellMisc rows]
        self.categories = categories        # spell -> [SpellCategories rows]
        self.durations = durations          # SpellDuration ID -> its row
        self.en, self.ru = en, ru           # spell -> Description_lang


def dot_of(periodic, misc, t, item_id, damage_spell):
    """The dot of a damage spell's aura 3 effect (module docstring): { tick, period, ticks, canCrit }; stops (SystemExit)
    on a row the checks refuse."""
    period = int(periodic["EffectAuraPeriod"])
    if period <= 0:
        raise SystemExit("item %d: spell %d's periodic damage has period %d" % (item_id, damage_spell, period))
    if float(periodic["Variance"]) != 0:
        raise SystemExit("item %d: spell %d's periodic damage has Variance %s" % (item_id, damage_spell, periodic["Variance"]))
    index = int(misc["DurationIndex"])
    d = t.durations.get(index)
    if d is None:
        raise SystemExit("item %d: spell %d names SpellDuration %d, which has no row" % (item_id, damage_spell, index))
    duration = int(d["Duration"])
    if duration <= 0 or int(d["DurationPerLevel"]) != 0 or int(d["MaxDuration"]) != duration:
        raise SystemExit("item %d: spell %d's SpellDuration %d is no fixed duration: %r" % (item_id, damage_spell, index, dict(d)))
    if duration % period != 0:
        raise SystemExit("item %d: spell %d lasts %d ms, no whole number of its %d ms periods" % (item_id, damage_spell, duration, period))
    opts = t.aura_options.get(damage_spell, [])
    if len(opts) > 1:
        raise SystemExit("item %d: spell %d has %d SpellAuraOptions rows of DifficultyID 0" % (item_id, damage_spell, len(opts)))
    if opts and int(opts[0]["CumulativeAura"]) > 1:
        raise SystemExit("item %d: spell %d's periodic damage stacks (CumulativeAura %s)" % (item_id, damage_spell, opts[0]["CumulativeAura"]))
    return {"tick": float(periodic["EffectBasePointsF"]), "period": period, "ticks": duration // period,
            "canCrit": (int(misc["Attributes_8"]) & ATTR8_PERIODIC_CAN_CRIT) != 0}


def entry_for(trigger_type, spell, t, item_id, mismatches_seen):
    """The ProcData entry of one ItemEffect (TriggerType, SpellID), None when it is left out, or the string "level" for
    a level-scaled damage, "hands" for an equip aura with ProcTypeMask_0's hand bits (Skips; module docstring); stops
    (SystemExit) on a
    chain it cannot follow. The entry also carries the school read from the shown spell's descriptions ("en", "ru":
    'magic', 'physical' or None) for the check; each TEXT_SCHOOL_MISMATCHES key it meets goes into mismatches_seen."""
    if trigger_type == TRIGGER_EQUIP:
        auras = [e for e in t.spell_effects.get(spell, [])
                 if int(e["Effect"]) == E_APPLY_AURA and int(e["EffectAura"]) == A_PROC_TRIGGER_SPELL]
        if not auras:
            return None
        if len(auras) > 1:
            raise SystemExit("item %d: equip spell %d has %d proc trigger auras" % (item_id, spell, len(auras)))
        damage_spell = int(auras[0]["EffectTriggerSpell"])
        opts = t.aura_options.get(spell, [])
        if len(opts) != 1:
            raise SystemExit("item %d: equip spell %d has %d SpellAuraOptions rows of DifficultyID 0"
                             % (item_id, spell, len(opts)))
        o = opts[0]
        ppm_id = int(o["SpellProcsPerMinuteID"])
        if ppm_id != 0 and ppm_id not in t.ppm:
            raise SystemExit("item %d: equip spell %d names SpellProcsPerMinute %d, which has no row" % (item_id, spell, ppm_id))
        entry = {"kind": "equip", "mask": int(o["ProcTypeMask_0"]), "chance": int(o["ProcChance"]),
                 "ppm": t.ppm[ppm_id] if ppm_id else 0.0, "icd": int(o["ProcCategoryRecovery"]),
                 "mask1": int(o["ProcTypeMask_1"])}
    elif trigger_type == TRIGGER_ON_HIT:
        damage_spell = spell
        entry = {"kind": "hit"}
    else:
        raise SystemExit("item %d: TriggerType %d is no proc" % (item_id, trigger_type))
    damage = [e for e in t.spell_effects.get(damage_spell, [])
              if int(e["Effect"]) == E_SCHOOL_DAMAGE and int(e["ImplicitTarget_0"]) != TARGET_UNIT_CASTER]
    periodic = [e for e in t.spell_effects.get(damage_spell, [])
                if int(e["Effect"]) == E_APPLY_AURA and int(e["EffectAura"]) == A_PERIODIC_DAMAGE
                and int(e["ImplicitTarget_0"]) != TARGET_UNIT_CASTER]
    if not damage and not periodic:
        return None
    if len(damage) > 1:
        raise SystemExit("item %d: spell %d deals school damage in %d effects" % (item_id, damage_spell, len(damage)))
    if len(periodic) > 1:
        raise SystemExit("item %d: spell %d applies %d periodic damage auras" % (item_id, damage_spell, len(periodic)))
    for e in damage + periodic:
        if float(e["EffectRealPointsPerLevel"]) != 0:
            return "level"
    misc = t.misc.get(damage_spell, [])
    if len(misc) != 1:
        raise SystemExit("item %d: spell %d has %d SpellMisc rows of DifficultyID 0" % (item_id, damage_spell, len(misc)))
    cats = t.categories.get(damage_spell, [])
    if len(cats) > 1:
        raise SystemExit("item %d: spell %d has %d SpellCategories rows of DifficultyID 0" % (item_id, damage_spell, len(cats)))
    defense = int(cats[0]["DefenseType"]) if cats else 0
    if defense not in (0, 1, 2, 3):
        raise SystemExit("item %d: spell %d has DefenseType %d" % (item_id, damage_spell, defense))
    school = int(misc[0]["SchoolMask"])
    if damage:
        d = damage[0]
        low, high, mean = spread(float(d["EffectBasePointsF"]), float(d["Variance"]), school == SCHOOL_PHYSICAL)
        if periodic and mean <= 0:
            raise SystemExit("item %d: spell %d's direct damage beside its damage over time has mean %s" % (item_id, damage_spell, mean))
    else:
        low = high = mean = 0
    entry.update({"trigger": spell, "spell": damage_spell, "avg": mean, "min": low, "max": high, "school": school,
                  "defense": defense, "crit": (int(misc[0]["Attributes_2"]) & ATTR_EX_2_CANT_CRIT) == 0,
                  "en": school_en(t.en.get(spell)), "ru": school_ru(t.ru.get(spell))})
    if periodic:
        entry["dot"] = dot_of(periodic[0], misc[0], t, item_id, damage_spell)
    # the hand bits (wowsims sim/core/proc_types.go:211-224): word 1's main-hand-only the entry's mainHand (module
    # docstring); word 0's main-hand / off-hand weapon swing, which HGA does not read, a skip; any other bit of word 1 stops
    if entry["kind"] == "equip":
        if entry["mask"] & HAND_BITS:
            return "hands"
        if entry["mask1"] & ~MAIN_HAND_ONLY:
            raise SystemExit("item %d: equip spell %d has ProcTypeMask_1 %d" % (item_id, spell, entry["mask1"]))
        if entry["mask1"] & MAIN_HAND_ONLY:
            entry["mainHand"] = True
        del entry["mask1"]
    if not damage:
        # a damage over time alone: no damage of it Parse reads (module docstring, Checks), so its words go unchecked
        entry["en"] = entry["ru"] = None
        return entry
    want = "physical" if school & SCHOOL_PHYSICAL else "magic"
    for lang, text in (("en", t.en.get(spell)), ("ru", t.ru.get(spell))):
        key = (item_id, spell, lang)
        if key in TEXT_SCHOOL_MISMATCHES:
            if text != TEXT_SCHOOL_MISMATCHES[key] or entry[lang] is None or entry[lang] == want:
                raise SystemExit("item %d: spell %d's %s description is not the misread one TEXT_SCHOOL_MISMATCHES cites: %r"
                                 % (item_id, spell, lang, text))
            mismatches_seen.add(key)
        elif entry[lang] is not None and entry[lang] != want:
            raise SystemExit("item %d: spell %d's %s description reads %s damage, its damage spell %d has SchoolMask %d"
                             % (item_id, spell, lang, entry[lang], damage_spell, school))
    return entry


GO_STRING = r'"(?:[^"\\]|\\.)*"'
# wowsims' proto.MobType names (proto/common.proto:544-554) to HGA's creature types (Core/Model.lua Model.CREATURE_TYPES)
MOB_TYPES = {"Beast": "BEAST", "Demon": "DEMON", "Dragonkin": "DRAGONKIN", "Elemental": "ELEMENTAL", "Giant": "GIANT",
             "Humanoid": "HUMANOID", "Mechanical": "MECHANICAL", "Undead": "UNDEAD"}


def go_blocks(text, var):
    """The { ... } literals of the Go slice `var` in text (wowsims' override files: one struct literal a row)."""
    start = text.find("var %s = " % var)
    if start < 0:
        raise SystemExit("no var %s in the override file" % var)
    i = text.index("{", start)
    blocks, depth, cur = [], 0, None
    while i < len(text):
        ch = text[i]
        if ch == '"':
            m = re.match(GO_STRING, text[i:])
            if cur is not None:
                cur.append(m.group(0))
            i += len(m.group(0))
            continue
        if text.startswith("//", i):
            i = text.index("\n", i)
            continue
        if ch == "{":
            depth += 1
            if depth == 2:
                cur = []
                i += 1
                continue
        elif ch == "}":
            depth -= 1
            if depth == 1:
                blocks.append("".join(cur))
                cur = None
                i += 1
                continue
            if depth == 0:
                break
        if cur is not None:
            cur.append(ch)
        i += 1
    return blocks


def go_field(block, name, pattern):
    m = re.search(r"\b%s:\s*(%s)" % (name, pattern), block)
    return m.group(1) if m else None


def read_weapon_procs(text):
    """WeaponProcs rows: [{item, spell, ppm, source}]; a row missing one of them stops."""
    rows = []
    for b in go_blocks(text, "WeaponProcs"):
        item, spell, ppm = go_field(b, "ItemID", r"\d+"), go_field(b, "SpellID", r"\d+"), go_field(b, "PPM", r"[\d.]+")
        source = go_field(b, "Source", GO_STRING)
        if None in (item, spell, ppm, source):
            raise SystemExit("a WeaponProcs row without its ItemID, SpellID, PPM or Source: %r" % b[:120])
        rows.append({"item": int(item), "spell": int(spell), "ppm": float(ppm), "source": source[1:-1]})
    return rows


def read_spell_overrides(text):
    """The PPM and ProcChancePct rows of the spell overrides (`Spells`): [{spell, field, value, source}]."""
    rows = []
    for b in go_blocks(text, "Spells"):
        field = go_field(b, "Field", r"\w+")
        if field not in ("PPM", "ProcChancePct"):
            continue
        spell, value, source = go_field(b, "SpellID", r"\d+"), go_field(b, "Value", r"[\d.]+"), go_field(b, "Source", GO_STRING)
        if None in (spell, value, source):
            raise SystemExit("a %s override row without its SpellID, Value or Source: %r" % (field, b[:120]))
        rows.append({"spell": int(spell), "field": field, "value": float(value), "source": source[1:-1]})
    return rows


def read_every_time(text):
    """The "every time" damage proc registrations of wowsims' stat_bonus_procs_auto_gen.go: [{trigger, items, active}]
    (module docstring); a registration of another constructor is not one."""
    regs = []
    for m in re.finditer(r"// trigger (\d+) \(every time,[^\n]*\n", text):
        rest = text[m.end():]
        end = rest.find("})")
        if end < 0:
            raise SystemExit("an every-time registration of trigger %s without its end" % m.group(1))
        block = rest[:end]
        first = block.lstrip()
        active = first.startswith("shared.NewSpellDataDamageProc(")
        if not active and not first.startswith("// shared.NewSpellDataDamageProc("):
            continue
        items = [int(i) for i in re.findall(r"ItemID: (\d+)", block)]
        if not items:
            raise SystemExit("an every-time registration of trigger %s names no item" % m.group(1))
        regs.append({"trigger": int(m.group(1)), "items": items, "active": active})
    return regs


def store_sources(text, spells):
    """The ProcChanceSource of each spell of `spells` in wowsims' spell store (spells_auto_gen.go): {spell: name}, the
    column's when the row names none (the store's default, ProcChanceColumn); a spell with no row is absent."""
    out = {}
    for spell in spells:
        m = re.search(r"\n\t\{ID: %d, [^\n]*" % spell, text)
        if m:
            src = re.search(r"ProcChanceSource: (\w+)", m.group(0))
            out[spell] = src.group(1) if src else "ProcChanceColumn"
    return out


def attach_always(out, regs, sources):
    """Marks always = True the equip entries an active "every time" registration names (module docstring). Returns (the
    (item, trigger) pairs marked, the pairs with no equip entry here, the pairs whose entry states a procs per minute)."""
    marked, missing, stated = [], [], []
    for r in regs:
        if not r["active"]:
            continue
        if sources.get(r["trigger"]) != "ProcChanceAlways":
            raise SystemExit("the every-time registration of trigger %d: its store row's ProcChanceSource is %s"
                             % (r["trigger"], sources.get(r["trigger"])))
        for item_id in r["items"]:
            hits = [e for e in out.get(item_id, []) if e["kind"] == "equip" and e["trigger"] == r["trigger"]]
            if not hits:
                missing.append((item_id, r["trigger"]))
                continue
            for e in hits:
                if e["ppm"] > 0:
                    stated.append((item_id, r["trigger"]))
                    continue
                if e["chance"] not in (100, 101) or "source" in e:
                    raise SystemExit("item %d: the every-time trigger %d has ProcChance %s and source %s"
                                     % (item_id, r["trigger"], e["chance"], e.get("source")))
                e["always"] = True
                marked.append((item_id, r["trigger"]))
    return marked, missing, stated


def read_versus_bonuses(text):
    """The VersusBonuses rows of the spell overrides: [{spell, index, multiplier, types, families, source}] (module
    docstring, Checks)."""
    rows = []
    for b in go_blocks(text, "VersusBonuses"):
        spell, source = go_field(b, "SpellID", r"\d+"), go_field(b, "Source", GO_STRING)
        index, mult = go_field(b, "EffectIndex", r"\d+"), go_field(b, "Multiplier", r"[\d.]+")
        types = re.findall(r"proto\.MobType_MobType(\w+)", b)
        families = re.findall(r"proto\.CreatureFamily_CreatureFamily(\w+)", b)
        if spell is None or source is None or not (types or families):
            raise SystemExit("a VersusBonuses row without its SpellID, Source or a mob type or family: %r" % b[:120])
        for ty in types:
            if ty not in MOB_TYPES:
                raise SystemExit("a VersusBonuses row of spell %s names mob type %s, no creature type of HGA" % (spell, ty))
        rows.append({"spell": int(spell), "index": int(index or 0), "multiplier": float(mult or 0),
                     "types": [MOB_TYPES[ty] for ty in types], "families": families, "source": source[1:-1]})
    return rows


def attach_versus(out, rows, t):
    """Puts the mob types of wowsims' VersusBonuses rows onto the written entries whose trigger is the row's spell
    (module docstring): versus = {factor, types}. Returns (the spells of the rows of mob types some entry took, the
    spells of the rows of families alone, the spells of the rows of mob types no entry took)."""
    took, families_only, unused = [], [], []
    for r in rows:
        if not r["types"]:
            families_only.append(r["spell"])
            continue
        if r["multiplier"] > 0:
            factor = r["multiplier"]
        else:
            effs = [e for e in t.spell_effects.get(r["spell"], []) if int(e["EffectIndex"]) == r["index"]]
            if len(effs) != 1:
                raise SystemExit("the VersusBonuses row of spell %d: %d SpellEffect rows of its EffectIndex %d"
                                 % (r["spell"], len(effs), r["index"]))
            factor = float(effs[0]["EffectBasePointsF"])
        if factor <= 1:
            raise SystemExit("the VersusBonuses row of spell %d: a factor of %s" % (r["spell"], factor))
        hit = False
        for item_id in sorted(out):
            for e in out[item_id]:
                if e["trigger"] == r["spell"]:
                    if "versus" in e:
                        raise SystemExit("item %d: two VersusBonuses rows of spell %d" % (item_id, r["spell"]))
                    e["versus"] = {"factor": factor, "types": list(r["types"])}
                    hit = True
        (took if hit else unused).append(r["spell"])
    return took, families_only, unused


def attach_overrides(out, weapon_procs, spell_overrides):
    """Puts wowsims' override rates onto the written entries (module docstring); returns the rows no entry took."""
    unused = []
    seen = set()
    for r in weapon_procs:
        key = (r["item"], r["spell"])
        if key in seen:
            raise SystemExit("WeaponProcs names item %d spell %d twice" % key)
        seen.add(key)
        hits = [e for e in out.get(r["item"], []) if e["trigger"] == r["spell"]]
        if not hits:
            unused.append(("weapon", r["item"], r["spell"]))
            continue
        for e in hits:
            if e["kind"] == "equip" and (e["ppm"] > 0 or 1 <= e["chance"] <= 99):
                raise SystemExit("item %d: spell %d states a rate of its own, and WeaponProcs gives it one" % key)
            e["ppm"], e["source"] = r["ppm"], r["source"]
    for r in spell_overrides:
        took = False
        for item_id in sorted(out):
            for e in out[item_id]:
                if e["kind"] != "equip" or e["trigger"] != r["spell"]:
                    continue
                if e["ppm"] > 0 or 1 <= e["chance"] <= 99:
                    raise SystemExit("item %d: spell %d states a rate of its own, and wowsims overrides its %s"
                                     % (item_id, r["spell"], r["field"]))
                if r["field"] == "PPM":
                    e["ppm"] = r["value"]
                else:
                    e["chance"] = r["value"]
                e["source"] = r["source"]
                took = True
        if not took:
            unused.append(("spell", r["spell"], r["field"]))
    return unused


def lua_num(v):
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    return ("%.4f" % v).rstrip("0")


def add_entry(out, item_id, entry):
    """Appends a written entry to out[item_id]; stops on a second entry of the same kind and damage spell for the item
    (one entry per item, kind and damage spell: Items.Get links a parsed proc to the one entry of its kind and mean)."""
    for other in out[item_id]:
        if other["kind"] == entry["kind"] and other["spell"] == entry["spell"]:
            raise SystemExit("item %d has two %s procs of spell %d" % (item_id, entry["kind"], entry["spell"]))
    out[item_id].append(entry)


def check_mismatches_seen(mismatches_seen):
    """Stops when TEXT_SCHOOL_MISMATCHES lists a description no written entry met (entry_for records each it meets)."""
    unseen = set(TEXT_SCHOOL_MISMATCHES) - mismatches_seen
    if unseen:
        raise SystemExit("TEXT_SCHOOL_MISMATCHES lists descriptions no written entry has: %s" % sorted(unseen))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db2", required=True)
    ap.add_argument("--ru", required=True)
    ap.add_argument("--gear", required=True)
    ap.add_argument("--ppm", required=True)
    ap.add_argument("--overrides", required=True)
    ap.add_argument("--registrations", required=True)
    ap.add_argument("--store", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    def by_spell(path, keep=lambda r: r["DifficultyID"] == "0"):
        out = collections.defaultdict(list)
        for r in read_csv(path):
            if keep(r):
                out[int(r["SpellID"])].append(r)
        return out

    t = Tables(
        spell_effects=by_spell(os.path.join(a.db2, "SpellEffect.csv")),
        aura_options=by_spell(os.path.join(a.db2, "SpellAuraOptions.csv")),
        ppm={int(r["ID"]): float(r["BaseProcRate"]) for r in read_csv(a.ppm)},
        misc=by_spell(os.path.join(a.db2, "SpellMisc.csv")),
        categories=by_spell(os.path.join(a.gear, "SpellCategories.csv")),
        durations={int(r["ID"]): r for r in read_csv(os.path.join(a.gear, "SpellDuration.csv"))},
        en={int(r["ID"]): r["Description_lang"] for r in read_csv(os.path.join(a.db2, "Spell.csv"))},
        ru={int(r["ID"]): r["Description_lang"] for r in read_csv(a.ru)},
    )
    effects = {int(r["ID"]): r for r in read_csv(os.path.join(a.gear, "ItemEffect.csv"))}
    names = {int(r["ID"]): r["Display_lang"] for r in read_csv(os.path.join(a.db2, "ItemSparse.csv"))}
    spell_names = {int(r["ID"]): r["Name_lang"] for r in read_csv(os.path.join(a.db2, "SpellName.csv"))}

    out = collections.defaultdict(list)
    unchecked = []  # (item, spell): a description with no damage phrase in either locale
    level_scaled = []  # (item, spell): Skips
    hand_bits = []  # (item, spell): Skips
    mismatches_seen = set()
    for link in read_csv(os.path.join(a.gear, "ItemXItemEffect.csv")):
        e = effects.get(int(link["ItemEffectID"]))
        if e is None or int(e["TriggerType"]) not in (TRIGGER_EQUIP, TRIGGER_ON_HIT):
            continue
        item_id = int(link["ItemID"])
        entry = entry_for(int(e["TriggerType"]), int(e["SpellID"]), t, item_id, mismatches_seen)
        if entry is None:
            continue
        if entry == "level":
            level_scaled.append((item_id, int(e["SpellID"])))
            continue
        if entry == "hands":
            hand_bits.append((item_id, int(e["SpellID"])))
            continue
        add_entry(out, item_id, entry)
        if entry["en"] is None and entry["ru"] is None and not ("dot" in entry and entry["avg"] == 0):
            unchecked.append((item_id, entry["trigger"]))

    lines = [
        "-- Damage procs of gear from the Forever DB2 (build 70888): itemID -> { { trigger = <the spell the item effect",
        "-- names>, kind = \"equip\" (an equip aura, ItemEffect TriggerType 1) | \"hit\" (chance on hit, TriggerType 2), spell =",
        "-- <the damage spell>, avg / min / max = its damage (wowsims' spread and mean), school = <SchoolMask>, defense =",
        "-- <DefenseType: 0 none, 1 magic, 2 melee, 3 ranged>, crit = <false when the spell cannot crit, Attributes_2",
        "-- 0x20000000> and, for an equip aura, mask = <SpellAuraOptions ProcTypeMask_0>, chance = <ProcChance>, ppm =",
        "-- <SpellProcsPerMinute BaseProcRate, 0 for none>, icd = <ProcCategoryRecovery, ms> }, ... }; dot = { tick = <the",
        "-- damage a tick, aura 3's EffectBasePointsF>, period = <ms between ticks>, ticks = <the duration over the period>,",
        "-- canCrit = <its ticks crit: SpellMisc Attributes_8 0x200> } for a damage spell with a damage over time, whose avg,",
        "-- min and max are 0 when it deals no direct damage (Items.LinkProcs links such an entry by the item's one effect",
        "-- line of its kind that Parse leaves not counted).",
        "-- A chance-on-hit item effect states no rate (ItemEffect has no chance or procs-per-minute column): its entry has",
        "-- no mask, chance or icd, and a ppm only from wowsims' override data. source = <the Source of wowsims' override row",
        "-- the entry's ppm or chance comes from: \"EV-<n>\" a measurement on Forever, \"vanilla-carryover\" /",
        "-- \"tbc-carryover\" a rate carried over unchecked>; an entry without source states its own rate or none. Items.Get",
        "-- links each proc Parse reads to the one entry of its kind whose mean is the parsed average within 0.5 (an entry with",
        "-- a direct damage), and an entry of a fixed direct damage (min == max: one number on the tooltip, no range) by the",
        "-- item's one effect line of its kind that Parse leaves not counted and that states the amount as damage.",
        "-- mainHand = true: the equip aura hears the main hand's melee hits alone (SpellAuraOptions ProcTypeMask_1 0x20).",
        "-- always = true: wowsims rolls the equip aura on every hit of its mask (an active \"every time\" registration of",
        "-- sim/common/forever/stat_bonus_procs_auto_gen.go, its trigger ProcChanceAlways in sim/core/spelldata/spells_auto_gen.go).",
        "-- versus = { factor = <the factor its trigger deals against the types>, types = { <creature types> } }: wowsims'",
        "-- VersusBonuses row of the trigger (tools/database/overrides/spell_overrides.go), its mob types alone.",
        "-- Generated by tools/gen_proc_data.py (do not edit by hand) from ItemXItemEffect, ItemEffect, SpellEffect,",
        "-- SpellAuraOptions, SpellProcsPerMinute, SpellMisc, SpellDuration, SpellCategories, Spell (enUS, ruRU) and wowsims/forever's",
        "-- tools/database/overrides weapon_procs.go and spell_overrides.go, sim/common/forever/stat_bonus_procs_auto_gen.go and",
        "-- sim/core/spelldata/spells_auto_gen.go.",
        "-- %d of the entries' shown spells have a description with no damage phrase (their school is not checked); the"
        % len(unchecked),
        "-- entries with a damage over time and no direct damage have no damage Parse reads (their school is not checked).",
    ]
    check_mismatches_seen(mismatches_seen)
    with open(os.path.join(a.overrides, "weapon_procs.go"), encoding="utf-8") as f:
        weapon_procs = read_weapon_procs(f.read())
    with open(os.path.join(a.overrides, "spell_overrides.go"), encoding="utf-8") as f:
        spell_text = f.read()
    spell_overrides = read_spell_overrides(spell_text)
    unused = attach_overrides(out, weapon_procs, spell_overrides)
    taken = sum(1 for v in out.values() for e in v if "source" in e)
    lines.append("-- wowsims/forever's override rates (tools/database/overrides: %d WeaponProcs rows, %d PPM / ProcChancePct spell"
                 " rows): %d entries take one (rate and source); %d rows name no written entry"
                 % (len(weapon_procs), len(spell_overrides), taken, len(unused)))
    with open(a.registrations, encoding="utf-8") as f:
        regs = read_every_time(f.read())
    with open(a.store, encoding="utf-8") as f:
        sources = store_sources(f.read(), sorted({r["trigger"] for r in regs}))
    a_marked, a_missing, a_stated = attach_always(out, regs, sources)
    lines.append("-- wowsims/forever's every-time damage proc registrations (stat_bonus_procs_auto_gen.go: %d, %d active): always on"
                 " %d entries (%s); their items with no equip entry of the trigger here: %s; with a stated procs per minute,"
                 " which wowsims' manager takes: %s"
                 % (len(regs), sum(1 for r in regs if r["active"]), len(a_marked),
                    ", ".join("%d/%d" % x for x in a_marked), ", ".join("%d/%d" % x for x in a_missing) or "none",
                    ", ".join("%d/%d" % x for x in a_stated) or "none"))
    versus_rows = read_versus_bonuses(spell_text)
    v_took, v_families, v_unused = attach_versus(out, versus_rows, t)
    lines.append("-- wowsims/forever's VersusBonuses (spell_overrides.go: %d rows): the mob types of %s go onto %d entries"
                 " (versus); %d rows of creature families alone left out (%s); rows of mob types no written entry has: %s"
                 % (len(versus_rows), ", ".join(str(x) for x in v_took),
                    sum(1 for v in out.values() for e in v if "versus" in e), len(v_families),
                    ", ".join(str(x) for x in v_families), ", ".join(str(x) for x in v_unused) or "none"))
    for item_id, spell in sorted(level_scaled):
        lines.append("-- Left out, its proc stays unlinked: %d %s, spell %d: its damage gains points a level"
                     % (item_id, names.get(item_id) or spell_names.get(spell, "?"), spell))
    for item_id, spell in sorted(hand_bits):
        lines.append("-- Left out, its proc stays unlinked: %d %s, spell %d: its ProcTypeMask_0 has hand bits"
                     % (item_id, names.get(item_id) or spell_names.get(spell, "?"), spell))
    lines.append("-- %d descriptions the school-word rule misreads (TEXT_SCHOOL_MISMATCHES in the generator): %s"
                 % (len(mismatches_seen), ", ".join("%d %d %s" % k for k in sorted(mismatches_seen))))
    lines += [
        "local _, ns = ...",
        "",
        "ns.ProcData = {",
    ]
    fields = ["trigger", "kind", "mask", "mainHand", "chance", "ppm", "icd", "always", "source", "spell", "avg", "min", "max", "school", "defense",
              "crit", "dot", "versus"]
    for item_id in sorted(out):
        parts = []
        for entry in sorted(out[item_id], key=lambda x: (x["kind"], x["spell"])):
            kv = []
            for k in fields:
                if k not in entry:
                    continue
                v = entry[k]
                if k == "dot":
                    kv.append("dot = { tick = %s, period = %d, ticks = %d, canCrit = %s }" % (
                        lua_num(v["tick"]), v["period"], v["ticks"], "true" if v["canCrit"] else "false"))
                elif k == "versus":
                    kv.append("versus = { factor = %s, types = { %s } }" % (
                        lua_num(v["factor"]), ", ".join('"%s"' % ty for ty in v["types"])))
                elif isinstance(v, bool):
                    kv.append("%s = %s" % (k, "true" if v else "false"))
                elif isinstance(v, str):
                    kv.append('%s = "%s"' % (k, v))
                else:
                    kv.append("%s = %s" % (k, lua_num(v)))
            parts.append("{ " + ", ".join(kv) + " }")
        name = names.get(item_id) or "no ItemSparse name; spell: " + spell_names.get(out[item_id][0]["trigger"], "?")
        lines.append("\t[%d] = { %s }, -- %s" % (item_id, ", ".join(parts), name))
    lines.append("}")
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    n = sum(len(v) for v in out.values())
    print("wrote %d entries of %d items to %s (%d with a damage over time, %d of them no direct damage)" % (
        n, len(out), a.out, sum(1 for v in out.values() for e in v if "dot" in e),
        sum(1 for v in out.values() for e in v if "dot" in e and e["avg"] == 0)))
    print("%d shown spells without a damage phrase to check: %s" % (len(unchecked), unchecked))
    print("%d level-scaled damage procs left out: %s" % (len(level_scaled), level_scaled))
    print("%d equip auras with ProcTypeMask_0's hand bits left out: %s" % (len(hand_bits), hand_bits))
    print("%d equip entries of the main hand alone: %s" % (
        sum(1 for v in out.values() for e in v if e.get("mainHand")),
        sorted((i, e["trigger"]) for i, v in out.items() for e in v if e.get("mainHand"))))


if __name__ == "__main__":
    main()
