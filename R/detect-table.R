# Some evidence lies across columns. Latitude and longitude are usually kept
# in two columns side by side, each looking like any precise number alone.
# Each column is tested once for the shape of a coordinate, and candidates
# are paired only with the next `coordinate_window` columns, so the cost
# grows with the number of columns, not with the number of pairs.
coordinate_window <- 2L

# "latitude" when every value could be one, "longitude" when only a
# longitude fits, NA when the column is not a set of precise numbers in
# range. A single place repeated on every row is still a place, so values
# need not vary; and some sites round part of a column, so half need four
# decimals.
coordinate_shape <- function(values) {
  values <- trimws(values[!is.na(values) & nzchar(values)])
  x <- suppressWarnings(as.numeric(values))
  parsed <- !is.na(x)
  if (length(values) < 5L || mean(parsed) < 0.8) {
    return(NA_character_)
  }
  decimals <- nchar(sub("^[^.]*\\.?", "", values[parsed]))
  precise <- mean(decimals >= 4L) >= 0.5
  if (!precise || any(abs(x[parsed]) > 180)) {
    return(NA_character_)
  }
  if (all(abs(x[parsed]) <= 90)) "latitude" else "longitude"
}

# The fields of one table share a source and, for workbooks and databases, a
# sheet; they come in column order.
table_of <- function(fields) {
  sheet <- ifelse(
    !is.na(fields$name) & fields$locator != fields$name,
    substr(fields$locator, 1L, nchar(fields$locator) - nchar(fields$name) - 1L),
    ""
  )
  paste(fields$source, sheet, sep = "\r")
}

detect_coordinate_pairs <- function(fields) {
  tabular <- which(fields$kind == "tabular" & fields$type %in% c("numeric", "character"))
  if (length(tabular) < 2L) {
    return(integer())
  }
  shapes <- vapply(fields$values[tabular], coordinate_shape, character(1))
  named <- vapply(seq_along(tabular), function(j) {
    described <- c(fields$name[tabular[j]], fields$label[tabular[j]])
    text <- paste(stats::na.omit(described), collapse = " ")
    any(tokens(text) %in% not_coordinates())
  }, logical(1))
  shapes[named] <- NA_character_
  tables <- table_of(fields[tabular, ])
  paired <- logical(length(tabular))
  for (i in which(!is.na(shapes))) {
    later <- seq(i + 1L, length.out = coordinate_window)
    later <- later[later <= length(tabular)]
    later <- later[tables[later] == tables[i] & !is.na(shapes[later])]
    # A pair needs a latitude: two columns that could both only be
    # longitudes are not one.
    partner <- later[shapes[i] == "latitude" | shapes[later] == "latitude"]
    if (length(partner) > 0L) {
      paired[c(i, partner[1])] <- TRUE
    }
  }
  tabular[paired]
}

coordinate_findings <- function(fields, show_values) {
  rows <- lapply(detect_coordinate_pairs(fields), function(i) {
    values <- fields$values[[i]]
    values <- values[!is.na(values) & nzchar(values)]
    examples <- utils::head(unique(values), 3L)
    tibble::tibble(
      source = fields$source[i], locator = fields$locator[i], name = fields$name[i],
      label = fields$label[i], type = "coordinates", evidence = "value",
      detector = "coordinate_pair", n = length(values), share = 1,
      examples = list(if (show_values) examples else mask(examples)), confidence = "medium"
    )
  })
  do.call(rbind, c(list(empty_findings()), rows))
}
