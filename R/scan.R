# The distinct values of a field and their counts. Above `sample` distinct
# values an evenly spaced subset stands in for the rest; running text is
# always examined in full.
distinct_values <- function(field, sample) {
  values <- field$values[[1]]
  values <- values[!is.na(values)]
  distinct <- unique(values)
  clean <- normalize_values(distinct)
  values <- clean[match(values, distinct)]
  values <- values[nzchar(values)]
  distinct <- unique(values)
  weight <- tabulate(match(values, distinct), nbins = length(distinct))
  if (field$kind != "text" && length(distinct) > sample) {
    keep <- unique(round(seq(1, length(distinct), length.out = sample)))
    distinct <- distinct[keep]
    weight <- weight[keep]
  }
  list(values = distinct, weight = weight)
}

scan_field <- function(field, show_values, sample, config) {
  observed <- distinct_values(field, sample)
  named <- detect_name(field, observed$values, config$terms)
  if (name_contradicted(field, observed)) {
    # Places repeat across respondents, so few distinct values say nothing there.
    named <- lapply(named, function(f) {
      if (f$type %in% c("location", "coordinates")) f else replace(f, "confidence", "low")
    })
  }
  found <- c(
    named,
    detect_values(field, observed$values, observed$weight),
    detect_custom(field, observed$values, observed$weight, config$patterns)
  )
  if (length(found) == 0L) {
    return(empty_findings())
  }
  rows <- lapply(found, function(f) {
    examples <- f$examples[[1]]
    if (!show_values && f$evidence != "name") {
      examples <- mask(examples)
    }
    tibble::tibble(
      source = field$source, locator = field$locator, name = field$name, label = field$label,
      type = f$type, evidence = f$evidence, detector = f$detector, n = f$n, share = f$share,
      examples = list(examples), confidence = f$confidence
    )
  })
  do.call(rbind, rows)
}

#' Scan for likely personal data
#'
#' Looks at each field three ways: what it is called (its name, label or
#' question text, matched on whole words), what it contains (email addresses,
#' phone-like numbers, IP addresses, dates of birth, coordinates, person names)
#' and how it behaves (free text, or text that is distinct on nearly every
#' row). Each finding says which kind of evidence it rests on.
#'
#' In a table column a value pattern must match at least 5 values and 5% of
#' them; in free text and documents a single match is reported.
#'
#' The scan works on the distinct values of each column and uses the column's
#' type, so numeric, date and logical columns skip the text patterns and a
#' coded column costs little however many rows it has.
#'
#' The result is a list of things to review. An empty result does not show
#' that the data are safe to share.
#'
#' @param x Files or directories, a data frame, or fields from [pii_read()] or
#'   [as_pii_fields()].
#' @param show_values If `FALSE`, the default, example values in the result
#'   are masked so the report does not itself leak.
#' @param sample The most distinct values examined in one table column; 10,000
#'   unless the configuration says otherwise. A column with more is judged from
#'   an evenly spaced subset, and `n` then counts matches within that subset.
#'   Use `Inf` to examine every value. Running text is always examined in full.
#' @param config The project's configuration, from [pii_config()]: files to
#'   ignore, custom patterns and extra terms.
#' @return A tibble with one row per finding: `source`, `locator`, `name`,
#'   `label`, `type`, `evidence` (`name`, `value` or `structure`), `detector`,
#'   `n` and `share` of matching values, `examples` and `confidence`.
#' @export
#' @examples
#' survey <- data.frame(
#'   q1 = paste0("person", 1:20, "@example.org"),
#'   reason = rep(c("work", "family"), 10)
#' )
#' pii_scan(survey)
pii_scan <- function(x, show_values = FALSE, sample = NULL, config = pii_config()) {
  if (is.null(sample)) {
    sample <- if (is.null(config$sample)) 10000 else config$sample
  }
  if (is.data.frame(x) && all(c("source", "locator", "values", "kind") %in% names(x))) {
    fields <- x
  } else if (is.data.frame(x)) {
    fields <- as_pii_fields(x)
  } else if (is.character(x)) {
    fields <- pii_read(x, ignore = config$ignore)
  } else {
    cli::cli_abort("{.arg x} must be paths, a data frame or fields, not {.obj_type_friendly {x}}.")
  }
  rows <- lapply(seq_len(nrow(fields)), function(i) {
    scan_field(fields[i, ], show_values, sample, config)
  })
  findings <- do.call(rbind, c(list(empty_findings()), rows))
  attr(findings, "read_report") <- pii_read_report(fields)
  attr(findings, "config") <- config
  findings
}
