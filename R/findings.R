finding <- function(type, evidence, detector, n, share, examples, confidence) {
  list(
    type = type, evidence = evidence, detector = detector, n = as.integer(n),
    share = share, examples = list(utils::head(unique(examples), 3L)), confidence = confidence
  )
}

mask <- function(x) {
  keep <- stringr::str_sub(x, 1L, 2L)
  rest <- stringr::str_sub(x, 3L)
  rest <- stringr::str_replace_all(rest, "\\p{L}", "x")
  paste0(keep, stringr::str_replace_all(rest, "\\d", "9"))
}

empty_findings <- function() {
  tibble::tibble(
    source = character(), locator = character(), name = character(), label = character(),
    type = character(), evidence = character(), detector = character(), n = integer(),
    share = numeric(), examples = list(), confidence = character()
  )
}
