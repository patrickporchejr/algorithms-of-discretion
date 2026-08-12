#' Relevel a factor column to a specified reference level
#'
#' `glm()`'s default factor encoding picks the reference level
#' alphabetically, which for e.g. `subject_race` would silently pick
#' `"black"` as the baseline. This helper makes the reference level an
#' explicit, validated choice.
#'
#' @param data A data frame.
#' @param col String column name to relevel.
#' @param ref String level of `col` to use as the reference.
#' @return `data` with `data[[col]]` converted to a releveled factor.
#' @export
dubois_relevel <- function(data, col, ref) {
  abort_if_missing_cols(data, col)
  levels_present <- unique(as.character(data[[col]]))
  if (!ref %in% levels_present) {
    rlang::abort(sprintf(
      "`ref` = %s is not an observed level of `%s`. Observed levels: %s",
      shQuote(ref), col, paste(shQuote(levels_present), collapse = ", ")
    ))
  }
  data[[col]] <- stats::relevel(factor(data[[col]]), ref = ref)
  data
}

#' Build a GLM formula conditionally from a set of selected control terms
#'
#' Ports the `paste()`-chain formula-building logic previously inline in
#' `r_dashboard/R/mod_regression.R` into a reusable, testable function.
#'
#' @param outcome String, the LHS/dependent variable name (e.g.
#'   `"search_conducted"`).
#' @param base_term String, an RHS term always included (e.g.
#'   `"subject_race"`).
#' @param control_map Named list mapping control keys to RHS term strings,
#'   e.g. `list(demographics = "subject_sex", time = "factor(hour)")`.
#' @param controls_selected Character vector of keys from `control_map` to
#'   include. Keys not present in `control_map` are ignored.
#' @return A [stats::formula].
#' @export
build_formula <- function(outcome, base_term, control_map, controls_selected) {
  f <- paste(outcome, "~", base_term)
  selected_terms <- control_map[intersect(names(control_map), controls_selected)]
  for (term in selected_terms) {
    f <- paste(f, "+", term)
  }
  stats::as.formula(f)
}

#' Fit an audit GLM with closed-form Wald confidence intervals
#'
#' Fits `glm(formula, data, family)`, then computes confidence intervals in
#' closed form from `summary(model)$coefficients` (`estimate +/- z*SE` on
#' the link scale, then exponentiated if requested) rather than via
#' `broom::tidy(model, conf.int = TRUE)`. `broom` delegates to
#' `confint.glm()`, which defaults to profile-likelihood CIs — these require
#' iteratively refitting the model per coefficient, which is fine at
#' textbook sample sizes but effectively hangs at millions of rows. Wald CIs
#' are `O(1)` relative to the fit (no refitting) and are the standard choice
#' at this scale, since asymptotic normality of the MLE is a safe assumption
#' well before millions of rows.
#'
#' @param data A data frame.
#' @param formula A [stats::formula] (e.g. from [build_formula()]).
#' @param family Passed to [stats::glm()]. Default `"binomial"`.
#' @param conf_level Confidence level for the Wald interval. Default `0.95`.
#' @param exponentiate If `TRUE` (default), exponentiate `estimate` and its
#'   CI (e.g. to report odds ratios for a binomial/logit fit).
#' @return A list of class `duboisR_glm_fit` with elements:
#'   \describe{
#'     \item{model}{The fitted [stats::glm] object.}
#'     \item{summary}{A tibble with columns `term`, `estimate`, `std.error`,
#'       `statistic`, `p.value`, `conf.low`, `conf.high`.}
#'   }
#' @export
fit_audit_glm <- function(data, formula, family = "binomial", conf_level = 0.95, exponentiate = TRUE) {
  model <- stats::glm(formula, data = data, family = family)

  coefs <- summary(model)$coefficients
  df <- tibble::as_tibble(coefs, rownames = "term")
  colnames(df) <- c("term", "estimate", "std.error", "statistic", "p.value")

  z <- stats::qnorm(1 - (1 - conf_level) / 2)
  df$conf.low <- df$estimate - z * df$std.error
  df$conf.high <- df$estimate + z * df$std.error

  if (exponentiate) {
    df$estimate <- exp(df$estimate)
    df$conf.low <- exp(df$conf.low)
    df$conf.high <- exp(df$conf.high)
  }

  structure(list(model = model, summary = df), class = "duboisR_glm_fit")
}

#' Predicted probabilities for each level of a grouping variable
#'
#' Complements the reference-category odds ratios in `fit$summary` (each
#' relative to a baseline level, e.g. "white") with an absolute view: for
#' every level of `group_var`, the model's predicted probability of the
#' outcome, holding every other predictor at a reference value (mean for
#' numeric predictors, the most common observed value for categorical
#' ones). Unlike odds ratios, this shows every level of `group_var`
#' directly, including whichever level the model treats as the reference.
#'
#' Predictions are built from `data` (not `model.frame(fit$model)`) and
#' scored via `predict(newdata = ...)` so that formula terms computed from
#' a raw column (e.g. `factor(hour)`) are re-derived correctly -- passing
#' the model frame's own `factor(hour)` column back in as `newdata` would
#' not match the original formula's term.
#'
#' @param fit A `duboisR_glm_fit` (from [fit_audit_glm()]).
#' @param data The data frame `fit` was fitted on.
#' @param group_var String, the predictor to vary (e.g. `"subject_race"`).
#' @param conf_level Confidence level for the Wald interval. Default `0.95`.
#' @return A tibble with columns `level`, `probability`, `conf.low`,
#'   `conf.high`.
#' @export
predicted_probabilities <- function(fit, data, group_var, conf_level = 0.95) {
  abort_if_missing_cols(data, group_var)
  model <- fit$model

  predictor_vars <- all.vars(stats::formula(model))[-1]
  other_vars <- setdiff(predictor_vars, group_var)

  ref_row <- lapply(data[other_vars], function(col) {
    if (is.numeric(col)) {
      mean(col, na.rm = TRUE)
    } else {
      tab <- table(col)
      names(tab)[which.max(tab)]
    }
  })

  levels_group <- levels(factor(data[[group_var]]))
  newdata <- as.data.frame(ref_row, stringsAsFactors = FALSE)[rep(1, length(levels_group)), , drop = FALSE]
  newdata[[group_var]] <- levels_group

  pred <- stats::predict(model, newdata = newdata, type = "link", se.fit = TRUE)
  z <- stats::qnorm(1 - (1 - conf_level) / 2)

  tibble::tibble(
    level = levels_group,
    probability = stats::plogis(pred$fit),
    conf.low = stats::plogis(pred$fit - z * pred$se.fit),
    conf.high = stats::plogis(pred$fit + z * pred$se.fit)
  )
}

#' @export
print.duboisR_glm_fit <- function(x, ...) {
  cat(md_table(x$summary), "\n")
  invisible(x)
}
