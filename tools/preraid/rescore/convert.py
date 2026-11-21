# Converts the pre-raid candidates to HunterGearAdvisor's item format (Core/Score.lua header) as a Lua file.
# Sources:
#   rescore/cands_all.json  - avail.py (= opt/opt.py with the old-EP value filter `v + 1.14*hit < 8` removed): every
#                             wearable phase-1 item, quality >= 2, reqLvl <= 60, that passes opt.py's availability rules
#   opt/cands.json          - the original candidate pool (old EP filter on); `orig` marks its items
#   opt/exalted.txt         - Exalted-reputation items (variant B leaves them out)
#   db.json                 - wowsims/forever item stats (stats by proto Stat index, pseudoStats by PseudoStat index)
# Stat keys are the addon's (Core/Parse.lua): HIT / CRIT / EXPERTISE / HASTE_RATING in %, 10 hit rating = 1%, 14 crit rating
# = 1%, 10 haste rating = 1% (HASTE_RATING: the hunter's own attacks alone, Core/Model.lua), 10 expertise rating = 1%
# (wowsims base_stats_auto_gen.go constants).
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), 'data')   # tools/preraid/data (not in git, see SOURCES.txt)
OUTD = os.path.join(HERE, 'out')                     # generated files (not in git)
os.makedirs(OUTD, exist_ok=True)
OUT = os.path.join(OUTD, 'items.lua')
d = json.load(open(os.path.join(DATA, 'db.json'), encoding='utf-8'))
items = {i['id']: i for i in d['items']}
allc = json.load(open(os.path.join(OUTD, 'cands_all.json'), encoding='utf-8'))['cands']
orig = json.load(open(os.path.join(DATA, 'cands.json'), encoding='utf-8'))['cands']
orig_ids = {r['id'] for L in orig.values() for r in L}
exalted = {int(x) for x in open(os.path.join(DATA, 'exalted.txt')).read().strip().split(',')}

LOC = {1: 'INVTYPE_HEAD', 2: 'INVTYPE_NECK', 3: 'INVTYPE_SHOULDER', 4: 'INVTYPE_CLOAK', 5: 'INVTYPE_CHEST', 6: 'INVTYPE_WRIST',
       7: 'INVTYPE_HAND', 8: 'INVTYPE_WAIST', 9: 'INVTYPE_LEGS', 10: 'INVTYPE_FEET', 11: 'INVTYPE_FINGER', 12: 'INVTYPE_TRINKET'}
HAND_LOC = {1: 'INVTYPE_WEAPONMAINHAND', 2: 'INVTYPE_WEAPON', 3: 'INVTYPE_WEAPONOFFHAND', 4: 'INVTYPE_2HWEAPON'}  # proto HandType
# proto WeaponType -> WoW item subclass (class 2): axe 0/1, dagger 15, fist 13, polearm 6, staff 10, sword 7/8
def weapon_sub(wt, two):
    return {1: 1 if two else 0, 2: 15, 3: 13, 6: 6, 8: 10, 9: 8 if two else 7}[wt]
RANGED_SUB = {1: 2, 2: 18, 3: 3}          # proto RangedWeaponType bow / crossbow / gun -> subclass 2 / 18 / 3
RANGED_LOC = {1: 'INVTYPE_RANGED', 2: 'INVTYPE_RANGEDRIGHT', 3: 'INVTYPE_RANGEDRIGHT'}

