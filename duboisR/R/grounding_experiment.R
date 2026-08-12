#' The naive-vs-grounded question battery used by run_grounding_experiment()
#'
#' Returns the same fixed question list `data-raw/build_grounding_questions.R`
#' compiles into internal package data: each question has `type` (`"boolean"`
#' or `"enum"`), `prompt`, `choices` (enum only), `expected_answer`, and
#' `rationale` (which real, computed datasheet fact backs the expected
#' answer). Exposed so a consumer (e.g. the Shiny "LLM Grounding Test" tab)
#' can render question text/rationale without hardcoding a duplicate copy —
#' same pattern as [datasheet_schema()].
#'
#' @return The question battery, as a named list.
#' @export
grounding_questions <- function() grounding_questions_list

#' @keywords internal
pseudonymize_id_col <- function(x) sprintf("region_%02d", as.integer(factor(x)))

#' @keywords internal
relativize_date_col <- function(x) sprintf("day_%d", as.integer(x - min(x, na.rm = TRUE)))

#' Describe a dataset compactly enough to hand to an LLM
#'
#' Stands in for "the dataset" in the naive/grounded prompts: a full
#' multi-million-row CSV doesn't fit in a prompt, so this instead reports
#' column names/types/row count plus a small fixed-seed random sample of
#' rows. Used identically by both conditions in [run_grounding_experiment()]
#' — only the "grounded" condition additionally receives `datasheet.json`
#' content, so any difference in answers is attributable to that, not to a
#' different view of the raw data.
#'
#' `id_cols` and every `Date`/`POSIXct` column are pseudonymized/relativized
#' in the sample before it's shown (e.g. a real `county_fips` like `48171`
#' becomes `"region_07"`; a real date becomes `"day_412"`, an offset from
#' the data's own earliest date). Without this, a raw sample of real-world
#' identifiers hands the "naive" condition a shortcut that has nothing to do
#' with the datasheet: e.g. every Texas FIPS code starts with `48`, which a
#' knowledgeable model can recognize on sight, and a real calendar date
#' range reveals this project's year restriction directly. The columns'
#' *types* are still reported honestly (e.g. `date (Date)`) — only the
#' values are obscured, so this doesn't misrepresent the schema, just the
#' specific real-world provenance a sample of raw values would otherwise
#' leak for free.
#'
#' @param data A data frame.
#' @param n_sample Number of sample rows to include. Default 20.
#' @param seed Seed for the row sample, for a reproducible prompt across
#'   repeated runs. Default `20240101` (same convention as
#'   `precompute_audit.R`'s identity-proxy sample).
#' @param id_cols Character vector of column names to pseudonymize as opaque
#'   `"region_NN"` labels (real-world geographic/administrative identifiers
#'   like county FIPS codes) before sampling. Default `character(0)`.
#' @return A single character string.
#' @export
build_data_context <- function(data, n_sample = 20, seed = 20240101, id_cols = character(0)) {
  col_types <- vapply(data, function(col) class(col)[1], character(1))
  schema_lines <- sprintf("- %s (%s)", names(data), col_types)

  is_date_col <- vapply(data, function(col) inherits(col, c("Date", "POSIXct", "POSIXt")), logical(1))
  redacted <- data
  for (col in intersect(id_cols, names(redacted))) redacted[[col]] <- pseudonymize_id_col(redacted[[col]])
  for (col in names(redacted)[is_date_col]) redacted[[col]] <- relativize_date_col(redacted[[col]])

  set.seed(seed)
  sample_rows <- redacted[sample(nrow(redacted), min(n_sample, nrow(redacted))), ]

  redaction_note <- if (length(id_cols) > 0 || any(is_date_col)) {
    paste(
      "Note: identifier-like columns and calendar dates below have been",
      "pseudonymized/relativized (e.g. \"region_03\", \"day_412\") so this",
      "description doesn't incidentally reveal the dataset's real-world",
      "geographic or temporal provenance -- establishing that is exactly",
      "what a datasheet, not the raw data, is for."
    )
  } else {
    NULL
  }

  paste(
    sprintf("Dataset: %d rows, %d columns.", nrow(data), ncol(data)),
    "",
    "Columns:",
    paste(schema_lines, collapse = "\n"),
    if (!is.null(redaction_note)) paste("", redaction_note, sep = "\n"),
    "",
    sprintf("Random sample of %d rows:", nrow(sample_rows)),
    md_table(sample_rows),
    sep = "\n"
  )
}

