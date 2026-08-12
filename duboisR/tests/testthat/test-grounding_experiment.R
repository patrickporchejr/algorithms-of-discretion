# A small, self-contained 3-question fixture -- deliberately not the real
# grounding_questions() battery, so these tests stay stable if the real
# question bank's wording changes. grounding_questions() itself is checked
# separately below, structurally rather than by exact content.
test_questions <- list(
  q_bool = list(type = "boolean", prompt = "Is X true?", expected_answer = "TRUE", rationale = "because X"),
  q_enum = list(
    type = "enum", prompt = "Pick one.",
    choices = c(a = "Option A", b = "Option B"),
    expected_answer = "a", rationale = "because A"
  ),
  q_numeric = list(
    type = "numeric", prompt = "How many?", unit = "as a plain number",
    expected_answer = "10", tolerance = 2, rationale = "because 10"
  )
)

test_that("grounding_questions returns a well-formed, internally consistent battery", {
  qs <- grounding_questions()
  expect_true(length(qs) > 0)
  for (q in qs) {
    expect_true(q$type %in% c("boolean", "enum", "numeric"))
    expect_type(q$prompt, "character")
    expect_type(q$expected_answer, "character")
    expect_type(q$rationale, "character")
    if (q$type == "enum") {
      expect_false(is.null(q$choices))
      expect_true(q$expected_answer %in% names(q$choices))
    } else if (q$type == "numeric") {
      expect_false(is.na(suppressWarnings(as.numeric(q$expected_answer))))
      expect_true(is.numeric(q$tolerance) && q$tolerance >= 0)
      expect_type(q$unit, "character")
    } else {
      expect_true(q$expected_answer %in% c("TRUE", "FALSE"))
    }
  }
})

test_that("build_data_context reports row/column counts and the sample size", {
  df <- dubois_test_stops(n = 10)
  ctx <- build_data_context(df, n_sample = 5, seed = 1)
  expect_true(grepl("10 rows", ctx, fixed = TRUE))
  expect_true(grepl(paste0(ncol(df), " columns"), ctx, fixed = TRUE))
  expect_true(grepl("Random sample of 5 rows", ctx, fixed = TRUE))
})

test_that("build_data_context caps the sample at nrow(data)", {
  df <- dubois_test_stops(n = 3)
  ctx <- build_data_context(df, n_sample = 20, seed = 1)
  expect_true(grepl("Random sample of 3 rows", ctx, fixed = TRUE))
})

test_that("build_grounding_prompt's naive condition excludes the datasheet", {
  prompt <- build_grounding_prompt("naive", "Dataset: 10 rows, 2 columns.", test_questions)
  expect_false(grepl("datasheet.json", prompt$user, fixed = TRUE))
  expect_true(grepl("Is X true?", prompt$user, fixed = TRUE))
})

test_that("build_grounding_prompt's grounded condition requires and embeds the datasheet", {
  expect_error(
    build_grounding_prompt("grounded", "ctx", test_questions),
    "datasheet.*required"
  )

  ds <- read_datasheet(testthat::test_path("fixtures", "datasheet_example.json"))
  prompt <- build_grounding_prompt("grounded", "ctx", test_questions, datasheet = ds)
  expect_true(grepl("datasheet.json", prompt$user, fixed = TRUE))
  expect_true(grepl(ds$motivation$purpose, prompt$user, fixed = TRUE))
})

test_that("build_grounding_prompt formats boolean, enum, and numeric question instructions distinctly", {
  prompt <- build_grounding_prompt("naive", "ctx", test_questions)
  expect_true(grepl('answer exactly "TRUE" or "FALSE"', prompt$user, fixed = TRUE))
  expect_true(grepl("multiple choice", prompt$user, fixed = TRUE))
  expect_true(grepl('"a": Option A', prompt$user, fixed = TRUE))
  expect_true(grepl("numeric -- answer with a plain number, as a plain number", prompt$user, fixed = TRUE))
})

test_that("build_grounding_prompt asks for a per-question confidence score", {
  prompt <- build_grounding_prompt("naive", "ctx", test_questions)
  expect_true(grepl("confidence", prompt$user, fixed = TRUE))
  expect_true(grepl("0", prompt$user, fixed = TRUE))
  expect_true(grepl("100", prompt$user, fixed = TRUE))
})

