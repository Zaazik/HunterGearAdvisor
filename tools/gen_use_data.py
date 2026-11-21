"""Generates Game/UseData.lua: the stat buffs of gear "Use:" effects, priced by Score.SetValue over
their average uptime (duration / cooldown) while levelling, and in their windows of the raid fight in raid mode.

Sources (all read-only, Forever DB2 build 70888 exports):
  * ItemXItemEffect / ItemEffect: an item's effects; TriggerType 0 is "Use:". The ItemEffect row gives the
    cooldown (CoolDownMSec, -1 = the spell's own) and the shared category (SpellCategoryID,
    CategoryCoolDownMSec).
  * Item: InventoryType, 0 for items that are not worn (potions, elixirs, scrolls are left out).
  * SpellEffect / SpellEquippedItems: what the used spell does, read with tools/gen_set_data.py's
    spell_stats (the aura types as wowsims' parse_effects_table.go reads them: A_MOD_STAT 29, attack
    power 99 / 124, crit 52 / 290, hit 54, haste ...). A spell is taken only when every effect maps onto an
    HGA stat key and one of them is a key Model.Weights prices for damage.
  * SpellMisc (DurationIndex) / SpellDuration: how long the buff lasts; SpellCooldowns: the spell's cooldown
    when the item effect has none.
  * SpellAuraOptions (DifficultyID 0): ProcCharges, the charges of the buff's aura (see Skips); a spell without a
    row has none.
  * Spell (Description_lang): the description each CONDITIONAL_EFFECTS entry cites.
  * ItemSparse (names, for the comments only): the build 70888 export first, then the Era export for the
    classic rows the 70888 export lacks; SpellName when neither has the item.

Conditional effects: CONDITIONAL_EFFECTS leaves out the effects that hold only under a condition the Spell
description states and the SpellEffect rows do not carry.

Skips (printed, and listed in the generated file's header; the item's Use line stays "not counted"):
  * a buff whose aura lasts only while the user sits (SpellInterrupts AuraInterruptFlags_0 0x40000: drinks and food,
    "Must remain seated while drinking"): its mana comes in out of combat, and wowsims leaves such a spell out
    (sim/core/spelldata/consumable.go:21-25 WhileSeated);
  * a buff whose aura has charges (SpellAuraOptions ProcCharges > 0): it ends when the events of its ProcTypeMask
    use the charges up, before its duration runs out, so its uptime is not duration / cooldown, and HGA has no
    rate of those events to price it by. The script skips such a buff instead of stopping: HGA leaves a Use buff
    it cannot price out of the score, as it does every Use spell whose effects it cannot count (use_stats None).

Checks (the script stops instead of writing doubtful data):
  * one priced "Use:" effect per item, a duration and a cooldown above 0, no charges on the item effect;
  * at most one SpellAuraOptions row of DifficultyID 0 for a priced spell;
  * every non-empty DifficultyID 0 effect of a priced spell, the conditional ones included, is APPLY_AURA on
    TARGET_UNIT_CASTER: the buff is the used spell's own aura on the player, which Player.ReadStats looks up by
    that spell id to tell whether the buff's stats are in the character sheet values;
  * every CONDITIONAL_EFFECTS entry is used, its Spell description reads as cited and its effect indexes exist;
  * a shared category locks the other items for no longer than the buff lasts (SpellCategory 1141 "Item -
    Burst Trinket" sets CategoryCoolDownMSec to the buff's duration), so two buffs of one category never
    overlap but each runs its full uptime when used one after the other;
  * the uptimes a set can wear at once (the two largest trinkets plus the largest of every other slot type)
    add up to less than 1, so the buffs fit one after another.

Usage:
  python tools/gen_use_data.py --db2 <dir with SpellEffect.csv, SpellMisc.csv, SpellCooldowns.csv, SpellName.csv,
      SpellAuraOptions.csv, Spell.csv>
      --gear <dir with Item.csv, ItemEffect.csv, ItemXItemEffect.csv, SpellDuration.csv, SpellEquippedItems.csv>
      --names <ItemSparse.csv> [<ItemSparse.csv> ...] --interrupts <SpellInterrupts.csv> --out Game/UseData.lua

Tests: python -I tests/test_gen_use_data.py (the pricing rule, DAMAGE_KEYS, on synthetic rows).
"""
import argparse
import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_set_data as G  # noqa: E402  (spell_stats, read_csv, lua_num, lua_str)

