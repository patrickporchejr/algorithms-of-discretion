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

test_that("predicted_probabilities returns one row per level, including the reference", {
  d <- data.frame(subject_race = c("white", "white", "black", "black", "hispanic", "hispanic"))
  d$search_conducted <- c(0, 0, 1, 1, 0, 1)
  d <- dubois_relevel(d, "subject_race", ref = "white")

  fit <- fit_audit_glm(d, search_conducted ~ subject_race)
  out <- predicted_probabilities(fit, d, "subject_race")

  expect_setequal(out$level, c("white", "black", "hispanic"))
  expect_true(all(out$probability >= 0 & out$probability <= 1))
  expect_true(all(out$conf.low <= out$probability & out$probability <= out$conf.high))
})

test_that("predicted_probabilities matches a hand-computed probability at the mean of a numeric control", {
  set.seed(3)
  n <- 300
  d <- data.frame(
    subject_race = sample(c("white", "black"), n, replace = TRUE),
    poverty_rate = runif(n, 0.05, 0.30)
  )
  d$search_conducted <- rbinom(n, 1, plogis(-2 + 0.8 * (d$subject_race == "black") + 3 * d$poverty_rate))
  d <- dubois_relevel(d, "subject_race", ref = "white")

  fit <- fit_audit_glm(d, search_conducted ~ subject_race + poverty_rate)
  out <- predicted_probabilities(fit, d, "subject_race")

  coefs <- stats::coef(fit$model)
  mean_poverty <- mean(d$poverty_rate)
  expected_white <- plogis(coefs[["(Intercept)"]] + coefs[["poverty_rate"]] * mean_poverty)
  expected_black <- plogis(coefs[["(Intercept)"]] + coefs[["subject_raceblack"]] + coefs[["poverty_rate"]] * mean_poverty)

  expect_equal(unname(out$probability[out$level == "white"]), unname(expected_white), tolerance = 1e-8)
  expect_equal(unname(out$probability[out$level == "black"]), unname(expected_black), tolerance = 1e-8)
})

test_that("predicted_probabilities uses the mode, not the mean, for a factor()-wrapped numeric control", {
  set.seed(4)
  n <- 500
  d <- data.frame(
    subject_race = sample(c("white", "black"), n, replace = TRUE),
    hour = sample(0:23, n, replace = TRUE)
  )
  d$search_conducted <- rbinom(n, 1, plogis(-2 + 0.5 * (d$subject_race == "black")))
  d <- dubois_relevel(d, "subject_race", ref = "white")

  fit <- fit_audit_glm(d, search_conducted ~ subject_race + factor(hour))
  # mean(hour) is a non-integer (e.g. 11.7) that factor(hour) never saw during
  # fitting -- predict() used to hard-error with "has new levels" here.
  out <- expect_no_error(predicted_probabilities(fit, d, "subject_race"))

  mode_hour <- as.integer(names(sort(table(d$hour), decreasing = TRUE))[1])
  coefs <- stats::coef(fit$model)
  hour_term <- paste0("factor(hour)", mode_hour)
  hour_coef <- if (hour_term %in% names(coefs)) coefs[[hour_term]] else 0
  expected_white <- plogis(coefs[["(Intercept)"]] + hour_coef)

  expect_equal(unname(out$probability[out$level == "white"]), unname(expected_white), tolerance = 1e-8)
})
