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
# This module reads precomputed results/veil_*.rds artifacts (see
# duboisR/inst/scripts/precompute_audit.R) rather than fitting live --
# prepare_veil_of_darkness_data() takes ~2min over the full dataset (the
# daylight/dark classification, not the fit itself), and the dataset is a
# frozen pull, so there's no reason to pay that per session.
#
# The sidebar's intersectional-controls checkboxes DO reach this tab (same
# as the Regression tab), with the same cache-vs-live-fallback split: no
# extra controls selected hits the fully-cached veil_<outcome>.rds (instant).
# Any control selected reads the cached veil_prepared.rds -- the *already
# daylight-classified* data, skipping the ~2min step -- and calls
# fit_veil_of_darkness() live, which is cheap (a few seconds), same as the
# Regression tab's live fallback.
#
# "Time of Day" is deliberately excluded from this tab's control_map: the
# fit already includes factor(hour) unconditionally whenever the
# intertwilight restriction leaves more than one distinct hour (structurally
# required for the test's own design, not an optional covariate), so
# checking it here would just duplicate a term already in the model.

VEIL_CONTROL_MAP <- list(
  demographics = "subject_sex",
  poverty = "poverty_rate",
  income = "median_income"
)

veil_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    plotOutput(ns("vod_plot"), height = "280px", fill = FALSE),
    tableOutput(ns("vod_table")),
    uiOutput(ns("vod_diagnostics"))
  )
}

veil_module_server <- function(id, outcome_var, controls_selected, results_dir) {
  moduleServer(id, function(input, output, session) {
    applicable_controls <- reactive({
      intersect(controls_selected(), names(VEIL_CONTROL_MAP))
    })

    vod_fit <- reactive({
      if (length(applicable_controls()) == 0) {
        path <- file.path(results_dir, paste0("veil_", outcome_var(), ".rds"))
        validate(need(file.exists(path), paste0("No cached result at ", path, " -- run `make results` first.")))
        return(readRDS(path))
      }

      prepared_path <- file.path(results_dir, "veil_prepared.rds")
      validate(need(file.exists(prepared_path), paste0("No cached result at ", prepared_path, " -- run `make results` first.")))
      prepared <- readRDS(prepared_path)
      duboisR::fit_veil_of_darkness(
        prepared,
        outcome_var = outcome_var(),
        interaction = TRUE,
        control_map = VEIL_CONTROL_MAP,
        controls_selected = applicable_controls()
      )
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
        tags$ul(lapply(vod_fit()$caveats, tags$li)),
        if ("time" %in% controls_selected()) {
          p(em(
            "\"Time of Day\" has no effect on this tab: this test already ",
            "controls for clock hour unconditionally (factor(hour) above), ",
            "so there's nothing extra for that checkbox to add here."
          ))
        }
      )
    })
  })
}
