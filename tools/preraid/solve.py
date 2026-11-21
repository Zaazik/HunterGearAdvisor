# Best set under a hit cap: DP over slots with hit rating as state; set bonuses by forcing set pieces into slot combinations.
import json, itertools, sys, os
H = os.path.dirname(os.path.abspath(__file__))
CAP = int(sys.argv[1]) if len(sys.argv) > 1 else 80
DROP = set(int(x) for x in sys.argv[2].split(',')) if len(sys.argv) > 2 and sys.argv[2] else set()
HITW = 1.14
c = json.load(open(os.path.join(H, 'cands.json'), encoding='utf-8'))['cands']
for L in c.values():
    L[:] = [r for r in L if r['id'] not in DROP]

SINGLE = ['head', 'neck', 'shoulder', 'back', 'chest', 'wrist', 'hands', 'waist', 'legs', 'feet', 'ranged']
# set id -> (threshold, bonus value no-hit, bonus hit rating) from client ItemSetSpell (see opt.py spell_value)
SETS = {143: [(2, 0.0, 20)], 186: [(3, 30 * 0.34, 0)], 184: [(3, 30 * 0.34, 0)], 1669: [(6, 40 * 0.34, 0)], 1676: [(6, 40 * 0.34, 0)]}

def prune(L, n=14):
    L = sorted(L, key=lambda r: -(r['v'] + HITW * min(r['hit'], CAP)))
    keep = L[:n]
    # keep the best item for each hit level too (hit pieces can matter under the cap)
    best = {}
    for r in L:
        if r['hit'] not in best or r['v'] > best[r['hit']]['v']: best[r['hit']] = r
    for r in best.values():
        if r not in keep: keep.append(r)
    return keep

opts = {s: [([r], r['v'], r['hit']) for r in prune(c.get(s, []))] for s in SINGLE}
def pairs(L):
    L = prune(L, 16); out = []
    for a, b in itertools.combinations(L, 2):
        if a['id'] == b['id']: continue
        out.append(([a, b], a['v'] + b['v'], a['hit'] + b['hit']))
    return out
opts['fingers'] = pairs(c.get('finger', []))
opts['trinkets'] = pairs(c.get('trinket', []))
W = prune(c.get('weapon', []), 30)
wo = [([r], r['v'], r['hit']) for r in W if r['hand'] == 4]
mh = [r for r in W if r['hand'] in (1, 2)]; oh = [r for r in W if r['hand'] in (2, 3)]
for a in mh:
    for b in oh:
        if a['id'] != b['id']: wo.append(([a, b], a['v'] + b['v'], a['hit'] + b['hit']))
opts['weapons'] = wo
GROUPS = SINGLE + ['fingers', 'trinkets', 'weapons']
MAXH = CAP + 1   # states above cap collapse

def dp(forced):
    # forced: slot -> option tuple
    st = {0: (0.0, [])}
    for g in GROUPS:
        cand = [forced[g]] if g in forced else opts[g]
        if not cand: continue
        nst = {}
        for h, (v, pick) in st.items():
            for o in cand:
                nh = min(h + o[2], MAXH); nv = v + o[1]
                if nh not in nst or nst[nh][0] < nv: nst[nh] = (nv, pick + [(g, o)])
        st = nst
    best = None
    for h, (v, pick) in st.items():
        tot = v + HITW * min(h, CAP)
        if not best or tot > best[0]: best = (tot, h, pick)
    return best

def setpieces(sid):
    out = {}
    for s in SINGLE:
        for r in c.get(s, []):
            if r.get('set') == sid and (s not in out or r['v'] + HITW * r['hit'] > out[s]['v'] + HITW * out[s]['hit']): out[s] = r
    return out

results = []
base = dp({}); results.append(('no set', base))
for sid, bonuses in SETS.items():
    pcs = setpieces(sid)
    for th, bv, bh in bonuses:
        if len(pcs) < th: continue
        for combo in itertools.combinations(sorted(pcs), th):
            forced = {s: ([pcs[s]], pcs[s]['v'] + (bv if s == combo[0] else 0), pcs[s]['hit'] + (bh if s == combo[0] else 0)) for s in combo}
            r = dp(forced)
            if r: results.append((f'set {sid} x{th} {combo}', r))
results.sort(key=lambda x: -x[1][0])
for name, (tot, h, pick) in results[:3]:
    print(f'=== {tot:.1f} EP, hit {h/10:.1f}% ({name})')
    for g, o in pick:
        for r in o[0]:
            print(f"  {g:9} {r['id']:>7} {r['name']:<34} v{r['v']:5.1f} hit{r['hit']/10:4.1f} | {r['txt']} | {'; '.join(r['src'])[:120]}")
json.dump([(n, t, h, [(g, [r['id'] for r in o[0]]) for g, o in p]) for n, (t, h, p) in results[:5]], open(os.path.join(H, 'best.json'), 'w'))
