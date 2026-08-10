# Shiny module: "Veil of Darkness" tab.
#
# Wraps duboisR::veil_of_darkness_test() -- the natural-experiment comparison
# of stop outcomes in daylight vs. after dark (Grogger & Ridgeway 2006),
# restricted to intertwilight clock hours so the comparison isn't confounded
# by clock-time commuting patterns. The statistical core (sunset/dusk lookups
# via suncalc, the intertwilight restriction, the GLM fit) all lives in
# duboisR::veil_of_darkness_test(); this module is a thin reactive wrapper,
# same pattern as mod_regression.R. The forest plot reuses the package's own
# plot.duboisR_vod_result() S3 method rather than re-implementing it here.

veil_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    plotOutput(ns("vod_plot"), height = "280px", fill = FALSE),
    tableOutput(ns("vod_table")),
    uiOutput(ns("vod_diagnostics"))
  )
}

veil_module_server <- function(id, stops_data, outcome_var) {
  moduleServer(id, function(input, output, session) {
    vod_fit <- reactive({
      duboisR::veil_of_darkness_test(stops_data(), outcome_var = outcome_var())
    })

    output$vod_plot <- renderPlot({
      plot(vod_fit())
    })

    output$vod_table <- renderTable({
      vod_fit()$model_fit$summary |>
        dplyr::select(Term = term, `Odds Ratio` = estimate, `p-value` = p.value, `CI Low` = conf.low, `CI High` = conf.high)
    })

    output$vod_diagnostics <- renderUI({
      d <- vod_fit()$diagnostics
      tagList(
        p(
          strong(format(d$n_used, big.mark = ",")), " of ",
          format(d$n_total, big.mark = ","), " stops used, restricted to intertwilight hours (",
          paste(d$hours_used, collapse = ", "), " -- the clock hours that fall on both sides of ",
          "daylight/dark across the data's date and county range). Dropped ",
          format(d$n_dropped_twilight, big.mark = ","), " stops in civil twilight and ",
          format(d$n_dropped_no_centroid, big.mark = ","), " stops with no county centroid match."
        ),
        tags$ul(lapply(vod_fit()$caveats, tags$li))
      )
    })
  })
}