TRIGGER_ON_USE = 0
INVTYPE_NON_EQUIP = 0
INVTYPE_TRINKET = 12
# Keys Model.Weights gives a damage weight (Core/Model.lua); a buff of other keys only is not priced. The attack power
# against each creature type: gen_set_data.CREATURE_TYPE_BITS (Core/Model.lua Model.CREATURE_TYPES); the attack speed of
# aura 9 or 342 and haste rating: gen_set_data.effect_stats' ATTACK_SPEED and rating_stats' HASTE_RATING; Spirit, MP5 and
# mana, which raid mode's fight prices through the mana (raid-mode design 6.8; levelling's weight 0 prices such a buff at
# 0 there).
DAMAGE_KEYS = {"AGI", "STR", "AP", "RAP", "MAP", "CRIT", "HIT", "HASTE", "MELEE_HASTE", "RANGED_HASTE", "ATTACK_SPEED",
               "HASTE_RATING", "EXPERTISE", "INT", "SPI", "MP5", "MANA"} | {"AP_VS_" + t for t in G.CREATURE_TYPE_BITS.values()}

# SpellInterrupts AuraInterruptFlags_0's bit that drops the aura when the unit stands up: the eating and drinking, whose
# mana comes in only while the user sits, out of combat; wowsims leaves such a spell out of its consumables and on-use
# effects (sim/core/spelldata/consumable.go:11-25 WhileSeated; sim/common/shared/consumable_potion.go:124-125,
# consumable_stats.go:91-98)
AURA_INTERRUPT_STANDING = 0x40000


def while_seated(spell, interrupts):
    """Whether the used spell's aura lasts only while the user sits (its DifficultyID 0 SpellInterrupts row holds
    AURA_INTERRUPT_STANDING in AuraInterruptFlags_0); a spell without a row does not."""
    rows = [r for r in interrupts.get(spell, []) if r["DifficultyID"] == "0"]
    if len(rows) > 1:
        raise SystemExit("spell %d has %d SpellInterrupts rows of DifficultyID 0" % (spell, len(rows)))
    return bool(rows) and int(rows[0]["AuraInterruptFlags_0"]) & AURA_INTERRUPT_STANDING != 0


# A_MOD_MELEE_HASTE_3 319 and A_MOD_RANGED_HASTE 140 (wowsims sim/core/dbcenums/auras.go): melee speed and ranged speed,
# wowsims' MeleeSpeedMultiplier and RangedSpeedMultiplier (sim/core/spelldata/parse_effects_table.go), each its own
# scope in the damage model: MELEE_HASTE the melee swings and the pet, RANGED_HASTE the shots and the hawks
# (Core/Model.lua p.meleeHaste / p.rangedHaste). A Use spell is priced with them only when it casts both of one amount,
# as Kiss of the Spider 22954 does (spell 28866); gen_set_data.effect_stats has no key for either, so a spell with one
# alone stays not counted (use_stats None).
A_MOD_MELEE_HASTE_3, A_MOD_RANGED_HASTE = 319, 140

# Effects that hold only under a condition the spell's Spell.csv Description_lang states and its SpellEffect rows do
# not carry: used spell -> (effect indexes left out, that description). The rest of the spell is counted.
# A condition on the whole amount that no effect row carries leaves the rows at the base amount, which is what the
# script counts: Molten Heart of the Mountain 249470 (spell 1249113: "This effect is doubled in Volcanic areas.") and
# Golden Banana 270226 (spell 1287571: "Effect and duration are doubled in Forest and Grassland areas.").
CONDITIONAL_EFFECTS = {
    # Flamebreak Talisman 280071: effects 0 and 1 are both A_MOD_STAT 29 Agility (misc 1) bp 33 (SpellEffect rows
    # 1348442, 1348471); $s2, effect 1, needs an elemental nearby (ruRU: "Если поблизости есть элементаль, повышает
    # ловкость еще на $s2.").
    1315878: ({1}, "Increase your agility by $s1 for $d. If there is an elemental nearby, gain an additional $s2."),
}


