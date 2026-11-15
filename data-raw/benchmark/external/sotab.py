"""Turns SOTAB V2's column type annotation sets into one file of labeled
columns for scoring personal-data scanners.

SOTAB (Web Data Commons, University of Mannheim) annotates columns of real web
tables from Common Crawl with Schema.org types. Download the CTA validation and
test sets from https://webdatacommons.org/structureddata/sotab/v2/, unzip them
into a directory of their own, and run

    python sotab.py <unzipped dir> <out dir>

It writes <out>/sotab_validation.jsonl and <out>/sotab_test.jsonl, one labeled
column per line with its values. Tables carry no headers, so the columns are
judged by their values alone.

Which labels count as personal is fixed here, before any scanner is run:
values of a kind that identifies or contacts a person. Most phones and
addresses on the web belong to businesses, so this measures whether a scanner
recognizes the kind of value, which is all a scanner can see.
"""
import csv
import gzip
import json
import pathlib
import sys

PERSONAL = {
    "Person/name", "telephone", "faxNumber", "email", "streetAddress", "PostalAddress",
    "CoordinateAT",
}
# A musical artist may be a person or a band; a postcode alone is coarse.
AMBIGUOUS = {"MusicArtistAT", "postalCode"}

source, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
splits = {
    "validation": ("validation/sotab_v2_cta_validation_set.csv", "validation/Validation"),
    "test": ("test/sotab_v2_cta_test_set.csv", "test/Test"),
}
for split, (labels, tables) in splits.items():
    rows = list(csv.DictReader(open(source / labels)))
    cache = {}
    with open(out / f"sotab_{split}.jsonl", "w") as handle:
        for row in rows:
            if row["label"] in AMBIGUOUS:
                continue
            name = row["table_name"]
            if name not in cache:
                lines = gzip.open(source / tables / name, "rt").read().splitlines()
                cache = {name: [json.loads(line) for line in lines]}
            column = row["column_index"]
            values = [r.get(column) for r in cache[name]]
            values = [
                v if isinstance(v, str) else json.dumps(v)
                for v in values if v is not None and v != ""
            ]
            handle.write(json.dumps({
                "table": name, "column": int(column), "label": row["label"],
                "personal": row["label"] in PERSONAL, "values": values,
            }) + "\n")
    print(split, len(rows), "labeled columns")
