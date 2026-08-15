# Shiny module: "LLM Grounding Test" tab.
#
# Renders results/grounding_experiment.rds (see
# duboisR::run_grounding_experiment() and
# duboisR/inst/scripts/run_grounding_experiment.R) -- the same flagship
# model, asked the same fixed boolean/multiple-choice/numeric question
# battery twice per trial: once "naive" (a compact description of the
# dataset only) and once "grounded" (the same description plus an explicit
# instruction to first read datasheet.json). Each answer is scored against
# a hand-authored expected answer, so this tab makes the "Data Transparency
# & Provenance" tab's value empirically visible instead of asserted.
#
# Results are precomputed with repeated trials (see
# duboisR::summarize_grounding_trials()), so this renders the majority-vote
# answer per question plus its accuracy/stability/confidence across trials
# -- not a raw single draw, which could just be sampling noise.
#
# Not part of `make results`/`make all` -- see run_grounding_experiment.R --
# so this degrades gracefully (no error) when the .rds doesn't exist yet,
# same convention as mod_datasheet.R's missing-datasheet.json state.

grounding_module_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("summary")),
    plotOutput(ns("accuracy_plot"), height = "380px"),
    uiOutput(ns("accuracy_note")),
    h5("Per-question comparison"),
    p(
      class = "text-muted",
      "One row per question. Each provider's cell reads naive ", HTML("&rarr;"), " grounded: ",
      HTML("&#10003;"), " correct, ", HTML("&#10007;"), " incorrect, ", HTML("&mdash;"),
      " no valid answer in any trial."
    ),
    tableOutput(ns("comparison_table"))
  )
}

grounding_module_server <- function(id, results_dir) {
  moduleServer(id, function(input, output, session) {
    result <- reactive({
      path <- file.path(results_dir, "grounding_experiment.rds")
      if (!file.exists(path)) return(NULL)
      readRDS(path)
    })

    summarized <- reactive({
      res <- result()
      req(res)
      duboisR::summarize_grounding_trials(res$results)
    })

    # One row per question (not per question/provider pair): each provider
    # gets its own column, so a question's text is read once instead of
    # once per provider. Cell = naive accuracy -> grounded accuracy, each
    # side a checkmark/cross/percentage rather than a full sentence.
    question_table <- reactive({
      cols <- c("provider", "question_id", "accuracy")
      naive <- summarized()[summarized()$condition == "naive", cols]
      grounded <- summarized()[summarized()$condition == "grounded", cols]
      merged <- merge(naive, grounded, by = c("provider", "question_id"), suffixes = c("_naive", "_grounded"))

      symbol <- function(accuracy) {
        # accuracy is NA when no trial produced a valid answer; otherwise a
        # fraction correct across trials (usually 0 or 1 at n_repeats = 1).
        ifelse(
          is.na(accuracy), "—",
          ifelse(
            accuracy >= 0.999, "✓",
            ifelse(accuracy <= 0.001, "✗", sprintf("%.0f%%", 100 * accuracy))
          )
        )
      }
      # Non-breaking spaces around the arrow -- otherwise a narrow provider
      # column wraps "X" onto its own line, splitting "✓ → ✓" mid-cell.
      merged$cell <- paste0(symbol(merged$accuracy_naive), " → ", symbol(merged$accuracy_grounded))

      wide <- stats::reshape(
        merged[c("question_id", "provider", "cell")],
        idvar = "question_id", timevar = "provider", direction = "wide"
      )
      names(wide) <- sub("^cell\\.", "", names(wide))
      provider_cols <- setdiff(names(wide), "question_id")
      # A provider that never returned a row at all for this question (not
      # even an invalid one) reshapes to a genuine NA, not "no valid answer"
      # -- reads the same either way, as an em dash rather than "NA" text.
      for (col in provider_cols) wide[[col]][is.na(wide[[col]])] <- "—"

      meta <- unique(summarized()[c("question_id", "prompt", "expected_answer", "rationale")])
      out <- merge(meta, wide, by = "question_id")
      out[order(out$question_id), ]
    })

    output$summary <- renderUI({
      res <- result()

      if (is.null(res)) {
        return(tagList(
          p("No ", code("results/grounding_experiment.rds"), " found."),
          p(
            "Set at least one of ", code("ANTHROPIC_API_KEY"), ", ", code("OPENAI_API_KEY"), ", ",
            code("GEMINI_API_KEY"), ", or ", code("XAI_API_KEY"), " in a repo-root ", code(".env"),
            " (see ", code(".env.example"), " / README), then run ", code("make grounding"),
            " to generate it -- this makes real, billed LLM API calls, so it isn't part of ",
            code("make results"), "."
          )
        ))
      }

      tagList(
        h3("LLM Grounding Test"),
        p(
          "The same flagship model is asked the same fixed battery of true/false and multiple-choice ",
          "questions about the dataset twice: once with only a compact description of the data ",
          "(\"naive\"), once with the same description plus an explicit instruction to first read ",
          code("datasheet.json"), " (\"grounded\"). Each answer is scored against a hand-authored ",
          "expected answer grounded in the dataset's own documented provenance and diagnostics -- see ",
          "the Data Transparency & Provenance tab for the datasheet itself."
        ),
        markdown(paste(format(res), collapse = "\n"))
      )
    })

    output$accuracy_plot <- renderPlot({
      duboisR::plot_grounding_accuracy(summarized())
    })

    output$accuracy_note <- renderUI({
      p(strong("What this data shows: "), duboisR::interpret_grounding_accuracy(summarized()))
    })

    output$comparison_table <- renderTable({
      qt <- question_table()
      providers <- setdiff(names(qt), c("question_id", "prompt", "expected_answer", "rationale"))
      out <- qt[c("prompt", "expected_answer", providers, "rationale")]
      names(out) <- c("Question", "Expected", .dubois_display_cap(providers), "Rationale")
      out
    })
  })
}

# tools::toTitleCase-lite -- provider names ("anthropic") as column headers
# read better capitalized ("Anthropic"), and this module has no dependency
# on duboisR's internal (non-exported) .dubois_cap().
.dubois_display_cap <- function(x) {
  paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x)))
}
