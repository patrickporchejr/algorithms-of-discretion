# Shiny module: "Veil of Darkness" tab.
#
# --- Previous implementation (adjusted-odds forest plot via
# duboisR::fit_veil_of_darkness()/plot.duboisR_vod_result()) commented out
# while this tab is rebuilt around descriptive charts instead. Uncomment to
# bring it back -- it still works as-is against results/veil_<outcome>.rds.
#
# # Wraps duboisR::veil_of_darkness_test() -- the natural-experiment comparison
# # of stop outcomes in daylight vs. after dark (Grogger & Ridgeway 2006),
# # restricted to intertwilight clock hours so the comparison isn't confounded
# # by clock-time commuting patterns. The statistical core (sunset/dusk lookups
# # via suncalc, the intertwilight restriction, the GLM fit) all lives in
# # duboisR. The forest plot reuses the package's own plot.duboisR_vod_result()
# # S3 method rather than re-implementing it here.
# #
# # fit_veil_of_darkness() was called with interaction = TRUE when this was
# # precomputed: the Grogger & Ridgeway hypothesis is specifically that the
# # RACIAL DISPARITY shrinks once officers can't see race well, which only an
# # interaction term (race x is_dark) can test. An additive-only model can
# # show "race matters" and "darkness matters" separately but structurally
# # cannot show whether darkness changes the racial disparity -- i.e. it
# # cannot test the actual hypothesis this tab is named after.
# #
# # This module reads precomputed results/veil_*.rds artifacts (see
# # duboisR/inst/scripts/precompute_audit.R) rather than fitting live --
# # prepare_veil_of_darkness_data() takes ~2min over the full dataset (the
# # daylight/dark classification, not the fit itself), and the dataset is a
# # frozen pull, so there's no reason to pay that per session.
# #
# # The sidebar's intersectional-controls checkboxes DO reach this tab (same
# # as the Regression tab), with the same cache-vs-live-fallback split: no
# # extra controls selected hits the fully-cached veil_<outcome>.rds (instant).
# # Any control selected reads the cached veil_prepared.rds -- the *already
# # daylight-classified* data, skipping the ~2min step -- and calls
# # fit_veil_of_darkness() live, which is cheap (a few seconds), same as the
# # Regression tab's live fallback.
# #
# # "Time of Day" is deliberately excluded from this tab's control_map: the
# # fit already includes factor(hour) unconditionally whenever the
# # intertwilight restriction leaves more than one distinct hour (structurally
# # required for the test's own design, not an optional covariate), so
# # checking it here would just duplicate a term already in the model.
#
# VEIL_CONTROL_MAP <- list(
#   demographics = "subject_sex",
#   poverty = "poverty_rate",
#   income = "median_income"
# )
#
# veil_module_ui <- function(id) {
#   ns <- NS(id)
#   tagList(
#     plotOutput(ns("vod_plot"), height = "280px", fill = FALSE),
#     tableOutput(ns("vod_table")),
#     uiOutput(ns("vod_diagnostics"))
#   )
# }
#
# veil_module_server <- function(id, outcome_var, controls_selected, results_dir) {
#   moduleServer(id, function(input, output, session) {
#     applicable_controls <- reactive({
#       intersect(controls_selected(), names(VEIL_CONTROL_MAP))
#     })
#
#     vod_fit <- reactive({
#       if (length(applicable_controls()) == 0) {
#         path <- file.path(results_dir, paste0("veil_", outcome_var(), ".rds"))
#         validate(need(file.exists(path), paste0("No cached result at ", path, " -- run `make results` first.")))
#         return(readRDS(path))
#       }
#
#       prepared_path <- file.path(results_dir, "veil_prepared.rds")
#       validate(need(file.exists(prepared_path), paste0("No cached result at ", prepared_path, " -- run `make results` first.")))
#       prepared <- readRDS(prepared_path)
#       duboisR::fit_veil_of_darkness(
#         prepared,
#         outcome_var = outcome_var(),
#         interaction = TRUE,
#         control_map = VEIL_CONTROL_MAP,
#         controls_selected = applicable_controls()
#       )
#     })
#
#     output$vod_plot <- renderPlot({
#       plot(vod_fit())
#     })
#
#     output$vod_table <- renderTable({
#       vod_fit()$model_fit$summary |>
#         dplyr::select(Term = term, `Odds Ratio` = estimate, `p-value` = p.value, `CI Low` = conf.low, `CI High` = conf.high)
#     })
#
#     output$vod_diagnostics <- renderUI({
#       d <- vod_fit()$diagnostics
#       tagList(
#         p(
#           strong(format(d$n_used, big.mark = ",")), " of ",
#           format(d$n_total, big.mark = ","), " stops used, restricted to intertwilight hours (",
#           paste(d$hours_used, collapse = ", "), " -- the clock hours that fall on both sides of ",
#           "daylight/dark across the data's date and county range). Dropped ",
#           format(d$n_dropped_twilight, big.mark = ","), " stops in civil twilight and ",
#           format(d$n_dropped_no_centroid, big.mark = ","), " stops with no county centroid match."
#         ),
#         tags$ul(lapply(vod_fit()$caveats, tags$li)),
#         if ("time" %in% controls_selected()) {
#           p(em(
#             "\"Time of Day\" has no effect on this tab: this test already ",
#             "controls for clock hour unconditionally (factor(hour) above), ",
#             "so there's nothing extra for that checkbox to add here."
#           ))
#         }
#       )
#     })
#   })
# }

