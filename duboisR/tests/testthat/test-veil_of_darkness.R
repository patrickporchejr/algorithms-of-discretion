test_that("compute_daylight_status correctly classifies known daylight/twilight/dark triples", {
  # Harris County, TX (48201; lat 29.857273, lon -95.393037), 2016-01-03:
  # sunset = 17:35:19, dusk = 18:01:30 (verified via suncalc::getSunlightTimes()).
  d <- data.frame(
    county_fips = rep("48201", 3),
    date = as.Date("2016-01-03"),
    hour = c(17L, 18L, 19L)
  )
  out <- compute_daylight_status(d)
  expect_equal(as.character(out$light_condition), c("daylight", "twilight", "dark"))
  expect_equal(out$is_dark, c(FALSE, NA, TRUE))
})

test_that("compute_daylight_status warns and returns NA for an unmatched county", {
  d <- data.frame(county_fips = "99999", date = as.Date("2016-01-03"), hour = 12L)
  expect_warning(out <- compute_daylight_status(d), "no centroid match")
  expect_true(is.na(out$light_condition))
})

test_that("veil_of_darkness_test's intertwilight filter excludes always-dark and always-daylight hours", {
  # Harris County, hour 3 is dark year-round; hour 13 is daylight year-round;
  # hour 18 crosses from daylight (June) to dark (December) -- intertwilight.
  dates <- rep(as.Date(c("2016-06-15", "2016-12-15")), each = 3)
  hours <- rep(c(3L, 13L, 18L), times = 2)
  n <- length(dates)
  # explicit (not random) so both races and both outcome values are
  # guaranteed present in the hour == 18 subset the intertwilight filter keeps
  d <- data.frame(
    subject_race = rep(c("white", "black", "white", "black", "white", "black"), length.out = n),
    county_fips = "48201",
    date = dates,
    hour = hours,
    search_conducted = rep(c(TRUE, FALSE), length.out = n)
  )
  # pad with repeats so the GLM has enough rows/variation to fit cleanly
  d <- do.call(rbind, replicate(20, d, simplify = FALSE))

  res <- veil_of_darkness_test(d, race_ref = "white")
  expect_setequal(res$diagnostics$hours_used, 18L)
  expect_false(3L %in% res$diagnostics$hours_used)
  expect_false(13L %in% res$diagnostics$hours_used)
})

test_that("veil_of_darkness_test's caveats always include the nonreporting and hour-resolution notes", {
  d <- dubois_test_stops(2000)
  set.seed(3)
  d$county_fips <- sample(c("48201", "48113", "48453"), nrow(d), replace = TRUE)
  res <- suppressWarnings(veil_of_darkness_test(d))
  expect_true(any(grepl("reporting rates", res$caveats)))
  expect_true(any(grepl("hour only", res$caveats)))
})
