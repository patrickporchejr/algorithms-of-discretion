test_that("check_tendentious flags subjective/administrative classifications", {
  res <- check_tendentious("search_conducted", classification = "administrative", interactive = FALSE)
  expect_true(res$is_tendentious)

  res2 <- check_tendentious("lab_measurement", classification = "subjective", interactive = FALSE)
  expect_true(res2$is_tendentious)
})

test_that("check_tendentious does not flag objective classifications", {
  res <- check_tendentious("speed_radar_reading", classification = "objective", interactive = FALSE)
  expect_false(res$is_tendentious)
})

test_that("check_tendentious errors when non-interactive with no classification", {
  expect_error(
    check_tendentious("search_conducted", interactive = FALSE),
    "must be supplied"
  )
})

test_that("check_tendentious validates classification against the allowed set", {
  expect_error(
    check_tendentious("x", classification = "not_a_real_class", interactive = FALSE)
  )
})

test_that("check_tendentious carries a rationale through when supplied", {
  res <- check_tendentious("search_conducted", classification = "administrative",
                            rationale = "officer discretion", interactive = FALSE)
  expect_equal(res$rationale, "officer discretion")
})

test_that("format.duboisR_tendentious_check includes the classification, message, and rationale", {
  res <- check_tendentious("search_conducted", classification = "administrative",
                            rationale = "officer discretion", interactive = FALSE)
  out <- format(res)
  expect_true(any(grepl("administrative", out)))
  expect_true(any(grepl("officer discretion", out)))
  expect_true(any(grepl(res$message, out, fixed = TRUE)))
})

test_that("format.duboisR_tendentious_check omits the rationale line when none was given", {
  res <- check_tendentious("speed_radar_reading", classification = "objective", interactive = FALSE)
  out <- format(res)
  expect_false(any(grepl("Rationale:", out)))
})
