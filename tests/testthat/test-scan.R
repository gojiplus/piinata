test_that("personal columns are found and keyword traps are not", {
  findings <- pii_scan(survey())
  expect_setequal(unique(findings$name), personal)
})

test_that("values give a column away when its name does not", {
  findings <- pii_scan(survey())
  by_value <- findings[findings$evidence == "value", ]
  expect_equal(by_value$type[by_value$name == "q12"], "email")
  expect_true("phone" %in% by_value$type[by_value$name == "q13"])
  expect_equal(by_value$type[by_value$name == "q15"], "person_name")
})

test_that("names match on whole words only", {
  traps <- data.frame(reason = 1:30, season = 1:30, latrine = 1:30, relation = 1:30)
  expect_equal(nrow(pii_scan(traps)), 0L)
  expect_equal(pii_scan(data.frame(firstName = paste("Resp", 1:30)))$type[1], "person_name")
  expect_equal(pii_scan(data.frame(GPS_Lat = 26 + (1:30) / 1000))$type, "coordinates")
})

test_that("a stray match in a coded column is not a finding", {
  codes <- data.frame(q1 = c(rep("yes", 99), "a@example.org"))
  expect_equal(nrow(pii_scan(codes)), 0L)
})

test_that("an IP address is not also reported as a phone number", {
  findings <- pii_scan(data.frame(q9 = sprintf("49.35.%d.%d", 1:30, 100:129)))
  expect_equal(findings$type, "ip_address")
})

test_that("a survey date is not a date of birth", {
  recent <- format(Sys.Date() - 1:30)
  expect_equal(nrow(pii_scan(data.frame(interview = recent))), 0L)
  expect_equal(pii_scan(data.frame(q4 = sprintf("%02d/03/1984", 1:28)))$type, "date_of_birth")
})

test_that("examples are masked unless asked for", {
  email <- data.frame(q1 = paste0("person", 1:20, "@example.org"))
  masked <- unlist(pii_scan(email)$examples)
  expect_false(any(grepl("person", masked, fixed = TRUE)))
  shown <- unlist(pii_scan(email, show_values = TRUE)$examples)
  expect_true(all(shown %in% email$q1))
})

test_that("text is scanned match by match", {
  note <- as_pii_fields(c("Met the sarpanch.", "Her number is 98765 43210."), source = "note")
  expect_equal(pii_scan(note)$type, "phone")
})

test_that("the summary has one row per flagged field", {
  summary <- pii_summary(pii_scan(survey()))
  expect_equal(anyDuplicated(summary$locator), 0L)
  expect_setequal(summary$name, personal)
  expect_equal(nrow(pii_summary(pii_scan(data.frame(x = 1:30)))), 0L)
})

test_that("the check stops on unreviewed findings and passes once allowed", {
  findings <- pii_scan(data.frame(village = paste("Village", 1:30)))
  expect_error(pii_check(findings), "possible personal data")
  expect_invisible(pii_check(findings, allow = "village"))
})

test_that("timestamps are not reported for being distinct", {
  stamps <- format(as.POSIXct("2026-01-05 09:00:00", tz = "UTC") + 61 * 1:30)
  expect_equal(nrow(pii_scan(data.frame(submitted = stamps))), 0L)
})

test_that("large columns are judged from distinct values within the sample", {
  codes <- data.frame(q1 = rep(c("yes", "no"), 5e4), q2 = paste0("p", 1:1e5, "@example.org"))
  elapsed <- system.time(findings <- pii_scan(codes, sample = 500))[["elapsed"]]
  expect_equal(findings$name, "q2")
  expect_equal(findings$n, 500L)
  expect_lt(elapsed, 5)
  expect_equal(pii_scan(codes, sample = Inf)$n, 100000L)
})

test_that("long strings that are not dates are not sent to the date parser", {
  keys <- data.frame(event = paste0("General Election|JAN-MAR 2020|block ", 1:5000))
  expect_lt(system.time(pii_scan(keys))[["elapsed"]], 5)
})

test_that("column types decide which checks run", {
  typed <- data.frame(flag = rep(c(TRUE, FALSE), 15), born = as.Date("1980-01-01") + 1:30)
  findings <- pii_scan(typed)
  expect_equal(unique(findings$name), "born")
  expect_true("birth_date" %in% findings$detector)
})

test_that("a name of a place or thing is not a person's name", {
  places <- data.frame(name_of_gram_panchayat = 1:30, survey_name = 1:30, school_name = 1:30)
  expect_equal(nrow(pii_scan(places)), 0L)
  expect_equal(pii_scan(data.frame(candidate_name = paste("Resp", 1:30)))$type[1], "person_name")
})

test_that("keys and precise numbers are not findings", {
  keys <- data.frame(
    match_key = paste0("ajmer_arain_gp", 1:40),
    log_assets = sprintf("%.6f", log(1000 + 1:40))
  )
  expect_equal(nrow(pii_scan(keys)), 0L)
})

