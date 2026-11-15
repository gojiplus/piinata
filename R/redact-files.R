# Formats that cannot be written back faithfully, and why. A file of one of
# these types is reported, never silently left as it was.
unwritable <- c(
  sas7bdat = "haven cannot write SAS data files; export the data to xpt and redact that",
  por = "haven cannot write SPSS portable files; save the data as sav and redact that",
  json = "writing JSON back is not supported yet",
  jsonl = "writing JSON back is not supported yet",
  ndjson = "writing JSON back is not supported yet",
  pdf = "documents cannot be written back; redact the source document",
  docx = "documents cannot be written back; redact the source document",
  rtf = "documents cannot be written back; redact the source document",
  html = "documents cannot be written back; redact the source document",
  htm = "documents cannot be written back; redact the source document",
  pptx = "documents cannot be written back; redact the source document",
  ods = "writing OpenDocument spreadsheets is not supported; save the data as xlsx or csv",
  ipynb = "notebooks cannot be written back; clear the outputs and redact the data",
  geojson = "geographic files cannot be written back yet",
  kml = "geographic files cannot be written back yet",
  shp = "geographic files cannot be written back yet",
  dbf = "geographic files cannot be written back yet",
  gpkg = "geographic files cannot be written back yet",
  sqlite = "databases cannot be written back; redact the tables and rebuild it",
  sqlite3 = "databases cannot be written back; redact the tables and rebuild it",
  db = "databases cannot be written back; redact the tables and rebuild it"
)

# "survey.csv.gz" -> "survey_redacted.csv.gz"; an Excel file is always
# written as xlsx.
redacted_path <- function(path, suffix) {
  packed <- tolower(fs::path_ext(path)) %in% compression_extensions
  inner <- if (packed) fs::path_ext_remove(path) else path
  extension <- fs::path_ext(inner)
  if (tolower(extension) == "xls") {
    extension <- "xlsx"
  }
  stem <- fs::path_ext_remove(inner)
  out <- paste0(stem, suffix, if (nzchar(extension)) paste0(".", extension))
  as.character(if (packed) paste0(out, ".", fs::path_ext(path)) else out)
}

is_redacted_copy <- function(path, suffix) {
  packed <- tolower(fs::path_ext(path)) %in% compression_extensions
  inner <- if (packed) fs::path_ext_remove(path) else path
  endsWith(fs::path_ext_remove(basename(inner)), suffix)
}

# The findings for one table of a file: a sheet of a workbook, an object in an
# RData file, or the file itself.
table_findings <- function(findings, part = NULL) {
  if (is.null(part)) {
    return(findings[which(findings$locator == findings$name), ])
  }
  findings[which(findings$locator == paste0(part, "!", findings$name)), ]
}

# Redacts one table and keeps what was done, so the file's report can say.
redact_table <- function(data, findings, options) {
  clean <- redact_frame(data, findings, options$method, options$key)
  actions <- attr(clean, "redactions")
  attr(clean, "redactions") <- NULL
  list(data = clean, actions = actions)
}

redact_delim <- function(path, destination, findings, options) {
  delim <- c(csv = ",", tsv = "\t", tab = "\t", psv = "|")[[file_type(path)]]
  # Read and written as text so that untouched columns come back as they were;
  # only empty cells count as missing.
  data <- readr::read_delim(
    path,
    delim = delim, col_types = text_columns, na = "", progress = FALSE,
    show_col_types = FALSE, name_repair = "unique_quiet"
  )
  # A Qualtrics export holds question text and import ids in its first two
  # rows; they are kept as they are.
  header <- if (is_qualtrics(path)) data[1:2, ] else data[0, ]
  body <- if (nrow(header) > 0L) data[-(1:2), ] else data
  result <- redact_table(body, table_findings(findings), options)
  out <- rbind(header[names(result$data)], result$data)
  readr::write_delim(out, destination, delim = delim, na = "")
  result$actions
}

redact_excel <- function(path, destination, findings, options) {
  need("writexl", "and write Excel files")
  sheets <- readxl::excel_sheets(path)
  results <- lapply(sheets, function(sheet) {
    data <- readxl::read_excel(path, sheet = sheet, .name_repair = "unique_quiet")
    redact_table(data, table_findings(findings, sheet), options)
  })
  writexl::write_xlsx(stats::setNames(lapply(results, `[[`, "data"), sheets), destination)
  do.call(rbind, lapply(results, `[[`, "actions"))
}

redact_haven <- function(read, write) {
  function(path, destination, findings, options) {
    result <- redact_table(read(path), table_findings(findings), options)
    write(result$data, destination)
    result$actions
  }
}

redact_parquet <- function(path, destination, findings, options) {
  result <- redact_table(nanoparquet::read_parquet(path), table_findings(findings), options)
  nanoparquet::write_parquet(result$data, destination)
  result$actions
}

