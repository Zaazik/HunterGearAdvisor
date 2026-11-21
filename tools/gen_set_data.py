"""Generates Game/SetData.lua: item set bonuses as HGA stats.

Sources (all read-only, Forever DB2 build 1.60.1.70888 exports from wago.tools):
  * ItemSet: every item set, its name (Name_lang), SetFlags and the profession its bonuses need
    (RequiredSkill = SkillLine id, RequiredSkillRank = the rank of that skill).
  * ItemSetSpell: every bonus of every set: Threshold (pieces worn) and SpellID; ChrSpecID and
    TraitSubTreeID gate a bonus on a specialization / hero talent tree when not 0.
  * SpellEffect / SpellName / SpellEquippedItems: what each bonus spell does.

Aura types are read the way wowsims' sim/core/spelldata/parse_effects_table.go reads them (numbers
from sim/core/dbcenums/auras.go). A bonus spell becomes { n, spell, stats } only when every effect
of it maps onto an HGA stat key; otherwise it is { n, spell, unknown = "<SpellName>" } and the
tooltip says it is not counted. A stat bound to a weapon (WEAPON_BINDABLE) counts only on ranged weapons alone: the
crit of A_MOD_WEAPON_CRIT_PERCENT, HGA's CRIT_RANGED, and the hit of A_MOD_HIT_CHANCE, HGA's RANGED_HIT (effect_stats).

Checks (the script stops instead of writing doubtful data): ItemSet ids are unique; SetFlags is 0
(ItemConstantsDocumentation.lua Itemsetflags: Legacy 1, UseItemHistorySetSlots 2,
RequiresPvPTalentsActive 4 change when a bonus holds, HGA has no rule for them); RequiredSkill and
RequiredSkillRank are both 0 or both set; every ItemSetSpell row names a known set, a threshold of at
least 1, ChrSpecID 0 and TraitSubTreeID 0 (a bonus for one specialization or hero talent tree only:
HGA has no rule for it; build 70888 has none), and no row repeats a (set, threshold, spell); every
bonus spell but those of ABSENT_SPELLS has a SpellName row and SpellEffect rows (spell_stats).

Usage:
  python tools/gen_set_data.py --sets <dir with ItemSet.csv, ItemSetSpell.csv>
      --db2 <dir with SpellEffect.csv, SpellName.csv> --equip <SpellEquippedItems.csv> --out Game/SetData.lua

Tests: python -I tests/test_gen_set_data.py (the rules no set bonus of build 70888 exercises, on synthetic rows);
tests/test_score.lua scores real sets with the generated Game/SetData.lua.
"""
import argparse
import collections
import csv
import os
import sys


# Effect and target ids (wowsims sim/core/dbcenums/effects.go, targets.go).
E_APPLY_AURA = 6
TARGET_UNIT_CASTER = 1
ITEM_CLASS_WEAPON = 2

# Auras wowsims binds to the weapon its SpellEquippedItems row names (WeaponBindable in
# sim/core/spelldata/weapon_scope.go): on such a row the stat holds for that weapon only.
WEAPON_BINDABLE = {54, 52, 290, 189, 79, 55, 10}

# Ranged weapon subclass bits of an EquippedItemSubclass mask: bows 2, guns 3, thrown 16, crossbows 18, wands 19
# (wowsims sim/core/dbcenums/item_subclass.go ITEM_SUBCLASS_MASK_WEAPON_RANGED).
RANGED_WEAPON_SUBCLASSES = (1 << 2) | (1 << 3) | (1 << 16) | (1 << 18) | (1 << 19)
A_MOD_WEAPON_CRIT_PERCENT = 52
A_MOD_HIT_CHANCE = 54

# The creature types of a versus aura's misc mask, bit 1 << (CreatureType - 1) -> HGA's AP_VS_<TYPE> key suffix
# (wowsims sim/core/spelldata/mob_types.go:32-55: Beast 1, Dragonkin 2, Demon 3, Elemental 4, Giant 5, Undead 6,
# Humanoid 7, Mechanical 9; Critter 8 has no mob type there). Core/Model.lua Model.CREATURE_TYPES lists the same keys.
CREATURE_TYPE_BITS = {1 << 0: "BEAST", 1 << 1: "DRAGONKIN", 1 << 2: "DEMON", 1 << 3: "ELEMENTAL", 1 << 4: "GIANT",
                      1 << 5: "UNDEAD", 1 << 6: "HUMANOID", 1 << 8: "MECHANICAL"}


