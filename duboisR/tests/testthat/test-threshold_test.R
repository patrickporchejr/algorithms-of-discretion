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

test_that("restrict_to_top_counties drops counties below min_stops", {
  d <- data.frame(county_fips = c(rep("A", 5), rep("B", 2)))
  out <- restrict_to_top_counties(d, min_stops = 3, top_n = 100)
  expect_equal(unique(out$county_fips), "A")
  expect_equal(nrow(out), 5)
})

test_that("restrict_to_top_counties keeps only the top_n largest eligible counties", {
  d <- data.frame(county_fips = c(rep("A", 5), rep("B", 4), rep("C", 3)))
  out <- restrict_to_top_counties(d, min_stops = 1, top_n = 2)
  expect_equal(sort(unique(out$county_fips)), c("A", "B"))
  expect_equal(nrow(out), 9)
})

test_that("restrict_to_top_counties with top_n = Inf keeps every eligible county", {
  d <- data.frame(county_fips = c(rep("A", 5), rep("B", 4), rep("C", 1)))
  out <- restrict_to_top_counties(d, min_stops = 2, top_n = Inf)
  expect_equal(sort(unique(out$county_fips)), c("A", "B"))
  expect_equal(nrow(out), 9)
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

.make_outcome_test_fixture <- function() {
  tibble::tibble(
    race = c("white", "white", "black", "black"),
    county_fips = c("A", "B", "A", "B"),
    n = c(100, 100, 100, 100),
    S = c(20, 20, 40, 40),
    H = c(10, 10, 12, 12),
    search_rate = S / n,
    hit_rate = H / S
  )
}

test_that("compute_outcome_test pools S/H across groups and computes the reference gap", {
  suff_stats <- .make_outcome_test_fixture()
  out <- compute_outcome_test(suff_stats, reference_race = "white")

  white_row <- out[out$race == "white", ]
  black_row <- out[out$race == "black", ]

  expect_equal(white_row$S, 40)
  expect_equal(white_row$H, 20)
  expect_equal(white_row$hit_rate, 0.5)
  expect_equal(white_row$hit_rate_gap, 0)

  expect_equal(black_row$hit_rate, 0.3)
  expect_equal(black_row$hit_rate_gap, 0.3 - 0.5)
})

test_that("compute_outcome_test errors informatively when reference_race is absent", {
  suff_stats <- .make_outcome_test_fixture()
  expect_error(compute_outcome_test(suff_stats, reference_race = "hispanic"), "not found among races")
})

test_that("compare_outcome_threshold_test flags sign agreement between the two gaps", {
  suff_stats <- .make_outcome_test_fixture()
  threshold_fit <- structure(
    list(summary = tibble::tibble(
      race = c("white", "black"),
      mean_threshold_weighted = c(0.4, 0.4), # equal -> threshold_gap = 0, hit_rate_gap < 0 -> signs differ
      n_counties = c(2, 2)
    )),
    class = "duboisR_threshold_fit"
  )

  cmp <- compare_outcome_threshold_test(suff_stats, threshold_fit, reference_race = "white")
  black_row <- cmp[cmp$race == "black", ]

  expect_equal(black_row$hit_rate_gap, 0.3 - 0.5)
  expect_equal(black_row$threshold_gap, 0)
  expect_false(black_row$agrees_in_direction)

  white_row <- cmp[cmp$race == "white", ]
  expect_true(white_row$agrees_in_direction) # both gaps are exactly 0 against itself
})

test_that("compare_outcome_threshold_test requires a duboisR_threshold_fit", {
  suff_stats <- .make_outcome_test_fixture()
  expect_error(
    compare_outcome_threshold_test(suff_stats, list(summary = tibble::tibble(race = "white"))),
    "fit_threshold_test"
  )
})

test_that("interpret_threshold_fit narrates thresholds relative to reference_race and flags degenerate/nonconverged fits", {
  threshold_fit <- structure(
    list(
      race_params = tibble::tibble(
        race = c("white", "black", "hispanic"),
        a = c(1e7, 2, 1e8), b = c(1e7, 8, 1e8),
        convergence_code = c(0, 1, 0)
      ),
      summary = tibble::tibble(
        race = c("white", "black", "hispanic"),
        mean_threshold_weighted = c(0.47, 0.48, 0.32),
        n_counties = c(100, 100, 100)
      )
    ),
    class = "duboisR_threshold_fit"
  )

  out <- interpret_threshold_fit(threshold_fit, reference_race = "white")
  expect_type(out, "character")
  expect_match(
    out, "Hispanic drivers' inferred threshold is 0.32, notably lower than White drivers' -- a lower bar to search",
    fixed = TRUE
  )
  expect_match(out, "Black drivers' inferred threshold is 0.48, about the same as White drivers'", fixed = TRUE)
  expect_match(out, "White and Hispanic's fitted risk distribution is near-degenerate", fixed = TRUE)
  expect_match(out, "Black's optimizer did not fully converge", fixed = TRUE)
})

test_that("interpret_threshold_fit omits caveats when nothing is degenerate or nonconverged", {
  threshold_fit <- structure(
    list(
      race_params = tibble::tibble(race = c("white", "black"), a = c(2, 3), b = c(8, 7), convergence_code = c(0, 0)),
      summary = tibble::tibble(race = c("white", "black"), mean_threshold_weighted = c(0.4, 0.4), n_counties = c(10, 10))
    ),
    class = "duboisR_threshold_fit"
  )
  out <- interpret_threshold_fit(threshold_fit, reference_race = "white")
  expect_false(grepl("Caution", out, fixed = TRUE))
})

test_that("interpret_outcome_threshold_comparison narrates hit-rate gaps and flags agreement", {
  comparison <- tibble::tibble(
    race = c("white", "black", "hispanic"),
    hit_rate = c(0.48, 0.48, 0.33),
    hit_rate_gap = c(0, 0.004, -0.151),
    mean_threshold_weighted = c(0.47, 0.49, 0.32),
    threshold_gap = c(0, 0.02, -0.15),
    agrees_in_direction = c(TRUE, TRUE, TRUE)
  )
  out <- interpret_outcome_threshold_comparison(comparison, reference_race = "white")
  expect_type(out, "character")
  expect_match(
    out, "Hispanic drivers' naive hit rate is 15 points lower than White drivers' -- the corrected Threshold Test agrees",
    fixed = TRUE
  )
})

test_that("interpret_outcome_threshold_comparison flags disagreement as an infra-marginality signal", {
  comparison <- tibble::tibble(
    race = c("white", "black"),
    hit_rate = c(0.48, 0.30),
    hit_rate_gap = c(0, -0.18),
    mean_threshold_weighted = c(0.47, 0.50),
    threshold_gap = c(0, 0.03),
    agrees_in_direction = c(TRUE, FALSE)
  )
  out <- interpret_outcome_threshold_comparison(comparison, reference_race = "white")
  expect_match(out, "disagrees -- a sign the naive gap may be an infra-marginality artifact", fixed = TRUE)
})

test_that("interpret_outcome_threshold_comparison errors when only reference_race is present", {
  comparison <- tibble::tibble(
    race = "white", hit_rate = 0.5, hit_rate_gap = 0, mean_threshold_weighted = 0.5, threshold_gap = 0,
    agrees_in_direction = TRUE
  )
  expect_error(interpret_outcome_threshold_comparison(comparison, reference_race = "white"), "no races other than reference_race")
})

.make_search_rate_fixture <- function() {
  tibble::tibble(
    county_fips = c("48201", "48201", "48201", "48113", "48113", "48113"),
    subject_race = c("black", "hispanic", "white", "black", "hispanic", "white"),
    n_searches = c(20L, 12L, 10L, 5L, 4L, 5L),
    n_total = c(100L, 100L, 100L, 100L, 100L, 100L),
    search_rate = c(0.2, 0.12, 0.1, 0.05, 0.04, 0.05)
  )
}

test_that("summarize_county_search_disparity computes every non-reference race's ratio vs. the reference", {
  rates <- .make_search_rate_fixture()
  out <- summarize_county_search_disparity(rates, reference_race = "white")
  out <- out[order(out$county_fips, out$subject_race), ]

  expect_setequal(out$subject_race, c("black", "hispanic"))
  black_48201 <- out[out$county_fips == "48201" & out$subject_race == "black", ]
  expect_equal(black_48201$disparity_ratio, 0.2 / 0.1)
  hispanic_48113 <- out[out$county_fips == "48113" & out$subject_race == "hispanic", ]
  expect_equal(hispanic_48113$disparity_ratio, 0.04 / 0.05)
})

test_that("summarize_county_search_disparity respects a different reference_race", {
  rates <- .make_search_rate_fixture()
  out <- summarize_county_search_disparity(rates, reference_race = "black")
  expect_setequal(out$subject_race, c("hispanic", "white"))
  white_48201 <- out[out$county_fips == "48201" & out$subject_race == "white", ]
  expect_equal(white_48201$disparity_ratio, 0.1 / 0.2)
})

test_that("summarize_county_search_disparity drops a county missing the reference race", {
  rates <- tibble::tibble(
    county_fips = c("48201", "48113"),
    subject_race = c("black", "white"), # each county has only one race present
    n_searches = c(5L, 5L), n_total = c(50L, 50L), search_rate = c(0.1, 0.1)
  )
  out <- summarize_county_search_disparity(rates, reference_race = "white")
  expect_equal(nrow(out), 0L)
})

test_that("plot_county_search_disparity returns a ggplot object", {
  rates <- .make_search_rate_fixture()
  csd <- summarize_county_search_disparity(rates, reference_race = "white")
  expect_s3_class(plot_county_search_disparity(csd, min_n = 1), "ggplot")
})

test_that("interpret_search_rate_disparity narrates every race's median ratio vs. the reference", {
  csd <- summarize_county_search_disparity(.make_search_rate_fixture(), reference_race = "white")
  out <- interpret_search_rate_disparity(csd, min_n = 1, reference_race = "white")
  expect_type(out, "character")
  # Black's disparity_ratio is 2.0 in county 48201 (0.2/0.1) and 1.0 in
  # 48113 (0.05/0.05) -- median of those two is 1.5.
  expect_match(out, "the typical county searches Black drivers at 1.50× the rate of White drivers", fixed = TRUE)
  expect_match(out, "the typical county searches Hispanic drivers at", fixed = TRUE)
})