notes = []
def convert(it, grp):
    so = (it.get('scalingOptions') or {}).get('0') or {}
    s = so.get('stats') or {}
    ps = it.get('pseudoStats') or []
    p = lambda i: ps[i] if i < len(ps) else 0
    g = lambda k: s.get(str(k), 0)
    st = {}
    def add(k, v):
        if v: st[k] = round(st.get(k, 0) + v, 6)
    add('STR', g(0)); add('AGI', g(1)); add('STA', g(2)); add('INT', g(3)); add('SPI', g(13))
    ap = min(g(14), g(15))
    add('AP', ap); add('RAP', g(15) - ap); add('MAP', g(14) - ap)
    mh, rh = p(12), p(24)
    add('HIT', g(17) / 10 + min(mh, rh))
    # ranged-only hit ("Improves your chance to hit with ranged weapons", Spell 22780): RHIT, which rescore.lua puts
    # into the model's p.rangedHit (the shots' own hit) and, for Score, into HIT
    if rh > mh: add('RHIT', rh - mh); notes.append(f"{it['id']} {it['name']}: ranged-only hit {rh - mh}% -> RHIT")
    if mh > rh: notes.append(f"{it['id']} {it['name']}: melee-only hit {mh - rh}% not counted")
    mc, rc = p(14), p(25)
    add('CRIT', g(18) / 14 + min(mc, rc))
    if rc > mc: add('CRIT_RANGED', rc - mc)
    if mc > rc: notes.append(f"{it['id']} {it['name']}: melee-only crit {mc - rc}% not counted")
    add('HASTE_RATING', g(19) / 10)
    add('EXPERTISE', g(21) / 10 + p(27))
    add('MP5', g(31)); add('ARMOR', g(27)); add('DEFENSE', g(22)); add('HEALTH', g(29)); add('MANA', g(30))
    for i in (2, 17, 18, 20, 21):
        if p(i): notes.append(f"{it['id']} {it['name']}: pseudoStat {i} = {p(i)} not converted")
    for mt in so.get('mobTypeStats') or []:
        add('AP_CREATURE', (mt.get('stats') or {}).get('14', 0))
    if so.get('areaStats'):
        notes.append(f"{it['id']} {it['name']}: zone-only stats {so['areaStats']} not counted")
    t = it['type']
    rec = dict(id=it['id'], name=it['name'], grp=grp, stats=st, setID=it.get('setId'), uniqueEquipped=bool(it.get('unique')),
               exalted=it['id'] in exalted, orig=it['id'] in orig_ids, req=it.get('reqLvl') or 0)
    if t <= 12:
        rec.update(equipLoc=LOC[t], classID=4, subclassID=it.get('armorType', 0) if t not in (2, 11, 12) else 0)
    elif t == 13:
        two = it['handType'] == 4
        rec.update(equipLoc=HAND_LOC[it['handType']], classID=2, subclassID=weapon_sub(it['weaponType'], two))
    elif t == 14:
        rec.update(equipLoc=RANGED_LOC[it['rangedWeaponType']], classID=2, subclassID=RANGED_SUB[it['rangedWeaponType']])
    if t in (13, 14):
        spd = it['weaponSpeed']
        # the tooltip's DPS line (DPS_TEMPLATE, one decimal), which Parse reads
        rec['speed'] = spd
        rec['stats']['DPS'] = round((so.get('weaponDamageMin', 0) + so.get('weaponDamageMax', 0)) / 2 / spd + 1e-9, 1)
    effs = it.get('itemEffects') or []
    rec['hasProc'] = any('proc' in e for e in effs)
    rec['hasUse'] = any('onUse' in e for e in effs)
    rec['effects'] = '; '.join(f"{e.get('buffName')}{' [proc]' if 'proc' in e else ''}{' [use]' if 'onUse' in e else ''}" for e in effs)
    return rec

# Variant B (user 2026-11-17): no battleground reputation and no Barkskin Burrow reputation. An item is "repB" when
# one of its sources is such a faction or its quartermaster (opt.py src strings: "rep <faction> lvl N" / "vendor <npc> @ ...").
REP_B_FACTIONS = ('Darkspear Raiders', 'The Defilers', 'Warsong Outriders', 'Frostwolf Clan', 'Barkskin Burrow')
REP_B_VENDORS = ('Creeg Bothunk', 'Rutherford Twing', 'Kelm Hargunth', 'Jekyll Flandring', 'Grunnda Wolfheart', 'Dala Fairmaw')
def rep_b(src):
    return any(s.startswith('rep ' + f) for s in src for f in REP_B_FACTIONS) or         any(s.startswith('vendor ' + v) for s in src for v in REP_B_VENDORS)
out = []
for grp, L in allc.items():
    for r in L:
        rec = convert(items[r['id']], grp)
        rec['repB'] = rep_b(r['src'])
        out.append(rec)
missing = orig_ids - {r['id'] for r in out}
if missing: sys.exit(f'items of opt/cands.json missing from cands_all.json: {sorted(missing)}')

def lua(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if v is None: return 'nil'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, dict): return '{ ' + ', '.join(f'{k} = {lua(x)}' for k, x in v.items() if x is not None) + ' }'
    raise TypeError(v)
with open(OUT, 'w', encoding='utf-8') as f:
    f.write('-- generated by convert.py, do not edit\nreturn {\n')
    for r in out: f.write('  ' + lua(r) + ',\n')
    f.write('}\n')
print(len(out), 'items ->', OUT)
for n in notes: print('NOTE', n)
