# Shiny module: "Data Transparency & Provenance" tab.
#
# Looks for a datasheet.json (produced by duboisR::build_datasheet_wizard())
# next to the processed dataset and renders its motivation/limitations
# alongside a live duboisR::audit_composition() breakdown, so anyone using
# the regression model is confronted with the data's structural caveats.
# Degrades gracefully -- no datasheet.json is a normal, expected state, not
# an error -- when none is found.

datasheet_module_ui <- function(id) {
  ns <- NS(id)
  tagList(uiOutput(ns("datasheet_panel")))
}

datasheet_module_server <- function(id, stops_data, data_path) {
  moduleServer(id, function(input, output, session) {
    datasheet <- reactive({
      duboisR::read_datasheet(file.path(dirname(data_path), "datasheet.json"))
    })

    output$datasheet_panel <- renderUI({
      ds <- datasheet()

      if (is.null(ds)) {
        return(tagList(
          p("No ", code("datasheet.json"), " found next to the processed dataset."),
          p("Run ", code("duboisR::build_datasheet_wizard()"), " to generate one.")
        ))
      }

      motivation <- ds$motivation$purpose
      if (is.null(motivation) || !nzchar(motivation)) motivation <- "_not recorded_"

      uses <- ds$uses$inappropriate_uses
      if (is.null(uses) || !nzchar(uses)) uses <- "_not recorded_"

      comp <- duboisR::audit_composition(stops_data(), group_col = "subject_race", missing_col = "contraband_found")

      tagList(
        h4("Motivation"),
        markdown(motivation),
        h4("Uses This Dataset Should Not Be Put To"),
        markdown(uses),
        h4("Current Subpopulation Composition (computed live)"),
        markdown(paste(format(comp), collapse = "\n"))
      )
    })
  })
}
