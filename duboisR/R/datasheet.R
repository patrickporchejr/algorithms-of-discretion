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
