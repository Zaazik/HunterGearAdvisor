"""Stat-weight model for a WoW Forever BM hunter (BM 32 / MM 2 / SV 0), level 43.

All formulas come from the research workflow (scratchpad/research/*.md, verified by V1-V3).
Weights are finite differences of total single-target DPS (hunter + pet + 2 hawks),
expressed in "RAP units": weight(stat) = dDPS/dstat / dDPS/dRAP.
"""
import copy

BASE = dict(
    level=43,
    agi=167,            # measured in game 2026-11-12
    gear_rap=0,         # RAP from gear
    gear_ap=81,         # AP from gear (+N к силе атаки counts for RAP, verified in game)
    ap_to_rap=True,     # UNVERIFIED in Forever: does item "+Attack Power" raise ranged AP?
    aoth=70,            # Aspect of the Hawk R4 (L38)
    hm=98,              # Hunter's Mark R3 (L40), ranged attackers only, not inherited
    crit_gear=2.0,      # % crit from gear (rating/14)
    crit_base=0.0,      # server-side, assumed 0 (Classic)
    lethal=2.0,         # Lethal Attacks 2/5
    hit=1.0,            # % hit from gear
    expertise=0.0,
    bow_dps=21.0,       # tooltip DPS of the bow
    bow_speed=2.6,
    ammo_dps=13.0,      # Jagged Arrow (L40 vendor)
    quiver=0.13,        # Matriarch / Quickdraw quiver
    mob_level_diff=0,   # target level - player level
    phys=0.70,          # armor multiplier for physical damage (mob ~1800 armor at L43)
    aimed_bonus=115 + 9,  # Aimed Shot R3 (+9 per wowsims fit)
    arcane_base=120,    # Arcane Shot R5 (L36)
    serpent_tick=58,    # Serpent Sting R6 (L42)
    serpent_uptime=0.8,
    dive_base=47,       # Summon Hawk R2 (L36)
    hawk_uptime=0.9,
    hawk_base_dps=7.5,  # per hawk, non-AP part (L48 fit ~8.7, scaled down)
    pet_base_dps=34.0,  # pet own white DPS before multipliers (calibrated: pet ~1/3 of total)
    pet_special_dps=12.0,  # Claw/Bite flat damage per second before multipliers
    pet_mult=1.25 * 1.15 * 1.02 * 1.075 * 1.05,  # happy * UF 5/5 * FF 2/2 * BW avg * Orc Command
    ff=1.02,            # Focused Fire 2/2 on hunter damage
    melee_frac=0.05,    # share of time the hunter melees (user avoids melee)
    mh_dps=0.0, mh_speed=2.6, oh_dps=0.0, two_h=False,
    map_extra=0,        # extra melee AP (Aspect of the Beast etc.)
    crit_per_agi_l43=1 / 35.84,  # % crit per Agility at L43 (PlayerExpectedStat)
)


def miss_chance(p, special=True):
    gap = p['mob_level_diff'] * 5
    base = 5.0 + (0.1 * gap if gap <= 10 else 0.2 * gap)
    return max(0.0, base - p['hit']) / 100.0


