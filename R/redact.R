# Each method turns a vector of values into its redacted form. A pseudonym
# keeps the shape of a value (letters stay letters, digits stay digits) and
# maps equal values to equal pseudonyms, so joins, counts and formats keep
# working on the redacted data.
pseudonym <- function(values, key) {
  distinct <- unique(values[!is.na(values)])
  replacement <- vapply(distinct, function(value) {
    seed <- strtoi(substr(rlang::hash(paste0(key, value)), 1L, 7L), base = 16L)
    withr::with_seed(seed, {
      chars <- strsplit(value, "")[[1]]
      upper <- grepl("[[:upper:]]", chars)
      lower <- grepl("[[:lower:]]", chars)
      digit <- grepl("[[:digit:]]", chars)
      chars[upper] <- sample(LETTERS, sum(upper), replace = TRUE)
      chars[lower] <- sample(letters, sum(lower), replace = TRUE)
      chars[digit] <- as.character(sample(0:9, sum(digit), replace = TRUE))
      paste(chars, collapse = "")
    })
  }, character(1))
  unname(replacement[match(values, distinct)])
}

redactors <- function(key) {
  list(
    mask = function(values, type) ifelse(is.na(values), NA_character_, mask(values)),
    placeholder = function(values, type) {
      ifelse(is.na(values), NA_character_, paste0("<", toupper(type), ">"))
    },
    pseudonym = function(values, type) pseudonym(values, key)
  )
}

# Within free text only the matched spans are replaced; the rest of the answer
# is kept.
redact_spans <- function(values, types, redact) {
  for (type in intersect(types, c("email", "phone", "ip_address"))) {
    hit <- matched(values, type)
    found <- !is.na(hit)
    if (any(found)) {
      values[found] <- stringr::str_replace(
        values[found], stringr::fixed(hit[found]), redact(hit[found], type)
      )
    }
  }
  values
}

#' Redact the fields a scan flagged
#'
#' Returns a copy of `data` with flagged columns removed or their values
#' replaced. Four methods, in increasing order of what survives:
#'
#' * `"drop"` removes the column.
#' * `"placeholder"` replaces each value with its type, such as `<EMAIL>`.
#' * `"mask"` keeps the first two characters and hides the rest.
#' * `"pseudonym"` replaces each value with a made-up one of the same shape,
#'   the same every time for the same value and `key`, so joins across files,
#'   counts of distinct people and format checks still work.
#'
#' In free text, and in any column where only some values match, only the
#' matched email addresses, phone numbers and IP addresses are replaced; with
#' `"drop"` the whole column goes.
#'
#' Pseudonyms are for keeping analyses running, not for security. They are not
#' encryption, the same `key` always gives the same result, and a column of
#' pseudonyms can still identify people through what surrounds it. Names
#' buried in free text are not found without a language model.
#'
#' @param data A data frame.
#' @param findings The result of [pii_scan()] on `data`. Scanned if missing.
#' @param method One method for every flagged column, or a named vector giving
#'   the method per finding type, with an optional `default`.
#' @param key A string that determines the pseudonyms. Keep it out of the
#'   shared files; use the same key to redact files that must still join.
#' @param min_confidence The weakest findings to act on.
#' @return `data` with the flagged columns redacted, and the actions taken as
#'   its `"redactions"` attribute.
#' @export
#' @examples
#' survey <- data.frame(
#'   id = 1:20,
#'   email = paste0("person", 1:20, "@example.org"),
#'   village = rep(c("Palpur", "Netrad"), 10)
#' )
#' clean <- pii_redact(survey, method = c(email = "pseudonym", default = "drop"), key = "s3")
#' head(clean)
#' attr(clean, "redactions")
pii_redact <- function(data, findings = pii_scan(data), method = "pseudonym",
                       key = "piinata", min_confidence = "medium") {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame, not {.obj_type_friendly {data}}.")
  }
  methods <- c("drop", "placeholder", "mask", "pseudonym")
  unknown <- setdiff(method, methods)
  if (length(unknown) > 0L) {
    cli::cli_abort("{.arg method} must be one of {.or {.val {methods}}}, not {.val {unknown}}.")
  }
  min_confidence <- rlang::arg_match0(min_confidence, confidence_levels, "min_confidence")
  graded <- match(findings$confidence, confidence_levels) >=
    match(min_confidence, confidence_levels)
  findings <- findings[graded & findings$name %in% names(data), ]
  redact <- redactors(key)
  default <- if (is.null(names(method))) method[[1]] else unname(method["default"])
  actions <- list()
  for (column in unique(findings$name)) {
    types <- unique(findings$type[findings$name == column])
    chosen <- unname(stats::na.omit(c(method[types], default))[1])
    if (is.na(chosen)) {
      next
    }
    type <- setdiff(types, c("free_text", "unique_text"))[1]
    share <- findings$share[findings$name == column & findings$evidence == "value"]
    partial <- "free_text" %in% types || any(share < 0.8)
    type <- if (is.na(type)) "text" else type
    if (chosen == "drop") {
      data[[column]] <- NULL
    } else if (partial) {
      data[[column]] <- redact_spans(as_text(data[[column]]), types, redact[[chosen]])
    } else {
      data[[column]] <- redact[[chosen]](as_text(data[[column]]), type)
    }
    actions <- c(actions, list(tibble::tibble(name = column, type = type, method = chosen)))
  }
  empty <- tibble::tibble(name = character(), type = character(), method = character())
  attr(data, "redactions") <- do.call(rbind, c(list(empty), actions))
  data
}
