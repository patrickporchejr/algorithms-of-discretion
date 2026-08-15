# Descriptive (non-regression) Veil of Darkness charts: a purely
# share/ratio view of the same daylight/dark comparison
# fit_veil_of_darkness() tests with a GLM -- the stop decision only. Every
# function here takes already-prepared data (see
# prepare_veil_of_darkness_data()) rather than doing any daylight
# classification itself -- that stays a single, tested code path in
# veil_of_darkness.R.
#
# Search-rate disparity (summarize_county_search_rates()) used to live in
# this file too, paired with the VoD-ratio chart for a "does the disparity
# concentrate in the stop or the search" comparison. It moved out: search
# rate isn't restricted to daylight/dark or the intertwilight window at all
# -- its only tie to Veil of Darkness was that comparison framing, and it
# belongs with the rest of the search-decision diagnostics instead (see
# duboisR/R/threshold_test.R -- summarize_county_search_rates() itself still
# lives here since it's a generic aggregation, not VoD-specific, but its
# disparity/plot/interpret functions are threshold_test.R's now).

#' Aggregate county-level Veil of Darkness stop-share ratios
#'
#' For each county, the black share of black+white inter-twilight stops in
#' daylight vs. after dark, and their ratio. A descriptive companion to
#' [fit_veil_of_darkness()]'s regression test: if officers can't act on
#' race once it's dark, that share should hold roughly constant across the
#' boundary (`vod_ratio` near 1) rather than shift.
#'
#' @param vod_data Intertwilight-restricted, daylight-classified data --
#'   i.e. `prepare_veil_of_darkness_data(...)$fit_data`, or any data frame
#'   with the same `race_col`/`county_col`/`is_dark` columns.
#' @param race_col String race column. Default `"subject_race"`.
#' @param county_col String county column. Default `"county_fips"`.
#' @return A tibble, one row per county: `<county_col>`,
#'   `pct_black_dark_FALSE`/`pct_black_dark_TRUE` (black share of
#'   black+white stops, daylight/dark), `n_dark_FALSE`/`n_dark_TRUE`,
#'   `total_n`, `vod_ratio` (`pct_black_dark_TRUE / pct_black_dark_FALSE`).
#' @export
summarize_county_vod_disparity <- function(vod_data, race_col = "subject_race", county_col = "county_fips") {
  abort_if_missing_cols(vod_data, c(race_col, county_col, "is_dark"))
  d <- vod_data[vod_data[[race_col]] %in% c("black", "white"), , drop = FALSE]

  agg <- data.frame(
    county = d[[county_col]], is_dark = d$is_dark,
    is_black = as.integer(d[[race_col]] == "black"), n = 1L
  )
  summarized <- stats::aggregate(cbind(is_black, n) ~ county + is_dark, data = agg, FUN = sum)
  summarized$pct_black <- summarized$is_black / summarized$n

  daylight <- summarized[!summarized$is_dark, c("county", "pct_black", "n")]
  dark <- summarized[summarized$is_dark, c("county", "pct_black", "n")]
  names(daylight)[-1] <- paste0(names(daylight)[-1], "_dark_FALSE")
  names(dark)[-1] <- paste0(names(dark)[-1], "_dark_TRUE")

  wide <- merge(daylight, dark, by = "county")
  wide$total_n <- wide$n_dark_FALSE + wide$n_dark_TRUE
  wide$vod_ratio <- wide$pct_black_dark_TRUE / wide$pct_black_dark_FALSE
  names(wide)[names(wide) == "county"] <- county_col

  tibble::as_tibble(wide[order(wide[[county_col]]), ])
}

#' Aggregate statewide racial composition of stops, before vs. after dark
#'
#' The direct, no-regression answer to "does who gets stopped change once
#' it's dark": each race's share of inter-twilight stops, computed
#' separately for the daylight and dark subsets.
#'
#' @inheritParams summarize_county_vod_disparity
#' @return A tibble: `is_dark`, `<race_col>`, `n`, `share` (that race's
#'   share of all stops within its `is_dark` group).
#' @export
summarize_statewide_vod <- function(vod_data, race_col = "subject_race") {
  abort_if_missing_cols(vod_data, c(race_col, "is_dark"))
  agg <- data.frame(is_dark = vod_data$is_dark, race = vod_data[[race_col]], n = 1L)
  counted <- stats::aggregate(n ~ is_dark + race, data = agg, FUN = sum)
  totals <- stats::aggregate(n ~ is_dark, data = agg, FUN = sum)
  counted$share <- counted$n / totals$n[match(counted$is_dark, totals$is_dark)]
  names(counted)[names(counted) == "race"] <- race_col

  tibble::as_tibble(counted[order(counted$is_dark, counted[[race_col]]), ])
}