def unconditional_effects(spell, spell_effects, descriptions):
    """spell_effects with the CONDITIONAL_EFFECTS indexes of spell left out; stops when the spell's description is
    not the cited one or a listed index has no DifficultyID 0 row."""
    indexes, text = CONDITIONAL_EFFECTS[spell]
    if descriptions.get(spell) != text:
        raise SystemExit("spell %d: Spell description %r is not the one CONDITIONAL_EFFECTS cites: read it again"
                         % (spell, descriptions.get(spell)))
    rows = [e for e in spell_effects.get(spell, []) if e["DifficultyID"] == "0"]
    missing = indexes - {int(e["EffectIndex"]) for e in rows}
    if missing:
        raise SystemExit("spell %d has no effect %s that CONDITIONAL_EFFECTS leaves out" % (spell, sorted(missing)))
    return {spell: [e for e in rows if int(e["EffectIndex"]) not in indexes]}


def use_stats(spell, spell_effects, equip):
    """HGA stats of a used spell (gen_set_data.spell_stats), with a 319 + 140 pair of one amount as MELEE_HASTE and
    RANGED_HASTE; None when an effect cannot be counted."""
    rows = [e for e in spell_effects.get(spell, []) if e["DifficultyID"] == "0"]
    speed = {}
    rest = []
    for e in rows:
        aura = int(e["EffectAura"])
        if (int(e["Effect"]) == G.E_APPLY_AURA and aura in (A_MOD_MELEE_HASTE_3, A_MOD_RANGED_HASTE)
                and int(e["ImplicitTarget_0"]) == G.TARGET_UNIT_CASTER):
            speed[aura] = float(e["EffectBasePointsF"])
        else:
            rest.append(e)
    if not speed:
        return G.spell_stats(spell, spell_effects, equip)
    if set(speed) != {A_MOD_MELEE_HASTE_3, A_MOD_RANGED_HASTE} or speed[A_MOD_MELEE_HASTE_3] != speed[A_MOD_RANGED_HASTE]:
        return None
    stats = G.spell_stats(spell, {spell: rest}, equip) if rest else {}
    if stats is None:
        return None
    stats["MELEE_HASTE"] = stats.get("MELEE_HASTE", 0) + speed[A_MOD_MELEE_HASTE_3]
    stats["RANGED_HASTE"] = stats.get("RANGED_HASTE", 0) + speed[A_MOD_RANGED_HASTE]
    return stats


