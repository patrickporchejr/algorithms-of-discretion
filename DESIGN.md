# Design Doc: Algorithms of Discretion

This document is a technical deep dive into how this repository is built —
the architecture, the modules, and *why* specific decisions were made. It
complements the [README](README.md), which covers the project's
methodological framing and setup instructions. This doc assumes you've read
the README and want to understand the machinery underneath.

**Scope note:** the README describes the eventual product (a `duboisR`
diagnostic package, a Veil of Darkness natural-experiment module, a
multi-state Quarto white paper). As of this writing, the *implemented*
system covers a three-stage Python ETL pipeline feeding a single-state
(Texas) dataset into an R Shiny dashboard, plus a real, tested, installable
`duboisR` R package (`duboisR/`) implementing the Wells-Du Bois Protocol's
diagnostics — datasheet scaffolding, composition/proxy/tendentious-outcome
auditing, a Veil of Darkness test, a fast Threshold Test approximation, and
subpopulation disparity disaggregation. Still narrower than the full vision:
single-state, no multi-state Quarto white paper yet, and the VoD/Threshold
Test functions exist and are tested but aren't yet exposed as interactive
Shiny control layers (see §5). This doc describes what's actually built,
and flags where it diverges from or sets up for the broader vision.

---

## 1. Why a polyglot architecture

The repo is split into a Python half and an R half on purpose, not by
accident of who wrote what:

- **Python does ETL.** `pandas` + `requests` are the pragmatic choice for
  chunked CSV processing and calling a REST API (Census). Nothing here needs
  a statistical language — it's string cleaning, filtering, and joins.
- **R does statistics and the UI.** `glm()`'s formula interface, `broom`-style
  tidy output, and Shiny's reactive graph make R the more direct tool for
  "let a researcher toggle covariates and watch a regression refit
  live." Rebuilding a reactive logistic-regression UI in Python (e.g. Dash)
  would mean giving up R's terser statistical modeling syntax for no benefit.

The two halves communicate through **one file on disk**:
`data/processed/audit_ready_stops.csv`. There is no API, no shared process,
no serialization format smarter than CSV. This is a deliberate low-tech
boundary — the R side has no dependency on how the Python side is
implemented, only on a column contract (see §4). The tradeoff is that nothing
enforces that contract except human discipline and the `validate(need(...))`
guard in `mod_regression.R` (see §6).

```
Stanford Open Policing (raw CSV, .zip)  ──┐
                                           ├─▶ 02_clean_stops.py ──▶ stops_clean.csv ──┐
Census ACS 5-Year API             ──▶ 01_fetch_census.py ──▶ census_stratifiers.csv ──┴─▶ 03_merge_features.py ──▶ audit_ready_stops.csv ──▶ Shiny app (app.R)
```

---

## 2. Data pipeline (`python/`)

Three scripts, run in order, each reading the previous stage's output. They
are plain scripts (not a DAG framework, not Airflow/Prefect) — appropriate
at this scale: three steps, run manually, no scheduling or retries needed.

### 2.1 `01_fetch_census.py` — pull county covariates

Hits the ACS 5-Year API (`api.census.gov/data/2022/acs/acs5`) for Texas
(state FIPS `48`), requesting three variables:

| Census variable | Meaning |
|---|---|
| `B19013_001E` | Median household income |
| `B17001_002E` | Population below poverty line |
| `B17001_001E` | Poverty universe (denominator) |

`poverty_rate` is derived (`poverty_count / poverty_universe`) rather than
pulled as a pre-computed ACS variable, since ACS most often exposes counts,
not precomputed rates, at this table.

**Key decision — the join key.** The Census API returns `county_fips`
naturally (state+county FIPS concatenation), but the Stanford stop data (see
§2.2) only has a free-text `county_name` field, not FIPS. Rather than trying
to resolve stop-level records to FIPS (which would need a separate
name→FIPS crosswalk), this script instead normalizes *its own* county name
into the same shape the stop data will produce: strip `" County"`, uppercase,
trim (`"Harris County, Texas"` → `"HARRIS"`). Both sides of the eventual join
in `03_merge_features.py` are derived the same way, so they're guaranteed to
agree on formatting. `county_fips` is still carried through the pipeline
end-to-end, but only as a passenger for downstream reference (e.g. mapping) —
it is never used as a join key.

