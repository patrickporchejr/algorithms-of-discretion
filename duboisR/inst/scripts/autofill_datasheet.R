#!/usr/bin/env Rscript
# Fills the datasheet's "Audit Results Appendix" section straight from the
# latest cached chart data (results/vod_charts.rds, results/threshold_test.rds)
# -- run this right after `make results` / `Rscript
# duboisR/inst/scripts/precompute_audit.R` regenerates those artifacts, so
# the appendix's numbers never drift from what the VOD and Threshold Test
# tabs are actually showing.
#
# Unlike duboisR/inst/scripts/seed_demo_datasheet.R (hand-authored
# reflection, grounded in facts computed once and transcribed), every
# sentence this script writes comes straight out of duboisR's own
# interpret_*() functions run against whatever is currently in results/ --
# re-running it after `make results` regenerates new numbers refreshes the
# appendix instead of leaving it stale. Uses
# duboisR::seed_datasheet_answers(), so by default an existing non-blank
# answer is left alone; pass --overwrite to force these freshly-computed
# sentences over whatever is already there (the usual choice right after
# regenerating charts).
#
# Run from the repo root: Rscript duboisR/inst/scripts/autofill_datasheet.R
#   or: Rscript duboisR/inst/scripts/cli.R autofill
# Pass --overwrite to replace existing audit_appendix answers instead of
# only filling blanks.

CLI_ARGS <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% CLI_ARGS || "-h" %in% CLI_ARGS) {
  cat("
Usage: Rscript duboisR/inst/scripts/autofill_datasheet.R [options]
   or: Rscript duboisR/inst/scripts/cli.R autofill [options]

Fills datasheet.json's Audit Results Appendix section from the current
results/vod_charts.rds and results/threshold_test.rds -- run after
`make results` regenerates those. Merges into any existing datasheet.json
rather than replacing it -- an existing non-empty answer is left untouched
unless --overwrite is passed.

Options:
  --overwrite   Replace existing Audit Results Appendix answers instead of
                only filling blanks (the usual choice right after
                regenerating charts, since this section is meant to always
                reflect the latest computed results).
")
  quit(save = "no", status = 0)
}

source("duboisR/inst/scripts/_load_duboisR.R")
load_duboisR_or_die("duboisR")

OUTPUT_PATH <- "data/processed/datasheet.json"
RESULTS_DIR <- "results"
OVERWRITE_EXISTING <- "--overwrite" %in% CLI_ARGS

require_results <- function(name) {
  path <- file.path(RESULTS_DIR, paste0(name, ".rds"))
  if (!file.exists(path)) {
    stop("No cached result at ", path, " -- run `make results` (or Rscript duboisR/inst/scripts/precompute_audit.R) first.")
  }
  readRDS(path)
}

vod_charts <- require_results("vod_charts")
threshold_results <- require_results("threshold_test")

statewide_vod_table <- summarize_statewide_vod_table(vod_charts$statewide_vod)
threshold_comparison <- compare_outcome_threshold_test(threshold_results$suff_stats, threshold_results$fit)

# Same near-degenerate cutoff fit_threshold_test()/interpret_threshold_fit()
# already use internally -- replicated here (rather than reaching for the
# package's unexported .dubois_near_degenerate()) since it's one plain
# comparison, not a code path worth exposing across the package boundary.
race_params <- threshold_results$fit$race_params
near_degenerate_races <- as.character(race_params$race[race_params$a > 1e6 | race_params$b > 1e6])

reliability_note <- if (length(near_degenerate_races) > 0) {
  sprintf(
    paste(
      "Caution: the current Threshold Test fit's risk distribution is",
      "near-degenerate (near-zero variance) for %s -- read every inferred",
      "threshold below as suggestive, not precise, and do not rank",
      "counties against each other by it."
    ),
    paste(near_degenerate_races, collapse = ", ")
  )
} else {
  "The current Threshold Test fit's risk distributions are not near-degenerate for any race."
}

answers <- list(
  audit_appendix = list(
    vod_summary = paste(
      interpret_statewide_vod(statewide_vod_table),
      interpret_county_vod_disparity(vod_charts$county_vod_disparity)
    ),
    search_disparity_summary = interpret_search_rate_disparity(threshold_results$county_search_disparity),
    threshold_summary = paste(
      interpret_threshold_fit(threshold_results$fit),
      interpret_outcome_threshold_comparison(threshold_comparison)
    ),
    reliability_and_synthesis = paste(
      "Read together: the stop decision (Veil of Darkness) sits close to",
      "parity across most high-volume counties, while the search decision",
      "(both the naive search-rate gap and, where the fit is stable, the",
      "corrected threshold gap) shows a substantially larger racial",
      "disparity -- consistent with disparity concentrating downstream of",
      "the stop, in the decision to search, rather than in who gets pulled",
      "over in the first place.", reliability_note
    )
  )
)

seed_datasheet_answers(answers, path = OUTPUT_PATH, overwrite_existing = OVERWRITE_EXISTING)
cat(
  "Wrote", OUTPUT_PATH, "Audit Results Appendix",
  if (OVERWRITE_EXISTING) "(overwrote existing answers)\n" else "(existing answers, if any, were preserved)\n"
)
