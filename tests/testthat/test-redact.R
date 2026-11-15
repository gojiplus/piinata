test_that("pseudonyms keep shape, repeat for equal values and are not the original", {
  clean <- pii_redact(people(), method = "pseudonym", key = "k1")
  expect_equal(nchar(clean$email), nchar(people()$email))
  expect_true(all(grepl("^[a-z]+[0-9]+@[a-z]+\\.[a-z]+$", clean$email)))
  expect_equal(length(unique(clean$email)), 20L)
  expect_equal(clean$email[1:20], clean$email[21:40])
  expect_false(any(clean$email %in% people()$email))
  expect_true(all(grepl("^[0-9]{10}$", clean$phone)))
})

test_that("the same key joins across files and a different key does not", {
  first <- pii_redact(people()[1:20, ], method = "pseudonym", key = "k1")
  second <- pii_redact(people()[21:40, ], method = "pseudonym", key = "k1")
  other <- pii_redact(people()[21:40, ], method = "pseudonym", key = "k2")
  expect_equal(first$email, second$email)
  expect_false(any(first$email == other$email))
})

test_that("unflagged columns are untouched", {
  clean <- pii_redact(people())
  expect_equal(clean$id, people()$id)
  expect_equal(clean$income, people()$income)
})

test_that("free text loses only the matched spans", {
  clean <- pii_redact(people(), method = "pseudonym", key = "k1")
  expect_equal(clean$note[1], "The road is bad after the rains")
  expect_match(clean$note[4], "^Call me on [0-9]{10} after six$")
  expect_false(clean$note[4] == people()$note[4])
})

test_that("methods can be chosen by type", {
  clean <- pii_redact(people(), method = c(email = "placeholder", phone = "mask", default = "drop"))
  expect_equal(unique(clean$email), "<EMAIL>")
  expect_true(all(grepl("^98[9]{8}$", clean$phone)))
  expect_false("village" %in% names(clean))
  actions <- attr(clean, "redactions")
  expect_equal(actions$method[actions$name == "village"], "drop")
})

test_that("missing values stay missing", {
  data <- people()
  data$email[3] <- NA
  expect_true(is.na(pii_redact(data, method = "pseudonym", key = "k1")$email[3]))
  expect_true(is.na(pii_redact(data)$email[3]))
})

test_that("an unknown method is an error", {
  expect_error(pii_redact(people(), method = "shred"), "must be one of")
})

test_that("pseudonyms need a key", {
  expect_error(pii_redact(people(), method = "pseudonym"), "secret")
  expect_error(pii_redact(people(), method = c(email = "pseudonym", default = "drop")), "secret")
  expect_no_error(pii_redact(people(), method = "placeholder"))
})

test_that("every match in a cell is replaced, not only the first", {
  data <- data.frame(note = c(
    paste("The road near house", 1:30, "is bad after the long rains this year"),
    "write to a@example.org or b@example.org, or call 98765 43210 or 91234 56789"
  ))
  clean <- pii_redact(data)
  expect_equal(clean$note[31], "write to <EMAIL> or <EMAIL>, or call <PHONE> or <PHONE>")
  expect_equal(clean$note[1:30], data$note[1:30])
})

test_that("fields allowed in the configuration are not redacted", {
  config <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("allow:", "  - field: village", "    reason: Needed for clustering."), config)
  findings <- pii_scan(people(), config = pii_config(config))
  clean <- pii_redact(people(), findings, method = "drop")
  expect_true("village" %in% names(clean))
  expect_false("email" %in% names(clean))
})

test_that("variable labels survive redaction", {
  data <- people()
  attr(data$email, "label") <- "Email address"
  expect_equal(attr(pii_redact(data)$email, "label"), "Email address")
})
