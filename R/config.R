confidence_levels <- c("low", "medium", "high")

matches_glob <- function(x, globs) {
  if (length(globs) == 0L) {
    return(rep(FALSE, length(x)))
  }
  paths <- sub("^\\./", "", x)
  hits <- vapply(globs, function(glob) {
    pattern <- utils::glob2rx(sub("^\\./", "", glob))
    grepl(pattern, paths) | grepl(pattern, basename(paths))
  }, logical(length(x)))
  rowSums(matrix(hits, nrow = length(x))) > 0
}

check_allow <- function(rule, path) {
  if (!is.list(rule) || !any(c("field", "type", "source") %in% names(rule))) {
    cli::cli_abort("Each {.field allow} entry in {.file {path}} needs a field, type or source.")
  }
  if (is.null(rule$reason) || !nzchar(trimws(rule$reason))) {
    cli::cli_abort("Each {.field allow} entry in {.file {path}} needs a {.field reason}.")
  }
  rule[intersect(c("field", "type", "source", "reason"), names(rule))]
}

check_pattern <- function(pattern, path) {
  if (is.null(pattern$name) || is.null(pattern$regex)) {
    cli::cli_abort("Each {.field patterns} entry in {.file {path}} needs a name and a regex.")
  }
  valid <- tryCatch(is.logical(stringr::str_detect("", pattern$regex)), error = function(e) FALSE)
  if (!valid) {
    cli::cli_abort(
      "Pattern {.val {pattern$name}} in {.file {path}} is not a valid regular expression."
    )
  }
  confidence <- if (is.null(pattern$confidence)) "medium" else pattern$confidence
  list(
    name = pattern$name, regex = pattern$regex,
    type = if (is.null(pattern$type)) pattern$name else pattern$type,
    confidence = rlang::arg_match0(confidence, confidence_levels, "confidence")
  )
}

#' Read a project's piinata configuration
#'
#' A project records what it has decided in a `.piinata.yml` file kept with the
#' data: which findings were reviewed and may stay, which files are not
#' scanned, and which extra patterns and terms matter to the study.
#' [pii_scan()] and [pii_check()] read it by default.
#'
#' ```yaml
#' allow:
#'   - field: village
#'     reason: Needed for clustering; approved in the data management plan.
#'   - type: person_name
#'     source: data/elections/*
#'     reason: Public record of elected officials.
#' ignore:
#'   - data/raw/*
#' patterns:
#'   - name: study_id
#'     regex: "^RJ-[0-9]{6}$"
#'     confidence: high
#' terms:
#'   person_name: [mukhiya]
#' regions: [IN]
#' min_confidence: medium
#' sample: 10000
#' ```
#'
#' An `allow` entry names a `field`, a `type` of finding, a `source` glob, or
#' any combination, and must give a `reason`. Custom `patterns` are regular
#' expressions tried on values; `terms` add words to the vocabulary used on
#' field names and labels. `regions` names the countries whose numbering plans
#' judge phone numbers written without a country code, as two-letter codes
#' (see `dialtone::phone_regions()`); it is used when the 'dialtone' package
#' is installed.
#'
#' @param path The configuration file. A missing file gives an empty
#'   configuration.
#' @return A list of class `pii_config`.
#' @export
#' @examples
#' file <- tempfile(fileext = ".yml")
#' writeLines(c("allow:", "  - field: village", "    reason: Needed for clustering."), file)
#' pii_config(file)$allow
pii_config <- function(path = ".piinata.yml") {
  config <- list(
    allow = list(), ignore = character(), patterns = list(), terms = list(),
    regions = character(), min_confidence = NULL, sample = NULL, path = path
  )
  if (!fs::file_exists(path)) {
    return(structure(config, class = "pii_config"))
  }
  raw <- yaml::read_yaml(path)
  unknown <- setdiff(names(raw), names(config))
  if (length(unknown) > 0L) {
    cli::cli_abort(
      "{cli::qty(length(unknown))}Unknown setting{?s} {.val {unknown}} in {.file {path}}."
    )
  }
  config$allow <- lapply(raw$allow, check_allow, path = path)
  config$ignore <- as.character(unlist(raw$ignore))
  config$patterns <- lapply(raw$patterns, check_pattern, path = path)
  config$terms <- lapply(raw$terms, function(words) tolower(as.character(unlist(words))))
  if (!is.null(raw$min_confidence)) {
    config$min_confidence <- rlang::arg_match0(
      raw$min_confidence, confidence_levels, "min_confidence"
    )
  }
  config$sample <- raw$sample
  config$regions <- check_regions(toupper(as.character(unlist(raw$regions))), path)
  structure(config, class = "pii_config")
}

check_regions <- function(regions, path) {
  if (length(regions) == 0L || !rlang::is_installed("dialtone")) {
    return(regions)
  }
  unknown <- setdiff(regions, dialtone::phone_regions()$region)
  if (length(unknown) > 0L) {
    cli::cli_abort(c(
      "{cli::qty(length(unknown))}Unknown region{?s} {.val {unknown}} in {.file {path}}.",
      "i" = "{.fn dialtone::phone_regions} lists the two-letter codes."
    ))
  }
  regions
}

allowed_by <- function(findings, rules) {
  allowed <- rep(FALSE, nrow(findings))
  for (rule in rules) {
    match <- rep(TRUE, nrow(findings))
    if (!is.null(rule$field)) {
      match <- match & (findings$name %in% rule$field | findings$locator %in% rule$field)
    }
    if (!is.null(rule$type)) {
      match <- match & findings$type %in% rule$type
    }
    if (!is.null(rule$source)) {
      match <- match & matches_glob(findings$source, rule$source)
    }
    allowed <- allowed | match
  }
  allowed
}
