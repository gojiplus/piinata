empty_findings <- function() {
  tibble::tibble(
    source = character(), locator = character(), name = character(), label = character(),
    type = character(), evidence = character(), detector = character(), n = integer(),
    share = numeric(), examples = list(), confidence = character()
  )
}

scan_field <- function(field, show_values) {
  values <- field$values[[1]]
  values <- values[!is.na(values) & nzchar(values)]
  found <- c(detect_name(field, values), detect_values(field, values))
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
#' The result is a list of things to review. An empty result does not show
#' that the data are safe to share.
#'
#' @param x Files or directories, a data frame, or fields from [pii_read()] or
#'   [as_pii_fields()].
#' @param show_values If `FALSE`, the default, example values in the result
#'   are masked so the report does not itself leak.
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
pii_scan <- function(x, show_values = FALSE) {
  if (is.data.frame(x) && all(c("source", "locator", "values", "kind") %in% names(x))) {
    fields <- x
  } else if (is.data.frame(x)) {
    fields <- as_pii_fields(x)
  } else if (is.character(x)) {
    fields <- pii_read(x)
  } else {
    cli::cli_abort("{.arg x} must be paths, a data frame or fields, not {.obj_type_friendly {x}}.")
  }
  rows <- lapply(seq_len(nrow(fields)), function(i) scan_field(fields[i, ], show_values))
  findings <- do.call(rbind, c(list(empty_findings()), rows))
  attr(findings, "read_report") <- pii_read_report(fields)
  findings
}

#' One row per flagged field
#'
#' @param findings The result of [pii_scan()].
#' @return A tibble with `source`, `locator`, `name`, the `types` found, the
#'   kinds of `evidence`, and the highest `confidence`.
#' @export
#' @examples
#' pii_summary(pii_scan(data.frame(email = paste0("p", 1:20, "@example.org"))))
pii_summary <- function(findings) {
  if (nrow(findings) == 0L) {
    return(tibble::tibble(
      source = character(), locator = character(), name = character(),
      types = character(), evidence = character(), confidence = character()
    ))
  }
  key <- paste(findings$source, findings$locator, sep = "\r")
  levels <- c("low", "medium", "high")
  rows <- lapply(split(findings, factor(key, unique(key))), function(f) {
    tibble::tibble(
      source = f$source[1], locator = f$locator[1], name = f$name[1],
      types = paste(unique(f$type), collapse = ", "),
      evidence = paste(unique(f$evidence), collapse = ", "),
      confidence = levels[max(match(f$confidence, levels))]
    )
  })
  do.call(rbind, unname(rows))
}

#' Stop if personal data remain
#'
#' For scripts and continuous integration: errors when the scan found
#' anything that has not been reviewed and allowed, or when a file could not
#' be read.
#'
#' @param findings The result of [pii_scan()].
#' @param allow Field names or locators that have been reviewed and may stay.
#' @return `findings`, invisibly, when nothing unallowed remains.
#' @export
#' @examples
#' findings <- pii_scan(data.frame(village = rep(c("A", "B"), 10)))
#' pii_check(findings, allow = "village")
pii_check <- function(findings, allow = character()) {
  report <- pii_read_report(findings)
  unread <- if (is.null(report)) character() else report$source[report$status != "read"]
  if (length(unread) > 0L) {
    cli::cli_abort(c("Could not read {length(unread)} file{?s}.", "x" = "{.file {unread}}"))
  }
  open <- findings[!(findings$name %in% allow | findings$locator %in% allow), ]
  if (nrow(open) > 0L) {
    cli::cli_abort(c(
      "Found possible personal data in {length(unique(open$locator))} field{?s}.",
      "x" = "{.val {unique(open$locator)}}",
      "i" = "Review them, then remove them or pass them to {.arg allow}."
    ))
  }
  invisible(findings)
}
