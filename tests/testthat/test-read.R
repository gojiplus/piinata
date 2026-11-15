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

test_that("hidden files are read, and .git is left out (D5)", {
  dir <- withr::local_tempdir()
  writeLines("asha@example.org ravi@example.org", file.path(dir, ".Rhistory"))
  writeLines("SECRET_EMAIL=asha@example.org", file.path(dir, ".env"))
  fs::dir_create(file.path(dir, ".secret"))
  writeLines("asha@example.org", file.path(dir, ".secret", "notes.txt"))
  fs::dir_create(file.path(dir, ".git"))
  writeLines("ref: refs/heads/main", file.path(dir, ".git", "HEAD"))
  report <- pii_read_report(pii_read(dir))
  expect_setequal(basename(report$source), c(".Rhistory", ".env", "notes.txt", ".git"))
  expect_equal(report$status[basename(report$source) == ".git"], "ignored")
  expect_true(all(report$status[basename(report$source) != ".git"] == "read"))
})

test_that("Excel dates are read as dates (D7)", {
  skip_if_not_installed("writexl")
  path <- withr::local_tempfile(fileext = ".xlsx")
  writexl::write_xlsx(data.frame(q7 = as.Date("1980-01-01") + (0:29) * 211), path)
  expect_equal(pii_read(path)$values[[1]][1], "1980-01-01")
  expect_true("date_of_birth" %in% pii_scan(path, config = pii_config("none.yml"))$type)
})

test_that("objects with hidden names in RData files are read (D8)", {
  path <- withr::local_tempfile(fileext = ".RData")
  .hid <- data.frame(email = paste0("p", 1:20, "@example.org"))
  vis <- data.frame(x = 1:20)
  save(.hid, vis, file = path)
  expect_true(".hid!email" %in% pii_read(path)$locator)
})

test_that("gzip bombs are stopped before they fill the disk (D12)", {
  path <- withr::local_tempfile(fileext = ".txt.gz")
  connection <- gzfile(path, "w")
  writeLines(strrep("a", 5000), connection)
  close(connection)
  withr::local_options(piinata.max_unpacked = 1000)
  report <- pii_read_report(pii_read(path))
  expect_equal(report$status, "unsupported")
  expect_match(report$detail, "more than")
})

test_that("tool folders are reported as ignored, not scanned (N1)", {
  dir <- withr::local_tempdir()
  fs::dir_create(file.path(dir, ".venv", "lib"))
  writeBin(as.raw(0:255), file.path(dir, ".venv", "lib", "x.so"))
  writeLines("asha@example.org", file.path(dir, "notes.txt"))
  report <- pii_read_report(pii_read(dir))
  expect_equal(report$status[basename(report$source) == ".venv"], "ignored")
  expect_false(any(report$status %in% c("unsupported", "failed")))
})

test_that("Excel numbers keep their digits (N4)", {
  skip_if_not_installed("writexl")
  path <- withr::local_tempfile(fileext = ".xlsx")
  data <- data.frame(pin = c(100000, 200000, 110001), d = as.Date("1980-01-01") + 0:2)
  writexl::write_xlsx(data, path)
  fields <- pii_read(path)
  expect_equal(fields$values[[1]], c("100000", "200000", "110001"))
  expect_equal(fields$values[[2]][1], "1980-01-01")
})
