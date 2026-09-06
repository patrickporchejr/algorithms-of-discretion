# Design Doc: Algorithms of Discretion

This repository has two pieces, both plain Python, no dashboard, no server:
a three-step data pipeline (`python/01-03`) and an LLM datasheet-grounding
experiment (`python/run_grounding.py` and its supporting modules). Every
prior R/`duboisR`/Shiny-dashboard version of this project (Veil of
Darkness, the Threshold Test, identity-proxy and tendentious-outcome
checks, subpopulation disparity disaggregation) has been removed --
this doc covers only what's actually in the repository today.

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
                                                              (hand-authored) data/processed/datasheet.json
                                                                                    │
                                                                                    ▼
                                                                       python/run_grounding.py
                                                                       (naive vs. grounded LLM eval)
                                                                                    │
                                                                                    ▼
                                                              results/grounding_experiment.json + console report
```

One file-based contract at each stage: a CSV between the three pipeline
steps, and a CSV + a hand-authored JSON document feeding the grounding
experiment. No API, no message queue, no shared process, no persistent
service.

---

## 2. Data pipeline (`python/01-03`)

Three plain scripts, run in order by `make all` -- not a DAG framework.
Appropriate at this scale: three steps, no branching, no scheduling need.

**`01_fetch_census.py`** pulls ACS 5-Year variables for Texas counties and
derives a `county_join_key` by normalizing the Census `NAME` field
(`"Harris County, Texas"` -> `"HARRIS"`).

**`02_clean_stops.py`** is the heaviest-lifting script. The raw Stanford
TX file is ~27.4M rows across 44 columns; `pandas.read_csv` reads it with
`chunksize=500_000` directly against the `.zip` and `usecols=RAW_COLUMNS_NEEDED`
to skip parsing columns nothing downstream touches. Filtering to
`subject_race in {white,black,hispanic}` and to 2015-2017 (out of the full
2006-2017 range) gets the working set down to ~5.6M rows. `county_join_key`
is derived here independently of `01_fetch_census.py` using identical
normalization logic -- a duplication, not a shared helper (see §5's rough
edges).

Two schema facts, discovered against the actual file rather than assumed
up front: **no FIPS at the stop level** (only free-text `county_name`,
hence the name-based join), and **no `subject_age`** (Texas State Patrol
doesn't report it).

**`03_merge_features.py`** inner-joins `stops_clean.csv` to
`census_stratifiers.csv` on `county_join_key`, warning (with the distinct
unmatched names, capped at 10) when a stop's normalized county name
doesn't match a Texas county from the Census pull.

The resulting `audit_ready_stops.csv` carries `subject_race`,
`subject_sex`, `search_conducted`, `contraband_found`, `hour`, `date`,
`violation`, `search_basis`, `poverty_rate`, `median_income`,
`county_fips` -- the one data contract everything downstream (currently
just the grounding experiment's `build_data_context()`) reads against.

---

## 3. The datasheet (`python/datasheet.py`)

Implements Gebru et al. 2021's "Datasheets for Datasets" -- a standardized
questionnaire documenting a dataset's provenance and limitations, extended
here with a Positionality & Counter-Narrative section and an Audit Results
Appendix (Monroe-White & Lecy 2023's Du Boisian critique of the original
seven sections).

**There is deliberately no generation step.** The source paper is explicit
that automating the qualitative reflection defeats its purpose, so this
project has no wizard, no scaffolder, no autofill -- `data/processed/datasheet.json`
is written and edited by hand. `DATASHEET_SCHEMA` exists only as a
reference for valid section/question keys; `read_datasheet(path)` raises
(rather than returning `None`) when `path` doesn't exist or parses to an
empty document, since a missing/blank datasheet is something a caller
needs to know about immediately, not silently degrade around.

---

## 4. LLM datasheet-grounding experiment

Rather than *asserting* that a datasheet makes a dataset's provenance
legible, this measures it -- against an LLM as a concrete downstream
consumer. `run_grounding_experiment()` (`grounding_experiment.py`) asks the
same flagship model the same fixed battery of boolean/enum/numeric
questions about the dataset (`grounding_questions.QUESTIONS`): once
**naive** (a compact, pseudonymized description of the schema plus a small
random sample -- `build_data_context()`), and, when a datasheet is
supplied, once more **grounded** (the identical description plus the full
`datasheet.json` content and an instruction to consult it first). Each
answer is scored against a hand-authored `expected_answer`.

**Whether a datasheet is supplied decides which conditions run** -- this
is the one branch point in the whole tool. `run_grounding.py` (the CLI)
resolves that automatically: it runs both conditions if
`data/processed/datasheet.json` exists, naive-only otherwise (or if
`--no-datasheet` is passed). There's no separate flag for "run without my
datasheet" beyond that -- it falls out of whether the path exists.

**Pseudonymization (`build_data_context()`).** The raw sample handed to
both conditions has `id_cols` (real-world identifiers like `county_fips`)
and any date-typed columns pseudonymized/relativized before either
condition ever sees it, so the *naive* condition can't take a shortcut that
has nothing to do with grounding (e.g. recognizing a real Texas FIPS prefix
on sight, or inferring the project's year restriction from a real calendar
date range). Column *types* are still reported honestly -- only the values
are obscured.

**Forced structured output (`response_schema()`, `llm_clients.py`).** Every
provider call is forced through a JSON-Schema-constrained tool call rather
than parsed free text, with confidence nested per-answer
(`{answer, confidence}`) so the report can tell "grounding changed the
answer" apart from "grounding changed how sure the model was" -- these can
differ even when the raw answer doesn't. Boolean questions get a
`"TRUE"`/`"FALSE"` string enum (not JSON Schema's native boolean) and enum
questions get a string enum of choice keys, so scoring can treat every
non-numeric question as "does this string equal `expected_answer`" with no
type-specific branching; numeric questions get a bare number, scored
within a per-question `tolerance` band.

`llm_clients.py` implements each provider as a plain `requests` call
against its REST API directly (no provider SDKs, to keep the dependency
footprint identical to the rest of the Python side): `call_anthropic()`
forces a tool call via Anthropic's Messages API; `call_openai()` and
`call_grok()` share one implementation (`_call_openai_compatible()`) since
xAI's Grok API is explicitly OpenAI-compatible; `call_gemini()` uses
Gemini's native JSON response mode (`responseSchema` in its own
OpenAPI-subset dialect -- `gemini_response_schema()` translates the shared
schema into it) since Gemini returns schema-conformant JSON directly as
response text rather than via a tool call.

**Checkpointing.** `n_repeats > 1` runs independent trials per (provider,
condition) -- providers aren't called at temperature 0, so a single
trial's "changed answer" could be sampling noise;
`summarize_grounding_trials()` collapses repeats into a majority-vote
answer and a per-question agreement rate instead of trusting one draw.
Every completed (provider, condition, trial) row is written to a JSON
checkpoint file after each real API call (not after a cache hit, which
would just rewrite the same bytes), so a crash/rate-limit/Ctrl-C partway
through a run resumes from where it left off on the next invocation
instead of re-billing every already-answered call; `--restart` ignores an
existing checkpoint and starts over. The checkpoint is deleted on a clean
finish.

**Output.** The full result is saved to `results/grounding_experiment.json`
(so a completed run's answers survive independent of any later
`summarize_*()` bug), and `format_report()` prints a plain-text summary
straight to the console: accuracy by provider/condition, mean answer
stability across trials, and how many question/provider pairs flipped
their majority-vote answer once grounded in the datasheet. There's no PDF
or chart export -- the console report is the only output surface,
deliberately, since nothing downstream (no dashboard, no paper-figure
pipeline) currently consumes anything richer.

---

## 5. Known rough edges

1. **Join-key normalization is duplicated**, not shared, between
   `01_fetch_census.py` and `02_clean_stops.py`. If the normalization rule
   ever needs to change, it has to change in two places in sync.
2. **The CSV data contract is enforced by nothing except code review** and
   `02_clean_stops.py`'s own header check. No schema-validation step
   catches a column rename or dtype change between pipeline steps.
3. **Single-state scope.** Both the pipeline and the grounding
   experiment's question battery are Texas-specific; adapting to another
   state means updating the hardcoded values in `01`/`02`/`Makefile` (see
   README's "Pointing the pipeline at a different state") and rewriting
   `grounding_questions.QUESTIONS` to match a different dataset's actual
   facts.
4. **The grounding question battery cites facts (a proxy-accuracy lift, a
   Veil of Darkness ratio, a Threshold Test fit) that were originally
   computed by diagnostic tooling this project no longer ships in code.**
   They're still valid grounding-test questions because that content lives
   on as static, hand-authored prose in `datasheet.json` itself -- the
   question only checks whether a model's answer changes once it can read
   that prose, not whether it can re-derive the number from a live
   computation. If `datasheet.json`'s content is ever substantially
   rewritten, revisit whether each question's `expected_answer` still
   matches what the file actually says.
5. **Python has no schema-validation library** -- correctness rests on
   `02_clean_stops.py`'s own header check and the unmatched-county-name
   warning in `03_merge_features.py`, both runtime and data-dependent
   rather than an independent validation layer.
