# Fits every model the dashboard currently serves, once, against the frozen
# audit-ready dataset, and caches each as its own .rds under results/. The
# dataset is a static pull (see README), so there is no reason for the Shiny
# app to refit these live per session -- especially the Veil of Darkness
# prepare step, which is a ~2min pass over the full dataset (see
# duboisR::prepare_veil_of_darkness_data()).
#
# Run from the repo root: Rscript duboisR/inst/scripts/precompute_audit.R

source("duboisR/inst/scripts/_load_duboisR.R")
load_duboisR_or_die("duboisR")

DATA_PATH <- "data/processed/audit_ready_stops.csv"
RESULTS_DIR <- "results"
OUTCOMES <- c("search_conducted", "contraband_found")

if (!file.exists(DATA_PATH)) {
  stop("No processed dataset at ", DATA_PATH, " -- run `make all` first.")
}
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

cat("Loading", DATA_PATH, "...\n")
stops_data <- readr::read_csv(DATA_PATH, show_col_types = FALSE)
stops_data <- dubois_relevel(stops_data, "subject_race", ref = "white")

# --- Everything below except the Veil of Darkness prepare step is
# commented out while the dashboard is stripped down to just the Veil of
# Darkness tab (see r_dashboard/app.R). Nothing currently reads these
# artifacts. Uncomment any block to bring the corresponding tab back.

# glm() fit objects embed a full copy of the training data (model frame,
# fitted values, residuals, weights -- several length-nrow(data) vectors),
# so at 5.6M rows each cached fit balloons to tens of MB even though nothing
# downstream (the Shiny modules, the S3 print/plot methods) touches
# `$model` after fitting -- they only read `$summary`. Drop it before
# serializing; keeps the `duboisR_glm_fit`/`duboisR_vod_result` class and
# print/plot methods working, just without the embedded training data.
# strip_model <- function(fit) {
#   fit$model <- NULL
#   fit
# }
#
# for (outcome in OUTCOMES) {
#   cat("Fitting baseline regression:", outcome, "...\n")
#   fit <- fit_audit_glm(stops_data, stats::as.formula(paste(outcome, "~ subject_race")))
#   probs <- predicted_probabilities(fit, stops_data, "subject_race")
#   saveRDS(
#     list(fit = strip_model(fit), predicted_probabilities = probs),
#     file.path(RESULTS_DIR, paste0("regression_", outcome, ".rds"))
#   )
# }

cat("Preparing Veil of Darkness data (slow -- daylight/dark classification over the full dataset)...\n")
vod_prepared <- prepare_veil_of_darkness_data(stops_data)
# Cached separately from the outcome fits below so the dashboard's
# intersectional-controls checkboxes can refit live (a few seconds) against
# an already-classified dataset, instead of repeating this ~2min pass, when
# a control combination beyond the plain no-controls fit is selected.
saveRDS(vod_prepared, file.path(RESULTS_DIR, "veil_prepared.rds"))

