# Design Doc: Algorithms of Discretion / `duboisR`

This document is the technical companion to the [README](README.md). The
README tells you how to get the pipeline running and the dashboard open —
exact commands, exact file paths, exact environment variables. This
document assumes that worked and answers a different question: *how is
this actually built, and why does each piece exist in the shape it does.*

The center of gravity here is `duboisR`, an installable R package
(`duboisR/`) that is the actual diagnostic engine of the project. The
Python pipeline and the Shiny dashboard both exist to feed it data and
display its output — neither does statistics on its own. If you only read
one section, read §5.

---

## 1. System architecture at a glance

```
Stanford Open Policing (raw CSV, .zip)  ──┐
                                           ├─▶ 02_clean_stops.py ──▶ stops_clean.csv ──┐
Census ACS 5-Year API ──▶ 01_fetch_census.py ──▶ census_stratifiers.csv ──┴─▶ 03_merge_features.py
                                                                                    │
                                                                                    ▼
                                                                    data/processed/audit_ready_stops.csv
                                                                                    │
                                                              duboisR/inst/scripts/precompute_audit.R
                                                                    (calls into the duboisR package)
                                                                                    │
                                                                                    ▼
                                                                          results/*.rds (cached fits)
                                                                                    │
                                                                                    ▼
                                                                    r_dashboard/app.R (Shiny, reads .rds)
```

Three stages, one file-based contract between each: a CSV between Python
and the precompute step, a directory of `.rds` files between the precompute
step and the dashboard. There is no API, no message queue, no shared
process. `duboisR` sits in the middle as a library, not a service — both
the precompute script and the dashboard call it in-process
(`devtools::load_all("duboisR")` or `library(duboisR)`).

---

## 2. Language and package choices

**Python does ETL, nothing else.** `pandas` + `requests` for chunked CSV
processing and a REST call to the Census API. No statistical modeling
happens in `python/` — it's string cleaning, filtering, and one join. This
is a deliberate boundary, not an accident of who wrote what: nothing in the
ETL stage needs R's modeling tools, and nothing in the statistical stage
needs Python's data-wrangling ergonomics.

**R does statistics, packaged as a real library, not scripts.** `duboisR`
is a proper `DESCRIPTION`/`NAMESPACE`/roxygen2/testthat package — 30
exported functions, a full `testthat` suite (see §10 for the current test
count), `devtools::check()` clean (0 errors/warnings/notes). This matters
for a reason beyond code hygiene: a
diagnostic tool for auditing bias has to be independently verifiable. A
tested, documented, `?help`-able package is falsifiable in a way a pile of
analysis scripts in a notebook is not — every claim it makes about a
dataset traces to a function with a docstring, a return type, and a test
that pins its behavior against known inputs.

**Why `glm()` over a Python equivalent.** R's formula interface
(`search_conducted ~ subject_race + poverty_rate`) and Shiny's reactive
graph are the more direct tool for "let a researcher toggle covariates and
watch a regression refit." Rebuilding this in Python (Dash + statsmodels)
would mean giving up R's terser modeling syntax for no offsetting benefit —
nothing here needs Python's ML ecosystem; every model in this repo is a
GLM, a Beta-distribution MLE fit via `optim()`, or a random forest used
only as a diagnostic classifier, not a production predictor.

**Why Wald confidence intervals instead of `broom::tidy(conf.int = TRUE)`.**
This choice recurs across almost every fitting function in `duboisR`
(`fit_audit_glm()`, and everything built on it), so it's worth stating once
here rather than in every docstring. `broom::tidy()`'s default CI is
profile-likelihood, computed via `confint.glm()`, which iteratively refits
the model to trace the log-likelihood's profile per coefficient. That's the
statistically preferred method at textbook sample sizes, and it hangs at
millions of rows — refitting a GLM against 5.6M rows once per coefficient
is not viable interactively. The closed-form alternative,

```r
z <- stats::qnorm(1 - (1 - conf_level) / 2)
df$conf.low  <- df$estimate - z * df$std.error
df$conf.high <- df$estimate + z * df$std.error
```

is `O(1)` relative to the fit — no refitting, just arithmetic on
`summary(model)$coefficients` — and is asymptotically justified (MLE
normality) well before millions of rows. This is the actual reason a
Shiny checkbox toggle can refit and redraw in ~9 seconds instead of
minutes.

---

## 3. Data pipeline (`python/`)

Three scripts, run in order by `make all`, each a plain script — not a DAG
framework. Appropriate at this scale: three steps, no branching, no
scheduling need. See the README for exact invocation; this section covers
what each script decides and why.

