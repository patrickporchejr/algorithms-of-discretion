#!/usr/bin/env Rscript
# Builds R/sysdata.rda's `grounding_questions_list` -- the fixed question
# battery used by run_grounding_experiment() to compare a flagship LLM's
# answers about this dataset with vs. without access to data/processed/
# datasheet.json. Companion to build_datasheet_questions.R, same
# single-source-of-truth pattern (edit here, never hand-edit sysdata.rda).
#
# Every question's `expected_answer` and `rationale` cite a real, computed
# fact -- from duboisR/inst/scripts/seed_demo_datasheet.R (the project's own
# datasheet.json content) or duboisR/inst/scripts/precompute_audit.R (the
# diagnostics that content is grounded in) -- not an invented "gotcha".
# Each is chosen because a model given only a generic description of "a
# traffic-stop dataset" is likely to default to a wrong assumption (all 50
# states, outcomes as objective fact, controls that cleanly isolate race
# from class) that the datasheet directly corrects.
#
# Three question types: "boolean" (TRUE/FALSE), "enum" (a `choices` named
# vector, `expected_answer` one of its names), and "numeric" (a free
# quantity, `expected_answer` a string-encoded number, scored within
# `tolerance` rather than exact match -- see score_answer() in
# grounding_experiment.R).
#
# usethis::use_data(internal = TRUE) overwrites the *entire* sysdata.rda
# with only the objects named in its call -- it doesn't merge with what's
# already there. Load the existing internal objects (datasheet_questions,
# from build_datasheet_questions.R) first so this run doesn't silently
# delete them.
load("R/sysdata.rda")

