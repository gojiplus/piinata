found_in <- function(path) sort(unique(pii_scan(path)$name))

test_that("the same survey gives the same findings in every table format", {
  dir <- withr::local_tempdir()
  data <- survey()
  readr::write_csv(data, file.path(dir, "s.csv"))
  readr::write_tsv(data, file.path(dir, "s.tsv"))
  haven::write_dta(data, file.path(dir, "s.dta"))
  haven::write_sav(data, file.path(dir, "s.sav"))
  saveRDS(data, file.path(dir, "s.rds"))
  expected <- sort(personal)
  for (file in c("s.csv", "s.tsv", "s.dta", "s.sav", "s.rds")) {
    expect_equal(found_in(file.path(dir, file)), expected, info = file)
  }
  skip_if_not_installed("writexl")
  writexl::write_xlsx(list(first = data, second = data[1:2]), file.path(dir, "s.xlsx"))
  expect_equal(found_in(file.path(dir, "s.xlsx")), expected)
  expect_true("second!resp_name" %in% pii_read(file.path(dir, "s.xlsx"))$locator)
})

test_that("Parquet and JSON lines are read when their packages are installed", {
  skip_if_not_installed("nanoparquet")
  skip_if_not_installed("jsonlite")
  dir <- withr::local_tempdir()
  nanoparquet::write_parquet(survey(), file.path(dir, "s.parquet"))
  jsonlite::stream_out(survey(), file(file.path(dir, "s.jsonl")), verbose = FALSE)
  expect_equal(found_in(file.path(dir, "s.parquet")), sort(personal))
  expect_equal(found_in(file.path(dir, "s.jsonl")), sort(personal))
})

test_that("variable labels are read and used", {
  path <- withr::local_tempfile(fileext = ".dta")
  data <- data.frame(q7 = 1:30)
  attr(data$q7, "label") <- "Respondent's mobile number"
  haven::write_dta(data, path)
  expect_equal(pii_read(path)$label, "Respondent's mobile number")
  expect_equal(pii_scan(path)$detector, "label_term")
})

test_that("a Qualtrics export keeps its question text and platform fields", {
  skip_if_not_installed("qualtRics")
  path <- withr::local_tempfile(fileext = ".csv")
  import_id <- function(id) paste0("\"{\"\"ImportId\"\":\"\"", id, "\"\"}\"")
  header <- c(
    "IPAddress,Q1,Q2",
    "IP Address,What is your phone number?,How satisfied are you?",
    paste(import_id(c("ipAddress", "QID1", "QID2")), collapse = ",")
  )
  rows <- sprintf("49.35.1.%d,4,%d", 1:30, 1:30 %% 5)
  writeLines(c(header, rows), path)
  fields <- pii_read(path)
  expect_equal(nrow(fields), 3L)
  expect_equal(lengths(fields$values), c(30L, 30L, 30L))
  expect_equal(fields$label[fields$name == "Q1"], "What is your phone number?")
  expect_setequal(unique(pii_scan(path)$name), c("IPAddress", "Q1"))
})

test_that("documents are read as text", {
  dir <- withr::local_tempdir()
  lines <- c("Interview notes.", "Reach Asha at asha.devi@example.org or 98765 43210.")
  writeLines(lines, file.path(dir, "notes.txt"))
  expect_setequal(pii_scan(file.path(dir, "notes.txt"))$type, c("email", "phone"))
  skip_if_not_installed("officer")
  doc <- officer::read_docx()
  for (line in lines) doc <- officer::body_add_par(doc, line)
  print(doc, target = file.path(dir, "notes.docx"))
  expect_setequal(pii_scan(file.path(dir, "notes.docx"))$type, c("email", "phone"))
})

test_that("PDF pages are located", {
  skip_if_not_installed("pdftools")
  path <- withr::local_tempfile(fileext = ".pdf")
  grDevices::pdf(path)
  for (text in c("Nothing here.", "Write to asha.devi@example.org")) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, text)
  }
  grDevices::dev.off()
  findings <- pii_scan(path)
  expect_equal(findings$type, "email")
  expect_equal(findings$locator, "page 2")
})

test_that("every file is accounted for", {
  dir <- withr::local_tempdir()
  readr::write_csv(survey(), file.path(dir, "good.csv"))
  writeLines("binary", file.path(dir, "photo.jpg"))
  writeLines("not a stata file", file.path(dir, "broken.dta"))
  report <- pii_read_report(pii_scan(dir))
  status <- stats::setNames(report$status, basename(report$source))
  expect_equal(status[["good.csv"]], "read")
  expect_equal(status[["photo.jpg"]], "unsupported")
  expect_equal(status[["broken.dta"]], "failed")
  expect_error(pii_check(pii_scan(dir)), "Could not read 2 files")
})

test_that("a missing path is an error, not an empty scan", {
  expect_error(pii_read("no/such/file.csv"), "Cannot find")
})

test_that("compressed delimited files and R workspaces are read", {
  dir <- withr::local_tempdir()
  data <- survey()
  readr::write_csv(data, file.path(dir, "s.csv.gz"))
  save(data, file = file.path(dir, "s.RData"))
  expect_equal(found_in(file.path(dir, "s.csv.gz")), sort(personal))
  expect_equal(found_in(file.path(dir, "s.RData")), sort(personal))
  connection <- gzfile(file.path(dir, "notes.txt.gz"), "w")
  writeLines("Write to asha@example.org", connection)
  close(connection)
  report <- pii_read_report(pii_read(file.path(dir, "notes.txt.gz")))
  expect_equal(report$status, "read")
  expect_match(report$source, "notes.txt.gz!notes.txt", fixed = TRUE)
})