#' Build the system/user prompt for one naive-or-grounded LLM call
#'
#' The "naive" condition gets `data_context` and the question battery only.
#' The "grounded" condition gets the same `data_context` and battery, plus
#' the full `datasheet.json` content and an explicit instruction to consult
#' it before answering — the single manipulated variable between the two
#' conditions.
#'
#' @param condition `"naive"` or `"grounded"`.
#' @param data_context A string from [build_data_context()].
#' @param questions A question list from [grounding_questions()].
#' @param datasheet A parsed datasheet list from [read_datasheet()].
#'   Required when `condition = "grounded"`.
#' @return A list with `system` and `user` prompt strings.
#' @export
build_grounding_prompt <- function(condition = c("naive", "grounded"), data_context, questions, datasheet = NULL) {
  condition <- rlang::arg_match(condition)

  question_lines <- vapply(names(questions), function(id) {
    q <- questions[[id]]
    if (identical(q$type, "boolean")) {
      sprintf('- [%s] (boolean -- answer exactly "TRUE" or "FALSE") %s', id, q$prompt)
    } else if (identical(q$type, "numeric")) {
      sprintf('- [%s] (numeric -- answer with a plain number, %s) %s', id, q$unit, q$prompt)
    } else {
      choice_lines <- paste(sprintf('"%s": %s', names(q$choices), q$choices), collapse = "; ")
      sprintf('- [%s] (multiple choice -- answer with the choice key, not its text) %s Choices: %s', id, q$prompt, choice_lines)
    }
  }, character(1))

  battery <- paste(
    "Answer every question below about the dataset. For each question, also",
    "report your confidence in that specific answer as an integer from 0",
    "(pure guess) to 100 (certain) -- confidence should reflect how sure you",
    "actually are, not a default value repeated across every question.",
    paste(question_lines, collapse = "\n"),
    sep = "\n\n"
  )

  if (condition == "naive") {
    system <- paste(
      "You are a careful data analyst. Answer strictly from the dataset",
      "description provided below. Do not draw on outside knowledge of any",
      "specific real-world dataset, agency, or research project this data",
      "might resemble or that you might recognize it as -- reason only from",
      "what is explicitly shown below, plus ordinary statistical/domain",
      "judgment that isn't tied to identifying a specific real-world source.",
      "You must still answer every question, using your best judgment where",
      "the description doesn't say explicitly."
    )
    user <- paste(data_context, battery, sep = "\n\n")
  } else {
    if (is.null(datasheet)) {
      rlang::abort('`datasheet` is required when condition = "grounded".')
    }
    system <- paste(
      "You are a careful data analyst. Before answering, read the attached",
      "datasheet.json (a Datasheets-for-Datasets provenance document) in",
      "full and ground every answer in it -- it takes precedence over any",
      "assumption you would otherwise make from the raw data sample alone."
    )
    datasheet_json <- jsonlite::toJSON(datasheet, auto_unbox = TRUE, pretty = TRUE)
    user <- paste(
      data_context,
      paste("datasheet.json:", "```json", datasheet_json, "```", sep = "\n"),
      battery,
      sep = "\n\n"
    )
  }

  list(system = system, user = user)
}

#' @keywords internal
score_answer <- function(type, answer, expected, tolerance) {
  if (identical(type, "numeric")) {
    a <- suppressWarnings(as.numeric(answer))
    e <- suppressWarnings(as.numeric(expected))
    !is.na(a) && !is.na(e) && abs(a - e) <= tolerance
  } else {
    identical(answer, expected)
  }
}

