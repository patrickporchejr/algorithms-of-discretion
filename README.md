# Algorithms of Discretion

This repository is the applied computational engine for the white paper:

> **The Algorithmic Color Line: Auditing "Algorithms of Discretion" via QuantCrit and Du Boisian Sociology**  
> _By: Patrick Eugene Porché Jr._  
> [SocArXiv preprint](https://osf.io/preprints/socarxiv) (placeholder link until this paper's own preprint is posted)

---

## What this is

Two pieces, one file-based pipeline, all Python:

- **Data pipeline (`python/01_fetch_census.py`, `02_clean_stops.py`, `03_merge_features.py`):** ingests Texas traffic-stop records from the Stanford Open Policing Project, pulls county-level ACS covariates from the Census API, and joins them into one analysis-ready CSV.
- **LLM datasheet-grounding experiment (`python/run_grounding.py` + `python/grounding_experiment.py`, `llm_clients.py`, `grounding_questions.py`, `datasheet.py`):** asks a flagship LLM the same fixed battery of questions about the dataset twice -- once with only a compact description of the data ("naive"), once with the same description plus this project's hand-authored `datasheet.json` ("grounded") -- and scores both against hand-authored expected answers. Measures, rather than asserts, whether a [Datasheets for Datasets](https://arxiv.org/abs/1803.09010) provenance document actually changes a concrete downstream consumer's answers.

There is no dashboard and no R code in this repository -- both are print-to-console tools you run locally.

---

## Data Sources

1. **[Stanford Open Policing Project](https://openpolicing.stanford.edu/):** standardized traffic stop records, including timestamps, race/sex demographics, search outcomes, and county identifiers.
2. **U.S. Census Bureau ACS 5-Year API:** county-level median household income and poverty rate, joined on normalized county name.

**Geographic/temporal scope:** Texas only, 2015-2017 (~5.6M stops). See [Pointing the pipeline at a different state](#pointing-the-pipeline-at-a-different-state) to adapt it.

---

## Unmeasured Factors (Explicit Methodological Caveats)

Administrative datasets reflect institutional policing practices rather than raw public behavior:

- **Missing Denominator:** administrative records capture who was stopped, not who drove by without being stopped.
- **Enforcement Discretion:** stop volume reflects departmental priorities and pretextual enforcement.
- **Hour-only time resolution:** the pipeline carries an integer stop hour, no minutes -- any time-of-day analysis built on top of this data inherits that resolution ceiling.

See `data/processed/datasheet.json` for the full, hand-authored account of this dataset's provenance, composition, and appropriate/inappropriate uses.

---

## Repo Layout

```
├── Makefile                 # `make all`/`make data` (pipeline), `make grounding` (opt-in, billed)
├── data/
│   ├── raw/                 # Stanford Open Policing CSVs + Census pull (gitignored)
│   └── processed/           # Merged, analysis-ready dataset (gitignored) + datasheet.json (hand-authored, tracked)
├── results/                 # `make grounding` output (gitignored)
├── python/
│   ├── 01_fetch_census.py   # Census ACS pull
│   ├── 02_clean_stops.py    # Stanford CSV cleaning/filtering
│   ├── 03_merge_features.py # joins the two into audit_ready_stops.csv
│   ├── datasheet.py         # read_datasheet() + DATASHEET_SCHEMA (no generation step -- see below)
│   ├── llm_clients.py        # Anthropic/OpenAI/Gemini/Grok clients, forced structured output
│   ├── grounding_questions.py # the fixed naive-vs-grounded question battery
│   ├── grounding_experiment.py # prompt building, scoring, summarizing, console report
│   ├── run_grounding.py      # CLI entry point for the experiment
│   └── tests/                # pytest suite for all of the above
└── notebooks/                 # scratch EDA, not pipeline code
```

## Setup

```bash
# 1. Python env
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# 2. cp .env.example .env, then get a free Census API key
#    (https://api.census.gov/data/key_signup.html) and set CENSUS_API_KEY

# 3. Download the raw Texas State Patrol CSV (~1GB zipped, ~7.2GB unzipped --
#    the pipeline reads directly from the .zip, no need to unzip by hand)
curl -L -o data/raw/tx_statewide_2020_04_01.csv.zip \
  "https://stacks.stanford.edu/file/druid:yg821jf8611/yg821jf8611_tx_statewide_2020_04_01.csv.zip"

# 4. Build the dataset. `make` only reruns steps whose inputs actually
#    changed -- see `make -n all` to preview what would run.
make all       # -> data/processed/audit_ready_stops.csv (~5.6M rows)
```

---

## The datasheet

`data/processed/datasheet.json` is a [Datasheets for Datasets](https://arxiv.org/abs/1803.09010)-style provenance document (extended with a Positionality & Counter-Narrative section and an Audit Results Appendix, per Monroe-White & Lecy 2023) for `audit_ready_stops.csv`. **There is no generation step.** Per the source paper, the qualitative reflection a datasheet captures is the point -- automating it away defeats the purpose. You write and edit it by hand.

- `python/datasheet.py`'s `DATASHEET_SCHEMA` lists every section and question key this project recognizes (`motivation.purpose`, `composition.sensitive_data`, ...) -- use it as a reference for what to fill in, or look at the existing `data/processed/datasheet.json` for a fully worked example.
- `read_datasheet(path)` raises (doesn't silently degrade) if `path` doesn't exist or parses to an empty document -- a missing/blank datasheet is a data-entry gap the grounding experiment needs to know about immediately, not something to paper over.

```bash
python3 -c "
import sys; sys.path.insert(0, 'python')
import json, datasheet
print(json.dumps(datasheet.DATASHEET_SCHEMA, indent=2))
"
```

---

## LLM Grounding Test

`python/run_grounding.py` asks a flagship LLM the same fixed battery of boolean/multiple-choice/numeric questions about the dataset (`grounding_questions.QUESTIONS`) twice -- once given only a compact, pseudonymized description of the schema plus a small random sample ("naive"), once given the same description plus `datasheet.json`'s full content and an instruction to consult it first ("grounded") -- and scores both against each question's hand-authored expected answer.

**Runs with or without a datasheet.** If `data/processed/datasheet.json` exists, both conditions run and get compared; if it doesn't (or `--no-datasheet` is passed), only the naive condition runs. This is the one thing the CLI branches on -- there's no separate "mode" flag beyond that.

```bash
# Set at least one of these in your .env (see .env.example):
#   ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY / XAI_API_KEY
cd python && python run_grounding.py                    # naive+grounded if datasheet.json exists, else naive-only
python run_grounding.py --no-datasheet                   # force naive-only even if a datasheet exists
python run_grounding.py --repeats=1                       # halve the billed calls while iterating (default 2 trials/condition)
python run_grounding.py --restart                         # ignore an existing checkpoint, start over
python run_grounding.py --datasheet=/path/to/datasheet.json  # point at a different datasheet

# Makefile shortcut (passes ARGS through, e.g. `make grounding ARGS="--repeats=1"`):
make grounding
```

Real, billed API calls -- not part of `make all`. Every completed (provider, condition, trial) call is checkpointed to `results/grounding_experiment_checkpoint.json` as the run goes, so a crash/rate-limit/Ctrl-C partway through resumes instead of re-billing; the checkpoint is cleared on a clean finish. The full result is saved to `results/grounding_experiment.json` and a summary report is printed straight to the console (accuracy by provider/condition, mean answer stability across trials, how many question/provider pairs flipped their majority-vote answer once grounded).

`n_repeats > 1` runs independent trials per (provider, condition) -- providers aren't called at temperature 0, so a single trial's "changed answer" could be sampling noise; repeats let the summary report a majority-vote answer and a per-question stability rate instead of trusting one draw.

Every provider call is forced through a JSON-Schema-constrained tool call rather than parsed free text (`grounding_experiment.response_schema()`), with confidence nested per-answer so the report can tell "grounding changed the answer" apart from "grounding changed how sure the model was."

---

## Pointing the pipeline at a different state

The Stanford Open Policing Project publishes one "State Patrol" file per state, each at its own URL (Stanford's `stacks.stanford.edu` assigns a unique "druid" ID per file -- there's no predictable pattern to construct it from a state abbreviation).

1. Go to the [data page](https://openpolicing.stanford.edu/data/), find your target state's State Patrol download link.
2. Update what's currently Texas-hardcoded:
   - **`python/01_fetch_census.py`**: `TARGET_STATE_FIPS` (Texas is `"48"`).
   - **`python/02_clean_stops.py`**: the raw file path and `RAW_COLUMNS_NEEDED` -- Stanford's schema isn't fully uniform across states; check the new file's header first.
   - **`Makefile`**: the `RAW_STOPS` variable, to match the new raw filename.
3. Re-run `make all` (`make clean` first for a fully fresh run).

**Schema realities discovered wiring this up:**
- No FIPS code at the stop level in the raw file -- only `county_name` text; the pipeline joins to Census county data on a normalized name, and FIPS is carried through from the Census side afterward.
- No `subject_age` -- Texas State Patrol doesn't report it.
- 27.4M raw rows is too large to fit live in an interactive session; `02_clean_stops.py` filters to 2015-2017 (~5.6M rows).

---

## Testing

```bash
pip install -r requirements-dev.txt
pytest python/tests -v
```

`python/tests/_helpers.py`'s `import_script()` loads the numbered pipeline scripts (`01_fetch_census.py`, ...) by file path, since their filenames start with a digit and can't be `import`ed normally; it also puts `python/` on `sys.path` so the grounding modules (which don't have that naming constraint) import each other normally. `.github/workflows/ci.yml` runs the suite on every push/PR against `main`.
