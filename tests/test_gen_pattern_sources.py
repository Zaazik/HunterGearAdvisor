"""Tests of tools/preraid/gen_pattern_sources.py on synthetic foreverdb.net item pages: the "Where to get it" section's
<li> items are a known source, its "not known" lines an unknown one, the not-found page "no page", and any other page
an error; the TSV has one line per page, sorted by item id.

The pages below copy the layout of the pages saved on 2026-11-21 (https://foreverdb.net/item/15758, 279322, 7994, 7977):
the list <ul class="ssr-list"><li>...</li></ul>, a <p> note under Classic data, the closing
<p class="ssr-data">Data from the WoW Forever client ...</p>.

Run from the addon root: python -I tests/test_gen_pattern_sources.py (the generator is loaded from its path: -I keeps
the script's directory off sys.path). Exits 1 on a failure.
"""
import importlib.util
import os
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("gen_pattern_sources",
                                              os.path.join(ROOT, "tools", "preraid", "gen_pattern_sources.py"))
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

TAIL = '<p class="ssr-data">Data from the WoW Forever client, build 1.60.1.70959, extracted 2026-11-20.</p>'


def page(section, title="Pattern: X - WoW Forever item | ForeverDB"):
    return "<html><head><title>%s</title></head><body><h1>X</h1>%s<footer>f</footer></body></html>" % (title, section)


KNOWN = page('<h2>Where to get it</h2><ul class="ssr-list"><li>Sold by <a href="/npc/9179">Nergal</a> (Classic data)</li>'
             '<li>Drops from Overmaster Pyron, 25% (Classic drop rate) (seen in WoW Forever)</li></ul><p>Drops, quest '
             'rewards and vendors marked Classic data come from Classic (CMaNGOS classic-db) until someone sees them in '
             'Forever.</p><h2>Reagents</h2><ul><li>not a source</li></ul>' + TAIL)
NEW_UNKNOWN = page("<h2>Where to get it</h2><p>New in Forever: where it comes from isn&#39;t known yet.</p>" + TAIL)
OLD_UNKNOWN = page("<h2>Where to get it</h2><p>Not known yet.</p>" + TAIL)
NOT_FOUND = page("<p>No such item.</p>", title="Item not found - WoW Forever | ForeverDB")
NO_SECTION = page("<p>Some other page.</p>", title="Pattern: Y - WoW Forever item | ForeverDB")
EMPTY_SECTION = page("<h2>Where to get it</h2><p>Ask around.</p>" + TAIL)

CASES = [
    ("<li> items are the known sources, the Classic note and the next section's list left out", KNOWN,
     ("known", "Sold by Nergal (Classic data) / Drops from Overmaster Pyron, 25% (Classic drop rate) (seen in WoW Forever)")),
    ("a new Forever item whose source is not known", NEW_UNKNOWN, ("unknown", "")),
    ("an item whose source is not known", OLD_UNKNOWN, ("unknown", "")),
    ("the not-found page", NOT_FOUND, ("no page", "")),
]
ERRORS = [
    ("a page with no section that is not the not-found page", NO_SECTION),
    ("a section with no source and no 'not known' line", EMPTY_SECTION),
]

# The rule opt.py and rescore/avail.py share: a recipe's db.json sources first, else its foreverdb.net list; no source
# known for an unknown or missing page; None for a recipe with no row (an error there, after the run lists them all).
# Recipe 1 has db.json sources and a foreverdb row; 2 a known foreverdb source; 3 an unknown one; 4 no page; 5 no row.
FDB = {1: ("known", "Sold by A"), 2: ("known", "Drops from B, 1%"), 3: ("unknown", ""), 4: ("no page", "")}
DB_WHERE = {1: "vendor C @ Tanaris"}
SOURCE_CASES = [
    ("db.json's sources before foreverdb.net's", [1], [(1, "vendor C @ Tanaris")]),
    ("foreverdb.net's list", [2], [(2, "foreverdb.net: Drops from B, 1%")]),
    ("an unknown source and a missing page give no source, a missing row None", [3, 4, 5], [(3, ""), (4, ""), (5, None)]),
]
GETTABLE_CASES = [
    ("a recipe with a known source", (False, [(2, "foreverdb.net: x")], set()), True),
    ("no source known, nothing on the AH", (False, [(3, ""), (4, "")], set()), False),
    ("no source known, the recipe seen on the AH", (False, [(3, ""), (4, "")], {4}), True),
    ("no source known, the item seen on the AH", (True, [(3, "")], set()), True),
    ("a missing row is no source", (False, [(5, None)], set()), False),
]


def main():
    passed = failed = 0

    def check(name, ok, detail):
        nonlocal passed, failed
        if ok:
            passed += 1
        else:
            failed += 1
            print("FAIL %s: %s" % (name, detail))

    for name, text, want in CASES:
        got = gen.where(text)
        check(name, got == want, "expected %r, got %r" % (want, got))
    for name, text in ERRORS:
        try:
            got = gen.where(text)
            check(name, False, "expected an error, got %r" % (got,))
        except ValueError:
            check(name, True, "")
    for name, recipes, want in SOURCE_CASES:
        got = gen.recipe_sources(recipes, FDB, lambda rid: DB_WHERE.get(rid, ""))
        check(name, got == want, "expected %r, got %r" % (want, got))
    for name, args, want in GETTABLE_CASES:
        got = gen.craft_gettable(*args)
        check(name, bool(got) == want, "expected %r, got %r" % (want, got))
    with tempfile.TemporaryDirectory() as tmp:
        pages = os.path.join(tmp, "fdb")
        os.mkdir(pages)
        for item_id, text in ((279322, NEW_UNKNOWN), (15758, KNOWN), (7977, NOT_FOUND)):
            with open(os.path.join(pages, "%d.html" % item_id), "w", encoding="utf-8") as f:
                f.write(text)
        out = os.path.join(tmp, "pattern_sources.tsv")
        gen.main(pages, out)
        with open(out, encoding="utf-8", newline="") as f:
            lines = f.read()
        want = ("7977\tno page\t\n15758\tknown\tSold by Nergal (Classic data) / Drops from Overmaster Pyron, 25% (Classic "
                "drop rate) (seen in WoW Forever)\n279322\tunknown\t\n")
        check("the TSV: one line per page, sorted by item id", lines == want, "expected %r, got %r" % (want, lines))
        table = gen.read_tsv(out)
        want_table = {7977: ("no page", ""), 15758: ("known", want.split("\n")[1].split("\t")[2]), 279322: ("unknown", "")}
        check("read_tsv reads the TSV back", table == want_table, "expected %r, got %r" % (want_table, table))
        with open(os.path.join(pages, "notes.txt"), "w", encoding="utf-8") as f:
            f.write("x")
        try:
            gen.main(pages, out)
            check("a file not named <itemID>.html is an error", False, "no error")
        except ValueError as e:
            check("a file not named <itemID>.html is an error", "notes.txt" in str(e), str(e))
    print("%d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
