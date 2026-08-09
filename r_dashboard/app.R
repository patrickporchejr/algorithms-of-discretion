# Algorithms of Discretion — Shiny audit dashboard
#
# Not runnable yet: r_dashboard/R modules expect
# ../data/processed/audit_ready_stops.csv, which doesn't exist until the
# Python pipeline (python/01-03) has run against a real, decided-on state
# dataset. See README Open Questions #1.

library(shiny)
library(bslib)
library(tidyverse)
library(broom)

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
        "Arrest Made" = "is_arrested"
      )
    ),
    checkboxGroupInput(
      "controls", "Layer Intersectional Controls:",
      choices = c(
        "Driver Age & Sex" = "demographics",
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
