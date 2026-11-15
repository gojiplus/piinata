"""Summarizes per-column results: personal columns found, false alarms, and
per label.

    python summarize.py [--without ENTITY,...] <result.csv> [<result.csv> ...]

--without recomputes a Presidio result as if those entities were not
reported, from the shares of rows it records.
"""
import csv
import json
import sys
from collections import defaultdict

args = sys.argv[1:]
without = set()
if args and args[0] == "--without":
    without, args = set(args[1].split(",")), args[2:]

for path in args:
    rows = list(csv.DictReader(open(path)))
    if without:
        for r in rows:
            shares = {e: s for e, s in json.loads(r["shares"]).items() if e not in without}
            r["any"] = str(bool(shares))
            # Shares of different entities can overlap, so the largest is a
            # lower bound on the share of rows with any of them.
            r["strong"] = str(bool(shares) and max(shares.values()) >= 0.5)
    truth = [r["personal"] == "True" or r["personal"] == "TRUE" for r in rows]
    print(f"\n{path}")
    for level in ("strong", "any"):
        flag = [r[level] in ("True", "TRUE") for r in rows]
        tp = sum(f and t for f, t in zip(flag, truth))
        fp = sum(f and not t for f, t in zip(flag, truth))
        recall, precision = tp / sum(truth), tp / max(1, tp + fp)
        f1 = 2 * precision * recall / max(1e-9, precision + recall)
        print(f"  {level:6s} found {tp}/{sum(truth)}  false alarms {fp}/{len(rows) - sum(truth)}"
              f"  precision {precision:.2f} recall {recall:.2f} F1 {f1:.2f}")
    by = defaultdict(lambda: [0, 0])
    for r, t in zip(rows, truth):
        by[r["label"]][0] += 1
        by[r["label"]][1] += r["strong"] in ("True", "TRUE")
    personal = sorted({r["label"] for r, t in zip(rows, truth) if t})
    print("  personal, found at strong:", ", ".join(f"{k} {by[k][1]}/{by[k][0]}" for k in personal))
    alarms = sorted(((v[1], k, v[0]) for k, v in by.items() if k not in personal and v[1]), reverse=True)
    print("  false alarms at strong:", ", ".join(f"{k} {n}/{m}" for n, k, m in alarms[:12]))
