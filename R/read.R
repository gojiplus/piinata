read_one <- function(path, registry) {
  extension <- tolower(fs::path_ext(path))
  reader <- registry[[extension]]
  if (is.null(reader)) {
    detail <- "no reader for this file type"
    return(list(fields = new_fields(), status = "unsupported", detail = detail))
  }
  tryCatch(
    {
      fields <- reader(path)
      list(fields = fields, status = "read", detail = NA_character_)
    },
    piiscan_unsupported = function(e) {
      list(fields = new_fields(), status = "unsupported", detail = conditionMessage(e))
    },
    error = function(e) {
      list(fields = new_fields(), status = "failed", detail = conditionMessage(e))
    }
  )
}

#' Read files into fields
#'
#' Reads every file under `path` with an established reader and returns one row
#' per column of each table and per block of running text. Nothing is skipped
#' silently: [pii_read_report()] lists every file as read, unsupported or
#' failed, with the reason.
#'
#' Delimited text, Excel, Stata, SPSS and SAS files, R data, and plain text are
#' always readable. Parquet, JSON, PDF, Word, RTF, HTML and Qualtrics exports
#' need a suggested package and are reported as unsupported, naming the
#' package, when it is missing. Variable labels and Qualtrics question text are
#' kept as the field's `label`.
#'
#' @param path Files or directories. Directories are searched recursively.
#' @return A tibble of fields; see [as_pii_fields()].
#' @export
#' @examples
#' file <- tempfile(fileext = ".csv")
#' write.csv(data.frame(q1 = c("a@example.org", "b@example.org")), file, row.names = FALSE)
#' fields <- pii_read(file)
#' fields
#' pii_read_report(fields)
pii_read <- function(path) {
  if (!is.character(path) || length(path) == 0L) {
    cli::cli_abort("{.arg path} must be a character vector of files or directories.")
  }
  missing <- path[!fs::file_exists(path)]
  if (length(missing) > 0L) {
    cli::cli_abort("Cannot find {.file {missing}}.")
  }
  directory <- fs::is_dir(path)
  files <- c(path[!directory], unlist(lapply(path[directory], function(d) {
    as.character(fs::dir_ls(d, recurse = TRUE, type = "file"))
  })))
  files <- unique(as.character(files))
  registry <- readers()
  results <- lapply(files, read_one, registry = registry)
  fields <- do.call(rbind, c(list(new_fields()), lapply(results, `[[`, "fields")))
  attr(fields, "read_report") <- tibble::tibble(
    source = files,
    status = vapply(results, `[[`, character(1), "status"),
    fields = vapply(results, function(r) nrow(r$fields), integer(1)),
    detail = vapply(results, `[[`, character(1), "detail")
  )
  fields
}

#' What was and was not read
#'
#' @param x The result of [pii_read()] or [pii_scan()].
#' @return A tibble with one row per file: `source`, `status` (`read`,
#'   `unsupported` or `failed`), the number of `fields` read and, when not
#'   read, the reason in `detail`. `NULL` if `x` did not come from files.
#' @export
#' @examples
#' file <- tempfile(fileext = ".xyz")
#' writeLines("something", file)
#' pii_read_report(pii_read(file))
pii_read_report <- function(x) {
  attr(x, "read_report", exact = TRUE)
}
