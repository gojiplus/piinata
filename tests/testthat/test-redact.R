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

test_that("obfuscated matches are redacted where the scan found them (D1)", {
  filler <- paste("The road near house", 1:20, "is bad after the long rains this year")
  data <- data.frame(note = c(
    filler, "write ａｂｃ@example.org today please", "info&#64;example.org please",
    "mail jo​hn@example.org now"
  ))
  clean <- pii_redact(data)
  expect_equal(clean$note[1:20], filler)
  expect_false(any(grepl("example", clean$note[21:23])))
  expect_true(all(grepl("<EMAIL>", clean$note[21:23])))
})

test_that("pseudonyms replace letters of every script (D2)", {
  out <- pseudonym(c("रमेश कुमार", "李小龙"), "k")
  expect_false(any(grepl("[ऀ-ॿ一-鿿]", out)))
  expect_match(out[1], "^[a-z]+ [a-z]+$")
})

test_that("pseudonyms rarely collide and do not depend on the session's RNG (D3, D4)", {
  ids <- sprintf("%010d", seq_len(50000) * 7919L)
  expect_gte(length(unique(pseudonym(ids, "k"))), 49990L)
  default <- pseudonym(c("9876543210", "jane@example.org"), "k")
  withr::with_preserve_seed({
    RNGkind("L'Ecuyer-CMRG")
    other <- pseudonym(c("9876543210", "jane@example.org"), "k")
    RNGkind("default", "default", "default")
  })
  expect_equal(other, default)
})

test_that("redaction follows the configuration's min_confidence (D13)", {
  path <- withr::local_tempfile(fileext = ".yml")
  writeLines("min_confidence: low", path)
  data <- data.frame(q = paste("answer number", 1:30, "says something else"))
  findings <- pii_scan(data, config = pii_config(path))
  expect_gt(nrow(attr(pii_redact(data, findings), "redactions")), 0L)
})

test_that("a card number in free text is a financial account, redacted whole (C1)", {
  skip_if_not("intl_payment_card" %in% idcheck::id_schemes()$scheme)
  filler <- paste("The road near house", 1:20, "is bad after the long rains this year")
  data <- data.frame(note = c(filler, "card 4111 1111 1111 1111 thanks for the help"))
  found <- pii_scan(data, config = pii_config("none.yml"))
  expect_true("financial_account" %in% found$type)
  expect_false("phone" %in% found$type)
  expect_equal(pii_redact(data, found)$note[21], "card <FINANCIAL_ACCOUNT> thanks for the help")
})
