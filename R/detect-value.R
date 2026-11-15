patterns <- list(
  email = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
  phone = "(?<![\\d.])\\+?\\d[\\d\\s().-]{8,16}\\d(?!\\d)",
  ipv4 = "(?<![\\d.])\\d{1,3}(?:\\.\\d{1,3}){3}(?![\\d.])",
  person = "^\\p{Lu}[\\p{L}'.-]+(?:\\s+\\p{Lu}[\\p{L}'.-]+){1,3}$"
)

is_phone_like <- function(candidate) {
  digits <- stringr::str_count(candidate, "\\d")
  dated <- stringr::str_detect(candidate, "^\\d{4}[-./]\\d{1,2}[-./]\\d{1,2}")
  dotted <- stringr::str_detect(candidate, "^\\d+(?:\\.\\d+){1,3}$")
  digits >= 10L & digits <= 13L & !dated & !dotted
}

# Each detector sees the distinct values of a field and how often each occurs,
# so a coded column with a million rows costs as much as its handful of codes.
matched <- function(values, type) {
  switch(type,
    email = stringr::str_extract(values, patterns$email),
    phone = {
      candidate <- stringr::str_extract(values, patterns$phone)
      ifelse(is_phone_like(candidate), candidate, NA_character_)
    },
    ip_address = {
      candidate <- stringr::str_extract(values, patterns$ipv4)
      valid <- !is.na(suppressWarnings(ipaddress::ip_address(candidate)))
      ifelse(valid, candidate, NA_character_)
    }
  )
}

# Most ten-digit numbers are assignable phone numbers somewhere, so digits
# alone say little about one value. They say a lot about a column: random
# identifiers are almost never phone-like on nine rows in ten across a hundred
# rows. Short columns need a name or label that says phone, and a number
# written the way people write phone numbers (a leading plus, separators, or
# inside a sentence) needs neither.
phone_confidence <- function(values, weight, hit, free, corroborated) {
  found <- !is.na(hit)
  n <- sum(weight[found])
  share <- n / sum(weight)
  written <- stringr::str_detect(hit[found], "^\\+|\\d[\\s().-]+\\d")
  embedded <- nchar(values[found]) > nchar(hit[found]) + 4L
  deliberate <- sum(weight[found][written | embedded]) > n / 2
  filled <- share >= 0.9 && (sum(weight) >= 100 || corroborated)
  if (free || deliberate || filled) "medium" else "low"
}

# With the dialtone package, phone-like numbers are checked against
# libphonenumber's numbering plans: numbers written with a country code always,
# others against the project's `regions`. Validity is weak evidence for one
# number (about two in three random ten-digit strings are valid Indian
# numbers), so a rejected number stops counting, but only a column in which
# nearly every judged number is valid moves up a grade. At 30 numbers, random
# strings valid two times in three pass that bar about once in 2,000 columns;
# the odds fall quickly with more.
judge_phones <- function(hit, regions) {
  judged <- rep(NA, length(hit))
  if (!rlang::is_installed("dialtone")) {
    return(judged)
  }
  hit <- as.character(hit)
  present <- !is.na(hit)
  international <- present & startsWith(hit, "+")
  if (any(international)) {
    judged[international] <- dialtone::phone_valid(hit[international])
  }
  national <- present & !international
  if (any(national) && length(regions) > 0L) {
    valid <- Reduce(`|`, lapply(regions, function(region) {
      dialtone::phone_valid(hit[national], region = region)
    }))
    judged[national] <- valid
  }
  judged
}

upgrade <- function(confidence) {
  confidence_levels[min(match(confidence, confidence_levels) + 1L, length(confidence_levels))]
}

detect_patterns <- function(values, weight, free, types = c("email", "phone", "ip_address"),
                            corroborated = FALSE, regions = character()) {
  found <- list()
  total <- sum(weight)
  threshold <- if (free) 1 else max(5, 0.05 * total)
  for (type in types) {
    hit <- matched(values, type)
    judged <- if (type == "phone") judge_phones(hit, regions) else rep(NA, length(hit))
    hit[judged %in% FALSE] <- NA_character_
    n <- sum(weight[!is.na(hit)])
    if (n >= threshold) {
      confidence <- if (type == "phone") {
        graded <- phone_confidence(values, weight, hit, free, corroborated)
        verdicts <- judged[!is.na(judged)]
        if (length(verdicts) >= 30L && mean(verdicts) >= 0.95) upgrade(graded) else graded
      } else {
        "high"
      }
      examples <- hit[!is.na(hit)]
      found <- c(found, list(finding(type, "value", type, n, n / total, examples, confidence)))
    }
  }
  found
}

