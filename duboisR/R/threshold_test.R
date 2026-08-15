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

  counts <- .dubois_count_searches(data, race_col, group_col, search_col)

  # contraband_found is structurally NA whenever no search occurred; a
  # non-search cannot have found contraband, so NA is correctly treated
  # as "not a hit" here rather than propagated.
  hits <- data.frame(
    race = data[[race_col]], group = data[[group_col]],
    H = as.integer(data[[hit_col]] %in% TRUE)
  )
  hits <- stats::aggregate(H ~ race + group, data = hits, FUN = sum)

  summarized <- merge(counts, hits, by = c("race", "group"))
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

#' Restrict stop-level data to the highest-volume counties
#'
#' A coarser, pre-aggregation companion to [aggregate_sufficient_statistics()]'s
#' own per-(race, county) `min_n`: this filters at the whole-county level
#' (every race pooled together), before any race split, to counties with
#' enough total stops to be a priori stable, then keeps only the `top_n`
#' largest of those. Motivated by [fit_threshold_test()] tending to land on
#' a near-degenerate (huge `a`, `b`) risk distribution when many small,
#' noisy counties dominate its per-cell squared-error objective — this is
#' one way to check whether that degeneracy is a data-sparsity artifact
#' rather than a real near-point-mass risk distribution.
#'
#' @param data A data frame.
#' @param county_col String county column. Default `"county_fips"`.
#' @param min_stops Minimum total stops (any race) for a county to be
#'   eligible. Default `1000`.
#' @param top_n Keep at most this many of the largest eligible counties.
#'   Default `100`. Pass `Inf` to keep every county that clears `min_stops`.
#' @return `data`, filtered to rows in the kept counties.
#' @export
restrict_to_top_counties <- function(data, county_col = "county_fips", min_stops = 1000, top_n = 100) {
  abort_if_missing_cols(data, county_col)

  agg <- data.frame(county = data[[county_col]], n = 1L)
  counts <- stats::aggregate(n ~ county, data = agg, FUN = sum)
  counts <- counts[counts$n >= min_stops, , drop = FALSE]
  counts <- counts[order(-counts$n), , drop = FALSE]
  keep <- utils::head(counts$county, top_n)

  data[data[[county_col]] %in% keep, , drop = FALSE]
}

#' Aggregate county-level search-rate disparity, every race vs. a reference
#'
#' Pivots [summarize_county_search_rates()]'s long output against a single
#' reference race and computes each other race's search-rate ratio to it —
#' long format, one row per (county, non-reference race), so it covers
#' every race in the data at once instead of a hardcoded pair. This is a
#' pure frequency comparison (how often someone gets searched at all) —
#' see [aggregate_sufficient_statistics()]/[fit_threshold_test()] for the
#' separate question of how *justified* those searches are.
#'
#' @param county_search_rates Output of [summarize_county_search_rates()].
#' @param race_col String race column. Default `"subject_race"`.
#' @param county_col String county column. Default `"county_fips"`.
#' @param reference_race Race every other race's search rate is compared
#'   against. Default `"white"`.
#' @return A tibble, one row per (county, non-reference race):
#'   `<county_col>`, `<race_col>`, `n_searches`, `search_rate`,
#'   `n_searches_reference`, `search_rate_reference`, `disparity_ratio`
#'   (`search_rate / search_rate_reference`).
#' @export
summarize_county_search_disparity <- function(county_search_rates, race_col = "subject_race",
                                               county_col = "county_fips", reference_race = "white") {
  abort_if_missing_cols(county_search_rates, c(race_col, county_col, "n_searches", "search_rate"))

  ref <- county_search_rates[
    county_search_rates[[race_col]] == reference_race, c(county_col, "n_searches", "search_rate")
  ]
  names(ref)[-1] <- paste0(names(ref)[-1], "_reference")

  other <- county_search_rates[county_search_rates[[race_col]] != reference_race, , drop = FALSE]

  wide <- merge(other, ref, by = county_col)
  wide$disparity_ratio <- wide$search_rate / wide$search_rate_reference

  tibble::as_tibble(wide[order(wide[[county_col]], wide[[race_col]]), ])
}

