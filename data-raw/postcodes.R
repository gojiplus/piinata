# Postcode patterns for every country, from Google's address metadata (the
# data behind libaddressinput; its code is Apache-2.0 but the data are
# CC BY 4.0, credited in inst/COPYRIGHTS), stored in R/sysdata.rda so the
# scanner never goes online.
#
#   Rscript data-raw/postcodes.R
base <- "https://chromium-i18n.appspot.com/ssl-address/data"
countries <- strsplit(jsonlite::fromJSON(base)$countries, "~", fixed = TRUE)[[1]]
rows <- lapply(countries, function(code) {
  Sys.sleep(0.1)
  meta <- jsonlite::fromJSON(paste0(base, "/", code))
  if (is.null(meta$zip)) {
    return(NULL)
  }
  data.frame(
    region = code, pattern = meta$zip,
    example = if (is.null(meta$zipex)) NA_character_ else meta$zipex
  )
})
postcodes <- do.call(rbind, rows)
stopifnot(nrow(postcodes) > 150, all(c("US", "IN", "GB") %in% postcodes$region))
attr(postcodes, "source") <- paste(base, format(Sys.Date()))
usethis::use_data(postcodes, internal = TRUE, overwrite = TRUE)
