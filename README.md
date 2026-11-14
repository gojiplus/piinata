# piiscan

<!-- badges: start -->
[![R-CMD-check](https://github.com/gojiplus/piiscan/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/gojiplus/piiscan/actions/workflows/R-CMD-check.yml)
<!-- badges: end -->

Find likely personal data in research files before they are shared.

piiscan reads survey exports, statistical data files, spreadsheets and text
documents, and reports which fields look personal and why. It looks at what a
field is called, what it contains, and how it behaves, so an email address in a
column named `q12` is found as readily as one in a column named `email`.

It is a scanner. It does not anonymize, and an empty report does not show that
data are safe to share.

## Installation

``` r
# install.packages("pak")
pak::pak("gojiplus/piiscan")
```

## Usage

Point it at a folder, a file or a data frame:

``` r
library(piiscan)

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

[SPEC.md](SPEC.md) has the design, the benchmark it is held to, and what is
out of scope.