**`01_fetch_census.py`** pulls three ACS 5-Year variables for Texas
counties (`B19013_001E` median income, `B17001_002E`/`B17001_001E`
poverty count/universe, `poverty_rate` derived as their ratio) and derives
a `county_join_key` by normalizing the Census `NAME` field
(`"Harris County, Texas"` → `"HARRIS"`).

**`02_clean_stops.py`** is the heaviest-lifting script, both
computationally and in schema decisions. The raw Stanford TX file is
~27.4M rows across 44 columns; `pandas.read_csv` reads it with
`chunksize=500_000` directly against the `.zip` (pandas decompresses
transparently) and `usecols=RAW_COLUMNS_NEEDED` to skip parsing the 35
columns nothing downstream touches — the C parser skips unrequested
columns during parsing, which is materially faster than reading everything
and dropping columns after. Filtering to `subject_race in
{white,black,hispanic}` and to 2015–2017 (out of the full 2006–2017 range)
gets the working set down to ~5.6M rows, the point at which an interactive
`glm()` refit stays under ~10 seconds. `county_join_key` is derived here
independently of `01_fetch_census.py` using the identical normalization
logic — a duplication, not a shared helper, flagged in §12.

Three schema facts, discovered against the actual file rather than assumed
up front, shape everything downstream: **no FIPS at the stop level** (only
free-text `county_name`, hence the name-based join), **no arrest outcome**
(`outcome` is only ever `"warning"`/`"citation"`, so `contraband_found`
serves as the dashboard's second target instead of an arrest indicator),
and **no `subject_age`** (Texas State Patrol doesn't report it, so the
"Individual Demographics" control layer is driver sex only). `_validate_columns`
runs a zero-row header read before the full chunked pass, so a schema
mismatch fails fast with a clear message instead of a `KeyError` partway
through a multi-minute read.

**`03_merge_features.py`** inner-joins `stops_clean.csv` to
`census_stratifiers.csv` on `county_join_key`. `how="inner"` silently drops
any stop whose normalized county name doesn't match a Texas county from
the Census pull — but not silently overall: the script computes the
unmatched set and prints a warning with the distinct names (capped at 10)
and a count, so a join-key mismatch shows up as an observable warning
rather than an unexplained row-count discrepancy.

---

## 4. The data contract: `audit_ready_stops.csv`

The one interface between the Python and R halves. Every `duboisR`
function that takes stop-level `data` assumes these column names exist —
there's no schema-validation layer; `abort_if_missing_cols()` (in
`utils.R`, called at the top of nearly every exported function) is the
closest thing to one, and it only catches a missing column, not a wrong
type.

| Column | Type | Origin | Notes |
|---|---|---|---|
| `subject_race` | string, releveled to `white` before modeling | Stanford | restricted to white/black/hispanic |
| `subject_sex` | string | Stanford | the entire "demographics" control layer |
| `search_conducted` | 0/1, `NA` for ~38% of real rows | Stanford | Stanford doesn't report this for every stop — see `subpop_disparities.R`'s NA handling below |
| `contraband_found` | 0/1, structurally `NA` off-search | Stanford | stand-in for arrest — no arrest field exists |
| `hour` | int 0–23, no minutes | derived from `date`+`time` | resolution ceiling for Veil of Darkness — see §5.5 |
| `date` | date | Stanford | consumed by Veil of Darkness |
| `violation`, `search_basis` | string | Stanford | carried through, not yet consumed by any model — forward-provisioned for a pretextual-stop or consent-search analysis that isn't scoped |
| `poverty_rate`, `median_income` | float | Census | socioeconomic controls |
| `county_fips` | string | Census | join target for Veil of Darkness centroids; reference-only elsewhere |

`county_join_key` deliberately does not survive into this file — it's an
internal pipeline join mechanism, not something any statistical function
should ever reference.

---

## 5. `duboisR`: the diagnostic engine

Everything in this section lives under `duboisR/R/`. The package
implements what its own vignette (`vignette("wells-du-bois-protocol",
package = "duboisR")`) calls the **Wells-Du Bois Protocol** — named for
W.E.B. Du Bois (statistical data visualization as a tool against an
institution's official narrative) and Ida B. Wells (`The Red Record`,
1895 — using an institution's own reporting against its official
narrative). The protocol's working premise, stated plainly: administrative
data produced by an institution is not a transparent window onto the world
that institution polices. It is a record of that institution's decisions.
Every function below exists to make some part of that gap visible and
measurable rather than left implicit.

