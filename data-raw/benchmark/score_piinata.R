# Scores piinata against the benchmark's known answers.
#
#   Rscript data-raw/benchmark/score_piinata.R data-raw/benchmark/out
#
# from the root of the repository, after make_data.py.
# A column counts as flagged at a confidence level when any finding on it is
# at least that strong. Reported at "medium", the level pii_check() gates on,
# and at "low", everything the scan reports.
args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args) > 0L) args[[1]] else "data-raw/benchmark/out"
pkgload::load_all(quiet = TRUE)

score <- function(findings, truth, label) {
  levels <- c("low", "medium", "high")
  rows <- lapply(c("medium", "low"), function(level) {
    strong <- findings[match(findings$confidence, levels) >= match(level, levels), ]
    flagged <- unique(strong$name)
    personal <- names(truth)[vapply(truth, isTRUE, logical(1))]
    other <- setdiff(names(truth), personal)
    data.frame(
      file = label, level = level,
      caught = sprintf("%d/%d", length(intersect(flagged, personal)), length(personal)),
      false_alarms = sprintf("%d/%d", length(intersect(flagged, other)), length(other)),
      missed = paste(setdiff(personal, flagged), collapse = " "),
      alarms = paste(intersect(flagged, other), collapse = " ")
    )
  })
  do.call(rbind, rows)
}

truth <- lapply(jsonlite::read_json(file.path(out, "truth.json")), `[[`, "pii")
qualtrics <- jsonlite::read_json(file.path(out, "truth_qualtrics.json"))
config <- pii_config(file.path(out, "none.yml"))
files <- c(
  file.path(out, "std", c("survey.csv", "survey.dta")),
  file.path(out, "other", c("survey.xlsx", "survey.parquet", "survey.tsv", "survey.jsonl"))
)
results <- lapply(files, function(file) {
  score(pii_scan(file, config = config), truth, basename(file))
})
results <- c(results, list(score(
  pii_scan(file.path(out, "qualtrics", "export.csv"), config = config), qualtrics, "qualtrics"
)))
print(do.call(rbind, results), right = FALSE, row.names = FALSE)
