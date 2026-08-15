#!/usr/bin/env Rscript
# Command-line interface to the Veil of Darkness diagnostic --
# duboisR::veil_of_darkness_module() driven from the shell, for a quick
# "what does this show" pass over the processed data without opening
# RStudio or the Shiny dashboard. See README.md's "Command-line interface"
# section for a walkthrough; see ?duboisR::veil_of_darkness_module for the
# underlying object this script is a thin wrapper around.
#
# Scoped to the stop decision only (both charts here are about who gets
# pulled over, before vs. after dark). The search decision -- how often
# people get searched, and how justified those searches are -- lives in
# threshold_test_cli.R instead; it was never actually a Veil of Darkness
# test (not restricted to daylight/dark or the intertwilight window), it
# was only paired here for a "where does the disparity concentrate"
# comparison chart that's been retired.
#
# Usage:
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R [subcommand] [options]
#
# Subcommands (default: all):
#   county      County-level VoD ratio (chart 1)
#   statewide   Statewide before/after racial composition (chart 2)
#   all         Both charts, in one run
#
# Options:
#   --data=<path>       Path to the processed CSV.
#                       Default: data/processed/audit_ready_stops.csv
#   --out=<dir>         Directory to write chart PNGs into. Pass --out=
#                       (empty) to skip writing PNGs and only print to the
#                       console. Default: .
#   --min-n=<int>       Minimum county sample size for the county-level
#                       scatter chart. Default: 30
#
# Examples:
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R county --min-n=50
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R statewide --out=charts/

source("duboisR/inst/scripts/_load_duboisR.R")
load_duboisR_or_die("duboisR")

USAGE <- "
Usage: Rscript duboisR/inst/scripts/veil_of_darkness_cli.R [subcommand] [options]
   or: Rscript duboisR/inst/scripts/cli.R veil [subcommand] [options]

Subcommands (default: all):
  county      County-level VoD ratio (chart 1)
  statewide   Statewide before/after racial composition (chart 2)
  all         Both charts, in one run

Options:
  --data=<path>        Path to the processed CSV. Default: data/processed/audit_ready_stops.csv
  --out=<dir>          Directory to write chart PNGs into (--out= to skip PNGs). Default: .
  --min-n=<int>        Minimum county sample size for the county-level scatter chart. Default: 30

Examples:
  Rscript duboisR/inst/scripts/veil_of_darkness_cli.R
  Rscript duboisR/inst/scripts/veil_of_darkness_cli.R county --min-n=50
  Rscript duboisR/inst/scripts/veil_of_darkness_cli.R statewide --out=charts/
"

args <- commandArgs(trailingOnly = TRUE)

if ("--help" %in% args || "-h" %in% args) {
  cat(USAGE)
  quit(save = "no", status = 0)
}

flags <- grep("^--", args, value = TRUE)
positional <- setdiff(args, flags)
subcommand <- if (length(positional) > 0) positional[1] else "all"

parse_flag <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), flags, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0("^--", name, "="), "", hit[1])
}

data_path <- parse_flag("data", "data/processed/audit_ready_stops.csv")
out_dir <- parse_flag("out", ".")
min_n <- as.integer(parse_flag("min-n", "30"))

valid_subcommands <- c("county", "statewide", "all")
if (!subcommand %in% valid_subcommands) {
  stop(sprintf("Unknown subcommand '%s'. Valid: %s", subcommand, paste(valid_subcommands, collapse = ", ")))
}
if (nzchar(out_dir) && !dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

vod <- veil_of_darkness_module()
vod$init(data_path = data_path)
print(vod)

# caption, when given, is baked into the saved PNG itself (via
# add_figure_caption()) -- not just printed to console -- so the image
# stands alone if it's pulled directly into a paper/report.
save_plot <- function(plot, filename, caption = NULL) {
  if (!nzchar(out_dir)) return(invisible(NULL))
  if (!is.null(caption)) plot <- add_figure_caption(plot, caption)
  path <- file.path(out_dir, filename)
  ggplot2::ggsave(path, plot, width = 8, height = 5, dpi = 150)
  cli::cli_inform("Wrote {.path {path}}")
}

report_county <- function() {
  vod$plot_county_vod(min_n = min_n)
  cat("\n--- County-level Veil of Darkness ratio (chart 1) ---\n")
  print(vod$county_vod_disparity[vod$county_vod_disparity$total_n >= min_n, ])
  note <- interpret_county_vod_disparity(vod$county_vod_disparity, min_n = min_n)
  cat(note, "\n")
  save_plot(vod$vod_plot, "vod_county.png", caption = note)
}

report_statewide <- function() {
  vod$plot_statewide()
  cat("\n--- Statewide racial composition, before vs. after dark (chart 2) ---\n")
  print(vod$statewide_table)
  note <- interpret_statewide_vod(vod$statewide_table)
  cat(note, "\n")
  save_plot(vod$statewide_plot, "vod_statewide.png", caption = note)
}

switch(subcommand,
  county = report_county(),
  statewide = report_statewide(),
  all = {
    report_county()
    report_statewide()
  }
)