test_that("score_answer does exact match for boolean/enum and tolerance-band match for numeric", {
  expect_true(score_answer("boolean", "TRUE", "TRUE", NA))
  expect_false(score_answer("boolean", "FALSE", "TRUE", NA))
  expect_true(score_answer("enum", "a", "a", NA))
  expect_false(score_answer("enum", "b", "a", NA))

  expect_true(score_answer("numeric", "10", "10", 2))
  expect_true(score_answer("numeric", "12", "10", 2)) # exactly at the tolerance boundary
  expect_false(score_answer("numeric", "13", "10", 2))
  expect_false(score_answer("numeric", "not a number", "10", 2))
})

test_that("run_grounding_experiment aborts when `models` is missing a requested provider", {
  expect_error(
    run_grounding_experiment("irrelevant.csv", "irrelevant.json", providers = "anthropic", models = list(), questions = test_questions),
    "missing an entry"
  )
})

test_that("run_grounding_experiment aborts when no datasheet exists at datasheet_path", {
  tmp_csv <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(dubois_test_stops(n = 5), tmp_csv)

  expect_error(
    run_grounding_experiment(
      tmp_csv, "does/not/exist.json",
      providers = "anthropic", models = list(anthropic = "test-model"), questions = test_questions
    ),
    "No datasheet found"
  )
})

test_that("run_grounding_experiment scores naive vs. grounded answers against expected_answer, and parses confidence", {
  tmp_csv <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(dubois_test_stops(n = 5), tmp_csv)
  fixture_datasheet <- testthat::test_path("fixtures", "datasheet_example.json")

  # A fake provider that answers correctly only when it can see the
  # datasheet content in the prompt -- i.e. only in the "grounded" condition.
  mock_call <- function(system, user, schema, model, api_key = "fake") {
    if (grepl("datasheet.json", user, fixed = TRUE)) {
      list(
        q_bool = list(answer = "TRUE", confidence = 90),
        q_enum = list(answer = "a", confidence = 85),
        q_numeric = list(answer = 10, confidence = 80)
      )
    } else {
      list(
        q_bool = list(answer = "FALSE", confidence = 40),
        q_enum = list(answer = "b", confidence = 30),
        q_numeric = list(answer = 999, confidence = 20)
      )
    }
  }
  testthat::local_mocked_bindings(call_anthropic = mock_call)

  result <- run_grounding_experiment(
    tmp_csv, fixture_datasheet,
    providers = "anthropic", models = list(anthropic = "test-model"), questions = test_questions
  )

  expect_s3_class(result, "duboisR_grounding_result")
  r <- result$results
  expect_equal(nrow(r), 6) # 3 questions x 2 conditions x 1 trial
  expect_true(all(r$trial == 1))
  expect_setequal(r$condition, c("naive", "grounded"))

  naive_rows <- r[r$condition == "naive", ]
  grounded_rows <- r[r$condition == "grounded", ]
  expect_false(any(naive_rows$correct))
  expect_true(all(grounded_rows$correct))
  expect_equal(naive_rows$confidence[naive_rows$question_id == "q_bool"], 40)
  expect_equal(grounded_rows$confidence[grounded_rows$question_id == "q_bool"], 90)

  expect_no_error(format(result))
  expect_no_error(print(result))
})

test_that("run_grounding_experiment with n_repeats runs multiple independent trials per condition", {
  tmp_csv <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(dubois_test_stops(n = 5), tmp_csv)
  fixture_datasheet <- testthat::test_path("fixtures", "datasheet_example.json")

  call_count <- 0
  mock_call <- function(system, user, schema, model, api_key = "fake") {
    call_count <<- call_count + 1
    list(
      q_bool = list(answer = "TRUE", confidence = 50),
      q_enum = list(answer = "a", confidence = 50),
      q_numeric = list(answer = 10, confidence = 50)
    )
  }
  testthat::local_mocked_bindings(call_anthropic = mock_call)

  result <- run_grounding_experiment(
    tmp_csv, fixture_datasheet,
    providers = "anthropic", models = list(anthropic = "test-model"),
    questions = test_questions, n_repeats = 3
  )

  expect_equal(call_count, 6) # 2 conditions x 3 trials
  r <- result$results
  expect_equal(nrow(r), 18) # 3 questions x 2 conditions x 3 trials
  expect_setequal(r$trial, c(1, 2, 3))
})

