test_that("dubois_relevel sets the reference level", {
  d <- data.frame(subject_race = c("white", "black", "hispanic", "black"))
  out <- dubois_relevel(d, "subject_race", ref = "white")
  expect_equal(levels(out$subject_race)[1], "white")
})

test_that("dubois_relevel errors on an unobserved reference level", {
  d <- data.frame(subject_race = c("white", "black"))
  expect_error(dubois_relevel(d, "subject_race", ref = "asian"), "not an observed level")
})

test_that("build_formula includes only selected controls", {
  control_map <- list(demographics = "subject_sex", poverty = "poverty_rate",
                       income = "median_income", time = "factor(hour)")

  f_none <- build_formula("search_conducted", "subject_race", control_map, character(0))
  expect_equal(deparse(f_none), "search_conducted ~ subject_race")

  f_some <- build_formula("search_conducted", "subject_race", control_map, c("demographics", "time"))
  expect_equal(deparse(f_some), "search_conducted ~ subject_race + subject_sex + factor(hour)")

  f_unknown_key <- build_formula("search_conducted", "subject_race", control_map, c("demographics", "nonexistent"))
  expect_equal(deparse(f_unknown_key), "search_conducted ~ subject_race + subject_sex")
})

test_that("fit_audit_glm computes Wald CIs matching a hand-computed value", {
  set.seed(1)
  n <- 200
  d <- data.frame(x = rnorm(n))
  d$y <- rbinom(n, 1, plogis(0.5 + 1.2 * d$x))

  fit <- fit_audit_glm(d, y ~ x, exponentiate = FALSE)
  s <- summary(fit$model)$coefficients
  z <- stats::qnorm(0.975)
  expected_low <- s["x", "Estimate"] - z * s["x", "Std. Error"]
  expected_high <- s["x", "Estimate"] + z * s["x", "Std. Error"]

  row <- fit$summary[fit$summary$term == "x", ]
  expect_equal(row$conf.low, expected_low, tolerance = 1e-8)
  expect_equal(row$conf.high, expected_high, tolerance = 1e-8)
})

test_that("fit_audit_glm exponentiates estimate and CI when requested", {
  set.seed(2)
  n <- 200
  d <- data.frame(x = rnorm(n))
  d$y <- rbinom(n, 1, plogis(0.3 - 0.5 * d$x))

  fit_log <- fit_audit_glm(d, y ~ x, exponentiate = FALSE)
  fit_exp <- fit_audit_glm(d, y ~ x, exponentiate = TRUE)

  row_log <- fit_log$summary[fit_log$summary$term == "x", ]
  row_exp <- fit_exp$summary[fit_exp$summary$term == "x", ]

  expect_equal(row_exp$estimate, exp(row_log$estimate), tolerance = 1e-8)
  expect_equal(row_exp$conf.low, exp(row_log$conf.low), tolerance = 1e-8)
  expect_equal(row_exp$conf.high, exp(row_log$conf.high), tolerance = 1e-8)
})
