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
    h5("Per-question comparison"),
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

    comparison <- reactive({
      res <- result()
      req(res)
      summarized <- duboisR::summarize_grounding_trials(res$results)

      cols <- c("provider", "question_id", "modal_answer", "accuracy", "agreement", "mean_confidence")
      naive <- summarized[summarized$condition == "naive", cols]
      grounded <- summarized[summarized$condition == "grounded", cols]
      merged <- merge(naive, grounded, by = c("provider", "question_id"), suffixes = c("_naive", "_grounded"))

      meta <- unique(summarized[c("question_id", "type", "prompt", "expected_answer", "rationale")])
      out <- merge(meta, merged, by = "question_id")
      # modal_answer is NA when a question was never validly answered in any
      # trial -- "changed" is undefined there, not FALSE, so call it out by
      # name instead of letting `==` against NA surface as a bare "NA" cell.
      out$changed <- ifelse(
        is.na(out$modal_answer_naive) | is.na(out$modal_answer_grounded), "unanswered",
        ifelse(out$modal_answer_naive == out$modal_answer_grounded, "", "changed")
      )
      out[order(out$provider, out$question_id), ]
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

    output$comparison_table <- renderTable({
      cmp <- comparison()
      fmt_cell <- function(answer, accuracy, agreement, confidence) {
        # answer/agreement are NA when no trial produced a valid answer --
        # say so plainly instead of rendering a bare "NA (0% correct, NA%
        # stable, conf NaN)" cell.
        ifelse(
          is.na(answer), "(no valid answer in any trial)",
          sprintf("%s (%.0f%% correct, %.0f%% stable, conf %.0f)", answer, 100 * accuracy, 100 * agreement, confidence)
        )
      }
      data.frame(
        Provider = cmp$provider,
        Question = cmp$prompt,
        Naive = fmt_cell(cmp$modal_answer_naive, cmp$accuracy_naive, cmp$agreement_naive, cmp$mean_confidence_naive),
        Grounded = fmt_cell(cmp$modal_answer_grounded, cmp$accuracy_grounded, cmp$agreement_grounded, cmp$mean_confidence_grounded),
        Changed = cmp$changed,
        Rationale = cmp$rationale,
        check.names = FALSE
      )
    })
  })
}