def versus_keys(mask):
    """The AP_VS_<TYPE> keys a creature-type mask names, or None when it names a bit outside the eight types (or none)."""
    keys = [("AP_VS_" + t) for bit, t in sorted(CREATURE_TYPE_BITS.items()) if mask & bit]
    rest = mask
    for bit in CREATURE_TYPE_BITS:
        rest &= ~bit
    if rest or not keys:
        return None
    return keys


# A_MOD_STAT misc -> stat (parse_effects_table.go clientStats: Strength, Agility, Stamina,
# Intellect, Spirit; misc -1 = all five).
CLIENT_STATS = ["STR", "AGI", "STA", "INT", "SPI"]

# A_MOD_SKILL misc (skill line) -> HGA key. A_MOD_SKILL's misc value is a SkillLine id (Game/Player.lua WEAPON_SKILL):
# Defense 95, the ranged lines Bows 45, Guns 46, Crossbows 226, and the melee lines Swords 43, Axes 44, Maces 54,
# Two-Handed Swords 55, Staves 136, Two-Handed Maces 160, Two-Handed Axes 172, Daggers 173, Polearms 229, Fist Weapons
# 473: the weapon skills HGA scores (Core/Score.lua RANGED_SKILL, MELEE_SKILL; Parse TOOLTIP_ITEM_STAT_SKILL_*)
SKILL_KEYS = {95: "DEFENSE", 45: "SKILL_BOWS", 46: "SKILL_GUNS", 226: "SKILL_CROSSBOWS",
              43: "SKILL_SWORDS", 44: "SKILL_AXES", 54: "SKILL_MACES", 55: "SKILL_2H_SWORDS", 136: "SKILL_STAVES",
              160: "SKILL_2H_MACES", 172: "SKILL_2H_AXES", 173: "SKILL_DAGGERS", 229: "SKILL_POLEARMS", 473: "SKILL_FIST"}

# A_MOD_RATING mask bits (sim/core/dbcenums/ratings.go) and the Forever rating per 1% at every
# level (Forever DB2 combat ratings table: hit 10, crit 14, haste 10, expertise 10; the same table
# Core/Parse.lua's rating templates use).
R_DEFENSE, R_DODGE, R_PARRY, R_BLOCK = 0x2, 0x4, 0x8, 0x10
R_HIT_MELEE, R_HIT_RANGED, R_HIT_SPELL = 0x20, 0x40, 0x80
R_CRIT_MELEE, R_CRIT_RANGED, R_CRIT_SPELL = 0x100, 0x200, 0x400
R_HASTE_MELEE, R_HASTE_RANGED, R_HASTE_SPELL = 0x20000, 0x40000, 0x80000
R_EXPERTISE = 0x800000
KNOWN_RATING_BITS = (R_HIT_MELEE | R_HIT_RANGED | R_HIT_SPELL | R_CRIT_MELEE | R_CRIT_RANGED | R_CRIT_SPELL
                     | R_HASTE_MELEE | R_HASTE_RANGED | R_HASTE_SPELL | R_EXPERTISE)


def rating_stats(mask, v):
    """HGA stats of an A_MOD_RATING effect, or None when the mask holds a rating HGA has no key for
    or a melee / ranged half alone (HGA's HIT, CRIT and HASTE_RATING are melee and ranged together). Haste rating is
    HASTE_RATING, as Core/Parse.lua reads the item lines: wowsims gives it the hunter's own attacks alone (sim/core/
    unit.go:564-566 hasteRatingMultiplier on the owner's totals; the pet and the hawks inherit speed multipliers, not the
    rating, sim/core/pet.go:381-431)."""
    if mask & ~KNOWN_RATING_BITS:
        return None
    out = {}
    for melee, ranged, key, per in ((R_HIT_MELEE, R_HIT_RANGED, "HIT", 10), (R_CRIT_MELEE, R_CRIT_RANGED, "CRIT", 14),
                                    (R_HASTE_MELEE, R_HASTE_RANGED, "HASTE_RATING", 10)):
        has_m, has_r = bool(mask & melee), bool(mask & ranged)
        if has_m != has_r:
            return None
        if has_m:
            out[key] = v / per
    if mask & R_HIT_SPELL:
        out["SPELL_HIT"] = v / 10
    if mask & R_CRIT_SPELL:
        out["SPELL_CRIT"] = v / 14
    if mask & R_HASTE_SPELL:
        out["CAST_SPEED"] = v / 10
    if mask & R_EXPERTISE:
        out["EXPERTISE"] = v / 10
    return out


