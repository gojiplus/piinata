test_that("personal columns are found and keyword traps are not", {
  findings <- pii_scan(survey())
  expect_setequal(unique(findings$name), personal)
})

test_that("values give a column away when its name does not", {
  findings <- pii_scan(survey())
  by_value <- findings[findings$evidence == "value", ]
  expect_equal(by_value$type[by_value$name == "q12"], "email")
  expect_equal(by_value$type[by_value$name == "q13"], "phone")
  expect_equal(by_value$type[by_value$name == "q15"], "person_name")
})

test_that("names match on whole words only", {
  traps <- data.frame(reason = 1:30, season = 1:30, latrine = 1:30, relation = 1:30)
  expect_equal(nrow(pii_scan(traps)), 0L)
  expect_equal(pii_scan(data.frame(firstName = 1:30))$type, "person_name")
  expect_equal(pii_scan(data.frame(GPS_Lat = 1:30))$type, "coordinates")
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
  findings <- pii_scan(data.frame(village = rep(c("A", "B"), 15)))
  expect_error(pii_check(findings), "possible personal data")
  expect_invisible(pii_check(findings, allow = "village"))
})

test_that("timestamps are not reported for being distinct", {
  stamps <- format(as.POSIXct("2026-01-05 09:00:00", tz = "UTC") + 61 * 1:30)
  expect_equal(nrow(pii_scan(data.frame(submitted = stamps))), 0L)
})
