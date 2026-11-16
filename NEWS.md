# piinata (development version)

* `pii_ignore_originals()` works with git built on MSYS, which prints
  repository paths as `/d/...` that R on Windows cannot open.
* Google Inc. is credited as the copyright holder of the bundled postcode
  patterns, which are CC BY 4.0 (`inst/COPYRIGHTS`).

# piinata 0.1.0

First release.

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
* Postal addresses are found from their values: two of a postcode, a house
  marker and an area word. Postcode patterns for 182 countries come from
  Google's address metadata and follow the `regions` setting.
* The benchmark gains Indian and US names and addresses, names in lower case
  and Devanagari, and decoy columns of place, facility, scheme, caste, crop,
  city, business and street names; `score_piinata.R` scores a scan against it.
* `use_gliner()` turns on an optional named-entity backend, GLiNER through
  'reticulate', which takes a second look at text columns the rules leave
  uncertain: it adds a person-name finding when most rows name people, and
  withdraws the rules' guess when they name places or organizations.
* `pii_read()` reads more formats: zip and tar archives member by member
  (`archive.zip!member`), Jupyter notebooks with their outputs, GeoJSON,
  KML/KMZ, shapefiles and GeoPackages (coordinates and attributes), SQLite
  databases, ods, xlsm and pptx files, and as text, scripts for SAS, SPSS,
  Julia, MATLAB and the shell, contact cards, mail, calendars and
  transcripts. Shapefile side files are reported as ignored; legacy `.doc`
  files as unsupported, with what to do.
* Value findings move up a grade when the column's name or label names
  their kind, after Presidio's context words. Custom patterns in
  `.piinata.yml` may match a list of `words`, `exclude` values, `validate`
  against an idcheck scheme or check-digit algorithm, and carry `context`
  words. In sentences, custom patterns count single matches, as built-in
  ones do.
* IBANs, MAC addresses and UUIDs are checked with 'checkstring'; US Social
  Security, UK NHS and payment card numbers with 'idcheck', when installed.
* Lessons from real web tables (SOTAB): HTML character references are
  decoded before matching, so obfuscated addresses such as `info&#64;...` are
  found; dotted phone numbers (970.369.7799) count; year spans and ordinals
  ("21st") no longer look like phones and streets; address cues must sit
  within 40 characters of each other; and a birth date read from values alone
  is `low` until the column's name agrees.
* Fixes from an independent review before release: redaction finds and
  replaces matches in the normalized text the scan matched, so obfuscated and
  full-width emails no longer survive it; pseudonyms are drawn from SHA-256,
  not R's random-number generator, so they are the same in every session,
  collide rarely, and replace letters of every script; hidden files are read
  (`.git` is left out); Excel dates are read as dates; RData objects with
  hidden names are kept; `.xlsm` files are redacted to xlsx; `ignore` and
  `allow` globs are relative to the folder of `.piinata.yml` and match file
  names with regex characters; YAML's `NO` and `yes` are read as words; the
  unpacking limit covers gzip, bzip2, xz and compressed tar files
  (`options(piinata.max_unpacked = )`); redaction follows the
  configuration's `min_confidence`; card numbers in free text are found as
  `financial_account`; text files keep their line endings; and two files
  that would write the same redacted copy are both reported. Requires R 4.5.
  A second review of those fixes led to more: a span is replaced in the raw
  text, so a redacted line keeps its spacing, and only cells where an
  obfuscated match survives are normalized; Excel numbers keep their digits;
  a redacted dotfile is named `_redacted.Rhistory`, which reads as its type;
  folders tools keep for themselves (`.git`, `.venv`, `node_modules`,
  `.Rproj.user` and the like) are reported once each as ignored; and globs
  hold through symlinked paths. Files named as redacted copies are skipped
  even when their original is gone, so a re-run does not stack copies.
* Names settled before the first release. A finding's `type` is the kind of
  personal data and `detector` the rule that matched: identity numbers are
  `government_id` with detector `idcheck:<scheme>` (was the scheme as type),
  cards and IBANs `financial_account` (was `intl_payment_card`, `iban`), MAC
  addresses `device_id` with detector `checkstring:mac`. An `IPAddress`
  column is named `ip_address` (was `online_id`). Report columns:
  `pii_read_report()` `fields` -> `n_fields`; `pii_ignore_originals()`
  `tracked` -> `is_tracked`. Indian mobile numbers are left to the phone
  detector. Source files use snake_case.
* Latitude and longitude in neighboring columns are found as a pair, from
  their values: precise numbers in range, one within ±90. Columns named as
  rates, prices, scores and the like are never candidates. On SOTAB's test
  tables it finds all 26 coordinate columns and no other labeled column.
  (The design article had claimed value-based coordinates before they
  existed.)
* The README compares piinata and Presidio on SOTAB, real web tables neither
  wrote: F1 0.68 for piinata with `use_gliner()` against 0.42 for Presidio's
  best configuration, on a test split scored once. Scripts and protocol are
  in `data-raw/benchmark/external/`.
* `pii_ignore_originals()` adds the originals of redacted files to
  `.gitignore`, one rule per file, checks each rule with `git check-ignore`,
  and reports originals already tracked and copies an existing rule hides.
* The package is named piinata; it was briefly piiscan. The configuration file
  is `.piinata.yml`.
* Phone-like numbers are graded by how they are written and how much of a
  column they fill: bare digits need nine rows in ten across at least a
  hundred rows, or a name or label that says phone.
