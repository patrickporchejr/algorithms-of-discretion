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

test_that("extract_answer_field returns the named field from a well-formed entry", {
  expect_equal(extract_answer_field(list(answer = "TRUE", confidence = 90), "answer"), "TRUE")
  expect_equal(extract_answer_field(list(answer = "TRUE", confidence = 90), "confidence"), 90)
})

test_that("extract_answer_field returns NULL, not an error, for a missing field or a non-list entry", {
  expect_null(extract_answer_field(list(answer = "TRUE"), "confidence"))
  expect_null(extract_answer_field(NULL, "answer"))
  # Regression test: a provider that doesn't strictly honor the forced
  # {answer, confidence} object schema and instead returns a bare scalar
  # for a question (e.g. answers$q1 <- "TRUE" instead of
  # answers$q1 <- list(answer = "TRUE", confidence = 90)) used to crash
  # run_grounding_experiment() with "$ operator is invalid for atomic
  # vectors" -- see grounding_experiment.R.
  expect_null(extract_answer_field("TRUE", "answer"))
  expect_null(extract_answer_field(42, "answer"))
})

test_that("run_grounding_experiment tolerates a provider returning a bare scalar instead of {answer, confidence} for one question", {
  tmp_csv <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(dubois_test_stops(n = 5), tmp_csv)
  fixture_datasheet <- testthat::test_path("fixtures", "datasheet_example.json")

  # q_bool comes back schema-conforming; q_enum comes back as a bare string
  # (not nested under answer/confidence) -- simulates a provider that
  # doesn't strictly honor the forced tool schema for every field.
  mock_call <- function(system, user, schema, model, api_key = "fake") {
    list(
      q_bool = list(answer = "TRUE", confidence = 90),
      q_enum = "a",
      q_numeric = list(answer = 10, confidence = 80)
    )
  }
  testthat::local_mocked_bindings(call_anthropic = mock_call)

  result <- run_grounding_experiment(
    tmp_csv, fixture_datasheet,
    providers = "anthropic", models = list(anthropic = "test-model"), questions = test_questions
  )

  r <- result$results
  q_enum_rows <- r[r$question_id == "q_enum", ]
  expect_true(all(is.na(q_enum_rows$answer)))
  expect_true(all(is.na(q_enum_rows$confidence)))
  expect_false(any(q_enum_rows$correct)) # NA answer never scores correct

  q_bool_rows <- r[r$question_id == "q_bool", ]
  expect_equal(q_bool_rows$answer, rep("TRUE", nrow(q_bool_rows)))
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

test_that("run_grounding_experiment resumes from a checkpoint instead of re-calling already-completed trials", {
  tmp_csv <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(dubois_test_stops(n = 5), tmp_csv)
  fixture_datasheet <- testthat::test_path("fixtures", "datasheet_example.json")
  checkpoint <- withr::local_tempfile(fileext = ".rds")

  call_count <- 0
  # Fails on the 3rd call (of 4: naive trial 1, naive trial 2, grounded
  # trial 1, grounded trial 2) -- simulates a crash partway through a run.
  flaky_call <- function(system, user, schema, model, api_key = "fake") {
    call_count <<- call_count + 1
    if (call_count == 3) stop("simulated transient failure")
    list(
      q_bool = list(answer = "TRUE", confidence = 50),
      q_enum = list(answer = "a", confidence = 50),
      q_numeric = list(answer = 10, confidence = 50)
    )
  }
  testthat::local_mocked_bindings(call_anthropic = flaky_call)

  expect_error(
    run_grounding_experiment(
      tmp_csv, fixture_datasheet,
      providers = "anthropic", models = list(anthropic = "test-model"),
      questions = test_questions, n_repeats = 2, checkpoint_path = checkpoint
    ),
    "simulated transient failure"
  )
  expect_true(file.exists(checkpoint))
  expect_equal(call_count, 3) # crashed on the 3rd call, so only 2 succeeded

  # Second run resumes: the first 2 calls are served from the checkpoint,
  # so only the 2 remaining trials (the one that crashed, plus the last one)
  # actually call the (now-fixed) provider function.
  call_count <- 0
  reliable_call <- function(system, user, schema, model, api_key = "fake") {
    call_count <<- call_count + 1
    list(
      q_bool = list(answer = "TRUE", confidence = 50),
      q_enum = list(answer = "a", confidence = 50),
      q_numeric = list(answer = 10, confidence = 50)
    )
  }
  testthat::local_mocked_bindings(call_anthropic = reliable_call)

  result <- run_grounding_experiment(
    tmp_csv, fixture_datasheet,
    providers = "anthropic", models = list(anthropic = "test-model"),
    questions = test_questions, n_repeats = 2, checkpoint_path = checkpoint
  )
  expect_equal(call_count, 2) # only the 2 not-yet-completed trials were called
  expect_equal(nrow(result$results), 12) # 3 questions x 2 conditions x 2 trials, all present
})

test_that("run_grounding_experiment treats a checkpoint with zero rows the same as no checkpoint", {
  tmp_csv <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(dubois_test_stops(n = 5), tmp_csv)
  fixture_datasheet <- testthat::test_path("fixtures", "datasheet_example.json")
  checkpoint <- withr::local_tempfile(fileext = ".rds")
  saveRDS(tibble::tibble(), checkpoint) # empty results, e.g. from a run that crashed immediately

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
    questions = test_questions, checkpoint_path = checkpoint
  )
  expect_equal(call_count, 2) # naive + grounded, nothing skipped
  expect_equal(nrow(result$results), 6)
})

test_that("run_grounding_experiment's restart = TRUE ignores an existing checkpoint", {
  tmp_csv <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(dubois_test_stops(n = 5), tmp_csv)
  fixture_datasheet <- testthat::test_path("fixtures", "datasheet_example.json")
  checkpoint <- withr::local_tempfile(fileext = ".rds")

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

  run_grounding_experiment(
    tmp_csv, fixture_datasheet,
    providers = "anthropic", models = list(anthropic = "test-model"),
    questions = test_questions, checkpoint_path = checkpoint
  )
  expect_equal(call_count, 2)

  run_grounding_experiment(
    tmp_csv, fixture_datasheet,
    providers = "anthropic", models = list(anthropic = "test-model"),
    questions = test_questions, checkpoint_path = checkpoint, restart = TRUE
  )
  expect_equal(call_count, 4) # restart = TRUE re-called both, ignoring the full checkpoint
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

test_that("plot_grounding_accuracy returns a ggplot with one bar per provider/condition", {
  summarized <- tibble::tibble(
    provider = rep(c("anthropic", "openai"), each = 2),
    condition = rep(c("naive", "grounded"), 2),
    accuracy = c(0.5, 1, 0.75, 0.75)
  )
  p <- plot_grounding_accuracy(summarized)
  expect_s3_class(p, "ggplot")
  expect_equal(nrow(p$data), 4)
})

test_that("interpret_grounding_accuracy narrates which providers improved, worsened, or stayed the same", {
  summarized <- tibble::tibble(
    provider = rep(c("anthropic", "openai", "gemini"), each = 2),
    condition = rep(c("naive", "grounded"), 3),
    accuracy = c(0.5, 1, 1, 0.5, 0.5, 0.5)
  )
  out <- interpret_grounding_accuracy(summarized)
  expect_true(grepl("Anthropic got more accurate", out, fixed = TRUE))
  expect_true(grepl("Openai got less accurate", out, fixed = TRUE))
  expect_true(grepl("Gemini was unchanged", out, fixed = TRUE))
})

test_that("summarize_grounding_accuracy_table matches format.duboisR_grounding_result's own table", {
  results <- tibble::tibble(
    provider = "anthropic", model = "test-model",
    condition = rep(c("naive", "grounded"), each = 2), trial = rep(c(1, 2), 2),
    question_id = "q1", type = "boolean", prompt = "Is X true?",
    answer = c("TRUE", "TRUE", "TRUE", "TRUE"), confidence = c(60, 80, 90, 90),
    expected_answer = "TRUE", correct = TRUE, rationale = "because X"
  )
  summarized <- summarize_grounding_trials(results)
  tbl <- summarize_grounding_accuracy_table(summarized)

  expect_setequal(names(tbl), c("provider", "model", "condition", "mean_confidence", "accuracy_pct"))
  expect_equal(tbl$accuracy_pct, c(100, 100)) # every trial in this fixture is correct
  naive_row <- tbl[tbl$condition == "naive", ]
  expect_equal(naive_row$mean_confidence, 70) # mean(60, 80)

  result <- structure(list(results = results), class = "duboisR_grounding_result")
  out <- paste(format(result), collapse = "\n")
  expect_true(grepl("70", out, fixed = TRUE))
})

test_that("build_grounding_question_table collapses to one row per question with naive -> grounded cells", {
  summarized <- tibble::tibble(
    provider = rep(c("anthropic", "openai"), each = 2),
    condition = rep(c("naive", "grounded"), 2),
    question_id = "q1", type = "boolean", prompt = "Is X true?",
    accuracy = c(0, 1, 1, 1), # anthropic: wrong -> right; openai: right -> right
    expected_answer = "TRUE", rationale = "because X"
  )
  out <- build_grounding_question_table(summarized)

  expect_equal(nrow(out), 1) # one row for q1, not one per provider
  expect_setequal(names(out), c("question_id", "prompt", "expected_answer", "rationale", "anthropic", "openai"))
  # \uXXXX escapes, not literal typed glyphs -- avoids a Unicode
  # normalization mismatch between this file's bytes and the ones
  # build_grounding_question_table() actually constructs.
  expect_equal(out$anthropic, "✗ → ✓")
  expect_equal(out$openai, "✓ → ✓")
})

test_that("build_grounding_question_table marks a provider with no row at all for a question as an em dash", {
  # anthropic answered both questions; openai only ran on q1 -- q2 has no
  # (openai, q2) row whatsoever, unlike an NA accuracy (ran, but no trial
  # produced a valid answer). reshape() leaves that cell NA; the em dash
  # fill-in must catch it the same as the NA-accuracy case does.
  summarized <- tibble::tibble(
    provider = c("anthropic", "anthropic", "anthropic", "anthropic", "openai", "openai"),
    condition = c("naive", "grounded", "naive", "grounded", "naive", "grounded"),
    question_id = c("q1", "q1", "q2", "q2", "q1", "q1"),
    type = "boolean", prompt = c("Is X true?", "Is X true?", "Is Y true?", "Is Y true?", "Is X true?", "Is X true?"),
    accuracy = 1, expected_answer = "TRUE",
    rationale = c("because X", "because X", "because Y", "because Y", "because X", "because X")
  )
  out <- build_grounding_question_table(summarized)
  out <- out[order(out$question_id), ]
  expect_equal(out$anthropic, c("✓ → ✓", "✓ → ✓"))
  expect_equal(out$openai, c("✓ → ✓", "—")) # q1, then q2 (never ran)
})

test_that("render_table_pdf writes a PDF for a small table and for a wrapped, multi-page one", {
  tmp <- withr::local_tempdir()

  small_path <- file.path(tmp, "small.pdf")
  small_df <- data.frame(a = 1:3, b = c("x", "y", "z"))
  render_table_pdf(small_df, small_path, title = "A small table")
  expect_true(file.exists(small_path))
  expect_gt(file.size(small_path), 0)

  wrapped_path <- file.path(tmp, "wrapped.pdf")
  wrapped_df <- data.frame(
    text = rep("This is a long sentence that should get word-wrapped across several lines.", 10)
  )
  render_table_pdf(wrapped_df, wrapped_path, wrap_cols = "text", wrap_width = 20, rows_per_page = 3)
  expect_true(file.exists(wrapped_path))
  # 10 rows at 3/page -> 4 pages; pdf() writes one "endobj"-delimited page
  # tree per page, and the simplest content-agnostic proxy for "more than
  # one page got written" is just that the multi-page file is bigger than
  # the single-page one above.
  expect_gt(file.size(wrapped_path), file.size(small_path))
})

test_that("write_grounding_report writes all three PDFs without making any API calls", {
  tmp <- withr::local_tempdir()
  results <- tibble::tibble(
    provider = rep(c("anthropic", "openai"), each = 2),
    model = rep(c("m1", "m2"), each = 2),
    condition = rep(c("naive", "grounded"), 2), trial = 1,
    question_id = "q1", type = "boolean", prompt = "Is X true?",
    answer = "TRUE", confidence = 80, expected_answer = "TRUE",
    correct = TRUE, rationale = "because X"
  )
  result <- structure(list(results = results), class = "duboisR_grounding_result")

  paths <- write_grounding_report(result, out_dir = tmp)
  expect_length(paths, 3)
  expect_true(all(file.exists(paths)))
  expect_true(all(grepl("\\.pdf$", paths)))
})
