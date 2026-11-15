"""Scores Microsoft Presidio's default analyzer on the benchmark, for comparison.

    uv run --no-project --python 3.12 --with presidio-analyzer \
        --with "en_core_web_lg @ https://github.com/explosion/spacy-models/releases/download/en_core_web_lg-3.8.0/en_core_web_lg-3.8.0-py3-none-any.whl" \
        python score_presidio.py out/

Each distinct value of a column is analyzed alone, as presidio-structured
does, and a column is judged two ways: any detection (presidio-structured's
rule) and detections in at least half the rows (piinata's).
"""
import json, sys, time, csv
from collections import Counter, defaultdict
from presidio_analyzer import AnalyzerEngine
bench = sys.argv[1]
truth = {k: v["pii"] for k, v in json.load(open(f"{bench}/truth.json")).items()}
rows = list(csv.DictReader(open(f"{bench}/std/survey.csv")))
engine = AnalyzerEngine()
import importlib.metadata
print("presidio-analyzer", importlib.metadata.version("presidio-analyzer"))
t = time.time()
result = {}
for col in rows[0].keys():
    values = [r[col] for r in rows if r[col] != ""]
    counts = Counter(values)
    hits = defaultdict(int)
    for value, n in counts.items():
        found = {r.entity_type for r in engine.analyze(text=value, language="en") if r.score >= 0.5}
        for e in found:
            hits[e] += n
    total = sum(counts.values())
    result[col] = {e: round(h / total, 2) for e, h in sorted(hits.items(), key=lambda x: -x[1])}
print(f"seconds: {time.time() - t:.1f}")
for rule, test in [("any hit", lambda s: len(s) > 0), ("half the rows", lambda s: any(v >= 0.5 for v in s.values()))]:
    flagged = {c for c, s in result.items() if test(s)}
    personal = {c for c, p in truth.items() if p}
    print(f"{rule:14s} caught {len(flagged & personal)}/{len(personal)}  false alarms {len(flagged - personal)}/{len(truth) - len(personal)}")
    print("   missed:", " ".join(sorted(personal - flagged)))
    print("   alarms:", " ".join(f"{c}{result[c]}" for c in sorted(flagged - personal)))
