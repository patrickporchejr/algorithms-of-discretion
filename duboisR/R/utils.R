#' @keywords internal
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Render a data frame as a Markdown pipe table
#'
#' A small hand-rolled formatter so `duboisR` doesn't need to depend on
#' `knitr`/`rmarkdown` just to produce copy-paste-ready tables for a
#' datasheet.
#'
#' @param df A data frame.
#' @param digits Number of decimal places for numeric columns.
#' @return A character scalar (one string, embedded newlines) containing a
#'   Markdown pipe table.
#' @keywords internal
md_table <- function(df, digits = 3) {
  if (nrow(df) == 0) {
    return(paste0("_(no rows)_"))
  }
  fmt_col <- function(x) {
    out <- if (is.numeric(x)) {
      format(round(x, digits), trim = TRUE, scientific = FALSE)
    } else {
      as.character(x)
    }
    # as.character()/format() both propagate NA as a genuine NA rather than
    # the string "NA" -- nchar(NA) is itself NA, which breaks the width
    # computation below. Make missing values an explicit, printable "NA".
    out[is.na(out)] <- "NA"
    out
  }
  cols <- names(df)
  body <- lapply(df, fmt_col)
  body <- as.data.frame(body, stringsAsFactors = FALSE, check.names = FALSE)

  widths <- vapply(cols, function(cn) max(nchar(cn), nchar(body[[cn]])), integer(1))

  pad <- function(s, w) formatC(s, width = -w)

  header <- paste0("| ", paste(mapply(pad, cols, widths), collapse = " | "), " |")
  sep <- paste0("|", paste(strrep("-", widths + 2), collapse = "|"), "|")
  rows <- vapply(seq_len(nrow(body)), function(i) {
    paste0("| ", paste(mapply(pad, unlist(body[i, ]), widths), collapse = " | "), " |")
  }, character(1))

  paste(c(header, sep, rows), collapse = "\n")
}

#' Abort with a clear message if required columns are missing
#'
#' @param data A data frame.
#' @param cols Character vector of required column names.
#' @param call The calling environment, for error attribution.
#' @keywords internal
abort_if_missing_cols <- function(data, cols, call = rlang::caller_env()) {
  missing <- setdiff(cols, names(data))
  if (length(missing) > 0) {
    rlang::abort(
      sprintf("`data` is missing required column(s): %s", paste(missing, collapse = ", ")),
      call = call
    )
  }
  invisible(TRUE)
}
