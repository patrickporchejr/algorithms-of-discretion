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

# --- The search-decision race:is_dark interaction GLM block below is
# commented out while the Veil of Darkness tab shows only its two
# descriptive charts (see r_dashboard/R/mod_veil_of_darkness.R's header
# comment) -- on the frozen dataset that regression didn't meaningfully
# change the picture, so it's no longer precomputed. fit_veil_of_darkness()
# itself is still exported and tested; call it directly for console/
# white-paper use. Uncomment the block below to bring it back.
#
# composition.rds / identity_proxies.rds / tendentious_checks.rds ARE
# computed below -- they back the "Data Transparency & Provenance" tab
# (r_dashboard/R/mod_datasheet.R), which reads all three.

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
cat("Computing search-rate disparity by county (frequency -- how often people get searched at all)...\n")
# Not restricted to daylight/dark, the intertwilight window, or the
# top-counties cut below -- it's a plain descriptive ratio, not an input to
# the Beta-distribution optimizer, so it doesn't need that stabilization.
county_search_rates <- summarize_county_search_rates(stops_data)
county_search_disparity <- summarize_county_search_disparity(county_search_rates)

cat("Fitting Threshold Test (restricted to the 100 largest counties with >= 1000 stops)...\n")
# Unlike Veil, this always models search_conducted/contraband_found together
# -- it isn't parameterized by the sidebar's outcome or controls at all, so
# there's exactly one artifact, no per-outcome/per-control variants.
# restrict_to_top_counties() first: verified (see README/CLI --help for
# duboisR/inst/scripts/threshold_test_cli.R) that fitting against every
# county tends to land fit_threshold_test() on a near-degenerate,
# barely-converged risk distribution for the sparser races -- restricting
# to the state's highest-volume counties doesn't change the substantive
# finding, but it does fix convergence, so that's the version cached here.
# suff_stats is cached alongside the fit (small) so compare_outcome_threshold_test()
# can be computed live in the Shiny module without re-deriving it from raw stops.
threshold_stops <- restrict_to_top_counties(stops_data)
suff_stats <- aggregate_sufficient_statistics(threshold_stops)
threshold_fit <- fit_threshold_test(suff_stats)
saveRDS(
  list(
    suff_stats = suff_stats, fit = threshold_fit,
    county_search_rates = county_search_rates, county_search_disparity = county_search_disparity
  ),
  file.path(RESULTS_DIR, "threshold_test.rds")
)

cat("Computing dataset composition...\n")
# Same shape as Threshold Test: fixed, not parameterized by any sidebar
# input, so one cached artifact.
composition <- audit_composition(stops_data, group_col = "subject_race", missing_col = "contraband_found")
saveRDS(composition, file.path(RESULTS_DIR, "composition.rds"))

cat("Running identity-proxy check (subject_race ~ county_fips + poverty_rate + median_income + hour)...\n")
# check_proxies(method = "rf") on the FULL 5.6M-row dataset takes ~18min
# (verified) for a result within 0.1 accuracy points of a 300k-row sample
# (67.9% vs. 68.0%, 20.8 vs. 20.9-point lift) -- not worth 18min of `make
# results` for that difference, so this uses a fixed-seed sample instead.
set.seed(20240101)
proxy_sample <- stops_data[sample(nrow(stops_data), 300000), ]
proxy_sample$county_fips <- as.character(proxy_sample$county_fips)
identity_proxies <- check_proxies(
  proxy_sample, protected_attr = "subject_race",
  predictors = c("county_fips", "poverty_rate", "median_income", "hour"),
  method = "rf", test_prop = 0.2, seed = 1
)
saveRDS(identity_proxies, file.path(RESULTS_DIR, "identity_proxies.rds"))

cat("Classifying outcome variables as tendentious...\n")
# check_tendentious() doesn't touch the data -- it's a researcher
# classification, not a statistic -- so this is instant. Both outcomes are
# classified as administrative (officer discretion), not objective ground
# truth: see the rationale strings below, which are what
# duboisR::format.duboisR_tendentious_check() renders on the dashboard.
tendentious_checks <- list(
  search_conducted = check_tendentious(
    "search_conducted", classification = "administrative", interactive = FALSE,
    rationale = paste(
      "An officer's discretionary decision to search, not an objective",
      "measurement of what a driver was carrying."
    )
  ),
  contraband_found = check_tendentious(
    "contraband_found", classification = "administrative", interactive = FALSE,
    rationale = paste(
      "Structurally NA unless a search happened, and the decision to search",
      "is itself administrative discretion -- so this outcome inherits the",
      "same selection bias as search_conducted, on top of whatever the",
      "search itself finds."
    )
  )
)
saveRDS(tendentious_checks, file.path(RESULTS_DIR, "tendentious_checks.rds"))

cat("Computing Veil of Darkness descriptive charts...\n")
# Two small aggregate tables backing the dashboard's descriptive charts
# (see r_dashboard/R/mod_veil_of_darkness.R) and the CLI
# (duboisR/inst/scripts/veil_of_darkness_cli.R) -- the same
# summarize_*() functions duboisR::veil_of_darkness_module() calls, so all
# three consumers (Shiny, CLI, this script) share one tested aggregation
# path rather than three copies that can drift apart. Built on top of
# vod_prepared$fit_data (already intertwilight-restricted and
# daylight/dark-classified) rather than re-deriving any of that, so these
# are cheap aggregation passes, not a repeat of the slow prepare step. Both
# are the stop decision only now -- the search decision's frequency
# (county_search_rates/county_search_disparity, above) and quality
# (Threshold Test, above) both moved into threshold_test.rds; they were
# never actually daylight/dark-restricted, so they didn't belong here.
# Plot objects themselves aren't cached here, only the tiny aggregated
# data -- callers build ggplot/patchwork objects live from these, which is
# fast at this size.
county_vod_disparity <- summarize_county_vod_disparity(vod_prepared$fit_data)
statewide_vod <- summarize_statewide_vod(vod_prepared$fit_data)

saveRDS(
  list(
    county_vod_disparity = county_vod_disparity,
    statewide_vod = statewide_vod
  ),
  file.path(RESULTS_DIR, "vod_charts.rds")
)

cat("Done. Wrote", length(list.files(RESULTS_DIR)), "artifacts to", RESULTS_DIR, "/\n")
