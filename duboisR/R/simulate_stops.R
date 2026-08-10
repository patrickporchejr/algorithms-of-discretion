#' A fixed set of real Texas county FIPS codes used as the default sampling
#' frame for [simulate_stops()] (Harris, Dallas, Travis, Bexar, Tarrant, El
#' Paso, Collin, Denton, Fort Bend, Hidalgo).
#' @keywords internal
.dubois_default_tx_counties <- c(
  "48201", "48113", "48453", "48029", "48439",
  "48141", "48085", "48121", "48157", "48215"
)

#' Simulate schema-correct synthetic traffic-stop data
#'
#' Generates synthetic data matching the real `audit_ready_stops.csv` data
#' contract exactly (see DESIGN.md \eqn{\S}4) — used both as the package's
#' own test fixtures and as the dashboard's dev-data script
#' (`r_dashboard/dev/generate_synthetic_data.R`). Unlike the pipeline's
#' original synthetic generator, this deliberately does NOT fabricate
#' `subject_age` or `is_arrested`, neither of which exist in the real Texas
#' State Patrol data.
#'
#' A synthetic race effect is baked into `search_conducted` purely so plots
#' and diagnostics have a visible, non-null signal to check against — it is
#' not a finding and should never be treated as one.
#'
#' @param n Number of rows to simulate. Default `2000`.
#' @param seed RNG seed, for reproducibility. Default `42`.
#' @param counties Optional character vector of `county_fips` codes to
#'   sample from. Defaults to a fixed set of 10 real TX FIPS codes.
#' @return A tibble with columns `subject_race`, `subject_sex`,
#'   `search_conducted`, `contraband_found`, `hour`, `date`, `violation`,
#'   `search_basis`, `poverty_rate`, `median_income`, `county_fips`.
#' @export
simulate_stops <- function(n = 2000, seed = 42, counties = NULL) {
  if (!is.null(seed)) set.seed(seed)

  counties <- counties %||% .dubois_default_tx_counties

  races <- c("white", "black", "hispanic")
  violations <- c(
    "Speeding Over Limit", "Fail To Drive In Single Lane", "Improper Use Of Turn Indicator",
    "No/Non-Compliant Head Lamps", "Disregard Stop Sign/Light", "Expired Registration"
  )
  search_bases <- c("Consent", "Probable Cause", "Incident to Arrest", "Plain View")

  subject_race <- sample(races, n, replace = TRUE, prob = c(0.55, 0.22, 0.23))
  subject_sex <- sample(c("male", "female"), n, replace = TRUE, prob = c(0.62, 0.38))
  county_fips <- sample(counties, n, replace = TRUE)
  poverty_rate <- pmin(pmax(stats::rnorm(n, mean = 0.15, sd = 0.06), 0.01), 0.6)
  median_income <- pmin(pmax(stats::rnorm(n, mean = 62000, sd = 15000), 20000), 150000)
  hour <- sample(0:23, n, replace = TRUE)
  date <- as.Date("2015-01-01") + sample(0:(365 * 3 - 1), n, replace = TRUE)
  violation <- sample(violations, n, replace = TRUE)

  # Synthetic race effect, purely for exercising plots/diagnostics — not a finding.
  race_effect <- ifelse(subject_race %in% c("black", "hispanic"), 0.5, 0)
  logit_search <- -2.2 + race_effect - 0.00001 * median_income + stats::rnorm(n, 0, 0.5)
  search_conducted <- as.logical(stats::rbinom(n, 1, stats::plogis(logit_search)))

  contraband_found <- rep(NA, n)
  n_searched <- sum(search_conducted)
  if (n_searched > 0) {
    logit_hit <- -1.0 + stats::rnorm(n_searched, 0, 0.6)
    contraband_found[search_conducted] <- as.logical(stats::rbinom(n_searched, 1, stats::plogis(logit_hit)))
  }

  search_basis <- rep(NA_character_, n)
  if (n_searched > 0) {
    search_basis[search_conducted] <- sample(search_bases, n_searched, replace = TRUE)
  }

  tibble::tibble(
    subject_race = subject_race,
    subject_sex = subject_sex,
    search_conducted = search_conducted,
    contraband_found = contraband_found,
    hour = hour,
    date = date,
    violation = violation,
    search_basis = search_basis,
    poverty_rate = poverty_rate,
    median_income = median_income,
    county_fips = county_fips
  )
}
