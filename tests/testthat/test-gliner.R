entity <- function(label, start, end) {
  list(list(label = label, start = start, end = end, score = 0.9))
}

test_that("a value takes the label of an entity covering most of it", {
  values <- c("Ramesh Kumar", "Palpur Khurd", "call Ramesh Kumar tomorrow", "nothing")
  predictions <- list(
    entity("person", 0L, 12L), entity("location", 0L, 12L), entity("person", 5L, 17L), list()
  )
  expect_equal(covering_label(values, predictions), c("person", "location", NA, NA))
})

heuristic <- function() {
  list(finding("person_name", "value", "person_name", 40, 1, "Asha Devi", "low"))
}

test_that("columns of people gain a finding graded by how much of the column they fill", {
  labels <- stats::setNames(c("person", "person", "person", "person", NA), letters[1:5])
  found <- vote_entities(heuristic(), labels, rep(1, 5), 0.5)
  expect_length(found, 1L)
  expect_equal(found[[1]]$detector, "gliner")
  expect_equal(found[[1]]$confidence, "medium")
  labels[3:4] <- NA
  expect_equal(vote_entities(list(), labels, rep(1, 5), 0.5), list())
  labels[3] <- "person"
  expect_equal(vote_entities(list(), labels, rep(1, 5), 0.5)[[1]]$confidence, "low")
})

test_that("columns of places withdraw the rules' person-name finding", {
  labels <- stats::setNames(c("location", "location", "organization", NA), letters[1:4])
  expect_equal(vote_entities(heuristic(), labels, rep(1, 4), 0.5), list())
})

test_that("numbers and gender words do not vote", {
  expect_equal(not_names(c("1", "Asha Devi"), c(1, 1)), c(TRUE, FALSE))
  expect_true(all(not_names(c("Male", "Female", "male"), c(5, 4, 1))))
})

test_that("votes are weighted by rows", {
  labels <- stats::setNames(c("person", NA), c("a", "b"))
  expect_length(vote_entities(list(), labels, c(1, 9), 0.5), 0L)
  expect_length(vote_entities(list(), labels, c(9, 1), 0.5), 1L)
})

test_that("only uncertain short text columns are reviewed", {
  field <- as_pii_fields(data.frame(q1 = paste("Person", 1:10)))
  values <- field$values[[1]]
  expect_true(uncertain(field, list(), values))
  strong <- list(finding("email", "value", "email", 10, 1, "a@b.org", "high"))
  expect_false(uncertain(field, strong, values))
  numbers <- as_pii_fields(data.frame(q1 = 1:10))
  expect_false(uncertain(numbers, list(), as.character(1:10)))
})

# Downloads Python packages and a 1 GB model, so it runs only when the
# environment variable PIINATA_TEST_GLINER is "true".
test_that("GLiNER tells people from places", {
  skip_on_cran()
  asked <- identical(Sys.getenv("PIINATA_TEST_GLINER"), "true")
  skip_if_not(asked, "PIINATA_TEST_GLINER is not set")
  skip_if_not_installed("reticulate")
  use_gliner()
  withr::defer(use_gliner(FALSE))
  config <- pii_config("none.yml")
  people <- data.frame(q15 = rep(c(
    "Ramesh Kumar", "James Smith", "sunita devi", "Maria Garcia", "Imran Khan", "Linda Lee"
  ), 5))
  places <- data.frame(q32 = rep(c(
    "Palpur Khurd", "Ajgara Kalan", "Netrad Nagar", "Konra Pura", "Biliya Dhani", "Sewali Gaon"
  ), 5))
  expect_equal(pii_scan(people, config = config)$confidence, "medium")
  expect_equal(nrow(pii_scan(places, config = config)), 0L)
})