### 5.0 Shared statistical core (`glm_utils.R`)

Three functions everything else builds on:

- `dubois_relevel(data, col, ref)` — `glm()`'s default factor encoding
  picks the reference level alphabetically, which for `subject_race` would
  silently make `"black"` the baseline and invert every reported disparity's
  framing. This makes the reference level an explicit, validated argument
  instead of an alphabetical accident.
- `build_formula(outcome, base_term, control_map, controls_selected)` — a
  small formula-string builder driven by a named list, so a Shiny
  checkbox group maps directly onto RHS terms without inline `paste()`
  logic scattered through the app.
- `fit_audit_glm(data, formula, ...)` — `glm()` plus the closed-form Wald
  CI from §2, wrapped in a `duboisR_glm_fit` S3 object with `$model` (the
  raw fit) and `$summary` (a tibble: `term`, `estimate`, `std.error`,
  `statistic`, `p.value`, `conf.low`, `conf.high`, exponentiated to odds
  ratios by default). Every other function that needs a fitted model —
  `veil_of_darkness_test()`, the dashboard's regression tab —
  calls this instead of `glm()` directly.

A fourth function, `predicted_probabilities()`, complements the
reference-relative odds ratios in `$summary` with an absolute view: for
every level of a grouping variable (e.g. every race), the model's predicted
probability of the outcome, holding every other predictor at a reference
value. It scores via `predict(newdata = ...)` against freshly constructed
rows rather than reusing `model.frame(fit$model)`, specifically so formula
terms computed from a raw column (`factor(hour)` on an integer `hour`) get
re-derived correctly. One subtlety worth knowing if you extend this: a
predictor referenced through `factor(...)` always uses its *mode*, not its
mean, even though the underlying column is numeric — `mean(hour) == 11.7`
isn't a level `factor(hour)` was ever fit on, and `predict()` errors ("has
new levels") if asked to score one.

### 5.1 Datasheets for Datasets (`datasheet.R`, `datasheet_wizard.R`)

Implements Gebru et al. 2021's "Datasheets for Datasets" — a standardized
seven-section questionnaire (Motivation, Composition, Collection Process,
Preprocessing, Uses, Distribution, Maintenance) that documents a dataset's
provenance and limitations before anyone downstream builds on it.

`use_datasheet()` scaffolds a static template into the researcher's
project; `build_datasheet_wizard()` is an interactive CLI walkthrough of
the identical question structure that writes to a resumable, incremental
`datasheet.json`. Both are generated from one internal
`datasheet_questions` list (`data-raw/build_datasheet_questions.R`), so the
template and the wizard cannot drift apart. Neither automates the
qualitative reflection — this is a design decision inherited directly from
the source paper, which explicitly warns that automating the reflection
defeats its purpose. What `duboisR` *does* automate is producing the
precise statistics some of the questions require (§5.2–5.4), so the
researcher is filling in judgment, not arithmetic.

```r
devtools::load_all("duboisR")
build_datasheet_wizard(output = "data/processed/datasheet.json")
# -> walks all 7 sections, resumable, crash-safe (saves after every section)
```

`seed_datasheet_answers()` is the non-interactive counterpart — used to
seed a first-pass draft or script an update to one section — with the same
never-silently-overwrite discipline as the wizard's `resume = TRUE`: an
already-answered question is left untouched unless
`overwrite_existing = TRUE`. `read_datasheet()` is a thin, defensive
`jsonlite::read_json()` wrapper that returns `NULL` (not an error) when no
datasheet exists yet, so both the Shiny tab and `run_grounding_experiment()`
can degrade gracefully instead of crashing on missing state.

### 5.2 Composition & missingness auditing (`audit_composition.R`)

`audit_composition(data, group_col, missing_col)` computes exactly the
numbers the datasheet's Composition section needs: representation counts
and percentages per subgroup (intersectional if `group_col` has length >
1), and — if `missing_col` is given — subgroup-specific missingness rates.
The function deliberately stops at computing and formatting; it doesn't
narrate whether a missingness pattern is concerning. That's the
researcher's judgment call, the same division of labor as §5.1.

### 5.3 Identity Proxy diagnostic (`proxy_diagnostics.R`)

The core insight this function operationalizes: *excluding a protected
attribute from a model does not remove the information it carries if that
information is encoded in other columns.* Zip code, county, even vehicle
age can proxy for race well enough that a "race-blind" model reproduces
race-correlated outcomes anyway. `check_proxies()` tests this directly by
temporarily inverting the modeling problem — predicting the protected
attribute *from* the "neutral" covariates:

