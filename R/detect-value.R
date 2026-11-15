patterns <- list(
  email = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
  phone = "(?<![\\d.])\\+?\\d[\\d\\s().-]{8,16}\\d(?!\\d)",
  ipv4 = "(?<![\\d.])\\d{1,3}(?:\\.\\d{1,3}){3}(?![\\d.])",
  person = "^\\p{Lu}[\\p{L}'.-]+(?:\\s+\\p{Lu}[\\p{L}'.-]+){1,3}$"
)

is_phone_like <- function(candidate) {
  digits <- stringr::str_count(candidate, "\\d")
  dated <- stringr::str_detect(candidate, "^\\d{4}[-./]\\d{1,2}[-./]\\d{1,2}")
  # Decimals have one point and IP addresses four groups of up to three
  # digits; 970.369.7799 is how many people write a phone number.
  dotted <- stringr::str_detect(candidate, "^\\d+\\.\\d+$|^\\d{1,3}(?:\\.\\d{1,3}){3}$")
  # "1699-1707 (56" is a span of years and a page count.
  year <- "(?:1[0-9]|20)\\d{2}"
  years <- stringr::str_detect(candidate, paste0("^", year, "\\s?[-/]\\s?", year, "(?!\\d)"))
  digits >= 10L & digits <= 13L & !dated & !dotted & !years
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
  # Any column of past dates looks like this, publication and visit dates
  # alike, so values alone are weak evidence; a name or label that says
  # birth lifts it (lift_by_context()).
  list(finding(
    "date_of_birth", "value", "birth_date", sum(weight[parsed]), share, values[parsed], "low"
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

# An address needs two of three cues, so a ward number, a street name or a
# postcode alone is not one: a postcode, a house marker (a number leading a
# street, or a word such as "house", "apt" or "plot" before a number) and an
# area word (street, avenue, ward, tehsil, district ...). It follows Amazon
# Macie's rule of a place plus a postcode. Address parsers (libpostal,
# deepparse, usaddress) label any string they are given, so they cannot tell
# whether a string is an address.
#
# Postcodes come from Google's address metadata (data-raw/postcodes.R) for the
# project's `regions`; without regions, every country's pattern of five or
# more characters is used, leaving out four-digit codes that look like years
# and the few that would take a phone number or a month for a postcode.
postcode_cache <- new.env(parent = emptyenv())

postcode_cue <- function(regions) {
  key <- paste(c("regions", sort(regions)), collapse = " ")
  if (!exists(key, envir = postcode_cache, inherits = FALSE)) {
    assign(key, build_postcode_cue(regions), envir = postcode_cache)
  }
  get(key, envir = postcode_cache, inherits = FALSE)
}

build_postcode_cue <- function(regions) {
  rows <- if (length(regions) > 0L) {
    postcodes[postcodes$region %in% regions, ]
  } else {
    shortest <- vapply(strsplit(postcodes$example, ",", fixed = TRUE), function(e) {
      min(nchar(gsub("\\s", "", e)))
    }, numeric(1))
    # Patterns that would also take a phone number or a month and year
    # ("MAR 2020" is a Maltese postcode) are left to projects that name the
    # region.
    lookalikes <- c("9876543210", "MAR 2020", "JAN 2021", "DEC 1999")
    confusable <- vapply(postcodes$pattern, function(pattern) {
      any(stringi::stri_detect_regex(lookalikes, paste0("^(?:", pattern, ")$")))
    }, logical(1))
    postcodes[!is.na(shortest) & shortest >= 5 & !confusable, ]
  }
  if (nrow(rows) == 0L) {
    return(NULL)
  }
  alternatives <- paste(unique(rows$pattern), collapse = "|")
  # Some countries' patterns allow letters only, which would take "ALL CAPS"
  # for a postcode; a postcode found here must hold a digit.
  paste0("(?<![\\p{L}\\p{N}])(?=[\\p{L}\\p{N} -]{0,9}\\d)(?:", alternatives, ")(?![\\p{L}\\p{N}])")
}

house_cue <- paste0(
  "(?i)(?:^\\s*\\d+[a-z]?(?:[/-]\\w+)?\\s*(?:,|\\s+\\p{L})|(?<![\\p{L}\\p{M}])",
  "(?:house|h\\.?\\s?no|plot|flat|door|apt|apartment|suite|ste|unit|khasra|makan|",
  "\u092e\u0915\u093e\u0928)(?![\\p{L}\\p{M}])\\.?\\s*(?:no\\.?\\s*|#\\s*)?\\d+|",
  "p\\.?\\s?o\\.?\\s+box\\s+\\d+)"
)

area_cue <- paste0(
  "(?i)(?<![\\p{L}\\p{M}\\p{N}])(?:street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|",
  "court|ct|place|pl|way|highway|hwy|parkway|pkwy|terrace|county|ward|gali|marg|mohalla|",
  "colony|sector|village|vill|post|tehsil|taluka|taluk|district|dist|zila|block|near|chowk|",
  "basti|tola|\u0917\u094d\u0930\u093e\u092e|\u092a\u094b\u0938\u094d\u091f|",
  "\u091c\u093f\u0932\u093e|\u0924\u0939\u0938\u0940\u0932|\u0935\u093e\u0930\u094d\u0921)",
  "(?![\\p{L}\\p{M}])"
)

# The cues must sit near each other, as Presidio looks for context words
# just before a match: in a long review, "post" and a model number far apart
# are not an address.
address_window <- 40L

is_address <- function(values, regions = character()) {
  cues <- c(postcode_cue(regions), house_cue, area_cue)
  found <- rep(FALSE, length(values))
  some <- Reduce(`+`, lapply(cues, function(cue) stringi::stri_detect_regex(values, cue))) >= 2L
  some[is.na(some)] <- FALSE
  candidates <- which(some)
  located <- lapply(cues, function(cue) {
    lapply(stringi::stri_locate_all_regex(values[candidates], cue), function(m) m[, 1])
  })
  found[candidates] <- vapply(seq_along(candidates), function(j) {
    places <- lapply(located, `[[`, j)
    starts <- unlist(places)
    kinds <- rep(seq_along(places), lengths(places))
    keep <- !is.na(starts)
    near <- abs(outer(starts[keep], starts[keep], `-`)) <= address_window &
      outer(kinds[keep], kinds[keep], `!=`)
    any(near)
  }, logical(1))
  found
}

detect_addresses <- function(values, weight, free, regions) {
  found <- is_address(values, regions)
  n <- sum(weight[found])
  share <- n / sum(weight)
  if (n == 0L || (!free && (n < 5L || share < 0.5))) {
    return(list())
  }
  list(finding("address", "value", "address", n, share, values[found], "medium"))
}

# Identifiers 'checkstring' validates, which idcheck leaves to it: bank
# account numbers (IBAN, with its MOD 97-10 check), and the device and
# record identifiers Presidio also recognizes. checkstring judges one value
# at a time, so only values shaped like candidates are passed to it.
checkstring_types <- list(
  iban = list(
    shape = "^[A-Za-z]{2}[0-9]{2}[A-Za-z0-9 ]{10,}$", check = "is_iban", confidence = "high",
    clean = function(v) toupper(gsub(" ", "", v, fixed = TRUE))
  ),
  device_id = list(
    shape = "^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$", check = "is_mac", confidence = "medium",
    clean = identity
  ),
  uuid = list(
    shape = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
    check = "is_uuid", confidence = "low", clean = identity
  )
)

detect_checkstring <- function(values, weight) {
  if (!rlang::is_installed("checkstring")) {
    return(list())
  }
  found <- list()
  for (type in names(checkstring_types)) {
    rule <- checkstring_types[[type]]
    candidate <- grepl(rule$shape, values)
    if (sum(weight[candidate]) / sum(weight) < 0.8) next
    check <- getExportedValue("checkstring", rule$check)
    valid <- candidate
    valid[candidate] <- vapply(rule$clean(values[candidate]), check, logical(1))
    share <- sum(weight[valid]) / sum(weight)
    if (share >= 0.8) {
      found <- c(found, list(finding(
        type, "value", "checkstring", sum(weight[valid]), share, values[valid], rule$confidence
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

# Sentences are searched match by match: running text, and columns whose
# answers average five words or more, even when most rows repeat a stock
# answer.
match_by_match <- function(field, values, weight) {
  field$kind == "text" ||
    (length(values) > 0L && stats::weighted.mean(stringr::str_count(values, "\\S+"), weight) >= 5)
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
  found <- c(
    detect_patterns(values, weight, free || wordy, corroborated = phone_named, regions = regions),
    detect_addresses(values, weight, free || wordy, regions)
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
    detect_identity_numbers(values, weight), detect_checkstring(values, weight)
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
