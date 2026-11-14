# piiscan: specification

Status: draft 2, 2026-11-14. The reading layer and the core detectors exist and
pass the tabular benchmark. This file is the contract versions are checked
against; it changes by pull request.

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

## Pipeline

A scan is four stages, each in its own files, each replaceable:

| Stage | Does | Code |
|---|---|---|
| read | turns files and objects into fields; accounts for every file | `R/read.R`, `R/readers.R`, `R/fields.R` |
| normalize | cleans values so patterns can match dirty data | `R/normalize.R` |
| detect | name, value and structure evidence, one function each | `R/terms.R`, `R/detect-name.R`, `R/detect-value.R` |
| report | findings, summary, the check that gates a script | `R/findings.R`, `R/scan.R`, `R/report.R` |

A fifth stage, redact, comes later and consumes findings.

Normalization exists because real exports are dirty. It applies Unicode
compatibility normalization, turns decimal digits of any script into ASCII
digits, drops zero-width and other invisible format characters, and collapses
whitespace, all through ICU (`stringi`). It does not yet undo deliberate
obfuscation ("name at gmail dot com"), spelled-out digits, or OCR confusions
such as O for 0; those belong to an optional, more aggressive cleaning step.

The flagger proposes and a person disposes. A finding is a proposal with its
evidence; the decision (keep, drop, redact, allow with a reason) is the
user's, is recorded in the project, and is what the check enforces.

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

Readers are the tidyverse and r-lib packages social scientists already use:

| Input | Reader | Notes |
|---|---|---|
| csv, tsv, psv | `readr` | everything read as text |
| xlsx, xls | `readxl` | every sheet |
| dta, sav, zsav, por, sas7bdat, xpt | `haven` | variable and value labels kept |
| rds | base R | data frames and character vectors only |
| txt, md, log, do, R, tex and similar | `readr::read_lines()` | scripts and logs can list rows of data |
| Qualtrics csv/tsv export | `qualtRics::read_survey()` | detected from its `ImportId` row; question text becomes the label |
| parquet | `nanoparquet` | |
| json, jsonl, ndjson | `jsonlite` | tabular JSON as a table, otherwise as text |
| pdf | `pdftools` | text layer only; a scan is reported as unsupported |
| docx | `officer` | |
| rtf | `striprtf` | |
| html | `rvest` | |
| data frame, character vector | none | passed straight through |

`readr`, `readxl` and `haven` are imports. The rest are suggested and checked
at run time: a missing package produces an "unsupported: install X" row in the
read report, not an error.

Still to read, in the order social scientists meet them: SurveyCTO and
KoboToolbox/ODK exports (repeat groups, media file names), REDCap exports with
their data dictionary, SurveyMonkey and Google Forms headers, ods, doc, Stata
logs in smcl, and the file names themselves, which often carry a respondent's
name.

Not in the first release: images and scanned PDFs (would use `tesseract`),
email archives, databases, live survey-platform APIs (`rsurveycto`,
`robotoolbox` exist and can be added as readers later).

## Detection

A detector is a function from a field to zero or more findings. The core set:

| Evidence | Detector | Built on |
|---|---|---|
| name | terms for names, contact, birth, location, identifiers, relatives, in English with some Spanish, French and Hindi; matched on whole tokens after splitting `snake_case`, `camelCase` and digits | `stringr` |
| name | platform fields: Qualtrics (`IPAddress`, `RecipientEmail`, `LocationLatitude` ...), SurveyCTO (`deviceid`, `subscriberid`, `devicephonenum` ...) | fixed lists |
| value | email address | `stringr` |
| value | IP address | `ipaddress` for validation |
| value | date of birth: parseable dates in a plausible birth range | `lubridate` |
| value | coordinates: numeric latitude/longitude pairs in range | base R |
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
5. **Real data.** Scans of real project folders, compared by hand. The first,
   a folder of election and survey files, cut flagged fields from 465 to 251
   by showing where the rules were loose (place names read as person names,
   precise numbers as coordinates, keys as text), and found a column of real
   mobile numbers. The benchmark and the detectors were written by the same
   hand, so real folders are the check that counts.
6. `R CMD check --as-cran` clean on the five r-canon platforms with no
   optional backend installed. Examples and tests run offline in seconds.

The benchmark is adversarial by construction, so its false-alarm rate is a
stress test, not an estimate for typical data.

## Standards

