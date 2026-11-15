# Values as they arrive are not values as they were typed. Exports carry
# non-breaking spaces, zero-width characters and full-width or local digits,
# any of which stops a pattern from matching. Compatibility normalization
# (NFKC) folds the width and spacing variants, decimal digits of any script
# become ASCII digits, and invisible format characters are dropped.
# Web pages hide addresses from harvesters as HTML character references
# ("info&#64;example.org"). A numeric reference is defined by the HTML
# standard as the code point it names, so it is decoded here, with the five
# XML named entities; the one CRAN decoder (textutils) is GPL-3, a heavy
# dependency for this.
decode_references <- function(values) {
  coded <- !is.na(values) & grepl("&#?[0-9A-Za-z]+;", values)
  if (!any(coded)) {
    return(values)
  }
  reference <- "&#([xX]?)([0-9A-Fa-f]{1,6});"
  values[coded] <- stringr::str_replace_all(values[coded], reference, function(ref) {
    hex <- grepl("^&#x", ref, ignore.case = TRUE)
    digits <- sub("^&#x?", "", sub(";$", "", ref), ignore.case = TRUE)
    point <- ifelse(hex, strtoi(digits, 16L), strtoi(digits, 10L))
    valid <- !is.na(point) & point > 0 & point <= 0x10FFFF & !(point >= 0xD800 & point <= 0xDFFF)
    ref[valid] <- vapply(point[valid], intToUtf8, character(1))
    ref
  })
  named <- c("&amp;" = "&", "&lt;" = "<", "&gt;" = ">", "&quot;" = "\"", "&apos;" = "'")
  values[coded] <- stringi::stri_replace_all_fixed(
    values[coded], names(named), named, vectorize_all = FALSE
  )
  values
}

normalize_values <- function(values) {
  values <- decode_references(values)
  values <- stringi::stri_trans_nfkc(values)
  values <- stringi::stri_replace_all_regex(values, "\\p{Cf}", "")
  values <- stringi::stri_trans_general(values, "[:Nd:] Any-Latin")
  stringr::str_squish(values)
}