def effect_stats(e, weapon_bound, ranged_only):
    """HGA stats of one SpellEffect row, or None when HGA cannot count it. weapon_bound: the spell's
    SpellEquippedItems row asks for a weapon; ranged_only: that row names ranged weapons alone.

    Keys with no damage weight (SPELL_HIT, SPELL_CRIT, CAST_SPEED, HEALING, RESIST, SPELL_POWER,
    DEFENSE, DODGE, PARRY, BLOCK) mark effects that are known and worth nothing for a hunter's
    damage; Score skips keys W has no weight for."""
    effect, aura = int(e["Effect"]), int(e["EffectAura"])
    if effect == 0:
        return {}  # an empty effect slot
    if effect != E_APPLY_AURA or int(e["ImplicitTarget_0"]) != TARGET_UNIT_CASTER:
        return None
    if weapon_bound and aura in WEAPON_BINDABLE:
        # A_MOD_WEAPON_CRIT_PERCENT on ranged weapons alone is a crit of the attacks made with the ranged weapon
        # (wowsims weapon_scope.go WeaponScope: per weapon, ProcMaskRanged), HGA's CRIT_RANGED, which Score prices
        # at W.CRIT_RANGED as it does the crit scope's (Core/Parse.lua, SpellItemEnchantment 8720). A_MOD_HIT_CHANCE on
        # ranged weapons alone is the ranged-only hit wowsims folds into RangedHitPercent (tools/database/dbc/util.go:
        # 356-373), which the pet and the hawks inherit with the physical hit (sim/hunter/pets.go:155-158): HGA's
        # RANGED_HIT, which Score prices at W.RANGED_HIT up to the cap as it does the hit scopes' (Core/Parse.lua,
        # SpellItemEnchantment 2523 / 8057). Every other weapon-bound stat stays unknown: HGA has no key for a melee
        # weapon's own crit or hit.
        if aura == A_MOD_WEAPON_CRIT_PERCENT and ranged_only:
            return {"CRIT_RANGED": float(e["EffectBasePointsF"])}
        if aura == A_MOD_HIT_CHANCE and ranged_only:
            return {"RANGED_HIT": float(e["EffectBasePointsF"])}
        return None
    misc = int(e["EffectMiscValue_0"])
    v = float(e["EffectBasePointsF"])
    if aura == 29:  # A_MOD_STAT
        if misc == -1:
            return {k: v for k in CLIENT_STATS}
        if 0 <= misc < 5:
            return {CLIENT_STATS[misc]: v}
        return None
    if aura == 99:  # A_MOD_ATTACK_POWER: melee attack power
        return {"MAP": v}
    if aura == 124:  # A_MOD_RANGED_ATTACK_POWER
        return {"RAP": v}
    if aura == 54:  # A_MOD_HIT_CHANCE: melee and ranged hit (stats.PhysicalHitPercent)
        return {"HIT": v}
    if aura == 55:  # A_MOD_SPELL_HIT_CHANCE
        return {"SPELL_HIT": v}
    if aura == 52:  # A_MOD_WEAPON_CRIT_PERCENT: melee and ranged crit (stats.PhysicalCritPercent)
        return {"CRIT": v}
    if aura == 290:  # A_MOD_CRIT_PCT: physical and spell crit
        return {"CRIT": v, "SPELL_CRIT": v}
    if aura == 57:  # A_MOD_SPELL_CRIT_CHANCE
        return {"SPELL_CRIT": v}
    if aura == 189:  # A_MOD_RATING
        return rating_stats(misc, v)
    if aura == 240:  # A_MOD_EXPERTISE: percent (stats.ExpertisePercent)
        return {"EXPERTISE": v}
    if aura == 85:  # A_MOD_POWER_REGEN: mana per 5 s on misc 0 (POWER_MANA)
        return {"MP5": v} if misc == 0 else None
    if aura == 13:  # A_MOD_DAMAGE_DONE: flat damage by school; HGA keeps magic schools as SPELL_POWER
        return {"SPELL_POWER": v} if misc != 0 and misc & 1 == 0 else None
    if aura == 135:  # A_MOD_HEALING_DONE
        return {"HEALING": v}
    if aura == 22:  # A_MOD_RESISTANCE: school 1 is armor, the other bits the magic resistances
        out = {}
        if misc & 1:
            out["ARMOR"] = v
        if misc & 126:
            out["RESIST"] = v
        return out or None
    if aura == 674:  # A_MOD_ARMOR_NO_MODS on the armor bit alone
        return {"ARMOR": v} if misc == 1 else None
    if aura == 30:  # A_MOD_SKILL
        key = SKILL_KEYS.get(misc)
        return {key: v} if key else None
    if aura in (34, 230):  # A_MOD_INCREASE_HEALTH, A_MOD_MAX_HEALTH
        return {"HEALTH": v}
    if aura == 35:  # A_MOD_INCREASE_ENERGY on misc 0 (mana)
        return {"MANA": v} if misc == 0 else None
    if aura in (9, 342):
        # A_MOD_ATTACKSPEED, A_MOD_MELEE_RANGED_HASTE_2: wowsims' attackSpeedRow for both (sim/core/spelldata/
        # parse_effects_table.go:367-368, 1048-1050), MultiplyAttackSpeed, which a set bonus and a parsed buff take
        # (ParsedSetBonus -> ParseEffects, sim/common/shared/item_sets.go:16-28): the owner's melee and ranged speed and
        # the tamed pet (sim/core/unit.go:729-742, the DynamicMeleeSpeedPets), not the hawks, which inherit the ranged
        # speed multiplier alone (sim/core/pet.go:415-431): HGA's ATTACK_SPEED
        return {"ATTACK_SPEED": v}
    if aura == 192:
        # A_MOD_MELEE_RANGED_HASTE: no row of wowsims' parse table and no handler in sim/ reads it, so HGA has no rule for
        # it; no set bonus or item effect of build 70888 carries it
        raise SystemExit("spell %s has an aura 192 (A_MOD_MELEE_RANGED_HASTE) effect: HGA has no rule for it"
                         % e["SpellID"])
    if aura == 65:
        # A_MOD_CASTING_SPEED_NOT_STACK: a hunter's shots take their cast time from ranged speed
        # (wowsims sim/hunter/hunter.go: Cast.CastTime = ApplyRangedSpeed), so casting speed adds nothing
        return {"CAST_SPEED": v}
    if aura == 47:
        return {"PARRY": v}
    if aura == 49:
        return {"DODGE": v}
    if aura == 51:
        return {"BLOCK": v}
    return None