#' Plot county-level search-rate disparity (chart 3), every race vs. a reference
#'
#' @param county_search_disparity Output of
#'   [summarize_county_search_disparity()].
#' @param min_n Minimum `n_searches`/`n_searches_reference` for a county to
#'   be plotted. Default `30`.
#' @param race_col String race column name in `county_search_disparity`.
#'   Default `"subject_race"`.
#' @return A `ggplot`.
#' @export
plot_county_search_disparity <- function(county_search_disparity, min_n = 30, race_col = "subject_race") {
  abort_if_missing_cols(
    county_search_disparity, c("n_searches", "n_searches_reference", "disparity_ratio", race_col)
  )
  plot_data <- county_search_disparity[
    county_search_disparity$n_searches >= min_n & county_search_disparity$n_searches_reference >= min_n,
  ]
  ggplot2::ggplot(plot_data, ggplot2::aes(
    x = .data$n_searches + .data$n_searches_reference, y = .data$disparity_ratio, color = .data[[race_col]]
  )) +
    ggplot2::geom_point(alpha = 0.6) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed") +
    ggplot2::scale_x_log10() +
    ggplot2::labs(
      title = "How often drivers get searched, by county",
      subtitle = "Frequency of searches vs. a reference race -- not whether the searches find anything",
      x = "Total searches (log scale)",
      y = "Search rate ratio vs. reference race",
      color = "Race"
    )
}

