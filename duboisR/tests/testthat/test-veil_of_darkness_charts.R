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

test_that("plot_county_vod_disparity/plot_statewide_vod return ggplot objects", {
  d <- dubois_test_stops(2000)
  prepared <- suppressWarnings(prepare_veil_of_darkness_data(d))
  vd <- prepared$fit_data

  cvd <- summarize_county_vod_disparity(vd)
  sw <- summarize_statewide_vod(vd)

  expect_s3_class(plot_county_vod_disparity(cvd, min_n = 1), "ggplot")
  expect_s3_class(plot_statewide_vod(sw), "ggplot")
})

test_that("interpret_county_vod_disparity reads the median ratio and % of counties above daylight", {
  d <- tibble::tibble(
    county_fips = c("A", "B", "C"), total_n = c(100, 100, 100), vod_ratio = c(1.0, 1.04, 0.96)
  )
  out <- interpret_county_vod_disparity(d, min_n = 30)
  expect_type(out, "character")
  expect_match(out, "n ≥ 30", fixed = TRUE)
  expect_match(out, "1.00×", fixed = TRUE)
  expect_match(out, "close to unchanged", fixed = TRUE)
})

test_that("interpret_county_vod_disparity flags a notable shift instead of 'close to unchanged'", {
  d <- tibble::tibble(
    county_fips = c("A", "B"), total_n = c(100, 100), vod_ratio = c(0.6, 0.6)
  )
  out <- interpret_county_vod_disparity(d, min_n = 30)
  expect_match(out, "notably lower after dark", fixed = TRUE)
})

test_that("interpret_statewide_vod identifies the race with the largest before/after-dark shift", {
  d <- tibble::tibble(
    subject_race = c("white", "black", "hispanic"),
    `Before dark (daylight)` = c(0.44, 0.10, 0.46),
    `After dark` = c(0.46, 0.12, 0.42)
  )
  out <- interpret_statewide_vod(d)
  expect_type(out, "character")
  expect_match(out, "Hispanic drivers get stopped 4 points less", fixed = TRUE)
  expect_match(out, "Black drivers get stopped 2 points more", fixed = TRUE)
  expect_match(out, "clearest shift is Hispanic drivers, who are pulled over less at night", fixed = TRUE)
})

test_that("interpret_statewide_vod handles a factor race column (dubois_relevel's output type)", {
  d <- tibble::tibble(
    subject_race = factor(c("white", "black", "hispanic"), levels = c("white", "black", "hispanic")),
    `Before dark (daylight)` = c(0.44, 0.10, 0.46),
    `After dark` = c(0.46, 0.12, 0.42)
  )
  out <- interpret_statewide_vod(d)
  expect_match(out, "Hispanic drivers get stopped 4 points less", fixed = TRUE)
})

test_that("interpret_statewide_vod flags a small largest shift as not a strong change", {
  d <- tibble::tibble(
    subject_race = c("white", "black"),
    `Before dark (daylight)` = c(0.50, 0.50),
    `After dark` = c(0.505, 0.495)
  )
  out <- interpret_statewide_vod(d)
  expect_match(out, "under 2 points")
})

