"""Tests of tools/gen_use_data.py's pricing rule on synthetic DB2 rows: a "Use:" buff is priced only when one of its keys
is in DAMAGE_KEYS, the keys Model.Weights gives a damage weight (Core/Model.lua).

Run from the addon root: python -I tests/test_gen_use_data.py (the generator is loaded from its path: -I keeps the
script's directory off sys.path). Exits 1 on a failure.

The attack speed of aura 342 (A_MOD_MELEE_RANGED_HASTE_2) and haste rating (A_MOD_RATING, aura 189, the melee and ranged
haste bits 0x20000 | 0x40000, 10 rating a 1%) are tools/gen_set_data.py's ATTACK_SPEED and HASTE_RATING (Core/Model.lua
W.ATTACK_SPEED and W.HASTE_RATING; raid-mode W1 design 7.3); no Use buff of build 70888 carries either, so
Game/UseData.lua shows none. Aura 65 (A_MOD_CASTING_SPEED) alone is CAST_SPEED, which has no damage weight: not priced. A
319 + 140 pair of one amount (Kiss of the Spider 22954, spell 28866) is MELEE_HASTE and RANGED_HASTE.
"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("gen_use_data", os.path.join(ROOT, "tools", "gen_use_data.py"))
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

SPELL = 900002  # a made-up Use spell id


def aura_effect(aura, bp, misc=0):
    """One SpellEffect row of SPELL: APPLY_AURA (6) on the caster (target 1) of `aura` by bp, misc value misc."""
    return {"SpellID": str(SPELL), "DifficultyID": "0", "Effect": "6", "EffectAura": str(aura), "ImplicitTarget_0": "1",
            "EffectMiscValue_0": str(misc), "EffectBasePointsF": str(bp)}


CASES = [
    ("aura 342 is ATTACK_SPEED, priced", [aura_effect(342, 2)], {"ATTACK_SPEED": 2.0}),
    ("A_MOD_RATING haste (melee and ranged) is HASTE_RATING, priced", [aura_effect(189, 20, 0x20000 | 0x40000)],
     {"HASTE_RATING": 2.0}),
    ("aura 65 alone is CAST_SPEED, no damage key: not priced", [aura_effect(65, 3)], None),
    ("a 319 + 140 pair of one amount is MELEE_HASTE and RANGED_HASTE, priced", [aura_effect(319, 20), aura_effect(140, 20)],
     {"MELEE_HASTE": 20.0, "RANGED_HASTE": 20.0}),
    ("aura 319 alone stays not counted", [aura_effect(319, 20)], None),
    # raid mode prices the mana stats through the fight (raid-mode design 6.8): Spirit (A_MOD_STAT 29, misc 4), MP5 (aura
    # 85 on mana, misc 0) and mana (aura 35 on mana) are damage keys
    ("Spirit alone (Serenity Field 272439's kind) is priced", [aura_effect(29, 72, 4)], {"SPI": 72.0}),
    ("MP5 alone is priced", [aura_effect(85, 20, 0)], {"MP5": 20.0}),
    ("mana alone is priced", [aura_effect(35, 300, 0)], {"MANA": 300.0}),
]

# A drink whose aura lasts while the user sits (SpellInterrupts AuraInterruptFlags_0 0x40000, as Lapidis Tankard of
# Tidesippe 4696's spell 1135 holds, 262272): left out, as wowsims leaves it (sim/core/spelldata/consumable.go:21-25)
SEATED_CASES = [
    ("a drink's 0x40000 (262272) is seated", {SPELL: [{"DifficultyID": "0", "AuraInterruptFlags_0": "262272"}]}, True),
    ("another interrupt flag alone is not", {SPELL: [{"DifficultyID": "0", "AuraInterruptFlags_0": "128"}]}, False),
    ("no row is not", {}, False),
    ("a row of another difficulty alone is not", {SPELL: [{"DifficultyID": "1", "AuraInterruptFlags_0": "262144"}]}, False),
]


def main():
    passed = failed = 0
    for name, effects, want in CASES:
        got = gen.priced_use_stats(SPELL, {SPELL: effects}, {})
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    for name, interrupts, want in SEATED_CASES:
        got = gen.while_seated(SPELL, interrupts)
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    print("%d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
