project <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  readr::write_csv(people(), file.path(dir, "survey.csv"), na = "")
  data <- people()
  attr(data$email, "label") <- "Email address"
  data$village <- haven::labelled(match(data$village, c("Palpur", "Netrad")),
    c(Palpur = 1, Netrad = 2),
    label = "Village"
  )
  haven::write_dta(data, file.path(dir, "survey.dta"))
  writeLines(
    c("Started.", "Called 98765 43210 and 91234 56789; wrote to a@example.org.", "Done."),
    file.path(dir, "fieldwork.log")
  )
  writeLines("{\"email\": \"a@example.org\"}", file.path(dir, "contacts.json"))
  readr::write_csv(data.frame(season = rep(c("rabi", "kharif"), 20)), file.path(dir, "crops.csv"))
  dir
}

status_of <- function(report, file) report$status[basename(report$source) == file]

test_that("each flagged file gets a redacted copy and every file is accounted for", {
  dir <- project()
  report <- suppressMessages(pii_redact_files(dir))
  expect_setequal(
    basename(report$source),
    c("survey.csv", "survey.dta", "fieldwork.log", "contacts.json", "crops.csv")
  )
  expect_equal(status_of(report, "survey.csv"), "redacted")
  expect_equal(status_of(report, "fieldwork.log"), "redacted")
  expect_equal(status_of(report, "contacts.json"), "unsupported")
  expect_equal(status_of(report, "crops.csv"), "clean")
  expect_false(fs::file_exists(file.path(dir, "crops_redacted.csv")))
  expect_true(fs::file_exists(file.path(dir, "survey_redacted.dta")))
})

test_that("a redacted csv changes flagged columns only", {
  dir <- project()
  suppressMessages(pii_redact_files(dir, method = c(location = "drop", default = "placeholder")))
  text <- readr::cols(.default = readr::col_character())
  original <- readr::read_csv(file.path(dir, "survey.csv"), col_types = text)
  clean <- readr::read_csv(file.path(dir, "survey_redacted.csv"), col_types = text)
  expect_equal(unique(clean$email), "<EMAIL>")
  expect_false("village" %in% names(clean))
  expect_equal(clean$id, original$id)
  expect_equal(clean$income, original$income)
  expect_match(clean$note[4], "^Call me on <PHONE> after six$")
})

test_that("Stata labels survive", {
  dir <- project()
  suppressMessages(pii_redact_files(dir, method = c(email = "pseudonym"), key = "k1"))
  clean <- haven::read_dta(file.path(dir, "survey_redacted.dta"))
  expect_equal(attr(clean$email, "label"), "Email address")
  expect_false(any(clean$email %in% people()$email))
})

test_that("text files lose every match and keep the rest", {
  dir <- project()
  suppressMessages(pii_redact_files(dir))
  expect_equal(
    readLines(file.path(dir, "fieldwork_redacted.log")),
    c("Started.", "Called <PHONE> and <PHONE>; wrote to <EMAIL>.", "Done.")
  )
})

test_that("a second run skips the copies and does not overwrite by default", {
  dir <- project()
  suppressMessages(pii_redact_files(dir))
  again <- suppressMessages(pii_redact_files(dir))
  expect_equal(status_of(again, "survey_redacted.csv"), "skipped")
  expect_equal(status_of(again, "survey.csv"), "failed")
  expect_match(again$detail[basename(again$source) == "survey.csv"], "overwrite")
  replaced <- suppressMessages(pii_redact_files(dir, overwrite = TRUE))
  expect_equal(status_of(replaced, "survey.csv"), "redacted")
})

test_that("Excel files are redacted sheet by sheet", {
  skip_if_not_installed("writexl")
  dir <- withr::local_tempdir()
  writexl::write_xlsx(
    list(main = people(), other = data.frame(contact = paste0("x", 1:30, "@example.org"))),
    file.path(dir, "book.xlsx")
  )
  report <- suppressMessages(pii_redact_files(dir))
  expect_equal(report$status, "redacted")
  other <- readxl::read_excel(file.path(dir, "book_redacted.xlsx"), sheet = "other")
  main <- readxl::read_excel(file.path(dir, "book_redacted.xlsx"), sheet = "main")
  expect_equal(unique(other$contact), "<EMAIL>")
  expect_equal(main$income, people()$income)
})

test_that("compressed csv keeps its compression and name", {
  dir <- withr::local_tempdir()
  readr::write_csv(people(), file.path(dir, "survey.csv.gz"))
  report <- suppressMessages(pii_redact_files(dir))
  expect_equal(basename(report$destination), "survey_redacted.csv.gz")
  expect_equal(unique(readr::read_csv(report$destination, show_col_types = FALSE)$email), "<EMAIL>")
})

test_that("findings from a data frame are refused", {
  expect_error(pii_redact_files("x", findings = pii_scan(people())), "scan of files")
})