```r
check_proxies(
  data, protected_attr = "subject_race",
  predictors = c("county_fips", "poverty_rate", "median_income", "hour"),
  method = "rf"   # ranger::ranger() if installed, else a one-vs-rest glm() fallback
)
```

It reports classification accuracy against a stratified held-out split,
compares that to the no-information baseline (majority-class accuracy),
and calls the gap the `lift`. A `lift` above `warn_threshold` (default
0.10) flags the covariate set as identity proxies, and reports which
individual covariates drove that (variable importance for the random
forest path; the largest `|z|` coefficient per covariate across the
one-vs-rest logistic fits for the `glm` fallback). Run against the real
dataset (`precompute_audit.R`), `county_fips + poverty_rate + median_income
+ hour` alone predicts `subject_race` at ~68% accuracy against a ~47%
baseline — geography and time of day are meaningfully proxying for race in
this data, which is exactly the finding a naive "we didn't include race in
the model" argument would miss. Worth noting: the `glm` fallback routinely
produces a (quasi-)separated fit warning — that's the diagnostic *working*
(a covariate perfectly predicting a race level is the strongest possible
proxy signal), so the warning is suppressed rather than left to alarm the
caller.

### 5.4 Tendentious-outcome diagnostic (`tendentious.R`)

A models-trained-on-human-decisions problem, stated as a forced
classification rather than a computation: `check_tendentious()` prompts
the researcher (interactively, or via an explicit `classification`
argument in non-interactive use) to categorize an outcome variable as
`"objective"`, `"subjective"`, or `"administrative"`. `search_conducted`
and `contraband_found` are both classified `"administrative"` in this
project's own precomputed artifacts — an officer's discretionary decision
to search is not an objective measurement of what a driver was carrying,
and a model trained on it will faithfully reproduce whatever bias was in
that discretion. `classification = NULL` with `interactive = FALSE` is a
hard error, not a silent default — this categorization is required to be
explicit, never assumed.

### 5.5 Veil of Darkness (`veil_of_darkness.R`)

The most literal implementation of the package's Du Boisian framing: a
natural experiment exploiting the fact that an officer's ability to
observe a driver's race is worse after dark (Grogger & Ridgeway 2006). If
a racial disparity in stops is driven by the officer visually profiling
race, that disparity should shrink once darkness removes the officer's
ability to act on race at all.

