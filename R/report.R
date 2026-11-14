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
#'   `"medium"` or `"high"`; `"medium"` unless the configuration says
#'   otherwise. Low-confidence findings, such as text that merely looks like
#'   names, are for reading, not for gating.
#' @param config The project's configuration, from [pii_config()]. By default
#'   the one the scan used. Its `allow` entries count as reviewed.
#' @return `findings`, invisibly, when nothing unallowed remains.
#' @export
#' @examples
#' findings <- pii_scan(data.frame(village = rep(c("A", "B"), 10)))
#' pii_check(findings, allow = "village")
pii_check <- function(findings, allow = character(), min_confidence = NULL, config = NULL) {
  if (is.null(config)) {
    config <- attr(findings, "config", exact = TRUE)
    config <- if (is.null(config)) pii_config() else config
  }
  if (is.null(min_confidence)) {
    min_confidence <- if (is.null(config$min_confidence)) "medium" else config$min_confidence
  }
  report <- pii_read_report(findings)
  unread <- report$source[report$status %in% c("unsupported", "failed")]
  if (length(unread) > 0L) {
    cli::cli_abort(c("Could not read {length(unread)} file{?s}.", "x" = "{.file {unread}}"))
  }
  levels <- c("low", "medium", "high")
  min_confidence <- rlang::arg_match(min_confidence, levels)
  graded <- match(findings$confidence, levels) >= match(min_confidence, levels)
  allowed <- findings$name %in% allow | findings$locator %in% allow |
    allowed_by(findings, config$allow)
  open <- findings[graded & !allowed, ]
  if (nrow(open) > 0L) {
    cli::cli_abort(c(
      "Found possible personal data in {length(unique(open$locator))} field{?s}.",
      "x" = "{.val {unique(open$locator)}}",
      "i" = "Review them with {.code pii_review()}, then remove them or record them as allowed."
    ))
  }
  invisible(findings)
}