test_that("low-confidence findings do not stop the check unless asked", {
  people <- data.frame(q2 = paste(c("Asha", "Ravi", "Meena", "Imran"), c("Devi", "Khan", "Rao")))
  findings <- pii_scan(people[rep(1:12, 3), , drop = FALSE])
  expect_equal(findings$confidence, "low")
  expect_invisible(pii_check(findings))
  expect_error(pii_check(findings, min_confidence = "low"), "possible personal data")
})

test_that("a suggestive name on a column of codes is weak evidence", {
  flags <- data.frame(phone_answered = rep(c("yes", "no"), 15), has_email = rep(0:1, 15))
  expect_equal(unique(pii_scan(flags)$confidence), "low")
  numbers <- data.frame(phone = sprintf("98765%05d", 1:30))
  expect_true("medium" %in% pii_scan(numbers)$confidence)
})

test_that("identity numbers with a valid checksum are strong evidence", {
  skip_if_not_installed("idcheck")
  body <- sprintf("%011.0f", 20000000000 + 7919 * 1:30)
  aadhaar <- paste0(body, idcheck::id_verhoeff_digit(body))
  findings <- pii_scan(data.frame(q8 = aadhaar))
  expect_true("in_aadhaar" %in% findings$type)
  expect_equal(findings$confidence[findings$type == "in_aadhaar"], "high")
  random <- pii_scan(data.frame(q8 = sprintf("%012.0f", 2e11 + 104729 * 1:30)))
  expect_false("in_aadhaar" %in% random$type)
})

phone_grade <- function(data) {
  findings <- pii_scan(data)
  findings$confidence[findings$type == "phone" & findings$evidence == "value"]
}

test_that("bare digits are weak evidence in a short, unnamed column", {
  digits <- sprintf("98765%05d", 1:40)
  expect_equal(phone_grade(data.frame(q7 = digits)), "low")
  expect_equal(phone_grade(data.frame(q7 = sprintf("98765%05d", 1:150))), "medium")
  expect_equal(phone_grade(data.frame(mobile = digits)), "medium")
})

test_that("a column only partly phone-like stays weak", {
  mixed <- c(sprintf("98765%05d", 1:120), sprintf("%04d", 1:40))
  expect_equal(phone_grade(data.frame(q7 = mixed)), "low")
})

test_that("numbers written as phone numbers need no other support", {
  expect_equal(phone_grade(data.frame(q7 = sprintf("+1 415 555 %04d", 1:20))), "medium")
  expect_equal(phone_grade(data.frame(q7 = sprintf("(415) 555-%04d ext", 1:20))), "medium")
  expect_equal(phone_grade(data.frame(q7 = sprintf("+44 20 7946 %04d", 1:20))), "medium")
})

with_regions <- function(regions) {
  path <- withr::local_tempfile(fileext = ".yml", .local_envir = parent.frame())
  writeLines(paste0("regions: [", paste(regions, collapse = ", "), "]"), path)
  pii_config(path)
}

phone_grade_in <- function(data, config) {
  findings <- pii_scan(data, config = config)
  findings$confidence[findings$type == "phone" & findings$evidence == "value"]
}

test_that("numbers valid in the project's region move up a grade", {
  skip_if_not_installed("dialtone")
  mobiles <- sprintf("98%08d", seq(1234567, by = 7919, length.out = 60))
  expect_equal(phone_grade_in(data.frame(q13 = mobiles), pii_config("none.yml")), "low")
  expect_equal(phone_grade_in(data.frame(q13 = mobiles), with_regions("IN")), "medium")
})

test_that("random ten-digit identifiers do not move up", {
  skip_if_not_installed("dialtone")
  withr::local_seed(1)
  ids <- sprintf("%010.0f", stats::runif(200, 1e9, 1e10))
  expect_equal(phone_grade_in(data.frame(q7 = ids), with_regions("IN")), "low")
})

test_that("numbers the numbering plan rejects are not phones", {
  skip_if_not_installed("dialtone")
  road <- paste("The road near house", 1:30, "is bad after the rains this year")
  note <- data.frame(note = c(road, "ref 0123456789"))
  phones <- function(config) sum(pii_scan(note, config = config)$type == "phone")
  expect_equal(phones(pii_config("none.yml")), 1L)
  expect_equal(phones(with_regions("IN")), 0L)
})

test_that("international numbers are judged without a region", {
  skip_if_not_installed("dialtone")
  valid <- sprintf("+44 20 7946 %04d", 1:40)
  expect_equal(phone_grade_in(data.frame(q7 = valid), pii_config("none.yml")), "high")
})

test_that("an unknown region is an error", {
  skip_if_not_installed("dialtone")
  path <- withr::local_tempfile(fileext = ".yml")
  writeLines("regions: [XX]", path)
  expect_error(pii_config(path), "Unknown region")
})
