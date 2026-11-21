"""Where each recipe item comes from, by foreverdb.net, for the pre-raid harness (opt.py, rescore/avail.py).

Reads the saved item pages tools/preraid/data/fdb/<itemID>.html (fetched as https://foreverdb.net/item/<itemID>; data
only, read as text and never run) and writes tools/preraid/data/pattern_sources.tsv, one line per page: itemID, state,
text, tab-separated.

The page's "Where to get it" section (<h2>Where to get it</h2>, up to the next <h2> or the "Data from the WoW Forever
client" line) lists the sources as <li> items, e.g. "Sold by Nergal (Classic data)", "Drops from Overmaster Pyron, 25%
(Classic drop rate) (seen in WoW Forever)". state:
  known    - the section lists sources; text: the items, " / " between them
  unknown  - the section lists none and says so: "New in Forever: where it comes from isn't known yet." or
             "Not known yet."; text empty
  no page  - foreverdb.net has no page for the id: its title is "Item not found - WoW Forever | ForeverDB" (the client's
             ItemSparse has no row for such recipe ids, build 1.60.1.70888); text empty
Any other page is an error naming its file: a layout this script does not read is not guessed at.

opt.py and rescore/avail.py load this file by its path (python -I keeps the script's directory off sys.path) for
read_tsv, recipe_sources and craft_gettable: the rule of a craft's recipe source lives here once.

Run from the addon root: python -I tools/preraid/gen_pattern_sources.py [pages dir] [out.tsv]
"""
import html
import os
import re
import sys

SECTION = re.compile(r'<h2>Where to get it</h2>(.*?)(?:<h2>|Data from the WoW Forever client)', re.S)
ITEM = re.compile(r'<li>(.*?)</li>', re.S)
TITLE = re.compile(r'<title>(.*?)</title>', re.S)
NO_PAGE_TITLE = 'Item not found - WoW Forever | ForeverDB'
UNKNOWN = ("where it comes from isn't known yet.", 'Not known yet.')


def plain(fragment):
    """The text of an HTML fragment: tags dropped, entities read, runs of white space one space."""
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', fragment))).strip()


def where(page):
    """(state, text) of one saved foreverdb.net item page; ValueError for a page of another layout."""
    section = SECTION.search(page)
    if section is None:
        title = TITLE.search(page)
        if title is not None and plain(title.group(1)) == NO_PAGE_TITLE:
            return 'no page', ''
        raise ValueError('no "Where to get it" section, and not the not-found page')
    items = [plain(i) for i in ITEM.findall(section.group(1))]
    if items:
        return 'known', ' / '.join(items)
    if any(phrase in plain(section.group(1)) for phrase in UNKNOWN):
        return 'unknown', ''
    raise ValueError('a "Where to get it" section with no source and no "not known" line')


def main(pages, out_path):
    rows = []
    for name in os.listdir(pages):
        m = re.fullmatch(r'(\d+)\.html', name)
        if m is None:
            raise ValueError('%s: not a page named <itemID>.html' % os.path.join(pages, name))
        path = os.path.join(pages, name)
        try:
            state, text = where(open(path, encoding='utf-8').read())
        except ValueError as e:
            raise ValueError('%s: %s' % (path, e)) from e
        rows.append((int(m.group(1)), state, text))
    rows.sort()
    with open(out_path, 'w', encoding='utf-8', newline='\n') as out:
        for item_id, state, text in rows:
            out.write('%d\t%s\t%s\n' % (item_id, state, text))
    return rows


def read_tsv(path):
    """pattern_sources.tsv -> {itemID: (state, text)}."""
    table = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            item_id, state, text = line.rstrip('\n').split('\t')
            table[int(item_id)] = (state, text)
    return table


def recipe_sources(recipes, fdb, db_where):
    """For the recipe items of one craft: [(itemID, where)]. where: the recipe's own sources in wowsims db.json
    (db_where(itemID), '' when db.json names none), else its foreverdb.net list ('foreverdb.net: <text>'), '' when that
    page says the source is not known or there is no page, None when fdb (read_tsv) has no row for it."""
    out = []
    for rid in recipes:
        where = db_where(rid)
        if not where:
            if rid not in fdb:
                where = None
            else:
                state, text = fdb[rid]
                where = 'foreverdb.net: ' + text if state == 'known' else ''
        out.append((rid, where))
    return out


def craft_gettable(item_on_ah, wheres, ah):
    """Whether a craft can be had: the item was seen on the AH, or one of its recipes (recipe_sources' list) has a known
    source or was seen on the AH (ah: the itemIDs of ah.tsv)."""
    return item_on_ah or any(where or rid in ah for rid, where in wheres)


if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    pages = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'data', 'fdb')
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, 'data', 'pattern_sources.tsv')
    rows = main(pages, out_path)
    counts = {}
    for _, state, _ in rows:
        counts[state] = counts.get(state, 0) + 1
    print(out_path, len(rows), counts)
