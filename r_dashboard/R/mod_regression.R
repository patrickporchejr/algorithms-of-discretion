# Shiny module: builds a logistic regression formula reactively from the
# sidebar toggles and renders an odds-ratio forest plot + summary table.
#
# Depends on ../../data/processed/audit_ready_stops.csv existing — see
# README for the real-data pipeline that produces it.

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
      d <- readr::read_csv(path, show_col_types = FALSE)
      # glm() otherwise picks the reference level alphabetically ("black"),
      # silently contradicting the "relative to white drivers" plot header.
      d$subject_race <- stats::relevel(factor(d$subject_race), ref = "white")
      d
    })

    model_formula <- reactive({
      f <- paste(outcome_var(), "~ subject_race")
      if ("demographics" %in% controls()) f <- paste(f, "+ subject_sex")
      if ("poverty" %in% controls()) f <- paste(f, "+ poverty_rate")
      if ("income" %in% controls()) f <- paste(f, "+ median_income")
      if ("time" %in% controls()) f <- paste(f, "+ factor(hour)")
      as.formula(f)
    })

    fitted_model <- reactive({
      glm(model_formula(), data = stops_data(), family = "binomial")
    })

    # Wald CIs (estimate +/- 1.96*SE on the log-odds scale, then exponentiated),
    # computed directly from summary() rather than via broom::tidy(conf.int=TRUE).
    # broom delegates to confint.glm(), which defaults to profile-likelihood CIs —
    # each one requires refitting the model multiple times, which is fine at
    # textbook sample sizes but effectively hangs at 5.6M rows. Wald CIs are the
    # standard choice at this scale and are a closed-form calculation.
    model_summary <- reactive({
      coefs <- summary(fitted_model())$coefficients
      df <- tibble::as_tibble(coefs, rownames = "term")
      colnames(df) <- c("term", "estimate", "std.error", "statistic", "p.value")
      z <- stats::qnorm(0.975)
      df$conf.low <- exp(df$estimate - z * df$std.error)
      df$conf.high <- exp(df$estimate + z * df$std.error)
      df$estimate <- exp(df$estimate)
      df
    })

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
