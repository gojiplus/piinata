test_that("dirty values are cleaned before patterns run", {
  zero_width <- "​"
  no_break <- " "
  dirty <- data.frame(
    q1 = paste0("person", 1:20, zero_width, "@example.org"),
    q2 = paste0("98765", no_break, sprintf("%05d", 1:20)),
    q3 = paste0("९८७६५", sprintf("%05d", 1:20))
  )
  findings <- pii_scan(dirty)
  expect_equal(findings$type[findings$name == "q1"][1], "email")
  expect_true("phone" %in% findings$type[findings$name == "q2"])
  expect_true("phone" %in% findings$type[findings$name == "q3"])
})

test_that("normalizing leaves ordinary text alone", {
  text <- c("Asha Devi", "आशा देवी", "café", NA)
  expect_equal(normalize_values(text), text)
  expect_equal(normalize_values("  two   spaces "), "two spaces")
})
