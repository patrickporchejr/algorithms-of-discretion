#' Check whether "neutral" covariates act as proxies for a protected attribute
#'
#' The Wells-Du Bois Identity Proxy test: temporarily treats a protected
#' attribute (e.g. `subject_race`) as the dependent variable and trains a
#' predictive model on the remaining covariates. "Excluding" a protected
#' attribute from a model does not remove race information if it is encoded
#' in other columns (e.g. zip code, county, vehicle age) — if this function
#' can predict the protected attribute well above baseline from covariates
#' the researcher intended to be "neutral," those covariates are acting as
#' identity proxies. This merges what were described as two identical
#' proposals ("Identity Proxy Check" and `check_proxies()`) across the two
#' source documents into one function.
#'
#' @param data A data frame.
#' @param protected_attr String column name of the protected attribute
#'   (e.g. `"subject_race"`). Default `"subject_race"`.
#' @param predictors Character vector of column names to test as candidate
#'   proxies. Must not include `protected_attr` itself.
#' @param method `"rf"` (default) uses [ranger::ranger()] if installed;
#'   `"glm"` is a dependency-free one-vs-rest [stats::glm()] fallback.
#' @param test_prop Proportion of rows (stratified by `protected_attr`) held
#'   out for evaluation. Default `0.2`.
#' @param seed Optional RNG seed for the train/test split.
#' @param warn_threshold `lift` above which the result is `flagged`. Default
#'   `0.10`.
#' @return A list of class `duboisR_proxy_check` with `accuracy`,
#'   `baseline_accuracy` (no-information rate), `lift`, `confusion_matrix`,
#'   `importance` (named numeric vector, which columns are acting as
#'   proxies), `flagged`, and `message`.
#' @export
check_proxies <- function(data, protected_attr = "subject_race", predictors,
                           method = c("rf", "glm"), test_prop = 0.2, seed = NULL,
                           warn_threshold = 0.10) {
  method <- rlang::arg_match(method)
  abort_if_missing_cols(data, c(protected_attr, predictors))
  if (protected_attr %in% predictors) {
    rlang::abort("`predictors` must not include `protected_attr`.")
  }

  model_data <- data[c(protected_attr, predictors)]
  model_data <- model_data[stats::complete.cases(model_data), , drop = FALSE]
  model_data[[protected_attr]] <- factor(model_data[[protected_attr]])

  if (!is.null(seed)) set.seed(seed)
  split <- .dubois_stratified_split(model_data[[protected_attr]], test_prop)
  train <- model_data[split$train, , drop = FALSE]
  test <- model_data[split$test, , drop = FALSE]

  baseline_class <- names(which.max(table(train[[protected_attr]])))
  baseline_accuracy <- mean(as.character(test[[protected_attr]]) == baseline_class)

  fit_result <- if (method == "rf") {
    .dubois_check_proxies_rf(train, test, protected_attr, predictors)
  } else {
    .dubois_check_proxies_glm(train, test, protected_attr, predictors)
  }

  accuracy <- mean(fit_result$predicted == as.character(test[[protected_attr]]))
  confusion_matrix <- table(predicted = fit_result$predicted, actual = as.character(test[[protected_attr]]))
  lift <- accuracy - baseline_accuracy
  flagged <- lift > warn_threshold

  top_vars <- names(sort(fit_result$importance, decreasing = TRUE))[seq_len(min(3, length(fit_result$importance)))]

  message <- if (flagged) {
    sprintf(
      paste0(
        "Identity proxies detected: %s is predictable from 'neutral' covariates ",
        "at %.1f%% accuracy, %.1f points above the %.1f%% no-information baseline. ",
        "Removing %s from a model does not remove race information if it is ",
        "encoded in: %s."
      ),
      protected_attr, 100 * accuracy, 100 * lift, 100 * baseline_accuracy,
      protected_attr, paste(top_vars, collapse = ", ")
    )
  } else {
    sprintf(
      "%s is not strongly predictable from the supplied covariates (%.1f%% accuracy vs. %.1f%% baseline).",
      protected_attr, 100 * accuracy, 100 * baseline_accuracy
    )
  }

  structure(
    list(
      accuracy = accuracy,
      baseline_accuracy = baseline_accuracy,
      lift = lift,
      confusion_matrix = confusion_matrix,
      importance = fit_result$importance,
      flagged = flagged,
      message = message
    ),
    class = "duboisR_proxy_check"
  )
}

