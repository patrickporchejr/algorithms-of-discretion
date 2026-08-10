test_that("audit_composition's representation percentages sum to ~100", {
  d <- dubois_test_stops(200)
  comp <- audit_composition(d, "subject_race")
  expect_equal(sum(comp$representation$pct), 100, tolerance = 1e-8)
})

test_that("audit_composition's missingness matches known NA placement", {
  d <- data.frame(
    group = c("a", "a", "a", "b", "b"),
    outcome = c(1, NA, 1, NA, NA)
  )
  comp <- audit_composition(d, "group", missing_col = "outcome")
  a_row <- comp$missingness[comp$missingness$group == "a", ]
  b_row <- comp$missingness[comp$missingness$group == "b", ]
  expect_equal(a_row$n_missing, 1)
  expect_equal(a_row$n_total, 3)
  expect_equal(b_row$n_missing, 2)
  expect_equal(b_row$n_total, 2)
  expect_equal(b_row$pct_missing, 100)
})

test_that("audit_composition supports intersectional group_col", {
  d <- data.frame(
    race = c("white", "white", "black", "black"),
    sex = c("male", "female", "male", "female")
  )
  comp <- audit_composition(d, c("race", "sex"))
  expect_setequal(comp$representation$group, c("white_male", "white_female", "black_male", "black_female"))
  expect_true(all(comp$representation$n == 1))
})

test_that("audit_composition without missing_col returns NULL missingness", {
  d <- dubois_test_stops(50)
  comp <- audit_composition(d, "subject_race")
  expect_null(comp$missingness)
})

test_that("format.duboisR_composition returns Markdown text", {
  d <- dubois_test_stops(50)
  comp <- audit_composition(d, "subject_race", missing_col = "contraband_found")
  out <- format(comp)
  expect_true(any(grepl("Representation", out)))
  expect_true(any(grepl("Missingness", out)))
})