def spell_stats(spell, effects, equip):
    """Stats of a bonus spell, or None when one of its effects cannot be counted. A melee and a
    ranged attack power versus the same creature types (A_MOD_MELEE_ATTACK_POWER_VERSUS 102 +
    A_MOD_RANGED_ATTACK_POWER_VERSUS 131, one misc mask) are HGA's AP_VS_<TYPE>, one key for each type the mask
    names (versus_keys; a mask with a bit outside the eight types makes the spell unknown); equal melee and ranged
    attack power are AP (melee and ranged, as Parse reads "+N к силе атаки")."""
    rows = [e for e in effects.get(spell, []) if e["DifficultyID"] == "0"]
    if not rows:
        raise SystemExit("spell %d has no SpellEffect rows" % spell)
    eq = equip.get(spell)
    weapon_bound = eq is not None and int(eq["EquippedItemClass"]) == ITEM_CLASS_WEAPON
    # ranged weapons alone: a subclass mask of ranged bits and no other, no inventory type mask
    ranged_only = (weapon_bound and int(eq["EquippedItemInvTypes"]) == 0 and int(eq["EquippedItemSubclass"]) != 0
                   and int(eq["EquippedItemSubclass"]) & ~RANGED_WEAPON_SUBCLASSES == 0)
    versus = {}
    total = collections.defaultdict(float)
    for e in rows:
        aura = int(e["EffectAura"])
        if int(e["Effect"]) == E_APPLY_AURA and aura in (102, 131) and int(e["ImplicitTarget_0"]) == TARGET_UNIT_CASTER:
            versus[aura] = (int(e["EffectMiscValue_0"]), float(e["EffectBasePointsF"]))
            continue
        st = effect_stats(e, weapon_bound, ranged_only)
        if st is None:
            return None
        for k, v in st.items():
            total[k] += v
    if versus:
        if set(versus) != {102, 131} or versus[102] != versus[131]:
            return None
        keys = versus_keys(versus[102][0])
        if keys is None:
            return None
        for k in keys:
            total[k] += versus[102][1]
    ap = min(total.get("MAP", 0), total.get("RAP", 0))
    if ap > 0:
        total["AP"] += ap
        total["MAP"] -= ap
        total["RAP"] -= ap
    return {k: v for k, v in total.items() if v != 0}


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_num(v):
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    return ("%.4f" % v).rstrip("0")


