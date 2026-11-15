# Each method turns a vector of values into its redacted form. A pseudonym
# keeps the shape of a value (letters stay letters, digits stay digits) and
# maps equal values to equal pseudonyms, so joins, counts and formats keep
# working on the redacted data.
#
# Each character is drawn from SHA-256 of the key, the value and a block
# number, not from R's random-number generator, so the same value and key
# give the same pseudonym in every session, on every platform and under any
# RNG setting. Letters of every script become Latin letters, digits of every
# script ASCII digits, and combining marks go with the letter they belong to.
# Different values of the same shape can still collide: for n values of a
# shape with S possible spellings, about n^2 / 2S pairs do.
hash_bytes <- function(key, value, n) {
  blocks <- seq_len(ceiling(n / 32))
  bytes <- unlist(lapply(blocks, function(block) {
    hex <- tools::sha256sum(bytes = charToRaw(enc2utf8(paste(key, value, block, sep = "\x1f"))))
    strtoi(substring(hex, seq(1L, 63L, 2L), seq(2L, 64L, 2L)), 16L)
  }))
  bytes[seq_len(n)]
}

pseudonym <- function(values, key) {
  distinct <- unique(values[!is.na(values)])
  replacement <- vapply(distinct, function(value) {
    chars <- strsplit(value, "")[[1]]
    if (length(chars) == 0L) {
      return(value)
    }
    draw <- hash_bytes(key, value, length(chars))
    upper <- stringi::stri_detect_regex(chars, "^\\p{Lu}$")
    letter <- stringi::stri_detect_regex(chars, "^\\p{L}$") & !upper
    digit <- stringi::stri_detect_regex(chars, "^\\p{Nd}$")
    mark <- stringi::stri_detect_regex(chars, "^\\p{M}$")
    chars[upper] <- LETTERS[draw[upper] %% 26L + 1L]
    chars[letter] <- letters[draw[letter] %% 26L + 1L]
    chars[digit] <- as.character(draw[digit] %% 10L)
    chars[mark] <- ""
    paste(chars, collapse = "")
  }, character(1))
  unname(replacement[match(values, distinct)])
}

redactors <- function(key) {
  list(
    mask = function(values, type) ifelse(is.na(values), NA_character_, mask(values)),
    placeholder = function(values, type) {
      ifelse(is.na(values), NA_character_, paste0("<", toupper(type), ">"))
    },
    pseudonym = function(values, type) pseudonym(values, key)
  )
}

# Types whose matches can be found and replaced inside longer text. Emails go
# first so the digits of an address are not taken for a phone number, and
# card numbers before phones so a card is not cut into a phone and a rest.
span_types <- c("email", "ip_address", "financial_account", "phone")
span_patterns <- c(
  email = patterns$email, ip_address = patterns$ipv4, financial_account = patterns$card,
  phone = patterns$phone
)
structure_types <- c("free_text", "unique_text")

# Within free text only the matched spans are replaced, every one of them; the
# rest of the answer is kept. The scan matches normalized text (entities
# decoded, widths folded, invisible characters dropped), so a cell is
# normalized the same way before its spans are replaced; a cell with nothing
# to replace is left exactly as it was.
replace_spans <- function(values, types, redact) {
  for (type in intersect(span_types, types)) {
    values <- stringr::str_replace_all(values, span_patterns[[type]], function(hit) {
      real <- !is.na(matched(hit, type))
      hit[real] <- redact(hit[real], type)
      hit
    })
  }
  values
}

redact_spans <- function(values, types, redact) {
  clean <- normalize_values(values)
  replaced <- replace_spans(clean, types, redact)
  touched <- !is.na(replaced) & replaced != clean
  values[touched] <- replaced[touched]
  values
}