Requires a free `CENSUS_API_KEY`, loaded via `python-dotenv` from a
repo-root `.env` (gitignored).

### 2.2 `02_clean_stops.py` — standardize and filter the raw stop file

This is the heaviest-lifting script, both computationally and in terms of
schema-reality decisions.

**Chunked reads.** The raw Stanford "TX statewide" file is ~27.4M rows / 44
columns, distributed as a ~1GB zip (~7.2GB unzipped). `pandas.read_csv` is
called with `chunksize=500_000` directly against the `.zip` — pandas
transparently decompresses, so there's no separate unzip step. Each chunk is
independently filtered and concatenated at the end; nothing here needs
cross-chunk state.

**Column pruning at read time.** `usecols=RAW_COLUMNS_NEEDED` limits the read
to 9 of the 44 raw columns (race, sex, county, search/contraband flags,
violation, search basis, date, time). This is meaningfully faster than
reading everything and dropping columns afterward, since pandas' C parser
skips unrequested columns during parsing rather than materializing and
discarding them.

**Row filtering:**
- `subject_race` restricted to `white`, `black`, `hispanic` — these are the
  three groups with sufficient sample size for stable disparity estimates;
  other categories are dropped rather than binned into "other."
- Filtered to **2015–2017** out of the full 2006–2017 range. This is a
  performance decision, not a methodological one: at ~5.6M rows the
  dashboard's `glm()` refits in ~9 seconds when a control is toggled, which
  is the threshold for the UI still feeling interactive. At the full
  27.4M-row scale, an interactive Shiny `glm()` refit is not viable.

**Derived columns:**
- `hour` — extracted from a combined `date + time` timestamp parse, not from
  `time` alone, since `pd.to_datetime` needs the date component to parse
  reliably.
