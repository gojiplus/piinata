detect_name <- function(field, values, extra = list()) {
  name <- field$name
  if (!is.na(name) && tolower(name) %in% names(platform_terms())) {
    type <- unname(platform_terms()[tolower(name)])
    return(list(finding(type, "name", "platform_field", NA, NA_real_, name, "high")))
  }
  terms <- name_terms()
  for (type in names(extra)) {
    terms[[type]] <- union(terms[[type]], extra[[type]])
  }
  found <- list()
  sources <- c(name = name, label = field$label)
  for (part in names(sources)) {
    text <- sources[[part]]
    if (is.na(text)) next
    words <- tokens(text)
    for (type in names(terms)) {
      hit <- intersect(words, terms[[type]])
      if (type == "person_name" && any(words %in% not_a_person())) {
        hit <- character()
      }
      if (length(hit) > 0L && !type %in% vapply(found, `[[`, character(1), "type")) {
        detector <- paste0(part, "_term")
        found <- c(found, list(finding(type, "name", detector, NA, NA_real_, hit, "medium")))
      }
    }
  }
  found
}

# A suggestive name on a column of codes, flags or plain numbers is weak
# evidence: "phone_answered" holding yes and no is not a phone number.
name_contradicted <- function(field, observed) {
  if (field$kind != "tabular" || length(observed$values) == 0L) {
    return(FALSE)
  }
  coded <- length(observed$values) <= 10L && sum(observed$weight) >= 20
  short <- all(nchar(observed$values) <= 4L)
  coded || short || field$type == "logical"
}
