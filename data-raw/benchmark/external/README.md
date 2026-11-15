# An outside benchmark: SOTAB

The synthetic benchmark one directory up was written by the same hand as the
detectors. This one was not. [SOTAB V2](https://webdatacommons.org/structureddata/sotab/v2/)
(Web Data Commons, University of Mannheim) labels the columns of real web
tables from Common Crawl with Schema.org types. Its tables have no headers,
so a column is judged by its values alone, the hardest case for a scanner.

## Protocol

1. Which labels count as personal was fixed in `sotab.py` before any scanner
   was run: `Person/name`, `telephone`, `faxNumber`, `email`, `streetAddress`,
   `PostalAddress` and `CoordinateAT`. `MusicArtistAT` (a person or a band)
   and `postalCode` (coarse) are left out as ambiguous. Every other label is
   not personal, among them the names of products, books, places and
   businesses, which look like person names, and ISBN-like identifiers.
2. piinata was studied and changed on the validation split only (198
   personal columns, 1,507 others). Each change is in the git history with
   the validation numbers that motivated it.
3. The test split (217 personal columns, 1,582 others) was scored once per
   configuration after that, and those are the numbers reported. A weakness
   first seen on test (digits in image URLs read as phone numbers) was fixed
   afterwards; the reported test numbers are from before the fix.
4. Presidio was run as a user would choose to run it: its default analyzer
   with spaCy `en_core_web_lg`, and its documented GLiNER configuration with
   the same model `use_gliner()` uses. Each distinct value, up to 50 per
   column, is analyzed alone, as presidio-structured analyzes cells. A
   column is flagged when at least half its rows hold a personal entity
   scoring 0.5 or more; dates, URLs and NRP do not count. Results are given
   with and without LOCATION, since whether a city is personal is a choice.
5. A column counts as found by piinata when a finding on it is `medium` or
   stronger, the level `pii_check()` gates on.

## Caveats

- Most phones and addresses on the web belong to businesses. The benchmark
  measures whether a scanner recognizes the kind of value, which is all a
  scanner can see.
- Some SOTAB labels are wrong: three `Person/name` columns in validation hold
  blog-post titles.
- Latitude and longitude sit in separate columns of web tables, and
  `score_piinata_sotab.R` scores columns one at a time, so it never finds
  `CoordinateAT`. `score_coordinates_sotab.R` scans whole tables instead:
  piinata pairs 11 of 13 coordinate columns in validation and 26 of 26 in
  test, and no column with another label (0 of 1,756 and 0 of 1,825). Every
  unlabeled column it paired in validation (69) holds coordinates.
- Street names without a house number ("Rectory Lane, Little Bookham") are
  missed by piinata; Presidio finds some of them as LOCATION, which also
  fires on every city.

## Running it

    # download and unzip CTA_validation_schemaorg.zip and CTA_test_schemaorg.zip
    python sotab.py <unzipped> <columns>
    Rscript data-raw/benchmark/external/score_piinata_sotab.R <columns>/sotab_test.jsonl piinata.csv [gliner]
    Rscript data-raw/benchmark/external/score_coordinates_sotab.R <unzipped> test
    uv run ... python score_presidio_sotab.py <columns>/sotab_test.jsonl presidio.csv {spacy,gliner}
    python summarize.py [--without LOCATION] piinata.csv presidio.csv

The data are not redistributed here; SOTAB's tables come from Common Crawl
and carry its terms.
