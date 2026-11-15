# A pattern a project declares matches a regular expression or a list of
# words, may exclude values or require them to pass a check, and is held to
# the same threshold as the built-in value patterns. The parts follow
# Microsoft Presidio's recognizers: a pattern, a deny-list, an invalidation
# and a validation.
custom_hits <- function(values, pattern) {
  hit <- rep(FALSE, length(values))
  if (!is.null(pattern$regex)) {
    hit <- hit | stringr::str_detect(values, pattern$regex)
  }
  if (length(pattern$words) > 0L) {
    words <- paste0(
      "(?i)(?<![\\p{L}\\p{N}])(?:", paste(stringr::str_escape(pattern$words), collapse = "|"),
      ")(?![\\p{L}\\p{N}])"
    )
    hit <- hit | stringr::str_detect(values, words)
  }
  if (!is.null(pattern$exclude)) {
    hit <- hit & !stringr::str_detect(values, pattern$exclude)
  }
  if (!is.null(pattern$validate)) {
    hit[hit] <- validates(values[hit], pattern$validate)
  }
  hit[is.na(hit)] <- FALSE
  hit
}

# An idcheck scheme, or one of its check-digit algorithms applied to the
# value's digits and letters.
validates <- function(values, check) {
  if (check %in% idcheck::id_schemes()$scheme) {
    return(idcheck::id_valid(values, check))
  }
  bare <- toupper(gsub("[^0-9A-Za-z]", "", values))
  switch(check,
    luhn = idcheck::id_luhn_valid(bare),
    verhoeff = idcheck::id_verhoeff_valid(bare),
    damm = idcheck::id_damm_valid(bare),
    mod11_2 = idcheck::id_mod11_2_valid(bare),
    mod97_10 = idcheck::id_mod97_10_valid(bare)
  )
}

detect_custom <- function(field, values, weight, patterns) {
  if (length(values) == 0L || length(patterns) == 0L) {
    return(list())
  }
  total <- sum(weight)
  threshold <- if (match_by_match(field, values, weight)) 1 else max(5, 0.05 * total)
  found <- list()
  for (pattern in patterns) {
    hit <- custom_hits(values, pattern)
    n <- sum(weight[hit])
    if (n >= threshold) {
      detector <- paste0("custom:", pattern$name)
      found <- c(found, list(finding(
        pattern$type, "value", detector, n, n / total, values[hit], pattern$confidence
      )))
    }
  }
  found
}
