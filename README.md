# piinata

<!-- badges: start -->
[![R-CMD-check](https://github.com/gojiplus/piinata/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/gojiplus/piinata/actions/workflows/R-CMD-check.yml)
<!-- badges: end -->

Find likely personal data in research files before they are shared.

piinata reads survey exports, statistical data files, spreadsheets and text
documents, and reports which fields look personal and why. It looks at what a
field is called, what it contains, and how it behaves, so an email address in a
column named `q12` is found as readily as one in a column named `email`.

It reports, and it can redact what it finds, in a data frame or in a copy of
each file. An empty report does not show that data are safe to share.

The name: hit a file and see what personal data falls out.

## Installation

``` r
# install.packages("pak")
pak::pak("gojiplus/piinata")
```

## Usage

Point it at a folder, a file or a data frame:

``` r
library(piinata)

survey <- data.frame(
  q12 = paste0("person", 1:20, "@example.org"),
  resp_name = rep(c("Asha Devi", "Ravi Kumar", "Meena Bai", "Imran Khan"), 5),
  reason_visit = rep(c("work", "family"), 10)
)

findings <- pii_scan(survey)
pii_summary(findings)
#> # A tibble: 2 × 6
#>   source locator   name      types       evidence    confidence
#>   <chr>  <chr>     <chr>     <chr>       <chr>       <chr>
#> 1 data   q12       q12       email       value       high
#> 2 data   resp_name resp_name person_name name, value medium
```

`reason_visit` is not flagged: names are matched on whole words, so "reason"
does not match "son". Example values in the findings are masked unless you ask
for them with `show_values = TRUE`.

Every file is accounted for. A file that cannot be read is reported, never
skipped:

``` r
findings <- pii_scan("path/to/project")
pii_read_report(findings)
```

In a script or a CI job, stop when something has not been reviewed:

``` r
pii_check(findings, allow = c("village", "district"))
```

## Decide once, keep the decision

The scanner proposes; you decide. Write the findings to a review file, mark
each field `allow` or `remove` with a reason, and record the allowed ones in
the project's `.piinata.yml`:

``` r
pii_review(findings, "piinata-review.csv")
# ... fill in the decision and reason columns ...
pii_accept("piinata-review.csv")
pii_check(findings)
```

`.piinata.yml` also holds files to ignore, patterns for the study's own
identifiers, and extra terms. Every exception needs a reason.

## Redact

``` r
clean <- pii_redact(survey, method = c(email = "pseudonym", default = "drop"), key = "a secret")
```

Flagged columns can be dropped, replaced with a placeholder such as
`<EMAIL>` (the default), masked, or replaced with pseudonyms that keep each
value's shape and repeat for equal values, so joins and counts still work.
Pseudonyms keep analyses running; they are not encryption. They need a key
you keep to yourself, because anyone with the key can test a guessed phone
number against them. Fields allowed in `.piinata.yml` are left alone.

For files, `pii_redact_files()` writes a redacted copy beside each flagged
one, `survey.dta` to `survey_redacted.dta`, and reports on every file:

``` r
pii_redact_files("path/to/project", key = "a secret")
#> # A tibble: 4 × 4
#>   source                 status      destination           detail
#>   <chr>                  <chr>       <chr>                 <chr>
#> 1 project/crops.csv      clean       <NA>                  nothing to redact
#> 2 project/fieldwork.log  redacted    project/fieldwork_re… replaced: email, phone
#> 3 project/survey.dta     redacted    project/survey_redac… redacted: resp_name, q12, ...
#> 4 project/survey.sas7bdat unsupported <NA>                 haven cannot write SAS data …
```

Untouched columns are written as they were read, and Stata and SPSS labels
are kept. Delimited text, Excel, Stata, SPSS, SAS transport, R data, Parquet
and plain-text files can be written back; SAS data files, JSON and documents
are reported as unsupported. The originals are not changed: until they are
removed or kept out of version control, the personal data are still in the
project. To keep them out of git, add each one to `.gitignore`:

``` r
pii_ignore_originals(report)
```

This does not rewrite history; an original that was already committed is
reported, with the command that stops tracking it.

## What it reads

| Kind | Formats | Needs |
|---|---|---|
| Delimited text | csv, tsv, psv | |
| Spreadsheets | xlsx, xls, every sheet | |
| Statistical packages | Stata, SPSS, SAS, with variable and value labels | |
| R | rds | |
| Plain text | txt, md, log, do, R, tex and similar | |
| Survey platforms | Qualtrics exports, with question text | qualtRics |
| Columnar and JSON | parquet, json, jsonl | nanoparquet, jsonlite |
| Documents | pdf, docx, rtf, html | pdftools, officer, striprtf, rvest |

The last three rows use suggested packages. When one is missing the file is
reported as unsupported, with the package to install.

## What it looks for

- **Names and labels:** terms for names, phones, email, addresses, birth
  dates, places, coordinates and identity numbers, in English with some
  Spanish, French and Hindi, plus the fields Qualtrics, SurveyCTO and
  KoboToolbox add to exports.
- **Values:** email addresses, phone-like numbers, IP addresses, dates of
  birth, coordinates and person names.
- **Behavior:** free-text answers, and text that is different on nearly every
  row.
- **Identity numbers:** Aadhaar, GSTIN, PAN and others, when the
  [idcheck](https://github.com/gojiplus/idcheck) package is installed.

[How piinata works](https://gojiplus.github.io/piinata/articles/design.html)
has the design, the benchmark it is held to and what is out of scope. The
[roadmap](https://gojiplus.github.io/piinata/articles/roadmap.html) has what
comes next.
