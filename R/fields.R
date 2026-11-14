new_fields <- function(source = character(), locator = character(), name = character(),
                       label = character(), values = list(), kind = character(),
                       type = rep("character", length(source))) {
  tibble::tibble(
    source = source, locator = locator, name = name, label = label,
    values = values, kind = kind, type = type
  )
}

storage_type <- function(x) {
  if (haven::is.labelled(x) || is.factor(x)) {
    "character"
  } else if (inherits(x, c("Date", "POSIXt"))) {
    "date"
  } else if (is.logical(x)) {
    "logical"
  } else if (is.numeric(x)) {
    "numeric"
  } else {
    "character"
  }
}

as_text <- function(x) {
  if (haven::is.labelled(x)) {
    x <- haven::as_factor(x)
  }
  if (is.list(x)) {
    x <- vapply(x, function(v) paste(format(v), collapse = " "), character(1))
  }
  as.character(x)
}

fields_from_table <- function(data, source, sheet = NULL) {
  if (ncol(data) == 0L) {
    return(new_fields())
  }
  labels <- vapply(data, function(x) {
    label <- attr(x, "label", exact = TRUE)
    if (is.null(label)) NA_character_ else as.character(label)[1]
  }, character(1))
  locator <- if (is.null(sheet)) names(data) else paste0(sheet, "!", names(data))
  new_fields(
    source = rep(source, ncol(data)), locator = locator, name = names(data),
    label = unname(labels), values = unname(lapply(data, as_text)),
    kind = rep("tabular", ncol(data)),
    type = unname(vapply(data, storage_type, character(1)))
  )
}

fields_from_text <- function(text, source, locator = "text") {
  text <- stringr::str_squish(text)
  text <- text[!is.na(text) & nzchar(text)]
  new_fields(
    source = source, locator = locator, name = NA_character_, label = NA_character_,
    values = list(text), kind = "text"
  )
}

#' Turn a data frame or text into fields
#'
#' `pii_scan()` works on fields: one row per column of a table, or per block of
#' running text. Files are turned into fields by [pii_read()]; use this for
#' objects already in memory.
#'
#' @param x A data frame, or a character vector of text.
#' @param source A name for `x`, used in the `source` column of the result.
#' @return A tibble with columns `source`, `locator`, `name`, `label`, `values`,
#'   `kind` (`tabular` or `text`) and the column's storage `type`.
#' @export
#' @examples
#' as_pii_fields(data.frame(q1 = c("a@example.org", "b@example.org")))
#' as_pii_fields("Call Asha on 98765 43210.", source = "note")
as_pii_fields <- function(x, source = "data") {
  if (is.data.frame(x)) {
    return(fields_from_table(x, source))
  }
  if (is.character(x)) {
    return(fields_from_text(x, source))
  }
  cli::cli_abort(
    "{.arg x} must be a data frame or a character vector, not {.obj_type_friendly {x}}."
  )
}
