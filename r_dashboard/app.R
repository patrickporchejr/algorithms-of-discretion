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

library(shiny)
library(bslib)
library(tidyverse)

source("R/mod_regression.R")

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
    card(
      card_header("Adjusted Odds Ratios (relative to white drivers)"),
      regression_module_ui("regression")
    )
  )
)

server <- function(input, output, session) {
  regression_module_server("regression", outcome_var = reactive(input$outcome_var), controls = reactive(input$controls))
}

shinyApp(ui = ui, server = server)