redact_rds <- function(path, destination, findings, options) {
  data <- readRDS(path)
  if (is.character(data)) {
    result <- redact_lines(data, findings, options)
    saveRDS(result$lines, destination)
    return(result$actions)
  }
  result <- redact_table(data, table_findings(findings), options)
  saveRDS(result$data, destination)
  result$actions
}

redact_rdata <- function(path, destination, findings, options) {
  objects <- new.env()
  load(path, envir = objects)
  actions <- list()
  for (name in ls(objects)) {
    object <- get(name, envir = objects)
    if (is.data.frame(object)) {
      result <- redact_table(object, table_findings(findings, name), options)
      assign(name, result$data, envir = objects)
      actions <- c(actions, list(result$actions))
    }
  }
  save(list = ls(objects), envir = objects, file = destination)
  do.call(rbind, actions)
}

# Running text has no columns to drop, so "drop" replaces each match with a
# placeholder.
redact_lines <- function(lines, findings, options) {
  findings <- findings[is.na(findings$name), ]
  types <- unique(findings$type)
  redact <- redactors(options$key)
  method <- options$method
  default <- if (is.null(names(method))) method[[1]] else unname(method["default"])
  actions <- list()
  for (type in intersect(span_types, types)) {
    chosen <- unname(stats::na.omit(c(method[type], default))[1])
    if (is.na(chosen)) {
      next
    }
    applied <- if (chosen == "drop") "placeholder" else chosen
    lines <- redact_spans(lines, type, redact[[applied]])
    actions <- c(actions, list(tibble::tibble(
      name = NA_character_, type = type, method = applied, left = ""
    )))
  }
  left <- setdiff(types, c(span_types, structure_types))
  actions <- c(actions, list(tibble::tibble(
    name = NA_character_, type = character(), method = character(), left = character()
  )))
  actions <- do.call(rbind, actions)
  if (length(left) > 0L) {
    actions <- rbind(actions, tibble::tibble(
      name = NA_character_, type = NA_character_, method = NA_character_,
      left = paste(left, collapse = ", ")
    ))
  }
  list(lines = lines, actions = actions)
}

redact_text <- function(path, destination, findings, options) {
  lines <- readr::read_lines(path, na = character(), progress = FALSE)
  result <- redact_lines(lines, findings, options)
  readr::write_lines(result$lines, destination)
  result$actions
}

writers <- function() {
  c(
    stats::setNames(rep(list(redact_delim), length(delimited_extensions)), delimited_extensions),
    stats::setNames(rep(list(redact_text), length(text_extensions)), text_extensions),
    list(
      xlsx = redact_excel, xls = redact_excel,
      dta = redact_haven(haven::read_dta, haven::write_dta),
      sav = redact_haven(haven::read_sav, haven::write_sav),
      zsav = redact_haven(haven::read_sav, function(data, path) {
        haven::write_sav(data, path, compress = "zsav")
      }),
      xpt = redact_haven(haven::read_xpt, haven::write_xpt),
      parquet = redact_parquet, rds = redact_rds, rdata = redact_rdata, rda = redact_rdata
    )
  )
}

file_row <- function(source, status, destination = NA_character_, detail = NA_character_) {
  tibble::tibble(source = source, status = status, destination = destination, detail = detail)
}

redact_one <- function(source, read_status, findings, options, registry) {
  if (read_status != "read") {
    return(file_row(source, "not read", detail = paste("the scan could not read it:", read_status)))
  }
  if (is_redacted_copy(source, options$suffix)) {
    return(file_row(source, "skipped", detail = "a redacted copy"))
  }
  flagged <- findings[findings$source == source, ]
  findings <- acted_on(flagged, options$min_confidence, options$config)
  unreviewed <- acted_on(flagged, "low", options$config)
  weak <- setdiff(unique(unreviewed$locator), unique(findings$locator))
  weak <- if (length(weak) > 0L) {
    paste0("below ", options$min_confidence, " confidence, left: ", paste(weak, collapse = ", "))
  }
  if (nrow(findings) == 0L) {
    return(file_row(source, "clean", detail = paste(c("nothing to redact", weak), collapse = "; ")))
  }
  if (!fs::file_exists(source) && grepl("!", source, fixed = TRUE)) {
    return(file_row(source, "unsupported", detail = "inside an archive; extract it to redact it"))
  }
  type <- file_type(source)
  if (type %in% names(unwritable)) {
    return(file_row(source, "unsupported", detail = unwritable[[type]]))
  }
  destination <- redacted_path(source, options$suffix)
  if (fs::file_exists(destination) && !options$overwrite) {
    return(file_row(source, "failed", destination,
      detail = "the redacted copy exists; set `overwrite = TRUE` to replace it"
    ))
  }
  tryCatch(
    {
      actions <- registry[[type]](source, destination, findings, options)
      acted <- actions[!is.na(actions$method), ]
      left <- unique(unlist(strsplit(actions$left[nzchar(actions$left)], ", ", fixed = TRUE)))
      fields <- unique(stats::na.omit(acted$name))
      spans <- acted$type[is.na(acted$name)]
      detail <- c(
        if (length(fields) > 0L) paste("redacted:", paste(fields, collapse = ", ")),
        if (length(spans) > 0L) paste("replaced:", paste(spans, collapse = ", ")),
        if (length(left) > 0L) paste("left in place:", paste(left, collapse = ", ")),
        weak
      )
      file_row(
        source, if (length(left) > 0L) "partly redacted" else "redacted", destination,
        detail = if (length(detail) > 0L) paste(detail, collapse = "; ") else NA_character_
      )
    },
    error = function(e) {
      if (fs::file_exists(destination)) {
        fs::file_delete(destination)
      }
      file_row(source, "failed", detail = conditionMessage(e))
    }
  )
}

