# Algorithms of Discretion

An interactive data audit platform examining how socioeconomic and spatial/environmental covariates modify (or fail to modify) apparent racial disparities in U.S. traffic stops.

This repository serves as the applied computational data engine for the white paper:

> **The Algorithmic Color Line: Auditing "Algorithms of Discretion" via QuantCrit and Du Boisian Sociology**  
> _By: Patrick Eugene Porché Jr._

By examining data science in tandem with W.E.B. Du Bois's _double consciousness_ and Ruha Benjamin's _Race After Technology_, this project demonstrates how administrative police data (and the machine learning models trained on it) encode historical enforcement discretion rather than underlying driver behavior.

---

## Architecture Overview

This project separates data engineering, statistical estimation, and interactive visualization into a polyglot pipeline:

- **Data Pipeline (Python):** Ingests standardized records from the Stanford Open Policing Project, pulls ACS (American Community Survey) 5-Year Census covariates via API, and performs spatial joins on County FIPS (Federal Information Processing Standards).
- **`duboisR` Core Engine (R):** an installable R package (`duboisR/`) implementing the _Wells-Du Bois Protocol_ for algorithmic auditing — multivariable logistic regressions with closed-form Wald CIs, a Veil of Darkness natural-experiment test, a fast Threshold Test approximation for infra-marginality, identity-proxy/tendentious-outcome diagnostics, subpopulation disparity disaggregation, and Datasheets-for-Datasets scaffolding. See `vignette("wells-du-bois-protocol", package = "duboisR")` for the theoretical grounding and each function's `?` help page for details.
- **Audit Dashboard (R Shiny):** An interactive UI allowing policy researchers to layer demographic, socioeconomic, and environmental controls in real time to observe how disparity estimates shift.

---

## Product Scope & Methodological Framing