#' @keywords internal
.dubois_stratified_split <- function(group, test_prop) {
  idx <- seq_along(group)
  test_idx <- unlist(lapply(split(idx, group), function(g) {
    n_test <- max(1, round(length(g) * test_prop))
    sample(g, min(n_test, length(g) - 1))
  }))
  list(train = setdiff(idx, test_idx), test = test_idx)
}

#' @keywords internal
.dubois_check_proxies_rf <- function(train, test, protected_attr, predictors) {
  rlang::check_installed("ranger", reason = "to run check_proxies(method = \"rf\")")
  f <- stats::as.formula(paste(protected_attr, "~ ."))
  model <- ranger::ranger(f, data = train, importance = "impurity")
  predicted <- as.character(stats::predict(model, data = test)$predictions)
  list(predicted = predicted, importance = model$variable.importance)
}

#' @keywords internal
.dubois_check_proxies_glm <- function(train, test, protected_attr, predictors) {
  levels_r <- levels(train[[protected_attr]])
  rhs <- paste(predictors, collapse = " + ")

  probs <- matrix(NA_real_, nrow = nrow(test), ncol = length(levels_r), dimnames = list(NULL, levels_r))
  importance <- stats::setNames(rep(0, length(predictors)), predictors)

  for (lvl in levels_r) {
    y <- as.integer(train[[protected_attr]] == lvl)
    fit_data <- train[predictors]
    fit_data$.dubois_y <- y
    # A strong identity proxy routinely produces (quasi-)separated fits here
    # -- that IS the signal this diagnostic is designed to surface, not a
    # bug, so the resulting glm.fit convergence warning is expected and
    # suppressed rather than left to alarm the caller.
    fit <- suppressWarnings(
      stats::glm(stats::as.formula(paste(".dubois_y ~", rhs)), data = fit_data, family = "binomial")
    )
    probs[, lvl] <- stats::predict(fit, newdata = test, type = "response")

    coefs <- summary(fit)$coefficients
    z <- abs(coefs[, "z value"])
    z <- z[setdiff(names(z), "(Intercept)")]
    # Match longest predictor names first, claiming their coefficients out of
    # the pool as we go -- otherwise a shorter predictor whose name is a
    # string-prefix of a longer one's (e.g. "hour" vs. a hypothetical
    # "hour_bucket") would have startsWith() match both predictors'
    # model.matrix() coefficient names, silently inflating the shorter
    # predictor's importance with the longer one's coefficients too.
    ordered_predictors <- predictors[order(-nchar(predictors))]
    remaining <- z
    for (p in ordered_predictors) {
      matched <- remaining[startsWith(names(remaining), p)]
      if (length(matched) > 0) {
        importance[[p]] <- max(importance[[p]], max(matched, na.rm = TRUE))
        remaining <- remaining[!startsWith(names(remaining), p)]
      }
    }
  }

  predicted <- levels_r[apply(probs, 1, which.max)]
  list(predicted = predicted, importance = importance)
}

#' @export
print.duboisR_proxy_check <- function(x, ...) {
  if (x$flagged) cli::cli_alert_danger(x$message) else cli::cli_alert_success(x$message)
  invisible(x)
}

#' @export
format.duboisR_proxy_check <- function(x, ...) {
  imp <- tibble::tibble(covariate = names(x$importance), importance = as.numeric(x$importance))
  imp <- imp[order(-imp$importance), ]
  c(
    sprintf("**Identity proxy check** (accuracy = %.1f%%, baseline = %.1f%%, lift = %.1f pts)",
            100 * x$accuracy, 100 * x$baseline_accuracy, 100 * x$lift),
    "",
    x$message,
    "",
    md_table(imp)
  )
}
