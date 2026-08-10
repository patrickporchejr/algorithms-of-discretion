# Algorithms of Discretion — Shiny audit dashboard
#
# Expects ../data/processed/audit_ready_stops.csv, produced by the Python
# pipeline (python/01-03) against Texas State Patrol (Stanford Open Policing)
# + ACS county data. See README for the real-data setup.

# macOS defaults bitmapType to "quartz", which needs an active window-server
# session. When the app runs from a background/non-interactive process
# (Rscript launched without a foreground GUI session), quartz plot devices
# hang indefinitely instead of erroring — renderPlot() never resolves, so the
# forest plot area just stays blank forever. Cairo works headless.
if (capabilities("cairo")) options(bitmapType = "cairo")

# duboisR: the Wells-Du Bois Protocol diagnostic engine. Dev-mode loads the
# sibling package source directly (no install step required); falls back to
# an installed copy if present (e.g. after `devtools::install("duboisR")`).
if (requireNamespace("duboisR", quietly = TRUE)) {
  library(duboisR)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all("../duboisR", quiet = TRUE)
} else {
  stop(
    "duboisR is not installed and devtools is unavailable to load it from ",
    "source. Run: Rscript -e 'install.packages(\"devtools\"); devtools::install(\"duboisR\")'"
  )
}

library(shiny)
library(bslib)
library(tidyverse)

source("R/mod_regression.R")
source("R/mod_datasheet.R")
source("R/mod_veil_of_darkness.R")
source("R/mod_threshold_test.R")
source("R/mod_subpop_disparities.R")

DATA_PATH <- "../data/processed/audit_ready_stops.csv"

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
      ),
      selected = c("demographics")
    ),
    helpText(
      "Each layer tests how much raw racial disparity persists after ",
      "accounting for a structural covariate. See the README for what ",
      "these layers can't account for."
    )
  ),

  layout_columns(
    navset_card_tab(
      title = "Adjusted Odds Ratios (relative to white drivers)",
      nav_panel("Regression Model", regression_module_ui("regression")),
      nav_panel("Veil of Darkness", veil_module_ui("veil")),
      nav_panel("Threshold Test", threshold_module_ui("threshold")),
      nav_panel("Subpopulation Disparities", subpop_module_ui("subpop")),
      nav_panel("Data Transparency & Provenance", datasheet_module_ui("provenance"))
    )
  )
)

server <- function(input, output, session) {
  # Shared across all tabs -- the regression model, veil-of-darkness test,
  # threshold test, subpopulation disparities, and the provenance tab's live
  # composition numbers all need the same loaded/releveled data.
  stops_data <- reactive({
    validate(need(file.exists(DATA_PATH), "No processed dataset yet — run the Python pipeline first."))
    d <- readr::read_csv(DATA_PATH, show_col_types = FALSE)
    # glm() otherwise picks the reference level alphabetically ("black"),
    # silently contradicting the "relative to white drivers" plot header.
    duboisR::dubois_relevel(d, "subject_race", ref = "white")
  })

  # Also shared -- the Subpopulation Disparities tab scores this SAME fitted
  # model (not a separate glm() call) so it reads as "how does the
  # currently-adjusted model perform across subgroups," not a divergent fit.
  audit_fit <- reactive({
    control_map <- list(
      demographics = "subject_sex",
      poverty = "poverty_rate",
      income = "median_income",
      time = "factor(hour)"
    )
    formula <- duboisR::build_formula(input$outcome_var, "subject_race", control_map, input$controls)
    duboisR::fit_audit_glm(stops_data(), formula)
  })

  regression_module_server("regression", audit_fit = audit_fit)
  veil_module_server(
    "veil",
    stops_data = stops_data,
    outcome_var = reactive(input$outcome_var)
  )
  threshold_module_server("threshold", stops_data = stops_data)
  subpop_module_server(
    "subpop",
    stops_data = stops_data,
    audit_fit = audit_fit,
    outcome_var = reactive(input$outcome_var)
  )
  datasheet_module_server("provenance", stops_data = stops_data, data_path = DATA_PATH)
}

shinyApp(ui = ui, server = server)
