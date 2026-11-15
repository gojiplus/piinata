# Scans whole SOTAB tables, so columns can be paired, and counts coordinate
# pairs by label: found among CoordinateAT columns, and on everything else.
#
#   Rscript data-raw/benchmark/external/score_coordinates_sotab.R <unzipped dir> {validation,test}
args <- commandArgs(trailingOnly = TRUE)
pkgload::load_all(quiet = TRUE)
split <- args[[2]]
folder <- file.path(args[[1]], split, if (split == "test") "Test" else "Validation")
labels <- utils::read.csv(
  file.path(args[[1]], split, paste0("sotab_v2_cta_", split, "_set.csv"))
)
rows <- lapply(unique(labels$table_name), function(table) {
  lines <- readLines(gzfile(file.path(folder, table)))
  records <- lapply(lines, jsonlite::fromJSON)
  columns <- unique(unlist(lapply(records, names)))
  data <- as.data.frame(lapply(stats::setNames(columns, paste0("c", columns)), function(k) {
    vapply(records, function(r) {
      if (is.null(r[[k]])) NA_character_ else paste(r[[k]], collapse = " ")
    }, "")
  }), stringsAsFactors = FALSE)
  found <- coordinate_findings(as_pii_fields(data, source = table), FALSE)
  paired <- as.integer(sub("^c", "", found$name))
  own <- labels[labels$table_name == table, ]
  data.frame(
    table = table, pairs = length(paired),
    coordinate_columns = sum(own$label == "CoordinateAT"),
    coordinate_found = sum(own$column_index[own$label == "CoordinateAT"] %in% paired),
    other_labeled_found = sum(own$column_index[own$label != "CoordinateAT"] %in% paired),
    unlabeled_found = sum(!paired %in% own$column_index)
  )
})
result <- do.call(rbind, rows)
cat(sprintf(
  paste(
    "%s: %d tables; CoordinateAT found %d of %d;",
    "paired columns with other labels %d (of %d labeled); unlabeled columns paired %d\n"
  ),
  split, nrow(result), sum(result$coordinate_found), sum(result$coordinate_columns),
  sum(result$other_labeled_found), nrow(labels) - sum(labels$label == "CoordinateAT"),
  sum(result$unlabeled_found)
))
