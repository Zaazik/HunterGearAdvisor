"""Generates Game/StatMultData.lua: the auras that multiply the player's stats (A_MOD_TOTAL_STAT_PERCENTAGE and
A_MOD_PERCENT_STAT), which Player.ReadStats finds up on the live character sheet (Greater Blessing of Kings, Spirit of
Zandalar, Sayge's Dark Fortune of Agility and the like) and Model.ApplyStats multiplies an item's Agility, Strength,
Intellect and Spirit by (the user's answer O8 = (a): the live sheet's stat multipliers count; raid-mode design 4.8, 24.3).

Sources (all read-only, Forever DB2 build 70888 exports):
  * SpellEffect: every Effect 6 APPLY_AURA effect of aura 137 A_MOD_TOTAL_STAT_PERCENTAGE or aura 80 A_MOD_PERCENT_STAT
    with positive base points (EffectBasePointsF, the percent; a debuff's negative points never come from a buff the
    sheet keeps). wowsims multiplies a stat by either aura alike (wowsims/forever sim/core/spelldata/
    parse_effects_table.go:311-312 maps A_MOD_PERCENT_STAT to percentStatRow and A_MOD_TOTAL_STAT_PERCENTAGE to
    totalStatPercentRow, :807-813: both p.statMultiplier of MultiplierFromPercent).
  * SpellName: names, for the comments only.

The stats an aura 137 effect multiplies, as wowsims reads them (wowsims/forever sim/core/spelldata/parse_effects_table.go:
1446-1454 TotalStatPercentStats): a mask in the second misc value (EffectMiscValue_1, one bit per client stat index:
1 Strength, 2 Agility, 4 Stamina, 8 Intellect, 16 Spirit, statMaskList :1435-1444) names them where it is not 0, and
the first misc value then does not (Heart of the Wild 17003 states 0 and 8: Intellect); with no mask the first misc
value names them, -1 all five and 0..4 one client stat index (clientStatList :1425-1433, the client order Strength,
Agility, Stamina, Intellect, Spirit, clientStats :52-54). The design's own rule (raid-mode design 4.8: "misc -1 all
five, 0..4 one") reads the first misc value alone, which every row of build 70888 overrides with its mask (Lightning
Reflexes 19168 states 0 and 2: Agility, not Strength). An aura 80 effect names its stats by the first misc value alone,
-1 all five and 0..4 one (percentStatRow: clientStatList(e.Misc), parse_effects_table.go:807-809; Sayge's Dark Fortune
of Agility 23736 states 1, Elune's Blessing 26393 -1).

Left out: the talents the model reads itself as a rank (MODEL_TALENTS: Lightning Reflexes, Core/Model.lua applyStats
1 + 0.03 x its rank), so its factor is not counted twice.

The auras that lower the stats (ns.StatDebuffData, raid-mode design 25.6): every spell with an Effect 6 effect of aura 137
or aura 80 of negative points (Resurrection Sickness 15007 aura 80 -75%, Coward! 422978 aura 137 -20% and the like). wowsims
multiplies a stat by such a row too (parse_effects_table.go:807-813); HGA prices gear on the character's sheet without
one: while one is up, Player.ReadStats takes the last reading of the same gear and talents (statsStaleBy "debuff"), or
none.

Checks (the script stops instead of writing doubtful data):
  * an aura 137 or 80 effect of positive points is Effect 6 of DifficultyID 0;
  * its stats are one or more client stats (a mask of no known bit, or a first misc value outside -1..4 where it is
    read, stops);
  * a spell names a stat at most once among its written effects (two effects of one stat would multiply);
  * every MODEL_TALENTS spell has such an effect (an exclusion that matches nothing is stale);
  * every written spell has a SpellName row;
  * an aura 137 or 80 effect of negative points is Effect 6 of DifficultyID 0 as well.

Usage:
  python tools/gen_stat_mult_data.py --db2 <dir with SpellEffect.csv, SpellName.csv> --out Game/StatMultData.lua

Tests: python -I tests/test_gen_stat_mult_data.py (the rules on synthetic rows).
"""
import argparse
import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_set_data as G  # noqa: E402  (read_csv, lua_num, lua_str, CLIENT_STATS)

E_APPLY_AURA = 6
A_MOD_PERCENT_STAT = 80
A_MOD_TOTAL_STAT_PERCENTAGE = 137
STAT_AURAS = (A_MOD_PERCENT_STAT, A_MOD_TOTAL_STAT_PERCENTAGE)
MISC_ALL_STATS = -1
# The talents Core/Model.lua reads as a rank (Player.BRANCHES): Lightning Reflexes, both trait nodes 110859 and 104982
# (TraitNodeXTraitNodeEntry -> TraitNodeEntry 137851 / 129646 -> TraitDefinition 142605 / 134447, SpellID 19168, build
# 70888), +3% Agility a rank (Core/Model.lua applyStats AGI)
MODEL_TALENTS = {19168: "Lightning Reflexes"}


def effect_stats(aura, misc, mask):
    """The client stat indexes (0..4) an effect of aura 137 (wowsims TotalStatPercentStats: the mask first) or aura 80
    (percentStatRow: the first misc value alone) multiplies; None for none."""
    if aura == A_MOD_TOTAL_STAT_PERCENTAGE and mask != 0:
        if mask & ~0x1F:
            return None
        return [i for i in range(5) if mask & (1 << i)]
    if misc == MISC_ALL_STATS:
        return list(range(5))
    if 0 <= misc <= 4:
        return [misc]
    return None