The design's key control is the **intertwilight restriction**: rather than
comparing all daylight stops to all dark stops (confounded by the fact
that *who's on the road* varies by clock time regardless of race), the
comparison is restricted to clock hours that are *sometimes* daylight and
*sometimes* dark across the data's date/county range.
`prepare_veil_of_darkness_data()` computes this via
`compute_daylight_status()` — see that function's own docstring for the
`match()`-vs-`merge()` and `ISOdatetime()`-vs-string-parsing performance
numbers (the difference between this pass finishing in ~2 minutes and not
finishing at all at 5.6M rows) and for the hour-only timestamp resolution
caveat it attaches to every result.

`fit_veil_of_darkness(prepared, outcome_var, interaction)` is the cheap,
outcome-dependent second stage — split out from the expensive daylight
classification specifically so a caller refitting against multiple
outcomes (a Shiny dropdown) pays that ~2-minute cost once and reuses it.
The one thing worth stating here rather than leaving entirely to the
docstring: `interaction = TRUE` (`race:is_dark`) is the actual
Grogger-Ridgeway test — a ratio below 1 on that term means the race
disparity shrinks after dark. `interaction = FALSE` fits race and `is_dark`
as separate additive effects and structurally cannot show that. See
`?fit_veil_of_darkness` for the full mechanism and the caveats it attaches
to its own output based on which mode was used.

### 5.6 Threshold Test (`threshold_test.R`)

Addresses a different failure mode than Veil of Darkness: **infra-marginality**.
Even a "fair" search policy (a single risk threshold applied uniformly)
will show different hit rates across races if the underlying distribution
of risk within each race differs — a higher search rate for one group
doesn't by itself prove a lower bar was applied to that group, if that
group's marginal searched driver was still, on average, more likely to be
carrying contraband. The Threshold Test (Simoiu, Corbett-Davies & Goel
2017) exists to distinguish "different threshold" from "different risk
distribution" as explanations for an observed search/hit-rate pattern.

The full published method is a hierarchical Bayesian model fit via MCMC.
`duboisR` implements a **fast, non-hierarchical, non-MCMC approximation**
instead — a Stan/MCMC dependency and its validation would be a multi-week
undertaking disproportionate to what this project needs from it (a point
estimate to compare against the other diagnostics, not a
publication-grade Bayesian result). See `?fit_threshold_test` for the
closed-form derivation that makes it fast: only two numbers per race,
`(a_r, b_r)`, are actually fit via `stats::optim()`, and each county's
search threshold falls out of that in closed form from its own observed
search rate rather than being fit as a free parameter. It's described
there, deliberately, as "in the spirit of," not "identical to," the cited
literature — no partial pooling across sparse counties, no credible
intervals, point estimates only — and validated by
`test-threshold_test.R`'s parameter-recovery test against data simulated
from a known `Beta(a, b)`.

One real numerical edge case, surfaced running this against the actual
5.6M-row Texas data, is worth naming here since it spans three files: the
fitted `(a, b)` for the "white" race come back extremely large (~1.9×10⁸,
~2×10⁸ — a near-point-mass risk distribution), which drives
`predicted_hit_rate` to `NaN` across the observed range.
`plot.duboisR_threshold_fit()` clamps its viewport to the observed data's
range for exactly this reason (the fitted curve's theoretical domain is
`[0, 1]`, real per-county search rates never exceed ~13%), and
`mod_threshold_test.R` surfaces the `NaN` case as an explicit UI flag
rather than silently rendering a blank curve.

### 5.7 Subpopulation disparities (`subpop_disparities.R`)

Disaggregates a fitted model's error rates — TPR, FPR, PPV — per
intersectional subgroup (e.g. `black_female`, formed by pasting
`subgroup_cols` together), rather than reporting one pooled accuracy
number that can hide starkly different error rates by group. The function
states the mathematical impossibility result directly in its output
(Chouldechova 2017; Kleinberg, Mullainathan & Raghavan 2016): when base
rates differ across groups, a calibrated classifier (equal PPV) generally
cannot also equalize FPR and FNR simultaneously. This isn't a limitation
of the fit — it's a structural fact about any classifier, so the function
reports the trade-off rather than implying it could be tuned away.

Two real bugs, found wiring this against the actual dataset rather than
synthetic fixtures, are worth knowing about because they're the kind of
thing that silently corrupts results without erroring:

- `search_conducted` is `NA` (not `FALSE`) for ~38% of real rows. `glm()`
  drops `NA` rows automatically when *fitting* (`na.action = na.omit`),
  but this function scores against caller-supplied `data` independently of
  the model's training frame — an unfiltered `NA` there poisons every
  group's confusion-matrix `sum()` (default `na.rm = FALSE`). Fixed by
  dropping `NA`-outcome rows before scoring, with the drop count recorded
  in the result's `"notes"` attribute.
- The default `threshold = 0.5` is degenerate for an outcome this
  imbalanced — predicted probabilities for `search_conducted` top out
  around 3%, so every row predicts negative and TPR/PPV come back `NaN`
  (0/0) regardless of the NA fix above. The dashboard doesn't hardcode
  `0.5`; `mod_subpop_disparities.R` defaults its threshold slider to the
  outcome's own observed base rate and lets the researcher move off it.

### 5.8 LLM datasheet-grounding experiment (`grounding_experiment.R`, `llm_clients.R`)

The newest and most unusual piece of the package: rather than *asserting*
that a datasheet makes a dataset's provenance legible, this measures it —
against an LLM as a concrete downstream consumer. `run_grounding_experiment()`
asks the same flagship model the same fixed battery of boolean/enum/numeric
questions about the dataset twice: once **naive** (a compact, pseudonymized
description of the schema plus a small random sample — see
`build_data_context()`), once **grounded** (the identical description plus
the full `datasheet.json` and an instruction to consult it first). Each
answer is scored against a hand-authored `expected_answer`.

```r
run_grounding_experiment(
  data_path = "data/processed/audit_ready_stops.csv",
  datasheet_path = "data/processed/datasheet.json",
  providers = c("anthropic", "openai"),
  models = list(anthropic = "claude-opus-5", openai = "gpt-5.1"),
  n_repeats = 2
)
```

Two design choices keep this from being a one-off demo, each documented in
full at its own function rather than repeated here: the raw sample is
pseudonymized before either condition ever sees it (`build_data_context()`)
specifically so the *naive* condition can't take a shortcut that has
nothing to do with grounding (e.g. recognizing a real Texas FIPS prefix on
sight); and every provider call is forced through a JSON-Schema-constrained
tool call rather than parsed free text (`grounding_response_schema()`,
`gemini_response_schema()` for Gemini's OpenAPI-subset dialect), with
confidence nested per-answer so the report can tell "grounding changed the
answer" apart from "grounding changed how sure the model was."

`n_repeats > 1` runs independent trials per (provider, condition); see
`summarize_grounding_trials()` for why that matters (providers aren't
called at temperature 0, so a single trial's "changed answer" could be
sampling noise). `call_anthropic()`, `call_openai()`, `call_gemini()`, and
`call_grok()` are the four provider clients — `call_openai()` and
`call_grok()` share one implementation (`call_openai_compatible()`) since
xAI's API is explicitly OpenAI-compatible.

This is opt-in (`make grounding`, not part of `make all`/`make results`) —
it makes real, billed API calls — but it's the piece of this package that
turns "datasheets improve data legibility" from an assertion the Datasheets
for Datasets paper makes into a number this project's own dataset actually
produced.

### 5.9 Synthetic data (`simulate_stops.R`)

`simulate_stops(n, seed, counties)` generates data matching the real
`audit_ready_stops.csv` contract exactly — same columns, same types, no
extra fields. It's the single generator behind both the package's own
`tests/testthat/` fixtures and `r_dashboard/dev/generate_synthetic_data.R`
(a thin wrapper around it), which matters structurally: one implementation
means the dashboard's dev-mode data and the package's test fixtures cannot
drift apart, unlike the pipeline's original standalone synthetic generator
this replaced (see §12). A synthetic race effect is baked into
`search_conducted` purely so plots have a visible, non-null signal to
render when checking that a chart looks right — it is manufactured, not a
finding, and the docstring says so explicitly.

---

## 6. Using `duboisR` directly

The dashboard is one consumer of this package, not the only reasonable
one. Everything below runs from an R console with the package loaded —
either `library(duboisR)` after `devtools::install("duboisR")`, or
`devtools::load_all("duboisR")` from the repo root for dev-mode use without
an install step.

```r
devtools::load_all("duboisR")

stops <- readr::read_csv("data/processed/audit_ready_stops.csv")
stops <- dubois_relevel(stops, "subject_race", ref = "white")

# 1. Fit and inspect a regression directly
fit <- fit_audit_glm(stops, search_conducted ~ subject_race + poverty_rate)
print(fit)                                   # md_table of term/OR/CI/p
plot(predicted_probabilities(fit, stops, "subject_race"))

# 2. Check whether "neutral" geography/socioeconomic covariates proxy for race
check_proxies(stops, predictors = c("county_fips", "poverty_rate", "median_income"))

# 3. Classify an outcome variable's epistemic status
check_tendentious("search_conducted", classification = "administrative", interactive = FALSE)

# 4. Run the Veil of Darkness natural experiment
vod <- veil_of_darkness_test(stops, outcome_var = "search_conducted", interaction = TRUE)
print(vod); plot(vod)

# 5. Threshold Test for infra-marginality
suff_stats <- aggregate_sufficient_statistics(stops)
tt <- fit_threshold_test(suff_stats)
plot(tt)

# 6. Disaggregate error rates across intersectional subgroups
subpopulation_disparities(fit, stops, actual_col = "search_conducted",
                           subgroup_cols = c("subject_race", "subject_sex"))

# 7. Scaffold and fill in a datasheet
use_datasheet("datasheet.md")                # static template
build_datasheet_wizard("datasheet.json")     # interactive, resumable
```

Every function above is documented via `?function_name` and covered by
`tests/testthat/`; nothing here is dashboard-specific plumbing.

---

## 7. Precompute & caching (`inst/scripts/precompute_audit.R`)

The dataset is a frozen, one-time pull — nothing about it changes between
sessions — so the dashboard renders precomputed fits rather than fitting
live per user. `precompute_audit.R` (run by `make results`) calls straight
into the `duboisR` functions from §5 and writes one `.rds` per artifact:
two baseline regressions, Veil of Darkness's expensive prepared/classified
data plus per-outcome fits, the Threshold Test, dataset composition, the
identity-proxy check, and the tendentious-outcome classifications.

Two decisions in that script are worth knowing if you're extending it:

- **`strip_model()` before serializing.** A `glm` fit object embeds a full
  copy of its training data (model frame, fitted values, residuals,
  weights) — at 5.6M rows, several length-`nrow(data)` vectors balloon each
  cached fit to tens of MB even though nothing downstream reads `$model`
  after fitting (only `$summary`). Every cache write drops `$model` first,
  keeping the S3 class and print/plot methods intact.
- **Sampling for the identity-proxy check.** `check_proxies(method = "rf")`
  on the full 5.6M rows takes ~18 minutes for a result within 0.1 accuracy
  points of a 300k-row sample (67.9% vs. 68.0% accuracy, 20.8 vs. 20.9-point
  lift) — not worth paying in every `make results` run for that difference,
  so the precomputed artifact uses a fixed-seed 300k-row sample instead.

`app.R`'s `audit_fit()` reactive reads the cached no-controls artifact
instantly when no sidebar checkboxes are selected, and falls back to a live
`fit_audit_glm()` call (~9s) the moment any control is toggled — precomputing
all 16 possible control combinations wasn't worth it against a live refit
that's already fast enough to feel interactive. The Veil of Darkness tab
follows the same pattern one level cheaper: any control selected still
reuses the cached, already-daylight-classified `veil_prepared.rds` (skipping
the ~2-minute classification pass) and only refits the cheap outcome-dependent
half live.

---

## 8. Shiny dashboard architecture (`r_dashboard/`)

Built on `shiny` + `bslib` (Bootstrap 5, `litera` theme) using
`page_sidebar()`. The sidebar exposes two reactive inputs — target outcome,
and which control layers to include — shared across every tab via a
`navset_card_tab` with six panels: Regression Model, Veil of Darkness,
Threshold Test, Subpopulation Disparities, Data Transparency & Provenance,
and LLM Grounding Test. Each is its own Shiny module
(`R/mod_*.R`, `*_module_ui()`/`*_module_server()` with `NS(id)` namespacing)
— not because the app instantiates any of them twice today, but because it
gives each tab a clean seam for isolated testing and no global ID
collisions if it ever needs to.

`stops_data()` and `audit_fit()` both live in `app.R`'s `server()`, not
inside any one module — they moved up specifically because Subpopulation
Disparities needs to score the exact fitted model the Regression tab shows,
and Data Transparency needs the same loaded dataset the Regression tab
does. Lifting shared reactives up rather than duplicating them per module
is the load-bearing reason the tabs stay consistent with each other.

**The one genuinely nasty bug class in the Shiny layer** is a headless
rendering hang, not a data bug: macOS defaults `ggplot2`'s bitmap device to
`"quartz"`, which needs an active window-server session. Launched via
`Rscript` outside a foreground GUI session (SSH, CI, a background process),
quartz doesn't error — it hangs indefinitely, so `renderPlot()` never
resolves and a forest plot area just stays blank forever with no error
message anywhere. The fix is one line, guarded at the very top of `app.R`
before any Shiny code runs:

```r
if (capabilities("cairo")) options(bitmapType = "cairo")
```

This is exactly the kind of failure that's silent and painful to debug
from symptoms alone (a blank plot, no stack trace, no log line), which is
why it's called out explicitly in a comment at the top of the file rather
than left to be rediscovered.

---

## 9. What's unique about `duboisR`

Answering directly, since it's a reasonable thing to ask before deciding
whether to actually run this: most "fairness toolkits" ship a battery of
generic metric functions (disparate impact ratio, equalized odds gap,
calibration error) that you point at any classifier and any protected
attribute — domain-agnostic by design. `duboisR` is the opposite bet: it's
built around one specific, deeply understood domain (administrative
traffic-stop data) and encodes domain-specific quasi-experimental methods
that a generic toolkit has no way to offer, because they don't generalize
to arbitrary tabular data:

- **Veil of Darkness** is not a metric you compute from a confusion matrix
  — it's a natural experiment specific to data with a timestamp and a
  location, exploiting a real physical fact (officers can't see as well in
  the dark) as an identification strategy.
- **The Threshold Test** targets infra-marginality specifically, a failure
  mode invisible to outcome-rate comparisons alone — two groups can have
  identical search *thresholds* and still show different hit rates purely
  because their risk distributions differ, and a plain disparity number
  can't tell those apart.
- **The Identity Proxy check** and **Tendentious-outcome diagnostic** are
  aimed at the two most common ways a bias audit fools itself: variables
  that launder a protected attribute through "neutral" geography, and
  outcome variables that are themselves administrative discretion dressed
  up as ground truth.
- **The LLM grounding experiment** is, as far as this project's authors are
  aware, a genuinely novel empirical test of the Datasheets for Datasets
  thesis — instead of asserting that provenance documentation matters, it
  measures whether a concrete downstream consumer's answers about a
  dataset actually change when that documentation is present.

None of these functions outputs a verdict — "this dataset is biased" is
never a return value anywhere in this package. They output the specific
numbers a researcher needs to reach that judgment themselves, and the
package is explicit, in its own docs, about the trade-offs (impossibility
results, resolution limits, approximation error) that make "a single clean
answer" the wrong thing to expect from any one of them.

---

## 10. Testing

`duboisR/tests/testthat/` — 100 `test_that()` blocks across every exported
function, run against `simulate_stops()`-derived fixtures
(`helper-fixtures.R`), independent of the real multi-GB dataset ever being
present on disk. Two tests are worth calling out specifically because they
validate something a plain "does it run without erroring" test wouldn't:
the Threshold Test's parameter-recovery test (fits against data simulated
from a *known* `Beta(a, b)` and asserts the recovered parameters are close
to the truth — testing the method, not just the code path), and the Veil
of Darkness suite's hand-verified daylight/dark/twilight classifications
against known sunset times. `devtools::check()` passes clean.

The Python side has no test suite — correctness there rests on
`_validate_columns`'s header check and the unmatched-county-name warning,
both runtime and data-dependent rather than an independent test harness.
This asymmetry is real and unresolved; see §12.

---

## 11. Environment & toolchain

- **Python:** a local `.venv` (3.11), `pandas`/`requests`/`pyarrow`/`python-dotenv`
  pinned only by name in `requirements.txt`. `pyarrow` is declared but not
  yet imported anywhere — reserved, most likely for a future faster CSV
  parse or Parquet intermediate, not currently exercised.
- **R (`duboisR/`):** a real `DESCRIPTION`-managed dependency set — no
  `renv` lockfile yet, but `Imports`/`Suggests` are explicit (`rlang`,
  `ggplot2`, `readr`, `tibble`, `cli`, `jsonlite`, `suncalc`, `httr2`;
  `Suggests`: `testthat`, `ranger`, `withr`, `devtools`, `knitr`,
  `rmarkdown`). Building the vignette needs `pandoc` as a system binary.
- **R (dashboard):** `shiny`, `bslib`, `tidyverse`, `broom`, `devtools`,
  installed globally per the README. `broom` is listed but no longer
  actually used for CI computation (see §2) — it may still be a
  transitive convenience import, or a leftover from before that decision.
- **Secrets:** `CENSUS_API_KEY` (required, pipeline) plus optional
  `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`/`GEMINI_API_KEY`/`XAI_API_KEY`
  (grounding experiment only), all in a gitignored root `.env`.
- **Data is never committed.** `data/raw/*` and `data/processed/*` are
  gitignored; reproducing the dataset means re-running the pipeline.

---

## 12. Known rough edges

Worth naming explicitly — a design doc that only describes the happy path
is misleading.

1. **Join-key normalization is duplicated**, not shared, between
   `01_fetch_census.py` and `02_clean_stops.py`. If the normalization rule
   ever needs to change, it has to change in two places in sync, with
   nothing enforcing that.
2. **The CSV data contract (§4) is enforced by nothing except code review
   and `abort_if_missing_cols()`'s existence check.** No schema-validation
   step catches a column rename or dtype change between the Python output
   and the R input before it hits `glm()`-fit time (or worse, a dtype
   coercion that happens to silently succeed).
3. **Single-state, single-outcome-pair scope.** The README frames this as
   multi-state; only Texas is wired end-to-end. `duboisR` itself is
   state-agnostic except one piece: `dubois_tx_centroids()` bundles a
   Texas-only county centroid table, and nothing in the dashboard exposes
   swapping the `centroids` argument `compute_daylight_status()` already
   accepts for exactly this — a second state needs its own centroid table
   plumbed through by hand.
4. **Python has no automated test suite**, unlike the R side's 88 tests
   (§10) — correctness rests on runtime, data-dependent checks rather than
   an independent harness.
5. **The Threshold Test's numerical edge case for a near-point-mass risk
   distribution** (§5.6 — `predicted_hit_rate` comes back `NaN` when a
   race's fitted `(a, b)` are extremely large) is surfaced in the UI, not
   fixed. Fixing it means touching the fitting methodology itself
   (regularization, reparameterization, non-uniform sampling of the sweep
   variable), out of scope for the pass that found it.
6. **No `renv` lockfile** for either R project — dependencies are
   version-unpinned beyond what's declared in `DESCRIPTION`'s `Imports`,
   so a fresh install can in principle resolve different transitive
   versions than what this was built and tested against.
