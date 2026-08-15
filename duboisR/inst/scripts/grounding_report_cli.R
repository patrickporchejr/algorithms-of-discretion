#!/usr/bin/env Rscript
# Regenerates the LLM Grounding Test PDFs (accuracy table, accuracy chart,
# per-question comparison -- see ?duboisR::write_grounding_report) from an
# already-saved results/grounding_experiment.rds. Makes no API calls -- all
# the real, billed work happens in run_grounding_experiment.R, which already
# calls write_grounding_report() itself at the end of a run. This script
# exists so a formatting tweak to the PDFs (wrap width, page size, ...)
# doesn't require re-running (and re-billing) the whole experiment -- point
# it at an existing .rds and it just re-renders.
#
# Usage:
#   Rscript duboisR/inst/scripts/grounding_report_cli.R [options]
#   Rscript duboisR/inst/scripts/cli.R grounding-report [options]
#
# Options:
#   --rds=<path>   Path to a duboisR_grounding_result .rds.
#                  Default: results/grounding_experiment.rds
#   --out=<dir>    Directory to write the three PDFs into. Default: results

CLI_ARGS <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% CLI_ARGS || "-h" %in% CLI_ARGS) {
  cat("
Usage: Rscript duboisR/inst/scripts/grounding_report_cli.R [options]
   or: Rscript duboisR/inst/scripts/cli.R grounding-report [options]

Regenerates the LLM Grounding Test PDFs (accuracy table, accuracy chart,
per-question comparison) from an already-saved
results/grounding_experiment.rds. Makes no API calls.

Options:
  --rds=<path>   Path to a duboisR_grounding_result .rds.
                 Default: results/grounding_experiment.rds
  --out=<dir>    Directory to write the three PDFs into. Default: results
")
  quit(save = "no", status = 0)
}

source("duboisR/inst/scripts/_load_duboisR.R")
load_duboisR_or_die("duboisR")

parse_flag <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), CLI_ARGS, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0("^--", name, "="), "", hit[1])
}

rds_path <- parse_flag("rds", "results/grounding_experiment.rds")
out_dir <- parse_flag("out", "results")

if (!file.exists(rds_path)) {
  stop(
    "No grounding result at '", rds_path, "' -- run `make grounding` first ",
    "(makes real, billed API calls), or pass --rds=<path> to an existing one."
  )
}

result <- readRDS(rds_path)
write_grounding_report(result, out_dir)
