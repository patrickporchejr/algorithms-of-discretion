# Contributing

PRs are welcome, especially ones that extend this beyond its current scope.
Concretely, some directions worth pursuing:

- **More states.** The pipeline, dashboard, and Veil of Darkness
  county-centroid table are all Texas-only today. README's
  ["Pointing the pipeline at a different state"](README.md#pointing-the-pipeline-at-a-different-state)
  walks through exactly what's hardcoded and what to change — start there.
- **Handling more data.** `02_clean_stops.py` reads the raw file in chunks,
  but everything downstream (the merged CSV, the dashboard's `read_csv()`,
  `glm()`) loads the full dataset into memory at once. That's a deliberate
  ceiling for the current ~5.6M-row scope (see README's "Schema realities"
  section), not a load-bearing design decision — a state with a much larger
  raw file, or supporting multiple states at once, will need something
  more than "read it all into a data.frame." Out-of-core processing,
  a real database backing the dashboard, incremental/streaming ingestion —
  open to any of these; raise an issue first if you want to talk through
  the approach before building it.
- **Additional covariates.** The current socioeconomic layer is
  county-level (median income, poverty rate, pulled from ACS and joined on
  `county_fips`/`county_join_key`), and Veil of Darkness needs a lat/lon
  centroid per join unit to compute sunset/dusk. Something like ZIP-level
  covariates would need both a different ACS geography (ZCTA, not county)
  *and* a finer-grained centroid table for Veil of Darkness — it's a real
  change to two places, not just a new column.
- **More data in general.** Additional Stanford Open Policing fields
  (`violation`, `search_basis` are already carried through but unused —
  see README's Repo Layout), other administrative datasets entirely,
  additional demographic/environmental controls for the dashboard's
  toggle layers.

If you're planning something bigger than a small fix, opening an issue
first is a good way to avoid building something that doesn't fit the
project's scope — see `DESIGN.md` for the reasoning behind the current
architecture and its explicit methodological caveats (README's "Unmeasured
Factors" section).

## Getting set up

README's [Setup](README.md#setup) section covers the full local
environment: R + `duboisR`, the Python pipeline, and the dashboard.

## Tests

Both the R package and the Python pipeline have real test suites, and CI
runs both on every PR (see below). The bar is: **all tests pass.** There's
no enforced coverage percentage, but if you add new functionality, add
tests for it; if you change existing behavior, update the tests that
covered it rather than leaving them checking the old behavior.

**R (`duboisR/`)** uses `testthat`. Run the suite with:

```bash
Rscript -e 'devtools::test("duboisR")'
```

**Python (`python/`)** uses `pytest`. Its numbered scripts
(`01_fetch_census.py`, ...) aren't importable by their literal names, so
tests load them via `python/tests/_helpers.py`'s `import_script()` — follow
that pattern for new test files rather than trying to `import` a script
directly. Run the suite with:

```bash
pip install -r requirements-dev.txt
pytest python/tests
```

## CI

`.github/workflows/ci.yml` runs both suites — `r-tests` (a full
`R CMD check` on `duboisR`, which includes `testthat`) and `python-tests`
(`pytest`) — on every push and PR against `main`. Both are required status
checks: a PR with a failing test won't merge until it's fixed. The R check
only fails the build on genuine errors (build/test failures), not
CRAN-style documentation nitpicks, since `duboisR` isn't headed for CRAN.

## License

Contributions are accepted under this repo's [MIT license](LICENSE).