def priced_use_stats(spell, spell_effects, equip):
    """use_stats of a used spell when one of its keys is in DAMAGE_KEYS (the buff is priced); None otherwise (its Use
    line stays not counted). Tests: python -I tests/test_gen_use_data.py."""
    stats = use_stats(spell, spell_effects, equip)
    if not stats or not (set(stats) & DAMAGE_KEYS):
        return None
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db2", required=True)
    ap.add_argument("--gear", required=True)
    ap.add_argument("--names", nargs="+", required=True)
    ap.add_argument("--interrupts", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    items = {int(r["ID"]): r for r in G.read_csv(os.path.join(a.gear, "Item.csv"))}
    effects_by_id = {int(r["ID"]): r for r in G.read_csv(os.path.join(a.gear, "ItemEffect.csv"))}
    links = G.read_csv(os.path.join(a.gear, "ItemXItemEffect.csv"))
    durations = {int(r["ID"]): int(r["Duration"]) for r in G.read_csv(os.path.join(a.gear, "SpellDuration.csv"))}
    equip = {int(r["SpellID"]): r for r in G.read_csv(os.path.join(a.gear, "SpellEquippedItems.csv"))}
    spell_effects = collections.defaultdict(list)
    for e in G.read_csv(os.path.join(a.db2, "SpellEffect.csv")):
        spell_effects[int(e["SpellID"])].append(e)
    misc = {int(r["SpellID"]): r for r in G.read_csv(os.path.join(a.db2, "SpellMisc.csv")) if r["DifficultyID"] == "0"}
    spell_cd = {int(r["SpellID"]): r for r in G.read_csv(os.path.join(a.db2, "SpellCooldowns.csv"))
                if r["DifficultyID"] == "0"}
    names = {}
    for path in reversed(a.names):  # the first file wins
        for r in G.read_csv(path):
            names[int(r["ID"])] = r["Display_lang"]
    spell_names = {int(r["ID"]): r["Name_lang"] for r in G.read_csv(os.path.join(a.db2, "SpellName.csv"))}
    aura_options = collections.defaultdict(list)
    for r in G.read_csv(os.path.join(a.db2, "SpellAuraOptions.csv")):
        if r["DifficultyID"] == "0":
            aura_options[int(r["SpellID"])].append(r)
    descriptions = {int(r["ID"]): r["Description_lang"] for r in G.read_csv(os.path.join(a.db2, "Spell.csv"))}
    interrupts = collections.defaultdict(list)
    for r in G.read_csv(a.interrupts):
        interrupts[int(r["SpellID"])].append(r)

    out = {}
    no_effects = []  # worn items whose Use spell has no SpellEffect rows in the export: their Use line stays not counted
    used_up = []  # (item, spell, charges): buffs that events use up (Skips); their Use line stays not counted
    seated = []  # (item, spell): drinks and food whose aura lasts while the user sits (Skips); not counted
    conditional_used = set()
    for link in links:
        e = effects_by_id.get(int(link["ItemEffectID"]))
        if e is None or int(e["TriggerType"]) != TRIGGER_ON_USE:
            continue
        item_id = int(link["ItemID"])
        item = items.get(item_id)
        if item is None or int(item["InventoryType"]) == INVTYPE_NON_EQUIP:
            continue
        spell = int(e["SpellID"])
        if spell not in spell_effects:
            no_effects.append((item_id, spell))
            continue
        effects = spell_effects
        if spell in CONDITIONAL_EFFECTS:
            effects = unconditional_effects(spell, spell_effects, descriptions)
            conditional_used.add(spell)
        stats = priced_use_stats(spell, effects, equip)
        if stats is None:
            continue
        if while_seated(spell, interrupts):
            seated.append((item_id, spell))
            continue
        opts = aura_options.get(spell, [])
        if len(opts) > 1:
            raise SystemExit("item %d: spell %d has %d SpellAuraOptions rows of DifficultyID 0"
                             % (item_id, spell, len(opts)))
        charges = int(opts[0]["ProcCharges"]) if opts else 0
        if charges > 0:
            used_up.append((item_id, spell, charges))
            continue
        for row in spell_effects[spell]:
            if row["DifficultyID"] == "0" and int(row["Effect"]) != 0 and (
                    int(row["Effect"]) != G.E_APPLY_AURA or int(row["ImplicitTarget_0"]) != G.TARGET_UNIT_CASTER):
                raise SystemExit("item %d: spell %d effect %s is no aura on the caster (Effect %s, ImplicitTarget %s)"
                                 % (item_id, spell, row["EffectIndex"], row["Effect"], row["ImplicitTarget_0"]))
        if item_id in out:
            raise SystemExit("item %d has two priced Use effects (%d, %d)" % (item_id, out[item_id]["spell"], spell))
        if int(e["Charges"]) != 0:
            raise SystemExit("item %d: Use effect with charges %s" % (item_id, e["Charges"]))
        m = misc.get(spell)
        duration = durations.get(int(m["DurationIndex"])) if m else None
        if not duration or duration <= 0:
            raise SystemExit("item %d: spell %d has no duration" % (item_id, spell))
        cooldown = int(e["CoolDownMSec"])
        if cooldown <= 0:
            c = spell_cd.get(spell)
            cooldown = int(c["RecoveryTime"]) if c else 0
        if cooldown <= 0:
            raise SystemExit("item %d: spell %d has no cooldown" % (item_id, spell))
        category, category_cd = int(e["SpellCategoryID"]), int(e["CategoryCoolDownMSec"])
        if category != 0 and category_cd > duration:
            raise SystemExit("item %d: category %d locks for %d ms, longer than the %d ms buff"
                             % (item_id, category, category_cd, duration))
        out[item_id] = {"spell": spell, "stats": stats, "duration": duration / 1000, "cooldown": cooldown / 1000,
                        "inv": int(item["InventoryType"]), "category": category}
    unused = set(CONDITIONAL_EFFECTS) - conditional_used
    if unused:
        raise SystemExit("CONDITIONAL_EFFECTS lists spells no worn item's Use effect casts: %s" % sorted(unused))

    by_inv = collections.defaultdict(list)
    for v in out.values():
        by_inv[v["inv"]].append(v["duration"] / v["cooldown"])
    worn = 0.0
    for inv, ups in by_inv.items():
        ups.sort(reverse=True)
        worn += sum(ups[:2] if inv == INVTYPE_TRINKET else ups[:1])
    if worn >= 1:
        raise SystemExit("the uptimes a set can wear add up to %.3f" % worn)

    lines = [
        "-- On-use stat buffs of gear: itemID -> { spell = <used spell>, stats = { <HGA key> = amount }, duration = <s>,",
        "-- cooldown = <s> }. Units as Core/Parse.lua (HIT / CRIT / HASTE in %). Score.SetValue prices a buff over its",
        "-- average uptime, duration / cooldown, while levelling, and in its windows of the raid fight in raid mode (Model",
        "-- useWindows). category = the shared cooldown category (SpellCategory 1141 \"Item - Burst Trinket\": it locks the",
        "-- others for the buff's own duration only). The uptimes a set can wear add up to %.3f." % worn,
        "-- Generated by tools/gen_use_data.py (do not edit by hand) from the Forever DB2 (build 70888): ItemXItemEffect /",
        "-- ItemEffect (TriggerType 0), Item, SpellEffect, SpellEquippedItems, SpellMisc, SpellDuration, SpellCooldowns,",
        "-- SpellAuraOptions, SpellInterrupts, Spell.",
        "-- Every effect of each spell is APPLY_AURA on TARGET_UNIT_CASTER (checked): the buff is the spell's own aura on",
        "-- the player, which Player.ReadStats looks up by this spell id.",
    ]
    for spell in sorted(conditional_used):
        indexes, _ = CONDITIONAL_EFFECTS[spell]
        lines.append("-- Spell %d counts without its conditional effect %s (CONDITIONAL_EFFECTS in the generator)."
                     % (spell, ", ".join(str(i) for i in sorted(indexes))))
    for item_id, spell, charges in sorted(used_up):
        lines.append("-- Left out, its Use line stays not counted: %d %s, spell %d: an aura with %d charge%s"
                     % (item_id, names.get(item_id) or spell_names.get(spell, "?"), spell, charges,
                        "" if charges == 1 else "s"))
        lines.append("-- (SpellAuraOptions ProcCharges) that events use up before its duration ends.")
    for item_id, spell in sorted(seated):
        lines.append("-- Left out, its Use line stays not counted: %d %s, spell %d:"
                     % (item_id, names.get(item_id) or spell_names.get(spell, "?"), spell))
        lines.append("-- its aura lasts while the user sits (SpellInterrupts AuraInterruptFlags_0 0x40000), out of combat.")
    lines += [
        "local _, ns = ...",
        "",
        "ns.UseData = {",
    ]
    for item_id in sorted(out):
        v = out[item_id]
        stats = ", ".join("%s = %s" % (k, G.lua_num(v["stats"][k])) for k in sorted(v["stats"]))
        cat = ", category = %d" % v["category"] if v["category"] else ""
        lines.append("\t[%d] = { spell = %d, stats = { %s }, duration = %s, cooldown = %s%s }, -- %s"
                     % (item_id, v["spell"], stats, G.lua_num(v["duration"]), G.lua_num(v["cooldown"]), cat,
                        names.get(item_id) or "no ItemSparse name; spell: " + spell_names.get(v["spell"], "?")))
    lines.append("}")
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %d items to %s (worn uptime sum %.3f)" % (len(out), a.out, worn))
    print("%d worn items' Use spells have no SpellEffect rows (not priced): %s" % (len(no_effects), no_effects))
    print("%d priced Use buffs left out, used up by events (item, spell, SpellAuraOptions ProcCharges): %s"
          % (len(used_up), used_up))
    print("%d priced Use buffs left out, lasting while seated (item, spell): %s" % (len(seated), seated))


if __name__ == "__main__":
    main()
