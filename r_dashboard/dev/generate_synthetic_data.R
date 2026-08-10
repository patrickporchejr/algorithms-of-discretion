#!/usr/bin/env Rscript
# Schema-correct synthetic data matching the real audit_ready_stops.csv data
# contract, so the Shiny app can be exercised locally before the real Python
# pipeline (01-03) has run against a decided-on state dataset. Not a source
# of real findings.
#
# Thin wrapper around duboisR::simulate_stops() -- the same function the
# package's own test fixtures use -- so this script can no longer drift from
# the real schema the way the old standalone generator did (it used to
# fabricate subject_age/is_arrested, neither of which the real Texas State
# Patrol data has).

# Resolved relative to this script's own location, not the shell's cwd --
# this script is documented (README) to be run from the repo root, unlike
# app.R which runs with r_dashboard/ as its cwd.
file_arg <- sub("--file=", "", grep("--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
script_dir <- dirname(normalizePath(file_arg))

if (requireNamespace("duboisR", quietly = TRUE)) {
  library(duboisR)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(file.path(script_dir, "..", "..", "duboisR"), quiet = TRUE)
} else {
  stop(
    "duboisR is not installed and devtools is unavailable to load it from ",
    "source. Run: Rscript -e 'install.packages(\"devtools\"); devtools::install(\"duboisR\")'"
  )
}

df <- simulate_stops(n = 2000, seed = 42)

out_path <- file.path(script_dir, "..", "..", "data", "processed", "audit_ready_stops.csv")
readr::write_csv(df, out_path)
cat("Wrote", nrow(df), "rows to", normalizePath(out_path), "\n")
