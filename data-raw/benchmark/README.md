# Benchmark

A synthetic survey with known answers, used to score scanners.

`make_data.py` writes the same 28-column survey (12 personal columns, 16 not)
as csv, dta, xlsx, parquet, tsv and ndjson, a Qualtrics-style export with its
three header rows, and `truth.json`. All names, phone numbers and addresses
are generated; none belongs to a person.

    uv run --no-project --with pandas --with pyarrow --with openpyxl \
        python make_data.py out/

Twelve of the non-personal columns are traps: their names contain a keyword
(`reason_visit` contains "son"). The false-alarm rate on this file is a stress
test, not an estimate for typical data.

`score_jpal.py` scores the output of J-PAL's `PII-Scan` against `truth.json`;
it produced the numbers quoted in `SPEC.md`.

The generator is Python for now and moves to R with the package skeleton.
