# Benchmark

A synthetic survey with known answers, used to score scanners.

`make_data.py` writes the same 42-column survey (17 personal columns, 25 not)
as csv, dta, xlsx, parquet, tsv and ndjson, a Qualtrics-style export with its
three header rows, and `truth.json`. All names, phone numbers and addresses
are generated; none belongs to a person.

    uv run --no-project --with pandas --with pyarrow --with openpyxl \
        python make_data.py out/

Twelve of the non-personal columns are traps: their names contain a keyword
(`reason_visit` contains "son"). Eight more are decoys behind question
numbers: village, facility, scheme, caste, crop, city, business and street
names, capitalized and often several words, so they look like person names
or addresses. The personal columns include Indian and US names and addresses,
and names in lower case and Devanagari. The false-alarm rate on this file is
a stress test, not an estimate for typical data.

`score_piinata.R` scores piinata, run from the root of the repository:

    Rscript data-raw/benchmark/score_piinata.R data-raw/benchmark/out

`score_jpal.py` scores the output of J-PAL's `PII-Scan` against `truth.json`;
it produced the numbers quoted in the design article.

The generator is Python for now and moves to R with the package skeleton.
