#!/usr/bin/env Rscript
# Command-line interface to the Veil of Darkness diagnostic --
# duboisR::veil_of_darkness_module() driven from the shell, for a quick
# "what does this show" pass over the processed data without opening
# RStudio or the Shiny dashboard. See README.md's "Command-line interface"
# section for a walkthrough; see ?duboisR::veil_of_darkness_module for the
# underlying object this script is a thin wrapper around.
#
# Usage:
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R [subcommand] [options]
#
# Subcommands (default: all):
#   county      County-level VoD ratio (chart 1)
#   statewide   Statewide before/after racial composition (chart 2)
#   search      Search-rate disparity by county (chart 3)
#   combined    Both mechanisms side by side (chart 4)
#   all         All four, in one run
#
# Options:
#   --data=<path>   Path to the processed CSV.
#                   Default: data/processed/audit_ready_stops.csv
#   --out=<dir>     Directory to write chart PNGs into. Pass --out= (empty)
#                   to skip writing PNGs and only print to the console.
#                   Default: .
#   --min-n=<int>   Minimum county sample size for the two scatter charts
#                   (county/search). Default: 30
#
# Examples:
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R county --min-n=50
#   Rscript duboisR/inst/scripts/veil_of_darkness_cli.R combined --out=charts/

source("duboisR/inst/scripts/_load_duboisR.R")
load_duboisR_or_die("duboisR")

USAGE <- "
Usage: Rscript duboisR/inst/scripts/veil_of_darkness_cli.R [subcommand] [options]
   or: Rscript duboisR/inst/scripts/cli.R veil [subcommand] [options]

Subcommands (default: all):
  county      County-level VoD ratio (chart 1)
  statewide   Statewide before/after racial composition (chart 2)
  search      Search-rate disparity by county (chart 3)
  combined    Both mechanisms side by side (chart 4)
  all         All four, in one run

Options:
  --data=<path>   Path to the processed CSV. Default: data/processed/audit_ready_stops.csv
  --out=<dir>     Directory to write chart PNGs into (--out= to skip PNGs). Default: .
  --min-n=<int>   Minimum county sample size for the two scatter charts. Default: 30

Examples:
  Rscript duboisR/inst/scripts/veil_of_darkness_cli.R
  Rscript duboisR/inst/scripts/veil_of_darkness_cli.R county --min-n=50
  Rscript duboisR/inst/scripts/veil_of_darkness_cli.R combined --out=charts/
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

valid_subcommands <- c("county", "statewide", "search", "combined", "all")
if (!subcommand %in% valid_subcommands) {
  stop(sprintf("Unknown subcommand '%s'. Valid: %s", subcommand, paste(valid_subcommands, collapse = ", ")))
}
if (nzchar(out_dir) && !dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

vod <- veil_of_darkness_module()
vod$init(data_path = data_path)
print(vod)

save_plot <- function(plot, filename) {
  if (!nzchar(out_dir)) return(invisible(NULL))
  path <- file.path(out_dir, filename)
  ggplot2::ggsave(path, plot, width = 8, height = 5, dpi = 150)
  cli::cli_inform("Wrote {.path {path}}")
}

report_county <- function() {
  vod$plot_county_vod(min_n = min_n)
  cat("\n--- County-level Veil of Darkness ratio (chart 1) ---\n")
  print(vod$county_vod_disparity[vod$county_vod_disparity$total_n >= min_n, ])
  save_plot(vod$vod_plot, "vod_county.png")
}

report_statewide <- function() {
  vod$plot_statewide()
  cat("\n--- Statewide racial composition, before vs. after dark (chart 2) ---\n")
  print(vod$statewide_table)
  save_plot(vod$statewide_plot, "vod_statewide.png")
}

report_search <- function() {
  vod$plot_search_rate(min_n = min_n)
  cat("\n--- County-level search-rate disparity (chart 3) ---\n")
  cd <- vod$county_search_disparity
  print(cd[cd$n_searches_black >= min_n & cd$n_searches_white >= min_n, ])
  save_plot(vod$search_rate_plot, "vod_search_rate.png")
}

report_combined <- function() {
  vod$plot_combined()
  cat("\n--- Combined stop-vs-search figure (chart 4) ---\n")
  cat("(descriptive only -- see 'county'/'search' subcommands for the underlying numbers)\n")
  save_plot(vod$combined_plot, "vod_combined.png")
}

switch(subcommand,
  county = report_county(),
  statewide = report_statewide(),
  search = report_search(),
  combined = report_combined(),
  all = {
    report_county()
    report_statewide()
    report_search()
    report_combined()
  }
)
