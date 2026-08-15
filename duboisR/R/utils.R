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

#' Build an intersectional group key by pasting one or more columns together
#'
#' e.g. `subject_race` x `subject_sex` -> `"black_female"`. Shared by
#' [audit_composition()] and [subpopulation_disparities()] so both key
#' subpopulation groups the same way.
#'
#' @param data A data frame.
#' @param cols Character vector of one or more column names.
#' @return A character vector, one element per row of `data`.
#' @keywords internal
dubois_group_key <- function(data, cols) {
  do.call(paste, c(as.list(data[cols]), sep = "_"))
}

#' Count stops and searches per (race, group), dropping unresolved rows
#'
#' The single aggregation step behind both [aggregate_sufficient_statistics()]
#' (the Threshold Test's input) and [summarize_county_search_rates()] (the
#' Veil of Darkness search-rate chart) -- both ultimately answer "how many
#' stops, how many of them searched, per (race, group)" from the same
#' `search_col`. Kept as one shared helper instead of two independently
#' hand-rolled `aggregate()` calls that could silently disagree on how an
#' unresolved/`NA` `search_col` row is handled.
#'
#' @param data A data frame.
#' @param race_col,group_col,search_col Column names.
#' @return A data frame: `race`, `group`, `S` (rows where `search_col` is
#'   `TRUE`), `n` (non-`NA` `search_col` rows).
#' @keywords internal
.dubois_count_searches <- function(data, race_col, group_col, search_col) {
  d <- data.frame(
    race = data[[race_col]], group = data[[group_col]],
    S = as.integer(as.logical(data[[search_col]])), n = 1L
  )
  d <- d[!is.na(d$S), , drop = FALSE]
  stats::aggregate(cbind(S, n) ~ race + group, data = d, FUN = sum)
}

#' Capitalize the first letter of each element of a character (or factor) vector
#'
#' Shared by every `interpret_*()` narration function so "white"/"black" read
#' as "White"/"Black" in prose, instead of five near-identical local copies.
#' @keywords internal
.dubois_cap <- function(x) {
  x <- as.character(x)
  paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x)))
}

#' Add a wrapped, italicized figure caption to a plot for publication use
#'
#' For figures headed into a paper/report as standalone images, where the
#' interpretation needs to travel with the image itself rather than live in
#' surrounding prose (the Shiny dashboard's "What this data shows" text, or
#' a CLI's console output, don't help a reader looking at just the PNG).
#' Wraps `caption` to `width` characters and styles it like a journal
#' figure caption (small, italic, centered) -- deliberately with no
#' "Figure:"/"Fig. N:" label prefix, since that numbering is the paper's
#' to assign, not this package's. Works on both a plain `ggplot` and a
#' `patchwork` composition (e.g. [plot_outcome_threshold_comparison()]'s
#' output) -- patchwork merges a second `plot_annotation()` call's non-NULL
#' fields onto the first rather than replacing it, so this is safe to call
#' even on a patchwork object that already has a title/subtitle set.
#'
#' @param plot A `ggplot` or `patchwork` object.
#' @param caption Character scalar -- typically an `interpret_*()`
#'   function's output.
#' @param width Wrap width in characters. Default `100`.
#' @return `plot`, with the caption added.
#' @export
add_figure_caption <- function(plot, caption, width = 100) {
  wrapped <- paste(strwrap(caption, width = width), collapse = "\n")
  cap_text <- ggplot2::element_text(hjust = 0.5, size = 9, face = "italic", lineheight = 1.15)
  if (inherits(plot, "patchwork")) {
    rlang::check_installed("patchwork", reason = "to caption a patchwork figure.")
    plot + patchwork::plot_annotation(
      caption = wrapped,
      theme = ggplot2::theme(plot.caption = cap_text, plot.caption.position = "plot")
    )
  } else {
    plot + ggplot2::labs(caption = wrapped) +
      ggplot2::theme(plot.caption = cap_text, plot.caption.position = "plot")
  }
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
