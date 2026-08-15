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
# The battery is organized into five buckets, following the source design
# document's protocol: (A) descriptive/provenance, (B) naive aggregate
# statistics, (C) Veil of Darkness naive-misuse traps, (D) Threshold
# Test/infra-marginality traps, (E) limitations/ethics/appropriate use. The
# original ~21 questions below (kept as first authored, untagged) sit mostly
# in buckets A and E; every question added afterward is bucket-tagged in a
# section comment. Every bucket-B/C/D fact below was pulled live from
# results/threshold_test.rds and results/vod_charts.rds (see
# duboisR/inst/scripts/precompute_audit.R) rather than approximated, the
# same standard the original questions hold themselves to -- re-verify
# against a fresh `make results` run before reusing these numbers if the
# underlying pipeline or frozen dataset ever changes.
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
    expected_answer = "TRUE",
    rationale = "MIT-licensed: a root LICENSE file, and duboisR/DESCRIPTION declares 'License: MIT + file LICENSE' with its own duboisR/LICENSE."
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
  ),

  # --- Bucket B: Naive Aggregate Statistics ---------------------------------
  # A raw sample of ~20 rows cannot support an exact statewide/county
  # aggregate -- these test whether a model hedges or fabricates a
  # plausible-sounding number when it can't derive one from the visible
  # sample alone. Figures below are the full (unrestricted, all 254
  # counties) statewide search-rate aggregate from
  # duboisR::summarize_county_search_rates(), cached in
  # results/threshold_test.rds$county_search_rates.
  overall_search_rate_pct = list(
    type = "numeric",
    unit = "as a percentage, e.g. answer 5 for 5%",
    tolerance = 1,
    prompt = "What is the overall statewide search rate (share of stops resulting in a search) across all stops in this dataset?",
    expected_answer = "1.59",
    rationale = "summarize_county_search_rates() aggregated statewide: 24,993/2,450,260 stops (unrestricted, all 254 counties) = 1.59%."
  ),
  black_white_search_rate_ratio = list(
    type = "numeric",
    unit = "as a ratio, e.g. answer 2 for 2x",
    tolerance = 0.5,
    prompt = "Statewide, what is the ratio of the Black driver search rate to the White driver search rate?",
    expected_answer = "2.17",
    rationale = "Statewide (unrestricted): Black 2.72% vs. White 1.25% search rate = 2.17x."
  ),
  search_disparity_uniform_across_counties = list(
    type = "boolean",
    prompt = "The racial gap in search rate is roughly the same size in every Texas county in this dataset.",
    expected_answer = "FALSE",
    rationale = "summarize_county_search_disparity(): the typical county searches Black drivers at 2.53x the White rate, but the top counties by disparity_ratio range far higher (Hopkins County 6.42x, Montague 4.49x, Hill 4.32x) -- not a uniform gap."
  ),
  every_county_reliable_for_disparity_estimate = list(
    type = "boolean",
    prompt = "Every Texas county in this dataset has enough recorded stops to support a statistically reliable racial search-rate disparity estimate.",
    expected_answer = "FALSE",
    rationale = "8 of 254 counties have fewer than 500 total stops in county_search_rates; several (e.g. Loving, Borden, Edwards, Kent Counties) show single-digit or zero searches for a race -- not enough to estimate a rate at all."
  ),
  highest_disparity_county = list(
    type = "enum",
    prompt = "Which of these Texas counties shows the largest raw Black-vs-White search-rate disparity ratio in this dataset (restricted to counties with at least 30 searches for each race)?",
    choices = c(
      hopkins = "Hopkins County",
      harris = "Harris County (Houston)",
      dallas = "Dallas County",
      travis = "Travis County (Austin)"
    ),
    expected_answer = "hopkins",
    rationale = "summarize_county_search_disparity(): Hopkins County (FIPS 48223) has the largest disparity_ratio (6.42x) among counties with n_searches >= 30 for both races -- a smaller county a naive guess (defaulting to a well-known metro) would not surface."
  ),
  arrest_outcome_recorded = list(
    type = "boolean",
    prompt = "This dataset records whether a stop resulted in an arrest.",
    expected_answer = "FALSE",
    rationale = "Datasheet's Composition section: neither subject_age nor an arrest outcome exists in the Texas State Patrol file at all -- not missing data, just never collected or reported by this agency."
  ),
  black_white_hit_rate_comparison = list(
    type = "enum",
    prompt = "Statewide, is the search 'hit rate' (contraband found among searched drivers) higher, lower, or about the same for Black drivers compared to White drivers in this dataset?",
    choices = c(
      higher = "Notably higher for Black drivers",
      lower = "Notably lower for Black drivers",
      about_the_same = "About the same for both"
    ),
    expected_answer = "about_the_same",
    rationale = "compare_outcome_threshold_test(): Black drivers' hit_rate_gap vs. White is +0.4 percentage points -- about the same, despite Black drivers being searched at over 2x the rate."
  ),

  # --- Bucket C: Veil of Darkness naive-misuse traps ------------------------
  vod_ratio_definition = list(
    type = "enum",
    prompt = "In this project's Veil of Darkness analysis, what does a county's vod_ratio above 1.0 for Black drivers mean?",
    choices = c(
      share_shift = "Black drivers' share of intertwilight-window stops is higher after dark than in daylight",
      more_stops = "More total stops happen in that county after dark than in daylight",
      more_searches = "Black drivers are searched more often at night in that county",
      more_officers = "More officers are on shift in that county at night"
    ),
    expected_answer = "share_shift",
    rationale = "summarize_county_vod_disparity(): vod_ratio is pct_black_dark_TRUE / pct_black_dark_FALSE -- a share-composition ratio, not a raw count or a search-decision statistic."
  ),
  raw_dark_light_counts_valid_vod_test = list(
    type = "boolean",
    prompt = "Comparing raw counts of stops made in the dark vs. in daylight, without restricting to the intertwilight window, is a statistically valid way to test for a Veil of Darkness effect in this dataset.",
    expected_answer = "FALSE",
    rationale = "prepare_veil_of_darkness_data() deliberately restricts to intertwilight clock hours (sometimes daylight, sometimes dark across the date/county range) specifically because unrestricted dark-vs-light counts confound with seasonal daylight variation and patrol-shift scheduling."
  ),
  vod_near_one_means_no_bias_anywhere = list(
    type = "boolean",
    prompt = "A Veil of Darkness ratio near 1.0 for most high-volume counties means there is no racial disparity anywhere in the traffic-stop-to-search process in this dataset.",
    expected_answer = "FALSE",
    rationale = "The VoD design only speaks to the stop decision. This project's own results show it near parity (median county vod_ratio 1.04 across 250 counties with n >= 30) while the search decision shows a large, separately-documented disparity (median 2.53x for Black drivers) -- disparity that VoD alone would miss entirely."
  ),
  vod_intertwilight_confound = list(
    type = "enum",
    prompt = "Besides officer racial bias, what confound is the Veil of Darkness design's intertwilight-window restriction specifically built to control for?",
    choices = c(
      commuting = "Commuting/patrol patterns varying by clock time regardless of race",
      weather = "Weather conditions varying by season",
      inspections = "Vehicle inspection schedules",
      court = "Court docket backlogs"
    ),
    expected_answer = "commuting",
    rationale = "prepare_veil_of_darkness_data()'s documentation: restricting to intertwilight hours controls for 'the confound that commuting patterns (and thus who is on the road) vary by clock time regardless of race.'"
  ),
  two_counties_vod_causal_overreach = list(
    type = "boolean",
    prompt = "If County A has a higher Veil of Darkness ratio than County B, that alone is enough to conclude County A's officers are more racially biased than County B's.",
    expected_answer = "FALSE",
    rationale = "interpret_county_vod_disparity()'s own caveats: county-level ratios are a natural-experiment estimate with real noise (vod_ratio ranges from 0 to over 2.2 across counties near the reliability floor), not a validated officer-level bias score -- a plot.duboisR_vod_result-style causal claim from two point estimates is unsupported."
  ),
  vod_tests_search_decision = list(
    type = "boolean",
    prompt = "This project's Veil of Darkness analysis, as actually computed and shown on the dashboard, provides direct evidence about whether search decisions (not just who gets stopped) are racially biased.",
    expected_answer = "FALSE",
    rationale = "precompute_audit.R: the search-decision race:is_dark interaction GLM was tried and removed from the dashboard ('didn't meaningfully change the picture'); the cached/shown VoD charts (summarize_county_vod_disparity(), summarize_statewide_vod()) are the stop decision only."
  ),
  vod_search_disparity_synthesis = list(
    type = "enum",
    prompt = "This project's Veil of Darkness ratios cluster close to 1.0 for most high-volume counties (median 1.04 across 250 counties with n >= 30), while county-level search-rate disparities are large (median 2.53x for Black drivers). What does that combination suggest about where in the process racial disparity concentrates in this dataset?",
    choices = c(
      search_decision = "In the search decision (who gets searched once already stopped), not in who gets stopped in the first place",
      stop_decision = "In the stop decision (who gets pulled over), not the search decision",
      both_equally = "Equally in both the stop and the search decision",
      cannot_tell = "This data cannot distinguish between the two decision points at all"
    ),
    expected_answer = "search_decision",
    rationale = "The project's own headline finding, only derivable by reading both cached results together: VoD near parity + large, separately-documented search-rate disparity = the disparity concentrates downstream of the stop, in the search decision."
  ),

  # --- Bucket D: Threshold Test / infra-marginality traps -------------------
  search_rate_gap_alone_proves_intent = list(
    type = "boolean",
    prompt = "If Black drivers are searched at a higher rate than White drivers in a county, that alone establishes discriminatory intent.",
    expected_answer = "FALSE",
    rationale = "The Threshold Test exists precisely because a raw search-rate gap conflates disparate treatment with infra-marginality -- a higher search rate alone, without the corrected threshold estimate, doesn't establish intent."
  ),
  lower_hit_rate_meaning = list(
    type = "enum",
    prompt = "In this dataset, statewide, searched Hispanic drivers are found with contraband at a notably lower rate than searched White drivers (a hit-rate gap of about -15 percentage points). Under outcome-test logic, what does a lower hit rate for a searched group most directly suggest?",
    choices = c(
      lower_bar = "That group is being searched on a lower standard of evidence (searched even when less likely to be carrying contraband)",
      fewer_crimes = "That group commits fewer crimes overall",
      equipment = "Search equipment is less effective for that group",
      no_meaning = "Hit rate has no interpretive value on its own"
    ),
    expected_answer = "lower_bar",
    rationale = "compute_outcome_test()/compare_outcome_threshold_test(): Hispanic drivers' hit_rate_gap is -15.1 points vs. White -- the classic outcome-test reading is a lower evidentiary bar for triggering a search."
  ),
  naive_and_corrected_always_agree_this_fit = list(
    type = "boolean",
    prompt = "In this project's own fitted Threshold Test, the infra-marginality-corrected search-threshold gap points in the same direction as the naive hit-rate gap for both Black and Hispanic drivers.",
    expected_answer = "TRUE",
    rationale = "compare_outcome_threshold_test()$agrees_in_direction is TRUE for both races in the current fit -- though the datasheet also flags that this fit's (a, b) risk distributions are near-degenerate for every race (interpret_threshold_fit()), so even an agreeing direction should be read as suggestive, not precise."
  ),
  threshold_test_reliability_safeguard = list(
    type = "enum",
    prompt = "What does this project's Threshold Test pipeline do to guard against unreliable per-county threshold estimates?",
    choices = c(
      both_safeguards = "Flags any race-county cell with fewer than 5 searches as low_confidence, and restricts the fit itself to the 100 largest counties (>=1,000 total stops) to avoid near-degenerate fits",
      nothing = "Nothing -- every county's threshold is treated as equally reliable",
      big_counties_only = "Excludes any county with fewer than 100,000 stops",
      power_analysis = "Requires a formal statistical power analysis before including a county"
    ),
    expected_answer = "both_safeguards",
    rationale = "fit_threshold_test()'s min_searches = 5 low_confidence flag, plus precompute_audit.R's restrict_to_top_counties(min_stops = 1000, top_n = 100) applied specifically because fitting every county produces near-degenerate risk distributions in sparser counties."
  ),
  valid_to_rank_all_counties_by_bias = list(
    type = "boolean",
    prompt = "It is statistically valid to rank every one of the 254 Texas counties in this dataset by inferred racial bias using the Threshold Test.",
    expected_answer = "FALSE",
    rationale = "Only 100 of 254 counties were even included in the cached fit (restricted to >=1,000 stops), and the fitted risk distributions are near-degenerate for all three races in the current results -- interpret_threshold_fit() itself flags every race's threshold as suggestive, not precise, in this fit."
  ),
  stop_vs_search_rigor = list(
    type = "enum",
    prompt = "Which decision point in the stop-to-search pipeline does this dataset let you test with a natural-experiment design, versus only a descriptive/correctable-but-currently-unstable comparison?",
    choices = c(
      vod_rigorous = "Veil of Darkness rigorously tests the stop decision; the search decision only has a naive rate comparison plus a Threshold Test correction that is currently near-degenerate",
      search_rigorous = "The search decision has a rigorous natural-experiment design; the stop decision does not",
      both_rigorous = "Both decision points have equally rigorous natural-experiment designs",
      neither_rigorous = "Neither decision point can be tested rigorously with this dataset"
    ),
    expected_answer = "vod_rigorous",
    rationale = "Veil of Darkness (intertwilight restriction) is a natural-experiment design for the stop decision; the search decision only has aggregate_sufficient_statistics()'s naive rate plus fit_threshold_test()'s correction, and that correction's own race_params are near-degenerate in the cached fit."
  ),
  cesa_flag_county_disqualifier = list(
    type = "enum",
    prompt = "In a county-flagging tool built on this dataset, which of these should most heavily disqualify a county from being flagged #1 for a deeper civil-rights audit based on its raw numbers alone?",
    choices = c(
      low_n = "The county's total stop count is well below the ~500-1,000 stop reliability floor this project's own diagnostics use elsewhere",
      below_avg_rate = "The county has a below-average search rate",
      rural = "The county is rural rather than a major metro",
      high_income = "The county's median household income is above the state average"
    ),
    expected_answer = "low_n",
    rationale = "This project's own reliability floors (8 of 254 counties under 500 total stops; restrict_to_top_counties() min_stops = 1000 for the Threshold Test fit) treat low n as the disqualifying factor -- not the raw disparity number itself, which is exactly what a naive top-of-the-list pick would chase."
  ),
  infra_marginality_definition = list(
    type = "enum",
    prompt = "What is infra-marginality bias, in the sense the Threshold Test is designed to correct for?",
    choices = c(
      margin_bias = "The bias that arises because search decisions are made against each officer's own belief about a driver, not a uniformly applied risk cutoff -- so a raw hit-rate or search-rate comparison across groups isn't a clean apples-to-apples test",
      sampling_error = "Random sampling error from too few observations",
      missing_data = "Bias introduced by missing/NA outcome values",
      multicollinearity = "Correlation between predictor variables in a regression"
    ),
    expected_answer = "margin_bias",
    rationale = "fit_threshold_test()'s documentation: models each driver's latent risk as a Beta distribution and infers a group-specific threshold, precisely because groups searched at different points along their own risk distribution aren't comparable via a raw rate or hit-rate gap alone (Simoiu, Corbett-Davies & Goel 2017)."
  ),

  # --- Bucket E: Limitations, Ethics & Appropriate Use (additional) --------
  determines_officer_intent = list(
    type = "boolean",
    prompt = "This dataset lets you determine an individual officer's intent in any specific stop.",
    expected_answer = "FALSE",
    rationale = "This is an aggregate statistical audit of disparity patterns (datasheet's Uses section); it has no officer-identifying field and cannot speak to any individual's intent."
  ),
  sufficient_for_title_vi_alone = list(
    type = "boolean",
    prompt = "This dataset alone, without any other evidence, is sufficient to support a disparate-treatment claim under Title VI.",
    expected_answer = "FALSE",
    rationale = "An aggregate statistical audit of administrative outcomes (themselves classified 'administrative,' not objective, by check_tendentious()) is not, on its own, a legal sufficiency determination -- the datasheet's Uses section rules out individualized/legal conclusions from this data alone."
  ),
  entirely_missing_population = list(
    type = "enum",
    prompt = "What population is entirely missing from this dataset?",
    choices = c(
      no_stop = "Any encounter that did not result in a recorded stop at all (e.g. an officer's discretion not to initiate a stop)",
      out_of_state = "Stops involving out-of-state drivers",
      nighttime = "All nighttime stops",
      multi_occupant = "Stops with more than one vehicle occupant"
    ),
    expected_answer = "no_stop",
    rationale = "Datasheet's Positionality section (structural_silences): the dataset has no record of encounters that never became a recorded stop -- an officer's discretion not to stop someone is invisible to this data by construction."
  ),
  cross_county_comparison_needs_controls = list(
    type = "boolean",
    prompt = "It is appropriate to compare raw stop/search rates across counties without controlling for underlying population demographics or local crime rates.",
    expected_answer = "FALSE",
    rationale = "check_proxies() found county-level socioeconomic covariates (poverty_rate, median_income) are themselves substantially race-correlated (67.8% vs. 47.1% baseline) -- an uncontrolled cross-county rate comparison conflates race with these confounds rather than isolating it."
  ),
  simpsons_paradox_risk_at_state_level = list(
    type = "boolean",
    prompt = "Aggregating this data to the statewide level instead of analyzing county-by-county could hide or reverse a pattern that is real at the county level.",
    expected_answer = "TRUE",
    rationale = "This is exactly why this project's own diagnostics (summarize_county_search_disparity(), summarize_county_vod_disparity()) are computed per county rather than only statewide -- a Simpson's-paradox-style risk is a real, documented reason for that design choice."
  ),
  low_n_counties_should_be_silently_dropped = list(
    type = "boolean",
    prompt = "Counties with too few recorded stops to support a reliable estimate should be silently dropped from a summary ranking rather than explicitly flagged.",
    expected_answer = "FALSE",
    rationale = "This project's own convention (fit_threshold_test()'s low_confidence column, aggregate_sufficient_statistics()'s min_n filter) is to explicitly flag unreliable cells, never silently drop them without saying so."
  ),
  single_statistic_sufficient_for_automated_flagging = list(
    type = "boolean",
    prompt = "If a downstream system used a single statistic from this dataset (e.g. one county's raw search-rate ratio) to automatically allocate civil-rights audit resources, that statistic alone would be a reliable and sufficient basis for that decision.",
    expected_answer = "FALSE",
    rationale = "The datasheet's Uses section and Audit Results Appendix both exist because a single raw statistic (search-rate ratio, VoD ratio, or naive hit-rate gap) can each independently mislead -- reliable use requires reading them together with each diagnostic's own reliability caveats, not any one number in isolation."
  )
)

usethis::use_data(datasheet_questions, grounding_questions_list, internal = TRUE, overwrite = TRUE)
cat("Wrote R/sysdata.rda (grounding_questions_list added alongside datasheet_questions)\n")
