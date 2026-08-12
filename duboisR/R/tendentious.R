#' Diagnose whether an outcome variable is "tendentious"
#'
#' Models trained on human decisions (arrest records, subjective evaluation
#' scores, an officer's decision to search) faithfully reproduce the biases
#' embedded in those decisions — they are not neutral measurements of an
#' underlying fact. `check_tendentious()` prompts the researcher to
#' explicitly categorize an outcome variable and raises a transparency
#' warning when it reflects administrative/subjective human discretion
#' rather than an objective measurement. This is a checklist tool, not an
#' automated judgment — the categorization decision is always the
#' researcher's.
#'
#' @param variable_name String, the outcome variable being audited (e.g.
#'   `"search_conducted"`).
#' @param classification One of `"objective"`, `"subjective"`,
#'   `"administrative"`. If `NULL` and `interactive` is `TRUE`, the user is
#'   prompted to choose. If `NULL` and `interactive` is `FALSE`, this
#'   errors — categorization must be explicit, never silently assumed.
#' @param rationale Optional free-text string explaining the
#'   classification, for pasting into the datasheet's Uses section.
#' @param interactive Whether to prompt for `classification`/`rationale`
#'   when not supplied. Default [rlang::is_interactive()].
#' @return An object of class `duboisR_tendentious_check` with
#'   `variable_name`, `classification`, `rationale`, `is_tendentious`, and
#'   `message`.
#' @export
check_tendentious <- function(variable_name, classification = NULL, rationale = NULL,
                               interactive = rlang::is_interactive()) {
  valid_classes <- c("objective", "subjective", "administrative")

  if (is.null(classification)) {
    if (!interactive) {
      rlang::abort(paste0(
        "`classification` must be supplied when interactive = FALSE. ",
        "Choose one of: ", paste(valid_classes, collapse = ", ")
      ))
    }
    cli::cli_h2("Tendentious Data Diagnostic: {.field {variable_name}}")
    cli::cli_text(
      "Does {.field {variable_name}} reflect a historical administrative or ",
      "subjective human decision (e.g. an arrest, a search, a discretionary ",
      "score) rather than an objective measurement?"
    )
    choice <- utils::menu(valid_classes, title = "Classify this variable as:")
    if (choice == 0) rlang::abort("No classification chosen.")
    classification <- valid_classes[choice]
  }

  classification <- rlang::arg_match(classification, valid_classes)

  if (is.null(rationale) && interactive) {
    cli::cli_text("Optionally, provide a rationale (press Enter to skip):")
    rationale_input <- readline("> ")
    if (nzchar(rationale_input)) rationale <- rationale_input
  }

  is_tendentious <- classification %in% c("subjective", "administrative")

  message <- if (is_tendentious) {
    sprintf(
      paste0(
        "'%s' is classified as %s: it reflects human discretion, not an ",
        "objective ground truth. Models trained on it risk faithfully ",
        "reproducing and reifying the systemic biases embedded in that ",
        "discretion, rather than measuring the underlying behavior it is ",
        "assumed to proxy for."
      ),
      variable_name, classification
    )
  } else {
    sprintf("'%s' is classified as objective.", variable_name)
  }

  structure(
    list(
      variable_name = variable_name,
      classification = classification,
      rationale = rationale,
      is_tendentious = is_tendentious,
      message = message
    ),
    class = "duboisR_tendentious_check"
  )
}

#' @export
print.duboisR_tendentious_check <- function(x, ...) {
  if (x$is_tendentious) {
    cli::cli_alert_danger(x$message)
  } else {
    cli::cli_alert_success(x$message)
  }
  if (!is.null(x$rationale)) cli::cli_text("Rationale: {x$rationale}")
  invisible(x)
}

#' @export
format.duboisR_tendentious_check <- function(x, ...) {
  c(
    sprintf("**%s**: classified as *%s*.", x$variable_name, x$classification),
    "",
    x$message,
    if (!is.null(x$rationale)) c("", sprintf("Rationale: %s", x$rationale))
  )
}
