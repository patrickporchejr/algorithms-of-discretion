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

CLI_ARGS_HELP_CHECK <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% CLI_ARGS_HELP_CHECK || "-h" %in% CLI_ARGS_HELP_CHECK) {
  cat("
Usage: Rscript duboisR/inst/scripts/run_grounding_experiment.R [options]
   or: Rscript duboisR/inst/scripts/cli.R grounding [options]

Runs the naive-vs-grounded LLM datasheet-grounding experiment against this
project's real dataset and datasheet, caching the result as
results/grounding_experiment.rds. Needs a datasheet.json to already exist
(see the 'datasheet' command) and at least one of ANTHROPIC_API_KEY /
OPENAI_API_KEY / GEMINI_API_KEY / XAI_API_KEY set in a repo-root .env --
makes real, billed API calls.

Options:
  --restart        Ignore/overwrite an existing checkpoint and start over,
                    instead of resuming an interrupted run.
  --repeats=<int>   Independent trials per (provider, condition). Default 2.
")
  quit(save = "no", status = 0)
}

source("duboisR/inst/scripts/_load_duboisR.R")
load_duboisR_or_die("duboisR")

# Unlike the Python pipeline (which calls load_dotenv() explicitly), plain
# Rscript never reads a .env file on its own -- Sys.getenv() only sees
# variables the shell already exported. readRenviron() (base R, same
# NAME=value format .Renviron files use) loads it into this process's
# environment before anything below checks for the *_API_KEY vars.
if (file.exists(".env")) readRenviron(".env")

DATA_PATH <- "data/processed/audit_ready_stops.csv"
DATASHEET_PATH <- "data/processed/datasheet.json"
RESULTS_DIR <- "results"
# Every completed (provider, condition, trial) call is saved here as the run
# goes, so a crash/timeout/Ctrl-C partway through (real API calls, so this
# does happen -- rate limits, a provider hiccup, a malformed error body) lets
# the next invocation pick back up instead of re-billing every call already
# made. Deleted on a fully successful run so the *next* `make grounding`
# starts fresh, per the Makefile's "re-running is itself sometimes the
# point" note -- this checkpoint is for resuming an interrupted run, not for
# caching a completed one indefinitely. Pass --restart to ignore/overwrite
# an existing checkpoint and start over even if one is present.
CHECKPOINT_PATH <- file.path(RESULTS_DIR, "grounding_experiment_checkpoint.rds")
CLI_ARGS <- commandArgs(trailingOnly = TRUE)
RESTART <- "--restart" %in% CLI_ARGS

# Independent trials per (provider, condition) -- each extra repeat adds
# another full pass over every provider (and roughly that much more token
# spend), in exchange for a majority-vote answer and a per-question
# stability rate instead of trusting one draw. See
# summarize_grounding_trials(). Default 2; override with --repeats=N (e.g.
# --repeats=1 while iterating on a bug, to halve the billed calls).
REPEATS_ARG <- grep("^--repeats=", CLI_ARGS, value = TRUE)
N_REPEATS <- if (length(REPEATS_ARG) > 0) {
  n <- suppressWarnings(as.integer(sub("^--repeats=", "", REPEATS_ARG[[1]])))
  if (is.na(n) || n < 1) {
    stop("--repeats must be a positive integer, got: ", REPEATS_ARG[[1]])
  }
  n
} else {
  2
}

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

# Pricing snapshot, not current guidance -- provider $/1M-token pricing
# moves faster than this file does. Measured against this project's real
# dataset/datasheet as of 2026-08-12: a naive-condition call is ~7.6K input /
# ~0.7K output tokens, grounded is ~10.1K input / ~1.1K output (grounded
# costs more mainly because datasheet.json itself is embedded in the
# prompt). At N_REPEATS = 2 that's 4 calls/provider (2 conditions x 2
# trials); all 4 providers together, at that snapshot's list pricing, ran
# about $0.55 total ($0.27 of that on Anthropic alone -- the priciest of the
# four at the time). Check each provider's current pricing page (linked in
# .env.example) and multiply by the token counts above for today's number.
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

if (RESTART && file.exists(CHECKPOINT_PATH)) {
  file.remove(CHECKPOINT_PATH)
  cat("--restart passed: ignoring existing checkpoint at", CHECKPOINT_PATH, "\n")
} else if (file.exists(CHECKPOINT_PATH)) {
  cat("Resuming from checkpoint at", CHECKPOINT_PATH, "(pass --restart to start over)\n")
}

cat(
  "Running grounding experiment against:", paste(PROVIDERS, collapse = ", "),
  sprintf("(%d trial(s) per condition)...\n", N_REPEATS)
)
result <- run_grounding_experiment(
  data_path = DATA_PATH,
  datasheet_path = DATASHEET_PATH,
  providers = PROVIDERS,
  models = MODELS,
  n_repeats = N_REPEATS,
  checkpoint_path = CHECKPOINT_PATH,
  restart = RESTART
)

# Save before printing -- every API call above is already made and billed
# by this point, so a bug in the summary/print path must never be able to
# discard results that already cost real money. Print second, and even a
# print failure still leaves the .rds on disk.
saveRDS(result, file.path(RESULTS_DIR, "grounding_experiment.rds"))
cat("Wrote", file.path(RESULTS_DIR, "grounding_experiment.rds"), "\n")

# The run finished cleanly and is fully captured in grounding_experiment.rds
# above -- clear the checkpoint so the next run starts fresh instead of
# silently replaying these same (cached, now-stale-by-the-next-run) answers.
if (file.exists(CHECKPOINT_PATH)) file.remove(CHECKPOINT_PATH)

print(result)

# PDF versions of the same three views, for pulling straight into a paper/
# report -- see ?write_grounding_report. Runs against the .rds just saved
# above, not live data, so a formatting bug here can't touch anything
# already billed; re-running only this step (no new API calls) is
# `Rscript duboisR/inst/scripts/cli.R grounding-report`.
write_grounding_report(result, RESULTS_DIR)