#' Run the naive-vs-grounded LLM datasheet-grounding experiment
#'
#' For every requested provider, calls the same flagship model twice --
#' once "naive" (dataset description only) and once "grounded" (dataset
#' description plus `datasheet.json`, with an explicit instruction to
#' consult it) -- over the fixed [grounding_questions()] battery, and scores
#' each answer against that question's hand-authored `expected_answer`. The
#' Datasheets-for-Datasets literature's central claim -- that provenance
#' documentation changes how a dataset gets used -- made empirically
#' checkable for one concrete downstream consumer (an LLM answering
#' questions about the data) instead of asserted.
#'
#' @param data_path Path to the audit-ready CSV (e.g.
#'   `data/processed/audit_ready_stops.csv`).
#' @param datasheet_path Path to `datasheet.json`.
#' @param providers Character vector, any of `"anthropic"`, `"openai"`,
#'   `"gemini"`, `"grok"`.
#' @param models Named list mapping each requested provider to a model
#'   string, e.g. `list(anthropic = "claude-opus-5", openai = "gpt-5.1",
#'   gemini = "gemini-3.1-pro-preview", grok = "grok-4.6")`.
#' @param questions Question battery. Default [grounding_questions()].
#' @param id_cols Columns to pseudonymize in the naive/grounded data context
#'   before either condition sees it -- see [build_data_context()]. Default
#'   `"county_fips"`, this project's real-world geographic identifier.
#' @param n_repeats Independent trials per (provider, condition), same
#'   prompt each time. A single trial's "changed answer" could just be
#'   sampling noise (providers aren't run at temperature 0 -- see
#'   `llm_clients.R` for why); repeats let [summarize_grounding_trials()]
#'   report a majority-vote answer and a stability/agreement rate instead
#'   of trusting one draw. Default 1.
#' @return An object of class `duboisR_grounding_result` wrapping a tibble
#'   `results` with one row per (provider, condition, trial, question):
#'   `provider`, `model`, `condition`, `trial`, `question_id`, `type`,
#'   `prompt`, `answer`, `confidence`, `expected_answer`, `correct`,
#'   `rationale`. Pass `results` to [summarize_grounding_trials()] to
#'   collapse repeats into one row per question.
#' @export
run_grounding_experiment <- function(data_path, datasheet_path, providers, models,
                                      questions = grounding_questions(), id_cols = "county_fips",
                                      n_repeats = 1) {
  providers <- rlang::arg_match(providers, c("anthropic", "openai", "gemini", "grok"), multiple = TRUE)
  missing_models <- setdiff(providers, names(models))
  if (length(missing_models) > 0) {
    rlang::abort(sprintf(
      '`models` is missing an entry for: %s. Pass e.g. list(anthropic = "claude-opus-5").',
      paste(missing_models, collapse = ", ")
    ))
  }

  data <- readr::read_csv(data_path, show_col_types = FALSE)
  datasheet <- read_datasheet(datasheet_path)
  if (is.null(datasheet)) {
    rlang::abort(sprintf("No datasheet found at %s -- the grounded condition needs one.", datasheet_path))
  }

  data_context <- build_data_context(data, id_cols = id_cols)
  schema <- grounding_response_schema(questions)
  clients <- list(anthropic = call_anthropic, openai = call_openai, gemini = call_gemini, grok = call_grok)

  # unname() throughout: questions (and so `ids`) is a named list, and
  # vapply()/mapply() propagate input names onto their result by default --
  # without stripping them, every derived vector below ends up with e.g.
  # names(types) == ids, which then leaks into the results tibble's columns
  # as a spurious per-element "names" attribute.
  ids <- names(questions)
  types <- unname(vapply(questions, `[[`, character(1), "type"))
  prompts <- unname(vapply(questions, `[[`, character(1), "prompt"))
  expected <- unname(vapply(questions, `[[`, character(1), "expected_answer"))
  rationale <- unname(vapply(questions, `[[`, character(1), "rationale"))
  tolerance <- unname(vapply(questions, function(q) if (is.null(q$tolerance)) NA_real_ else q$tolerance, numeric(1)))

  runs <- list()
  for (provider in providers) {
    model <- models[[provider]]
    call_fn <- clients[[provider]]

    for (condition in c("naive", "grounded")) {
      prompt <- build_grounding_prompt(
        condition, data_context, questions,
        datasheet = if (condition == "grounded") datasheet else NULL
      )

      for (trial in seq_len(n_repeats)) {
        answers <- call_fn(prompt$system, prompt$user, schema, model)
        answer <- unname(vapply(ids, function(id) {
          a <- answers[[id]]$answer
          if (is.null(a)) NA_character_ else as.character(a)
        }, character(1)))
        confidence <- unname(vapply(ids, function(id) {
          c_val <- answers[[id]]$confidence
          if (is.null(c_val)) NA_real_ else as.numeric(c_val)
        }, numeric(1)))
        correct <- unname(mapply(score_answer, types, answer, expected, tolerance))

        runs[[length(runs) + 1]] <- tibble::tibble(
          provider = provider, model = model, condition = condition, trial = trial,
          question_id = ids, type = types, prompt = prompts,
          answer = answer, confidence = confidence, expected_answer = expected,
          correct = correct, rationale = rationale
        )
      }
    }
  }

  structure(list(results = do.call(rbind, runs)), class = "duboisR_grounding_result")
}

