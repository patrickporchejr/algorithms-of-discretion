#' Scaffold a Datasheets-for-Datasets document
#'
#' Copies a standardized, pre-formatted datasheet template — the seven
#' lifecycle sections of Gebru et al. 2021 ("Datasheets for Datasets"),
#' each with its standard sub-questions — into the researcher's project.
#' This deliberately copies **static template text only**: the original
#' Datasheets for Datasets paper explicitly warns against automating the
#' qualitative reflection, since that reflection is the point. Use
#' [audit_composition()], [check_proxies()], and [check_tendentious()] to
#' get the precise statistics some of the template's questions reference.
#'
#' @param path Where to write the datasheet. Default `"datasheet.md"`.
#' @param format `"md"` (default) or `"qmd"`.
#' @param overwrite Whether to overwrite an existing file at `path`.
#'   Default `FALSE`.
#' @param open Whether to open the file in the default editor after
#'   writing it. Default [rlang::is_interactive()].
#' @return `path`, invisibly.
#' @export
use_datasheet <- function(path = "datasheet.md", format = c("md", "qmd"),
                           overwrite = FALSE, open = rlang::is_interactive()) {
  format <- rlang::arg_match(format)

  if (file.exists(path) && !overwrite) {
    rlang::abort(sprintf("'%s' already exists. Pass overwrite = TRUE to replace it.", path))
  }

  template_path <- system.file("templates", paste0("datasheet_template.", format), package = "duboisR")
  file.copy(template_path, path, overwrite = overwrite)

  if (open) utils::file.edit(path)

  invisible(path)
}

#' Seed or update a datasheet.json's answers non-interactively
#'
#' `build_datasheet_wizard()` is interactive-only by design (the reflection
#' is the point), but a first-pass draft still needs to come from
#' *somewhere* -- e.g. seeding realistic demo content, or scripting an
#' update to one section after a diagnostic result changes. This is that
#' non-interactive path, with the same principle the wizard's own
#' `resume = TRUE` already applies: never silently destroy an existing
#' answer. By default, a question that already has a non-empty answer at
#' `path` is left untouched and only blank/missing questions are filled in
#' from `answers`; pass `overwrite_existing = TRUE` to intentionally
#' replace existing answers instead. Unrecognized section/question keys
#' (typos, or drift from the package's internal question schema) warn and
#' are skipped rather than silently written into the file.
#'
#' @param answers A named list matching the structure of the package's
#'   internal question schema: `list(section_key = list(question_key =
#'   "answer text", ...), ...)`. See a template from [use_datasheet()] or
#'   the section/question keys documented there for what's valid.
#' @param path Path to the `datasheet.json` to create or update. Default
#'   `"datasheet.json"`.
#' @param overwrite_existing If `TRUE`, values in `answers` replace existing
#'   non-empty answers for the same question. Default `FALSE` (fill blanks
#'   only, preserving anything already answered).
#' @return `path`, invisibly.
#' @export
seed_datasheet_answers <- function(answers, path = "datasheet.json", overwrite_existing = FALSE) {
  existing <- if (file.exists(path)) jsonlite::read_json(path, simplifyVector = TRUE) else list()

  for (section_key in names(answers)) {
    if (!section_key %in% names(datasheet_questions)) {
      rlang::warn(sprintf("'%s' is not a known datasheet section; skipping.", section_key))
      next
    }
    valid_questions <- names(datasheet_questions[[section_key]]$questions)
    section_answers <- existing[[section_key]] %||% list()

    for (q_key in names(answers[[section_key]])) {
      if (!q_key %in% valid_questions) {
        rlang::warn(sprintf("'%s.%s' is not a known datasheet question; skipping.", section_key, q_key))
        next
      }
      current <- section_answers[[q_key]]
      has_existing_answer <- !is.null(current) && nzchar(current)
      if (!has_existing_answer || overwrite_existing) {
        section_answers[[q_key]] <- answers[[section_key]][[q_key]]
      }
    }
    existing[[section_key]] <- section_answers
  }

  jsonlite::write_json(existing, path, pretty = TRUE, auto_unbox = TRUE)
  invisible(path)
}

#' The Datasheets-for-Datasets question schema this package's tooling shares
#'
#' Returns the same seven-section, question-keyed schema that
#' [use_datasheet()], [build_datasheet_wizard()], and
#' [seed_datasheet_answers()] all use as their single source of truth: each
#' section has a `title` and a named `questions` character vector (question
#' key -> question text). Exposed so a consumer of [read_datasheet()]'s raw
#' JSON (e.g. the Shiny "Data Transparency & Provenance" tab) can render
#' real section/question titles alongside the stored answers, instead of
#' hardcoding a duplicate copy of the schema or displaying raw JSON keys.
#'
#' @return The seven-section question schema, as a named list.
#' @export
datasheet_schema <- function() datasheet_questions

#' Read a datasheet.json produced by build_datasheet_wizard()
#'
#' A thin [jsonlite::read_json()] wrapper used by both tests and the Shiny
#' "Data Transparency & Provenance" tab. Returns `NULL` (not an error) when
#' `path` doesn't exist, so callers can render a graceful empty state
#' instead of crashing when no datasheet has been created yet.
#'
#' @param path Path to a `datasheet.json` file.
#' @return A list of section-question-answer data, or `NULL` if `path`
#'   doesn't exist.
#' @export
read_datasheet <- function(path) {
  if (!file.exists(path)) {
    cli::cli_inform("No datasheet found at {.path {path}}.")
    return(NULL)
  }
  jsonlite::read_json(path, simplifyVector = TRUE)
}
