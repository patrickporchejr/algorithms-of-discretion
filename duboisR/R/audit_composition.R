#' Audit subpopulation composition and missingness
#'
#' Computes the precise statistical ground truth needed to fill in a
#' datasheet's Composition section correctly (Gebru et al. 2021): total
#' instance counts and representation percentages per subpopulation, and
#' (optionally) subgroup-specific missingness rates, so a researcher can
#' check whether data is disproportionately missing or redacted for
#' marginalized groups. This function deliberately only computes and
#' formats these numbers — it does not narrate or interpret them. Filling
#' in the qualitative reflection is the researcher's job, not the
#' package's; see [use_datasheet()].
#'
#' @param data A data frame.
#' @param group_col Character vector of one or more column names to group
#'   by. When more than one is given, groups are intersectional composite
#'   keys (e.g. `subject_race` x `subject_sex` -> `"black_female"`).
#' @param missing_col Optional string column name to compute
#'   subgroup-specific missingness for (e.g. `"contraband_found"`).
#' @param weight_col Optional string column of row weights; if given,
#'   counts become weighted sums instead of row counts. Not used by
#'   default — forward-provisioned for survey-weighted data sources.
#' @return A list of class `duboisR_composition` with elements
#'   `representation` (tibble: `group`, `n`, `pct`) and `missingness`
#'   (tibble: `group`, `n_total`, `n_missing`, `pct_missing`, or `NULL` if
#'   `missing_col` was not supplied).
#' @export
audit_composition <- function(data, group_col, missing_col = NULL, weight_col = NULL) {
  abort_if_missing_cols(data, group_col)
  if (!is.null(missing_col)) abort_if_missing_cols(data, missing_col)
  if (!is.null(weight_col)) abort_if_missing_cols(data, weight_col)

  grouped <- data
  grouped$.dubois_group <- dubois_group_key(data, group_col)

  weights <- if (!is.null(weight_col)) data[[weight_col]] else rep(1, nrow(data))

  representation <- stats::aggregate(weights, by = list(group = grouped$.dubois_group), FUN = sum)
  names(representation) <- c("group", "n")
  representation$pct <- 100 * representation$n / sum(representation$n)
  representation <- tibble::as_tibble(representation[order(-representation$n), ])

  missingness <- NULL
  if (!is.null(missing_col)) {
    is_missing <- is.na(data[[missing_col]])
    total_agg <- stats::aggregate(weights, by = list(group = grouped$.dubois_group), FUN = sum)
    missing_agg <- stats::aggregate(weights * is_missing, by = list(group = grouped$.dubois_group), FUN = sum)
    missingness <- tibble::tibble(
      group = total_agg$group,
      n_total = total_agg$x,
      n_missing = missing_agg$x,
      pct_missing = 100 * missing_agg$x / total_agg$x
    )
    missingness <- missingness[order(-missingness$pct_missing), ]
  }

  structure(
    list(representation = representation, missingness = missingness),
    class = "duboisR_composition"
  )
}

#' @export
format.duboisR_composition <- function(x, ...) {
  out <- c("**Representation**", "", md_table(x$representation))
  if (!is.null(x$missingness)) {
    out <- c(out, "", "**Missingness**", "", md_table(x$missingness))
  }
  out
}

#' @export
print.duboisR_composition <- function(x, ...) {
  cat(paste(format(x), collapse = "\n"), "\n")
  invisible(x)
}
