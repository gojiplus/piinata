#' Review findings and record the decisions
#'
#' The scanner proposes; a person decides. `pii_review()` writes one row per
#' flagged field to a CSV file with two empty columns, `decision` and
#' `reason`. Fill in `allow` for a field that may stay, with the reason, and
#' `remove` for one that must go. `pii_accept()` then records the allowed
#' fields in the project's `.piinata.yml`, where [pii_check()] finds them, so a
#' decision is made once and kept with the data.
#'
#' @param findings The result of [pii_scan()].
#' @param file The review file to write or read.
#' @param config The project configuration file to update.
#' @return `pii_review()` returns `file`, invisibly. `pii_accept()` returns the
#'   updated configuration, invisibly.
#' @export
#' @examples
#' dir <- tempfile()
#' dir.create(dir)
#' review <- file.path(dir, "review.csv")
#' config <- file.path(dir, ".piinata.yml")
#' findings <- pii_scan(data.frame(village = paste("Village", 1:30)))
#' pii_review(findings, review)
#'
#' decisions <- read.csv(review)
#' decisions$decision <- "allow"
#' decisions$reason <- "Needed for clustering."
#' write.csv(decisions, review, row.names = FALSE)
#'
#' pii_accept(review, config)
#' pii_check(findings, config = pii_config(config))
pii_review <- function(findings, file = "piinata-review.csv") {
  review <- pii_summary(findings)
  review$decision <- rep("", nrow(review))
  review$reason <- rep("", nrow(review))
  readr::write_csv(review, file)
  cli::cli_inform(c(
    "Wrote {nrow(review)} field{?s} to review to {.file {file}}.",
    "i" = "Set {.field decision} to {.val allow} or {.val remove}, give a {.field reason},
           then run {.code pii_accept()}."
  ))
  invisible(file)
}

#' @rdname pii_review
#' @export
pii_accept <- function(file = "piinata-review.csv", config = ".piinata.yml") {
  review <- readr::read_csv(
    file,
    col_types = readr::cols(.default = readr::col_character()), na = character()
  )
  decision <- tolower(trimws(review$decision))
  unknown <- setdiff(unique(decision), c("", "allow", "remove"))
  if (length(unknown) > 0L) {
    cli::cli_abort(
      "A {.field decision} must be {.val allow} or {.val remove}, not {.val {unknown}}."
    )
  }
  allowed <- review[decision == "allow", ]
  if (any(!nzchar(trimws(allowed$reason)))) {
    cli::cli_abort("Every allowed field in {.file {file}} needs a {.field reason}.")
  }
  rules <- lapply(seq_len(nrow(allowed)), function(i) {
    list(field = allowed$locator[i], source = allowed$source[i], reason = allowed$reason[i])
  })
  raw <- if (fs::file_exists(config)) read_config_yaml(config) else list()
  raw$allow <- unique(c(raw$allow, rules))
  yaml::write_yaml(raw, config)
  cli::cli_inform("Recorded {length(rules)} allowed field{?s} in {.file {config}}.")
  invisible(pii_config(config))
}
