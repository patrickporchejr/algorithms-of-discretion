# Design Doc: Algorithms of Discretion / `duboisR`

`duboisR` is an installable R package (`duboisR/`) that is the diagnostic
engine of this project. The Python pipeline, the Shiny dashboard, and the
CLI (one dispatcher, `duboisR/inst/scripts/cli.R`, over three underlying
Rscript programs — see §5.3's "One consistent CLI entry point") all exist
to feed it data and render its output. This doc covers the currently
shipped surface: the **Veil of Darkness** audit (the dashboard's one
active tab, the CLI's `veil` command, and the precompute script that feeds
both), plus the CLI's other two commands — the datasheet generator and
the LLM grounding test. `duboisR` itself
implements several other diagnostics (a Threshold Test approximation,
identity-proxy and tendentious-outcome checks, subpopulation disparity
disaggregation) that remain exported and tested but aren't part of any
currently active dashboard tab or `inst/scripts/` entry point —
`?function_name` covers them if you go looking, but they're out of scope
for this doc.

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
                                                                          results/vod_charts.rds
                                                                                    │
                                                        ┌───────────────────────────┴───────────────────────────┐
                                                        ▼                                                       ▼
                                          r_dashboard/app.R (Shiny)                  inst/scripts/cli.R veil (Rscript CLI)
```

Three stages, one file-based contract between each: a CSV between Python
and the precompute step, one small `.rds` between the precompute step and
its two front ends (dashboard, CLI). There is no API, no message queue,
no shared process. `duboisR` sits in the middle as a library, not a
service — the precompute script, the dashboard, and the CLI all call it
in-process (`devtools::load_all("duboisR")` or `library(duboisR)`).

---

## 2. Language and package choices

**Python does ETL, nothing else.** `pandas` + `requests` for chunked CSV
processing and a REST call to the Census API. No statistical modeling
happens in `python/` — it's string cleaning, filtering, and one join.

**R does statistics, packaged as a real library, not scripts.** `duboisR`
is a proper `DESCRIPTION`/`NAMESPACE`/roxygen2/testthat package,
`devtools::check()` clean (0 errors/warnings/notes). A diagnostic tool for
auditing bias has to be independently verifiable — a tested, documented,
`?help`-able package is falsifiable in a way a pile of analysis scripts in
a notebook is not.

**Why the Veil of Darkness charts are descriptive, not a regression fit.**
`duboisR` also has a regression-based version of this test
(`fit_veil_of_darkness()`, a `race:is_dark` interaction GLM with
closed-form Wald CIs — see `?fit_audit_glm` for why closed-form rather
than `broom::tidy()`'s default profile-likelihood CI, which hangs at
millions of rows) — it's exported, tested, and still the more rigorous
answer to "did the disparity change after dark." The currently shipped
CLI/dashboard don't call it, though: `veil_of_darkness_module()` and the
`summarize_*()`/`plot_*()` functions it wraps are pure aggregation (base R
`aggregate()`/`merge()`, no `glm()` call anywhere in that path), which is
what makes them fast enough to run as a synchronous CLI command instead of
needing a precomputed cache the way a 5.6M-row GLM fit would.

---

## 3. Data pipeline (`python/`)

Three scripts, run in order by `make all`, each a plain script — not a DAG
framework. Appropriate at this scale: three steps, no branching, no
scheduling need.

**`01_fetch_census.py`** pulls ACS 5-Year variables for Texas counties and
derives a `county_join_key` by normalizing the Census `NAME` field
(`"Harris County, Texas"` → `"HARRIS"`).

**`02_clean_stops.py`** is the heaviest-lifting script. The raw Stanford
TX file is ~27.4M rows across 44 columns; `pandas.read_csv` reads it with
`chunksize=500_000` directly against the `.zip` and `usecols=RAW_COLUMNS_NEEDED`
to skip parsing columns nothing downstream touches. Filtering to
`subject_race in {white,black,hispanic}` and to 2015–2017 (out of the full
2006–2017 range) gets the working set down to ~5.6M rows. `county_join_key`
is derived here independently of `01_fetch_census.py` using identical
normalization logic — a duplication, not a shared helper, flagged in §11.

Two schema facts, discovered against the actual file rather than assumed
up front: **no FIPS at the stop level** (only free-text `county_name`,
hence the name-based join — FIPS is carried through from the Census side
afterward), and **no `subject_age`** (Texas State Patrol doesn't report
it).

**`03_merge_features.py`** inner-joins `stops_clean.csv` to
`census_stratifiers.csv` on `county_join_key`, warning (with the distinct
unmatched names, capped at 10) when a stop's normalized county name
doesn't match a Texas county from the Census pull.

---

## 4. The data contract: `audit_ready_stops.csv`

The one interface between the Python and R halves. `compute_daylight_status()`
and `summarize_county_search_rates()` (the two `duboisR` functions the
Veil of Darkness pipeline calls against this file directly) assume these
column names exist — there's no schema-validation layer; `abort_if_missing_cols()`
is the closest thing to one, and it only catches a missing column, not a
wrong type.

| Column              | Type                                         | Origin                     | Used by Veil of Darkness?                                          |
| ------------------- | --------------------------------------------- | -------------------------- | -------------------------------------------------------------------- |
| `subject_race`      | string, releveled to `white` before modeling | Stanford                   | yes — the comparison variable                                       |
| `search_conducted`  | 0/1, `NA` for ~38% of real rows              | Stanford                   | yes — chart 3/4's search-rate disparity                             |
| `hour`              | int 0–23, no minutes                          | derived from `date`+`time` | yes — resolution ceiling for daylight/dark classification, see §6.5 |
| `date`               | date                                          | Stanford                   | yes — sunset/dusk lookup                                             |
| `county_fips`       | string                                        | Census                     | yes — centroid join key                                              |
| `subject_sex`, `contraband_found`, `violation`, `search_basis`, `poverty_rate`, `median_income` | — | Stanford/Census | carried through, not consumed by the currently shipped Veil of Darkness charts |

`county_join_key` deliberately does not survive into this file — it's an
internal pipeline join mechanism, not something any statistical function
should ever reference.

---

## 5. `duboisR`: the diagnostic engine (Veil of Darkness slice)

### 5.1 Shared statistical core (`glm_utils.R`)

One function the Veil of Darkness path actually uses:

- `dubois_relevel(data, col, ref)` — `glm()`'s default factor encoding
  picks the reference level alphabetically, which for `subject_race` would
  silently make `"black"` the baseline. `veil_of_darkness_module()$init()`
  and `prepare_veil_of_darkness_data()` both call this before anything
  else touches `subject_race`.

`build_formula()` and `fit_audit_glm()` (the closed-form-Wald-CI `glm()`
wrapper) also live here, used by `fit_veil_of_darkness()`'s optional
interaction-model fit (§2) — not called anywhere in the currently active
precompute/CLI/dashboard path.

### 5.2 Datasheets for Datasets (`datasheet.R`, `datasheet_wizard.R`)

Implements Gebru et al. 2021's "Datasheets for Datasets" — a standardized
seven-section questionnaire that documents a dataset's provenance and
limitations. `use_datasheet()` scaffolds a static template;
`build_datasheet_wizard()` is an interactive CLI walkthrough that writes
to a resumable `datasheet.json`; `seed_datasheet_answers()` /
`duboisR/inst/scripts/seed_demo_datasheet.R` is the non-interactive
counterpart. Neither wizard nor scaffold automates the qualitative
reflection itself — a design decision inherited directly from the source
paper. `read_datasheet()` returns `NULL` (not an error) when no datasheet
exists yet, so `run_grounding_experiment()` (§5.4) can degrade gracefully.

### 5.3 Veil of Darkness (`veil_of_darkness.R`, `veil_of_darkness_charts.R`, `veil_of_darkness_module.R`)

The most literal implementation of the package's Du Boisian framing: a
natural experiment exploiting the fact that an officer's ability to
observe a driver's race is worse after dark (Grogger & Ridgeway 2006). If
a racial disparity in stops is driven by the officer visually profiling
race, that disparity should shrink once darkness removes the officer's
ability to act on race at all.

**Daylight classification (`compute_daylight_status()`).** Joins county
centroids (`dubois_tx_centroids()`, bundled, TX-only), computes each
stop's sunset/civil-dusk time via `suncalc::getSunlightTimes()` (vectorized
over unique `(date, county)` pairs, not per-row), and classifies each
stop as `"daylight"`, `"dark"`, or `"twilight"` (`is_dark`, `NA` for
twilight). Two performance decisions worth knowing if you extend this:
the joins use `match()` rather than `merge()` (~2–15s vs. ~250–800s at
5.6M rows — base `merge()`'s sort-and-match join is the difference between
this pass finishing in ~2 minutes and not finishing at all), and
`stop_datetime` is built via `ISOdatetime()` on `POSIXlt` components
rather than `paste()`-then-`as.POSIXct()` string parsing (~65s vs. ~125s).
Because the data contract only carries an integer `hour`, every stop's
timestamp is assumed to be at the top of its recorded hour — a real,
unavoidable resolution limitation, not a convenience shortcut.

**The intertwilight restriction (`prepare_veil_of_darkness_data()`).**
Comparing all daylight stops to all dark stops is confounded by the fact
that *who's on the road* varies by clock time regardless of race, so the
comparison is restricted to clock hours that are *sometimes* daylight and
*sometimes* dark across the data's date/county range — this is the core
Grogger-Ridgeway design trick, not an optional filter.

**The descriptive charts (`veil_of_darkness_charts.R`).** Four
`summarize_*()`/`plot_*()` function pairs, each taking the *already*
prepared/classified data rather than doing any classification themselves
— one tested code path (above) feeds all of them:

- `summarize_county_vod_disparity()` / `plot_county_vod_disparity()` —
  each county's black share of black+white inter-twilight stops, daylight
  vs. dark, and their ratio (chart 1).
- `summarize_statewide_vod()` / `plot_statewide_vod()` /
  `summarize_statewide_vod_table()` — each race's statewide share of
  stops, before vs. after dark (chart 2, plus its numeric table).
- `summarize_county_search_rates()` / `summarize_county_search_disparity()`
  / `plot_county_search_disparity()` — county-level search-rate disparity
  (chart 3). Built from the *full* dataset, not the intertwilight
  restriction — the search decision is a separate discretion point from
  the stop decision Veil of Darkness targets, and isn't bound to that
  clock-time window.
- `plot_vod_search_combined()` — charts 1 and 3 side by side via
  `patchwork` (`Suggests`, not `Imports` — guarded by
  `rlang::check_installed()`, since it's the only function in the package
  that needs it), reusing the already-built plot objects rather than
  rebuilding them (chart 4).

All four are written in base R (`aggregate()`, `merge()`, `split()`) —
deliberately, matching `compute_daylight_status()`'s own dependency-light
approach above, rather than `dplyr`/`tidyr` pipelines. At the row counts
these actually aggregate over (hundreds of thousands to ~5.6M rows into a
~254-county or ~6-row result), base R's `aggregate()` is not a performance
concern the way `merge()` was for the raw stop-level join above.

**The stateful CLI/console wrapper (`veil_of_darkness_module.R`).**
`veil_of_darkness_module()` returns a plain environment (not R6/S4 —
deliberately, to avoid a new OOP-framework dependency for a thin piece of
session state) with an `$init()` method that loads the CSV, runs the two
steps above, and populates every intermediate table (`$stops_geo`,
`$vod_data`, `$county_vod_disparity`, etc.) directly on the object, plus
one `$plot_*()` method per chart that builds, caches, and returns it.
Environments have reference semantics, so `self$field <- value` inside
any method mutates state every other method sees immediately — no `<<-`,
no reassigning the returned object. `duboisR/inst/scripts/veil_of_darkness_cli.R`
is a thin Rscript wrapper around this object (subcommand → method call →
print the relevant table + optionally `ggsave()` the plot); the Shiny
dashboard's `mod_veil_of_darkness.R` calls the plain `summarize_*()`/`plot_*()`
functions directly instead (it already has `results/vod_charts.rds`
precomputed, so it doesn't need `$init()`'s CSV-loading step) — both front
ends render from the same tested functions, never their own copy of the
ggplot code.

**One consistent CLI entry point (`inst/scripts/cli.R`).** `veil_of_darkness_cli.R`
above, `seed_demo_datasheet.R` (§5.2), and `run_grounding_experiment.R`
(§5.4) are each independently runnable, but `cli.R` gives all three one
uniform invocation: `Rscript duboisR/inst/scripts/cli.R <command> [options]`,
where `<command>` is `veil`/`datasheet`/`grounding`. It's a dispatcher, not
a reimplementation — the mechanism worth knowing if you add a fourth
command: each underlying script is a plain top-level `Rscript`, written to
call `commandArgs(trailingOnly = TRUE)` itself, so `cli.R` can't just call
a function and pass arguments the normal way. Instead, `run_command()`
defines a local override of `commandArgs()` (returning the dispatcher's
own args with the `<command>` token stripped) and calls
`source(path, local = TRUE)` from inside that same local frame — the
sourced script's top-level, unqualified `commandArgs()` calls resolve to
the override via ordinary lexical scoping before falling through to
`base::commandArgs()`, so the underlying script sees exactly the argument
vector it would if invoked directly, without any of its own code changing.

### 5.4 LLM datasheet-grounding experiment (`grounding_experiment.R`, `llm_clients.R`)

Rather than *asserting* that a datasheet makes a dataset's provenance
legible, this measures it — against an LLM as a concrete downstream
consumer. `run_grounding_experiment()` asks the same flagship model the
same fixed battery of boolean/enum/numeric questions about the dataset
twice: once **naive** (a compact, pseudonymized description of the schema
plus a small random sample — see `build_data_context()`), once
**grounded** (the identical description plus the full `datasheet.json`
and an instruction to consult it first). Each answer is scored against a
hand-authored `expected_answer`.

```r
run_grounding_experiment(
  data_path = "data/processed/audit_ready_stops.csv",
  datasheet_path = "data/processed/datasheet.json",
  providers = c("anthropic", "openai"),
  models = list(anthropic = "claude-opus-5", openai = "gpt-5.1"),
  n_repeats = 2
)
```

The raw sample is pseudonymized before either condition ever sees it
(`build_data_context()`) so the *naive* condition can't take a shortcut
that has nothing to do with grounding (e.g. recognizing a real Texas FIPS
prefix on sight); every provider call is forced through a
JSON-Schema-constrained tool call rather than parsed free text, with
confidence nested per-answer so the report can tell "grounding changed
the answer" apart from "grounding changed how sure the model was."
`n_repeats > 1` runs independent trials per (provider, condition) — see
`summarize_grounding_trials()` for why (providers aren't called at
temperature 0, so a single trial's "changed answer" could be sampling
noise). `call_anthropic()`, `call_openai()`, `call_gemini()`, and
`call_grok()` are the four provider clients — `call_openai()` and
`call_grok()` share one implementation since xAI's API is explicitly
OpenAI-compatible.

Opt-in (`make grounding`, not part of `make all`/`make results`) — it
makes real, billed API calls.

### 5.5 Synthetic data (`simulate_stops.R`)

`simulate_stops(n, seed, counties)` generates data matching the real
`audit_ready_stops.csv` contract exactly. It's the single generator behind
both the package's own `tests/testthat/` fixtures
(`dubois_test_stops()`) and `r_dashboard/dev/generate_synthetic_data.R`, so
the dashboard's dev-mode data and the package's test fixtures cannot
drift apart. A synthetic race effect is baked into `search_conducted`
purely so plots have a visible signal when checking that a chart looks
right — it is manufactured, not a finding.

---

## 6. Using `duboisR` directly

```r
devtools::load_all("duboisR")

# Interactive/CLI-style module -- see §5.3
vod <- veil_of_darkness_module()
vod$init(data_path = "data/processed/audit_ready_stops.csv")
vod$plot_combined()

# Or the plain functions, if you already have prepared data:
stops <- readr::read_csv("data/processed/audit_ready_stops.csv")
stops <- dubois_relevel(stops, "subject_race", ref = "white")
prepared <- prepare_veil_of_darkness_data(stops)
plot_county_vod_disparity(summarize_county_vod_disparity(prepared$fit_data))

# The regression-based version of the same test (§2) -- not called by the
# CLI/dashboard, but still available directly:
vod_fit <- fit_veil_of_darkness(prepared, outcome_var = "search_conducted", interaction = TRUE)
print(vod_fit); plot(vod_fit)

# Datasheet + LLM grounding (§5.2, §5.4)
build_datasheet_wizard("datasheet.json")
run_grounding_experiment(
  data_path = "data/processed/audit_ready_stops.csv",
  datasheet_path = "data/processed/datasheet.json",
  providers = "anthropic", models = list(anthropic = "claude-opus-5")
)
```

Every function above is documented via `?function_name` and covered by
`tests/testthat/`.

---

## 7. Precompute & caching (`inst/scripts/precompute_audit.R`)

The dataset is a frozen, one-time pull, and daylight classification is a
~2-minute pass over 5.6M rows — not something to repeat per dashboard
session or per CLI invocation. `precompute_audit.R` (run by `make
results`) does exactly two things: `prepare_veil_of_darkness_data()`
(cached separately as `results/veil_prepared.rds`, in case a caller wants
the full intertwilight-restricted dataset rather than just the chart
summaries), then the four `summarize_*()` calls from §5.3, written
together as `results/vod_charts.rds` — the one file both `app.R` and
`veil_of_darkness_cli.R` read.

`app.R`'s `veil_module_server()` reads `vod_charts.rds` directly (no live
`read_csv()` of the 650MB source CSV at all); `veil_of_darkness_cli.R`
goes through `veil_of_darkness_module()$init()` instead, since a
standalone CLI invocation has no dashboard session to have already paid
the precompute cost — it re-loads and re-classifies from the raw CSV
every run (~2 minutes), by design: it's meant for an occasional console
check, not a per-request path.

---

## 8. Shiny dashboard architecture (`r_dashboard/`)

Built on `shiny` + `bslib` (Bootstrap 5, `litera` theme) using
`page_fluid()` — no sidebar; the currently active tab takes no
outcome/covariate inputs. `app.R`'s `navset_card_tab` has one active
`nav_panel`, Veil of Darkness (`R/mod_veil_of_darkness.R`); the file also
still `source()`s and structurally supports adding more panels back the
same way it always did (Shiny modules, `NS(id)`-namespaced), it's just
that nothing else is wired into `ui`/`server` right now.

`mod_veil_of_darkness.R` renders the four charts straight from
`duboisR::plot_county_vod_disparity()` / `plot_statewide_vod()` /
`plot_county_search_disparity()` / `plot_vod_search_combined()` (§5.3) —
no ggplot code lives in the module itself, so the dashboard and the CLI
are guaranteed to render identically.

**The one genuinely nasty bug class in the Shiny layer** is a headless
rendering hang, not a data bug: macOS defaults `ggplot2`'s bitmap device
to `"quartz"`, which needs an active window-server session. Launched via
`Rscript` outside a foreground GUI session (SSH, CI, a background
process), quartz doesn't error — it hangs indefinitely, so `renderPlot()`
never resolves and a chart area just stays blank forever with no error
message anywhere. The fix is one line, guarded at the very top of `app.R`
before any Shiny code runs:

```r
if (capabilities("cairo")) options(bitmapType = "cairo")
```

---

## 9. What's unique about `duboisR`

Answering directly, since it's a reasonable thing to ask before deciding
whether to actually run this: most "fairness toolkits" ship a battery of
generic metric functions (disparate impact ratio, equalized odds gap,
calibration error) domain-agnostic by design. `duboisR`'s Veil of
Darkness implementation is the opposite bet: not a metric computed from a
confusion matrix, but a natural experiment specific to data with a
timestamp and a location, exploiting a real physical fact (officers can't
see as well in the dark) as an identification strategy — something a
generic toolkit has no way to offer, because it doesn't generalize to
arbitrary tabular data.

The **LLM grounding experiment** (§5.4) is, as far as this project's
authors are aware, a genuinely novel empirical test of the Datasheets for
Datasets thesis — instead of asserting that provenance documentation
matters, it measures whether a concrete downstream consumer's answers
about a dataset actually change when that documentation is present.

`duboisR` also implements a Threshold Test approximation, identity-proxy
and tendentious-outcome checks, and subpopulation disparity
disaggregation — exported and tested, not part of the currently shipped
surface this doc covers (see the file header).

Nothing in this package outputs a verdict — "this dataset is biased" is
never a return value anywhere. It outputs the specific numbers a
researcher needs to reach that judgment themselves.

---

## 10. Testing

`duboisR/tests/testthat/` runs against `simulate_stops()`-derived
fixtures (`helper-fixtures.R`), independent of the real multi-GB dataset
ever being present on disk. Worth calling out specifically because it
validates something a plain "does it run without erroring" test wouldn't:
the Veil of Darkness suite's hand-verified daylight/dark/twilight
classifications against known sunset times
(`test-veil_of_darkness.R`), and the chart/module tests
(`test-veil_of_darkness_charts.R`, `test-veil_of_darkness_module.R`) that
check aggregation arithmetic against hand-built tables, not just "returns
a data frame." `devtools::check()` passes clean (0 errors/warnings/notes).

The Python side has no test suite — correctness there rests on
`_validate_columns`'s header check and the unmatched-county-name warning,
both runtime and data-dependent rather than an independent test harness.

---

## 11. Environment & toolchain

- **Python:** a local `.venv` (3.11), `pandas`/`requests`/`pyarrow`/`python-dotenv`
  pinned only by name in `requirements.txt`.
- **R (`duboisR/`):** `Imports`: `rlang`, `ggplot2`, `readr`, `tibble`,
  `cli`, `jsonlite`, `suncalc`, `httr2`, `stats`, `utils`. `Suggests`:
  `testthat`, `ranger`, `withr`, `devtools`, `knitr`, `rmarkdown`,
  `patchwork` (only needed for `plot_vod_search_combined()`, guarded by
  `rlang::check_installed()`). No `renv` lockfile for `duboisR` itself —
  see §12.
- **R (dashboard, `r_dashboard/`):** `shiny`, `bslib`, `tidyverse`,
  `devtools`, `renv`-managed (`renv.lock`).
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
   ever needs to change, it has to change in two places in sync.
2. **The CSV data contract (§4) is enforced by nothing except code review
   and `abort_if_missing_cols()`'s existence check.** No schema-validation
   step catches a column rename or dtype change between the Python output
   and the R input before it hits `compute_daylight_status()`-time.
3. **Single-state scope.** `duboisR` itself is state-agnostic except one
   piece: `dubois_tx_centroids()` bundles a Texas-only county centroid
   table, and nothing in the dashboard/CLI exposes swapping the
   `centroids` argument `compute_daylight_status()` already accepts for
   exactly this — a second state needs its own centroid table plumbed
   through by hand (see README's "Pointing the pipeline at a different
   state").
4. **Python has no automated test suite** — correctness rests on runtime,
   data-dependent checks rather than an independent harness.
5. **Hour-only timestamp resolution** (§5.3) means daylight/dark
   classification for stops near sunset/dusk is coarser than the
   underlying astronomical calculation supports — a real data-contract
   limitation, not something any fix in `duboisR` itself can correct.
6. **No `renv` lockfile** for `duboisR` (unlike `r_dashboard/`) —
   dependencies are version-unpinned beyond what's declared in
   `DESCRIPTION`'s `Imports`.
