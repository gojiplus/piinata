# Scans each SOTAB column with piinata, as a column without a name.
#
#   Rscript data-raw/benchmark/external/score_piinata_sotab.R <columns.jsonl> <out.csv> [gliner]
args <- commandArgs(trailingOnly = TRUE)
pkgload::load_all(quiet = TRUE)
if (length(args) >= 3L && args[[3]] == "gliner") use_gliner()
config <- pii_config("none.yml")
columns <- lapply(readLines(args[[1]]), jsonlite::fromJSON)
rows <- lapply(columns, function(column) {
  findings <- if (length(column$values) == 0L) {
    empty_findings()
  } else {
    pii_scan(data.frame(col = column$values), config = config)
  }
  level <- function(at) {
    any(match(findings$confidence, confidence_levels) >= match(at, confidence_levels))
  }
  data.frame(
    table = column$table, column = column$column, label = column$label,
    personal = column$personal, strong = level("medium"), any = level("low"),
    types = paste(unique(findings$type), collapse = " ")
  )
})
utils::write.csv(do.call(rbind, rows), args[[2]], row.names = FALSE)
