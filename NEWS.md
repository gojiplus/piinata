# piiscan (development version)

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
* `pii_config()` reads a project's `.piiscan.yml`: reviewed exceptions with
  reasons, files to ignore, custom patterns and extra terms.
* `pii_review()` and `pii_accept()` write findings for a person to decide on
  and record the decisions.
* `pii_redact()` drops, masks, replaces or pseudonymizes flagged columns.