- `county_join_key` — same normalization logic as §2.1, applied independently
  here (there's no shared helper module between the two scripts — see §7 for
  why that's a known rough edge, not an oversight).

**Schema realities baked into the output** (discovered against the actual
raw file, not assumed up front):
- **No FIPS at the stop level** — only free-text `county_name`. This is why
  the whole pipeline joins on normalized name instead of FIPS (§2.1).
- **No arrest outcome.** `outcome` in the raw data is only ever `"warning"`
  or `"citation"` — there's no arrest field to build a second target metric
  from. `contraband_found` (search hit rate) is used as the dashboard's
  second outcome instead, which also happens to match the README's originally
  stated primary metrics.
- **No `subject_age`.** Texas State Patrol doesn't report it. This directly
  shrinks the "Individual Demographics" control layer in the dashboard down
  to driver sex only — it's not a cleaning omission, the source data doesn't
  have it.

These three facts explain several shapes elsewhere in the codebase (the
dashboard's control list, the `OUTPUT_COLUMNS` set, the absence of an
`is_arrested` field) — see them as the root cause if those choices look
arbitrary from a downstream file alone.

`_validate_columns` runs a zero-row header read before the full chunked read,
so a schema mismatch (e.g. Stanford renames a column upstream) fails fast
with a clear message instead of a `KeyError` partway through a multi-minute
chunked read.

### 2.3 `03_merge_features.py` — join stops to county covariates

An inner join between `stops_clean.csv` and `census_stratifiers.csv` on
`county_join_key`. `how="inner"` means any stop whose normalized county name
doesn't match a Texas county from the Census pull is silently dropped from
the *merged* output — but not silently overall: the script computes the
unmatched set (`~isin`) and prints a warning with the distinct unmatched
county names (capped at 10) and a count. This is a deliberate
observability tradeoff — inner join keeps the merge logic and the downstream
`OUTPUT_COLUMNS` contract simple (no `NaN` covariates to handle in the
regression), at the cost of needing this warning to catch silent data loss
from a join-key mismatch (e.g. a misspelled or unincorporated-area county
name that doesn't exist in Census data).

Output: `audit_ready_stops.csv`, ~5.6M rows — the direct input to the Shiny
app.

### 2.4 Why not a shared library or DAG tool

Each script recomputes its own `county_join_key` normalization and each
declares its own `OUTPUT_COLUMNS`. There's no `pipeline/common.py`, no
Makefile, no orchestrator — you run three scripts by hand, in order, per the
README. At three stages with no branching, no scheduling, and no need for
partial re-runs, that's the appropriately minimal amount of infrastructure.
The duplicated join-key logic is a real seam (see §7), but factoring it out
prematurely would be over-engineering for a pipeline this size.

---

## 3. Statistical, diagnostic & dashboard architecture

### 3.0 The `duboisR` package (`duboisR/`)

A real, installable R package (`DESCRIPTION`/`NAMESPACE`/roxygen2/testthat —
not more flat scripts), built to implement the Wells-Du Bois Protocol's
diagnostics. `r_dashboard/app.R` and `r_dashboard/dev/generate_synthetic_data.R`
both load it in dev mode via `devtools::load_all("../duboisR")` (falling back
to an installed copy if present), resolved relative to each script's own
location rather than the shell's cwd, since the two scripts are documented
to be invoked from different working directories (`app.R` from inside
`r_dashboard/`, `generate_synthetic_data.R` from the repo root).

**Shared statistical core (`R/glm_utils.R`).** `dubois_relevel()`,
`build_formula()`, and `fit_audit_glm()` extract exactly the releveling /
formula-construction / Wald-CI logic that used to live inline in
`mod_regression.R` (see §3.2) into tested, reusable functions — the Wald-CI
rationale (closed-form, not `broom::tidy(conf.int=TRUE)`'s profile-likelihood
default, which hangs at millions of rows) is unchanged, just relocated.
Every other diagnostic below that needs a fitted GLM (`check_proxies()`'s
`glm` fallback, `veil_of_darkness_test()`, `subpopulation_disparities()`)
builds on this same function rather than reimplementing it.

**Datasheets for Datasets (`R/datasheet.R`, `R/datasheet_wizard.R`).**
`use_datasheet()` scaffolds a static 7-section template (Motivation,
Composition, Collection Process, Preprocessing, Uses, Distribution,
Maintenance — Gebru et al. 2021) into the researcher's project;
`build_datasheet_wizard()` is an interactive CLI walkthrough of the same
question structure (single source of truth: both are generated from an
internal `datasheet_questions` list built by
`data-raw/build_datasheet_questions.R`) that writes incremental,
resumable answers to `datasheet.json`. Neither automates the qualitative
reflection itself — per the original Datasheets for Datasets paper, that
would defeat the point.

**Composition/proxy/tendentious diagnostics.** `audit_composition()`
computes subpopulation representation and (optionally) subgroup-specific
missingness rates — the numbers a researcher needs for the Composition
section, without narrating them. `check_proxies()` (one function serving
both source documents' identical "Identity Proxy" proposal) temporarily
predicts a protected attribute from "neutral" covariates via `ranger`
(if installed) or a dependency-free one-vs-rest `glm` fallback, flagging
when "excluding" race from a model doesn't actually remove race information.
`check_tendentious()` is a checklist tool prompting explicit classification
of whether an outcome variable reflects an objective measurement or
administrative/subjective human discretion.

**Veil of Darkness (`R/veil_of_darkness.R`).** `compute_daylight_status()`
joins a bundled 254-row TX county centroid table
(`inst/extdata/tx_county_centroids.csv`, sourced from the public-domain
Census Gazetteer Files, joined on the `county_fips` column already carried
through the Python pipeline) and calls `suncalc::getSunlightTimes()`
**vectorized over unique `(date, county)` pairs**, not per-row — required
for acceptable performance at millions of rows. Because the data contract
only carries integer `hour` (no minutes), each stop's timestamp is assumed
to be at the top of its hour — a real, documented resolution limitation, not
a convenience shortcut. `veil_of_darkness_test()` restricts to the
**intertwilight period** (clock hours that are sometimes daylight and
sometimes dark across the data's date/county range — Grogger & Ridgeway
2006) before fitting, and its result always carries the nonreporting-
robustness assumption as an explicit caveat rather than a silent one.

**Threshold Test (`R/threshold_test.R`).** Implements a **fast,
non-hierarchical, non-MCMC approximation** to the Threshold Test for
infra-marginality (Simoiu, Corbett-Davies & Goel 2017) — deliberately scoped
down from the full Bayesian hierarchical model, which would need a new
Stan/MCMC dependency and its own multi-week validation effort.
`aggregate_sufficient_statistics()` collapses millions of rows into
per-(race, county) stop/search/hit counts (county stands in for
"department," since this dataset has no department field). `fit_threshold_test()`
then exploits a closed-form identity — a county's threshold is fully
determined by its own observed search rate given `(a_r, b_r)`, via
`qbeta(1 - search_rate, a_r, b_r)` — so only two parameters per race are fit
via `stats::optim()`, no MCMC. This is a from-first-principles frequentist
point-estimate procedure "in the spirit of" the cited literature, not a
verbatim reproduction of any published implementation; it provides no
partial pooling and no credible intervals. Validated in tests via parameter
recovery on data simulated from known `Beta(a, b)` parameters.

**Subpopulation disparities (`R/subpop_disparities.R`).**
`subpopulation_disparities()` disaggregates TPR/FPR/PPV per intersectional
subgroup from a fitted model's predictions — and explicitly states the
fairness-metrics impossibility result (Chouldechova 2017; Kleinberg,
Mullainathan & Raghavan 2016: FPR and FNR generally can't both be equalized
across groups with a calibrated classifier when base rates differ) in its
output rather than implying a single model can satisfy every fairness
definition at once.

**Synthetic data (`R/simulate_stops.R`).** Generates schema-correct
synthetic data matching the real `audit_ready_stops.csv` contract exactly —
used both as the package's own `tests/testthat/` fixtures and by
`r_dashboard/dev/generate_synthetic_data.R` (now a thin wrapper around it;
see §3.3 and §7).

### 3.1 App shell (`app.R`)

Built on `shiny` + `bslib` (Bootstrap 5 theming, `litera` theme) using the
modern `page_sidebar()` layout primitive rather than the older
`fluidPage()`/`sidebarLayout()` pair. The sidebar exposes exactly two
reactive inputs:

- `outcome_var` — a `selectInput` choosing the glm's dependent variable
  (`search_conducted` or `contraband_found`)
- `controls` — a `checkboxGroupInput` choosing which covariates layer into
  the model (demographics / poverty / income / time of day)

The main panel is a `navset_card_tab` with two panels: "Regression Model"
(the regression module's UI, unchanged from before) and "Data Transparency &
Provenance" (`R/mod_datasheet.R`, new — reads a `datasheet.json` sitting next
to the processed CSV via `duboisR::read_datasheet()` and renders its
motivation/limitations alongside a live `duboisR::audit_composition()`
breakdown; degrades to a "run `build_datasheet_wizard()`" message when no
datasheet exists yet, rather than erroring). Both tabs need the same loaded
data, so the `stops_data()` reactive that used to live inside the regression
module's closure was lifted up into `app.R`'s `server()` and is now passed
into both modules as a parameter.

Three more panels were added later, all reusing the same `stops_data()`
reactive — the `navset_card_tab` now has five panels, not two: "Veil of
Darkness" (`R/mod_veil_of_darkness.R`, see §5/§7.6), "Threshold Test"
(`R/mod_threshold_test.R`, see §7.6), and "Subpopulation Disparities"
(`R/mod_subpop_disparities.R`, see §7.7 — the one panel that also needs
`audit_fit()`, not just `stops_data()`, since it scores the same fitted
model the Regression Model tab shows rather than an independent one;
`audit_fit()` itself was lifted from `mod_regression.R` into `server()` for
exactly this sharing, the same move `stops_data()` went through earlier).

**Headless rendering fix:** macOS defaults `ggplot2`'s bitmap device to
`"quartz"`, which requires an active window-server session. When Shiny is
launched via `Rscript` outside a foreground GUI session (e.g. over SSH, in
CI, or from a background process), quartz doesn't error — it hangs
indefinitely, so `renderPlot()` never resolves and the forest plot area just
stays blank forever with no error message. `app.R` guards against this with
`if (capabilities("cairo")) options(bitmapType = "cairo")` before any Shiny
code runs, since Cairo works headless. This is exactly the kind of failure
that's silent and confusing to debug from symptoms alone, which is why it's
called out explicitly in a comment at the top of the file.

### 3.2 Regression module (`R/mod_regression.R`)

Written as a proper Shiny module (`regression_module_ui` /
`regression_module_server` with namespacing via `NS(id)`), even though the
app currently only instantiates it once. This buys two things: no global ID
collisions if a second model panel is added later (e.g. a side-by-side
comparison view), and a clean seam for testing the module in isolation.

**Data loading now lives in `app.R`'s `server()`** (see §3.1 — it moved up
to be shared with the new provenance tab), still gated behind a
`validate(need(...))` check for the processed CSV's existence, still
releveling `subject_race` — but via `duboisR::dubois_relevel()` now rather
than an inline `stats::relevel()` call.

**The module itself is a thin reactive wrapper around the `duboisR`
package** (§3.0), calling `duboisR::build_formula()` then
`duboisR::fit_audit_glm()`. Both the reference-level fix and the
closed-form Wald-CI computation (`estimate ± 1.96·SE` on the log-odds
scale, exponentiated — chosen over `broom::tidy(conf.int=TRUE)`'s
profile-likelihood default specifically because that hangs at 5.6M rows)
apply exactly as before; they live in `duboisR/R/glm_utils.R`, unit-tested
independent of Shiny. Every checkbox toggle still invalidates
`build_formula()` → `fit_audit_glm()` → `model_summary()` → the plot/table,
with Shiny's dependency graph handling recomputation automatically.

**The `audit_fit()` reactive itself no longer lives inside this module** —
it moved up into `app.R`'s `server()` (same move `stops_data()` made in
§3.1), because `mod_subpop_disparities.R` (§7.7) needs to score the exact
same fitted model this tab plots, not an independently-fit one.
`regression_module_server()`'s signature shrank accordingly: it now just
takes `audit_fit` (a reactive) instead of `stops_data`/`outcome_var`/
`controls` separately and building the fit itself.

**Output surfaces are unchanged:** a `ggplot2` forest plot (point + 95% CI
per race coefficient, `geom_pointrange`, flipped coordinates, a dashed
reference line at OR = 1) and a plain `renderTable` of the same numbers,
filtered to `subject_race` terms only.

### 3.3 Synthetic data generator (`dev/generate_synthetic_data.R`)

A standalone script (not part of the reactive app, not sourced by `app.R`)
that generates a 2,000-row dataset matching the dashboard's expected shape,
with a seeded RNG (`seed = 42`) for reproducibility. It exists so the Shiny
plumbing — reactivity, plotting, table rendering — can be exercised and
debugged without first standing up the real ~7GB data pipeline, API key, and
multi-minute chunked read.

**Now a thin wrapper around `duboisR::simulate_stops()`** (§3.0) rather than
its own standalone generation logic — this fixes the schema-drift rough edge
§7 used to document: the old version fabricated `subject_age` and
`is_arrested`, neither of which exist in the real Texas data; `simulate_stops()`
produces exactly the real data contract's columns, since it's also what the
package's own `tests/testthat/` fixtures are built from (one implementation,
two consumers, no drift possible between them). It still bakes in a
synthetic race effect specifically so the forest plot has a visible,
non-null disparity to render — useful for checking the plot looks right,
worthless as a finding.