#' Redact the fields a scan flagged
#'
#' Returns a copy of `data` with flagged columns removed or their values
#' replaced. Four methods, in increasing order of what survives:
#'
#' * `"drop"` removes the column.
#' * `"placeholder"`, the default, replaces each value with its type, such as
#'   `<EMAIL>`.
#' * `"mask"` keeps the first two characters and hides the rest.
#' * `"pseudonym"` replaces each value with a made-up one of the same shape,
#'   the same every time for the same value and `key`, so joins across files,
#'   counts of distinct people and format checks still work.
#'
#' In free text, and in any column where only some values match, only the
#' matched email addresses, phone numbers and IP addresses are replaced, every
#' one of them; with `"drop"` the whole column goes. Anything else flagged in
#' such a column, such as a name inside an answer, is left in place.
#'
#' Fields allowed in the project's configuration (see [pii_config()]) are left
#' alone, as [pii_check()] leaves them alone.
#'
#' Pseudonyms are for keeping analyses running, not for security. They are not
#' encryption, and a column of pseudonyms can still identify people through
#' what surrounds it. Anyone who knows the `key` can test whether a guessed
#' value, such as a phone number, gives a pseudonym in the file, so the key
#' has no default and must not be shared with the data.
#'
#' @param data A data frame.
#' @param findings The result of [pii_scan()] on `data`. Scanned if missing.
#' @param method One method for every flagged column, or a named vector giving
#'   the method per finding type, with an optional `default`.
#' @param key A secret string that determines the pseudonyms; needed only for
#'   `"pseudonym"`. Keep it out of the shared files; use the same key to redact
#'   files that must still join.
#' @param min_confidence The weakest findings to act on; the configuration's
#'   `min_confidence`, or `"medium"`, unless given.
#' @return `data` with the flagged columns redacted, and the actions taken as
#'   its `"redactions"` attribute: the column `name`, the `type` acted on, the
#'   `method`, and `left`, the flagged types left in a column where only
#'   matches were replaced.
#' @export
#' @examples
#' survey <- data.frame(
#'   id = 1:20,
#'   email = paste0("person", 1:20, "@example.org"),
#'   village = rep(c("Palpur", "Netrad"), 10)
#' )
#' clean <- pii_redact(survey, method = c(email = "pseudonym", default = "drop"), key = "s3")
#' head(clean)
#' attr(clean, "redactions")
pii_redact <- function(data, findings = pii_scan(data), method = "placeholder",
                       key = NULL, min_confidence = NULL) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame, not {.obj_type_friendly {data}}.")
  }
  check_method(method, key)
  min_confidence <- gate(min_confidence, attr(findings, "config", exact = TRUE))
  redact_frame(data, acted_on(findings, min_confidence), method, key)
}

# Redacts the columns of `data` named in `findings`, which have already been
# graded and checked against the allowed fields.
redact_frame <- function(data, findings, method, key) {
  findings <- findings[findings$name %in% names(data), ]
  redact <- redactors(key)
  default <- if (is.null(names(method))) method[[1]] else unname(method["default"])
  actions <- list()
  for (column in unique(findings$name)) {
    types <- unique(findings$type[findings$name == column])
    chosen <- unname(stats::na.omit(c(method[types], default))[1])
    if (is.na(chosen)) {
      next
    }
    type <- setdiff(types, structure_types)[1]
    share <- findings$share[findings$name == column & findings$evidence == "value"]
    partial <- "free_text" %in% types || any(share < 0.8)
    type <- if (is.na(type)) "text" else type
    left <- if (partial && chosen != "drop") setdiff(types, c(span_types, structure_types))
    if (chosen == "drop") {
      data[[column]] <- NULL
    } else {
      label <- attr(data[[column]], "label", exact = TRUE)
      values <- as_text(data[[column]])
      data[[column]] <- if (partial) {
        redact_spans(values, types, redact[[chosen]])
      } else {
        redact[[chosen]](values, type)
      }
      attr(data[[column]], "label") <- label
    }
    actions <- c(actions, list(tibble::tibble(
      name = column, type = type, method = chosen, left = paste(left, collapse = ", ")
    )))
  }
  empty <- tibble::tibble(
    name = character(), type = character(), method = character(), left = character()
  )
  attr(data, "redactions") <- do.call(rbind, c(list(empty), actions))
  data
}

redaction_methods <- c("drop", "placeholder", "mask", "pseudonym")

check_method <- function(method, key) {
  unknown <- setdiff(method, redaction_methods)
  if (length(unknown) > 0L) {
    cli::cli_abort(
      "{.arg method} must be one of {.or {.val {redaction_methods}}}, not {.val {unknown}}."
    )
  }
  if ("pseudonym" %in% method && (!rlang::is_string(key) || !nzchar(key))) {
    cli::cli_abort(c(
      "Pseudonyms need a secret {.arg key}.",
      "i" = "Anyone who knows the key can test guessed values against the pseudonyms."
    ))
  }
}

# The weakest confidence acted on: as given, or as the configuration says.
gate <- function(min_confidence, config) {
  if (is.null(min_confidence)) {
    min_confidence <- if (is.null(config$min_confidence)) "medium" else config$min_confidence
  }
  rlang::arg_match0(min_confidence, confidence_levels, "min_confidence")
}

# The findings redaction acts on: strong enough, and not reviewed and allowed
# in the configuration the scan used.
acted_on <- function(findings, min_confidence, config = attr(findings, "config", exact = TRUE)) {
  config <- if (is.null(config)) pii_config() else config
  graded <- match(findings$confidence, confidence_levels) >=
    match(min_confidence, confidence_levels)
  findings[graded & !allowed_by(findings, config$allow, config_root(config)), ]
}
