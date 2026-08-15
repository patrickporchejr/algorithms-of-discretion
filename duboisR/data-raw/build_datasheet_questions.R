#!/usr/bin/env Rscript
# Builds R/sysdata.rda (the internal `datasheet_questions` list) AND
# renders inst/templates/datasheet_template.{md,qmd} from that same list,
# so use_datasheet()'s static template and build_datasheet_wizard()'s
# interactive prompts never drift out of sync with each other.
#
# The base seven sections and their sub-questions follow Gebru et al. 2021,
# "Datasheets for Datasets" (Communications of the ACM), with three
# questions explicitly cross-referencing duboisR's own diagnostic
# functions (audit_composition(), check_proxies(), check_tendentious())
# per the source feedback document's integration proposal.
#
# Two more sections extend that base per Monroe-White & Lecy 2023's
# Du Boisian/Wells-Du Bois critique of Gebru et al.: "Positionality &
# Counter-Narrative" (whose categories does the dataset use, and what does
# it structurally prevent an analyst from seeing) and "Audit Results
# Appendix" (the actual computed Veil of Darkness / Threshold Test tables,
# not just a promise that audits were run). Additive to the original seven
# -- nothing renamed or removed -- so existing datasheet.json content and
# the Shiny "Data Transparency & Provenance" tab keep working unchanged for
# every section besides these two new ones.
#
# usethis::use_data(internal = TRUE) overwrites the *entire* sysdata.rda
# with only the objects named in its call -- it doesn't merge with what's
# already there. Load the existing internal objects (grounding_questions_list,
# from build_grounding_questions.R) first so this run doesn't silently
# delete them.
if (file.exists("R/sysdata.rda")) load("R/sysdata.rda")

datasheet_questions <- list(
  motivation = list(
    title = "Motivation",
    questions = c(
      purpose = "For what purpose was the dataset created?",
      funder = "Who funded the creation of the dataset?"
    )
  ),
  composition = list(
    title = "Composition",
    questions = c(
      instances = "What do the instances that comprise the dataset represent?",
      subpopulations = "Are there subpopulation identifiers (e.g. race, gender)? If so, describe them (see duboisR::audit_composition()).",
      sensitive_data = "Does the dataset contain data that might be considered sensitive?",
      missing_info = "Is any information missing from individual instances, and if so, why (see duboisR::audit_composition())?"
    )
  ),
  collection_process = list(
    title = "Collection Process",
    questions = c(
      acquisition = "How was the data associated with each instance acquired?",
      collectors_timeframe = "Who was involved in the data collection process, and over what timeframe?",
      ethical_review = "Were any ethical review processes conducted?"
    )
  ),
  positionality = list(
    title = "Positionality & Counter-Narrative",
    questions = c(
      researcher_positionality = "What is the analyst/research team's relationship to the communities and institutions this data represents, and how might that shape interpretation?",
      whose_categories = "Whose categories does this dataset use to describe people and stops (e.g. who defines 'search', 'contraband', race labels), and what alternative framings does that choice foreclose?",
      structural_silences = "What does this dataset structurally prevent an analyst from seeing (e.g. stops never initiated, an officer's discretion not to record an encounter, outcomes beyond citation/arrest/search)?",
      counter_narrative = "What counter-narrative or alternative causal story should a reader hold alongside any single disparity number this dataset produces?"
    )
  ),
  preprocessing = list(
    title = "Preprocessing/cleaning/labeling",
    questions = c(
      was_preprocessed = "Was any preprocessing/cleaning/labeling of the data done?",
      raw_data_saved = "Was the 'raw' data saved in addition to the preprocessed/cleaned/labeled data?",
      software_available = "Is the software used to preprocess/clean/label the data available?",
      identity_proxies = "Are there covariates that act as proxies for protected attributes (see duboisR::check_proxies())?"
    )
  ),
  uses = list(
    title = "Uses",
    questions = c(
      prior_uses = "Has the dataset been used for any tasks already?",
      composition_impact = "Is there anything about the composition of the dataset, or the way it was collected, that might impact future uses?",
      inappropriate_uses = "Are there tasks for which the dataset should not be used (see duboisR::check_tendentious())?"
    )
  ),
  audit_appendix = list(
    title = "Audit Results Appendix",
    questions = c(
      vod_summary = "Summarize the Veil of Darkness (stop-decision) audit results across counties: is there a systematic ratio shift after dark, and which counties are reliable enough to interpret individually (see duboisR::summarize_county_vod_disparity())?",
      search_disparity_summary = "Summarize the county-level search-rate (frequency) disparity by race: how large is the typical gap, and how consistent is it across counties (see duboisR::summarize_county_search_disparity())?",
      threshold_summary = "Summarize the Threshold Test (infra-marginality-corrected) results: where does the naive outcome-test gap agree or disagree with the corrected inferred-threshold gap, and how reliable is the corrected fit (see duboisR::fit_threshold_test(), duboisR::compare_outcome_threshold_test())?",
      reliability_and_synthesis = "Given the Veil of Darkness and Threshold Test results together, where in the stop-to-search pipeline does racial disparity concentrate in this data, and what caveats limit how far that conclusion can be pushed?"
    )
  ),
  distribution = list(
    title = "Distribution",
    questions = c(
      third_parties = "Will the dataset be distributed to third parties outside of the entity on behalf of which it was created?",
      distribution_mechanism = "How will the dataset be distributed?",
      licensing = "Is the dataset subject to any copyright, licensing, or export-control restrictions?"
    )
  ),
  maintenance = list(
    title = "Maintenance",
    questions = c(
      maintainer = "Who will be supporting/hosting/maintaining the dataset?",
      contact = "How can the owner/curator/manager of the dataset be contacted?",
      updates = "Will the dataset be updated? If so, how often, and by whom?",
      erratum = "Is there an erratum process for reporting errors in the dataset?"
    )
  )
)

