#' Interactive CLI wizard for filling in a datasheet
#'
#' Walks the researcher question-by-question through the same seven-section
#' structure [use_datasheet()] scaffolds (single source of truth: both come
#' from the package's internal `datasheet_questions` list), and writes
#' responses to a structured, machine-readable `datasheet.json` — this is
#' what powers the Shiny "Data Transparency & Provenance" tab. Saves
#' incrementally after every section (crash-safe), and is resumable: if
#' `output` already exists, previously-answered questions are shown and can
#' be kept or edited rather than re-asked from scratch.
#'
#' @param output Path to write the JSON answers to. Default
#'   `"datasheet.json"`.
#' @param resume If `TRUE` (default) and `output` already exists, loads and
#'   offers to keep/edit existing answers instead of starting over.
#' @return `output`, invisibly.
#' @export
build_datasheet_wizard <- function(output = "datasheet.json", resume = TRUE) {
  if (!rlang::is_interactive()) {
    rlang::abort("build_datasheet_wizard() requires an interactive session.")
  }

  answers <- if (resume && file.exists(output)) {
    jsonlite::read_json(output, simplifyVector = TRUE)
  } else {
    list()
  }

  for (section_key in names(datasheet_questions)) {
    section <- datasheet_questions[[section_key]]
    cli::cli_h1(section$title)

    section_answers <- answers[[section_key]] %||% list()

    for (q_key in names(section$questions)) {
      question_text <- section$questions[[q_key]]
      existing_answer <- section_answers[[q_key]]

      cli::cli_text("{.strong {question_text}}")

      if (!is.null(existing_answer) && nzchar(existing_answer)) {
        cli::cli_text("Existing answer: {existing_answer}")
        keep <- tolower(readline("Keep this answer? [Y/n] "))
        if (identical(keep, "n")) {
          section_answers[[q_key]] <- readline("New answer: ")
        }
      } else {
        section_answers[[q_key]] <- readline("> ")
      }
    }

    answers[[section_key]] <- section_answers
    jsonlite::write_json(answers, output, pretty = TRUE, auto_unbox = TRUE)
  }

  cli::cli_alert_success("Wrote {.path {output}}.")
  invisible(output)
}
