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
- **`duboisR` Core Engine (R):** An internal R package/module that executes the _Wells-Du Bois Protocol_ for algorithmic auditing, including multivariable logistic regressions ($glm$), interaction effects, and quasi-experimental _Veil of Darkness_ tests.
- **Audit Dashboard (R Shiny):** An interactive UI allowing policy researchers to layer demographic, socioeconomic, and environmental controls in real time to observe how disparity estimates shift.

---

## Product Scope & Methodological Framing

- **Primary Metrics:** Traffic stop rate, search rate, search "hit rate" (contraband yield).
- **Geographic Scope:** Tiered sampling strategy focusing on 3–5 high-coverage states from the Stanford Open Policing Project (e.g., NC, CT, RI, TX) with standardized County FIPS and timestamp records.
- **Toggleable Control Layers:**
  1. _Unadjusted / Raw Disparity_
  2. _+ Individual Demographics_ (Driver Sex — Texas State Patrol doesn't report driver age)
  3. _+ Socioeconomic Context_ (County Median Household Income, Poverty Rate)
  4. _+ Environmental Discretion_ (Time of Day / Sunset Daylight Status via Veil of Darkness)
- **Target Audience:** Computational social scientists, policy researchers, and data engineers. UI is designed for legible exploration of regression outputs.
- **Deliverables:**
  - Interactive R Shiny Web Platform
  - Reproducible Quarto (`.qmd`) White Paper compiling to PDF/HTML
  - `duboisR` R-package module for diagnostic fairness testing

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
├── data/
│   ├── raw/                 # Stanford Open Policing CSVs, Census API pulls (gitignored)
│   └── processed/           # Merged, analysis-ready datasets (gitignored)
├── python/                  # Data acquisition, cleaning, spatial join
├── r_dashboard/             # Shiny app: reactive modeling + visualization
│   ├── R/                   # Shiny modules (regression, veil of darkness)
│   └── www/                 # CSS/static assets
├── notebooks/                # Scratch EDA, not pipeline code
└── paper/                   # Quarto white paper (added once findings exist)
```

## Setup

The pipeline currently targets **Texas** — the Stanford Open Policing
"State Patrol" file (statewide, county-level, 2006-2017). Other states
(NC, CT, RI) can be wired the same way later.

```bash
# 1. Install R (the CLI, not the R.app cask — the cask installer needs sudo)
brew install r
Rscript -e 'install.packages(c("shiny","bslib","tidyverse","broom"), repos="https://cloud.r-project.org")'

# 2. Python env
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# 3. Get a free Census API key (https://api.census.gov/data/key_signup.html)
#    and put it in a repo-root .env file: CENSUS_API_KEY=your_key_here

# 4. Download the raw Texas State Patrol CSV (~1GB zipped, ~7.2GB unzipped —
#    01/02 below read directly from the .zip, no need to unzip by hand)
curl -L -o data/raw/tx_statewide_2020_04_01.csv.zip \
  "https://stacks.stanford.edu/file/druid:yg821jf8611/yg821jf8611_tx_statewide_2020_04_01.csv.zip"

# 5. Run the pipeline
cd python
../.venv/bin/python 01_fetch_census.py   # -> data/raw/census_stratifiers.csv (254 TX counties)
../.venv/bin/python 02_clean_stops.py    # -> data/processed/stops_clean.csv (filters to 2015-2017)
../.venv/bin/python 03_merge_features.py # -> data/processed/audit_ready_stops.csv (~5.6M rows)

# 6. Run the app
cd ../r_dashboard && Rscript -e 'shiny::runApp(".")'
```

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
- 27.4M raw rows is too large for an interactive `glm()`; `02_clean_stops.py`
  filters to 2015-2017 (~5.6M rows), which fits in ~9s per model refit.

You can still run the **Shiny dashboard against synthetic data** for pure
plumbing checks, without any of the above:

```bash
Rscript r_dashboard/dev/generate_synthetic_data.R
cd r_dashboard && Rscript -e 'shiny::runApp(".")'
```

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
