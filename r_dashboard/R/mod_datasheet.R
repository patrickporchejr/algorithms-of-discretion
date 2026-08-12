# Shiny module: "Data Transparency & Provenance" tab.
#
# Renders every section of a datasheet.json (produced by
# duboisR::build_datasheet_wizard(), or seeded non-interactively via
# duboisR::seed_datasheet_answers() -- see
# duboisR/inst/scripts/seed_demo_datasheet.R for this project's own
# grounded first-pass content) against the full Datasheets-for-Datasets
# question schema (duboisR::datasheet_schema()) -- all seven sections, not
# just a couple of hand-picked fields -- so anyone using the regression
# model is confronted with the data's structural caveats in full.
#
# Three sections get a precomputed diagnostic attached right where the
# schema's own question text references it, so the qualitative claim and
# the number backing it sit next to each other instead of the claim being
# unfalsifiable prose: Composition gets the live subpopulation
# representation/missingness breakdown; Preprocessing gets the identity-
# proxy check (does "neutral" geography/socioeconomic data leak race?);
# Uses gets the tendentious-outcome classification (is search_conducted /
# contraband_found an objective measurement or administrative discretion?).
# All three are precomputed (see duboisR/inst/scripts/precompute_audit.R)
# rather than fitted live -- the identity-proxy check in particular is a
# random forest that takes ~18min on the full 5.6M-row dataset.
#
# Degrades gracefully -- no datasheet.json is a normal, expected state, not
# an error -- when none is found.

datasheet_module_ui <- function(id) {
  ns <- NS(id)
  tagList(uiOutput(ns("datasheet_panel")))
}

datasheet_module_server <- function(id, results_dir, data_path) {
  moduleServer(id, function(input, output, session) {
    datasheet <- reactive({
      duboisR::read_datasheet(file.path(dirname(data_path), "datasheet.json"))
    })

    read_cached <- function(name) {
      path <- file.path(results_dir, paste0(name, ".rds"))
      validate(need(file.exists(path), paste0("No cached result at ", path, " -- run `make results` first.")))
      readRDS(path)
    }

    render_section <- function(section_key, schema, ds, extra = NULL) {
      section <- schema[[section_key]]
      answers <- ds[[section_key]]
      if (is.null(answers)) answers <- list()

      question_blocks <- lapply(names(section$questions), function(q_key) {
        answer <- answers[[q_key]]
        if (is.null(answer) || !nzchar(answer)) answer <- "_not recorded_"
        tagList(p(strong(section$questions[[q_key]])), markdown(answer))
      })

      tagList(h3(section$title), question_blocks, extra)
    }

    output$datasheet_panel <- renderUI({
      ds <- datasheet()

      if (is.null(ds)) {
        return(tagList(
          p("No ", code("datasheet.json"), " found next to the processed dataset."),
          p(
            "Run ", code("duboisR::build_datasheet_wizard()"), " to fill one in interactively, or ",
            code("Rscript duboisR/inst/scripts/seed_demo_datasheet.R"), " for a grounded first-pass draft."
          )
        ))
      }

      schema <- duboisR::datasheet_schema()

      composition_block <- tagList(
        h4("Computed: Current Subpopulation Composition"),
        markdown(paste(format(read_cached("composition")), collapse = "\n"))
      )

      identity_proxies_block <- tagList(
        h4("Computed: Identity Proxy Check"),
        markdown(paste(format(read_cached("identity_proxies")), collapse = "\n"))
      )

      tendentious_checks <- read_cached("tendentious_checks")
      tendentious_block <- tagList(
        h4("Computed: Outcome Tendentiousness Classification"),
        lapply(tendentious_checks, function(check) markdown(paste(format(check), collapse = "\n")))
      )

      tagList(
        render_section("motivation", schema, ds),
        render_section("composition", schema, ds, extra = composition_block),
        render_section("collection_process", schema, ds),
        render_section("preprocessing", schema, ds, extra = identity_proxies_block),
        render_section("uses", schema, ds, extra = tendentious_block),
        render_section("distribution", schema, ds),
        render_section("maintenance", schema, ds)
      )
    })
  })
}
