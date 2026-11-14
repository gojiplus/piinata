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

detect_name <- function(field, values) {
  name <- field$name
  if (!is.na(name) && tolower(name) %in% names(platform_terms())) {
    type <- unname(platform_terms()[tolower(name)])
    return(list(finding(type, "name", "platform_field", NA, NA_real_, name, "high")))
  }
  terms <- name_terms()
  found <- list()
  sources <- c(name = name, label = field$label)
  for (part in names(sources)) {
    text <- sources[[part]]
    if (is.na(text)) next
    words <- tokens(text)
    for (type in names(terms)) {
      hit <- intersect(words, terms[[type]])
      if (length(hit) > 0L && !type %in% vapply(found, `[[`, character(1), "type")) {
        detector <- paste0(part, "_term")
        found <- c(found, list(finding(type, "name", detector, NA, NA_real_, hit, "medium")))
      }
    }
  }
  found
}

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

matches <- function(values, type) {
  hits <- switch(type,
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
  hits[!is.na(hits)]
}

detect_patterns <- function(values, free) {
  found <- list()
  threshold <- if (free) 1 else max(5, 0.05 * length(values))
  for (type in c("email", "phone", "ip_address")) {
    hits <- matches(values, type)
    if (length(hits) >= threshold) {
      confidence <- if (type == "phone") "low" else "high"
      share <- length(hits) / length(values)
      found <- c(found, list(finding(type, "value", type, length(hits), share, hits, confidence)))
    }
  }
  found
}

parse_dates <- function(values) {
  orders <- c("dmy", "mdy", "ymd", "ymd HMS", "ymd HM", "dmy HMS", "dmy HM", "mdy HMS", "mdy HM")
  suppressWarnings(lubridate::parse_date_time(values, orders = orders, quiet = TRUE))
}

detect_birth_dates <- function(values) {
  dates <- parse_dates(values)
  parsed <- !is.na(dates)
  if (mean(parsed) < 0.8) {
    return(list())
  }
  years <- lubridate::year(dates[parsed])
  latest <- lubridate::year(Sys.Date()) - 10
  if (stats::median(years) < 1900 || stats::median(years) > latest) {
    return(list())
  }
  list(finding(
    "date_of_birth", "value", "birth_date", sum(parsed), mean(parsed), values[parsed], "medium"
  ))
}

detect_coordinates <- function(values) {
  numbers <- suppressWarnings(as.numeric(values))
  if (anyNA(numbers) || any(abs(numbers) > 180)) {
    return(list())
  }
  precise <- stringr::str_detect(values, "\\.\\d{4,}")
  if (mean(precise) < 0.8) {
    return(list())
  }
  list(finding("coordinates", "value", "coordinates", sum(precise), mean(precise), values, "low"))
}

detect_person_names <- function(values) {
  named <- stringr::str_detect(values, patterns$person)
  if (mean(named) < 0.8 || length(unique(values)) / length(values) < 0.2) {
    return(list())
  }
  list(finding("person_name", "value", "person_name", sum(named), mean(named), values, "low"))
}

detect_values <- function(field, values) {
  if (length(values) == 0L) {
    return(list())
  }
  distinct <- length(unique(values)) / length(values)
  wordy <- mean(nchar(values)) >= 25 || mean(stringr::str_count(values, "\\S+")) >= 4
  free <- field$kind == "text" || (wordy && distinct >= 0.3)
  found <- detect_patterns(values, free)
  if (field$kind == "text") {
    return(found)
  }
  if (free) {
    note <- finding("free_text", "structure", "free_text", length(values), 1, values, "low")
    return(c(found, list(note)))
  }
  found <- c(
    found, detect_birth_dates(values), detect_coordinates(values),
    detect_person_names(values)
  )
  bookkeeping <- !is.na(field$name) && tolower(field$name) %in% platform_bookkeeping()
  textual <- mean(is.na(suppressWarnings(as.numeric(values)))) > 0.5 &&
    mean(is.na(parse_dates(values))) > 0.5
  if (length(found) == 0L && textual && !bookkeeping && length(values) >= 20L && distinct >= 0.9) {
    found <- list(finding(
      "unique_text", "structure", "unique_text", length(values), distinct, values, "low"
    ))
  }
  found
}
