# Runs the naive-vs-grounded LLM datasheet-grounding experiment (see
# duboisR::run_grounding_experiment()) against this project's real dataset
# and datasheet, and caches the result as results/grounding_experiment.rds
# for the "LLM Grounding Test" dashboard tab.
#
# Unlike precompute_audit.R, this is NOT part of `make results`/`make all`
# -- it makes real, billed API calls and needs provider secrets, so it has
# its own opt-in `make grounding` target. See .env.example / the README for
# the ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY / XAI_API_KEY setup
# this requires.
#
# Run from the repo root: Rscript duboisR/inst/scripts/run_grounding_experiment.R

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

# Unlike the Python pipeline (which calls load_dotenv() explicitly), plain
# Rscript never reads a .env file on its own -- Sys.getenv() only sees
# variables the shell already exported. readRenviron() (base R, same
# NAME=value format .Renviron files use) loads it into this process's
# environment before anything below checks for the *_API_KEY vars.
if (file.exists(".env")) readRenviron(".env")

DATA_PATH <- "data/processed/audit_ready_stops.csv"
DATASHEET_PATH <- "data/processed/datasheet.json"
RESULTS_DIR <- "results"
# 2 independent trials per (provider, condition) -- doubles the call count
# (and roughly the token spend) over a single run, in exchange for a
# majority-vote answer and a per-question stability rate instead of trusting
# one draw. See summarize_grounding_trials().
N_REPEATS <- 2

# Update these to whatever flagship models you want to compare -- only
# providers with a matching *_API_KEY set in .env are actually called.
# Provider model IDs churn fast (Gemini deprecated gemini-2.5-pro AND its
# gemini-3-pro-preview successor within months of each other); if a run
# 404s on "model no longer available", check the provider's current model
# list rather than assuming the fix here is still current.
PROVIDERS <- character(0)
MODELS <- list()
if (nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
  PROVIDERS <- c(PROVIDERS, "anthropic")
  MODELS$anthropic <- "claude-opus-5"
}
if (nzchar(Sys.getenv("OPENAI_API_KEY"))) {
  PROVIDERS <- c(PROVIDERS, "openai")
  MODELS$openai <- "gpt-5.1"
}
if (nzchar(Sys.getenv("GEMINI_API_KEY"))) {
  PROVIDERS <- c(PROVIDERS, "gemini")
  MODELS$gemini <- "gemini-3.1-pro-preview"
}
if (nzchar(Sys.getenv("XAI_API_KEY"))) {
  PROVIDERS <- c(PROVIDERS, "grok")
  MODELS$grok <- "grok-4.6"
}

if (length(PROVIDERS) == 0) {
  stop(
    "None of ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY / XAI_API_KEY ",
    "are set. Add at least one to a repo-root .env file -- see .env.example / ",
    "the README's Setup section."
  )
}

if (!file.exists(DATA_PATH)) {
  stop("No processed dataset at ", DATA_PATH, " -- run `make all` first.")
}
if (!file.exists(DATASHEET_PATH)) {
  stop(
    "No datasheet at ", DATASHEET_PATH, " -- run ",
    "`Rscript duboisR/inst/scripts/seed_demo_datasheet.R` first."
  )
}
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

cat(
  "Running grounding experiment against:", paste(PROVIDERS, collapse = ", "),
  sprintf("(%d trial(s) per condition)...\n", N_REPEATS)
)
result <- run_grounding_experiment(
  data_path = DATA_PATH,
  datasheet_path = DATASHEET_PATH,
  providers = PROVIDERS,
  models = MODELS,
  n_repeats = N_REPEATS
)

# Save before printing -- every API call above is already made and billed
# by this point, so a bug in the summary/print path must never be able to
# discard results that already cost real money. Print second, and even a
# print failure still leaves the .rds on disk.
saveRDS(result, file.path(RESULTS_DIR, "grounding_experiment.rds"))
cat("Wrote", file.path(RESULTS_DIR, "grounding_experiment.rds"), "\n")

print(result)
