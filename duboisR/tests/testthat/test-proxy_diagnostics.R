.make_proxy_fixture <- function(n = 400, seed = 1) {
  set.seed(seed)
  # county perfectly determines race (near-perfect proxy)
  county_race_map <- c(A = "white", B = "black", C = "hispanic", D = "white")
  county <- sample(names(county_race_map), n, replace = TRUE)
  race <- unname(county_race_map[county])
  noise <- stats::rnorm(n) # unrelated to race
  data.frame(subject_race = race, county_fips = county, noise = noise, stringsAsFactors = FALSE)
}

test_that("check_proxies flags a near-perfect proxy (method = 'glm')", {
  d <- .make_proxy_fixture()
  res <- check_proxies(d, protected_attr = "subject_race", predictors = "county_fips",
                        method = "glm", seed = 42)
  expect_true(res$flagged)
  expect_gt(res$lift, 0.10)
})

test_that("check_proxies does not flag an independent covariate (method = 'glm')", {
  set.seed(2)
  n <- 400
  d <- data.frame(
    subject_race = sample(c("white", "black", "hispanic"), n, replace = TRUE),
    noise = stats::rnorm(n)
  )
  res <- check_proxies(d, protected_attr = "subject_race", predictors = "noise",
                        method = "glm", seed = 42)
  expect_false(res$flagged)
})

test_that("check_proxies errors if protected_attr is included in predictors", {
  d <- .make_proxy_fixture()
  expect_error(
    check_proxies(d, protected_attr = "subject_race", predictors = c("subject_race", "county_fips"), method = "glm"),
    "must not include"
  )
})

test_that("check_proxies works with method = 'rf' when ranger is installed", {
  testthat::skip_if_not_installed("ranger")
  d <- .make_proxy_fixture()
  res <- check_proxies(d, protected_attr = "subject_race", predictors = "county_fips",
                        method = "rf", seed = 42)
  expect_true(res$flagged)
})

test_that("format.duboisR_proxy_check returns Markdown text", {
  d <- .make_proxy_fixture()
  res <- check_proxies(d, protected_attr = "subject_race", predictors = "county_fips", method = "glm", seed = 42)
  out <- format(res)
  expect_true(any(grepl("Identity proxy check", out)))
})
