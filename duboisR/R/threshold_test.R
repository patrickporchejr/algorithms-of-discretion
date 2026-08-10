#' Aggregate stop-level data into sufficient statistics for the Threshold Test
#'
#' Aggregates millions of stop-level rows into a small per-(race, group)
#' table of stop counts, search counts, and search "hit" counts — the
#' sufficient statistics the Threshold Test (see [fit_threshold_test()])
#' needs. This dataset has no "department" field, so `group_col` defaults to
#' `county_fips`, the finest available administrative unit.
#'
#' @param data A data frame.
#' @param race_col String race column. Default `"subject_race"`.
#' @param group_col String grouping column (a department/agency ID in the
#'   original literature; county here). Default `"county_fips"`.
#' @param search_col String logical search column. Default
#'   `"search_conducted"`.
#' @param hit_col String logical/`NA` hit column, `NA` when no search
#'   occurred. Default `"contraband_found"`.
#' @param min_n Minimum stop count `n` for a cell to be retained. Default
#'   `20`.
#' @return A tibble of class `duboisR_suff_stats` with columns `race`,
#'   `<group_col>`, `n`, `S` (searches), `H` (hits), `search_rate`,
#'   `hit_rate` (`NA` when `S == 0`).
#' @export
aggregate_sufficient_statistics <- function(data, race_col = "subject_race", group_col = "county_fips",
                                             search_col = "search_conducted", hit_col = "contraband_found",
                                             min_n = 20) {
  abort_if_missing_cols(data, c(race_col, group_col, search_col, hit_col))

  agg <- data.frame(
    race = data[[race_col]],
    group = data[[group_col]],
    n = 1L,
    S = as.integer(as.logical(data[[search_col]])),
    # contraband_found is structurally NA whenever no search occurred; a
    # non-search cannot have found contraband, so NA is correctly treated
    # as "not a hit" here rather than propagated.
    H = as.integer(data[[hit_col]] %in% TRUE)
  )

  summarized <- stats::aggregate(cbind(n, S, H) ~ race + group, data = agg, FUN = sum)
  summarized$search_rate <- summarized$S / summarized$n
  summarized$hit_rate <- ifelse(summarized$S > 0, summarized$H / summarized$S, NA_real_)
  summarized <- summarized[summarized$n >= min_n, , drop = FALSE]
  summarized <- summarized[order(summarized$race, summarized$group), ]

  out <- tibble::as_tibble(summarized)
  names(out)[names(out) == "group"] <- group_col

  out <- structure(out, class = c("duboisR_suff_stats", class(out)))
  attr(out, "min_n") <- min_n
  attr(out, "group_col") <- group_col
  out
}

#' Predicted hit rate under a Beta(a, b) risk distribution and threshold t
#'
#' `E[p | p > t]` for `p ~ Beta(a, b)`, using the fact that
#' `1 - pbeta(t, a, b) == search_rate` by construction when `t` is derived
#' via [stats::qbeta()] from that same search rate (see [fit_threshold_test()]).
#' @keywords internal
.dubois_predicted_hit_rate <- function(t, a, b, search_rate) {
  (a / (a + b)) * (1 - stats::pbeta(t, a + 1, b)) / search_rate
}

