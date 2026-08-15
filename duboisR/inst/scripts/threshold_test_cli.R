#!/usr/bin/env Rscript
# Command-line interface to the search decision's diagnostics -- how often
# people get searched (frequency) and how justified those searches are
# (the Threshold Test + its naive outcome-test baseline) -- driven from the
# shell, same "quick look without opening RStudio/Shiny" purpose as
# veil_of_darkness_cli.R (this script's flag/dispatch conventions are
# copied from that one). See ?duboisR::summarize_county_search_disparity,
# ?duboisR::fit_threshold_test, and ?duboisR::compare_outcome_threshold_test
# for the underlying functions this script wraps.
#
# Usage:
#   Rscript duboisR/inst/scripts/threshold_test_cli.R [subcommand] [options]
#
# Subcommands (default: all):
#   search    Search-rate disparity by county, every race vs. --reference-race
#             -- a pure frequency comparison, not restricted to the
#             --county-min-stops/--top-n-counties cut below (that
#             restriction is specifically about stabilizing the Threshold
#             Test's optimizer, not needed for a plain ratio).
#   fit       Fit the Threshold Test; print its per-race (a, b)/threshold
#             summary and save the search-rate-vs-hit-rate curve chart.
#   compare   Fit the Threshold Test, then compare it against the naive
#             (Ayres 2002) outcome test computed on the same sufficient
#             statistics -- prints the comparison table and saves the
#             two-panel comparison chart.
#   all       All three of the above, in one run (default).
#
# Options:
#   --data=<path>            Path to the processed CSV.
#                             Default: data/processed/audit_ready_stops.csv
#   --out=<dir>               Directory to write chart PNGs into. Pass
#                              --out= (empty) to skip writing PNGs and only
#                              print to the console. Default: .
#   --search-min-n=<int>      search only: minimum searches per (race,
#                              county) cell to plot. Default: 30
#   --county-min-stops=<int>  fit/compare only: minimum total stops (any
#                              race) for a county to be eligible at all
#                              (restrict_to_top_counties()'s min_stops) --
#                              applied before --top-n-counties and before
#                              any race split. Default: 1000
#   --top-n-counties=<int>    fit/compare only: keep only this many of the
#                              largest eligible counties
#                              (restrict_to_top_counties()'s top_n). Pass
#                              Inf to keep every eligible county. Default: 100
#   --group-min-n=<int>       fit/compare only: minimum stops per (race,
#                              county) cell to retain
#                              (aggregate_sufficient_statistics()'s min_n).
#                              Default: 20
#   --min-searches=<int>      fit/compare only: minimum searches per cell
#                              for it to count toward fitting (a, b)
#                              (fit_threshold_test()'s min_searches).
#                              Default: 5
#   --reference-race=<race>   Race every gap is computed against (also the
#                              GLM releveling reference). Default: white
#
# Examples:
#   Rscript duboisR/inst/scripts/threshold_test_cli.R
#   Rscript duboisR/inst/scripts/threshold_test_cli.R search --out=charts/
#   Rscript duboisR/inst/scripts/threshold_test_cli.R fit --out=charts/
#   Rscript duboisR/inst/scripts/threshold_test_cli.R compare --reference-race=white
#   Rscript duboisR/inst/scripts/threshold_test_cli.R --county-min-stops=0 --top-n-counties=Inf  # no county restriction

source("duboisR/inst/scripts/_load_duboisR.R")
load_duboisR_or_die("duboisR")

USAGE <- "
Usage: Rscript duboisR/inst/scripts/threshold_test_cli.R [subcommand] [options]
   or: Rscript duboisR/inst/scripts/cli.R threshold [subcommand] [options]

Subcommands (default: all):
  search    Search-rate disparity by county, every race vs. --reference-race (frequency, not restricted to the county cut below).
  fit       Fit the Threshold Test; print its per-race summary and save the search-rate-vs-hit-rate curve chart.
  compare   Fit the Threshold Test, then compare it against the naive (Ayres 2002) outcome test.
  all       All three of the above, in one run (default).

Options:
  --data=<path>            Path to the processed CSV. Default: data/processed/audit_ready_stops.csv
  --out=<dir>              Directory to write chart PNGs into (--out= to skip PNGs). Default: .
  --search-min-n=<int>     search only: minimum searches per (race, county) cell to plot. Default: 30
  --county-min-stops=<int> fit/compare only: minimum total stops for a county to be eligible at all. Default: 1000
  --top-n-counties=<int>   fit/compare only: keep only this many of the largest eligible counties (Inf = no cap). Default: 100
  --group-min-n=<int>      fit/compare only: minimum stops per (race, county) cell. Default: 20
  --min-searches=<int>     fit/compare only: minimum searches per cell to fit (a, b). Default: 5
  --reference-race=<race>  Race every gap is computed against. Default: white