grounding_questions_list <- list(
  all_50_states = list(
    type = "boolean",
    prompt = "This dataset contains traffic-stop records from all 50 U.S. states.",
    expected_answer = "FALSE",
    rationale = "Texas DPS (state troopers) only -- one state's records, standardized by the Stanford Open Policing Project."
  ),
  full_release_years = list(
    type = "boolean",
    prompt = "This dataset covers the full 2006-2017 span released by the Stanford Open Policing Project for Texas.",
    expected_answer = "FALSE",
    rationale = "Restricted to 2015-2017 (3 of the 12 released years), a performance decision to keep glm() refits interactive at ~5.6M rows."
  ),
  search_conducted_objective = list(
    type = "boolean",
    prompt = "search_conducted is an objective measurement of criminal activity, not an officer's discretionary decision.",
    expected_answer = "FALSE",
    rationale = "check_tendentious() classifies search_conducted as administrative: it reflects an officer's discretionary decision to search, not an objective fact about the driver."
  ),
  contraband_found_objective = list(
    type = "boolean",
    prompt = "contraband_found is an unbiased ground-truth measurement of who was carrying contraband.",
    expected_answer = "FALSE",
    rationale = "It inherits search_conducted's selection bias (only defined when a search happened) on top of whatever the search itself finds -- also classified administrative."
  ),
  contraband_found_mostly_recorded = list(
    type = "boolean",
    prompt = "contraband_found is recorded (non-missing) for the large majority of stops in this dataset.",
    expected_answer = "FALSE",
    rationale = "Structurally NA for ~98-99% of rows: it is only defined when search_conducted == TRUE, and searches are rare (~1.6% base rate)."
  ),
  controls_isolate_race_from_class = list(
    type = "boolean",
    prompt = "County-level poverty rate and median income, used as statistical controls in this dataset, cleanly separate race from class.",
    expected_answer = "FALSE",
    rationale = "check_proxies() predicts subject_race from these county covariates at 67.8% accuracy vs. a 47.1% no-information baseline -- they are themselves substantially race-correlated (consistent with historical redlining), so 'controlling for poverty' does not cleanly isolate race from class here."
  ),
  race_categories_limited = list(
    type = "boolean",
    prompt = "Every subject_race category present in the original Stanford release is included in this dataset.",
    expected_answer = "FALSE",
    rationale = "Restricted to white/black/hispanic (~5.6M of ~27.4M raw rows); other race categories were dropped for insufficient sample size, not binned into 'other'."
  ),
  appropriate_for_individual_risk_score = list(
    type = "boolean",
    prompt = "This dataset, on its own, is appropriate for building an individualized risk score to flag a specific driver for a search.",
    expected_answer = "FALSE",
    rationale = "The datasheet's Uses section explicitly rules this out: it is an aggregate statistical audit of disparity patterns, not a risk-scoring or officer-evaluation tool, and its outcome variables reflect discretion rather than ground truth."
  ),
  data_source = list(
    type = "enum",
    prompt = "What is the primary source of this dataset's traffic-stop records?",
    choices = c(
      stanford_tx_dps = "Texas DPS records standardized by the Stanford Open Policing Project",
      nypd = "NYPD stop-and-frisk database",
      survey = "A self-reported driver survey",
      synthetic = "Synthetic/simulated data generated for this project"
    ),
    expected_answer = "stanford_tx_dps",
    rationale = "Administrative records from Texas DPS troopers, standardized and released by the Stanford Open Policing Project (stacks.stanford.edu, druid:yg821jf8611)."
  ),
  strongest_proxy_pair = list(
    type = "enum",
    prompt = "Which pair of covariates was found to be the strongest proxy for driver race in this dataset?",
    choices = c(
      age_vehicle = "Driver age and vehicle model",
      poverty_income = "County poverty rate and median income",
      weather_season = "Weather and time of year",
      badge_shift = "Officer badge number and shift"
    ),
    expected_answer = "poverty_income",
    rationale = "check_proxies() found county poverty_rate and median_income led the +20.8-point lift in race-predictability over baseline."
  ),
  outcome_characterization = list(
    type = "enum",
    prompt = "What is the best characterization of search_conducted and contraband_found as outcome variables in this dataset?",
    choices = c(
      objective = "Objective ground truth about criminal activity",
      administrative = "Administrative outcomes shaped by officer discretion, not objective measurements",
      random = "Randomly assigned experimental labels",
      self_reported = "Self-reported by the drivers themselves"
    ),
    expected_answer = "administrative",
    rationale = "Both are classified 'administrative' via check_tendentious(): they reflect officer discretion, compounded (for contraband_found) with what a search happens to find."
  ),
  years_covered = list(
    type = "enum",
    prompt = "What years of stops does this dataset actually cover?",
    choices = c(
      full_range = "2006-2017, the full Stanford release",
      restricted = "2015-2017 only",
      recent = "2020-2023",
      unrestricted = "All years, unrestricted"
    ),
    expected_answer = "restricted",
    rationale = "Restricted to 2015-2017 of Stanford's 2006-2017 release, to keep model refits interactive at ~5.6M rows."
  ),
  race_categories = list(
    type = "enum",
    prompt = "Which subject_race categories are present in this dataset?",
    choices = c(
      wbh_only = "White, Black, and Hispanic only",
      all_categories = "All race categories from the Stanford release",
      wb_only = "White and Black only",
      not_recorded = "subject_race is not recorded in this dataset"
    ),
    expected_answer = "wbh_only",
    rationale = "Other race categories were dropped for insufficient sample size to support stable disparity estimates, not binned into an 'other' catch-all."
  ),
  proxy_accuracy_lift = list(
    type = "enum",
    # Deliberately narrow-band choices: the general claim "poverty/income
    # correlate with race" is guessable from common domain knowledge, but
    # the specific empirical magnitude of the lift this project's own
    # check_proxies() run found is not -- it's an artifact of this exact
    # random-forest fit on this exact sample, not a fact about the world.
    prompt = "By how many percentage points does a random-forest model using only county poverty rate, median income, and hour beat a no-information baseline at predicting driver race in this dataset?",
    choices = c(
      under_5 = "Under 5 points",
      five_to_15 = "5-15 points",
      fifteen_to_25 = "15-25 points",
      over_25 = "Over 25 points"
    ),
    expected_answer = "fifteen_to_25",
    rationale = "check_proxies(): 67.8% accuracy vs. a 47.1% no-information baseline -- a 20.8-point lift, in the 15-25 point band."
  ),
  year_restriction_reason = list(
    type = "enum",
    # Also a curatorial fact specific to this project's own pipeline, not
    # a property of the Stanford release or of Texas DPS data generally --
    # unguessable without the datasheet, and the "boring" true answer
    # (iteration speed) is not the choice a naive guess would gravitate to.
    prompt = "Why does this project's audit-ready dataset cover only 3 years of stops rather than the full span Stanford released for this state?",
    choices = c(
      data_quality = "Data quality problems in the excluded years",
      performance = "A performance/compute decision, to keep model refits interactive at ~5.6M rows",
      legal = "A legal or licensing restriction from the data provider",
      availability = "Those are the only years the provider actually released"
    ),
    expected_answer = "performance",
    rationale = "Explicitly a performance decision (interactive glm() refits at ~5.6M rows), not a methodological or data-quality one -- stated directly in the datasheet's Composition section."
  ),
  proxy_causal_mechanism = list(
    type = "enum",
    # Goes one level past "the correlation exists" (proxy_accuracy_lift) to
    # *why* -- a causal attribution that's in the datasheet's prose, not
    # derivable from the number alone.
    prompt = "What documented historical mechanism explains why county poverty rate and median income correlate so strongly with driver race in this dataset?",
    choices = c(
      coincidence = "An unexplained statistical coincidence with no known cause",
      redlining = "Historical residential segregation/redlining patterns",
      measurement_error = "Measurement error in the Census covariates",
      manipulation = "Deliberate manipulation of the covariates by the research team"
    ),
    expected_answer = "redlining",
    rationale = "Datasheet's Composition section attributes the correlation to patterns 'consistent with historical redlining/residential segregation,' not an unexplained artifact."
  ),
  search_conducted_missingness_pct = list(
    type = "numeric",
    unit = "as a percentage, e.g. answer 42 for 42%",
    tolerance = 10,
    # A free numeric guess, not multiple choice -- nothing to narrow down by
    # elimination. Distinct from contraband_found's ~98-99% missingness
    # (already a boolean question above): search_conducted's own gap is a
    # smaller, separately-documented figure.
    prompt = "Roughly what percentage of stops in this dataset have search_conducted itself missing (not contraband_found -- search_conducted)?",
    expected_answer = "33",
    rationale = "Datasheet's Composition section: 'search_conducted itself is NA for roughly a third of rows -- Stanford's own reporting gap.'"
  ),
  funder = list(
    type = "enum",
    prompt = "Who funded this research project?",
    choices = c(
      no_external = "No external funder -- independent research",
      federal_grant = "A federal research grant (e.g. NIH, NSF)",
      corporate = "A corporate sponsor",
      university_grant = "A university research grant"
    ),
    expected_answer = "no_external",
    rationale = "Datasheet's Motivation section: 'No external funder. Independent research project by Patrick Eugene Porche Jr.'"
  ),
  ethical_review_conducted = list(
    type = "boolean",
    prompt = "A formal IRB or other ethical review process was conducted before this project used this data.",
    expected_answer = "FALSE",
    rationale = "Datasheet's Collection Process section: 'None conducted by this project... no IRB review was sought or is understood to be required' for secondary analysis of already-public administrative records."
  ),
  raw_data_discarded = list(
    type = "boolean",
    prompt = "The original raw data files were discarded after preprocessing; only the merged/cleaned dataset was kept.",
    expected_answer = "FALSE",
    rationale = "Datasheet's Preprocessing section: the original Stanford .zip and Census API response are both kept in data/raw/, separate from the merged data/processed/audit_ready_stops.csv."
  ),
  code_has_explicit_license = list(
    type = "boolean",
    prompt = "This project's own code currently carries an explicit software license file.",
    expected_answer = "FALSE",
    rationale = "Datasheet's Distribution section: 'This project's own code does not yet carry an explicit license file -- add one before any public redistribution beyond the demo.'"
  ),
  dataset_actively_distributed = list(
    type = "boolean",
    prompt = "This project's derived/merged dataset is actively distributed to third parties.",
    expected_answer = "FALSE",
    rationale = "Datasheet's Distribution section: the derived dataset 'is not distributed; it's regenerated locally from the two public sources via `make all`.'"
  ),
  update_policy = list(
    type = "enum",
    prompt = "How does this project handle updates to the dataset going forward?",
    choices = c(
      scheduled = "Updated on a regular published schedule",
      frozen = "A frozen, point-in-time snapshot with no update schedule",
      live_feed = "A continuously live/real-time data feed",
      vendor_pushed = "Updates are pushed automatically by the original data provider"
    ),
    expected_answer = "frozen",
    rationale = "Datasheet's Maintenance section: 'No update schedule -- this is a frozen, point-in-time dataset (2015-2017) for a specific research project, not a live feed.'"
  )
)

usethis::use_data(datasheet_questions, grounding_questions_list, internal = TRUE, overwrite = TRUE)
cat("Wrote R/sysdata.rda (grounding_questions_list added alongside datasheet_questions)\n")
