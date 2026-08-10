test_that("aggregate_sufficient_statistics computes correct n/S/H on a hand-constructed data frame", {
  d <- data.frame(
    subject_race = c("white", "white", "white", "black", "black"),
    county_fips = c("A", "A", "A", "A", "A"),
    search_conducted = c(TRUE, TRUE, FALSE, TRUE, TRUE),
    contraband_found = c(TRUE, FALSE, NA, TRUE, TRUE)
  )
  out <- aggregate_sufficient_statistics(d, min_n = 1)
  white_row <- out[out$race == "white", ]
  black_row <- out[out$race == "black", ]

  expect_equal(white_row$n, 3)
  expect_equal(white_row$S, 2)
  expect_equal(white_row$H, 1)
  expect_equal(white_row$search_rate, 2 / 3)
  expect_equal(white_row$hit_rate, 1 / 2)

  expect_equal(black_row$n, 2)
  expect_equal(black_row$S, 2)
  expect_equal(black_row$H, 2)
})

test_that("aggregate_sufficient_statistics drops cells below min_n", {
  d <- data.frame(
    subject_race = c("white", "black"),
    county_fips = c("A", "B"),
    search_conducted = c(TRUE, TRUE),
    contraband_found = c(TRUE, FALSE)
  )
  out <- aggregate_sufficient_statistics(d, min_n = 5)
  expect_equal(nrow(out), 0)
})

test_that("aggregate_sufficient_statistics's output column is named after group_col", {
  d <- data.frame(
    subject_race = "white", county_fips = "A",
    search_conducted = TRUE, contraband_found = TRUE
  )
  out <- aggregate_sufficient_statistics(d, min_n = 1)
  expect_true("county_fips" %in% names(out))
})

.make_threshold_fixture <- function(true_a = 2, true_b = 8, n_counties = 25, n_rd = 500, seed = 42) {
  desired_search_rates <- seq(0.1, 0.6, length.out = n_counties)
  thr <- stats::qbeta(1 - desired_search_rates, true_a, true_b)
  S_rd <- round(n_rd * desired_search_rates)
  true_hit_rate <- (true_a / (true_a + true_b)) *
    (1 - stats::pbeta(thr, true_a + 1, true_b)) / desired_search_rates
  set.seed(seed)
  H_rd <- stats::rbinom(n_counties, S_rd, true_hit_rate)

  suff_stats <- tibble::tibble(
    race = "testrace", county_fips = paste0("C", seq_len(n_counties)),
    n = n_rd, S = S_rd, H = H_rd,
    search_rate = S_rd / n_rd, hit_rate = H_rd / S_rd
  )
  attr(suff_stats, "group_col") <- "county_fips"
  class(suff_stats) <- c("duboisR_suff_stats", class(suff_stats))
  suff_stats
}

test_that("fit_threshold_test recovers (a, b) from data simulated with known parameters", {
  true_a <- 2; true_b <- 8
  suff_stats <- .make_threshold_fixture(true_a, true_b)

  fit <- fit_threshold_test(suff_stats, min_searches = 5)

  expect_equal(fit$race_params$a, true_a, tolerance = 0.5)
  expect_equal(fit$race_params$b, true_b, tolerance = 2)
  expect_equal(fit$race_params$convergence_code, 0)

  # thresholds/group column carries the original group_col name through
  expect_true("county_fips" %in% names(fit$thresholds))
  expect_equal(nrow(fit$thresholds), 25)
  expect_false(any(fit$thresholds$low_confidence))
})

test_that("fit_threshold_test errors informatively with fewer than 2 qualifying counties", {
  suff_stats <- tibble::tibble(
    race = "testrace", county_fips = "C1",
    n = 100, S = 50, H = 10, search_rate = 0.5, hit_rate = 0.2
  )
  attr(suff_stats, "group_col") <- "county_fips"
  expect_error(fit_threshold_test(suff_stats, min_searches = 5), "at least 2 are required")
})

test_that("fit_threshold_test flags cells below min_searches as low_confidence", {
  suff_stats <- .make_threshold_fixture(n_rd = 500)
  suff_stats$S[1] <- 2 # below default min_searches = 5
  suff_stats$search_rate[1] <- suff_stats$S[1] / suff_stats$n[1]
  fit <- fit_threshold_test(suff_stats, min_searches = 5)
  expect_true(fit$thresholds$low_confidence[1])
})
