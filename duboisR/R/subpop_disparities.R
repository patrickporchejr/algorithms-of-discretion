#' Disaggregate model performance across intersectional subgroups
#'
#' A single accuracy or hit-rate number can hide starkly different error
#' rates for different subgroups. `subpopulation_disparities()` scores a
#' fitted model's predicted probabilities against a ground-truth outcome
#' and disaggregates True Positive Rate, False Positive Rate, and Positive
#' Predictive Value per intersectional subgroup (e.g. `"black_female"`).
#'
#' It is a mathematical fact (Chouldechova 2017; Kleinberg, Mullainathan &
#' Raghavan 2016) that when base rates differ across groups, a calibrated
#' classifier (equal PPV across groups) generally **cannot** also equalize
#' both FPR and FNR simultaneously. This function reports that trade-off —
#' it does not attempt to resolve it.
#'
#' @param model_fit A `duboisR_glm_fit` (from [fit_audit_glm()]) or a raw
#'   [stats::glm] object.
#' @param data A data frame to score (e.g. the fitting data, or a held-out
#'   set).
#' @param actual_col String ground-truth outcome column (e.g.
#'   `"search_conducted"` or `"contraband_found"`).
#' @param subgroup_cols Character vector of columns to form intersectional
#'   subgroups from. Default `c("subject_race", "subject_sex")`.
#' @param threshold Probability threshold for a "predicted positive".
#'   Default `0.5`.
#' @param filter_search_only If `NULL` (default), auto-set to `TRUE` when
#'   `actual_col == "contraband_found"` (structurally `NA` off-search) and
#'   `FALSE` otherwise. Can be forced explicitly.
#' @param search_col String search-indicator column, used only when
#'   `filter_search_only` is `TRUE`. Default `"search_conducted"`.
#' @return A tibble of class `duboisR_subpop_disparities` with columns
#'   `group`, `n`, `base_rate`, `TPR`, `FPR`, `PPV`, `threshold_used`. Rows
#'   with `NA` `actual_col` are dropped before scoring (administrative data
#'   commonly leaves the outcome unreported for some rows; an `NA` here
#'   would otherwise poison every group's `sum()`/`mean()`). Has an
#'   attribute `"notes"` documenting the threshold, whether search-only
#'   filtering was applied, how many rows were dropped for an `NA` outcome
#'   (if any), and the fairness-metrics trade-off above.
#' @export
subpopulation_disparities <- function(model_fit, data, actual_col,
                                       subgroup_cols = c("subject_race", "subject_sex"),
                                       threshold = 0.5, filter_search_only = NULL,
                                       search_col = "search_conducted") {
  model <- if (inherits(model_fit, "duboisR_glm_fit")) model_fit$model else model_fit
  abort_if_missing_cols(data, c(actual_col, subgroup_cols))

  if (is.null(filter_search_only)) {
    filter_search_only <- identical(actual_col, "contraband_found")
  }
  if (filter_search_only) {
    abort_if_missing_cols(data, search_col)
    data <- data[as.logical(data[[search_col]]), , drop = FALSE]
  }

  # Administrative data commonly leaves the outcome unreported for a
  # meaningful fraction of rows (e.g. search_conducted is NA, not FALSE, for
  # ~38% of the real Texas dataset) -- glm() silently drops these via its
  # default na.action when *fitting*, but this function scores against the
  # caller-supplied `data` independently of the model's training frame, so
  # without this filter an NA here poisons every group's confusion-matrix sum
  # via sum()/mean()'s default na.rm = FALSE.
  n_before_na_drop <- nrow(data)
  data <- data[!is.na(data[[actual_col]]), , drop = FALSE]
  n_dropped_na_outcome <- n_before_na_drop - nrow(data)

  predicted_prob <- stats::predict(model, newdata = data, type = "response")
  predicted_positive <- predicted_prob >= threshold
  actual_positive <- as.logical(data[[actual_col]])

  group <- do.call(paste, c(as.list(data[subgroup_cols]), sep = "_"))

  groups <- split(seq_along(group), group)
  rows <- lapply(names(groups), function(g) {
    idx <- groups[[g]]
    pred <- predicted_positive[idx]
    act <- actual_positive[idx]

    TP <- sum(pred & act); FP <- sum(pred & !act)
    TN <- sum(!pred & !act); FN <- sum(!pred & act)

    tibble::tibble(
      group = g, n = length(idx), base_rate = mean(act),
      TPR = TP / (TP + FN), FPR = FP / (FP + TN), PPV = TP / (TP + FP),
      threshold_used = threshold
    )
  })

  out <- tibble::as_tibble(do.call(rbind, rows))
  out <- out[order(-out$n), ]

  notes <- c(
    sprintf("Predicted-positive threshold: %.2f.", threshold),
    if (filter_search_only) {
      sprintf("Filtered to %s == TRUE before scoring (outcome is structurally undefined otherwise).", search_col)
    } else {
      "No search-only filtering applied."
    },
    if (n_dropped_na_outcome > 0) {
      sprintf("Dropped %d of %d rows with NA %s before scoring.", n_dropped_na_outcome, n_before_na_drop, actual_col)
    },
    paste0(
      "When base rates differ across groups, a calibrated classifier (equal PPV) ",
      "cannot generally equalize both FPR and FNR simultaneously (Chouldechova 2017; ",
      "Kleinberg, Mullainathan & Raghavan 2016) -- the trade-off above is reported, not resolved."
    )
  )

  structure(out, class = c("duboisR_subpop_disparities", class(out)), notes = notes)
}

#' @export
print.duboisR_subpop_disparities <- function(x, ...) {
  cat(md_table(as.data.frame(x)), "\n\n")
  cli::cli_bullets(stats::setNames(attr(x, "notes"), rep("i", length(attr(x, "notes")))))
  invisible(x)
}

#' @export
plot.duboisR_subpop_disparities <- function(x, metrics = c("TPR", "FPR", "PPV"), ...) {
  long <- do.call(rbind, lapply(metrics, function(m) {
    tibble::tibble(group = x$group, metric = m, value = x[[m]])
  }))
  ggplot2::ggplot(long, ggplot2::aes(x = .data$group, y = .data$value, fill = .data$group)) +
    ggplot2::geom_col() +
    ggplot2::facet_wrap(~metric) +
    ggplot2::coord_flip() +
    ggplot2::theme_minimal(base_size = 14) +
    ggplot2::labs(x = "", y = "", title = "Subpopulation disparities") +
    ggplot2::theme(legend.position = "none")
}
