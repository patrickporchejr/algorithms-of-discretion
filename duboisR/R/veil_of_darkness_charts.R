# Descriptive (non-regression) Veil of Darkness charts: a purely
# share/ratio view of the same daylight/dark comparison
# fit_veil_of_darkness() tests with a GLM, plus the search-rate disparity
# (a separate, post-stop discretion point) alongside it for scale
# comparison. Every function here takes already-prepared data (see
# prepare_veil_of_darkness_data()) rather than doing any daylight
# classification itself -- that stays a single, tested code path in
# veil_of_darkness.R.

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
  d <- data.frame(
    county = data[[county_col]], race = data[[race_col]],
    searched = as.integer(as.logical(data[[outcome_var]])), n = 1L
  )
  d <- d[!is.na(d$searched), , drop = FALSE]

  agg <- stats::aggregate(cbind(searched, n) ~ county + race, data = d, FUN = sum)
  agg$search_rate <- agg$searched / agg$n
  names(agg)[names(agg) == "searched"] <- "n_searches"
  names(agg)[names(agg) == "n"] <- "n_total"
  names(agg)[names(agg) == "county"] <- county_col
  names(agg)[names(agg) == "race"] <- race_col

  tibble::as_tibble(agg[order(agg[[county_col]], agg[[race_col]]), ])
}

#' Aggregate county-level search-rate disparity (post-stop discretion)
#'
#' Pivots [summarize_county_search_rates()]'s long output to black/white
#' side by side and computes their ratio -- the same shape as
#' [summarize_county_vod_disparity()], so the two are directly comparable
#' (see [plot_vod_search_combined()]).
#'
#' @param county_search_rates Output of [summarize_county_search_rates()].
#' @inheritParams summarize_county_vod_disparity
#' @return A tibble, one row per county: `<county_col>`,
#'   `n_searches_black`/`n_searches_white`,
#'   `search_rate_black`/`search_rate_white`,
#'   `disparity_ratio` (`search_rate_black / search_rate_white`).
#' @export
summarize_county_search_disparity <- function(county_search_rates, race_col = "subject_race",
                                               county_col = "county_fips") {
  abort_if_missing_cols(county_search_rates, c(race_col, county_col, "n_searches", "search_rate"))
  black <- county_search_rates[county_search_rates[[race_col]] == "black", c(county_col, "n_searches", "search_rate")]
  white <- county_search_rates[county_search_rates[[race_col]] == "white", c(county_col, "n_searches", "search_rate")]
  names(black)[-1] <- paste0(names(black)[-1], "_black")
  names(white)[-1] <- paste0(names(white)[-1], "_white")

  wide <- merge(black, white, by = county_col)
  wide$disparity_ratio <- wide$search_rate_black / wide$search_rate_white

  tibble::as_tibble(wide[order(wide[[county_col]]), ])
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
      title = "Racial composition of stops: before vs. after dark",
      subtitle = "Inter-twilight window only",
      x = NULL, y = "Share of stops", fill = NULL
    ) +
    ggplot2::theme(legend.position = "top")
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

#' Plot county-level search-rate disparity (chart 3)
#'
#' @param county_search_disparity Output of
#'   [summarize_county_search_disparity()].
#' @param min_n Minimum `n_searches_black`/`n_searches_white` for a county
#'   to be plotted. Default `30`.
#' @return A `ggplot`.
#' @export
plot_county_search_disparity <- function(county_search_disparity, min_n = 30) {
  abort_if_missing_cols(county_search_disparity, c("n_searches_black", "n_searches_white", "disparity_ratio"))
  plot_data <- county_search_disparity[
    county_search_disparity$n_searches_black >= min_n & county_search_disparity$n_searches_white >= min_n,
  ]
  ggplot2::ggplot(plot_data, ggplot2::aes(x = .data$n_searches_black + .data$n_searches_white, y = .data$disparity_ratio)) +
    ggplot2::geom_point() +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed") +
    ggplot2::scale_x_log10() +
    ggplot2::labs(
      title = "Search rate (post-stop discretion)",
      x = "Total searches (log scale)",
      y = "Black:White search rate ratio"
    )
}

#' Combine the county VoD-ratio and search-rate plots side by side (chart 4)
#'
#' "Where does the racial disparity concentrate: the stop, or the search?"
#' -- the same two charts ([plot_county_vod_disparity()] and
#' [plot_county_search_disparity()]) placed next to each other via
#' `patchwork`, rather than rebuilt, so this is never out of sync with the
#' standalone versions of either chart.
#'
#' @param vod_plot A `ggplot` from [plot_county_vod_disparity()].
#' @param search_plot A `ggplot` from [plot_county_search_disparity()].
#' @param title,subtitle Passed to `patchwork::plot_annotation()`.
#' @return A `patchwork` object.
#' @export
plot_vod_search_combined <- function(vod_plot, search_plot,
                                      title = "Where does the racial disparity concentrate: the stop, or the search?",
                                      subtitle = "Each point is a county. Dashed line = parity (ratio of 1).") {
  rlang::check_installed("patchwork", reason = "to combine these two plots side by side.")
  vod_plot + search_plot + patchwork::plot_annotation(title = title, subtitle = subtitle)
}
