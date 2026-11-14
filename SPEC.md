# piiscan: specification

Status: draft 1, 2026-11-14. Nothing is built yet. This file is the contract the
first versions are checked against; it changes by pull request.

## Problem

Before a research dataset is shared, someone has to find the personal data in
it. The existing free scanners do not do this well. Measured on a synthetic
survey with known answers (`data-raw/benchmark/`, 28 columns, 12 personal):

| Tool | Reads | Looks at | Result |
|---|---|---|---|
| J-PAL `PII-Scan` (R, last commit 2022) | csv, dta, sav, sas7bdat | 56 substrings in column names and labels | 6 of 12 personal columns; 12 of 16 keyword-trap columns flagged; does not start under current `optparse`; `--strict` flags nothing |
| J-PAL `stata_PII_scan` | dta | the same list, plus every string longer than 3 characters | not run (no Stata); by its rules it flags nearly every text column |
| IPA `PII_detection` | csv, xlsx, dta | word lists, three value regexes, uniqueness, a Google population lookup | not run; a Windows desktop application, not a library |
| `detector` (CRAN, 2015) | data frames | email, phone, national id | abandoned |

Two failures recur. The tools skip files they cannot open without saying so,
and they judge a column by its name, so an email address in a column called
`q12` is invisible.

## What piiscan is

An R package that finds likely personal data in files and data frames and
reports where it is, with the evidence, so a person can decide what to do.

It is a scanner. It does not anonymize, redact, or certify that data are safe.

## Principles

1. **Read first.** Nothing is scanned until it has been read, and every file
   the scan was pointed at is accounted for: read, unsupported, or failed, with
   the reason. A file that could not be read is a finding, not a silence.
2. **Do not hand-roll.** Reading, parsing and validation come from maintained
   CRAN packages. Where none exists the gap is recorded here and the feature
   waits, is optional, or is delegated to a backend.
3. **Three kinds of evidence.** What a field is called (name, label, question
   text); what it contains (values); how it behaves (uniqueness, free text).
   A finding says which kind it rests on.
4. **Quiet by default.** A finding needs a share of matching values, not one
   stray hit, and names are matched on whole words. Every rule can be turned
   off, and any field can be allowlisted.
5. **The scanner must not leak.** Example values in reports are masked unless
   asked for. The core makes no network calls.
6. **A small core, optional backends.** The core installs with no Python, no
   Java and no system libraries beyond what its imports need. Heavier
   detectors (Presidio, named-entity models, libphonenumber) are opt-in.

## Reading

Everything is read into one shape, a table of **fields**:

| column | meaning |
|---|---|
| `source` | file path, or the name of the object passed in |
| `locator` | where in the source: column, sheet and column, page, line range |
| `name` | column name, or `NA` for running text |
| `label` | variable label or question text, when the format carries one |
| `values` | list-column of character vectors |
| `kind` | `tabular` or `text` |

A table gives one field per column. A document gives one field per page or
paragraph block. Detectors only ever see fields, so a detector written once
works on a Stata file, a PDF and a data frame alike.

Readers, all existing packages:

| Input | Reader | Notes |
|---|---|---|
| csv, tsv, psv, fwf | `rio::import()` | |
| xlsx, xls, ods | `rio::import_list()` | every sheet |
| dta, sav, por, sas7bdat, xpt | `rio` via `haven` | variable and value labels kept |
| parquet, feather | `rio` via `nanoparquet` / `arrow` | |
| json, ndjson | `rio` via `jsonlite` | |
| rds, rda | `rio` | data frames and character vectors only |
| txt and other plain text | `readtext::readtext()` | |
| pdf | `readtext` via `pdftools` | text layer only; scanned pages are reported as unread |
| docx, doc, rtf | `readtext` via `antiword`, `striprtf` | |
| html, xml | `readtext` | |
| Qualtrics csv/tsv export | `qualtRics::read_survey()` | question text becomes the label; platform fields are known |
| data frame, character vector | none | passed straight through |

`rio` and `readtext` are imports; format-specific packages they need are
suggested and checked at run time. A missing suggested package produces an
"unsupported: install X" row in the read report, not an error.

Not in the first release: images and scanned PDFs (would use `tesseract`),
email archives, databases, live survey-platform APIs (`rsurveycto`,
`robotoolbox` exist and can be added as readers later).

## Detection

A detector is a function from a field to zero or more findings. The core set:

| Evidence | Detector | Built on |
|---|---|---|
| name | terms for names, contact, birth, location, identifiers, relatives, in English, Hindi (transliterated), Spanish, French; matched on whole tokens after splitting `snake_case`, `camelCase` and digits | `stringi` |
| name | platform fields: Qualtrics (`IPAddress`, `RecipientEmail`, `LocationLatitude` ...), SurveyCTO (`deviceid`, `subscriberid`, `devicephonenum` ...) | fixed lists |
| value | email address | `stringi` regex, ICU |
| value | URL, IP address | `ipaddress` for validation |
| value | date of birth: parseable dates in a plausible birth range | `anytime` |
| value | coordinates: numeric latitude/longitude pairs in range | base R |
| value | card-like numbers passing the Luhn check | `checkLuhn` |
| value | phone numbers | see open questions |
| structure | identifier-like: nearly all values distinct | base R |
| structure | free text: long, varied strings; value detectors then run cell by cell | base R |

A value finding carries the number and share of matching values. The default
threshold is 5% of non-missing values or 5 values, whichever is larger; for
free-text fields any match is reported.

Optional backends, each behind one function and one suggested package:

| Backend | Adds | Requires |
|---|---|---|
| `use_presidio()` | person names, locations, India ids (Aadhaar, PAN, voter id), phones with region rules, in free text and columns | `reticulate`; Python packages declared with `py_require()` |
| `use_nametagger()` | person and place names without Python | `nametagger` |
| `use_dialr()` | phone validation against libphonenumber | `dialr`, Java |

## Output

`pii_scan()` returns a tibble, one row per finding:

`source`, `locator`, `name`, `label`, `type` (email, phone, person_name ...),
`evidence` (name, value, structure), `detector`, `n`, `share`, `examples`
(masked), `confidence` (low, medium, high).

Around it:

- `pii_read(path)` returns the fields and, as an attribute printed with them,
  the read report.
- `pii_summary(findings)` gives one row per field with the strongest evidence.
- `pii_check(findings, allow = )` errors when anything unallowed remains, so a
  script or CI job can gate on it.
- `pii_detectors()` lists the registry; `pii_detector()` builds a custom one.

Function names share the `pii_` prefix; arguments are data first.

## How we know it works

1. **Benchmark, tabular.** On `data-raw/benchmark/` the core must catch at
   least 11 of 12 personal columns with at most 2 false alarms among the 16
   others, and 9 of 9 in the Qualtrics export. The same file in csv, dta, xlsx,
   parquet, tsv and ndjson must give the same findings.
2. **Benchmark, text.** A txt, a docx and a pdf with planted emails, phones
   and dates: every planted item found, located to page or line.
3. **Read report.** A folder holding one unreadable file and one unsupported
   file yields two rows saying so, and the scan still completes.
4. **A second opinion.** Presidio run on the same benchmark; disagreements are
   listed in a vignette, not hidden.
5. **Real data.** One public survey file with documented personal fields,
   named in the vignette, scanned and compared by hand.
6. `R CMD check --as-cran` clean on the five r-canon platforms with no
   optional backend installed. Examples and tests run offline in seconds.

The benchmark is adversarial by construction, so its false-alarm rate is a
stress test, not an estimate for typical data.

## Standards

[r-canon](https://github.com/gojiplus/r-canon) throughout: its five workflows
at `@v2`, the canonical `.lintr`, testthat edition 3, roxygen2, pkgdown
published by Actions, `NEWS.md`, semantic versions matching tags. Scaffolding
by `usethis`. Release by `usethis::use_release_issue()`.

License: MIT. `rio`, `readtext` and `checkLuhn` are GPL; importing them from an
MIT package is common on CRAN, and is to be confirmed before submission.

## Milestones

| Version | Contents |
|---|---|
| 0.0.0.9000 | this spec, package skeleton, r-canon adopted, benchmark generator |
| 0.1.0 | reading layer and read report for every format above |
| 0.2.0 | name and value detectors; tabular benchmark passes |
| 0.3.0 | text documents and the Qualtrics reader; text benchmark passes |
| 0.4.0 | optional backends; comparison vignette |
| 0.5.0 | `pii_check()`, allowlists, real-data vignette |
| 1.0.0 | CRAN submission |

## Out of scope

- Removing, masking or recoding personal data.
- Indirect identification from combinations of traits. `sdcMicro` does this.
- Secrets such as API keys. `gitleaks` does this.
- Images, audio, scanned documents.

## Open questions

1. **Phone numbers in the core.** No maintained, Java-free libphonenumber
   exists on CRAN: `dialvalidator` was archived on 2026-03-30 and `dialr`
   (2023) needs Java. Proposal: the core flags digit strings of plausible
   length as `phone`, confidence low, labelled unvalidated; validation comes
   from `use_dialr()` or `use_presidio()`.
2. **National ids in the core.** Aadhaar needs the Verhoeff checksum, for
   which there is no CRAN package. Proposal: leave country ids to Presidio in
   the first release rather than write checksums here.
3. **Person names in values.** Without a model, the core can only say "short,
   capitalized, mostly distinct strings", confidence low. Proposal: that, plus
   `use_nametagger()` as the no-Python upgrade.
4. **The name.** `piiscan` is free on CRAN and GitHub.