#' Collapse repeated-trial rows into one summary row per question/condition
#'
#' [run_grounding_experiment()] with `n_repeats > 1` returns one row per
#' trial; this collapses those into, per (provider, model, condition,
#' question_id): the modal (most common) answer, the fraction of trials
#' that were correct, the fraction of trials that agreed with the modal
#' answer (a stability signal -- a single-run "changed answer" could be
#' sampling noise, a low-agreement one visibly is), and mean self-reported
#' confidence.
#'
#' @param results The `results` tibble from a `duboisR_grounding_result`
#'   (i.e. `run_grounding_experiment(...)$results`).
#' @return A tibble, one row per (provider, model, condition, question_id):
#'   `provider`, `model`, `condition`, `question_id`, `type`, `prompt`,
#'   `modal_answer`, `accuracy`, `agreement`, `mean_confidence`, `n_trials`,
#'   `expected_answer`, `rationale`.
#' @export
summarize_grounding_trials <- function(results) {
  # Builds every column as a fixed-length vector first, then a single
  # tibble() call at the end -- same pattern as run_grounding_experiment().
  # An earlier version built one tibble() per key and rbind()ed them; if a
  # single key's row ever came out a different shape than the rest (e.g. a
  # question every trial answered NA -- table()'s modal answer over an
  # all-NA vector is zero-length, and tibble()'s size-0/1 recycling rule
  # silently drops that whole row instead of erroring) the rbind() failed
  # opaquely with "numbers of columns of arguments do not match" *after*
  # every API call for the run had already been made and billed. One
  # tibble() call structurally cannot produce that failure, and the
  # all-NA-answer case is now handled explicitly (NA modal answer, NA
  # agreement) instead of making the row vanish.
  keys <- unique(results[c("provider", "model", "condition", "question_id", "type", "prompt", "expected_answer", "rationale")])
  keys <- keys[order(keys$provider, keys$condition, keys$question_id), ]

  n <- nrow(keys)
  modal_answer <- character(n)
  accuracy <- numeric(n)
  agreement <- numeric(n)
  mean_confidence <- numeric(n)
  n_trials <- integer(n)

  for (i in seq_len(n)) {
    rows <- results[
      results$provider == keys$provider[i] & results$condition == keys$condition[i] & results$question_id == keys$question_id[i],
    ]
    answer_counts <- table(rows$answer)
    if (length(answer_counts) == 0) {
      modal_answer[i] <- NA_character_
      agreement[i] <- NA_real_
    } else {
      modal_answer[i] <- names(answer_counts)[which.max(answer_counts)]
      agreement[i] <- mean(rows$answer == modal_answer[i], na.rm = TRUE)
    }
    accuracy[i] <- mean(rows$correct)
    mean_confidence[i] <- mean(rows$confidence, na.rm = TRUE)
    n_trials[i] <- nrow(rows)
  }

  tibble::tibble(
    provider = keys$provider, model = keys$model, condition = keys$condition,
    question_id = keys$question_id, type = keys$type, prompt = keys$prompt,
    modal_answer = modal_answer, accuracy = accuracy, agreement = agreement,
    mean_confidence = mean_confidence, n_trials = n_trials,
    expected_answer = keys$expected_answer, rationale = keys$rationale
  )
}

#' @export
format.duboisR_grounding_result <- function(x, ...) {
  results <- x$results
  summarized <- summarize_grounding_trials(results)
  n_trials <- if (nrow(results) > 0) max(results$trial) else 0

  by_condition <- stats::aggregate(cbind(accuracy, mean_confidence) ~ provider + model + condition, data = summarized, FUN = mean)
  by_condition$accuracy_pct <- round(100 * by_condition$accuracy, 1)
  by_condition$mean_confidence <- round(by_condition$mean_confidence, 1)
  by_condition$accuracy <- NULL

  # agreement is NA for a question no trial ever produced a valid answer
  # for -- na.rm = TRUE so that one unanswered question excludes itself from
  # the average instead of poisoning the whole statistic to NA.
  mean_agreement_pct <- round(100 * mean(summarized$agreement, na.rm = TRUE), 1)

  naive <- summarized[summarized$condition == "naive", c("provider", "question_id", "modal_answer")]
  grounded <- summarized[summarized$condition == "grounded", c("provider", "question_id", "modal_answer")]
  changed <- merge(naive, grounded, by = c("provider", "question_id"), suffixes = c("_naive", "_grounded"))

  # A pair where either side's modal_answer is NA (never validly answered in
  # any trial) has no defined "changed or not" -- exclude those from the
  # comparison rather than letting `!=` against NA propagate to NA for the
  # whole sum(), but report how many were excluded instead of silently
  # shrinking the denominator.
  comparable <- changed[!is.na(changed$modal_answer_naive) & !is.na(changed$modal_answer_grounded), ]
  n_changed <- sum(comparable$modal_answer_naive != comparable$modal_answer_grounded)
  n_unanswered <- nrow(changed) - nrow(comparable)

  c(
    sprintf("**Accuracy by provider/condition** (majority vote across %d trial(s) per question)", n_trials), "",
    md_table(by_condition), "",
    sprintf(
      "**Mean answer stability across trials: %.1f%%** (share of trials matching the modal answer, per question).",
      mean_agreement_pct
    ), "",
    sprintf(
      "**%d of %d question/provider pairs changed their majority-vote answer when grounded in the datasheet.**",
      n_changed, nrow(comparable)
    ),
    if (n_unanswered > 0) {
      sprintf(
        paste(
          "**%d question/provider pair(s) excluded from that comparison** -- at least one",
          "condition never produced a valid answer in any trial."
        ),
        n_unanswered
      )
    }
  )
}

#' @export
print.duboisR_grounding_result <- function(x, ...) {
  cat(paste(format(x), collapse = "\n"), "\n")
  invisible(x)
}
