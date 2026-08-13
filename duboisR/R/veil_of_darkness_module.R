# A stateful wrapper around the Veil of Darkness pipeline, for interactive
# console/CLI use where re-passing the same prepared data into every call
# (as the plain functions in veil_of_darkness_charts.R require) is more
# friction than it's worth. See duboisR/inst/scripts/veil_of_darkness_cli.R
# for the Rscript entry point built on top of this.

#' Create a stateful Veil of Darkness console/CLI module
#'
#' Call `$init()` once; every chart method afterward reads from state
#' `$init()` populated, and every intermediate table/plot it builds is left
#' readable directly off the returned object (e.g. `vod$county_vod_disparity`
#' after calling `vod$plot_county_vod()`), not just returned from the call
#' that built it.
#'
#' This is a plain environment, not an R6/S4 object -- deliberately, to
#' avoid pulling in a new OOP-framework dependency for what's a thin piece
#' of session state. Environments in R have reference semantics: `self` is
#' captured by every method via its enclosing scope, so `self$field <-
#' value` inside any one method mutates state every other method (and the
#' caller's own `vod$field` access) immediately sees, without needing `<<-`
#' or reassigning the returned object.
#'
#' @return An object of class `duboisR_vod_module` (an environment) with:
#'   \describe{
#'     \item{`$init(data_path, ..., config = list())`}{Loads and prepares
#'       everything downstream needs. Sets `$stops` (the loaded,
#'       race-releveled data), `$county_centroids`, `$stops_geo` (every
#'       stop with lat/lon/sunset/dusk/`is_dark` attached -- see
#'       [compute_daylight_status()]), `$sun_times` (the distinct
#'       date x county sunset/dusk lookup `$stops_geo` was built from),
#'       `$vod_data` (the intertwilight-restricted subset -- see
#'       [prepare_veil_of_darkness_data()]), and the four chart-data
#'       tables: `$county_vod_disparity`, `$statewide_vod`,
#'       `$county_search_rates`, `$county_search_disparity`. `config` is
#'       reserved for future options; nothing reads it yet.}
#'     \item{`$plot_county_vod(min_n = 30)`}{Builds, stores as `$vod_plot`,
#'       and returns the county VoD-ratio scatter (chart 1).}
#'     \item{`$plot_statewide()`}{Builds, stores as `$statewide_plot` and
#'       `$statewide_table`, and returns the statewide before/after bar
#'       chart (chart 2).}
#'     \item{`$plot_search_rate(min_n = 30)`}{Builds, stores as
#'       `$search_rate_plot`, and returns the county search-rate disparity
#'       scatter (chart 3).}
#'     \item{`$plot_combined()`}{Builds (calling the two methods above
#'       first if their plots aren't built yet), stores as
#'       `$combined_plot`, and returns the side-by-side stop-vs-search
#'       figure (chart 4).}
#'   }
#' @examples
#' \dontrun{
#' vod <- veil_of_darkness_module()
#' vod$init(data_path = "data/processed/audit_ready_stops.csv")
#' print(vod)
#' vod$plot_combined()
#' vod$county_vod_disparity  # the underlying table is right there too
#' }
#' @export
veil_of_darkness_module <- function() {
  self <- new.env(parent = emptyenv())
  self$initialized <- FALSE

  self$init <- function(data_path = "data/processed/audit_ready_stops.csv",
                         date_col = "date", hour_col = "hour", county_fips_col = "county_fips",
                         race_col = "subject_race", race_ref = "white",
                         centroids = NULL, config = list()) {
    if (!file.exists(data_path)) {
      rlang::abort(sprintf("No data at '%s'.", data_path))
    }

    cli::cli_inform("Loading {.path {data_path}} ...")
    stops <- readr::read_csv(data_path, show_col_types = FALSE)
    stops <- dubois_relevel(stops, race_col, ref = race_ref)
    self$stops <- stops
    self$config <- config

    self$county_centroids <- centroids %||% dubois_tx_centroids()

    cli::cli_inform("Classifying daylight/dark status ({format(nrow(stops), big.mark = ',')} rows -- this is the slow step) ...")
    self$stops_geo <- compute_daylight_status(stops, date_col, hour_col, county_fips_col, centroids = self$county_centroids)
    self$sun_times <- unique(self$stops_geo[c(date_col, county_fips_col, "sunset", "dusk")])

    prepared <- prepare_veil_of_darkness_data(
      stops, date_col, hour_col, county_fips_col, race_col, race_ref,
      centroids = self$county_centroids
    )
    self$vod_prepared <- prepared
    self$vod_data <- prepared$fit_data

    cli::cli_inform("Aggregating chart data ...")
    self$county_vod_disparity <- summarize_county_vod_disparity(self$vod_data, race_col, county_fips_col)
    self$statewide_vod <- summarize_statewide_vod(self$vod_data, race_col)
    self$county_search_rates <- summarize_county_search_rates(stops, "search_conducted", race_col, county_fips_col)
    self$county_search_disparity <- summarize_county_search_disparity(self$county_search_rates, race_col, county_fips_col)

    self$initialized <- TRUE
    cli::cli_inform("Done -- {length(unique(self$county_vod_disparity[[county_fips_col]]))} counties ready.")
    invisible(self)
  }

  self$plot_county_vod <- function(min_n = 30) {
    .vod_module_require_init(self)
    self$vod_plot <- plot_county_vod_disparity(self$county_vod_disparity, min_n = min_n)
    self$vod_plot
  }

  self$plot_statewide <- function() {
    .vod_module_require_init(self)
    self$statewide_plot <- plot_statewide_vod(self$statewide_vod)
    self$statewide_table <- summarize_statewide_vod_table(self$statewide_vod)
    self$statewide_plot
  }

  self$plot_search_rate <- function(min_n = 30) {
    .vod_module_require_init(self)
    self$search_rate_plot <- plot_county_search_disparity(self$county_search_disparity, min_n = min_n)
    self$search_rate_plot
  }

  self$plot_combined <- function() {
    .vod_module_require_init(self)
    if (is.null(self$vod_plot)) self$plot_county_vod()
    if (is.null(self$search_rate_plot)) self$plot_search_rate()
    self$combined_plot <- plot_vod_search_combined(self$vod_plot, self$search_rate_plot)
    self$combined_plot
  }

  structure(self, class = "duboisR_vod_module")
}

#' @keywords internal
.vod_module_require_init <- function(self) {
  if (!isTRUE(self$initialized)) {
    rlang::abort("Call $init() before requesting a chart.")
  }
}

#' @export
print.duboisR_vod_module <- function(x, ...) {
  if (!isTRUE(x$initialized)) {
    cat("<duboisR_vod_module> not yet initialized -- call $init() first.\n")
    return(invisible(x))
  }
  cat(sprintf(
    "<duboisR_vod_module> %s stops loaded, %s inter-twilight stops, %d counties.\n",
    format(nrow(x$stops), big.mark = ","),
    format(nrow(x$vod_data), big.mark = ","),
    length(unique(x$county_vod_disparity[[1]]))
  ))
  built <- c("vod_plot", "statewide_plot", "search_rate_plot", "combined_plot")
  built <- built[vapply(built, function(f) !is.null(x[[f]]), logical(1))]
  cat("Charts built:", if (length(built) == 0) "(none yet)" else paste(built, collapse = ", "), "\n")
  invisible(x)
}
