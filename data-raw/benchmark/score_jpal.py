import csv, json, sys
from pathlib import Path
truth = {k: v["pii"] for k, v in json.loads(Path("data/truth.json").read_text()).items()}
def score(flagged, truth, tag):
    tp = sorted(c for c in truth if truth[c] and c in flagged); fn = sorted(c for c in truth if truth[c] and c not in flagged)
    fp = sorted(c for c in truth if not truth[c] and c in flagged)
    print(f"{tag}: caught {len(tp)}/{len(tp)+len(fn)} personal columns; false alarms {len(fp)}/{sum(not v for v in truth.values())}")
    print("   missed:", ", ".join(fn) or "-"); print("   false alarms:", ", ".join(fp) or "-")
for tag, f in (("csv", "survey.csv"), ("dta (with labels)", "survey.dta")):
    rows = [r for r in csv.DictReader(open("out/jpal_std.csv")) if r["file"].endswith(f)]
    score({r["var"] for r in rows}, truth, "J-PAL R, " + tag)
rows = list(csv.DictReader(open("out/jpal_std_strict.csv"))); print("J-PAL R --strict: flagged", len(rows), "columns in total")
qt = json.loads(Path("data/truth_qualtrics.json").read_text())
score({r["var"] for r in csv.DictReader(open("out/jpal_qualtrics.csv"))}, qt, "J-PAL R, Qualtrics export")
print("other formats (xlsx, parquet, tsv, jsonl): rows flagged", len(list(csv.DictReader(open("out/jpal_other.csv")))))
