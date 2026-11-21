"""Tests of tools/gen_stat_mult_data.py's rules: the stats of an aura 137 A_MOD_TOTAL_STAT_PERCENTAGE effect by wowsims'
TotalStatPercentStats (the mask of the second misc value first, else the first misc value), the stats of an aura 80
A_MOD_PERCENT_STAT effect by wowsims' percentStatRow (the first misc value alone), the positive points alone, the
talents the model reads left out, and the checks that stop the generator.

Run from the addon root: python -I tests/test_gen_stat_mult_data.py (the generator is loaded from its path: -I keeps the
script's directory off sys.path). Exits 1 on a failure.

Rows of build 70888 (Forever DB2 SpellEffect): 702574 (Greater Blessing of Kings 25898: Effect 6, aura 137, misc -1, mask
31, +10), 696059 (Lightning Reflexes 19168: misc 0, mask 2, +15), 694815 (Heart of the Wild 17003: misc 0, mask 8, +10),
705473 (Vitality 29140: misc 2, mask 5, +10), 700258 (Sayge's Dark Fortune of Agility 23736: aura 80, misc 1, +10), 704415
(Elune's Blessing 26393: aura 80, misc -1, +10), 692008 (Resurrection Sickness 15007: aura 80, misc -1, -75); the rest
are synthetic.
"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("gen_stat_mult_data", os.path.join(ROOT, "tools", "gen_stat_mult_data.py"))
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def se(spell, bp, misc, mask, effect=6, aura=137, difficulty=0):
    return {"SpellID": str(spell), "Effect": str(effect), "EffectAura": str(aura), "DifficultyID": str(difficulty),
            "EffectBasePointsF": str(bp), "EffectMiscValue_0": str(misc), "EffectMiscValue_1": str(mask)}


LR = se(19168, 15, 0, 2)
KINGS = se(25898, 10, -1, 31)

CASES = [
    ("Greater Blessing of Kings 25898: all five stats 10; Lightning Reflexes 19168 left out", [KINGS, LR],
     {25898: {0: 10.0, 1: 10.0, 2: 10.0, 3: 10.0, 4: 10.0}}),
    ("the mask wins over the first misc value: Heart of the Wild 17003 (0, 8) is Intellect", [se(17003, 10, 0, 8), LR],
     {17003: {3: 10.0}}),
    ("a mask of two bits: Vitality 29140 (2, 5) is Strength and Stamina", [se(29140, 10, 2, 5), LR],
     {29140: {0: 10.0, 2: 10.0}}),
    ("no mask: the first misc value, -1 all five", [se(900001, 5, -1, 0), LR],
     {900001: {0: 5.0, 1: 5.0, 2: 5.0, 3: 5.0, 4: 5.0}}),
    ("no mask: the first misc value 4 is Spirit", [se(900002, 5, 4, 0), LR], {900002: {4: 5.0}}),
    ("negative points (a debuff) are left out", [se(900003, -10, -1, 31), LR], {}),
    ("another aura is not read", [se(900004, 10, -1, 31, aura=29), LR], {}),
    ("two effects of two stats on one spell", [se(900005, 15, 0, 4), se(900005, 10, 0, 16), LR],
     {900005: {2: 15.0, 4: 10.0}}),
    ("the mask wins over a first misc value of -1: (-1, 2) is Agility alone", [se(900012, 10, -1, 2), LR],
     {900012: {1: 10.0}}),
    ("aura 80: Sayge's Dark Fortune of Agility 23736 (misc 1) is Agility", [se(23736, 10, 1, 0, aura=80), LR],
     {23736: {1: 10.0}}),
    ("aura 80: Elune's Blessing 26393 (misc -1) is all five", [se(26393, 10, -1, 0, aura=80), LR],
     {26393: {0: 10.0, 1: 10.0, 2: 10.0, 3: 10.0, 4: 10.0}}),
    ("aura 80 reads the first misc value alone: (1, 8) is Agility, not Intellect", [se(900013, 10, 1, 8, aura=80), LR],
     {900013: {1: 10.0}}),
    ("aura 80: Resurrection Sickness 15007's negative points are left out", [se(15007, -75, -1, 0, aura=80), LR], {}),
    ("aura 80 and aura 137 on one spell, two stats", [se(900017, 10, 3, 0, aura=80), se(900017, 5, 0, 16), LR],
     {900017: {3: 10.0, 4: 5.0}}),
]

STOPS = [
    ("two effects of one stat on one spell stop", [se(900006, 15, 0, 4), se(900006, 10, 2, 0), LR]),
    ("an aura 137 effect on another Effect stops", [se(900007, 10, -1, 31, effect=35), LR]),
    ("another difficulty stops", [se(900008, 10, -1, 31, difficulty=1), LR]),
    ("a mask of an unknown bit alone stops", [se(900009, 10, 0, 32), LR]),
    ("a mask of Strength and an unknown bit stops", [se(900011, 10, 0, 33), LR]),
    ("a first misc value outside -1..4 with no mask stops", [se(900010, 10, 5, 0), LR]),
    ("Lightning Reflexes absent: the exclusion is stale and stops", [KINGS]),
    ("an aura 80 effect on another Effect stops", [se(900014, 10, 1, 0, effect=35, aura=80), LR]),
    ("an aura 80 first misc value outside -1..4 stops", [se(900015, 10, 5, 0, aura=80), LR]),
    ("aura 80 and aura 137 of one stat on one spell stop", [se(900016, 10, 1, 0, aura=80), se(900016, 5, 0, 2), LR]),
]


# The auras that lower the stats (raid-mode design 25.6; tools/gen_stat_mult_data.py stat_debuffs): every spell with a
# negative aura 137 or aura 80 effect, once, sorted; a positive one or another aura is none; one on another Effect or
# DifficultyID stops. Resurrection Sickness 15007 (aura 80 -75, SpellEffect 692008) and Coward! 422978 (aura 137 -20, misc
# 0, mask 31) as build 70888 has them
DEBUFF_CASES = [
    ("Resurrection Sickness 15007 and Coward! 422978, each once, sorted; the positive Kings and Lightning Reflexes none",
     [se(422978, -20, 0, 31), se(15007, -75, -1, 0, aura=80), se(15007, -75, -1, 0, aura=80), KINGS, LR], [15007, 422978]),
    ("another aura of negative points is none", [se(900020, -10, -1, 31, aura=29)], []),
]
DEBUFF_STOPS = [
    ("a negative aura 137 effect on another Effect stops", [se(900021, -10, -1, 31, effect=35)]),
    ("a negative aura 80 effect of another difficulty stops", [se(900022, -10, -1, 0, aura=80, difficulty=1)]),
]


def main():
    passed = failed = 0
    for name, rows, want in DEBUFF_CASES:
        got = gen.stat_debuffs(rows)
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    for name, rows in DEBUFF_STOPS:
        try:
            got = gen.stat_debuffs(rows)
        except SystemExit:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: no stop, got %r" % (name, got))
    for name, rows, want in CASES:
        got = gen.stat_mults(rows)
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: expected %r, got %r" % (name, want, got))
    for name, rows in STOPS:
        try:
            got = gen.stat_mults(rows)
        except SystemExit:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: no stop, got %r" % (name, got))
    print("%d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
