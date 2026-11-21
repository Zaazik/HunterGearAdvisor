# Pre-raid set optimizer for the WoW Forever hunter (ranged / turret EP).
# Data: wowsims/forever assets/database/db.json (commit 6084403), set bonuses from client DB2 ItemSet/ItemSetSpell/SpellEffect
# (wago, build 1.60.1.70888), recipe items from client DB2 ItemEffect/ItemXItemEffect (same build), where a recipe
# comes from by foreverdb.net (pattern_sources.tsv), sources of new-dungeon items from ForeverGuide NewDungeonData.lua.
import json, csv, re, sys, itertools, os, importlib.util
csv.field_size_limit(10**9)
SP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(SP, 'taskA/forever/assets/database/db.json')
T = os.path.join(SP, 'trinkets')
FG = r'D:/wow/World of Warcraft/_forever_/Interface/AddOns/ForeverGuide/NewDungeonData.lua'
HIT_CAP = int(sys.argv[1]) if len(sys.argv) > 1 else 80   # rating; 8% raid boss cap (10 rating = 1%)

d = json.load(open(DB, encoding='utf-8'))
zones = {z['id']: z['name'] for z in d['zones']}
npcs = {n['id']: (n['name'], n.get('zoneId')) for n in d['npcs']}
factions = {f['id']: f['name'] for f in d['factions']}

# Turret EP (wowsims ui/specs/hunter/dps/presets.ts), Agility units, measured at the 8% hit cap
EP = {1: 1.0, 3: 0.42, 15: 0.34, 17: 1.14, 18: 0.84, 19: 0.8, 'mp5': 0.14, 'rdps': 2.87}
RAID_ZONES = {1977, 2159, 2677, 2717, 3428, 3429, 3456, 3478, 16076}
RAID_QUESTS = {7491: 'Onyxia head quest'}
RAID_CRAFTS = {15141: 'needs Onyxia Scale'}
AH = {}
for line in open(os.path.join(SP, 'opt', 'ah.tsv'), encoding='utf-8'):
    a = line.split('	'); AH[int(a[0])] = (int(a[1]), int(a[2]), a[4].strip() == 'true')
