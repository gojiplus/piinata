compression_extensions <- c("gz", "bz2", "xz", "zip")
delimited_extensions <- c("csv", "tsv", "tab", "psv")

# readr reads and writes compressed delimited files directly, so
# "survey.csv.gz" is a csv. Other compressed files, and archives, are of type
# "archive" and are read member by member.
file_type <- function(path) {
  # A dotfile's name is its type: ".Rhistory" is an R history, ".env" a list
  # of settings.
  name <- basename(path)
  if (startsWith(name, ".") && !grepl(".", substring(name, 2L), fixed = TRUE)) {
    return(tolower(substring(name, 2L)))
  }
  packed <- tolower(fs::path_ext(path)) %in% compression_extensions
  extension <- tolower(fs::path_ext(if (packed) fs::path_ext_remove(path) else path))
  if (packed && !extension %in% delimited_extensions) {
    return("archive")
  }
  if (tolower(fs::path_ext(path)) %in% archive_extensions) {
    return("archive")
  }
  extension
}

read_one <- function(path, registry) {
  reader <- registry[[file_type(path)]]
  if (is.null(reader)) {
    detail <- "no reader for this file type"
    return(list(fields = new_fields(), status = "unsupported", detail = detail))
  }
  tryCatch(
    {
      fields <- reader(path)
      list(fields = fields, status = "read", detail = NA_character_)
    },
    piinata_unsupported = function(e) {
      list(fields = new_fields(), status = "unsupported", detail = conditionMessage(e))
    },
    piinata_ignored = function(e) {
      list(fields = new_fields(), status = "ignored", detail = conditionMessage(e))
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
#' @param ignore Globs of files not to read. They are reported as `ignored`.
#' @param root The folder `ignore` globs are relative to, normally the one
#'   holding `.piinata.yml`.
#' @return A tibble of fields; see [as_pii_fields()].
#' @export
#' @examples
#' file <- tempfile(fileext = ".csv")
#' write.csv(data.frame(q1 = c("a@example.org", "b@example.org")), file, row.names = FALSE)
#' fields <- pii_read(file)
#' fields
#' pii_read_report(fields)
pii_read <- function(path, ignore = character(), root = ".") {
  if (!is.character(path) || length(path) == 0L) {
    cli::cli_abort("{.arg path} must be a character vector of files or directories.")
  }
  missing <- path[!fs::file_exists(path)]
  if (length(missing) > 0L) {
    cli::cli_abort("Cannot find {.file {missing}}.")
  }
  directory <- fs::is_dir(path)
  # Hidden files are read too: .Rhistory and .env files hold personal data
  # as often as anything. Folders that tools keep for themselves (version
  # control, environments, caches) are reported once each as ignored.
  listed <- lapply(path[directory], function(d) {
    found <- as.character(fs::dir_ls(d, recurse = TRUE, type = "file", all = TRUE))
    parts <- strsplit(as.character(fs::path_rel(found, d)), "/", fixed = TRUE)
    # A .git file, as in worktrees and submodules, points to a repository.
    tool <- vapply(parts, function(p) {
      hit <- which(p %in% tool_folders & (seq_along(p) < length(p) | p == ".git"))
      if (length(hit) == 0L) NA_character_ else paste(p[seq_len(hit[1])], collapse = "/")
    }, character(1))
    list(files = found[is.na(tool)], tools = unique(file.path(d, stats::na.omit(tool))))
  })
  files <- c(path[!directory], unlist(lapply(listed, `[[`, "files")))
  tools <- unlist(lapply(listed, `[[`, "tools"))
  files <- unique(as.character(files))
  registry <- readers()
  skipped <- matches_glob(files, ignore, root)
  results <- unlist(lapply(seq_along(files), function(i) {
    if (skipped[i]) {
      return(list(list(
        source = files[i], fields = new_fields(), status = "ignored",
        detail = "listed under ignore"
      )))
    }
    read_path(files[i], registry, ignore, root = root)
  }), recursive = FALSE)
  results <- c(results, lapply(tools, function(folder) {
    list(source = folder, fields = new_fields(), status = "ignored", detail = "a tool's own folder")
  }))
  fields <- do.call(rbind, c(list(new_fields()), lapply(results, `[[`, "fields")))
  attr(fields, "read_report") <- tibble::tibble(
    source = vapply(results, `[[`, character(1), "source"),
    status = vapply(results, `[[`, character(1), "status"),
    n_fields = vapply(results, function(r) nrow(r$fields), integer(1)),
    detail = vapply(results, `[[`, character(1), "detail")
  )
  fields
}

#' What was and was not read
#'
#' @param x The result of [pii_read()] or [pii_scan()].
#' @return A tibble with one row per file: `source`, `status` (`read`,
#'   `unsupported`, `failed` or `ignored`), the number of fields read (`n_fields`) and, when not
#'   read, the reason in `detail`. `NULL` if `x` did not come from files.
#' @export
#' @examples
#' file <- tempfile(fileext = ".xyz")
#' writeLines("something", file)
#' pii_read_report(pii_read(file))
pii_read_report <- function(x) {
  attr(x, "read_report", exact = TRUE)
}
