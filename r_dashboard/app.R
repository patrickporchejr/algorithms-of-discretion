# Algorithms of Discretion — Shiny audit dashboard
#
# Expects results/regression_*.rds and results/veil_*.rds, produced by
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

source("R/mod_regression.R")
source("R/mod_veil_of_darkness.R")
source("R/mod_threshold_test.R")
source("R/mod_subpop_disparities.R")
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

AUDIT_CONTROL_MAP <- list(
  demographics = "subject_sex",
  poverty = "poverty_rate",
  income = "median_income",
  time = "factor(hour)"
)

ui <- page_sidebar(
  theme = bs_theme(bootswatch = "litera", primary = "#2C3E50"),
  title = "Algorithms of Discretion: Traffic Stop Audit",

  sidebar = sidebar(
    title = "Audit Controls",
    selectInput(
      "outcome_var", "Target Outcome:",
      choices = c(
        "Search Conducted" = "search_conducted",
        "Contraband Found" = "contraband_found"
      )
    ),
    checkboxGroupInput(
      "controls", "Layer Intersectional Controls:",
      choices = c(
        "Driver Sex" = "demographics",
        "County Poverty Rate" = "poverty",
        "County Median Income" = "income",
        "Time of Day" = "time"
      )
    ),
    helpText(
      "Each layer tests how much raw racial disparity persists after ",
      "accounting for a structural covariate. See the README for what ",
      "these layers can't account for."
    )
  ),

  layout_columns(
    navset_card_tab(
      title = "Adjusted Odds Ratios",
      nav_panel("Regression Model", regression_module_ui("regression")),
      nav_panel("Veil of Darkness", veil_module_ui("veil")),
      nav_panel("Threshold Test", threshold_module_ui("threshold")),
      nav_panel("Subpopulation Disparities", subpop_module_ui("subpop")),
      nav_panel("Data Transparency & Provenance", datasheet_module_ui("provenance")),
      nav_panel("LLM Grounding Test", grounding_module_ui("grounding"))
    )
  )
)

server <- function(input, output, session) {
  # Loaded lazily -- only actually read when live_audit_fit() needs it
  # (controls selected on Regression, or Subpopulation Disparities).
  stops_data <- reactive({
    validate(need(file.exists(DATA_PATH), "No processed dataset yet — run `make all` first."))
    d <- readr::read_csv(DATA_PATH, show_col_types = FALSE)
    # glm() otherwise picks the reference level alphabetically ("black"),
    # silently contradicting the "relative to white drivers" plot header.
    duboisR::dubois_relevel(d, "subject_race", ref = "white")
  })

  # Always fits live, keeping $model -- unlike audit_fit() below, this never
  # reads the model-stripped cache. Subpopulation Disparities needs to call
  # predict() against arbitrary subgroups, which the (deliberately shrunk,
  # see precompute_audit.R) cached artifacts can't support. Cheap enough to
  # always live-fit regardless (~9s for the glm() call; predict() + the
  # subgroup aggregation together are ~1.3s over the full 5.6M rows), so
  # there's no cache/live branch to maintain here the way audit_fit() has.
  live_audit_fit <- reactive({
    formula <- duboisR::build_formula(input$outcome_var, "subject_race", AUDIT_CONTROL_MAP, input$controls)
    fit <- duboisR::fit_audit_glm(stops_data(), formula)
    list(fit = fit, predicted_probabilities = duboisR::predicted_probabilities(fit, stops_data(), "subject_race"))
  })

  # results/regression_<outcome>.rds (see
  # duboisR/inst/scripts/precompute_audit.R) only covers the no-controls
  # fit per outcome -- precomputing all 16 possible control combinations
  # wasn't worth it when a live glm() fit against the full 5.6M-row dataset
  # only takes ~9s. So: no controls selected hits the instant cached path;
  # any control selected delegates to live_audit_fit() above (Shiny memoizes
  # it per reactive flush, so this doesn't duplicate work when Subpopulation
  # Disparities is also live with the same outcome/controls). Both branches
  # return the same shape (list(fit=, predicted_probabilities=)) so the
  # modules downstream don't need to know which path served them.
  audit_fit <- reactive({
    if (length(input$controls) == 0) {
      path <- file.path(RESULTS_DIR, paste0("regression_", input$outcome_var, ".rds"))
      validate(need(file.exists(path), paste0("No cached result at ", path, " -- run `make results` first.")))
      return(readRDS(path))
    }
    live_audit_fit()
  })

  regression_module_server("regression", audit_fit = audit_fit)
  veil_module_server(
    "veil",
    outcome_var = reactive(input$outcome_var),
    controls_selected = reactive(input$controls),
    results_dir = RESULTS_DIR
  )
  threshold_module_server("threshold", results_dir = RESULTS_DIR)
  subpop_module_server(
    "subpop",
    stops_data = stops_data,
    audit_fit = live_audit_fit,
    outcome_var = reactive(input$outcome_var)
  )
  datasheet_module_server("provenance", results_dir = RESULTS_DIR, data_path = DATA_PATH)
  grounding_module_server("grounding", results_dir = RESULTS_DIR)
}

shinyApp(ui = ui, server = server)
