need <- function(package, what) {
  if (!rlang::is_installed(package)) {
    rlang::abort(
      paste0("install the '", package, "' package to read ", what),
      class = "piinata_unsupported"
    )
  }
}

text_columns <- readr::cols(.default = readr::col_character())

is_qualtrics <- function(path) {
  head <- tryCatch(readr::read_lines(path, n_max = 3L, progress = FALSE), error = function(e) "")
  length(head) == 3L && stringr::str_detect(head[3], stringr::fixed("ImportId"))
}

read_qualtrics <- function(path) {
  need("qualtRics", "Qualtrics exports with their question text")
  data <- suppressMessages(qualtRics::read_survey(path, col_types = text_columns))
  fields_from_table(data, path)
}

read_delim_file <- function(path, delim) {
  if (is_qualtrics(path)) {
    return(read_qualtrics(path))
  }
  data <- readr::read_delim(
    path,
    delim = delim, col_types = text_columns, progress = FALSE,
    show_col_types = FALSE, name_repair = "unique_quiet"
  )
  fields_from_table(data, path)
}

read_excel_file <- function(path) {
  sheets <- readxl::excel_sheets(path)
  fields <- lapply(sheets, function(sheet) {
    data <- readxl::read_excel(
      path,
      sheet = sheet, col_types = "text", .name_repair = "unique_quiet"
    )
    fields_from_table(data, path, sheet = sheet)
  })
  do.call(rbind, fields)
}

read_parquet_file <- function(path) {
  need("nanoparquet", "Parquet files")
  fields_from_table(nanoparquet::read_parquet(path), path)
}

read_json_file <- function(path, lines = FALSE) {
  need("jsonlite", "JSON files")
  data <- if (lines) {
    jsonlite::stream_in(file(path), verbose = FALSE)
  } else {
    jsonlite::fromJSON(path, flatten = TRUE)
  }
  if (is.data.frame(data)) {
    return(fields_from_table(data, path))
  }
  read_text_file(path)
}

read_rds_file <- function(path) {
  data <- readRDS(path)
  if (is.data.frame(data) || is.character(data)) {
    return(as_pii_fields(data, source = path))
  }
  rlang::abort("holds neither a data frame nor text", class = "piinata_unsupported")
}

read_rdata_file <- function(path) {
  objects <- new.env()
  load(path, envir = objects)
  fields <- lapply(ls(objects), function(name) {
    object <- get(name, envir = objects)
    if (is.data.frame(object)) fields_from_table(object, path, sheet = name) else new_fields()
  })
  do.call(rbind, c(list(new_fields()), fields))
}

read_text_file <- function(path) {
  fields_from_text(readr::read_lines(path, progress = FALSE), path, "lines")
}

read_pdf_file <- function(path) {
  need("pdftools", "PDF files")
  pages <- pdftools::pdf_text(path)
  if (!any(nzchar(stringr::str_squish(pages)))) {
    rlang::abort("has no text layer; it is probably a scan", class = "piinata_unsupported")
  }
  fields <- lapply(seq_along(pages), function(i) {
    lines <- stringr::str_split(pages[i], "\n")[[1]]
    fields_from_text(lines, path, paste("page", i))
  })
  do.call(rbind, fields)
}

read_docx_file <- function(path) {
  need("officer", "Word documents")
  fields_from_text(officer::docx_summary(officer::read_docx(path))$text, path, "paragraphs")
}

read_rtf_file <- function(path) {
  need("striprtf", "RTF files")
  fields_from_text(striprtf::read_rtf(path), path, "paragraphs")
}

read_html_file <- function(path) {
  need("rvest", "HTML files")
  text <- rvest::html_text2(rvest::read_html(path))
  fields_from_text(stringr::str_split(text, "\n")[[1]], path, "lines")
}

readers <- function() {
  haven_reader <- function(read) function(path) fields_from_table(read(path), path)
  text <- c(
    "txt", "md", "log", "do", "r", "rmd", "qmd", "py", "tex", "bib", "smcl", "sql", "yaml", "yml"
  )
  c(
    list(
      csv = function(path) read_delim_file(path, ","),
      tsv = function(path) read_delim_file(path, "\t"),
      tab = function(path) read_delim_file(path, "\t"),
      psv = function(path) read_delim_file(path, "|"),
      xlsx = read_excel_file, xls = read_excel_file,
      dta = haven_reader(haven::read_dta), sav = haven_reader(haven::read_sav),
      zsav = haven_reader(haven::read_sav), por = haven_reader(haven::read_por),
      sas7bdat = haven_reader(haven::read_sas), xpt = haven_reader(haven::read_xpt),
      parquet = read_parquet_file,
      json = function(path) read_json_file(path),
      jsonl = function(path) read_json_file(path, lines = TRUE),
      ndjson = function(path) read_json_file(path, lines = TRUE),
      rds = read_rds_file, rdata = read_rdata_file, rda = read_rdata_file,
      pdf = read_pdf_file, docx = read_docx_file, rtf = read_rtf_file,
      html = read_html_file, htm = read_html_file
    ),
    stats::setNames(rep(list(read_text_file), length(text)), text)
  )
}
