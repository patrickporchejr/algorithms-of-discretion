# Shiny module: "Subpopulation Disparities" tab.
#
# Wraps duboisR::subpopulation_disparities() -- disaggregates a fitted
# model's True Positive Rate / False Positive Rate / Positive Predictive
# Value per intersectional subgroup (race x sex), reporting the
# Chouldechova / Kleinberg-Mullainathan-Raghavan fairness-metrics trade-off
# rather than resolving it. `audit_fit` here is app.R's live_audit_fit(),
# not the (possibly model-stripped, see precompute_audit.R) audit_fit() the
# Regression tab uses -- this tab needs predict()'s ability to score
# arbitrary subgroups, which the shrunk cache can't support. It's the same
# formula/data either way, so this still answers "how does the
# currently-adjusted model perform across subgroups," just always freshly
# fit rather than sometimes read from cache.
#
# The predicted-positive threshold defaults to the outcome's own observed
# base rate rather than a hardcoded 0.5: search_conducted's base rate is
# ~1.6% in the real Texas data, so a fixed 0.5 threshold predicts everything
# negative and every TPR/PPV comes back NaN (0/0). Base rate is a standard,
# non-ideological default for an imbalanced binary threshold classifier; the
# slider lets a researcher move off it. The slider is debounced (300ms):
# scoring is ~1.3s over the full dataset, cheap for one recompute but a drag
# gesture fires many intermediate values, so debouncing avoids queuing up a
# backlog of stale recomputations.

subpop_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("threshold_slider")),
    plotOutput(ns("subpop_plot"), height = "320px", fill = FALSE),
    tableOutput(ns("subpop_table")),
    uiOutput(ns("subpop_notes"))
  )
}

subpop_module_server <- function(id, stops_data, audit_fit, outcome_var) {
  moduleServer(id, function(input, output, session) {
    default_threshold <- reactive({
      round(mean(stops_data()[[outcome_var()]], na.rm = TRUE), 3)
    })

    output$threshold_slider <- renderUI({
      ns <- session$ns
      sliderInput(
        ns("threshold"), "Predicted-positive threshold:",
        min = 0, max = 1, value = default_threshold(), step = 0.005
      )
    })

    threshold_debounced <- reactive({ input$threshold }) |> debounce(300)

    subpop_fit <- reactive({
      req(threshold_debounced())
      duboisR::subpopulation_disparities(
        audit_fit()$fit, stops_data(),
        actual_col = outcome_var(), threshold = threshold_debounced()
      )
    })

    output$subpop_plot <- renderPlot({
      plot(subpop_fit())
    })

    output$subpop_table <- renderTable({
      subpop_fit() |>
        dplyr::select(Group = group, N = n, `Base Rate` = base_rate, TPR, FPR, PPV)
    })

    output$subpop_notes <- renderUI({
      fit <- subpop_fit()
      predictors <- all.vars(stats::delete.response(stats::terms(audit_fit()$fit$model)))
      # subgroups here are always race x sex (subpop_module_ui's fixed
      # subgroup_cols); if the model's predictors are a subset of those same
      # two columns, every driver in a subgroup shares one predicted
      # probability, so TPR/FPR degenerate to exactly 0 or 1 at any single
      # threshold instead of a real distribution -- worth flagging before a
      # user reads an all-or-nothing bar chart as a bug.
      degenerate_risk <- length(setdiff(predictors, c("subject_race", "subject_sex"))) == 0

      tagList(
        if (degenerate_risk) {
          p(
            strong("Note: "), "the current model's only predictors are Driver Sex (and/or race), ",
            "the exact columns these subgroups are defined by -- so every driver in a group gets an ",
            "identical predicted probability. At any single threshold, TPR/FPR come back exactly 0 ",
            "or 1 per group rather than a real distribution. Check more control layers in the ",
            "sidebar (County Poverty Rate, County Median Income, Time of Day) for within-group ",
            "variation in the scores."
          )
        },
        tags$ul(lapply(attr(fit, "notes"), tags$li))
      )
    })
  })
}
