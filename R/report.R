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
#' @param min_confidence The weakest findings that stop the check: `"low"`,
#'   `"medium"` or `"high"`. Low-confidence findings, such as text that merely
#'   looks like names, are for reading, not for gating.
#' @return `findings`, invisibly, when nothing unallowed remains.
#' @export
#' @examples
#' findings <- pii_scan(data.frame(village = rep(c("A", "B"), 10)))
#' pii_check(findings, allow = "village")
pii_check <- function(findings, allow = character(), min_confidence = "medium") {
  report <- pii_read_report(findings)
  unread <- if (is.null(report)) character() else report$source[report$status != "read"]
  if (length(unread) > 0L) {
    cli::cli_abort(c("Could not read {length(unread)} file{?s}.", "x" = "{.file {unread}}"))
  }
  levels <- c("low", "medium", "high")
  min_confidence <- rlang::arg_match(min_confidence, levels)
  graded <- match(findings$confidence, levels) >= match(min_confidence, levels)
  open <- findings[graded & !(findings$name %in% allow | findings$locator %in% allow), ]
  if (nrow(open) > 0L) {
    cli::cli_abort(c(
      "Found possible personal data in {length(unique(open$locator))} field{?s}.",
      "x" = "{.val {unique(open$locator)}}",
      "i" = "Review them, then remove them or pass them to {.arg allow}."
    ))
  }
  invisible(findings)
}
