gliner_state <- new.env(parent = emptyenv())

gliner_labels <- c("person", "location", "organization")

#' Use GLiNER for a second look at uncertain columns
#'
#' Loads [GLiNER](https://github.com/urchade/GLiNER), a named-entity model,
#' through 'reticulate', and makes [pii_scan()] use it on the text columns the
#' rules leave uncertain: those with no finding stronger than `low`, made of
#' short values. Up to `values` distinct values of such a column are tagged
#' one at a time, without the column's name, so the model's evidence does not
#' merely repeat the name's. A value counts as a person, a place or an
#' organization when an entity of that kind covers most of it, and the column
#' is judged by the share of rows so tagged:
#'
#' * when at least `share` of rows name people, a `person_name` finding is added,
#'   of `medium` confidence when at least 80% of rows do and `low` otherwise;
#' * when at least `share` of rows name places or organizations, the
#'   low-confidence `person_name` finding of the rules is withdrawn, since
#'   place and office names look like person names to them.
#'
#' The model never decides a single cell, and never gives `high` confidence.
#' Independent evaluations put models of this kind at 0.4 to 0.6 F1 on
#' unfamiliar text, and none covers short cells. On the benchmark in
#' `data-raw/benchmark/` the default model finds names behind question
#' numbers, in lower case and in US and Indian spellings, and tells village
#' names from person names; it does not see names written in Devanagari.
#'
#' The first call installs the Python packages into an environment managed by
#' 'reticulate' and downloads the model, about 1 GB, from Hugging Face. That
#' is the only time piinata goes online. On a laptop CPU the model tags tens
#' of values a second.
#'
#' @param model A GLiNER model on Hugging Face. The default is the
#'   multilingual, Apache-2.0 licensed `urchade/gliner_multi_pii-v1`.
#' @param threshold The weakest entity score that counts.
#' @param values The most distinct values tagged per column.
#' @param share The share of rows that decides a column.
#' @return The settings, invisibly. `use_gliner(FALSE)` turns the backend off.
#' @export
#' @examples
#' \dontrun{
#' use_gliner()
#' pii_scan(data.frame(q15 = c("Ramesh Kumar", "James Smith", "sunita devi")))
#' use_gliner(FALSE)
#' }
use_gliner <- function(model = "urchade/gliner_multi_pii-v1", threshold = 0.5, values = 50L,
                       share = 0.5) {
  if (isFALSE(model)) {
    rm(list = ls(gliner_state), envir = gliner_state)
    return(invisible(NULL))
  }
  rlang::check_installed("reticulate", "to use GLiNER")
  # The multilingual models' tokenizer needs sentencepiece and protobuf, which
  # gliner does not declare.
  reticulate::py_require(c("gliner", "sentencepiece", "protobuf"))
  gliner <- reticulate::import("gliner")
  gliner_state$model <- gliner$GLiNER$from_pretrained(model)
  gliner_state$settings <- list(
    model = model, threshold = threshold, values = as.integer(values), share = share
  )
  invisible(gliner_state$settings)
}

gliner_active <- function() !is.null(gliner_state$model)

# The label of the entity covering most of each value, or NA when none covers
# at least half of it.
covering_label <- function(values, predictions) {
  vapply(seq_along(values), function(i) {
    entities <- predictions[[i]]
    if (length(entities) == 0L) {
      return(NA_character_)
    }
    covered <- vapply(entities, function(e) (e$end - e$start) / nchar(values[i]), numeric(1))
    best <- which.max(covered)
    if (covered[best] >= 0.5) entities[[best]]$label else NA_character_
  }, character(1))
}

# Revises a column's findings from the labels of its sampled values.
vote_entities <- function(found, labels, weight, share) {
  shares <- vapply(gliner_labels, function(label) {
    sum(weight[labels %in% label]) / sum(weight)
  }, numeric(1))
  named <- vapply(found, function(f) f$type == "person_name" && f$evidence == "value", logical(1))
  if (shares[["person"]] >= share) {
    n <- round(shares[["person"]] * sum(weight))
    # Like phone numbers, a column is judged by how much of it the model fills:
    # real name columns score above 0.9, crop varieties such as "Raj Vijay"
    # about 0.6.
    confidence <- if (shares[["person"]] >= 0.8) "medium" else "low"
    vote <- finding(
      "person_name", "value", "gliner", n, shares[["person"]],
      names(labels)[labels %in% "person"], confidence
    )
    return(c(found[!named], list(vote)))
  }
  if (shares[["location"]] + shares[["organization"]] >= share) {
    return(found[!named])
  }
  found
}

uncertain <- function(field, found, values) {
  strong <- vapply(found, function(f) f$confidence %in% c("medium", "high"), logical(1))
  free <- vapply(found, function(f) f$type == "free_text", logical(1))
  field$kind == "tabular" && field$type == "character" && length(values) >= 5L &&
    !any(strong) && !any(free) && stats::median(nchar(values)) <= 60
}

gliner_review <- function(field, found, values, weight) {
  if (!gliner_active() || !uncertain(field, found, values)) {
    return(found)
  }
  settings <- gliner_state$settings
  keep <- unique(round(seq(1, length(values), length.out = min(settings$values, length(values)))))
  values <- values[keep]
  weight <- weight[keep]
  predictions <- gliner_state$model$inference(
    as.list(values), as.list(gliner_labels), threshold = settings$threshold
  )
  labels <- stats::setNames(covering_label(values, predictions), values)
  vote_entities(found, labels, weight, settings$share)
}