[r-canon](https://github.com/gojiplus/r-canon) throughout: its five workflows
at `@v2`, the canonical `.lintr`, testthat edition 3, roxygen2, pkgdown
published by Actions, `NEWS.md`, semantic versions matching tags. Scaffolding
by `usethis`. Release by `usethis::use_release_issue()`.

License: MIT. Every import is MIT, Apache or similarly permissive.

## Speed

A scan must be cheap enough to run on every commit.

- Detectors see the distinct values of a column and their counts, so a coded
  column costs the same at a thousand rows or a million.
- Column types are used: logical columns are skipped, numeric and date columns
  skip the text patterns.
- Above `sample` distinct values (default 10,000) a column is judged from an
  evenly spaced subset. `sample = Inf` examines everything. Running text is
  always examined in full.
- Date formats are only guessed for values shaped like dates. Guessing on
  arbitrary strings took 336 seconds on one real column; it now takes none.
- Measured: a real project folder of 50 files and 3,137 fields scans in about
  15 seconds on a laptop. The sister package's checksums are C++ (`cpp11`).
- Later, where profiling says so: parallel scanning of files, and an
  exhaustive mode for ragged sources such as YAML, nested JSON and long text.

## Using it in a workflow

Researchers call it from R. Projects also need it in the flow of work:

1. **Review and exceptions.** `pii_review()` would write the findings as a
   file with a decision column for a person to fill in. A committed `.piiscan.yml` holds what has been reviewed:
   fields and files that may stay, detectors turned off, thresholds, and extra
   terms. `pii_check()` reads it. An exception names a field and a reason, not
   a blanket switch.
2. **Custom patterns.** Users declare their own: a name, a regular expression
   or a function, an optional validator and a confidence. Study ids, staff
   codes and local identifiers go here.
3. **Git.** A pre-commit hook (`language: r` in `.pre-commit-hooks.yaml`) and a
   GitHub Action that scan the files a commit touches and fail on unreviewed
   findings. A Python port is on the table if no Python package does the same
   job, since most hooks run in Python environments.
4. **Redaction.** The levels are: report (now); drop a field; replace values
   with a placeholder of the same type; replace with a stable pseudonym, so
   joins and counts still work; and a custom function. The model is Presidio's
   split between an analyzer that returns typed spans with scores and an
   anonymizer that applies an operator per type (replace, mask, hash, redact,
   encrypt, custom). `pii_scan()` is the analyzer; `pii_redact()` would be the
   anonymizer and write a clean copy beside the original.
5. **Originals out of git.** With a clean copy written, the original can be
   added to `.gitignore` and the clean copy committed. This is opt-in and
   prints what it did; it does not rewrite history, so an original already
   committed stays in the repository's past.
6. **URLs and browsing data.** A URL can carry personal data in its user,
   path and query string. A URL detector would parse with a maintained parser
   and report or strip those parts while keeping the host.

Items 1 to 3 come before redaction: a scanner people cannot quiet is one they
remove.

## Milestones

| Version | Contents | State |
|---|---|---|
| 0.0.0.9000 | spec, package, r-canon, reading layer, core detectors, `idcheck` hook-in, speed | done |
| 0.1.0 | `.piiscan.yml` exceptions, custom patterns, file-name scanning | |
| 0.2.0 | SurveyCTO, KoboToolbox/ODK, REDCap, SurveyMonkey and Google Forms exports | |
| 0.3.0 | pre-commit hook and GitHub Action | |
| 0.4.0 | optional backends: Presidio, `nametagger`; comparison vignette | |
| 0.5.0 | phone validation on libphonenumber metadata | |
| 0.6.0 | `pii_redact()` | |
| 1.0.0 | CRAN submission, after `idcheck` is on CRAN | |

## Out of scope

- Removing, masking or recoding personal data, until `pii_redact()`.
- Indirect identification from combinations of traits. `sdcMicro` does this.
- Secrets such as API keys. `gitleaks` does this.
- Images, audio, scanned documents.

## Open questions

1. **Phone numbers.** No maintained, Java-free libphonenumber exists on CRAN:
   `dialvalidator` was archived on 2026-03-30 and `dialr` (2023) needs Java.
   The core flags digit strings of 10 to 13 digits as `phone`, confidence
   low. Decided: build our own validator on Google's libphonenumber metadata
   (Apache-2.0), credited, likely in the sister package below.
2. **National ids.** Decided and built: the sister package
   [idcheck](https://github.com/gojiplus/idcheck) validates identity numbers in
   C++ (Aadhaar by Verhoeff checksum, GSTIN by checksum, PAN, voter id,
   passport and Indian mobile numbers by format). piiscan uses it when
   installed; a checksum match is high confidence. CRAN does have two Verhoeff
   packages, `verhoeff` and `CheckDigit`, but both are GPL and neither is
   built for scanning a column.
3. **Person names in values.** Without a model, the core can only say "short,
   capitalized, mostly distinct strings", confidence low. Proposal: that, plus
   `use_nametagger()` as the no-Python upgrade.
4. **The name.** `piiscan` is free on CRAN and GitHub.