---

## 4. The data contract: `audit_ready_stops.csv`

This is the one interface between the Python and R halves of the system.
Columns, as written by `03_merge_features.py` and consumed by
`r_dashboard/` (via `duboisR`'s functions, §3.0):

| Column | Type | Origin | Notes |
|---|---|---|---|
| `subject_race` | factor (releveled to `white`) | Stanford | restricted to white/black/hispanic |
| `subject_sex` | string | Stanford | the entire "demographics" control layer |
| `search_conducted` | 0/1 | Stanford | outcome option 1 |
| `contraband_found` | 0/1 | Stanford | outcome option 2 (stand-in for arrest — no arrest field exists) |
| `hour` | int 0–23 | derived from `date`+`time` | used as `factor(hour)` in the model |
| `date` | date | Stanford | carried through but not yet used by the model — see §5 |
| `violation` | string | Stanford | carried through but not yet used by the model — see §5 |
| `search_basis` | string | Stanford | carried through but not yet used by the model — see §5 |
| `poverty_rate` | float | Census (derived) | socioeconomic control |
| `median_income` | float | Census | socioeconomic control |
| `county_fips` | string | Census | reference/mapping only, not a model input |

`county_join_key` deliberately does **not** survive into the final output —
it's a join mechanism internal to the pipeline, not a field the dashboard
should ever need.

---

## 5. Columns that exist but aren't wired up yet

Three columns (`date`, `violation`, `search_basis`) are threaded all the way
through the pipeline — read from raw, kept through cleaning, kept through the
merge — but are not referenced anywhere in `mod_regression.R`'s formula
construction. `02_clean_stops.py` documents this as intentional
forward-provisioning:

- **`date`** → Veil of Darkness natural experiment. **Now implemented, both
  engine and dashboard.** `duboisR::veil_of_darkness_test()` (§3.0) uses
  `date` (+ `hour` + `county_fips`) to compute sunset/dusk per county/day and
  classify stops as daylight vs. dark; `r_dashboard/R/mod_veil_of_darkness.R`
  (§3.2's sibling module) exposes it as its own "Veil of Darkness" tab rather
  than a sidebar checkbox layer on the main regression, since it's a distinct
  model (race + `is_dark` + `factor(hour)`, restricted to intertwilight
  hours) rather than an additional covariate on `fit_audit_glm()`'s formula.
- **`violation`** (equipment vs. moving violation type) and **`search_basis`**
  (consent vs. probable-cause search) are carried through unused.
  `02_clean_stops.py` retains them as forward-provisioned string columns —
  the kind of thing a pretextual-stop or consent-search disparity analysis
  would need — but no such analysis is scoped, planned, or implemented in
  `duboisR` today. Building one isn't just wiring: it means first deciding
  the methodology (e.g. what counts as "pretextual"), which this project
  hasn't done and isn't committing to here.

---

## 6. Environment & toolchain

- **Python:** a local `.venv` (Python 3.11), dependencies pinned only by name
  in `requirements.txt` (`pandas`, `requests`, `pyarrow`, `python-dotenv`).
  `pyarrow` is declared but not yet imported anywhere in `python/` — it's a
  reserved dependency, most likely for a future faster CSV parsing engine or
  Parquet intermediate format rather than something currently exercised.
- **R (dashboard):** no lockfile / `renv` yet — packages (`shiny`, `bslib`,
  `tidyverse`, `broom`, `devtools`) are installed globally per the README's
  `install.packages(...)` call. `broom` is a listed dependency even though
  `mod_regression.R` (now via `duboisR::fit_audit_glm()`) bypasses
  `broom::tidy()` for the CI calculation (§3.0/§3.2) — it may still be used
  elsewhere or was kept from before that decision was made.
- **R (`duboisR/` package):** a real `DESCRIPTION`-managed dependency set —
  still no `renv` lockfile, but `Imports`/`Suggests` are explicit (`rlang`,
  `ggplot2`, `readr`, `tibble`, `cli`, `jsonlite`, `suncalc`; `Suggests`:
  `testthat`, `ranger`, `withr`, `devtools`, `knitr`, `rmarkdown`). Building
  the vignette additionally needs `pandoc` (a system binary, not an R
  package — `brew install pandoc` on macOS). `devtools::check()` passes
  clean (0 errors, 0 warnings, 0 notes).
- **Secrets:** a single `CENSUS_API_KEY` in a gitignored root `.env`, loaded
  via `python-dotenv`. No other credentials in the system.
- **Data is never committed.** Both `data/raw/*` and `data/processed/*` are
  gitignored (only `.gitkeep` placeholders survive), including the ~1GB raw
  zip and the multi-GB processed CSVs. Reproducing the dataset means
  re-running the pipeline, not pulling from git.
- **macOS build gotchas** (Xcode Command Line Tools path, `clang` C-standard
  mismatches for `tidyverse`'s compiled dependencies, missing `harfbuzz` /
  `fribidi` / `libtiff` system libs) are documented in the README rather than
  here, since they're setup instructions, not architecture.

---

## 7. Known rough edges

Worth naming explicitly, since a design doc that only describes the happy
path is misleading:

1. **Join-key normalization is duplicated**, not shared, between
   `01_fetch_census.py` and `02_clean_stops.py` (§2.1, §2.2). If the
   normalization rule ever needs to change (e.g. to handle a county name
   Census formats differently than Stanford does), it has to change in two
   places in sync, with nothing enforcing that.
2. ~~The synthetic data generator's schema has drifted from the real
   pipeline's schema~~ **Fixed.** `r_dashboard/dev/generate_synthetic_data.R`
   is now a thin wrapper around `duboisR::simulate_stops()` (§3.0, §3.3),
   which produces exactly the real data contract's columns and is also what
   the package's own tests are built from — one implementation, no more
   drift possible between "what tests use" and "what the dashboard's dev
   script produces."
3. **The CSV data contract (§4) is enforced by nothing except code review.**
   There's no schema validation step between the Python output and the R
   input — a column rename or dtype change on either side fails at
   `glm()`-fit time (or worse, silently, if a dtype coercion happens to
   succeed) rather than at a clear boundary. Still true; `duboisR`'s
   functions all assume the same fixed column names the Python pipeline has
   always produced, and don't add a schema-validation layer of their own.
4. **Single-state, single-outcome-pair scope.** The README frames this as a
   multi-state (NC/CT/RI/TX) platform; only Texas is wired end-to-end today.
   Adding a second state means re-running the same three-script pipeline
   against a different raw file and FIPS code, plus deciding how the
   dashboard should let a user pick a state (not yet a UI input). The
   `duboisR` package itself is state-agnostic except for one piece:
   `dubois_tx_centroids()` (§3.0) bundles a Texas-only county centroid table
   for the Veil of Darkness test — a second state would need its own
   centroid table plumbed through the same `centroids` parameter
   `compute_daylight_status()`/`veil_of_darkness_test()` already expose for
   exactly this kind of injection.
5. **Python side still has no automated tests.** Correctness there still
   rests on the inline `_validate_columns` header check (§2.2) and the
   unmatched-county-name warning (§2.3) — both runtime, data-dependent
   checks, not a test suite that runs independent of having the real
   multi-GB dataset on disk. The R side no longer shares this gap: `duboisR/`
   has a `tests/testthat/` suite (96 tests as of this writing) covering
   every exported function against synthetic fixtures, including a
   parameter-recovery test for the Threshold Test approximation (§3.0) and
   hand-verified daylight/dark/twilight classifications for the Veil of
   Darkness test — none of it depends on the real 650MB dataset being
   present.
6. ~~The Veil of Darkness and Threshold Test functions aren't exposed in the
   Shiny UI yet~~ **Fixed, both.** `r_dashboard/R/mod_veil_of_darkness.R` and
   `R/mod_threshold_test.R` are new dedicated modules/tabs (same
   `*_module_ui`/`*_module_server` pattern as §3.2) calling
   `duboisR::veil_of_darkness_test()` and
   `duboisR::aggregate_sufficient_statistics()` + `fit_threshold_test()`
   directly — neither is a sidebar checkbox layer, since both are their own
   models (VoD: race + `is_dark` + `factor(hour)`, restricted to
   intertwilight hours; Threshold Test: per-race Beta risk-distribution
   parameters fit from county-level sufficient statistics) rather than
   covariates on the main regression's formula. Both reuse the app's
   existing `stops_data()` reactive and their package's own `plot.*()` S3
   method. Two real issues surfaced wiring these up against the full
   5.6M-row dataset, both now fixed:
   - `plot.duboisR_threshold_fit()`'s fitted curve spans its full
     theoretical `[0, 1]` search-rate domain by construction (as the sweep
     variable `t` ranges over `(0.001, 0.999)`), while real per-county search
     rates never exceed ~13% — left unclamped, ggplot's default axis
     autoscaling squeezed every actual data point into a sliver against the
     left edge. Now `coord_cartesian(xlim = c(0, observed_max_x * 1.1))`
     zooms the viewport to where the data actually is; this only affects
     what's rendered, not the curve's underlying computation.
   - Also discovered, not fixed by this change: for a race whose fitted
     `(a, b)` are extremely large (the real "white" fit is ~1.9×10⁸,
     ~2×10⁸ — a near point-mass risk distribution), `predicted_hit_rate`
     comes back numerically `NaN` across the entire observed search-rate
     range, so that race's curve is invisible even after the axis fix — not
     an axis problem, a genuine numerical edge case in the unconstrained
     `optim()` fit. Fixing that would mean touching the fitting/curve-sampling
     methodology itself (regularization, reparameterization, non-uniform
     `t` sampling), which wasn't in scope for this pass; `mod_threshold_test.R`
     instead surfaces it as an explicit UI note (`a`/`b` > 1e6 flagged
     alongside nonzero `convergence_code`) rather than hiding it.
7. **`subpopulation_disparities()` silently returned all-`NA`/`NaN` rows
   against the real dataset** — found while wiring `mod_subpop_disparities.R`
   (§3.2's sibling for the new "Subpopulation Disparities" tab, which scores
   the same `audit_fit()` reactive shown on the Regression Model tab, shared
   via `app.R`'s `server()` same as `stops_data()`). Root cause:
   `search_conducted` is `NA` (not `FALSE`) for ~38% of the real Texas
   dataset — Stanford's data simply doesn't report the outcome for a chunk
   of stops, a fact not documented anywhere before this. `glm()` already
   silently drops those rows via its default `na.action = na.omit` when
   *fitting*, but `subpopulation_disparities()` scores against the
   caller-supplied `data` independently of the model's training frame, so an
   `NA` there poisoned every group's confusion-matrix `sum()`/`mean()`
   (default `na.rm = FALSE`). Fixed in `duboisR/R/subpop_disparities.R` by
   dropping `NA`-outcome rows before scoring, with the drop count surfaced in
   the returned `"notes"` attribute; covered by a new regression test
   (`test-subpop_disparities.R`). Separately, the function's `threshold`
   parameter defaults to `0.5`, which is degenerate for an outcome this
   imbalanced (predicted probabilities for `search_conducted` top out
   around 3%) — every row predicts negative, so TPR/PPV come back `NaN` (0/0)
   regardless of the NA fix. `mod_subpop_disparities.R` doesn't hardcode
   `0.5`; it defaults a sidebar-adjacent slider to the outcome's own observed
   base rate (a standard, non-ideological default for an imbalanced binary
   threshold classifier) and lets the researcher move off it. The tab also
   flags a subtler artifact live: if the currently-checked sidebar controls
   leave the model's only predictors as `subject_race`/`subject_sex` — the
   exact columns these subgroups are defined by — every driver in a subgroup
   shares one predicted probability, so TPR/FPR come back exactly `0` or `1`
   per group at any single threshold rather than a real distribution; the UI
   detects this (via `all.vars(delete.response(terms(audit_fit()$model)))`)
   and tells the researcher to check more control layers rather than let it
   read as a bug.
