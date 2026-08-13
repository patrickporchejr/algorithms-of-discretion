# Algorithms of Discretion

A Veil of Darkness audit of racial disparity in Texas traffic stops (2015–2017): does the racial mix of who gets stopped change once officers can't see a driver's race clearly (i.e., after dusk)?

This repository is the applied computational engine for the white paper:

> **The Algorithmic Color Line: Auditing "Algorithms of Discretion" via QuantCrit and Du Boisian Sociology**  
> _By: Patrick Eugene Porché Jr._  
> [SocArXiv preprint](https://osf.io/preprints/socarxiv) (placeholder link until this paper's own preprint is posted)

By examining data science in tandem with W.E.B. Du Bois's _double consciousness_ and Ruha Benjamin's _Race After Technology_, this project demonstrates how administrative police data (and the machine learning models trained on it) encode historical enforcement discretion rather than underlying driver behavior.

---

## What this is

Three pieces, one file-based pipeline:

- **Data Pipeline (Python, `python/`):** ingests Texas traffic-stop records from the Stanford Open Policing Project and performs spatial joins on County FIPS.
- **`duboisR` (R package, `duboisR/`):** the Veil of Darkness natural-experiment test (Grogger & Ridgeway 2006) — sunset/dusk classification via `suncalc`, the intertwilight-hour design that makes the comparison valid, and the descriptive charts built on top of it. Also implements the Datasheets-for-Datasets provenance scaffolding and the LLM datasheet-grounding experiment that two of the CLI's three programs (below) drive.
- **Shiny Dashboard (`r_dashboard/`):** a browser front end onto the precomputed Veil of Darkness charts (see [The Veil of Darkness dashboard](#the-veil-of-darkness-dashboard)).
- **CLI (`duboisR/inst/scripts/`):** three Rscript entry points — Veil of Darkness charts, the datasheet generator, and the LLM grounding test (see [Command-line interface](#command-line-interface)).

`duboisR` also implements several other diagnostics from its broader Wells-Du Bois Protocol design (a Threshold Test approximation, identity-proxy/tendentious-outcome checks, subpopulation disparity disaggregation) — exported and tested, but not part of the currently shipped dashboard/CLI surface this README documents. `?function_name` after `devtools::load_all("duboisR")` covers all of it if you go looking.

---

## Data Sources

1. **[Stanford Open Policing Project](https://openpolicing.stanford.edu/):** standardized traffic stop records, including timestamps, race/sex demographics, search outcomes, and county identifiers.
2. **U.S. Census Bureau Gazetteer Files:** county centroid lat/lon (bundled in `duboisR`, TX-only), used to compute each stop's sunset/dusk time.
3. **Astronomical solar position data:** sunset/civil-dusk calculations via `suncalc`, keyed on stop date + county centroid.

**Geographic/temporal scope:** Texas only, 2015–2017 (~5.6M stops). See [Pointing the pipeline at a different state](#pointing-the-pipeline-at-a-different-state) to adapt it.

---

## Unmeasured Factors (Explicit Methodological Caveats)

Administrative datasets reflect institutional policing practices rather than raw public behavior:

- **Missing Denominator:** administrative records capture who was stopped, not who drove by without being stopped.
- **Enforcement Discretion:** stop volume reflects departmental priorities and pretextual enforcement.
- **Reporting-rate assumption:** the Veil of Darkness design assumes race-specific *reporting* rates don't vary systematically between day and night, conditional on clock time — a weaker assumption than requiring equal absolute reporting rates, but still an assumption, not a guarantee.
- **Hour-only time resolution:** the pipeline carries an integer stop hour, no minutes, so daylight/dark classification near sunset/dusk is coarser than the underlying astronomical calculation supports.

---

## Repo Layout

```
├── Makefile                 # DAG over the pipeline: `make all` (data), `make results` (+ precompute)
├── data/
│   ├── raw/                 # Stanford Open Policing CSVs (gitignored)
│   └── processed/           # Merged, analysis-ready dataset (gitignored)
├── results/                 # Precomputed vod_charts.rds the dashboard/CLI read (gitignored)
├── python/                  # Data acquisition, cleaning, spatial join
├── duboisR/                 # R package: the Wells-Du Bois Protocol diagnostic engine
│   ├── R/                   # veil_of_darkness.R (+ _charts.R / _module.R), glm_utils.R, datasheet*.R, grounding_experiment.R, ...
│   ├── inst/extdata/        # bundled TX county centroids (Veil of Darkness geodata)
│   ├── inst/scripts/        # cli.R (single entry point), precompute_audit.R, + the 3 scripts cli.R dispatches to
│   ├── tests/testthat/      # unit + parameter-recovery tests
│   └── vignettes/           # theoretical grounding (QuantCrit, Du Bois, Wells)
├── r_dashboard/             # Shiny app: the Veil of Darkness dashboard (consumes duboisR)
└── notebooks/                # Scratch EDA, not pipeline code
```

## Setup

```bash
# 1. Install R (the CLI, not the R.app cask — the cask installer needs sudo)
brew install r
Rscript -e 'install.packages(c("shiny","bslib","tidyverse","devtools"), repos="https://cloud.r-project.org")'

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

# 5. Build everything: the 3-step Python pipeline, then the Veil of Darkness
#    precompute. `make` only reruns steps whose inputs actually changed --
#    see `make -n all results` to preview what would run.
make all       # -> data/processed/audit_ready_stops.csv (~5.6M rows)
make results   # -> results/vod_charts.rds (~2min, mostly the sunset/dusk pass
               #    over the full dataset -- see duboisR/inst/scripts/precompute_audit.R)

# 6. Run the dashboard -- it renders results/vod_charts.rds, it does not fit anything live
cd r_dashboard && Rscript -e 'shiny::runApp(".")'
```

---

## The Veil of Darkness dashboard

`r_dashboard/app.R` renders four descriptive charts, all built from `results/vod_charts.rds` via `duboisR`'s `summarize_*()`/`plot_*()` functions (`?plot_county_vod_disparity`, `?plot_statewide_vod`, `?plot_county_search_disparity`, `?plot_vod_search_combined`) — the same functions the CLI below calls, so the dashboard and CLI always render identically:

1. **County-level Veil of Darkness ratio** — each county's black share of inter-twilight stops, dark ÷ daylight. Near 1 across most counties is the descriptive signature the Grogger-Ridgeway hypothesis predicts if the *stop* decision isn't strongly race-driven.
2. **Statewide before/after comparison** — each race's share of stops, compared directly across the daylight/dark boundary.
3. **Search-rate disparity by county** — the *search* decision (a separate discretion point, once a stop has already happened), not restricted to the intertwilight window.
4. **Both mechanisms side by side** — charts 1 and 3 combined via `patchwork`, to compare where a racial disparity concentrates: the stop itself, or what happens once a stop has been made.

`duboisR` also ships a regression-based version of this test (`fit_veil_of_darkness()`, `race:is_dark` interaction model with closed-form Wald CIs — see `?fit_veil_of_darkness`) — exported and tested, but not part of the currently rendered dashboard/CLI, which are purely descriptive (no model fitting).

---

## Command-line interface

Every command-line program in this project is called the same way, through one dispatcher:

```bash
Rscript duboisR/inst/scripts/cli.R <command> [options]
```

| Command     | What it does                                                      |
| ----------- | -------------------------------------------------------------------- |
| `veil`      | Print/save the four Veil of Darkness charts (see below)            |
| `datasheet` | Seed a first-pass `datasheet.json` for the processed dataset       |
| `grounding` | Run the naive-vs-grounded LLM datasheet-grounding experiment       |

`Rscript duboisR/inst/scripts/cli.R --help` lists all three; `Rscript duboisR/inst/scripts/cli.R <command> --help` prints that command's own options — every command supports `--help`. Each command is also its own independently runnable script (`Rscript duboisR/inst/scripts/veil_of_darkness_cli.R ...`, etc., named in each subsection below) — `cli.R <command> [options]` is a thin dispatcher onto the exact same script with the exact same options, not a separate implementation, so either form does the same thing.

### Veil of Darkness charts

`veil` (`duboisR/inst/scripts/veil_of_darkness_cli.R`), a thin wrapper around `duboisR::veil_of_darkness_module()` (see `?duboisR::veil_of_darkness_module`), loads the processed data, classifies daylight/dark status, and prints/saves each of the four charts above.

```bash
Rscript duboisR/inst/scripts/cli.R veil [subcommand] [options]
```

**Subcommands** (positional; default `all` if omitted):

| Subcommand  | What it prints                                   | PNG written (`--out`)  |
| ----------- | ------------------------------------------------- | ----------------------- |
| `county`    | Chart 1's table (`total_n >= --min-n` only)       | `vod_county.png`        |
| `statewide` | Chart 2's before/after table, one row per race    | `vod_statewide.png`     |
| `search`    | Chart 3's table (both race counts `>= --min-n`)   | `vod_search_rate.png`   |
| `combined`  | A one-line pointer to `county`/`search` for numbers | `vod_combined.png`    |
| `all`       | Runs all four of the above, in that order          | all four files above  |

Every subcommand also prints a one-line `<duboisR_vod_module>` summary (rows loaded, inter-twilight rows, county count) before its own output — that's `print(vod)` under the hood, same object as the console usage below.

**Options:**

| Flag           | Default                                  | Meaning                                                                                     |
| -------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------- |
| `--data=<path>` | `data/processed/audit_ready_stops.csv`   | Path to the processed CSV, resolved relative to wherever you run the script from.             |
| `--out=<dir>`   | `.` (current directory)                  | Directory PNGs are written into; created if it doesn't exist. Pass `--out=` (empty) to print to the console only and skip `ggsave()` entirely. |
| `--min-n=<int>` | `30`                                     | Minimum county sample size for the two scatter charts (`county`'s `total_n`, `search`'s per-race `n_searches`) — counties below this are dropped from both the printed table and the plot, same threshold `plot_county_vod_disparity()`/`plot_county_search_disparity()` take directly. |

`--help`/`-h` (checked before anything else runs, so it works even without a processed dataset on disk) prints the same subcommand/option reference as a plain usage string and exits.

```bash
# All four charts, defaults everywhere:
Rscript duboisR/inst/scripts/cli.R veil

# Just the county-level scatter, a higher min-county-size cutoff, saved
# to a subdirectory instead of the current one:
Rscript duboisR/inst/scripts/cli.R veil county --min-n=50 --out=charts/

# Console output only, no PNGs:
Rscript duboisR/inst/scripts/cli.R veil statewide --out=

# Point it at a differently-located processed CSV (the synthetic dataset
# from "Pointing the pipeline at a different state" below writes to the
# same default path, so --data is only needed if yours lives elsewhere):
Rscript duboisR/inst/scripts/cli.R veil all --data=/path/to/audit_ready_stops.csv
```

### Using the module directly (console, or your own script)

`veil_of_darkness_module()` is what the CLI above wraps — call it the same
way from an R console or another script, with every intermediate table
left readable off the returned object directly instead of only returned
from the call that built it (see §5.3 of [DESIGN.md](DESIGN.md) for how
it's implemented):

```r
devtools::load_all("duboisR")
vod <- veil_of_darkness_module()
vod$init(data_path = "data/processed/audit_ready_stops.csv")
```

`$init(data_path, date_col = "date", hour_col = "hour", county_fips_col = "county_fips", race_col = "subject_race", race_ref = "white", centroids = NULL, config = list())` loads and prepares everything downstream needs, once. Every argument past `data_path` matches the corresponding `compute_daylight_status()`/`prepare_veil_of_darkness_data()` argument if your data uses different column names; `config` is reserved for future options and currently unused. It sets:

| Field                     | What it is                                                                 |
| -------------------------- | --------------------------------------------------------------------------- |
| `$stops`                  | The loaded, race-releveled data                                            |
| `$county_centroids`       | `dubois_tx_centroids()` (or your own `centroids` argument)                 |
| `$stops_geo`               | Every stop with lat/lon/sunset/dusk/`is_dark` attached                     |
| `$sun_times`               | The distinct date × county sunset/dusk lookup `$stops_geo` was built from  |
| `$vod_data`                | The intertwilight-restricted subset (`prepare_veil_of_darkness_data()$fit_data`) |
| `$county_vod_disparity`    | Chart 1's table                                                             |
| `$statewide_vod`           | Chart 2's table                                                             |
| `$county_search_rates`     | Long-format search rates, one row per (county, race)                       |
| `$county_search_disparity` | Chart 3's table (pivoted, with `disparity_ratio`)                          |

Then, one method per chart — each builds, stores, and returns:

| Method                          | Stores as             | Also stores                |
| --------------------------------- | ---------------------- | ----------------------------- |
| `$plot_county_vod(min_n = 30)`    | `$vod_plot`            | —                              |
| `$plot_statewide()`               | `$statewide_plot`      | `$statewide_table`            |
| `$plot_search_rate(min_n = 30)`   | `$search_rate_plot`    | —                              |
| `$plot_combined()`                | `$combined_plot`       | calls the two `min_n = 30` methods above first if their plots aren't built yet |

```r
print(vod)                    # <duboisR_vod_module> summary + which charts are built
vod$plot_combined()           # chart 4, also stored as vod$combined_plot
vod$county_vod_disparity      # the underlying table is right there too
vod$plot_county_vod(min_n = 50)  # rebuild chart 1 with a different cutoff any time
```

### Datasheet

`datasheet` (`duboisR/inst/scripts/seed_demo_datasheet.R`) seeds a non-interactive first-pass [Datasheets-for-Datasets](https://arxiv.org/abs/1803.09010) provenance document for `audit_ready_stops.csv`:

```bash
Rscript duboisR/inst/scripts/cli.R datasheet                # -> data/processed/datasheet.json
Rscript duboisR/inst/scripts/cli.R datasheet --overwrite     # replace existing answers, not just fill blanks
```

For the interactive, resumable version (or a static template with no automation) — genuinely R-console-only, since it prompts via `readline()` and refuses to run under a non-interactive `Rscript` session, so it can't be a `cli.R` command the way the other two are — call the underlying `duboisR` functions directly instead:

```r
devtools::load_all("duboisR")
build_datasheet_wizard(output = "data/processed/datasheet.json")   # interactive, resumable
# or: use_datasheet("datasheet.md")                                # static template only
```

### LLM Grounding Test

`grounding` (`duboisR/inst/scripts/run_grounding_experiment.R`) asks a flagship LLM the same fixed battery of boolean/multiple-choice/numeric questions about the dataset twice — once given only a compact, pseudonymized description ("naive"), once given the same description plus an explicit instruction to read `datasheet.json` first ("grounded") — and scores both against hand-authored expected answers, so the value of the datasheet is measured rather than asserted (see `duboisR::run_grounding_experiment()`).

```bash
# Set at least one of these in your .env (see .env.example):
#   ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY / XAI_API_KEY
Rscript duboisR/inst/scripts/cli.R grounding                          # -> results/grounding_experiment.rds
Rscript duboisR/inst/scripts/cli.R grounding --repeats=1              # halve the billed calls while iterating
Rscript duboisR/inst/scripts/cli.R grounding --restart                # ignore an existing checkpoint, start over

# Makefile shortcut for the first form above (chains the same script):
make grounding
```

Real, billed API calls — not part of `make all`/`make results`, and needs a datasheet to already exist (run the Datasheet step above first). See a dated cost snapshot in a comment near the top of `duboisR/inst/scripts/run_grounding_experiment.R`.

`make clean` removes every generated file (`data/processed/*.csv`, `results/`) so you can rebuild from scratch; it does *not* touch the raw Stanford download.

---

## Pointing the pipeline at a different state

The Stanford Open Policing Project publishes one "State Patrol" file per state, each at its own URL (Stanford's `stacks.stanford.edu` assigns a unique "druid" ID per file — there's no predictable pattern to construct it from a state abbreviation).

1. Go to the [data page](https://openpolicing.stanford.edu/data/), find your target state's State Patrol download link.
2. Update what's currently Texas-hardcoded:
   - **`python/01_fetch_census.py`**: `TARGET_STATE_FIPS` (Texas is `"48"`).
   - **`python/02_clean_stops.py`**: the raw file path and `RAW_COLUMNS_NEEDED` — Stanford's schema isn't fully uniform across states; check the new file's header first.
   - **`Makefile`**: the `RAW_STOPS` variable, to match the new raw filename.
   - **`duboisR`'s county centroid table**: `dubois_tx_centroids()` / `inst/extdata/tx_county_centroids.csv` is Texas-only today (FIPS prefix `48`). Veil of Darkness needs a lat/lon centroid per county to compute sunset/dusk; without a matching table it warns "no centroid match" and drops every row. Regenerate one by adapting `duboisR/data-raw/build_tx_county_centroids.R` (its source is a *national* Census Gazetteer file) — just change the `substr(.data$GEOID, 1, 2) == "48"` filter to your state's FIPS prefix.
3. Re-run `make all && make results` (`make clean` first for a fully fresh run).

**Schema realities discovered wiring this up:**
- No FIPS code at the stop level in the raw file — only `county_name` text; the pipeline joins to Census county data on a normalized name, and FIPS is carried through from the Census side afterward.
- No `subject_age` — Texas State Patrol doesn't report it.
- 27.4M raw rows is too large to fit live in an interactive session; `02_clean_stops.py` filters to 2015–2017 (~5.6M rows).

You can still run the **dashboard against synthetic data** for pure plumbing checks, without any of the above:

```bash
Rscript r_dashboard/dev/generate_synthetic_data.R      # writes data/processed/audit_ready_stops.csv
Rscript duboisR/inst/scripts/precompute_audit.R         # -> results/vod_charts.rds, same as `make results`
cd r_dashboard && Rscript -e 'shiny::runApp(".")'
```

**Both of these write to the same paths the real pipeline uses** — if you already have a real dataset built, back up `data/processed/audit_ready_stops.csv` and `results/` first. Synthetic data is for plumbing checks only — treat any numbers it produces as meaningless.

**macOS gotchas** if package installs fail to compile:
- If `xcode-select -p` points at a broken/corrupted Xcode.app, point it at the Command Line Tools instead: `sudo xcode-select -s /Library/Developer/CommandLineTools`
- If compilation fails with `invalid value 'gnu23'`, force an older C standard via `~/.R/Makevars`: `CC = clang -std=gnu17`
- `tidyverse` (via `ragg`/`textshaping`) needs a few system libs: `brew install harfbuzz fribidi libtiff`

---

## Deployment (shinyapps.io)

`r_dashboard/` is set up to deploy as a self-contained bundle via [`rsconnect`](https://rstudio.github.io/rsconnect/). Two things make that non-obvious:

- **`app.R`'s paths are dual-mode.** In dev, it reaches out to the sibling `../duboisR` and `../results` directories. shinyapps.io only uploads the directory you deploy, so `app.R` checks for a bundled `results/`/`duboisR/` inside `r_dashboard/` first and only falls back to the sibling paths when those aren't present. `r_dashboard/deploy/prepare.sh` populates that bundled copy.
- **`duboisR` isn't on CRAN, and isn't renv-installed for deploy.** `duboisR` is listed in `renv/settings.json`'s `ignored.packages`, and `deploy/prepare.sh` stages a plain source copy at `r_dashboard/duboisR/` instead; `app.R` loads it with `pkgload::load_all()` at startup. `duboisR`'s own dependencies (`rlang`, `ggplot2`, `suncalc`, etc.) are still ordinary CRAN packages renv resolves normally.

**One-time setup:**

```bash
# 1. Create a free account at https://www.shinyapps.io, then from its
#    dashboard: Account > Tokens > Show, to get a token + secret.

# 2. From inside r_dashboard/ (so .Rprofile activates its renv project and
#    rsconnect/duboisR are both visible to the session):
cd r_dashboard
Rscript -e 'renv::install("rsconnect")'   # dev tooling only, not an app dependency -- deliberately not in renv.lock
Rscript -e 'rsconnect::setAccountInfo(name="<account>", token="<token>", secret="<secret>")'
```

`setAccountInfo()` writes straight to `rsconnect`'s local config — never commit a token/secret to the repo or paste them anywhere shared.

**Every deploy:**

```bash
make deploy   # results (if stale) -> stage results -> rsconnect::deployApp(".")
```

`make deploy` chains `results`, runs `r_dashboard/deploy/prepare.sh` to stage `results/vod_charts.rds` and a plain source copy of `duboisR/` into `r_dashboard/`, then calls `rsconnect::deployApp(".")`. The `APP_NAME` variable at the top of the `Makefile` controls the app name it deploys under.

**Fresh clone / new machine.** `r_dashboard/renv/library` is gitignored, so after cloning, run `renv::restore()` from inside `r_dashboard/` to rebuild it — this covers every CRAN dependency, but not `duboisR` itself, which renv is told to ignore (see above). For local dev, `app.R` finds it via the sibling `../duboisR` checkout that comes with the clone.
