coordinates_in <- function(data) {
  found <- pii_scan(data, config = pii_config("none.yml"))
  sort(found$name[found$detector == "coordinate_pair"])
}

test_that("latitude and longitude in neighboring columns are a pair", {
  withr::local_seed(1)
  data <- data.frame(
    id = 1:40, q7 = round(26 + stats::runif(40), 6), q8 = round(75 + stats::runif(40), 6),
    price = round(stats::runif(40, 1, 50), 2)
  )
  expect_equal(coordinates_in(data), c("q7", "q8"))
})

test_that("a lone precise column, or two longitudes, is not a pair", {
  withr::local_seed(2)
  lone <- data.frame(q7 = round(26 + stats::runif(40), 6), q8 = sample(letters, 40, TRUE))
  expect_length(coordinates_in(lone), 0L)
  far <- data.frame(q7 = round(120 + stats::runif(40), 6), q8 = round(150 + stats::runif(40), 6))
  expect_length(coordinates_in(far), 0L)
})

test_that("columns named as rates or prices are never coordinates", {
  withr::local_seed(3)
  rates <- data.frame(
    fx_usd = round(stats::runif(40, 0.8, 0.9), 6), fx_eur = round(stats::runif(40, 1, 1.2), 6)
  )
  expect_length(coordinates_in(rates), 0L)
  unnamed <- stats::setNames(rates, c("q1", "q2"))
  expect_equal(coordinates_in(unnamed), c("q1", "q2"))
})

test_that("one place repeated on every row is still a place", {
  data <- data.frame(q1 = rep("53.508987", 20), q2 = rep("-113.431055", 20))
  expect_equal(coordinates_in(data), c("q1", "q2"))
})

test_that("columns of different sheets are not paired", {
  fields <- rbind(
    as_pii_fields(data.frame(a = round(26 + (1:20) / 1000, 6)), source = "x.xlsx"),
    as_pii_fields(data.frame(b = round(75 + (1:20) / 1000, 6)), source = "y.xlsx")
  )
  expect_length(detect_coordinate_pairs(fields), 0L)
})
