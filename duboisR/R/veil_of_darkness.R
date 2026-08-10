#' Texas county centroid lookup table
#'
#' Reads the package's bundled 254-row Texas county centroid table (`lat`,
#' `lon` per `county_fips`), sourced from the U.S. Census Bureau's
#' public-domain Gazetteer Files. See
#' `data-raw/build_tx_county_centroids.R` for provenance.
#'
#' @return A tibble with columns `county_fips`, `county_name`, `lat`, `lon`.
#' @export
dubois_tx_centroids <- function() {
  path <- system.file("extdata", "tx_county_centroids.csv", package = "duboisR")
  readr::read_csv(path, col_types = readr::cols(
    county_fips = readr::col_character(),
    county_name = readr::col_character(),
    lat = readr::col_double(),
    lon = readr::col_double()
  ))
}

#' Classify each stop as daylight, dark, or twilight
#'
#' Joins county centroids, computes each stop's sunset/civil-dusk time via
#' [suncalc::getSunlightTimes()] (vectorized over unique `(date, county)`
#' pairs, not per-row — required for acceptable performance at millions of
#' rows), and classifies each stop's lighting condition.
#'
#' Because the data contract only carries an integer `hour` (no minutes;
#' see DESIGN.md \eqn{\S}4), each stop's timestamp is assumed to be at the
#' top of its recorded hour. This is a real, unavoidable resolution
#' limitation given the upstream pipeline, not a choice made for
#' convenience here.
#'
#' @param data A data frame.
#' @param date_col String column name of the stop date. Default `"date"`.
#' @param hour_col String column name of the stop hour (integer 0-23).
#'   Default `"hour"`.
#' @param county_fips_col String column name of the county FIPS code.
#'   Default `"county_fips"`.
#' @param centroids Optional pre-loaded centroid tibble (see
#'   [dubois_tx_centroids()]); defaults to loading the bundled table.
#'   Injectable for testing.
#' @return `data` augmented with `stop_datetime`, `sunset`, `dusk`,
#'   `light_condition` (factor: `"daylight"`, `"dark"`, `"twilight"`), and
#'   `is_dark` (logical; `NA` when `light_condition == "twilight"`).
#' @export
compute_daylight_status <- function(data, date_col = "date", hour_col = "hour",
                                     county_fips_col = "county_fips", centroids = NULL) {
  abort_if_missing_cols(data, c(date_col, hour_col, county_fips_col))
  centroids <- centroids %||% dubois_tx_centroids()

  n_before <- nrow(data)
  data <- merge(data, centroids[c("county_fips", "lat", "lon")],
                by.x = county_fips_col, by.y = "county_fips", all.x = TRUE)
  n_unmatched <- sum(is.na(data$lat))
  if (n_unmatched > 0) {
    cli::cli_warn("{n_unmatched} of {n_before} rows have a {county_fips_col} with no centroid match; their light_condition will be NA.")
  }

  data$stop_datetime <- as.POSIXct(
    paste0(as.character(data[[date_col]]), " ", sprintf("%02d:00:00", data[[hour_col]])),
    tz = "America/Chicago"
  )

  unique_pairs <- unique(data[c(date_col, county_fips_col, "lat", "lon")])
  unique_pairs <- unique_pairs[stats::complete.cases(unique_pairs[c("lat", "lon")]), ]
  suns <- suncalc::getSunlightTimes(
    data = data.frame(date = as.Date(unique_pairs[[date_col]]), lat = unique_pairs$lat, lon = unique_pairs$lon),
    tz = "America/Chicago",
    keep = c("sunset", "dusk")
  )
  unique_pairs$sunset <- suns$sunset
  unique_pairs$dusk <- suns$dusk

  data <- merge(
    data, unique_pairs[c(date_col, county_fips_col, "sunset", "dusk")],
    by = c(date_col, county_fips_col), all.x = TRUE
  )

  data$light_condition <- factor(
    ifelse(is.na(data$sunset), NA_character_,
      ifelse(data$stop_datetime <= data$sunset, "daylight",
        ifelse(data$stop_datetime >= data$dusk, "dark", "twilight")
      )
    ),
    levels = c("daylight", "twilight", "dark")
  )
  data$is_dark <- ifelse(data$light_condition == "twilight", NA, data$light_condition == "dark")

  tibble::as_tibble(data)
}