#' Aggregate county-level search rates by race
#'
#' Unlike [summarize_county_vod_disparity()], this runs against the full
#' dataset, not the intertwilight-restricted `vod_data` -- the search
#' decision is a separate discretion point from the stop decision the Veil
#' of Darkness design targets, and isn't bound to that clock-time window.
#'
#' @param data A data frame (e.g. the full audit-ready stops data).
#' @param outcome_var String logical/0-1 search column. Default
#'   `"search_conducted"`.
#' @inheritParams summarize_county_vod_disparity
#' @return A tibble, one row per (county, race): `<county_col>`,
#'   `<race_col>`, `n_searches`, `n_total` (non-`NA` `outcome_var` rows),
#'   `search_rate`.
#' @export
summarize_county_search_rates <- function(data, outcome_var = "search_conducted",
                                           race_col = "subject_race", county_col = "county_fips") {
  abort_if_missing_cols(data, c(outcome_var, race_col, county_col))
  agg <- .dubois_count_searches(data, race_col, county_col, outcome_var)
  agg$search_rate <- agg$S / agg$n
  names(agg)[names(agg) == "S"] <- "n_searches"
  names(agg)[names(agg) == "n"] <- "n_total"
  names(agg)[names(agg) == "race"] <- race_col
  names(agg)[names(agg) == "group"] <- county_col

  tibble::as_tibble(agg[order(agg[[county_col]], agg[[race_col]]), ])
}

#' Plot the county-level Veil of Darkness ratio (chart 1)
#'
#' @param county_vod_disparity Output of [summarize_county_vod_disparity()].
#' @param min_n Minimum `total_n` for a county to be plotted. Default `30`.
#' @return A `ggplot`.
#' @export
plot_county_vod_disparity <- function(county_vod_disparity, min_n = 30) {
  abort_if_missing_cols(county_vod_disparity, c("total_n", "vod_ratio"))
  plot_data <- county_vod_disparity[county_vod_disparity$total_n >= min_n, ]
  ggplot2::ggplot(plot_data, ggplot2::aes(x = .data$total_n, y = .data$vod_ratio)) +
    ggplot2::geom_point() +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed") +
    ggplot2::scale_x_log10() +
    ggplot2::labs(
      title = "Veil of Darkness (stop decision)",
      x = "Total inter-twilight stops (log scale)",
      y = "Black share of stops: dark / daylight"
    )
}

#' Plain-language interpretation of the county-level VoD ratio scatter
#'
#' Reads the actual per-county ratios behind [plot_county_vod_disparity()]
#' and narrates them -- the median county's ratio, and how many counties
#' lean each direction -- rather than restating what the chart is
#' generically about.
#'
#' @inheritParams plot_county_vod_disparity
#' @return A character scalar (one paragraph).
#' @export
interpret_county_vod_disparity <- function(county_vod_disparity, min_n = 30) {
  abort_if_missing_cols(county_vod_disparity, c("total_n", "vod_ratio"))
  d <- county_vod_disparity[county_vod_disparity$total_n >= min_n, ]

  med <- stats::median(d$vod_ratio, na.rm = TRUE)
  pct_above <- round(100 * mean(d$vod_ratio > 1, na.rm = TRUE))

  reading <- if (abs(med - 1) < 0.1) {
    "close to unchanged -- consistent with race not driving much of who gets pulled over in the typical county"
  } else if (med > 1) {
    "notably higher after dark than in daylight -- a shift consistent with race shaping who gets pulled over"
  } else {
    "notably lower after dark than in daylight -- a shift consistent with race shaping who gets pulled over"
  }

  sprintf(
    "Across counties with enough stops to compare (n ≥ %d), the typical county's Black share of stops after dark is %.2f× what it is in daylight (%d%% of counties are higher than daylight) -- %s.",
    min_n, med, pct_above, reading
  )
}

