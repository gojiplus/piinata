write_config <- function(lines, dir = withr::local_tempdir(.local_envir = parent.frame())) {
  path <- file.path(dir, ".piinata.yml")
  writeLines(lines, path)
  path
}

test_that("a missing configuration is empty", {
  config <- pii_config(file.path(withr::local_tempdir(), ".piinata.yml"))
  expect_length(config$allow, 0L)
  expect_null(config$min_confidence)
})

test_that("an allowed field with a reason passes the check", {
  findings <- pii_scan(data.frame(village = paste("Village", 1:30)))
  expect_error(pii_check(findings), "possible personal data")
  config <- pii_config(write_config(c(
    "allow:", "  - field: village", "    reason: Needed for clustering."
  )))
  expect_invisible(pii_check(findings, config = config))
})

test_that("an exception must say why", {
  path <- write_config(c("allow:", "  - field: village"))
  expect_error(pii_config(path), "needs a")
  path <- write_config(c("allow:", "  - reason: because"))
  expect_error(pii_config(path), "field, type or source")
  path <- write_config("alow: []")
  expect_error(pii_config(path), "Unknown setting")
})

test_that("an exception can be limited to a type and a source", {
  dir <- withr::local_tempdir()
  data <- data.frame(winner_name = paste("Resp", 1:30), phone = sprintf("98765%05d", 1:30))
  readr::write_csv(data, file.path(dir, "elections.csv"))
  readr::write_csv(data, file.path(dir, "survey.csv"))
  config <- pii_config(write_config(c(
    "allow:", "  - type: person_name", "    source: elections.csv",
    "    reason: Public record of elected officials."
  ), dir))
  findings <- pii_scan(dir, config = config)
  open <- findings[!allowed_by(findings, config$allow) & findings$confidence != "low", ]
  expect_false(any(open$type == "person_name" & basename(open$source) == "elections.csv"))
  expect_true(any(open$type == "person_name" & basename(open$source) == "survey.csv"))
  expect_true(any(open$name == "phone" & basename(open$source) == "elections.csv"))
})

test_that("ignored files are reported, not read, and do not fail the check", {
  dir <- withr::local_tempdir()
  readr::write_csv(data.frame(x = 1:30), file.path(dir, "clean.csv"))
  dir.create(file.path(dir, "raw"))
  emails <- data.frame(email = paste0("p", 1:30, "@example.org"))
  readr::write_csv(emails, file.path(dir, "raw", "a.csv"))
  config <- pii_config(write_config(c("ignore:", "  - '*/raw/*'"), dir))
  findings <- pii_scan(dir, config = config)
  report <- pii_read_report(findings)
  expect_equal(report$status[basename(report$source) == "a.csv"], "ignored")
  expect_equal(nrow(findings), 0L)
  expect_invisible(pii_check(findings))
})

test_that("custom patterns and terms extend the scan", {
  config <- pii_config(write_config(c(
    "patterns:", "  - name: study_id", "    regex: '^RJ-[0-9]{6}$'", "    confidence: high",
    "terms:", "  person_name: [mukhiya]"
  )))
  data <- data.frame(q1 = sprintf("RJ-%06d", 1:30), mukhiya = paste("Resp", 1:30))
  findings <- pii_scan(data, config = config)
  expect_equal(findings$detector[findings$name == "q1"], "custom:study_id")
  expect_equal(findings$confidence[findings$name == "q1"], "high")
  expect_true("name_term" %in% findings$detector[findings$name == "mukhiya"])
  expect_equal(nrow(pii_scan(data["q1"])), 0L)
})

test_that("a bad pattern is rejected when the configuration is read", {
  path <- write_config(c("patterns:", "  - name: broken", "    regex: '('"))
  expect_error(pii_config(path), "not a valid regular expression")
})

test_that("review decisions are recorded and then honored", {
  dir <- withr::local_tempdir()
  review <- file.path(dir, "review.csv")
  config <- file.path(dir, ".piinata.yml")
  data <- data.frame(village = paste("Village", 1:30), phone = sprintf("98765%05d", 1:30))
  findings <- pii_scan(data)
  expect_message(pii_review(findings, review), "to review")
  decisions <- readr::read_csv(review, show_col_types = FALSE)
  expect_setequal(decisions$name, c("village", "phone"))
  decisions$decision <- ifelse(decisions$name == "village", "allow", "remove")
  decisions$reason <- ifelse(decisions$name == "village", "Needed for clustering.", "")
  readr::write_csv(decisions, review)
  expect_message(accepted <- pii_accept(review, config), "Recorded 1 allowed field")
  expect_equal(accepted$allow[[1]]$field, "village")
  expect_error(pii_check(findings, config = accepted), "1 field")
  expect_invisible(pii_check(findings[findings$name == "village", ], config = accepted))
})

test_that("allowing without a reason is refused", {
  dir <- withr::local_tempdir()
  review <- file.path(dir, "review.csv")
  findings <- pii_scan(data.frame(village = paste("Village", 1:30)))
  suppressMessages(pii_review(findings, review))
  decisions <- readr::read_csv(review, show_col_types = FALSE, col_types = "c")
  decisions$decision <- "allow"
  decisions$reason <- ""
  readr::write_csv(decisions, review)
  expect_error(pii_accept(review, file.path(dir, ".piinata.yml")), "needs a")
})

