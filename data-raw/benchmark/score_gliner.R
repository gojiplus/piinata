# Scores piinata with and without the GLiNER backend, and times it.
#
#   Rscript data-raw/benchmark/score_gliner.R data-raw/benchmark/out
args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args) > 0L) args[[1]] else "data-raw/benchmark/out"
pkgload::load_all(quiet = TRUE)
truth <- lapply(jsonlite::read_json(file.path(out, "truth.json")), `[[`, "pii")
config <- pii_config(file.path(out, "none.yml"))
file <- file.path(out, "std", "survey.csv")
flagged <- function(findings, level) {
  strong <- match(findings$confidence, confidence_levels) >= match(level, confidence_levels)
  unique(findings$name[strong])
}
report <- function(findings, label) {
  personal <- names(truth)[vapply(truth, isTRUE, logical(1))]
  for (level in c("medium", "low")) {
    hit <- flagged(findings, level)
    cat(sprintf(
      "%-8s %-6s caught %d/%d  false alarms %d/%d  missed: %s  alarms: %s\n", label, level,
      length(intersect(hit, personal)), length(personal),
      length(setdiff(intersect(hit, names(truth)), personal)), length(truth) - length(personal),
      paste(setdiff(personal, hit), collapse = " "),
      paste(setdiff(intersect(hit, names(truth)), personal), collapse = " ")
    ))
  }
}
report(pii_scan(file, config = config), "rules")
use_gliner()
time <- system.time(with_model <- pii_scan(file, config = config))[["elapsed"]]
report(with_model, "gliner")
cat(sprintf("scan with GLiNER: %.1f s\n", time))
print(as.data.frame(with_model[with_model$detector == "gliner", c("name", "share", "confidence")]))
