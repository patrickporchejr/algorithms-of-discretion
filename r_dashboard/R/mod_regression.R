# Shiny module: renders an odds-ratio forest plot + summary table from a
# fitted audit GLM.
#
# The statistical core (formula construction, the GLM fit, and its
# closed-form Wald confidence intervals) lives in the duboisR package
# (R/glm_utils.R: build_formula(), fit_audit_glm()) rather than here, so it's
# tested and reusable outside Shiny.
#
# The audit_fit() reactive itself lives in app.R's server(), not here --
# mod_subpop_disparities.R will need the same fitted model to score against
# once it's wired up. It now reads a precomputed results/regression_*.rds
# artifact (see duboisR/inst/scripts/precompute_audit.R) rather than calling
# fit_audit_glm() live -- the dataset is a frozen pull, so there's no reason
# to refit per session. The cached fit's `$model` (the raw glm object) is
# stripped before caching -- see the script for why -- so this module (and
# the future subpop one) can only rely on `$summary`, not on scoring new
# data against the live model object.

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
    tableOutput(ns("model_table")),
    tags$hr(),
    tags$h5("Predicted Probability by Race"),
    plotOutput(ns("probability_plot"), height = "420px", fill = FALSE),
    tableOutput(ns("probability_table"))
  )
}

regression_module_server <- function(id, audit_fit) {
  moduleServer(id, function(input, output, session) {
    model_summary <- reactive({ audit_fit()$fit$summary })

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

    predicted_probs <- reactive({ audit_fit()$predicted_probabilities })

    output$probability_plot <- renderPlot({
      ggplot2::ggplot(predicted_probs(), ggplot2::aes(x = level, y = probability, ymin = conf.low, ymax = conf.high)) +
        ggplot2::geom_pointrange(color = "#2C3E50", linewidth = 0.8) +
        ggplot2::coord_flip() +
        ggplot2::scale_y_continuous(labels = scales::percent) +
        ggplot2::theme_minimal(base_size = 14) +
        ggplot2::labs(x = "", y = "Predicted Probability (95% CI)")
    })

    output$probability_table <- renderTable({
      predicted_probs() |>
        dplyr::select(Race = level, Probability = probability, `CI Low` = conf.low, `CI High` = conf.high)
    }, digits = 3)
  })
}