if (exists("grounding_questions_list")) {
  usethis::use_data(datasheet_questions, grounding_questions_list, internal = TRUE, overwrite = TRUE)
} else {
  usethis::use_data(datasheet_questions, internal = TRUE, overwrite = TRUE)
}

render_datasheet_body <- function(questions) {
  sections <- vapply(questions, function(sec) {
    qs <- vapply(sec$questions, function(q) paste0("**", q, "**\n\n_Your answer here._\n"), character(1))
    paste0("## ", sec$title, "\n\n", paste(qs, collapse = "\n"))
  }, character(1))
  paste(sections, collapse = "\n\n")
}

body_md <- render_datasheet_body(datasheet_questions)

md_content <- paste0(
  "# Datasheet\n\n",
  "Generated by `duboisR::use_datasheet()`. This scaffolds the structure ",
  "only -- per Gebru et al. 2021, the reflection itself is deliberately ",
  "not automated. Fill in each section yourself; use `duboisR::audit_composition()`, ",
  "`duboisR::check_proxies()`, and `duboisR::check_tendentious()` to get the ",
  "precise statistics referenced below.\n\n",
  body_md, "\n"
)
writeLines(md_content, file.path("inst", "templates", "datasheet_template.md"))

qmd_content <- paste0(
  "---\ntitle: \"Datasheet\"\nformat: html\n---\n\n",
  "Generated by `duboisR::use_datasheet()`. This scaffolds the structure ",
  "only -- per Gebru et al. 2021, the reflection itself is deliberately ",
  "not automated. Fill in each section yourself; use `duboisR::audit_composition()`, ",
  "`duboisR::check_proxies()`, and `duboisR::check_tendentious()` to get the ",
  "precise statistics referenced below.\n\n",
  body_md, "\n"
)
writeLines(qmd_content, file.path("inst", "templates", "datasheet_template.qmd"))

cat("Wrote R/sysdata.rda and inst/templates/datasheet_template.{md,qmd}\n")
