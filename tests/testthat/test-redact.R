people <- function() {
  data.frame(
    id = 1:40,
    email = paste0("person", rep(1:20, 2), "@example.org"),
    phone = sprintf("98765%05d", rep(1:20, 2)),
    village = rep(c("Palpur", "Netrad"), 20),
    note = ifelse(1:40 %% 4 == 0, paste("Call me on", sprintf("98765%05d", 1:40), "after six"),
      "The road is bad after the rains"
    ),
    income = 2000 + 1:40
  )
}

test_that("pseudonyms keep shape, repeat for equal values and are not the original", {
  clean <- pii_redact(people(), key = "k1")
  expect_equal(nchar(clean$email), nchar(people()$email))
  expect_true(all(grepl("^[a-z]+[0-9]+@[a-z]+\\.[a-z]+$", clean$email)))
  expect_equal(length(unique(clean$email)), 20L)
  expect_equal(clean$email[1:20], clean$email[21:40])
  expect_false(any(clean$email %in% people()$email))
  expect_true(all(grepl("^[0-9]{10}$", clean$phone)))
})

test_that("the same key joins across files and a different key does not", {
  first <- pii_redact(people()[1:20, ], key = "k1")
  second <- pii_redact(people()[21:40, ], key = "k1")
  other <- pii_redact(people()[21:40, ], key = "k2")
  expect_equal(first$email, second$email)
  expect_false(any(first$email == other$email))
})

test_that("unflagged columns are untouched", {
  clean <- pii_redact(people())
  expect_equal(clean$id, people()$id)
  expect_equal(clean$income, people()$income)
})

test_that("free text loses only the matched spans", {
  clean <- pii_redact(people(), key = "k1")
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
  expect_true(is.na(pii_redact(data)$email[3]))
  expect_true(is.na(pii_redact(data, method = "placeholder")$email[3]))
})

test_that("an unknown method is an error", {
  expect_error(pii_redact(people(), method = "shred"), "must be one of")
})