#' Write redacted copies of files
#'
#' For each file a scan read and flagged, writes a copy beside it with the
#' flagged fields redacted by [pii_redact()]: `survey.dta` becomes
#' `survey_redacted.dta`. Untouched columns are written as they were read;
#' Stata and SPSS variable and value labels are kept. In text files, such as
#' logs and scripts, matched email addresses, phone numbers and IP addresses
#' are replaced wherever they occur.
#'
#' Every file is accounted for in the result. A file can be `redacted`,
#' `partly redacted` (something flagged could not be removed, such as a name
#' inside free text), `clean` (nothing to redact; no copy written),
#' `unsupported` (the format cannot be written back), `skipped` (it is itself a
#' redacted copy), `not read`, or `failed`.
#'
#' Delimited text, Excel, Stata, SPSS (sav, zsav), SAS transport (xpt), R data
#' and Parquet files can be written back, as can plain text. An Excel file is
#' written as xlsx without its formatting or formulas and needs the 'writexl'
#' package. SAS data files, SPSS portable files, JSON and documents are
#' reported as unsupported.
#'
#' The originals are not changed or moved. Until they are removed or kept out
#' of version control, the personal data are still in the project.
#'
#' @param path Files or directories, as for [pii_scan()].
#' @param findings The result of [pii_scan()] on `path`. Scanned if missing.
#' @inheritParams pii_redact
#' @param suffix Added to a file's name to name its redacted copy.
#' @param overwrite Whether to replace a redacted copy that already exists.
#' @param config The project's configuration, from [pii_config()]; used for
#'   the scan when `findings` is missing.
#' @return A tibble with one row per file: `source`, `status`, the
#'   `destination` written, and in `detail` what was redacted and what was
#'   left.
#' @export
#' @examples
#' dir <- tempfile()
#' dir.create(dir)
#' survey <- data.frame(
#'   id = 1:20,
#'   q12 = paste0("person", 1:20, "@example.org"),
#'   village = rep(c("Palpur", "Netrad"), 10)
#' )
#' write.csv(survey, file.path(dir, "survey.csv"), row.names = FALSE)
#' writeLines("Call 98765 43210 after six.", file.path(dir, "notes.txt"))
#'
#' report <- pii_redact_files(dir, method = c(email = "pseudonym", default = "drop"), key = "s3")
#' report
#' read.csv(file.path(dir, "survey_redacted.csv"))[1:3, ]
pii_redact_files <- function(path, findings = pii_scan(path, config = config),
                             method = "placeholder", key = NULL, min_confidence = "medium",
                             suffix = "_redacted", overwrite = FALSE, config = pii_config()) {
  check_method(method, key)
  min_confidence <- rlang::arg_match0(min_confidence, confidence_levels, "min_confidence")
  if (!rlang::is_string(suffix) || !nzchar(suffix)) {
    cli::cli_abort("{.arg suffix} must be a non-empty string.")
  }
  report <- pii_read_report(findings)
  if (is.null(report)) {
    cli::cli_abort("{.arg findings} must come from a scan of files, not of a data frame.")
  }
  scan_config <- attr(findings, "config", exact = TRUE)
  options <- list(
    method = method, key = key, min_confidence = min_confidence, suffix = suffix,
    overwrite = overwrite, config = if (is.null(scan_config)) config else scan_config
  )
  registry <- writers()
  rows <- lapply(seq_len(nrow(report)), function(i) {
    redact_one(report$source[i], report$status[i], findings, options, registry)
  })
  result <- do.call(rbind, c(list(file_row(character(), character())), rows))
  cli::cli_inform(c(
    "Wrote {sum(result$status %in% c('redacted', 'partly redacted'))} redacted cop{?y/ies}.",
    "i" = "The originals are unchanged and still hold the personal data."
  ))
  result
}
