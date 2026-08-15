# Algorithms of Discretion — Shiny audit dashboard
#
# Expects results/veil_*.rds and results/threshold_test.rds, produced by
# `make results` (which chains the Python data pipeline and then
# duboisR/inst/scripts/precompute_audit.R). The dataset is a frozen pull, so
# this app renders precomputed model fits rather than fitting live -- see
# that script and the module files for what's cached and why. See the
# README for the full pipeline setup.

# macOS defaults bitmapType to "quartz", which needs an active window-server
# session. When the app runs from a background/non-interactive process
# (Rscript launched without a foreground GUI session), quartz plot devices
# hang indefinitely instead of erroring — renderPlot() never resolves, so the
# forest plot area just stays blank forever. Cairo works headless.
if (capabilities("cairo")) options(bitmapType = "cairo")

# duboisR: the Wells-Du Bois Protocol diagnostic engine. Not on CRAN, and
# shinyapps.io's build backend doesn't support either renv's local-sources
# ("Cellar") mechanism or GitHub-sourced package installs (hit hard build
# failures with both -- see the README's Deployment section) -- so rather
# than have renv "install" duboisR at all, deploy bundles just carry a
# plain source copy (deploy/prepare.sh stages it at duboisR/, same as
# local dev's sibling ../duboisR checkout) and pkgload::load_all() it at
# startup, identically to how the shared loader below already works.
# renv is told to ignore duboisR entirely (see renv/settings.json) so it
# never tries to resolve/install it as a managed dependency.
duboisR_loader <- Find(file.exists, c(
  "duboisR/inst/scripts/_load_duboisR.R",   # deploy bundle (staged copy)
  "../duboisR/inst/scripts/_load_duboisR.R" # local dev (sibling checkout)
))
if (!is.null(duboisR_loader)) {
  source(duboisR_loader)
  load_duboisR_or_die(dirname(dirname(dirname(duboisR_loader))))
} else {
  library(duboisR)
}

library(shiny)
library(bslib)
library(tidyverse)

# Veil of Darkness, Threshold Test, Data Transparency & Provenance, and LLM
# Grounding Test are all active right now (see nav_panel section below).
# (The Regression Model / Subpopulation Disparities tabs that used to sit
# here were removed entirely, not just commented -- see the git history
# for r_dashboard/R/mod_regression.R and mod_subpop_disparities.R if you
# want them back.)
source("R/mod_veil_of_darkness.R")
source("R/mod_threshold_test.R")
source("R/mod_datasheet.R")
source("R/mod_grounding_experiment.R")

# Deploy bundles carry their own data/ and results/ (staged by
# deploy/prepare.sh, since shinyapps.io only uploads this directory); local
# dev falls back to the sibling repo layout instead.
DATA_PATH <- if (file.exists("data/audit_ready_stops.csv")) {
  "data/audit_ready_stops.csv"
} else {
  "../data/processed/audit_ready_stops.csv"
}
RESULTS_DIR <- if (dir.exists("results")) "results" else "../results"

ui <- page_fluid(
  theme = bs_theme(bootswatch = "litera", primary = "#2C3E50"),
  title = "Algorithms of Discretion: Traffic Stop Audit",

  layout_columns(
    navset_card_tab(
      nav_panel("Veil of Darkness (VOD)", veil_module_ui("veil")),
      nav_panel("Threshold Test", threshold_module_ui("threshold")),
      nav_panel("Data Transparency & Provenance", datasheet_module_ui("provenance")),
      nav_panel("LLM Grounding Test", grounding_module_ui("grounding"))
    )
  )
)

server <- function(input, output, session) {
  veil_module_server("veil", results_dir = RESULTS_DIR)
  threshold_module_server("threshold", results_dir = RESULTS_DIR)
  datasheet_module_server("provenance", results_dir = RESULTS_DIR, data_path = DATA_PATH)

  # Renders the precomputed results/grounding_experiment.rds only -- loading
  # this tab does NOT trigger any live LLM API calls (those only happen via
  # `make grounding` / duboisR::run_grounding_experiment(), a separate,
  # explicitly billed step). Degrades gracefully with a setup message if
  # the .rds doesn't exist yet.
  grounding_module_server("grounding", results_dir = RESULTS_DIR)
}

shinyApp(ui = ui, server = server)