config_with <- function(lines) {
  path <- withr::local_tempfile(fileext = ".yml", .local_envir = parent.frame())
  writeLines(lines, path)
  pii_config(path)
}

test_that("a word list finds its words, whole and in any case", {
  config <- config_with(c(
    "patterns:", "  - name: interviewer", "    type: person_name",
    "    words: [Kamla Meena, Ravi Bairwa]"
  ))
  notes <- data.frame(note = c(
    paste("Visit", 1:30, "went well and the road was dry after the rains"),
    "Interview done by kamla meena at noon", "Ravi Bairwanath came along"
  ))
  found <- pii_scan(notes, config = config)
  hit <- found[found$detector == "custom:interviewer", ]
  expect_equal(hit$n, 1L)
})

test_that("excluded values do not count and validation must pass", {
  config <- config_with(c(
    "patterns:", "  - name: member_card", "    regex: '^[0-9]{16}$'",
    "    validate: luhn", "    exclude: '^0'", "    confidence: low"
  ))
  withr::local_seed(4)
  valid <- c("4111111111111111", "5555555555554444", "0000000000000000")
  numbers <- data.frame(q9 = rep(valid, 10))
  found <- pii_scan(numbers, config = config)
  hit <- found[found$detector == "custom:member_card", ]
  expect_equal(hit$n, 20L)
})

test_that("an unknown check is an error", {
  expect_error(
    config_with(c("patterns:", "  - name: x", "    regex: x", "    validate: crc32")),
    "must be one of"
  )
})

test_that("a column's name lifts what its values show", {
  skip_if_not("us_ssn" %in% idcheck::id_schemes()$scheme)
  withr::local_seed(5)
  ssn <- sprintf("%03d-%02d-%04d", sample(1:665, 60), sample(1:99, 60, TRUE), sample(1:9999, 60))
  grade <- function(data) {
    found <- pii_scan(data, config = pii_config("none.yml"))
    found$confidence[found$detector == "idcheck:us_ssn"]
  }
  expect_equal(grade(data.frame(q24 = ssn)), "low")
  expect_equal(grade(data.frame(ssn_number = ssn)), "medium")
})

test_that("context words of custom patterns lift their findings", {
  config <- config_with(c(
    "patterns:", "  - name: study_id", "    regex: '^RJ-[0-9]{6}$'",
    "    confidence: low", "    context: [respondent]"
  ))
  ids <- sprintf("RJ-%06d", 1:30)
  grade <- function(data) pii_scan(data, config = config)$confidence
  expect_equal(grade(data.frame(q1 = ids)), "low")
  expect_equal(grade(data.frame(respondent_code = ids)), "medium")
})

test_that("ignore and allow globs hold whatever path the scan was given (D9)", {
  root <- withr::local_tempdir()
  fs::dir_create(file.path(root, "data", "raw"))
  utils::write.csv(data.frame(e = paste0("p", 1:20, "@example.org")),
    file.path(root, "data", "raw", "a.csv"),
    row.names = FALSE
  )
  writeLines(c("ignore:", "  - data/raw/*"), file.path(root, ".piinata.yml"))
  config <- pii_config(file.path(root, ".piinata.yml"))
  report <- pii_read_report(pii_scan(file.path(root, "data"), config = config))
  expect_equal(report$status, "ignored")
})

test_that("recorded sources match file names with regex characters (D10)", {
  root <- withr::local_tempdir()
  utils::write.csv(data.frame(email = paste0("p", 1:20, "@example.org")),
    file.path(root, "a+b.csv"),
    row.names = FALSE
  )
  findings <- pii_scan(file.path(root, "a+b.csv"), config = pii_config("none.yml"))
  review <- file.path(root, "review.csv")
  suppressMessages(pii_review(findings, review))
  decisions <- utils::read.csv(review)
  decisions$decision <- "allow"
  decisions$reason <- "test"
  utils::write.csv(decisions, review, row.names = FALSE)
  config <- suppressMessages(pii_accept(review, file.path(root, ".piinata.yml")))
  expect_no_error(pii_check(findings, config = config))
})

test_that("YAML 1.1 booleans are read as the words they are (D11)", {
  skip_if_not_installed("dialtone")
  path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("regions: [NO, IN]", "terms:", "  person_name: [no, yes]"), path)
  config <- pii_config(path)
  expect_equal(config$regions, c("NO", "IN"))
  expect_equal(config$terms$person_name, c("no", "yes"))
})

test_that("globs hold through a symlinked path (D9)", {
  root <- withr::local_tempdir()
  fs::dir_create(file.path(root, "data", "raw"))
  utils::write.csv(data.frame(e = 1), file.path(root, "data", "raw", "a.csv"), row.names = FALSE)
  link <- file.path(withr::local_tempdir(), "linked")
  fs::link_create(root, link)
  writeLines(c("ignore:", "  - data/raw/*"), file.path(root, ".piinata.yml"))
  config <- pii_config(file.path(root, ".piinata.yml"))
  report <- pii_read_report(pii_scan(file.path(link, "data"), config = config))
  expect_equal(report$status, "ignored")
})
