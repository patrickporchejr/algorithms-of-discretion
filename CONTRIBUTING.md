# Contributing

PRs are welcome, especially ones that extend this beyond its current scope.
Concretely, some directions worth pursuing:

- **More states.** The pipeline is Texas-only today. README's
  ["Pointing the pipeline at a different state"](README.md#pointing-the-pipeline-at-a-different-state)
  walks through exactly what's hardcoded and what to change -- start there.
  A different state's `grounding_questions.QUESTIONS` battery would also
  need its own facts, since the current one cites Texas-specific numbers.
- **Handling more data.** `02_clean_stops.py` reads the raw file in
  chunks, but everything downstream (the merged CSV, `pandas.read_csv()`
  in `build_data_context()`) loads the full dataset into memory at once.
  That's a deliberate ceiling for the current ~5.6M-row scope, not a
  load-bearing design decision -- a state with a much larger raw file, or
  supporting multiple states at once, will need something more than "read
  it all into a DataFrame." Raise an issue first if you want to talk
  through the approach before building it.
- **Additional covariates.** The current socioeconomic layer is
  county-level (median income, poverty rate, pulled from ACS and joined on
  `county_fips`/`county_join_key`). Something like ZIP-level covariates
  would need a different ACS geography (ZCTA, not county).
- **More data in general.** Additional Stanford Open Policing fields
  (`violation`, `search_basis` are already carried through but unused),
  other administrative datasets entirely, additional demographic/
  environmental controls.

If you're planning something bigger than a small fix, opening an issue
first is a good way to avoid building something that doesn't fit the
project's scope -- see `DESIGN.md` for the reasoning behind the current
architecture and its explicit methodological caveats (README's "Unmeasured
Factors" section).

## Getting set up

README's [Setup](README.md#setup) section covers the full local
environment.

## Tests

`python/` has a real test suite, and CI runs it on every PR (see below).
The bar is: **all tests pass.** There's no enforced coverage percentage,
but if you add new functionality, add tests for it; if you change existing
behavior, update the tests that covered it rather than leaving them
checking the old behavior.

Uses `pytest`. Its numbered pipeline scripts (`01_fetch_census.py`, ...)
aren't importable by their literal names, so tests load them via
`python/tests/_helpers.py`'s `import_script()` -- follow that pattern for
new test files that need to load a numbered script (modules without a
leading digit, like `datasheet.py` or `llm_clients.py`, can be `import`ed
directly instead, since `_helpers.py` puts `python/` on `sys.path`). Run
the suite with:

```bash
pip install -r requirements-dev.txt
pytest python/tests -v
```

## CI

`.github/workflows/ci.yml` runs the test suite (`pytest`) on every push and
PR against `main`. It's a required status check: a PR with a failing test
won't merge until it's fixed.

## License

Contributions are accepted under this repo's [MIT license](LICENSE).