- **Primary Metrics:** Traffic stop rate, search rate, search "hit rate" (contraband yield).
- **Geographic Scope:** Tiered sampling strategy targeting 3–5 high-coverage states from the Stanford Open Policing Project (e.g., NC, CT, RI, TX) with standardized County FIPS and timestamp records. **Currently implemented: Texas only** — the pipeline, dashboard, and Veil of Darkness county-centroid table are all TX-specific today; the other states are planned scope, not wired up yet (see Setup below).
- **Toggleable Control Layers:**
  1. _Unadjusted / Raw Disparity_
  2. _+ Individual Demographics_ (Driver Sex — Texas State Patrol doesn't report driver age)
  3. _+ Socioeconomic Context_ (County Median Household Income, Poverty Rate)
  4. _+ Environmental Discretion_ (Time of Day / Sunset Daylight Status via Veil of Darkness)
- **Target Audience:** Computational social scientists, policy researchers, and data engineers. UI is designed for legible exploration of regression outputs.
- **Deliverables:**
  - Interactive R Shiny Web Platform
  - Reproducible Quarto (`.qmd`) White Paper compiling to PDF/HTML
  - `duboisR` R package for diagnostic fairness testing (`duboisR/` — installable, tested, documented)

---

## Data Sources

1. **[Stanford Open Policing Project](https://openpolicing.stanford.edu/):** Standardized traffic stop records across state patrol agencies, including timestamps, race/sex demographics, search outcomes, and county FIPS identifiers.
2. **U.S. Census Bureau ACS 5-Year Estimates:** Pulled dynamically via `Census API` for county-level median household income (`B19013_001E`) and poverty rates (`B17001_002E`).
3. **Astronomical Solar Position Data:** Solar dusk/sunset calculations computed via `suncalc` (R) / `astral` (Python) keyed on stop date, timestamps, and county centroids to execute the Veil of Darkness natural experiment.

---

## Unmeasured Factors (Explicit Methodological Caveats)

Administrative datasets reflect institutional policing practices rather than raw public behavior. This platform explicitly identifies and controls for the following unobservables in its write-ups:

- **Missing Denominator (Baseline Driving Population):** Administrative records capture who was stopped, not who drove by without being stopped.
- **Enforcement Discretion:** Stop volume reflects departmental priorities and pretextual enforcement (e.g., minor equipment violations vs. moving violations).
- **Structural Upstream Causes:** Socioeconomic indicators (e.g., income, poverty) interact with race due to historical redlining and residential segregation; statistical controls adjust for these variables but do not imply independence.
- **Instrument Discrepancies:** Self-reported offense/victimization data (NCVS) measures a different population than administrative traffic stop records.

---

## Repo Layout

```
├── Makefile                 # DAG over the pipeline: `make all` (data), `make results` (+ precompute)
├── data/
│   ├── raw/                 # Stanford Open Policing CSVs, Census API pulls (gitignored)
│   └── processed/           # Merged, analysis-ready datasets (gitignored)
├── results/                 # Precomputed model fits the dashboard reads (gitignored, see below)
├── python/                  # Data acquisition, cleaning, spatial join
├── duboisR/                 # R package: the Wells-Du Bois Protocol diagnostic engine
│   ├── R/                   # glm_utils, veil_of_darkness, threshold_test, datasheet, ...
│   ├── inst/extdata/        # bundled TX county centroids (Veil of Darkness geodata)
│   ├── inst/scripts/        # precompute_audit.R (populates results/), run_grounding_experiment.R (opt-in, `make grounding`)
│   ├── inst/templates/      # datasheet.md/.qmd scaffolding templates
│   ├── tests/testthat/      # unit + parameter-recovery tests
│   └── vignettes/           # theoretical grounding (QuantCrit, Du Bois, Wells)
├── r_dashboard/             # Shiny app: renders results/*.rds (consumes duboisR)
│   ├── R/                   # Shiny modules (regression, veil of darkness, threshold test, subpop disparities, data transparency, llm grounding test)
│   └── www/                 # CSS/static assets
├── notebooks/                # Scratch EDA, not pipeline code
└── paper/                   # Quarto white paper (added once findings exist)
```

## Setup

The pipeline currently targets **Texas** — the Stanford Open Policing
"State Patrol" file (statewide, county-level, 2006-2017). See
[Pointing the pipeline at a different state](#pointing-the-pipeline-at-a-different-state)
below to adapt it.

```bash
# 1. Install R (the CLI, not the R.app cask — the cask installer needs sudo)
brew install r
Rscript -e 'install.packages(c("shiny","bslib","tidyverse","broom","devtools"), repos="https://cloud.r-project.org")'

# 1.5. Install duboisR itself (or just leave it -- r_dashboard/app.R falls back
#      to `devtools::load_all("../duboisR")` automatically in dev mode)
Rscript -e 'devtools::install("duboisR")'

# 2. Python env
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# 3. cp .env.example .env, then get a free Census API key
#    (https://api.census.gov/data/key_signup.html) and set CENSUS_API_KEY

# 4. Download the raw Texas State Patrol CSV (~1GB zipped, ~7.2GB unzipped —
#    the pipeline reads directly from the .zip, no need to unzip by hand)
curl -L -o data/raw/tx_statewide_2020_04_01.csv.zip \
  "https://stacks.stanford.edu/file/druid:yg821jf8611/yg821jf8611_tx_statewide_2020_04_01.csv.zip"

# 5. Build everything: the 3-step Python pipeline, then every model fit the
#    dashboard serves. `make` only reruns steps whose inputs actually
#    changed -- see `make -n all results` to preview what would run.
make all       # -> data/processed/audit_ready_stops.csv (~5.6M rows)
make results   # -> results/*.rds (~2min, mostly Veil of Darkness's sunset/dusk pass over
               #    the full dataset -- see duboisR/inst/scripts/precompute_audit.R)

# 6. Run the app -- it renders results/*.rds, it does not fit models live
cd r_dashboard && Rscript -e 'shiny::runApp(".")'
```

### LLM Grounding Test (optional)

The dashboard's "LLM Grounding Test" tab asks a flagship LLM the same fixed
battery of boolean/multiple-choice/numeric questions about the dataset
twice per trial — once given only a compact, pseudonymized description of
the data ("naive"), once given the same description plus an explicit
instruction to read `datasheet.json` first ("grounded") — and scores both
against hand-authored expected answers, so the value of the datasheet is
shown empirically rather than asserted (see
`duboisR::run_grounding_experiment()`). Each answer also carries a
self-reported confidence score, and every condition runs `N_REPEATS = 2`
independent trials (set at the top of the script below) so the report is a
majority-vote answer plus a stability rate, not a single noisy draw — see
`duboisR::summarize_grounding_trials()`.

It's **not** part of `make all`/`make results`: it makes real, billed LLM
API calls and needs provider credentials, so it has its own opt-in target.

```bash
# Set at least one of these in your .env (see .env.example) -- every
# provider with a key set gets run and compared:
#   ANTHROPIC_API_KEY=your_key_here
#   OPENAI_API_KEY=your_key_here
#   GEMINI_API_KEY=your_key_here
#   XAI_API_KEY=your_key_here

make grounding   # -> results/grounding_experiment.rds
```

If none are set, that dashboard tab just shows a message pointing here
instead of erroring — everything else in the app works without it.

**Approximate cost per `make grounding` run.** At `N_REPEATS = 2`, one
provider makes 4 calls total (2 conditions × 2 trials) — 16 calls if all 4
providers are set. Dollar cost depends on each provider's current per-token
pricing, which moves too fast to keep accurate in this file; see the dated
snapshot (measured token counts plus a one-time pricing estimate) in a
comment near the top of
`duboisR/inst/scripts/run_grounding_experiment.R`, and each provider's own
current pricing page (linked in `.env.example`) for today's number. Set
`N_REPEATS <- 1` in that same script to roughly halve the token spend, at
the cost of losing the stability/majority-vote signal.

`make clean` removes every generated file (`data/raw/census_stratifiers.csv`,
`data/processed/*.csv`, `results/`) so you can rebuild from scratch; it does
*not* touch the raw Stanford download, since that's not something `make`
generates. If you only want to run one pipeline step by hand (e.g. to debug
it), each script is still directly runnable — see the `Makefile` for the
exact `Rscript`/`python` invocations and working directories it uses.

### Pointing the pipeline at a different state

The Stanford Open Policing Project publishes one "State Patrol" file per
state, each at its own URL (Stanford's `stacks.stanford.edu` assigns a
unique "druid" ID per file — there's no predictable pattern to construct it
from a state abbreviation). To point this pipeline at a different state:

1. Go to the [data page](https://openpolicing.stanford.edu/data/), find your
   target state's State Patrol download link, and copy its actual URL (same
   as step 4 above, just for a different state).
2. Update what's currently Texas-hardcoded:
   - **`python/01_fetch_census.py`**: `TARGET_STATE_FIPS` (Texas is `"48"` —
     look up your state's 2-digit FIPS code).
   - **`python/02_clean_stops.py`**: the raw file path passed to
     `clean_stops(...)` in `if __name__ == "__main__":`, and
     `RAW_COLUMNS_NEEDED` if the new state's file has different column
     coverage — Stanford's schema isn't fully uniform across states (Texas,
     for instance, has no `subject_age` and no arrest outcome; check the new
     file's header before assuming parity — see "Schema realities" below).
   - **`Makefile`**: the `RAW_STOPS` variable, to match the new raw filename.
   - **`duboisR`'s county centroid table**: `dubois_tx_centroids()` /
     `inst/extdata/tx_county_centroids.csv` is Texas-only today (FIPS prefix
     `48`). Veil of Darkness needs a lat/lon centroid per county to compute
     sunset/dusk, so without a matching centroid table it'll warn "no
     centroid match" and drop every row. Regenerate one by adapting
     `duboisR/data-raw/build_tx_county_centroids.R` — its source is a
     *national* Census Gazetteer file it already downloads; just change the
     `substr(.data$GEOID, 1, 2) == "48"` filter to your state's FIPS prefix.
     This is genuinely Texas-hardcoded rather than a config toggle today
     (`compute_daylight_status()` takes a `centroids` argument, but nothing
     in the dashboard exposes swapping it) — matches the "Currently
     implemented: Texas only" note in Product Scope above.
3. Re-run `make all && make results`. Because the raw file, target FIPS, and
   centroid table are all different inputs now, Make will detect the
   relevant steps as stale and rebuild them; use `make clean` first if you
   want a fully fresh run.

**Schema realities discovered wiring this up** (the raw Stanford file doesn't
match the originally assumed schema):
- No FIPS code at the stop level — only `county_name` text. The pipeline
  joins stops to Census county data on a normalized name (`county_join_key`),
  not FIPS; FIPS is carried through from the Census side afterward.
- No arrest outcome — `outcome` is only ever `"warning"` or `"citation"`.
  The dashboard's second target metric is `contraband_found` (search hit
  rate) instead of an arrest indicator, matching the README's own stated
  primary metrics.
- No `subject_age` — Texas State Patrol doesn't report it. The
  "demographics" control layer is driver sex only.
- 27.4M raw rows is too large to fit live in an interactive session;
  `02_clean_stops.py` filters to 2015-2017 (~5.6M rows). Even at that size,
  `make results` fits and caches every model once (~2min, mostly Veil of
  Darkness's sunset/dusk pass) rather than the dashboard refitting per
  session — see `duboisR/inst/scripts/precompute_audit.R`.

You can still run the **Shiny dashboard against synthetic data** for pure
plumbing checks, without any of the above:

```bash
Rscript r_dashboard/dev/generate_synthetic_data.R      # writes data/processed/audit_ready_stops.csv
Rscript duboisR/inst/scripts/precompute_audit.R         # -> results/*.rds, same as `make results`
cd r_dashboard && Rscript -e 'shiny::runApp(".")'
```

**Both of these write to the same paths the real pipeline uses** (there's no
`--output` flag) — if you already have a real dataset built, back up
`data/processed/audit_ready_stops.csv` and `results/` first, or you'll
overwrite them with synthetic numbers. To get back to the real data
afterward: if `data/raw/` and `data/processed/stops_clean.csv` are still
around, `make data && make results` only needs to redo the fast merge step,
not the full pipeline (Make's staleness check is timestamp-based, so `touch`
the still-real upstream files first if their mtimes ended up older than the
synthetic run).

**macOS gotchas** if package installs fail to compile:
- If `xcode-select -p` points at a broken/corrupted Xcode.app (symptom:
  `xcrun` errors about `xcodebuild` even for unrelated tools like `clang`),
  point it at the Command Line Tools instead:
  `sudo xcode-select -s /Library/Developer/CommandLineTools`
- If compilation fails with `invalid value 'gnu23'`, your CLT's clang is too
  old for R's default C standard. Force an older one via `~/.R/Makevars`:
  ```
  CC = clang -std=gnu17
  CFLAGS = -Wall -g -O2
  ```
- `tidyverse` (via `ragg`/`textshaping`) needs a few system libs:
  `brew install harfbuzz fribidi libtiff`

Synthetic data is for plumbing checks only — treat any numbers it produces
as meaningless.

**Datasheet workflow.** The dashboard's "Data Transparency & Provenance" tab
looks for a `datasheet.json` next to `audit_ready_stops.csv`. Generate one
interactively with:

```r
devtools::load_all("duboisR")
build_datasheet_wizard(output = "data/processed/datasheet.json")
```

or scaffold the plain-Markdown version (no automation of the reflection
itself, by design — see the package's Datasheets-for-Datasets docs) with
`use_datasheet()`.
