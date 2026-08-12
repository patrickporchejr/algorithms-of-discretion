# Shiny module: "Veil of Darkness" tab.
#
# Wraps duboisR::veil_of_darkness_test() -- the natural-experiment comparison
# of stop outcomes in daylight vs. after dark (Grogger & Ridgeway 2006),
# restricted to intertwilight clock hours so the comparison isn't confounded
# by clock-time commuting patterns. The statistical core (sunset/dusk lookups
# via suncalc, the intertwilight restriction, the GLM fit) all lives in
# duboisR. The forest plot reuses the package's own plot.duboisR_vod_result()
# S3 method rather than re-implementing it here.
#
# fit_veil_of_darkness() was called with interaction = TRUE when this was
# precomputed: the Grogger & Ridgeway hypothesis is specifically that the
# RACIAL DISPARITY shrinks once officers can't see race well, which only an
# interaction term (race x is_dark) can test. An additive-only model can
# show "race matters" and "darkness matters" separately but structurally
# cannot show whether darkness changes the racial disparity -- i.e. it
# cannot test the actual hypothesis this tab is named after.
#
# This module reads a precomputed results/veil_*.rds artifact (see
# duboisR/inst/scripts/precompute_audit.R) rather than fitting live --
# prepare_veil_of_darkness_data() takes ~2min over the full dataset (the
# daylight/dark classification, not the fit itself), and the dataset is a
# frozen pull, so there's no reason to pay that per session. Only which
# outcome's cached artifact to load reacts to outcome_var.

veil_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    plotOutput(ns("vod_plot"), height = "280px", fill = FALSE),
    tableOutput(ns("vod_table")),
    uiOutput(ns("vod_diagnostics"))
  )
}

veil_module_server <- function(id, outcome_var, results_dir) {
  moduleServer(id, function(input, output, session) {
    vod_fit <- reactive({
      path <- file.path(results_dir, paste0("veil_", outcome_var(), ".rds"))
      validate(need(file.exists(path), paste0("No cached result at ", path, " -- run `make results` first.")))
      readRDS(path)
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