#' Fit a Veil of Darkness natural-experiment test
#'
#' The Veil of Darkness test evaluates racial profiling in traffic stops by
#' comparing the race distribution of stops made in daylight vs. after dark
#' — under the hypothesis that officers find it harder to observe a
#' driver's race at night (Grogger & Ridgeway 2006). This function
#' restricts the comparison to the **intertwilight period**: clock hours
#' that are sometimes daylight and sometimes dark across the data's
#' date/county range, controlling for the confound that commuting patterns
#' (and thus who is on the road) vary by clock time regardless of race.
#'
#' @param data A data frame.
#' @param outcome_var String outcome column. Default `"search_conducted"`.
#' @param date_col,hour_col,county_fips_col Passed to
#'   [compute_daylight_status()].
#' @param race_col String race column. Default `"subject_race"`.
#' @param race_ref String reference level for `race_col`. Default `"white"`.
#' @param interaction If `TRUE`, include a `race:is_dark` interaction term.
#'   Default `FALSE`.
#' @param centroids Passed to [compute_daylight_status()].
#' @return A list of class `duboisR_vod_result` with `model_fit` (a
#'   `duboisR_glm_fit`), `diagnostics` (row counts / hours used), and
#'   `caveats` (character vector, always including the nonreporting-
#'   robustness assumption and the hour-only time-resolution limitation).
#' @export
veil_of_darkness_test <- function(data, outcome_var = "search_conducted", date_col = "date",
                                   hour_col = "hour", county_fips_col = "county_fips",
                                   race_col = "subject_race", race_ref = "white",
                                   interaction = FALSE, centroids = NULL) {
  abort_if_missing_cols(data, c(outcome_var, date_col, hour_col, county_fips_col, race_col))
  n_total <- nrow(data)

  data <- compute_daylight_status(data, date_col, hour_col, county_fips_col, centroids)
  n_dropped_no_centroid <- sum(is.na(data$light_condition))

  hours_with_both <- vapply(split(data$light_condition, data[[hour_col]]), function(lc) {
    lc <- lc[!is.na(lc) & lc != "twilight"]
    length(unique(lc)) > 1
  }, logical(1))
  intertwilight_hours <- as.integer(names(hours_with_both)[hours_with_both])

  n_dropped_twilight <- sum(data$light_condition == "twilight", na.rm = TRUE)

  fit_data <- data[!is.na(data$is_dark) & data[[hour_col]] %in% intertwilight_hours, , drop = FALSE]
  fit_data <- dubois_relevel(fit_data, race_col, ref = race_ref)

  base_term <- if (interaction) paste0(race_col, " * is_dark") else paste0(race_col, " + is_dark")
  # A `factor(hour)` term with only one surviving level breaks model.matrix()'s
  # contrasts (needs >= 2 levels), so only include it when the intertwilight
  # restriction has left more than one distinct hour to control for.
  rhs <- if (length(intertwilight_hours) > 1) {
    paste(base_term, "+ factor(", hour_col, ")")
  } else {
    base_term
  }
  formula <- stats::as.formula(paste(outcome_var, "~", rhs))
  model_fit <- fit_audit_glm(fit_data, formula)

  diagnostics <- list(
    n_total = n_total,
    n_dropped_no_centroid = n_dropped_no_centroid,
    n_dropped_twilight = n_dropped_twilight,
    n_used = nrow(fit_data),
    n_intertwilight_hours_used = length(intertwilight_hours),
    hours_used = sort(intertwilight_hours)
  )

  caveats <- c(
    paste0(
      "This test assumes race-specific reporting rates do not vary systematically ",
      "between day and night conditional on clock time; it does NOT require equal ",
      "absolute reporting rates by race (a weaker, more realistic assumption for ",
      "administrative policing data)."
    ),
    paste0(
      "Stop times are resolved to the hour only (the pipeline does not carry minutes), ",
      "so daylight/dark classification for stops near sunset/dusk is coarser than the ",
      "underlying astronomical calculation supports."
    )
  )

  structure(
    list(model_fit = model_fit, diagnostics = diagnostics, caveats = caveats),
    class = "duboisR_vod_result"
  )
}

#' @export
print.duboisR_vod_result <- function(x, ...) {
  cat(md_table(x$model_fit$summary), "\n\n")
  cli::cli_bullets(stats::setNames(x$caveats, rep("i", length(x$caveats))))
  invisible(x)
}

#' @export
plot.duboisR_vod_result <- function(x, ...) {
  df <- x$model_fit$summary
  df <- df[grepl("is_dark", df$term), ]
  ggplot2::ggplot(df, ggplot2::aes(x = .data$term, y = .data$estimate, ymin = .data$conf.low, ymax = .data$conf.high)) +
    ggplot2::geom_pointrange(color = "#2C3E50", linewidth = 0.8) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = "red") +
    ggplot2::coord_flip() +
    ggplot2::theme_minimal(base_size = 14) +
    ggplot2::labs(x = "", y = "Adjusted Odds Ratio (95% CI)", title = "Veil of Darkness: dark vs. daylight")
}
