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
  expect_true(is.data.frame(vod$county_search_rates))
  expect_true(is.data.frame(vod$county_search_disparity))

  expect_null(vod$vod_plot)
  expect_s3_class(vod$plot_county_vod(min_n = 1), "ggplot")
  expect_identical(vod$vod_plot, vod$plot_county_vod(min_n = 1))

  expect_s3_class(vod$plot_statewide(), "ggplot")
  expect_true(is.data.frame(vod$statewide_table))

  expect_s3_class(vod$plot_search_rate(min_n = 1), "ggplot")
})

test_that("$plot_combined() lazily builds the county/search plots it depends on", {
  skip_if_not_installed("patchwork")
  d <- dubois_test_stops(3000)
  tmp <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(d, tmp)

  vod <- veil_of_darkness_module()
  vod$init(data_path = tmp)
  expect_null(vod$vod_plot)
  expect_null(vod$search_rate_plot)

  combined <- vod$plot_combined()
  expect_s3_class(combined, "patchwork")
  expect_false(is.null(vod$vod_plot))
  expect_false(is.null(vod$search_rate_plot))
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
