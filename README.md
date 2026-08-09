# Algorithms of Discretion

An interactive data audit platform and diagnostic suite examining how socioeconomic and spatial/environmental covariates modify (or fail to modify) apparent racial disparities in U.S. traffic stop outcomes.

This repository serves as the applied computational data engine for the white paper:

> **The Algorithmic Color Line: Auditing "Algorithms of Discretion" via QuantCrit and Du Boisian Sociology**  
> _By: Patrick Eugene Porché Jr._

Placing empirical data science in conversation with W.E.B. Du Bois's _double consciousness_ and Ruha Benjamin's _Race After Technology_, this project demonstrates how administrative police data (and the machine learning models trained on it) encode historical enforcement discretion rather than underlying driver behavior.

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
  2. _+ Individual Demographics_ (Driver Age, Driver Sex)
  3. _+ Socioeconomic Context_ (County Median Household Income, Poverty Rate)
  4. _+ Environmental Discretion_ (Time of Day / Sunset Daylight Status via Veil of Darkness)
- **Target Audience:** Computational social scientists, policy researchers, and data engineers. Heavy on statistical rigor and econometric validity; UI is designed for legible exploration of regression outputs.
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

Not yet runnable end to end — see Open Questions. Python deps in
`requirements.txt`; R deps to be pinned via `renv` once the Shiny app
has real package usage.
