# Patterns a project declares for its own identifiers, held to the same
# threshold as the built-in value patterns.
detect_custom <- function(field, values, weight, patterns) {
  if (length(values) == 0L || length(patterns) == 0L) {
    return(list())
  }
  total <- sum(weight)
  threshold <- if (field$kind == "text") 1 else max(5, 0.05 * total)
  found <- list()
  for (pattern in patterns) {
    hit <- stringr::str_detect(values, pattern$regex)
    hit[is.na(hit)] <- FALSE
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
