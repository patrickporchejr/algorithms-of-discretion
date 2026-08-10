# Shiny module: "Threshold Test" tab.
#
# Wraps duboisR::aggregate_sufficient_statistics() + fit_threshold_test() --
# the fast (non-hierarchical, non-MCMC) approximation to the Threshold Test
# for infra-marginality (Simoiu, Corbett-Davies & Goel 2017). The statistical
# core lives entirely in duboisR/R/threshold_test.R; this module is a thin
# reactive wrapper, same pattern as the other tabs. The scatter/curve plot
# reuses the package's own plot.duboisR_threshold_fit() S3 method. Unlike
# the Regression Model tab, this always models search_conducted /
# contraband_found regardless of the sidebar's "Target Outcome" dropdown --
# that pairing is the Threshold Test's own methodology, not a swappable
# outcome.

threshold_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    plotOutput(ns("threshold_plot"), height = "320px", fill = FALSE),
    h5("Fitted risk-distribution parameters per race"),
    tableOutput(ns("race_params_table")),
    h5("Weighted mean inferred threshold per race"),
    tableOutput(ns("summary_table")),
    uiOutput(ns("threshold_notes"))
  )
}

threshold_module_server <- function(id, stops_data) {
  moduleServer(id, function(input, output, session) {
    threshold_fit <- reactive({
      suff_stats <- duboisR::aggregate_sufficient_statistics(stops_data())
      duboisR::fit_threshold_test(suff_stats)
    })

    output$threshold_plot <- renderPlot({
      plot(threshold_fit())
    })

    output$race_params_table <- renderTable({
      threshold_fit()$race_params |>
        dplyr::select(Race = race, a, b, `Convergence Code` = convergence_code, `Counties Used` = n_cells_used_in_fit)
    })

    output$summary_table <- renderTable({
      threshold_fit()$summary |>
        dplyr::select(Race = race, `Weighted Mean Threshold` = mean_threshold_weighted, Counties = n_counties)
    })

    output$threshold_notes <- renderUI({
      rp <- threshold_fit()$race_params
      nonconverged <- rp$race[rp$convergence_code != 0]
      near_degenerate <- rp$race[rp$a > 1e6 | rp$b > 1e6]
      tagList(
        if (length(nonconverged) > 0) {
          p(
            strong("Optimizer did not fully converge"), " (nonzero convergence code) for: ",
            paste(nonconverged, collapse = ", "), ". Treat that race's fitted (a, b) and ",
            "downstream thresholds cautiously."
          )
        },
        if (length(near_degenerate) > 0) {
          p(
            strong("Extremely large fitted (a, b)"), " for: ", paste(near_degenerate, collapse = ", "),
            " -- consistent with a near point-mass risk distribution for that race. The predicted ",
            "search-rate/hit-rate curve above can become numerically degenerate (effectively invisible) ",
            "across parts of the observed search-rate range for such races; the summary table's point ",
            "estimates are still computed, but read the curve for that race with extra caution."
          )
        },
        p(em(
          "This is a fast, non-hierarchical, non-MCMC point-estimate approximation ",
          "(no partial pooling, no credible intervals) -- describe results as ",
          "\"in the spirit of\" Simoiu, Corbett-Davies & Goel (2017), not identical to it."
        ))
      )
    })
  })
}
