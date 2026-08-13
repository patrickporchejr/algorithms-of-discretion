test_that("summarize_county_vod_disparity computes the right ratio from a hand-built table", {
  # 2 counties, black/white only, exact counts chosen so pct_black and
  # vod_ratio are simple fractions to check by hand.
  d <- data.frame(
    county_fips = c(rep("48201", 8), rep("48113", 8)),
    is_dark = c(rep(FALSE, 4), rep(TRUE, 4), rep(FALSE, 4), rep(TRUE, 4)),
    subject_race = c(
      "black", "white", "white", "white",   # 48201 daylight: 1/4 black
      "black", "white", "white", "white",   # 48201 dark: 1/4 black
      "black", "black", "white", "white",   # 48113 daylight: 2/4 black
      "black", "black", "black", "white"    # 48113 dark: 3/4 black
    )
  )

  out <- summarize_county_vod_disparity(d)
  out <- out[order(out$county_fips), ]

  expect_equal(out$county_fips, c("48113", "48201"))
  expect_equal(out$pct_black_dark_FALSE, c(0.5, 0.25))
  expect_equal(out$pct_black_dark_TRUE, c(0.75, 0.25))
  expect_equal(out$total_n, c(8L, 8L))
  expect_equal(out$vod_ratio, c(0.75 / 0.5, 1))
})

test_that("summarize_county_vod_disparity excludes races other than black/white", {
  d <- data.frame(
    county_fips = "48201",
    is_dark = c(FALSE, FALSE, TRUE, TRUE),
    subject_race = c("black", "hispanic", "white", "hispanic")
  )
  out <- summarize_county_vod_disparity(d)
  # Only 1 black (daylight) and 1 white (dark) row survive the black/white
  # filter, one in each is_dark group -- pct_black is 1 and 0 respectively.
  expect_equal(out$pct_black_dark_FALSE, 1)
  expect_equal(out$pct_black_dark_TRUE, 0)
  expect_equal(out$total_n, 2L)
})

test_that("summarize_statewide_vod shares sum to 1 within each is_dark group", {
  d <- dubois_test_stops(2000)
  prepared <- suppressWarnings(prepare_veil_of_darkness_data(d))
  out <- summarize_statewide_vod(prepared$fit_data)

  totals <- stats::aggregate(share ~ is_dark, data = out, FUN = sum)
  expect_equal(totals$share, c(1, 1), tolerance = 1e-9)
})

test_that("summarize_statewide_vod_table pivots to one row per race with both periods", {
  d <- dubois_test_stops(2000)
  prepared <- suppressWarnings(prepare_veil_of_darkness_data(d))
  sw <- summarize_statewide_vod(prepared$fit_data)
  out <- summarize_statewide_vod_table(sw)

  expect_setequal(names(out), c("subject_race", "Before dark (daylight)", "After dark"))
  expect_setequal(out$subject_race, unique(sw$subject_race))
})

test_that("summarize_county_search_rates computes search_rate as n_searches / n_total, dropping NA outcomes", {
  d <- data.frame(
    county_fips = "48201", subject_race = "black",
    search_conducted = c(TRUE, FALSE, FALSE, NA)
  )
  out <- summarize_county_search_rates(d)
  expect_equal(out$n_searches, 1L)
  expect_equal(out$n_total, 3L) # the NA row is dropped, not counted
  expect_equal(out$search_rate, 1 / 3)
})

test_that("summarize_county_search_disparity computes disparity_ratio as black/white search rate", {
  rates <- tibble::tibble(
    county_fips = c("48201", "48201", "48113", "48113"),
    subject_race = c("black", "white", "black", "white"),
    n_searches = c(20L, 10L, 5L, 5L),
    n_total = c(100L, 100L, 100L, 100L),
    search_rate = c(0.2, 0.1, 0.05, 0.05)
  )
  out <- summarize_county_search_disparity(rates)
  out <- out[order(out$county_fips), ]

  expect_equal(out$county_fips, c("48113", "48201"))
  expect_equal(out$disparity_ratio, c(1, 2))
})

test_that("summarize_county_search_disparity drops a county missing either race", {
  rates <- tibble::tibble(
    county_fips = c("48201", "48113"),
    subject_race = c("black", "white"), # each county has only one race present
    n_searches = c(5L, 5L), n_total = c(50L, 50L), search_rate = c(0.1, 0.1)
  )
  out <- summarize_county_search_disparity(rates)
  expect_equal(nrow(out), 0L)
})

test_that("plot_county_vod_disparity/plot_statewide_vod/plot_county_search_disparity return ggplot objects", {
  d <- dubois_test_stops(2000)
  prepared <- suppressWarnings(prepare_veil_of_darkness_data(d))
  vd <- prepared$fit_data

  cvd <- summarize_county_vod_disparity(vd)
  sw <- summarize_statewide_vod(vd)
  csr <- summarize_county_search_rates(d)
  csd <- summarize_county_search_disparity(csr)

  expect_s3_class(plot_county_vod_disparity(cvd, min_n = 1), "ggplot")
  expect_s3_class(plot_statewide_vod(sw), "ggplot")
  expect_s3_class(plot_county_search_disparity(csd, min_n = 1), "ggplot")
})

test_that("plot_vod_search_combined returns a patchwork object combining both plots", {
  skip_if_not_installed("patchwork")
  d <- dubois_test_stops(2000)
  prepared <- suppressWarnings(prepare_veil_of_darkness_data(d))
  vd <- prepared$fit_data

  cvd <- summarize_county_vod_disparity(vd)
  csr <- summarize_county_search_rates(d)
  csd <- summarize_county_search_disparity(csr)

  combined <- plot_vod_search_combined(
    plot_county_vod_disparity(cvd, min_n = 1),
    plot_county_search_disparity(csd, min_n = 1)
  )
  expect_s3_class(combined, "patchwork")
})
