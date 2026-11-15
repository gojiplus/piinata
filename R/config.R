confidence_levels <- c("low", "medium", "high")

# A glob as a regular expression: `*` is any run of characters, `?` any one,
# and everything else stands for itself, so "a+b.csv" matches only itself.
# utils::glob2rx() leaves +, ^, $ and | as regex operators.
glob_regex <- function(glob) {
  pattern <- gsub("([.+^$|(){}\\[\\]\\\\])", "\\\\\\1", glob, perl = TRUE)
  pattern <- gsub("*", ".*", pattern, fixed = TRUE)
  paste0("^", gsub("?", ".", pattern, fixed = TRUE), "$")
}

# A glob in .piinata.yml names paths relative to the folder the file is in,
# so it holds whether a scan is given "data", "./data" or an absolute path.
# A glob also matches a bare file name.
matches_glob <- function(x, globs, root = ".") {
  if (length(globs) == 0L || length(x) == 0L) {
    return(rep(FALSE, length(x)))
  }
  inside <- sub("^([^!]*).*$", "\\1", x)
  relative <- as.character(fs::path_rel(fs::path_abs(inside), fs::path_abs(root)))
  relative <- paste0(relative, substring(x, nchar(inside) + 1L))
  forms <- list(sub("^\\./", "", x), relative, basename(x))
  hits <- vapply(globs, function(glob) {
    pattern <- glob_regex(sub("^\\./", "", glob))
    Reduce(`|`, lapply(forms, function(form) grepl(pattern, form)))
  }, logical(length(x)))
  rowSums(matrix(hits, nrow = length(x))) > 0
}

config_root <- function(config) {
  if (is.null(config$path)) "." else dirname(config$path)
}

# YAML 1.1 reads NO, yes and on as booleans; in a region list or a word list
# they are words ("NO" is Norway).
read_config_yaml <- function(path) {
  keep <- function(x) x
  yaml::read_yaml(path, handlers = list("bool#yes" = keep, "bool#no" = keep))
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
  if (is.null(pattern$name) || (is.null(pattern$regex) && is.null(pattern$words))) {
    cli::cli_abort(
      "Each {.field patterns} entry in {.file {path}} needs a name and a regex or words."
    )
  }
  for (part in intersect(c("regex", "exclude"), names(pattern))) {
    valid <- tryCatch(
      is.logical(stringr::str_detect("", pattern[[part]])),
      error = function(e) FALSE
    )
    if (!valid) {
      cli::cli_abort(c(
        "Pattern {.val {pattern$name}} in {.file {path}} is not a valid regular expression.",
        "i" = "Check its {.field {part}}."
      ))
    }
  }
  checks <- c(
    "luhn", "verhoeff", "damm", "mod11_2", "mod97_10",
    if (rlang::is_installed("idcheck")) idcheck::id_schemes()$scheme
  )
  if (!is.null(pattern$validate)) {
    rlang::check_installed("idcheck", "to validate patterns")
    if (!pattern$validate %in% checks) {
      cli::cli_abort(c(
        "Pattern {.val {pattern$name}} in {.file {path}} has an unknown {.field validate}.",
        "i" = "It must be one of {.or {.val {checks}}}."
      ))
    }
  }
  confidence <- if (is.null(pattern$confidence)) "medium" else pattern$confidence
  list(
    name = pattern$name, regex = pattern$regex, exclude = pattern$exclude,
    words = as.character(unlist(pattern$words)),
    context = tolower(as.character(unlist(pattern$context))),
    validate = pattern$validate,
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
#'   - name: interviewer
#'     type: person_name
#'     words: [Kamla Meena, Ravi Bairwa]
#'   - name: member_card
#'     regex: "[0-9]{16}"
#'     validate: luhn
#'     context: [member, card]
#'     confidence: low
#' terms:
#'   person_name: [mukhiya]
#' regions: [IN]
#' min_confidence: medium
#' sample: 10000
#' ```
#'
#' An `allow` entry names a `field`, a `type` of finding, a `source` glob, or
#' any combination, and must give a `reason`. Custom `patterns` match values
#' by a regular expression (`regex`) or a list of `words` found as whole
#' words, and may set an `exclude` expression for values that never count,
#' a `validate` check they must pass (an idcheck scheme, or `luhn`,
#' `verhoeff`, `damm`, `mod11_2`, `mod97_10`), and `context` words: when a
#' column's name or label holds one, its finding moves up a grade, as
#' built-in findings do when the name agrees with the values. `terms` add
#' words to the vocabulary used on field names and labels. `regions` names the
#' countries whose numbering plans judge phone numbers written without a
#' country code, as two-letter codes (see `dialtone::phone_regions()`); it is
#' used when the 'dialtone' package is installed.
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
  raw <- read_config_yaml(path)
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

allowed_by <- function(findings, rules, root = ".") {
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
      match <- match & matches_glob(findings$source, rule$source, root)
    }
    allowed <- allowed | match
  }
  allowed
}
