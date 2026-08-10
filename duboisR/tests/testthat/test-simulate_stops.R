test_that("simulate_stops matches the real data contract's column set exactly", {
  d <- simulate_stops(n = 50)
  expected_cols <- c(
    "subject_race", "subject_sex", "search_conducted", "contraband_found",
    "hour", "date", "violation", "search_basis", "poverty_rate",
    "median_income", "county_fips"
  )
  expect_setequal(names(d), expected_cols)
  expect_false("subject_age" %in% names(d))
  expect_false("is_arrested" %in% names(d))
})

test_that("simulate_stops restricts subject_race to white/black/hispanic", {
  d <- simulate_stops(n = 500)
  expect_setequal(unique(d$subject_race), c("white", "black", "hispanic"))
})

test_that("simulate_stops's contraband_found is NA exactly when search_conducted is FALSE", {
  d <- simulate_stops(n = 1000)
  expect_true(all(is.na(d$contraband_found[!d$search_conducted])))
  expect_true(all(!is.na(d$contraband_found[d$search_conducted]) | sum(d$search_conducted) == 0))
})

test_that("simulate_stops's search_basis is NA exactly when search_conducted is FALSE", {
  d <- simulate_stops(n = 1000)
  expect_true(all(is.na(d$search_basis[!d$search_conducted])))
})

test_that("simulate_stops is reproducible under a fixed seed", {
  d1 <- simulate_stops(n = 100, seed = 7)
  d2 <- simulate_stops(n = 100, seed = 7)
  expect_equal(d1, d2)
})

test_that("simulate_stops's hour is an integer in [0, 23]", {
  d <- simulate_stops(n = 500)
  expect_true(all(d$hour >= 0 & d$hour <= 23))
})