# for (outcome in OUTCOMES) {
#   cat("Fitting Veil of Darkness:", outcome, "...\n")
#   vod_fit <- fit_veil_of_darkness(vod_prepared, outcome_var = outcome, interaction = TRUE)
#   vod_fit$model_fit <- strip_model(vod_fit$model_fit)
#   saveRDS(vod_fit, file.path(RESULTS_DIR, paste0("veil_", outcome, ".rds")))
# }
#
# cat("Fitting Threshold Test...\n")
# # Unlike Regression/Veil, this always models search_conducted/contraband_found
# # together -- it isn't parameterized by the sidebar's outcome or controls at
# # all, so there's exactly one artifact, no per-outcome/per-control variants.
# suff_stats <- aggregate_sufficient_statistics(stops_data)
# threshold_fit <- fit_threshold_test(suff_stats)
# saveRDS(threshold_fit, file.path(RESULTS_DIR, "threshold_test.rds"))
#
# cat("Computing dataset composition...\n")
# # Same shape as Threshold Test: fixed, not parameterized by any sidebar
# # input, so one cached artifact.
# composition <- audit_composition(stops_data, group_col = "subject_race", missing_col = "contraband_found")
# saveRDS(composition, file.path(RESULTS_DIR, "composition.rds"))
#
# cat("Running identity-proxy check (subject_race ~ county_fips + poverty_rate + median_income + hour)...\n")
# # check_proxies(method = "rf") on the FULL 5.6M-row dataset takes ~18min
# # (verified) for a result within 0.1 accuracy points of a 300k-row sample
# # (67.9% vs. 68.0%, 20.8 vs. 20.9-point lift) -- not worth 18min of `make
# # results` for that difference, so this uses a fixed-seed sample instead.
# set.seed(20240101)
# proxy_sample <- stops_data[sample(nrow(stops_data), 300000), ]
# proxy_sample$county_fips <- as.character(proxy_sample$county_fips)
# identity_proxies <- check_proxies(
#   proxy_sample, protected_attr = "subject_race",
#   predictors = c("county_fips", "poverty_rate", "median_income", "hour"),
#   method = "rf", test_prop = 0.2, seed = 1
# )
# saveRDS(identity_proxies, file.path(RESULTS_DIR, "identity_proxies.rds"))
#
# cat("Classifying outcome variables as tendentious...\n")
# # check_tendentious() doesn't touch the data -- it's a researcher
# # classification, not a statistic -- so this is instant. Both outcomes are
# # classified as administrative (officer discretion), not objective ground
# # truth: see the rationale strings below, which are what
# # duboisR::format.duboisR_tendentious_check() renders on the dashboard.
# tendentious_checks <- list(
#   search_conducted = check_tendentious(
#     "search_conducted", classification = "administrative", interactive = FALSE,
#     rationale = paste(
#       "An officer's discretionary decision to search, not an objective",
#       "measurement of what a driver was carrying."
#     )
#   ),
#   contraband_found = check_tendentious(
#     "contraband_found", classification = "administrative", interactive = FALSE,
#     rationale = paste(
#       "Structurally NA unless a search happened, and the decision to search",
#       "is itself administrative discretion -- so this outcome inherits the",
#       "same selection bias as search_conducted, on top of whatever the",
#       "search itself finds."
#     )
#   )
# )
# saveRDS(tendentious_checks, file.path(RESULTS_DIR, "tendentious_checks.rds"))

cat("Computing Veil of Darkness descriptive charts...\n")
# Four small aggregate tables backing the dashboard's descriptive charts
# (see r_dashboard/R/mod_veil_of_darkness.R) and the CLI
# (duboisR/inst/scripts/veil_of_darkness_cli.R) -- the same
# summarize_*() functions duboisR::veil_of_darkness_module() calls, so all
# three consumers (Shiny, CLI, this script) share one tested aggregation
# path rather than three copies that can drift apart. Built on top of
# vod_prepared$fit_data (already intertwilight-restricted and
# daylight/dark-classified) rather than re-deriving any of that, so these
# are cheap aggregation passes, not a repeat of the slow prepare step.
# Plot objects themselves aren't cached here, only the tiny aggregated
# data -- callers build ggplot/patchwork objects live from these, which is
# fast at this size.
county_vod_disparity <- summarize_county_vod_disparity(vod_prepared$fit_data)
statewide_vod <- summarize_statewide_vod(vod_prepared$fit_data)

# Unlike the two tables above, this is the search decision (a separate
# discretion point from the stop decision the VOD test targets), so it's
# built from the full stops_data, not the intertwilight-restricted
# vod_prepared$fit_data -- there's no reason to bind it to that clock-time
# window.
county_search_rates <- summarize_county_search_rates(stops_data)
county_search_disparity <- summarize_county_search_disparity(county_search_rates)

saveRDS(
  list(
    county_vod_disparity = county_vod_disparity,
    statewide_vod = statewide_vod,
    county_search_rates = county_search_rates,
    county_search_disparity = county_search_disparity
  ),
  file.path(RESULTS_DIR, "vod_charts.rds")
)

cat("Done. Wrote", length(list.files(RESULTS_DIR)), "artifacts to", RESULTS_DIR, "/\n")