#' Fit a fast (non-hierarchical, non-MCMC) Threshold Test approximation
#'
#' Approximates the hierarchical Bayesian Threshold Test of Simoiu,
#' Corbett-Davies & Goel (2017) for infra-marginality without MCMC. Each
#' stopped driver of race `r` has a latent risk `p ~ Beta(a_r, b_r)`
#' (shared per race across groups — the simplification vs. the full
#' hierarchical model), and is searched iff `p` exceeds a group-specific
#' threshold `t_{r,d}`. Given `(a_r, b_r)`, a group's threshold is *derived
#' in closed form* from its own observed search rate
#' (`t_rd = qbeta(1 - search_rate, a_r, b_r)`) rather than estimated as a
#' free per-cell parameter — this is what makes the method fast. `(a_r,
#' b_r)` are then fit once per race via [stats::optim()], minimizing
#' weighted squared error between the model's predicted hit rate and each
#' group's observed hit rate.
#'
#' This is a from-first-principles frequentist point-estimate procedure
#' consistent with the same Beta signal/threshold model as the cited
#' literature — it is **not** a verbatim reproduction of any published
#' "fast approximation" implementation. It provides no partial pooling
#' across sparse groups and no credible intervals (point estimates only).
#' Describe results as "in the spirit of," not "identical to," Simoiu et
#' al. 2017 / Pierson et al. 2020.
#'
#' @param suff_stats Output of [aggregate_sufficient_statistics()].
#' @param min_searches Minimum `S` for a cell to be included in the `(a_r,
#'   b_r)` fit (hit rate is undefined/unstable below this). Default `5`.
#'   At least 2 qualifying cells per race are required to identify `(a_r,
#'   b_r)`.
#' @param weight One of `"searches"` (default, weight by `S` so noisy
#'   small-sample hit rates don't dominate), `"n"`, or `"none"`.
#' @param optim_control Passed as `control` to [stats::optim()].
#' @return A list of class `duboisR_threshold_fit` with `race_params`
#'   (tibble: `race`, `a`, `b`, `convergence_code`, `n_cells_used_in_fit`),
#'   `thresholds` (tibble: per-group threshold/predicted hit rate, every
#'   cell including those below `min_searches`, flagged `low_confidence`),
#'   and `summary` (tibble: `race`, `mean_threshold_weighted`,
#'   `n_counties`).
#' @export
fit_threshold_test <- function(suff_stats, min_searches = 5, weight = c("searches", "n", "none"),
                                optim_control = list(maxit = 500)) {
  weight <- rlang::arg_match(weight)
  group_col <- attr(suff_stats, "group_col") %||% "group"
  abort_if_missing_cols(suff_stats, c("race", "n", "S", "H", "search_rate", "hit_rate"))

  races <- sort(unique(suff_stats$race))
  race_params_rows <- list()
  threshold_rows <- list()

  for (r in races) {
    cells <- suff_stats[suff_stats$race == r, , drop = FALSE]
    fit_cells <- cells[cells$S >= min_searches, , drop = FALSE]

    if (nrow(fit_cells) < 2) {
      rlang::abort(sprintf(
        "Race '%s' has only %d cell(s) with S >= min_searches (%d); at least 2 are required to identify (a, b).",
        r, nrow(fit_cells), min_searches
      ))
    }

    w <- switch(weight,
      searches = fit_cells$S,
      n = fit_cells$n,
      none = rep(1, nrow(fit_cells))
    )

    objective <- function(par) {
      a <- par[1]; b <- par[2]
      t <- stats::qbeta(1 - fit_cells$search_rate, a, b)
      predicted <- .dubois_predicted_hit_rate(t, a, b, fit_cells$search_rate)
      sum(w * (predicted - fit_cells$hit_rate)^2)
    }

    fit <- stats::optim(
      par = c(a = 1, b = 1), fn = objective, method = "L-BFGS-B",
      lower = c(1e-3, 1e-3), control = optim_control
    )
    a_hat <- unname(fit$par[1]); b_hat <- unname(fit$par[2])

    race_params_rows[[r]] <- tibble::tibble(
      race = r, a = a_hat, b = b_hat,
      convergence_code = fit$convergence, n_cells_used_in_fit = nrow(fit_cells)
    )

    t_all <- stats::qbeta(1 - cells$search_rate, a_hat, b_hat)
    predicted_all <- .dubois_predicted_hit_rate(t_all, a_hat, b_hat, cells$search_rate)

    threshold_rows[[r]] <- tibble::tibble(
      race = r, group = cells[[group_col]], n = cells$n, S = cells$S, H = cells$H,
      search_rate = cells$search_rate, hit_rate = cells$hit_rate,
      threshold_t = t_all, predicted_hit_rate = predicted_all,
      low_confidence = cells$S < min_searches
    )
  }

  race_params <- do.call(rbind, race_params_rows)
  thresholds <- do.call(rbind, threshold_rows)
  names(thresholds)[names(thresholds) == "group"] <- group_col

  summary_tbl <- do.call(rbind, lapply(races, function(r) {
    sub <- thresholds[thresholds$race == r, ]
    tibble::tibble(
      race = r,
      mean_threshold_weighted = stats::weighted.mean(sub$threshold_t, w = sub$n),
      n_counties = nrow(sub)
    )
  }))

  structure(
    list(
      race_params = tibble::as_tibble(race_params),
      thresholds = tibble::as_tibble(thresholds),
      summary = tibble::as_tibble(summary_tbl)
    ),
    class = "duboisR_threshold_fit"
  )
}

#' @export
print.duboisR_threshold_fit <- function(x, ...) {
  cat(md_table(x$race_params), "\n\n")
  cat(md_table(x$summary), "\n")
  invisible(x)
}

#' @export
plot.duboisR_threshold_fit <- function(x, ...) {
  df <- x$thresholds
  races <- unique(x$race_params$race)
  curve_rows <- lapply(races, function(r) {
    params <- x$race_params[x$race_params$race == r, ]
    t_seq <- seq(0.001, 0.999, length.out = 200)
    search_rate <- 1 - stats::pbeta(t_seq, params$a, params$b)
    predicted_hit_rate <- .dubois_predicted_hit_rate(t_seq, params$a, params$b, search_rate)
    tibble::tibble(race = r, search_rate = search_rate, predicted_hit_rate = predicted_hit_rate)
  })
  curves <- do.call(rbind, curve_rows)

  # The fitted curve's x range is the full theoretical [0, 1] support of
  # 1 - pbeta(t, a, b) as t sweeps (0.001, 0.999) -- that's correct math, not
  # a bug, but real per-county search rates are typically well under 15%.
  # Without clamping the viewport to where the observed points actually are,
  # ggplot's default axis autoscaling (driven by the curve's extremes, not
  # the scatter) squeezes every real data point into a sliver against the
  # left edge. coord_cartesian() only zooms the viewport -- it doesn't drop
  # data from the curve computation -- so this is a legibility fix, not a
  # statistical one.
  observed_max_x <- max(df$search_rate, na.rm = TRUE)

  ggplot2::ggplot() +
    ggplot2::geom_line(data = curves, ggplot2::aes(x = .data$search_rate, y = .data$predicted_hit_rate, color = .data$race)) +
    ggplot2::geom_point(data = df, ggplot2::aes(x = .data$search_rate, y = .data$hit_rate, color = .data$race, size = .data$n), alpha = 0.6) +
    ggplot2::coord_cartesian(xlim = c(0, observed_max_x * 1.1), ylim = c(0, 1)) +
    ggplot2::theme_minimal(base_size = 14) +
    ggplot2::labs(x = "Search rate", y = "Hit rate", title = "Threshold Test: search rate vs. hit rate",
                  color = "Race", size = "Stops")
}