# --- Current implementation: two charts, in a fixed order (statewide
# composition -> county-level VoD ratio), both about the stop decision
# only. Each chart is followed by two short text blocks, in this order: a
# plain caption (what the chart generically shows) and a plain
# interpretation (what THIS data actually shows, read straight off the
# same numbers the chart plots) -- both below the chart, not above it, so
# the chart is the first thing a reader sees.
#
# The search decision (how often people get searched, and how justified
# those searches are) used to have a "combined" section here comparing the
# stop and search decisions side by side. It moved out entirely, to the
# Threshold Test tab (r_dashboard/R/mod_threshold_test.R): search rate was
# never actually restricted to daylight/dark or the intertwilight window,
# so its only real tie to Veil of Darkness was that one comparison chart,
# and it belongs with the rest of the search-decision diagnostics (search
# frequency + the Threshold Test's search-justification estimate) instead
# of split across two unrelated tabs.
#
# A third section -- the search decision's race:is_dark interaction GLM
# forest plot -- was removed earlier for a related reason: on the frozen
# dataset it didn't show anything that changed the picture (the Black
# interaction term's CI always crossed 1), and the search decision is
# already the weaker half of the veil-of-darkness logic anyway (by the
# time an officer decides whether to search, they've typically already had
# close-up contact with the driver). duboisR::fit_veil_of_darkness() /
# plot.duboisR_vod_result() / interpret_veil_regression() remain in the
# package for console/white-paper use; they're just not part of this
# tab's or the CLI's default surface anymore.
#
# The interpretation text is NOT static copy -- it's generated by
# duboisR::interpret_statewide_vod() / interpret_county_vod_disparity(),
# which read the actual reactive data and narrate the real numbers (which
# race's share moved most, the median county's ratio). Kept in duboisR
# rather than written inline here so the CLI/console module can reuse the
# same narration later instead of a second copy drifting out of sync with
# the charts.
#
# One cached input: results/vod_charts.rds -- county_vod_disparity and
# statewide_vod, both stop-decision-only tables -- built by
# duboisR/inst/scripts/precompute_audit.R on top of
# prepare_veil_of_darkness_data() output, so no live daylight/dark
# classification or geocoding happens in this module.
#
# The actual plot-building (ggplot calls, the black/white filter, the
# min-n threshold) lives in duboisR's plot_statewide_vod() /
# plot_county_vod_disparity() -- the same functions
# duboisR::veil_of_darkness_module() and the CLI
# (duboisR/inst/scripts/veil_of_darkness_cli.R) call, so this module, the
# CLI, and any future consumer render identically from one tested source
# instead of three copies of the same ggplot code.

VOD_MIN_N <- 30

veil_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h4("Statewide racial composition of stops, before vs. after dark"),
    plotOutput(ns("statewide_vod_plot"), height = "320px"),
    tableOutput(ns("statewide_vod_table")),
    p(
      "Each bar shows the share of stops by race, split into ",
      "daylight and after-dark stops. If officers can't see race after ",
      "it's dark, each bar pair should look about the same in both conditions. ",
      "A shift suggests race is visible and shaping who gets pulled over."
    ),
    uiOutput(ns("statewide_interpretation")),

    h4("County-level Veil of Darkness ratio"),
    plotOutput(ns("county_vod_plot"), height = "360px"),
    p(
      "Each dot is a county: its Black share of stops after dark, divided ",
      "by its Black share of stops in daylight (near 1.0 = no shift). ",
      "This is the same comparison as the statewide chart above, broken ",
      "out by county, so you can see whether the pattern holds everywhere ",
      "or is driven by a handful of outliers."
    ),
    uiOutput(ns("county_vod_interpretation"))
  )
}

veil_module_server <- function(id, results_dir) {
  moduleServer(id, function(input, output, session) {
    charts_data <- reactive({
      path <- file.path(results_dir, "vod_charts.rds")
      validate(need(file.exists(path), paste0("No cached result at ", path, " -- run `make results` first.")))
      readRDS(path)
    })

    statewide_vod_table <- reactive({
      duboisR::summarize_statewide_vod_table(charts_data()$statewide_vod)
    })

    output$statewide_vod_plot <- renderPlot({
      duboisR::plot_statewide_vod(charts_data()$statewide_vod)
    })

    output$statewide_vod_table <- renderTable(statewide_vod_table())

    output$statewide_interpretation <- renderUI({
      p(strong("What this data shows: "), duboisR::interpret_statewide_vod(statewide_vod_table()))
    })

    output$county_vod_plot <- renderPlot({
      duboisR::plot_county_vod_disparity(charts_data()$county_vod_disparity, min_n = VOD_MIN_N)
    })

    output$county_vod_interpretation <- renderUI({
      p(strong("What this data shows: "), duboisR::interpret_county_vod_disparity(
        charts_data()$county_vod_disparity, min_n = VOD_MIN_N
      ))
    })
  })
}