# Bonus spells ItemSetSpell names that the build 70888 Spell, SpellName and SpellEffect exports do not have: the
# Season of Discovery sets 1593 Felheart of the Wicked (8 pieces 438169), 1662 Lawbringer Radiance (3 / 5 / 8:
# 447284 / 447285 / 447286), 1663 Nightslayer Battlearmor (3 / 5 / 8: 447289 / 447291 / 447292) and 1664 Cenarion
# Eclipse (3 / 8: 447295 / 447294). No ItemSparse row of that export names these sets; ItemSet lists one item for
# 1664 (221785, an Item.csv row without an ItemSparse row). Nothing says what the spells do, so these bonuses stay
# unknown; any other bonus spell missing from those tables stops the script, and so does a spell of this list that
# the tables do have.
ABSENT_SPELLS = {438169, 447284, 447285, 447286, 447289, 447291, 447292, 447294, 447295}


def read_sets(path):
    """setID -> (name, skill line or None, skill rank or None) from ItemSet.csv."""
    sets = {}
    for r in read_csv(path):
        sid = int(r["ID"])
        if sid in sets:
            raise SystemExit("ItemSet %d twice" % sid)
        if int(r["SetFlags"]) != 0:
            raise SystemExit("ItemSet %d has SetFlags %s: HGA has no rule for set flags" % (sid, r["SetFlags"]))
        skill, rank = int(r["RequiredSkill"]), int(r["RequiredSkillRank"])
        if (skill == 0) != (rank == 0):
            raise SystemExit("ItemSet %d: RequiredSkill %d with RequiredSkillRank %d" % (sid, skill, rank))
        sets[sid] = (r["Name_lang"], skill or None, rank or None)
    return sets


