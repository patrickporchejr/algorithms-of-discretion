test_that("veil_of_darkness_module() errors on chart methods before $init()", {
  vod <- veil_of_darkness_module()
  expect_false(vod$initialized)
  expect_error(vod$plot_county_vod(), "Call \\$init\\(\\)")
})

test_that("$init() populates every documented field and chart methods build the plots/tables", {
  d <- dubois_test_stops(3000)
  tmp <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(d, tmp)

  vod <- veil_of_darkness_module()
  expect_invisible(vod$init(data_path = tmp))
  expect_true(vod$initialized)

  expect_equal(nrow(vod$stops), nrow(d))
  expect_true(all(c("subject_race", "county_fips") %in% names(vod$stops)))
  expect_true(is.data.frame(vod$county_centroids))
  expect_true(all(c("is_dark", "sunset", "dusk") %in% names(vod$stops_geo)))
  expect_true(all(c("sunset", "dusk") %in% names(vod$sun_times)))
  expect_true(all(!is.na(vod$vod_data$is_dark)))
  expect_true(is.data.frame(vod$county_vod_disparity))
  expect_true(is.data.frame(vod$statewide_vod))

  expect_null(vod$vod_plot)
  expect_s3_class(vod$plot_county_vod(min_n = 1), "ggplot")
  expect_identical(vod$vod_plot, vod$plot_county_vod(min_n = 1))

  expect_s3_class(vod$plot_statewide(), "ggplot")
  expect_true(is.data.frame(vod$statewide_table))
})

test_that("$fit_regression() errors before $init() and fits the interaction model by default after", {
  vod <- veil_of_darkness_module()
  expect_error(vod$fit_regression(), "Call \\$init\\(\\)")

  d <- dubois_test_stops(3000)
  tmp <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(d, tmp)
  vod$init(data_path = tmp)

  expect_null(vod$regression_fit)
  fit <- vod$fit_regression()
  expect_s3_class(fit, "duboisR_vod_result")
  expect_identical(vod$regression_fit, fit)
  expect_true(any(grepl(":is_dark", fit$model_fit$summary$term)))

  additive <- vod$fit_regression(interaction = FALSE)
  expect_false(any(grepl(":is_dark", additive$model_fit$summary$term)))
})

test_that("print.duboisR_vod_module reports initialization and chart-build state", {
  vod <- veil_of_darkness_module()
  expect_output(print(vod), "not yet initialized")

  d <- dubois_test_stops(2000)
  tmp <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(d, tmp)
  vod$init(data_path = tmp)

  expect_output(print(vod), "stops loaded")
  expect_output(print(vod), "\\(none yet\\)")
  vod$plot_county_vod(min_n = 1)
  expect_output(print(vod), "vod_plot")
})
