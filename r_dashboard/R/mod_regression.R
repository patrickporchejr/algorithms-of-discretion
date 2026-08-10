# Shiny module: renders an odds-ratio forest plot + summary table from a
# fitted audit GLM.
#
# The statistical core (formula construction, the GLM fit, and its
# closed-form Wald confidence intervals) lives in the duboisR package
# (R/glm_utils.R: build_formula(), fit_audit_glm()) rather than here, so it's
# tested and reusable outside Shiny. This module is now a thin reactive
# wrapper around that package API.
#
# The audit_fit() reactive itself lives in app.R's server(), not here --
# mod_subpop_disparities.R needs the same fitted model to score against, so
# it's shared across both modules the same way stops_data() is (see app.R).

regression_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    # fill = FALSE is the load-bearing part: plotOutput() defaults to
    # fill = TRUE, which makes bslib treat it as a flex item inside
    # navset_card_tab's card body and stretch/shrink it to the flex
    # container's computed height -- overriding the explicit height below.
    # When that flex computation collapses toward 0 (viewport-dependent),
    # ggplot's theme margins exceed the device size and grid throws
    # "figure margins too large". fill = FALSE takes the plot out of the
    # flex layout so height = "420px" is actually respected.
    plotOutput(ns("forest_plot"), height = "420px", fill = FALSE),
    tableOutput(ns("model_table"))
  )
}

regression_module_server <- function(id, audit_fit) {
  moduleServer(id, function(input, output, session) {
    model_summary <- reactive({ audit_fit()$summary })

    output$forest_plot <- renderPlot({
      model_df <- model_summary() |>
        dplyr::filter(stringr::str_detect(term, "subject_race"))

      ggplot2::ggplot(model_df, ggplot2::aes(x = term, y = estimate, ymin = conf.low, ymax = conf.high)) +
        ggplot2::geom_pointrange(color = "#2C3E50", linewidth = 0.8) +
        ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = "red") +
        ggplot2::coord_flip() +
        ggplot2::theme_minimal(base_size = 14) +
        ggplot2::labs(x = "", y = "Adjusted Odds Ratio (95% CI)")
    })

    output$model_table <- renderTable({
      model_summary() |>
        dplyr::select(Term = term, `Odds Ratio` = estimate, `p-value` = p.value, `CI Low` = conf.low, `CI High` = conf.high)
    })
  })
}
