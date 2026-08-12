# Fits every model the dashboard currently serves, once, against the frozen
# audit-ready dataset, and caches each as its own .rds under results/. The
# dataset is a static pull (see README), so there is no reason for the Shiny
# app to refit these live per session -- especially the Veil of Darkness
# prepare step, which is a ~2min pass over the full dataset (see
# duboisR::prepare_veil_of_darkness_data()).
#
# Run from the repo root: Rscript duboisR/inst/scripts/precompute_audit.R

if (requireNamespace("duboisR", quietly = TRUE)) {
  library(duboisR)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all("duboisR", quiet = TRUE)
} else {
  stop(
    "duboisR is not installed and devtools is unavailable to load it from ",
    "source. Run: Rscript -e 'install.packages(\"devtools\"); devtools::install(\"duboisR\")'"
  )
}

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

# glm() fit objects embed a full copy of the training data (model frame,
# fitted values, residuals, weights -- several length-nrow(data) vectors),
# so at 5.6M rows each cached fit balloons to tens of MB even though nothing
# downstream (the Shiny modules, the S3 print/plot methods) touches
# `$model` after fitting -- they only read `$summary`. Drop it before
# serializing; keeps the `duboisR_glm_fit`/`duboisR_vod_result` class and
# print/plot methods working, just without the embedded training data.
strip_model <- function(fit) {
  fit$model <- NULL
  fit
}

for (outcome in OUTCOMES) {
  cat("Fitting baseline regression:", outcome, "...\n")
  fit <- fit_audit_glm(stops_data, stats::as.formula(paste(outcome, "~ subject_race")))
  probs <- predicted_probabilities(fit, stops_data, "subject_race")
  saveRDS(
    list(fit = strip_model(fit), predicted_probabilities = probs),
    file.path(RESULTS_DIR, paste0("regression_", outcome, ".rds"))
  )
}

cat("Preparing Veil of Darkness data (slow -- daylight/dark classification over the full dataset)...\n")
vod_prepared <- prepare_veil_of_darkness_data(stops_data)

for (outcome in OUTCOMES) {
  cat("Fitting Veil of Darkness:", outcome, "...\n")
  vod_fit <- fit_veil_of_darkness(vod_prepared, outcome_var = outcome, interaction = TRUE)
  vod_fit$model_fit <- strip_model(vod_fit$model_fit)
  saveRDS(vod_fit, file.path(RESULTS_DIR, paste0("veil_", outcome, ".rds")))
}

cat("Done. Wrote", length(list.files(RESULTS_DIR)), "artifacts to", RESULTS_DIR, "/\n")