def read_set_spells(path, sets):
    """setID -> [(threshold, spell id)] in (threshold, ItemSetSpell ID) order from ItemSetSpell.csv."""
    rows = collections.defaultdict(list)
    seen = set()
    for r in read_csv(path):
        rid, sid, n, spell = int(r["ID"]), int(r["ItemSetID"]), int(r["Threshold"]), int(r["SpellID"])
        if sid not in sets:
            raise SystemExit("ItemSetSpell %d names set %d, which ItemSet lacks" % (rid, sid))
        if n < 1:
            raise SystemExit("ItemSetSpell %d: threshold %d" % (rid, n))
        if int(r["ChrSpecID"]) != 0 or int(r["TraitSubTreeID"]) != 0:
            raise SystemExit("ItemSetSpell %d: ChrSpecID %s / TraitSubTreeID %s gate the bonus on a specialization: "
                             "HGA has no rule for it" % (rid, r["ChrSpecID"], r["TraitSubTreeID"]))
        if (sid, n, spell) in seen:
            raise SystemExit("ItemSetSpell %d repeats set %d, %d pieces, spell %d" % (rid, sid, n, spell))
        seen.add((sid, n, spell))
        rows[sid].append((n, rid, spell))
    return {sid: [(n, spell) for n, _, spell in sorted(v)] for sid, v in rows.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sets", required=True)
    ap.add_argument("--db2", required=True)
    ap.add_argument("--equip", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    effects = collections.defaultdict(list)
    for r in read_csv(os.path.join(a.db2, "SpellEffect.csv")):
        effects[int(r["SpellID"])].append(r)
    names = {int(r["ID"]): r["Name_lang"] for r in read_csv(os.path.join(a.db2, "SpellName.csv"))}
    equip = {}
    for r in read_csv(a.equip):
        sid = int(r["SpellID"])
        if sid in equip:
            raise SystemExit("spell %d has two SpellEquippedItems rows" % sid)
        equip[sid] = r

    sets = read_sets(os.path.join(a.sets, "ItemSet.csv"))
    bonuses = read_set_spells(os.path.join(a.sets, "ItemSetSpell.csv"), sets)

    lines = [
        "-- Item set bonuses: setID -> { name = <set name>, skill = <SkillLine id>, skillRank = <rank>, { n = <pieces>,",
        "-- spell = <bonus spell>, stats = { <HGA key> = amount } } or { n, spell, unknown = <spell name> } for a bonus",
        "-- HGA cannot count }, the bonuses in piece order. skill / skillRank: the profession and the rank of it the set's",
        "-- bonuses need (the ItemSet row's RequiredSkill / RequiredSkillRank), nil for none. A set without ItemSetSpell",
        "-- rows has no entries. Units as Core/Parse.lua (HIT / CRIT / CRIT_RANGED / ATTACK_SPEED / HASTE_RATING / EXPERTISE",
        "-- in %; CRIT_RANGED: the crit of the ranged weapon's attacks alone; ATTACK_SPEED: aura 9 or 342, the owner's speed",
        "-- and the pet's, not the hawks'). Keys with no damage weight (SPELL_HIT, SPELL_CRIT, CAST_SPEED,",
        "-- HEALING, RESIST, SPELL_POWER, ...) are effects that do nothing for a hunter's damage; Score skips keys W has",
        "-- no weight for.",
        "-- Generated by tools/gen_set_data.py (do not edit by hand) from the Forever DB2 (build 1.60.1.70888): ItemSet",
        "-- (sets, names, professions), ItemSetSpell (every bonus: pieces and spell) and the SpellEffect / SpellName /",
        "-- SpellEquippedItems rows of each bonus spell.",
        "local _, ns = ...",
        "",
        "ns.SetData = {",
    ]
    counted = unknown = 0
    for sid in sorted(sets):
        name, skill, rank = sets[sid]
        skill_field = (" skill = %d, skillRank = %d," % (skill, rank)) if skill else ""
        lines.append("\t[%d] = { name = %s,%s" % (sid, lua_str(name), skill_field))
        for n, spell in bonuses.get(sid, []):
            if spell in ABSENT_SPELLS:
                if spell in names or spell in effects:
                    raise SystemExit("spell %d is in ABSENT_SPELLS but the DB2 has it: read it" % spell)
                unknown += 1
                lines.append("\t\t{ n = %d, spell = %d, unknown = %s }," % (n, spell, lua_str("spell %d (no DB2 row)" % spell)))
                continue
            if spell not in names:
                raise SystemExit("spell %d (set %d) has no SpellName row" % (spell, sid))
            st = spell_stats(spell, effects, equip)
            if st is None:
                unknown += 1
                lines.append("\t\t{ n = %d, spell = %d, unknown = %s }," % (n, spell, lua_str(names[spell])))
            else:
                counted += 1
                body = ", ".join("%s = %s" % (k, lua_num(v)) for k, v in sorted(st.items()))
                lines.append("\t\t{ n = %d, spell = %d, stats = { %s } }," % (n, spell, body))
        lines.append("\t},")
    lines.append("}")
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%d sets (%d without bonuses), %d bonuses counted, %d unknown" % (
        len(sets), sum(1 for s in sets if s not in bonuses), counted, unknown), file=sys.stderr)


if __name__ == "__main__":
    main()