# Recipes: the client DB2 links a craft spell to the items that teach it - ItemEffect rows with TriggerType 6 (learn)
# name the spell, ItemXItemEffect gives their item. Where a recipe drops or is sold: its own sources in db.json, when
# db.json lists the recipe item (wowsims 6084403 lists gear only, no recipe items), else the "Where to get it" list of
# its foreverdb.net page: pattern_sources.tsv, which gen_pattern_sources.py (next to this file) writes from the saved
# pages <id>.html; that file also holds the rule (recipe_sources, craft_gettable), loaded by its path.
_spec = importlib.util.spec_from_file_location('gen_pattern_sources', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gen_pattern_sources.py'))
PS = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(PS)
FDB = PS.read_tsv(os.path.join(SP, 'opt', 'pattern_sources.tsv'))
NO_FDB_ROW = set()   # recipes looked up that have no row: an error before anything is written
_learn = {r['ID']: int(r['SpellID']) for r in csv.DictReader(open(os.path.join(T, 'ItemEffect.csv'), encoding='utf-8'))
          if r['TriggerType'] == '6'}
TAUGHT_BY = {}   # craft spell -> recipe item ids (some have no ItemSparse row, so no name: 221339 in build 70888)
for r in csv.DictReader(open(os.path.join(T, 'ItemXItemEffect.csv'), encoding='utf-8')):
    if r['ItemEffectID'] in _learn: TAUGHT_BY.setdefault(_learn[r['ItemEffectID']], []).append(int(r['ItemID']))
DB_ITEMS = {it['id']: it for it in d['items']}
BOND = {}
NAME = {}
_r = csv.reader(open(os.path.join(SP, 'opt', 'ItemSparse.csv'), encoding='utf-8')); _h = next(_r); _bi, _ni = _h.index('Bonding'), _h.index('Display_lang')
for _row in _r: BOND[int(_row[0])], NAME[int(_row[0])] = int(_row[_bi]), _row[_ni]
MY_PROFS = {8}   # Leatherworking, the character's profession (its WowSimsExporter export, 2026-11-20); wowsims profession 8 = LW, 2 = BS
BAD_REP = {2819: 'The Watchers (raid rep)', 910: 'Brood of Nozdormu (AQ)'}

# new-dungeon boss -> item ids
fg_src = {}
txt = open(FG, encoding='utf-8', errors='replace').read()
for m in re.finditer(r'\{\["n"\]="([^"]+)",\["r"\]="[^"]*",\["id"\]=(\d+),\["ids"\]=\{([0-9,]+)\}', txt):
    npc = int(m.group(3 - 1)) if False else int(m.group(2))
    for i in m.group(3).split(','):
        fg_src[int(i)] = f'drop {m.group(1)} (npc {npc}, ForeverGuide)'

def db_where(rid):
    """A recipe item's own sources in db.json as one text, '' when db.json does not list it."""
    return ', '.join(sources(DB_ITEMS[rid])[0]) if rid in DB_ITEMS else ''

def sources(it):
    out, bad = [], []
    for s in it.get('sources') or []:
        k, v = next(iter(s.items()))
        if v.get('faction') == 1: bad.append('Alliance'); continue
        if k == 'drop':
            z = v.get('zoneId'); nm = npcs.get(v.get('npcId'), (v.get('otherName') or 'world', None))[0]
            if z in RAID_ZONES: bad.append(f'raid {zones.get(z)}'); continue
            out.append(f'drop {nm} @ {zones.get(z, z)}')
        elif k == 'quest' and v.get('id') in RAID_QUESTS: bad.append(RAID_QUESTS[v['id']]); continue
        elif k == 'quest': out.append(f"quest {v.get('id')} {v.get('name')}")
        elif k == 'soldBy': out.append(f"vendor {v.get('npcName')} @ {zones.get(v.get('zoneId'), v.get('zoneId'))}")
        elif k == 'crafted':
            if BOND.get(it['id']) == 1 and v.get('profession') not in MY_PROFS:
                bad.append(f"BoP craft, needs profession {v.get('profession')}"); continue
            recipes = TAUGHT_BY.get(v.get('spellId'), [])
            if not recipes:
                out.append(f"crafted, spell {v.get('spellId')}: no recipe item teaches it (DB2)"); continue
            wheres = PS.recipe_sources(recipes, FDB, db_where)
            NO_FDB_ROW.update(rid for rid, where in wheres if where is None)
            if not PS.craft_gettable(it['id'] in AH, wheres, AH):
                bad.append(f"craft: recipe {', '.join(map(str, recipes))} source unknown (db.json, foreverdb.net), neither recipe nor item ever seen on AH"); continue
            for rid, where in wheres:
                out.append(f"crafted, recipe {NAME.get(rid, '(no ItemSparse row)')} {rid}: " + (where or 'source unknown (db.json, foreverdb.net)')
                           + (' (recipe on AH %.0fg)' % (AH[rid][0] / 10000) if rid in AH else ''))
        elif k == 'rep':
            f = v.get('repFactionId')
            if f in BAD_REP: bad.append(BAD_REP[f]); continue
            if v.get('factionId') == 1: bad.append('Alliance'); continue
            out.append(f"rep {factions.get(f, f)} lvl {v.get('repLevel')}")
        elif k == 'pvp': bad.append('PvP rank')
    if not out and not bad and it['id'] in fg_src: out.append(fg_src[it['id']])
    if it['id'] in RAID_CRAFTS: return [], [RAID_CRAFTS[it['id']]]
    if it['id'] in AH: out.append('AH %.2fg' % (AH[it['id']][0] / 10000) + (' (gone now)' if AH[it['id']][2] else ''))
    return out, bad

# set bonuses from client DB2
sets = {r['ID']: r['Name_lang'] for r in csv.DictReader(open(os.path.join(T, 'ItemSet.csv'), encoding='utf-8'))}
setspells = {}
for r in csv.DictReader(open(os.path.join(T, 'ItemSetSpell.csv'), encoding='utf-8')):
    setspells.setdefault(int(r['ItemSetID']), []).append((int(r['Threshold']), int(r['SpellID'])))
eff = {}
rd = csv.reader(open(os.path.join(T, 'SpellEffect.csv'), encoding='utf-8')); h = next(rd)
ix = {k: h.index(k) for k in ('SpellID', 'EffectAura', 'EffectBasePointsF', 'EffectMiscValue_0')}
for row in rd:
    eff.setdefault(int(row[ix['SpellID']]), []).append((int(row[ix['EffectAura']]), float(row[ix['EffectBasePointsF']] or 0), int(row[ix['EffectMiscValue_0']] or 0)))
desc = {}
for r in csv.DictReader(open(os.path.join(T, 'Spell.csv'), encoding='utf-8')):
    desc[int(r['ID'])] = r['Description_lang']

def spell_value(sid):
    """EP value of a passive set-bonus spell; returns (value_no_hit, hit_rating, text)."""
    v, hit = 0.0, 0
    for aura, bp, misc in eff.get(sid, []):
        if aura == 99 or aura == 124: v += bp * EP[15]            # AP / RAP
        elif aura == 29 and misc == 1: v += bp * EP[1]            # agility
        elif aura == 54: hit += round(bp * 10)                    # hit % (55 = spell hit duplicate)
        elif aura in (52, 57, 290): v += bp * 14 * EP[18]         # crit %
        elif aura == 189:                                         # rating, misc mask
            if misc & (1 << 5) or misc & (1 << 6): hit += bp          # hit rating
            elif misc & (1 << 8) or misc & (1 << 9): v += bp * EP[18]
    return v, hit, desc.get(sid, '')

def wearable(it):
    t = it.get('type', 0)
    if not t: return False
    if it.get('factionRestriction') == 1: return False   # 1 = Alliance-only (checked on Horde items: 2)
    ca = it.get('classAllowlist')
    if ca and 3 not in ca: return False
    if t <= 10: return it.get('armorType', 0) in (0, 1, 2, 3)
    if t in (11, 12): return True
    if t == 13: return it.get('weaponType') in (1, 2, 3, 6, 8, 9) and it.get('handType') in (1, 2, 3, 4)
    if t == 14: return it.get('rangedWeaponType') in (1, 2, 3)
    return False

def stats(it):
    s = (it.get('scalingOptions', {}).get('0') or {}).get('stats') or {}
    ps = it.get('pseudoStats') or []
    p = lambda i: ps[i] if i < len(ps) else 0
    g = lambda k: s.get(str(k), 0)
    hit = g(17) + round(10 * max(p(24), p(12)))
    crit = g(18) + 14 * max(p(25), p(14))
    v = EP[1] * g(1) + EP[3] * g(3) + EP[15] * max(g(14), g(15)) + EP[18] * crit + EP[19] * g(19) + EP['mp5'] * g(47 if False else 0)
    so = it.get('scalingOptions', {}).get('0') or {}
    rdps = (so.get('weaponDamageMin', 0) + so.get('weaponDamageMax', 0)) / 2 / it['weaponSpeed'] if it['type'] == 14 and it.get('weaponSpeed') else 0
    if it['type'] == 14: v += EP['rdps'] * rdps
    txt = []
    for k, n in ((1, 'Agi'), (3, 'Int'), (2, 'Sta')):
        if g(k): txt.append(f'+{g(k)} {n}')
    if max(g(14), g(15)): txt.append(f'+{max(g(14), g(15))} AP')
    if hit: txt.append(f'+{hit/10:g}% hit')
    if crit: txt.append(f'+{crit/14:.2g}% crit')
    if g(19): txt.append(f'+{g(19)/10:g}% haste')
    if it['type'] == 14: txt.append(f"{rdps:.1f} DPS @{it['weaponSpeed']}")
    return v, hit, ', '.join(txt)

SLOT = {1: 'head', 2: 'neck', 3: 'shoulder', 4: 'back', 5: 'chest', 6: 'wrist', 7: 'hands', 8: 'waist', 9: 'legs', 10: 'feet', 11: 'finger', 12: 'trinket', 13: 'weapon', 14: 'ranged'}
cands, excluded = {}, []
for it in d['items']:
    if it.get('phase') != 1 or (it.get('reqLvl') or 0) > 60 or it.get('quality', 0) < 2 or not wearable(it): continue
    v, hit, txt = stats(it)
    if v + EP[17] * hit < 8: continue
    src, bad = sources(it)
    rec = dict(id=it['id'], name=it['name'], slot=SLOT[it['type']], v=v, hit=hit, txt=txt, src=src, bad=bad, req=it.get('reqLvl'),
               unique=it.get('unique', False), set=it.get('setId'), hand=it.get('handType'), q=it.get('quality'))
    if bad and not src: excluded.append(rec); continue
    if not src: rec['src'] = ['SOURCE UNKNOWN']; rec['bad'] = rec['bad'] + ['source unknown, never seen on AH']; excluded.append(rec); continue
    cands.setdefault(rec['slot'], []).append(rec)

if NO_FDB_ROW:
    sys.exit('no row in pattern_sources.tsv for recipe items ' + ', '.join(map(str, sorted(NO_FDB_ROW)))
             + ': save https://foreverdb.net/item/<id> as <id>.html and run gen_pattern_sources.py')
json.dump({'cands': cands, 'excluded': excluded}, open(os.path.join(SP, 'opt', 'cands.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print({k: len(v) for k, v in cands.items()}, 'excluded', len(excluded))
