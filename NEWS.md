# piiscan (development version)

* `pii_read()` reads delimited text, Excel, Stata, SPSS, SAS, R data, plain
  text, Parquet, JSON, PDF, Word, RTF, HTML and Qualtrics exports into fields,
  and `pii_read_report()` accounts for every file.
* `pii_scan()` finds likely personal data from field names and labels, from
  values, and from how a field behaves.
* `pii_summary()` gives one row per flagged field; `pii_check()` stops a script
  when something has not been reviewed.
