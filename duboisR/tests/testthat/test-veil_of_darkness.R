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

test_that("fit_veil_of_darkness layers extra control terms onto the base formula", {
  d <- dubois_test_stops(2000)
  set.seed(3)
  d$county_fips <- sample(c("48201", "48113", "48453"), nrow(d), replace = TRUE)
  d <- dubois_relevel(d, "subject_race", ref = "white")
  prepared <- suppressWarnings(prepare_veil_of_darkness_data(d))

  control_map <- list(demographics = "subject_sex", poverty = "poverty_rate")

  bare <- fit_veil_of_darkness(prepared, interaction = TRUE)
  expect_false("subject_sexmale" %in% bare$model_fit$summary$term)

  with_controls <- fit_veil_of_darkness(
    prepared, interaction = TRUE,
    control_map = control_map, controls_selected = c("demographics", "poverty")
  )
  expect_true("subject_sexmale" %in% with_controls$model_fit$summary$term)
  expect_true("poverty_rate" %in% with_controls$model_fit$summary$term)
  # unselected map entries are dropped, same as build_formula()
  expect_false("median_income" %in% with_controls$model_fit$summary$term)
})

test_that("interpret_veil_regression narrates significant vs. non-significant race:is_dark terms", {
  fake_fit <- list(
    model_fit = list(
      summary = tibble::tibble(
        term = c(
          "(Intercept)", "subject_raceblack", "subject_racehispanic", "is_darkTRUE",
          "subject_raceblack:is_darkTRUE", "subject_racehispanic:is_darkTRUE"
        ),
        estimate = c(0.013, 1.954, 1.312, 1.020, 0.953, 0.868),
        conf.low = c(0.012, 1.797, 1.237, 0.950, 0.850, 0.797),
        conf.high = c(0.014, 2.125, 1.391, 1.096, 1.069, 0.944),
        p.value = c(0, 0, 0, 0.588, 0.411, 0.001)
      )
    )
  )

  out <- interpret_veil_regression(fake_fit)
  expect_type(out, "character")
  expect_match(out, "hispanic drivers")
  expect_match(out, "shrinks by about 13%")
  expect_match(out, "unlikely to be chance")
  expect_match(out, "black drivers")
  expect_match(out, "crosses 1")
})

test_that("interpret_veil_regression errors informatively without interaction terms", {
  fake_fit <- list(model_fit = list(summary = tibble::tibble(
    term = "is_darkTRUE", estimate = 1, conf.low = 0.9, conf.high = 1.1, p.value = 0.5
  )))
  expect_error(interpret_veil_regression(fake_fit), "interaction = TRUE")
})