test_that("summarize_grounding_trials collapses repeats into a modal answer, accuracy, agreement, and mean confidence", {
  results <- tibble::tibble(
    provider = "anthropic", model = "test-model", condition = "naive", trial = c(1, 2, 3),
    question_id = "q1", type = "boolean", prompt = "Is X true?",
    answer = c("TRUE", "TRUE", "FALSE"), confidence = c(60, 80, 40),
    expected_answer = "TRUE", correct = c(TRUE, TRUE, FALSE), rationale = "because X"
  )

  summarized <- summarize_grounding_trials(results)
  expect_equal(nrow(summarized), 1)
  expect_equal(summarized$modal_answer, "TRUE")
  expect_equal(summarized$accuracy, 2 / 3)
  expect_equal(summarized$agreement, 2 / 3) # 2 of 3 trials matched the modal answer "TRUE"
  expect_equal(summarized$mean_confidence, 60)
  expect_equal(summarized$n_trials, 3)
})

test_that("summarize_grounding_trials handles a question with no non-NA answer in any trial without dropping its row", {
  # Regression test: a provider that never successfully answers one specific
  # question across every trial (answer always NA) makes table(answer) a
  # zero-length table. This must produce an explicit NA row, not silently
  # vanish the question from the summary (the previous rbind()-of-per-row-
  # tibbles implementation did the latter, and separately could crash with
  # "numbers of columns of arguments do not match" -- see grounding_experiment.R).
  results <- tibble::tibble(
    provider = c("anthropic", "anthropic", "openai", "openai"),
    model = "test-model", condition = "naive", trial = c(1, 2, 1, 2),
    question_id = c("q_missing", "q_missing", "q_ok", "q_ok"),
    type = "boolean", prompt = c("Is X true?", "Is X true?", "Is Y true?", "Is Y true?"),
    answer = c(NA_character_, NA_character_, "TRUE", "TRUE"),
    confidence = c(NA_real_, NA_real_, 90, 90),
    expected_answer = "TRUE", correct = c(FALSE, FALSE, TRUE, TRUE),
    rationale = c("because X", "because X", "because Y", "because Y")
  )

  summarized <- summarize_grounding_trials(results)
  expect_equal(nrow(summarized), 2) # both questions present, not just q_ok
  missing_row <- summarized[summarized$question_id == "q_missing", ]
  expect_true(is.na(missing_row$modal_answer))
  expect_true(is.na(missing_row$agreement))
  expect_equal(missing_row$n_trials, 2)
  expect_equal(missing_row$accuracy, 0)

  ok_row <- summarized[summarized$question_id == "q_ok", ]
  expect_equal(ok_row$modal_answer, "TRUE")
  expect_equal(ok_row$agreement, 1)
})

test_that("format.duboisR_grounding_result excludes unanswered questions from aggregates instead of reporting NA", {
  # Regression test: a single unanswered question anywhere in the battery
  # must not poison the top-line "mean stability" / "changed answer" stats
  # to NA for the whole report -- mean()/sum() without na.rm = TRUE do
  # exactly that when even one input is NA.
  results <- tibble::tibble(
    provider = "anthropic", model = "test-model",
    condition = rep(c("naive", "grounded"), each = 4), trial = rep(c(1, 2, 1, 2), 2),
    question_id = rep(c("q_missing", "q_missing", "q_ok", "q_ok"), 2),
    type = "boolean", prompt = rep(c("Is X true?", "Is X true?", "Is Y true?", "Is Y true?"), 2),
    answer = c(NA_character_, NA_character_, "FALSE", "FALSE", NA_character_, NA_character_, "TRUE", "TRUE"),
    confidence = c(NA_real_, NA_real_, 40, 40, NA_real_, NA_real_, 90, 90),
    expected_answer = rep(c("TRUE", "TRUE"), each = 4),
    correct = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE),
    rationale = "because"
  )
  result <- structure(list(results = results), class = "duboisR_grounding_result")

  out <- paste(format(result), collapse = "\n")
  expect_false(grepl("NA%", out, fixed = TRUE))
  expect_true(grepl("stability across trials: 100.0%", out, fixed = TRUE)) # only q_ok is comparable, and it's fully stable
  expect_true(grepl("excluded from that comparison", out, fixed = TRUE))
  expect_true(grepl("1 question/provider pair\\(s\\) excluded", out))
})
