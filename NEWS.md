# piinata (development version)

* `pii_read()` reads delimited text, Excel, Stata, SPSS, SAS, R data, plain
  text, Parquet, JSON, PDF, Word, RTF, HTML and Qualtrics exports into fields,
  and `pii_read_report()` accounts for every file.
* `pii_scan()` finds likely personal data from field names and labels, from
  values, and from how a field behaves.
* `pii_summary()` gives one row per flagged field; `pii_check()` stops a script
  when something has not been reviewed.
* The scan works on distinct values, uses column types, and by default examines
  at most 10,000 distinct values per column (`sample`).
* Identity numbers are validated when the 'idcheck' package is installed.
* `pii_check()` gains `min_confidence`; low-confidence findings no longer stop
  it by default.
* `pii_config()` reads a project's `.piinata.yml`: reviewed exceptions with
  reasons, files to ignore, custom patterns and extra terms.
* `pii_review()` and `pii_accept()` write findings for a person to decide on
  and record the decisions.
* `pii_redact()` drops, masks, replaces or pseudonymizes flagged columns.
  Placeholders are the default; pseudonyms need a `key`, which has no default.
  Every match in a cell is replaced, not only the first, and fields allowed in
  `.piinata.yml` are left alone.
* `pii_redact_files()` writes a redacted copy beside each flagged file
  (delimited text, Excel, Stata, SPSS, SAS transport, R data, Parquet and
  plain text) and reports on every file, including the ones it cannot write
  back and the fields left below the confidence threshold.
* Phone-like numbers are checked against libphonenumber's numbering plans
  when the 'dialtone' package is installed: always for numbers with a country
  code, and for others against the new `regions` setting in `.piinata.yml`.
  A rejected number stops counting; a column in which at least 95% of 30 or
  more judged numbers are valid moves up a grade.
* `pii_ignore_originals()` adds the originals of redacted files to
  `.gitignore`, one rule per file, checks each rule with `git check-ignore`,
  and reports originals already tracked and copies an existing rule hides.
* The package is named piinata; it was briefly piiscan. The configuration file
  is `.piinata.yml`.
* Phone-like numbers are graded by how they are written and how much of a
  column they fill: bare digits need nine rows in ten across at least a
  hundred rows, or a name or label that says phone.
