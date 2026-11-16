## Test environments

* macOS (local), R 4.6.0
* GitHub Actions: Ubuntu (release, devel, oldrel-1), macOS (release), Windows (release)

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.
* The suggested packages 'idcheck' and 'dialtone' are sister packages by the
  same maintainer, submitted to CRAN separately. They are used only when
  installed (`rlang::is_installed()`), and tests and examples run without them.
* The example for `use_gliner()` is in `\dontrun{}`: it needs Python, installs
  the 'gliner' Python package through 'reticulate' and downloads a 1 GB model
  from Hugging Face. Every other example runs.
* The postcode patterns in `R/sysdata.rda` come from Google's Address Data
  Service under CC BY 4.0; Google Inc. is listed as a copyright holder and the
  attribution is in `inst/COPYRIGHTS`.

## Reverse dependencies

There are none; this is a new package.