def model(p):
    lvl = p['level']
    rap_stat = 2 * lvl - 10 + 2 * p['agi'] + p['gear_rap'] + (p['gear_ap'] if p['ap_to_rap'] else 0) + p['aoth']
    rap_shot = rap_stat + p['hm']
    map_ = 2 * lvl - 20 + p['agi'] + p['gear_ap'] + p['map_extra']
    crit = (p['crit_base'] + p['agi'] * p['crit_per_agi_l43'] + p['crit_gear'] + p['lethal']) / 100.0
    miss = miss_chance(p)
    hitf = 1 - miss

    # ranged haste: quiver * Quick Shots average * Rapid Fire average
    s = p['bow_speed']
    shots_12s = 12 * (1 + p['quiver']) * 1.3 / s
    qs_up = 1 - 0.9 ** shots_12s
    h_r = (1 + p['quiver']) * (1 + 0.3 * qs_up) * 1.02

    out = {}
    w = p['bow_dps'] + p['ammo_dps']
    out['auto'] = (w + rap_shot / 14) * h_r * hitf * (1 + crit) * p['phys'] * p['ff']
    out['aimed'] = (w * s + rap_shot * 2.8 / 14 + p['aimed_bonus']) / 6 * hitf * (1 + crit) * p['phys'] * p['ff']
    out['arcane'] = (p['arcane_base'] + 0.15 * rap_shot) / 18 * hitf * (1 + crit) * p['ff']
    out['serpent'] = (5 * p['serpent_tick'] + 0.25 * rap_shot) / 15 * p['serpent_uptime'] * hitf * (1 + crit) * p['ff']
    out['dive'] = (p['dive_base'] + 0.05 * rap_shot) / 9 * (1 + crit) * p['phys'] * p['ff']

    hawk_ap = 0.8 * (rap_stat + 7 + 14 * w)
    hawk_crit = 0.5 * crit + 0.10
    out['hawks'] = 2 * p['hawk_uptime'] * (p['hawk_base_dps'] + hawk_ap / 60) * (1 + p['quiver']) * (1 + 0.3 * qs_up) \
        * hitf * (1 + hawk_crit) * p['phys']

    pet_crit = crit + 0.10
    pet_miss = miss + max(0.0, 0.05 - p['expertise'] / 100.0)  # miss + dodge
    attacks_8s = 8 / 2.0 * 1.3 + 3          # white swings under Frenzy + ~3 specials
    frenzy_up = 1 - (1 - 0.8 * pet_crit) ** attacks_8s
    pet_haste = (1 + 0.3 * frenzy_up) * 1.02
    pet_white = (p['pet_base_dps'] + 0.10 * max(rap_stat, map_) / 14) * pet_haste
    out['pet'] = (pet_white + p['pet_special_dps']) * p['pet_mult'] * (1 - pet_miss) * (1 + pet_crit) * p['phys']

    # melee (only melee_frac of the time): white MH (+OH), Raptor Strike every 6 s
    if p['melee_frac'] > 0 and (p['mh_dps'] or p['two_h']):
        dw = p['oh_dps'] > 0 and not p['two_h']
        wmiss = miss + (0.19 if dw else 0) + 0.05  # + mob dodge
        mh = (p['mh_dps'] + map_ / 14) * (1 - wmiss) * (1 + crit) * 0.95  # ~glancing
        oh = 0.5 * (p['oh_dps'] + map_ / 14) * (1 - wmiss) * (1 + crit) * 0.95 if dw else 0
        raptor = (p['mh_dps'] * p['mh_speed'] + map_ / 14 * p['mh_speed'] + 40) / 6 * (1 - miss - 0.05) * (1 + crit)
        out['melee'] = p['melee_frac'] * (mh + oh + raptor) * p['phys'] * p['ff']
        # while meleeing, ranged parts stop
        for k in ('auto', 'aimed', 'arcane'):
            out[k] *= (1 - p['melee_frac'])
    return out


def total(p):
    return sum(model(p).values())


def weights(p, eps=1.0):
    t0 = total(p)
    def d(key, step):
        q = copy.deepcopy(p)
        q[key] = q[key] + step
        return (total(q) - t0) / step
    rap = d('gear_rap', 10)
    res = {'RAP': 1.0}
    res['AGI'] = d('agi', 10) / rap
    q = copy.deepcopy(p)
    res['AP (if it counts for ranged)'] = d('gear_ap', 10) / rap
    q['ap_to_rap'] = False
    t1 = total(q); q['gear_ap'] += 10
    res['AP (if melee only)'] = (total(q) - t1) / 10 / rap
    res['HIT 1%'] = d('hit', 0.5) / rap
    res['CRIT 1%'] = d('crit_gear', 0.5) / rap
    res['EXPERTISE 1%'] = d('expertise', 0.5) / rap
    res['ranged weapon DPS'] = d('bow_dps', 1) / rap
    res['ammo DPS'] = d('ammo_dps', 1) / rap
    if p['mh_dps']:
        res['MH DPS'] = d('mh_dps', 1) / rap
    if p['oh_dps']:
        res['OH DPS'] = d('oh_dps', 1) / rap
    return t0, res


if __name__ == '__main__':
    p = copy.deepcopy(BASE)
    parts = model(p)
    t = sum(parts.values())
    print('BREAKDOWN total %.1f DPS' % t)
    for k, v in parts.items():
        print('  %-8s %6.1f  %4.1f%%' % (k, v, 100 * v / t))
    for label, over in [
        ('reference (bow 2.6s)', {}),
        ('slow bow 3.0s', {'bow_speed': 3.0}),
        ('fast bow 2.0s', {'bow_speed': 2.0}),
        ('vs +2 mobs (dungeon boss)', {'mob_level_diff': 2}),
        ('hit already 5%', {'hit': 5.0}),
        ('melee 10%, DW 26/26', {'melee_frac': 0.10, 'mh_dps': 26, 'oh_dps': 26}),
        ('melee 35%, DW 26/26', {'melee_frac': 0.35, 'mh_dps': 26, 'oh_dps': 26}),
        ('melee 10%, 2H 34 (3.3s)', {'melee_frac': 0.10, 'mh_dps': 34, 'mh_speed': 3.3, 'two_h': True}),
        ('melee 35%, 2H 34 (3.3s)', {'melee_frac': 0.35, 'mh_dps': 34, 'mh_speed': 3.3, 'two_h': True}),
        ('melee 35%, MH only 26', {'melee_frac': 0.35, 'mh_dps': 26}),
    ]:
        q = copy.deepcopy(BASE); q.update(over)
        t0, w = weights(q)
        print('\n== %s  (total %.1f DPS, 1 RAP = %.4f DPS)' % (label, t0, (total(dict(q, gear_rap=q['gear_rap'] + 10)) - t0) / 10))
        for k, v in w.items():
            print('  %-30s %6.2f' % (k, v))
