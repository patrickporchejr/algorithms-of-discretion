test_that("subpopulation_disparities matches hand-computed TPR/FPR/PPV for an intercept-only model", {
  d <- data.frame(
    group_col1 = c("a", "a", "a", "a", "b", "b", "b", "b"),
    y = c(1, 1, 0, 0, 1, 0, 1, 0)
  )
  model <- stats::glm(y ~ 1, data = d, family = "binomial")

  res <- subpopulation_disparities(model, d, actual_col = "y", subgroup_cols = "group_col1",
                                    threshold = 0.5, filter_search_only = FALSE)

  a_row <- res[res$group == "a", ]
  b_row <- res[res$group == "b", ]

  # predicted prob is a constant 0.5 for every row (intercept-only fit);
  # threshold = 0.5 with >= means every row is predicted positive.
  expect_equal(a_row$n, 4)
  expect_equal(a_row$base_rate, 0.5)
  expect_equal(a_row$TPR, 1)   # TP=2, FN=0
  expect_equal(a_row$FPR, 1)   # FP=2, TN=0
  expect_equal(a_row$PPV, 0.5) # TP=2, FP=2

  expect_equal(b_row$TPR, 1)
  expect_equal(b_row$FPR, 1)
  expect_equal(b_row$PPV, 0.5)
})

test_that("subpopulation_disparities accepts a duboisR_glm_fit directly", {
  d <- dubois_test_stops(200)
  fit <- fit_audit_glm(d, search_conducted ~ subject_race)
  res <- subpopulation_disparities(fit, d, actual_col = "search_conducted", subgroup_cols = "subject_race")
  expect_true(all(c("group", "n", "base_rate", "TPR", "FPR", "PPV") %in% names(res)))
})

test_that("filter_search_only auto-enables for contraband_found and auto-disables otherwise", {
  d <- dubois_test_stops(500)
  fit <- fit_audit_glm(d, search_conducted ~ subject_race)

  res_search <- subpopulation_disparities(fit, d, actual_col = "search_conducted", subgroup_cols = "subject_race")
  expect_false(grepl("Filtered to", attr(res_search, "notes")[2]))

  fit2 <- fit_audit_glm(d[d$search_conducted, ], contraband_found ~ subject_race)
  res_contraband <- subpopulation_disparities(fit2, d, actual_col = "contraband_found", subgroup_cols = "subject_race")
  expect_true(grepl("Filtered to", attr(res_contraband, "notes")[2]))
  expect_true(all(res_contraband$n <= sum(d$search_conducted)))
})

test_that("subpopulation_disparities supports intersectional subgroup_cols", {
  d <- dubois_test_stops(300)
  fit <- fit_audit_glm(d, search_conducted ~ subject_race + subject_sex)
  res <- subpopulation_disparities(fit, d, actual_col = "search_conducted",
                                    subgroup_cols = c("subject_race", "subject_sex"))
  expect_true(any(grepl("_", res$group)))
})

test_that("subpopulation_disparities drops NA-outcome rows before scoring instead of propagating NA", {
  # Administrative data (e.g. the real Texas dataset, where ~38% of
  # search_conducted is NA rather than FALSE) can leave the outcome
  # unreported for some rows; glm() silently na.omit()s these when fitting,
  # but scoring must apply the same drop or every group's sum()/mean()
  # comes back NA/NaN (see subpop_disparities.R's na.rm = FALSE note).
  d <- data.frame(
    group_col1 = c("a", "a", "a", "a", "b", "b", "b", "b"),
    y = c(1, 1, 0, NA, 1, 0, 1, NA)
  )
  model <- stats::glm(y ~ 1, data = d, family = "binomial")

  res <- subpopulation_disparities(model, d, actual_col = "y", subgroup_cols = "group_col1",
                                    threshold = 0.5, filter_search_only = FALSE)

  a_row <- res[res$group == "a", ]
  b_row <- res[res$group == "b", ]

  expect_equal(a_row$n, 3)
  expect_equal(a_row$base_rate, 2 / 3)
  expect_equal(a_row$TPR, 1)
  expect_equal(a_row$PPV, 2 / 3)

  expect_equal(b_row$n, 3)
  expect_equal(b_row$base_rate, 2 / 3)

  expect_true(any(grepl("Dropped 2 of 8 rows with NA y", attr(res, "notes"))))
})

test_that("subpopulation_disparities's notes state the fairness-metrics trade-off", {
  d <- data.frame(group_col1 = c("a", "a", "b", "b"), y = c(1, 0, 1, 0))
  model <- stats::glm(y ~ 1, data = d, family = "binomial")
  res <- subpopulation_disparities(model, d, actual_col = "y", subgroup_cols = "group_col1", filter_search_only = FALSE)
  expect_true(any(grepl("cannot generally equalize", attr(res, "notes"))))
})