#' Plot statewide racial composition of stops, before vs. after dark (chart 2)
#'
#' @param statewide_vod Output of [summarize_statewide_vod()].
#' @param race_col String race column name in `statewide_vod`. Default
#'   `"subject_race"`.
#' @return A `ggplot`.
#' @export
plot_statewide_vod <- function(statewide_vod, race_col = "subject_race") {
  abort_if_missing_cols(statewide_vod, c(race_col, "is_dark", "share"))
  plot_data <- statewide_vod
  plot_data$period <- factor(
    ifelse(plot_data$is_dark, "After dark", "Before dark (daylight)"),
    levels = c("Before dark (daylight)", "After dark")
  )
  ggplot2::ggplot(plot_data, ggplot2::aes(x = .data[[race_col]], y = .data$share, fill = .data$period)) +
    ggplot2::geom_col(position = "dodge") +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%")) +
    ggplot2::labs(
      title = "Who gets stopped, before vs. after dark",
      subtitle = "Same clock-hour window on every date -- darkness is the only thing that changes",
      x = NULL, y = "Share of stops", fill = NULL
    ) +
    ggplot2::theme(legend.position = "top")
}

#' Plain-language interpretation of the statewide before/after-dark composition shift
#'
#' Reads the actual point estimates off [summarize_statewide_vod_table()]
#' and narrates them — which race's share of stops moves the most across
#' the daylight/dark boundary, and in which direction — rather than
#' restating what [plot_statewide_vod()] is generically about.
#'
#' @param statewide_vod_table Output of [summarize_statewide_vod_table()].
#' @inheritParams summarize_statewide_vod_table
#' @return A character scalar (one paragraph).
#' @export
interpret_statewide_vod <- function(statewide_vod_table, race_col = "subject_race") {
  before_col <- "Before dark (daylight)"
  after_col <- "After dark"
  abort_if_missing_cols(statewide_vod_table, c(race_col, before_col, after_col))

  d <- statewide_vod_table
  d$delta <- d[[after_col]] - d[[before_col]]
  d <- d[order(-abs(d$delta)), ]

  pct <- function(x) paste0(round(100 * x), "%")
  more_or_less <- function(delta) if (delta > 0) "more" else if (delta < 0) "less" else "the same amount"

  race_sentences <- vapply(seq_len(nrow(d)), function(i) {
    sprintf(
      "%s drivers get stopped %d points %s (from %s to %s)",
      .dubois_cap(d[[race_col]][i]), round(100 * abs(d$delta[i])), more_or_less(d$delta[i]),
      pct(d[[before_col]][i]), pct(d[[after_col]][i])
    )
  }, character(1))

  top <- d[1, ]
  top_direction <- if (top$delta > 0) "pulled over more" else if (top$delta < 0) "pulled over less" else "pulled over about the same amount"
  small_shift_note <- if (abs(top$delta) < 0.02) {
    " -- though even that shift is under 2 points, so this data doesn't show a strong composition change either way"
  } else {
    ""
  }

  sprintf(
    "%s. The clearest shift is %s drivers, who are %s at night%s.",
    paste(race_sentences, collapse = "; "), .dubois_cap(top[[race_col]]), top_direction, small_shift_note
  )
}

#' Pivot the statewide before/after shares to one row per race
#'
#' The numeric read-out that accompanies [plot_statewide_vod()] -- easiest
#' to cite directly in text/tables.
#'
#' @inheritParams plot_statewide_vod
#' @return A tibble: `<race_col>`, `Before dark (daylight)`, `After dark`.
#' @export
summarize_statewide_vod_table <- function(statewide_vod, race_col = "subject_race") {
  abort_if_missing_cols(statewide_vod, c(race_col, "is_dark", "share"))
  before <- statewide_vod[!statewide_vod$is_dark, c(race_col, "share")]
  after <- statewide_vod[statewide_vod$is_dark, c(race_col, "share")]
  names(before)[2] <- "Before dark (daylight)"
  names(after)[2] <- "After dark"
  tibble::as_tibble(merge(before, after, by = race_col))
}

