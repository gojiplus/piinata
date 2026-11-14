# Values as they arrive are not values as they were typed. Exports carry
# non-breaking spaces, zero-width characters and full-width or local digits,
# any of which stops a pattern from matching. Compatibility normalization
# (NFKC) folds the width and spacing variants, decimal digits of any script
# become ASCII digits, and invisible format characters are dropped.
normalize_values <- function(values) {
  values <- stringi::stri_trans_nfkc(values)
  values <- stringi::stri_replace_all_regex(values, "\\p{Cf}", "")
  values <- stringi::stri_trans_general(values, "[:Nd:] Any-Latin")
  stringr::str_squish(values)
}