Examples:
  Rscript duboisR/inst/scripts/threshold_test_cli.R
  Rscript duboisR/inst/scripts/threshold_test_cli.R search --out=charts/
  Rscript duboisR/inst/scripts/threshold_test_cli.R fit --out=charts/
  Rscript duboisR/inst/scripts/threshold_test_cli.R compare --reference-race=white
  Rscript duboisR/inst/scripts/threshold_test_cli.R --county-min-stops=0 --top-n-counties=Inf  # no county restriction
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
search_min_n <- as.integer(parse_flag("search-min-n", "30"))
county_min_stops <- as.integer(parse_flag("county-min-stops", "1000"))
top_n_counties <- as.numeric(parse_flag("top-n-counties", "100")) # as.numeric, not as.integer -- must accept "Inf"
group_min_n <- as.integer(parse_flag("group-min-n", "20"))
min_searches <- as.integer(parse_flag("min-searches", "5"))
reference_race <- parse_flag("reference-race", "white")

valid_subcommands <- c("search", "fit", "compare", "all")
if (!subcommand %in% valid_subcommands) {
  stop(sprintf("Unknown subcommand '%s'. Valid: %s", subcommand, paste(valid_subcommands, collapse = ", ")))
}
if (!file.exists(data_path)) {
  stop(sprintf("No data at '%s'.", data_path))
}
if (nzchar(out_dir) && !dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

cli::cli_inform("Loading {.path {data_path}} ...")
stops <- readr::read_csv(data_path, show_col_types = FALSE)
stops <- dubois_relevel(stops, "subject_race", ref = reference_race)

# fit/compare share one restricted-and-fit pass; search doesn't need it (it
# runs against the full, unrestricted stops), so this only runs when asked.
if (subcommand %in% c("fit", "compare", "all")) {
  n_before <- nrow(stops)
  threshold_stops <- restrict_to_top_counties(stops, min_stops = county_min_stops, top_n = top_n_counties)
  cli::cli_inform(
    "Restricted to {length(unique(threshold_stops$county_fips))} counties (>= {county_min_stops} stops, top {top_n_counties}): {format(nrow(threshold_stops), big.mark = ',')} of {format(n_before, big.mark = ',')} stops kept."
  )
  suff_stats <- aggregate_sufficient_statistics(threshold_stops, min_n = group_min_n)
  threshold_fit <- fit_threshold_test(suff_stats, min_searches = min_searches)
}

# caption, when given, is baked into the saved PNG itself (via
# add_figure_caption()) -- not just printed to console -- so the image
# stands alone if it's pulled directly into a paper/report.
save_plot <- function(plot, filename, width = 8, height = 5, caption = NULL) {
  if (!nzchar(out_dir)) return(invisible(NULL))
  if (!is.null(caption)) plot <- add_figure_caption(plot, caption)
  path <- file.path(out_dir, filename)
  ggplot2::ggsave(path, plot, width = width, height = height, dpi = 150)
  cli::cli_inform("Wrote {.path {path}}")
}

report_search <- function() {
  county_search_rates <- summarize_county_search_rates(stops)
  county_search_disparity <- summarize_county_search_disparity(county_search_rates, reference_race = reference_race)
  cat(sprintf("\n--- Search-rate disparity by county (reference race: %s) ---\n", reference_race))
  note <- interpret_search_rate_disparity(county_search_disparity, min_n = search_min_n, reference_race = reference_race)
  cat(note, "\n")
  save_plot(
    plot_county_search_disparity(county_search_disparity, min_n = search_min_n),
    "search_rate_disparity.png",
    caption = note
  )
}

report_fit <- function() {
  cat("\n--- Threshold Test: fitted risk-distribution parameters per race ---\n")
  print(threshold_fit)
  note <- interpret_threshold_fit(threshold_fit, reference_race = reference_race)
  cat(note, "\n")
  save_plot(plot(threshold_fit), "threshold_test.png", caption = note)
}

report_compare <- function() {
  comparison <- compare_outcome_threshold_test(suff_stats, threshold_fit, reference_race = reference_race)
  cat(sprintf("\n--- Naive outcome test vs. Threshold Test (reference race: %s) ---\n", reference_race))
  print(comparison)
  note <- interpret_outcome_threshold_comparison(comparison, reference_race = reference_race)
  cat(note, "\n")
  save_plot(
    plot_outcome_threshold_comparison(comparison, reference_race = reference_race),
    "outcome_threshold_comparison.png",
    width = 10, caption = note
  )
}

switch(subcommand,
  search = report_search(),
  fit = report_fit(),
  compare = report_compare(),
  all = {
    report_search()
    report_fit()
    report_compare()
  }
)
