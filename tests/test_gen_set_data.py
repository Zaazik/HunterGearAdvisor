"""Tests of tools/gen_set_data.py's rules that build 70888's set bonuses do not exercise, on synthetic DB2 rows.

Run from the addon root: python -I tests/test_gen_set_data.py (the generator is loaded from its path: -I keeps the
script's directory off sys.path). Exits 1 on a failure.

A_MOD_SKILL (aura 30) on a weapon skill line: its misc value is a SkillLine id (Game/Player.lua WEAPON_SKILL), each melee
line HGA's SKILL_<LINE> (Core/Score.lua MELEE_SKILL). Build 70888's five melee skill bonuses (Defias Leather 161, Insulated
Leathers 1585, The Twin Blades of Hakkari 461 and 1800, Defias Enforcer's Garb 2136) are in Game/SetData.lua; the case of
The Twin Blades of Hakkari 461 is its 2-piece bonus spell 15763 as SpellEffect row 693254 has it (Effect 6, aura 30,
target 1, misc 43, base points 6; Forever DB2 build 70888 db2/SpellEffect.csv).

The weapon-bound hit (A_MOD_HIT_CHANCE, aura 54, on a spell whose SpellEquippedItems row asks for a weapon): on ranged
weapons alone it is HGA's RANGED_HIT, the ranged-only hit wowsims folds into RangedHitPercent (tools/database/dbc/
util.go:356-373) and the pet and the hawks inherit (sim/hunter/pets.go:155-158); on melee weapons it stays unknown;
without a weapon row it is the hit of every attack, HIT. No set bonus of build 70888 has a weapon-bound aura 54, so
Game/SetData.lua shows none of these.

Attack speed (raid-mode W1 design 7.3, wowsims' paths): a set bonus's aura 9 (A_MOD_ATTACKSPEED) or 342
(A_MOD_MELEE_RANGED_HASTE_2) is wowsims' attackSpeedRow (sim/core/spelldata/parse_effects_table.go:367-368), HGA's
ATTACK_SPEED: the Tier-1 two-piece bonus 1300945 as SpellEffect rows 1325822 / 1353973 have it (aura 342 bp 1 and aura 65
bp 1, target 1; Forever DB2 build 70888 db2/SpellEffect.csv); no set bonus of build 70888 carries aura 9. Aura 192
(A_MOD_MELEE_RANGED_HASTE), which no row of wowsims' parse table reads, stops the generator. A haste rating
(A_MOD_RATING, aura 189, the melee and ranged haste bits 0x20000 | 0x40000) is HASTE_RATING, 10 rating a 1%; no set
bonus of build 70888 carries one.
"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("gen_set_data", os.path.join(ROOT, "tools", "gen_set_data.py"))
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

SPELL = 900001  # a made-up bonus spell id

# Subclass masks of real SpellEquippedItems rows (Forever DB2 build 70888, SpellEquippedItems.csv): 256232 (spell
# 1294769, the ranged-hit line of Marksman Bands and others) asks for item class 2 with bows, guns and crossbows,
# 262156; 170492 (spell 7786, Beastslaying) for class 2 with the melee subclasses, 189939.
RANGED_MASK = 262156
MELEE_MASK = 189939
ONE_HANDED_SWORD = 1 << 7


def hit_effect(bp):
    """One SpellEffect row: APPLY_AURA (6) on the caster (target 1) of A_MOD_HIT_CHANCE (54) by bp percent."""
    return {"DifficultyID": "0", "Effect": "6", "EffectAura": "54", "ImplicitTarget_0": "1",
            "EffectMiscValue_0": "0", "EffectBasePointsF": str(bp)}


def equip_row(item_class, subclass, inv_types=0):
    return {"EquippedItemClass": str(item_class), "EquippedItemSubclass": str(subclass),
            "EquippedItemInvTypes": str(inv_types)}


def stats(equip):
    return gen.spell_stats(SPELL, {SPELL: [hit_effect(1)]}, {SPELL: equip} if equip else {})


def skill_effect(line, bp):
    """One SpellEffect row: APPLY_AURA (6) on the caster (target 1) of A_MOD_SKILL (30) on skill line `line` by bp."""
    return {"DifficultyID": "0", "Effect": "6", "EffectAura": "30", "ImplicitTarget_0": "1",
            "EffectMiscValue_0": str(line), "EffectBasePointsF": str(bp)}


# The melee skill lines and their keys (Game/Player.lua WEAPON_SKILL, Core/Score.lua MELEE_SKILL)
MELEE_LINES = {43: "SKILL_SWORDS", 44: "SKILL_AXES", 54: "SKILL_MACES", 55: "SKILL_2H_SWORDS", 136: "SKILL_STAVES",
               160: "SKILL_2H_MACES", 172: "SKILL_2H_AXES", 173: "SKILL_DAGGERS", 229: "SKILL_POLEARMS", 473: "SKILL_FIST"}
SKILL_CASES = [("A_MOD_SKILL on line %d is %s" % (line, key), skill_effect(line, 3), {key: 3.0})
               for line, key in sorted(MELEE_LINES.items())]
SKILL_CASES.append(("The Twin Blades of Hakkari 461, 2 pieces: spell 15763 is SKILL_SWORDS 6", skill_effect(43, 6),
                    {"SKILL_SWORDS": 6.0}))

CASES = [
    ("aura 54 on bows, guns and crossbows alone is RANGED_HIT", equip_row(2, RANGED_MASK), {"RANGED_HIT": 1.0}),
    ("aura 54 on melee weapons stays unknown", equip_row(2, MELEE_MASK), None),
    ("aura 54 on ranged and melee weapons together stays unknown", equip_row(2, RANGED_MASK | ONE_HANDED_SWORD), None),
    ("aura 54 on a weapon row with an inventory type mask stays unknown", equip_row(2, RANGED_MASK, 1 << 15), None),
    ("aura 54 on a weapon row with no subclass stays unknown", equip_row(2, 0), None),
    ("aura 54 without a SpellEquippedItems row is HIT", None, {"HIT": 1.0}),
    ("aura 54 on an armor row is HIT", equip_row(4, 1 << 2), {"HIT": 1.0}),
]


def aura_effect(aura, bp, misc=0):
    """One SpellEffect row of SPELL: APPLY_AURA (6) on the caster (target 1) of `aura` by bp, misc value misc."""
    return {"SpellID": str(SPELL), "DifficultyID": "0", "Effect": "6", "EffectAura": str(aura), "ImplicitTarget_0": "1",
            "EffectMiscValue_0": str(misc), "EffectBasePointsF": str(bp)}


SPEED_CASES = [
    ("Tier-1 two-piece 1300945: aura 342 and aura 65 are ATTACK_SPEED and CAST_SPEED", [aura_effect(342, 1), aura_effect(65, 1)],
     {"ATTACK_SPEED": 1.0, "CAST_SPEED": 1.0}),
    ("aura 9 is ATTACK_SPEED", [aura_effect(9, 2)], {"ATTACK_SPEED": 2.0}),
    ("A_MOD_RATING haste (melee and ranged) is HASTE_RATING, 10 rating a 1%", [aura_effect(189, 20, 0x20000 | 0x40000)],
     {"HASTE_RATING": 2.0}),
]


def main():
    passed = failed = 0
    for name, effects, want in SPEED_CASES:
        got = gen.spell_stats(SPELL, {SPELL: effects}, {})
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    try:
        got = gen.spell_stats(SPELL, {SPELL: [aura_effect(192, 1)]}, {})
        failed += 1
        print("FAIL aura 192 stops the generator: got %r" % (got,))
    except SystemExit as e:
        if "spell %d has an aura 192" % SPELL in str(e):
            passed += 1
        else:
            failed += 1
            print("FAIL aura 192 stops the generator naming the spell: %s" % e)
    for name, equip, want in CASES:
        got = stats(equip)
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    for name, effect, want in SKILL_CASES:
        got = gen.spell_stats(SPELL, {SPELL: [effect]}, {})
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    print("%d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