# Guessing date formats is slow, so only values shaped like dates are parsed.
parse_dates <- function(values) {
  dates <- rep(as.POSIXct(NA), length(values))
  shaped <- stringr::str_detect(values, "^\\s*\\d{1,4}[-/.]\\d{1,2}[-/.]\\d{1,4}(?:$|[ T])")
  shaped[is.na(shaped)] <- FALSE
  if (any(shaped)) {
    orders <- c("dmy", "mdy", "ymd", "ymd HMS", "ymd HM", "dmy HMS", "dmy HM", "mdy HMS", "mdy HM")
    dates[shaped] <- suppressWarnings(
      lubridate::parse_date_time(values[shaped], orders = orders, quiet = TRUE)
    )
  }
  dates
}

detect_birth_dates <- function(values, weight, dates = parse_dates(values)) {
  parsed <- !is.na(dates)
  share <- sum(weight[parsed]) / sum(weight)
  if (share < 0.8) {
    return(list())
  }
  typical <- stats::median(rep(lubridate::year(dates[parsed]), weight[parsed]))
  if (typical < 1900 || typical > lubridate::year(Sys.Date()) - 10) {
    return(list())
  }
  list(finding(
    "date_of_birth", "value", "birth_date", sum(weight[parsed]), share, values[parsed], "medium"
  ))
}

# Identity numbers, when the idcheck package is installed. A checksum makes a
# match strong evidence; a scheme that only fixes a shape does not.
detect_identity_numbers <- function(values, weight) {
  if (!rlang::is_installed("idcheck")) {
    return(list())
  }
  schemes <- idcheck::id_schemes()
  found <- list()
  for (i in seq_len(nrow(schemes))) {
    valid <- idcheck::id_valid(values, schemes$scheme[i])
    valid[is.na(valid)] <- FALSE
    share <- sum(weight[valid]) / sum(weight)
    if (share >= 0.8) {
      confidence <- if (schemes$check[i] == "checksum") "high" else "low"
      found <- c(found, list(finding(
        schemes$scheme[i], "value", "idcheck", sum(weight[valid]), share, values[valid], confidence
      )))
    }
  }
  found
}

detect_person_names <- function(values, weight) {
  named <- stringr::str_detect(values, patterns$person)
  share <- sum(weight[named]) / sum(weight)
  if (share < 0.8 || length(values) / sum(weight) < 0.2) {
    return(list())
  }
  list(finding("person_name", "value", "person_name", sum(weight[named]), share, values, "low"))
}

detect_values <- function(field, values, weight, regions = character()) {
  if (length(values) == 0L || field$type == "logical") {
    return(list())
  }
  total <- sum(weight)
  described <- tokens(paste(stats::na.omit(c(field$name, field$label)), collapse = " "))
  phone_named <- any(described %in% name_terms()$phone)
  if (field$type == "date") {
    dates <- lubridate::parse_date_time(values, orders = c("ymd", "ymd HMS"), quiet = TRUE)
    return(detect_birth_dates(values, weight, dates))
  }
  if (field$type == "numeric") {
    return(c(
      detect_patterns(values, weight, FALSE, "phone", phone_named, regions),
      detect_identity_numbers(values, weight)
    ))
  }
  distinct <- length(values) / total
  words <- stringr::str_count(values, "\\S+")
  wordy <- stats::weighted.mean(words, weight) >= 5
  free <- field$kind == "text" || (wordy && distinct >= 0.3)
  # Sentences are searched match by match even when most rows repeat a stock answer.
  found <- detect_patterns(values, weight, free || wordy,
    corroborated = phone_named, regions = regions
  )
  if (field$kind == "text") {
    return(found)
  }
  if (free) {
    note <- finding("free_text", "structure", "free_text", total, 1, values, "low")
    return(c(found, list(note)))
  }
  dates <- parse_dates(values)
  found <- c(
    found, detect_birth_dates(values, weight, dates), detect_person_names(values, weight),
    detect_identity_numbers(values, weight)
  )
  bookkeeping <- !is.na(field$name) && tolower(field$name) %in% platform_bookkeeping()
  # Keys and codes are distinct on every row too; text made of several words is not a key.
  plain <- is.na(suppressWarnings(as.numeric(values))) & is.na(dates) & words >= 2
  textual <- sum(weight[plain]) / total > 0.5
  if (length(found) == 0L && textual && !bookkeeping && total >= 20 && distinct >= 0.9) {
    found <- list(
      finding("unique_text", "structure", "unique_text", total, distinct, values, "low")
    )
  }
  found
}
