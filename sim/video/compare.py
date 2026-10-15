#!/usr/bin/env python3
"""Compare a bench dump (pa.txt) with the reference renderer, or two dumps.

usage: compare.py ref SCENEDIR RECIPE SEED [limit] [skip]
       compare.py dumps DIR_A DIR_B
"""
import sys, importlib
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import scene, recipes

def load(path):
    """frame[line][x] = PA (int), aa[line]"""
    fr, aa = {}, {}
    for l in open(path):
        r, p, pa, a = l.split()
        r, p = int(r), int(p)
        line = r - 256
        if not 16 <= line < 240:
            continue
        if p >= 271:
            x = p - 271
        elif 128 <= p <= 206:
            x = p - 128 + 241
        else:
            continue
        fr.setdefault(line, {})[x] = int(pa, 16)
        aa[line] = int(a)
    return fr, aa

def main():
    mode = sys.argv[1]
    if mode == "dumps":
        a, _ = load(sys.argv[2] + "/pa.txt")
        b, _ = load(sys.argv[3] + "/pa.txt")
        bad = [(l, x, a[l][x], b[l].get(x)) for l in a for x in a[l] if a[l][x] != b[l].get(x)]
        print("pixels: %d, different: %d" % (sum(len(v) for v in a.values()), len(bad)))
        for e in bad[:10]:
            print("  line %d x %d: %03x vs %s" % (e[0], e[1], e[2], "%03x" % e[3] if e[3] is not None else "-"))
        sys.exit(1 if bad else 0)
    d, recipe, seed = sys.argv[2], sys.argv[3], int(sys.argv[4])
    limit = int(sys.argv[5]) if len(sys.argv) > 5 else 96
    half = int(sys.argv[6]) if len(sys.argv) > 6 else 1
    sc = getattr(recipes, recipe)(seed)
    fr, aa = load(d + "/pa.txt")
    bad = 0
    shown = 0
    total = 0
    for line in sorted(fr):
        ref = scene.render_line(sc, line, aa[line], limit=limit, half_order=half)
        for x in range(320):
            got = fr[line].get(x)
            exp = ref[x] if ref[x] is not None else 0xfff
            total += 1
            if got != exp:
                bad += 1
                if shown < 12:
                    shown += 1
                    print("  line %d x %d: got %03x expected %03x" % (line, x, got, exp))
    print("pixels: %d, different: %d" % (total, bad))
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