def stat_mults(effects):
    """spell id -> { client stat index: percent } of every positive aura 137 or aura 80 effect (effects: SpellEffect
    rows), less MODEL_TALENTS; stops (SystemExit) on a row the checks refuse."""
    out = collections.defaultdict(dict)
    seen_talents = set()
    for r in effects:
        aura = int(r["EffectAura"])
        if aura not in STAT_AURAS:
            continue
        bp = float(r["EffectBasePointsF"])
        if bp <= 0:
            continue
        spell = int(r["SpellID"])
        if int(r["Effect"]) != E_APPLY_AURA or int(r["DifficultyID"]) != 0:
            raise SystemExit("spell %d: an aura %d effect of +%s on Effect %s, DifficultyID %s: HGA reads Effect 6 of "
                             "DifficultyID 0 alone" % (spell, aura, r["EffectBasePointsF"], r["Effect"], r["DifficultyID"]))
        stats = effect_stats(aura, int(r["EffectMiscValue_0"]), int(r["EffectMiscValue_1"]))
        if not stats:
            raise SystemExit("spell %d: aura %d misc %s and mask %s name no client stat" % (
                spell, aura, r["EffectMiscValue_0"], r["EffectMiscValue_1"]))
        if spell in MODEL_TALENTS:
            seen_talents.add(spell)
            continue
        for i in stats:
            if i in out[spell]:
                raise SystemExit("spell %d: two stat multiplier effects of %s" % (spell, G.CLIENT_STATS[i]))
            out[spell][i] = bp
    stale = set(MODEL_TALENTS) - seen_talents
    if stale:
        raise SystemExit("MODEL_TALENTS %s: no positive stat multiplier effect" % sorted(stale))
    return dict(out)


def stat_debuffs(effects):
    """The spell ids of every negative aura 137 or aura 80 effect (effects: SpellEffect rows), sorted; stops (SystemExit) on
    one of another Effect or DifficultyID."""
    out = set()
    for r in effects:
        aura = int(r["EffectAura"])
        if aura not in STAT_AURAS or float(r["EffectBasePointsF"]) >= 0:
            continue
        spell = int(r["SpellID"])
        if int(r["Effect"]) != E_APPLY_AURA or int(r["DifficultyID"]) != 0:
            raise SystemExit("spell %d: an aura %d effect of %s on Effect %s, DifficultyID %s: HGA reads Effect 6 of "
                             "DifficultyID 0 alone" % (spell, aura, r["EffectBasePointsF"], r["Effect"], r["DifficultyID"]))
        out.add(spell)
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db2", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    effects = G.read_csv(os.path.join(a.db2, "SpellEffect.csv"))
    names = {int(r["ID"]): r["Name_lang"] for r in G.read_csv(os.path.join(a.db2, "SpellName.csv"))}
    mults = stat_mults(effects)
    debuffs = stat_debuffs(effects)
    lines = [
        "-- The auras that multiply the player's stats: spellID -> { [client stat index] = percent }, the index in the client",
        "-- order 0 Strength, 1 Agility, 2 Stamina, 3 Intellect, 4 Spirit. Player.ReadStats multiplies 1 + percent / 100 of",
        "-- each aura up on the player into p.statMult (Agility, Strength, Intellect, Spirit), and Model.ApplyStats multiplies",
        "-- an item's stats by it (raid-mode design 4.8, the user's answer O8 = (a)).",
        "-- Generated by tools/gen_stat_mult_data.py (do not edit by hand) from the Forever DB2 (build 70888): SpellEffect",
        "-- (Effect 6, aura 137 A_MOD_TOTAL_STAT_PERCENTAGE or aura 80 A_MOD_PERCENT_STAT, positive points; an aura 137",
        "-- effect's stats by the mask of EffectMiscValue_1, else EffectMiscValue_0, as wowsims sim/core/spelldata/",
        "-- parse_effects_table.go TotalStatPercentStats; an aura 80 effect's by EffectMiscValue_0, as percentStatRow) and",
        "-- SpellName.",
        "-- Left out, the model reads it as a talent rank: " + ", ".join(
            "%d %s" % (s, n) for s, n in sorted(MODEL_TALENTS.items())) + ".",
        "local _, ns = ...",
        "",
        "ns.StatMultData = {",
    ]
    for spell in sorted(mults):
        if spell not in names:
            raise SystemExit("spell %d has no SpellName row" % spell)
        body = ", ".join("[%d] = %s" % (i, G.lua_num(v)) for i, v in sorted(mults[spell].items()))
        lines.append("\t[%d] = { %s }, -- %s" % (spell, body, names[spell]))
    lines.append("}")
    lines += [
        "",
        "-- The auras that lower the player's stats (aura 137 or aura 80 of negative points): spellID -> true. While one is up",
        "-- Player.ReadStats takes the last reading of the same gear and talents (statsStaleBy \"debuff\"), or none (raid-mode",
        "-- design 25.6).",
        "ns.StatDebuffData = {",
    ]
    for spell in debuffs:
        if spell not in names:
            raise SystemExit("spell %d has no SpellName row" % spell)
        lines.append("\t[%d] = true, -- %s" % (spell, names[spell]))
    lines.append("}")
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%d spells, %d debuffs" % (len(mults), len(debuffs)), file=sys.stderr)


if __name__ == "__main__":
    main()
