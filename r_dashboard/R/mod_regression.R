# Shiny module: builds a logistic regression formula reactively from the
# sidebar toggles and renders an odds-ratio forest plot + summary table.
#
# Depends on ../../data/processed/audit_ready_stops.csv existing — see
# README Open Questions before wiring this up against real data.

regression_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    plotOutput(ns("forest_plot")),
    tableOutput(ns("model_table"))
  )
}

regression_module_server <- function(id, outcome_var, controls) {
  moduleServer(id, function(input, output, session) {
    stops_data <- reactive({
      path <- "../data/processed/audit_ready_stops.csv"
      validate(need(file.exists(path), "No processed dataset yet — run the Python pipeline first."))
      readr::read_csv(path, show_col_types = FALSE)
    })

    model_formula <- reactive({
      f <- paste(outcome_var(), "~ subject_race")
      if ("demographics" %in% controls()) f <- paste(f, "+ subject_age + subject_sex")
      if ("poverty" %in% controls()) f <- paste(f, "+ poverty_rate")
      if ("income" %in% controls()) f <- paste(f, "+ median_income")
      if ("time" %in% controls()) f <- paste(f, "+ factor(hour)")
      as.formula(f)
    })

    fitted_model <- reactive({
      glm(model_formula(), data = stops_data(), family = "binomial")
    })

    output$forest_plot <- renderPlot({
      model_df <- broom::tidy(fitted_model(), exponentiate = TRUE, conf.int = TRUE) |>
        dplyr::filter(stringr::str_detect(term, "subject_race"))

      ggplot2::ggplot(model_df, ggplot2::aes(x = term, y = estimate, ymin = conf.low, ymax = conf.high)) +
        ggplot2::geom_pointrange(color = "#2C3E50", linewidth = 0.8) +
        ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = "red") +
        ggplot2::coord_flip() +
        ggplot2::theme_minimal(base_size = 14) +
        ggplot2::labs(x = "", y = "Adjusted Odds Ratio (95% CI)")
    })

    output$model_table <- renderTable({
      broom::tidy(fitted_model(), exponentiate = TRUE, conf.int = TRUE) |>
        dplyr::select(Term = term, `Odds Ratio` = estimate, `p-value` = p.value, `CI Low` = conf.low, `CI High` = conf.high)
    })
  })
}