#' Plain-language interpretation of the county-level search-rate disparity
#'
#' Reads the actual per-race search-rate ratios behind
#' [plot_county_search_disparity()] and narrates them — each race's median
#' county ratio vs. the reference race, and how many counties lean above
#' parity — rather than restating what the chart is generically about.
#'
#' @inheritParams plot_county_search_disparity
#' @param reference_race Race every ratio is computed against. Default
#'   `"white"`.
#' @return A character scalar (one paragraph).
#' @export
interpret_search_rate_disparity <- function(county_search_disparity, min_n = 30, race_col = "subject_race",
                                             reference_race = "white") {
  abort_if_missing_cols(
    county_search_disparity, c("n_searches", "n_searches_reference", "disparity_ratio", race_col)
  )
  d <- county_search_disparity[
    county_search_disparity$n_searches >= min_n & county_search_disparity$n_searches_reference >= min_n,
  ]

  ref_label <- .dubois_cap(reference_race)
  races <- sort(unique(as.character(d[[race_col]])))
  race_sentences <- vapply(races, function(r) {
    sub <- d[d[[race_col]] == r, ]
    med <- stats::median(sub$disparity_ratio, na.rm = TRUE)
    pct_above <- round(100 * mean(sub$disparity_ratio > 1, na.rm = TRUE))
    sprintf(
      "the typical county searches %s drivers at %.2f× the rate of %s drivers (%d%% of counties above parity)",
      .dubois_cap(r), med, ref_label, pct_above
    )
  }, character(1))

  sprintf("Across counties with enough searches to compare (n ≥ %d): %s.", min_n, paste(race_sentences, collapse = "; "))
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

#' Classic (Ayres 2002) outcome test: race-level hit-rate comparison
#'
#' The naive test [fit_threshold_test()] exists to correct for
#' infra-marginality: pools every stop-level search/hit across groups into
#' one search-weighted hit rate per race, then reads a lower hit rate than
#' `reference_race` as evidence that race is searched at a lower
#' evidentiary bar. Provided as an explicit uncorrected baseline to compare
#' against the Threshold Test's corrected estimate — see
#' [compare_outcome_threshold_test()].
#'
#' @param suff_stats Output of [aggregate_sufficient_statistics()].
#' @param reference_race Race every gap is computed against. Default
#'   `"white"`.
#' @return A tibble: `race`, `S`, `H`, `hit_rate` (search-weighted, pooled
#'   across every group), `hit_rate_gap` (`hit_rate` minus
#'   `reference_race`'s `hit_rate`).
#' @export
compute_outcome_test <- function(suff_stats, reference_race = "white") {
  abort_if_missing_cols(suff_stats, c("race", "S", "H"))
  agg <- stats::aggregate(cbind(S, H) ~ race, data = suff_stats, FUN = sum)
  agg$hit_rate <- agg$H / agg$S

  if (!reference_race %in% agg$race) {
    rlang::abort(sprintf(
      "reference_race '%s' not found among races in suff_stats: %s",
      reference_race, paste(sort(agg$race), collapse = ", ")
    ))
  }
  agg$hit_rate_gap <- agg$hit_rate - agg$hit_rate[agg$race == reference_race]

  tibble::as_tibble(agg[order(agg$race), ])
}

#' Compare the naive outcome test to the Threshold Test's corrected estimate
#'
#' Puts the classic outcome test's hit-rate gap ([compute_outcome_test()])
#' next to the Threshold Test's inferred-threshold gap
#' (`threshold_fit$summary`), both relative to the same `reference_race`,
#' so the two can be read side by side. They live on different scales — an
#' observed conditional probability vs. an inferred risk cutoff — so this
#' isn't a before/after difference of one number; it's whether the two
#' methods agree on *direction*. A negative gap means "held to a lower bar"
#' under either metric (lower hit rate among the searched, or a lower
#' inferred risk threshold for triggering a search), so matching signs mean
#' the two methods agree; a sign flip is the interesting case — it's the
#' signature of infra-marginality distorting the naive test (see Simoiu,
#' Corbett-Davies & Goel 2017, cited in [fit_threshold_test()]).
#'
#' @param suff_stats Output of [aggregate_sufficient_statistics()].
#' @param threshold_fit Output of [fit_threshold_test()], fit on the same
#'   `suff_stats` (or a superset covering the same races).
#' @param reference_race Race both gaps are computed against. Default
#'   `"white"`.
#' @return A tibble: `race`, `hit_rate`, `hit_rate_gap`,
#'   `mean_threshold_weighted`, `threshold_gap`, `agrees_in_direction`
#'   (`TRUE` when `hit_rate_gap` and `threshold_gap` share a sign,
#'   including both exactly `0`).
#' @export
compare_outcome_threshold_test <- function(suff_stats, threshold_fit, reference_race = "white") {
  if (!inherits(threshold_fit, "duboisR_threshold_fit")) {
    rlang::abort("threshold_fit must be the output of fit_threshold_test().")
  }

  outcome <- compute_outcome_test(suff_stats, reference_race = reference_race)
  thr <- threshold_fit$summary
  if (!reference_race %in% thr$race) {
    rlang::abort(sprintf(
      "reference_race '%s' not found among races in threshold_fit$summary: %s",
      reference_race, paste(sort(thr$race), collapse = ", ")
    ))
  }
  thr$threshold_gap <- thr$mean_threshold_weighted - thr$mean_threshold_weighted[thr$race == reference_race]

  out <- merge(
    outcome[c("race", "hit_rate", "hit_rate_gap")],
    thr[c("race", "mean_threshold_weighted", "threshold_gap")],
    by = "race"
  )
  out$agrees_in_direction <- sign(out$hit_rate_gap) == sign(out$threshold_gap)

  tibble::as_tibble(out[order(out$race), ])
}

#' Plot the naive outcome test next to the Threshold Test's corrected estimate
#'
#' Two panels, race on the x-axis in both: the classic outcome test's
#' pooled hit rate (left) and the Threshold Test's weighted mean inferred
#' threshold (right), each with a dashed reference line at
#' `reference_race`'s value. Read this as "does the naive test's story
#' about who faces a lower bar survive the infra-marginality correction" —
#' not as one quantity moving from an uncorrected to a corrected value,
#' since hit rate and threshold live on different scales.
#'
#' @param comparison Output of [compare_outcome_threshold_test()].
#' @param reference_race Race the dashed reference lines mark. Default
#'   `"white"`.
#' @return A `patchwork` object.
#' @export
plot_outcome_threshold_comparison <- function(comparison, reference_race = "white") {
  abort_if_missing_cols(comparison, c("race", "hit_rate", "mean_threshold_weighted"))
  rlang::check_installed("patchwork", reason = "to combine these two plots side by side.")

  ref_hit_rate <- comparison$hit_rate[comparison$race == reference_race]
  ref_threshold <- comparison$mean_threshold_weighted[comparison$race == reference_race]

  outcome_plot <- ggplot2::ggplot(comparison, ggplot2::aes(x = .data$race, y = .data$hit_rate)) +
    ggplot2::geom_col() +
    ggplot2::geom_hline(yintercept = ref_hit_rate, linetype = "dashed") +
    ggplot2::labs(title = "Naive outcome test", subtitle = "Pooled hit rate by race", x = NULL, y = "Hit rate")

  threshold_plot <- ggplot2::ggplot(comparison, ggplot2::aes(x = .data$race, y = .data$mean_threshold_weighted)) +
    ggplot2::geom_col() +
    ggplot2::geom_hline(yintercept = ref_threshold, linetype = "dashed") +
    ggplot2::labs(
      title = "Threshold Test (corrected)", subtitle = "Weighted mean inferred threshold by race",
      x = NULL, y = "Threshold t"
    )

  outcome_plot + threshold_plot + patchwork::plot_annotation(
    title = "Naive outcome test vs. infra-marginality-corrected Threshold Test",
    subtitle = paste0(
      "Dashed line = ", reference_race, "'s value. Different scales -- compare the direction of the gap, not its magnitude."
    )
  )
}

#' Plain-language interpretation of the fitted Threshold Test
#'
#' Reads the actual per-race weighted mean thresholds off
#' `threshold_fit$summary` and narrates them relative to `reference_race`,
#' then flags any race whose fitted `(a, b)` is near-degenerate or didn't
#' converge (`threshold_fit$race_params`) — the same criteria
#' `plot.duboisR_threshold_fit()` dashes on the chart — so a reader doesn't
#' take a degenerate fit's number at face value.
#'
#' @param threshold_fit Output of [fit_threshold_test()].
#' @param reference_race Race every comparison is phrased against. Default
#'   `"white"`.
#' @return A character scalar (one paragraph).
#' @export
interpret_threshold_fit <- function(threshold_fit, reference_race = "white") {
  summary_tbl <- threshold_fit$summary
  if (!reference_race %in% summary_tbl$race) {
    rlang::abort(sprintf(
      "reference_race '%s' not found among races in threshold_fit$summary: %s",
      reference_race, paste(sort(summary_tbl$race), collapse = ", ")
    ))
  }
  ref_threshold <- summary_tbl$mean_threshold_weighted[summary_tbl$race == reference_race]

  # "X" / "X and Y" / "X, Y, and Z" -- an Oxford-comma list, capitalized.
  list_and <- function(x) {
    x <- .dubois_cap(x)
    if (length(x) == 1) {
      x
    } else if (length(x) == 2) {
      paste(x, collapse = " and ")
    } else {
      paste0(paste(x[-length(x)], collapse = ", "), ", and ", x[length(x)])
    }
  }

  ref_label <- .dubois_cap(reference_race)
  race_sentences <- vapply(seq_len(nrow(summary_tbl)), function(i) {
    r <- as.character(summary_tbl$race[i])
    t <- summary_tbl$mean_threshold_weighted[i]
    if (r == reference_race) {
      return(sprintf("%s drivers' inferred threshold is %.2f", .dubois_cap(r), t))
    }
    gap <- t - ref_threshold
    if (abs(gap) < 0.02) {
      sprintf("%s drivers' inferred threshold is %.2f, about the same as %s drivers'", .dubois_cap(r), t, ref_label)
    } else if (gap < 0) {
      sprintf(
        "%s drivers' inferred threshold is %.2f, notably lower than %s drivers' -- a lower bar to search",
        .dubois_cap(r), t, ref_label
      )
    } else {
      sprintf(
        "%s drivers' inferred threshold is %.2f, notably higher than %s drivers' -- a higher bar to search",
        .dubois_cap(r), t, ref_label
      )
    }
  }, character(1))

  rp <- threshold_fit$race_params
  nonconverged <- rp$race[rp$convergence_code != 0]
  near_degenerate <- rp$race[.dubois_near_degenerate(rp$a, rp$b)]

  caveat <- ""
  if (length(near_degenerate) > 0) {
    caveat <- paste0(
      " Caution: ", list_and(near_degenerate), "'s fitted risk distribution is near-degenerate ",
      "(near-zero variance), so treat ", if (length(near_degenerate) > 1) "those thresholds" else "that threshold",
      " as suggestive, not precise."
    )
  }
  if (length(nonconverged) > 0) {
    caveat <- paste0(
      caveat, " ", list_and(nonconverged), "'s optimizer did not fully converge; treat ",
      if (length(nonconverged) > 1) "those fits" else "that fit", " with extra caution."
    )
  }

  paste0(paste(race_sentences, collapse = "; "), ".", caveat)
}

#' Plain-language interpretation of the naive-vs-corrected outcome test comparison
#'
#' Reads [compare_outcome_threshold_test()]'s actual gaps and narrates, per
#' race, whether the naive outcome test's story survives the Threshold
#' Test's infra-marginality correction — a sign flip between `hit_rate_gap`
#' and `threshold_gap` (`agrees_in_direction == FALSE`) is the interesting
#' case, not a matching one.
#'
#' @param comparison Output of [compare_outcome_threshold_test()].
#' @param reference_race Race every gap is phrased against. Default
#'   `"white"`.
#' @return A character scalar (one paragraph).
#' @export
interpret_outcome_threshold_comparison <- function(comparison, reference_race = "white") {
  other <- comparison[comparison$race != reference_race, , drop = FALSE]
  if (nrow(other) == 0) {
    rlang::abort("comparison has no races other than reference_race to narrate.")
  }

  ref_label <- .dubois_cap(reference_race)
  race_sentences <- vapply(seq_len(nrow(other)), function(i) {
    row <- other[i, ]
    hit_pts <- round(100 * abs(row$hit_rate_gap))
    hit_dir <- if (row$hit_rate_gap < 0) "lower than" else if (row$hit_rate_gap > 0) "higher than" else "the same as"
    agreement <- if (isTRUE(row$agrees_in_direction)) {
      "the corrected Threshold Test agrees"
    } else {
      "the corrected Threshold Test disagrees -- a sign the naive gap may be an infra-marginality artifact"
    }
    sprintf(
      "%s drivers' naive hit rate is %d points %s %s drivers' -- %s",
      .dubois_cap(row$race), hit_pts, hit_dir, ref_label, agreement
    )
  }, character(1))

  paste0(paste(race_sentences, collapse = "; "), ".")
}

#' @export
print.duboisR_threshold_fit <- function(x, ...) {
  cat(md_table(x$race_params), "\n\n")
  cat(md_table(x$summary), "\n")
  invisible(x)
}

#' Is a fitted `(a, b)` pair near-degenerate (a near-point-mass risk distribution)?
#'
#' Same threshold the Shiny Threshold Test module already warns on
#' (`r_dashboard/R/mod_threshold_test.R`) — shared here so
#' `plot.duboisR_threshold_fit()` flags the same fits, not a second opinion.
#' @keywords internal
.dubois_near_degenerate <- function(a, b) a > 1e6 | b > 1e6

#' @export
plot.duboisR_threshold_fit <- function(x, ...) {
  df <- x$thresholds
  races <- unique(x$race_params$race)
  curve_rows <- lapply(races, function(r) {
    params <- x$race_params[x$race_params$race == r, ]
    t_seq <- seq(0.001, 0.999, length.out = 200)
    search_rate <- 1 - stats::pbeta(t_seq, params$a, params$b)
    predicted_hit_rate <- .dubois_predicted_hit_rate(t_seq, params$a, params$b, search_rate)
    tibble::tibble(
      race = r, search_rate = search_rate, predicted_hit_rate = predicted_hit_rate,
      near_degenerate = .dubois_near_degenerate(params$a, params$b)
    )
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

  # A near-point-mass Beta(a, b) collapses the fitted curve to a near-flat
  # line -- correct given the math, but easy to misread as a stray
  # reference/annotation line (like the dashed parity lines used elsewhere
  # in this dashboard) rather than what it actually is: that race's own
  # fitted curve, degenerated. Dash it and say so in the subtitle instead
  # of letting a flat colored line pass without explanation.
  any_degenerate <- any(curves$near_degenerate)

  ggplot2::ggplot() +
    ggplot2::geom_line(
      data = curves,
      ggplot2::aes(x = .data$search_rate, y = .data$predicted_hit_rate, color = .data$race, linetype = .data$near_degenerate)
    ) +
    ggplot2::geom_point(data = df, ggplot2::aes(x = .data$search_rate, y = .data$hit_rate, color = .data$race, size = .data$n), alpha = 0.6) +
    ggplot2::scale_linetype_manual(values = c("FALSE" = "solid", "TRUE" = "22"), guide = "none") +
    ggplot2::coord_cartesian(xlim = c(0, observed_max_x * 1.1), ylim = c(0, 1)) +
    ggplot2::theme_minimal(base_size = 14) +
    ggplot2::labs(
      x = "Search rate", y = "Hit rate", title = "Threshold Test: search rate vs. hit rate",
      subtitle = if (any_degenerate) "Dashed curve = near-degenerate fit for that race -- treat with caution" else NULL,
      color = "Race", size = "Stops"
    )
}
